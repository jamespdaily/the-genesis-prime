//// A player's casts, a feature of the game connection's rule
//// (genesis_prime/game/connection) as movement and chat are: the press of an
//// ability on the action bar, the answers the client expects, the cast bar and
//// cooldowns it keeps, the cast's go and finish, the child casts a Proxy effect
//// starts, the thresholds of a RapidTap or ChargeRelease ability, and the cast's
//// end when the client cancels it. The caster's connection owns its casts and
//// sends every message about them; it tells the connections that see its player
//// the same news, which they write for a cast they know.
////
//// ```
//// client                    connection (this rule)                         viewers' connections
//// 0x9a press ──────────────▶ decode; bag index ─▶ the ability's tree (genesis_prime/game/spell_plan)
////                            an open threshold of the ability ─▶ the stage its index names
////                            a refusal of the client's own checks ──▶ 0x7fc {client id, Spell4 id, result}
////                            accepted: id k = mint(unit, n); the gcd starts
//// ◀── 0x7fd {client id, k, caster}                  (the caster's cast starts in its client)
////                            Tell(each viewer, CastStarted)  ──────────────▶ 0x7ff, when its client shows the caster
//// ◀── 0x816 {ability, ability, 0, k}   a RapidTap or ChargeRelease ability's first press opens its threshold
//// ◀── 0x817 {ability, index}           the next tap's stage, or the next charge level (a timer)
////                            cast time 0: the go at once; else StartTimer(go)
//// ◀── 0x7f4 {k, phase 0, no target, no effect}  ◀── Tell(each viewer, CastWent) ─▶ 0x7f4, for a cast it wrote
////                            the spell's own cooldown starts at the go its method names
////                            each Proxy of the phase: StartTimer(delay), or at once for delay 0
////                            a child: id k2 = mint, root = the pressed spell, parent = the proxying spell
//// ◀── 0x7ff {k2, ..}        Tell(each viewer, CastStarted) ───────────────▶ 0x7ff
//// ◀── 0x7f4, 0x7fe          its go and finish, as the pressed cast's
//// ◀── 0x7fe {k}             Tell(each viewer, CastFinished) ──────────────▶ 0x7fe, for a cast it wrote
//// ◀── 0x814 {ability, bit}  the last tap or the release closes the threshold
//// 0x801 {k, 6, 1} ─────────▶ the cast ends: its timers cancelled, 0x7fe to all
////
//// 0x4db held 1 ────────────▶ the ability is held: the same press, with the id k minted and no 0x7fd
////                            its cast over and its cooldowns run ─▶ the same press again (StartTimer(repeat))
//// 0x4db held 0 ────────────▶ the ability is not held: the repeat timer cancelled; a charge fires its stage
//// ```
////
//// - **The press** is 0x9a inside 0x038C: the client's cast id, the ability's bag
////   index, the target and the press bit (`opcode.0x9a`). A cast id of 0 is one
////   the client never sends, and ends the connection. A press bit of 0 is a
////   console setting's; the press is logged and ignored. A bag index the player
////   does not hold is answered 0x7fc with Spell4 id 0 and result 4
////   (`0x14039a040`; the server's choice, which the client allows).
//// - **The hold** is 0x4db: the client sends it instead of 0x9a under its default
////   hold-to-continue-casting setting, once with held 1 at key down and once with
////   held 0 at key up, with no cast id of its own (`opcode.0x4db`). A held 1 is the
////   same press as a 0x9a's with two differences: the server mints the cast id and
////   writes 0x7ff in place of 0x7fd (a 0x7fd names a pending cast the client does
////   not make), and a refusal is a 0x7fc with client cast id 0
////   (`cast.hold_answer`). The client holds no repeat timer, so while the key is
////   held the server casts the ability again, when its last cast is over and the
////   global cooldown it started and the ability's own cooldown have ended, on a
////   timer of the rule; a press behind another cast waits for its end, never
////   refused 13, which the client hides under the setting (`cast.hold_repeat`; the
////   server's choice). A second ability's held 1 replaces the held one, and a second
////   held 1 of the held ability is the same hold. Held 0 ends the repeats and cuts
////   no cast or channel short; for a ChargeRelease ability it fires the charged
////   stage, and a RapidTap ability's repeats are its next stages inside its
////   threshold (`cast.hold_by_method`, `cast.hold_stop`). A refused repeat ends the
////   hold, and so does a 0x801 naming the hold's last cast (the server's choice: a
////   cancel is the player's intent to stop, so a cancelled charge neither restarts
////   nor fires at the held 0 that follows). A bag index with no ability is answered as a 0x9a's is.
//// - **The target** of every cast is the caster: no level-1 ability needs a
////   target the client picks (`Spell4TargetMechanics.targetType`: the client makes
////   the caster the target of a spell of kind 0, 2, 6 or 7 before it sends), so
////   the press's target is not read, and the target checks of the client (91, 105)
////   wait for the first ability that needs one. Who a spell strikes is the area its
////   effects name, which a later step reads.
//// - **The refusals** are the client's own checks, answered 0x7fc with the
////   client's result and clearing the client's global cooldown: 57 for a dead
////   caster's press of a spell whose caster condition row has the dead bit, and
////   58 for a living caster's press of one whose row asks for a dead caster
////   (`Spell4.spell4ConditionsIdCaster`, `cast.dead_player`; the row's other
////   conditions are not checked); 13 while the
////   caster's current cast is live (below); 14 while the global cooldown has more
////   than 500 ms left, for kinds 0 and 2; 15 while the spell's own cooldown has
////   more than 500 ms left (`0x1403b14c0`); a caster requirement's result when the
////   caster's resource fails it, never waived (`0x1403b1780`, `Rampage` 51 below
////   250 Kinetic Energy); 50 + the resource slot for a cost the caster's class
////   resource cannot pay (`0x1403b3320`, `0x1405e7980`,
////   `Spell4CastResult.vital_cost`); 169 for a spell that needs the weapon when
////   slot 16 holds none (`0x1403afb10`); and 285 for a spell whose method is not
////   one of Normal, Multiphase, Channeled, RapidTap and ChargeRelease
////   (`Spell.CodeEnumCastMethod`). A cost in a vital the server does not hold and
////   a method not built are each logged once on the connection for the coverage
////   measure. The caster's checks run in the client's order (`Verdict`).
//// - **A cost is paid at the accept** (`Pay`), in the step of its check: a second
////   press taken in the same step is checked against what the first left
////   (genesis_prime/game/class_resource).
//// - **The current cast** is the client's: a cast whose spell shows a cast bar
////   (`spell_plan.shows_cast_bar`) is the caster's current cast from its start. Its
////   go clears it for a Normal cast with a cast time and no parent, and a cast
////   that is itself the current cast clears it at its go unless its method is
////   Multiphase, ChargeRelease or PressHold or it is a channel; any cast's finish
////   clears it, and a 0x801 clears it whatever cast it names. The client refuses
////   a press with 13 only against it, and not when its spell is free while live or
////   the pressed spell ignores casting (`cast.current_cast`, `Spell4.propertyFlags`,
////   `0x1403afb10`). The server keeps the same in `current`.
//// - **A press during the current cast is the server's choice.** The client itself
////   never refuses an ability press with 13 and never queues one behind its current
////   cast: its casting test runs only for a request whose word 0x14 is non-zero,
////   which a press leaves 0 (`cast.press_queue`). The server models that unused test
////   with the same window as the cooldown queue: a press with more than 500 ms of
////   the current cast left (its start plus its duration, `spell_plan.duration_ms`,
////   less the time now) is refused 13, and one with 500 ms or less left is held and
////   starts at the go or finish that clears the current cast, not from a timer. A
////   cast that has no end of its own, a charge held until its release, always
////   refuses.
//// - **A press within 500 ms of a cooldown's end** is held: the client queues it
////   (317) and sends it (`0x1403b14c0`), so the server starts it when the
////   cooldown ends, from a timer, and answers nothing before. A second press
////   while one is held is refused 13 (the server's choice). The held press keeps
////   the stage it resolved to when it came, as the client does. The release of a
////   ChargeRelease threshold is resolved before any caster check, so a held press
////   neither refuses it nor is changed by it (`0x1403bfd60`).
//// - **The cast id** is 2^31 + unit id x 2^11 + n mod 2^11, skipping an id a live
////   cast of the caster holds: unique among the live casts of every unit, since
////   the client keeps one table of casts (`0x140561c30`) and unit ids are below
////   2^20, and never 0. The client's own counter makes no collision: its
////   pending casts live apart (`cast.pending_table`). A child takes the next id.
//// - **The cast bar and cooldowns** are the client's own: 0x7fd and 0x7ff start
////   the caster's global cooldown (`0x14046afc0`, kinds 0 and 1), and a go starts
////   the spell's own (`0x14046b1e0`), so the server sends no 0x804. The server
////   keeps the same, to refuse what the client would: the global cooldown from the
////   accept for the SpellCoolDown time, the spell's own where its method says
////   (`spell_plan.CooldownStart`, `0x14053e5a0`), the child casts none (kind 3).
//// - **The go** is 0x7f4 with the cast id, the ignore-cooldown bit 0, the caster's
////   place as the destination, no target, no position and no missile, and the
////   phase (`opcode.0x7f4`): a go that names no target carries no damage, which
////   the next step adds. A Multiphase spell's phase is the phase's index and a
////   channel's the pulse's (`opcode.0x7f4.phase`). Each go is followed by the
////   spell's Proxies of that phase, and the finish, 0x7fe, comes after the last go,
////   at once for a spell that is not Multiphase, and for a channel at its
////   channelMaxTime from a timer of its own.
//// - **A go's gains** (`Gain`) are the spell's own gains of the phase and, once
////   for the go and not once per unit, the gains of each Proxy of the phase aimed
////   at each struck unit when the round has a Hit and the Proxy's gate passes
////   (`spell_plan.Gain`). Each is given when its prerequisite passes against the
////   caster (genesis_prime/game/prerequisite): the spells of the caster's own live
////   casts whose primary target it is, whether it is in combat, its health, shield
////   and class resource as the vitals 1, 3 and 5 to 11, and the rolls the
////   connection drew. A prerequisite of a type or a vital not read, and a ticking
////   gain, give nothing and a debug line. A creature's cast on the player is not
////   held here, so a prerequisite cannot find one (no kit prerequisite tests a
////   creature's spell).
//// - **A go's rolls** are one for each type 37 condition among the gates of the
////   Proxies that start a child and of the gains that may be given
////   (`rolls_needed`); the connection draws that many from its seed before it calls
////   `went`, and none when there is no such condition, so no other roll of the
////   connection moves.
//// - **A child cast** is the Proxy's spell cast as its own, from the caster, with
////   root the pressed spell and parent the spell whose Proxy fired
////   (`opcode.0x7ff.root_parent`), after the Proxy's delay from the parent's go;
////   its 0x7ff goes to the caster too. Its go and finish follow as a pressed
////   cast's, and it starts no global cooldown (kind 3). A Proxy behind a caster
////   apply prerequisite or one its dataBits06 names starts only when each passes
////   against the caster at the go (`proxy_gate`); one behind a target apply
////   prerequisite is not started. A child's timer is its own: the parent's finish
////   leaves the pending children, which start 100 ms after it (Crush), and only
////   the player leaving the world cancels them.
//// - **A RapidTap threshold** opens with the first tap's 0x816 and lasts the
////   ability's thresholdTime from a timer the server mirrors, since the client
////   closes it by itself then (`opcode.0x816`). Each later tap casts the stage at
////   the threshold's index, with root the ability and parent the ability
////   (`cast.stage_root_parent`), and the next index goes in 0x817; the last stage
////   closes the threshold with 0x814 and the bit set, which starts the ability's
////   cooldown. The window ending closes it, writes nothing and starts the cooldown
////   (`opcode.0x814`, `opcode.0x817`, `0x1403bfd60`).
//// - **A ChargeRelease threshold** opens with the first press's 0x816; the press's
////   cast, the base cast, stays live with no go until the release or a cancel
////   (`cast.charge_release_base`). Each later row's thresholdDuration after the
////   one before, a timer sends the next level in 0x817. The release is the next
////   press, which casts the row at the level reached; its first go starts the
////   ability's cooldown, and after its finish 0x814 closes the threshold and the
////   base cast ends with 0x7fe. The client marks the charge full at the ability's
////   thresholdTime and sends nothing, so the server holds the charge until a
////   release or a cancel.
//// - **The cancel** is 0x801: the server's cast id, a reason and a bit, which the
////   client sends as (6 or 11, 1) when the player's cast ends in its client, and
////   (0, 0) with the 0x816 value for an open ChargeRelease threshold
////   (`opcode.0x801`). It clears the caster's current cast, whatever cast that is,
////   and the cast ends with its go timers cancelled and 0x7fe to the caster and the
////   audience, no strike; the base cast of a charge ends its threshold too, with
////   0x814 before its 0x7fe. A cast that is not live is a debug line. Any other
////   reason or bit is one the client never sends, and ends the connection.
//// - **The audience** of a cast is the caster's viewers when it starts; its go and
////   finish go to them. A viewer writes a 0x7ff only when its client shows the
////   caster, and a go, or a finish, only for a cast it wrote
////   (genesis_prime/game/connection). The threshold messages go to the caster only.
//// - **Timers** are the connection's: this rule starts them with ids from
////   `first_timer`, one for each go, finish, child, held press, threshold window
////   and charge level waiting, and owns the ids from there up (`owns`).
////
//// What happens at each failure point of a cast:
////
//// | Point | What happens |
//// |---|---|
//// | a 0x9a body the client's reader refuses, or a cast id of 0 | the connection ends, nothing written |
//// | a 0x4db body the client's reader refuses | the connection ends, nothing written |
//// | a 0x4db whose bag index holds no ability | 0x7fc {0, 0, 4} for held 1, a debug line for held 0 |
//// | a 0x4db held 1 of the ability already held | the same hold: nothing written |
//// | a held cast refused, at the first press or a repeat | the 0x7fc, and the hold ends |
//// | the repeat timer fires after the release | nothing: the release cancelled it, and a firing that was already sent finds no hold |
//// | a press whose bag index the player does not hold | 0x7fc {client id, 0, 4} |
//// | a press past the last stage of an open threshold | 0x7fc {client id, the ability, 4} |
//// | a refusal of the client's own checks | 0x7fc with the result; nothing else changes |
//// | a press while one is held | 0x7fc 13 |
//// | a press with 500 ms or less of the current cast left | held, nothing written; taken at the go or finish that clears the current cast |
//// | a 0x801 for a cast that is not live, or one already finished | no change, a debug line |
//// | a 0x801 (0, 0) naming no open threshold | no change, a debug line |
//// | a 0x801 with a reason and bit the client never sends | the connection ends |
//// | a parent cast finishes with a child's timer pending | the child starts when its timer fires, with the root and parent it was made with |
//// | a threshold's window ends with taps left | the threshold closes, nothing is written, the cooldown starts |
//// | the player camps with casts, children or a threshold pending | every timer is cancelled and nothing is written: the viewers' clients drop the cast with the unit (the connection writes each viewer's 0x7fe before its 0x355) |
//// | the caster's connection ends, a key held | its timers and the hold end with it; the map's `Gone` removes the unit from each viewer, which finishes its casts first |
//// | the caster dies with casts live | each ends with its timers cancelled and 0x7fe to the caster and its audience; the hold and every other timer end (`died`) |
//// | a timer fires after its cast ended | a go finds no live cast and does nothing; the cast's end cancels its go timers |
//// | a timer fires in a status that holds no player in the world | dropped; the world is left already |
//// | the answer of a store ask comes after a timer's due time | the timer is taken after the answer: the go and finish are late by the ask, never lost |
//// | a viewer is told a go or finish of a cast it did not write | dropped (genesis_prime/game/connection) |
//// | the audience's connection has ended | the tell is dropped by the shell |

