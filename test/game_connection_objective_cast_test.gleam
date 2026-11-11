//// The cast-a-spell objective (`QuestObjective.type.11`) on a running game connection: the
//// objective's spell is given to the client as a button, a press casts it on the caster, or on
//// the unit the press names when the spell takes a target, and the go counts it. Expected
//// values come from these places, and never from the helpers that
//// build the input.
//// - `opcode.0x176`: a spell shortcut is the spell (18 bits), the kind (3 bits, 2 for an
////   objective), the objective's id (32) and an add bit (1 add, 0 remove), written by the
////   widths of the client's reader (`message_support.packed`), not by our codec.
//// - `opcode.0x361` and `opcode.0x35c`: quest id (15 bits), objective index (32) and progress
////   (32); quest id (15), state (32) and objective id (32), state 1 Accepted and 2 Achieved.
//// - `opcode.0x9d`: a press is the client's cast id, the Spell4 id, a target (0 for none) and
////   a position, as three floats; `opcode.0x9d.answers`: it takes the answers of a 0x9a cast.
//// - `opcode.0x7fc`: the answer to a press of a spell the client holds no button for is the
////   client cast id, the Spell4 id and result 1 (`0x14039b340`, `UnableToCreateSpell`).
//// - `QuestObjective.type.11.rows`: quest 7618's only objective, 13884, is type 11 with data
////   40471 (Spell4 40471: castTime 0, spellCoolDown 10000) and count 1, so the first go
////   finishes the quest. The quest names preq_level 8 and preq_quest0 7617 and has no giver in
////   the tests' world, so the test of the accept sets the one flag bit it needs, 0x4 (the
////   communicator call, `Quest2.flags`, which the row leaves 0), as the tests of a communicator
////   quest do. The row's other requirements are met by the character: level 8, an Exile
////   (`Quest2.questPlayerFactionEnum` 0, Faction2 167) and the quest 7617 completed.
//// - The order of the go's frames: the quest's 0x361 and 0x35c come before the 0x176 remove, as
////   for any other counted objective; the client's remove (`0x1403b9fb0`) needs only the
////   objective's id. Spell 40471 holds a node with life after its go, so its 0x7fe comes at
////   the node's end, after those frames; a spell that finishes at its go writes the 0x7fe
////   before the count (`cast_shortcut_test`).

import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Answer, type Message}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/cast_objective_ability.{CastObjectiveAbility}
import genesis_prime/message/cast_result
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/quest_abandon.{QuestAbandon}
import genesis_prime/message/quest_accept.{QuestAccept}
import genesis_prime/message/spell_cast_refused
import genesis_prime/step.{type ConnectionEvent, type Event, OwnEvent}
import genesis_prime/store.{Character}
import genesis_prime/world_map/creature_life.{Hostile}
import gleam/list
import message_support
import owned_test
import planted_table.{Integer}
import quest_support
import vendor_support

const quest = 7618

const objective = 13_884

const spell = 40_471

/// A shortcut message of the client's reader for the quest's objective.
fn shortcut_frame(add add: Int) -> #(Int, BitArray) {
  #(
    0x0176,
    message_support.packed([#(18, spell), #(3, 2), #(32, objective), #(1, add)]),
  )
}

/// A 0x35c of the client's reader with objective id 0.
fn state_frame(state state: Int) -> #(Int, BitArray) {
  #(0x035C, message_support.packed([#(15, quest), #(32, state), #(32, 0)]))
}

/// A 0x361 of the client's reader for the quest's only objective.
fn progress_frame(progress progress: Int) -> #(Int, BitArray) {
  #(0x0361, message_support.packed([#(15, quest), #(32, 0), #(32, progress)]))
}

