//// The fact file read as records (`genesis_prime/coverage/fact_record`): the statement, grade
//// and gap of each record, and the tests' reader of them (`fact_file`).
//// - `0x140566ad0` is graded sure and states no gap: the fact file's record of the flat part
////   of the client's value formula.

import fact_file.{NoRecord}
import genesis_prime/coverage/fact_record.{
  BadRecord, FairlySure, Guess, Record, Sure,
}
import gleam/dict
import gleam/option.{None, Some}
import owned_test

const planted =
  "
[\"first\"]
statement = \"What the first holds.\"
proof = \"Where.\"
grade = \"guess\"
gap = \"What is open.\"

[\"second\"]
statement = \"What the second holds.\"
proof = \"Where.\"
grade = \"fairly sure\"

[\"third\"]
statement = \"What the third holds.\"
proof = \"Where.\"
grade = \"sure\"
"

pub fn a_records_statement_grade_and_gap_are_read_when_it_has_them_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(facts) = fact_record.parse(text: planted)
    as "the planted text is a fact file"
  assert dict.get(facts, "first")
    == Ok(Record(
      statement: "What the first holds.",
      grade: Some(Guess),
      gap: Some("What is open."),
    ))
    as "a record with a gap holds it"
  assert fact_record.grade_of(facts:, key: "second") == Some(FairlySure)
    as "the grade of a record with no gap"
  assert fact_record.gap_of(facts:, key: "second") == None
    as "a record states a gap or none"
  assert fact_record.grade_of(facts:, key: "third") == Some(Sure)
  assert fact_record.grade_of(facts:, key: "missing") == None
    as "a record that is not there has no grade"
  assert !fact_record.has_record(facts:, key: "missing")
  assert fact_record.has_record(facts:, key: "first")
}

pub fn a_record_with_a_grade_the_checker_does_not_allow_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert fact_record.parse(
      text: "[\"odd\"]\nstatement = \"S.\"\ngrade = \"likely\"\n",
    )
    == Error(BadRecord(name: "odd"))
    as "a grade is sure, fairly sure or guess"
  assert fact_record.parse(text: "[\"odd\"]\nproof = \"P.\"\n")
    == Error(BadRecord(name: "odd"))
    as "a record states what it holds"
}

pub fn the_tests_reader_gives_a_records_grade_and_gap_and_names_a_missing_record_test() -> Nil {
  use <- owned_test.run(5000)
  assert fact_file.grade_of(record: "0x140566ad0") == Ok(Some(Sure))
    as "the formula's flat part is graded sure"
  assert fact_file.gap_of(record: "0x140566ad0") == Ok(None)
    as "and states no gap"
  assert fact_file.grade_of(record: "no.such.record")
    == Error(NoRecord(name: "no.such.record"))
  assert fact_file.gap_of(record: "no.such.record")
    == Error(NoRecord(name: "no.such.record"))
}
