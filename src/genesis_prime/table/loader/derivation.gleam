//// The values the server builds once when its tables load, each from the
//// tables a rule reads, and stores under the tables' key.

import genesis_prime/game/activate
import genesis_prime/game/appearance
import genesis_prime/game/communicator
import genesis_prime/game/faction_level
import genesis_prime/game/loadout
import genesis_prime/game/quest_turn_in
import genesis_prime/game/rating
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/game/top_zone
import genesis_prime/game/unit_properties
import genesis_prime/table/loader/store

/// Each derived value. A feature whose rule reads a value of the tables that
/// is costly to build adds it here.
/// - The appearance index: the factions of the labels and the rows the
///   character list's bodies are taken from (genesis_prime/game/appearance).
/// - The loadouts: each class and faction's Novice weapon, abilities and gear
///   properties, whose missing rows fail the load (genesis_prime/game/loadout).
/// - The spell plans: the tree of casts each class's level-1 ability starts, whose
///   missing rows, unread costs and cycles fail the load (genesis_prime/game/spell_plan).
/// - The spell areas: what each spell of those trees strikes (genesis_prime/game/spell_area),
///   built after the trees, which it reads from the built value: the list is in
///   build order, and an edit rebuilds the derivations it is given in that order.
/// - The activations: the spell each creature's right-click casts and the plans of those
///   spells, built after the ability trees' sources, whose missing GameFormula 414 row or
///   unreadable Prerequisite row fails the load (genesis_prime/game/activate).
/// - The faction levels: each faction's parent and the level of each pair of factions
///   that has a relationship (genesis_prime/game/faction_level).
/// - The communicator's index: the CommunicatorMessages rows of each quest they
///   deliver and the creatures that receive each quest (genesis_prime/game/communicator).
/// - The quest rewards: each quest's Quest2Reward rows, which a turn-in reads
///   (genesis_prime/game/quest_turn_in).
/// - The rating formulas: the hit rule's GameFormula rows (genesis_prime/game/rating).
/// - The top zones: each WorldZone's top zone, which a cycle in the parent chain
///   fails (genesis_prime/game/top_zone).
/// - The unit property defaults: each UnitProperty2 row's defaultValue, the base of
///   a player's property no 0x262 lists, whose missing rows the rules read fail the
///   load (genesis_prime/game/unit_properties).
pub fn all() -> List(store.Derivation) {
  [
    appearance.derivation(),
    loadout.derivation(),
    spell_plan.derivation(),
    spell_area.derivation(),
    activate.derivation(),
    faction_level.derivation(),
    communicator.derivation(),
    quest_turn_in.derivation(),
    rating.derivation(),
    top_zone.derivation(),
    unit_properties.derivation(),
  ]
}
