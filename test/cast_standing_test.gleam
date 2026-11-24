//// The player's standing spells (`genesis_prime/game/cast` `standing_changed`): a spell
//// the player holds while its source lasts starts as the innate passive does and
//// ends with its 0x7fe when it is no longer wanted. Every spell here is planted, so the
//// tests run without the client's tables. Expected values come from these places.
//// - `opcode.0x7ff`, `opcode.0x7fe` and `cast.target_node_end`: a cast the client
////   holds lasts until its 0x7fe, and a cast with no press has no 0x7fd.
//// - The server's choices, in the rule's doc: a spell wanted twice starts once, a call
////   that wants what stands changes and writes nothing, and a call that ends one spell
////   and starts another writes the 0x7fe first.

import cast_support as support
import genesis_prime/client_connection
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/spell_plan.{type Spell, LandsHit}
import genesis_prime/game/unit_properties
import genesis_prime/step.{ConnectionId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import owned_test

const first = 250_101

const second = 250_102

const third = 250_103

/// The state and effects once the wanted spells stand at the time, each go answered with
/// no unit struck.
fn standing(
  cast cast: State,
  caster caster: Caster,
  wanted wanted: List(Spell),
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    cast.standing_changed(cast:, caster:, wanted:, now: support.at(ms:))
  support.answered_as(caster:, state:, effects:, at: ms, struck: [], rolls: [])
}

fn started_spells(effects effects: List(Effect)) -> List(Int) {
  list.map(support.started_in(effects:), fn(start) { start.spell4_id })
}

fn started_ids(effects effects: List(Effect)) -> List(Int) {
  list.map(support.started_in(effects:), fn(start) { start.cast_id })
}

fn message_ids(effects effects: List(Effect)) -> List(Int) {
  list.map(support.writes(effects:), fn(frame) { frame.message_id })
}

pub fn standing_changed_starts_each_wanted_spell_not_yet_standing_in_list_order_and_the_same_list_again_changes_nothing_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster = support.caster()
  let wanted = [
    support.standing_spell(first),
    support.standing_spell(second),
    support.standing_spell(first),
  ]
  let #(state, effects) =
    standing(cast: cast_state.new(), caster:, wanted:, at: 1000)
  let assert [first_cast, _] = started_ids(effects:)
    as "the first call started two casts"
  assert started_spells(effects:) == [first, second]
    as "two spells start two casts in list order, and the spell wanted twice starts once"
  assert dict.to_list(state.standing)
    == list.zip(started_ids(effects:), [first, second])
    as "each cast stands for its own spell"
  let #(again, written) =
    cast.standing_changed(
      cast: state,
      caster:,
      wanted:,
      now: support.at(ms: 2000),
    )
  assert again == state
    as "the same list changes no state: the spell wanted twice is the one that stands"
  assert written == [] as "and writes nothing"
  let #(swapped, swap) =
    cast.standing_changed(
      cast: state,
      caster:,
      wanted: [support.standing_spell(second), support.standing_spell(third)],
      now: support.at(ms: 3000),
    )
  assert message_ids(effects: swap) == [0x07FE, 0x07FF]
    as "opcode.0x7fe, opcode.0x7ff: one call that drops a spell and adds another writes the 0x7fe of the first before the 0x7ff of the second"
  assert support.finished_ids(support.writes(effects: swap)) == [first_cast]
    as "the 0x7fe is the first spell's cast"
  assert started_spells(effects: swap) == [third]
  assert set.from_list(dict.values(swapped.standing))
    == set.from_list([second, third])
    as "the spell that was kept stands on, and the added one stands beside it"
}

pub fn standing_changed_ends_a_lingering_spell_no_longer_wanted_with_its_0x7fe_and_takes_its_modifiers_procs_and_timers_with_it_and_leaves_the_others_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster = support.caster()
  let proc_cast = support.child(spell4_id: 250_900, base: 250_900)
  let holder =
    support.standing_holder(first, fires_on: LandsHit, casts: proc_cast)
  let kept = support.standing_spell(second)
  let #(state, effects) =
    standing(cast: cast_state.new(), caster:, wanted: [holder, kept], at: 1000)
  let assert [holder_cast, kept_cast] = started_ids(effects:)
  let assert [#(child_timer, 5000)] = support.started_timers(effects:)
    as "the holder's Proxy waits its delay"
  assert dict.keys(state.lingering) |> list.sort(by: int.compare)
    == [holder_cast, kept_cast]
    as "the setup: both casts linger with their nodes"
  assert dict.size(state.procs) == 1 as "and the holder holds its Proc row"
  let #(state, ended) =
    cast.standing_changed(
      cast: state,
      caster:,
      wanted: [kept],
      now: support.at(ms: 2000),
    )
  assert support.finished_ids(support.writes(effects: ended)) == [holder_cast]
    as "opcode.0x7fe: the spell no longer wanted ends with its 0x7fe to the caster"
  assert list.filter_map(support.tells(effects: ended), fn(told) {
      case told.1 {
        client_connection.CastFinished(cast_id:) -> Ok(#(told.0, cast_id))
        _ -> Error(Nil)
      }
    })
    == [#(ConnectionId(2), holder_cast), #(ConnectionId(3), holder_cast)]
    as "and to the audience that was told its start"
  assert support.caster_change_ends(effects: ended)
    == [
      unit_properties.Source(
        cast_id: holder_cast,
        effect_id: support.standing_modifier_id(spell4_id: first),
      ),
    ]
    as "the CasterChangeEnds takes its until-removed modifier off"
  assert dict.size(state.procs) == 0 as "its Proc row is gone"
  assert cast_state.timers_in_order(cast: state) == []
    as "and its pending child's timer"
  assert list.contains(support.cancelled_timers(effects: ended), child_timer)
    as "is cancelled, not left to fire"
  assert dict.keys(state.lingering) == [kept_cast]
    as "the other standing spell keeps its cast"
  // A spell whose cast is still live, before its go.
  let live_spell =
    spell_plan.Spell(..support.standing_spell(third), cast_time_ms: 1000)
  let #(state, started) =
    standing(cast: state, caster:, wanted: [kept, live_spell], at: 3000)
  let assert [live_cast] = started_ids(effects: started)
  let assert [#(go_timer, 1000)] = support.started_timers(effects: started)
    as "the setup: the go waits the cast time, so the cast is live"
  assert dict.has_key(state.casts, live_cast)
  let #(state, stopped) =
    cast.standing_changed(
      cast: state,
      caster:,
      wanted: [kept],
      now: support.at(ms: 3500),
    )
  assert support.finished_ids(support.writes(effects: stopped)) == [live_cast]
    as "a live cast no longer wanted ends with its 0x7fe"
  assert list.contains(support.cancelled_timers(effects: stopped), go_timer)
    as "its go timer is cancelled"
  assert support.caster_change_starts(effects: stopped) == []
    as "and nothing is applied"
  assert !dict.has_key(state.casts, live_cast)
    as "the cast is no longer live, and no later cast takes it for a standing one"
  assert dict.values(state.standing) == [second]
}
