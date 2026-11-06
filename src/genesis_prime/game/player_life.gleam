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
////                                                                              CombatLeft (the cast rule's `combat_left`)
//// the map's Gone(C) ───────────▶ the same as Released(C), and C joins gone
//// ```
////
//// Health and shield regenerate on two timers this rule asks for as effects, as the
//// class resource's (genesis_prime/game/class_resource) do. The client predicts
//// neither (`regen.client`), so each change is a message:
////
//// ```
//// P below its max health, alive, out of combat   ─▶ StartTimer(health_timer, health_tick_ms)
//// health_timer ─▶ + max(1, floor(max x fraction x multiplier)), capped
////                ─▶ 0x92f(P, health) to P, 0x937(P, health) to its viewers
////                below the max still ─▶ StartTimer(health_timer, health_tick_ms)
//// the first fighter ─▶ CancelTimer(health_timer);  the last release ─▶ StartTimer(health_timer)
//// a blow that lowers shield or health, P alive    ─▶ CancelTimer(shield_timer) if running,
////                                                    StartTimer(shield_timer, ShieldRebootTime)
//// shield_timer ─▶ + max(1, floor(max_shield x ShieldRegenPct)), capped
////                ─▶ 0x938(P, 20, shield) to P and to its viewers
////                below the max still ─▶ StartTimer(shield_timer, ShieldTickTime)
//// death ─▶ both cancelled;  coming back is full: nothing started
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
////   mitigation is GameFormula 1234 from its Armor, its gear's unless a modifier
////   changes it (`0x140464240`, `player.level1_gear_properties`), and its shield takes
////   up to ShieldMitigationMax of each blow (genesis_prime/game/hit). Armor,
////   ShieldMitigationMax, the maxima and the regeneration numbers are the player's
////   properties (genesis_prime/game/unit_properties).
//// - **Health** stays in [0, max]. At 0 the answer is `Landed` with the killed bit,
////   the creature releases the player, and a later strike is refused `Dead`.
//// - **Health regenerates** while P is alive, out of combat and below its maximum,
////   each `health_tick_ms` by `health_fraction` of the maximum times
////   HealthRegenMultiplier (UnitProperty2 8), at least 1: the client's text says only
////   "slowly out of combat" (149418), so the fraction and the tick are the server's
////   choices, two game_number rows (migration 0015), and the multiplier is the
////   player's property, the UnitProperty2 default unless a modifier changes it
////   (`UnitProperty2.176`).
//// - **The shield regenerates** ShieldRebootTime after the last blow that lowered
////   health or shield (text 531855), then each ShieldTickTime by ShieldRegenPct of
////   its maximum (text 531859), in or out of combat. ShieldRegenPct and
////   ShieldRebootTime are the player's shield item's (properties 176 and 178 of its
////   0x262); ShieldTickTime is the player's property, UnitProperty2 177's default unless
////   a modifier changes it (`UnitProperty2.176`).
//// - **The combat flag** has no client timer (`opcode.0x89a`): the server sends it on
////   with the first fighter and off with the last. `CombatLeft` follows the flag's news
////   when it goes off, with the last release and with a death that had a fighter, and
////   never when the flag was off already; it is the event of a Proc of kind 44
////   (`Spell4Effects.effectType.14.dataBits00.0_44`).
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
//// - **Entering dead**: a save while dead keeps health 0 and the body's place, and
////   an entry at a saved health of 0 (`entering`) is dead, with the ghost at the
////   saved place and the window open, with a shield of 0, and no 0x88c, no 0x89a and
////   no regeneration:
////   the client creates a unit of health 0 dead (`0x140457bc5`, `death.enter_dead`).
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
////   connection decodes each with the checks of the body's moves, and drops it.
////   After the Holocrypt's join, a ghost's move sent before the join's 0xAD
////   reached the client is dropped the same way, until the stay's first 0xF2
////   (`world_entry.GhostLoading`).
//// - **The stay.** A threat, a release and a strike travel for P's stay, and the
////   connection drops one of an earlier stay: one sent before a Holocrypt or a
////   camp that reaches the next stay (genesis_prime/world_map/stay).
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
//// | C's strike reaches P after P died | refused `Dead`; C's go leaves P out | `a_strike_on_a_dead_player_is_refused_dead_and_writes_nothing_test` |
//// | 0x15a comes twice | the second finds P alive (also when it was sent while the Holocrypt's leave and join ran) and is refused unchanged | `a_second_choice_is_refused_unchanged_test`, `what_the_dead_client_sends_during_the_holocrypts_leave_and_join_is_taken_as_from_the_dead_test` |
//// | the dead client's frames wait while the Holocrypt's leave and join are asked | taken after the join: a ghost's 0x637 is dropped, until the stay's first 0xF2; nothing the dead client may send ends the connection | `what_the_dead_client_sends_during_the_holocrypts_leave_and_join_is_taken_as_from_the_dead_test` |
//// | the Holocrypt's leave has no answer by its deadline | the connection ends, as the camp's leave does | `a_holocrypt_leave_with_no_answer_ends_the_connection_test` |
//// | the Holocrypt's join is refused or has no answer | refused: 0x0594 and character select; no answer: the connection ends, as entry's join does | `a_refused_holocrypt_join_returns_to_character_select_test`, `a_holocrypt_join_with_no_answer_ends_the_connection_test` |
//// | P's connection ends while dead | the map's `Leave` as for any end; the ghost was P's client's alone; the save keeps health 0 and the body's place, and the next entry is dead at the body (`entering`) | `a_save_while_dead_keeps_0_and_the_place_of_the_body_test`, `a_player_dead_at_camp_enters_again_dead_at_the_body_and_a_character_never_saved_enters_alive_and_full_test` |
//// | the map crashes while P is dead | the connection ends, as for any player in the world, after the save of the place the body lies at | `the_map_ending_while_the_player_is_dead_saves_where_the_body_lies_and_ends_the_connection_test` |
//// | C's killing strike reaches P mid-cast | each live cast ends with 0x7fe to P and the viewers told its start, its timers cancelled; a round that closes later has no go | `a_creatures_killing_strike_on_a_player_mid_cast_ends_the_cast_with_0x7fe_to_it_and_every_viewer_told_its_start_test`, `a_dead_casters_casts_end_with_their_timers_cancelled_and_0x7fe_to_the_caster_and_its_audience_test` |
//// | the map's notice, a peer's news or a creature's threat, release or strike sent for P's earlier stay arrives after the Holocrypt's join, a camp and a new entry, or a join to a restarted run that gives the same unit id | dropped: it names the earlier stay | `messages_of_the_stay_before_the_holocrypt_are_dropped_after_its_join_test`, `messages_of_the_stay_before_a_camp_are_dropped_after_the_next_entry_test`, `messages_of_the_stay_before_are_dropped_in_a_restarted_run_that_gives_the_same_unit_id_test` |

