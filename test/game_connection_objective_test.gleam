//// The talk-to and use objectives on a running game connection: the player's right-click
//// of a creature that an open objective of its log names counts toward the objective and
//// the client is told. Expected values come from these places.
//// - `opcode.0x7ea` and `opcode.0x357`: a talk is the client's 0x7ea (unit, kind 37),
////   answered by 0x357, and the client sends nothing later for the talk.
//// - `opcode.0x361`: quest id (15 bits), objective index (32) and progress (32), written
////   by the widths of the client's reader (`message_support.packed`), not by our codec.
//// - `opcode.0x35c`: quest id (15), state (32) and objective id (32); state 2 is
////   Achieved, and objective id 0 leaves the quest's objectives as they are.
//// - `opcode.0x97`, `opcode.0x7fd`, `opcode.0x7f4` and `opcode.0x7fe`: a use is the client's
////   0x97, answered by the start of the cast; its go and finish come after the cast time of
////   the creature's activate spell, and the use is complete at the go.
//// - `opcode.0x801`: a cancel before the go ends the cast, and the use never happened.
//// - `opcode.0x1ac`: the kill's experience, written before its objective progress (the
////   order is this step's design choice, as for talks); the kill's amount, 5 for a level 1
////   player and the level 1 Beast (Creature2 73464), is `experience_flow_test`'s evidence.
//// - A credit told for another stay of the player is dropped (the stay rule of
////   `experience_flow_test`), so it counts for no objective either.
////
//// The client's rows in the fixture, each objective count 1 (`table_rows -- QuestObjective`):
//// - quest 6961's only objective, 12889, is type 3 for Creature2 57050, so a talk to that
////   creature finishes the quest.
//// - quest 3668's objective 0, 4744, is type 3 for Creature2 12484, and its objectives 1 and 2
////   (types 5 and 8) are not talks, so a talk to that creature leaves the quest Accepted.
//// - quest 1857's only objective, 1961, is type 2 for Creature2 5006 with count 1; pointed
////   at the Beast (Creature2 73464) by its data, the Beast's kill finishes the quest. No
////   real quest names a creature the tests' player kills at level 1.
//// - quest 9207's only objective, 17932, is type 12 for Creature2 58487, whose activate spell
////   is Spell4 1817, cast time 2000 ms (Creature2.58487 activateSpellCastTime) and maximum
////   range 1.0 (activateSpellMaxRange). Its display 24340 has hitRadius 3.5; the player's
////   Race hitRadius is 1.2, so a creature 5.0 east is 5.0 - 1.2 - 3.5 = 0.3 away.
////
//// The collect, visit and collectible objectives, from these places.
//// - `QuestObjective.type.4.progress`: the client counts nothing for them and takes the
////   server's 0x361 value, so a destroy that lowers the held count sends 0x361 and, when
////   a finished quest is no longer done, 0x35c 1. The inventory rule refuses a move to
////   the bank, so only the destroy half of a count going down is driven through the
////   connection; `objective_test` covers the rest on the rule.
//// - `opcode.0x111` and `opcode.0xbe`: a buy of Item2 14838 at Dorian Walker (stock
////   position 2) tells the new stack, then the counts. Quest 1854's objective 1959 names
////   item 3993, which the Item2 table lacks, so these tests point its data at 14838.
//// - `Prerequisite.prerequisiteTypeId.26`: a visit counts when the player's zone or a
////   parent of it is the objective's zone, and the player enters the world in zone 6009
////   (`WorldLocation2` 51596), which objective 1965 is changed to name.
//// - `QuestObjective.type.32.sources`: a use of Creature2 12919 (quest 3741, objective
////   0, VirtualItem 363) counts one; a guess, graded so.

import cast_support
import experience_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Answer, type Message, type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/start_place
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/cast_result
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/item_delete
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/quest_accept.{QuestAccept}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/step.{type ConnectionEvent, type Event, OwnEvent}
import genesis_prime/store.{HeldItem}
import genesis_prime/table/id.{Creature2Id, Item2Id}
import genesis_prime/world_map/creature_life.{Attackable, Combat, Hostile}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map.{ObjectsSeen}
import genesis_prime/world_map/spawn.{Spawn}
import genesis_prime/world_map/static_object.{StaticObject}
import gleam/list
import gleam/option.{None}
import message_support
import owned_test
import planted_table.{Integer}
import quest_support
import spawn_support
import vendor_support

