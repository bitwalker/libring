defmodule HashRing.Managed do
  @moduledoc """
  This module defines the API for working with hash rings where the ring state is managed
  in a GenServer process.

  There is a performance penalty with working with the ring this way, but it is the best approach
  if you need to share the ring across multiple processes, or need to maintain multiple rings.

  If your rings map 1:1 with Erlang node membership, you can configure rings to automatically
  monitor node up/down events and update the hash ring accordingly, with a default weight,
  and either whitelist or blacklist nodes from the ring. You configure this at the ring level in your `config.exs`.

  Each ring is configured in `config.exs`, and can contain a list of nodes to seed the ring with,
  and you can then dynamically add/remove nodes to the ring using the API here. Each node on the ring can
  be configured with a weight, which affects the amount of the total keyspace it owns. The default weight
  is `128`. It's best to base the weight of nodes on some concrete relative value, such as the amount of
  memory a node has.
  """

  @type ring :: pid() | atom()
  @type key :: any()
  @type weight :: pos_integer
  @type node_list :: [term() | {term(), weight}]
  @type pattern_list :: [String.t() | Regex.t()]
  @type ring_options :: [
          name: atom(),
          nodes: node_list,
          monitor_nodes: boolean,
          node_blacklist: pattern_list,
          node_whitelist: pattern_list,
          node_type: :all | :hidden | :visible
        ]

  @type child_spec_option ::
          {:name, atom()}
          | {:id, term()}
          | {:start, {module, function_name :: atom, args :: [term]}}
          | {:restart, :permanent | :transient | :temporary}
          | {:shutdown, timeout() | :brutal_kill}
          | {:type, :worker | :supervisor}
          | {:modules, [module] | :dynamic}
          | {:significant, boolean}
          | {:nodes, node_list}
          | {:monitor_nodes, boolean}
          | {:node_blacklist, pattern_list}
          | {:node_whitelist, pattern_list}
          | {:node_type, :all | :hidden | :visible}

  @type child_spec_options :: [child_spec_option()]

  @valid_ring_opts [:name, :nodes, :monitor_nodes, :node_blacklist, :node_whitelist, :node_type]
  @valid_child_spec_opts [:id, :start, :restart, :shutdown, :type, :modules, :significant]
  @empty_node_message "Node keys cannot be empty strings"

  @spec child_spec(child_spec_options) :: Supervisor.child_spec()
  def child_spec(opts) do
    validate_option_keys!(
      opts,
      @valid_ring_opts ++ @valid_child_spec_opts,
      "HashRing.Managed.child_spec/1"
    )

    opts = Keyword.put_new(opts, :name, :hash_ring_manager)

    Map.merge(
      %{
        id: opts[:id] || opts[:name],
        type: :worker,
        restart: :permanent,
        modules: [HashRing.Worker],
        start: {__MODULE__, :start_link, [Keyword.take(opts, @valid_ring_opts)]}
      },
      Map.new(Keyword.drop(opts, @valid_ring_opts))
    )
  end

  @doc """
  Starts a managed ring linked to the calling process.

  This is the startup entry point used by `child_spec/1`. The `:name` option is
  required; other ring options are the same as for `new/2`. The calling supervisor
  owns the worker's restart and shutdown lifecycle.
  """
  @spec start_link(ring_options) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    validate_ring_options!(opts, "HashRing.Managed.start_link/1")
    HashRing.Worker.start_link(opts)
  end

  @doc """
  Creates a new stateful hash ring with the given name.

  This name is how you will refer to the hash ring via other API calls.

  It takes an optional set of options which control how the ring behaves.
  Valid options are as follows:

  * `nodes: list` - a list of nodes to initialize the ring.
  * `monitor_nodes: boolean` - will automatically monitor Erlang node membership,
    if new nodes are connected or nodes are disconnected, the ring will be updated automatically.
    In this configuration, nodes cannot be added or removed via the API. Those requests will be ignored.
  * `node_blacklist: [String.t | Regex.t]` - Used in conjunction with `monitor_nodes: true`, this
    is a list of patterns, either as literal strings, or as regex patterns (in either string or literal form),
    and will be used to ignore nodeup/down events for nodes which are blacklisted. If a node whitelist
    is provided, the blacklist has no effect.
  * `node_whitelist: [String.t | Regex.t]` - The same as `node_blacklist`, except the opposite; only nodes
    which match a pattern in the whitelist will result in the ring being updated.
  * `node_type: :all | :hidden | :visible`: refers what kind of nodes will be monitored
    when `monitor_nodes` is `true`. For more information, see `:net_kernel.monitor_nodes/2`.

  An error is returned if the ring already exists. Invalid options raise `ArgumentError`.

  ## Examples

      iex> {:ok, _pid} = HashRing.Managed.new(:test1, [nodes: ["a", {"b", 64}]])
      ...> HashRing.Managed.key_to_node(:test1, :foo)
      "a"

      iex> {:ok, pid} = HashRing.Managed.new(:test2)
      ...> {:error, {:already_started, existing_pid}} = HashRing.Managed.new(:test2)
      ...> pid == existing_pid
      true
      iex> HashRing.Managed.new(:test3, [nodes: "a"])
      ** (ArgumentError) {:nodes, "a"} is an invalid option for `HashRing.Managed.new/2`

  """
  @spec new(atom()) :: {:ok, pid} | {:error, term()}
  @spec new(atom(), ring_options) :: {:ok, pid} | {:error, term()}
  def new(name, ring_options \\ []) when is_list(ring_options) do
    opts = [{:name, name} | ring_options]
    validate_ring_options!(opts)

    case Process.whereis(:"libring_#{name}") do
      nil ->
        DynamicSupervisor.start_child(HashRing.Supervisor, {HashRing.Worker, opts})

      pid ->
        {:error, {:already_started, pid}}
    end
  end

  defp validate_ring_options!(opts, caller \\ "HashRing.Managed.new/2") do
    validate_option_keys!(opts, @valid_ring_opts, caller)

    unless Keyword.has_key?(opts, :name), do: raise(ArgumentError, "#{caller} requires :name")

    Enum.each(opts, fn option ->
      unless valid_ring_option?(option), do: invalid_option!(option, caller)
    end)
  end

  defp validate_option_keys!(opts, keys, caller) do
    unless Keyword.keyword?(opts),
      do: raise(ArgumentError, "#{caller} expects a keyword list, got: #{inspect(opts)}")

    Enum.each(opts, fn {key, _} = option ->
      unless key in keys, do: invalid_option!(option, caller)
    end)
  end

  defp invalid_option!(option, caller),
    do: raise(ArgumentError, "#{inspect(option)} is an invalid option for `#{caller}`")

  defp valid_ring_option?({:name, name}), do: is_atom(name)
  defp valid_ring_option?({:nodes, nodes}) when is_list(nodes), do: node_entry_errors(nodes) == []
  defp valid_ring_option?({:monitor_nodes, enabled}), do: is_boolean(enabled)

  defp valid_ring_option?({key, patterns})
       when key in [:node_blacklist, :node_whitelist] and is_list(patterns),
       do: Enum.all?(patterns, &(is_binary(&1) or is_struct(&1, Regex)))

  defp valid_ring_option?({:node_type, type}), do: type in [:all, :hidden, :visible]
  defp valid_ring_option?(_), do: false

  defp node_entry_errors(nodes),
    do: nodes |> Enum.map(&node_entry_error/1) |> Enum.reject(&is_nil/1)

  defp node_entry_error({node, weight}) when is_integer(weight) and weight > 0,
    do: node_key_error(node)

  defp node_entry_error({node, weight}), do: {:invalid_weight, node, weight}
  defp node_entry_error(node), do: node_key_error(node)
  defp node_key_error(""), do: :empty_node
  defp node_key_error(_), do: nil

  defp validate_node_key!(node) do
    if node_key_error(node), do: raise(ArgumentError, @empty_node_message)
    :ok
  end

  @doc """
  Same as `HashRing.nodes/1`, returns a list of nodes on the ring.

  ## Examples

      iex> {:ok, _pid} = HashRing.Managed.new(:nodes_test)
      ...> HashRing.Managed.add_nodes(:nodes_test, [:a, :b])
      ...> HashRing.Managed.nodes(:nodes_test)
      [:b, :a]
  """
  @spec nodes(ring) :: [term()]
  def nodes(ring) do
    HashRing.Worker.nodes(ring)
  end

  @doc """
  Adds a node to the given hash ring.

  An error is returned if the ring does not exist, or the node already exists in the ring.

  ## Examples

      iex> {:ok, _pid} = HashRing.Managed.new(:test4)
      ...> HashRing.Managed.add_node(:test4, "a")
      ...> HashRing.Managed.key_to_node(:test4, :foo)
      "a"

      iex> HashRing.Managed.add_node(:no_exist, "a")
      {:error, :no_such_ring}
  """
  @spec add_node(ring, key) :: :ok | {:error, :no_such_ring}
  def add_node(ring, node) do
    validate_node_key!(node)
    HashRing.Worker.add_node(ring, node)
  end

  @doc """
  Same as `add_node/2`, but takes a weight value.

  The weight controls the relative presence this node will have on the ring,
  the default is `128`, but it's best to give each node a weight value which maps
  to a concrete resource such as memory or priority. It's not ideal to have a number
  which is too high, as it will make the ring data structure larger, but a good value
  is probably in the range of 64-256.

  ## Examples

      iex> {:ok, _pid} = HashRing.Managed.new(:test5)
      ...> HashRing.Managed.add_node(:test5, "a", 64)
      ...> HashRing.Managed.key_to_node(:test5, :foo)
      "a"

      iex> HashRing.Managed.add_node(:no_exist, "a")
      {:error, :no_such_ring}

  """
  @spec add_node(ring, key, weight) ::
          :ok
          | {:error, :no_such_ring}
          | {:error, {:invalid_weight, key, term}}
  def add_node(ring, node, weight)
      when is_integer(weight) and weight > 0 do
    validate_node_key!(node)
    HashRing.Worker.add_node(ring, node, weight)
  end

  def add_node(_ring, node, weight) do
    {:error, {:invalid_weight, node, weight}}
  end

  @doc """
  Adds a list of nodes to the ring.

  The list of nodes can contain either node names or `{node_name, weight}`
  tuples. If there is an error with any of the node weights, an error will
  be returned, and the ring will remain unchanged.

  Two-tuples are always interpreted as weighted entries here, including when
  their weights are invalid. To use a two-tuple as a node key, wrap it in an
  explicitly weighted entry, such as `{{:region, :node}, 128}`. Other bare terms
  are accepted as node keys. Empty binary keys raise `ArgumentError` before mutation.

  ## Examples

      iex> {:ok, _pid} = HashRing.Managed.new(:test6)
      ...> :ok = HashRing.Managed.add_nodes(:test6, ["a", {"b", 64}])
      ...> HashRing.Managed.key_to_node(:test6, :foo)
      "a"

      iex> {:ok, _pid} = HashRing.Managed.new(:test7)
      ...> HashRing.Managed.add_nodes(:test7, ["a", {"b", :wrong}])
      {:error, [{:invalid_weight, "b", :wrong}]}

  """
  @spec add_nodes(ring, node_list) ::
          :ok
          | {:error, :no_such_ring}
          | {:error, [{:invalid_weight, key, term}]}
  def add_nodes(ring, nodes) when is_list(nodes) do
    invalid = node_entry_errors(nodes)
    if :empty_node in invalid, do: raise(ArgumentError, @empty_node_message)

    case invalid do
      [] ->
        HashRing.Worker.add_nodes(ring, nodes)

      _ ->
        {:error, invalid}
    end
  end

  @doc """
  Removes a node from the given hash ring.

  An error is returned if the ring does not exist.

  ## Examples

      iex> {:ok, _pid} = HashRing.Managed.new(:test8)
      ...> :ok = HashRing.Managed.add_nodes(:test8, ["a", {"b", 64}])
      ...> :ok = HashRing.Managed.remove_node(:test8, "b")
      ...> HashRing.Managed.key_to_node(:test8, :foo)
      "a"

  """
  @spec remove_node(ring, key) :: :ok | {:error, :no_such_ring}
  def remove_node(ring, node) do
    HashRing.Worker.remove_node(ring, node)
  end

  @doc """
  Maps a key to a node on the hash ring.

  An error is returned if the ring does not exist.
  """
  @spec key_to_node(ring, any()) ::
          key
          | {:error, :no_such_ring}
          | {:error, {:invalid_ring, :no_nodes}}
  def key_to_node(ring, key) do
    HashRing.Worker.key_to_node(ring, key)
  end

  @doc """
  Maps a key to a set of nodes on the hash ring.

  An error is returned if the ring does not exist.
  """
  @spec key_to_nodes(ring, any(), pos_integer) ::
          [key]
          | {:error, :no_such_ring}
          | {:error, {:invalid_ring, :no_nodes}}
  def key_to_nodes(ring, key, count) do
    HashRing.Worker.key_to_nodes(ring, key, count)
  end
end