import genesis_prime/client_connection.{type News}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/class_resource.{type Payment, type Resources, Payment}
import genesis_prime/game/hit
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Plans, type Proxy, type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/ability_hold
import genesis_prime/message/cancel_cast.{type CancelCast}
import genesis_prime/message/cast_ability
import genesis_prime/message/cast_result
import genesis_prime/message/combat_result
import genesis_prime/message/float32
import genesis_prime/message/miss_reason
import genesis_prime/message/spell_cast_confirmed.{SpellCastConfirmed}
import genesis_prime/message/spell_cast_refused.{SpellCastRefused}
import genesis_prime/message/spell_effect_damage.{SpellEffectDamage}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_finished.{SpellFinished}
import genesis_prime/message/spell_go.{type SpellGo, SpellGo}
import genesis_prime/message/spell_miss.{SpellMiss}
import genesis_prime/message/spell_missed.{type SpellMissed, SpellMissed}
import genesis_prime/message/spell_position.{type SpellPosition, SpellPosition}
import genesis_prime/message/spell_started.{type SpellStarted, SpellStarted}
import genesis_prime/message/spell_target_info.{
  type SpellTargetInfo, SpellTargetInfo,
}
import genesis_prime/message/spell_threshold_closed.{SpellThresholdClosed}
import genesis_prime/message/spell_threshold_index.{SpellThresholdIndex}
import genesis_prime/message/spell_threshold_opened.{SpellThresholdOpened}
import genesis_prime/step.{
  type ConnectionId, type LogLevel, type Now, type TimerId, LogDebug, LogInfo,
  LogWarning, TimerId,
}
import genesis_prime/table/id.{type Item2Id, type Spell4BaseId, type Spell4Id}
import genesis_prime/world_map/map
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

/// The messages of a player's casts, which the client sends inside 0x038C
/// (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x009A, the press of an ability.
  Pressed
  /// 0x04DB, the key or button of an ability goes down or up under the client's
  /// hold-to-continue-casting setting, which is on by default.
  KeyHeld
  /// 0x0801, the client ends one of its player's casts.
  Cancelled
}

/// The player that casts, as the connection holds it when it takes an input.
pub type Caster {
  Caster(
    unit_id: Int,
    /// Where the player stands now.
    place: Place,
    /// The abilities the player holds, as Spell4Base ids in bag order
    /// (genesis_prime/game/loadout).
    abilities: List(Spell4BaseId),
    /// The item in the equipped slot 16, when there is one.
    weapon: Option(Item2Id),
    /// The connections whose players see this one.
    audience: Set(ConnectionId),
    /// Whether the player is dead (genesis_prime/game/player_life), which the
    /// client checks a press against (`cast.dead_player`).
    dead: Bool,
    /// The player's class resource (genesis_prime/game/class_resource), which a
    /// press's costs and requirements are checked against and paid from, and whose
    /// slots are the vitals 5 to 11 of a prerequisite.
    resources: Resources,
    /// Whether a creature holds the player on its threat list
    /// (genesis_prime/game/player_life), which a type 28 prerequisite reads.
    in_combat: Bool,
    /// The player's health (Vital 1) and shield (Vital 3), by Vital id, which a
    /// type 71 or 73 prerequisite reads beside the class resource's slots.
    life_vitals: Dict(Int, prerequisite.Vital),
  )
}

/// What the rule asks the connection to do, in order.
pub type Effect {
  /// Write a message to the caster's client.
  Send(frame: Frame)
  /// Tell the connection of a player who sees the caster the news of a cast.
  Tell(to: ConnectionId, news: News)
  StartTimer(timer: TimerId, after_ms: Int)
  CancelTimer(timer: TimerId)
  Log(level: LogLevel, text: String)
  /// A go is asked: the connection selects its targets, strikes them
  /// (genesis_prime/game/strike) and, when the round closes, answers with `went`.
  /// The go's 0x7f4 waits for that answer.
  Strike(asked: GoAsked)
  /// An accepted press's costs are taken from the caster's class resource, at the
  /// accept (genesis_prime/game/class_resource `pay`).
  Pay(payments: List(Payment))
  /// A go's resource gains are given to the caster's class resource
  /// (genesis_prime/game/class_resource `gain`).
  Gain(gains: List(class_resource.Gain))
}

/// A go of a live cast that waits for its targets: which cast and phase, the spell
/// and the cast's primary target, which a child cast on a struck unit holds as that
/// unit and any other cast as its caster.
pub type GoAsked {
  GoAsked(cast_id: Int, phase: Int, spell4_id: Spell4Id, primary_target: Int)
}

/// A unit a go names, from the round that closed (genesis_prime/game/strike).
pub type Struck {
  /// The unit is named in the 0x7f4 with the damage that landed on it, which is
  /// none for a spell that only selects it (Crush's first spell).
  Hit(unit_id: Int, descriptions: List(hit.Description))
  /// The unit deflected the strike: an entry of the 0x7fb, no description and no
  /// child (`opcode.0x7fb`).
  Deflected(unit_id: Int)
}

/// Why the client's message is refused: it ends the connection, because the
/// client's own code never sends it.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: client_connection.Undecoded)
  /// A 0x9a with the client's cast id 0, which its counter never gives
  /// (`opcode.0x9a`).
  NoClientCastId
  /// A 0x801 whose reason and bit are none the client sends together
  /// (`opcode.0x801`).
  UnknownCancel(reason: Int, bit: Int)
}

/// What a timer of the rule is for, which `State` keeps by the timer's id.
pub type Due {
  /// The go of phase `phase` of the live cast `cast_id`.
  Go(cast_id: Int, phase: Int)
  /// The live channel `cast_id` ends at its channelMaxTime, which can come after
  /// its last pulse.
  Finish(cast_id: Int)
  /// The child cast of `proxy` starts: with the pressed spell as its root and the
  /// spell whose Proxy fired as its parent, which need not be live.
  StartChild(
    root: Spell4Id,
    parent: Spell4Id,
    primary_target: Int,
    proxy: Proxy,
  )
  /// The held press starts.
  StartHeld
  /// The ability the player holds down casts again: its cooldowns have ended.
  RepeatHeld
  /// The time of the RapidTap threshold of the ability `spell4_id` runs out.
  WindowEnd(spell4_id: Int)
  /// The ChargeRelease threshold of the ability `spell4_id` reaches the charge
  /// level `level`.
  ChargeLevel(spell4_id: Int, level: Int)
}

/// What a press resolved to when it came: the spell it casts, the ability that
/// was pressed, and which stage of the ability's open threshold it casts (none for
/// the ability's own spell).
pub type Resolution {
  Resolution(spell: Spell, ability: Spell, stage: Option(Int))
}

/// What a cast is to its ability's threshold.
type Role {
  /// A child a Proxy started: no threshold is touched.
  Child
  /// The ability's own spell, which opens a threshold when its method has one.
  Base(ability: Spell)
  /// The stage at `index` of the ability's open threshold.
  Stage(ability: Spell, index: Int)
}

/// A cast of the caster that has started and not finished.
pub type Live {
  Live(
    spell: Spell,
    /// The spell the player pressed, the root of every child.
    root: Spell4Id,
    /// The spell whose Proxy started this one; none for the pressed spell.
    parent: Option(Spell4Id),
    primary_target: Int,
    /// The connections told of the start, which its go and finish go to.
    audience: Set(ConnectionId),
    /// How many of its gos have been sent.
    gone: Int,
    /// The monotonic time the cast started at, which its time left is counted from.
    started_ms: Int,
    /// The ability whose open threshold this cast is a stage of.
    stage_of: Option(Spell),
    /// Whether this cast's finish closes the ability's threshold: a release, and the
    /// last tap.
    closes_threshold: Bool,
  )
}

/// An open threshold of one ability: the stage or charge level the next press
/// casts, and the id of the base cast, which the client sends back in a 0x801
/// (`opcode.0x816`).
pub type Threshold {
  Threshold(ability: Spell, index: Int, cast_id: Int)
}

/// A press the client queued within 500 ms of a cooldown's end, or the server
/// queues within 500 ms of the end of the current cast.
pub type Held {
  Held(client_cast_id: Option(Int), resolution: Resolution, until: HeldUntil)
}

/// The ability whose key the player holds down: it casts when the key goes down
/// and again each time its cast has ended and its cooldowns allow, until the key
/// comes up (`cast.hold_repeat`).
pub type Holding {
  Holding(
    ability: Spell,
    /// The timer that waits for the cooldowns to end, when one runs.
    repeat_timer: Option(TimerId),
    /// The cast the hold started last, once it has started one: until that cast is
    /// over the ability is not cast again, and from then on a cooldown is waited
    /// for and no longer refused.
    last_cast: Option(Int),
  )
}

/// What a held press waits for.
pub type HeldUntil {
  /// The cooldown's end, from a timer.
  CooldownEnds
  /// The go or finish that clears the caster's current cast.
  CastClears
}

/// What the rule keeps for one player: its cooldowns, its live casts, its open
/// thresholds and what waits on a timer, and the counters its cast ids and timer
/// ids are made from.
pub opaque type State {
  State(
    /// The monotonic time the global cooldown ends at, once one has started. The
    /// monotonic clock can be negative, so 0 never means none.
    global_cooldown_ends_ms: Option(Int),
    /// The monotonic time each Spell4's own cooldown ends at.
    cooldown_ends_ms: Dict(Int, Int),
    casts: Dict(Int, Live),
    /// The caster's current cast, which a press is refused against (13).
    current: Option(Int),
    /// The open thresholds, by the Spell4 id of the ability.
    thresholds: Dict(Int, Threshold),
    timers: Dict(TimerId, Due),
    held: Option(Held),
    holding: Option(Holding),
    /// How many casts the player has started, which the cast ids are made from.
    presses: Int,
    /// How many timers the rule has started, which the timer ids are made from.
    timers_started: Int,
    /// The Spell4 ids already logged as unbuilt on this connection.
    logged: Set(Int),
  )
}

