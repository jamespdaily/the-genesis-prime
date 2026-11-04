//// The map's rule (`genesis_prime/world_map/map`), run as the pure function it
//// is: inputs in, new state and effects out. Expected values come from these
//// places.
//// - The rule's doc comment: a join is answered with the unit of the Join's
////   character at the Join's place, with a unit id from 1, the map's realm and
////   the body of the character's look, and the map's incarnation, and opens a
////   watch on the player's connection; a connection's end removes its player;
////   a second join answers the unit the map keeps and logs an error; a watch
////   that names no player is an error and changes nothing; a leave removes the
////   connection's player with its unit, drops its watch and is answered `Left`,
////   and a leave of a connection that is not in the map is an error and the
////   same answer.
//// - The worn set: a character wears its whole Novice set, so its 0x262 holds an
////   item visual for each armor piece and the weapon after its body's, and none
////   for the shield (`opcode.0x262.worn_visuals`, `Item2.novice_visuals`).
//// - The body: CharacterCustomization row 10 of the planted tables (race 1,
////   sex 0; labels 21 = 2 and 2 = 1) shows display 137 on slot 25
////   (`character_tables`), and the tables hold no row of race 3, so a look of
////   race 3 shows nothing.
//// - The unit's record is `player_unit.create`, whose bytes
////   `player_unit_test` checks against the client's own.
//// - The client: it refuses a 0x262 whose unit id it has already seen
////   (opcode.0x262), so no unit id is given twice in a map's life, whoever
////   leaves.

import character_tables
import connection_rule_support as support
import genesis_prime/game/loadout
import genesis_prime/message/item_visual.{type ItemVisual, ItemVisual}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Asked, CallerId, Connection,
  ConnectionId, Effects, LogError, OwnEffect, OwnEvent, Reply, StartServiceTimer,
  Started, Stop, Stopping, Unwatch, Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{type Character, Character}
import genesis_prime/table/id.{ClassId, RaceId}
import genesis_prime/world_map/map.{type State, Join, Joined, Leave, Left}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/player_unit
import gleam/int
import gleam/list
import gleam/option.{Some}
import map_support
import novice_tables
import owned_test
import place_support

const incarnation = 31

const realm_id = map_support.realm_id

fn started() -> State {
  map_support.empty(incarnation:)
}

/// The body of that look: display 137 on slot 25.
fn row_10_body() -> List(ItemVisual) {
  [ItemVisual(slot: 25, display_id: 137, item_color_set_id: 0, dye: 0)]
}

/// The visuals of a class's Novice set of a faction, with colour set 0 and dye
/// 0 (`opcode.0x262.worn_visuals`).
fn novice_worn(
  class_id class_id: Int,
  faction_id faction_id: Int,
) -> List(ItemVisual) {
  list.map(novice_tables.worn_visuals(class_id:, faction_id:), fn(visual) {
    ItemVisual(
      slot: visual.0,
      display_id: visual.1,
      item_color_set_id: 0,
      dye: 0,
    )
  })
}

/// What the map answers a join of `character` as unit `unit_id`: the record of
/// the unit at the Join's place, in the map's realm, with the `body` of its look,
/// the loadout of its class and faction and the health that loadout gives at its
/// level, which the answer carries beside the record.
fn answer_of(
  character character: Character,
  unit_id unit_id: Int,
  body body: List(ItemVisual),
) -> map.Outgoing {
  let tables = character_tables.shared()
  let assert Ok(loadout) =
    loadout.of(
      tables:,
      class_id: character.class_id,
      faction_id: character.faction_id,
    )
    as "the planted tables hold a Novice set for the class and faction"
  let assert Ok(max_health) =
    loadout.max_health(tables:, loadout:, level: character.level)
    as "the planted tables hold a CreatureLevel row for the character's level"
  Joined(
    unit: player_unit.create(
      unit: player_unit.new(
        character:,
        place: place_support.live_character_place(),
        unit_id:,
        body:,
        loadout:,
        max_health:,
      ),
      realm_id:,
    ),
    loadout:,
    max_health:,
    incarnation:,
    clock_origin_ms: 0,
  )
}

fn feed(
  state: State,
  event: Event(ServiceEvent(map.Message)),
) -> #(State, ServiceStep(map.Outgoing)) {
  map.step(state, support.input(event))
}

/// A join of the connection as the map's caller number `caller`, as
/// `character`.
fn join_as(
  state state: State,
  connection connection: Int,
  caller caller: Int,
  character character: Character,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state,
    OwnEvent(Asked(
      caller: CallerId(caller),
      message: Join(
        connection: ConnectionId(connection),
        character:,
        place: place_support.live_character_place(),
      ),
    )),
  )
}

