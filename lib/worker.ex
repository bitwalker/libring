defmodule HashRing.Worker do
  @moduledoc false
  use GenServer

  def nodes(name),                  do: do_call(name, :list_nodes)
  def add_node(name, node),         do: do_call(name, {:add_node, node})
  def add_node(name, node, weight), do: do_call(name, {:add_node, node, weight})
  def add_nodes(name, nodes),       do: do_call(name, {:add_nodes, nodes})
  def remove_node(name, node),      do: do_call(name, {:remove_node, node})
  def key_to_node(name, key),       do: do_call(name, {:key_to_node, key})
  def delete(name),                 do: do_call(name, :delete)

  defp do_call(name, msg) do
    GenServer.call(name, msg)
  catch
    :exit, {:noproc, _} ->
      {:error, :no_such_ring}
  end

  def start_link(options) do
    name = Keyword.fetch!(options, :name)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def init(options) do
    ring = HashRing.new()

    monitor_nodes? = Keyword.get(options, :monitor_nodes, false)
    cond do
      monitor_nodes? ->
        nodes = [Node.self|Node.list(:connected)]
        node_blacklist = Keyword.get(options, :node_blacklist, [~r/^remsh.*$/])
        node_whitelist = Keyword.get(options, :node_whitelist, [])
        ring = Enum.reduce(nodes, ring, fn node, acc ->
          cond do
            HashRing.Utils.ignore_node?(node, node_blacklist, node_whitelist) ->
              acc
            :else ->
              HashRing.add_node(acc, node)
          end
        end)
        :ok = :net_kernel.monitor_nodes(true, [node_type: :all])
        {:ok, {ring, node_blacklist, node_whitelist}}
      :else ->
        nodes = Keyword.get(options, :nodes, [])
        ring = HashRing.add_nodes(ring, nodes)
        {:ok, {ring, [], []}}
    end
  end

  def handle_call(:list_nodes, _from, {ring, _, _} = state) do
    {:reply, HashRing.nodes(ring), state}
  end
  def handle_call({:add_node, node}, _from, {ring, b, w}) do
    {:reply, :ok, {HashRing.add_node(ring, node), b, w}}
  end
  def handle_call({:add_node, node, weight}, _from, {ring, b, w}) do
    {:reply, :ok, {HashRing.add_node(ring, node, weight), b, w}}
  end
  def handle_call({:add_nodes, nodes}, _from, {ring, b, w}) do
    {:reply, :ok, {HashRing.add_nodes(ring, nodes), b, w}}
  end
  def handle_call({:remove_node, node}, _from, {ring, b, w}) do
    {:reply, :ok, {HashRing.remove_node(ring, node), b, w}}
  end
  def handle_call({:key_to_node, key}, _from, {ring, _, _} = state) do
    {:reply, HashRing.key_to_node(ring, key), state}
  end
  def handle_call(:delete, _from, state) do
    :ok = :net_kernel.monitor_nodes(false)
    {:stop, :shutdown, state}
  end

  def handle_info({:nodeup, node, _info}, {ring, b, w} = state) do
    if HashRing.Utils.ignore_node?(node, b, w) do
      {:noreply, state}
    else
      {:noreply, {HashRing.add_node(ring, node), b, w}}
    end
  end
  def handle_info({:nodedown, node, _info}, {ring, b, w}) do
    {:noreply, {HashRing.remove_node(ring, node), b, w}}
  end
end
