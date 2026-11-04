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
//// | C crashes mid-fight | the map's `Gone(C)`: C leaves the fighters, and 0x89a (P, 0) goes when none is left | `the_map_reporting_a_fighter_gone_clears_the_combat_flag_test`, `a_dagun_that_crashes_mid_fight_is_gone_and_the_bots_combat_flag_clears_test` |
//// | P's answer reaches C after C's deadline | C's go leaves P out; P's hit stands and P's 0x92f shows it | `an_answer_after_the_deadline_is_left_out_of_the_go_test` |
//// | C's strike reaches P after P's connection ended | dropped by the registry; C's deadline leaves P out | `a_player_whose_connection_ends_mid_chase_makes_the_dagun_leash_test` |
//// | P and C strike each other at one instant | each strike is a tell, each answered in its owner's own step | `a_medic_and_a_beast_striking_each_other_at_one_instant_both_get_their_answers_before_either_deadline_test` |
//// | P camps and enters again while a move of its first stay is in flight | the move sequence number counts for the connection's life, so the old move is lower and the creature drops it | `the_move_sequence_number_counts_through_a_camp_and_the_next_entry_test` |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/hit.{type Defence, type Rolls}
import genesis_prime/game/item_property
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/rating.{type Formulas}
import genesis_prime/game/strike_tell.{type Tell, Answered}
import genesis_prime/step.{type Address}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
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
  Answer(to: Address, answered: strike_tell.Answered)
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

/// A level-1 player's defence from its loadout: its deflect, critical deflect and
/// glance chances and its glance amount from UnitProperty2's defaults (0) and no
/// rating (`player.level1_defence`), each through its rating formula; the mitigation
/// of its gear's Armor (property 42, with ResistPhysical and the offsets at their
/// defaults, 0) by GameFormula 1234 (`0x140464240`) for each damage type; and its
/// shield's ShieldMitigationMax.
pub fn defence(
  loadout loadout: Loadout,
  level level: Int,
  formulas formulas: Formulas,
) -> Defence {
  let chance = fn(formula) {
    rating.to_fraction(formula:, level:, base: 0.0, rating: 0.0)
  }
  let mitigation =
    rating.mitigation_fraction(
      formulas:,
      level:,
      base: 0.0,
      rating: loadout.properties.armor,
    )
  hit.Defence(
    deflect_chance: chance(formulas.deflect_chance),
    crit_deflect_chance: chance(formulas.crit_deflect),
    glance_chance: chance(formulas.glance_chance),
    glance_amount: chance(formulas.glance_amount),
    physical_mitigation: mitigation,
    tech_mitigation: mitigation,
    magic_mitigation: mitigation,
    shield_mitigation_max: case loadout.properties.shield {
      Some(item_property.Shield(mitigation_max:, ..)) -> mitigation_max
      None -> 0.0
    },
  )
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
  case life.health {
    0 -> #(life, [
      Answer(
        to: strike.from,
        answered: Answered(
          key: strike.key,
          outcome: strike_tell.Refused(why: strike_tell.Dead),
        ),
      ),
    ])
    health ->
      case
        hit.apply(
          health:,
          shield: life.shield,
          offence: strike.offence,
          defence:,
          rolls:,
        )
      {
        hit.Deflected -> #(life, [
          Answer(
            to: strike.from,
            answered: Answered(key: strike.key, outcome: strike_tell.Deflected),
          ),
        ])
        hit.Landed(descriptions:, health: left, shield:, ..) -> {
          let shield_news = case shield == life.shield {
            True -> []
            False -> [
              ToClient(OwnShield(shield:)),
              ToViewers(client_connection.Shield(shield:)),
            ]
          }
          #(
            Life(..life, health: left, shield:),
            list.flatten([
              shield_news,
              [
                ToClient(OwnHealth(health: left)),
                ToViewers(client_connection.Health(
                  health: left,
                  dead: left == 0,
                )),
                Answer(
                  to: strike.from,
                  answered: Answered(
                    key: strike.key,
                    outcome: strike_tell.Landed(descriptions:),
                  ),
                ),
              ],
            ]),
          )
        }
      }
  }
}

/// The creature `unit_id` of life `creature_life` threatens the player: it joins
/// the fighters, the first one sets the combat flag, and its stream starts. Dropped
/// for a unit in `gone`, and for one already a fighter.
pub fn threatened(
  life life: Life,
  unit_id unit_id: Int,
  creature_life creature_life: Int,
  gone gone: Set(Int),
) -> #(Life, List(Effect)) {
  use <- bool.guard(
    when: set.contains(gone, unit_id) || dict.has_key(life.fighters, unit_id),
    return: #(life, []),
  )
  let flag = case dict.is_empty(life.fighters) {
    True -> [
      ToClient(OwnCombatState(in_combat: True)),
      ToViewers(client_connection.CombatState(in_combat: True)),
    ]
    False -> []
  }
  #(
    Life(..life, fighters: dict.insert(life.fighters, unit_id, creature_life)),
    list.append(flag, [StreamTo(unit_id:, life: creature_life)]),
  )
}

/// The creature `unit_id` released the player, or the map reported it gone: it
/// leaves the fighters, and the last one clears the combat flag.
pub fn released(
  life life: Life,
  unit_id unit_id: Int,
) -> #(Life, List(Effect)) {
  use <- bool.guard(
    when: !dict.has_key(life.fighters, unit_id),
    return: #(life, []),
  )
  let fighters = dict.delete(life.fighters, unit_id)
  #(Life(..life, fighters:), case dict.is_empty(fighters) {
    True -> [
      ToClient(OwnCombatState(in_combat: False)),
      ToViewers(client_connection.CombatState(in_combat: False)),
    ]
    False -> []
  })
}

/// The creatures the player's accepted moves are told to, by unit id with their
/// life, in unit id order.
pub fn fighters(life life: Life) -> List(#(Int, Int)) {
  dict.to_list(life.fighters)
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

/// The player's health.
pub fn health(life life: Life) -> Int {
  life.health
}

/// The player's shield.
pub fn shield(life life: Life) -> Int {
  life.shield
}
