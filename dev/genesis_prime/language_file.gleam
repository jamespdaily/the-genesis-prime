//// The client's text file `en-US.bin`, read for the developer tools: the texts by
//// id, as the client looks them up (`GetLocalizedText`, 0x14034bdd0).
////
//// The layout is the fact file's `language_file.layout`: magic `XETL`; at 0x40 the
//// entry count (u32), at 0x48 the entries' place (u64), at 0x50 the text's length in
//// UTF-16 characters (u64), at 0x58 the text's place (u64), both places counted from
//// byte 0x60; entries of 8 bytes, a text id then the character offset of its text,
//// sorted by id; each text zero-terminated UTF-16LE.
////
//// `read` refuses a file with another magic, entries or text past its end, an offset
//// past the text, or ids not in order; `text` refuses a text that is not UTF-16 or has
//// no terminating zero.

import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

/// Where the header ends: the entries' and the text's places count from here.
const header_end = 0x60

/// The file's magic.
const magic = <<"XETL">>

/// A language file: its bytes and where its entries and its text lie.
pub opaque type LanguageFile {
  LanguageFile(
    bytes: BitArray,
    count: Int,
    entries_at: Int,
    text_at: Int,
    text_length: Int,
  )
}

/// Why the file is refused.
pub type Refusal {
  TooShort
  WrongMagic
  EntriesPastTheEnd(count: Int)
  TextPastTheEnd(length: Int)
  OffsetPastTheText(text_id: Int, offset: Int)
  IdsOutOfOrder(before: Int, after: Int)
  NoTerminatingZero(text_id: Int)
  NotUtf16(text_id: Int)
}

/// The sentence for a refusal.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    TooShort -> "the language file is shorter than its header"
    WrongMagic -> "the language file does not start with XETL"
    EntriesPastTheEnd(count:) ->
      "the " <> int.to_string(count) <> " entries run past the end of the file"
    TextPastTheEnd(length:) ->
      "the text of "
      <> int.to_string(length)
      <> " characters runs past the end of the file"
    OffsetPastTheText(text_id:, offset:) ->
      "text "
      <> int.to_string(text_id)
      <> " starts at character "
      <> int.to_string(offset)
      <> ", past the end of the text"
    IdsOutOfOrder(before:, after:) ->
      "the entries are not in id order: "
      <> int.to_string(before)
      <> " is followed by "
      <> int.to_string(after)
    NoTerminatingZero(text_id:) ->
      "text "
      <> int.to_string(text_id)
      <> " has no terminating zero before the end of the text"
    NotUtf16(text_id:) -> "text " <> int.to_string(text_id) <> " is not UTF-16"
  }
}

/// Reads the header and checks every entry; the texts are decoded by `text`.
pub fn read(bytes bytes: BitArray) -> Result(LanguageFile, Refusal) {
  case bytes {
    <<
      file_magic:bytes-size(4),
      _:bytes-size(60),
      count:32-little,
      _:32,
      entries_place:64-little,
      text_length:64-little,
      text_place:64-little,
      _:bits,
    >> -> {
      use <- bool.guard(when: file_magic != magic, return: Error(WrongMagic))
      let entries_at = header_end + entries_place
      let text_at = header_end + text_place
      let size = bit_array.byte_size(bytes)
      use <- bool.guard(
        when: entries_at + 8 * count > size,
        return: Error(EntriesPastTheEnd(count:)),
      )
      use <- bool.guard(
        when: text_at + 2 * text_length > size,
        return: Error(TextPastTheEnd(length: text_length)),
      )
      let file =
        LanguageFile(bytes:, count:, entries_at:, text_at:, text_length:)
      use Nil <- result.map(entries_checked(file:, index: 0, before: None))
      file
    }
    _ -> Error(TooShort)
  }
}