/// The timer id the rule's first timer takes; the connection's own are below it.
const first_timer = 1000

/// The queue window: a press with this much of a cooldown left or less is sent
/// by the client and held by the server (`player.abilityQueueMax`, `0x1403b14c0`).
const queue_window_ms = 500

/// The cast ids start here: 2^31, above where a client counter can reach.
const first_cast_id = 2_147_483_648

/// Each unit has this many cast ids: 2^11.
const ids_per_unit = 2048

/// A player that has cast nothing.
pub fn new() -> State {
  State(
    global_cooldown_ends_ms: None,
    cooldown_ends_ms: dict.new(),
    casts: dict.new(),
    current: None,
    thresholds: dict.new(),
    timers: dict.new(),
    held: None,
    holding: None,
    presses: 0,
    timers_started: 0,
    logged: set.new(),
  )
}

/// Whether the timer is one of this rule's, for the connection to hand it to
/// `timer_fired`.
pub fn owns(timer timer: TimerId) -> Bool {
  let TimerId(number) = timer
  number >= first_timer
}

/// The id of the `number`th cast of the unit `unit_id`: 2^31 + unit id x 2^11 +
/// number mod 2^11.
pub fn cast_id(unit_id unit_id: Int, number number: Int) -> Int {
  first_cast_id + unit_id * ids_per_unit + number % ids_per_unit
}

/// The unit a cast id was made for, which is how a viewer finds the casts of a
/// unit it stops showing.
pub fn caster_of(cast_id cast_id: Int) -> Int {
  { cast_id - first_cast_id } / ids_per_unit
}

/// The first id from the `number`th of the unit `unit_id` that none of the live
/// casts `live` holds: the id the rule gives the next cast. A unit holds at most
/// 2^11 ids, and a caster's live casts are far fewer.
pub fn mint(
  unit_id unit_id: Int,
  number number: Int,
  live live: List(Int),
) -> Int {
  mint_from(unit_id:, number:, live:, tried: 0)
}

fn mint_from(
  unit_id unit_id: Int,
  number number: Int,
  live live: List(Int),
  tried tried: Int,
) -> Int {
  let id = cast_id(unit_id:, number:)
  case list.contains(live, id) && tried < ids_per_unit {
    True -> mint_from(unit_id:, number: number + 1, live:, tried: tried + 1)
    False -> id
  }
}

/// The caster's 0x9a, 0x4DB or 0x801, decoded and decided: the new state and what
/// the connection must do, or the refusal that ends the connection. `now` is the
/// time of the input; the plans give each ability's tree.
pub fn take(
  cast cast: State,
  message message: Message,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  case message {
    Pressed -> pressed(cast:, body:, caster:, plans:, now:)
    KeyHeld -> key_held(cast:, body:, caster:, plans:, now:)
    Cancelled ->
      cancelled(cast:, body:, now:)
      |> result.map(fn(taken) { released(taken:, caster:, now_ms:) })
  }
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
}

/// A step's result with the held press started when the step cleared the current
/// cast it waited for.
fn released(
  taken taken: #(State, List(Effect)),
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, effects) = taken
  let caster = after_payments(caster:, effects:)
  case cast.held {
    Some(Held(client_cast_id:, resolution:, until: CastClears)) ->
      case cast.current {
        None -> {
          let #(cast, started) =
            press_of(
              cast: State(..cast, held: None),
              caster:,
              now_ms:,
              client_cast_id:,
              resolution:,
            )
          #(cast, list.append(effects, started))
        }
        Some(_) -> taken
      }
    Some(Held(until: CooldownEnds, ..)) | None -> taken
  }
}

fn pressed(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    cast_ability.decode(body)
    |> client_connection.decoded(message_id: cast_ability.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  use <- bool.guard(
    when: press.press == 0,
    return: Ok(
      #(cast, [
        Log(
          level: LogInfo,
          text: "a press with the press bit 0 is a console setting's, which is not built",
        ),
      ]),
    ),
  )
  case ability_at(caster:, plans:, bag_index: press.bag_index) {
    Error(Nil) ->
      Ok(
        #(cast, [
          refused_unknown(client_cast_id: press.client_cast_id, spell4_id: 0),
        ]),
      )
    Ok(ability) ->
      case resolved(cast:, ability:) {
        Error(Nil) ->
          Ok(
            #(cast, [
              refused_unknown(
                client_cast_id: press.client_cast_id,
                spell4_id: ability.spell4_id.value,
              ),
            ]),
          )
        Ok(resolution) ->
          Ok(press_of(
            cast:,
            caster:,
            now_ms: now.monotonic_ms,
            client_cast_id: Some(press.client_cast_id),
            resolution:,
          ))
      }
  }
}

/// The ability the player holds at the bag index, as the plans have it.
fn ability_at(
  caster caster: Caster,
  plans plans: Plans,
  bag_index bag_index: Int,
) -> Result(Spell, Nil) {
  list.drop(caster.abilities, bag_index)
  |> list.first
  |> result.try(fn(base) { spell_plan.in_plans(plans:, base:) })
}

/// The key of an ability goes down (held 1) or up (held 0). The client's reader
/// refuses a body longer or shorter than the message (`opcode.0x4db`), which ends
/// the connection, and a bag index with no ability is answered as a 0x9a's is,
/// with the client cast id 0 the client shows with no pending cast
/// (`cast.hold_stop`).
fn key_held(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use change <- result.try(
    ability_hold.decode(body)
    |> client_connection.decoded(message_id: ability_hold.message_id)
    |> result.map_error(NotDecoded),
  )
  let now_ms = now.monotonic_ms
  Ok(
    case
      ability_at(caster:, plans:, bag_index: change.bag_index),
      change.held == 1
    {
      Error(Nil), True -> #(cast, [
        refused_unknown(client_cast_id: 0, spell4_id: 0),
      ])
      Error(Nil), False -> #(cast, [
        Log(
          level: LogDebug,
          text: "the key of the bag index "
            <> int.to_string(change.bag_index)
            <> ", which holds no ability, comes up",
        ),
      ])
      Ok(ability), True -> key_down(cast:, ability:)
      Ok(ability), False -> key_up(cast:, caster:, ability:, now_ms:)
    },
  )
}

/// The ability becomes the one held: a second key down of the ability already held
/// is the same hold, and the newest ability's key replaces the held one, whose
/// cast under way ends by itself (the server's choice: the client sends each key
/// its own key up, and gives no way to hold two). Its first cast is made by
/// `continued`, once the caster is free.
fn key_down(
  cast cast: State,
  ability ability: Spell,
) -> #(State, List(Effect)) {
  case cast.holding {
    Some(Holding(ability: held, ..)) if held.spell4_id == ability.spell4_id -> #(
      cast,
      [],
    )
    Some(_) | None -> {
      let #(cast, cancels) = stop_holding(cast:)
      #(
        State(
          ..cast,
          holding: Some(Holding(ability:, repeat_timer: None, last_cast: None)),
        ),
        cancels,
      )
    }
  }
}

/// The ability's key comes up: its repeats stop, and the cast under way is left to
/// end. A ChargeRelease ability with its threshold open fires its charged stage, as
/// a 0x9a release does.
fn key_up(
  cast cast: State,
  caster caster: Caster,
  ability ability: Spell,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = case cast.holding {
    Some(Holding(ability: held, ..)) if held.spell4_id == ability.spell4_id ->
      stop_holding(cast:)
    Some(_) | None -> #(cast, [])
  }
  case
    ability.method == spell_plan.ChargeRelease
    && dict.has_key(cast.thresholds, ability.spell4_id.value)
  {
    False -> #(cast, cancels)
    True ->
      case resolved(cast:, ability:) {
        Error(Nil) -> #(cast, [
          refused_unknown(client_cast_id: 0, spell4_id: ability.spell4_id.value),
          ..cancels
        ])
        Ok(resolution) -> {
          let #(cast, released) =
            press_of(cast:, caster:, now_ms:, client_cast_id: None, resolution:)
          #(cast, list.append(cancels, released))
        }
      }
  }
}

/// No ability is held: the timer that waits to repeat is cancelled.
fn stop_holding(cast cast: State) -> #(State, List(Effect)) {
  case cast.holding {
    None -> #(cast, [])
    Some(Holding(repeat_timer:, ..)) -> {
      let #(cast, cancels) = case repeat_timer {
        Some(timer) -> #(
          State(..cast, timers: dict.delete(cast.timers, timer)),
          [CancelTimer(timer:)],
        )
        None -> #(cast, [])
      }
      #(State(..cast, holding: None), cancels)
    }
  }
}

/// The timer of the held ability's repeat fired: it waits no longer, unless the
/// hold ended or moved on to another timer.
fn repeat_fired(cast cast: State, timer timer: TimerId) -> State {
  State(
    ..cast,
    holding: option.map(cast.holding, fn(holding) {
      case holding.repeat_timer == Some(timer) {
        True -> Holding(..holding, repeat_timer: None)
        False -> holding
      }
    }),
  )
}

/// A step's result with the held ability cast again when the step left nothing in
/// its way: its last cast is over, the caster's current cast is, and no timer waits
/// for a cooldown (`cast.hold_repeat`).
fn continued(
  taken taken: #(State, List(Effect)),
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, effects) = taken
  let caster = after_payments(caster:, effects:)
  case cast.holding {
    Some(Holding(ability:, repeat_timer: None, last_cast:)) -> {
      let #(cast, more) =
        repeated(cast:, caster:, now_ms:, ability:, last_cast:)
      #(cast, list.append(effects, more))
    }
    Some(Holding(repeat_timer: Some(_), ..)) | None -> taken
  }
}

/// The held ability's next cast: a refusal when no stage is left, nothing while its
/// last cast or the caster's current cast is under way, a timer while a cooldown
/// runs, else the press itself.
fn repeated(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  ability ability: Spell,
  last_cast last_cast: Option(Int),
) -> #(State, List(Effect)) {
  case resolved(cast:, ability:) {
    Error(Nil) -> no_stage_left(cast:, ability:)
    Ok(resolution) ->
      next_cast(cast:, caster:, now_ms:, resolution:, last_cast:)
  }
}

/// A held RapidTap ability whose threshold has no stage at its index: refused, as
/// a 0x9a press is, and the hold ends.
fn no_stage_left(
  cast cast: State,
  ability ability: Spell,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = stop_holding(cast:)
  #(
    cast,
    list.append(cancels, [
      refused_unknown(client_cast_id: 0, spell4_id: ability.spell4_id.value),
    ]),
  )
}

fn next_cast(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  resolution resolution: Resolution,
  last_cast last_cast: Option(Int),
) -> #(State, List(Effect)) {
  let last_cast_is_live =
    option.map(last_cast, dict.has_key(cast.casts, _)) == Some(True)
  let blocked =
    last_cast_is_live
    || casting(cast)
    && !resolution.spell.ignores_casting
    || option.is_some(cast.held)
  let wait_ms = case last_cast {
    Some(_) -> cooldown_wait_ms(cast:, spell: resolution.spell, now_ms:)
    None -> 0
  }
  case blocked, wait_ms > 0 {
    True, _ -> #(cast, [])
    False, True -> repeat_after(cast:, wait_ms:)
    False, False ->
      press_of(cast:, caster:, now_ms:, client_cast_id: None, resolution:)
  }
}

/// How long a held ability waits before it casts again: until the global cooldown
/// its last cast started and the spell's own cooldown have both ended, whether or
/// not the global cooldown would refuse the spell (the server's choice,
/// `cast.hold_repeat`). Every level-1 ability and stage starts a global cooldown or
/// has a cooldown of its own, so a repeat is never at once; a later ability with
/// neither would recast as soon as its cast ended.
fn cooldown_wait_ms(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> Int {
  let #(_, own_left) = cooldown_left_ms(cast:, spell:, now_ms:)
  let global_left =
    option.map(cast.global_cooldown_ends_ms, fn(ends_ms) {
      int.max(0, ends_ms - now_ms)
    })
    |> option.unwrap(0)
  int.max(global_left, own_left)
}

/// The held ability waits `wait_ms` for its cooldowns on a timer of its own.
fn repeat_after(
  cast cast: State,
  wait_ms wait_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, timer) = new_timer(cast:)
  #(
    State(
      ..cast,
      timers: dict.insert(cast.timers, timer, RepeatHeld),
      holding: option.map(cast.holding, fn(holding) {
        Holding(..holding, repeat_timer: Some(timer))
      }),
    ),
    [StartTimer(timer:, after_ms: wait_ms)],
  )
}

