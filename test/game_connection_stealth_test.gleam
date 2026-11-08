//// A player's stealth on the game connection (`genesis_prime/game/connection/casting`,
//// `life`, `viewers` and `frames`): the owner writes 0x8f5 to its own client and tells
//// each viewer `Stealth`, a blow ends the stealth the cast rule holds, a viewer writes
//// 0x8f5 and then 0x247 of type 24 for a unit it shows, and a viewer that first sees a
//// stealthed player is sent its 0x262 with create flag 16. Expected values come from
//// these places:
//// - `opcode.0x8f5`: the unit and the stealthed bit; the client handles it for any unit it
////   knows, its own player's included, and logs the own player's change itself.
//// - `opcode.0x247.type24`: the entry {unit, exiting} is for other players' units, so a
////   viewer is written it and the owner is not (the client makes the owner's own).
//// - `opcode.0x262.unit_fields`: create flag 16 makes the unit stealthed from its creation.
//// - `unit.stealth_look`: the client slows a stealthed player itself, so no speed or
////   property message is sent for the stealth.
//// - The tests' tables: the Stalker's Stealth, Spell4 46073 at bag index 3, starts Stealth
////   38784 (Spell4Effects 107792, behind Prerequisite 7050: not stealthed), whose row 83834
////   is a Stealth effect broken by damage (dataBits02 0), so a press enters stealth. 95774
////   keeps it on damage (dataBits02 1) for a caster that holds Spell4 59389, which the
////   test of the kept stealth gives it by an edit (`with_stealth_kept_on_damage`). A second
////   press starts Stealth Cancel 38783 (107793, behind Prerequisite 8127: stealthed).
//// - The server's choices, in the viewers and cast modules: the order of a blow is the
////   health's news, the damage taken, then the death; the stealth change is the last of
////   the input that moved it; creatures' sight of a stealthed player is left as it was.

import cast_support
import connection_rule_support
import game_connection_support as support
import genesis_prime/client_connection.{
  type Request, Appeared, FromMap, FromStore, PeerNews, Stealth,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/strike_tell
import genesis_prime/message/combat_log
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_log_stealth.{CombatLogStealth}
import genesis_prime/message/spell_finished
import genesis_prime/message/unit_stealth.{UnitStealth}
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/store.{Character, ForSelect, Listed}
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map.{Left, SeenBy}
import gleam/int
import gleam/list
import owned_test
import spawn_support

// ---- the owner ----

/// A press of the Stalker's Stealth, seen by the connections 2 and 3.
fn stealthed() -> #(game_connection.State, ConnectionStep(Request)) {
  support.stealthed_stalker()
}

/// The ids of the frames written, kept to the ones named, in order.
fn only(frames frames: List(Frame), ids wanted: List(Int)) -> List(Int) {
  list.filter(cast_support.ids(frames:), fn(id) { list.contains(wanted, id) })
}

pub fn a_press_that_makes_the_stealth_writes_0x8f5_to_the_player_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, taken) = stealthed()
  let frames = support.written(taken:)
  assert only(frames:, ids: [0x08F5]) == [0x08F5]
    as "one 0x8f5 goes to the player's own client (opcode.0x8f5)"
  let assert [stealth] =
    list.filter(frames, fn(frame) { frame.message_id == 0x08F5 })
  assert unit_stealth.decode(stealth.body)
    == Ok(UnitStealth(unit_id: support.own_unit_id, stealthed: 1))
  let at = fn(id) {
    let assert Ok(found) =
      list.index_map(cast_support.ids(frames:), fn(found, index) {
        #(found, index)
      })
      |> list.find(fn(entry) { entry.0 == id })
      as "the message is written"
    found.1
  }
  assert at(0x07F4) < at(0x08F5)
    as "the 0x8f5 follows the go that made the stealth"
  assert only(frames:, ids: [0x0247, 0x093A]) == []
    as "no combat log entry (the client logs its own change) and no property (the client slows a stealthed player itself, unit.stealth_look)"
  list.each([2, 3], fn(viewer) {
    assert list.contains(
      support.news_told(taken:, viewer:),
      Stealth(stealthed: True),
    )
      as "each viewer is told"
  })
}

