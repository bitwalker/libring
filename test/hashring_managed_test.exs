defmodule HashRing.ManagedTest do
  use ExUnit.Case, async: true
  doctest HashRing.Managed
  import HashRing.TestSupport

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