import genesis_prime/client_connection.{type News}
import genesis_prime/game/hit.{type Defence, type Rolls}
import genesis_prime/game/item_property
import genesis_prime/game/rating.{type Formulas}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{type Tell, Answered}
import genesis_prime/game/unit_properties.{type Properties}
import genesis_prime/message/choose_resurrection
import genesis_prime/step.{type Address, type TimerId, TimerId}
import genesis_prime/world_map/game_number.{type GameNumbers}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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
    regeneration: Regeneration,
    health_clock: Clock,
    shield_clock: Clock,
  )
}

/// The numbers health and shield regenerate by (`regeneration` builds them).
pub type Regeneration {
  Regeneration(
    /// The share of the maximum health a health tick adds, before the multiplier.
    health_fraction: Float,
    /// HealthRegenMultiplier (UnitProperty2 8).
    health_multiplier: Float,
    /// The time between health ticks, in milliseconds.
    health_tick_ms: Int,
    /// The shield's, or none for a player with no shield item, whose shield has no
    /// clock.
    shield: Option(ShieldRegeneration),
  )
}

/// The numbers a shield regenerates by.
pub type ShieldRegeneration {
  ShieldRegeneration(
    /// ShieldRegenPct: the share of the maximum shield a shield tick adds.
    percent: Float,
    /// ShieldRebootTime: the wait after a blow before the shield regenerates, in
    /// milliseconds.
    reboot_ms: Int,
    /// ShieldTickTime (UnitProperty2 177): the time between shield ticks, in
    /// milliseconds.
    tick_ms: Int,
  )
}

