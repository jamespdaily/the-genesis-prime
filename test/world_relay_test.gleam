//// What a player's connection is sent about a creature when the creature tells only its
//// map, run as the real processes: a map and its creature under their supervisors on the
//// driven clock, with the map's sends to connections held at a gate the test opens
//// (`send_gate`), so the test, not a time, decides how late they are. Expected values come
//// from these places.
//// - The relation protocol of the map (the doc comment of `genesis_prime/world_map/map`):
////   a creature's news, answers, credits and fight tells reach a player only from the map,
////   in the order the creature told the map them.
//// - The strike round (`genesis_prime/shared/strike_tell`, `genesis_prime/game/strike`): an
////   answer is waited for 1,000 ms; the caster's round, not the map, decides that a later
////   answer is late.
//// - `creature.struck`'s order: the answer, the kill credit, then the health and the death.

import cast_struck_support
import driven_time
import game_connection_support
import genesis_prime/client_connection.{
  type Message, ForStay, SentByKill, SentByPeer, SentByTarget,
}
import genesis_prime/game/strike
import genesis_prime/service
import genesis_prime/shared/spell_plan
import genesis_prime/shared/strike_tell.{
  type Answered, Answered, Key, Landed, Refused,
}
import genesis_prime/shared/unit_news.{PeerNews}
import genesis_prime/step.{ConnectionId, Woken}
import genesis_prime/world_map/creature
import genesis_prime/world_map/map
import genesis_prime/world_map/registry
import genesis_prime/world_map/relay
import gleam/list
import gleam/result
import inbound_support
import legal_order_support
import map_support
import owned_test
import place_support
import send_gate
import spawn_support
import world_support.{type World}
import world_watch_support

/// A world of one Battle Beast at x 0 on a driven clock, its maps' sends to connections
/// passing a gate that is open until the test closes it.
fn gated_beast_world(
  time time: driven_time.Time,
  respawn_ms respawn_ms: Int,
) -> World {
  world_support.start_gated(
    time:,
    spawns: [spawn_support.battle_beast(number: 1, x: 0.0)],
    respawn_ms:,
    idle_stop_ms: world_watch_support.idle_stop_ms,
    sweep_ms: world_watch_support.sweep_ms,
  )
}

/// Waits until the gate holds at least `count` sends of the map: the map's step that made
/// them is done when the clock's participants are quiet, so a send the map never made fails
/// the wait at once (`driven_time.wait_for`).
fn held_at_least(
  time time: driven_time.Time,
  world world: World,
  count count: Int,
) -> Nil {
  driven_time.wait_for(
    time:,
    what: "the map to hold back sends to the connection",
    condition: fn() {
      send_gate.held(gate: world_support.gate(world:)) >= count
    },
  )
}