/// A join of the connection as the map's caller number `caller`, as character
/// 100 more than the connection.
fn join(
  state state: State,
  connection connection: Int,
  caller caller: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  join_as(
    state:,
    connection:,
    caller:,
    character: map_support.character(100 + connection),
  )
}

/// The effects that are not sends to a connection: a join of two players at
/// one place also sends each a `Seen` of the other.
fn without_sends(
  effects: List(step.Effect(step.ServiceEffect(map.Outgoing))),
) -> List(step.Effect(step.ServiceEffect(map.Outgoing))) {
  list.filter(effects, fn(effect) {
    case effect {
      OwnEffect(step.Send(..)) -> False
      OwnEffect(Reply(..))
      | OwnEffect(step.StartCreature(..))
      | OwnEffect(step.StartServiceTimer(..))
      | OwnEffect(step.CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | Stop -> True
    }
  })
}

/// The unit id a join was answered with.
fn unit_of(taken: ServiceStep(map.Outgoing), caller: Int) -> Int {
  let assert [#(CallerId(number), Joined(unit:, incarnation: given, ..))] =
    support.replies(taken)
    as "one reply answers the join"
  assert number == caller as "the reply is for the caller that joined"
  assert given == incarnation
    as "every Joined carries the map's incarnation, so the joiner watches the run that holds its player"
  unit.unit_id
}

pub fn the_first_join_is_unit_1_with_a_watch_on_the_connection_and_the_maps_incarnation_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) = join(state: started(), connection: 7, caller: 1)
  assert support.effects_of(taken)
    == [
      Watch(WatchId(1), Connection(ConnectionId(7))),
      OwnEffect(Reply(
        CallerId(1),
        answer_of(
          character: map_support.character(107),
          unit_id: 1,
          body: row_10_body(),
        ),
      )),
    ]
    as "the player's connection is watched, then the join is answered with the unit of the Join's character at the Join's place, in the map's realm, with the body of its look: unit ids start at 1"
}

pub fn started_starts_the_sweep_timer_and_stopping_stops_the_rule_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = feed(started(), OwnEvent(Started))
  assert taken
    == Effects([
      OwnEffect(StartServiceTimer(
        timer: map.sweep_timer,
        after_ms: map_support.sweep_ms,
      )),
    ])
    as "a map starts empty, with only its sweep timer"
  let #(_, taken) = feed(state, Stopping(deadline_ms: 9000))
  assert taken == Effects([Stop]) as "Stopping stops the rule at once"
}

pub fn each_join_gets_the_next_unit_id_and_its_own_watch_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(_, second) = join(state:, connection: 8, caller: 2)
  assert unit_of(first, 1) == 1
  assert unit_of(second, 2) == 2
  assert without_sends(support.effects_of(second))
    == [
      Watch(WatchId(2), Connection(ConnectionId(8))),
      OwnEffect(Reply(
        CallerId(2),
        answer_of(
          character: map_support.character(108),
          unit_id: 2,
          body: row_10_body(),
        ),
      )),
    ]
    as "the watch ids go up too, so a watch is never taken for an older one; the two players stand at one place, so the join also sends their `Seen`s, which the seeing tests below check"
}

pub fn a_unit_id_is_never_given_twice_across_leaves_and_rejoins_test() -> Nil {
  use <- owned_test.run(10_000)
  // Two connections join and leave in turn, ten rounds, each rejoining as the
  // same connection it was before: every join of the run is a new unit id.
  let #(_, ids) =
    int.range(from: 0, to: 10, with: #(started(), []), run: fn(held, round) {
      let #(state, ids) = held
      let #(state, joined) = join(state:, connection: 1, caller: 4 * round + 1)
      let #(state, joined_too) =
        join(state:, connection: 2, caller: 4 * round + 2)
      let first_watch = 2 * round + 1
      let #(state, _) = feed(state, WatchEnded(WatchId(first_watch)))
      let #(state, _) = feed(state, WatchEnded(WatchId(first_watch + 1)))
      #(state, [
        unit_of(joined_too, 4 * round + 2),
        unit_of(joined, 4 * round + 1),
        ..ids
      ])
    })
  assert list.reverse(ids)
    == int.range(from: 1, to: 21, with: [], run: fn(numbers, number) {
      list.append(numbers, [number])
    })
    as "opcode.0x262: the client refuses a unit id it has seen, so a connection that leaves and joins again is a new unit, and the ids are 1 to 20 with none repeated"
}

