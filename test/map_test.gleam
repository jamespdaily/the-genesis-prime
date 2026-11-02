//// The map's rule (`genesis_prime/world_map/map`), run as the pure function it
//// is: inputs in, new state and effects out. Expected values come from these
//// places.
//// - The rule's doc comment: a join is answered with the unit of the Join's
////   character at the Join's place, with a unit id from 1, the map's realm and
////   the body of the character's look, and the map's incarnation, and opens a
////   watch on the player's connection; a connection's end removes its player;
////   a second join answers the unit the map keeps and logs an error; a watch
////   that names no player is an error and changes nothing.
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
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/item_visual.{type ItemVisual, ItemVisual}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Asked, CallerId, Connection,
  ConnectionId, Effects, LogError, OwnEffect, OwnEvent, Reply, Started, Stop,
  Stopping, Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{
  type Character, Character, CharacterId, LookEntry, NameStands,
}
import genesis_prime/table/id.{CharacterCustomizationLabelId, ClassId, RaceId}
import genesis_prime/world_map/map.{type State, Join, Joined}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/player_unit
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test
import place_support

const incarnation = 31

const realm_id = 1

fn started() -> State {
  map.new(map.Settings(
    map: MapId(world_id: 3460, instance: 0),
    incarnation:,
    realm_id:,
    tables: character_tables.shared(),
  ))
}

/// The place the client is told for every join of these tests.
fn joined_place() -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: 6009,
    x: 4605.65,
    y: -7.571,
    z: 494.996,
  )
}

/// A Dominion human male whose id is `number`, with the look of
/// CharacterCustomization row 10.
fn character(number: Int) -> Character {
  Character(
    character_id: CharacterId(number),
    name: "Roxo Stompstone",
    gender: 0,
    race_id: RaceId(1),
    class_id: ClassId(1),
    faction_id: 166,
    level: 1,
    path: 0,
    place: Some(joined_place()),
    look: [
      LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
      LookEntry(label: CharacterCustomizationLabelId(21), value: 2),
    ],
    bones: [],
    naming: NameStands,
  )
}

/// The body of that look: display 137 on slot 25.
fn row_10_body() -> List(ItemVisual) {
  [ItemVisual(slot: 25, display_id: 137, item_color_set_id: 0, dye: 0)]
}

/// What the map answers a join of `character` as unit `unit_id`: the record of
/// the unit at the Join's place, in the map's realm, with the body `visuals`.
fn answer_of(
  character character: Character,
  unit_id unit_id: Int,
  visuals visuals: List(ItemVisual),
) -> map.Outgoing {
  Joined(
    unit: player_unit.create(
      unit: player_unit.new(
        character:,
        place: joined_place(),
        unit_id:,
        visuals:,
      ),
      realm_id:,
    ),
    incarnation:,
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
        place: joined_place(),
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
  join_as(state:, connection:, caller:, character: character(100 + connection))
}

/// The unit id a join was answered with.
fn unit_of(taken: ServiceStep(map.Outgoing), caller: Int) -> Int {
  let assert [#(CallerId(number), Joined(unit:, incarnation: given))] =
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
        answer_of(character: character(107), unit_id: 1, visuals: row_10_body()),
      )),
    ]
    as "the player's connection is watched, then the join is answered with the unit of the Join's character at the Join's place, in the map's realm, with the body of its look: unit ids start at 1"
}

pub fn started_does_nothing_and_stopping_stops_the_rule_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = feed(started(), OwnEvent(Started))
  assert taken == Effects([]) as "a map starts empty"
  let #(_, taken) = feed(state, Stopping(deadline_ms: 9000))
  assert taken == Effects([Stop]) as "Stopping stops the rule at once"
}

pub fn each_join_gets_the_next_unit_id_and_its_own_watch_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(_, second) = join(state:, connection: 8, caller: 2)
  assert unit_of(first, 1) == 1
  assert unit_of(second, 2) == 2
  assert support.effects_of(second)
    == [
      Watch(WatchId(2), Connection(ConnectionId(8))),
      OwnEffect(Reply(
        CallerId(2),
        answer_of(character: character(108), unit_id: 2, visuals: row_10_body()),
      )),
    ]
    as "the watch ids go up too, so a watch is never taken for an older one"
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
    join_as(state:, connection: 7, caller: 2, character: character(900))
  assert unit_of(second, 2) == unit_of(first, 1)
    as "the join is answered with the unit id the connection has"
  assert support.replies(second)
    == [
      #(
        CallerId(2),
        answer_of(character: character(107), unit_id: 1, visuals: row_10_body()),
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
  let unknown = Character(..character(107), race_id: RaceId(3))
  let #(_, taken) =
    join_as(state: started(), connection: 7, caller: 1, character: unknown)
  assert support.replies(taken)
    == [
      #(CallerId(1), answer_of(character: unknown, unit_id: 1, visuals: [])),
    ]
    as "the tables hold no CharacterCustomization row of race 3, so the body is empty and the join is still answered with the unit, as for any character"
  assert support.logs_of(step: taken, level: LogError) == []
  assert list.length(support.watches(taken)) == 1
    as "the player is in the map, and its connection watched"
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
