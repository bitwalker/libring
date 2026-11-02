# libring - A fast consistent hash ring for Elixir

[![Module Version](https://img.shields.io/hexpm/v/libring.svg)](https://hex.pm/packages/libring)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/libring/)
[![Total Download](https://img.shields.io/hexpm/dt/libring.svg)](https://hex.pm/packages/libring)
[![License](https://img.shields.io/hexpm/l/libring.svg)](https://github.com/bitwalker/libring/blob/main/LICENSE.md)
[![Last Updated](https://img.shields.io/github/last-commit/bitwalker/libring.svg)](https://github.com/bitwalker/libring/commits/main)

This library implements a consistent hash ring in Elixir, with no external runtime
dependencies. Historical benchmarks compared it favorably with
[voicelayer/hash-ring](https://github.com/voicelayer/hash-ring) and
[sile/hash_ring](https://github.com/sile/hash_ring); use `bench/ring.exs` to assess
performance for your own workload and runtime.

Like [libketama](https://github.com/rj/ketama), the ring distributes virtual nodes
(shards) through a keyspace. Shard positions use `:erlang.phash2/2` with range
`2^32 - 1`, producing values from `0` through `2^32 - 2`. Placement is deterministic.

Lookup uses the same hash range. Atom keys are first serialized with
`:erlang.term_to_binary/1`; other terms are hashed directly. The owner is the node
at the first shard at or above the key's hash, wrapping to the smallest shard when
necessary. Shards are stored in Erlang's balanced `:gb_trees` structure.

## Usage

Add `:libring` to your deps, and run `mix deps.get`.

```elixir
def deps do
  [
    {:libring, "~> 1.0"}
  ]
end
```

You have two choices for managing hash rings in your application:

### `HashRing`

This API works with the raw ring data structure. It is the fastest implementation,
and is best suited for when you have a single process which will need to access the
ring, and which can hold the ring in its internal state.

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

`HashRing.key_to_nodes(ring, key, count)` returns distinct owners in clockwise
order, starting with the same primary owner as `key_to_node/2`. For a populated
ring, the result contains the smaller of `count` and the number of nodes. Both
lookups return `{:error, {:invalid_ring, :no_nodes}}` for an empty ring. Counts must
be positive integers.

### `HashRing.Managed`

Managed rings keep their data in an ETS table owned by a GenServer. Writes go
through that server; reads using a ring name access ETS directly, while reads
using a PID go through the server. This supports shared access and multiple named
rings. The raw API avoids shared-process and table overhead when a caller can
keep the ring itself.

Dynamic creation through `new/2` requires the `:libring` application to be started.

```elixir
{:ok, pid} = HashRing.Managed.new(:myring)
:ok = HashRing.Managed.add_node(:myring, "a")
:ok = HashRing.Managed.add_node(:myring, "b", 64)
:ok = HashRing.Managed.add_node(:myring, "c", 200)
"c" = HashRing.Managed.key_to_node(:myring, {:myworker, 123})
```

`new/2` creates a worker under libring's dynamic supervisor. To give your own
supervisor ownership of restart and shutdown, use a child specification instead:

```elixir
children = [
  {HashRing.Managed, name: :myring, nodes: ["a", {"b", 64}]}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

The child specification defaults to name/id `:hash_ring_manager` and supports
normal supervisor overrides such as `:id`, `:restart`, and `:shutdown`. This linked
startup route does not depend on libring's global dynamic supervisor. Startup
options must be keyword lists; invalid options raise `ArgumentError` before a
worker is started. A duplicate dynamically created name returns
`{:error, {:already_started, pid}}`.

Managed bulk/configured node lists interpret every two-tuple as a weighted entry.
Invalid weights return an error for bulk addition without changing membership.
For a tuple node key, use an explicitly weighted entry such as
`{{:region, :node}, 128}`. Other unambiguous terms are accepted directly. Empty
binary node keys are rejected with `ArgumentError` before mutation.

You can configure managed rings in `config.exs`, and they will be created and initialized
when the `:libring` application starts. Configured rings take two shapes, static and dynamic
rings. Static rings are simply those where the nodes are provided up front, although you can
always add/remove nodes manually at runtime; dynamic rings have Erlang node monitoring enabled,
and add or remove nodes on the ring based on cluster membership. On monitored
rings, valid manual add/remove requests return `:ok` without changing membership;
the `nodes` option seeds only static rings.

`node_type` selects remote peers (`:visible`, `:hidden`, or `:all`) consistently
at startup and afterward. The local node is also included unless filtered out.
Monitoring reflects Erlang connectivity, which does not guarantee that a peer's
applications or services are ready to receive work. Applications needing readiness
admission can maintain a static ring and add/remove nodes after their own checks.

You can whitelist/blacklist nodes when using dynamic rings, so that only those nodes which you
actually want to distribute work to are used in calculations. This configuration is shown below as well.

If you provide a whitelist, the blacklist will have no effect, and only nodes matching the whitelist
will be added. If you do not provide a whitelist, the blacklist will be used to filter nodes. If you
do not provide either, the default blacklist excludes `~r/^remsh.*$/` and
`~r/^rem-.*$/` to keep common remote-shell node names from changing the ring.

The whitelist and blacklist only have an effect when `monitor_nodes: true`.

## Configuration

Below is an example configuration:

```elixir
config :libring,
  rings: [
    # A ring which automatically changes based on Erlang cluster membership,
    # but does not allow nodes named "a" or "remsh*" to be added to the ring
    ring_a: [monitor_nodes: true,
             node_type: :visible,
             node_blacklist: ["a", ~r/^remsh.*$/, ~r/^rem-.*$/]],
    # A ring which is composed of three nodes, of which "c" has a non-default weight of 200
    # The default weight is 128
    ring_b: [nodes: ["a", "b", {"c", 200}]]
  ]
```

## Contributing

If you have changes in mind that are significant or potentially time-consuming, please open an RFC-style PR first, where we
can discuss your plans first. I don't want you to spend all your time crafting a PR that I ultimately reject because I don't
think it's a good fit or is too large for me to review. Not that I plan to reject PRs in general, but I have to be careful to
balance features with maintenance burden, or I will quickly be unable to manage the project.

Please ensure that you adhere to a commit style where logically related changes are in a single commit, or broken up in a way that
eases review if necessary. Keep commit subject lines informative, but short, and provide additional detail in the extended message text
if needed. If you can, mention relevant issue numbers in either the subject or the extended message.

### CI and local checks

Consumer compatibility remains Elixir 1.11 and later. CI checks the exact minimum,
Elixir 1.11.0 / OTP 23.1.1, in a pinned container with a dependency-free smoke suite.
Development tools have a newer minimum; the full suite runs on Elixir 1.17.3 /
OTP 27.3.4.19 and Elixir 1.20.5 / OTP 29.1.2. Use `mise` to install and select
alternate local runtimes without changing your global defaults, for example:

```sh
mise exec erlang@29.1.2 elixir@1.20.5 -- mix test
```

On the current development pair, run:

```sh
mix local.hex 2.6.0 --force
mix deps.get --check-locked
mix format --check-formatted
MIX_ENV=test mix deps.compile
MIX_ENV=test mix compile --warnings-as-errors
mix test
mix dialyzer
MIX_ENV=docs mix deps.get --only docs --check-locked
mix docs --warnings-as-errors
mix deps.unlock --check-unused
```

Normal verification uses the checked-in dependency lock; dependency updates should
be deliberate changes. CI restores caches for the exact runtime/environment and
saves them only after successful default-branch pushes. Dialyzer's PLTs live in
`_build/plts`, separate from global developer state.

Workflow checks use actionlint 1.7.12, zizmor 1.31.1, and gh-actions-lock v0.4.0:

```sh
actionlint -color
zizmor .github
gh actions-lock --verify-local
gh actions-lock --verify
```

Install the GitHub CLI extension with
`gh extension install github/gh-actions-lock --pin v0.4.0` (upgrade an existing
installation to that version if necessary). Online lock verification needs an
authenticated `gh`; the offline check verifies coverage, not provenance.

Actions are SHA-pinned, with release comments for review, and native
`.github/workflows/actions.lock` also locks their transitive dependencies. After
changing a workflow's action versions, run `gh actions-lock --no-narrow`, then
review the workflow and lockfile diffs and rerun both analyzers. The `--no-narrow`
option preserves SHA references rather than rewriting them to tags. No zizmor
pinning exceptions are needed. Never automate `--accept-moved`; investigate
unexpected upstream changes. Container images and shell-installed tools are
pinned separately because the action lock does not cover them.

Dependabot groups weekly action and Hex dependency updates with a seven-day
cooldown. When updating shell-installed tools or the legacy container/Hex archive,
update their versions and verified checksums/digests together. The legacy job
checks out on a modern host and runs with read-only source and no container
network access; it does not share the modern toolchain cache.

### Releases

Record user-visible changes under Unreleased in [CHANGELOG.md](CHANGELOG.md),
including routing or lifecycle compatibility notes. Before publishing, select the
new version, update `mix.exs`, and move those notes into its release section.
Use `jj` to create a matching release tag without a `v` prefix, and ensure the
reviewed release commit and tag are available on GitHub before publishing docs.

Local development docs link to `main`. Set `DOCS_SOURCE_REF` to the release tag
when building release documentation; CI supplies its tested commit SHA. Review
the generated source links, run `mix hex.build`, and inspect the package contents
before publishing. Builds and checks do not publish a release. The Hex package
includes the changelog and library sources, excluding local task documents.

## Copyright and License

Copyright (c) 2016 Paul Schoenfelder

This library is MIT licensed. See the
[LICENSE](https://github.com/bitwalker/libring/blob/main/LICENSE.md) for details.
