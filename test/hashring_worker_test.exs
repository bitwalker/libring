defmodule HashRing.WorkerTest do
  use ExUnit.Case

  describe "when the given node_type is :visible" do
    setup do
      TestCluster.prepare()

      {:ok, pid} =
        HashRing.Worker.start_link(
          name: :test_ring_worker,
          monitor_nodes: true,
          node_type: :visible
        )

      on_exit(fn ->
        HashRing.Worker.delete(pid)
        TestCluster.teardown()
      end)

      %{worker: pid}
    end

    test "it monitors only visible nodes", %{worker: pid} do
      nodes = [Node.self()]
      assert nodes == HashRing.Worker.nodes(pid)

      {:ok, node1} = TestCluster.start_node('test_node1')

      nodes = [node1 | nodes]
      assert nodes == HashRing.Worker.nodes(pid)

      {:ok, _node2} = TestCluster.start_node('test_node2', :hidden)
      assert nodes == HashRing.Worker.nodes(pid)
    end
  end
end