/// Whether a regeneration timer is running.
type Clock {
  Idle
  Running
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
  /// A landed blow lowered the player's health or shield, after the news of both and
  /// before the answer and any death: the connection tells the cast rule, which ends the
  /// stealth damage breaks (genesis_prime/game/cast `damage_taken`). A deflected blow, and
  /// a landed one that lowered neither, send none.
  DamageTaken
  /// The player's combat flag went off, right after its news (0x89a off): the last
  /// fighter released it, or it died with a fighter on its list. The connection tells the
  /// cast rule (genesis_prime/game/cast `combat_left`).
  CombatLeft
  /// The player died: each of its own live casts ends with 0x7fe to its client
  /// and to every viewer told the cast's start (genesis_prime/game/cast `died`).
  EndCasts
  /// The player chose the Holocrypt: the connection takes it out of its map and
  /// joins it at the Holocrypt place, whose entry burst follows.
  GoToHolocrypt
  /// Start a regeneration timer: its firing comes back to `timer_fired`.
  StartTimer(timer: TimerId, after_ms: Int)
  /// Cancel a regeneration timer.
  CancelTimer(timer: TimerId)
}

/// The timer of the health tick; the class resource's timers are 4 to 7
/// (genesis_prime/game/class_resource) and the connection's other timers are
/// below them.
const health_timer = TimerId(8)

/// The timer of the shield's reboot, then each of its ticks.
const shield_timer = TimerId(9)

/// Whether the timer is one of this rule's, for the connection to hand it to
/// `timer_fired`.
pub fn owns(timer timer: TimerId) -> Bool {
  timer == health_timer || timer == shield_timer
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

/// The numbers a player regenerates by: the server's two choices from the
/// game_number rows, the player's HealthRegenMultiplier and ShieldTickTime
/// properties, and ShieldRegenPct and ShieldRebootTime of the player's shield item;
/// with no shield item the shield has no clock.
pub fn regeneration(
  numbers numbers: GameNumbers,
  properties properties: Properties,
  shield shield: Option(item_property.Shield),
) -> Regeneration {
  let shield =
    option.map(shield, fn(item) {
      ShieldRegeneration(
        percent: item.regen_percent,
        reboot_ms: item.reboot_time_ms,
        tick_ms: shield_tick_ms(properties:),
      )
    })
  Regeneration(
    health_fraction: numbers.health_regen_fraction,
    health_multiplier: health_multiplier(properties:),
    health_tick_ms: numbers.health_regen_tick_ms,
    shield:,
  )
}

/// The number a health tick's share is multiplied by: the player's
/// HealthRegenMultiplier.
fn health_multiplier(properties properties: Properties) -> Float {
  unit_properties.value(
    properties:,
    property: unit_properties.health_regen_multiplier,
  )
}

/// The milliseconds between shield ticks: the player's ShieldTickTime, rounded.
fn shield_tick_ms(properties properties: Properties) -> Int {
  float.round(unit_properties.value(
    properties:,
    property: unit_properties.shield_tick_time,
  ))
}

/// The life after the player's properties changed: the maxima are the BaseHealth and
/// ShieldCapacityMax values, the health and the shield are kept and capped at the new
/// maxima (the server's choice: the client holds no rule for a maximum that changes), and
/// the regeneration takes the new HealthRegenMultiplier and ShieldTickTime. A health or
/// shield the cap lowers is written to the player's client and its viewers, and the
/// health clock starts or stops as the new maximum asks. The shield's clock is left as it
/// is: a raised maximum does not start it, the next blow does.
pub fn properties_changed(
  life life: Life,
  properties properties: Properties,
) -> #(Life, List(Effect)) {
  let max_health =
    float.round(unit_properties.value(
      properties:,
      property: unit_properties.base_health,
    ))
  let max_shield =
    float.round(unit_properties.value(
      properties:,
      property: unit_properties.shield_capacity_max,
    ))
  let regeneration =
    Regeneration(
      ..life.regeneration,
      health_multiplier: health_multiplier(properties:),
      shield: option.map(life.regeneration.shield, fn(shield) {
        ShieldRegeneration(..shield, tick_ms: shield_tick_ms(properties:))
      }),
    )
  let health = int.min(life.health, max_health)
  let shield = int.min(life.shield, max_shield)
  let changed =
    Life(..life, max_health:, max_shield:, health:, shield:, regeneration:)
  let #(changed, timers) = health_clock_settled(life: changed)
  #(
    changed,
    list.flatten([
      case health == life.health {
        True -> []
        False -> health_told(health:, dead: False)
      },
      case shield == life.shield {
        True -> []
        False -> shield_told(shield:)
      },
      timers,
    ]),
  )
}

/// A player at full `health` with a full `shield`, alive and fighting no one,
/// regenerating by `regeneration`.
pub fn new(
  health health: Int,
  shield shield: Int,
  regeneration regeneration: Regeneration,
) -> Life {
  Life(
    health:,
    max_health: health,
    shield:,
    max_shield: shield,
    fighters: dict.new(),
    state: Alive,
    regeneration:,
    health_clock: Idle,
    shield_clock: Idle,
  )
}

