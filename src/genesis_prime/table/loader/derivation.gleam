//// The values the server builds once when its tables load, each from the
//// tables a rule reads, and stores under the tables' key.

import genesis_prime/game/activate
import genesis_prime/game/amp_spec
import genesis_prime/game/appearance
import genesis_prime/game/communicator
import genesis_prime/game/faction_level
import genesis_prime/game/focus
import genesis_prime/game/level_up
import genesis_prime/game/limited_action_set
import genesis_prime/game/loadout
import genesis_prime/game/objective_action
import genesis_prime/game/objective_link
import genesis_prime/game/passed_in_value
import genesis_prime/game/quest_turn_in
import genesis_prime/game/rating
import genesis_prime/game/shortcut_spell
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/game/spell_surge
import genesis_prime/game/spell_tier
import genesis_prime/game/top_zone
import genesis_prime/game/unit_properties
import genesis_prime/table/loader/store
import genesis_prime/world_map/creature_attack
import gleam/bool
import gleam/list
import gleam/result
import gleam/set.{type Set}

/// Each derived value. A feature whose rule reads a value of the tables that
/// is costly to build adds it here.
/// - The appearance index: the factions of the labels and the rows the
///   character list's bodies are taken from (genesis_prime/game/appearance).
/// - The loadouts: each class and faction's Novice weapon, abilities and gear
///   properties, whose missing rows fail the load (genesis_prime/game/loadout).
/// - The spell plans: the tree of casts each class's level-1 ability starts, whose
///   missing rows, unread costs and cycles fail the load, that of each later ability
///   of a class that the server can plan, and that of each equip spell a worn item puts on
///   its wearer (genesis_prime/game/spell_plan).
/// - The tier plans: the plan of each tier 2 to 9 spell of the planned abilities, built after the
///   plans and the ability tiers, whose missing rows fail the load and whose unbuilt tiers
///   (a cycle among them) are left out and listed (genesis_prime/game/spell_plan `tier_derivation`).
/// - Spell Surge's spell, GameFormula 913's dataint0, whose missing row fails the load
///   (genesis_prime/game/spell_surge).
/// - The spell areas: what each spell of those trees and of the tier plans strikes
///   (genesis_prime/game/spell_area), built after the trees, which it reads from the built value: the list is in
///   build order, and an edit rebuilds the derivations it is given in that order.
/// - The activations: the spell each creature's right-click casts and the plans of those
///   spells, built after the ability trees' sources, whose missing GameFormula 414 row or
///   unreadable Prerequisite row fails the load (genesis_prime/game/activate).
/// - The linked objectives: the quest objectives some creature's row links, built after
///   the activations whose prerequisites its links read (genesis_prime/game/objective_link).
/// - The named objectives: the quest objectives a spell effect advances and an item needs
///   open (genesis_prime/game/objective_action).
/// - The passed-in value: the family-33 budget curve at each level 0 to 150, whose missing
///   GameFormula rows fail the load (genesis_prime/game/passed_in_value).
/// - The shortcut spells: the plan of each spell a cast-a-spell objective names or an item
///   casts on its user, built after the ability trees' sources
///   (genesis_prime/game/shortcut_spell).
/// - The level-up fanfares: the plan of each tier of the Level Up spell, the cast a 0x07A5 is
///   answered with, built after the ability trees' sources (genesis_prime/game/level_up).
/// - The faction levels: each faction's parent and the level of each pair of factions
///   that has a relationship (genesis_prime/game/faction_level).
/// - The communicator's index: the CommunicatorMessages rows of each quest they
///   deliver and the creatures that receive each quest (genesis_prime/game/communicator).
/// - The action bar's slot unlocks: the level each of the twelve slots opens at, whose
///   missing rows fail the load (genesis_prime/game/limited_action_set).
/// - The ability tiers: each base the book can hold with the cost, Spell4 row and level of
///   its tiers, whose repeated tier, missing level row and missing Spell4 row fail the load
///   (genesis_prime/game/spell_tier).
/// - The AMP specs: the EldanAugmentation rows with their categories and GameFormula 942's
///   power, whose missing or unread rows fail the load (genesis_prime/game/amp_spec).
/// - The quest rewards: each quest's Quest2Reward rows, which a turn-in reads
///   (genesis_prime/game/quest_turn_in).
/// - The rating formulas: the hit rule's GameFormula rows (genesis_prime/game/rating).
/// - The Focus formulas: GameFormula 88, 1237, 1243 and 1267, which a healer's Focus
///   reads, whose missing rows fail the load (genesis_prime/game/focus).
/// - The top zones: each WorldZone's top zone, which a cycle in the parent chain
///   fails (genesis_prime/game/top_zone).
/// - The unit property defaults: each UnitProperty2 row's defaultValue, the base of
///   a player's property no 0x262 lists, whose missing rows the rules read fail the
///   load (genesis_prime/game/unit_properties).
/// - The creature damage effects: each spell's damage effects in the order they take effect,
///   which the content load asks for once for every spell of every creature
///   (genesis_prime/world_map/creature_attack).
pub fn all() -> List(store.Derivation) {
  [
    spell_tier.derivation(),
    appearance.derivation(),
    loadout.derivation(left_out: abilities_left_out),
    spell_plan.derivation(area_checked: spell_area.checker),
    spell_plan.tier_derivation(area_checked: spell_area.checker),
    spell_surge.derivation(),
    spell_area.derivation(),
    activate.derivation(),
    objective_link.derivation(),
    objective_action.derivation(),
    passed_in_value.derivation(),
    shortcut_spell.derivation(),
    level_up.derivation(),
    limited_action_set.derivation(),
    amp_spec.derivation(),
    faction_level.derivation(),
    communicator.derivation(),
    quest_turn_in.derivation(),
    rating.derivation(),
    focus.derivation(),
    top_zone.derivation(),
    unit_properties.derivation(),
    creature_attack.derivation(),
  ]
}

/// Whether a loadout holds the abilities above level 1 that the spell plans leave out
/// (`spell_plan.unplanned`): the book then lists them and a press of one is refused
/// unknown. `False` leaves them out of every loadout, so no character holds them. The
/// switch stays `True`.
const give_unplanned_abilities = True

/// The Spell4 ids of the later abilities no loadout holds, or `Error(Nil)` when the plans
/// cannot be built (the plans' own derivation then fails the load with the reason).
fn abilities_left_out(tables: store.Tables) -> Result(Set(Int), Nil) {
  use <- bool.guard(when: give_unplanned_abilities, return: Ok(set.new()))
  spell_plan.unplanned(tables:, area_checked: spell_area.checker)
  |> result.replace_error(Nil)
  |> result.map(fn(unplanned) {
    list.map(unplanned, fn(one) { one.spell4_id }) |> set.from_list
  })
}
