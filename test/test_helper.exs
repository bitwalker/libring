defmodule TestCluster do
  def start_node(name) do
    :peer.start_link(%{name: name})
  end

  def start_node(name, :hidden) do
    :peer.start_link(%{name: name, args: [~c"-hidden"]})
  end

  def stop_node(node) do
    :peer.stop(node)
  end

  def prepare do
    :ok = :net_kernel.monitor_nodes(true)

    _ = :os.cmd(~c"epmd -daemon")

    {:ok, _} = Node.start(:test_cluster@localhost, :shortnames)
  end

  def teardown do
    :ok = Node.stop()
  end
end

defmodule HashRing.TestSupport do
  def assert_eventually(assertion, timeout \\ 1_000) do
    retry_assertion(assertion, System.monotonic_time(:millisecond) + timeout)
  end

  defp retry_assertion(assertion, deadline) do
    assertion.()
  rescue
    error in ExUnit.AssertionError ->
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(10)
        retry_assertion(assertion, deadline)
      else
        reraise error, __STACKTRACE__
      end
  end
end

ExUnit.start()
