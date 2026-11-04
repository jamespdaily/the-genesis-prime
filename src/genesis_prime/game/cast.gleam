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
//// ◀── 0x7fd {client id, k, caster}                  (the caster's cast starts in its client)
////                            Tell(each viewer, CastStarted)  ──────────────▶ 0x7ff, when its client shows the caster
////                            cast time 0: the go at once; else StartTimer(go)
//// ◀── 0x7f4 {k, phase 0, no target, no effect}  ◀── Tell(each viewer, CastWent) ─▶ 0x7f4, for a cast it wrote
////                            the first go starts the spell's own cooldown
////                            each Proxy of the phase: StartTimer(delay), or at once for delay 0
////                            a child: id k2 = mint, root = the pressed spell, parent = the proxying spell
//// ◀── 0x7ff {k2, ..}        Tell(each viewer, CastStarted) ───────────────▶ 0x7ff
//// ◀── 0x7f4, 0x7fe          its go and finish, as the pressed cast's
//// ◀── 0x7fe {k}             Tell(each viewer, CastFinished) ──────────────▶ 0x7fe, for a cast it wrote
//// 0x801 {k, 6, 1} ─────────▶ the cast ends: its timers cancelled, 0x7fe to all
//// ```
////
//// - **The press** is 0x9a inside 0x038C: the client's cast id, the ability's bag
////   index, the target and the press bit (`opcode.0x9a`). A cast id of 0 is one
////   the client never sends, and ends the connection. A press bit of 0 is the
////   hold-to-cast setting; the press is logged and ignored, since the server
////   builds no hold. A bag index the player does not hold is answered 0x7fc with
////   Spell4 id 0 and result 4 (`0x14039a040`; the server's choice, which the
////   client allows).
//// - **The target** of every cast is the caster: no level-1 ability needs a
////   target the client picks (`Spell4TargetMechanics.targetType`: the client makes
////   the caster the target of a spell of kind 0, 2, 6 or 7 before it sends), so
////   the press's target is not read, and the target checks of the client (91, 105)
////   wait for the first ability that needs one. Who a spell strikes is the area its
////   effects name, which a later step reads.
//// - **The refusals** are the client's own checks, answered 0x7fc with the
////   client's result and clearing the client's global cooldown: 13 while the
////   caster's current cast is live (below); 14 while the global cooldown has more
////   than 500 ms left, for kinds 0 and 2; 15 while the spell's own cooldown has
////   more than 500 ms left (`0x1403b14c0`); 169 for a spell that needs the weapon
////   when slot 16 holds none (`0x1403afb10`); 51 or 55, 50 + the class's resource
////   slot, for a cost the unit cannot pay, since a new unit holds 0 of every
////   resource (`Spell4CastResult.vital_cost`); and 285 for a spell that is not
////   Normal (`Spell.CodeEnumCastMethod`, the cast methods of a later step), each
////   logged once on the connection for the coverage measure.
//// - **The current cast** is the client's: a cast with a cast time and a cast bar
////   is the caster's current cast from its start until its go (a Normal cast) or
////   its finish (a Multiphase one), and a 0x801 clears it; the client refuses a
////   press with 13 only against it, and not when its spell is free while live or
////   the pressed spell ignores casting (`cast.current_cast`,
////   `Spell4.propertyFlags`, `0x1403afb10`). A cast with no cast bar, such as
////   Stagger's Multiphase child, never blocks a press. The server keeps the same
////   in `current`.
//// - **A press within 500 ms of a cooldown's end** is held: the client queues it
////   (317) and sends it (`0x1403b14c0`), so the server starts it when the
////   cooldown ends, from a timer, and answers nothing before. A second press
////   while one is held is refused 13 (the server's choice).
//// - **The cast id** is 2^31 + unit id x 2^11 + n mod 2^11, skipping an id a live
////   cast of the caster holds: unique among the live casts of every unit, since
////   the client keeps one table of casts (`0x140561c30`) and unit ids are below
////   2^20, and never 0. The client's own counter makes no collision: its
////   pending casts live apart (`cast.pending_table`). A child takes the next id.
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
////   not Multiphase.
//// - **A child cast** is the Proxy's spell cast as its own, from the caster, with
////   root the pressed spell and parent the spell whose Proxy fired
////   (`opcode.0x7ff.root_parent`), after the Proxy's delay from the parent's go;
////   its 0x7ff goes to the caster too. Its go and finish follow as a pressed
////   cast's, and it starts no global cooldown (kind 3). A Proxy behind a
////   prerequisite is not started. A child's timer is its own: the parent's finish
////   leaves the pending children, which start 100 ms after it (Crush), and only
////   the player leaving the world cancels them.
//// - **The cancel** is 0x801: the server's cast id, a reason and a bit, which the
////   client sends as (6 or 11, 1) when the player's cast ends in its client, and
////   (0, 0) for a ChargeRelease threshold (`opcode.0x801`). The cast ends with its
////   go timers cancelled and 0x7fe to the caster and the audience, no strike; a
////   cast that is not live is no change and a debug line. Any other reason or bit
////   is one the client never sends, and ends the connection.
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
//// | a parent cast finishes with a child's timer pending | the child starts when its timer fires, with the root and parent it was made with |
//// | the player camps with casts or children pending | every timer is cancelled and nothing is written: the viewers' clients drop the cast with the unit (the connection writes each viewer's 0x7fe before its 0x355) |
//// | the caster's connection ends | its timers end with it; the map's `Gone` removes the unit from each viewer, which finishes its casts first |
//// | a timer fires after its cast ended | a go finds no live cast and does nothing; the cast's end cancels its go timers |
//// | a timer fires in a status that holds no player in the world | dropped; the world is left already |
//// | the answer of a store ask comes after a timer's due time | the timer is taken after the answer: the go and finish are late by the ask, never lost |
//// | a viewer is told a go or finish of a cast it did not write | dropped (genesis_prime/game/connection) |
//// | the audience's connection has ended | the tell is dropped by the shell |