pub fn a_players_connection_ending_removes_the_player_so_its_next_join_is_a_new_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(state, ended) = feed(state, WatchEnded(WatchId(1)))
  assert ended == Effects([]) as "the player is removed; nothing is sent"
  let #(_, again) = join(state:, connection: 7, caller: 2)
  assert unit_of(first, 1) == 1
  assert unit_of(again, 2) == 2
    as "the connection that left is no longer in the map: its join is a new player, not the old unit"
  assert support.logs_of(step: again, level: LogError) == []
    as "no error: it is not a second join of a connection in the map"
}

pub fn a_second_join_from_a_connection_in_the_map_answers_the_unit_it_keeps_and_logs_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(state, second) =
    join_as(
      state:,
      connection: 7,
      caller: 2,
      character: map_support.character(900),
    )
  assert unit_of(second, 2) == unit_of(first, 1)
    as "the join is answered with the unit id the connection has"
  assert support.replies(second)
    == [
      #(
        CallerId(2),
        answer_of(
          character: map_support.character(107),
          unit_id: 1,
          body: row_10_body(),
        ),
      ),
    ]
    as "the answer is the record of the unit the map keeps, character 107, not one built from the second Join's character 900"
  let assert [line] = support.logs_of(step: second, level: LogError)
    as "the connection's rule joins once: a second is a bug, logged as an error"
  assert line.about
    == step.About(
      ..step.no_one,
      connection: Some(ConnectionId(7)),
      character_id: Some(900),
      map: Some(MapId(world_id: 3460, instance: 0)),
    )
    as "the line is about the connection, the character of the second Join and the map, in its metadata"
  assert line.text
    == "the connection joined the map a second time, as character 900; it is already unit 1 of character 107"
    as "the text names the second Join's character and the unit and character the map keeps"
  assert support.watches(second) == [] as "no second watch is opened"
  assert list.length(support.effects_of(second)) == 2
    as "the error and the answer are all the step holds: nothing else changes"
  let #(_, third) = join(state:, connection: 8, caller: 3)
  assert unit_of(third, 3) == 2
    as "the next unit id is not spent by the second join"
}

pub fn a_character_whose_look_the_tables_lack_is_answered_with_fewer_visuals_test() -> Nil {
  use <- owned_test.run(5000)
  let unknown = Character(..map_support.character(107), race_id: RaceId(3))
  let #(_, taken) =
    join_as(state: started(), connection: 7, caller: 1, character: unknown)
  assert support.replies(taken)
    == [
      #(CallerId(1), answer_of(character: unknown, unit_id: 1, body: [])),
    ]
    as "the tables hold no CharacterCustomization row of race 3, so the body is empty, the Novice set is still worn and the join is still answered with the unit, as for any character"
  assert support.logs_of(step: taken, level: LogError) == []
  assert list.length(support.watches(taken)) == 1
    as "the player is in the map, and its connection watched"
}

pub fn a_character_whose_class_and_faction_have_no_novice_set_is_refused_and_takes_no_unit_id_test() -> Nil {
  use <- owned_test.run(5000)
  let setless = Character(..map_support.character(107), class_id: ClassId(99))
  let #(state, taken) =
    join_as(state: started(), connection: 7, caller: 1, character: setless)
  assert support.replies(taken)
    == [
      #(
        CallerId(1),
        map.NotJoined(reason: map.NoLoadout(class_id: 99, faction_id: 166)),
      ),
    ]
    as "no Novice set holds class 99, so the join is refused: the map does not crash on one character's data, which would end every player's connection"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
    as "the refusal is an error line"
  assert support.watches(taken) == []
    as "the refused player is not in the map, so no watch is opened on its connection"
  let #(_, second) = join(state:, connection: 8, caller: 2)
  assert unit_of(second, 2) == 1
    as "the refused join took no unit id, so the next player is unit 1"
}

pub fn a_character_whose_level_has_no_base_health_row_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let tall = Character(..map_support.character(107), level: 99)
  let #(_, taken) =
    join_as(state: started(), connection: 7, caller: 1, character: tall)
  assert support.replies(taken)
    == [#(CallerId(1), map.NotJoined(reason: map.NoBaseHealth(level: 99)))]
    as "CreatureLevel holds no row for level 99, so the character's health is unknown (loadout.max_health)"
  assert support.watches(taken) == []
}

