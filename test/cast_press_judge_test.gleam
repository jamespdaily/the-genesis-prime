//// What the client refuses of a press at another player, in its order
//// (`genesis_prime/game/cast/press_target`). Expected values come from these places.
//// - `0x1403ad540` (`CheckCastTargetFaction`, before the caster checks) and `0x1403b4560`
////   (`CheckCastPlayerTargetFaction`, in `CheckCastUnitTargetRange`), with the fact file's
////   `Spell4TargetMechanics.flags` and `Spell4ValidTargets.targetBitmask`: the mechanics flag
////   n is the value 1 << n, the valid-target bit n likewise.
//// - `opcode.0x9d.target_checks`, `0x1403b0880` (286, 255, 256) and `0x1403b2240` (the
////   conditions, the crowd-control conditions `0x1403b2c40`, the type test 102, the cast group
////   89, then the range 104, 105, 183, edge to edge): the order of the checks.
//// - Mind Over Body (Spell4 32820): Spell4TargetMechanics row 4 (flags 11), valid targets 0,
////   target conditions mask 129 value 0, range 0 to 35, vertical -1. The Race rows give every
////   player race a hit radius of 1.2, so two players are 2.4 m closer edge to edge than
////   their centres are.
//// - The 2 m allowance on the maximum range is the server's guess (a moving player's picture
////   lags), the only value here the client does not give.

import cast_support as support
import genesis_prime/game/cast/press_target
import genesis_prime/game/cast/state.{type Caster, type Verdict} as cast_state
import genesis_prime/game/faction_level.{
  type Disposition, Friendly, Hostile, Neutral,
}
import genesis_prime/game/held_state.{type HeldState, HeldState}
import genesis_prime/game/player_state.{type PlayerState, PlayerState}
import genesis_prime/game/spell_plan.{
  type Spell, type TargetAim, FacesWithin, Limits, MustBeDead, MustBeInCombat,
  OutOfCombatOnly, PetBits, Spell, TargetAim,
}
import genesis_prime/game/start_place
import genesis_prime/game/target_mechanic.{Targeted, Targeting}
import genesis_prime/message/cast_result
import genesis_prime/message/crowd_control_state
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import owned_test
import player_state_support
import spell_tables

/// What a check of a press comes to.
type Outcome {
  Passes
  Refuses(result: Int)
  Unbuilt(words: String)
}

/// Where in the client's order a faction refusal comes.
type Pass {
  FirstPass
  SecondPass
}

fn mind_over_body() -> Spell {
  spell_tables.client_spell(spell4_id: 32_820)
}

fn with_flags(
  spell spell: Spell,
  mechanics mechanics: Int,
  valid valid: Int,
) -> Spell {
  Spell(
    ..spell,
    targeting: Targeting(
      kind: Targeted,
      mechanics_flags: mechanics,
      valid_targets: valid,
    ),
  )
}

fn with_aim(spell: Spell, change: fn(TargetAim) -> TargetAim) -> Spell {
  Spell(..spell, target_aim: change(spell.target_aim))
}

/// The caster of the shared scene, standing at the live character's place.
fn caster() -> Caster {
  support.caster()
}

/// The ally `metres` east of the caster at the caster's height, otherwise at the defaults.
fn ally_at(metres metres: Float) -> PlayerState {
  ally_beside(east: metres, up: 0.0)
}

fn ally_beside(east east: Float, up up: Float) -> PlayerState {
  player_state_support.beside_the_caster(east:, up:)
}

fn ally() -> PlayerState {
  ally_at(metres: 10.0)
}

fn outcome_of(verdict verdict: Option(Verdict)) -> Outcome {
  case verdict {
    None -> Passes
    Some(cast_state.Refuse(result:)) ->
      Refuses(result: cast_result.to_value(result))
    Some(cast_state.NotBuilt(result: _, why:)) -> Unbuilt(words: why)
    Some(cast_state.Accept(..))
    | Some(cast_state.Hold(..))
    | Some(cast_state.HoldForCast) ->
      panic as "the target checks never accept or hold a press"
  }
}

/// The checks in the client's order: the faction test before the caster checks, then the
/// target block.
fn first_refusal(
  spell spell: Spell,
  caster caster: Caster,
  target target: PlayerState,
) -> Outcome {
  case press_target.faction_precheck(spell:, caster:, target:) {
    Some(refused) -> outcome_of(verdict: Some(refused))
    None -> outcome_of(verdict: press_target.judge(spell:, caster:, target:))
  }
}

