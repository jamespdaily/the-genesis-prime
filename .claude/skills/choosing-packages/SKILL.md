---
name: choosing-packages
description: How a package, an Erlang external or our own helper is chosen - the search, the trust filter, licences, Rust. Use before adding a dependency or an Erlang external.
---

# Choosing packages

Before writing a helper that is not game logic, look for a base, in this order: Gleam's own libraries (`gleam_stdlib`, `gleam_otp`, `gleam_erlang`), then a vetted Gleam package, then an Erlang package or OTP through an external, only for what no Gleam library exposes.

The search fits the size of the need:
- **An existing helper or installed library does the job:** read its contract and use it.
- **A small helper whose behaviour differs from what exists:** keep it, and say in its doc comment what differs.
- **New infrastructure or a new dependency:** search packages.gleam.run and hex.pm and record the search on the step's issue: the query, the candidates and why each was taken or left. A package already in manifest.toml that does the job is used; a new one that does it better is proposed to Jim.
- Each candidate passes a trust filter (an accepted licence, its source read, maintained, its dependencies, the Erlang target), then a fit test in a scratch project when compatibility or speed is uncertain. The best fit wins; on a tie, the one with fewer moving parts.
- Our own code needs a need no candidate meets, named in its doc comment.
- A package under a licence that would bind this project, such as AGPL, needs Jim's yes; code from such a project is never copied.
- Rust only with four numbers on the issue: a deadline a player can feel, cheaper fixes tried, Rust closes the gap, a test compares the two. A package with native code counts as Rust; an Elixir package needs a named reason.
- A broken package is patched in place, each patch marked with its upstream bug, never rewritten.
- Erlang externals only for runtime APIs Gleam lacks, each with an exact Gleam type, never `Dynamic`, and its module says why no Gleam library covers it.
