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

import cast_support
import character_tables
import genesis_prime/client_connection
import genesis_prime/game/hit
import genesis_prime/game/loadout
import genesis_prime/game/player_life.{
  Answer, CancelTimer, ControlBody, ControlGhost, ControlGiven, EndCasts,
  GhostCreated, GhostRemoved, GoToHolocrypt, OwnCameBackLogged, OwnCombatState,
  OwnDeathLogged, OwnDeathState, OwnHealth, OwnInterruptArmor,
  OwnResurrectionWindow, OwnShield, StartTimer, StreamTo, ToClient, ToViewers,
}
import genesis_prime/game/rating
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{
  Answered, CreatureStriker, Key, Landed, Refused, Strike,
}
import genesis_prime/game/unit_properties
import genesis_prime/message/float32
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/step.{TimerId}
import genesis_prime/table/id.{ClassId, Spell4EffectsId, UnitProperty2Id}
import gleam/float
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import message_support
import owned_test
import player_life_support
import properties_support
import spawn_support

fn attack(cast_id: Int) -> strike_tell.Tell {
  Strike(
    key: Key(cast_id:, phase: 0, unit_id: 20),
    from: player_life_support.beast(),
    striker: CreatureStriker,
    offence: spawn_support.beast_attack().offence,
    controls: [],
  )
}

/// The defence of the class's Dominion Novice at level 1, on the planted tables.
fn defence_of(class_id: Int) -> hit.Defence {
  let tables = character_tables.shared()
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(class_id), faction_id: 166)
    as "the class has a Dominion Novice set"
  player_life.defence(
    properties: properties_support.wearing(loadout:),
    level: 1,
    formulas: rating.formulas(tables:),
  )
}

pub fn a_level_1_players_defence_has_no_deflect_crit_deflect_or_glance_and_its_armors_mitigation_test() -> Nil {
  use <- owned_test.run(60_000)
  let esper = defence_of(3)
  let warrior = defence_of(1)
  assert esper.deflect_chance == 0.0
    && esper.crit_deflect_chance == 0.0
    && esper.glance_chance == 0.0
    as "player.level1_defence: no roll changes a hit"
  assert float.loosely_equals(
    esper.physical_mitigation,
    with: 0.5996959,
    tolerating: 0.0000005,
  )
    as "Armor 150 at level 1: 0.5996959 (0x140464240)"
  assert warrior.physical_mitigation == 0.75
    as "Armor 250 reaches the 0.75 cap (GameFormula 1234's 75)"
  assert esper.shield_mitigation_max == 0.625 as "ShieldMitigationMax 0.625"
}