const unit = 40

const client_cast_id = 9

/// The edge gap a talk is within the reach of (`opcode.0x7ea`) is far above this one.
const talk_gap = 1.0

/// The 0x262 news of a creature of the given rows as unit 40, standing `talk_gap` from
/// the player's edge straight ahead of the player, alive and hostile to nobody. The
/// creature's number, health and the rest of its spawn are Dorian Walker's, whom the
/// tests of a talk already use; the identity the client's marking reads (creature id,
/// display, outfit and hit radius) is the creature's own.
fn appears(
  creature_id creature_id: Int,
  display_info_id display_info_id: Int,
  outfit_info_id outfit_info_id: Int,
  hit_radius hit_radius: Float,
) -> Event(ConnectionEvent(Message, Answer)) {
  let entry = connection_support.entry_place()
  let place =
    start_place.moved(
      place: entry,
      x: start_place.x(entry),
      y: start_place.y(entry),
      z: start_place.z(entry)
        -. { talk_gap +. vendor_support.player_radius +. hit_radius },
    )
  let walker = spawn_support.dorian_walker(number: 1, place:)
  let target =
    Spawn(
      ..walker,
      creature_id: Creature2Id(creature_id),
      display_info_id:,
      outfit_info_id:,
      combat: Combat(
        ..walker.combat,
        hit_radius:,
        attackable: Attackable(exile: False, dominion: False),
        hostile_to: Hostile(exile: False, dominion: False),
      ),
    )
  connection_support.sent_by_a_peer(connection_support.news_of(
    unit_id: unit,
    news: client_connection.CreatureAppeared(
      unit: creature_unit.create(
        spawn: target,
        unit_id: unit,
        health: 52,
        interrupt_armor: None,
        server_time_estimate_start: 0,
      ),
      life: 4,
      place:,
      hit_radius:,
      attackable: target.combat.attackable,
      hostile_to: target.combat.hostile_to,
    ),
  ))
}

/// The ids and bodies the step writes to the client, in order.
fn frames(taken taken: step.ConnectionStep(Request)) -> List(Frame) {
  connection_support.written(taken:)
}

/// A 0x361 of the client's reader.
fn progress_frame(
  quest quest: Int,
  index index: Int,
  progress progress: Int,
) -> #(Int, BitArray) {
  #(
    0x0361,
    message_support.packed([#(15, quest), #(32, index), #(32, progress)]),
  )
}

/// A 0x35c of the client's reader with objective id 0.
fn state_frame(quest quest: Int, state state: Int) -> #(Int, BitArray) {
  #(0x035C, message_support.packed([#(15, quest), #(32, state), #(32, 0)]))
}

