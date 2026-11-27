//// What a player's casts hold on creatures, told to each creature so a viewer that comes
//// into sight of the creature later is listed the buff with its time left.
////
//// ```
//// cast state (nodes, each with the life of the creature a round struck)
////   |  cast_state.creature_views
////   v
//// compared  ---- against creature_told ---->  ViewSet / ViewEnds, creature_told replaced
////   |
////   v  the connection tells each change to the creature, through its map (CastViewSet, CastViewEnds)
//// ```
////
//// The compare runs after every input of the player, over the state as the input left it,
//// so every way a node comes, changes or leaves the state is told without a site of its
//// own: a go, a stack off, a removal, a push off, an end by time, a cast that finishes or
//// lingers, the caster's death and its leaving the world.
////
//// - A creature is told only for a node a round struck as that creature
////   (`lasting.Node.struck`); a node on the caster, or on a unit no round hit, is told
////   no one.
//// - A node that lists no effect with a life is no view (`unit_casts.target_of`).
//// - A creature's view of a cast holds that creature's target alone and no cast in
////   progress: a creature shows no player's cast bar (`opcode.0x262.casts`).

import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/pair

import genesis_prime/game/cast/state.{type State, type Told, State, Told}
import genesis_prime/game/unit_casts
import genesis_prime/shared/lasting

/// What the creature is told of one cast.
pub type Change {
  /// The creature `unit_id` of `life` holds this view of the cast: the caster's cast with
  /// that creature's target alone and no cast in progress. It is sent again, whole, whenever
  /// the creature's life or target (its effects' starts and ends) differs from what it was told.
  ViewSet(unit_id: Int, life: Int, view: unit_casts.CastView)
  /// The creature holds no node of the cast `cast_id` any more.
  ViewEnds(unit_id: Int, life: Int, cast_id: Int)
}

/// The nodes the caster holds on creatures now, each with the life of the creature a round struck, its view
/// and its target, by cast id and unit id.
type Held =
  Dict(
    #(Int, Int),
    #(lasting.StruckCreature, unit_casts.CastView, unit_casts.ViewTarget),
  )

/// Compares what the player's casts hold on creatures (`cast_state.creature_views`) with
/// what the creatures were last told (`creature_told`): a `ViewSet` for each node that is
/// new or differs in life or target, and a `ViewEnds` for each told node the state
/// no longer holds, in cast id then unit id order. The state records the result, so a
/// second call with no step between returns no change. A state with nothing told and no
/// stamped node is returned as it is.
pub fn compared(
  cast cast: State,
  caster_unit_id caster_unit_id: Int,
) -> #(State, List(Change)) {
  use <- bool.guard(
    when: dict.is_empty(cast.creature_told) && !any_stamped(cast:),
    return: #(cast, []),
  )
  let held =
    list.map(state.creature_views(cast:, caster_unit_id:), fn(entry) {
      let #(_, view, target) = entry
      #(#(view.cast_id, target.unit_id), entry)
    })
    |> dict.from_list
  let changes =
    list.append(
      list.filter_map(dict.to_list(held), fn(entry) {
        set_of(told: cast.creature_told, key: entry.0, held: entry.1)
      }),
      ends_of(told: cast.creature_told, held:),
    )
  #(
    State(..cast, creature_told: told_of(held:)),
    changes
      |> list.sort(fn(first, second) { key_order(first.0, second.0) })
      |> list.map(pair.second),
  )
}

/// The `ViewSet` of a held node the creature was not told as it is now.
fn set_of(
  told told: Dict(#(Int, Int), Told),
  key key: #(Int, Int),
  held held: #(
    lasting.StruckCreature,
    unit_casts.CastView,
    unit_casts.ViewTarget,
  ),
) -> Result(#(#(Int, Int), Change), Nil) {
  let #(struck, view, target) = held
  case dict.get(told, key) {
    Ok(Told(life:, target: earlier))
      if life == struck.life && earlier == target
    -> Error(Nil)
    Ok(_) | Error(Nil) ->
      Ok(#(key, ViewSet(unit_id: key.1, life: struck.life, view:)))
  }
}

/// The `ViewEnds` of each told node the caster holds no longer.
fn ends_of(
  told told: Dict(#(Int, Int), Told),
  held held: Held,
) -> List(#(#(Int, Int), Change)) {
  dict.to_list(told)
  |> list.filter(fn(entry) { !dict.has_key(held, entry.0) })
  |> list.map(fn(entry) {
    let #(key, earlier) = entry
    #(key, ViewEnds(unit_id: key.1, life: earlier.life, cast_id: key.0))
  })
}

/// What the creatures are told once the held nodes are: each node's life and target.
fn told_of(held held: Held) -> Dict(#(Int, Int), Told) {
  dict.map_values(held, fn(_, entry) {
    let #(struck, _, target) = entry
    Told(life: struck.life, target:)
  })
}

/// Cast id order, then unit id order.
fn key_order(first: #(Int, Int), second: #(Int, Int)) -> order.Order {
  order.break_tie(
    in: int.compare(first.0, second.0),
    with: int.compare(first.1, second.1),
  )
}

/// Whether any cast holds a node a round struck as a creature.
fn any_stamped(cast cast: State) -> Bool {
  list.any(state.holders(cast:), fn(entry) {
    let #(_, holder) = entry
    list.any(dict.values(holder.nodes), fn(node) { option.is_some(node.struck) })
  })
}
