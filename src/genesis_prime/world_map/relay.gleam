//// What a creature tells a player and what a player tells a creature, both through the
//// map, and the checks the map makes before it delivers either
//// (genesis_prime/world_map/map). A creature sends the map a `Relay` naming the player's
//// unit address with a `Payload`; the map admits it by the creature's running state and
//// life and by the table below, then sends the connection that joined that unit the
//// payload in the form it takes, for the stay of the join. A player's connection sends
//// the map a `TellCreature` naming its unit address, the creature's unit and life and an
//// `Inbound`; the map admits it by the creature's running state and life and by the
//// table below, then sends the creature `ToldCreature` with the sender the relay named,
//// never the payload's. The creature's news of its own unit is no payload: it
//// goes as a `Broadcast` or a `Snapshot`, which the map relays through the relation it
//// holds for each viewer, so no news reaches a viewer that the relation does not name.
////
//// ```
//// creature                 map                                        player's connection
//// Relay(unit, life, to, payload) ─▶ spawn of (unit, life) runs?  no: dropped
////                                         `to` is a unit of this run?  no: dropped
////                                         Relayed(stay of to's join, Tell(payload)) ─▶ ForStay(stay, ..)
////
//// player's connection P    map                                        creature
//// TellCreature(a, unit, life, inbound) ─▶ spawn of (unit, life) runs?  no: dropped
////                                         source check of the kind (`TargetMoved`: `a` is a
////                                         unit of this run?)  no: dropped
////                                         ToldCreature(a, inbound) ─▶ the creature's message
//// ```
////
//// The table of kinds, one row for each `Payload`, each `Inbound` and each `Landing`: which
//// way it goes, the check on its destination and the check on its source. A destination check
//// is never sight: an answer or a tell reaches a unit of the run whether or not it sees the
//// creature, and a tell reaches a running creature whatever the sender sees. A
//// landing is what one player's connection tells another through the map: it reaches the told
//// player in the stay the tell names whatever the two see of each other. A local chat line
//// and a unit's news are no landing: the map relays them through a player's relation.
////
//// | Payload | Kind | Destination check | Source check |
//// |---|---|---|---|
//// | `Struck` | the answer to a player's strike | a unit of this run | none |
//// | `KillCredit` | the credit for the kill | a unit of this run | none |
//// | `Fight` | the creature's threat, release or strike of the player | a unit of this run | none |
//// | `Strike` | a player's strike on the creature | the running creature | none here: the strike names its own sender, which the map checks against the relay |
//// | `TargetMoved` | where a player that may be on the creature's threat list stands | the running creature | the sender is a unit of this run |
//// | `StrikeAnswered` | the player's answer to the creature's strike | the running creature | none |
//// | `ModifierStarts` | a property modifier of a player's spell starts on the creature | the running creature | the sender is a unit of this run |
//// | `ModifierEnds` | the modifier of a source ends | the running creature | none |
//// | `Thrown` | a ForcedMove effect of a player's cast throws the creature | the running creature | none |
//// | `Despawn` | a DespawnUnit effect of a player's cast removes the creature | the running creature | none |
//// | `UnitStates` | the UnitStateSet rows of a player's cast hold on the creature | the running creature | none |
//// | `CastViewSet` | what a player's cast holds on the creature | the running creature | the sender is a unit of this run |
//// | `CastViewEnds` | a cast holds nothing on the creature any more | the running creature | none |
//// | `ControlsEnd` | the states a cast landed on the creature end | the running creature | none |
//// | `HealStrike` | the heal rows of a caster's cast, for the told player's life | the told player's current stay | none |
//// | `HealAnswer` | the told player's answer to a heal strike, for the caster's round | the told player's current stay | none |
//// | `ChangeStart` | a change the caster's cast puts on the told player | the told player's current stay | the sender is a player of the map in the stay the tell names |
//// | `ChangeEnd` | the end of a change the caster's cast put on the told player | the told player's current stay | none |
//// | `CastWent` | the caster's go has told the told player each of its changes | the told player's current stay | none |
//// | `AllyEvent` | the events of a blow on the told player that the caster's Proc rows on it wait for | the told player's current stay | none |

import genesis_prime/map/message.{
  type Inbound, type Landing, type Payload, AllyEvent, CastViewEnds, CastViewSet,
  CastWent, ChangeEnd, ChangeStart, ControlsEnd, Despawn, Fight, HealAnswer,
  HealStrike, KillCredit, ModifierEnds, ModifierStarts, Strike, StrikeAnswered,
  Struck, TargetMoved, Thrown, UnitStates,
}

/// The check on where a relayed payload goes.
pub type Destination {
  /// The unit the relay names is a unit of this run: one that left or ended is not.
  UnitOfRun
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
    Struck(..) -> Kind(destination: UnitOfRun, source: NoSourceCheck)
    KillCredit(..) -> Kind(destination: UnitOfRun, source: NoSourceCheck)
    Fight(..) -> Kind(destination: UnitOfRun, source: NoSourceCheck)
  }
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
  /// The sender is a unit of this run.
  SenderUnitOfRun
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
      InboundKind(destination: RunningCreature, source: SenderUnitOfRun)
    StrikeAnswered(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    ModifierStarts(..) ->
      InboundKind(destination: RunningCreature, source: SenderUnitOfRun)
    ModifierEnds(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    Thrown(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    Despawn(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    UnitStates(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    CastViewSet(..) ->
      InboundKind(destination: RunningCreature, source: SenderUnitOfRun)
    CastViewEnds(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
    ControlsEnd(..) ->
      InboundKind(destination: RunningCreature, source: NoSenderCheck)
  }
}

/// The check on where a landing goes.
pub type LandingDestination {
  /// The told player is in the map in the stay the tell names, whether or not it sees the
  /// sender.
  TellsCurrentStay
}

/// The check on where a landing comes from.
pub type LandingSource {
  /// No check: the landing's own rules decide.
  NoLandingSourceCheck
  /// The sender is a player of the map in the stay the tell names for it.
  SenderStayIsCurrent
}

/// The destination and source checks of a landing's kind.
pub type LandingKind {
  LandingKind(destination: LandingDestination, source: LandingSource)
}

/// The kind of a landing, from the table above.
pub fn landing_kind_of(landing landing: Landing) -> LandingKind {
  case landing {
    HealStrike(..) ->
      LandingKind(destination: TellsCurrentStay, source: NoLandingSourceCheck)
    HealAnswer(..) ->
      LandingKind(destination: TellsCurrentStay, source: NoLandingSourceCheck)
    ChangeStart(..) ->
      LandingKind(destination: TellsCurrentStay, source: SenderStayIsCurrent)
    ChangeEnd(..) ->
      LandingKind(destination: TellsCurrentStay, source: NoLandingSourceCheck)
    CastWent(..) ->
      LandingKind(destination: TellsCurrentStay, source: NoLandingSourceCheck)
    AllyEvent(..) ->
      LandingKind(destination: TellsCurrentStay, source: NoLandingSourceCheck)
  }
}
