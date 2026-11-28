//// An event of a proc's holder, which a caster's connection tells another player's and
//// the proc rule reads (genesis_prime/game/proc `decide`).

import genesis_prime/shared/spell_plan
import genesis_prime/table/id.{type Spell4BaseId, type Spell4Id}
import gleam/option.{type Option}

/// An event of a proc's holder. `other_unit` is the unit the event concerns besides the
/// holder, the creature a hit struck, none for stealth, combat, death and a heal;
/// `spell` is the spell that made it, none for an event no spell makes. `holder` is the
/// unit the proc is held on when it is not the caster's own, the ally whose blow raised
/// the event, and none for the caster's own events.
pub type Event {
  Event(
    trigger: spell_plan.Trigger,
    other_unit: Option(Int),
    spell: Option(EventSpell),
    holder: Option(Int),
  )
}

/// The spell of an event: its Spell4, its Spell4Base (`Spell4.spell4BaseIdBaseSpell`), its
/// spell groups (`Spell4GroupList`) and its school (`Spell4Base.school`).
pub type EventSpell {
  EventSpell(
    spell4_id: Spell4Id,
    spell4_base_id: Spell4BaseId,
    groups: List(Int),
    school: Int,
  )
}
