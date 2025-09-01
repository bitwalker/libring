defmodule HashRing.WorkerTest do
  use ExUnit.Case, async: false

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

      {:ok, _peer, node1} = TestCluster.start_node(~c"test_node1")

      nodes = [node1 | nodes]
      assert nodes == HashRing.Worker.nodes(pid)

      {:ok, _peer, _node2} = TestCluster.start_node(~c"test_node2", :hidden)
      assert nodes == HashRing.Worker.nodes(pid)
    end
  end

  describe "node weight distribution" do
    test "initial nodes respect node_weight configuration" do
      TestCluster.prepare()

      {:ok, pid} =
        HashRing.Worker.start_link(
          name: :initial_nodes_weight_test,
          monitor_nodes: false,
          node_weight: 100,
          nodes: [:node_default, {:node_explicit, 300}]
        )

      on_exit(fn ->
        HashRing.Worker.delete(pid)
        TestCluster.teardown()
      end)

      distribution = distribute_keys(pid, 50_000)

      assert_in_delta(distribution[:node_default] / 50_000, 0.25, 0.03)
      assert_in_delta(distribution[:node_explicit] / 50_000, 0.75, 0.03)
    end

    test "add_node API respects node_weight vs explicit weight" do
      TestCluster.prepare()

      {:ok, pid} =
        HashRing.Worker.start_link(
          name: :add_node_weight_test,
          monitor_nodes: false,
          node_weight: 100,
          nodes: []
        )

      on_exit(fn ->
        HashRing.Worker.delete(pid)
        TestCluster.teardown()
      end)

      :ok = HashRing.Worker.add_node(pid, :default_weight)
      :ok = HashRing.Worker.add_node(pid, :explicit_weight, 200)

      distribution = distribute_keys(pid, 50_000)

      assert_in_delta(distribution[:default_weight] / 50_000, 0.3333, 0.03)
      assert_in_delta(distribution[:explicit_weight] / 50_000, 0.6667, 0.03)
    end

    test "add_nodes API respects node_weight for unweighted nodes" do
      TestCluster.prepare()

      {:ok, pid} =
        HashRing.Worker.start_link(
          name: :add_nodes_weight_test,
          monitor_nodes: false,
          node_weight: 100,
          nodes: []
        )

      on_exit(fn ->
        HashRing.Worker.delete(pid)
        TestCluster.teardown()
      end)

      :ok =
        HashRing.Worker.add_nodes(pid, [
          :light_node,
          {:heavy_node, 300}
        ])

      distribution = distribute_keys(pid, 50_000)

      assert_in_delta(distribution[:light_node] / 50_000, 0.25, 0.03)
      assert_in_delta(distribution[:heavy_node] / 50_000, 0.75, 0.03)
    end

    test "nodes with equal weights get equal distribution" do
      TestCluster.prepare()

      {:ok, pid} =
        HashRing.Worker.start_link(
          name: :equal_weight_test,
          monitor_nodes: false,
          node_weight: 150,
          nodes: [:node_a, :node_b]
        )

      on_exit(fn ->
        HashRing.Worker.delete(pid)
        TestCluster.teardown()
      end)

      :ok = HashRing.Worker.add_node(pid, :node_c)

      distribution = distribute_keys(pid, 60_000)

      assert_in_delta(distribution[:node_a] / 60_000, 0.3333, 0.03)
      assert_in_delta(distribution[:node_b] / 60_000, 0.3333, 0.03)
      assert_in_delta(distribution[:node_c] / 60_000, 0.3333, 0.03)
    end

    test "monitored nodes respect configured node_weight through distribution variance" do
      TestCluster.prepare()

      # Ring with LOW weight - expect higher variance
      {:ok, pid_low} =
        HashRing.Worker.start_link(
          name: :monitor_low_weight,
          monitor_nodes: true,
          node_weight: 10,
          node_type: :visible
        )

      # Ring with HIGH weight - expect lower variance
      {:ok, pid_high} =
        HashRing.Worker.start_link(
          name: :monitor_high_weight,
          monitor_nodes: true,
          node_weight: 500,
          node_type: :visible
        )

      on_exit(fn ->
        HashRing.Worker.delete(pid_low)
        HashRing.Worker.delete(pid_high)
        TestCluster.teardown()
      end)

      assert wait_for_nodes(pid_low, 1)
      assert wait_for_nodes(pid_high, 1)

      {:ok, _peer, new_node} = TestCluster.start_node(~c"test_node")

      assert wait_for_nodes(pid_low, 2)
      assert wait_for_nodes(pid_high, 2)
      assert new_node in HashRing.Worker.nodes(pid_low)
      assert new_node in HashRing.Worker.nodes(pid_high)

      sample_size = 10_000
      dist_low = distribute_keys(pid_low, sample_size)
      dist_high = distribute_keys(pid_high, sample_size)

      # Calculate how far from perfect 50% each node is
      deviation_low = abs(dist_low[Node.self()] / sample_size - 0.5)
      deviation_high = abs(dist_high[Node.self()] / sample_size - 0.5)

      # Low weight ring should have higher deviation from ideal 50%
      assert deviation_low > deviation_high

      # More specifically, low weight should be noticeably uneven
      assert deviation_low > 0.1
      assert deviation_high < 0.015
    end

    defp wait_for_nodes(pid, expected_count, timeout \\ 5000) do
      deadline = System.monotonic_time(:millisecond) + timeout
      wait_for_nodes_loop(pid, expected_count, deadline)
    end

    defp wait_for_nodes_loop(pid, expected_count, deadline) do
      case HashRing.Worker.nodes(pid) do
        nodes when length(nodes) == expected_count ->
          true

        _ ->
          if System.monotonic_time(:millisecond) < deadline do
            :timer.sleep(50)
            wait_for_nodes_loop(pid, expected_count, deadline)
          else
            false
          end
      end
    end

    defp distribute_keys(pid, count) do
      1..count
      |> Enum.map(fn i ->
        HashRing.Worker.key_to_node(pid, "test_key_#{i}")
      end)
      |> Enum.frequencies()
    end
  end
end
