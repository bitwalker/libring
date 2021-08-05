defmodule HashRing.Worker do
  @moduledoc false
  use GenServer

  def nodes(pid_or_name)

  def nodes(pid) when is_pid(pid) do
    do_call(pid, :list_nodes)
  end

  def nodes(name) when is_atom(name) do
    name
    |> get_ets_name()
    |> get_ring()
    |> HashRing.nodes()
  rescue
    ArgumentError -> 
      {:error, :no_such_ring}
  end

  def add_node(name, node), do: do_call(name, {:add_node, node})
  def add_node(name, node, weight), do: do_call(name, {:add_node, node, weight})
  def add_nodes(name, nodes), do: do_call(name, {:add_nodes, nodes})
  def remove_node(name, node), do: do_call(name, {:remove_node, node})

  def key_to_node(pid_or_name, key)

  def key_to_node(pid, key) when is_pid(pid) do
    do_call(pid, {:key_to_node, key})
  end

  def key_to_node(name, key) when is_atom(name) do
    name
    |> get_ets_name()
    |> get_ring()
    |> HashRing.key_to_node(key)
  rescue
    ArgumentError ->
      {:error, :no_such_ring}
  end

  def delete(name), do: do_call(name, :delete)

  ## Server

  def start_link(options) do
    name = Keyword.fetch!(options, :name)
    GenServer.start_link(__MODULE__, options, name: :"libring_#{name}")
  end

  def init(options) do
    name = Keyword.fetch!(options, :name)

    table =
      :ets.new(get_ets_name(name), [
        :set,
        :protected,
        :named_table,
        {:write_concurrency, false},
        {:read_concurrency, true}
      ])

    ring = HashRing.new()

    monitor_nodes? = Keyword.get(options, :monitor_nodes, false)

    cond do
      monitor_nodes? ->
        nodes = [Node.self() | Node.list(:connected)]
        node_blacklist = Keyword.get(options, :node_blacklist, [~r/^remsh.*$/, ~r/^rem-.*$/])
        node_whitelist = Keyword.get(options, :node_whitelist, [])

        ring =
          Enum.reduce(nodes, ring, fn node, acc ->
            cond do
              HashRing.Utils.ignore_node?(node, node_blacklist, node_whitelist) ->
                acc

              :else ->
                HashRing.add_node(acc, node)
            end
          end)

        node_type = Keyword.get(options, :node_type, :all)
        :ok = :net_kernel.monitor_nodes(true, node_type: node_type)
        true = :ets.insert_new(table, {:ring, ring})
        {:ok, {table, node_blacklist, node_whitelist}}

      :else ->
        nodes = Keyword.get(options, :nodes, [])
        ring = HashRing.add_nodes(ring, nodes)
        true = :ets.insert_new(table, {:ring, ring})
        {:ok, {table, [], []}}
    end
  end

  def handle_call(:list_nodes, _from, {table, _b, _w} = state) do
    {:reply, HashRing.nodes(get_ring(table)), state}
  end

  def handle_call({:key_to_node, key}, _from, {table, _b, _w} = state) do
    {:reply, HashRing.key_to_node(get_ring(table), key), state}
  end

  def handle_call({:add_node, node}, _from, {table, _b, _w} = state) do
    get_ring(table) |> HashRing.add_node(node) |> update_ring(table)
    {:reply, :ok, state}
  end

  def handle_call({:add_node, node, weight}, _from, {table, _b, _w} = state) do
    get_ring(table) |> HashRing.add_node(node, weight) |> update_ring(table)
    {:reply, :ok, state}
  end

  def handle_call({:add_nodes, nodes}, _from, {table, _b, _w} = state) do
    get_ring(table) |> HashRing.add_nodes(nodes) |> update_ring(table)
    {:reply, :ok, state}
  end

  def handle_call({:remove_node, node}, _from, {table, _b, _w} = state) do
    get_ring(table) |> HashRing.remove_node(node) |> update_ring(table)
    {:reply, :ok, state}
  end

  def handle_call(:delete, _from, state) do
    :ok = :net_kernel.monitor_nodes(false)
    {:stop, :shutdown, state}
  end

  def handle_info({:nodeup, node, _info}, {table, b, w} = state) do
    unless HashRing.Utils.ignore_node?(node, b, w) do
      get_ring(table) |> HashRing.add_node(node) |> update_ring(table)
    end

    {:noreply, state}
  end

  def handle_info({:nodedown, node, _info}, state = {table, _b, _w}) do
    get_ring(table) |> HashRing.remove_node(node) |> update_ring(table)
    {:noreply, state}
  end

  defp get_ets_name(name), do: :"libring_#{name}"

  defp do_call(pid_or_name, msg)

  defp do_call(pid, msg) when is_pid(pid) do
    GenServer.call(pid, msg)
  catch
    :exit, {:noproc, _} ->
      {:error, :no_such_ring}
  end

  defp do_call(name, msg) when is_atom(name) do
    GenServer.call(:"libring_#{name}", msg)
  catch
    :exit, {:noproc, _} ->
      {:error, :no_such_ring}
  end

  defp get_ring(table), do: :ets.lookup_element(table, :ring, 2)

  defp update_ring(ring, table), 
    do: :ets.update_element(table, :ring, {2, ring})
end