fn as_pairs(frames frames: List(Frame)) -> List(#(Int, BitArray)) {
  list.map(frames, fn(frame) { #(frame.message_id, frame.body) })
}

pub fn talking_to_a_target_sends_its_dialog_progress_and_achieved_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 6961 (objective 12889, type 3, Creature2 57050): the talk is its last open
  // objective, so 0x357 is followed by 0x361 and 0x35c state 2.
  let #(state, _) =
    connection_support.entered_with_quests(quests: [
      quest_support.accepted(quest_id: 6961, progress: [0]),
    ])
  let state =
    connection_support.feed(
      state:,
      event: appears(
        creature_id: 57_050,
        display_info_id: 27_879,
        outfit_info_id: 9074,
        hit_radius: 1.2,
      ),
    ).0
  let #(state, talked) =
    connection_support.interaction_requested(state:, unit_id: unit, kind: 37)
  let written = as_pairs(frames: frames(taken: talked))
  let assert [dialog, progress, achieved] = written
    as "a talk that finishes a quest writes 0x357, then 0x361, then 0x35c"
  assert dialog.0 == 0x0357
    as "opcode.0x357: the dialog opens first, as for any talk"
  assert progress == progress_frame(quest: 6961, index: 0, progress: 1)
    as "opcode.0x361: objective 0 of quest 6961 is at 1 of 1"
  assert achieved == state_frame(quest: 6961, state: 2)
    as "opcode.0x35c: the last open objective is done, so the quest is Achieved"
  let #(_, again) =
    connection_support.interaction_requested(state:, unit_id: unit, kind: 37)
  assert connection_support.written_ids(again) == []
    as "a second talk to the same creature opens no dialog the client would show: it holds no open objective naming the creature and no quest of its own, so the request is declined and logged"

  // Quest 3668 (objective 4744, type 3, Creature2 12484): objectives 1 and 2 stay open.
  let #(partial, _) =
    connection_support.entered_with_quests(quests: [
      quest_support.accepted(quest_id: 3668, progress: [0, 0, 0]),
    ])
  let partial =
    connection_support.feed(
      state: partial,
      event: appears(
        creature_id: 12_484,
        display_info_id: 27_273,
        outfit_info_id: 0,
        hit_radius: 1.0,
      ),
    ).0
  let #(_, talked) =
    connection_support.interaction_requested(
      state: partial,
      unit_id: unit,
      kind: 37,
    )
  let assert [dialog, progress] = as_pairs(frames: frames(taken: talked))
    as "a talk that leaves the quest open writes 0x357 and 0x361 and no 0x35c"
  assert dialog.0 == 0x0357
  assert progress == progress_frame(quest: 3668, index: 0, progress: 1)
    as "opcode.0x361: objective 0 of quest 3668 is at 1 of 1"
}

/// The connection of a player whose log holds quest 9207 (objective 17932, type 12,
/// Creature2 58487), which sees Creature2 58487 as unit 40, 5.0 east of the player.
fn seeing_the_use_target() -> game_connection.State {
  seeing_a_use_target(quest: 9207, creature_id: 58_487, display_info_id: 24_340)
}

/// The connection of a player whose log holds this quest, accepted with one objective
/// open, which sees this creature as unit 40, 5.0 east of the player.
fn seeing_a_use_target(
  quest quest: Int,
  creature_id creature_id: Int,
  display_info_id display_info_id: Int,
) -> game_connection.State {
  let #(state, _) =
    connection_support.entered_with_quests(quests: [
      quest_support.accepted(quest_id: quest, progress: [0]),
    ])
  let place =
    connection_support.standing_at(
      x: 29.128599166870117 +. 5.0,
      y: -853.87158203125,
      z: -560.18798828125,
    )
  connection_support.feed(
    state:,
    event: connection_support.sent_by_the_map(
      ObjectsSeen(units: [
        static_object.create(
          object: StaticObject(
            ..spawn_support.holoring(number: unit, place:),
            creature_id: Creature2Id(creature_id),
            display_info_id:,
          ),
          unit_id: unit,
          server_time_estimate_start: 0,
        ),
      ]),
    ),
  ).0
}

/// The client's 0x97 right-click of the unit, inside the client's 0x038C.
fn right_click() -> BitArray {
  let assert Ok(body) =
    cast_activate.encode(CastActivate(client_cast_id:, target_unit_id: unit))
    as "the message fits"
  connection_support.world_message(message_id: cast_activate.message_id, body:)
}

fn ids_of(steps steps: List(step.ConnectionStep(Request))) -> List(Int) {
  list.flat_map(steps, fn(taken) { connection_support.written_ids(taken) })
}

pub fn using_a_target_sends_progress_after_the_activate_go_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, started) =
    connection_support.at(
      state: seeing_the_use_target(),
      ms: 0,
      event: OwnEvent(step.Read(right_click())),
    )
  assert connection_support.written_ids(started) == [0x07FD]
    as "opcode.0x7fd: the cast starts, and the right-click alone counts nothing"
  let #(state, pending, before) =
    connection_support.casts_left(
      state:,
      pending: connection_support.cast_timers(steps: [started], ms: 0),
      until_ms: 1999,
      steps: [],
    )
  assert ids_of(steps: before) == []
    as "Creature2.58487 activateSpellCastTime 2000: 1 ms before the go nothing is written, 0x361 included"
  let #(_, go) =
    connection_support.casts_run(state:, pending:, until_ms: 2000, steps: [])
  assert list.map(list.flat_map(go, fn(taken) { frames(taken:) }), fn(frame) {
      frame.message_id
    })
    == [0x07F4, 0x07FE, 0x0361, 0x035C]
    as "opcode.0x7f4 and 0x7fe: the go and the finish at 2000 ms, then the use counts: 0x361 and, the quest's only objective being done, 0x35c"
  let counted =
    list.flat_map(go, fn(taken) { as_pairs(frames: frames(taken:)) })
    |> list.drop(2)
  assert counted
    == [
      progress_frame(quest: 9207, index: 0, progress: 1),
      state_frame(quest: 9207, state: 2),
    ]
    as "opcode.0x361 and opcode.0x35c: objective 0 of quest 9207 is at 1 of 1, and the quest is Achieved"
}