/// The step's stealth change is written and told to the viewers before its tell to the
/// map: no 0x8f5 and no stealth news follows the tell. Other casts the real rows start
/// in the same step, such as a trigger of the Stalker's passives, may.
fn assert_the_change_comes_before_the_map_tell(
  taken taken: ConnectionStep(Request),
) -> Nil {
  let #(before, after) = support.written_around_the_map_tell(taken:)
  assert list.contains(cast_support.ids(frames: before), 0x08F5)
    as "the 0x8f5 is written before the tell"
  assert !list.contains(cast_support.ids(frames: after), 0x08F5)
    as "no 0x8f5 follows the tell"
  list.each([2, 3], fn(viewer) {
    assert list.filter(
        support.news_told_after_the_map_tell(taken:, viewer:),
        fn(news) { news == Stealth(True) || news == Stealth(False) },
      )
      == []
      as "no stealth news follows the tell"
  })
}

/// What the connection tells the map when its player's stealth changes to `stealthed`.
fn stealth_told(
  stealthed stealthed: Bool,
) -> step.Effect(step.ConnectionEffect(Request)) {
  support.map_tell(request: client_connection.TellStealthChanged(
    connection: step.ConnectionId(1),
    stealthed:,
  ))
}

pub fn the_cast_rules_stealth_changed_tells_the_map_after_the_0x8f5_and_the_viewers_news_once_for_entering_and_once_for_leaving_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, entering) = stealthed()
  assert support.told_the_map(entering) == [stealth_told(stealthed: True)]
    as "the toggle press that enters stealth tells the run of the player's map once: Jim's decision on issue 483, so no creature aggroes a stealthed player it is not fighting"
  assert_the_change_comes_before_the_map_tell(taken: entering)
  list.each([2, 3], fn(viewer) {
    assert list.contains(
      support.news_told(taken: entering, viewer:),
      Stealth(True),
    )
      as "each viewer is told too (Spell4Effects.effectType.83, opcode.0x8f5)"
  })
  let #(_, leaving) =
    support.press_stealth_again(state:, client_cast_id: 2, ms: 3000)
  assert support.told_the_map(leaving) == [stealth_told(stealthed: False)]
    as "the second press ends the stealth (Spell4.46073, Stealth Cancel 38783): one tell, False"
  assert_the_change_comes_before_the_map_tell(taken: leaving)
  let blow = struck_while_stealthed()
  assert support.told_the_map(blow) == [stealth_told(stealthed: False)]
    as "a landed blow on a stealth that ends on damage taken (Spell4Effects.effectType.83, 83834: dataBits02 0) tells the map False once"
  assert_the_change_comes_before_the_map_tell(taken: blow)
}

pub fn a_camp_while_stealthed_tells_the_map_no_stealth_changed_and_only_the_leave_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = stealthed()
  let #(state, requested) =
    support.read(state:, bytes: support.camp_request_message(True))
  let #(state, finished) =
    support.read(state:, bytes: support.camp_finished_message())
  let #(state, saved) =
    support.answer(state:, taken: finished, outcome: support.place_saved())
  let #(_, left) =
    support.answer(state:, taken: saved, outcome: step.Answer(FromMap(Left)))
  list.each([requested, finished, saved, left], fn(taken) {
    assert support.told_the_map(taken) == []
      as "cast.left clears the stealth with no StealthChanged (#474), so the camp tells the map no stealth"
  })
  assert support.ask_request(saved) == support.leave_asked()
    as "the map gets only the ask of the player's Leave, which removes the player with its stealth copy"
}

// ---- a blow ----

/// A step of a blow on the stealthed player, after the press.
fn struck_while_stealthed() -> ConnectionStep(Request) {
  let #(state, _) = stealthed()
  support.feed(state, support.a_beast_strike(support.own_unit_id)).1
}

