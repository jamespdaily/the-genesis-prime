//// What a creature tells a player through its map, and the checks the map makes
//// before it delivers it (genesis_prime/world_map/map). A creature sends the map a
//// `Relay` naming the player's connection and stay with a `Payload`; the map admits
//// it by the creature's running state and life and by the table below, then sends
//// the player's connection the payload in the form it takes, for the stay named.
//// The creature's news of its own unit is no payload: it goes as a `Broadcast` or a
//// `Snapshot`, which the map relays through the relation it holds for each viewer, so
//// no news reaches a viewer that the relation does not name.
////
//// ```
//// creature                 map                                        player's connection
//// Relay(unit, life, to, stay, payload) ─▶ spawn of (unit, life) runs?  no: dropped
////                                         `to` is a player of the map in `stay`?  no: dropped
////                                         Relayed(stay, Tell(payload)) ─▶ ForStay(stay, ..)
//// ```
////
//// The table of kinds, one row for each `Payload`: where the payload goes, the check on
//// its destination and the check on its source. A destination check is never sight:
//// an answer or a tell reaches a player in its current stay whether or not it sees
//// the creature.
////
//// | Payload | Kind | Destination check | Source check |
//// |---|---|---|---|
//// | `Struck` | the answer to a player's strike | the player's current stay | none |
//// | `KillCredit` | the credit for the kill | the player's current stay | none |
//// | `Fight` | the creature's threat, release or strike of the player | the player's current stay | none |

import genesis_prime/game/experience.{type Credit}
import genesis_prime/game/strike_tell.{type Answered, type Fight}
import genesis_prime/game/unit_news.{type PeerNews}

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