pub fn an_interrupted_use_counts_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, started) =
    connection_support.at(
      state: seeing_the_use_target(),
      ms: 0,
      event: OwnEvent(step.Read(right_click())),
    )
  let assert [confirmed] =
    connection_support.decoded(
      frames(taken: started),
      spell_cast_confirmed.message_id,
      spell_cast_confirmed.decode,
    )
    as "the right-click starts a cast, confirmed by one 0x7fd"
  let #(state, cancelled) =
    connection_support.at(
      state:,
      ms: 1000,
      event: OwnEvent(
        step.Read(connection_support.world_message(
          message_id: 0x0801,
          body: cast_support.cancel_body(
            cast_id: confirmed.server_cast_id,
            reason: cast_result.from_value(11),
            bit: 1,
          ),
        )),
      ),
    )
  let #(state, later) =
    connection_support.casts_run(
      state:,
      pending: connection_support.cast_timers(steps: [started], ms: 0),
      until_ms: 5000,
      steps: [],
    )
  let all = ids_of(steps: [cancelled, ..later])
  assert !list.contains(all, 0x0361)
    as "opcode.0x801: a cast cancelled before its go at 2000 ms counts no use"
  assert !list.contains(all, 0x07F4)
    as "the cancelled cast never reaches its go, so the 0x361 is absent because the use did not happen, not because the timer was lost"

  let #(state, again) =
    connection_support.at(
      state:,
      ms: 5000,
      event: OwnEvent(step.Read(right_click())),
    )
  let #(_, go) =
    connection_support.casts_run(
      state:,
      pending: connection_support.cast_timers(steps: [again], ms: 5000),
      until_ms: 7000,
      steps: [],
    )
  assert list.flat_map(go, fn(taken) { as_pairs(frames: frames(taken:)) })
    |> list.drop(2)
    == [
      progress_frame(quest: 9207, index: 0, progress: 1),
      state_frame(quest: 9207, state: 2),
    ]
    as "a use of the same creature after the cancel completes at its go and counts once: one 0x361 at 1 of 1, then 0x35c, so the silence before was the cancel and not a count that is never wired"
}

pub fn a_kill_sends_its_experience_then_objective_progress_and_achieved_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 1857's objective 1961 (type 2, count 1) names the Beast, Creature2 73464.
  use tables <- fixture_tables.changed(table: "QuestObjective", id: 1961, with: [
    #("data", Integer(73_464)),
  ])
  let #(state, _) =
    connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.accepted(quest_id: 1857, progress: [0]),
    ])
  let #(state, stale) =
    experience_support.credited_in(
      state:,
      stay: connection_support.viewer_stay(2),
      creature_id: 73_464,
      level: 1,
    )
  assert connection_support.written_ids(stale) == []
    as "a credit for another stay writes neither the experience nor any objective message"

  let #(_, credit) =
    experience_support.credited(state:, creature_id: 73_464, level: 1)
  assert experience_support.gains(taken: credit)
    == [
      ExperienceGained(
        experience: 5,
        rest_experience_used: 0,
        bonus_experience: 0,
        source_kind: 2,
        source_unit_id: experience_support.creature_unit_id,
      ),
    ]
    as "opcode.0x1ac: the kill's experience"
  let written = as_pairs(frames: frames(taken: credit))
  assert list.map(written, fn(frame) { frame.0 }) == [0x01AC, 0x0361, 0x035C]
    as "the experience is written first, then the objective's progress and, the quest's only objective being done, its state; the credit for the other stay left the objective open"
  assert list.drop(written, 1)
    == [
      progress_frame(quest: 1857, index: 0, progress: 1),
      state_frame(quest: 1857, state: 2),
    ]
    as "opcode.0x361 and opcode.0x35c: objective 0 of quest 1857 is at 1 of 1, and the quest is Achieved"
}