fn matches(outcome outcome: Outcome, expected expected: Outcome) -> Bool {
  case outcome, expected {
    Passes, Passes -> True
    Refuses(result: found), Refuses(result: wanted) -> found == wanted
    Unbuilt(words: found), Unbuilt(words: wanted) ->
      string.contains(found, wanted)
    Passes, Refuses(..)
    | Passes, Unbuilt(..)
    | Refuses(..), Passes
    | Refuses(..), Unbuilt(..)
    | Unbuilt(..), Passes
    | Unbuilt(..), Refuses(..)
    -> False
  }
}

type Row {
  Row(
    why: String,
    spell: Spell,
    caster: Caster,
    target: PlayerState,
    expected: Outcome,
  )
}

/// A row of the shared scene: Mind Over Body at a live ally 10 m away.
fn row(why: String, expected: Outcome) -> Row {
  Row(
    why:,
    spell: mind_over_body(),
    caster: caster(),
    target: ally(),
    expected:,
  )
}

fn stunned() -> List(HeldState) {
  [HeldState(state: crowd_control_state.Stun, instance_id: 1)]
}

fn pet_bits(
  must_be_pet must_be_pet: Bool,
  must_be_master must_be_master: Bool,
) -> Spell {
  with_aim(mind_over_body(), fn(aim) {
    TargetAim(..aim, pets: PetBits(must_be_pet:, must_be_master:))
  })
}

fn combat(combat combat: spell_plan.TargetCombat) -> Spell {
  with_aim(mind_over_body(), fn(aim) { TargetAim(..aim, combat:) })
}

fn unread(why why: String) -> Spell {
  with_aim(mind_over_body(), fn(aim) { TargetAim(..aim, unread: Some(why)) })
}

fn cast_group(spell spell: Spell) -> Spell {
  with_aim(spell, fn(aim) { TargetAim(..aim, cast_group_id: 5) })
}

fn ranged(min min: Float, vertical vertical: Float) -> Spell {
  with_aim(mind_over_body(), fn(aim) {
    TargetAim(..aim, limits: Limits(min:, max: 35.0, vertical:))
  })
}

/// Mind Over Body with a facing arc of `arc_degrees` and the range limits `min`, `max`.
fn facing(arc_degrees arc_degrees: Float) -> Spell {
  with_aim(mind_over_body(), fn(aim) {
    TargetAim(..aim, facing: FacesWithin(arc_degrees:))
  })
}

/// Mind Over Body with a maximum range of `max`.
fn reaching(max max: Float) -> Spell {
  with_aim(mind_over_body(), fn(aim) {
    TargetAim(..aim, limits: Limits(min: 0.0, max:, vertical: -1.0))
  })
}

/// The caster turned to face `yaw` radians, as its last rotation command left it.
fn caster_facing(yaw yaw: Float) -> Caster {
  let caster = caster()
  cast_state.Caster(
    ..caster,
    place: start_place.turned(
      place: caster.place,
      facing: start_place.Facing(yaw:, pitch: 0.0, roll: 0.0),
    ),
  )
}

fn masked(mask mask: Int) -> Spell {
  Spell(..mind_over_body(), target_cc_mask: mask)
}

fn check(rows rows: List(Row)) -> Nil {
  list.each(rows, fn(row) {
    assert matches(
      outcome: first_refusal(
        spell: row.spell,
        caster: row.caster,
        target: row.target,
      ),
      expected: row.expected,
    )
      as row.why
  })
}

