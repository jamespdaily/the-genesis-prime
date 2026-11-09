//// A player's request to talk to a unit on the game connection
//// (`genesis_prime/game/interaction`): the client's 0x7EA, which it sends when the
//// player right-clicks a quest giver, and the server's 0x357, which alone opens
//// the unit's dialog. Expected values come from these places.
//// - `opcode.0x7ea` and `opcode.0x357`: the request is a unit id and a kind, 37
////   (TalkTo) for any quest giver, and the answer is 0x357 with the unit id; unit 0
////   with kind 0x65 is the client's own end of an interaction, and kind 0x31 is a
////   vendor.
//// - `0x14039d5d0`, `0x140554470`, `0x14047a060`: the client sends the request only
////   for a creature that is alive, not Hostile to the player and a quest giver, and opens the
////   dialog only within 6.0 of the creature edge to edge. `opcode.0x7ea` adds 3.0 to a
////   request's range.
//// - `0x1403ad690`: the gap is the distance less both hit radii. The player's is the
////   Race table's hitRadius, 1.2 (0x3f99999a, every playable race); Dorian Walker's is
////   Creature2DisplayInfo 25510's, 1.1 (0x3f8ccccd), the one entry of the display group
////   28097 of Creature2 74812.
//// - Creature2 74812 (Dorian Walker) gives quest 10528 and receives quest 10520;
////   Creature2 73464, the Virtual Battle Beast, gives and receives none.

import connection_rule_support as support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{
  type Answer, type Message, CreatureAppeared,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/start_place
import genesis_prime/message/unit_dialog_open.{UnitDialogOpen}
import genesis_prime/step.{type ConnectionEvent, type Event, LogWarning}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_life.{type Hostile, Hostile}
import genesis_prime/world_map/creature_unit
import gleam/list
import gleam/option.{None}
import owned_test
import planted_table.{Integer}
import spawn_support

/// The edge gap a request is answered up to: 6.0 for a quest kind, plus the 3.0 a
/// request may add (`opcode.0x7ea`).
const reach = 9.0

/// The player's hit radius (Race.hitRadius, 0x3f99999a) and Dorian Walker's
/// (Creature2DisplayInfo 25510's hitRadius, 0x3f8ccccd).
const player_radius = 1.2

const walker_radius = 1.1

const walker_unit = 40

/// A creature that is Hostile to neither player faction.
const friendly = Hostile(exile: False, dominion: False)

/// A creature that is Hostile to both player factions (the client's disposition of
/// the creature toward the player is 0, `0x14045a950`).
const hostile = Hostile(exile: True, dominion: True)

/// The 0x262 news of Dorian Walker, standing `gap` from the player's edge straight
/// ahead of the player, with `health` and `hostile_to`.
fn walker_appears(
  unit_id unit_id: Int,
  gap gap: Float,
  health health: Int,
  hostile_to hostile_to: Hostile,
) -> Event(ConnectionEvent(Message, Answer)) {
  let entry = connection_support.entry_place()
  let place =
    start_place.moved(
      place: entry,
      x: start_place.x(entry),
      y: start_place.y(entry),
      z: start_place.z(entry) -. { gap +. player_radius +. walker_radius },
    )
  let walker = spawn_support.dorian_walker(number: 1, place:)
  connection_support.sent_by_a_peer(connection_support.news_of(
    unit_id:,
    news: CreatureAppeared(
      unit: creature_unit.create(
        spawn: walker,
        unit_id:,
        health:,
        interrupt_armor: None,
        server_time_estimate_start: 0,
      ),
      life: 4,
      place:,
      hit_radius: walker.combat.hit_radius,
      attackable: walker.combat.attackable,
      hostile_to:,
    ),
  ))
}

/// A connection with Dorian Walker in its picture `gap` away, alive.
fn with_walker(gap gap: Float) -> game_connection.State {
  connection_support.feed(
    state: connection_support.in_world(),
    event: walker_appears(
      unit_id: walker_unit,
      gap:,
      health: 52,
      hostile_to: friendly,
    ),
  ).0
}

pub fn talk_to_giver_in_range_opens_dialog_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = with_walker(gap: reach -. 0.1)
  let #(state, taken) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 37,
    )
  let assert [Frame(message_id: 0x0357, body:)] =
    connection_support.written(taken:)
    as "a TalkTo of a giver within 6.0 + 3.0 is answered with 0x357 alone"
  assert unit_dialog_open.decode(body)
    == Ok(UnitDialogOpen(unit_id: walker_unit, field_2: 0))
    as "opcode.0x357: the answer names the unit"
  assert support.logs_of(step: taken, level: LogWarning) == []
  let #(_, again) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 37,
    )
  assert connection_support.written_ids(again) == [0x0357]
    as "a repeated request is answered again: the connection keeps no interaction"
}

