//// What the cast rule does with the targets of a go (`genesis_prime/game/cast`
//// `Strike` and `went`), on the rows of the cast tests' planted plans
//// (`cast_support`). Expected values come from these places.
//// - The cast rule's doc comment: a go with damage asks for its targets and writes
////   nothing until the round closes; the closed round's go is a 0x7f4 with one target
////   info for each Hit unit, target flags 0, then a 0x7fb of the deflected units
////   (`opcode.0x7f4`, `opcode.0x7fb`); a cast the client ended while the round was open
////   has no go and writes nothing.
//// - The cast id of the caster's first cast: 2^31 + unit id x 2^11 + 0 for unit 7
////   (`cast.pending_table`, `0x140561c30`).
//// - Telekinetic Strike: bag index 0, a cast time of 1250 ms (`Spell4.32893`).

import cast_support as support
import genesis_prime/game/cast.{Deflected, GoAsked, Hit}
import genesis_prime/message/cast_result
import genesis_prime/message/miss_reason
import genesis_prime/message/spell_go
import genesis_prime/message/spell_miss.{SpellMiss}
import genesis_prime/message/spell_missed
import genesis_prime/message/spell_started
import genesis_prime/table/id.{Spell4Id}
import gleam/list
import owned_test

/// 2^31 + 7 x 2^11: the caster 7's first cast id.
const first_cast = 2_147_497_984

/// The state and effects after Telekinetic Strike is pressed and its go timer
/// fires at 2250 ms.
fn gone() -> #(cast.State, List(cast.Effect)) {
  let #(state, pressed) =
    support.pressed_raw(
      state: cast.new(),
      caster: support.caster(),
      bag_index: 0,
      target: 0,
      at: 1000,
    )
  let assert [#(timer, 1250)] = support.started_timers(effects: pressed)
    as "the cast time of Spell4.32893"
  support.fired_raw(state:, timer:, at: 2250)
}

pub fn a_go_with_damage_asks_for_its_targets_and_writes_nothing_until_the_round_closes_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, effects) = gone()
  assert list.contains(
    effects,
    cast.Strike(asked: GoAsked(
      cast_id: first_cast,
      phase: 0,
      spell4_id: Spell4Id(32_893),
      primary_target: 7,
    )),
  )
    as "the go asks the connection for its targets, with the caster as the primary target"
  assert support.writes(effects:) == []
    as "the 0x7f4 waits for the closed round"
  assert support.tells(effects:) == []
}

pub fn a_closed_round_writes_the_go_with_a_target_info_for_each_hit_unit_and_a_0x7fb_for_each_deflect_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = gone()
  let #(_, effects) =
    cast.went(
      cast: state,
      caster: support.caster(),
      now: support.at(ms: 2260),
      cast_id: first_cast,
      phase: 0,
      struck: [Hit(unit_id: 10, descriptions: []), Deflected(unit_id: 11)],
    )
  let assert [go, missed, ..] = support.writes(effects:)
    as "the go, then the miss"
  let assert Ok(go) = spell_go.decode(go.body)
  assert list.map(go.targets, fn(target) { #(target.unit_id, target.flags) })
    == [#(10, 0)]
    as "one target info for each Hit unit, target flags 0 (opcode.0x7f4.target_info)"
  assert missed.message_id == spell_missed.message_id
  let assert Ok(missed) = spell_missed.decode(missed.body)
  assert missed
    == spell_missed.SpellMissed(cast_id: first_cast, misses: [
      SpellMiss(unit_id: 11, reason: miss_reason.Dodge, time_ms: 0),
    ])
    as "a deflect is an entry with reason 0 (Dodge), which the client shows as Deflect (opcode.0x7fb)"
}

pub fn a_struck_unit_the_client_no_longer_shows_is_still_named_in_the_go_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = gone()
  let #(_, effects) =
    cast.went(
      cast: state,
      caster: support.caster(),
      now: support.at(ms: 2260),
      cast_id: first_cast,
      phase: 0,
      struck: [Hit(unit_id: 99, descriptions: [])],
    )
  let assert [go, ..] = support.writes(effects:)
  let assert Ok(go) = spell_go.decode(go.body)
  assert list.map(go.targets, fn(target) { target.unit_id }) == [99]
    as "the client skips a unit it does not have (opcode.0x7f4.target_info), so the info is sent"
}

pub fn a_0x801_while_a_round_is_open_leaves_the_close_with_nothing_to_write_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = gone()
  let assert Ok(#(state, _)) =
    cast.take(
      cast: state,
      message: cast.Cancelled,
      body: support.cancel_body(
        cast_id: first_cast,
        reason: cast_result.SpellCancelled,
        bit: 1,
      ),
      caster: support.caster(),
      plans: support.plans(),
      now: support.at(ms: 2300),
    )
    as "the client ends the cast with reason 6 (opcode.0x801)"
  let #(_, effects) =
    cast.went(
      cast: state,
      caster: support.caster(),
      now: support.at(ms: 2400),
      cast_id: first_cast,
      phase: 0,
      struck: [Hit(unit_id: 10, descriptions: [])],
    )
  assert effects == []
    as "the cast is no longer live: no go and no finish are written, and the hits stand in the creature"
}

pub fn a_proxy_aimed_at_the_area_starts_one_child_for_each_hit_unit_and_none_for_a_deflect_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = gone()
  let #(_, effects) =
    cast.went(
      cast: state,
      caster: support.caster(),
      now: support.at(ms: 2260),
      cast_id: first_cast,
      phase: 0,
      struck: [
        Hit(unit_id: 10, descriptions: []),
        Deflected(unit_id: 11),
        Hit(unit_id: 12, descriptions: []),
      ],
    )
  let frames = support.writes(effects:)
  assert list.map(frames, fn(frame) { frame.message_id })
    == [0x07F4, 0x07FB, 0x07FF, 0x07FF, 0x07FE]
    as "the go, then the miss, then each child's start (its own go asks for its targets), then the pressed cast's finish, after the miss (cast.miss_order: a miss after the finish is dropped)"
  let starts =
    list.filter_map(frames, fn(frame) {
      case frame.message_id == 0x07FF {
        True -> {
          let assert Ok(start) = spell_started.decode(frame.body)
          Ok(#(start.spell4_id, start.primary_target_unit_id))
        }
        False -> Error(Nil)
      }
    })
  assert starts == [#(30_900, 10), #(30_900, 12)]
    as "Spell4Effects 62204 is a Proxy to 30900 aimed at the area: one child for each Hit unit, with that unit as its primary target, and none for the deflected 11"
}
