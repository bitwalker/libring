defmodule HashRing.Managed do
  @moduledoc """
  This module defines the API for working with hash rings where the ring state is managed
  in a GenServer process.

  There is a performance penalty with working with the ring this way, but it is the best approach
  if you need to share the ring across multiple processes, or need to maintain multiple rings.

  If your rings map 1:1 with Erlang node membership, you can configure rings to automatically
  monitor node up/down events and update the hash ring accordingly, with a default weight,
  and either whitelist or blacklist nodes from the ring. You configure this at the ring level in your `config.exs`

  Each ring is configured in `config.exs`, and can contain a list of nodes to seed the ring with,
  and you can then dynamically add/remove nodes to the ring using the API here. Each node on the ring can
  be configured with a weight, which affects the amount of the total keyspace it owns. The default weight
  is `128`. It's best to base the weight of nodes on some concrete relative value, such as the amount of
  memory a node has.
  """

  @type ring         :: atom()
  @type key          :: any()
  @type weight       :: pos_integer
  @type node_list    :: [node() | {node(), weight}]
  @type pattern_list :: [String.t | Regex.t]
  @type ring_options :: [
    nodes: node_list,
    monitor_nodes: boolean,
    node_blacklist: pattern_list,
    node_whitelist: pattern_list]

  @valid_ring_opts [:name, :nodes, :monitor_nodes, :node_blacklist, :node_whitelist]

  @doc """
  Creates a new stateful hash ring with the given name.
  This name is how you will refer to the hash ring via other API calls.

  It takes an optional set of options which control how the ring behaves.
  Valid options are as follows:

  - `monitor_nodes: boolean`: will automatically monitor Erlang node membership,
    if new nodes are connected or nodes are disconnected, the ring will be updated automatically.
    In this configuration, nodes cannot be added or removed via the API. Those requests will be ignored.
  - `node_blacklist: [String.t | Regex.t]`: Used in conjunction with `monitor_nodes: true`, this
    is a list of patterns, either as literal strings, or as regex patterns (in either string or literal form),
    and will be used to ignore nodeup/down events for nodes which are blacklisted. If a node whitelist
    is provided, the blacklist has no effect.
  - `node_whitelist: [String.t | Regex.t]`: The same as `node_blacklist`, except the opposite; only nodes
    which match a pattern in the whitelist will result in the ring being updated.

  An error is returned if the ring already exists or if bad ring options are provided.

  ## Examples

      iex> {:ok, _pid} = HashRing.Managed.new(:test1, [nodes: ["a", {"b", 64}]])
      ...> HashRing.Managed.key_to_node(:test1, :foo)
      "b"

      iex> {:ok, pid} = HashRing.Managed.new(:test2)
      ...> {:error, {:already_started, existing_pid}} = HashRing.Managed.new(:test2)
      ...> pid == existing_pid
      true
      iex> HashRing.Managed.new(:test3, [nodes: "a"])
      ** (ArgumentError) {:nodes, "a"} is an invalid option for `HashRing.Managed.new/2`
  """
  @spec new(ring) :: {:ok, pid} | {:error, {:already_started, pid}}
  @spec new(ring, ring_options) :: {:ok, pid} | {:error, {:already_started, pid}} | {:error, {:invalid_option, term}}
  def new(name, ring_options \\ []) when is_list(ring_options) do
    opts = [{:name, name}|ring_options]
    invalid = Enum.find(opts, fn
      {key, value} when key in @valid_ring_opts ->
        case key do
          :name when is_atom(value) -> false
          :nodes when is_list(value) -> Keyword.keyword?(value)
          :monitor_nodes when is_boolean(value) -> false
          :node_blacklist when is_list(value) -> false
          :node_whitelist when is_list(value) -> false
          _ -> true
        end
    end)
    case invalid do
      nil ->
        case Process.whereis(:"libring_#{name}") do
          nil ->
            Supervisor.start_child(HashRing.Supervisor, [opts])
          pid ->
            {:error, {:already_started, pid}}
        end
      _ ->
        raise ArgumentError, message: "#{inspect invalid} is an invalid option for `HashRing.Managed.new/2`"
    end
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
  def add_node(ring, node) when is_atom(ring) do
    HashRing.Worker.add_node(ring, node)
  end

  @doc """
  Same as `add_node/2`, but takes a weight value.

  The weight controls the relative presence this node will have on the ring,
  the default is 128, but it's best to give each node a weight value which maps
  to a concrete resource such as memory or priority. It's not ideal to have a number
  which is too high, as it will make the ring datastructure larger, but a good value
  is probably in the range of 64-256.

  ## Examples

      iex> {:ok, _pid} = HashRing.Managed.new(:test5)
      ...> HashRing.Managed.add_node(:test5, "a", 64)
      ...> HashRing.Managed.key_to_node(:test5, :foo)
      "a"

      iex> HashRing.Managed.add_node(:no_exist, "a")
      {:error, :no_such_ring}
  """
  @spec add_node(ring, key, weight) :: :ok |
    {:error, :no_such_ring} |
    {:error, {:invalid_weight, key, term}}
  def add_node(ring, node, weight) when is_atom(ring)
    and is_integer(weight)
    and weight > 0 do
    HashRing.Worker.add_node(ring, node, weight)
  end
  def add_node(ring, node, weight) when is_atom(ring) do
    {:error, {:invalid_weight, node, weight}}
  end

  @doc """
  Adds a list of nodes to the ring.

  The list of nodes can contain either node names or `{node_name, weight}`
  tuples. If there is an error with any of the node weights, an error will
  be returned, and the ring will remain unchanged.

  ## Examples

      iex> {:ok, _pid} = HashRing.Managed.new(:test6)
      ...> :ok = HashRing.Managed.add_nodes(:test6, ["a", {"b", 64}])
      ...> HashRing.Managed.key_to_node(:test6, :foo)
      "b"

      iex> {:ok, _pid} = HashRing.Managed.new(:test7)
      ...> HashRing.Managed.add_nodes(:test7, ["a", {"b", :wrong}])
      {:error, [{:invalid_weight, "b", :wrong}]}
  """
  @spec add_nodes(ring, node_list) :: :ok |
    {:error, :no_such_ring} |
    {:error, [{:invalid_weight, key, term}]}
  def add_nodes(ring, nodes) when is_list(nodes) do
      invalid = Enum.filter(nodes, fn
        {_node, weight} when is_integer(weight) and weight > 0 ->
          false
        {_node, _weight} ->
          true
        node when is_binary(node) or is_atom(node) ->
          false
        _node ->
          true
      end)
      case invalid do
        [] ->
          HashRing.Worker.add_nodes(ring, nodes)
        _ ->
          {:error, Enum.map(invalid, fn {k,v} -> {:invalid_weight, k, v} end)}
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
  def remove_node(ring, node) when is_atom(ring) do
    HashRing.Worker.remove_node(ring, node)
  end

  @doc """
  Maps a key to a node on the hash ring.

  An error is returned if the ring does not exist.
  """
  @spec key_to_node(ring, any()) :: key |
    {:error, :no_such_ring} |
    {:error, {:invalid_ring, :no_nodes}}
  def key_to_node(ring, key) when is_atom(ring) do
    HashRing.Worker.key_to_node(ring, key)
  end
end
