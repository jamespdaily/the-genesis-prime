//// What a unit holds from other units' casts: the changes a caster's cast put on it,
//// and the tells between a caster's connection and the connection of a player that holds
//// one. A pure ledger, kept by the player's connection (`Entered.held`) and by a
//// creature, so the two end a caster's changes by one rule.
////
//// ```
//// caster's connection C                                holder's connection T
////   Tell(T, TellPlayerChange(stay_T, PlayerChangeStarts(C, stay_C, source, change, sight, spell4_id, effect)))
////                                  ─▶ started(by: C, source, .., spell4_id, effect)
////   Tell(T, TellPlayerChange(stay_T, PlayerChangeEnds(C, source)))
////                                  ─▶ released(source)
////   the map's UnseenBy(C)          ─▶ released_unseen(C): the sources with `EndsWhenUnseen`
////   the map's Gone(C's unit)       ─▶ released_with_unit(unit): every source of that unit
////   C's connection ends (creature) ─▶ released_by(C): every source of C
////   T dies                         ─▶ all(), then new()
////   a viewer arrives at T          ─▶ cast_views(T's unit, now): the casts T's create lists
////   a release leaves a cast no source ─▶ casts_left(released): the casts T tells its viewers ended
//// ```
////
//// - **A source is held once**, by the caster that started it: a cast id names its caster
////   (genesis_prime/game/cast/state), so a second caster never starts a held source.
//// - **A source lists its cast**: the tell carries the cast's Spell4 id and the change's
////   effect with the go's own monotonic time as its start (`unit_casts.held_effect_of`, the
////   function the caster's own node uses), so `cast_views` lists the one cast the caster's
////   node on the player lists, with the same effects, delay and time left
////   (`opcode.0x262.casts`).
//// - **A source of a spell with propertyFlags 0x100 outlives its caster's sight**: the
////   client's removal of a caster's unit finishes the casts it made, and so ends their buffs
////   on other units, unless that flag keeps the cast (fact `cast.target_node_end`).
////   `kept_casts_of_unit` names those casts when the unit leaves, and `holds_cast` says
////   when the last source of one has ended, which is when the client is written its end.
////

import genesis_prime/game/unit_casts
import genesis_prime/game/unit_properties.{type Source}
import genesis_prime/step.{type ConnectionId}
import genesis_prime/table/id.{type Spell4Id}
import genesis_prime/world_map/stay.{type Stay}
import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/set.{type Set}

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
    spell4_id: Spell4Id,
    effect: unit_casts.HeldEffect,
  )
  /// The cast's node on the player has ended: the change of `source` that `from` started
  /// is taken off.
  PlayerChangeEnds(from: ConnectionId, source: Source)
  /// The go of the cast `cast_id` that `from` started has told the player each of its
  /// changes: the player starts the cast for each of its viewers outside `audience` (the
  /// connections the caster told the cast's 0x7ff) except `from`, from what it holds of the
  /// cast. It names no stay: the player's own stay is fenced where it is taken, and the
  /// guard is the ledger's (`holds_cast_from`).
  PlayerCastWent(from: ConnectionId, cast_id: Int, audience: Set(ConnectionId))
}

/// What a player lists of a cast that holds a change on it: the cast's spell and the
/// change's effect as a create lists it.
type Listing {
  Listing(spell4_id: Spell4Id, effect: unit_casts.HeldEffect)
}

type Entry {
  /// A source of another player's cast: the caster's connection and unit, how the change
  /// keeps when the caster leaves sight, and what a create lists of it.
  PlayerSource(
    source: Source,
    by: ConnectionId,
    unit_id: Int,
    sight: Sight,
    listing: Listing,
  )
  /// A source of a creature's, held for its connection until the connection ends: no unit,
  /// no sight rule and nothing listed.
  CreatureSource(source: Source, by: ConnectionId)
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
/// `sight` says and listed to a viewer as the cast of `spell4_id` with the effect `effect`:
/// `True` when it was not held. The same source told again by its holder keeps its place
/// and takes the new spell and effect (a later go of one cast); told by another connection
/// it changes nothing.
pub fn started(
  held held: Held,
  by by: ConnectionId,
  unit_id unit_id: Int,
  source source: Source,
  sight sight: Sight,
  spell4_id spell4_id: Spell4Id,
  effect effect: unit_casts.HeldEffect,
) -> #(Held, Bool) {
  let listing = Listing(spell4_id:, effect:)
  case holder_of(held:, source:) {
    Ok(holder) if holder == by -> #(
      Held(
        entries: list.map(held.entries, fn(entry) {
          case entry {
            PlayerSource(..) if entry.source == source ->
              PlayerSource(..entry, listing:)
            PlayerSource(..) | CreatureSource(..) -> entry
          }
        }),
      ),
      False,
    )
    Ok(_) | Error(Nil) ->
      added(
        held:,
        entry: PlayerSource(source:, by:, unit_id:, sight:, listing:),
      )
  }
}

