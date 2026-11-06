//// A player's own properties: each UnitProperty2 id's base and value, and the
//// property modifiers of its own spells that change the value for their time. The
//// connection keeps one `Properties` for its player (genesis_prime/game/world_entry
//// `Entered`), applies and removes a modifier when the cast rule says so
//// (genesis_prime/game/cast `PropertyStarts`, `PropertyEnds`), tells the player's
//// client and its viewers the entries that changed (0x93a), and hands each rule the
//// value it reads. The module is pure.
////
//// ```
//// cast rule                connection                         clients
////  go + delay
////    PropertyStarts ─────▶ apply(source, modifier) ─────────▶ 0x93a to the player,
////                            changed entries                   PropertiesChanged to viewers
////                            max health or shield changed ──▶ player_life takes the new maximum
////  go + delay + duration, a node taken off, the caster dies
////    PropertyEnds ───────▶ remove(source) / remove_cast ────▶ 0x93a, PropertiesChanged
////
//// strike, damage, defence, regeneration ◀── value(property)
//// ```
////
//// - **The client works out no property.** It stores the base and the value of each
////   property that 0x262 or 0x93a last sent, so the server works out every value and
////   sends the result (`UnitProperty2.client_value`, `opcode.0x93a`).
//// - **The base** is the property's word in the player's 0x262 and, for a property the
////   0x262 does not list, the property's UnitProperty2 defaultValue, which is what the
////   client starts every property of a player at (`opcode.0x262`,
////   `SetUnitPropertiesFromCreate` 0x1404584b0).
//// - **One modifier** changes a value x to x * multiplier + flat, plus perLevel * the
////   player's level when perLevel is set (`Spell4Effects.effectType.11.change`).
//// - **Several modifiers on one property** apply to the base in the order they
////   started, each to the result of the one before. This is the server's choice: the
////   client has no value for it, and the mode of a row (dataBits01) does not change the
////   formula. A retail 0x93a recording of Swiftness 10663 with Sprint 1921 on
////   MoveSpeedMultiplier would settle it (`Spell4Effects.effectType.11.change`).
//// - **A change reports the property's base and value** as the 0x93a carries them, for
////   the properties whose value changed, so a modifier that leaves the value as it was
////   reports nothing.
//// - **A modifier is read by a rule only for the properties the rules name.** The
////   constants below name them; a modifier on any other property is held and sent, and
////   no rule reads it (for example MoveSpeedMultiplier, 100: the client moves at it and
////   the server checks no speed; FallingDamageMultiplier, 134: falling damage is not
////   handled).
////
//// What happens at each failure point:
////
//// | Step | Killed there | Twice at once | Late |
//// |---|---|---|---|
//// | A modifier starts | the connection restarts from storage with the table's bases and no modifier, and the client is created again | the same source applied twice is held once | n/a |
//// | A modifier ends | as above | the same source removed twice changes nothing the second time | removing a source that is not held changes nothing |
//// | The caster dies or leaves | every modifier of its casts is removed (`remove_cast`), each reported | | |

import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/table/id.{
  type Spell4EffectsId, type UnitProperty2Id, UnitProperty2Id,
}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}

/// BaseHealth (7): the maximum health `Unit:GetMaxHealth` reads
/// (`Unit.GetMaxHealth`).
pub const base_health = UnitProperty2Id(7)

/// HealthRegenMultiplier (8): what a player's health regeneration is multiplied by.
pub const health_regen_multiplier = UnitProperty2Id(8)

/// AssaultRating (35): the rating the damage formulas read.
pub const assault_rating = UnitProperty2Id(35)

/// SupportRating (36): the rating the damage formulas read.
pub const support_rating = UnitProperty2Id(36)

/// ShieldCapacityMax (41): the most shield a unit holds.
pub const shield_capacity_max = UnitProperty2Id(41)

/// Armor (42): the rating the defence formulas read.
pub const armor = UnitProperty2Id(42)

/// MoveSpeedMultiplier (100): what the client multiplies the player's own movement
/// speed by. The server holds and sends it and checks no speed
/// (`UnitProperty2.client_value`).
pub const move_speed_multiplier = UnitProperty2Id(100)

/// BaseCritChance (102): the base the critical hit chance formula takes.
pub const base_crit_chance = UnitProperty2Id(102)

/// BaseAvoidReduceChance (104): the base the strikethrough formula takes.
pub const base_avoid_reduce_chance = UnitProperty2Id(104)

/// CriticalHitSeverityMultiplier (127): the base the critical hit severity formula
/// takes.
pub const critical_hit_severity_multiplier = UnitProperty2Id(127)

/// FallingDamageMultiplier (134): held and sent; falling damage is not handled, so no
/// rule reads it.
pub const falling_damage_multiplier = UnitProperty2Id(134)