import genesis_prime/client_connection.{type News}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/spell_plan.{type Plans, type Proxy, type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/cancel_cast
import genesis_prime/message/cast_ability
import genesis_prime/message/cast_result
import genesis_prime/message/float32
import genesis_prime/message/spell_cast_confirmed.{SpellCastConfirmed}
import genesis_prime/message/spell_cast_refused.{SpellCastRefused}
import genesis_prime/message/spell_finished.{SpellFinished}
import genesis_prime/message/spell_go.{type SpellGo, SpellGo}
import genesis_prime/message/spell_position.{type SpellPosition, SpellPosition}
import genesis_prime/message/spell_started.{type SpellStarted, SpellStarted}
import genesis_prime/step.{
  type ConnectionId, type LogLevel, type Now, type TimerId, ConnectionId,
  LogDebug, LogInfo, LogWarning, TimerId,
}
import genesis_prime/table/id.{type Item2Id, type Spell4BaseId, type Spell4Id}
import gleam/bool
import gleam/dict.{type Dict}
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
    /// The timers of its gos still waiting.
    timers: List(TimerId),
  )
}

/// A press the client queued within 500 ms of a cooldown's end.
pub type Held {
  Held(client_cast_id: Int, spell: Spell)
}

/// What the rule keeps for one player: its cooldowns, its live casts and what
/// waits on a timer, and the counters its cast ids and timer ids are made from.
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
    timers: dict.new(),
    held: None,
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
  case message {
    Pressed -> pressed(cast:, body:, caster:, plans:, now:)
    Cancelled -> cancelled(cast:, body:)
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
          text: "a press with the press bit 0 is the hold-to-cast setting, which is not built",
        ),
      ]),
    ),
  )
  let held_spell =
    list.drop(caster.abilities, press.bag_index)
    |> list.first
    |> result.try(fn(base) { spell_plan.in_plans(plans:, base:) })
  case held_spell {
    Error(Nil) ->
      Ok(
        #(cast, [
          refused(
            client_cast_id: press.client_cast_id,
            spell4_id: 0,
            result: cast_result.SpellUnknown,
          ),
        ]),
      )
    Ok(spell) ->
      Ok(press_of(
        cast:,
        caster:,
        now_ms: now.monotonic_ms,
        client_cast_id: press.client_cast_id,
        spell:,
      ))
  }
}

