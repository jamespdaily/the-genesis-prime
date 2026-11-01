//// A vector test takes its bytes from the fact file's record and fails when the
//// record is missing or its statement gives other bytes. Expected values are
//// the statements of these records, read in the fact file.
//// - `vector.opcode.0x36.body`: "the highest character level 3 is the 32 bits
////   03000000 (4 bytes)".
//// - `vector.opcode.0x3.body`: the body in groups, "aa3e0000 44332211 88776655
////   ...".
//// - `vector.opcode.0x1.body`: the single bytes "00, 13, 14 and ff".
//// - `opcode.0x7e0`: "its body is empty".

import fact_file.{BytesNotGiven, NoRecord}
import message_support
import owned_test

pub fn a_record_the_fact_file_does_not_have_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert fact_file.gives(record: "vector.opcode.0xffff.body", bytes: <<1>>)
    == Error(NoRecord(name: "vector.opcode.0xffff.body"))
    as "no record has this name"
}

pub fn the_bytes_a_statement_gives_are_accepted_test() -> Nil {
  use <- owned_test.run(5000)
  assert fact_file.gives(
      record: "vector.opcode.0x36.body",
      bytes: message_support.hex("03000000"),
    )
    == Ok(Nil)
    as "the statement gives 03000000"
  assert fact_file.gives(
      record: "vector.opcode.0x1.body",
      bytes: message_support.hex("13"),
    )
    == Ok(Nil)
    as "the statement gives the single byte 13, beside the commas that part the bytes"
  assert fact_file.gives(
      record: "vector.opcode.0x3.body",
      bytes: message_support.hex("aa3e0000 44332211 88776655"),
    )
    == Ok(Nil)
    as "the statement gives its groups one after another, so a run of them is its bytes"
}

pub fn bytes_that_differ_from_the_statements_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let record = "vector.opcode.0x36.body"
  assert fact_file.gives(record:, bytes: message_support.hex("04000000"))
    == Error(BytesNotGiven(name: record, bytes: message_support.hex("04000000")))
    as "a byte that differs from 03000000"
  assert fact_file.gives(record:, bytes: message_support.hex("0300"))
    == Error(BytesNotGiven(name: record, bytes: message_support.hex("0300")))
    as "the first two bytes are part of a group of the statement, not a whole one"
  assert fact_file.gives(record:, bytes: message_support.hex("00000003"))
    == Error(BytesNotGiven(name: record, bytes: message_support.hex("00000003")))
    as "the same bytes in another order"
  assert fact_file.gives(
      record: "vector.opcode.0x3.body",
      bytes: message_support.hex("aa3e0000 88776655"),
    )
    != Ok(Nil)
    as "two groups that are not next to each other in the statement"
  assert fact_file.gives(record: "vector.opcode.0x1.body", bytes: <<0, 19, 20>>)
    == Error(
      BytesNotGiven(name: "vector.opcode.0x1.body", bytes: <<0, 19, 20>>),
    )
    as "the statement gives the single bytes 00, 13, 14 and ff, each in a phrase of its own, so 00 13 14 is not a run of it"
}

pub fn an_empty_body_is_given_only_by_a_statement_that_says_it_is_empty_test() -> Nil {
  use <- owned_test.run(5000)
  assert fact_file.gives(record: "opcode.0x7e0", bytes: <<>>) == Ok(Nil)
    as "opcode.0x7e0: its body is empty"
  assert fact_file.gives(record: "vector.opcode.0x36.body", bytes: <<>>)
    == Error(BytesNotGiven(name: "vector.opcode.0x36.body", bytes: <<>>))
    as "the record of a 4-byte body does not give an empty one"
}
