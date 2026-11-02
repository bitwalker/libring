# Changelog

## Unreleased

### Fixed

- Select all requested distinct replica owners across both ring boundaries, in
  clockwise order, with bounded traversal. Addresses [#39](https://github.com/bitwalker/libring/issues/39)
  and the incomplete wraparound case discussed in [#40](https://github.com/bitwalker/libring/pull/40).
- Start supervised managed rings under the requesting supervisor, with correct
  restart/shutdown ownership, rather than calling a missing function. Addresses
  [#38](https://github.com/bitwalker/libring/pull/38).
- Apply the existing primary-owner atom normalization to replica lookup too.
- Accept empty/weighted-atom managed node configurations and unambiguous scalar
  or compound bulk keys; report invalid options and weights intentionally.
  Reject empty binary keys before worker mutation, preserving existing ring state.
- Apply remote node-type filtering consistently at monitored startup and on later
  events, and subscribe before the initial membership snapshot. Honor the documented
  no-op behavior of manual membership requests on monitored rings.
- Correct hashing, keyspace, read-path, license, source-link, and release guidance.

### Maintenance

- Restore supported CI runners and explicit runtime pairs, including a separate
  minimum-consumer compatibility job without development dependencies.
- Enforce action lockfiles, actionlint, zizmor, least-privilege tokens, and trusted
  cache writes; refresh documentation, type-analysis, and property-test tooling.
- Add a changelog to documentation and package contents.

### Compatibility

- Existing atom-key replica selections can change: the first replica now matches
  `key_to_node/2`. Single-node routing and non-atom hashing remain unchanged.
  Applications persisting replicas should reconcile placement during rollout.
- Monitored rings now ignore valid manual membership changes as documented.
  Applications managing membership explicitly should use static rings.
- Managed two-tuples remain weighted-entry syntax; wrap a tuple node in an
  explicitly weighted entry. Invalid startup options raise `ArgumentError`.
- The declared Elixir 1.11 consumer requirement and default node weight of 128
  remain unchanged. Development tooling uses newer runtimes.
