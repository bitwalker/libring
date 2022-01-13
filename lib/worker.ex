defmodule HashRing.Worker do
  @moduledoc false
  use GenServer

  @erpc_timeout 500
  @node_readiness_check_interval :timer.seconds(1)

  defstruct [
    :table,
    :node_blacklist,
    :node_whitelist,
    :wait_for_readiness,
    :readiness_deps_set
  ]

  alias __MODULE__, as: State

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
        wait_for_readiness = Keyword.get(options, :wait_for_readiness, false)
        readiness_deps_set = Keyword.get(options, :readiness_deps, []) |> MapSet.new()

        ring =
          Enum.reduce(nodes, ring, fn node, acc ->
            if HashRing.Utils.ignore_node?(node, node_blacklist, node_whitelist) do
              acc
            else
              if wait_for_readiness do
                if node_ready?(node, readiness_deps_set) do
                  HashRing.add_node(acc, node)
                else
                  schedule_check_for_node_readiness(node)
                  acc
                end
              else
                HashRing.add_node(acc, node)
              end
            end
          end)

        node_type = Keyword.get(options, :node_type, :all)
        :ok = :net_kernel.monitor_nodes(true, node_type: node_type)
        true = :ets.insert_new(table, {:ring, ring})

        {:ok,
         %State{
           table: table,
           node_blacklist: node_blacklist,
           node_whitelist: node_whitelist,
           wait_for_readiness: wait_for_readiness,
           readiness_deps_set: readiness_deps_set
         }}

      :else ->
        nodes = Keyword.get(options, :nodes, [])
        ring = HashRing.add_nodes(ring, nodes)
        true = :ets.insert_new(table, {:ring, ring})

        {:ok,
         %State{
           table: table,
           node_blacklist: [],
           node_whitelist: [],
           wait_for_readiness: false,
           readiness_deps_set: MapSet.new()
         }}
    end
  end

  def handle_call(:list_nodes, _from, %State{table: table} = state) do
    {:reply, HashRing.nodes(get_ring(table)), state}
  end

  def handle_call({:key_to_node, key}, _from, %State{table: table} = state) do
    {:reply, HashRing.key_to_node(get_ring(table), key), state}
  end

  def handle_call(
        {:add_node, node},
        _from,
        %State{
          table: table,
          wait_for_readiness: wait_for_readiness,
          readiness_deps_set: readiness_deps_set
        } = state
      ) do
    if wait_for_readiness and not node_ready?(node, readiness_deps_set) do
      schedule_check_for_node_readiness(node)
    else
      get_ring(table) |> HashRing.add_node(node) |> update_ring(table)
    end

    {:reply, :ok, state}
  end

  def handle_call(
        {:add_node, node, weight},
        _from,
        %State{
          table: table,
          wait_for_readiness: wait_for_readiness,
          readiness_deps_set: readiness_deps_set
        } = state
      ) do
    if wait_for_readiness and not node_ready?(node, readiness_deps_set) do
      schedule_check_for_node_readiness({node, weight})
    else
      get_ring(table) |> HashRing.add_node(node, weight) |> update_ring(table)
    end

    {:reply, :ok, state}
  end

  def handle_call(
        {:add_nodes, nodes},
        _from,
        %State{
          table: table,
          wait_for_readiness: wait_for_readiness,
          readiness_deps_set: readiness_deps_set
        } = state
      ) do
    if wait_for_readiness do
      %{true: ready_nodes, false: starting_nodes} =
        Enum.group_by(
          nodes,
          fn
            {node, _weight} ->
              node_ready?(node, readiness_deps_set)

            node ->
              node_ready?(node, readiness_deps_set)
          end
        )

      get_ring(table) |> HashRing.add_nodes(ready_nodes) |> update_ring(table)

      for starting_node <- starting_nodes do
        schedule_check_for_node_readiness(starting_node)
      end
    else
      get_ring(table) |> HashRing.add_nodes(nodes) |> update_ring(table)
    end

    {:reply, :ok, state}
  end

  def handle_call({:remove_node, node}, _from, %State{table: table} = state) do
    get_ring(table) |> HashRing.remove_node(node) |> update_ring(table)
    {:reply, :ok, state}
  end

  def handle_call(:delete, _from, state) do
    :ok = :net_kernel.monitor_nodes(false)
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:nodeup, node, _info},
        %State{
          table: table,
          node_blacklist: b,
          node_whitelist: w,
          wait_for_readiness: wait_for_readiness,
          readiness_deps_set: readiness_deps_set
        } = state
      ) do
    unless HashRing.Utils.ignore_node?(node, b, w) do
      if wait_for_readiness and not node_ready?(node, readiness_deps_set) do
        schedule_check_for_node_readiness(node)
      else
        get_ring(table) |> HashRing.add_node(node) |> update_ring(table)
      end
    end

    {:noreply, state}
  end

  def handle_info({:nodedown, node, _info}, %State{table: table} = state) do
    get_ring(table) |> HashRing.remove_node(node) |> update_ring(table)
    {:noreply, state}
  end

  def handle_info(
        {:check_node_readiness, node, weight},
        %State{table: table, readiness_deps_set: readiness_deps_set} = state
      ) do
    if node_ready?(node, readiness_deps_set) do
      get_ring(table) |> HashRing.add_node(node, weight) |> update_ring(table)
    else
      schedule_check_for_node_readiness({node, weight})
    end

    {:noreply, state}
  end

  def handle_info(
        {:check_node_readiness, node},
        %State{table: table, readiness_deps_set: readiness_deps_set} = state
      ) do
    if node_ready?(node, readiness_deps_set) do
      get_ring(table) |> HashRing.add_node(node) |> update_ring(table)
    else
      schedule_check_for_node_readiness(node)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
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

  defp get_started_apps_set(node) do
    try do
      :erpc.call(node, Application, :started_applications, [], @erpc_timeout)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()
    rescue
      _e -> MapSet.new()
    end
  end

  defp node_ready?(node, readiness_deps_set) do
    MapSet.difference(readiness_deps_set, get_started_apps_set(node))
    |> MapSet.equal?(MapSet.new())
  end

  defp schedule_check_for_node_readiness({node, weight}) do
    if node in Node.list() do
      :timer.send_after(@node_readiness_check_interval, {:check_node_readiness, node, weight})
    end
  end

  defp schedule_check_for_node_readiness(node) do
    if node in Node.list() do
      :timer.send_after(@node_readiness_check_interval, {:check_node_readiness, node})
    end
  end
end