pub fn a_landed_blow_writes_the_health_then_0x811_of_the_stealth_cast_then_0x8f5_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  let taken = struck_while_stealthed()
  let frames = support.written(taken:)
  assert only(frames:, ids: [0x092F, 0x0811, 0x08F5])
    == [0x092F, 0x0811, 0x08F5]
    as "the blow's health to the player, then the stealth cast taken off, then the change"
  let assert [stealth] =
    list.filter(frames, fn(frame) { frame.message_id == 0x08F5 })
  assert unit_stealth.decode(stealth.body)
    == Ok(UnitStealth(unit_id: support.own_unit_id, stealthed: 0))
  list.each([2, 3], fn(viewer) {
    let assert [
      client_connection.Shield(..),
      client_connection.Health(dead: False, ..),
      client_connection.CastTargetsRemoved(..),
      Stealth(stealthed: False),
      ..
    ] = support.news_told(taken:, viewer:)
      as "each viewer is told the blow's shield and health (0x938 and 0x937), the stealth cast taken off (0x811) and then the stealth, before the real Stalker's own casts that follow"
  })
}

pub fn a_blow_does_not_end_a_stealth_kept_on_damage_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = support.stealthed_stalker_kept_on_damage()
  let taken = support.feed(state, support.a_beast_strike(support.own_unit_id)).1
  assert only(frames: support.written(taken:), ids: [0x092F, 0x0811, 0x08F5])
    == [0x092F]
    as "the blow's health is written and the kept stealth holds (Spell4Effects.effectType.83: dataBits02 1)"
  list.each([2, 3], fn(viewer) {
    assert !list.contains(
      support.news_told(taken:, viewer:),
      Stealth(stealthed: False),
    )
  })
}

// ---- a go that ends the stealth ----

pub fn a_go_that_ends_the_stealth_writes_0x811_then_0x8f5_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  // The second press of Stealth starts Cancel 38783, which removes the stealth held.
  let #(state, _) = stealthed()
  let #(_, taken) =
    support.press_stealth_again(state:, client_cast_id: 2, ms: 3000)
  let frames = support.written(taken:)
  assert only(frames:, ids: [0x0811, 0x08F5]) == [0x0811, 0x08F5]
    as "the stealth cast taken off, then the change"
  let assert [stealth] =
    list.filter(frames, fn(frame) { frame.message_id == 0x08F5 })
  assert unit_stealth.decode(stealth.body)
    == Ok(UnitStealth(unit_id: support.own_unit_id, stealthed: 0))
  list.each([2, 3], fn(viewer) {
    let assert [client_connection.CastTargetsRemoved(..), Stealth(False)] =
      list.filter(support.news_told(taken:, viewer:), fn(news) {
        support.is_cast_removal(news) || news == Stealth(False)
      })
      as "each viewer is told the stealth cast taken off (0x811), then the change (the casts the real rows start in between are other news)"
  })
}

/// A creature's strike of 0 on the tests' player, a blow that lowers neither its health
/// nor its shield.
fn harmless_strike() -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  support.foe(
    strike_tell.Attacks(
      tell: strike_tell.Strike(
        key: strike_tell.Key(
          cast_id: 2_147_500_002,
          phase: 0,
          unit_id: support.own_unit_id,
        ),
        from: support.fighter(),
        striker: strike_tell.CreatureStriker,
        offence: spawn_support.dealing(
          offence: spawn_support.beast_attack().offence,
          damage: 0,
        ),
        controls: [],
      ),
    ),
  )
}

pub fn a_blow_that_lowers_nothing_keeps_the_stealth_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = stealthed()
  let taken = support.feed(state, harmless_strike()).1
  assert only(frames: support.written(taken:), ids: [0x0811, 0x08F5]) == []
    as "a blow that lowers neither health nor shield takes no damage"
  list.each([2, 3], fn(viewer) {
    assert !list.contains(
      support.news_told(taken:, viewer:),
      Stealth(stealthed: False),
    )
  })
}

pub fn a_lethal_blow_ends_the_stealth_before_the_death_is_written_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = stealthed()
  let taken = support.killed(state).1
  assert only(frames: support.written(taken:), ids: [
      0x0811,
      0x08F5,
      0x088C,
      0x0247,
    ])
    == [0x0811, 0x08F5, 0x088C, 0x0247]
    as "the stealth cast off, the change, then the death 0x88c and its log 0x247 of type 22"
}