/// The source `source` held for the connection `by`, whose unit is not known and whose
/// change ends with the connection: as `started`. A source held this way (a creature's)
/// has no sight rule and lists nothing, and is taken only by `released_by` and `released`.
pub fn started_by_connection(
  held held: Held,
  by by: ConnectionId,
  source source: Source,
) -> #(Held, Bool) {
  added(held:, entry: CreatureSource(source:, by:))
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
    case entry {
      PlayerSource(sight: EndsWhenUnseen, ..) -> entry.by == by
      PlayerSource(sight: KeptWhenUnseen, ..) | CreatureSource(..) -> False
    }
  })
}

/// Every source whose caster's unit is `unit_id` taken out, in the order they started:
/// the caster's unit is gone, which ends a change that outlives sight as well.
pub fn released_with_unit(
  held held: Held,
  unit_id unit_id: Int,
) -> #(Held, List(Source)) {
  released_where(held:, which: fn(entry) {
    case entry {
      PlayerSource(unit_id: caster_unit_id, ..) -> caster_unit_id == unit_id
      CreatureSource(..) -> False
    }
  })
}

fn released_where(
  held held: Held,
  which which: fn(Entry) -> Bool,
) -> #(Held, List(Source)) {
  let #(taken, kept) = list.partition(held.entries, which)
  #(Held(entries: kept), list.map(taken, fn(entry) { entry.source }))
}

/// The casts of the unit `unit_id` with a source that outlives its caster's sight
/// (`KeptWhenUnseen`), each once, in the order their first source started: the casts the
/// client keeps with their buffs when the unit is removed.
pub fn kept_casts_of_unit(held held: Held, unit_id unit_id: Int) -> List(Int) {
  list.filter(held.entries, fn(entry) {
    case entry {
      PlayerSource(unit_id: caster_unit_id, sight: KeptWhenUnseen, ..) ->
        caster_unit_id == unit_id
      PlayerSource(sight: EndsWhenUnseen, ..) | CreatureSource(..) -> False
    }
  })
  |> list.map(fn(entry) { entry.source.cast_id })
  |> list.unique
}

/// Whether any source of the cast `cast_id` is held.
pub fn holds_cast(held held: Held, cast_id cast_id: Int) -> Bool {
  list.any(held.entries, fn(entry) { entry.source.cast_id == cast_id })
}

/// Whether a source of the cast `cast_id` that the connection `by` started is held.
pub fn holds_cast_from(
  held held: Held,
  cast_id cast_id: Int,
  by by: ConnectionId,
) -> Bool {
  let _ = #(held, cast_id, by)
  False
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

/// The casts the unit `holder_unit_id` holds from other players' casts, as a create lists
/// them at `now_ms`: one view for each cast with a listed source, in cast id order, the
/// caster's unit, the cast's spell, the holder as primary and only target with one stack,
/// the cast gone (a landed change is told at the go) and each effect in the order its source
/// started. A source with no caster unit (a creature's) is left out, and so is an effect
/// whose end is at or before `now_ms`: its end tell may still be on its way.
pub fn cast_views(
  held held: Held,
  holder_unit_id holder_unit_id: Int,
  now_ms now_ms: Int,
) -> List(unit_casts.CastView) {
  let listed =
    list.filter_map(held.entries, fn(entry) {
      case entry {
        PlayerSource(
          unit_id: caster_unit_id,
          listing: Listing(spell4_id:, effect:),
          ..,
        ) ->
          case effect.ends {
            unit_casts.EndsAt(ms:) if ms <= now_ms -> Error(Nil)
            unit_casts.EndsAt(..) | unit_casts.UntilRemoved ->
              Ok(#(entry.source.cast_id, caster_unit_id, spell4_id, effect))
          }
        CreatureSource(..) -> Error(Nil)
      }
    })
  list.map(list.unique(list.map(listed, fn(one) { one.0 })), fn(cast_id) {
    let of_cast = list.filter(listed, fn(one) { one.0 == cast_id })
    let assert [#(_, caster_unit_id, spell4_id, _), ..] = of_cast
      as "a cast id taken from the listed sources has one"
    unit_casts.CastView(
      caster_unit_id:,
      cast_id:,
      spell4_id:,
      primary_target: holder_unit_id,
      gone: True,
      current: False,
      targets: [
        unit_casts.ViewTarget(
          unit_id: holder_unit_id,
          count: 1,
          effects: list.map(of_cast, fn(one) { one.3 }),
        ),
      ],
    )
  })
  |> list.sort(fn(left, right) { int.compare(left.cast_id, right.cast_id) })
}

/// The cast ids of `released` of which `held` holds no source any more, each once, in
/// cast id order: the casts a release has just ended on the unit.
pub fn casts_left(
  held held: Held,
  released released: List(Source),
) -> List(Int) {
  casts_without_source(
    held:,
    cast_ids: list.map(released, fn(source) { source.cast_id }),
  )
}

/// The cast ids of `cast_ids` of which `held` holds no source, each once, in cast id order.
pub fn casts_without_source(
  held held: Held,
  cast_ids cast_ids: List(Int),
) -> List(Int) {
  list.unique(cast_ids)
  |> list.filter(fn(cast_id) { !holds_cast(held:, cast_id:) })
  |> list.sort(int.compare)
}