/// A player entering the world with the health its last save kept: `saved`
/// capped at `max_health`, or `max_health` when nothing was saved, alive and
/// fighting no one, with a full `shield`. The cap and "nothing saved is full" are
/// the server's choices: the client holds no saved health (the stat 0 of the
/// player's 0x262 is the health it shows, `opcode.0x262`). Below its maximum, out
/// of combat, the player starts regenerating: the effect starts its health timer.
///
/// A saved health of 0 is a player that left dead: it enters dead with its body
/// at `place`, where the character is saved. The client creates a unit with
/// health 0 dead and refuses nothing for it (`0x140457bc5`), so the entry sends
/// no 0x88c and no 0x89a, which would run the death branch again, and no timer
/// starts; its effects are the ghost's 0x262 at `place`, 0x1b3 with dead 1 and
/// control of the ghost, which the entry burst places before its 0x636
/// (`death.enter_dead`, `death.player_branch`). Its shield is 0: a death in the
/// world leaves what the killing blow left, which no save keeps, so a player that
/// enters dead holds none (the server's choice, as the save holds no shield),
/// and coming back gives it the maximum.
pub fn entering(
  saved saved: Option(Int),
  max_health max_health: Int,
  shield shield: Int,
  regeneration regeneration: Regeneration,
  place place: Place,
) -> #(Life, List(Effect)) {
  let health = int.min(option.unwrap(saved, or: max_health), max_health)
  let life = Life(..new(health: max_health, shield:, regeneration:), health:)
  case health {
    0 -> #(Life(..life, shield: 0, state: Dead), [
      ToClient(GhostCreated(place:)),
      ToClient(OwnResurrectionWindow(dead: True)),
      ToClient(ControlGiven(to: ControlGhost)),
    ])
    _ -> health_clock_settled(life:)
  }
}

/// The health a save keeps: the player's health now, 0 while it is dead, so a
/// player who camps or drops dead comes back dead (`death.enter_dead`). The table
/// holds 0 and above (`character_health_is_not_negative`).
pub fn saved_health(life life: Life) -> Int {
  case life.state {
    Alive -> life.health
    Dead -> 0
  }
}

/// A level-1 player's defence from its properties: its deflect, critical deflect and
/// glance chances and its glance amount from UnitProperty2's defaults (0) and no
/// rating (`player.level1_defence`), each through its rating formula; the mitigation
/// of its Armor (property 42, with ResistPhysical and the offsets at their
/// defaults, 0) by GameFormula 1234 (`0x140464240`) for each damage type; and its
/// ShieldMitigationMax (property 175), 0 for a player with no shield.
pub fn defence(
  properties properties: Properties,
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
      rating: unit_properties.value(
        properties:,
        property: unit_properties.armor,
      ),
    )
  hit.Defence(
    deflect_chance: chance(formulas.deflect_chance),
    crit_deflect_chance: chance(formulas.crit_deflect),
    glance_chance: chance(formulas.glance_chance),
    glance_amount: chance(formulas.glance_amount),
    physical_mitigation: mitigation,
    tech_mitigation: mitigation,
    magic_mitigation: mitigation,
    shield_mitigation_max: unit_properties.value(
      properties:,
      property: unit_properties.shield_mitigation_max,
    ),
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
            False -> shield_told(shield:)
          }
          let lowered = shield != life.shield || left != life.health
          let #(life, after) = case left {
            0 -> died(life: Life(..life, health: left, shield:), place:)
            _ -> blow_taken(life: Life(..life, health: left, shield:), lowered:)
          }
          #(
            life,
            list.flatten([
              shield_news,
              health_told(health: left, dead: left == 0),
              case lowered {
                True -> [DamageTaken]
                False -> []
              },
              [
                Answer(
                  to: strike.from,
                  answered: Answered(
                    key: strike.key,
                    outcome: strike_tell.Landed(descriptions:, controls: []),
                  ),
                ),
              ],
              after,
            ]),
          )
        }
      }
  }
}

/// A blow left the living player with the health and shield it has now: when it
/// `lowered` either, the shield's reboot starts again, and the health tick runs or
/// not as the player's state asks.
fn blow_taken(life life: Life, lowered lowered: Bool) -> #(Life, List(Effect)) {
  let #(life, shield_timers) = case lowered {
    True -> shield_rebooted(life:)
    False -> #(life, [])
  }
  let #(life, health_timers) = health_clock_settled(life:)
  #(life, list.append(shield_timers, health_timers))
}

