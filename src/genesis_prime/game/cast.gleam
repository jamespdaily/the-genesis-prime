//// A player's casts, a feature of the game connection's rule
//// (genesis_prime/game/connection) as movement and chat are: the press of an
//// ability on the action bar, the answers the client expects, the cast bar and
//// cooldowns it keeps, the cast's go and finish, the child casts a Proxy effect
//// starts, and the cast's end when the client cancels it. The caster's connection
//// owns its casts and sends every message about them; it tells the connections
//// that see its player the same news, which they write for a cast they know.
////
//// ```
//// client                    connection (this rule)                         viewers' connections
//// 0x9a press ──────────────▶ decode; bag index ─▶ the ability's tree (genesis_prime/game/spell_plan)
////                            a refusal of the client's own checks ──▶ 0x7fc {client id, Spell4 id, result}
////                            accepted: id k = mint(unit, n); the gcd starts
//// ◀── 0x7fd {client id, k, target}                  (the caster's cast starts in its client)
////                            Tell(each viewer, CastStarted)  ──────────────▶ 0x7ff, when its client shows the caster
////                            cast time 0: the go at once; else StartTimer(go)
//// ◀── 0x7f4 {k, phase 0, no target, no effect}  ◀── Tell(each viewer, CastWent) ─▶ 0x7f4, for a cast it wrote
////                            the first go starts the spell's own cooldown
////                            each Proxy of the phase: StartTimer(delay), or at once for delay 0
////                            a child: id k2 = mint, root = the pressed spell, parent = the proxying spell
//// ◀── 0x7ff {k2, ..}        Tell(each viewer, CastStarted) ───────────────▶ 0x7ff
//// ◀── 0x7f4, 0x7fe          its go and finish, as the pressed cast's
//// ◀── 0x7fe {k}             Tell(each viewer, CastFinished) ──────────────▶ 0x7fe, for a cast it wrote
//// 0x801 {k, 6, 1} ─────────▶ the cast ends: its timers cancelled, 0x7fe to the caster and the audience
//// ```
////
//// - **The press** is 0x9a inside 0x038C: the client's cast id, the ability's bag
////   index, the target and the press bit (`opcode.0x9a`). A cast id of 0 is one
////   the client never sends, and ends the connection. A press bit of 0 is the
////   hold-to-cast setting; the press is logged and ignored, since the server
////   builds no hold. A bag index the player does not hold is answered 0x7fc with
////   Spell4 id 0 and result 4 (`0x14039a040`; the server's choice, which the
////   client allows).
//// - **The refusals** are the client's own checks, answered 0x7fc with the
////   client's result and clearing the client's global cooldown: 13 while a cast
////   of the caster is live (`0x1403afb10`); 14 while the global cooldown has more
////   than 500 ms left, for kinds 0 and 2; 15 while the spell's own cooldown has
////   more than 500 ms left (`0x1403b14c0`); for a spell that needs a target
////   (`Spell4TargetMechanics.targetType`; none of the 18 level-1 abilities does):
////   91 with no target, 90 for a target that is no creature the client shows
////   (the server's choice: this step strikes creatures only) and 105 beyond the
////   spell's range plus 1.25 m (`0x1403b0880`; the margin is the server's: how
////   the client measures range is not read); 169 for
////   a spell that needs the weapon when slot 16 holds none (`0x1403afb10`); 51 or
////   55, 50 + the class's resource slot, for a cost the unit cannot pay, since a
////   new unit holds 0 of every resource (`Spell4CastResult.vital_cost`); 285 for
////   a spell that is not Normal (`Spell.CodeEnumCastMethod`, the cast methods of
////   a later step), each logged once on the connection for the coverage
////   measure.
//// - **A spell that needs no target** is cast on the caster: the client makes the
////   caster the target of such a spell before it sends (`Spell4TargetMechanics.targetType`
////   0, 2, 6 and 7), so a 0x9a for it names the caster's own unit
////   or none, and the cast's primary target is the caster whatever the press
////   names; no target check applies. Who the spell strikes is the area its
////   effects name, which a later step reads.
//// - **A press within 500 ms of a cooldown's end** is held: the client queues it
////   (317) and sends it (`0x1403b14c0`), so the server starts it when the
////   cooldown ends, from a timer, and answers nothing before. A second press
////   while one is held is refused 13.
//// - **The cast id** is 2^31 + unit id x 2^11 + n mod 2^11, skipping an id a live
////   cast of the caster holds: unique among the live casts of every unit, since
////   the client keeps one table of casts (`0x140561c30`) and unit ids are below
////   2^20, and never 0. The client's own counter makes no collision: its
////   pending casts live apart (`cast.pending_table`). The caster's id inside the
////   cast's tree is the same mint, for the children.
//// - **The cast bar and cooldowns** are the client's own: 0x7fd and 0x7ff start
////   the caster's global cooldown (`0x14046afc0`, kinds 0 and 1), and a first go
////   starts the spell's own (`0x14046b1e0`), so the server sends no 0x804. The
////   server keeps the same, to refuse what the client would: the global cooldown
////   from the accept for the SpellCoolDown time, the spell's own from the first
////   go, the child casts none (kind 3).
//// - **The go** is 0x7f4 with the cast id, the ignore-cooldown bit 0, the caster's
////   place as the destination, no target, no position and no missile, and the
////   phase (`opcode.0x7f4`): a go that names no target carries no damage, which
////   the next step adds. Each go is followed by the spell's Proxies of that phase,
////   and the finish, 0x7fe, comes after the last go, at once for a spell that is
////   not Multiphase: the client counts the caster as casting until it
////   (`0x1403afb10`).
//// - **A child cast** is the Proxy's spell cast as its own, from the caster, with
////   root the pressed spell and parent the spell whose Proxy fired
////   (`opcode.0x7ff.root_parent`), after the Proxy's delay from the parent's go;
////   its 0x7ff goes to the caster too. Its go and finish follow as a pressed
////   cast's, and it starts no global cooldown (kind 3). A Proxy behind a
////   prerequisite is not started.
//// - **The cancel** is 0x801: the server's cast id, a reason and a bit, which the
////   client sends as (6 or 11, 1) when the player's cast ends in its client, and
////   (0, 0) for a ChargeRelease threshold (`opcode.0x801`). The cast ends with its
////   timers cancelled and 0x7fe to the caster and the audience, no strike; a cast
////   that is not live is no change and a debug line. Any other reason or bit is
////   one the client never sends, and ends the connection.
//// - **The audience** of a cast is the caster's viewers when it starts; its go and
////   finish go to them. A viewer writes a 0x7ff only when its client shows the
////   caster, and a go, or a finish, only for a cast it wrote
////   (genesis_prime/game/connection).
//// - **Timers** are the connection's: this rule starts them with ids from
////   `first_timer`, one for each go, child or held press waiting, and owns the
////   ids from there up (`owns`).
////
//// What happens at each failure point of a cast:
////
//// | Point | What happens |
//// |---|---|
//// | a 0x9a body the client's reader refuses, or a cast id of 0 | the connection ends, nothing written |
//// | a press whose bag index the player does not hold | 0x7fc {client id, 0, 4} |
//// | a refusal of the client's own checks | 0x7fc with the result; nothing else changes |
//// | a press while one is held | 0x7fc 13 |
//// | a 0x801 for a cast that is not live, or one already finished | no change, a debug line |
//// | a 0x801 with a reason and bit the client never sends | the connection ends |
//// | the player camps with a cast live | its timers are cancelled and nothing is written: the viewers' clients drop the cast with the unit |
//// | the caster's connection ends | its timers end with it; the map's `Gone` removes the unit from each viewer, which drops the cast |
//// | a timer fires after its cast ended | not possible: the cast's end cancels it |
//// | a timer fires in a status that holds no player in the world | dropped; the world is left already |
//// | the answer of a store ask comes after a timer's due time | the timer is taken after the answer: the go and finish are late by the ask, never lost |
//// | a viewer is told a go or finish of a cast it did not write | dropped (genesis_prime/game/connection) |
//// | the audience's connection has ended | the tell is dropped by the shell |