/// The frames of the quest and its button, in the order written.
fn quest_frames(frames frames: List(Frame)) -> List(#(Int, BitArray)) {
  list.map(frames, fn(frame) { #(frame.message_id, frame.body) })
  |> list.filter(fn(pair) { list.contains([0x035C, 0x0361, 0x0176], pair.0) })
}

/// The client's 0x9d press of the spell, inside the client's 0x038C, with no target and a
/// position of 0.
fn press(client_cast_id client_cast_id: Int) -> BitArray {
  let assert Ok(body) =
    cast_objective_ability.encode(CastObjectiveAbility(
      client_cast_id:,
      spell4_id: spell,
      target_unit_id: 0,
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  connection_support.world_message(
    message_id: cast_objective_ability.message_id,
    body:,
  )
}

/// The dialog's accept of the quest: location 300 and bag index -1 (`opcode.0x35b`).
fn accept() -> BitArray {
  let assert Ok(body) =
    quest_accept.encode(QuestAccept(
      item: ItemPlace(location: 300, bag_index: 4_294_967_295),
      quest_id: quest,
    ))
    as "the dialog's accept fits the message"
  connection_support.world_message(message_id: quest_accept.message_id, body:)
}

pub fn accepting_a_cast_objective_quest_sends_its_button_after_the_state_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- fixture_tables.changed(table: "Quest2", id: quest, with: [
    #("flags", Integer(0x4)),
  ])
  let #(state, _) =
    connection_support.entered_as_with_quests_on(
      tables:,
      character: Character(
        ..connection_support.world_character(),
        level: 8,
        faction_id: 167,
      ),
      quests: [
        quest_support.completed(quest_id: 7617, at: 1000),
        quest_support.known(quest, 5),
      ],
    )
  let #(_, taken) = connection_support.read(state, accept())
  assert quest_frames(frames: connection_support.written(taken:))
    == [state_frame(state: 1), shortcut_frame(add: 1)]
    as "opcode.0x35c 1 for the accept, then opcode.0x176 {40471, kind 2, objective 13884, add}: the button comes after the quest's state"
}

pub fn a_shortcut_cast_counts_and_takes_the_button_away_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    connection_support.entered_with_quests(quests: [
      quest_support.accepted(quest_id: quest, progress: [0]),
    ])
  let #(state, started) =
    connection_support.at(
      state:,
      ms: 0,
      event: OwnEvent(step.Read(press(client_cast_id: 7))),
    )
  let #(state, steps) =
    connection_support.casts_run(
      state:,
      pending: connection_support.cast_timers(steps: [started], ms: 0),
      until_ms: 20_000,
      steps: [started],
    )
  let frames =
    list.flat_map(steps, fn(taken) { connection_support.written(taken:) })
  assert list.take(list.map(frames, fn(frame) { frame.message_id }), 1)
    == [0x07FD]
    as "opcode.0x7fd: the press is confirmed first, as a 0x9a press is"
  assert quest_frames(frames:)
    == [
      progress_frame(progress: 1),
      state_frame(state: 2),
      shortcut_frame(add: 0),
    ]
    as "opcode.0x361 {7618, 0, 1} at the go, 0x35c 2 for the finished quest, then opcode.0x176 {40471, 2, 13884, remove}"
  assert list.filter(frames, fn(frame) {
      list.contains([0x07FE, 0x0361], frame.message_id)
    })
    |> list.map(fn(frame) { frame.message_id })
    == [0x0361, 0x07FE]
    as "the go counts the objective at once; the cast's finish 0x7fe waits for the node of spell 40471 to end"
  let #(_, again) =
    connection_support.at(
      state:,
      ms: 20_001,
      event: OwnEvent(step.Read(press(client_cast_id: 8))),
    )
  let assert [frame] = connection_support.written(taken: again)
    as "a press after the button is gone writes one frame"
  let assert Ok(refused) = spell_cast_refused.decode(frame.body)
  assert frame.message_id == 0x07FC
    && refused.client_cast_id == 8
    && refused.spell4_id == spell
    && cast_result.to_value(refused.result) == 1
    as "opcode.0x7fc {8, 40471, 1}: the closed objective's button is gone, and the client's own refusal of a spell it holds no button for is result 1 (0x14039b340)"
}

/// The 0x9d press of this spell at this unit, inside the client's 0x038C, at a position
/// of 0.
fn press_at(
  spell4_id spell4_id: Int,
  unit_id unit_id: Int,
  client_cast_id client_cast_id: Int,
) -> BitArray {
  let assert Ok(body) =
    cast_objective_ability.encode(CastObjectiveAbility(
      client_cast_id:,
      spell4_id:,
      target_unit_id: unit_id,
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  connection_support.world_message(
    message_id: cast_objective_ability.message_id,
    body:,
  )
}

/// A creature of the tables' own display and outfit, as unit `unit_id`, 10.0 from the
/// player's edge straight ahead, alive and hostile to nobody (the range of the spells of
/// these tests is 15.0, 15.0 and 30.0).
fn appears_at_ten(
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  display_info_id display_info_id: Int,
  outfit_info_id outfit_info_id: Int,
  hit_radius hit_radius: Float,
) -> Event(ConnectionEvent(Message, Answer)) {
  connection_support.creature_appears(
    unit_id:,
    creature_id:,
    display_info_id:,
    outfit_info_id:,
    hit_radius:,
    place: vendor_support.ahead_of_the_player(hit_radius:, gap: 10.0),
    hostile_to: Hostile(exile: False, dominion: False),
  )
}

/// A player whose log holds this quest with its one objective at 0, shown these units.
fn seeing(
  quest quest: Int,
  events events: List(Event(ConnectionEvent(Message, Answer))),
) -> game_connection.State {
  let #(state, _) =
    connection_support.entered_with_quests(quests: [
      quest_support.accepted(quest_id: quest, progress: [0]),
    ])
  list.fold(events, state, fn(state, event) {
    connection_support.feed(state:, event:).0
  })
}

/// The press at `ms` and the cast's timers up to `until_ms`: the state after and the
/// frames written, as ids and bodies, of the messages these tests look at.
fn pressed_and_run(
  state state: game_connection.State,
  ms ms: Int,
  press press: BitArray,
  until_ms until_ms: Int,
) -> #(game_connection.State, List(#(Int, BitArray))) {
  let #(state, started) =
    connection_support.at(state:, ms:, event: OwnEvent(step.Read(press)))
  let #(state, steps) =
    connection_support.casts_run(
      state:,
      pending: connection_support.cast_timers(steps: [started], ms:),
      until_ms:,
      steps: [started],
    )
  let frames =
    list.flat_map(steps, fn(taken) { connection_support.written(taken:) })
    |> list.map(fn(frame) { #(frame.message_id, frame.body) })
    |> list.filter(fn(pair) {
      list.contains([0x07FD, 0x07F4, 0x07FE, 0x07FC, 0x0361, 0x035C], pair.0)
    })
  #(state, frames)
}

fn ids(frames frames: List(#(Int, BitArray))) -> List(Int) {
  list.map(frames, fn(pair) { pair.0 })
}

/// A 0x361 of the client's reader for the objective at index 0 of this quest.
fn progress_of(quest quest: Int, progress progress: Int) -> #(Int, BitArray) {
  #(0x0361, message_support.packed([#(15, quest), #(32, 0), #(32, progress)]))
}

pub fn a_targeted_press_counts_at_the_go_on_the_unit_it_names_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 8184's objective 15092 is type 11 with data 42735 (castTime 0), count 10, and
  // its reward pane is target group 25705 of Creature2 41604 (display 25705, outfit
  // 9152, hit radius 1.0).
  let state =
    seeing(quest: 8184, events: [
      appears_at_ten(
        unit_id: 40,
        creature_id: 41_604,
        display_info_id: 25_705,
        outfit_info_id: 9152,
        hit_radius: 1.0,
      ),
    ])
  let #(_, frames) =
    pressed_and_run(
      state:,
      ms: 0,
      press: press_at(spell4_id: 42_735, unit_id: 40, client_cast_id: 7),
      until_ms: 5000,
    )
  assert ids(frames:) == [0x07FD, 0x07F4, 0x0361, 0x07FE]
    as "opcode.0x7fd the press, 0x7f4 the cast's start, opcode.0x361 for the go, then 0x7fe at the end of the node Spell4Effects 97459 of the spell holds after its go (the header's order)"
  assert list.contains(frames, progress_of(quest: 8184, progress: 1))
    as "opcode.0x361 {8184, 0, 1}: the unit the press named counts once, of the objective's 10"
}

pub fn a_targeted_cast_whose_unit_dies_before_the_go_counts_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 8935's objective 16055 is type 11 with data 47953 (castTime 3000, target group
  // 7083 of Creature2 49963: display 26384, hit radius 1.0).
  let state =
    seeing(quest: 8935, events: [
      appears_at_ten(
        unit_id: 40,
        creature_id: 49_963,
        display_info_id: 26_384,
        outfit_info_id: 0,
        hit_radius: 1.0,
      ),
    ])
  let #(state, pressed) =
    connection_support.at(
      state:,
      ms: 0,
      event: OwnEvent(
        step.Read(press_at(spell4_id: 47_953, unit_id: 40, client_cast_id: 7)),
      ),
    )
  let #(state, pending, before) =
    connection_support.casts_left(
      state:,
      pending: connection_support.cast_timers(steps: [pressed], ms: 0),
      until_ms: 1000,
      steps: [pressed],
    )
  assert list.contains(
    list.flat_map(before, fn(taken) {
      list.map(connection_support.written(taken:), fn(frame) {
        frame.message_id
      })
    }),
    0x07FD,
  )
    as "opcode.0x7fd: the press is confirmed"
  assert pending != [] as "the cast of 3000 ms is still to go at 1000 ms"
  let #(state, _) =
    connection_support.at(
      state:,
      ms: 1000,
      event: connection_support.news_sent_by_a_peer(
        unit_id: 40,
        news: client_connection.Died,
      ),
    )
  let #(_, after) =
    connection_support.casts_run(state:, pending:, until_ms: 4000, steps: [])
  let frames =
    list.flat_map(after, fn(taken) { connection_support.written(taken:) })
  assert list.filter(frames, fn(frame) { frame.message_id == 0x0361 }) == []
    as "opcode.0x361: the unit is dead at the go (SetUnitDeathState 0x14045e740), so nothing is counted"
}

pub fn a_targeted_press_outside_the_cast_group_writes_89_test() -> Nil {
  use <- owned_test.run(10_000)
  // Creature2 32668 (display 21557, hit radius 1.7) is not in quest 8184's cast group.
  let state =
    seeing(quest: 8184, events: [
      appears_at_ten(
        unit_id: 40,
        creature_id: 32_668,
        display_info_id: 21_557,
        outfit_info_id: 0,
        hit_radius: 1.7,
      ),
    ])
  let #(_, frames) =
    pressed_and_run(
      state:,
      ms: 0,
      press: press_at(spell4_id: 42_735, unit_id: 40, client_cast_id: 7),
      until_ms: 5000,
    )
  let assert [pair] = frames
    as "a press refused by the cast group writes the one 0x7fc"
  let assert Ok(refused) = spell_cast_refused.decode(pair.1)
  assert pair.0 == 0x07FC
    && refused.client_cast_id == 7
    && refused.spell4_id == 42_735
    && cast_result.to_value(refused.result) == 89
    as "opcode.0x7fc {7, 42735, 89}: TargetGroup (CastResult 89), and no opcode.0x361"
}

pub fn a_cast_at_a_cast_group_unit_outside_the_pane_goes_and_counts_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 7757's objective 14295 is type 11 with data 69507; Creature2 58762 (display
  // 22879, hit radius 1.0) is in its cast group and not in its reward pane.
  let state =
    seeing(quest: 7757, events: [
      appears_at_ten(
        unit_id: 40,
        creature_id: 58_762,
        display_info_id: 22_879,
        outfit_info_id: 0,
        hit_radius: 1.0,
      ),
    ])
  let #(_, frames) =
    pressed_and_run(
      state:,
      ms: 0,
      press: press_at(spell4_id: 69_507, unit_id: 40, client_cast_id: 7),
      until_ms: 5000,
    )
  assert ids(frames:) == [0x07FD, 0x07F4, 0x07FE]
    as "opcode.0x7fd, 0x7f4 and 0x7fe: the cast goes, and no opcode.0x361, as the unit is outside the reward pane"
}

pub fn a_second_cast_at_a_counted_unit_goes_and_writes_no_progress_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    seeing(quest: 8184, events: [
      appears_at_ten(
        unit_id: 40,
        creature_id: 41_604,
        display_info_id: 25_705,
        outfit_info_id: 9152,
        hit_radius: 1.0,
      ),
      appears_at_ten(
        unit_id: 41,
        creature_id: 41_604,
        display_info_id: 25_705,
        outfit_info_id: 9152,
        hit_radius: 1.0,
      ),
    ])
  let #(state, first) =
    pressed_and_run(
      state:,
      ms: 0,
      press: press_at(spell4_id: 42_735, unit_id: 40, client_cast_id: 7),
      until_ms: 4999,
    )
  assert ids(frames: first) == [0x07FD, 0x07F4, 0x0361, 0x07FE]
    as "opcode.0x361 for the first unit, as in the first test"
  // Spell4 42735's spellCoolDown is 5000.
  let #(state, second) =
    pressed_and_run(
      state:,
      ms: 5000,
      press: press_at(spell4_id: 42_735, unit_id: 40, client_cast_id: 8),
      until_ms: 9999,
    )
  assert ids(frames: second) == [0x07FD, 0x07F4, 0x07FE]
    as "the cast at the counted unit goes, and writes no opcode.0x361"
  let #(_, third) =
    pressed_and_run(
      state:,
      ms: 10_000,
      press: press_at(spell4_id: 42_735, unit_id: 41, client_cast_id: 9),
      until_ms: 14_999,
    )
  assert list.contains(third, progress_of(quest: 8184, progress: 2))
    as "opcode.0x361 {8184, 0, 2}: a different unit of the group counts"
}

pub fn abandoning_a_quest_takes_its_cast_button_away_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    connection_support.entered_with_quests(quests: [
      quest_support.accepted(quest_id: quest, progress: [0]),
    ])
  let assert Ok(body) = quest_abandon.encode(QuestAbandon(quest_id: quest))
    as "a quest id fits the message"
  let #(_, taken) =
    connection_support.read(
      state,
      connection_support.world_message(
        message_id: quest_abandon.message_id,
        body:,
      ),
    )
  assert list.filter(
      quest_frames(frames: connection_support.written(taken:)),
      fn(pair) { pair.0 == 0x0176 },
    )
    == [shortcut_frame(add: 0)]
    as "opcode.0x176 {40471, 2, 13884, remove}: an abandoned quest's objective is no longer open, so its button goes, and no add is written"
}
