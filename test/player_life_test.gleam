//// A player's side of a creature's fight (`genesis_prime/game/player_life`), as the
//// pure rule it is. Expected values come from these places.
//// - A level-1 player's defence (`player.level1_defence`): deflect, critical deflect
////   and glance are 0 from UnitProperty2's defaults, so no roll changes a hit;
////   physical mitigation is GameFormula 1234 of the gear's Armor (`0x140464240`):
////   0.5996959 at Armor 150 (an Esper, class 3), the 0.75 cap at Armor 250 (a Warrior,
////   class 1) (`player.level1_gear_properties`), whose shield holds 450 and takes up
////   to ShieldMitigationMax 0.625 of each blow.
//// - Effect 184741 hits for 12 before mitigation (`Spell4Effects.184741`), Physical
////   (`Spell4Effects.damageType`). The creature's armor pierce is planted at 0: its
////   IgnoreArmorBase (property 122) is not read, a gap the decode named.
//// - The hit order, after mitigation the shield, and rounding half away from zero at
////   each step are the server's choice (genesis_prime/game/hit, 274 section 3):
////   Armor 150 takes 12 x (1 - 0.5996959) = 4.80 to 5, the shield round(5 x 0.625) =
////   3 of it, the health 2; Armor 250 takes 3, the shield round(1.875) = 2, the health
////   1. A level-1 player has 736 health (`player.level1_base_health`).
//// - 0x92f is the player's own health, 0x938 of stat 20 its shield and 0x937 another
////   unit's health (`opcode.0x92f`, `opcode.0x938`, `opcode.0x937`); 0x89a has no
////   client timer, so the server sends it on with the first fighter and off with the
////   last (`opcode.0x89a`).

import character_tables
import genesis_prime/client_connection
import genesis_prime/game/hit.{Rolls}
import genesis_prime/game/loadout
import genesis_prime/game/player_life.{
  Answer, OwnCombatState, OwnHealth, OwnShield, StreamTo, ToClient, ToViewers,
}
import genesis_prime/game/rating
import genesis_prime/game/strike_tell.{
  Answered, CreatureStriker, Key, Landed, Refused, Strike,
}
import genesis_prime/step
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map_id.{MapId}
import gleam/float
import gleam/set
import owned_test
import spawn_support

/// The Beast that strikes: unit 7, life 3.
fn beast() -> step.Address {
  step.Creature(
    map: MapId(world_id: 3460, instance: 0),
    incarnation: 1,
    unit_id: 7,
    life: 3,
  )
}

fn attack(cast_id: Int) -> strike_tell.Tell {
  Strike(
    key: Key(cast_id:, phase: 0, unit_id: 20),
    from: beast(),
    striker: CreatureStriker,
    offence: spawn_support.beast_attack().offence,
  )
}

/// Rolls a level-1 player's defence never reads: deflect, crit deflect and glance
/// are 0, and the Beast's offence has no crit chance.
const rolls = Rolls(crit: 0.5, deflect: 0.0, glance: 0.0)

/// The defence of the class's Dominion Novice at level 1, on the planted tables.
fn defence_of(class_id: Int) -> hit.Defence {
  let tables = character_tables.shared()
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(class_id), faction_id: 166)
    as "the class has a Dominion Novice set"
  player_life.defence(loadout:, level: 1, formulas: rating.formulas(tables:))
}

fn close(first: Float, second: Float) -> Bool {
  float.absolute_value(first -. second) <. 0.0000005
}

pub fn a_level_1_players_defence_has_no_deflect_crit_deflect_or_glance_and_its_armors_mitigation_test() -> Nil {
  use <- owned_test.run(60_000)
  let esper = defence_of(3)
  let warrior = defence_of(1)
  assert esper.deflect_chance == 0.0
    && esper.crit_deflect_chance == 0.0
    && esper.glance_chance == 0.0
    as "player.level1_defence: no roll changes a hit"
  assert close(esper.physical_mitigation, 0.5996959)
    as "Armor 150 at level 1: 0.5996959 (0x140464240)"
  assert warrior.physical_mitigation == 0.75
    as "Armor 250 reaches the 0.75 cap (GameFormula 1234's 75)"
  assert esper.shield_mitigation_max == 0.625 as "ShieldMitigationMax 0.625"
}

