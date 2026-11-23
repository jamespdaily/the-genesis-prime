//// What the client refuses of a press at another player, in its order: the target block of
//// `CheckCast`, which the cast rule runs for a bag press (0x9a) or a held key (0x4db) once
//// the player's picture of the target is known (genesis_prime/game/player_state).
////
//// ```
//// press ─▶ faction_precheck (99)                          before the caster checks
////       ─▶ cast_press.verdict (the caster's own checks)
////       ─▶ judge: 286 ─▶ 255, 256 ─▶ unread ─▶ 106, 107 ─▶ 108, 109 ─▶ crowd control ─▶ 102
////                 ─▶ cast group ─▶ 99, 322, 323 ─▶ 104, 105, 183 ─▶ 101
//// ```
////
//// - **The first faction test** runs before the caster checks (`CheckCastTargetFaction`
////   `0x1403ad540`, called from `0x14039a040` at `0x14039a47f`): a spell with valid-target
////   bit 1 skips it; a Friendly target, or one in the caster's group, is refused 99 unless
////   the spell has mechanics flag 3; any other target is refused 99 when it is Hostile and the
////   spell lacks mechanics flag 4, or Neutral and the spell has mechanics flag 0.
//// - **The target block** runs only when the caster's own checks pass or queue the press
////   (`CheckCast` `0x1403ae8c0`, then `CheckCastTarget` `0x1403b0880`, then
////   `CheckCastUnitTargetRange` `0x1403b2240`): 286 for valid-target bit 4 outside the
////   caster's group; 255 and 256 for the pet bits, which no player meets since the server
////   gives no player an owned unit; the target's life 106, 107 and combat 108, 109; the
////   crowd-control states the spell's mask names (`0x1403b2c40`); 102 for valid-target bit 0;
////   the faction test again for a cast between players (`CheckCastPlayerTargetFaction`
////   `0x1403b4560`); the range, edge to edge; the facing arc (101, `0x1400a7a40`).
//// - **A held key has no client check** (`AbilityPressHold` `0x1403bd3d0` sends the message
////   without one), so the answer to a 0x4db is the server's own: the same order, as the result
////   the client gives a 0x9a (the server's choice).
//// - **The range** has an allowance of 2 m beyond the spell's maximum, the server's guess: the
////   picture of a moving player is its last position command's place, up to about two movement
////   send intervals old (`range_allowance_metres`).
//// - **Not judged** (listed in `cast_press.gaps`): a spell with a cast group, a target vital
////   requirement, a required zone, an unread target condition bit or a target angle that a
////   movement flag of the caster can waive is refused as not built; line of sight and
////   terrain (166); invulnerable and immune states (96, 92), a taxi
////   ride (120) and a duel; the creature word 0x18 of a tradeskill node target (181); and an
////   unnamed game word at `0x7258` that can waive 323 for a PvP-flagged friendly target (read
////   as clear).

import genesis_prime/game/activate
import genesis_prime/game/area
import genesis_prime/game/cast/state.{
  type Caster, type Verdict, NotBuilt, Refuse,
}
import genesis_prime/game/crowd_control
import genesis_prime/game/faction_level.{Friendly, Hostile, Neutral}
import genesis_prime/game/held_state
import genesis_prime/game/player_state.{type PlayerState}
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/target_mechanic
import genesis_prime/message/cast_result
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import gleam/bool
import gleam/option.{type Option, None, Some}

/// How far beyond a spell's maximum range a press at another player is allowed, in metres.
/// The server's guess: the caster's picture of a moving player lags by up to about two
/// movement send intervals, and the default press (0x4db) has no client check of its own, so
/// strict judging would refuse at the edge a press the player's own screen shows in range.
const range_allowance_metres = 2.0

/// The Spell4TargetMechanics.flags values the checks test (the fact file's
/// `Spell4TargetMechanics.flags`); the Spell4ValidTargets.targetBitmask bits are named in
/// `target_mechanic`.
const mechanics_friendly_passes = 8

const mechanics_hostile_passes = 16

/// Whether the target is in the caster's group: both group ids are non-zero and equal
/// (`UnitsShareGroup` `0x140561e60`).
fn shares_group(caster caster: Caster, target target: PlayerState) -> Bool {
  caster.group_id != 0 && caster.group_id == target.group_id
}

fn refused_as(result result: cast_result.CastResult) -> Option(Verdict) {
  Some(Refuse(result:))
}

fn has(flags flags: Int, bit bit: Int) -> Bool {
  spell_effect.has_flag(flags:, bit:)
}

/// The faction test the client runs before the caster's own checks (`0x1403ad540`), or none
/// when the spell passes it.
pub fn faction_precheck(
  spell spell: Spell,
  caster caster: Caster,
  target target: PlayerState,
) -> Option(Verdict) {
  let flags = spell.targeting.mechanics_flags
  let refuses = case
    has(
      flags: spell.targeting.valid_targets,
      bit: target_mechanic.valid_skips_faction_test,
    )
  {
    True -> False
    False ->
      case shares_group(caster:, target:) || target.disposition == Friendly {
        True -> !has(flags:, bit: mechanics_friendly_passes)
        False ->
          case target.disposition {
            Hostile -> !has(flags:, bit: mechanics_hostile_passes)
            Neutral -> target_mechanic.is_beneficial(flags:)
            Friendly -> False
          }
      }
  }
  case refuses {
    True -> refused_as(result: cast_result.TargetFaction)
    False -> None
  }
}

