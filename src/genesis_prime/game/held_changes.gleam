//// What a unit holds from other units' casts: the changes a caster's cast put on it,
//// and the tells between a caster's connection and the connection of a player that holds
//// one. A pure ledger, kept by the player's connection (`Entered.held`) and by a
//// creature, so the two end a caster's changes by one rule.
////
//// ```
//// caster's connection C                                holder's connection T
////   Tell(T, TellPlayerChange(stay_T, PlayerChangeStarts(C, stay_C, source, change, sight)))
////                                  ─▶ started(by: C, source, ..)
////   Tell(T, TellPlayerChange(stay_T, PlayerChangeEnds(C, source)))
////                                  ─▶ released(source)
////   the map's UnseenBy(C)          ─▶ released_unseen(C): the sources with `EndsWhenUnseen`
////   the map's Gone(C's unit)       ─▶ released_with_unit(unit): every source of that unit
////   C's connection ends (creature) ─▶ released_by(C): every source of C
////   T dies                         ─▶ all(), then new()
//// ```
////
//// - **A source is held once**, by the caster that started it: a cast id names its caster
////   (genesis_prime/game/cast/state), so a second caster never starts a held source.
//// - **A source of a spell with propertyFlags 0x100 outlives its caster's sight**: the
////   client's removal of a caster's unit finishes the casts it made, and so ends their buffs
////   on other units, unless that flag keeps the cast (fact `cast.target_node_end`).
////

import genesis_prime/game/unit_properties.{type Source}
import genesis_prime/step.{type ConnectionId}
import genesis_prime/world_map/stay.{type Stay}
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// What a caster's cast changes on a player that is not the caster, as it is told: a
/// property modifier (the UnitPropertyModifier and UnitPropertyConversion rows, and the
/// Proxy-started Interrupt Armor's property), or an absorb pool (an Absorption row) of
/// `amount`, as the caster's formula gave it at the go, that takes the damage types of
/// `mask`.
pub type Change {
  Property(modifier: unit_properties.Modifier)
  Absorb(amount: Int, mask: Int)
}

/// Whether a held change ends when its caster leaves the sight of the unit that holds it.
pub type Sight {
  /// The change ends when the caster is no longer seen: the spell's Spell4 propertyFlags
  /// do not hold 0x100.
  EndsWhenUnseen
  /// The change outlives its caster's sight: the spell's propertyFlags hold 0x100. It ends
  /// by the caster's end tell, or by the caster's unit gone.
  KeptWhenUnseen
}

/// How a change keeps when its caster leaves the sight of the unit that holds it, for a
/// spell the client keeps (`outlives_caster`: Spell4 propertyFlags 0x100) or does not.
pub fn sight_of(outlives_caster outlives_caster: Bool) -> Sight {
  use <- bool.guard(when: outlives_caster, return: KeptWhenUnseen)
  EndsWhenUnseen
}

/// What a caster's connection tells the connection of another player, for the stay of
/// that player (genesis_prime/client_connection `TellPlayerChange`).
pub type PlayerChange {
  /// The change `change` of the cast `source` names is put on the player. `from` is the
  /// caster's connection and `from_stay` its stay, which the player holds the change
  /// against: the player takes it only while that caster is among its viewers with that
  /// stay.
  PlayerChangeStarts(
    from: ConnectionId,
    from_stay: Stay,
    source: Source,
    change: Change,
    sight: Sight,
  )
  /// The cast's node on the player has ended: the change of `source` that `from` started
  /// is taken off.
  PlayerChangeEnds(from: ConnectionId, source: Source)
}

type Entry {
  Entry(source: Source, by: ConnectionId, unit_id: Option(Int), sight: Sight)
}

/// The sources a unit holds from other units' casts, with the connection of the caster
/// of each, in the order they started.
pub opaque type Held {
  Held(entries: List(Entry))
}

/// A unit that holds nothing.
pub fn new() -> Held {
  Held(entries: [])
}

/// The source `source` held for the connection `by` whose unit is `unit_id`, kept as
/// `sight` says: `True` when it was not held, and the same source twice is held once by
/// its first holder.
pub fn started(
  held held: Held,
  by by: ConnectionId,
  unit_id unit_id: Int,
  source source: Source,
  sight sight: Sight,
) -> #(Held, Bool) {
  added(held:, entry: Entry(source:, by:, unit_id: Some(unit_id), sight:))
}

/// The source `source` held for the connection `by`, whose unit is not known and whose
/// change ends with the connection: as `started`. The entry's sight is stored as
/// `EndsWhenUnseen` and nothing reads it: a source held this way (a creature's) is taken only
/// by `released_by` and `released`.
pub fn started_by_connection(
  held held: Held,
  by by: ConnectionId,
  source source: Source,
) -> #(Held, Bool) {
  added(held:, entry: Entry(source:, by:, unit_id: None, sight: EndsWhenUnseen))
}

fn added(held held: Held, entry entry: Entry) -> #(Held, Bool) {
  use <- bool.guard(
    when: list.any(held.entries, fn(held) { held.source == entry.source }),
    return: #(held, False),
  )
  #(Held(entries: list.append(held.entries, [entry])), True)
}

/// The connection that holds `source`, when it is held.
pub fn holder_of(
  held held: Held,
  source source: Source,
) -> Result(ConnectionId, Nil) {
  list.find(held.entries, fn(entry) { entry.source == source })
  |> result.map(fn(entry) { entry.by })
}

/// `source` taken out, with the connection that held it; `Error` when it is not held.
pub fn released(
  held held: Held,
  source source: Source,
) -> Result(#(Held, ConnectionId), Nil) {
  use by <- result.map(holder_of(held:, source:))
  #(Held(entries: list.filter(held.entries, fn(e) { e.source != source })), by)
}

/// Every source of the connection `by` taken out, in the order they started.
pub fn released_by(
  held held: Held,
  by by: ConnectionId,
) -> #(Held, List(Source)) {
  released_where(held:, which: fn(entry) { entry.by == by })
}

/// The sources of the connection `by` that end when their caster is no longer seen
/// (`EndsWhenUnseen`) taken out, in the order they started; a `KeptWhenUnseen` source of
/// `by` stays.
pub fn released_unseen(
  held held: Held,
  by by: ConnectionId,
) -> #(Held, List(Source)) {
  released_where(held:, which: fn(entry) {
    entry.by == by && entry.sight == EndsWhenUnseen
  })
}

/// Every source whose caster's unit is `unit_id` taken out, in the order they started:
/// the caster's unit is gone, which ends a change that outlives sight as well.
pub fn released_with_unit(
  held held: Held,
  unit_id unit_id: Int,
) -> #(Held, List(Source)) {
  released_where(held:, which: fn(entry) { entry.unit_id == Some(unit_id) })
}

fn released_where(
  held held: Held,
  which which: fn(Entry) -> Bool,
) -> #(Held, List(Source)) {
  let #(taken, kept) = list.partition(held.entries, which)
  #(Held(entries: kept), list.map(taken, fn(entry) { entry.source }))
}

/// Every source held, in the order they started.
pub fn all(held held: Held) -> List(Source) {
  list.map(held.entries, fn(entry) { entry.source })
}

/// The connections that hold a source, each once, in the order their first source
/// started.
pub fn connections(held held: Held) -> List(ConnectionId) {
  list.map(held.entries, fn(entry) { entry.by }) |> list.unique
}