/// The player at 0 dies where its body lies, `place`: it is dead with its ghost
/// there, it fights no one, and the death's messages go out in the client's order:
/// 0x88c and 0x89a to it and its viewers, the combat left when it had a fighter, its casts
/// ended, 0x247 type 22, then for its own client the ghost's 0x262, 0x1b3 and 0x636.
fn died(life life: Life, place place: Place) -> #(Life, List(Effect)) {
  let #(life, cancels) = stopped(life:)
  let combat_left = case in_combat(life:) {
    True -> [CombatLeft]
    False -> []
  }
  #(
    Life(..life, fighters: dict.new(), state: Dead),
    list.flatten([
      [
        ToClient(OwnDeathState(dead: True)),
        ToViewers(client_connection.Died),
        ToClient(OwnCombatState(in_combat: False)),
        ToViewers(client_connection.CombatState(in_combat: False)),
      ],
      combat_left,
      [
        EndCasts,
        ToClient(OwnDeathLogged),
        ToViewers(client_connection.DeathLogged),
        ToClient(GhostCreated(place:)),
        ToClient(OwnResurrectionWindow(dead: True)),
        ToClient(ControlGiven(to: ControlGhost)),
      ],
      cancels,
    ]),
  )
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
  #(
    Life(..life, health:, shield:, state: Alive),
    list.flatten([
      health_told(health:, dead: False),
      shield_told(shield:),
      came_back_news(),
    ]),
  )
}

/// What the player's coming back tells after its health and shield: the death state,
/// the resurrection window, the ghost's removal, the body's control and the combat log.
fn came_back_news() -> List(Effect) {
  [
    ToClient(OwnDeathState(dead: False)),
    ToViewers(client_connection.CameBack),
    ToClient(OwnResurrectionWindow(dead: False)),
    ToClient(GhostRemoved),
    ToClient(ControlGiven(to: ControlBody)),
    ToClient(OwnCameBackLogged),
    ToViewers(client_connection.CameBackLogged),
  ]
}

/// The player's health written to its own client (0x92f) and told to its viewers (0x937).
fn health_told(health health: Int, dead dead: Bool) -> List(Effect) {
  [
    ToClient(OwnHealth(health:)),
    ToViewers(client_connection.Health(health:, dead:)),
  ]
}

/// The player's shield written to its own client and told to its viewers (0x938 of
/// stat 20).
fn shield_told(shield shield: Int) -> List(Effect) {
  [ToClient(OwnShield(shield:)), ToViewers(client_connection.Shield(shield:))]
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
  let #(life, timers) =
    health_clock_settled(
      life: Life(
        ..life,
        fighters: dict.insert(life.fighters, unit_id, creature_life),
      ),
    )
  #(
    life,
    list.flatten([flag, [StreamTo(unit_id:, life: creature_life)], timers]),
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
  let flag = case dict.is_empty(fighters) {
    True -> [
      ToClient(OwnCombatState(in_combat: False)),
      ToViewers(client_connection.CombatState(in_combat: False)),
      CombatLeft,
    ]
    False -> []
  }
  let #(life, timers) = health_clock_settled(life: Life(..life, fighters:))
  #(life, list.append(flag, timers))
}

/// A regeneration timer of the rule fired. A health tick adds its share, capped at
/// the maximum, and a shield tick likewise; each asks for its next tick while the
/// player is below its maximum. A timer that fires after its cancel, after the
/// player died, in combat (health) or at its maximum changes nothing.
pub fn timer_fired(
  life life: Life,
  timer timer: TimerId,
) -> #(Life, List(Effect)) {
  case timer == health_timer, timer == shield_timer {
    True, _ -> health_ticked(life:)
    False, True -> shield_ticked(life:)
    False, False -> #(life, [])
  }
}

/// The timers to cancel when the player leaves the world: those running.
pub fn left(life life: Life) -> List(TimerId) {
  list.flatten([
    case life.health_clock {
      Running -> [health_timer]
      Idle -> []
    },
    case life.shield_clock {
      Running -> [shield_timer]
      Idle -> []
    },
  ])
}

/// Whether health should be regenerating: the player is alive, out of combat and
/// below its maximum.
fn regenerates_health(life life: Life) -> Bool {
  life.state == Alive
  && dict.is_empty(life.fighters)
  && life.health < life.max_health
}