/// What a press of a spell comes to: the client's refusal, a held press or a
/// cast that starts.
fn press_of(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  spell spell: Spell,
) -> #(State, List(Effect)) {
  case verdict(cast:, caster:, spell:, now_ms:) {
    Accept ->
      start(
        cast:,
        caster:,
        now_ms:,
        spell:,
        root: spell.spell4_id,
        parent: None,
        client_cast_id: Some(client_cast_id),
      )
    Refuse(result:) -> #(cast, [
      refused(client_cast_id:, spell4_id: spell.spell4_id.value, result:),
    ])
    NotBuilt ->
      case set.contains(cast.logged, spell.spell4_id.value) {
        True -> #(cast, [
          refused(
            client_cast_id:,
            spell4_id: spell.spell4_id.value,
            result: cast_result.IllegalSpellCast,
          ),
        ])
        False -> #(
          State(..cast, logged: set.insert(cast.logged, spell.spell4_id.value)),
          [
            Log(
              level: LogWarning,
              text: "the ability with Spell4 "
                <> int.to_string(spell.spell4_id.value)
                <> " is not cast by the Normal method, which is not built: it is refused with 285",
            ),
            refused(
              client_cast_id:,
              spell4_id: spell.spell4_id.value,
              result: cast_result.IllegalSpellCast,
            ),
          ],
        )
      }
    Hold(wait_ms:) -> {
      let #(cast, timer) = new_timer(cast:)
      #(
        State(
          ..cast,
          timers: dict.insert(cast.timers, number_of(timer:), StartHeld),
          held: Some(Held(client_cast_id:, spell:)),
        ),
        [StartTimer(timer:, after_ms: wait_ms)],
      )
    }
  }
}

/// What the client's checks make of a press, in its order: the caster's (a press
/// held already, the weapon, the current cast), the cost, then the cooldowns.
type Verdict {
  Accept
  Refuse(result: cast_result.CastResult)
  /// The press is within the queue window of a cooldown's end.
  Hold(wait_ms: Int)
  /// The spell is not cast by the Normal method.
  NotBuilt
}

fn verdict(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> Verdict {
  use <- bool.guard(
    when: option.is_some(cast.held),
    return: Refuse(result: cast_result.SpellAlreadyCasting),
  )
  use <- bool.guard(when: spell.method != spell_plan.Normal, return: NotBuilt)
  use <- bool.guard(
    when: lacks_the_weapon(spell:, caster:),
    return: Refuse(result: cast_result.WeaponSlot),
  )
  use <- bool.guard(
    when: casting(cast) && !spell.ignores_casting,
    return: Refuse(result: cast_result.SpellAlreadyCasting),
  )
  use <- bool.guard(
    when: option.is_some(spell.unpayable_cost),
    return: Refuse(
      result: cast_result.from_value(option.unwrap(spell.unpayable_cost, 0)),
    ),
  )
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
  case global_left > queue_window_ms, own_left > queue_window_ms {
    True, _ -> Refuse(result: cast_result.SpellGlobalCooldown)
    False, True -> Refuse(result: cast_result.SpellCooldown)
    False, False ->
      case int.max(global_left, own_left) {
        0 -> Accept
        wait_ms -> Hold(wait_ms:)
      }
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

fn cancelled(
  cast cast: State,
  body body: BitArray,
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
  case dict.get(cast.casts, cancel.cast_id) {
    Error(Nil) ->
      Ok(
        #(cast, [
          Log(
            level: LogDebug,
            text: "the client ended the cast "
              <> int.to_string(cancel.cast_id)
              <> ", which is not live",
          ),
        ]),
      )
    Ok(live) -> {
      let waiting =
        list.filter(live.timers, fn(timer) {
          dict.has_key(cast.timers, number_of(timer:))
        })
      let cast =
        State(
          ..cast,
          timers: list.fold(waiting, cast.timers, fn(timers, timer) {
            dict.delete(timers, number_of(timer:))
          }),
        )
      let #(cast, finished) = finish(cast:, cast_id: cancel.cast_id, live:)
      Ok(#(
        cast,
        list.append(
          list.map(waiting, fn(timer) { CancelTimer(timer:) }),
          finished,
        ),
      ))
    }
  }
}