/// The checks of the target block, in the client's order, after the caster's own checks: the
/// first refusal, or none when the target passes.
pub fn judge(
  spell spell: Spell,
  caster caster: Caster,
  target target: PlayerState,
) -> Option(Verdict) {
  let aim = spell.target_aim
  group_refusal(spell:, caster:, target:)
  |> option.lazy_or(fn() { pet_refusal(aim:) })
  |> option.lazy_or(fn() { unread_refusal(aim:) })
  |> option.lazy_or(fn() {
    option.map(
      life_refusal(target_death: spell.target_death, alive: target.alive),
      fn(result) { Refuse(result:) },
    )
  })
  |> option.lazy_or(fn() {
    option.map(
      combat_refusal(combat: aim.combat, in_combat: target.in_combat),
      fn(result) { Refuse(result:) },
    )
  })
  |> option.lazy_or(fn() {
    option.map(
      held_refusal(
        mask: spell.target_cc_mask,
        held: held_state.states(held: target.held),
      ),
      fn(result) { Refuse(result:) },
    )
  })
  |> option.lazy_or(fn() { type_refusal(spell:) })
  |> option.lazy_or(fn() { cast_group_refusal(aim:) })
  |> option.lazy_or(fn() { second_faction_refusal(spell:, caster:, target:) })
  |> option.lazy_or(fn() { range_refusal(aim:, caster:, target:) })
}

/// 286: valid-target bit 4 and a target outside the caster's group (`0x1403b0880`).
fn group_refusal(
  spell spell: Spell,
  caster caster: Caster,
  target target: PlayerState,
) -> Option(Verdict) {
  use <- bool.guard(
    when: !has(
      flags: spell.targeting.valid_targets,
      bit: target_mechanic.valid_same_group_only,
    )
      || shares_group(caster:, target:),
    return: None,
  )
  refused_as(result: cast_result.TargetNotInSameGroup)
}

/// 255 and 256: a spell that needs the target to be the caster's pet or master, which no
/// player is, as the server gives no player an owned unit (`0x1403b0880`).
fn pet_refusal(aim aim: spell_plan.TargetAim) -> Option(Verdict) {
  case aim.pets.must_be_pet, aim.pets.must_be_master {
    True, _ -> refused_as(result: cast_result.TargetMustBeCastersPet)
    False, True -> refused_as(result: cast_result.TargetMustBeCastersMaster)
    False, False -> None
  }
}

/// A spell with a target row the plan does not read is not built, with the cause in words.
fn unread_refusal(aim aim: spell_plan.TargetAim) -> Option(Verdict) {
  option.map(aim.unread, fn(cause) {
    NotBuilt(
      result: cast_result.IllegalSpellCast,
      why: "is pressed at another player and has "
        <> cause
        <> ", which the server does not read",
    )
  })
}

/// The client's 106 and 107 for the target's life (`0x1403b2240`).
pub fn life_refusal(
  target_death target_death: spell_plan.CasterDeath,
  alive alive: Bool,
) -> Option(cast_result.CastResult) {
  case target_death, alive {
    spell_plan.CannotBeDead, False -> Some(cast_result.TargetCannotBeDead)
    spell_plan.MustBeDead, True -> Some(cast_result.TargetMustBeDead)
    spell_plan.CannotBeDead, True
    | spell_plan.MustBeDead, False
    | spell_plan.AliveOrDead, _
    -> None
  }
}

/// The client's 108 and 109 for the target's combat.
pub fn combat_refusal(
  combat combat: spell_plan.TargetCombat,
  in_combat in_combat: Bool,
) -> Option(cast_result.CastResult) {
  case combat, in_combat {
    spell_plan.OutOfCombatOnly, True -> Some(cast_result.TargetCannotBeInCombat)
    spell_plan.MustBeInCombat, False -> Some(cast_result.TargetMustBeInCombat)
    spell_plan.OutOfCombatOnly, False
    | spell_plan.MustBeInCombat, True
    | spell_plan.CombatAllowed, _
    -> None
  }
}

/// The target result of the lowest crowd-control state the spell's mask names among those the
/// target holds (`CheckSpellCCConditions` `0x1403b2c40`).
pub fn held_refusal(
  mask mask: Int,
  held held: List(CrowdControlState),
) -> Option(cast_result.CastResult) {
  crowd_control.first_masked(mask:, held:)
  |> option.from_result
  |> option.map(fn(state) {
    cast_result.from_value(crowd_control.target_result(state:))
  })
}

/// Whether a spell with these valid-target bits refuses every player: bit 0 (102,
/// `0x1403b2240`).
pub fn refuses_a_player(valid_targets valid_targets: Int) -> Bool {
  has(flags: valid_targets, bit: target_mechanic.valid_refuses_player)
}

