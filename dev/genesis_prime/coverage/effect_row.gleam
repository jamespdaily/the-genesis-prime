//// How many Spell4Effects rows the plan does not read, by effect type, which the effect
//// measure counts rows by. A row is read as `effect_row_read.is_read` says; the measure
//// restates none of the load's rules.
////
//// - A DespawnUnit row in a spell the activate
////   cast names (a creature's activate column, the default spell or an item's use) is the
////   exception `unread_by_type` makes: the plan applies it, the activate cast drops it
////   (`activate.drops_despawn`), so it is not read, unless a Proxy or Proc names the spell
////   as its child, which applies the row by that route.

import genesis_prime/game/effect_row_read
import genesis_prime/shared/activate
import genesis_prime/shared/spell_plan
import genesis_prime/table/loader/store
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/set

/// How many of these rows the plan does not read, by effect type. A type with no such row
/// has no entry. A DespawnUnit row the plan applies in a spell the activate cast names
/// (`activate.activated_spell_ids`) is not read either: the activate cast drops it
/// (`activate.drops_despawn`), unless a Proxy or Proc names the spell as its child, which
/// applies the row by that route; a QuestAdvanceObjective row aimed at the primary target
/// alone is dropped the same way (`activate.drops_quest_advance`).
pub fn unread_by_type(
  tables tables: store.Tables,
  effects effects: List(Spell4Effects),
) -> Dict(Int, Int) {
  let sources = spell_plan.sources_of(tables:)
  let place_of = effect_row_read.places(tables:, effects:)
  let activated = activate.activated_spell_ids(tables:, sources:)
  list.fold(effects, dict.new(), fn(counts, effect) {
    let dropped =
      {
        activate.drops_despawn(effect:) || activate.drops_quest_advance(effect:)
      }
      && set.contains(activated, effect.spell_id)
      && !spell_plan.is_child(sources:, spell4_id: effect.spell_id)
    case
      effect_row_read.is_read(
        tables:,
        sources:,
        place: place_of(effect.spell_id),
        effect:,
      )
      && !dropped
    {
      True -> counts
      False ->
        dict.upsert(counts, effect.effect_type, fn(found) {
          option.unwrap(found, 0) + 1
        })
    }
  })
}
