defmodule HashRing.WorkerTest do
  use ExUnit.Case

  describe "when the given node_type is :visible" do
    setup do
      {:ok, pid} =
        HashRing.Worker.start_link(
          name: :test_ring_worker,
          monitor_nodes: true,
          node_type: :visible,
          node_whitelist: [~r/^normal.*$/, ~r/^hidden.*$/, ~r/^manager.*$/]
        )

      %{worker: pid}
    end

    test "it monitors only visible nodes", %{worker: pid} do
      nodes = [Node.self()]

      TestCluster.retry_until_true(fn ->
        nodes == HashRing.Worker.nodes(pid)
      end)

      assert nodes == HashRing.Worker.nodes(pid)

      [node1] = TestCluster.start_nodes("normal", 1)

      nodes = [node1 | nodes]
      assert nodes == HashRing.Worker.nodes(pid)

      [node2] = TestCluster.start_nodes("hidden", 1, hidden: true)
      assert nodes == HashRing.Worker.nodes(pid)
      LocalCluster.stop_nodes([node1, node2])
    end
  end
end