pub fn a_creatures_hit_takes_the_shield_first_up_to_its_share_and_the_rest_from_health_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(esper, esper_effects) =
    player_life.struck(
      life: player_life.new(health: 736, shield: 450),
      defence: defence_of(3),
      strike: attack(1),
      rolls:,
    )
  assert #(player_life.health(life: esper), player_life.shield(life: esper))
    == #(734, 447)
    as "Armor 150: 12 mitigated to 5, the shield takes 3, the health 2"
  let #(warrior, _) =
    player_life.struck(
      life: player_life.new(health: 736, shield: 450),
      defence: defence_of(1),
      strike: attack(1),
      rolls:,
    )
  assert #(player_life.health(life: warrior), player_life.shield(life: warrior))
    == #(735, 448)
    as "Armor 250: 12 mitigated to 3, the shield takes 2, the health 1"
  let assert [
    ToClient(OwnShield(shield: 447)),
    ToViewers(client_connection.Shield(shield: 447)),
    ToClient(OwnHealth(health: 734)),
    ToViewers(client_connection.Health(health: 734, dead: False)),
    Answer(
      to:,
      answered: Answered(outcome: Landed(descriptions: [description]), ..),
    ),
  ] = esper_effects
    as "0x938 stat 20 to the player and its viewers, 0x92f to the player, 0x937 to the viewers, then the answer"
  assert to == beast() as "the answer goes to the striker's address"
  assert description.damage.raw_damage == 12
    && description.damage.absorbed == 7
    && description.damage.shield_absorbed == 3
    && description.damage.health_damage_with_overkill == 2
    as "the description the creature's 0x7f4 carries: raw 12, 7 mitigated, 3 to the shield, 2 to health"
}

pub fn health_is_floored_at_0_the_answer_is_landed_and_killed_and_a_later_strike_is_refused_dead_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, effects) =
    player_life.struck(
      life: player_life.new(health: 1, shield: 0),
      defence: defence_of(1),
      strike: attack(1),
      rolls:,
    )
  assert player_life.health(life:) == 0 as "3 against 1 health: floored at 0"
  let assert [
    ToClient(OwnHealth(health: 0)),
    ToViewers(client_connection.Health(health: 0, dead: True)),
    Answer(
      answered: Answered(outcome: Landed(descriptions: [description]), ..),
      ..,
    ),
  ] = effects
    as "no shield to change: 0x92f and 0x937 at 0, then the answer"
  assert description.damage.killed == 1 && description.damage.overkill == 2
    as "the killed bit, and 2 beyond the 1 health"
  let #(_, later) =
    player_life.struck(life:, defence: defence_of(1), strike: attack(2), rolls:)
  assert later
    == [
      Answer(
        to: beast(),
        answered: Answered(
          key: Key(cast_id: 2, phase: 0, unit_id: 20),
          outcome: Refused(why: strike_tell.Dead),
        ),
      ),
    ]
    as "a player at 0 takes no strike"
}

pub fn the_first_threat_sets_the_combat_flag_and_the_last_release_clears_it_test() -> Nil {
  use <- owned_test.run(5000)
  let life = player_life.new(health: 736, shield: 450)
  let #(life, first) =
    player_life.threatened(life:, unit_id: 7, creature_life: 3, gone: set.new())
  assert first
    == [
      ToClient(OwnCombatState(in_combat: True)),
      ToViewers(client_connection.CombatState(in_combat: True)),
      StreamTo(unit_id: 7, life: 3),
    ]
    as "0x89a (P, 1) to the player and its viewers, then its place to the creature at once"
  let #(life, second) =
    player_life.threatened(life:, unit_id: 9, creature_life: 4, gone: set.new())
  assert second == [StreamTo(unit_id: 9, life: 4)]
    as "the flag is already on: the second fighter only starts its stream"
  assert player_life.fighters(life:) == [#(7, 3), #(9, 4)]
  let #(life, one_left) = player_life.released(life:, unit_id: 7)
  assert one_left == [] as "a fighter is left: the flag stays on"
  let #(life, last) = player_life.released(life:, unit_id: 9)
  assert last
    == [
      ToClient(OwnCombatState(in_combat: False)),
      ToViewers(client_connection.CombatState(in_combat: False)),
    ]
    as "the last release clears 0x89a: no client timer does"
  assert player_life.fighters(life:) == [] as "no stream after the release"
}

pub fn a_threat_from_a_unit_the_map_reported_gone_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, effects) =
    player_life.threatened(
      life: player_life.new(health: 736, shield: 450),
      unit_id: 7,
      creature_life: 3,
      gone: set.from_list([7]),
    )
  assert effects == [] && player_life.fighters(life:) == []
    as "the creature ended after it sent its threat"
}
