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
//// - The tests' tables: Paralytic Surge 42352, the Medic's bag index 2, holds a planted
////   Stealth effect (`character_tables.shared_with_stealth`), so a press enters stealth.
//// - The server's choices, in the viewers and cast modules: the order of a blow is the
////   health's news, the damage taken, then the death; the stealth change is the last of
////   the input that moved it; creatures' sight of a stealthed player is left as it was.

import character_tables
import connection_rule_support
import game_connection_support as support
import genesis_prime/client_connection.{
  type News, type Request, Appeared, FromMap, FromStore, PeerNews, SentByPeer,
  Stealth,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/strike_tell
import genesis_prime/message/combat_log
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_log_stealth.{CombatLogStealth}
import genesis_prime/message/unit_stealth.{UnitStealth}
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/store.{Character, ForSelect, Listed}
import genesis_prime/table/id.{ClassId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map.{Left, SeenBy}
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_test
import spawn_support

// ---- the owner ----

/// The Medic of the tests' tables in the world, seen by the connections `viewers`.
fn medic_in_world(
  tables tables: table_store.Tables,
  viewers viewers: List(Int),
) -> game_connection.State {
  let fresh = support.accepted(Settings(..support.settings(), tables:)).0
  let #(state, _) =
    support.entered_saved(
      in_character_select: support.in_select_from(fresh),
      character: Character(..support.world_character(), class_id: ClassId(4)),
      saved_health: None,
    )
  support.watched_by(state:, viewers:)
}

/// A press of Paralytic Surge by a Medic whose spell holds the planted Stealth effect,
/// seen by the connections 2 and 3.
fn stealthed() -> #(game_connection.State, ConnectionStep(Request)) {
  stealthed_in(tables: character_tables.shared_with_stealth())
}

/// The same with the tables given, whose Stealth effect may be kept on damage.
fn stealthed_in(
  tables tables: table_store.Tables,
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.press_paralytic_surge(
    state: medic_in_world(tables:, viewers: [2, 3]),
    client_cast_id: 1,
  )
}

fn written(taken taken: ConnectionStep(Request)) -> List(Frame) {
  support.heard(taken, support.keyed())
}

fn ids(frames frames: List(Frame)) -> List(Int) {
  list.map(frames, fn(frame) { frame.message_id })
}

/// The news a step tells the viewer connection `viewer` about the player's unit.
fn news_told(
  taken taken: ConnectionStep(Request),
  viewer viewer: Int,
) -> List(News) {
  list.filter_map(support.peer_tells(taken), fn(tell) {
    case tell.0 == viewer {
      True -> Ok({ tell.1 }.news)
      False -> Error(Nil)
    }
  })
}

/// The ids of the frames written, kept to the ones named, in order.
fn only(frames frames: List(Frame), ids wanted: List(Int)) -> List(Int) {
  list.filter(ids(frames:), fn(id) { list.contains(wanted, id) })
}

pub fn a_press_that_makes_the_stealth_writes_0x8f5_to_the_player_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, taken) = stealthed()
  let frames = written(taken:)
  assert only(frames:, ids: [0x08F5]) == [0x08F5]
    as "one 0x8f5 goes to the player's own client (opcode.0x8f5)"
  let assert [stealth] =
    list.filter(frames, fn(frame) { frame.message_id == 0x08F5 })
  assert unit_stealth.decode(stealth.body)
    == Ok(UnitStealth(unit_id: support.own_unit_id, stealthed: 1))
  let at = fn(id) {
    let assert Ok(found) =
      list.index_map(ids(frames:), fn(found, index) { #(found, index) })
      |> list.find(fn(entry) { entry.0 == id })
      as "the message is written"
    found.1
  }
  assert at(0x07F4) < at(0x08F5)
    as "the 0x8f5 follows the go that made the stealth"
  assert only(frames:, ids: [0x0247, 0x093A]) == []
    as "no combat log entry (the client logs its own change) and no property (the client slows a stealthed player itself, unit.stealth_look)"
  list.each([2, 3], fn(viewer) {
    assert list.contains(news_told(taken:, viewer:), Stealth(stealthed: True))
      as "each viewer is told"
  })
}

/// What the connection tells the map when its player's stealth changes to `stealthed`:
/// a tell to the run of the player's map, for the player's connection.
fn the_map_told(
  stealthed stealthed: Bool,
) -> step.Effect(step.ConnectionEffect(Request)) {
  step.OwnEffect(step.Tell(
    to: step.Map(map: support.camp_map(), incarnation: support.incarnation),
    request: client_connection.TellStealthChanged(
      connection: step.ConnectionId(1),
      stealthed:,
    ),
  ))
}

/// The step's effects after the tell to the map that its stealth change makes: none
/// writes to the client or tells a viewer.
fn writes_or_viewer_tells_after_the_map_tell(
  taken taken: ConnectionStep(Request),
) -> List(step.Effect(step.ConnectionEffect(Request))) {
  connection_rule_support.effects_of(taken)
  |> list.drop_while(fn(effect) {
    case effect {
      step.OwnEffect(step.Tell(to: step.Map(..), ..)) -> False
      step.OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> True
    }
  })
  |> list.drop(1)
  |> list.filter(fn(effect) {
    case effect {
      step.OwnEffect(step.Write(..))
      | step.OwnEffect(step.Tell(to: step.Connection(..), ..)) -> True
      step.OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> False
    }
  })
}

pub fn the_cast_rules_stealth_changed_tells_the_map_after_the_0x8f5_and_the_viewers_news_once_for_entering_and_once_for_leaving_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, entering) = stealthed()
  assert support.told_the_map(entering) == [the_map_told(stealthed: True)]
    as "the toggle press that enters stealth tells the run of the player's map once: Jim's decision on issue 483, so no creature aggroes a stealthed player it is not fighting"
  assert writes_or_viewer_tells_after_the_map_tell(taken: entering) == []
    as "after the 0x8f5 to the player and the viewers' news: the tell is the stealth change's last effect"
  list.each([2, 3], fn(viewer) {
    assert list.contains(news_told(taken: entering, viewer:), Stealth(True))
      as "each viewer is told too (Spell4Effects.effectType.83, opcode.0x8f5)"
  })
  let #(_, leaving) = support.press_paralytic_surge(state:, client_cast_id: 2)
  assert support.told_the_map(leaving) == [the_map_told(stealthed: False)]
    as "the second press ends the stealth (Spell4.46073): one tell, False"
  assert writes_or_viewer_tells_after_the_map_tell(taken: leaving) == []
  let blow = struck_while_stealthed()
  assert support.told_the_map(blow) == [the_map_told(stealthed: False)]
    as "a landed blow on a stealth that ends on damage taken (Spell4Effects.effectType.83, 83834: dataBits02 0) tells the map False once"
  assert writes_or_viewer_tells_after_the_map_tell(taken: blow) == []
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
  let frames = written(taken:)
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
    ] = news_told(taken:, viewer:)
      as "each viewer is told the blow's shield and health (0x938 and 0x937), the stealth cast taken off (0x811) and then the stealth"
  })
}

