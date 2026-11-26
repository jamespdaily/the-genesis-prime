//// What a creature tells a player and what a player tells a creature, both through the
//// map, and the checks the map makes before it delivers either
//// (genesis_prime/world_map/map). A creature sends the map a `Relay` naming the player's
//// connection and stay with a `Payload`; the map admits it by the creature's running
//// state and life and by the table below, then sends the player's connection the
//// payload in the form it takes, for the stay named. A player's connection sends the map
//// a `TellCreature` naming itself, its stay, the creature's unit and life and an
//// `Inbound`; the map admits it by the creature's running state and life and by the
//// table below, then sends the creature `ToldCreature` with the sender and stay the relay
//// named, never the payload's. The creature's news of its own unit is no payload: it
//// goes as a `Broadcast` or a `Snapshot`, which the map relays through the relation it
//// holds for each viewer, so no news reaches a viewer that the relation does not name.
////
//// ```
//// creature                 map                                        player's connection
//// Relay(unit, life, to, stay, payload) ─▶ spawn of (unit, life) runs?  no: dropped
////                                         `to` is a player of the map in `stay`?  no: dropped
////                                         Relayed(stay, Tell(payload)) ─▶ ForStay(stay, ..)
////
//// player's connection P    map                                        creature
//// TellCreature(P, stay, unit, life, inbound) ─▶ spawn of (unit, life) runs?  no: dropped
////                                         source check of the kind (`TargetMoved`: P is a
////                                         player of the map in `stay`?)  no: dropped
////                                         ToldCreature(P, stay, inbound) ─▶ the creature's message
//// ```
////
//// The table of kinds, one row for each `Payload` and each `Inbound`: which way it goes,
//// the check on its destination and the check on its source. A destination check is
//// never sight: an answer or a tell reaches a player in its current stay whether or not
//// it sees the creature, and a tell reaches a running creature whatever the sender sees.
////
//// | Payload | Kind | Destination check | Source check |
//// |---|---|---|---|
//// | `Struck` | the answer to a player's strike | the player's current stay | none |
//// | `KillCredit` | the credit for the kill | the player's current stay | none |
//// | `Fight` | the creature's threat, release or strike of the player | the player's current stay | none |
//// | `Strike` | a player's strike on the creature | the running creature | none here: the strike names its own sender, which the map checks against the relay |
//// | `TargetMoved` | where a player that may be on the creature's threat list stands | the running creature | the sender is a player of the map in the stay the relay names |
//// | `StrikeAnswered` | the player's answer to the creature's strike | the running creature | none |
//// | `ModifierStarts` | a property modifier of a player's spell starts on the creature | the running creature | the sender is a player of the map in the stay the relay names |
//// | `ModifierEnds` | the modifier of a source ends | the running creature | none |
//// | `Thrown` | a ForcedMove effect of a player's cast throws the creature | the running creature | none |
//// | `Despawn` | a DespawnUnit effect of a player's cast removes the creature | the running creature | none |
//// | `UnitStates` | the UnitStateSet rows of a player's cast hold on the creature | the running creature | none |
//// | `CastViewSet` | what a player's cast holds on the creature | the running creature | the sender is a player of the map in the stay the relay names |
//// | `CastViewEnds` | a cast holds nothing on the creature any more | the running creature | none |
//// | `ControlsEnd` | the states a cast landed on the creature end | the running creature | none |

import genesis_prime/game/experience.{type Credit}
import genesis_prime/game/forced_move
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{
  type Answered, type Fight, type Tell as StrikeTell,
}
import genesis_prime/game/unit_casts
import genesis_prime/game/unit_news.{type PeerNews}
import genesis_prime/game/unit_properties
import genesis_prime/game/unit_state

/// What a creature tells one player through the map.
pub type Payload {
  /// The answer to the player's strike on the creature.
  Struck(answered: Answered)
  /// The credit for the kill the player's blow made.
  KillCredit(credit: Credit)
  /// The creature threatens, releases or strikes the player.
  Fight(told: Fight)
}

/// What the map sends a player's connection for a creature: the creature's news,
/// which it relays through a relation, or a payload the creature told.
pub type Delivered {
  /// News of the creature's unit, from a snapshot's burst or a broadcast, for a
  /// viewer whose relation the map holds as relaying.
  News(news: PeerNews)
  /// A payload the creature told the player.
  Tell(payload: Payload)
}

