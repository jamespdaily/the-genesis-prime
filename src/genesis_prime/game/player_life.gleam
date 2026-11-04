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
//// Death and coming back, when a strike leaves P at 0:
////
//// ```
//// creature C                 this rule (P's connection)                  P's client                P's viewers
//// Attacks(..) health 0  ─▶  Dead, the body where it fell; fighters emptied
////                            Answer(C, Landed killed) ─▶ C releases P
////                                                    ─▶ 0x92f(P, 0)               0x937(P, 0, dead)
////                                                    ─▶ 0x88c(P, 1)               0x88c(P, 1)
////                                                    ─▶ 0x89a(P, 0)               0x89a(P, 0)
////                            EndCasts: each own cast ─▶ 0x7fe                     0x7fe (those told its start)
////                                                    ─▶ 0x247 type 22 P           0x247 type 22 P
////                                                    ─▶ 0x262 ghost (type 23)
////                                                    ─▶ 0x1b3 {ghost, 0, 0, 1, 3, 0, 0, 0}
////                                                    ─▶ 0x636 ghost
//// 0x637 while dead      ─▶  decoded and dropped (genesis_prime/game/connection): the body, the map,
////                            viewers and fighters untouched
//// 0x15a {P, 1, 0}       ─▶  Alive at the body's place, full health and shield
////                                                    ─▶ 0x92f(P, max)             0x937(P, max)
////                                                    ─▶ 0x938(P, 20, max)         0x938(P, 20, max)
////                                                    ─▶ 0x88c(P, 0)               0x88c(P, 0)
////                                                    ─▶ 0x1b3 {ghost, .., dead 0, ..}
////                                                    ─▶ 0x355 ghost
////                                                    ─▶ 0x636 P
////                                                    ─▶ 0x247 type 23 P           0x247 type 23 P
//// 0x15a {P, 2, 0}       ─▶  the same, then GoToHolocrypt: the connection leaves the map and
////                            joins at the Holocrypt place (genesis_prime/game/connection)
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
////   ended after it sent it. So is one that reaches a dead player.
//// - **Death** is the client's: 0x88c sets the unit dead and draws it so, and
////   leaves its combat flag, so 0x89a (P, 0) follows (`opcode.0x88c`,
////   `death.combat_flag`); the combat log line is 0x247 type 22, which the client
////   shows for a player (`opcode.0x247.death`).
//// - **The ghost** is a unit of type 23 for P's own client only (the server's
////   choice: viewers need only the body), with the id `map.ghost_unit_id` gives,
////   at the body's place (`0x140096970`). 0x1b3 hands the client's control to it
////   (`opcode.0x1b3`) and 0x636 its movement (`opcode.0x636`).
//// - **The window's values** are the server's choices (`death.server_choices`):
////   no cost, penalty, cooldown or forced release, since any cost disables Wake
////   Here with no currency sent (`death.window`); the choices Wake Here and
////   Holocrypt, flags 1 and 2 (`lua.GameLib.RezType`).
//// - **0x15a** names P's own unit, a choice offered and 0 (`opcode.0x15a`); any
////   other, or one while alive, is refused with no change. P comes back at full
////   health and full shield (the server's choice, `death.server_choices`) where
////   the body lies.
//// - **The ghost's moves** come as 0x637 for the player while the ghost is the
////   controlled unit, and the client expects no answer (`ghost.movement`): the
////   connection decodes and drops each, so no check of the body's moves applies.
//// - **The stay.** A threat or a release names P's unit, as the creature holds it,
////   and the connection drops one of another unit: one sent before a Holocrypt or
////   a camp that reaches the next stay (genesis_prime/game/connection).
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
//// | C's strike reaches P after P died | refused `Dead`; C's go leaves P out | `a_strike_on_a_dead_player_is_refused_dead_test` |
//// | 0x15a comes twice | the second finds P alive (or leaving for the Holocrypt) and is refused unchanged | `a_second_choice_is_refused_unchanged_test` |
//// | the Holocrypt's leave has no answer by its deadline | the connection ends, as the camp's leave does | `a_holocrypt_leave_with_no_answer_ends_the_connection_test` |
//// | the Holocrypt's join is refused or has no answer | refused: 0x0594 and character select; no answer: the connection ends, as entry's join does | `a_refused_holocrypt_join_returns_to_character_select_test`, `a_holocrypt_join_with_no_answer_ends_the_connection_test` |
//// | P's connection ends while dead | the map's `Leave` as for any end; the ghost was P's client's alone; the next entry is alive and full | `a_player_dead_at_camp_enters_again_alive_and_full_test` |
//// | the map crashes while P is dead | the connection ends, as for any player in the world | `the_end_of_the_players_map_saves_the_place_then_writes_0x036a_reason_8_and_ends_the_connection_test` |
//// | C's killing strike reaches P mid-cast | each live cast ends with 0x7fe to P and the viewers told its start, its timers cancelled; a round that closes later has no go | `a_creatures_killing_strike_on_a_player_mid_cast_ends_the_cast_with_0x7fe_to_it_and_every_viewer_told_its_start_test`, `a_dead_casters_casts_end_with_their_timers_cancelled_and_0x7fe_to_the_caster_and_its_audience_test` |
//// | a threat, a release or a peer's news sent for P's earlier stay arrives after the Holocrypt's join or a camp and a new entry | dropped: it names P's earlier unit | `an_appeared_and_a_threatened_of_the_stay_before_the_holocrypt_delivered_after_its_join_are_dropped_test`, `an_appeared_and_a_threatened_of_the_stay_before_a_camp_delivered_after_the_next_entry_are_dropped_test` |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/hit.{type Defence, type Rolls}
import genesis_prime/game/item_property
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/rating.{type Formulas}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{type Tell, Answered}
import genesis_prime/message/choose_resurrection
import genesis_prime/step.{type Address}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}

