defmodule HashRingTest do
  use ExUnit.Case, async: true
  doctest HashRing
  use EQC.ExUnit

  def string, do: utf8()


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

end