/// A timer of the rule fired: a go, a child cast or the held press.
pub fn timer_fired(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  case dict.get(cast.timers, number_of(timer:)) {
    Error(Nil) -> #(cast, [])
    Ok(due) -> {
      let cast =
        State(..cast, timers: dict.delete(cast.timers, number_of(timer:)))
      let now_ms = now.monotonic_ms
      case due {
        Go(cast_id:, phase:) -> go(cast:, caster:, now_ms:, cast_id:, phase:)
        StartChild(root:, parent:, proxy:, ..) ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell: proxy.spell,
            root:,
            parent: Some(parent),
            client_cast_id: None,
          )
        StartHeld ->
          case cast.held {
            None -> #(cast, [])
            Some(Held(client_cast_id:, spell:)) ->
              press_of(
                cast: State(..cast, held: None),
                caster:,
                now_ms:,
                client_cast_id:,
                spell:,
              )
          }
      }
    }
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
      current: None,
    ),
    list.map(dict.keys(cast.timers), fn(number) {
      CancelTimer(timer: TimerId(number))
    }),
  )
}

/// A cast of the spell starts: its id, the start written to the caster (0x7fd for
/// a press, 0x7ff for a child) and told to the audience, the global cooldown, the
/// timer of each later go, and the first go at once when it has no wait.
fn start(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  spell spell: Spell,
  root root: Spell4Id,
  parent parent: Option(Spell4Id),
  client_cast_id client_cast_id: Option(Int),
) -> #(State, List(Effect)) {
  let id =
    mint(
      unit_id: caster.unit_id,
      number: cast.presses,
      live: dict.keys(cast.casts),
    )
  let audience = caster.audience
  let go_times = spell_plan.go_times_ms(spell:)
  let #(cast, timers, timer_effects) =
    list.index_fold(go_times, #(cast, [], []), fn(so_far, wait_ms, phase) {
      let #(cast, timers, effects) = so_far
      case wait_ms > 0 {
        False -> so_far
        True -> {
          let #(cast, timer) = new_timer(cast:)
          #(
            State(
              ..cast,
              timers: dict.insert(
                cast.timers,
                number_of(timer:),
                Go(cast_id: id, phase:),
              ),
            ),
            [timer, ..timers],
            list.append(effects, [StartTimer(timer:, after_ms: wait_ms)]),
          )
        }
      }
    })
  let start_message = started_message(id:, spell:, root:, parent:, caster:)
  let live =
    Live(
      spell:,
      root:,
      parent:,
      primary_target: caster.unit_id,
      audience:,
      gone: 0,
      timers: list.reverse(timers),
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
      current: case spell.cast_bar {
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
    list.map(sorted(audience), fn(viewer) {
      Tell(
        to: viewer,
        news: client_connection.CastStarted(start: start_message),
      )
    })
  let opening = [Send(frame: to_caster), ..list.append(told, timer_effects)]
  case go_times {
    [0, ..] -> {
      let #(cast, going) = go(cast:, caster:, now_ms:, cast_id: id, phase: 0)
      #(cast, list.append(opening, going))
    }
    _ -> #(cast, opening)
  }
}

/// The go of phase `phase` of a live cast: 0x7f4 to the caster and the audience,
/// the spell's own cooldown at its first go, the current cast cleared at the go
/// of a Normal cast, the Proxies of the phase, and the finish after the last go.
/// A cast that is not live has no go.
fn go(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  phase phase: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(live) -> {
      let spell = live.spell
      let go_message = go_message(cast_id:, phase:, caster:)
      let going = [
        Send(frame: went_frame(go: go_message)),
        ..list.map(sorted(live.audience), fn(viewer) {
          Tell(to: viewer, news: client_connection.CastWent(go: go_message))
        })
      ]
      let running =
        dict.get(cast.cooldown_ends_ms, spell.spell4_id.value)
        |> result.map(fn(ends_ms) { ends_ms > now_ms })
        |> result.unwrap(False)
      let cooldown_ends_ms = case
        live.gone == 0 && spell.cooldown_ms > 0 && !running
      {
        True ->
          dict.insert(
            cast.cooldown_ends_ms,
            spell.spell4_id.value,
            now_ms + spell.cooldown_ms,
          )
        False -> cast.cooldown_ends_ms
      }
      let current = case spell.method == spell_plan.Normal {
        True ->
          case
            live.parent == None
            && spell.cast_bar
            || cast.current == Some(cast_id)
          {
            True -> None
            False -> cast.current
          }
        False -> cast.current
      }
      let live = Live(..live, gone: live.gone + 1)
      let cast =
        State(
          ..cast,
          cooldown_ends_ms:,
          current:,
          casts: dict.insert(cast.casts, cast_id, live),
        )
      let #(cast, children) =
        list.fold(
          spell_plan.proxies_in_phase(spell:, phase:),
          #(cast, []),
          fn(so_far, proxy) {
            let #(cast, effects) = so_far
            let #(cast, more) = child(cast:, caster:, now_ms:, live:, proxy:)
            #(cast, list.append(effects, more))
          },
        )
      let #(cast, finished) = case
        live.gone == list.length(spell_plan.go_times_ms(spell:))
      {
        True -> finish(cast:, cast_id:, live:)
        False -> #(cast, [])
      }
      #(cast, list.flatten([going, children, finished]))
    }
  }
}

