//// The Experimental Loftite Railgun on a running game connection: each hit on a Chua advances
//// quest 3769's objective by the spell's QuestAdvanceObjective row, six seconds after the shot.
//// Expected values come from these places.
//// - Item2 6938 -> ItemSpecial 3942 -> Spell4 24501: castTime 0, targetMaxRange 25.0, a
////   cooldown of 10 s on Spell4Base 11094, whose cast group is TargetGroup 2125 (Creature2
////   20794, a Chua, 20795 and 20798). Its type 42 row 89873 names quest 3769 index 0 with an
////   amount of 1 and a delayTime of 6000; the item requires that objective open
////   (`Item2.quest2IdActivationRequired` 3769, index 0).
//// - Quest 3769, objective 4849: type 5, count 5, flags 4, so five hits finish it.
//// - `opcode.0x7fd`, `opcode.0x7f4` and `opcode.0x7fe`: the cast's confirmation, its go and its
////   finish, which come at the press for a cast time of 0; the go lists no effect of the type 42
////   row, which the client has no effect for.
//// - `opcode.0x361` and `opcode.0x35c`: the objective's progress, then the quest's state 2.
//// - `0x140398cc0`: the client's item check refuses a use whose objective is done (result 29,
////   0x1d).

import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request, FromStore}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/cast_result
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/item_use.{ItemUse}
import genesis_prime/step.{OwnEvent}
import genesis_prime/store.{ForItems, HeldItem, TurnedIn}
import genesis_prime/table/id.{Creature2Id, Item2Id}
import genesis_prime/world_map/map.{ObjectsSeen}
import genesis_prime/world_map/static_object.{StaticObject}
import gleam/list
import gleam/option.{None}
import message_support
import owned_test
import quest_support
import spawn_support

const unit = 40

const chua = 20_794

/// Creature2DisplayGroupEntry 26826 puts Creature2 20794 (display group 28332) on
/// Creature2DisplayInfo 26312.
const chua_display = 26_312

const railgun = 6938

/// The connection of a player who holds the railgun at {1, 0} and quest 3769 accepted, and
/// sees a Chua as unit 40, 5.0 east of the player.
fn seeing_a_chua_holding_the_railgun() -> game_connection.State {
  let state =
    connection_support.entered_with_items_and_quests(
      items: [
        HeldItem(
          item_guid: 4_000_001,
          item2_id: Item2Id(railgun),
          location: 1,
          bag_index: 0,
          stack_count: 1,
          random_stats: 0,
          charges: 0,
        ),
      ],
      quests: [quest_support.accepted(quest_id: 3769, progress: [0])],
    )
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
            creature_id: Creature2Id(chua),
            display_info_id: chua_display,
          ),
          unit_id: unit,
          server_time_estimate_start: 0,
        ),
      ]),
    ),
  ).0
}

/// The client's 0x943 of the railgun at {1, 0}, at unit 40, inside the client's 0x038C.
fn shot(client_cast_id client_cast_id: Int) -> BitArray {
  let assert Ok(body) =
    item_use.encode(ItemUse(
      client_cast_id:,
      item: ItemPlace(location: 1, bag_index: 0),
      target_unit_id: unit,
      second_item: ItemPlace(location: 300, bag_index: 0xffffffff),
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  connection_support.world_message(message_id: item_use.message_id, body:)
}

fn frames(
  steps steps: List(step.ConnectionStep(Request)),
) -> List(#(Int, BitArray)) {
  list.flat_map(steps, fn(taken) { connection_support.written(taken:) })
  |> list.map(fn(frame: Frame) { #(frame.message_id, frame.body) })
}

fn progress_frame(progress progress: Int) -> #(Int, BitArray) {
  #(0x0361, message_support.packed([#(15, 3769), #(32, 0), #(32, progress)]))
}

fn state_frame(state state: Int) -> #(Int, BitArray) {
  #(0x035C, message_support.packed([#(15, 3769), #(32, state), #(32, 0)]))
}

pub fn the_loftite_railgun_counts_each_hit_toward_up_up_and_away_test() -> Nil {
  use <- owned_test.run(60_000)
  // A shot, then the timers of the next 6 seconds: the steps taken, the press first.
  let shoot = fn(state, client_cast_id, at) {
    let #(state, started) =
      connection_support.at(
        state:,
        ms: at,
        event: OwnEvent(step.Read(shot(client_cast_id:))),
      )
    let #(state, later) =
      connection_support.casts_run(
        state:,
        pending: connection_support.cast_timers(steps: [started], ms: at),
        until_ms: at + 6000,
        steps: [],
      )
    #(state, started, later)
  }
  let #(state, started, later) =
    shoot(seeing_a_chua_holding_the_railgun(), 9, 0)
  assert list.map(frames(steps: [started]), fn(frame) { frame.0 })
    == [0x07FD, 0x07F4, 0x07FE]
    as "opcode.0x7fd, 0x7f4 and 0x7fe at the press (castTime 0), and no 0x361: the hit counts after the row's delay of 6000 ms"
  assert frames(steps: later) == [progress_frame(progress: 1)]
    as "opcode.0x361: at 6000 ms the objective shows 1 of 5"
  // Four more shots, each more than the spell's cooldown of 10 s after the last.
  let #(state, counted) =
    list.fold(
      [#(10, 11_000, 2), #(11, 22_000, 3), #(12, 33_000, 4), #(13, 44_000, 5)],
      #(state, []),
      fn(so_far, shooting) {
        let #(state, counted) = so_far
        let #(state, started, later) = shoot(state, shooting.0, shooting.1)
        #(
          state,
          list.append(counted, [
            #(
              shooting.2,
              list.map(frames(steps: [started]), fn(frame) { frame.0 }),
              frames(steps: later),
              list.last(later),
            ),
          ]),
        )
      },
    )
  let assert Ok(#(_, _, _, Ok(last))) = list.last(counted)
    as "the fifth hit's timer wrote its frames"
  assert list.map(counted, fn(shot) { #(shot.0, shot.1) })
    == [
      #(2, [0x07FD, 0x07F4, 0x07FE]),
      #(3, [0x07FD, 0x07F4, 0x07FE]),
      #(4, [0x07FD, 0x07F4, 0x07FE]),
      #(5, [0x07FD, 0x07F4, 0x07FE]),
    ]
    as "every press starts its cast and counts nothing at the press"
  assert list.map(counted, fn(shot) { shot.2 })
    == [
      [progress_frame(progress: 2)],
      [progress_frame(progress: 3)],
      [progress_frame(progress: 4)],
      [progress_frame(progress: 5), state_frame(state: 2)],
    ]
    as "opcode.0x361: 2, 3 and 4 of 5, and the fifth hit is 5 of 5 and then 0x35c state 2: the quest is Achieved"
  // The fifth hit finished the quest, which no creature receives, so the server turns it in: the
  // store is asked to save the completion, and the answer ends it.
  assert support.asked(last) != None
    as "the connection asks the store to save the server's completion of quest 3769"
  let #(state, _) =
    connection_support.answer(
      state:,
      taken: last,
      outcome: step.Answer(FromStore(ForItems(TurnedIn(credits: 0, made: [])))),
    )
  // A sixth press: the objective is done, so the client's item check refuses it.
  let #(_, sixth) =
    connection_support.at(
      state:,
      ms: 55_000,
      event: OwnEvent(step.Read(shot(client_cast_id: 14))),
    )
  assert list.map(
      connection_support.refusal_results(taken: sixth),
      cast_result.to_value,
    )
    == [29]
    as "0x140398cc0: an objective that is done refuses the use with 29"
}
