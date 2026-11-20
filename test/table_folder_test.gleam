//// The tools' home folder. Expected values are the rule the folder module
//// states: `GENESIS_HOME` when it is set, else `.genesis-prime` under the
//// user's home, else `.genesis-prime` in the working folder.

import genesis_prime/table_folder
import gleam/list
import owned_test

pub fn the_home_is_genesis_home_else_the_users_genesis_prime_folder_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #("both are set", Ok("/srv/gp"), Ok("/Users/jim"), "/srv/gp"),
    #("only GENESIS_HOME is set", Ok("/srv/gp"), Error(Nil), "/srv/gp"),
    #(
      "only the user's home is set",
      Error(Nil),
      Ok("/Users/jim"),
      "/Users/jim/.genesis-prime",
    ),
    #("neither is set", Error(Nil), Error(Nil), ".genesis-prime"),
  ]
  list.each(rows, fn(row) {
    assert table_folder.home_from(genesis_home: row.1, user_home: row.2)
      == row.3
      as row.0
  })
}
