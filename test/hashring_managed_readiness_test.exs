defmodule HashRing.ManagedReadinessTest do
  use ExUnit.Case, async: false

  test "Node doesn't get added until ready in readiness mode" do
    {:ok, pid} =
      HashRing.Worker.start_link(
        name: :test_ring_worker_readiness,
        monitor_nodes: true,
        node_type: :visible,
        wait_for_readiness: true,
        readiness_deps: [:ssh],
        node_whitelist: [~r/^readiness.*$/, ~r/^manager.*$/]
      )

    nodes =
      [node1, node2, node3] =
      LocalCluster.start_nodes(
        "readiness",
        3
      )

    for n <- nodes, do: :net_adm.ping(n)
    for n <- nodes, do: :erpc.call(n, Application, :ensure_all_started, [:libring])

    for n <- nodes,
        do:
          :erpc.call(n, HashRing.Worker, :start_link, [
            [
              name: :test_ring_worker_readiness,
              monitor_nodes: true,
              node_type: :visible,
              wait_for_readiness: true,
              readiness_deps: [:ssh],
              node_whitelist: [~r/^readiness.*$/, ~r/^manager.*$/]
            ]
          ])

    :erpc.call(node1, Application, :ensure_all_started, [:ssh])
    :erpc.call(node2, Application, :ensure_all_started, [:ssh])

    TestCluster.retry_until_true(fn ->
      :ssh in (:erpc.call(node1, Application, :started_applications, [])
               |> Enum.map(&elem(&1, 0)))
    end)

    TestCluster.retry_until_true(fn ->
      :ssh in (:erpc.call(node2, Application, :started_applications, [])
               |> Enum.map(&elem(&1, 0)))
    end)

    TestCluster.retry_until_true(fn ->
      case HashRing.Worker.key_to_node(pid, :k) do
        {:error, {:invalid_ring, :no_nodes}} -> false
        _ -> true
      end
    end)

    for i <- 1..100 do
      assert HashRing.Worker.key_to_node(pid, i) in [node1, node2]
    end

    :erpc.call(node3, Application, :ensure_all_started, [:ssh])

    TestCluster.retry_until_true(fn ->
      case HashRing.Worker.key_to_node(pid, :erlang.monotonic_time()) do
        ^node3 -> true
        _ -> false
      end
    end)

    assert for(i <- 1..100, do: HashRing.Worker.key_to_node(pid, i) === node3) |> Enum.any?()

    LocalCluster.stop_nodes(nodes)
  end
end