/// What a press of the ability casts: through its open threshold the stage at the
/// threshold's index, the ability's own spell at -1, and none past the last stage
/// (`0x1403bfd60`); with no threshold open, the ability's own spell.
fn resolved(
  cast cast: State,
  ability ability: Spell,
) -> Result(Resolution, Nil) {
  case dict.get(cast.thresholds, ability.spell4_id.value) {
    Error(Nil) -> Ok(Resolution(spell: ability, ability:, stage: None))
    Ok(threshold) ->
      spell_plan.stage_at(spell: ability, index: threshold.index)
      |> result.map(fn(spell) {
        Resolution(spell:, ability:, stage: case threshold.index < 0 {
          True -> None
          False -> Some(threshold.index)
        })
      })
  }
}

/// What a press of a spell comes to: the client's refusal, a held press or a
/// cast that starts. A press with no client cast id is a held key's (0x4DB): the
/// server mints the cast id, no 0x7fd is written, a refusal carries the client
/// cast id 0, and a cooldown or a current cast is waited for by the hold itself.
fn press_of(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Option(Int),
  resolution resolution: Resolution,
) -> #(State, List(Effect)) {
  let spell = resolution.spell
  let is_release = is_release(resolution:)
  let held = option.is_some(cast.held)
  let refusal = fn(result) {
    refused(
      client_cast_id: option.unwrap(client_cast_id, 0),
      spell4_id: spell.spell4_id.value,
      result:,
    )
  }
  case verdict(cast:, caster:, spell:, now_ms:, is_release:) {
    Accept(payments:) -> {
      let cast = case client_cast_id {
        Some(_) -> cast
        None ->
          hold_started(
            cast:,
            ability: resolution.ability,
            cast_id: next_cast_id(cast:, caster:),
          )
      }
      let paid = case payments {
        [] -> []
        [_, ..] -> [Pay(payments:)]
      }
      let #(cast, started) = case resolution.stage {
        None ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell:,
            root: resolution.ability.spell4_id,
            parent: None,
            primary_target: caster.unit_id,
            client_cast_id:,
            role: Base(ability: resolution.ability),
          )
        Some(index) ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell:,
            root: resolution.ability.spell4_id,
            parent: Some(resolution.ability.spell4_id),
            primary_target: caster.unit_id,
            client_cast_id:,
            role: Stage(ability: resolution.ability, index:),
          )
      }
      #(cast, list.append(paid, started))
    }
    Refuse(result:) ->
      refused_hold(
        cast:,
        client_cast_id:,
        ability: resolution.ability,
        effects: [
          refusal(result),
        ],
      )
    NotBuilt(result:, why:) ->
      case set.contains(cast.logged, spell.spell4_id.value) {
        True ->
          refused_hold(
            cast:,
            client_cast_id:,
            ability: resolution.ability,
            effects: [refusal(result)],
          )
        False ->
          refused_hold(
            cast: State(
              ..cast,
              logged: set.insert(cast.logged, spell.spell4_id.value),
            ),
            client_cast_id:,
            ability: resolution.ability,
            effects: [
              Log(
                level: LogWarning,
                text: "the ability with Spell4 "
                  <> int.to_string(spell.spell4_id.value)
                  <> " "
                  <> why
                  <> ": it is refused with "
                  <> int.to_string(cast_result.to_value(result)),
              ),
              refusal(result),
            ],
          )
      }
    Hold(..) | HoldForCast if is_release && held -> #(cast, [
      refusal(cast_result.SpellAlreadyCasting),
    ])
    Hold(wait_ms:) ->
      case client_cast_id, is_release {
        None, False -> repeat_after(cast:, wait_ms:)
        Some(_), _ | None, True -> {
          let #(cast, timer) = new_timer(cast:)
          #(
            State(
              ..cast,
              timers: dict.insert(cast.timers, timer, StartHeld),
              held: Some(Held(client_cast_id:, resolution:, until: CooldownEnds)),
            ),
            [StartTimer(timer:, after_ms: wait_ms)],
          )
        }
      }
    HoldForCast ->
      case client_cast_id, is_release {
        None, False -> #(cast, [])
        Some(_), _ | None, True -> #(
          State(
            ..cast,
            held: Some(Held(client_cast_id:, resolution:, until: CastClears)),
          ),
          [],
        )
      }
  }
}

/// The ability's hold has started the cast `cast_id`, so its cooldowns are waited
/// for from now on and no longer refused.
fn hold_started(
  cast cast: State,
  ability ability: Spell,
  cast_id cast_id: Int,
) -> State {
  case cast.holding {
    Some(Holding(ability: held, ..) as holding)
      if held.spell4_id == ability.spell4_id
    ->
      State(..cast, holding: Some(Holding(..holding, last_cast: Some(cast_id))))
    Some(_) | None -> cast
  }
}

/// A refusal of a press written; a refused held key stops its hold, which the
/// client does not know (it shows the failure and goes on holding).
fn refused_hold(
  cast cast: State,
  client_cast_id client_cast_id: Option(Int),
  ability ability: Spell,
  effects effects: List(Effect),
) -> #(State, List(Effect)) {
  case client_cast_id, cast.holding {
    None, Some(Holding(ability: held, ..))
      if held.spell4_id == ability.spell4_id
    -> {
      let #(cast, cancels) = stop_holding(cast:)
      #(cast, list.append(cancels, effects))
    }
    Some(_), _ | None, Some(_) | None, None -> #(cast, effects)
  }
}

/// Whether the press is the release of a ChargeRelease threshold: the client has
/// resolved it through the open threshold before any caster check, so a held press
/// does not refuse it (`0x1403bfd60`).
fn is_release(resolution resolution: Resolution) -> Bool {
  case resolution.stage {
    Some(_) -> resolution.ability.method == spell_plan.ChargeRelease
    None -> False
  }
}

/// Spell4CastResult 58, Caster_MustBeDead: a living caster's press of a spell
/// whose caster row asks for a dead one (`Spell4.spell4ConditionsIdCaster`).
const caster_must_be_dead = 58

/// What the client's checks make of a press, in its order: the caster's death, a
/// press held already and the method, then CheckCastCaster's own in its order
/// (`0x1403afb10.order`): the current cast, the cooldowns (a press within the queue
/// window passing as the client's 317 does), the caster requirements, the innate
/// costs and the weapon.
type Verdict {
  /// The press is accepted, and pays these costs at the accept.
  Accept(payments: List(Payment))
  Refuse(result: cast_result.CastResult)
  /// The press is within the queue window of a cooldown's end; its costs are
  /// checked again and paid when it starts.
  Hold(wait_ms: Int)
  /// The caster's current cast has 500 ms or less left: the press waits for the go
  /// or finish that clears it, which is the server's choice (`cast.press_queue`).
  HoldForCast
  /// The spell waits for a later step: its method is not built, or its cost needs
  /// a vital the server does not hold. It is refused, and logged once.
  NotBuilt(result: cast_result.CastResult, why: String)
}

fn verdict(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
  now_ms now_ms: Int,
  is_release is_release: Bool,
) -> Verdict {
  use <- bool.guard(
    when: caster.dead && spell.caster_death == spell_plan.CannotBeDead,
    return: Refuse(result: cast_result.CasterCannotBeDead),
  )
  use <- bool.guard(
    when: !caster.dead && spell.caster_death == spell_plan.MustBeDead,
    return: Refuse(result: cast_result.from_value(caster_must_be_dead)),
  )
  use <- bool.guard(
    when: option.is_some(cast.held) && !is_release,
    return: Refuse(result: cast_result.SpellAlreadyCasting),
  )
  use <- bool.guard(
    when: !is_built(spell.method),
    return: NotBuilt(
      result: cast_result.IllegalSpellCast,
      why: "is not cast by a method that is built",
    ),
  )
  use <- bool.guard(
    when: casting(cast) && !spell.ignores_casting,
    return: case time_left_of_current_cast(cast:, now_ms:) {
      Some(left_ms) if left_ms <= queue_window_ms -> HoldForCast
      Some(_) | None -> Refuse(result: cast_result.SpellAlreadyCasting)
    },
  )
  let #(global_left, own_left) = cooldown_left_ms(cast:, spell:, now_ms:)
  use <- bool.guard(
    when: global_left > queue_window_ms,
    return: Refuse(result: cast_result.SpellGlobalCooldown),
  )
  use <- bool.guard(
    when: own_left > queue_window_ms,
    return: Refuse(result: cast_result.SpellCooldown),
  )
  case
    failed_requirement(spell:, resources: caster.resources),
    costs_paid(costs: spell.costs, resources: caster.resources)
  {
    Some(result), _ -> Refuse(result: cast_result.from_value(result))
    None, Error(Unpaid(result:)) ->
      Refuse(result: cast_result.from_value(result))
    None, Error(Unheld(result:)) ->
      NotBuilt(
        result: cast_result.from_value(result),
        why: "has an innate cost of a vital the server does not hold",
      )
    None, Ok(payments) ->
      case lacks_the_weapon(spell:, caster:), int.max(global_left, own_left) {
        True, _ -> Refuse(result: cast_result.WeaponSlot)
        False, 0 -> Accept(payments:)
        False, wait_ms -> Hold(wait_ms:)
      }
  }
}

/// The result of the first of the spell's caster requirements the caster fails
/// (`0x1403b1780`). A failed requirement is never waived: the waiver is a
/// prerequisite (`spell_plan.Spell.requirement_waiver`), which is not checked.
fn failed_requirement(
  spell spell: Spell,
  resources resources: Resources,
) -> Option(Int) {
  list.find_map(spell.requirements, fn(requirement) {
    case meets(requirement:, resources:) {
      True -> Error(Nil)
      False -> Ok(requirement.result)
    }
  })
  |> option.from_result
}

/// Whether the caster's slot meets the requirement: its amount, or its percentage
/// of its maximum, compared with the value by the eval (`0x1403b1780`,
/// `0x1407a1750`). The client divides by a maximum of 0 as a float: a slot above 0
/// is then infinitely many percent, and one at 0 is no number, which every
/// comparison fails.
fn meets(
  requirement requirement: spell_plan.Requirement,
  resources resources: Resources,
) -> Bool {
  let current = class_resource.value(resources:, slot: requirement.slot)
  let max = class_resource.max(resources:, slot: requirement.slot)
  let value = int.to_float(requirement.value)
  case requirement.measure, max == 0.0 {
    spell_plan.Amount, _ ->
      compares(comparison: requirement.comparison, current:, value:)
    spell_plan.PercentOfMax, False ->
      compares(
        comparison: requirement.comparison,
        current: current *. 100.0 /. max,
        value:,
      )
    spell_plan.PercentOfMax, True ->
      current >. 0.0
      && case requirement.comparison {
        spell_plan.Greater | spell_plan.AtLeast -> True
        spell_plan.Equal
        | spell_plan.Less
        | spell_plan.AtMost
        | spell_plan.NeverPasses(..) -> False
      }
  }
}

/// CompareByEval (`0x1407a1750`): the current value against the requirement's.
fn compares(
  comparison comparison: spell_plan.Comparison,
  current current: Float,
  value value: Float,
) -> Bool {
  case comparison {
    spell_plan.Equal -> current == value
    spell_plan.Greater -> current >. value
    spell_plan.AtLeast -> current >=. value
    spell_plan.Less -> current <. value
    spell_plan.AtMost -> current <=. value
    spell_plan.NeverPasses(..) -> False
  }
}

/// Why a press's costs are not paid.
type CostRefusal {
  /// The caster's slot holds too little: refused with the cost's result.
  Unpaid(result: Int)
  /// The cost is in a vital the server does not hold.
  Unheld(result: Int)
}

/// The spell's costs checked in order against the caster's resources, each against
/// the slots as they stand before the press, as the client checks them
/// (`0x1403b1de0`): the first refusal, or what the press pays.
fn costs_paid(
  costs costs: List(spell_plan.Cost),
  resources resources: Resources,
) -> Result(List(Payment), CostRefusal) {
  list.try_fold(costs, [], fn(payments, cost) {
    case cost {
      spell_plan.UnheldCost(result:) -> Error(Unheld(result:))
      spell_plan.SlotCost(slot:, amount:, result:) -> {
        let held =
          float.truncate(class_resource.value(resources:, slot:))
          |> int.absolute_value
        case held < int.absolute_value(amount) {
          True -> Error(Unpaid(result:))
          False -> Ok([Payment(slot:, amount:), ..payments])
        }
      }
      spell_plan.ClassVitalCost(slots: [], ..) -> Ok(payments)
      spell_plan.ClassVitalCost(slots:, amount:, result:) ->
        case
          list.find(slots, fn(slot) {
            let left =
              class_resource.value(resources:, slot:) -. int.to_float(amount)
            left >=. 0.0 && left <=. class_resource.max(resources:, slot:)
          })
        {
          Ok(slot) -> Ok([Payment(slot:, amount:), ..payments])
          Error(Nil) -> Error(Unpaid(result:))
        }
    }
  })
  |> result.map(list.reverse)
}

