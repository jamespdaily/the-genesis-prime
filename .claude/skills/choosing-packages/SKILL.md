---
name: choosing-packages
description: Sets how a package, an Erlang external or the project's own helper is chosen - the search order, the trust filter, licences, Rust NIFs. Use before adding a dependency or an Erlang external, or writing infrastructure a package might cover.
---

# Choosing packages

Before writing a helper that is not game logic, look for a base in this order, taking each only when the ones before fall short:
1. Gleam's own libraries (`gleam_stdlib`, `gleam_otp`, `gleam_erlang`).
2. A vetted Gleam package.
3. OTP or an Erlang package, through a typed external.
4. An Elixir package, when it does the job clearly better or nothing earlier does; the step adds the Elixir toolchain to the setup check and CI.
5. A Rust NIF, only with four numbers on the issue: a deadline a player can feel, cheaper fixes tried, Rust closes the gap, a test compares the two. A package with native code counts as Rust.

- New infrastructure or a new dependency: search packages.gleam.run and hex.pm and record on the step's issue the query, the candidates and why each was taken or left. A package already in manifest.toml that does the job is used; a new one that does it better is proposed to Jim.
- Each candidate passes a trust filter (an accepted licence, its source read, maintained, its dependencies, the Erlang target), then a fit test in a scratch project when compatibility or speed is uncertain. The best fit wins; on a tie, the one with fewer moving parts. The project is AGPL-3.0, so any open-source licence is accepted.
- Our own helper names, in its doc comment, the need no candidate meets or how it differs from what exists.
- A broken package is patched in place, each patch marked with its upstream bug, never rewritten.
- Each Erlang external has an exact Gleam type, never `Dynamic`, and its module says why no Gleam library covers it.