pub fn each_check_of_a_press_at_another_player_gives_the_clients_result_test() -> Nil {
  use <- owned_test.run(10_000)
  let dead = PlayerState(..ally(), alive: False)
  let grouped = PlayerState(..ally(), group_id: 9)
  let caster_grouped = cast_state.Caster(..caster(), group_id: 9)
  let silenced = [
    HeldState(state: crowd_control_state.Silence, instance_id: 2),
  ]
  let rooted_and_stunned = [
    HeldState(state: crowd_control_state.Root, instance_id: 3),
    HeldState(state: crowd_control_state.Stun, instance_id: 4),
  ]
  check(rows: [
    row("the control row: a live ally 10 m away passes", Passes),
    Row(
      ..row(
        "0x1403b2240: Mind Over Body's conditions (value 0) refuse a dead target 106",
        Refuses(106),
      ),
      target: dead,
    ),
    Row(
      ..row(
        "the same spell with value 1 (must be dead) refuses a live target 107",
        Refuses(107),
      ),
      spell: Spell(..mind_over_body(), target_death: MustBeDead),
    ),
    Row(
      ..row("must be dead passes a dead target", Passes),
      spell: Spell(..mind_over_body(), target_death: MustBeDead),
      target: dead,
    ),
    Row(
      ..row("out of combat only refuses a target in combat 108", Refuses(108)),
      spell: combat(combat: OutOfCombatOnly),
      target: PlayerState(..ally(), in_combat: True),
    ),
    Row(
      ..row(
        "must be in combat refuses a target out of combat 109",
        Refuses(109),
      ),
      spell: combat(combat: MustBeInCombat),
    ),
    Row(
      ..row("must be in combat passes a target in combat", Passes),
      spell: combat(combat: MustBeInCombat),
      target: PlayerState(..ally(), in_combat: True),
    ),
    Row(
      ..row(
        "0x1403b2c40: a target holding Stun with the mask's bit 0 is refused 122",
        Refuses(122),
      ),
      spell: masked(mask: 1),
      target: PlayerState(..ally(), held: stunned()),
    ),
    Row(
      ..row(
        "a target holding Silence with the mask's bit 4 is refused 130",
        Refuses(130),
      ),
      spell: masked(mask: 16),
      target: PlayerState(..ally(), held: silenced),
    ),
    Row(
      ..row("a state the mask does not name passes", Passes),
      spell: masked(mask: 16),
      target: PlayerState(..ally(), held: stunned()),
    ),
    Row(
      ..row(
        "Root and Stun both masked: the lowest state's result, Stun 122",
        Refuses(122),
      ),
      spell: masked(mask: 5),
      target: PlayerState(..ally(), held: rooted_and_stunned),
    ),
    Row(
      ..row("valid-target bit 0 refuses a player 102", Refuses(102)),
      spell: with_flags(spell: mind_over_body(), mechanics: 11, valid: 1),
    ),
    Row(
      ..row(
        "valid-target bit 4 refuses a player outside the caster's group (both group ids 0) 286",
        Refuses(286),
      ),
      spell: with_flags(spell: mind_over_body(), mechanics: 11, valid: 16),
    ),
    Row(
      ..row(
        "valid-target bit 4 passes a player in the caster's group (equal, non-zero ids)",
        Passes,
      ),
      spell: with_flags(spell: mind_over_body(), mechanics: 11, valid: 16),
      caster: caster_grouped,
      target: grouped,
    ),
    Row(
      ..row(
        "targetingFlags bit 2: the target must be the caster's pet 255",
        Refuses(255),
      ),
      spell: pet_bits(must_be_pet: True, must_be_master: False),
    ),
    Row(
      ..row(
        "targetingFlags bit 3: the target must be the caster's master 256",
        Refuses(256),
      ),
      spell: pet_bits(must_be_pet: False, must_be_master: True),
    ),
    Row(
      ..row("an unread target vital is not built, in words", Unbuilt("vital")),
      spell: unread(why: "a target vital requirement"),
    ),
    Row(
      ..row("an unread required zone is not built, in words", Unbuilt("zone")),
      spell: unread(why: "a required zone"),
    ),
    Row(
      ..row(
        "an unread condition bit is not built, in words",
        Unbuilt("condition"),
      ),
      spell: unread(why: "a target condition bit"),
    ),
    Row(
      ..row("a cast group is not built, in words", Unbuilt("cast group")),
      spell: cast_group(spell: mind_over_body()),
    ),
    Row(
      ..row("range: centre distance 37.4 (edge to edge 35.0) passes", Passes),
      target: ally_at(metres: 37.4),
    ),
    Row(
      ..row("the server's 2 m allowance on the maximum: 39.4 passes", Passes),
      target: ally_at(metres: 39.4),
    ),
    Row(
      ..row("beyond the allowance: 39.5 is 105", Refuses(105)),
      target: ally_at(metres: 39.5),
    ),
    Row(
      ..row(
        "a synthetic minimum of 5: an edge gap of 4.9 (centres 7.3) is 104",
        Refuses(104),
      ),
      spell: ranged(min: 5.0, vertical: -1.0),
      target: ally_at(metres: 7.3),
    ),
    Row(
      ..row("an edge gap of 5.1 (centres 7.5) passes the minimum", Passes),
      spell: ranged(min: 5.0, vertical: -1.0),
      target: ally_at(metres: 7.5),
    ),
    Row(
      ..row(
        "a synthetic vertical range of 3: a height difference of 5.5 (3.1 edge to edge) is 183",
        Refuses(183),
      ),
      spell: ranged(min: 0.0, vertical: 3.0),
      target: ally_beside(east: 10.0, up: 5.5),
    ),
    Row(
      ..row("a height difference of 5.3 (2.9 edge to edge) passes", Passes),
      spell: ranged(min: 0.0, vertical: 3.0),
      target: ally_beside(east: 10.0, up: 5.3),
    ),
    Row(
      ..row(
        "a vertical range of -1 is never refused 183: 20 m above (17.6 edge to edge, 22.4 apart) passes",
        Passes,
      ),
      target: ally_beside(east: 10.0, up: 20.0),
    ),
    Row(
      ..row(
        "the target's hit radius counts: radius 3.0 at centres 41.0 (edge gap 36.8) passes",
        Passes,
      ),
      target: PlayerState(..ally_at(metres: 41.0), hit_radius: 3.0),
    ),
    Row(
      ..row("radius 3.0 at centres 41.4 (edge gap 37.2) is 105", Refuses(105)),
      target: PlayerState(..ally_at(metres: 41.4), hit_radius: 3.0),
    ),
    Row(
      ..row(
        "the caster's hit radius counts: radius 3.0 at centres 41.0 passes",
        Passes,
      ),
      caster: cast_state.Caster(..caster(), hit_radius: 3.0),
      target: ally_at(metres: 41.0),
    ),
    Row(
      ..row("the caster's radius 3.0 at 41.4 is 105", Refuses(105)),
      caster: cast_state.Caster(..caster(), hit_radius: 3.0),
      target: ally_at(metres: 41.4),
    ),
    Row(
      ..row("no place known for the target: 91", Refuses(91)),
      target: PlayerState(..ally(), place: None),
    ),
    Row(
      ..row(
        "a spell with maximum 0 gets no allowance: an edge gap of 0.1 (centres 2.5) is 105",
        Refuses(105),
      ),
      spell: reaching(max: 0.0),
      target: ally_at(metres: 2.5),
    ),
    Row(
      ..row(
        "a spell with maximum 0 reaches a target whose edges touch (centres 2.39)",
        Passes,
      ),
      spell: reaching(max: 0.0),
      target: ally_at(metres: 2.39),
    ),
    Row(
      ..row(
        "a target angle of 90 passes a target straight ahead (the facing of a character that has never turned is -z)",
        Passes,
      ),
      spell: facing(arc_degrees: 90.0),
      target: player_state_support.around_the_caster(
        east: 0.0,
        south: -10.0,
        up: 0.0,
      ),
    ),
    Row(
      ..row(
        "a target angle of 90 passes a target 26.6 degrees off the facing (half arc 45)",
        Passes,
      ),
      spell: facing(arc_degrees: 90.0),
      target: player_state_support.around_the_caster(
        east: 5.0,
        south: -10.0,
        up: 0.0,
      ),
    ),
    Row(
      ..row(
        "a target angle of 90 refuses a target at the side: 101",
        Refuses(101),
      ),
      spell: facing(arc_degrees: 90.0),
      target: ally_at(metres: 10.0),
    ),
    Row(
      ..row("a target angle of 90 refuses a target behind: 101", Refuses(101)),
      spell: facing(arc_degrees: 90.0),
      target: player_state_support.around_the_caster(
        east: 0.0,
        south: 10.0,
        up: 0.0,
      ),
    ),
    Row(
      ..row(
        "a target angle of 90 refuses a target on the caster's own point: 101",
        Refuses(101),
      ),
      spell: facing(arc_degrees: 90.0),
      target: player_state_support.around_the_caster(
        east: 0.0,
        south: 0.0,
        up: 0.0,
      ),
    ),
    Row(
      ..row(
        "a target angle of 200 passes the side (90 degrees off a half arc of 100)",
        Passes,
      ),
      spell: facing(arc_degrees: 200.0),
      target: ally_at(metres: 10.0),
    ),
    Row(
      ..row(
        "the caster's facing counts: turned a quarter turn to -x, a target 10 m east is behind it",
        Refuses(101),
      ),
      spell: facing(arc_degrees: 90.0),
      caster: caster_facing(yaw: 1.5707963267948966),
      target: ally_at(metres: 10.0),
    ),
    Row(
      ..row(
        "turned a quarter turn to -x, a target 10 m west is straight ahead",
        Passes,
      ),
      spell: facing(arc_degrees: 90.0),
      caster: caster_facing(yaw: 1.5707963267948966),
      target: ally_at(metres: -10.0),
    ),
  ])
}