pub fn a_watch_that_names_no_player_is_an_error_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(state, taken) = feed(state, WatchEnded(WatchId(9)))
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as "a watch the rule never opened is a bug"
  assert line.about
    == step.About(..step.no_one, map: Some(MapId(world_id: 3460, instance: 0)))
    as "the line is about the map only: no connection or character is known"
  let #(_, second) = join(state:, connection: 7, caller: 2)
  assert unit_of(second, 2) == unit_of(first, 1)
    as "the player of connection 7 is still in the map"
}

// ---- a player leaves ----

/// A leave of the connection as the map's caller number `caller`.
fn leave(
  state state: State,
  connection connection: Int,
  caller caller: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state,
    OwnEvent(Asked(
      caller: CallerId(caller),
      message: Leave(connection: ConnectionId(connection)),
    )),
  )
}

pub fn a_leave_removes_the_player_and_its_unit_drops_its_watch_and_is_answered_left_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(state, other) = join(state:, connection: 8, caller: 2)
  let #(state, left) = leave(state:, connection: 7, caller: 3)
  assert support.effects_of(left)
    == [
      Unwatch(WatchId(1)),
      OwnEffect(step.Send(
        Connection(ConnectionId(8)),
        map.Unwatched(by: ConnectionId(7)),
      )),
      OwnEffect(Reply(CallerId(3), Left)),
    ]
    as "the connection's watch, which the join opened as watch 1, is dropped: the connection goes on after its camp, so the map must not hold it as a player; the other player, who saw it, is told its viewer 7 is gone (the connection sent its clients the 0x355 itself, so no Unseen); then the leave is answered"
  assert support.logs(left) == []
  let #(state, again) = join(state:, connection: 7, caller: 4)
  assert unit_of(first, 1) == 1 && unit_of(other, 2) == 2
  assert unit_of(again, 4) == 3
    as "opcode.0x262: a later play is a new unit with a unit id never given before, the client refuses one it has seen"
  assert support.logs_of(step: again, level: LogError) == []
    as "the connection was not in the map any more, so its join is no second join"
  assert support.watches(again) == [#(WatchId(3), Connection(ConnectionId(7)))]
    as "and it is watched again, under a new watch id"
  let #(_, still_there) = join(state:, connection: 8, caller: 5)
  assert unit_of(still_there, 5) == 2
    as "the other player, which did not leave, is still unit 2: a second join answers the unit the map keeps"
}

pub fn a_leave_from_a_connection_not_in_the_map_logs_an_error_changes_nothing_and_is_answered_left_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(state, left) = leave(state:, connection: 9, caller: 2)
  let assert [line] = support.logs_of(step: left, level: LogError)
    as "the connection's rule leaves once, so a leave of one that is not here is a bug"
  assert line.about
    == step.About(
      ..step.no_one,
      connection: Some(ConnectionId(9)),
      map: Some(MapId(world_id: 3460, instance: 0)),
    )
    as "the line is about the connection and the map"
  assert support.replies(left) == [#(CallerId(2), Left)]
    as "the answer lets the connection go on"
  assert support.watches(left) == []
    && list.length(support.effects_of(left)) == 2
    as "no watch is dropped: the error and the answer are all the step holds"
  let #(_, rejoin) = join(state:, connection: 8, caller: 5)
  assert unit_of(first, 1) == 1 && unit_of(rejoin, 5) == 2
    as "the stray leave spent no unit id"
}

pub fn a_joined_unit_wears_the_novice_set_of_its_class_and_faction_after_its_body_for_every_set_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(novice_tables.sets(), fn(set) {
    let character =
      Character(
        ..map_support.character(107),
        class_id: ClassId(set.class_id),
        faction_id: set.faction_id,
      )
    let #(_, taken) =
      join_as(state: started(), connection: 7, caller: 1, character:)
    let assert [#(_, Joined(unit:, ..))] = support.replies(taken)
      as "one reply answers the join"
    let #(body, worn) =
      list.partition(unit.tail.item_visuals, fn(visual) { visual.slot >= 24 })
    assert body != [] && unit.tail.item_visuals == list.append(body, worn)
      as "the body of the look comes first (body slots are 24 to 39), then the worn set"
    assert worn
      == novice_worn(class_id: set.class_id, faction_id: set.faction_id)
      as {
        "opcode.0x262.worn_visuals: one visual for each of the five pieces and the weapon of CharacterCreation row "
        <> int.to_string(set.creation_id)
        <> "'s set, none for the shield"
      }
    assert !list.any(unit.tail.item_visuals, fn(visual) { visual.slot == 43 })
      as "opcode.0x262.worn_visuals: the shield (slot 43) has display 0, which is no visual"
  })
}
