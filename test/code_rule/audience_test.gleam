//// The audience rule. Expected value is the rule: a cast's news reaches a viewer through the
//// map's relation with the caster (genesis_prime/world_map/map `PlayerBroadcast`), so the
//// cast rule keeps no list of the connections that were told a cast's start, and the module
//// that states the gaps of the cast landing names neither such a list nor a sight notice
//// that two senders speak of. The word `audience` and its two functions `audience_joined`
//// and `audience_left` in a file of `src` are breaches, reported at their line, and so is an
//// entry of a gap list that says `audience` or `two senders`. The rule is shown on a planted
//// file, then read over the real ones.

import code_rule/planted
import code_rule/source.{type SourceFile}
import genesis_prime/game/connection/landing as connection_landing
import genesis_prime/gap
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

/// The lines of the file that say `audience`, in any case, which `audience_joined` and
/// `audience_left` do too.
fn audience_lines(file file: SourceFile) -> List(Int) {
  string.split(file.text, "\n")
  |> list.index_map(fn(line, index) { #(index + 1, line) })
  |> list.filter(fn(numbered) {
    string.contains(string.lowercase(numbered.1), "audience")
  })
  |> list.map(fn(numbered) { numbered.0 })
}

/// The entries of the gap list that name an audience or a notice two senders speak of.
fn entries_naming(entries entries: List(gap.Entry)) -> List(String) {
  list.filter(entries, fn(entry) {
    let text = string.lowercase(entry.missing)
    string.contains(text, "audience") || string.contains(text, "two senders")
  })
  |> list.map(fn(entry) { string.slice(entry.missing, 0, 60) })
}

pub fn the_cast_rule_holds_no_audience_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: "src/genesis_prime/game/cast/state.gleam", lines: [
      "pub type State {",
      "  State(audience: Dict(Int, Set(ConnectionId)))",
      "}",
      "",
      "pub fn audience_joined(cast cast: State) -> State {",
      "  cast",
      "}",
      "",
      "fn another() {",
      "  Nil",
      "}",
    ])
  assert audience_lines(file: planted_file) == [2, 5]
    as "a field and a function named after the audience are found, and another line is not"
  assert list.flat_map(source.files(under: "src"), fn(file) {
      list.map(audience_lines(file:), fn(line) {
        file.path <> ":" <> int.to_string(line)
      })
    })
    == []
    as "no file of src names an audience: the map's relation says who is told"
}

pub fn no_gap_entry_names_the_audience_or_a_sight_notice_from_two_senders_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  use <- unitest.tag("gaps")
  let planted_entries = [
    gap.Entry(
      area: "Casting",
      missing: "A viewer inside the audience of a cast.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "The map's notice and the caster's tell come from two senders.",
    ),
    gap.Entry(area: "Casting", missing: "A kept source stays."),
  ]
  assert list.length(entries_naming(entries: planted_entries)) == 2
    as "an entry that says audience and one that says two senders are found, and another is not"
  assert entries_naming(entries: connection_landing.gaps()) == []
    as "no entry of the landing's gaps names the audience or a notice from two senders"
  assert list.any(connection_landing.gaps(), fn(entry) {
    string.contains(entry.missing, "kept")
  })
    as "the sentence about a kept source stays"
}