/// The caster with the payments and gains among the effects taken into its
/// resources, so a second press of the same step, such as a held press a go
/// releases, is checked against what the first left.
fn after_payments(
  caster caster: Caster,
  effects effects: List(Effect),
) -> Caster {
  Caster(
    ..caster,
    resources: list.fold(effects, caster.resources, fn(resources, effect) {
      case effect {
        Pay(payments:) -> class_resource.paid(resources:, payments:)
        Gain(gains:) -> class_resource.gain(resources:, gains:).0
        Send(..)
        | Tell(..)
        | StartTimer(..)
        | CancelTimer(..)
        | Log(..)
        | Strike(..) -> resources
      }
    }),
  )
}

/// What is left of the global cooldown, when it refuses the spell, and of the
/// spell's own cooldown, in milliseconds.
fn cooldown_left_ms(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> #(Int, Int) {
  let global_left = case
    spell.global_cooldown.refused_while_running,
    option.map(cast.global_cooldown_ends_ms, fn(ends_ms) {
      int.max(0, ends_ms - now_ms)
    })
  {
    True, Some(left_ms) -> left_ms
    True, None | False, Some(_) | False, None -> 0
  }
  let own_left =
    dict.get(cast.cooldown_ends_ms, spell.spell4_id.value)
    |> result.map(fn(ends_ms) { int.max(0, ends_ms - now_ms) })
    |> result.unwrap(0)
  #(global_left, own_left)
}

/// The methods the rule casts; a spell of any other is refused 285.
fn is_built(method: spell_plan.CastMethod) -> Bool {
  case method {
    spell_plan.Normal
    | spell_plan.Multiphase
    | spell_plan.Channeled
    | spell_plan.RapidTap
    | spell_plan.ChargeRelease -> True
    spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> False
  }
}

fn lacks_the_weapon(spell spell: Spell, caster caster: Caster) -> Bool {
  case spell.weapon {
    spell_plan.PrimaryWeapon -> option.is_none(caster.weapon)
    spell_plan.Refused -> True
    spell_plan.NoWeaponNeeded | spell_plan.OtherWeaponSlot(..) -> False
  }
}

/// Whether the caster's current cast is live and blocks a press: a live cast of a
/// spell that leaves the caster free never does (`0x1403afb10`,
/// `Spell4.propertyFlags`).
fn casting(cast: State) -> Bool {
  case cast.current {
    None -> False
    Some(cast_id) ->
      case dict.get(cast.casts, cast_id) {
        Ok(live) -> !live.spell.free_while_live
        Error(Nil) -> False
      }
  }
}

/// The time the caster's current cast has left, in milliseconds, from its start
/// and its duration (`cast.press_queue`); none when it has no end of its own,
/// such as a charge held until its release.
fn time_left_of_current_cast(
  cast cast: State,
  now_ms now_ms: Int,
) -> Option(Int) {
  option.then(cast.current, fn(cast_id) {
    dict.get(cast.casts, cast_id) |> option.from_result
  })
  |> option.then(fn(live) {
    spell_plan.duration_ms(spell: live.spell)
    |> option.map(fn(duration_ms) {
      int.max(0, live.started_ms + duration_ms - now_ms)
    })
  })
}

fn cancelled(
  cast cast: State,
  body body: BitArray,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use cancel <- result.try(
    cancel_cast.decode(body)
    |> client_connection.decoded(message_id: cancel_cast.message_id)
    |> result.map_error(NotDecoded),
  )
  let reason = cast_result.to_value(cancel.reason)
  use <- bool.guard(
    when: !{
      { reason == 6 || reason == 11 }
      && cancel.field_3 == 1
      || reason == 0
      && cancel.field_3 == 0
    },
    return: Error(UnknownCancel(reason:, bit: cancel.field_3)),
  )
  // A cancel is the player's intent to stop: the cast it names ends the hold that
  // started it (the server's choice), so nothing restarts or fires after it.
  let #(cast, stopped) = stop_holding_cast(cast:, cast_id: cancel.cast_id)
  let #(cast, effects) = cancelling(cast:, cancel:, now_ms: now.monotonic_ms)
  Ok(#(cast, list.append(stopped, effects)))
}

/// The hold whose last cast is `cast_id` ends.
fn stop_holding_cast(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  case cast.holding {
    Some(Holding(last_cast: Some(last), ..)) if last == cast_id ->
      stop_holding(cast:)
    Some(_) | None -> #(cast, [])
  }
}

/// What a cancel the client may send ends: an open charge with its threshold, or
/// a live cast.
fn cancelling(
  cast cast: State,
  cancel cancel: CancelCast,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let reason = cast_result.to_value(cancel.reason)
  case reason == 0, open_charge_of(cast:, cast_id: cancel.cast_id) {
    True, None -> #(State(..cast, current: None), [
      Log(
        level: LogDebug,
        text: "the client ended the threshold of the cast "
          <> int.to_string(cancel.cast_id)
          <> ", which is not open",
      ),
    ])
    True, Some(threshold) | False, Some(threshold) ->
      // The client clears the player's current cast before it sends, whatever cast
      // that is (`cast.current_cast`); the base cast of the charge ends with the
      // threshold.
      close_threshold(
        cast: State(..cast, current: None),
        ability: threshold.ability,
        now_ms:,
      )
    False, None -> {
      let cast = State(..cast, current: None)
      case dict.get(cast.casts, cancel.cast_id) {
        Error(Nil) -> #(cast, [
          Log(
            level: LogDebug,
            text: "the client ended the cast "
              <> int.to_string(cancel.cast_id)
              <> ", which is not live",
          ),
        ])
        Ok(live) ->
          end_live_cast(cast:, cast_id: cancel.cast_id, live:, now_ms:)
      }
    }
  }
}

/// A live cast the client cancelled ends: its waiting go and finish timers are
/// cancelled and its 0x7fe goes out.
fn end_live_cast(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    cancel_timers(cast:, matching: fn(due) {
      case due {
        Go(cast_id: waiting, ..) | Finish(cast_id: waiting) ->
          waiting == cast_id
        StartChild(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..) -> False
      }
    })
  let #(cast, finished) = finish(cast:, cast_id:, live:, now_ms:)
  #(cast, list.append(cancels, finished))
}

/// Every timer whose purpose `matching` accepts is forgotten and cancelled.
fn cancel_timers(
  cast cast: State,
  matching matching: fn(Due) -> Bool,
) -> #(State, List(Effect)) {
  let waiting = dict.filter(cast.timers, fn(_, due) { matching(due) })
  #(
    State(..cast, timers: dict.drop(cast.timers, dict.keys(waiting))),
    list.map(dict.keys(waiting), fn(timer) { CancelTimer(timer:) }),
  )
}

/// The open threshold whose base cast is `cast_id`: the 32-bit value the 0x816
/// carried, which the client names in a 0x801 (`opcode.0x816`).
fn open_charge_of(cast cast: State, cast_id cast_id: Int) -> Option(Threshold) {
  dict.values(cast.thresholds)
  |> list.find(fn(threshold) {
    threshold.cast_id == cast_id
    && threshold.ability.method == spell_plan.ChargeRelease
  })
  |> option.from_result
}

/// A timer of the rule fired: a go, a finish, a child cast, the held press or a
/// threshold's time.
pub fn timer_fired(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  released(
    taken: fire(cast:, timer:, caster:, now:),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

fn fire(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  case dict.get(cast.timers, timer) {
    Error(Nil) -> #(cast, [])
    Ok(due) -> {
      let cast = State(..cast, timers: dict.delete(cast.timers, timer))
      let now_ms = now.monotonic_ms
      case due {
        Go(cast_id:, phase:) -> asked(cast:, cast_id:, phase:)
        Finish(cast_id:) ->
          case dict.get(cast.casts, cast_id) {
            Error(Nil) -> #(cast, [])
            Ok(live) -> finish(cast:, cast_id:, live:, now_ms:)
          }
        StartChild(root:, parent:, proxy:, primary_target:) ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell: proxy.spell,
            root:,
            parent: Some(parent),
            primary_target:,
            client_cast_id: None,
            role: Child,
          )
        RepeatHeld -> #(repeat_fired(cast:, timer:), [])
        StartHeld ->
          case cast.held {
            None -> #(cast, [])
            Some(Held(client_cast_id:, resolution:, ..)) ->
              press_of(
                cast: State(..cast, held: None),
                caster:,
                now_ms:,
                client_cast_id:,
                resolution:,
              )
          }
        WindowEnd(spell4_id:) -> window_ended(cast:, spell4_id:, now_ms:)
        ChargeLevel(spell4_id:, level:) ->
          charge_level_reached(cast:, spell4_id:, level:)
      }
    }
  }
}

/// How many rolls the go of `phase` of the live cast `cast_id` may take once its
/// round closed with `struck`: one for each type 37 condition among the gates of
/// the Proxies that start a child and of the gains that may be given
/// (`prerequisite.rolls_needed`). The connection draws that many from its seed and
/// no others, so a go with no type 37 condition moves no roll. A cast that is not
/// live takes none.
pub fn rolls_needed(
  cast cast: State,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(Struck),
) -> Int {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> 0
    Ok(live) -> {
      let spell = live.spell
      let proxies = proxies_with_targets(spell:, phase:, struck:)
      let gates =
        list.flat_map(proxies, fn(proxy) {
          case proxy.condition {
            spell_plan.GatedOnCaster(gates:) -> gates
            spell_plan.Always | spell_plan.GatedOnTarget(..) -> []
          }
        })
      let gains =
        list.append(
          spell_plan.gains_in_phase(spell:, phase:),
          list.flat_map(proxies, lifted_gains),
        )
      int.sum(list.append(
        list.map(gates, fn(gate) {
          prerequisite.rolls_needed(prerequisite: gate)
        }),
        list.map(gains, gain_rolls_needed),
      ))
    }
  }
}

/// The rolls the check of a gain's prerequisite takes; a ticking gain is not
/// checked.
fn gain_rolls_needed(gain: spell_plan.Gain) -> Int {
  case gain {
    spell_plan.TickingGain(..) | spell_plan.Gain(prerequisite: None, ..) -> 0
    spell_plan.Gain(prerequisite: Some(gate), ..) ->
      prerequisite.rolls_needed(prerequisite: gate)
  }
}

/// The Proxies of the phase that have a unit to start a child on: one aimed at the
/// caster always, one aimed at each struck unit when the round has a Hit.
fn proxies_with_targets(
  spell spell: Spell,
  phase phase: Int,
  struck struck: List(Struck),
) -> List(Proxy) {
  let hit = hit_units(struck:) != []
  list.filter(spell_plan.proxies_in_phase(spell:, phase:), fn(proxy) {
    case proxy.target {
      spell_plan.OnCaster -> True
      spell_plan.OnEachStruck -> hit
    }
  })
}

/// The gains of a Proxy's child that the go of its parent gives once (the gains the
/// plan lifted onto the Proxy); none for a Proxy that is never started.
fn lifted_gains(proxy proxy: Proxy) -> List(spell_plan.Gain) {
  case proxy.condition {
    spell_plan.Always | spell_plan.GatedOnCaster(..) -> proxy.gains
    spell_plan.GatedOnTarget(..) -> []
  }
}

/// The round of a go closed with `struck`, the units it named in the order of its
/// selection: the go's 0x7f4 with a target info for each (target flags 0), the
/// 0x7fb of the deflected ones, the spell's own cooldown at its first go, the
/// Proxies of the phase (a Proxy aimed at each struck unit starts one child for each
/// Hit unit and none for a deflect, and none for a Proxy whose gate against the
/// caster does not pass) and the finish after the last go. A cast that is no longer
/// live, because the client ended it while the round was open, has no go and writes
/// nothing: the hits stand. `rolls` are the rolls the go's type 37 conditions take
/// (`rolls_needed`), in the order the conditions are checked.
pub fn went(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(Struck),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  released(
    taken: go(
      cast:,
      caster:,
      now_ms: now.monotonic_ms,
      cast_id:,
      phase:,
      struck:,
      rolls:,
    ),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

/// A go of a live cast is asked: the connection selects its targets and strikes them,
/// and answers with `went` when the round closes. A cast that is not live has no go.
fn asked(
  cast cast: State,
  cast_id cast_id: Int,
  phase phase: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(live) -> #(cast, [
      Strike(asked: GoAsked(
        cast_id:,
        phase:,
        spell4_id: live.spell.spell4_id,
        primary_target: live.primary_target,
      )),
    ])
  }
}

/// The player left the world with casts live: every timer is cancelled and
/// nothing is written.
pub fn left(cast cast: State) -> #(State, List(Effect)) {
  #(
    State(
      ..cast,
      casts: dict.new(),
      timers: dict.new(),
      held: None,
      holding: None,
      current: None,
      thresholds: dict.new(),
    ),
    list.map(dict.keys(cast.timers), fn(timer) { CancelTimer(timer:) }),
  )
}