/// A player's health and shield, each with its full value, the creatures that
/// hold it on their threat lists, by unit id, with each one's life, and whether
/// it is alive.
pub opaque type Life {
  Life(
    health: Int,
    max_health: Int,
    shield: Int,
    max_shield: Int,
    fighters: Dict(Int, Int),
    state: State,
  )
}

/// Whether the player is alive. A dead player's body lies where it fell, which
/// the movement keeps (genesis_prime/game/movement); its client moves its ghost,
/// whose moves the server drops (`ghost.movement`).
pub type State {
  Alive
  Dead
}

/// The messages of a player's death, which the client sends inside 0x038C
/// (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x015A, the player chose how to come back.
  ResurrectionChosen
}

/// How the player comes back, from 0x15a's choice (`lua.GameLib.RezType`).
pub type Choice {
  /// 1: where the body lies.
  WakeHere
  /// 2: at the Holocrypt place.
  Holocrypt
  /// Any other value: 4 a caster's resurrection, 32 Exit Instance, or one no
  /// button sends; none is offered.
  OtherChoice(value: Int)
}

/// Why a 0x15a is refused. A body the client's reader would refuse ends the
/// connection; any other refusal changes nothing: `Unit:Resurrect` sends any
/// unit, choice and value a script gives it (`0x140659070`), so each is the
/// client's own code, and the Death addon sends none of them.
pub type Refusal {
  NotDecoded(undecoded: client_connection.Undecoded)
  /// The unit is not the player's own: the ghost's, or any other.
  NotThePlayer(unit_id: Int)
  /// The choice is not one the last 0x1b3 offered.
  NotOffered(choice: Choice)
  /// The player is alive.
  NotDead
  /// The third value is not 0, which the Death addon always sends.
  NonzeroValue(value: Int)
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
  /// The player died: each of its own live casts ends with 0x7fe to its client
  /// and to every viewer told the cast's start (genesis_prime/game/cast `died`).
  EndCasts
  /// The player chose the Holocrypt: the connection takes it out of its map and
  /// joins it at the Holocrypt place, whose entry burst follows.
  GoToHolocrypt
}

