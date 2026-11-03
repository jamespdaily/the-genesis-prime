---
name: choosing-packages
description: How a package, an Erlang external or our own helper is chosen - the search, the trust filter, licences, Rust. Use before adding a dependency or an Erlang external.
---

# Choosing packages

Before writing a helper that is not game logic, look for a base, in this order:
1. Gleam's own libraries (`gleam_stdlib`, `gleam_otp`, `gleam_erlang`).
2. A vetted Gleam package.
3. OTP or an Erlang package, through a typed external.
4. An Elixir package, when it does the job clearly better or nothing earlier does; it brings the Elixir toolchain into the setup check and CI, which the step adds.
5. A Rust NIF, by the four-numbers rule below.

Each step is taken only when the ones before it fall short, and the search on the step's issue says why.

The search fits the size of the need:
- **An existing helper or installed library does the job:** read its contract and use it.
- **A small helper whose behaviour differs from what exists:** keep it, and say in its doc comment what differs.
- **New infrastructure or a new dependency:** search packages.gleam.run and hex.pm and record the search on the step's issue: the query, the candidates and why each was taken or left. A package already in manifest.toml that does the job is used; a new one that does it better is proposed to Jim.
- Each candidate passes a trust filter (an accepted licence, its source read, maintained, its dependencies, the Erlang target), then a fit test in a scratch project when compatibility or speed is uncertain. The best fit wins; on a tie, the one with fewer moving parts.
- Our own code needs a need no candidate meets, named in its doc comment.
- The project is AGPL-3.0, so any open-source licence is accepted; code from another WildStar server is still never copied (CLAUDE.md).
- Rust only with four numbers on the issue: a deadline a player can feel, cheaper fixes tried, Rust closes the gap, a test compares the two. A package with native code counts as Rust.
- A broken package is patched in place, each patch marked with its upstream bug, never rewritten.
- Erlang externals only for runtime APIs Gleam lacks, each with an exact Gleam type, never `Dynamic`, and its module says why no Gleam library covers it.
