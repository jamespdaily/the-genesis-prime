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
  Answer, ControlBody, ControlGhost, ControlGiven, EndCasts, GhostCreated,
  GhostRemoved, GoToHolocrypt, OwnCameBackLogged, OwnCombatState, OwnDeathLogged,
  OwnDeathState, OwnHealth, OwnResurrectionWindow, OwnShield, StreamTo, ToClient,
  ToViewers,
}
import genesis_prime/game/rating
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{
  Answered, CreatureStriker, Key, Landed, Refused, Strike,
}
import genesis_prime/message/choose_resurrection.{ChooseResurrection}
import genesis_prime/step
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map_id.{MapId}
import gleam/float
import gleam/list
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
      place: test_place(),
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
      place: test_place(),
    )
  assert player_life.health(life:) == 0 as "3 against 1 health: floored at 0"
  let assert [
    ToClient(OwnHealth(health: 0)),
    ToViewers(client_connection.Health(health: 0, dead: True)),
    Answer(
      answered: Answered(outcome: Landed(descriptions: [description]), ..),
      ..,
    ),
    ..
  ] = effects
    as "no shield to change: 0x92f and 0x937 at 0, then the answer, then the death"
  assert description.damage.killed == 1 && description.damage.overkill == 2
    as "the killed bit, and 2 beyond the 1 health"
  let #(_, later) =
    player_life.struck(
      life:,
      defence: defence_of(1),
      strike: attack(2),
      rolls:,
      place: test_place(),
    )
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

/// The player's unit in these rules: the unit the Beast's strikes name.
const own_unit = 20

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
      rolls:,
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
      life: player_life.new(health: 736, shield: 450),
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
        | EndCasts
        | GoToHolocrypt -> True
      }
    })
      |> list.drop(1),
  )
}

/// 0x15a's body: the unit, the choice and the third value.
fn choice_body(
  unit_id unit_id: Int,
  choice choice: Int,
  value value: Int,
) -> BitArray {
  let assert Ok(body) =
    choose_resurrection.encode(ChooseResurrection(
      unit_id:,
      choice:,
      field_3: value,
    ))
    as "a unit id, a 7-bit choice and a 32-bit value fit the message"
  body
}

fn chosen(
  life: player_life.Life,
  body: BitArray,
) -> Result(#(player_life.Life, List(player_life.Effect)), player_life.Refusal) {
  player_life.take(
    life:,
    message: player_life.ResurrectionChosen,
    body:,
    unit_id: own_unit,
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
      EndCasts,
      ToClient(OwnDeathLogged),
      ToViewers(client_connection.DeathLogged),
      ToClient(GhostCreated(place: test_place())),
      ToClient(OwnResurrectionWindow(dead: True)),
      ToClient(ControlGiven(to: ControlGhost)),
    ]
    as "0x88c (P, 1) and 0x89a (P, 0) to the player and its viewers, its casts ended, 0x247 type 22 to both, then for its own client alone the ghost's 0x262 at the body's place, 0x1b3 and 0x636 for the ghost"
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
      rolls:,
      place: test_place(),
    )
  assert refused
    == [
      Answer(
        to: beast(),
        answered: Answered(
          key: Key(cast_id: 9999, phase: 0, unit_id: own_unit),
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
  assert chosen(dead, choice_body(unit_id: 21, choice: 1, value: 0))
    == Error(player_life.NotThePlayer(unit_id: 21))
    as "another unit"
  assert chosen(dead, choice_body(unit_id: 1_048_596, choice: 1, value: 0))
    == Error(player_life.NotThePlayer(unit_id: 1_048_596))
    as "the ghost's own id, 2^20 + 20 (the server's choice of a ghost id): the Death addon names the player's unit"
  assert chosen(dead, choice_body(unit_id: own_unit, choice: 4, value: 0))
    == Error(player_life.NotOffered(choice: player_life.OtherChoice(value: 4)))
    && chosen(dead, choice_body(unit_id: own_unit, choice: 32, value: 0))
    == Error(player_life.NotOffered(choice: player_life.OtherChoice(value: 32)))
    && chosen(dead, choice_body(unit_id: own_unit, choice: 0, value: 0))
    == Error(player_life.NotOffered(choice: player_life.OtherChoice(value: 0)))
    as "a caster's resurrection (4), Exit Instance (32) and 0: the window offered only 1 and 2"
  assert chosen(dead, choice_body(unit_id: own_unit, choice: 1, value: 5))
    == Error(player_life.NonzeroValue(value: 5))
    as "the Death addon always sends 0"
  assert chosen(
      player_life.new(health: 736, shield: 450),
      choice_body(unit_id: own_unit, choice: 1, value: 0),
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
    chosen(dead, choice_body(unit_id: own_unit, choice: 1, value: 0))
  assert chosen(alive, choice_body(unit_id: own_unit, choice: 2, value: 0))
    == Error(player_life.NotDead)
    as "the first choice brought the player back: the second finds it alive"
}

pub fn wake_here_brings_the_player_back_at_full_health_and_full_shield_where_its_body_lies_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(dead, _) = a_dead_warrior()
  let assert Ok(#(life, effects)) =
    chosen(dead, choice_body(unit_id: own_unit, choice: 1, value: 0))
  assert effects == came_back_effects()
    as "0x92f full and the full shield, 0x88c (P, 0) to the player and its viewers, 0x1b3 dead 0, the ghost's 0x355, 0x636 for the body, 0x247 type 23 to both, in that order"
  assert player_life.state(life:) == player_life.Alive
    && player_life.health(life:) == 736
    && player_life.shield(life:) == 450
  let #(after, later) =
    player_life.struck(
      life:,
      defence: defence_of(1),
      strike: attack(9999),
      rolls:,
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
    chosen(dead, choice_body(unit_id: own_unit, choice: 2, value: 0))
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
