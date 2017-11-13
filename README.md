# libring - A fast consistent hash ring for Elixir

[![Hex.pm Version](http://img.shields.io/hexpm/v/libring.svg?style=flat)](https://hex.pm/packages/libring)

This library implements a stateful consistent hash ring. It's extremely fast
(in benchmarks it's faster than all other implementations I've tested against,
namely [voicelayer/hash-ring](https://github.com/voicelayer/hash-ring) and 
[sile/hash_ring](https://github.com/sile/hash_ring)), it has no external dependencies, 
and is written in Elixir.

The algorithm is based on [libketama](https://github.com/rj/ketama). Nodes on the
ring are broken into shards and each one is assigned an integer value in the keyspace, which
is the set of integers from 1 to 2^32-1. The distribution of these shards is random, but
deterministic.

Keys are then mapped to a shard by converting the key to a binary, hashing it with SHA-256, 
converting the hash to an integer in the keyspace, then finding the shard which is assigned
the next highest value, if there is no next highest value, the lowest integer is used, which
is how the "ring" is formed.

This implementation uses a general balanced tree, via Erlang's `:gb_tree` module. Each shard
is inserted into the tree, and we use this data structure to efficiently lookup next-highest
key and smallest key. I suspect this is why `libring` is faster than other implementations I've
benchmarked against.

## Usage

Add `:libring` to your deps, and run `mix deps.get`.

```elixir
def deps do
  [{:libring, "~> 1.0"}]
end
```

You have two choices for managing hash rings in your application:

## HashRing

This API works with the raw ring datastructure. It is the fastest implementation,
and is best suited for when you have a single process which will need to access the
ring, and which can hold the ring in it's internal state.

```elixir
ring = HashRing.new()
       |> HashRing.add_node("a")
       |> HashRing.add_node("b")

"a" = HashRing.key_to_node(ring, {:myworker, 123})
```

You can also specify the weight of each node, and add nodes in bulk:

```elixir
ring = HashRing.new()
       |> HashRing.add_nodes(["a", {"b", 64}])
       |> HashRing.add_node("c", 200)
"c" = HashRing.key_to_node(ring, {:myworker, 123})
```

**NOTE**: Node names do not have to be strings, they can be atoms, tuples, etc.

## HashRing.Managed

This API works with rings which are held in the internal state of a GenServer process.
It supports the same API as `HashRing`. Because of this, there is a performance overhead
due to the messaging, and the GenServer can be a potential bottleneck. If this is the case
you are better off exploring ways to use the raw `HashRing` API. However this API is best suited
for situations where you have multiple processes accessing the ring, or need to maintain multiple
rings.

**NOTE**: You must have the `:libring` application started to use this API.

```elixir
{:ok, pid} = HashRing.Managed.new(:myring)
:ok = HashRing.Managed.add_node(:myring, "a")
:ok = HashRing.Managed.add_node(:myring, "b", 64)
:ok = HashRing.Managed.add_node(:myring, "c", 200)
"c" = HashRing.Managed.key_to_node(:myring, {:myworker, 123})
```

You can configure managed rings in `config.exs`, and they will be created and initialized
when the `:libring` application starts. Configured rings take two shapes, static and dynamic
rings. Static rings are simply those where the nodes are provided up front, although you can
always add/remove nodes manually at runtime; dynamic rings have Erlang node monitoring enabled,
and add or remove nodes on the ring based on cluster membership.

You can whitelist/blacklist nodes when using dynamic rings, so that only those nodes which you
actually want to distribute work to are used in calculations. This configuration is shown below as well.

If you provide a whitelist, the blacklist will have no effect, and only nodes matching the whitelist
will be added. If you do not provide a whitelist, the blacklist will be used to filter nodes. If you
do not provide either, a default blacklist containing the `~r/^remsh.*$/` pattern from the example below,
which is a good default to prevent remote shell sessions (at least those done via releases) from causing 
the ring to change.

The whitelist and blacklist only have an effect when `monitor_nodes: true`.

## Configuration

Below is an example configuration:

```elixir
config :libring,
  rings: [
    # A ring which automatically changes based on Erlang cluster membership,
    # but does not allow nodes named "a" or "remsh*" to be added to the ring
    ring_a: [monitor_nodes: true,
             node_blacklist: ["a", ~r/^remsh.*$/]],
    # A ring which is composed of three nodes, of which "c" has a non-default weight of 200
    # The default weight is 128
    ring_b: [nodes: ["a", "b", {"c", 200}]]
  ]
```

## Contributing

To run the test suite you will need to run `mix eqc.install --mini` once you've cloned the repo and fetched dependencies.

If you have changes in mind that are significant or potentially time consuming, please open a RFC-style PR first, where we
can discuss your plans first. I don't want you to spend all your time crafting a PR that I ultimately reject because I don't
think it's a good fit or is too large for me to review. Not that I plan to reject PRs in general, but I have to be careful to
balance features with maintenance burden, or I will quickly be unable to manage the project.

Please ensure that you adhere to a commit style where logically related changes are in a single commit, or broken up in a way that
eases review if necessary. Keep commit subject lines informative, but short, and provide additional detail in the extended message text
if needed. If you can, mention relevant issue numbers in either the subject or the extended message.

## License

MIT

Please see the `LICENSE` file for more info.
