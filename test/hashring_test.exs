defmodule HashRingTest do
  use ExUnit.Case, async: true
  use EQC.ExUnit
  doctest HashRing
  use EQC.ExUnit

  def string, do: utf8()

  test "binary names without a length are rejected" do
    assert_raise ArgumentError, fn ->
      HashRing.new("")
    end
  end

  property "adding one node leaves us with a tree with one node" do
    forall name <- string() do
      implies String.length(name) > 0 do
        %HashRing{nodes: nodes} = HashRing.new(name)
        ensure length(nodes) == 1
      end
    end
  end

  property "adding one node with a weight works" do
    forall {name, weight} <- {string(), int()} do
      implies weight > 0 and String.length(name) > 0 do
        %HashRing{nodes: nodes} = HashRing.new(name)
        ensure length(nodes) == 1
      end
    end
  end

  property "adding one node and removing it leaves us with an empty ring" do
    forall name <- string() do
      implies String.length(name) > 0 do
        ring = HashRing.new(name)
        %HashRing{nodes: nodes} = HashRing.remove_node(ring, name)
        ensure length(nodes) == 0
      end
    end
  end


  property "distribution of keys is uniformly distributed" do
    forall ring <- hash_ring() do
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
      deviation >= 0.95
    end
  end

  defp std_dev(elements) do
    average = Enum.sum(elements) / length(elements)
    variance = Enum.reduce(elements, 0.0, fn x, s -> s + (x - average) * (x - average) end)
    variance = variance / length(elements)
    :math.sqrt(variance)
  end

  def hash_ring() do
    sized s, do: sized_hash_ring(s, HashRing.new)
  end
  defp sized_hash_ring(i, r) do
    Enum.reduce(0..(i+1), r, fn n, r -> HashRing.add_node(r, n) end)
  end
end