/// What the player's own client is written about its own unit.
pub type Written {
  /// 0x89a: the player is in a fight or out of one.
  OwnCombatState(in_combat: Bool)
  /// 0x938 of stat 20: the player's shield.
  OwnShield(shield: Int)
  /// 0x92f: the player's health.
  OwnHealth(health: Int)
  /// 0x88c {P, dead, 0, 0}: the player died or came back. The 5-bit value is
  /// read and not used, and the 32-bit one is used only for a unit under client
  /// control that comes back, through a method not read: 0 (`opcode.0x88c`).
  OwnDeathState(dead: Bool)
  /// 0x247 type 22 of the player (`opcode.0x247.death`).
  OwnDeathLogged
  /// 0x247 type 23 of the player (`opcode.0x247.death`).
  OwnCameBackLogged
  /// 0x262 of type 23: the player's ghost, at `place` (`0x140096970`).
  GhostCreated(place: Place)
  /// 0x1b3 with the ghost's id and the server's choices, dead or not
  /// (`opcode.0x1b3`).
  OwnResurrectionWindow(dead: Bool)
  /// 0x355 of the ghost (`opcode.0x355`).
  GhostRemoved
  /// 0x636 for the unit the client moves (`opcode.0x636`).
  ControlGiven(to: Controlled)
}

/// The unit whose movement the player's client is given.
pub type Controlled {
  ControlBody
  ControlGhost
}

/// The choices 0x1b3 offers: Wake Here (1) and Holocrypt (2), the two built
/// (`lua.GameLib.RezType`; the server's choice).
pub const offered_choices = 3

/// The Wake Here cost in credits, the death penalty, the Wake Here cooldown and
/// the forced-release countdown 0x1b3 carries: 0 each. The server's choice
/// (`death.server_choices`): no currency is sent, so any cost leaves Wake Here
/// disabled (`death.window`).
pub const window_zero = 0

/// A player entering the world at full `health` with a full `shield`, alive and
/// fighting no one.
pub fn new(health health: Int, shield shield: Int) -> Life {
  Life(
    health:,
    max_health: health,
    shield:,
    max_shield: shield,
    fighters: dict.new(),
    state: Alive,
  )
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

/// A creature's strike on the player standing at `place`, on `rolls` from the
/// player's seed: the hit rule on its health and shield, the news of both, and the
/// answer; a refusal for a dead player. A strike that leaves the player at 0 kills
/// it: the death's messages follow the health's, and its ghost stands at `place`.
pub fn struck(
  life life: Life,
  defence defence: Defence,
  strike strike: Tell,
  rolls rolls: Rolls,
  place place: Place,
) -> #(Life, List(Effect)) {
  case life.state {
    Dead -> #(life, [
      Answer(
        to: strike.from,
        answered: Answered(
          key: strike.key,
          outcome: strike_tell.Refused(why: strike_tell.Dead),
        ),
      ),
    ])
    Alive ->
      case
        hit.apply(
          health: life.health,
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
          let #(life, death) = case left {
            0 -> died(life: Life(..life, health: left, shield:), place:)
            _ -> #(Life(..life, health: left, shield:), [])
          }
          #(
            life,
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
              death,
            ]),
          )
        }
      }
  }
}

/// The player at 0 dies where its body lies, `place`: it is dead with its ghost
/// there, it fights no one, and the death's messages go out in the client's order:
/// 0x88c and 0x89a to it and its viewers, its casts ended, 0x247 type 22, then
/// for its own client the ghost's 0x262, 0x1b3 and 0x636.
fn died(life life: Life, place place: Place) -> #(Life, List(Effect)) {
  #(Life(..life, fighters: dict.new(), state: Dead), [
    ToClient(OwnDeathState(dead: True)),
    ToViewers(client_connection.Died),
    ToClient(OwnCombatState(in_combat: False)),
    ToViewers(client_connection.CombatState(in_combat: False)),
    EndCasts,
    ToClient(OwnDeathLogged),
    ToViewers(client_connection.DeathLogged),
    ToClient(GhostCreated(place:)),
    ToClient(OwnResurrectionWindow(dead: True)),
    ToClient(ControlGiven(to: ControlGhost)),
  ])
}