pub fn the_checks_at_another_player_run_in_the_clients_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let dead = PlayerState(..ally(), alive: False)
  check(rows: [
    Row(
      ..row(
        "0x1403ad540 runs before the target block: a hostile faction and dead is 99, not 106",
        Refuses(99),
      ),
      target: PlayerState(..dead, disposition: Hostile),
    ),
    Row(
      ..row(
        "286 before the conditions: outside the group and dead",
        Refuses(286),
      ),
      spell: with_flags(spell: mind_over_body(), mechanics: 11, valid: 16),
      target: dead,
    ),
    Row(
      ..row("255 before the conditions: a pet bit and dead", Refuses(255)),
      spell: pet_bits(must_be_pet: True, must_be_master: False),
      target: dead,
    ),
    Row(
      ..row(
        "140 and 98 come before the conditions: an unread vital and dead is not built",
        Unbuilt("vital"),
      ),
      spell: unread(why: "a target vital requirement"),
      target: dead,
    ),
    Row(
      ..row("life before combat: dead and in combat is 106", Refuses(106)),
      spell: combat(combat: OutOfCombatOnly),
      target: PlayerState(..dead, in_combat: True),
    ),
    Row(
      ..row(
        "combat before the crowd-control conditions: in combat and stunned is 108",
        Refuses(108),
      ),
      spell: Spell(..combat(combat: OutOfCombatOnly), target_cc_mask: 1),
      target: PlayerState(..ally(), in_combat: True, held: stunned()),
    ),
    Row(
      ..row(
        "the crowd-control conditions before the type test: stunned and valid-target bit 0 is 122",
        Refuses(122),
      ),
      spell: Spell(
        ..with_flags(spell: mind_over_body(), mechanics: 11, valid: 1),
        target_cc_mask: 1,
      ),
      target: PlayerState(..ally(), held: stunned()),
    ),
    Row(
      ..row(
        "the type test before the cast group: 102 and a cast group is 102",
        Refuses(102),
      ),
      spell: cast_group(spell: with_flags(
        spell: mind_over_body(),
        mechanics: 11,
        valid: 1,
      )),
    ),
    Row(
      ..row(
        "the cast group before the second pass: a cast group and an unflagged opposite-faction target (flag 4) is not built",
        Unbuilt("cast group"),
      ),
      spell: cast_group(spell: with_flags(
        spell: mind_over_body(),
        mechanics: 16,
        valid: 0,
      )),
      target: PlayerState(..ally(), disposition: Hostile),
    ),
    Row(
      ..row(
        "the second pass before the range: 322 and out of range is 322",
        Refuses(322),
      ),
      spell: with_flags(spell: mind_over_body(), mechanics: 16, valid: 0),
      target: PlayerState(..ally_at(metres: 60.0), disposition: Hostile),
    ),
    Row(
      ..row(
        "the minimum before the height: 6 m straight above (3.6 edge to edge, below the minimum 8 and above the vertical range 3) is 104",
        Refuses(104),
      ),
      spell: ranged(min: 8.0, vertical: 3.0),
      target: ally_beside(east: 0.0, up: 6.0),
    ),
    Row(
      ..row(
        "the range before the facing: too far and behind is 105",
        Refuses(105),
      ),
      spell: facing(arc_degrees: 90.0),
      target: player_state_support.around_the_caster(
        east: 0.0,
        south: 40.0,
        up: 0.0,
      ),
    ),
    Row(
      ..row(
        "the maximum before the height: too far and too high is 105",
        Refuses(105),
      ),
      spell: ranged(min: 0.0, vertical: 3.0),
      target: ally_beside(east: 50.0, up: 10.0),
    ),
  ])
}

