//// The message ids the client sends, as the code lists them, against the fact
//// file's records of the client's send paths. The record's statement holds the
//// ids as hex numbers after "ids in all (hex): ".

import genesis_prime/coverage/sent_message
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import owned_test
import simplifile

const facts_file =
  ".claude/skills/decoding-the-client/references/client-facts.toml"

/// The ids a record's statement lists in hex after "ids in all (hex): ", up to
/// the full stop that ends the list.
fn ids_of_record(address: String) -> List(Int) {
  let assert Ok(text) = simplifile.read(facts_file)
    as "the fact file could not be read"
  let assert [_, after_key] = string.split(text, "[\"" <> address <> "\"]\n")
    as { "the fact file has not exactly one record " <> address }
  let assert Ok(#(statement, _)) = string.split_once(after_key, "\n")
    as "the record has no statement line"
  let assert Ok(#(_, listed)) =
    string.split_once(statement, "ids in all (hex): ")
    as { address <> " lists no ids" }
  let assert Ok(#(list_text, _)) = string.split_once(listed, ".")
    as "the list does not end"
  list.map(string.split(list_text, ", "), fn(token) {
    let assert Ok(id) =
      string.remove_prefix(token, "0x")
      |> int.base_parse(16)
      |> result.replace_error(Nil)
      as { "not a hex id: " <> token }
    id
  })
}

pub fn every_id_a_client_send_path_records_is_in_the_list_test() -> Nil {
  use <- owned_test.run(10_000)
  let listed = sent_message.all()
  list.each(
    [
      #("0x1403f4900", 245),
      #("0x1403f4740", 58),
      #("0x140016010", 7),
      #("0x1400161d0", 23),
    ],
    fn(path) {
      let ids = ids_of_record(path.0)
      assert list.length(ids) == path.1
        as { path.0 <> ": the record's own count of ids" }
      list.each(ids, fn(id) {
        assert list.contains(listed, id)
          as { path.0 <> " sends " <> int.to_string(id) <> ", missing here" }
      })
    },
  )
}

pub fn the_client_sends_352_distinct_ids_test() -> Nil {
  use <- owned_test.run(10_000)
  let listed = sent_message.all()
  assert list.length(listed) == 352
    as "fact 0x1403309a0: with 0x244, 0x38c and ids 0, 1 and 2 the client sends 352 ids in all"
  assert list.unique(listed) == listed
    as "no id is listed twice (RegisterMessage 0x1403309a0: 1,132 distinct ids registered; the send paths share none)"
  assert list.sort(listed, int.compare) == listed
    as "the list is in ascending order"
}

pub fn the_directly_sent_and_the_bare_ids_are_in_the_list_test() -> Nil {
  use <- owned_test.run(10_000)
  let listed = sent_message.all()
  // fact 0x140332920, SerialiseMessageById: the 14 ids sent directly.
  let direct = [
    0x7E0,
    0x6E7,
    0x7DD,
    0x25C,
    0x25B,
    0x352,
    0x786,
    0x3EE,
    0x142,
    0x58F,
    0x592,
    0x7A4,
    0x7DF,
    0x241,
  ]
  // fact 0x140332580: 0x244, and ids 0, 1 and 2 sent bare; fact 0x1403f4900: 0x38c.
  let others = [0x244, 0x38C, 0, 1, 2]
  list.each(list.append(direct, others), fn(id) {
    assert list.contains(listed, id)
      as { "the client sends " <> int.to_string(id) }
  })
}