/// What the client's 0x15a does, decoded at the edge: a choice offered, for the
/// player's own unit `unit_id`, while dead and with 0 brings the player back at
/// full health where its body lies, and for the Holocrypt asks the connection to
/// move it. Anything else is refused and changes nothing.
pub fn take(
  life life: Life,
  message message: Message,
  body body: BitArray,
  unit_id unit_id: Int,
) -> Result(#(Life, List(Effect)), Refusal) {
  let ResurrectionChosen = message
  use chosen <- result.try(
    choose_resurrection.decode(body)
    |> client_connection.decoded(message_id: choose_resurrection.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(when: life.state == Alive, return: Error(NotDead))
  use <- bool.guard(
    when: chosen.unit_id != unit_id,
    return: Error(NotThePlayer(unit_id: chosen.unit_id)),
  )
  use <- bool.guard(
    when: chosen.field_3 != 0,
    return: Error(NonzeroValue(value: chosen.field_3)),
  )
  case choice(value: chosen.choice) {
    WakeHere -> Ok(came_back(life:))
    Holocrypt -> {
      let #(life, effects) = came_back(life:)
      Ok(#(life, list.append(effects, [GoToHolocrypt])))
    }
    OtherChoice(..) as other -> Error(NotOffered(choice: other))
  }
}

/// The choice 0x15a's 7 bits name.
fn choice(value value: Int) -> Choice {
  case value {
    1 -> WakeHere
    2 -> Holocrypt
    other -> OtherChoice(value: other)
  }
}

/// The player comes back alive at full health and full shield (the server's
/// choice, `death.server_choices`) where its body lies: the health and the shield
/// to it and its viewers, 0x88c (P, 0) to both, 0x1b3 with dead 0, the ghost's
/// 0x355, 0x636 for the body, and 0x247 type 23 to both.
fn came_back(life life: Life) -> #(Life, List(Effect)) {
  let health = life.max_health
  let shield = life.max_shield
  #(Life(..life, health:, shield:, state: Alive), [
    ToClient(OwnHealth(health:)),
    ToViewers(client_connection.Health(health:, dead: False)),
    ToClient(OwnShield(shield:)),
    ToViewers(client_connection.Shield(shield:)),
    ToClient(OwnDeathState(dead: False)),
    ToViewers(client_connection.CameBack),
    ToClient(OwnResurrectionWindow(dead: False)),
    ToClient(GhostRemoved),
    ToClient(ControlGiven(to: ControlBody)),
    ToClient(OwnCameBackLogged),
    ToViewers(client_connection.CameBackLogged),
  ])
}

/// Whether the player is alive.
pub fn state(life life: Life) -> State {
  life.state
}

/// A sentence that says why a 0x15a was refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    NotThePlayer(unit_id:) ->
      "a 0x015A names unit "
      <> int.to_string(unit_id)
      <> ", which is not the player's own"
    NotOffered(choice:) ->
      "a 0x015A chooses "
      <> int.to_string(choice_value(choice:))
      <> ", which the window did not offer"
    NotDead -> "a 0x015A came while the player is alive"
    NonzeroValue(value:) ->
      "a 0x015A carries the value "
      <> int.to_string(value)
      <> " where the Death addon sends 0"
  }
}

/// The value 0x15a carries for a choice.
fn choice_value(choice choice: Choice) -> Int {
  case choice {
    WakeHere -> 1
    Holocrypt -> 2
    OtherChoice(value:) -> value
  }
}

/// The creature `unit_id` of life `creature_life` threatens the player: it joins
/// the fighters, the first one sets the combat flag, and its stream starts. Dropped
/// for a unit in `gone`, for one already a fighter, and while the player is dead.
pub fn threatened(
  life life: Life,
  unit_id unit_id: Int,
  creature_life creature_life: Int,
  gone gone: Set(Int),
) -> #(Life, List(Effect)) {
  use <- bool.guard(
    when: set.contains(gone, unit_id)
      || dict.has_key(life.fighters, unit_id)
      || life.state == Dead,
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