/// The health clock made to match `regenerates_health`: started when it should
/// run and does not, cancelled when it runs and should not.
fn health_clock_settled(life life: Life) -> #(Life, List(Effect)) {
  case regenerates_health(life:), life.health_clock {
    True, Idle -> #(Life(..life, health_clock: Running), [
      StartTimer(
        timer: health_timer,
        after_ms: life.regeneration.health_tick_ms,
      ),
    ])
    False, Running -> #(Life(..life, health_clock: Idle), [
      CancelTimer(timer: health_timer),
    ])
    True, Running | False, Idle -> #(life, [])
  }
}

/// A health tick: the share added to the health, 0x92f to the player and 0x937 to
/// its viewers, and the next tick while the player is below its maximum. The share
/// is floor(max x fraction x multiplier), raised to at least 1 so a tick always
/// moves the health (the server's choice: the client holds no health rate).
fn health_ticked(life life: Life) -> #(Life, List(Effect)) {
  use <- bool.guard(when: life.health_clock == Idle, return: #(life, []))
  let life = Life(..life, health_clock: Idle)
  use <- bool.guard(when: !regenerates_health(life:), return: #(life, []))
  let regeneration = life.regeneration
  let share =
    int.to_float(life.max_health)
    *. regeneration.health_fraction
    *. regeneration.health_multiplier
    |> float.truncate
    |> int.max(1)
  let health = int.min(life.health + share, life.max_health)
  let #(life, timers) = health_clock_settled(life: Life(..life, health:))
  #(life, list.append(health_told(health:, dead: False), timers))
}

/// A blow lowered the health or the shield of a living player: the shield's clock
/// starts again for ShieldRebootTime from the blow, if the player has a shield
/// below its maximum.
fn shield_rebooted(life life: Life) -> #(Life, List(Effect)) {
  let cancel = case life.shield_clock {
    Running -> [CancelTimer(timer: shield_timer)]
    Idle -> []
  }
  case life.regeneration.shield, life.shield < life.max_shield {
    Some(ShieldRegeneration(reboot_ms:, ..)), True -> #(
      Life(..life, shield_clock: Running),
      list.append(cancel, [
        StartTimer(timer: shield_timer, after_ms: reboot_ms),
      ]),
    )
    Some(..), False | None, _ -> #(Life(..life, shield_clock: Idle), cancel)
  }
}

/// A shield tick, the first after the reboot: the share added to the shield, 0x938
/// of stat 20 to the player and its viewers, and the next tick while the shield is
/// below its maximum. The share is floor(max shield x ShieldRegenPct) (text
/// 531859), raised to at least 1 so a tick always moves the shield (the server's
/// choice: the client holds no minimum).
fn shield_ticked(life life: Life) -> #(Life, List(Effect)) {
  use <- bool.guard(when: life.shield_clock == Idle, return: #(life, []))
  let life = Life(..life, shield_clock: Idle)
  use <- bool.guard(
    when: life.state == Dead || life.shield >= life.max_shield,
    return: #(life, []),
  )
  case life.regeneration.shield {
    Some(regeneration) -> shield_gained(life:, regeneration:)
    None -> #(life, [])
  }
}

/// The shield's tick of `regeneration` taken for a living player whose shield is
/// below its maximum.
fn shield_gained(
  life life: Life,
  regeneration regeneration: ShieldRegeneration,
) -> #(Life, List(Effect)) {
  let share =
    int.to_float(life.max_shield) *. regeneration.percent
    |> float.truncate
    |> int.max(1)
  let shield = int.min(life.shield + share, life.max_shield)
  let life = Life(..life, shield:)
  let #(life, timers) = case shield < life.max_shield {
    True -> #(Life(..life, shield_clock: Running), [
      StartTimer(timer: shield_timer, after_ms: regeneration.tick_ms),
    ])
    False -> #(life, [])
  }
  #(life, list.append(shield_told(shield:), timers))
}

/// Both clocks stopped, each running one cancelled.
fn stopped(life life: Life) -> #(Life, List(Effect)) {
  let cancels = list.map(left(life:), fn(timer) { CancelTimer(timer:) })
  #(Life(..life, health_clock: Idle, shield_clock: Idle), cancels)
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

/// The player's full health.
pub fn max_health(life life: Life) -> Int {
  life.max_health
}

/// The player's full shield.
pub fn max_shield(life life: Life) -> Int {
  life.max_shield
}

/// Whether the player is in combat: a creature holds it on its threat list.
pub fn in_combat(life life: Life) -> Bool {
  !dict.is_empty(life.fighters)
}
