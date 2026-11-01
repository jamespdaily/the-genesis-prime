//// The rule that compares a database's recorded migrations with the files
//// (`genesis_prime/migration`). Expected values come from these places.
//// - The card's cases: a file the database never ran, a recorded file whose
////   hash differs from its file's (an applied migration edited after it ran),
////   a recorded name with no file, a database with no record and one whose
////   record cannot be read, each a
////   reason to refuse to start, named by the migration.

import genesis_prime/migration.{
  type Migration, DatabasePredatesRecords, Edited, Migration, NoFile, NoRecord,
  NotApplied, RecordUnreadable, Recorded, Unreadable,
}
import gleam/list
import gleam/string
import owned_test

fn file(name: String, digit: String) -> Migration {
  Migration(name:, sha256: string.repeat(digit, 64))
}

pub fn files_and_a_record_that_name_the_same_migrations_with_the_same_hashes_agree_test() -> Nil {
  use <- owned_test.run(5000)
  let files = [file("0000_a", "a"), file("0001_b", "b")]
  assert migration.check(
      files:,
      recorded: Recorded([file("0001_b", "b"), file("0000_a", "a")]),
    )
    == Ok(Nil)
    as "the order the database lists its rows in is no difference"
  assert migration.check(files: [], recorded: Recorded([])) == Ok(Nil)
}

pub fn a_file_the_database_never_ran_is_not_applied_and_names_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert migration.check(
      files: [file("0000_a", "a"), file("0001_b", "b")],
      recorded: Recorded([file("0000_a", "a")]),
    )
    == Error(NotApplied("0001_b"))
}

pub fn a_recorded_hash_that_differs_from_its_files_is_an_edited_migration_test() -> Nil {
  use <- owned_test.run(5000)
  assert migration.check(
      files: [file("0000_a", "a"), file("0001_b", "b")],
      recorded: Recorded([file("0000_a", "a"), file("0001_b", "c")]),
    )
    == Error(Edited("0001_b"))
}

pub fn a_recorded_name_with_no_file_is_a_migration_this_build_does_not_know_test() -> Nil {
  use <- owned_test.run(5000)
  assert migration.check(
      files: [file("0000_a", "a")],
      recorded: Recorded([file("0000_a", "a"), file("0007_gone", "g")]),
    )
    == Error(NoFile("0007_gone"))
}

pub fn a_database_with_no_record_predates_migration_records_test() -> Nil {
  use <- owned_test.run(5000)
  assert migration.check(files: [file("0000_a", "a")], recorded: NoRecord)
    == Error(DatabasePredatesRecords)
}

pub fn a_record_that_cannot_be_read_is_refused_with_the_reason_test() -> Nil {
  use <- owned_test.run(5000)
  assert migration.check(
      files: [file("0000_a", "a")],
      recorded: Unreadable("permission denied"),
    )
    == Error(RecordUnreadable("permission denied"))
}

pub fn several_differences_name_the_first_by_name_whatever_the_order_given_test() -> Nil {
  use <- owned_test.run(5000)
  let files = [file("0002_c", "c"), file("0001_b", "b"), file("0004_e", "e")]
  let recorded = [file("0003_d", "d"), file("0001_b", "x"), file("0002_c", "c")]
  // 0001_b is edited, 0003_d has no file, 0004_e is not applied.
  list.each([recorded, list.reverse(recorded)], fn(rows) {
    assert migration.check(files:, recorded: Recorded(rows))
      == Error(Edited("0001_b"))
      as "the lowest name that differs is the one named"
  })
}

pub fn each_refusal_is_described_with_the_migration_it_names_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(NotApplied("0001_b"), "has not run the migration 0001_b"),
      #(Edited("0001_b"), "0001_b was edited after it ran"),
      #(NoFile("0001_b"), "ran the migration 0001_b, which has no file"),
      #(DatabasePredatesRecords, "predates migration records"),
      #(RecordUnreadable("boom"), "could not be read: boom"),
    ],
    fn(row) {
      assert string.contains(migration.describe(row.0), row.1)
        as "the sentence says what is wrong"
    },
  )
}