import genesis_prime/client_connection.{type News}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/spell_plan.{type Plans, type Proxy, type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/spell_finished.{SpellFinished}
import genesis_prime/message/spell_go.{type SpellGo}
import genesis_prime/message/spell_started.{type SpellStarted}
import genesis_prime/step.{
  type ConnectionId, type LogLevel, type Now, type TimerId, TimerId,
}
import genesis_prime/table/id.{type Item2Id, type Spell4BaseId, type Spell4Id}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/set.{type Set}

/// The messages of a player's casts, which the client sends inside 0x038C
/// (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x009A, the press of an ability.
  Pressed
  /// 0x0801, the client ends one of its player's casts.
  Cancelled
}

/// A unit the caster's client shows, as far as a cast needs: the target of a
/// press is one of its creatures.
pub type Shown {
  /// Another player's unit, which no ability of this step strikes.
  ShownPlayer
  /// A creature, at the place its 0x262 put it.
  ShownCreature(x: Float, y: Float, z: Float)
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
    /// The units the player's client shows.
    shown: Dict(Int, Shown),
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
  /// The child cast of `proxy` starts, in the live cast `parent_cast_id`.
  StartChild(parent_cast_id: Int, proxy: Proxy)
  /// The held press starts.
  StartHeld
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
    timers: List(TimerId),
  )
}