/// The caster died: each live cast ends with its timers cancelled and 0x7fe to
/// the caster and the audience that was told its start, in cast id order (as a
/// 0x801 ends one, `end_live_cast`); then the held press, the hold and every open
/// threshold end, and every other timer is cancelled, as when the player leaves
/// (`left`). The client does not end its own casts when it dies (not read,
/// `0x14045e740`), so the server's 0x7fe is the end its viewers see.
pub fn died(cast cast: State, now now: Now) -> #(State, List(Effect)) {
  let #(cast, ended) =
    dict.to_list(cast.casts)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.fold(#(cast, []), fn(so_far, entry) {
      let #(cast, effects) = so_far
      let #(cast, more) =
        end_live_cast(
          cast:,
          cast_id: entry.0,
          live: entry.1,
          now_ms: now.monotonic_ms,
        )
      #(cast, list.append(effects, more))
    })
  let #(cast, cancelled) = left(cast:)
  #(cast, list.append(ended, cancelled))
}

/// The id the caster's next cast takes: the id of its next press that no live cast
/// holds. `start` and the hold that records the cast it starts both ask this, so
/// they name the same cast.
fn next_cast_id(cast cast: State, caster caster: Caster) -> Int {
  mint(
    unit_id: caster.unit_id,
    number: cast.presses,
    live: dict.keys(cast.casts),
  )
}

/// A cast of the spell starts: its id, the start written to the caster (0x7fd for
/// a press, 0x7ff for a child) and told to the audience, the global cooldown, the
/// threshold's message and timers when the cast opens or moves one, the timer of
/// each later go and of a channel's finish, and the first go at once when it has
/// no wait.
fn start(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  spell spell: Spell,
  root root: Spell4Id,
  parent parent: Option(Spell4Id),
  primary_target primary_target: Int,
  client_cast_id client_cast_id: Option(Int),
  role role: Role,
) -> #(State, List(Effect)) {
  let id = next_cast_id(cast:, caster:)
  let audience = caster.audience
  let go_times = spell_plan.go_times_ms(spell:)
  let gos =
    list.index_map(go_times, fn(wait_ms, phase) {
      #(wait_ms, Go(cast_id: id, phase:))
    })
    |> list.filter(fn(go) { go.0 > 0 })
  let finishing = case spell_plan.finish_after_ms(spell:) {
    Some(wait_ms) -> [#(wait_ms, Finish(cast_id: id))]
    None -> []
  }
  let #(cast, timer_effects) =
    list.fold(list.append(gos, finishing), #(cast, []), fn(so_far, wait) {
      let #(cast, effects) = so_far
      let #(cast, timer) = new_timer(cast:)
      #(
        State(..cast, timers: dict.insert(cast.timers, timer, wait.1)),
        list.append(effects, [StartTimer(timer:, after_ms: wait.0)]),
      )
    })
  let start_message =
    started_message(id:, spell:, root:, parent:, primary_target:, caster:)
  let live =
    Live(
      spell:,
      root:,
      parent:,
      primary_target:,
      audience:,
      gone: 0,
      started_ms: now_ms,
      stage_of: case role {
        Stage(ability:, ..) -> Some(ability)
        Child | Base(..) -> None
      },
      closes_threshold: closes_threshold(role:),
    )
  let global_ends = case spell.global_cooldown.starts_for_ms {
    Some(wait_ms) -> Some(now_ms + wait_ms)
    None -> cast.global_cooldown_ends_ms
  }
  let cast =
    State(
      ..cast,
      presses: cast.presses + 1,
      global_cooldown_ends_ms: global_ends,
      casts: dict.insert(cast.casts, id, live),
      current: case
        spell_plan.shows_cast_bar(spell:, pressed: root == spell.spell4_id)
      {
        True -> Some(id)
        False -> cast.current
      },
    )
  let to_caster = case client_cast_id {
    Some(client_cast_id) ->
      confirmed_frame(client_cast_id:, start: start_message)
    None -> started_frame(start: start_message)
  }
  let told =
    list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(
        to: viewer,
        news: client_connection.CastStarted(start: start_message),
      )
    })
  let #(cast, threshold_effects) = threshold_step(cast:, role:, cast_id: id)
  let opening =
    list.flatten([
      [Send(frame: to_caster)],
      told,
      threshold_effects,
      timer_effects,
    ])
  case go_times {
    [0, ..] -> {
      let #(cast, going) = asked(cast:, cast_id: id, phase: 0)
      #(cast, list.append(opening, going))
    }
    _ -> #(cast, opening)
  }
}

/// Whether the finish of a cast that is a stage closes its ability's threshold: a
/// release always does, a tap only when it is the last stage.
fn closes_threshold(role role: Role) -> Bool {
  case role {
    Child | Base(..) -> False
    Stage(ability:, index:) ->
      case ability.method {
        spell_plan.ChargeRelease -> True
        spell_plan.RapidTap -> index + 1 >= list.length(ability.stages)
        spell_plan.Normal
        | spell_plan.Channeled
        | spell_plan.PressHold
        | spell_plan.ChanneledField
        | spell_plan.ClientSideInteraction
        | spell_plan.Multiphase
        | spell_plan.Transactional
        | spell_plan.OtherMethod(..) -> False
      }
  }
}

/// The threshold's part of a cast's start: the ability's own spell opens one
/// (0x816, with its time or its charge timer), and a tap that is not the last
/// moves the index of a RapidTap one (0x817).
fn threshold_step(
  cast cast: State,
  role role: Role,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  case role {
    Child -> #(cast, [])
    Base(ability:) ->
      case spell_plan.opens_threshold(spell: ability) {
        True -> open_threshold(cast:, ability:, cast_id:)
        False -> #(cast, [])
      }
    Stage(ability:, index:) ->
      case dict.get(cast.thresholds, ability.spell4_id.value) {
        Error(Nil) -> #(cast, [])
        Ok(threshold) -> {
          let next = index + 1
          case
            ability.method == spell_plan.RapidTap
            && next < list.length(ability.stages)
          {
            True -> #(
              State(
                ..cast,
                thresholds: dict.insert(
                  cast.thresholds,
                  ability.spell4_id.value,
                  Threshold(..threshold, index: next),
                ),
              ),
              [
                Send(frame: index_frame(
                  spell4_id: ability.spell4_id,
                  index: next,
                )),
              ],
            )
            False -> #(cast, [])
          }
        }
      }
  }
}

/// The ability's first press opens its threshold at index 0: 0x816 with the base
/// cast's id, and the timer of its time (RapidTap) or of its first charge level
/// (ChargeRelease).
fn open_threshold(
  cast cast: State,
  ability ability: Spell,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  let cast =
    State(
      ..cast,
      thresholds: dict.insert(
        cast.thresholds,
        ability.spell4_id.value,
        Threshold(ability:, index: 0, cast_id:),
      ),
    )
  let opened = Send(frame: opened_frame(spell4_id: ability.spell4_id, cast_id:))
  case ability.method {
    spell_plan.RapidTap -> {
      let #(cast, timer) = new_timer(cast:)
      #(
        State(
          ..cast,
          timers: dict.insert(
            cast.timers,
            timer,
            WindowEnd(spell4_id: ability.spell4_id.value),
          ),
        ),
        [opened, StartTimer(timer:, after_ms: ability.threshold_ms)],
      )
    }
    spell_plan.ChargeRelease -> {
      let #(cast, waiting) = charge_timer(cast:, ability:, level: 1)
      #(cast, [opened, ..waiting])
    }
    spell_plan.Normal
    | spell_plan.Channeled
    | spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.Multiphase
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> #(cast, [opened])
  }
}

/// The timer of the charge level `level`, after the row's thresholdDuration, when
/// the ability has that row.
fn charge_timer(
  cast cast: State,
  ability ability: Spell,
  level level: Int,
) -> #(State, List(Effect)) {
  case list.drop(ability.stages, level) |> list.first {
    Error(Nil) -> #(cast, [])
    Ok(stage) -> {
      let #(cast, timer) = new_timer(cast:)
      #(
        State(
          ..cast,
          timers: dict.insert(
            cast.timers,
            timer,
            ChargeLevel(spell4_id: ability.spell4_id.value, level:),
          ),
        ),
        [StartTimer(timer:, after_ms: stage.duration_ms)],
      )
    }
  }
}

/// The charge reaches `level`: 0x817, and the timer of the next level.
fn charge_level_reached(
  cast cast: State,
  spell4_id spell4_id: Int,
  level level: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.thresholds, spell4_id) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> {
      let cast =
        State(
          ..cast,
          thresholds: dict.insert(
            cast.thresholds,
            spell4_id,
            Threshold(..threshold, index: level),
          ),
        )
      let #(cast, waiting) =
        charge_timer(cast:, ability: threshold.ability, level: level + 1)
      #(cast, [
        Send(frame: index_frame(
          spell4_id: threshold.ability.spell4_id,
          index: level,
        )),
        ..waiting
      ])
    }
  }
}

/// A RapidTap threshold's time ran out: the client closes it by itself, so the
/// server writes nothing, closes its own and starts the ability's cooldown
/// (`opcode.0x816`).
fn window_ended(
  cast cast: State,
  spell4_id spell4_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.thresholds, spell4_id) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> #(
      start_cooldown(
        cast: State(..cast, thresholds: dict.delete(cast.thresholds, spell4_id)),
        spell: threshold.ability,
        now_ms:,
      ),
      [],
    )
  }
}

/// The ability's threshold closes: its timers are cancelled and 0x814 is sent. A
/// RapidTap one starts the ability's cooldown with the bit; a ChargeRelease one
/// ends its base cast with 0x7fe after the 0x814.
fn close_threshold(
  cast cast: State,
  ability ability: Spell,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let key = ability.spell4_id.value
  case dict.get(cast.thresholds, key) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> {
      let #(cast, cancels) =
        cancel_timers(cast:, matching: fn(due) {
          case due {
            WindowEnd(spell4_id:) | ChargeLevel(spell4_id:, ..) ->
              spell4_id == key
            Go(..) | Finish(..) | StartChild(..) | StartHeld | RepeatHeld ->
              False
          }
        })
      let cast = State(..cast, thresholds: dict.delete(cast.thresholds, key))
      case ability.method {
        spell_plan.RapidTap -> #(
          start_cooldown(cast:, spell: ability, now_ms:),
          list.append(cancels, [
            Send(frame: closed_frame(
              spell4_id: ability.spell4_id,
              start_cooldowns: 1,
            )),
          ]),
        )
        spell_plan.ChargeRelease -> {
          let closed =
            Send(frame: closed_frame(
              spell4_id: ability.spell4_id,
              start_cooldowns: 0,
            ))
          let #(cast, ended) =
            end_base_cast(cast:, cast_id: threshold.cast_id, now_ms:)
          #(cast, list.flatten([cancels, [closed], ended]))
        }
        spell_plan.Normal
        | spell_plan.Channeled
        | spell_plan.PressHold
        | spell_plan.ChanneledField
        | spell_plan.ClientSideInteraction
        | spell_plan.Multiphase
        | spell_plan.Transactional
        | spell_plan.OtherMethod(..) -> #(cast, cancels)
      }
    }
  }
}

/// The base cast of a charge ends with its 0x7fe, when it is still live.
fn end_base_cast(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Ok(base) -> finish(cast:, cast_id:, live: base, now_ms:)
    Error(Nil) -> #(cast, [])
  }
}