/// What the connection was sent that a creature's answer, credit or health news is.
fn heard_kind(message: Message) -> Result(String, Nil) {
  case message {
    ForStay(sent: SentByTarget(..), ..) -> Ok("answer")
    ForStay(sent: SentByKill(..), ..) -> Ok("credit")
    ForStay(sent: SentByPeer(PeerNews(news: unit_news.Health(..), ..)), ..) ->
      Ok("health")
    ForStay(sent: SentByPeer(PeerNews(news: unit_news.Died, ..)), ..) ->
      Ok("death")
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// The answer to a strike, whole, when the message is one.
fn answered_of(message: Message) -> Result(Answered, Nil) {
  case message {
    ForStay(sent: SentByTarget(answered:), ..) -> Ok(answered)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

pub fn a_viewer_writes_the_creatures_snapshot_and_then_its_news_in_the_order_the_map_relayed_them_test() -> Nil {
  use <- owned_test.run(10_000)
  let time = driven_time.new()
  let world = gated_beast_world(time:, respawn_ms: 60_000)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  send_gate.close(gate: world_support.gate(world:))
  let _player = world_watch_support.join(run:, connection: 1)
  held_at_least(time:, world:, count: 1)
  // A caster that is not in the map (connection 2) strikes the creature once: the damage
  // applies and the creature tells the map its health, with no threat for a connection that is
  // no viewer, so no fight and no path follow.
  let unit_id = 2
  let assert creature.Strike(tell:) =
    world_watch_support.strike_message(
      unit_id:,
      damage_type: 3,
      damage: 14,
      cast_id: 1,
      occasion: strike_tell.AtGo(phase: 0),
    )
  world_watch_support.told_creature_by(
    run:,
    connection: 2,
    unit_id:,
    life: 2,
    payload: relay.Strike(
      tell: strike_tell.Strike(..tell, from: step.Connection(ConnectionId(2))),
    ),
  )
  held_at_least(time:, world:, count: 2)
  send_gate.open(gate: world_support.gate(world:))
  let messages = world_support.sent_before_the_marker(world:, id: 1, received:)
  // The messages go to a real connection, as its shell hands them to it.
  let frames =
    list.fold(
      messages,
      #(game_connection_support.in_world(), []),
      fn(held, message) {
        let #(state, frames) = held
        let #(state, taken) =
          game_connection_support.feed(
            state:,
            event: step.OwnEvent(Woken(message)),
          )
        #(
          state,
          list.append(
            frames,
            game_connection_support.heard(
              taken,
              game_connection_support.keyed(),
            ),
          ),
        )
      },
    ).1
  assert legal_order_support.names(frames:) == ["0x262(2)", "0x937(2)"]
    as "the viewer's frames are the creature's 0x262 and then the news of the strike, the order the map relayed them in"
  world_support.stop(world:)
}

pub fn the_caster_is_told_the_answer_the_credit_and_the_health_news_in_that_order_while_the_maps_sends_are_held_back_test() -> Nil {
  use <- owned_test.run(10_000)
  let time = driven_time.new()
  let world = gated_beast_world(time:, respawn_ms: 60_000)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let beast =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  send_gate.close(gate: world_support.gate(world:))
  // The caster's connection, which is also the viewer, kills the creature in one strike.
  world_watch_support.strike_with(
    run:,
    unit_id: beast.unit_id,
    life: 2,
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  held_at_least(time:, world:, count: 4)
  send_gate.open(gate: world_support.gate(world:))
  let kinds =
    list.map([1, 2, 3, 4], fn(_) {
      world_watch_support.next(
        received:,
        what: "the answer, the credit, the health or the death",
        wanted: heard_kind,
      )
    })
  assert kinds == ["answer", "credit", "health", "death"]
    as "the caster is told the answer, the credit and then the health and the death, in the order the creature's one step told the map, whatever the map's sends were held back for"
  world_support.stop(world:)
}

pub fn a_dead_creature_that_is_released_still_answers_its_striker_through_the_map_until_it_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let time = driven_time.new()
  let respawn_ms = 1000
  let world = gated_beast_world(time:, respawn_ms:)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let beast =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  world_watch_support.strike_with(
    run:,
    unit_id: beast.unit_id,
    life: 2,
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  let _killed =
    world_watch_support.next(
      received:,
      what: "the answer to the killing strike",
      wanted: world_watch_support.answer_to(_, cast_id: 1),
    )
  // The player's use releases the unit: the spawn is released, and the dead creature is told
  // to end, which it does at its corpse timer.
  let _sent =
    service.tell_subject(run.subject, map.Released(unit_id: beast.unit_id))
  driven_time.wait_until_quiet(time)
  // A second strike reaches the dead creature, which refuses it as dead; the map, which holds
  // the spawn as releasing, still delivers the answer.
  world_watch_support.strike_with(
    run:,
    unit_id: beast.unit_id,
    life: 2,
    damage_type: 3,
    damage: 5,
    cast_id: 2,
  )
  let outcome =
    world_watch_support.next(
      received:,
      what: "the answer to the second strike",
      wanted: world_watch_support.answer_to(_, cast_id: 2),
    )
  assert outcome == Refused(why: strike_tell.Dead)
    as "the creature that was released answers its striker as dead until it ends"
  // The corpse timer ends the creature; a relay of its life that reaches the map after that
  // is dropped.
  driven_time.advance(time:, ms: respawn_ms)
  let gone =
    world_watch_support.next(
      received:,
      what: "Gone for the creature that ended",
      wanted: fn(message) { world_watch_support.gone_unit(message) },
    )
  assert gone == beast.unit_id
  let _sent =
    service.tell_subject(
      run.subject,
      map.Relay(
        unit_id: beast.unit_id,
        life: 2,
        to: ConnectionId(1),
        stay: map_support.stay(count: 1),
        payload: relay.Struck(answered: Answered(
          key: strike_tell.Key(
            cast_id: 3,
            occasion: strike_tell.AtGo(phase: 0),
            unit_id: beast.unit_id,
          ),
          outcome: Refused(why: strike_tell.Dead),
        )),
      ),
    )
  driven_time.wait_until_quiet(time)
  let after = world_support.sent_before_the_marker(world:, id: 1, received:)
  assert list.filter_map(after, answered_of) == []
    as "a relay of a creature that ended is dropped by the map"
  world_support.stop(world:)
}

pub fn the_map_delivers_a_relay_held_past_the_strike_deadline_unchanged_and_the_round_decides_that_it_is_late_test() -> Nil {
  use <- owned_test.run(10_000)
  let time = driven_time.new()
  let world = gated_beast_world(time:, respawn_ms: 60_000)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let beast =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  // The caster's round, open at the go for the creature, with its deadline 1,000 ms on.
  let spell =
    cast_struck_support.spell_gated_at(gated_aim: spell_plan.AimsAtArea)
  let #(_, asked) = cast_struck_support.pressed(spell:, target: beast.unit_id)
  let #(round, _) =
    cast_struck_support.begun(
      selection: cast_struck_support.selection_of(spell:, asked:, units: [
        beast.unit_id,
      ]),
    )
  send_gate.close(gate: world_support.gate(world:))
  let assert creature.Strike(tell:) =
    world_watch_support.strike_message(
      unit_id: beast.unit_id,
      damage_type: 3,
      damage: 5,
      cast_id: asked.cast_id,
      occasion: strike_tell.AtGo(phase: asked.phase),
    )
  world_watch_support.told_creature(
    run:,
    unit_id: beast.unit_id,
    life: 2,
    payload: relay.Strike(tell:),
  )
  held_at_least(time:, world:, count: 1)
  // The clock passes the deadline of the strike while the answer is held at the gate.
  driven_time.advance(time:, ms: strike_tell.deadline_ms + 100)
  send_gate.open(gate: world_support.gate(world:))
  let answered =
    world_watch_support.next(
      received:,
      what: "the answer to the strike",
      wanted: answered_of,
    )
  assert answered.key == tell.key
    && result.is_ok(case answered.outcome {
      Landed(..) -> Ok(Nil)
      Refused(..) | strike_tell.Immune(..) | strike_tell.Deflected(..) ->
        Error(Nil)
    })
    as "the map delivers the answer unchanged, however late: it keeps no deadline"
  // The caster's round, whose timer fired at its deadline, leaves the creature out and
  // takes the late answer as dropped.
  let #(round, closed) =
    strike.timer_fired(strike: round, now: cast_struck_support.at(ms: 2000))
  assert closed != [] as "the round closed at its deadline without the creature"
  let #(after, effects) =
    strike.answered(
      strike: round,
      answer: strike_tell.Answered(..answered, key: tell.key),
      now: cast_struck_support.at(ms: 2200),
    )
  assert effects == [] && after == round
    as "the answer that arrives after the round closed changes nothing: the round, not the map, decides that it is late"
  world_support.stop(world:)
}

/// The creature's tell that the connection's player is threatened, when the message is that.
fn threatened_by_the_creature(message: Message) -> Result(Nil, Nil) {
  case message {
    ForStay(sent: client_connection.SentByFoe(strike_tell.Threatened(..)), ..) ->
      Ok(Nil)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// The strike of the player of connection `from` on the Beast `unit_id` of life 2, told to
/// the map as that connection tells it.
fn struck_through_the_map(
  run run: registry.MapProcess,
  from from: Int,
  unit_id unit_id: Int,
  cast_id cast_id: Int,
) -> Nil {
  let tell =
    inbound_support.struck_by(
      tell: inbound_support.strike(unit_id:),
      from:,
      stay_count: 1,
    )
  let tell = strike_tell.Strike(..tell, key: Key(..tell.key, cast_id:))
  world_watch_support.told_creature_by(
    run:,
    connection: from,
    unit_id:,
    life: 2,
    payload: relay.Strike(tell:),
  )
}

pub fn a_strike_told_through_the_map_damages_the_creature_and_threatens_only_a_viewer_of_the_stay_it_names_test() -> Nil {
  use <- owned_test.run(10_000)
  let time = driven_time.new()
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms: 60_000,
      idle_stop_ms: world_watch_support.idle_stop_ms,
    )
  let run = world_watch_support.started(world)
  let near = world_support.connection(world:, id: 1)
  let far = world_support.connection(world:, id: 2)
  let _near_player = world_watch_support.join(run:, connection: 1)
  let beast =
    world_watch_support.next(
      received: near,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  // Connection 2 is in the map, in the stay its strike names, and stands where the creature
  // is out of its sight.
  let _far_player =
    world_watch_support.join_at(
      run:,
      connection: 2,
      character: map_support.character(number: 102),
      place: place_support.at(
        world_id: 3460,
        world_zone_id: spawn_support.warfare_woods,
        x: 5000.0,
        y: 0.0,
        z: 0.0,
      ),
    )
  driven_time.wait_until_quiet(time)
  let _unseen =
    world_support.sent_before_the_marker(world:, id: 2, received: far)
  struck_through_the_map(run:, from: 1, unit_id: beast.unit_id, cast_id: 1)
  driven_time.wait_until_quiet(time)
  let heard =
    world_support.sent_before_the_marker(world:, id: 1, received: near)
  assert list.filter_map(heard, heard_kind) == ["answer", "health"]
    as "the strike of a viewer, told through the map, damages the creature: the striker is answered and the viewers are told its health"
  assert list.filter_map(heard, threatened_by_the_creature) == [Nil]
    as "and the viewer that struck is told it is threatened"
  struck_through_the_map(run:, from: 2, unit_id: beast.unit_id, cast_id: 2)
  driven_time.wait_until_quiet(time)
  let heard =
    world_support.sent_before_the_marker(world:, id: 1, received: near)
  assert list.filter_map(heard, heard_kind) == ["health"]
    as "the strike of a player that does not see the creature damages it as well"
  assert list.filter_map(heard, threatened_by_the_creature) == []
    as "no one else is threatened"
  let unheard =
    world_support.sent_before_the_marker(world:, id: 2, received: far)
  assert list.filter_map(unheard, heard_kind) == ["answer"]
    as "the player out of sight is answered, whatever it sees"
  assert list.filter_map(unheard, threatened_by_the_creature) == []
    as "and told no threat: it is no viewer of the stay it names"
  world_support.stop(world:)
}
