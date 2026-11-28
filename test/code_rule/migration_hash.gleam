//// The migration-hash rule: a file of `priv/migrations` has the SHA-256
//// its row of the list records.

import code_rule/source.{type Breach}
import genesis_prime/migration.{type Migration}

/// A row of the list: a migration's name, its recorded hash, and its line of
/// the list file (counted from 1).
pub type Listed {
  Listed(name: String, sha256: String, line: Int)
}

/// The list of recorded hashes.
pub const list_path = "test/code_rule/migration_hashes.txt"

/// The rows of the list text.
pub fn parse_list(text text: String) -> List(Listed) {
  let _ = text
  panic as "the migration-hash rule is not built"
}

/// A breach for each migration whose hash differs from its row, each
/// migration with no row, each row with no migration, and each row not after
/// the row before it.
pub fn breaches(
  migrations migrations: List(Migration),
  listed listed: List(Listed),
) -> List(Breach) {
  let _ = migrations
  let _ = listed
  panic as "the migration-hash rule is not built"
}