/// A Proxy of a go: the child starts at once for no delay, else after it from a
/// timer of its own; a Proxy behind a prerequisite is not started.
fn child(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  live live: Live,
  proxy proxy: Proxy,
) -> #(State, List(Effect)) {
  case proxy.condition {
    spell_plan.NeedsPrerequisite(..) -> #(cast, [
      Log(
        level: LogDebug,
        text: "the Proxy to Spell4 "
          <> int.to_string(proxy.spell.spell4_id.value)
          <> " applies only behind a prerequisite, which is not checked, so it is not started",
      ),
    ])
    spell_plan.Always ->
      case proxy.delay_ms > 0 {
        False ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell: proxy.spell,
            root: live.root,
            parent: Some(live.spell.spell4_id),
            client_cast_id: None,
          )
        True -> {
          let #(cast, timer) = new_timer(cast:)
          #(
            State(
              ..cast,
              timers: dict.insert(
                cast.timers,
                number_of(timer:),
                StartChild(
                  root: live.root,
                  parent: live.spell.spell4_id,
                  primary_target: live.primary_target,
                  proxy:,
                ),
              ),
            ),
            [StartTimer(timer:, after_ms: proxy.delay_ms)],
          )
        }
      }
  }
}

/// A live cast ends: 0x7fe to the caster and the audience, and the cast is no
/// longer live nor the caster's current cast.
fn finish(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
) -> #(State, List(Effect)) {
  #(
    State(
      ..cast,
      casts: dict.delete(cast.casts, cast_id),
      current: case cast.current == Some(cast_id) {
        True -> None
        False -> cast.current
      },
    ),
    [
      Send(frame: finished_frame(cast_id:)),
      ..list.map(sorted(live.audience), fn(viewer) {
        Tell(to: viewer, news: client_connection.CastFinished(cast_id:))
      })
    ],
  )
}

/// The next timer's id, and the state counting it.
fn new_timer(cast cast: State) -> #(State, TimerId) {
  #(
    State(..cast, timers_started: cast.timers_started + 1),
    TimerId(first_timer + cast.timers_started),
  )
}

fn number_of(timer timer: TimerId) -> Int {
  let TimerId(number) = timer
  number
}

fn sorted(audience: Set(ConnectionId)) -> List(ConnectionId) {
  list.sort(set.to_list(audience), fn(first, second) {
    let ConnectionId(first) = first
    let ConnectionId(second) = second
    int.compare(first, second)
  })
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
    primary_target_unit_id: caster.unit_id,
    position: position_of(place: caster.place),
    yaw: yaw_of(place: caster.place),
    initial_positions: [],
    telegraph_positions: [],
    field_12: 1,
    field_13: 0,
  )
}

/// 0x7f4 for a go with no target, no position and no missile
/// (`opcode.0x7f4`, `spell.empty_lists`).
fn go_message(
  cast_id cast_id: Int,
  phase phase: Int,
  caster caster: Caster,
) -> SpellGo {
  SpellGo(
    cast_id:,
    ignore_cooldown: 0,
    destination: position_of(place: caster.place),
    targets: [],
    initial_positions: [],
    telegraph_positions: [],
    missiles: [],
    phase:,
  )
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
