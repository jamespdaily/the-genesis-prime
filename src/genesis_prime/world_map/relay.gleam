//// What a creature tells a player through its map, and the checks the map makes
//// before it delivers it (genesis_prime/world_map/map). A creature sends the map a
//// `Relay` naming the player's connection and stay with a `Payload`; the map admits
//// it by the creature's running state and life and by the table below, then sends
//// the player's connection the payload in the form it takes, for the stay named.
////
//// ```
//// creature                 map                                        player's connection
//// Relay(unit, life, to, stay, payload) ─▶ spawn of (unit, life) runs?  no: dropped
////                                         `to` is a player of the map in `stay`?  no: dropped
////                                         Relayed(stay, payload) ──────▶ ForStay(stay, ..)
//// ```
////
//// The table of kinds, one row for each `Payload`: where the payload goes, the check on
//// its destination and the check on its source. A destination check is never sight:
//// an answer or a tell reaches a player in its current stay whether or not it sees
//// the creature.
////
//// | Payload | Kind | Destination check | Source check |
//// |---|---|---|---|
//// | `News` | the creature's news to a viewer, from a snapshot's burst | the player's current stay | none: the map's relation decides who is sent it |
//// | `Struck` | the answer to a player's strike | the player's current stay | none |
//// | `KillCredit` | the credit for the kill | the player's current stay | none |

import genesis_prime/game/experience.{type Credit}
import genesis_prime/game/strike_tell.{type Answered, type Fight}
import genesis_prime/game/unit_news.{type PeerNews}

/// What a creature tells one player through the map.
pub type Payload {
  /// News of the creature's unit for a viewer that the map holds as relaying.
  News(news: PeerNews)
  /// The answer to the player's strike on the creature.
  Struck(answered: Answered)
  /// The credit for the kill the player's blow made.
  KillCredit(credit: Credit)
  /// The creature threatens, releases or strikes the player.
  Fight(told: Fight)
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
    News(..) -> Kind(destination: PlayersCurrentStay, source: NoSourceCheck)
    Struck(..) | KillCredit(..) | Fight(..) ->
      Kind(destination: PlayersCurrentStay, source: NoSourceCheck)
  }
}