/// A press the client queued within 500 ms of a cooldown's end.
pub type Held {
  Held(client_cast_id: Int, spell: Spell, target: Int, timer: TimerId)
}

/// What the rule keeps for one player: its cooldowns, its live casts and what
/// waits on a timer, and the counters its cast ids and timer ids are made from.
pub opaque type State {
  State(
    /// The monotonic time the global cooldown ends at; 0 for none.
    global_cooldown_ends_ms: Int,
    /// The monotonic time each Spell4's own cooldown ends at.
    cooldown_ends_ms: Dict(Int, Int),
    casts: Dict(Int, Live),
    timers: Dict(Int, Due),
    held: Option(Held),
    /// How many casts the player has started, which the cast ids are made from.
    presses: Int,
    /// How many timers the rule has started, which the timer ids are made from.
    timers_started: Int,
    /// The Spell4 ids already logged as unbuilt on this connection.
    logged: Set(Int),
  )
}

/// The timer id the rule's first timer takes; the connection's own timers are
/// below it.
const first_timer = 1000

/// A player that has cast nothing.
pub fn new() -> State {
  State(
    global_cooldown_ends_ms: 0,
    cooldown_ends_ms: dict.new(),
    casts: dict.new(),
    timers: dict.new(),
    held: option.None,
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
/// number mod 2^11. The caller skips an id a live cast holds.
pub fn cast_id(unit_id unit_id: Int, number number: Int) -> Int {
  unbuilt(inputs: #(unit_id, number))
}

/// The unit a cast id was made for, which is how a viewer finds the casts of a
/// unit it stops showing.
pub fn caster_of(cast_id cast_id: Int) -> Int {
  unbuilt(inputs: cast_id)
}

/// The caster's 0x9a or 0x801, decoded and decided: the new state and what the
/// connection must do, or the refusal that ends the connection. `now` is the
/// time of the input; the plans give each ability's tree.
pub fn take(
  cast cast: State,
  message message: Message,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  unbuilt(inputs: #(cast, message, body, caster, plans, now))
}

/// A timer of the rule fired: a go, a child cast or the held press.
pub fn timer_fired(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  unbuilt(inputs: #(cast, timer, caster, now))
}

/// The player left the world with casts live: every timer is cancelled and
/// nothing is written.
pub fn left(cast cast: State) -> #(State, List(Effect)) {
  #(
    State(..cast, casts: dict.new(), timers: dict.new(), held: option.None),
    list.map(dict.keys(cast.timers), fn(number) {
      CancelTimer(timer: TimerId(number))
    }),
  )
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

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