/// 102 for a spell that refuses a player.
fn type_refusal(spell spell: Spell) -> Option(Verdict) {
  use <- bool.guard(
    when: !refuses_a_player(valid_targets: spell.targeting.valid_targets),
    return: None,
  )
  refused_as(result: cast_result.TargetCannotBePlayer)
}

/// A spell with a cast group is tested by what the client reads of the target unit's creature
/// row, which the picture of a player does not hold: not built (`0x1403b44b0`).
fn cast_group_refusal(aim aim: spell_plan.TargetAim) -> Option(Verdict) {
  case aim.cast_group_id {
    0 -> None
    _ ->
      Some(NotBuilt(
        result: cast_result.IllegalSpellCast,
        why: "is pressed at another player and has a cast group, which the client tests by a unit record the server does not read of a player",
      ))
  }
}

/// The faction test of a cast between players (`CheckCastPlayerTargetFaction` `0x1403b4560`,
/// with no duel): a Friendly target is refused 323 when it is flagged and the caster is not,
/// else passes with valid-target bit 1 or mechanics flag 3, else 99; any other target in the
/// caster's group is refused 99 unless the spell has mechanics flag 0, and one outside it must
/// be flagged (322) as the caster must (323), then a spell with flag 0 and neither flag 4 nor
/// valid-target bit 1 is refused 99.
fn second_faction_refusal(
  spell spell: Spell,
  caster caster: Caster,
  target target: PlayerState,
) -> Option(Verdict) {
  let flags = spell.targeting.mechanics_flags
  let skips =
    has(
      flags: spell.targeting.valid_targets,
      bit: target_mechanic.valid_skips_faction_test,
    )
  case target.disposition {
    Friendly ->
      case target.pvp_flagged && !caster.pvp_flagged {
        True -> refused_as(result: cast_result.CasterMustBePvpFlagged)
        False ->
          case skips || has(flags:, bit: mechanics_friendly_passes) {
            True -> None
            False -> refused_as(result: cast_result.TargetFaction)
          }
      }
    Hostile | Neutral ->
      case shares_group(caster:, target:) {
        True ->
          case target_mechanic.is_beneficial(flags:) {
            True -> None
            False -> refused_as(result: cast_result.TargetFaction)
          }
        False ->
          case target.pvp_flagged, caster.pvp_flagged {
            False, _ -> refused_as(result: cast_result.TargetMustBePvpFlagged)
            True, False ->
              refused_as(result: cast_result.CasterMustBePvpFlagged)
            True, True ->
              case
                !skips
                && target_mechanic.is_beneficial(flags:)
                && !has(flags:, bit: mechanics_hostile_passes)
              {
                True -> refused_as(result: cast_result.TargetFaction)
                False -> None
              }
          }
      }
  }
}

/// 104, 105 and 183: the range edge to edge, from the place and hit radius of each player,
/// with the server's allowance beyond a non-zero maximum, as the client's own margin is
/// added only to one (`0x1403b2240`); then 101 for a target outside the spell's facing arc.
/// 91 for a target whose place the picture does not hold is the server's choice: the
/// client's 91 is its test for a cast with no target unit at all, and a unit the picture
/// shows without a place has none to measure.
fn range_refusal(
  aim aim: spell_plan.TargetAim,
  caster caster: Caster,
  target target: PlayerState,
) -> Option(Verdict) {
  case target.place {
    None -> refused_as(result: cast_result.NoTarget)
    Some(place) ->
      case
        activate.range_of(
          limits: spell_plan.Limits(
            ..aim.limits,
            max: allowed_maximum(maximum: aim.limits.max),
          ),
          caster: activate.Body(place: caster.place, radius: caster.hit_radius),
          target: activate.Body(place:, radius: target.hit_radius),
        )
      {
        activate.Within -> facing_refusal(aim:, caster:, place:)
        activate.TooClose -> refused_as(result: cast_result.TargetRangeMin)
        activate.TooFar -> refused_as(result: cast_result.TargetRangeMax)
        activate.TooHigh -> refused_as(result: cast_result.TargetRangeVertical)
      }
  }
}

/// The maximum range a press is held to: the spell's with the server's allowance, or 0 for
/// a spell whose maximum is 0.
fn allowed_maximum(maximum maximum: Float) -> Float {
  use <- bool.guard(when: maximum == 0.0, return: maximum)
  maximum +. range_allowance_metres
}

/// 101: the target stands outside the arc the spell's target angle allows off the caster's
/// facing (`0x1403b2240` calling `0x1400a7a40`, after the range).
fn facing_refusal(
  aim aim: spell_plan.TargetAim,
  caster caster: Caster,
  place place: Place,
) -> Option(Verdict) {
  case aim.facing {
    spell_plan.FacesAnywhere -> None
    spell_plan.FacesWithin(arc_degrees:) ->
      case
        area.faces(
          from: area.point_of(place: caster.place),
          target: area.point_of(place:),
          yaw: start_place.facing(caster.place).yaw,
          arc_degrees:,
        )
      {
        True -> None
        False -> refused_as(result: cast_result.TargetOrientation)
      }
  }
}
