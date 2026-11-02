defmodule HashRing.WorkerTest do
  use ExUnit.Case
  import HashRing.TestSupport

  setup_all do
    started? = TestCluster.prepare()
    on_exit(fn -> if started?, do: TestCluster.teardown() end)
    :ok
  end

  test "visible peers have the same eligibility before and after startup" do
    assert_membership(:visible)
  end

  test "hidden peers have the same eligibility before and after startup" do
    assert_membership(:hidden)
  end

  test "all peers have the same eligibility before and after startup" do
    assert_membership(:all)
  end

  test "valid manual mutations are ignored on monitored rings through either API" do
    pid = start_supervised!({HashRing.Managed, name: :monitored_mutations, monitor_nodes: true})
    expected = [Node.self()]

    for ring <- [pid, :monitored_mutations] do
      assert :ok = HashRing.Managed.add_node(ring, :manual)
      assert :ok = HashRing.Managed.add_node(ring, :weighted, 64)
      assert :ok = HashRing.Managed.add_nodes(ring, [:bulk, {:weighted_bulk, 32}])
      assert :ok = HashRing.Managed.remove_node(ring, Node.self())
      assert HashRing.Managed.nodes(ring) == expected
    end
  end

  test "whitelist admission overrides blacklist admission at startup and on nodeup" do
    {:ok, _, allowed} = TestCluster.start_node("allowed")
    {:ok, _, denied} = TestCluster.start_node("denied")

    pid =
      start_supervised!(
        {HashRing.Managed,
         name: :filtered_membership,
         monitor_nodes: true,
         node_blacklist: [~r/^allowed_/],
         node_whitelist: [~r/^allowed_/, Atom.to_string(Node.self())]}
      )

    assert_members(pid, [Node.self(), allowed])
    refute denied in HashRing.Managed.nodes(pid)
    {:ok, _, later} = TestCluster.start_node("allowed_later")
    assert_members(pid, [Node.self(), allowed, later])
  end

  test "startup during membership changes converges and removes disconnected peers" do
    for index <- 1..3 do
      name = :"churn_ring_#{index}"
      starter = Task.async(fn -> HashRing.Managed.new(name, monitor_nodes: true) end)
      {:ok, peer, node} = TestCluster.start_node("churn")
      {:ok, pid} = Task.await(starter)
      on_exit(fn -> DynamicSupervisor.terminate_child(HashRing.Supervisor, pid) end)
      assert_members(pid, [Node.self(), node])
      TestCluster.stop_node(peer)
      assert_members(pid, [Node.self()])
    end
  end

  defp assert_membership(type) do
    {:ok, _, visible} = TestCluster.start_node("visible_before")
    {:ok, _, hidden} = TestCluster.start_node("hidden_before", :hidden)
    pid = start_supervised!({HashRing.Managed, name: type, monitor_nodes: true, node_type: type})

    eligible =
      case type do
        :visible -> [visible]
        :hidden -> [hidden]
        :all -> [visible, hidden]
      end

    assert_members(pid, [Node.self() | eligible])
    {:ok, visible_peer, later_visible} = TestCluster.start_node("visible_after")
    {:ok, hidden_peer, later_hidden} = TestCluster.start_node("hidden_after", :hidden)

    eligible_later =
      case type do
        :visible -> [later_visible]
        :hidden -> [later_hidden]
        :all -> [later_visible, later_hidden]
      end

    assert_members(pid, [Node.self() | eligible ++ eligible_later])
    TestCluster.stop_node(visible_peer)
    TestCluster.stop_node(hidden_peer)
    assert_members(pid, [Node.self() | eligible])
  end

  defp assert_members(ring, expected) do
    assert_eventually(fn ->
      assert Enum.sort(HashRing.Managed.nodes(ring)) == Enum.sort(expected)
    end)
  end
end