/// TargetGroup 847 is type 3 with value 248 (`table_rows -- TargetGroup`): its members are
/// the units whose current Faction2 is 248 (`0x1403b4a20`), and the faction is the one
/// the killed creature's spawn row gives, which the kill's credit carries.
pub fn a_kill_counts_toward_a_group_objective_by_the_credits_faction_test() -> Nil {
  use <- owned_test.run(10_000)
  // Objective 1961 as type 8 (a kill of a unit of a TargetGroup) naming group 847.
  use tables <- fixture_tables.changed(table: "QuestObjective", id: 1961, with: [
    #("type", Integer(8)),
    #("data", Integer(847)),
  ])
  let #(state, _) =
    connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.accepted(quest_id: 1857, progress: [0]),
    ])

  // No creature is shown to this connection, so the faction can only come from the credit.
  let #(_, other) =
    experience_support.credited_of_faction(
      state:,
      stay: connection_support.own_stay(),
      creature_id: 73_464,
      faction_id: 249,
      level: 1,
    )
  assert list.map(as_pairs(frames: frames(taken: other)), fn(frame) { frame.0 })
    == [0x01AC]
    as "a kill of a creature of Faction2 249 is no member of group 847 (type 3, faction 248), so only the experience is written"

  let #(_, member) =
    experience_support.credited_of_faction(
      state:,
      stay: connection_support.own_stay(),
      creature_id: 73_464,
      faction_id: 248,
      level: 1,
    )
  assert list.drop(as_pairs(frames: frames(taken: member)), 1)
    == [
      progress_frame(quest: 1857, index: 0, progress: 1),
      state_frame(quest: 1857, state: 2),
    ]
    as "a kill of a creature of Faction2 248, which the connection does not show, is a member of group 847 and finishes the objective"
}

/// The 0x361 and 0x35c frames the step writes, in order.
fn quest_frames(
  taken taken: step.ConnectionStep(Request),
) -> List(#(Int, BitArray)) {
  list.filter(as_pairs(frames: frames(taken:)), fn(frame) {
    frame.0 == 0x0361 || frame.0 == 0x035C
  })
}

/// A held stack of Item2 14838 (quest 1854's objective 1959 once its data is changed to it, type 4, count 3): the guid
/// only has to differ between the stacks.
fn stack_of_14838(slot slot: Int, count count: Int) -> store.HeldItem {
  HeldItem(
    item_guid: 3_993_000 + slot,
    item2_id: Item2Id(14_838),
    location: 1,
    bag_index: slot,
    stack_count: count,
    random_stats: 0,
  )
}

/// A 0x149 of the item at inventory slot `slot`, inside 0x038C.
fn destroys(slot slot: Int) -> BitArray {
  let assert Ok(body) =
    item_delete.encode(
      item_delete.ItemDelete(place: ItemPlace(location: 1, bag_index: slot)),
    )
    as "a place fits the message"
  connection_support.world_message(message_id: item_delete.message_id, body:)
}

pub fn destroying_a_collected_item_lowers_its_progress_test() -> Nil {
  use <- owned_test.run(10_000)
  // The player holds 1 + 2 of item 14838, so quest 1854 is Achieved, as the log saved
  // it. Objective 1959 names item 3993, which the Item2 table lacks, so its data is
  // changed to 14838, a row the destroy can look up.
  let rows = case
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "QuestObjective",
      id: 1959,
      with: [#("data", Integer(14_838))],
    )
  {
    Ok(changed) -> changed
    Error(refusal) -> panic as fixture_tables.describe(refusal)
  }
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let #(state, _) =
    connection_support.entered_with_quests_and_items_on(
      tables:,
      quests: [
        quest_support.active(
          quest_id: 1854,
          state: 2,
          placeholder: 0,
          tracked: False,
          done_mask: 1,
          progress: [3],
        ),
      ],
      items: [
        stack_of_14838(slot: 0, count: 1),
        stack_of_14838(slot: 1, count: 2),
      ],
    )
  let #(state, taken) = connection_support.read(state, destroys(slot: 0))
  let #(state, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        client_connection.FromStore(store.ForItems(store.ItemsSaved)),
      ),
    )
  assert connection_support.written_ids(answered) == [0x0148, 0x0361, 0x035C]
    as "opcode.0x148 tells the destroy, then 0x361 lowers the count, then 0x35c 1 takes the quest back to Accepted: the client counts nothing for a collect objective and sets done when value >= count (0x1406115a0)"
  assert quest_frames(taken: answered)
    == [
      progress_frame(quest: 1854, index: 0, progress: 2),
      state_frame(quest: 1854, state: 1),
    ]
    as "opcode.0x361 and opcode.0x35c: 2 of 3 are held, and the quest is Accepted"
  // The 2 left in slot 1 are destroyed: 0 held, the quest already Accepted, so no state.
  let #(state, taken) = connection_support.read(state, destroys(slot: 1))
  let #(_, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        client_connection.FromStore(store.ForItems(store.ItemsSaved)),
      ),
    )
  assert quest_frames(taken: answered)
    == [progress_frame(quest: 1854, index: 0, progress: 0)]
    as "no held item is no count, and an Accepted quest has no state to send"
  assert connection_support.written_ids(answered) == [0x0148, 0x0361]
    as "0x148 then 0x361"
}

