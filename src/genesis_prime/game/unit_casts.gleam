//// The casts a unit create (0x262) lists, so a player that comes into sight
//// of a casting player shows the cast bar the caster holds and the buffs its
//// casts hold, each with the time it has left.
////
//// ```
//// cast state --views--> CastView --listed--> --entry_of--> UnitCreateCast list
////    (caster's connection)  (one per cast)   (the casts a    (tail.casts of the
////                                             create tells)   create)
//// ```
////
//// - The list is a 9-bit count, so 511 entries at most, in cast id order
////   (`opcode.0x262.casts`).
//// - An entry's bit is 1 for a cast whose first go has not gone and 0 after,
////   the client's cast state 2 or 3 (`cast.state`, `RestoreCastFromCreate
////   0x14053da80`).
//// - No entry has cast id 0: the client files such a cast as pending, so
////   `ApplyUnitCreateCasts 0x140458fe0` fails and skips every later entry
////   (`CreateCast 0x140561780`).
//// - A cast is listed when it is the unit's current cast, or when its node on a
////   unit holds an effect a unit create lists (`lasting.Listed`): its entry then
////   names that unit as a target with each such effect, and the client builds the
////   buff there as a watcher's did (`opcode.0x262.casts`). `listed` is the one
////   place that decides it, and the audience of a cast joins by the same list, so a
////   viewer is told the news of exactly the casts it was shown.
//// - An effect's delay is the delay still to run (0 once it has run) and its
////   lifetime the time left from now, counted with that delay, never 0 for an
////   effect that still ends and 0 only for one that lasts until removed
////   (`opcode.0x7f4.effect_delay`, `opcode.0x7f4.effect_time`).
//// - A node whose smallest delay is 1 and that holds an effect lasting until removed is
////   told no delay of 1: the client's node sums its earliest start (that smallest delay)
////   and its longest lifetime (all bits for such an effect) and builds no buff when that
////   is 0, so a delay of 1 is told as 2 (`opcode.0x7f4.first_start`).
//// - An entry lists no position, so the client draws no server-placed
////   telegraph row.
////
//// Not covered, for the coverage measure:
//// - A viewer that arrives while a live cast that is not the current cast holds
////   no node yet (a child cast before its first go) is not listed that cast and
////   told none of its later news, including the node its go makes: the client can
////   build that node only from the cast.
//// - The delay still to run of an effect an earlier go put on a node is counted from
////   the node's latest go, so an arrival within a row's delay of a later go of a
////   repeating cast is told a delay that already ran at the earlier go (the lifetime
////   is right: the client arms it from the later go).
//// - The item-use spells' telegraph rows that carry an end replay from the
////   viewer's arrival, not from where the cast stood.
//// - A creature's list holds the casts its viewers' casters told it of (`CastViewSet`),
////   not a cast of its own spells. A `CastViewSet` that reaches the creature after its
////   create was written leaves the node missing for that viewer until the cast's next
////   change on it, and a 0x811 for the creature that reaches a viewer before the
////   creature's create leaves the node the entry makes until the cast's 0x7fe.
//// - A creature that leaves its caster's sight loses the view for arrivals, while a viewer
////   already seeing both keeps the node until the cast's 0x7fe (the caster's client
////   destroys its nodes on the creature at its own 0x355, `0x1404550d0`).
//// - A crowd-control state a player holds on a creature is not listed, as for players.
//// - A creature's create keeps an entry only for a cast whose start its viewer was written
////   (`client_casts.is_written`), though the client would show a cast whose caster it does not
////   know (`cast.unknown_caster`).
//// - A player's list holds its own casts and the casts that other players' casts hold on it
////   (`held_changes.cast_views`: an absorb, an Interrupt Armor row or a modifier row a press
////   at the player landed); the Fluff rows of another player's press (Spell4 bases 26762,
////   35526, 63087, 19030's child 54912 and 47675's children) are listed on it by the caster's
////   own node and by no ledger.

import genesis_prime/game/cast/target_info
import genesis_prime/game/lasting
import genesis_prime/message/combat_result
import genesis_prime/message/spell_target_info.{type SpellTargetInfo}
import genesis_prime/message/unit_create_cast.{
  type UnitCreateCast, UnitCreateCast,
}
import genesis_prime/table/id.{type Spell4EffectsId, type Spell4Id}
import gleam/int
import gleam/list
import gleam/result

/// The most entries the list's 9-bit count holds.
const most_entries = 511

/// When a held effect ends.
pub type EffectEnd {
  /// The effect ends at this monotonic time in milliseconds.
  EndsAt(ms: Int)
  /// The effect ends only when the server takes it off (Spell4Effects flags bit 2).
  UntilRemoved
}

/// An effect a node holds that a unit create lists: its Spell4Effects id, the
/// monotonic time it starts (the go plus its delay) and when it ends.
pub type HeldEffect {
  HeldEffect(effect_id: Spell4EffectsId, starts_ms: Int, ends: EffectEnd)
}

/// A unit a cast holds a node on, with the stacks the cast gave there and the effects
/// of the node that a unit create lists.
pub type ViewTarget {
  ViewTarget(unit_id: Int, count: Int, effects: List(HeldEffect))
}

