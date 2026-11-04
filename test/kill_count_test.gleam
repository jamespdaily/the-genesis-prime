//// How many casts of each level-1 ability kill the 52-health Virtual Battle Beast, from
//// the client's own effect rows through the damage formula and the hit rule. Expected
//// values come from these places.
//// - The Beast has 52 health at level 1 (Base Health 52.6205 truncated,
////   `Creature2.creature2ArcheTypeId`, `opcode.0x262.creature`), no mitigation and a
////   deflect chance of 0.016 (`Creature2.73464.mitigation`,
////   `Creature2.73464.crit_deflect_glance`); a roll that is no deflect and no crit is used.
//// - The casts that kill it, from the damage of one cast at level 1 and rating 0 rounded
////   to a whole number (the server's choice): Telekinetic Strike 3 (18 a cast), Zap 6
////   (9), Crush 6 (9, the second spell's), Kick 13 (4), Paralytic Surge 7 (8) and
////   Stagger 5 (3 a hit and four hits a cast) (`Spell4.32893`, `Spell4.41438`,
////   `Spell4.32812`, `Spell4.58591`, `Spell4.42352`, `Spell4.38791`: each effect row's
////   level parameter).

import client_tables
import genesis_prime/game/damage
import genesis_prime/game/hit.{type Blow, Blow, Offence, Rolls}
import genesis_prime/game/spell_area
import genesis_prime/table/id.{Spell4Id}
import gleam/float
import gleam/list
import owned_test
import unitest

/// The hits one cast of the ability lands on one foe, as the spell and the number of
/// times it strikes in a cast.
fn hits_of(ability: String) -> List(#(Int, Int)) {
  case ability {
    "Telekinetic Strike" -> [#(32_893, 1)]
    "Zap" -> [#(41_438, 1)]
    "Crush" -> [#(42_297, 1)]
    "Kick" -> [#(58_591, 1)]
    "Paralytic Surge" -> [#(42_352, 1)]
    _ -> [#(38_781, 4)]
  }
}

/// How many casts of the ability take the Beast from 52 health to 0.
fn casts_to_kill(
  ability ability: String,
  areas areas: spell_area.Areas,
) -> Int {
  let blows =
    list.flat_map(hits_of(ability), fn(hit) {
      let assert Ok(area) =
        spell_area.of_spell(areas:, spell4_id: Spell4Id(hit.0))
        as "the spell is in the areas"
      let assert Ok(phase) = spell_area.phase(spell: area, phase: 0)
      list.flat_map(list.repeat(Nil, hit.1), fn(_) {
        list.map(phase.damage, fn(effect) {
          Blow(
            spell4_effects_id: effect.effect_id.value,
            damage_type: effect.damage_type,
            damage: float.round(damage.value(
              formula: effect.formula,
              attacker: damage.Attacker(
                level: 1,
                assault_rating: 0.0,
                support_rating: 0.0,
              ),
            )),
            delay_ms: effect.delay_ms,
          )
        })
      })
    })
  kill_loop(blows:, health: 52, casts: 0)
}

fn kill_loop(
  blows blows: List(Blow),
  health health: Int,
  casts casts: Int,
) -> Int {
  case health {
    0 -> casts
    _ -> {
      let assert hit.Landed(health: left, ..) =
        hit.apply(
          shield: 0,
          health:,
          offence: Offence(
            blows:,
            crit_chance: 0.0,
            crit_severity: 1.5,
            strikethrough: 0.0,
          ),
          defence: hit.Defence(
            deflect_chance: 0.016,
            crit_deflect_chance: 0.0,
            glance_chance: 0.0,
            glance_amount: 0.0,
            physical_mitigation: 0.0,
            tech_mitigation: 0.0,
            magic_mitigation: 0.0,
            shield_mitigation_max: 0.0,
          ),
          rolls: Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
        )
        as "no roll deflects"
      kill_loop(blows:, health: left, casts: casts + 1)
    }
  }
}

pub fn each_level_one_ability_kills_the_beast_in_the_decodes_number_of_casts_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let areas = spell_area.areas(tables: client_tables.shared())
  assert list.map(
      [
        "Telekinetic Strike",
        "Zap",
        "Crush",
        "Kick",
        "Paralytic Surge",
        "Stagger",
      ],
      fn(ability) { #(ability, casts_to_kill(ability:, areas:)) },
    )
    == [
      #("Telekinetic Strike", 3),
      #("Zap", 6),
      #("Crush", 6),
      #("Kick", 13),
      #("Paralytic Surge", 7),
      #("Stagger", 5),
    ]
    as "the decode's table of casts to kill the 52-health Beast"
}
