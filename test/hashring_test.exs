defmodule HashRingTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  doctest HashRing

  test "binary names without a length are rejected" do
    assert_raise ArgumentError, fn ->
      HashRing.new("")
    end
  end

  test "key_to_nodes/3 uses node length if the count is greater than node length" do
    nodes =
      HashRing.new()
      |> HashRing.add_node("foo")
      |> HashRing.add_node("bar")
      |> HashRing.key_to_nodes(123, 150)

    assert length(nodes) == 2
  end

  property "adding one node leaves us with a tree with one node" do
    check all(name <- string(:printable, min_length: 1)) do
      %HashRing{nodes: nodes} = HashRing.new(name)
      assert length(nodes) == 1
    end
  end

  property "adding one node with a weight works" do
    check all({name, weight} <- tuple({string(:printable, min_length: 1), positive_integer()})) do
      %HashRing{nodes: nodes} = HashRing.new(name, weight)
      assert length(nodes) == 1
    end
  end

  property "adding one node and removing it leaves us with an empty ring" do
    check all(name <- string(:printable, min_length: 1)) do
      ring = HashRing.new(name)
      %HashRing{nodes: nodes} = HashRing.remove_node(ring, name)
      assert length(nodes) == 0
    end
  end

  property "distribution of keys is uniformly distributed" do
    check all(ring <- hash_ring()) do
      tab = :ets.new(:ring, [:set, keypos: 1])

      for i <- 1..10_000 do
        :ets.insert(tab, {i, HashRing.key_to_node(ring, i)})
      end

      groups =
        :ets.tab2list(tab)
        |> Enum.group_by(fn {_, n} -> n end, fn {k, _} -> k end)

      distribution =
        groups
        |> Enum.map(fn {_node, values} -> length(values) end)

      # If the standard deviation is within .05 percent of the sample size,
      # that's good enough - we're not looking for perfectly uniform distribution
      deviation = (10_000 - std_dev(distribution)) / 10_000
      assert deviation >= 0.95
    end
  end

  property "distribution of keys is uniformly distributed when retrieving multiples" do
    check all(ring <- hash_ring()) do
      tab = :ets.new(:ring, [:set, keypos: 1])

      for i <- 1..10_000 do
        :ets.insert(tab, {i, HashRing.key_to_nodes(ring, i, 10)})
      end

      results = :ets.tab2list(tab)

      groups =
        Enum.reduce(results, %{}, fn {key, vals}, acc ->
          Enum.reduce(vals, acc, fn val, acc2 ->
            Map.update(acc2, val, [key], &[key | &1])
          end)
        end)

      distribution =
        groups
        |> Enum.map(fn {_node, values} -> length(values) end)

      # If the standard deviation is within .05 percent of the sample size,
      # that's good enough - we're not looking for perfectly uniform distribution
      deviation = (10_000 - std_dev(distribution)) / 10_000
      assert deviation >= 0.95
    end
  end

  defp std_dev(elements) do
    average = Enum.sum(elements) / length(elements)
    variance = Enum.reduce(elements, 0.0, fn x, s -> s + (x - average) * (x - average) end)
    variance = variance / length(elements)
    :math.sqrt(variance)
  end

  def hash_ring() do
    sized(fn size -> sized_hash_ring(size) end)
  end

  defp sized_hash_ring(i) do
    bind(constant(HashRing.new()), fn ring ->
      constant(Enum.reduce(0..(i + 1), ring, fn n, r -> HashRing.add_node(r, n) end))
    end)
  end
end
