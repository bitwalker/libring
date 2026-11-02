defmodule HashRing.ManagedTest do
  use ExUnit.Case, async: true
  doctest HashRing.Managed
  import HashRing.TestSupport

  describe "input validation" do
    test "accepts empty nodes and weighted atom nodes through either startup route" do
      {:ok, empty} = HashRing.Managed.new(:empty_config, nodes: [])
      on_exit(fn -> DynamicSupervisor.terminate_child(HashRing.Supervisor, empty) end)
      assert HashRing.Managed.nodes(empty) == []

      weighted =
        start_supervised!({HashRing.Managed, name: :weighted_config, nodes: [a: 64, b: 32]})

      assert Enum.sort(HashRing.Managed.nodes(weighted)) == [:a, :b]
      ring = :ets.lookup_element(:libring_weighted_config, :ring, 2)
      assert Enum.frequencies(:gb_trees.values(ring.ring)) == %{a: 64, b: 32}
    end

    test "rejects unknown, malformed, and semantically invalid startup options intentionally" do
      for opts <- [
            [unknown: true],
            [:malformed],
            [nodes: [a: 0]],
            [node_blacklist: [123]],
            [nodes: [:valid | :bad]],
            [node_blacklist: ["valid" | :bad]],
            [node_whitelist: [~r/valid/ | :bad]]
          ] do
        assert_raise ArgumentError, fn -> HashRing.Managed.new(:invalid_config, opts) end

        assert_raise ArgumentError, fn ->
          HashRing.Managed.start_link([{:name, :invalid_config} | opts])
        end

        assert Process.whereis(:libring_invalid_config) == nil
        assert :ets.info(:libring_invalid_config) == :undefined
      end

      assert_raise ArgumentError, fn ->
        HashRing.Managed.child_spec(name: :invalid_config, unknown: true)
      end
    end

    test "accepts unambiguous scalar and compound bulk nodes" do
      nodes = [123, %{a: 1}, [1, 2], {:tuple, :node, :value}]
      pid = start_supervised!({HashRing.Managed, name: :compound_nodes, nodes: []})
      assert :ok = HashRing.Managed.add_nodes(pid, nodes)
      assert MapSet.new(HashRing.Managed.nodes(pid)) == MapSet.new(nodes)
      assert HashRing.Managed.nodes(:compound_nodes) == HashRing.Managed.nodes(pid)
      assert HashRing.Managed.add_nodes(:missing_ring, [123]) == {:error, :no_such_ring}
    end

    test "reports every invalid weight without changing membership" do
      pid = start_supervised!({HashRing.Managed, name: :atomic_bulk, nodes: ["existing"]})

      for weight <- [0, -1, 1.5, :wrong, nil, {}] do
        assert HashRing.Managed.add_nodes(pid, [123, {"bad", weight}]) ==
                 {:error, [{:invalid_weight, "bad", weight}]}

        assert HashRing.Managed.nodes(pid) == ["existing"]
      end
    end

    test "rejects improper bulk lists before changing membership" do
      pid = start_supervised!({HashRing.Managed, name: :improper_bulk, nodes: ["existing"]})

      for ring <- [pid, :improper_bulk, :missing_ring] do
        assert_raise ArgumentError, fn ->
          HashRing.Managed.add_nodes(ring, ["new" | :bad])
        end

        assert HashRing.Managed.nodes(pid) == ["existing"]
      end
    end

    test "keeps managed two-tuples as weighted syntax and allows explicitly weighted tuple keys" do
      pid = start_supervised!({HashRing.Managed, name: :tuple_nodes})

      assert HashRing.Managed.add_nodes(pid, [{:tuple, :node}]) ==
               {:error, [{:invalid_weight, :tuple, :node}]}

      assert HashRing.nodes(HashRing.add_nodes(HashRing.new(), [{:tuple, :node}])) == [
               {:tuple, :node}
             ]

      assert :ok = HashRing.Managed.add_nodes(pid, [{{:tuple, :node}, 64}])
      assert HashRing.Managed.nodes(pid) == [{:tuple, :node}]
    end

    test "rejects empty binary keys before sending any mutation to the worker" do
      pid = start_supervised!({HashRing.Managed, name: :empty_node_key, nodes: ["existing"]})

      for operation <- [
            fn -> HashRing.Managed.add_node(pid, "") end,
            fn -> HashRing.Managed.add_node(pid, "", 64) end,
            fn -> HashRing.Managed.add_nodes(pid, ["new", ""]) end,
            fn -> HashRing.Managed.add_nodes(pid, ["new", {"", 64}]) end
          ] do
        assert_raise ArgumentError, operation
        assert HashRing.Managed.nodes(pid) == ["existing"]
      end

      assert_raise ArgumentError, fn -> HashRing.Managed.new(:invalid_config, nodes: [""]) end
      assert Process.whereis(:libring_invalid_config) == nil
    end
  end

  describe "supervised rings" do
    test "start with populated nodes, overrides, and ownership under the caller" do
      pid =
        start_supervised!(
          {HashRing.Managed,
           [
             name: :supervised_ring,
             nodes: ["a"],
             id: :custom_ring,
             restart: :temporary,
             shutdown: 100
           ]}
        )

      assert HashRing.Managed.nodes(:supervised_ring) == ["a"]
      assert {:links, links} = Process.info(pid, :links)
      refute Process.whereis(HashRing.Supervisor) in links

      refute Enum.any?(DynamicSupervisor.which_children(HashRing.Supervisor), fn {_, child, _, _} ->
               child == pid
             end)

      spec = HashRing.Managed.child_spec(name: :supervised_ring, id: :custom_ring, shutdown: 100)
      assert spec.id == :custom_ring
      assert spec.shutdown == 100
      assert spec.modules == [HashRing.Worker]
    end

    test "restart under their caller and disappear when it shuts down" do
      parent =
        start_supervised!(%{
          id: :ring_parent,
          type: :supervisor,
          restart: :temporary,
          start:
            {Supervisor, :start_link,
             [[{HashRing.Managed, [name: :owned_ring, nodes: ["a"]]}], [strategy: :one_for_one]]}
        })

      [{:owned_ring, original, :worker, _}] = Supervisor.which_children(parent)
      ref = Process.monitor(original)
      Process.exit(original, :kill)
      assert_receive {:DOWN, ^ref, :process, ^original, :killed}

      replacement =
        assert_eventually(fn ->
          assert [{:owned_ring, pid, :worker, _}] = Supervisor.which_children(parent)
          assert is_pid(pid) and pid != original
          assert HashRing.Managed.nodes(pid) == ["a"]
          assert :ets.info(:libring_owned_ring, :owner) == pid
          assert {:links, [^parent]} = Process.info(pid, :links)
          pid
        end)

      ref = Process.monitor(replacement)
      Supervisor.stop(parent)
      assert_receive {:DOWN, ^ref, :process, ^replacement, :shutdown}
      assert HashRing.Managed.nodes(:owned_ring) == {:error, :no_such_ring}
      assert :ets.info(:libring_owned_ring) == :undefined
    end

    test "keep the default name and dynamic creation's duplicate-name behavior" do
      pid = start_supervised!({HashRing.Managed, []})
      assert HashRing.Managed.nodes(:hash_ring_manager) == []
      assert HashRing.Managed.new(:hash_ring_manager) == {:error, {:already_started, pid}}
    end

    test "validate options through the linked startup route" do
      assert_raise ArgumentError, ~r/invalid option/, fn ->
        HashRing.Managed.start_link(name: :invalid_linked_ring, nodes: "a")
      end

      assert Process.whereis(:libring_invalid_linked_ring) == nil
    end
  end

  test "multi-node lookup wraps through both managed read paths" do
    {:ok, pid} = HashRing.Managed.new(:managed_wraparound)
    on_exit(fn -> DynamicSupervisor.terminate_child(HashRing.Supervisor, pid) end)
    :ok = HashRing.Managed.add_nodes(pid, [:a@localhost, :b@localhost])
    assert HashRing.Managed.key_to_nodes(pid, 14, 2) == [:a@localhost, :b@localhost]

    assert HashRing.Managed.key_to_nodes(:managed_wraparound, 14, 2) == [
             :a@localhost,
             :b@localhost
           ]
  end

  test "all managed lookup forms agree on primary owners for atom and compound keys" do
    {:ok, pid} = HashRing.Managed.new(:consistent_hashing)
    on_exit(fn -> DynamicSupervisor.terminate_child(HashRing.Supervisor, pid) end)
    :ok = HashRing.Managed.add_nodes(pid, [:a@localhost, :b@localhost])
    ring = HashRing.new() |> HashRing.add_nodes([:a@localhost, :b@localhost])

    for key <- [:key_0, nil, true, false, "key", 13, {:tuple, [1, 2]}],
        count <- [1, 2, 5],
        managed <- [pid, :consistent_hashing] do
      expected = HashRing.key_to_node(ring, key)
      assert HashRing.Managed.key_to_node(managed, key) == expected
      assert hd(HashRing.Managed.key_to_nodes(managed, key, count)) == expected
    end
  end
end
