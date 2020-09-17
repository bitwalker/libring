defmodule TestCluster do
  def start_node(name) do
    :slave.start_link(:localhost, name)
  end

  def start_node(name, :hidden) do
    :slave.start_link(:localhost, name, '-hidden')
  end

  def stop_node(node) do
    :slave.stop(node)
  end

  def prepare do
    :ok = :net_kernel.monitor_nodes(true)

    _ = :os.cmd('epmd -daemon')

    {:ok, _} = Node.start(:test_cluster@localhost, :shortnames)
  end

  def teardown do
    :ok = Node.stop()
  end
end

ExUnit.start()
