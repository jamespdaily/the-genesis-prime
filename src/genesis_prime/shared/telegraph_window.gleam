//// Whether the client is drawing a TelegraphDamage row at a go of a cast: the time window the
//// client gives the row from the cast's 0x7ff, not the go the row's phaseFlags name.
////
//// ```
//// row + the cast's go times + a go ─▶ drawn_at ─▶ the window [appears, goes] holds the go's time
//// ```
////
//// - **A row's clock** is the cast's age from the client's receipt of the 0x7ff, which the gos do
////   not move: it appears at `telegraphTimeStartMs` and goes at `telegraphTimeEndMs`, 0 being no
////   end (`TelegraphDamage.telegraphTimeStartMs`, `0x140546e60`, `0x14054b1b0`).
//// - **displayFlags** decide when a row may appear: bit 4 before the first go, bit 8 from it
////   (`0x140542d90`). A row that would appear before the first go without bit 4 appears at the
////   first go, and a row that would appear from it without bit 8 is never drawn.
//// - **A row with no end** goes at the first go at or after it appears when its displayFlags
////   lacks 8, else when the cast finishes, taken as the last go (`0x140546b70`, `0x1405465f0`).
//// - **A row with an end and displayFlags bit 0x10** also goes when the cast finishes, which
////   changes nothing here: the finish is the last go, no strike follows it, and a go is asked
////   at its own time (`0x140546b70`).
//// - **A row that appears at a go** is made at that go, the last included, before the go ends
////   rows with no end (`ApplySpellGo 0x14053e5a0` line 216); one that would appear after the
////   last go is drawn at none.
//// - **A row flagged 0x40 or 0x100** is never drawn (`0x140542d90`).
//// - **A row is drawn at a go equal to its end**: a marked guess, since the client's order of the
////   end and the go is not read (`TelegraphDamage.telegraphTimeStartMs`).
//// - **A row timed from a go** (flag 0x2000) is not read here: its window runs from a phase's go
////   (`TelegraphDamage.telegraphDamageFlags.0x2000`), so `timed_from_a_go` names it for the
////   caller to refuse.

import genesis_prime/shared/spell_effect
import genesis_prime/shared/telegraph_entries
import genesis_prime/table/telegraph_damage.{type TelegraphDamage}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Whether the row's window from the cast's start holds the time of go `go` of a cast whose
/// gos fall `go_times_ms` after its start, in order. A go the cast does not have is never
/// drawn at.
pub fn drawn_at(
  row row: TelegraphDamage,
  go_times_ms go_times_ms: List(Int),
  go go: Int,
) -> Bool {
  case window_of(row:, go_times_ms:), list.drop(go_times_ms, go) {
    Some(#(appears_ms, goes_ms)), [at_ms, ..] if go >= 0 ->
      appears_ms <= at_ms && at_ms <= goes_ms
    _, _ -> False
  }
}

/// Whether the row is timed from a phase's go instead of the cast's start (flag 0x2000).
pub fn timed_from_a_go(row row: TelegraphDamage) -> Bool {
  spell_effect.has_flag(flags: row.telegraph_damage_flags, bit: 0x2000)
}

/// When the row appears and when it goes, in milliseconds from the cast's start, or `None` for a
/// row the client never draws.
fn window_of(
  row row: TelegraphDamage,
  go_times_ms go_times_ms: List(Int),
) -> Option(#(Int, Int)) {
  let flags = row.display_flags
  let assert Ok(first_go_ms) = list.first(go_times_ms)
    as "a cast has at least one go"
  let assert Ok(finish_ms) = list.last(go_times_ms)
    as "a cast has at least one go"
  let appears_ms = case
    row.telegraph_time_start_ms < first_go_ms
    && !spell_effect.has_flag(flags:, bit: 4)
  {
    True -> first_go_ms
    False -> row.telegraph_time_start_ms
  }
  let has_end = row.telegraph_time_end_ms != 0
  let goes_ms = case has_end {
    True -> row.telegraph_time_end_ms
    False ->
      case spell_effect.has_flag(flags:, bit: 8) {
        True -> finish_ms
        False ->
          list.find(go_times_ms, fn(at_ms) { at_ms >= appears_ms })
          |> option.from_result
          |> option.unwrap(finish_ms)
      }
  }
  let never_drawn =
    telegraph_entries.drawn_rows(rows: [row]) == []
    || has_end
    && appears_ms >= row.telegraph_time_end_ms
    || appears_ms >= first_go_ms
    && !spell_effect.has_flag(flags:, bit: 8)
  case never_drawn {
    True -> None
    False -> Some(#(appears_ms, goes_ms))
  }
}