pub fn a_blow_does_not_end_a_stealth_kept_on_damage_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) =
    stealthed_in(tables: character_tables.shared_with_kept_stealth())
  let taken = support.feed(state, support.a_beast_strike(support.own_unit_id)).1
  assert only(frames: written(taken:), ids: [0x092F, 0x0811, 0x08F5])
    == [0x092F]
    as "the blow's health is written and the kept stealth holds (Spell4Effects.effectType.83: dataBits02 1)"
  list.each([2, 3], fn(viewer) {
    assert !list.contains(news_told(taken:, viewer:), Stealth(stealthed: False))
  })
}

// ---- a go that ends the stealth ----

pub fn a_go_that_ends_the_stealth_writes_0x811_then_0x8f5_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  // The second press of Paralytic Surge: its Stealth effect is behind 7050, not
  // stealthed, so it adds no source, and the spell's stealth change 0 ends the one held.
  let #(state, _) = stealthed()
  let #(_, taken) = support.press_paralytic_surge(state:, client_cast_id: 2)
  let frames = written(taken:)
  assert only(frames:, ids: [0x0811, 0x08F5]) == [0x0811, 0x08F5]
    as "the stealth cast taken off, then the change"
  let assert [stealth] =
    list.filter(frames, fn(frame) { frame.message_id == 0x08F5 })
  assert unit_stealth.decode(stealth.body)
    == Ok(UnitStealth(unit_id: support.own_unit_id, stealthed: 0))
  list.each([2, 3], fn(viewer) {
    assert list.last(news_told(taken:, viewer:))
      == Ok(Stealth(stealthed: False))
      as "each viewer is told the change last"
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
  assert only(frames: written(taken:), ids: [0x0811, 0x08F5]) == []
    as "a blow that lowers neither health nor shield takes no damage"
  list.each([2, 3], fn(viewer) {
    assert !list.contains(news_told(taken:, viewer:), Stealth(stealthed: False))
  })
}

pub fn a_lethal_blow_ends_the_stealth_before_the_death_is_written_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = stealthed()
  let taken = support.killed(state).1
  assert only(frames: written(taken:), ids: [0x0811, 0x08F5, 0x088C, 0x0247])
    == [0x0811, 0x08F5, 0x088C, 0x0247]
    as "the stealth cast off, the change, then the death 0x88c and its log 0x247 of type 22"
}

pub fn a_death_while_stealthed_by_a_kept_on_damage_source_ends_the_casts_then_the_stealth_before_the_log_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) =
    stealthed_in(tables: character_tables.shared_with_kept_stealth())
  let taken = support.killed(state).1
  assert only(frames: written(taken:), ids: [0x07FE, 0x08F5, 0x0247])
    == [0x07FE, 0x08F5, 0x0247]
    as "the stealth cast's 0x7fe, then 0x8f5, then the death's log entry of type 22"
}

// ---- a viewer ----

/// The state of a viewer that shows the unit 9, and the news of that unit.
fn viewer_showing_unit_9() -> game_connection.State {
  support.feed(support.in_world(), support.event_of(support.Appears)).0
}

fn news_of(
  unit_id unit_id: Int,
  news news: News,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  support.for_stay(support.own_stay(), SentByPeer(PeerNews(unit_id:, news:)))
}

pub fn a_shown_units_stealth_news_is_written_as_0x8f5_then_0x247_of_type_24_test() -> Nil {
  use <- owned_test.run(10_000)
  let shown = viewer_showing_unit_9()
  let #(_, entering) =
    support.feed(shown, news_of(unit_id: 9, news: Stealth(stealthed: True)))
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
    support.feed(shown, news_of(unit_id: 9, news: Stealth(stealthed: False)))
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
      viewer_showing_unit_9(),
      news_of(unit_id: 77, news: Stealth(stealthed: True)),
    )
  assert connection_rule_support.writes(taken) == []
    as "the client holds no unit 77"
  let #(_, early) =
    support.feed(
      support.in_world(),
      news_of(unit_id: 9, news: Stealth(stealthed: True)),
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
    support.feed(state, news_of(unit_id: 9, news: Stealth(stealthed: True)))
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
    assert only(frames: written(taken:), ids: [0x0811, 0x08F5]) == []
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