pub fn a_creatures_hit_takes_the_shield_first_up_to_its_share_and_the_rest_from_health_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(esper, esper_effects) =
    player_life.struck(
      life: player_life.new(
        health: 736,
        shield: 450,
        regeneration: player_life_support.regeneration,
      ),
      defence: defence_of(3),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert #(player_life.health(life: esper), player_life.shield(life: esper))
    == #(734, 447)
    as "Armor 150: 12 mitigated to 5, the shield takes 3, the health 2"
  let #(warrior, _) =
    player_life.struck(
      life: player_life.new(
        health: 736,
        shield: 450,
        regeneration: player_life_support.regeneration,
      ),
      defence: defence_of(1),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert #(player_life.health(life: warrior), player_life.shield(life: warrior))
    == #(735, 448)
    as "Armor 250: 12 mitigated to 3, the shield takes 2, the health 1"
  let assert [
    ToClient(OwnShield(shield: 447)),
    ToViewers(client_connection.Shield(shield: 447)),
    ToClient(OwnHealth(health: 734)),
    ToViewers(client_connection.Health(health: 734, dead: False)),
    player_life.DamageTaken,
    Answer(
      to:,
      answered: Answered(
        outcome: Landed(descriptions: [description], controls: []),
        ..,
      ),
    ),
    StartTimer(timer: TimerId(9), after_ms: 2500),
    StartTimer(timer: TimerId(8), after_ms: 500),
  ] = esper_effects
    as "0x938 stat 20 to the player and its viewers, 0x92f to the player, 0x937 to the viewers, then the damage taken that ends a stealth, then the answer, then the shield's reboot and, the player out of combat and below its maximum, the health tick"
  assert to == player_life_support.beast()
    as "the answer goes to the striker's address"
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
      life: player_life.new(
        health: 1,
        shield: 0,
        regeneration: player_life_support.regeneration,
      ),
      defence: defence_of(1),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert player_life.health(life:) == 0 as "3 against 1 health: floored at 0"
  let assert [
    ToClient(OwnHealth(health: 0)),
    ToViewers(client_connection.Health(health: 0, dead: True)),
    player_life.DamageTaken,
    Answer(
      answered: Answered(
        outcome: Landed(descriptions: [description], controls: []),
        ..,
      ),
      ..,
    ),
    ..
  ] = effects
    as "no shield to change: 0x92f and 0x937 at 0, then the damage taken, then the answer, then the death"
  assert description.damage.killed == 1 && description.damage.overkill == 2
    as "the killed bit, and 2 beyond the 1 health"
  let #(_, later) =
    player_life.struck(
      life:,
      defence: defence_of(1),
      strike: attack(2),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert later
    == [
      Answer(
        to: player_life_support.beast(),
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
  let life =
    player_life.new(
      health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
    )
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
  assert one_left == []
    as "a fighter is left: the flag stays on, and no combat is left"
  let #(life, last) = player_life.released(life:, unit_id: 9)
  assert last
    == [
      ToClient(OwnCombatState(in_combat: False)),
      ToViewers(client_connection.CombatState(in_combat: False)),
      player_life.CombatLeft,
    ]
    as "the last release clears 0x89a: no client timer does; the combat left follows the flag's news (Spell4Effects.effectType.14.dataBits00.0_44, kind 44 'leaves combat')"
  assert player_life.fighters(life:) == [] as "no stream after the release"
}

pub fn a_release_of_a_unit_that_is_no_fighter_is_no_combat_left_test() -> Nil {
  use <- owned_test.run(5000)
  let life =
    player_life.new(
      health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
    )
  let #(_, effects) = player_life.released(life:, unit_id: 7)
  assert effects == []
    as "the combat flag was off and stays off: nothing is left"
}

pub fn a_death_with_no_fighter_is_no_combat_left_and_a_death_with_one_is_test() -> Nil {
  use <- owned_test.run(60_000)
  let life =
    player_life.new(
      health: 1,
      shield: 0,
      regeneration: player_life_support.regeneration,
    )
  let #(_, alone) =
    player_life.struck(
      life:,
      defence: defence_of(1),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert !list.contains(alone, player_life.CombatLeft)
    as "a player whose flag is already off leaves no combat when it dies"
  let #(fighting, _) =
    player_life.threatened(life:, unit_id: 7, creature_life: 3, gone: set.new())
  let #(_, with_fighter) =
    player_life.struck(
      life: fighting,
      defence: defence_of(1),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  let combat_flag =
    list.take_while(with_fighter, fn(effect) {
      effect != player_life.TellMap(alive: False)
    })
  assert list.last(combat_flag) == Ok(player_life.CombatLeft)
    as "a player with a fighter leaves combat as it dies, right after the flag's news and before the map is told and its casts end"
  assert list.count(with_fighter, fn(effect) {
      effect == player_life.CombatLeft
    })
    == 1
}

pub fn a_threat_from_a_unit_the_map_reported_gone_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(life, effects) =
    player_life.threatened(
      life: player_life.new(
        health: 736,
        shield: 450,
        regeneration: player_life_support.regeneration,
      ),
      unit_id: 7,
      creature_life: 3,
      gone: set.from_list([7]),
    )
  assert effects == [] && player_life.fighters(life:) == []
    as "the creature ended after it sent its threat"
}

// ------------------------------------------- death and coming back
//
// Expected values come from the design of step G (the Design artifact of issue
// 368 and its shape review) and these places: 0x88c sets the unit dead and leaves
// its combat flag, so 0x89a (P, 0) follows (`opcode.0x88c`, `death.combat_flag`);
// the death and the coming back are logged as 0x247 types 22 and 23
// (`opcode.0x247.death`); the ghost is a unit of type 23 for the player's own
// client at the body's place (`0x140096970`), handed control by 0x1b3 and 0x636
// (`opcode.0x1b3`, `opcode.0x636`); 0x15a names the player's own unit, a choice
// of GameLib.RezType and 0 (`opcode.0x15a`, `lua.GameLib.RezType`); the window
// offers Wake Here (1) and Holocrypt (2), and the player comes back at full health
// and full shield (the server's choices, `death.server_choices`).

/// The life struck by the Beast, strike after strike, until it dies: the life
/// and the effects of the strike that killed it.
fn struck_until_dead(
  life: player_life.Life,
  cast_id: Int,
) -> #(player_life.Life, List(player_life.Effect)) {
  let #(life, effects) =
    player_life.struck(
      life:,
      defence: defence_of(1),
      strike: attack(cast_id),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  case player_life.state(life:) {
    player_life.Dead -> #(life, effects)
    player_life.Alive -> struck_until_dead(life, cast_id + 1)
  }
}

/// A level-1 Warrior with the Beast on its threat list, struck until it dies,
/// and the effects of the killing strike after its answer.
fn a_dead_warrior() -> #(player_life.Life, List(player_life.Effect)) {
  let #(life, _) =
    player_life.threatened(
      life: player_life.new(
        health: 736,
        shield: 450,
        regeneration: player_life_support.regeneration,
      ),
      unit_id: 7,
      creature_life: 3,
      gone: set.new(),
    )
  let #(life, effects) = struck_until_dead(life, 1)
  #(
    life,
    list.drop_while(effects, fn(effect) {
      case effect {
        Answer(..) -> False
        ToClient(..)
        | ToViewers(..)
        | StreamTo(..)
        | player_life.DamageTaken
        | player_life.CombatLeft
        | EndCasts
        | GoToHolocrypt
        | player_life.TellMap(..)
        | StartTimer(..)
        | CancelTimer(..) -> True
      }
    })
      |> list.drop(1),
  )
}

/// 0x15a's body: the unit, the choice and the third value.
fn chosen(
  life: player_life.Life,
  body: BitArray,
) -> Result(#(player_life.Life, List(player_life.Effect)), player_life.Refusal) {
  player_life.take(
    life:,
    message: player_life.ResurrectionChosen,
    body:,
    unit_id: player_life_support.own_unit,
  )
}

/// What coming back writes and tells, as Wake Here and the Holocrypt share it,
/// for a level-1 Warrior: 736 health (`player.level1_base_health`) and 450 shield
/// (`player.level1_gear_properties`), both full.
fn came_back_effects() -> List(player_life.Effect) {
  [
    ToClient(OwnHealth(health: 736)),
    ToViewers(client_connection.Health(health: 736, dead: False)),
    ToClient(OwnShield(shield: 450)),
    ToViewers(client_connection.Shield(shield: 450)),
    ToClient(OwnDeathState(dead: False)),
    ToViewers(client_connection.CameBack),
    ToClient(OwnResurrectionWindow(dead: False)),
    ToClient(GhostRemoved),
    ToClient(ControlGiven(to: ControlBody)),
    ToClient(OwnCameBackLogged),
    ToViewers(client_connection.CameBackLogged),
  ]
}

pub fn a_player_at_0_dies_ends_its_casts_and_sees_its_ghost_and_the_window_in_the_clients_order_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, death) = a_dead_warrior()
  assert death
    == [
      ToClient(OwnDeathState(dead: True)),
      ToViewers(client_connection.Died),
      ToClient(OwnCombatState(in_combat: False)),
      ToViewers(client_connection.CombatState(in_combat: False)),
      player_life.CombatLeft,
      player_life.TellMap(alive: False),
      EndCasts,
      ToClient(OwnDeathLogged),
      ToViewers(client_connection.DeathLogged),
      ToClient(GhostCreated(place: test_place())),
      ToClient(OwnResurrectionWindow(dead: True)),
      ToClient(ControlGiven(to: ControlGhost)),
      CancelTimer(timer: player_life_support.shield_timer),
    ]
    as "0x88c (P, 1) and 0x89a (P, 0) to the player and its viewers, the map told the death before the casts end, its casts ended, 0x247 type 22 to both, then for its own client alone the ghost's 0x262 at the body's place, 0x1b3 and 0x636 for the ghost, and the shield's player_life_support.regeneration timer, armed by the earlier blows, cancelled"
  assert player_life.state(life:) == player_life.Dead
    && player_life.fighters(life:) == []
    as "dead, and fighting no one: its fighters stream nothing more"
}

pub fn a_strike_on_a_dead_player_is_refused_dead_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(life, _) = a_dead_warrior()
  let #(after, refused) =
    player_life.struck(
      life:,
      defence: defence_of(1),
      strike: attack(9999),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert refused
    == [
      Answer(
        to: player_life_support.beast(),
        answered: Answered(
          key: Key(
            cast_id: 9999,
            phase: 0,
            unit_id: player_life_support.own_unit,
          ),
          outcome: Refused(why: strike_tell.Dead),
        ),
      ),
    ]
    && after == life
    as "a strike that reaches the player after its death is refused Dead, and the creature's go leaves it out"
  let #(after, threatened) =
    player_life.threatened(life:, unit_id: 9, creature_life: 4, gone: set.new())
  assert threatened == [] && after == life
    as "a threat that reaches the dead is dropped"
}

pub fn a_choice_for_another_unit_one_not_offered_a_nonzero_value_or_one_while_alive_is_refused_unchanged_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(dead, _) = a_dead_warrior()
  assert chosen(
      dead,
      message_support.choice_body(unit_id: 21, choice: 1, value: 0),
    )
    == Error(player_life.NotThePlayer(unit_id: 21))
    as "another unit"
  assert chosen(
      dead,
      message_support.choice_body(unit_id: 1_048_596, choice: 1, value: 0),
    )
    == Error(player_life.NotThePlayer(unit_id: 1_048_596))
    as "the ghost's own id, 2^20 + 20 (the server's choice of a ghost id): the Death addon names the player's unit"
  assert chosen(
      dead,
      message_support.choice_body(
        unit_id: player_life_support.own_unit,
        choice: 4,
        value: 0,
      ),
    )
    == Error(player_life.NotOffered(choice: player_life.OtherChoice(value: 4)))
    && chosen(
      dead,
      message_support.choice_body(
        unit_id: player_life_support.own_unit,
        choice: 32,
        value: 0,
      ),
    )
    == Error(player_life.NotOffered(choice: player_life.OtherChoice(value: 32)))
    && chosen(
      dead,
      message_support.choice_body(
        unit_id: player_life_support.own_unit,
        choice: 0,
        value: 0,
      ),
    )
    == Error(player_life.NotOffered(choice: player_life.OtherChoice(value: 0)))
    as "a caster's resurrection (4), Exit Instance (32) and 0: the window offered only 1 and 2"
  assert chosen(
      dead,
      message_support.choice_body(
        unit_id: player_life_support.own_unit,
        choice: 1,
        value: 5,
      ),
    )
    == Error(player_life.NonzeroValue(value: 5))
    as "the Death addon always sends 0"
  assert chosen(
      player_life.new(
        health: 736,
        shield: 450,
        regeneration: player_life_support.regeneration,
      ),
      message_support.choice_body(
        unit_id: player_life_support.own_unit,
        choice: 1,
        value: 0,
      ),
    )
    == Error(player_life.NotDead)
    as "the living come back from nothing"
  let assert Error(player_life.NotDecoded(..)) = chosen(dead, <<1, 2>>)
    as "a body the client's reader would refuse"
  Nil
}