fn entries_checked(
  file file: LanguageFile,
  index index: Int,
  before before: Option(Int),
) -> Result(Nil, Refusal) {
  use <- bool.guard(when: index >= file.count, return: Ok(Nil))
  let #(text_id, offset) = entry(file:, index:)
  use Nil <- result.try(case before {
    Some(previous) if previous >= text_id ->
      Error(IdsOutOfOrder(before: previous, after: text_id))
    _ -> Ok(Nil)
  })
  use <- bool.guard(
    when: offset >= file.text_length,
    return: Error(OffsetPastTheText(text_id:, offset:)),
  )
  entries_checked(file:, index: index + 1, before: Some(text_id))
}

/// The id and character offset of entry `index`, which `read` has checked lies in
/// the file.
fn entry(file file: LanguageFile, index index: Int) -> #(Int, Int) {
  let assert Ok(<<text_id:32-little, offset:32-little>>) =
    bit_array.slice(file.bytes, file.entries_at + 8 * index, 8)
    as "read checked every entry lies in the file"
  #(text_id, offset)
}

/// The text of `text_id`, found by binary search as the client does, or `None`
/// when the file has none.
pub fn text(
  file file: LanguageFile,
  text_id text_id: Int,
) -> Result(Option(String), Refusal) {
  case found(file:, text_id:, low: 0, high: file.count - 1) {
    None -> Ok(None)
    Some(offset) -> decoded(file:, text_id:, offset:) |> result.map(Some)
  }
}

fn found(
  file file: LanguageFile,
  text_id text_id: Int,
  low low: Int,
  high high: Int,
) -> Option(Int) {
  use <- bool.guard(when: low > high, return: None)
  let middle = { low + high } / 2
  let #(middle_id, offset) = entry(file:, index: middle)
  case int.compare(middle_id, text_id) {
    order.Eq -> Some(offset)
    order.Lt -> found(file:, text_id:, low: middle + 1, high:)
    order.Gt -> found(file:, text_id:, low:, high: middle - 1)
  }
}

fn decoded(
  file file: LanguageFile,
  text_id text_id: Int,
  offset offset: Int,
) -> Result(String, Refusal) {
  let start = file.text_at + 2 * offset
  let end = file.text_at + 2 * file.text_length
  units(file:, text_id:, at: start, end:, found: [])
  |> result.try(fn(units) { codepoints(text_id:, units:, points: []) })
  |> result.map(string.from_utf_codepoints)
}

/// The UTF-16 code units from `at` up to the terminating zero.
fn units(
  file file: LanguageFile,
  text_id text_id: Int,
  at at: Int,
  end end: Int,
  found found: List(Int),
) -> Result(List(Int), Refusal) {
  use <- bool.guard(
    when: at + 2 > end,
    return: Error(NoTerminatingZero(text_id:)),
  )
  let assert Ok(<<unit:16-little>>) = bit_array.slice(file.bytes, at, 2)
    as "the unit lies inside the text, which read checked lies in the file"
  case unit {
    0 -> Ok(list.reverse(found))
    _ -> units(file:, text_id:, at: at + 2, end:, found: [unit, ..found])
  }
}

fn codepoints(
  text_id text_id: Int,
  units units: List(Int),
  points points: List(UtfCodepoint),
) -> Result(List(UtfCodepoint), Refusal) {
  case units {
    [] -> Ok(list.reverse(points))
    [high, low, ..rest] if high >= 0xD800 && high < 0xDC00 ->
      case low >= 0xDC00 && low < 0xE000 {
        True ->
          point(
            text_id:,
            number: 0x10000 + { high - 0xD800 } * 0x400 + { low - 0xDC00 },
          )
          |> result.try(fn(codepoint) {
            codepoints(text_id:, units: rest, points: [codepoint, ..points])
          })
        False -> Error(NotUtf16(text_id:))
      }
    [unit, ..rest] ->
      case unit >= 0xD800 && unit < 0xE000 {
        True -> Error(NotUtf16(text_id:))
        False ->
          point(text_id:, number: unit)
          |> result.try(fn(codepoint) {
            codepoints(text_id:, units: rest, points: [codepoint, ..points])
          })
      }
  }
}

fn point(
  text_id text_id: Int,
  number number: Int,
) -> Result(UtfCodepoint, Refusal) {
  string.utf_codepoint(number) |> result.replace_error(NotUtf16(text_id:))
}
