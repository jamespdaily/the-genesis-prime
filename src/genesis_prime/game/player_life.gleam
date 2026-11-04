//// A player's health and shield in a fight, and the creatures it fights: the
//// feature of the game connection's rule (genesis_prime/game/connection) that takes
//// a creature's strike on its own player and keeps the player's combat flag. The
//// player's connection owns its unit, so every 0x938, 0x92f, 0x937 and 0x89a of the
//// player comes from one sender. The creature's side is
//// genesis_prime/world_map/creature_fight, whose module holds the whole sequence
//// from aggro to home.
////
//// ```
//// creature C                          this rule (P's connection)                       P's client and P's viewers
//// Threatened(C, life) ─────────▶ C not in gone: fighters + C
////                                the first fighter:                           ─▶ 0x89a(P, 1) to P and its viewers
////                                Stream(C): P's place now, its move seq ──────▶ TargetMoved to C
////                                each accepted 0x637 after: TargetMoved to every fighter
//// Attacks(Strike(key, C, CreatureStriker, offence))
////                             ─▶ dead: Answer(C, Refused(Dead))
////                                alive: rolls from P's seed (12 bytes)
////                                the hit rule on P's health and shield (genesis_prime/game/hit)
////                                the shield changed:                          ─▶ 0x938(P, 20, shield) to P and its viewers
////                                                                             ─▶ 0x92f(P, health) to P
////                                                                             ─▶ 0x937(P, health) to its viewers
////                                Answer(C, Landed(descriptions) | Deflected)  ─▶ TellStrikeAnswered to C
//// Released(C) ─────────────────▶ fighters - C; the last one:                  ─▶ 0x89a(P, 0) to P and its viewers
//// the map's Gone(C) ───────────▶ the same as Released(C), and C joins gone
//// ```
////
//// - **One owner rolls.** A creature keeps no random state, so the struck player's
////   connection draws the strike's rolls from its own seed, and a recording of the
////   connection replays them (genesis_prime/game/strike_tell).
//// - **A level-1 player's defence** has no deflect, critical deflect or glance: each
////   is 0 from UnitProperty2's defaults (`player.level1_defence`); its physical
////   mitigation is GameFormula 1234 from its gear's Armor (`0x140464240`,
////   `player.level1_gear_properties`), and its shield takes up to ShieldMitigationMax
////   of each blow (genesis_prime/game/hit).
//// - **Health** stays in [0, max]. At 0 the answer is `Landed` with the killed bit,
////   the creature releases the player, and a later strike is refused `Dead`.
//// - **The combat flag** has no client timer (`opcode.0x89a`): the server sends it on
////   with the first fighter and off with the last.
//// - **The stream** goes only to fighters: a creature that holds P on its threat list
////   is told P's place at once, then each accepted 0x637, and nothing after it releases P.
//// - **A `Threatened` from a unit the map reported gone** is dropped: the creature
////   ended after it sent it.
////
//// What happens at each deadline and process death on P's side:
////
//// | Point | What happens | Test |
//// |---|---|---|
//// | C crashes mid-fight | the map's `Gone(C)`: C leaves the fighters, and 0x89a (P, 0) goes when none is left | `a_creature_crash_mid_fight_clears_the_players_combat_flag_test` |
//// | P's answer reaches C after C's deadline | C's go leaves P out; P's hit stands and P's 0x92f shows it | `an_answer_after_the_deadline_is_left_out_of_the_go_test` |
//// | C's strike reaches P after P's connection ended | dropped by the registry; C's deadline leaves P out | `a_player_whose_connection_ends_mid_chase_makes_the_creature_leash_test` |
//// | P and C strike each other at one instant | each strike is a tell, each answered in its owner's own step | `mutual_strikes_are_both_answered_before_the_deadline_test` |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/hit.{type Defence, type Rolls}
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/rating.{type Formulas}
import genesis_prime/game/strike_tell.{type Answered, type Tell}
import genesis_prime/step.{type Address}
import gleam/dict.{type Dict}
import gleam/set.{type Set}

/// A player's health and shield, and the creatures that hold it on their threat
/// lists, by unit id, with each one's life.
pub opaque type Life {
  Life(health: Int, shield: Int, fighters: Dict(Int, Int))
}

/// What a creature's strike, threat or release asks the player's connection to do,
/// in order.
pub type Effect {
  /// News of the player's own unit for its own client: 0x89a, 0x938 of stat 20,
  /// and its health as 0x92f.
  ToClient(written: Written)
  /// News of the player's own unit for each of its viewers: 0x89a, 0x938 of stat
  /// 20 and 0x937.
  ToViewers(news: News)
  /// The answer to a creature's strike, told to the creature.
  Answer(to: Address, answered: Answered)
  /// Tell the creature `unit_id` of life `life` the player's place now, with its
  /// move sequence number: the start of the stream.
  StreamTo(unit_id: Int, life: Int)
}

/// What the player's own client is written about its own unit.
pub type Written {
  /// 0x89a: the player is in a fight or out of one.
  OwnCombatState(in_combat: Bool)
  /// 0x938 of stat 20: the player's shield.
  OwnShield(shield: Int)
  /// 0x92f: the player's health.
  OwnHealth(health: Int)
}

/// A player entering the world at `health` with a full `shield`, fighting no one.
pub fn new(health health: Int, shield shield: Int) -> Life {
  Life(health:, shield:, fighters: dict.new())
}

/// A level-1 player's defence from its loadout: no deflect, critical deflect or
/// glance, the mitigation of its gear's Armor by GameFormula 1234 at `level`, and
/// its shield's ShieldMitigationMax.
pub fn defence(
  loadout loadout: Loadout,
  level level: Int,
  formulas formulas: Formulas,
) -> Defence {
  todo as "defence: the build fills it in"
}

/// A creature's strike on the player, on `rolls` from the player's seed: the hit
/// rule on its health and shield, the news of both, and the answer; a refusal for a
/// player at 0.
pub fn struck(
  life life: Life,
  defence defence: Defence,
  strike strike: Tell,
  rolls rolls: Rolls,
) -> #(Life, List(Effect)) {
  todo as "struck: the build fills it in"
}

/// The creature `unit_id` of life `life` threatens the player: it joins the
/// fighters, the first one sets the combat flag, and its stream starts. Dropped for a
/// unit in `gone`.
pub fn threatened(
  life life: Life,
  unit_id unit_id: Int,
  creature_life creature_life: Int,
  gone gone: Set(Int),
) -> #(Life, List(Effect)) {
  todo as "threatened: the build fills it in"
}

/// The creature `unit_id` released the player, or the map reported it gone: it
/// leaves the fighters, and the last one clears the combat flag.
pub fn released(
  life life: Life,
  unit_id unit_id: Int,
) -> #(Life, List(Effect)) {
  todo as "released: the build fills it in"
}

/// The creatures the player's accepted moves are told to, by unit id with their
/// life.
pub fn fighters(life life: Life) -> List(#(Int, Int)) {
  todo as "fighters: the build fills it in"
}

/// The player's health.
pub fn health(life life: Life) -> Int {
  life.health
}