/// One branch of the faction tests: who the target is to the caster, the flags of the spell,
/// and which pass refuses with what, none when both pass.
type Faction {
  Faction(
    why: String,
    disposition: Disposition,
    shares_group: Bool,
    target_flagged: Bool,
    caster_flagged: Bool,
    mechanics: Int,
    valid: Int,
    refused: Option(#(Pass, Int)),
  )
}

pub fn the_faction_tests_of_a_press_at_another_player_follow_the_clients_branches_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      Faction(
        "Friendly with flags 0 and 3 (Mind Over Body, 11) passes both",
        Friendly,
        False,
        False,
        False,
        11,
        0,
        None,
      ),
      Faction(
        "Friendly with flag 0 only is 99 at the first pass",
        Friendly,
        False,
        False,
        False,
        1,
        0,
        Some(#(FirstPass, 99)),
      ),
      Faction(
        "Friendly with flag 0 only and valid-target bit 1 passes both",
        Friendly,
        False,
        False,
        False,
        1,
        2,
        None,
      ),
      Faction(
        "Friendly, target flagged, caster not: 323",
        Friendly,
        False,
        True,
        False,
        11,
        0,
        Some(#(SecondPass, 323)),
      ),
      Faction(
        "Friendly, both flagged: passes",
        Friendly,
        False,
        True,
        True,
        11,
        0,
        None,
      ),
      Faction(
        "Hostile with flags 0 and 3 is 99 at the first pass (flag 4 clear)",
        Hostile,
        False,
        False,
        False,
        9,
        0,
        Some(#(FirstPass, 99)),
      ),
      Faction(
        "Hostile with flag 4, target not flagged: 322",
        Hostile,
        False,
        False,
        False,
        16,
        0,
        Some(#(SecondPass, 322)),
      ),
      Faction(
        "Hostile with flag 4, target flagged, caster not: 323",
        Hostile,
        False,
        True,
        False,
        16,
        0,
        Some(#(SecondPass, 323)),
      ),
      Faction(
        "Hostile with flags 0 and 4, both flagged: passes",
        Hostile,
        False,
        True,
        True,
        17,
        0,
        None,
      ),
      Faction(
        "Hostile with flag 0 only, both flagged: 99 at the first pass",
        Hostile,
        False,
        True,
        True,
        1,
        0,
        Some(#(FirstPass, 99)),
      ),
      Faction(
        "Hostile sharing a group with flags 0 and 3: passes",
        Hostile,
        True,
        False,
        False,
        9,
        0,
        None,
      ),
      Faction(
        "Hostile sharing a group with flag 3 only: 99 at the second pass",
        Hostile,
        True,
        False,
        False,
        8,
        0,
        Some(#(SecondPass, 99)),
      ),
      Faction(
        "Neutral with flag 0 is 99 at the first pass",
        Neutral,
        False,
        False,
        False,
        1,
        0,
        Some(#(FirstPass, 99)),
      ),
      Faction(
        "Neutral with no flags, target not flagged: 322",
        Neutral,
        False,
        False,
        False,
        0,
        0,
        Some(#(SecondPass, 322)),
      ),
    ],
    fn(row) {
      let spell =
        with_flags(
          spell: mind_over_body(),
          mechanics: row.mechanics,
          valid: row.valid,
        )
      let group = case row.shares_group {
        True -> 9
        False -> 0
      }
      let caster =
        cast_state.Caster(
          ..caster(),
          pvp_flagged: row.caster_flagged,
          group_id: group,
        )
      let target =
        PlayerState(
          ..ally(),
          disposition: row.disposition,
          pvp_flagged: row.target_flagged,
          group_id: group,
        )
      let first =
        outcome_of(verdict: press_target.faction_precheck(
          spell:,
          caster:,
          target:,
        ))
      let second =
        outcome_of(verdict: press_target.judge(spell:, caster:, target:))
      case row.refused {
        None -> {
          assert first == Passes as row.why
          assert second == Passes as row.why
        }
        Some(#(FirstPass, result)) -> {
          assert first == Refuses(result:) as row.why
        }
        Some(#(SecondPass, result)) -> {
          assert first == Passes as row.why
          assert second == Refuses(result:) as row.why
        }
      }
    },
  )
}
