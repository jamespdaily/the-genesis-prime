//// The released server cannot be seeded. The expected value is the issue's
//// test 2: the settings `genesis_prime.main` starts with draw every random
//// byte of the login (the STS secrets and both hand-offs' keys) from the
//// operating system's strong source, whatever the environment holds. The
//// other half of the test, that no module of `src/` can import the seeded
//// generator, is in `code_rule/seeded_source_test`.

import genesis_prime
import genesis_prime/login/random_source.{Strong}
import gleam/dict
import owned_test

/// The environment of a machine that has what the server needs to start, and
/// also a variable that names a seed, which the released server must ignore.
fn environment(name: String) -> Result(String, Nil) {
  dict.from_list([
    #("PGHOST", "localhost"),
    #("PGPORT", "5432"),
    #("PGUSER", "genesis"),
    #("PGDATABASE", "genesis"),
    #("GENESIS_TABLE_DIR", "/tables"),
    #("GENESIS_SEED", "72"),
    #("GENESIS_RANDOM_SEED", "72"),
  ])
  |> dict.get(name)
}

pub fn the_released_servers_settings_use_the_strong_random_source_test() -> Nil {
  use <- owned_test.run(5000)
  let login = genesis_prime.release_settings(get: environment).login
  assert login.random == Strong
    as "the STS secrets are drawn from the operating system"
  assert login.game_tokens.random == Strong
    as "the game tokens are drawn from the operating system"
  assert login.session_keys.random == Strong
    as "the session keys are drawn from the operating system"
}
