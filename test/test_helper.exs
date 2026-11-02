defmodule TestCluster do
  def start_node(prefix, type \\ :visible) do
    name = ~c"#{prefix}_#{System.unique_integer([:positive])}"
    args = if type == :hidden, do: [~c"-hidden"], else: []
    # Explicit cleanup owns the controller; it must survive the test process exiting.
    {:ok, peer, node} = :peer.start(%{name: name, args: args})
    ExUnit.Callbacks.on_exit(fn -> stop_node(peer) end)
    {:ok, peer, node}
  end

  def stop_node(peer) do
    if Process.alive?(peer), do: :peer.stop(peer)
  end

  def prepare do
    if Node.alive?() do
      false
    else
      {_, 0} = System.cmd("epmd", ["-daemon"])
      {:ok, _} = Node.start(:"libring_tests_#{System.pid()}", :shortnames)
      true
    end
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