pub fn buying_a_collected_item_sends_its_progress_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item2 14838 is Dorian Walker's stock at position 2 for 67 credits
  // (`opcode.0xbe`); the objective of quest 1854 counts one of it.
  let rows = case
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "QuestObjective",
      id: 1959,
      with: [#("data", Integer(14_838)), #("count", Integer(1))],
    )
  {
    Ok(changed) -> changed
    Error(refusal) -> panic as fixture_tables.describe(refusal)
  }
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let fresh =
    connection_support.accepted(
      connection_state.Settings(
        ..connection_support.settings(),
        tables:,
        vendors: vendor_support.stocking(creature_ids: [74_812]),
      ),
    ).0
  let state =
    connection_support.entered_stocking_with_quests(
      in_character_select: connection_support.in_select_from(fresh),
      credits: 100,
      items: [],
      quests: [quest_support.accepted(quest_id: 1854, progress: [0])],
    )
  let walker =
    spawn_support.dorian_walker(
      number: 1,
      place: connection_support.entry_place(),
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: appears(
        creature_id: 74_812,
        display_info_id: walker.display_info_id,
        outfit_info_id: walker.outfit_info_id,
        hit_radius: walker.combat.hit_radius,
      ),
    )
  let #(state, _) =
    connection_support.interaction_requested(state:, unit_id: unit, kind: 0x31)
  let #(state, taken) =
    connection_support.purchase_requested(state:, unique_id: 2, quantity: 1)
  assert quest_frames(taken:) == []
    as "nothing is told before the store has saved the buy"
  let #(_, answered) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        client_connection.FromStore(
          store.ForItems(
            store.Bought(amount: 33, made: [
              HeldItem(
                item_guid: 900,
                item2_id: Item2Id(14_838),
                location: 1,
                bag_index: 0,
                stack_count: 1,
                random_stats: 0,
              ),
            ]),
          ),
        ),
      ),
    )
  let ids = connection_support.written_ids(answered)
  assert list.contains(ids, 0x0111)
    as "opcode.0x111: the new stack is told first"
  assert list.drop_while(ids, fn(id) { id != 0x0111 })
    |> list.drop(1)
    |> list.filter(fn(id) { id == 0x0361 || id == 0x035C })
    == [0x0361, 0x035C]
    as "then 0x361 and 0x35c 2: the one item finishes the quest"
  assert quest_frames(taken: answered)
    == [
      progress_frame(quest: 1854, index: 0, progress: 1),
      state_frame(quest: 1854, state: 2),
    ]
    as "opcode.0x361 and opcode.0x35c: 1 of 1, and the quest is Achieved"
}