pub fn a_second_choice_is_refused_unchanged_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(dead, _) = a_dead_warrior()
  let assert Ok(#(alive, _)) =
    chosen(
      dead,
      message_support.choice_body(
        unit_id: player_life_support.own_unit,
        choice: 1,
        value: 0,
      ),
    )
  assert chosen(
      alive,
      message_support.choice_body(
        unit_id: player_life_support.own_unit,
        choice: 2,
        value: 0,
      ),
    )
    == Error(player_life.NotDead)
    as "the first choice brought the player back: the second finds it alive"
}

pub fn wake_here_brings_the_player_back_at_full_health_and_full_shield_where_its_body_lies_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(dead, _) = a_dead_warrior()
  let assert Ok(#(life, effects)) =
    chosen(
      dead,
      message_support.choice_body(
        unit_id: player_life_support.own_unit,
        choice: 1,
        value: 0,
      ),
    )
  assert effects
    == list.append(came_back_effects(), [player_life.TellMap(alive: True)])
    as "0x92f full and the full shield, 0x88c (P, 0) to the player and its viewers, 0x1b3 dead 0, the ghost's 0x355, 0x636 for the body, 0x247 type 23 to both, in that order, then the map told the waking"
  assert player_life.state(life:) == player_life.Alive
    && player_life.health(life:) == 736
    && player_life.shield(life:) == 450
  let #(after, later) =
    player_life.struck(
      life:,
      defence: defence_of(1),
      strike: attack(9999),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  let assert [
    ToClient(OwnShield(shield: 448)),
    ToViewers(client_connection.Shield(shield: 448)),
    ToClient(OwnHealth(health: 735)),
    ..
  ] = later
    as "a later strike lands: Armor 250 takes 3, the shield 2 and the health 1"
  assert player_life.health(life: after) == 735
}

pub fn the_holocrypt_comes_back_as_wake_here_does_then_asks_to_go_to_the_holocrypt_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(dead, _) = a_dead_warrior()
  let assert Ok(#(life, effects)) =
    chosen(
      dead,
      message_support.choice_body(
        unit_id: player_life_support.own_unit,
        choice: 2,
        value: 0,
      ),
    )
  assert effects == list.append(came_back_effects(), [GoToHolocrypt])
    as "the coming back's messages where the body lies, then the move to the Holocrypt place, last"
  assert player_life.state(life:) == player_life.Alive
}

/// Where the struck player stands in these rules: any place in a world serves,
/// since a strike that kills reads it only as the ghost's place.
fn test_place() -> Place {
  let assert Ok(place) =
    start_place.place(
      world_id: 3460,
      world_zone_id: 0,
      x: 0.0,
      y: 0.0,
      z: 0.0,
      facing: start_place.unturned,
    )
    as "world 3460 is a world"
  place
}

pub fn a_player_enters_at_the_health_saved_capped_at_the_maximum_and_at_full_when_none_was_saved_test() -> Nil {
  use <- owned_test.run(10_000)
  let entered = fn(saved) {
    player_life.entering(
      saved:,
      max_health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
      place: test_place(),
    ).0
  }
  let below = entered(Some(500))
  assert player_life.health(life: below) == 500
    && player_life.max_health(life: below) == 736
    as "a saved health below the maximum is the health, and the maximum stays the level's"
  assert player_life.shield(life: below) == 450
    && player_life.max_shield(life: below) == 450
    as "the shield enters full"
  assert player_life.health(life: entered(Some(736))) == 736 as "at the maximum"
  assert player_life.health(life: entered(Some(737))) == 736
    as "above it, a planted row: the maximum"
  assert player_life.health(life: entered(Some(1_000_000))) == 736
  assert player_life.health(life: entered(None)) == 736
    as "nothing saved: full, as before"
  assert player_life.fighters(life: below) == []
    && !player_life.in_combat(life: below)
    && player_life.saved_health(life: below) == 500
    as "alive, fighting no one"
  let #(struck, _) =
    player_life.struck(
      life: below,
      defence: defence_of(1),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert player_life.health(life: struck) == 499
    as "Armor 250: the shield takes 2 and the health 1, from 500"
}

pub fn a_player_entering_at_a_saved_health_of_0_enters_dead_with_its_ghost_at_the_body_and_starts_no_timer_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(dead, effects) =
    player_life.entering(
      saved: Some(0),
      max_health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
      place: test_place(),
    )
  assert player_life.state(life: dead) == player_life.Dead
    && player_life.health(life: dead) == 0
    && player_life.max_health(life: dead) == 736
    && player_life.fighters(life: dead) == []
    && !player_life.in_combat(life: dead)
    as "health 0 is dead (0x140457bc5), the maximum stays the level's, and it fights no one"
  assert player_life.shield(life: dead) == 0
    && player_life.max_shield(life: dead) == 450
    as "a death in the world leaves what the killing blow left, which no save keeps: the server's choice is a shield of 0 with the level's maximum"
  assert effects
    == [
      ToClient(GhostCreated(place: test_place())),
      ToClient(OwnResurrectionWindow(dead: True)),
      ToClient(ControlGiven(to: ControlGhost)),
    ]
    as "the ghost at the body's place, 0x1b3 with dead 1, then control of the ghost, in the order of death.enter_dead: no 0x88c, no 0x89a, no player_life_support.regeneration timer"
  assert player_life.left(life: dead) == []
    as "nothing runs to cancel at the leave"
  assert player_life.saved_health(life: dead) == 0
    as "a player that camps again before coming back saves 0 again"
  assert player_life.timer_fired(life: dead, timer: TimerId(8)).1 == []
    && player_life.timer_fired(life: dead, timer: TimerId(9)).1 == []
    as "a player_life_support.regeneration timer that fires anyway changes nothing"
}

pub fn a_player_that_entered_dead_refuses_a_strike_takes_no_threat_and_comes_back_at_full_health_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(dead, _) =
    player_life.entering(
      saved: Some(0),
      max_health: 736,
      shield: 450,
      regeneration: player_life_support.regeneration,
      place: test_place(),
    )
  let #(after_strike, effects) =
    player_life.struck(
      life: dead,
      defence: defence_of(1),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert after_strike == dead
    && effects
    == [
      Answer(
        to: player_life_support.beast(),
        answered: Answered(
          key: Key(cast_id: 1, phase: 0, unit_id: 20),
          outcome: Refused(why: strike_tell.Dead),
        ),
      ),
    ]
    as "a dead player is refused the strike Dead and changes nothing"
  let #(threatened, effects) =
    player_life.threatened(
      life: dead,
      unit_id: 7,
      creature_life: 3,
      gone: set.new(),
    )
  assert threatened == dead && effects == []
    as "no combat flag, no stream: a dead player is fought by no one"
  let assert Ok(#(alive, came_back)) =
    player_life.take(
      life: dead,
      message: player_life.ResurrectionChosen,
      body: message_support.choice_body(unit_id: 5, choice: 1, value: 0),
      unit_id: 5,
    )
    as "the choice the window offers is taken"
  assert player_life.state(life: alive) == player_life.Alive
    && player_life.health(life: alive) == 736
    && player_life.shield(life: alive) == 450
    as "Wake Here brings it back at full health and the maximum shield, as after a death in the world"
  assert list.contains(came_back, ToClient(OwnDeathState(dead: False)))
    && list.contains(came_back, ToClient(ControlGiven(to: ControlBody)))
    as "0x88c (P, 0) and control of the body"
}

pub fn a_save_keeps_the_health_the_player_has_and_0_while_it_is_dead_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(hurt, _) =
    player_life.struck(
      life: player_life.new(
        health: 736,
        shield: 450,
        regeneration: player_life_support.regeneration,
      ),
      defence: defence_of(1),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert player_life.saved_health(life: hurt) == 735
    as "the health now, which the table holds (character_health_is_not_negative)"
  let #(dead, _) =
    player_life.struck(
      life: player_life.new(
        health: 1,
        shield: 0,
        regeneration: player_life_support.regeneration,
      ),
      defence: defence_of(1),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert player_life.health(life: dead) == 0
  assert player_life.saved_health(life: dead) == 0
    as "a dead player keeps 0, the health the client creates a unit dead at (0x140457bc5): the next entry is dead"
}

// ---- the maxima the player's properties give ----

/// A player of 100 health whose health regenerates a quarter of its maximum each tick,
/// the numbers test data of this rule's own.
fn quarter_regeneration() -> player_life.Regeneration {
  player_life.Regeneration(
    health_fraction: 0.25,
    health_multiplier: 1.0,
    health_tick_ms: 500,
    shield: None,
  )
}

/// The properties of a player whose 0x262 lists BaseHealth 100, with 100 more for the
/// source `source`, live or not.
fn base_health_100() -> unit_properties.Properties {
  let bits = float32.to_bits(100.0)
  unit_properties.new(
    defaults: properties_support.defaults(),
    listed: [UnitProperty(property_id: 7, base: bits, value: bits)],
    level: 1,
  )
}

pub fn a_modifier_of_the_maximum_health_raises_it_keeps_the_health_and_its_end_caps_it_test() -> Nil {
  use <- owned_test.run(5000)
  let source =
    unit_properties.Source(cast_id: 1, effect_id: Spell4EffectsId(99_901))
  let life =
    player_life.new(
      health: 100,
      shield: 0,
      regeneration: quarter_regeneration(),
    )
  // A modifier of BaseHealth (7): x * 1.0 + 100.0.
  let #(raised, _) =
    unit_properties.apply(
      properties: base_health_100(),
      source:,
      modifier: unit_properties.Change(
        property: unit_properties.base_health,
        mode: 3,
        multiplier: 1.0,
        flat: 100.0,
        per_level: 0.0,
      ),
    )
  let #(life, effects) =
    player_life.properties_changed(life:, properties: raised)
  assert player_life.max_health(life:) == 200
    as "the maximum is BaseHealth's value"
  assert player_life.health(life:) == 100 as "the current health is kept"
  assert effects == [player_life.StartTimer(timer: TimerId(8), after_ms: 500)]
    as "the player is now below its maximum, so its health regenerates, and nothing is written for a health that did not change"
  let #(life, _) = player_life.timer_fired(life:, timer: TimerId(8))
  assert player_life.health(life:) == 150
    as "a tick adds floor(200 x 0.25 x 1.0), 50"
  let #(ended, _) = unit_properties.remove(properties: raised, source:)
  let #(life, effects) =
    player_life.properties_changed(life:, properties: ended)
  assert player_life.max_health(life:) == 100
  assert player_life.health(life:) == 100
    as "the end caps the health at the old maximum (the server's choice)"
  assert effects
    == [
      player_life.ToClient(player_life.OwnHealth(health: 100)),
      player_life.ToViewers(client_connection.Health(health: 100, dead: False)),
      player_life.CancelTimer(timer: TimerId(8)),
    ]
    as "the lowered health is written to the player and told to its viewers, and the full player's health clock stops"
}

pub fn the_regeneration_numbers_follow_the_properties_test() -> Nil {
  use <- owned_test.run(5000)
  // HealthRegenMultiplier (8) at 2.0 doubles the share of a tick: floor(100 x 0.25 x
  // 2.0) is 50, where the multiplier 1.0 gives 25. The player entered with 10 health.
  let #(life, _) =
    player_life.entering(
      saved: Some(10),
      max_health: 100,
      shield: 0,
      regeneration: quarter_regeneration(),
      place: test_place(),
    )
  let doubled =
    properties_support.with_modifier(
      properties: base_health_100(),
      source: unit_properties.Source(cast_id: 1, effect_id: Spell4EffectsId(1)),
      modifier: unit_properties.Change(
        property: unit_properties.health_regen_multiplier,
        mode: 3,
        multiplier: 2.0,
        flat: 0.0,
        per_level: 0.0,
      ),
    )
  let #(plain, _) = player_life.timer_fired(life:, timer: TimerId(8))
  assert player_life.health(life: plain) == 35
    as "the multiplier 1.0 adds 25 to 10"
  let #(life, _) = player_life.properties_changed(life:, properties: doubled)
  let #(life, _) = player_life.timer_fired(life:, timer: TimerId(8))
  assert player_life.health(life:) == 60 as "the multiplier 2.0 adds 50 to 10"
}

pub fn a_creatures_strike_leaves_a_players_interrupt_armor_test() -> Nil {
  use <- owned_test.run(5000)
  // No creature's strike carries a crowd-control state today (`player_life.struck`
  // answers `controls: []`), so nothing wears a player's Interrupt Armor down: the
  // armor a type 52 row gave is held and shown (the gap is stated in `struck`).
  let source =
    unit_properties.Source(cast_id: 1, effect_id: Spell4EffectsId(199_192))
  // The maximum the row raises (property 44) comes first, as the connection does it.
  let raised =
    properties_support.with_modifier(
      properties: base_health_100(),
      source:,
      modifier: unit_properties.interrupt_armor_modifier(points: 1),
    )
  let #(armed, _) =
    player_life.properties_changed(
      life: player_life.new(
        health: 100,
        shield: 0,
        regeneration: player_life_support.regeneration,
      ),
      properties: raised,
    )
  assert player_life.interrupt_armor(life: armed) == 1
    as "the armor follows the raised maximum"
  let #(life, effects) =
    player_life.struck(
      life: armed,
      defence: defence_of(3),
      strike: attack(1),
      rolls: player_life_support.rolls,
      place: test_place(),
    )
  assert player_life.health(life:) < 100
    as "the blow landed: the Esper's health fell"
  assert player_life.interrupt_armor(life:) == 1
    as "and its armor is as the row gave it"
  assert !list.any(effects, writes_armor) as "no stat 21 is written for a blow"
}

/// Whether the effect writes the player's Interrupt Armor, to it or to a viewer.
fn writes_armor(effect: player_life.Effect) -> Bool {
  case effect {
    ToClient(OwnInterruptArmor(..)) -> True
    ToViewers(client_connection.InterruptArmor(..)) -> True
    ToClient(..) -> False
    ToViewers(..) -> False
    Answer(..)
    | StreamTo(..)
    | player_life.DamageTaken
    | player_life.CombatLeft
    | EndCasts
    | GoToHolocrypt
    | player_life.TellMap(..)
    | StartTimer(..)
    | CancelTimer(..) -> False
  }
}

/// A modifier of `property` that makes x into x * `multiplier` + `flat`.
fn changing(
  property property: Int,
  multiplier multiplier: Float,
  flat flat: Float,
) -> unit_properties.Modifier {
  unit_properties.Change(
    property: UnitProperty2Id(property),
    mode: 1,
    multiplier:,
    flat:,
    per_level: 0.0,
  )
}

/// UnitProperty2.damage_heal_multipliers: the multipliers default to 1.0 and the
/// offsets to 0.0, the damage type is the index (Physical 159 and 150, Tech 160 and
/// 151, Magic 161 and 152). A modifier changes a value as a row says, x * multiplier +
/// flat (`Spell4Effects.effectType.11.change`), and the defence reads the live value.
pub fn player_defence_reads_damage_taken_properties_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let assert Ok(loadout) =
    loadout.of(tables:, class_id: ClassId(1), faction_id: 166)
    as "a Warrior has a Dominion Novice set"
  let properties = properties_support.wearing(loadout:)
  let defence_of = fn(properties) {
    player_life.defence(
      properties:,
      level: 1,
      formulas: rating.formulas(tables:),
    )
  }
  let plain = defence_of(properties)
  assert plain.physical_taken == hit.as_dealt
    && plain.tech_taken == hit.as_dealt
    && plain.magic_taken == hit.as_dealt
    as "multipliers 1.0 and offsets 0.0 by default"
  let modified =
    list.index_fold(
      [
        changing(property: 159, multiplier: 0.5, flat: 0.0),
        changing(property: 160, multiplier: 2.0, flat: 0.0),
        changing(property: 151, multiplier: 1.0, flat: 3.0),
        changing(property: 161, multiplier: 1.25, flat: 0.0),
        changing(property: 152, multiplier: 1.0, flat: 4.0),
      ],
      properties,
      fn(properties, modifier, index) {
        properties_support.with_modifier(
          properties:,
          source: cast_support.source_of(cast_id: index + 1, effect_id: 1900),
          modifier:,
        )
      },
    )
  let defence = defence_of(modified)
  assert defence.physical_taken == hit.DamageTaken(multiplier: 0.5, offset: 0.0)
    as "159 halved, 150 untouched"
  assert defence.tech_taken == hit.DamageTaken(multiplier: 2.0, offset: 3.0)
    as "160 doubled, 151 plus 3"
  assert defence.magic_taken == hit.DamageTaken(multiplier: 1.25, offset: 4.0)
    as "161 x 1.25, 152 plus 4"
  assert defence.physical_mitigation == plain.physical_mitigation
    as "armor's mitigation is not a damage-taken property"
}
