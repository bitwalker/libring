defmodule HashRing do
  @moduledoc """
  This module defines an API for creating/manipulating a hash ring.
  The internal datastructure for the hash ring is actually a gb_tree, which provides
  fast lookups for a given key on the ring.

  - The ring is a continuum of 2^32 "points", or integer values
  - Nodes are sharded into 128 points, and distributed across the ring
  - Each shard owns the keyspace below it
  - Keys are hashed and assigned a point on the ring, the node for a given
    ring is determined by finding the next highest point on the ring for a shard,
    the node that shard belongs to is then the node which owns that key.
  - If a key's hash does not have any shards above it, it belongs to the first shard,
    this mechanism is what creates the ring-like topology.
  - When nodes are added/removed from the ring, only a small subset of keys must be reassigned
  """
  defstruct ring: :gb_trees.empty, nodes: []

  @type t :: %__MODULE__{
    ring: :gb_trees.tree,
    nodes: [term()]
  }

  @hash_range trunc(:math.pow(2, 32) - 1)


  @doc """
  Creates a new hash ring structure, with no nodes added yet

  ## Examples

      iex> ring = HashRing.new()
      ...> %HashRing{nodes: ["a"]} = ring = HashRing.add_node(ring, "a")
      ...> HashRing.key_to_node(ring, {:complex, "key"})
      "a"
  """
  @spec new() :: __MODULE__.t
  def new(), do: %__MODULE__{}

  @doc """
  Creates a new hash ring structure, seeded with the given node,
  with an optional weight provided which determines the number of
  virtual nodes (shards) that will be assigned to it on the ring.

  The default weight for a node is 128

  ## Examples

      iex> ring = HashRing.new("a")
      ...> %HashRing{nodes: ["a"]} = ring
      ...> HashRing.key_to_node(ring, :foo)
      "a"

      iex> ring = HashRing.new("a", 200)
      ...> %HashRing{nodes: ["a"]} = ring
      ...> HashRing.key_to_node(ring, :foo)
      "a"
  """
  @spec new(node(), pos_integer) :: __MODULE__.t
  def new(node, weight \\ 128) when is_integer(weight) and weight > 0,
    do: add_node(new(), node, weight)

  @doc """
  Returns the list of nodes which are present on the ring.

  The type of the elements in this list are the same as the type of the elements
  you initially added to the ring. In the following example, we used strings, but
  if you were using atoms, such as those used for Erlang node names, you would get
  a list of atoms back.

      iex> ring = HashRing.new |> HashRing.add_nodes(["a", "b"])
      ...> HashRing.nodes(ring)
      ["b", "a"]
  """
  @spec nodes(t) :: [term]
  def nodes(%__MODULE__{nodes: nodes}), do: nodes

  @doc """
  Adds a node to the hash ring, with an optional weight provided which
  determines the number of virtual nodes (shards) that will be assigned to
  it on the ring.

  The default weight for a node is 128

  ## Examples

      iex> ring = HashRing.new()
      ...> ring = HashRing.add_node(ring, "a")
      ...> %HashRing{nodes: ["b", "a"]} = ring = HashRing.add_node(ring, "b", 64)
      ...> HashRing.key_to_node(ring, :foo)
      "b"
  """
  @spec add_node(__MODULE__.t, term(), pos_integer) :: __MODULE__.t
  def add_node(ring, node, weight \\ 128)
  def add_node(_, node, _weight) when is_binary(node) and byte_size(node) == 0,
    do: raise ArgumentError, message: "Node keys cannot be empty strings"
  def add_node(%__MODULE__{} = ring, node, weight) when is_integer(weight) and weight > 0 do
    cond do
      Enum.member?(ring.nodes, node) ->
        ring
      :else ->
        ring = %{ring | nodes: [node|ring.nodes]}
        Enum.reduce(1..weight, ring, fn i, %__MODULE__{ring: r} = acc ->
          n = :erlang.phash2({node, i}, @hash_range)
          try do
            %{acc | ring: :gb_trees.insert(n, node, r)}
          catch
            :error, {:key_exists, _} ->
              acc
          end
        end)
    end
  end

  @doc """
  Adds a list of nodes to the hash ring. The list can contain just the node key, or
  a tuple of the node key and it's desired weight.

  See also the documentation for `add_node/3`.

  ## Examples

      iex> ring = HashRing.new()
      ...> ring = HashRing.add_nodes(ring, ["a", {"b", 64}])
      ...> %HashRing{nodes: ["b", "a"]} = ring
      ...> HashRing.key_to_node(ring, :foo)
      "b"
  """
  @spec add_nodes(__MODULE__.t, [term() | {term(), pos_integer}]) :: __MODULE__.t
  def add_nodes(%__MODULE__{} = ring, nodes) when is_list(nodes) do
    Enum.reduce(nodes, ring, fn
      {node, weight}, acc when is_integer(weight) and weight > 0 ->
        add_node(acc, node, weight)
      node, acc ->
        add_node(acc, node)
    end)
  end

  @doc """
  Removes a node from the hash ring.

  ## Examples

      iex> ring = HashRing.new()
      ...> %HashRing{nodes: ["a"]} = ring = HashRing.add_node(ring, "a")
      ...> %HashRing{nodes: []} = ring = HashRing.remove_node(ring, "a")
      ...> HashRing.key_to_node(ring, :foo)
      {:error, {:invalid_ring, :no_nodes}}
  """
  @spec remove_node(__MODULE__.t, node()) :: __MODULE__.t
  def remove_node(%__MODULE__{ring: r} = ring, node) do
    cond do
      Enum.member?(ring.nodes, node) ->
        r2 = :gb_trees.to_list(r)
        |> Enum.filter(fn {_key, ^node} -> false; _ -> true end)
        |> :gb_trees.from_orddict()
        %{ring | nodes: ring.nodes -- [node], ring: r2}
      :else ->
        ring
    end
  end

  @doc """
  Determines which node owns the given key.
  This function assumes that the ring has been populated with at least one node.

  ## Examples

      iex> ring = HashRing.new("a")
      ...> HashRing.key_to_node(ring, :foo)
      "a"

      iex> ring = HashRing.new()
      ...> HashRing.key_to_node(ring, :foo)
      {:error, {:invalid_ring, :no_nodes}}
  """
  @spec key_to_node(__MODULE__.t, term) :: node() | {:error, {:invalid_ring, :no_nodes}}
  def key_to_node(%__MODULE__{nodes: []}, _key),
    do: {:error, {:invalid_ring, :no_nodes}}
  def key_to_node(%__MODULE__{ring: r}, key) do
    hash = :erlang.phash2(key, @hash_range)
    case :gb_trees.iterator_from(hash, r) do
      [{_key, node, _, _}|_] ->
        node
      _ ->
        {_key, node} = :gb_trees.smallest(r)
        node
    end
  end

  @doc """
  Determines which nodes owns a given key. Will return either `count` results or
  the number of nodes, depending on which is smaller.
  This function assumes that the ring has been populated with at least one node.

  ## Examples

  iex> ring = HashRing.new()
  ...> ring = HashRing.add_node(ring, "a")
  ...> ring = HashRing.add_node(ring, "b")
  ...> ring = HashRing.add_node(ring, "c")
  ...> HashRing.key_to_nodes(ring, :foo, 2)
  ["b", "c"]

  iex> ring = HashRing.new()
  ...> HashRing.key_to_nodes(ring, :foo, 1)
  {:error, {:invalid_ring, :no_nodes}}
  """
  @spec key_to_nodes(__MODULE__.t, term, pos_integer) :: [node()] | {:error, {:invalid_ring, :no_nodes}}
  def key_to_nodes(%__MODULE__{nodes: []}, _key, _count),
    do: {:error, {:invalid_ring, :no_nodes}}
  def key_to_nodes(%__MODULE__{nodes: nodes, ring: r}, key, count) do
    hash = :erlang.phash2(key, @hash_range)
    count = min(length(nodes), count)
    case :gb_trees.iterator_from(hash, r) do
      [{_key, node, _, _} | _] = iter ->
        find_nodes_from_iter(iter, count - 1, [node])
      _ ->
        {_key, node} = :gb_trees.smallest(r)
        [node]
    end
  end

  defp find_nodes_from_iter(_iter, 0, results), do: Enum.reverse(results)
  defp find_nodes_from_iter(iter, count, results) do
    case :gb_trees.next(iter) do
      {_key, node, iter} ->
        if node in results do
          find_nodes_from_iter(iter, count, results)
        else
          [node | results]
          find_nodes_from_iter(iter, count - 1, [node | results])
        end
      _ ->
        results
    end
  end
end

defimpl Inspect, for: HashRing do
  def inspect(%HashRing{ring: ring}, _opts) do
    nodes = Enum.uniq(Enum.map(:gb_trees.to_list(ring), fn {_, n} -> n end))
    "#<Ring#{Kernel.inspect nodes}>"
  end
end