pub fn accepting_a_quest_counts_held_items_and_the_current_zone_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quests 1854 (type 4, objective 1959, whose item 3993 the Item2 table lacks, so
  // it names the held 14838) and 1862 (type 17, objective 1965) come by the
  // communicator here, as 1872 does (flags 4), and 1862's visit names zone 6009,
  // the zone the player enters the world in (`WorldLocation2` 51596).
  let rows =
    list.fold(
      [
        #("Quest2", 1854, [#("flags", Integer(4))]),
        #("Quest2", 1862, [#("flags", Integer(4))]),
        #("QuestObjective", 1959, [#("data", Integer(14_838))]),
        #("QuestObjective", 1965, [#("data", Integer(6009))]),
      ],
      fixture_tables.rows(),
      fn(rows, edit) {
        case
          fixture_tables.change(rows:, table: edit.0, id: edit.1, with: edit.2)
        {
          Ok(changed) -> changed
          Error(refusal) -> panic as fixture_tables.describe(refusal)
        }
      },
    )
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let #(state, _) =
    connection_support.entered_with_quests_and_items_on(
      tables:,
      quests: [quest_support.known(1854, 5), quest_support.known(1862, 5)],
      items: [stack_of_14838(slot: 0, count: 2)],
    )
  let accepts = fn(quest_id) {
    let assert Ok(body) =
      quest_accept.encode(QuestAccept(
        item: ItemPlace(location: 300, bag_index: 4_294_967_295),
        quest_id:,
      ))
      as "the dialog's accept fits the message"
    body
  }
  let #(state, taken) =
    connection_support.read(
      state,
      connection_support.world_message(
        message_id: quest_accept.message_id,
        body: accepts(1854),
      ),
    )
  assert quest_frames(taken:)
    == [
      state_frame(quest: 1854, state: 1),
      progress_frame(quest: 1854, index: 0, progress: 2),
    ]
    as "opcode.0x35c 1 for the accept, then 0x361 for the 2 of 3 held (locations 0, 1, 8 and 9 count: 0x140552550)"
  let #(_, taken) =
    connection_support.read(
      state,
      connection_support.world_message(
        message_id: quest_accept.message_id,
        body: accepts(1862),
      ),
    )
  assert quest_frames(taken:)
    == [
      state_frame(quest: 1862, state: 1),
      progress_frame(quest: 1862, index: 0, progress: 1),
      state_frame(quest: 1862, state: 2),
    ]
    as "a quest accepted in the zone counts its visit at once (prerequisite 26, 0x1403c92e0), then 0x35c 2 for the quest it finishes"
}

pub fn a_zone_change_sends_visit_progress_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 1862's visit names zone 5998, inside 5997 inside 4961.
  use tables <- fixture_tables.changed(table: "QuestObjective", id: 1965, with: [
    #("data", Integer(5998)),
  ])
  let #(state, _) =
    connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.accepted(quest_id: 1862, progress: [0]),
    ])
  let #(state, elsewhere) =
    connection_support.read(
      state,
      connection_support.zone_changed_message(old: 6009, new: 4962),
    )
  assert quest_frames(taken: elsewhere) == []
    as "opcode.0x63a: a zone outside the chain counts nothing"
  let #(_, entered) =
    connection_support.read(
      state,
      connection_support.zone_changed_message(old: 4962, new: 5998),
    )
  assert quest_frames(taken: entered)
    == [
      progress_frame(quest: 1862, index: 0, progress: 1),
      state_frame(quest: 1862, state: 2),
    ]
    as "opcode.0x63a: entering zone 5998 finishes the visit: 0x361, then 0x35c 2 for the quest it finishes"
}

pub fn activating_a_quest_anim_collectible_sends_its_progress_test() -> Nil {
  use <- owned_test.run(10_000)
  // Creature2 12919 (display 21373) names quest 3741, objective index 0 (objective
  // 4813, type 32, count 6), and its activate spell 1817 takes 2000 ms with a
  // maximum range of 5.0 (`Creature2.12919`).
  let #(state, started) =
    connection_support.at(
      state: seeing_a_use_target(
        quest: 3741,
        creature_id: 12_919,
        display_info_id: 21_373,
      ),
      ms: 0,
      event: OwnEvent(step.Read(right_click())),
    )
  let #(_, go) =
    connection_support.casts_run(
      state:,
      pending: connection_support.cast_timers(steps: [started], ms: 0),
      until_ms: 2000,
      steps: [],
    )
  assert list.map(list.flat_map(go, fn(taken) { frames(taken:) }), fn(frame) {
      frame.message_id
    })
    == [0x07F4, 0x07FE, 0x0361]
    as "opcode.0x7f4 and 0x7fe at 2000 ms, then 0x361 only: 1 of 6, so the quest stays Accepted"
  assert list.flat_map(go, fn(taken) { quest_frames(taken:) })
    == [progress_frame(quest: 3741, index: 0, progress: 1)]
    as "opcode.0x361: one virtual item of the six"
}