/// The spell's own cooldown starts now, unless it is running already or the spell
/// has none.
fn start_cooldown(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> State {
  let running =
    dict.get(cast.cooldown_ends_ms, spell.spell4_id.value)
    |> result.map(fn(ends_ms) { ends_ms > now_ms })
    |> result.unwrap(False)
  case spell.cooldown_ms > 0 && !running {
    True ->
      State(
        ..cast,
        cooldown_ends_ms: dict.insert(
          cast.cooldown_ends_ms,
          spell.spell4_id.value,
          now_ms + spell.cooldown_ms,
        ),
      )
    False -> cast
  }
}

/// The go of phase `phase` of a live cast, with the units its round struck: 0x7f4 to
/// the caster and the audience, then the 0x7fb of the deflected ones (the client
/// accepts either order and drops a miss after the finish, `cast.miss_order`), the
/// spell's own cooldown at the go its method names, the current cast cleared as the
/// client does, the Proxies of the phase whose gates pass, and the finish after the
/// last go. A cast that is not live has no go.
fn go(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(Struck),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(live) -> {
      let spell = live.spell
      let go_message =
        go_message(cast_id:, phase:, place: caster.place, struck:)
      let missed = missed_message(cast_id:, struck:)
      let going =
        list.flatten([
          [Send(frame: went_frame(go: go_message))],
          list.map(map.sorted_connections(live.audience), fn(viewer) {
            Tell(to: viewer, news: client_connection.CastWent(go: go_message))
          }),
          case missed {
            Some(missed) -> [
              Send(frame: missed_frame(missed:)),
              ..list.map(map.sorted_connections(live.audience), fn(viewer) {
                Tell(to: viewer, news: client_connection.CastMissed(missed:))
              })
            ]
            None -> []
          },
        ])
      let go_count = list.length(spell_plan.go_times_ms(spell:))
      let cast = case spell.cooldown_start {
        spell_plan.AtFirstGo if live.gone == 0 ->
          start_cooldown(cast:, spell:, now_ms:)
        spell_plan.AtLastGo if live.gone + 1 == go_count ->
          start_cooldown(cast:, spell:, now_ms:)
        spell_plan.AtFirstGo | spell_plan.AtLastGo | spell_plan.NotAtAGo -> cast
      }
      let cast = case live.stage_of {
        Some(ability)
          if spell.method == spell_plan.ChargeRelease && live.gone == 0
        -> start_cooldown(cast:, spell: ability, now_ms:)
        Some(_) | None -> cast
      }
      let current = case clears_current(cast:, live:, cast_id:) {
        True -> None
        False -> cast.current
      }
      let live = Live(..live, gone: live.gone + 1)
      let cast =
        State(..cast, current:, casts: dict.insert(cast.casts, cast_id, live))
      let subject = subject_of(cast:, caster:)
      let #(starting, gate_logs, rolls) =
        proxy_gates(
          proxies: proxies_with_targets(spell:, phase:, struck:),
          subject:,
          rolls:,
        )
      let #(cast, children) =
        list.fold(starting, #(cast, []), fn(so_far, proxy) {
          let #(cast, effects) = so_far
          let #(cast, more) =
            children(cast:, caster:, now_ms:, live:, proxy:, struck:)
          #(cast, list.append(effects, more))
        })
      let #(cast, finished) = case
        live.gone == go_count
        && option.is_none(spell_plan.finish_after_ms(spell:))
      {
        True -> finish(cast:, cast_id:, live:, now_ms:)
        False -> #(cast, [])
      }
      let gains = gains_given(spell:, phase:, starting:, subject:, rolls:)
      #(cast, list.flatten([going, gains, gate_logs, children, finished]))
    }
  }
}

/// What a prerequisite may read about the caster, with no roll: the live casts it is
/// the primary target of, whether it is in combat, and its vitals: its health and
/// shield, and the class resource's slots as Vitals 5 to 11 (Resource0 to
/// Resource6: `Prerequisite.prerequisiteTypeId.73`, `Spell4Effects.effectType.1`).
fn subject_of(cast cast: State, caster caster: Caster) -> prerequisite.Subject {
  let slots =
    list.map([5, 6, 7, 8, 9, 10, 11], fn(vital) {
      let slot = vital - 5
      #(
        vital,
        prerequisite.Vital(
          current: class_resource.value(resources: caster.resources, slot:),
          maximum: class_resource.max(resources: caster.resources, slot:),
        ),
      )
    })
  prerequisite.Subject(
    under: dict.values(cast.casts)
      |> list.filter(fn(live) { live.primary_target == caster.unit_id })
      |> list.map(fn(live) { live.spell.spell4_id }),
    in_combat: caster.in_combat,
    vitals: dict.merge(dict.from_list(slots), caster.life_vitals),
    rolls: [],
  )
}

/// The prerequisite checked against the subject with the rolls its type 37
/// conditions take off the front of `rolls`, and the rolls left.
fn checked(
  prerequisite gate: prerequisite.Prerequisite,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(prerequisite.Verdict, List(Int)) {
  let #(taken, left) =
    list.split(rolls, prerequisite.rolls_needed(prerequisite: gate))
  #(
    prerequisite.check(
      prerequisite: gate,
      subject: prerequisite.Subject(..subject, rolls: taken),
    ),
    left,
  )
}

/// What a Proxy's gate gives at a go.
type ProxyGate {
  /// Its child starts.
  Starts
  /// A gate fails: the client's answer, nothing to say.
  GateFails
  /// The server cannot tell, and `why` says so in a debug line.
  CannotTell(why: String)
}

/// Which of the Proxies of a go start a child, with a debug line for each that
/// cannot be decided, and the rolls left (`proxy_gate`).
fn proxy_gates(
  proxies proxies: List(Proxy),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(List(Proxy), List(Effect), List(Int)) {
  let #(starting, logs, rolls) =
    list.fold(proxies, #([], [], rolls), fn(so_far, proxy) {
      let #(starting, logs, rolls) = so_far
      let #(gate, rolls) = proxy_gate(proxy:, subject:, rolls:)
      case gate {
        Starts -> #([proxy, ..starting], logs, rolls)
        GateFails -> #(starting, logs, rolls)
        CannotTell(why:) -> #(
          starting,
          [Log(level: LogDebug, text: why), ..logs],
          rolls,
        )
      }
    })
  #(list.reverse(starting), list.reverse(logs), rolls)
}

/// A Proxy with no gate starts. One gated on the caster starts when every gate
/// passes against the caster, and is passed over when one fails; when none fails
/// and one is of a type or a vital not read it does not start, with a debug line.
/// One gated on a target prerequisite does not start, with a debug line
/// (genesis_prime/game/spell_plan `Condition`).
fn proxy_gate(
  proxy proxy: Proxy,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(ProxyGate, List(Int)) {
  let child = int.to_string(proxy.spell.spell4_id.value)
  case proxy.condition {
    spell_plan.Always -> #(Starts, rolls)
    spell_plan.GatedOnTarget(prerequisite_id:) -> #(
      CannotTell(
        why: "the Proxy to Spell4 "
        <> child
        <> " applies only behind target prerequisite "
        <> int.to_string(prerequisite_id.value)
        <> ", which is not checked, so it is not started",
      ),
      rolls,
    )
    spell_plan.GatedOnCaster(gates:) -> {
      let #(left, verdicts) =
        list.map_fold(gates, rolls, fn(rolls, gate) {
          let #(verdict, left) = checked(prerequisite: gate, subject:, rolls:)
          #(left, #(gate, verdict))
        })
      let not_read =
        list.find_map(verdicts, fn(decided) {
          case decided.1 {
            prerequisite.NotRead(prerequisite_type:) ->
              Ok(#(decided.0, prerequisite_type))
            prerequisite.Passes | prerequisite.Fails -> Error(Nil)
          }
        })
      let failed =
        list.any(verdicts, fn(decided) { decided.1 == prerequisite.Fails })
      case failed, not_read {
        True, _ -> #(GateFails, left)
        False, Error(Nil) -> #(Starts, left)
        False, Ok(#(gate, prerequisite_type)) -> #(
          CannotTell(
            why: "the Proxy to Spell4 "
            <> child
            <> " is behind prerequisite "
            <> int.to_string(prerequisite.id(prerequisite: gate).value)
            <> " of type "
            <> int.to_string(prerequisite_type)
            <> ", which is not read, so it is not started",
          ),
          left,
        )
      }
    }
  }
}

/// The gains a go gives (`Gain`), and a debug line for each it cannot: the spell's
/// own of the phase, then once each of the Proxies that start a child aimed at each
/// struck unit, which `starting` holds only when one unit was Hit.
fn gains_given(
  spell spell: Spell,
  phase phase: Int,
  starting starting: List(Proxy),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> List(Effect) {
  let #(_, given, logs) =
    list.fold(
      list.append(
        spell_plan.gains_in_phase(spell:, phase:),
        list.flat_map(starting, lifted_gains),
      ),
      #(rolls, [], []),
      fn(so_far, gain) {
        let #(rolls, given, logs) = so_far
        let #(verdict, rolls) = gain_verdict(gain:, subject:, rolls:)
        case verdict {
          Given(gain: gift) -> #(rolls, [gift, ..given], logs)
          Withheld -> #(rolls, given, logs)
          NotApplied(why:) -> #(rolls, given, [
            Log(level: LogDebug, text: why),
            ..logs
          ])
        }
      },
    )
  let gains = case given {
    [] -> []
    [_, ..] -> [Gain(gains: list.reverse(given))]
  }
  list.append(list.reverse(logs), gains)
}

/// What becomes of one gain of a go.
type GainVerdict {
  Given(gain: class_resource.Gain)
  /// Its prerequisite fails.
  Withheld
  /// It cannot be given, and `why` says so in a debug line: a ticking gain, or a
  /// prerequisite of a type not read.
  NotApplied(why: String)
}

/// The gain given, withheld for a prerequisite that fails, or not applied, and the
/// rolls left after its prerequisite's check.
fn gain_verdict(
  gain gain: spell_plan.Gain,
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(GainVerdict, List(Int)) {
  let effect = int.to_string(gain.effect_id.value)
  case gain {
    spell_plan.TickingGain(..) -> #(
      NotApplied(
        why: "the ticking gain of Spell4Effects " <> effect <> " is not applied",
      ),
      rolls,
    )
    spell_plan.Gain(prerequisite: None, slot:, amount:, ..) -> #(
      Given(gain: class_resource.Gain(slot:, amount:)),
      rolls,
    )
    spell_plan.Gain(prerequisite: Some(gate), slot:, amount:, ..) -> {
      let #(verdict, rolls) = checked(prerequisite: gate, subject:, rolls:)
      #(
        gate_verdict(
          verdict:,
          gate:,
          effect:,
          gift: class_resource.Gain(slot:, amount:),
        ),
        rolls,
      )
    }
  }
}

/// What a gain's prerequisite makes of the gain.
fn gate_verdict(
  verdict verdict: prerequisite.Verdict,
  gate gate: prerequisite.Prerequisite,
  effect effect: String,
  gift gift: class_resource.Gain,
) -> GainVerdict {
  case verdict {
    prerequisite.Passes -> Given(gain: gift)
    prerequisite.Fails -> Withheld
    prerequisite.NotRead(prerequisite_type:) ->
      NotApplied(
        why: "the gain of Spell4Effects "
        <> effect
        <> " is behind prerequisite "
        <> int.to_string(prerequisite.id(prerequisite: gate).value)
        <> " of type "
        <> int.to_string(prerequisite_type)
        <> ", which is not read, so it is not given",
      )
  }
}

/// Whether a go clears the caster's current cast (`cast.current_cast`): a cast with
/// a cast bar, a cast time and no parent clears whichever cast is current, unless
/// its method is Channeled, PressHold, ChanneledField, ChargeRelease or
/// Multiphase; any other cast clears it only when it is the current cast, has no
/// channel and is not PressHold, ChargeRelease or Multiphase.
fn clears_current(
  cast cast: State,
  live live: Live,
  cast_id cast_id: Int,
) -> Bool {
  let spell = live.spell
  let clears_whichever = case spell.method {
    spell_plan.Normal
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) ->
      spell.cast_time_ms != 0
      && live.parent == None
      && spell_plan.shows_cast_bar(
        spell:,
        pressed: live.root == spell.spell4_id,
      )
    spell_plan.Channeled
    | spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ChargeRelease
    | spell_plan.Multiphase -> False
  }
  let clears_itself = case spell.method {
    spell_plan.Normal
    | spell_plan.Channeled
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) ->
      cast.current == Some(cast_id) && option.is_none(spell.channel)
    spell_plan.PressHold | spell_plan.ChargeRelease | spell_plan.Multiphase ->
      False
  }
  clears_whichever || clears_itself
}

/// The units a round Hit, in the round's order; a deflect is none of them.
fn hit_units(struck struck: List(Struck)) -> List(Int) {
  list.filter_map(struck, fn(one) {
    case one {
      Hit(unit_id:, ..) -> Ok(unit_id)
      Deflected(..) -> Error(Nil)
    }
  })
}

/// A Proxy of a go: a Proxy aimed at the area starts one child for each Hit unit of
/// the round and none for a deflect, any other starts one on the caster.
fn children(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  live live: Live,
  proxy proxy: Proxy,
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  let targets = case proxy.target {
    spell_plan.OnCaster -> [caster.unit_id]
    spell_plan.OnEachStruck -> hit_units(struck:)
  }
  list.fold(targets, #(cast, []), fn(so_far, primary_target) {
    let #(cast, effects) = so_far
    let #(cast, more) =
      child(cast:, caster:, now_ms:, live:, proxy:, primary_target:)
    #(cast, list.append(effects, more))
  })
}

/// One child of a Proxy: it starts at once for no delay, else after it from a timer
/// of its own. The Proxy's gate has passed at the go (`proxy_gates`).
fn child(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  live live: Live,
  proxy proxy: Proxy,
  primary_target primary_target: Int,
) -> #(State, List(Effect)) {
  case proxy.delay_ms > 0 {
    False ->
      start(
        cast:,
        caster:,
        now_ms:,
        spell: proxy.spell,
        root: live.root,
        parent: Some(live.spell.spell4_id),
        primary_target:,
        client_cast_id: None,
        role: Child,
      )
    True -> {
      let #(cast, timer) = new_timer(cast:)
      #(
        State(
          ..cast,
          timers: dict.insert(
            cast.timers,
            timer,
            StartChild(
              root: live.root,
              parent: live.spell.spell4_id,
              primary_target:,
              proxy:,
            ),
          ),
        ),
        [StartTimer(timer:, after_ms: proxy.delay_ms)],
      )
    }
  }
}