/// A giver that does only one of giving and receiving (a row that gives or receives
/// is a quest giver as well), asked for its dialog from 1.0 away.
fn only_one_is_a_giver(tables tables: table_store.Tables) -> Nil {
  let #(_, taken) =
    connection_support.interaction_requested(
      state: connection_support.feed(
        state: connection_support.medic_in(tables:),
        event: walker_appears(
          unit_id: walker_unit,
          gap: 1.0,
          health: 52,
          hostile_to: friendly,
        ),
      ).0,
      unit_id: walker_unit,
      kind: 37,
    )
  assert connection_support.written_ids(taken) == [0x0357]
}

pub fn a_creature_that_only_gives_a_quest_is_a_giver_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- fixture_tables.changed(table: "Creature2", id: 74_812, with: [
    #("questIdReceive00", Integer(0)),
  ])
  only_one_is_a_giver(tables:)
}

pub fn a_creature_that_only_receives_a_quest_is_a_giver_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- fixture_tables.changed(table: "Creature2", id: 74_812, with: [
    #("questIdGiven00", Integer(0)),
  ])
  only_one_is_a_giver(tables:)
}

pub fn talk_to_refused_sends_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each case: what it is, the connection, the request's unit, and the words of its
  // one warning.
  let cases = [
    #("an unseen unit", connection_support.in_world(), 99, "not shown"),
    #(
      "a dead creature",
      connection_support.feed(
        state: connection_support.in_world(),
        event: walker_appears(
          unit_id: walker_unit,
          gap: 1.0,
          health: 0,
          hostile_to: friendly,
        ),
      ).0,
      walker_unit,
      "dead",
    ),
    #(
      "a creature whose row has no quest",
      connection_support.feed(
        state: connection_support.in_world(),
        event: connection_support.beast_appears(unit_id: 41),
      ).0,
      41,
      "no quest",
    ),
    #(
      "a creature that is Hostile to the player",
      connection_support.feed(
        state: connection_support.in_world(),
        event: walker_appears(
          unit_id: walker_unit,
          gap: 1.0,
          health: 52,
          hostile_to: hostile,
        ),
      ).0,
      walker_unit,
      "Hostile",
    ),
    #(
      "a giver beyond the reach",
      with_walker(gap: reach +. 0.1),
      walker_unit,
      "too far",
    ),
    #(
      "another player's unit",
      connection_support.viewer_showing_unit_9(),
      9,
      "not a creature",
    ),
  ]
  use #(what, state, unit_id, words) <- list.each(cases)
  let #(state, first) =
    connection_support.interaction_requested(state:, unit_id:, kind: 37)
  assert connection_support.written_ids(first) == []
    as { what <> " is answered with nothing" }
  let assert [line] = support.logs_of(step: first, level: LogWarning)
    as { what <> " is logged once as a warning" }
  assert support.says(line:, words:) as { what <> " says why: " <> words }
  assert !support.stops(first) as { what <> " leaves the connection up" }
  let #(_, second) =
    connection_support.interaction_requested(state:, unit_id:, kind: 37)
  assert connection_support.written_ids(second) == []
  assert support.logs_of(step: second, level: LogWarning) == []
    as { what <> " is a debug line the second time" }
}

pub fn end_and_dialog_reply_are_accepted_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = with_walker(gap: 1.0)
  // The client's own end of an interaction (opcode.0x7ea), and its 0x356 (opcode.0x356).
  let #(state, ended) =
    connection_support.interaction_requested(state:, unit_id: 0, kind: 0x65)
  assert connection_support.written_ids(ended) == []
  assert support.logs_of(step: ended, level: LogWarning) == []
  let #(state, replied) =
    connection_support.read(
      state:,
      bytes: connection_support.world_message(message_id: 0x0356, body: <<>>),
    )
  assert connection_support.written_ids(replied) == []
  assert support.logs_of(step: replied, level: LogWarning) == []
  // A vendor's kind (0x31) is not taken here: logged once, no reply, the gap named.
  let #(state, vendor) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 0x31,
    )
  assert connection_support.written_ids(vendor) == []
  let assert [line] = support.logs_of(step: vendor, level: LogWarning)
    as "an interaction kind no step takes is logged once"
  assert support.says(line:, words: "#582")
    as "the gap names the issue that will close it"
  let #(_, again) =
    connection_support.interaction_requested(
      state:,
      unit_id: walker_unit,
      kind: 0x31,
    )
  assert support.logs_of(step: again, level: LogWarning) == []
}