pub fn a_death_while_stealthed_by_a_kept_on_damage_source_ends_the_casts_then_the_stealth_before_the_log_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, pressed) = support.stealthed_stalker_kept_on_damage()
  let stealth_cast =
    support.cast_starts(support.news_told(taken: pressed, viewer: 2))
    |> list.filter(fn(started) { started.spell4_id == 38_784 })
    |> list.map(fn(started) { started.cast_id })
  assert list.length(stealth_cast) == 1 as "the press starts Stealth 38784 once"
  let frames = support.written(taken: support.killed(state).1)
  let positions = fn(wanted: Int) {
    list.index_map(cast_support.ids(frames:), fn(id, index) { #(id, index) })
    |> list.filter_map(fn(entry) {
      case entry.0 == wanted {
        True -> Ok(entry.1)
        False -> Error(Nil)
      }
    })
  }
  let finished_at =
    list.index_map(frames, fn(frame, index) { #(frame, index) })
    |> list.filter_map(fn(entry) {
      case
        { entry.0 }.message_id == 0x07FE,
        spell_finished.decode({ entry.0 }.body)
      {
        True, Ok(finished) -> Ok(#(finished.cast_id, entry.1))
        _, _ -> Error(Nil)
      }
    })
  let assert [stealth_cast] = stealth_cast
  let assert Ok(ended) = list.key_find(finished_at, stealth_cast)
    as "the stealth cast is ended at the death"
  let assert [change] = positions(0x08F5)
    as "the kept stealth is ended once, as the death takes it"
  let assert [log] = positions(0x0247)
  assert ended < change && change < log
    as "the stealth cast's 0x7fe, then 0x8f5, then the death's log entry of type 22 (the Stalker's own other casts end around them)"
}

// ---- a viewer ----

pub fn a_shown_units_stealth_news_is_written_as_0x8f5_then_0x247_of_type_24_test() -> Nil {
  use <- owned_test.run(10_000)
  let shown = support.viewer_showing_unit_9()
  let #(_, entering) =
    support.feed(
      shown,
      support.news_sent_by_a_peer(unit_id: 9, news: Stealth(stealthed: True)),
    )
  let assert [first, second] = support.heard(entering, support.keyed())
  assert first.message_id == 0x08F5 && second.message_id == 0x0247
    as "0x8f5 first, then the log entry (opcode.0x8f5, opcode.0x247.type24)"
  assert unit_stealth.decode(first.body)
    == Ok(UnitStealth(unit_id: 9, stealthed: 1))
  assert combat_log.decode(second.body)
    == Ok(
      combat_log.CombatLog(
        entry: combat_log_entry.Stealth(CombatLogStealth(unit_id: 9, exiting: 0)),
      ),
    )
    as "entering is exiting 0"
  let #(_, leaving) =
    support.feed(
      shown,
      support.news_sent_by_a_peer(unit_id: 9, news: Stealth(stealthed: False)),
    )
  let assert [first, second] = support.heard(leaving, support.keyed())
  assert unit_stealth.decode(first.body)
    == Ok(UnitStealth(unit_id: 9, stealthed: 0))
  assert combat_log.decode(second.body)
    == Ok(
      combat_log.CombatLog(
        entry: combat_log_entry.Stealth(CombatLogStealth(unit_id: 9, exiting: 1)),
      ),
    )
    as "leaving is exiting 1"
}

pub fn a_stealth_news_for_a_unit_not_shown_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    support.feed(
      support.viewer_showing_unit_9(),
      support.news_sent_by_a_peer(unit_id: 77, news: Stealth(stealthed: True)),
    )
  assert connection_rule_support.writes(taken) == []
    as "the client holds no unit 77"
  let #(_, early) =
    support.feed(
      support.in_world(),
      support.news_sent_by_a_peer(unit_id: 9, news: Stealth(stealthed: True)),
    )
  assert connection_rule_support.writes(early) == []
    as "a news before the unit's 0x262 finds no unit shown"
}

pub fn the_0x262_and_the_stealth_news_of_one_owner_are_written_in_the_order_they_came_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    support.feed(support.in_world(), support.event_of(support.Appears))
  assert support.written_ids(first) == [0x0262]
  let #(_, second) =
    support.feed(
      state,
      support.news_sent_by_a_peer(unit_id: 9, news: Stealth(stealthed: True)),
    )
  assert support.written_ids(second) == [0x08F5, 0x0247]
}

// ---- a viewer that first sees the player ----

/// The create flags of the 0x262 the player's connection sends the viewer 2 now, for its
/// first stay or, with `second_stay`, its next.
fn create_flags_sent_to_a_new_viewer(
  state state: game_connection.State,
  second_stay second_stay: Bool,
) -> Int {
  let seen =
    support.sent_by_the_map(SeenBy(
      by: step.ConnectionId(2),
      stay: support.viewer_stay(2),
    ))
  let #(_, taken) =
    support.feed(state, case second_stay {
      True -> support.in_second_stay(seen)
      False -> seen
    })
  let assert [#(2, PeerNews(news: Appeared(unit:), ..))] =
    support.peer_tells(taken)
    as "the viewer is sent the player's unit"
  unit.tail.create_flags
}

pub fn a_viewer_that_first_sees_a_stealthed_player_is_sent_the_0x262_with_create_flag_16_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(stealthed_state, _) = stealthed()
  assert int.bitwise_and(
      create_flags_sent_to_a_new_viewer(
        state: stealthed_state,
        second_stay: False,
      ),
      16,
    )
    == 16
    as "create flag 16 makes the unit stealthed from its creation (opcode.0x262.unit_fields)"
  let #(after_a_blow, _) =
    support.feed(stealthed_state, support.a_beast_strike(support.own_unit_id))
  assert int.bitwise_and(
      create_flags_sent_to_a_new_viewer(state: after_a_blow, second_stay: False),
      16,
    )
    == 0
    as "once the stealth has ended a new viewer's 0x262 carries 0"
}

pub fn a_camp_while_stealthed_writes_no_stealth_and_the_next_stay_starts_unstealthed_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = stealthed()
  let #(state, requested) =
    support.read(state:, bytes: support.camp_request_message(True))
  let #(state, finished) =
    support.read(state:, bytes: support.camp_finished_message())
  let #(state, saved) =
    support.answer(state:, taken: finished, outcome: support.place_saved())
  let #(state, left) =
    support.answer(state:, taken: saved, outcome: step.Answer(FromMap(Left)))
  let steps = [requested, finished, saved, left]
  list.each(steps, fn(taken) {
    assert only(frames: support.written(taken:), ids: [0x0811, 0x08F5]) == []
      as "a camp writes no stealth: the viewers' 0x355 removes the unit"
    assert !list.any(support.peer_tells(taken), fn(tell) {
      { tell.1 }.news == Stealth(stealthed: False)
      || { tell.1 }.news == Stealth(stealthed: True)
    })
      as "and tells the viewers no stealth"
  })
  let #(state, listing) = support.read(state:, bytes: support.select_start())
  let #(state, _) =
    support.answer(
      state:,
      taken: listing,
      outcome: step.Answer(FromStore(ForSelect(Listed([])))),
    )
  let #(again, _) =
    support.entered_from(
      in_character_select: state,
      character: Character(..support.world_character(), class_id: ClassId(4)),
    )
  assert int.bitwise_and(
      create_flags_sent_to_a_new_viewer(state: again, second_stay: True),
      16,
    )
    == 0
    as "the next stay starts unstealthed: a new viewer's 0x262 carries flag 0"
}

pub fn the_players_own_0x262_never_carries_the_create_flag_test() -> Nil {
  use <- owned_test.run(60_000)
  let own = support.player_in(support.entered().1)
  assert int.bitwise_and(own.tail.create_flags, 16) == 0
    as "every stay starts unstealthed, so the player's own 0x262 holds no flag 16"
}
