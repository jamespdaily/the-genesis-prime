//// The player-to-creature tells the tests send, one value of each kind of `relay.Inbound`,
//// and the values inside them, so a test that sends every kind through the map and a
//// test that reads each kind as the creature's message use the same ones.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/shared/strike_tell.{
  type Answered, type Tell as StrikeTell, Answered, Key,
}
import genesis_prime/shared/unit_casts.{type CastView, CastView}
import genesis_prime/shared/unit_properties.{type Modifier, type Source}
import genesis_prime/shared/unit_state
import genesis_prime/step.{Connection, ConnectionId}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/world_map/creature
import genesis_prime/world_map/relay
import gleam/list
import map_spawn_support
import map_support
import world_watch_support

/// The strike of connection 1 in its first stay on the creature `unit_id`: one Magic blow
/// of 5, cast 1, the first phase's go.
pub fn strike(unit_id unit_id: Int) -> StrikeTell {
  let assert creature.Strike(tell:) =
    world_watch_support.strike_message(
      unit_id:,
      damage_type: 3,
      damage: 5,
      cast_id: 1,
      occasion: strike_tell.AtGo(phase: 0),
    )
    as "the strike message holds a strike"
  tell
}

/// The player's answer to the creature `unit_id`'s strike: the creature's own strike of
/// cast 1, refused as dead.
pub fn answered(unit_id unit_id: Int) -> Answered {
  Answered(
    key: Key(cast_id: 1, occasion: strike_tell.AtGo(phase: 0), unit_id:),
    outcome: strike_tell.Refused(why: strike_tell.Dead),
  )
}

/// The place a told move stands at.
pub fn place() -> Place {
  map_spawn_support.at(3.0)
}

/// The source of the modifier `modifier` names.
pub fn source() -> Source {
  let assert creature.ModifierStarts(source:, ..) =
    world_watch_support.modifier_starts()
    as "the modifier start holds a source"
  source
}

/// The modifier a told start applies.
pub fn modifier() -> Modifier {
  let assert creature.ModifierStarts(modifier:, ..) =
    world_watch_support.modifier_starts()
    as "the modifier start holds a modifier"
  modifier
}

/// The rows a told hold of unit states carries: state 6 for 8500 ms, no delay.
pub fn rows() -> List(unit_state.Row) {
  [unit_state.Row(state: 6, delay_ms: 0, duration_ms: 8500)]
}

/// The view a cast holds on the creature, of cast 1.
pub fn view() -> CastView {
  CastView(
    caster_unit_id: 21,
    cast_id: 1,
    spell4_id: Spell4Id(41_886),
    primary_target: 7,
    gone: True,
    current: False,
    targets: [],
  )
}

/// One tell of each kind the player's connection sends a creature `unit_id`, by the kind's
/// name.
pub fn payloads(unit_id unit_id: Int) -> List(#(String, relay.Inbound)) {
  let inbounds = [
    relay.Strike(tell: strike(unit_id:)),
    relay.TargetMoved(place: place(), seq: 9, hit_radius: 0.75),
    relay.StrikeAnswered(answered: answered(unit_id:)),
    relay.ModifierStarts(source: source(), modifier: modifier()),
    relay.ModifierEnds(source: source()),
    relay.Thrown(throw: world_watch_support.throw()),
    relay.Despawn(delay_ms: 500, went_at_ms: 6000),
    relay.UnitStates(rows: rows(), went_at_ms: 6000),
    relay.CastViewSet(view: view()),
    relay.CastViewEnds(cast_id: 1),
    relay.ControlsEnd(cast_id: 1),
  ]
  list.map(inbounds, fn(inbound) {
    #(map_spawn_support.inbound_name(inbound), inbound)
  })
}

/// The strike `tell` as the connection `from` tells it in its stay `stay_count`: its own
/// sender and stay named as its striker.
pub fn struck_by(
  tell tell: StrikeTell,
  from from: Int,
  stay_count stay_count: Int,
) -> StrikeTell {
  strike_tell.Strike(
    ..tell,
    from: Connection(ConnectionId(from)),
    striker: case tell.striker {
      strike_tell.PlayerStriker(..) as striker ->
        strike_tell.PlayerStriker(
          ..striker,
          stay: map_support.stay(count: stay_count),
        )
      strike_tell.CreatureStriker(..) as striker -> striker
    },
  )
}
