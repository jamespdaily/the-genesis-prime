//// The migration-hash rule. A migration file's SHA-256 (as
//// `genesis_prime.load_migrations` computes it) must equal its row of
//// `test/code_rule/migration_hashes.txt`: a changed file is a breach at its
//// row, a file with no row and a row with no file are breaches, and rows out of
//// order or repeated are breaches. The hashes below are SHA-256 of the ASCII
//// text "abc" (FIPS 180-2 appendix B) and "abd" (`shasum -a 256`). The last
//// test runs the rule over the real folder and list.

import code_rule/migration_hash
import code_rule/planted
import code_rule/source
import genesis_prime
import genesis_prime/migration.{Migration}
import owned_test
import unitest

const abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

const abd = "a52d159f262b2c6ddb724a61840befc36eb30c88877a4030b65cbe86298449c9"

pub fn a_migration_whose_bytes_differ_from_its_recorded_hash_is_a_breach_at_its_row_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let listed = migration_hash.parse_list("0001_a " <> abc <> "\n")
  assert migration_hash.breaches(
      migrations: [Migration(name: "0001_a", sha256: abc)],
      listed:,
    )
    == []
  let breaches =
    migration_hash.breaches(
      migrations: [Migration(name: "0001_a", sha256: abd)],
      listed:,
    )
  assert planted.lines(breaches) == [1]
  let assert [breach] = breaches
  assert breach.path == migration_hash.list_path
}

pub fn a_migration_with_no_row_and_a_row_with_no_migration_are_breaches_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let listed =
    migration_hash.parse_list("0001_a " <> abc <> "\n0003_c " <> abc <> "\n")
  let breaches =
    migration_hash.breaches(
      migrations: [
        Migration(name: "0001_a", sha256: abc),
        Migration(name: "0002_b", sha256: abc),
      ],
      listed:,
    )
  assert planted.lines(breaches) == [1, 2]
  let assert [no_row, no_file] = breaches
  assert no_row.path == "priv/migrations/0002_b.sql"
  assert no_file.path == migration_hash.list_path
}

pub fn the_hash_rows_are_sorted_with_one_row_per_migration_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let migrations = [
    Migration(name: "0001_a", sha256: abc),
    Migration(name: "0002_b", sha256: abc),
  ]
  let sorted =
    migration_hash.parse_list("0001_a " <> abc <> "\n0002_b " <> abc <> "\n")
  assert migration_hash.breaches(migrations:, listed: sorted) == []
  let reversed =
    migration_hash.parse_list("0002_b " <> abc <> "\n0001_a " <> abc <> "\n")
  assert planted.lines(migration_hash.breaches(migrations:, listed: reversed))
    == [2]
  let repeated =
    migration_hash.parse_list(
      "0001_a " <> abc <> "\n0001_a " <> abc <> "\n0002_b " <> abc <> "\n",
    )
  assert planted.lines(migration_hash.breaches(migrations:, listed: repeated))
    == [2]
}

pub fn every_migration_of_the_real_tree_has_its_recorded_hash_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let migrations = genesis_prime.load_migrations()
  assert migrations != [] as "the migrations are found"
  let listed = migration_hash.parse_list(source.read(migration_hash.list_path))
  assert migration_hash.breaches(migrations:, listed:) == []
}