/// A live cast ends: 0x7fe to the caster and the audience, and the cast is no
/// longer live nor the caster's current cast. A channel starts its cooldown here
/// too (`0x14053e1b0`), and a stage that closes its ability's threshold does that
/// after its 0x7fe.
fn finish(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let cast =
    State(
      ..cast,
      casts: dict.delete(cast.casts, cast_id),
      current: case cast.current == Some(cast_id) {
        True -> None
        False -> cast.current
      },
    )
  let cast = case live.spell.method, live.spell.cooldown_phase {
    spell_plan.Channeled, _ -> start_cooldown(cast:, spell: live.spell, now_ms:)
    spell_plan.Multiphase, Some(phase) if live.gone > phase ->
      start_cooldown(cast:, spell: live.spell, now_ms:)
    spell_plan.Multiphase, _ -> cast
    spell_plan.Normal, _
    | spell_plan.PressHold, _
    | spell_plan.ChanneledField, _
    | spell_plan.ClientSideInteraction, _
    | spell_plan.RapidTap, _
    | spell_plan.ChargeRelease, _
    | spell_plan.Transactional, _
    | spell_plan.OtherMethod(..), _
    -> cast
  }
  let ended = [
    Send(frame: finished_frame(cast_id:)),
    ..list.map(map.sorted_connections(live.audience), fn(viewer) {
      Tell(to: viewer, news: client_connection.CastFinished(cast_id:))
    })
  ]
  case live.stage_of, live.closes_threshold {
    Some(ability), True -> {
      let #(cast, closed) = close_threshold(cast:, ability:, now_ms:)
      #(cast, list.append(ended, closed))
    }
    Some(_), False | None, True | None, False -> #(cast, ended)
  }
}

/// The next timer's id, and the state counting it.
fn new_timer(cast cast: State) -> #(State, TimerId) {
  #(
    State(..cast, timers_started: cast.timers_started + 1),
    TimerId(first_timer + cast.timers_started),
  )
}

fn position_of(place place: Place) -> SpellPosition {
  SpellPosition(
    x: float32.to_bits(start_place.x(place)),
    y: float32.to_bits(start_place.y(place)),
    z: float32.to_bits(start_place.z(place)),
  )
}

fn yaw_of(place place: Place) -> Int {
  float32.to_bits(start_place.facing(place).yaw)
}

/// 0x7ff for a cast that starts: the caster is its own primary target
/// (`Spell4TargetMechanics.targetType`), the lists are empty (`spell.empty_lists`)
/// and the 16-bit value and the two bits are the decode's safe values
/// (`opcode.0x7ff.caster_item_level`, `opcode.0x7ff.own_cast`,
/// `opcode.0x7ff.activate`).
fn started_message(
  id id: Int,
  spell spell: Spell,
  root root: Spell4Id,
  parent parent: Option(Spell4Id),
  primary_target primary_target: Int,
  caster caster: Caster,
) -> SpellStarted {
  SpellStarted(
    cast_id: id,
    spell4_id: spell.spell4_id.value,
    root_spell4_id: root.value,
    parent_spell4_id: case parent {
      Some(parent) -> parent.value
      None -> 0
    },
    caster_unit_id: caster.unit_id,
    field_6: 0,
    primary_target_unit_id: primary_target,
    position: position_of(place: caster.place),
    yaw: yaw_of(place: caster.place),
    initial_positions: [],
    telegraph_positions: [],
    field_12: 1,
    field_13: 0,
  )
}

/// 0x7f4 for a go: a target info for each Hit unit in the order of the round, with
/// target flags 0 (`opcode.0x7f4.target_info`), each with the damage that landed, no
/// position and no missile (`opcode.0x7f4`, `spell.empty_lists`). A deflected unit has
/// no info: the 0x7fb shows it.
fn go_message(
  cast_id cast_id: Int,
  phase phase: Int,
  place place: Place,
  struck struck: List(Struck),
) -> SpellGo {
  SpellGo(
    cast_id:,
    ignore_cooldown: 0,
    destination: position_of(place:),
    targets: list.filter_map(struck, fn(one) {
      case one {
        Hit(unit_id:, descriptions:) -> Ok(#(unit_id, descriptions))
        Deflected(..) -> Error(Nil)
      }
    })
      |> list.index_map(fn(hit, index) {
        target_info(index:, unit_id: hit.0, descriptions: hit.1)
      }),
    initial_positions: [],
    telegraph_positions: [],
    missiles: [],
    phase:,
  )
}

/// The refusal of a press that names no ability, or no stage left of one: result 4
/// (`0x14039a040`), the same answer to a 0x9a and to a 0x4db.
fn refused_unknown(
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
) -> Effect {
  refused(client_cast_id:, spell4_id:, result: cast_result.SpellUnknown)
}

fn refused(
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
  result result: cast_result.CastResult,
) -> Effect {
  let assert Ok(body) =
    spell_cast_refused.encode(SpellCastRefused(
      client_cast_id:,
      spell4_id:,
      result:,
    ))
    as "a cast id of 32 bits, a Spell4 id of 18 and a result of 9 fit the message"
  Send(frame: Frame(message_id: spell_cast_refused.message_id, body:))
}

/// 0x07FD for the press's cast: the client's id, the server's, the caster as its
/// primary target and the position and yaw the 0x7ff holds.
fn confirmed_frame(
  client_cast_id client_cast_id: Int,
  start start: SpellStarted,
) -> Frame {
  let assert Ok(body) =
    spell_cast_confirmed.encode(
      SpellCastConfirmed(
        client_cast_id:,
        server_cast_id: start.cast_id,
        primary_target_unit_id: start.primary_target_unit_id,
        position: start.position,
        yaw: start.yaw,
        initial_positions: [],
        telegraph_positions: [],
      ),
    )
    as "a cast id of 32 bits and floats fit the message, and the rule sends no list"
  Frame(message_id: spell_cast_confirmed.message_id, body:)
}

/// 0x0816 for a threshold that opens: the ability's spell as the opened and the
/// resolving spell, 0 for the third (the opened spell's own cooldowns), and the
/// base cast's id as the value the client sends back (`opcode.0x816`).
fn opened_frame(spell4_id spell4_id: Spell4Id, cast_id cast_id: Int) -> Frame {
  let assert Ok(body) =
    spell_threshold_opened.encode(SpellThresholdOpened(
      spell4_id: spell4_id.value,
      resolving_spell4_id: spell4_id.value,
      cooldown_spell4_id: 0,
      cancel_cast_id: cast_id,
    ))
    as "Spell4 ids of 18 bits and a cast id of 32 fit the message"
  Frame(message_id: spell_threshold_opened.message_id, body:)
}

/// 0x0817 for the index the next press casts (`opcode.0x817`).
fn index_frame(spell4_id spell4_id: Spell4Id, index index: Int) -> Frame {
  let assert Ok(body) =
    spell_threshold_index.encode(SpellThresholdIndex(
      spell4_id: spell4_id.value,
      index:,
    ))
    as "a Spell4 id of 18 bits and a stage index of 8 fit the message"
  Frame(message_id: spell_threshold_index.message_id, body:)
}

/// 0x0814 for a threshold that closes, with the bit that starts the cooldowns
/// (`opcode.0x814`).
fn closed_frame(
  spell4_id spell4_id: Spell4Id,
  start_cooldowns start_cooldowns: Int,
) -> Frame {
  let assert Ok(body) =
    spell_threshold_closed.encode(SpellThresholdClosed(
      spell4_id: spell4_id.value,
      start_cooldowns:,
    ))
    as "a Spell4 id of 18 bits and a bit fit the message"
  Frame(message_id: spell_threshold_closed.message_id, body:)
}

/// 0x7ff for a creature's cast of its attack spell on its target, from where it
/// stands: the target is the cast's primary target, the spell its own root, and the
/// lists and the safe values are a player's cast's (`started_message`).
pub fn creature_started(
  cast_id cast_id: Int,
  spell4_id spell4_id: Int,
  caster_unit_id caster_unit_id: Int,
  target_unit_id target_unit_id: Int,
  place place: Place,
) -> SpellStarted {
  SpellStarted(
    cast_id:,
    spell4_id:,
    root_spell4_id: spell4_id,
    parent_spell4_id: 0,
    caster_unit_id:,
    field_6: 0,
    primary_target_unit_id: target_unit_id,
    position: position_of(place:),
    yaw: yaw_of(place:),
    initial_positions: [],
    telegraph_positions: [],
    field_12: 1,
    field_13: 0,
  )
}

/// 0x7f4 for the one go, phase 0, of a creature's cast, with the units its round
/// struck, as a player's go is written (`go_message`).
pub fn creature_went(
  cast_id cast_id: Int,
  place place: Place,
  struck struck: List(Struck),
) -> SpellGo {
  go_message(cast_id:, phase: 0, place:, struck:)
}

/// 0x7fb for the units a creature's go missed, or none (`missed_message`).
pub fn creature_missed(
  cast_id cast_id: Int,
  struck struck: List(Struck),
) -> Option(SpellMissed) {
  missed_message(cast_id:, struck:)
}

/// 0x07FF for a cast that starts, which the caster's rule tells each viewer as
/// news and each viewer's connection writes the same way.
pub fn started_frame(start start: SpellStarted) -> Frame {
  let assert Ok(body) = spell_started.encode(start)
    as "a cast id of 32 bits, Spell4 ids of 18 and a unit id of 32 fit the message, and the rule sends no list"
  Frame(message_id: spell_started.message_id, body:)
}

/// 0x07F4 for a cast that goes off, written by the caster's rule and by each
/// viewer's connection the same way.
pub fn went_frame(go go: SpellGo) -> Frame {
  let assert Ok(body) = spell_go.encode(go)
    as "a cast id of 32 bits and a phase of 8 fit the message, and the rule sends no list"
  Frame(message_id: spell_go.message_id, body:)
}

/// 0x07FE for a cast that ends, written by the caster's rule and by each
/// viewer's connection the same way (`opcode.0x7fe`).
pub fn finished_frame(cast_id cast_id: Int) -> Frame {
  let assert Ok(body) = spell_finished.encode(SpellFinished(cast_id:))
    as "a cast id of 32 bits fits the message"
  Frame(message_id: spell_finished.message_id, body:)
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    NoClientCastId ->
      "0x009A names the client's cast id 0, which its counter never gives"
    UnknownCancel(reason:, bit:) ->
      "0x0801 holds the reason "
      <> int.to_string(reason)
      <> " and the bit "
      <> int.to_string(bit)
      <> ", which the client never sends together"
  }
}

/// One struck unit's info in a go: its place in the list, target flags 0
/// (`opcode.0x7f4.target_info`), the combat result of the strike, and an effect
/// info for each landed blow with its damage description and delay. The instance
/// count and the effects' instance ids number from 1 (kept by the client, no reader
/// traced).
fn target_info(
  index index: Int,
  unit_id unit_id: Int,
  descriptions descriptions: List(hit.Description),
) -> SpellTargetInfo {
  SpellTargetInfo(
    unit_id:,
    index:,
    flags: 0,
    instance_count: 1,
    combat_result: case
      list.any(descriptions, fn(description) {
        description.damage.combat_result == combat_result.Critical
      })
    {
      True -> combat_result.Critical
      False -> combat_result.Hit
    },
    effects: list.index_map(descriptions, fn(description, effect_index) {
      SpellEffectInfo(
        spell4_effects_id: description.spell4_effects_id,
        instance_id: effect_index + 1,
        delay_ms: description.delay_ms,
        field_4: 0,
        result: spell_effect_result.Damage(SpellEffectDamage(
          description: description.damage,
        )),
      )
    }),
  )
}

/// 0x7fb for the deflected units of a go, or none when none was deflected: each
/// entry has reason 0 (Dodge, which the client shows as Deflect) and time 0
/// (`opcode.0x7fb`, `opcode.0x7fb.time`).
fn missed_message(
  cast_id cast_id: Int,
  struck struck: List(Struck),
) -> Option(SpellMissed) {
  case
    list.filter_map(struck, fn(one) {
      case one {
        Deflected(unit_id:) ->
          Ok(SpellMiss(unit_id:, reason: miss_reason.Dodge, time_ms: 0))
        Hit(..) -> Error(Nil)
      }
    })
  {
    [] -> None
    misses -> Some(SpellMissed(cast_id:, misses:))
  }
}

/// 0x07FB for a cast whose targets were missed, written by the caster's rule and by
/// each viewer's connection the same way.
pub fn missed_frame(missed missed: SpellMissed) -> Frame {
  let assert Ok(body) = spell_missed.encode(missed)
    as "a cast id of 32 bits, a unit id of 32 and a reason of 4 fit the message"
  Frame(message_id: spell_missed.message_id, body:)
}