/// ShieldMitigationMax (175): the most of a blow the shield takes.
pub const shield_mitigation_max = UnitProperty2Id(175)

/// ShieldTickTime (177): the milliseconds between the shield's regeneration ticks.
pub const shield_tick_time = UnitProperty2Id(177)

/// One UnitPropertyModifier row's change to one property: x becomes x * multiplier +
/// flat + per_level * level (`Spell4Effects.effectType.11.change`: dataBits00 the
/// property, dataBits02 the multiplier, dataBits03 the flat amount, dataBits04 the
/// amount for each level of the unit). `mode` is the row's dataBits01, 1 to 4, named by
/// its number because the client does not settle its meaning and the server's order of
/// application ignores it.
pub type Modifier {
  Modifier(
    property: UnitProperty2Id,
    mode: Int,
    multiplier: Float,
    flat: Float,
    per_level: Float,
  )
}

/// What a modifier on the player belongs to: the cast that put it there and the
/// Spell4Effects row, so the cast's end, a removal of the cast and the modifier's own
/// end each take off exactly the modifier they started. A later go of the same cast
/// arms the same source again and holds it once.
pub type Source {
  Source(cast_id: Int, effect_id: Spell4EffectsId)
}

/// A property whose base or value changed, as a 0x93a entry carries it.
pub type Changed {
  Changed(property: UnitProperty2Id, base: Float, value: Float)
}

/// The player's properties: the base and the value of every UnitProperty2 id and the
/// modifiers that are live, in the order they started.
pub opaque type Properties {
  Properties(
    base: Dict(Int, Float),
    value: Dict(Int, Float),
    live: List(Live),
    level: Int,
  )
}

/// A modifier that is live on the player, with what it belongs to.
type Live {
  Live(source: Source, modifier: Modifier)
}

/// The properties of a player entering the world at `level`: every UnitProperty2 row's
/// defaultValue as base and value, and the base and value `listed` carries for the ids
/// the player's 0x262 lists, no modifier live. A row the table lacks for a listed id is
/// a crash: the 0x262 is the server's own.
pub fn new(
  tables tables: table_store.Tables,
  listed listed: List(UnitProperty),
  level level: Int,
) -> Properties {
  todo as "defaults of unit_property2.all, then the listed bases and values"
}

/// The base of a property: the number the 0x262 or the table gave it, which no modifier
/// changes.
pub fn base(
  properties properties: Properties,
  property property: UnitProperty2Id,
) -> Float {
  todo as "the base dict's entry; an id the table lacks is a crash"
}

/// The value of a property: its base with every live modifier on it applied in start
/// order, which the rules read and the client holds.
pub fn value(
  properties properties: Properties,
  property property: UnitProperty2Id,
) -> Float {
  todo as "the value dict's entry; an id the table lacks is a crash"
}

/// The properties with `modifier` live from `source`, and the entries whose value
/// changed (none for a modifier that changes nothing). A source already live changes
/// nothing: a later go of a cast that arms the effect again does not stack it.
pub fn apply(
  properties properties: Properties,
  source source: Source,
  modifier modifier: Modifier,
) -> #(Properties, List(Changed)) {
  todo as "append to live, recompute the property from its base in start order, compare"
}

/// The properties with the modifier of `source` taken off, and the entries whose value
/// changed; a source that is not live changes nothing. The modifiers after it in start
/// order stay applied to the base.
pub fn remove(
  properties properties: Properties,
  source source: Source,
) -> #(Properties, List(Changed)) {
  todo as "drop from live, recompute the property from its base in start order, compare"
}

/// The properties with every modifier of the cast `cast_id` taken off, and the entries
/// whose value changed, in property order: the cast ended, was removed or its caster
/// died.
pub fn remove_cast(
  properties properties: Properties,
  cast_id cast_id: Int,
) -> #(Properties, List(Changed)) {
  todo as "drop every live of the cast, recompute each affected property, compare"
}

/// The 0x93a entries for the changed properties, base and value as the client holds
/// them (32-bit floats), in the order given.
pub fn entries(changed changed: List(Changed)) -> List(UnitProperty) {
  todo as "float32.to_bits of base and value, the id's number"
}

/// The properties a player's 0x262 lists, with the current base and value of each
/// property a live modifier changes put in place of the listed one (added when the
/// 0x262 does not list it), in id order: the 0x262 a viewer that arrives while a
/// modifier lasts is created with (`UnitProperty2.client_value`).
pub fn overlay(
  listed listed: List(UnitProperty),
  properties properties: Properties,
) -> List(UnitProperty) {
  todo as "replace or add the entry of each property with a live modifier, sorted by id"
}