/// The check on where a relayed payload goes.
pub type Destination {
  /// The player is in the map and its stay is the one the relay names.
  PlayersCurrentStay
}

/// The check on where a relayed payload comes from.
pub type Source {
  /// No check: the payload's own rules decide.
  NoSourceCheck
}

/// The destination and source checks of a payload's kind.
pub type Kind {
  Kind(destination: Destination, source: Source)
}

/// The kind of a payload, from the table above.
pub fn kind_of(payload payload: Payload) -> Kind {
  case payload {
    Struck(..) -> Kind(destination: PlayersCurrentStay, source: NoSourceCheck)
    KillCredit(..) ->
      Kind(destination: PlayersCurrentStay, source: NoSourceCheck)
    Fight(..) -> Kind(destination: PlayersCurrentStay, source: NoSourceCheck)
  }
}

/// What a player's connection tells one running creature through the map. No payload
/// names its sender but `Strike`, whose `from` and striker's stay the map checks against
/// the relay's: the map names the sender and the stay to the creature (`ToldCreature`).
pub type Inbound {
  /// The strike of a cast's go, which the creature's owner process decides
  /// (genesis_prime/game/strike_tell).
  Strike(tell: StrikeTell)
  /// The player stands at `place`, its move `seq`, with its race's hit radius, for a
  /// creature that holds it on its threat list.
  TargetMoved(place: Place, seq: Int, hit_radius: Float)
  /// The player's answer to the creature's strike on it.
  StrikeAnswered(answered: Answered)
  /// A property modifier of the player's spell starts on the creature.
  ModifierStarts(
    source: unit_properties.Source,
    modifier: unit_properties.Modifier,
  )
  /// The property modifier of `source` ends on the creature.
  ModifierEnds(source: unit_properties.Source)
  /// A ForcedMove effect of the player's cast throws the creature.
  Thrown(throw: forced_move.Throw)
  /// A DespawnUnit effect of the player's cast removes the creature `delay_ms` after
  /// `went_at_ms`, the monotonic time of the go.
  Despawn(delay_ms: Int, went_at_ms: Int)
  /// The UnitStateSet rows of the player's cast hold their states on the creature, each
  /// from `went_at_ms`, the monotonic time of the go, plus its delay.
  UnitStates(rows: List(unit_state.Row), went_at_ms: Int)
  /// The player's cast holds `view` on the creature: its one target, the whole of it.
  CastViewSet(view: unit_casts.CastView)
  /// The player's cast `cast_id` holds nothing on the creature any more.
  CastViewEnds(cast_id: Int)
  /// The player's cast `cast_id` no longer holds a node on the creature that holds the
  /// states the cast landed, so each of those states ends.
  ControlsEnd(cast_id: Int)
}

/// The check on where an inbound payload goes.
pub type InboundDestination {
  /// The spawn of the creature's unit runs under the life the tell names (`Live`,
  /// `Retiring`, `Respawning` or `Releasing`).
  RunningCreature
}

/// The check on where an inbound payload comes from.
pub type InboundSource {
  /// No check: the payload's own rules decide.
  NoSenderCheck
  /// The sender is a player of the map in the stay the relay names.
  SenderInCurrentStay
}

/// The destination and source checks of an inbound payload's kind.
pub type InboundKind {
  InboundKind(destination: InboundDestination, source: InboundSource)
}

/// The kind of an inbound payload, from the table above.
pub fn inbound_kind_of(inbound inbound: Inbound) -> InboundKind {
  case inbound {
    Strike(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    TargetMoved(..) ->
      InboundKind(destination: RunningCreature, source: SenderInCurrentStay)
    StrikeAnswered(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    ModifierStarts(..) ->
      InboundKind(destination: RunningCreature, source: SenderInCurrentStay)
    ModifierEnds(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    Thrown(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    Despawn(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    UnitStates(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    CastViewSet(..) ->
      InboundKind(destination: RunningCreature, source: SenderInCurrentStay)
    CastViewEnds(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    ControlsEnd(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
  }
}