/// One cast of a unit as the viewer's client is told of it: who casts it, at
/// whom, under which id and spell, whether its first go has gone, whether it is
/// the caster's current cast (the one its cast bar shows) and the units it holds
/// a node on.
pub type CastView {
  CastView(
    caster_unit_id: Int,
    cast_id: Int,
    spell4_id: Spell4Id,
    primary_target: Int,
    gone: Bool,
    current: Bool,
    targets: List(ViewTarget),
  )
}

/// The effect a row of a node holds, as a create lists it: it starts at its go plus its
/// delay and ends at its go plus its lifetime (`lasting.life_of`, with
/// `longer_of_delay_and_duration` for the spells whose record flag says so); `Error(Nil)`
/// when the row has no life. `go_ms` is a monotonic time, which can be negative.
pub fn held_effect_of(
  effect_id effect_id: Spell4EffectsId,
  row row: lasting.LastingRow,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
  go_ms go_ms: Int,
) -> Result(HeldEffect, Nil) {
  let life =
    lasting.life_of(effects: [row], longer_of_delay_and_duration:, go_ms:)
  use ends <- result.map(case life {
    lasting.NoLife -> Error(Nil)
    lasting.UntilRemoved -> Ok(UntilRemoved)
    lasting.EndsAt(ms:) -> Ok(EndsAt(ms:))
  })
  HeldEffect(effect_id:, starts_ms: go_ms + row.delay_ms, ends:)
}

/// The target a node is, or `Error(Nil)` when none of its listed effects has a life: a
/// crowd-control state, an ability restriction and a heal applied at once give none.
/// Each listed effect is a `held_effect_of` the node's go.
pub fn target_of(
  node node: lasting.Node,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
) -> Result(ViewTarget, Nil) {
  let effects =
    list.filter_map(node.effects, fn(effect) {
      case effect {
        lasting.LifeOnly(..) -> Error(Nil)
        lasting.Listed(effect_id:, row:) ->
          held_effect_of(
            effect_id:,
            row:,
            longer_of_delay_and_duration:,
            go_ms: node.armed_ms,
          )
      }
    })
  case effects {
    [] -> Error(Nil)
    effects ->
      Ok(ViewTarget(unit_id: node.unit_id, count: node.count, effects:))
  }
}

/// The views a create lists and an audience joins: the current cast and each cast
/// that holds a target, with a cast id above 0, in cast id order, at most 511.
pub fn listed(views views: List(CastView)) -> List(CastView) {
  views
  |> list.filter(fn(view) { view.current || view.targets != [] })
  |> list.filter(fn(view) { view.cast_id > 0 })
  |> list.sort(fn(left, right) { int.compare(left.cast_id, right.cast_id) })
  |> list.take(most_entries)
}

/// The entry of one cast at the monotonic time `now_ms`, or `Error(Nil)` for a cast
/// id 0.
pub fn entry_of(
  view view: CastView,
  now_ms now_ms: Int,
) -> Result(UnitCreateCast, Nil) {
  case view.cast_id {
    0 -> Error(Nil)
    cast_id ->
      Ok(
        UnitCreateCast(
          caster_unit_id: view.caster_unit_id,
          primary_target_unit_id: view.primary_target,
          cast_id:,
          spell4_id: view.spell4_id.value,
          started: case view.gone {
            True -> 0
            False -> 1
          },
          targets: list.index_map(view.targets, fn(target, index) {
            target_of_view(target:, index:, now_ms:)
          }),
          initial_positions: [],
          telegraph_positions: [],
        ),
      )
  }
}

/// The entries a create lists at `now_ms`: those of `listed` views.
pub fn entries_of(
  views views: List(CastView),
  now_ms now_ms: Int,
) -> List(UnitCreateCast) {
  listed(views:)
  |> list.filter_map(fn(view) { entry_of(view:, now_ms:) })
}

/// The target info of one target: each held effect with the delay still to run and the
/// time left from `now_ms`, numbered from 1, a Hit with the node's count. A node whose
/// smallest delay is 1 and that holds an effect lasting until removed is told 2 for a
/// delay of 1 (`target_info.told_delay_ms`).
fn target_of_view(
  target target: ViewTarget,
  index index: Int,
  now_ms now_ms: Int,
) -> SpellTargetInfo {
  let holds_until_removed =
    list.any(target.effects, fn(held) { held.ends == UntilRemoved })
  let delays_ms =
    list.map(target.effects, fn(held) { int.max(0, held.starts_ms - now_ms) })
  target_info.target(
    index:,
    unit_id: target.unit_id,
    instance_count: target.count,
    combat_result: combat_result.Hit,
    effects: list.index_map(target.effects, fn(held, effect_index) {
      target_info.effect(
        effect_id: held.effect_id.value,
        instance_id: effect_index + 1,
        delay_ms: target_info.told_delay_ms(
          delay_ms: int.max(0, held.starts_ms - now_ms),
          node_delays_ms: delays_ms,
          holds_until_removed:,
        ),
        lifetime_ms: case held.ends {
          EndsAt(ms:) -> lasting.time_left_ms(end_ms: ms, now_ms:)
          UntilRemoved -> 0
        },
        result: target_info.bit(),
      )
    }),
  )
}
