//// A player's casts as a pure rule (`genesis_prime/game/cast`): what a 0x9a is
//// answered with, what the cast tells the players who see the caster, its go and
//// finish on a clock the test drives, its child casts, its cooldowns and the
//// client's 0x801. Expected values come from the client's facts, each named at the
//// assertion: `opcode.0x9a`, `opcode.0x7fc`, `opcode.0x7fd`, `opcode.0x7ff`,
//// `opcode.0x7ff.root_parent`, `opcode.0x7f4`, `opcode.0x7fe`, `opcode.0x801`,
//// `0x14039a040`, `0x1403afb10`, `0x1403b14c0`, `0x1403b0880`, `0x14046afc0`,
//// `0x14046b1e0`, `0x140561c30`, `cast.pending_table`, `Spell4CastResult.vital_cost`,
//// `Spell.CodeEnumCastMethod`, `Spell4TargetMechanics.targetType` and the `Spell4.*`
//// records of the abilities (`cast_support` names each value it sets). The rules the
//// client does not settle are the design's choices, each marked as one: the
//// 1.25 m margin of the range check, the refusals 4 and 13 for a bag index not held
//// and a second held press, 90 for a target that is no creature, and the gos of a
//// Multiphase spell at the running sums of its phase delays.

import cast_support as support
import genesis_prime/client_connection.{CastFinished, CastStarted, CastWent}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/spell_plan
import genesis_prime/message/cast_result.{
  CasterCannotBeDead, IllegalSpellCast, Other, SpellAlreadyCasting,
  SpellCancelled, SpellCooldown, SpellGlobalCooldown, SpellUnknown, WeaponSlot,
}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_cast_refused.{SpellCastRefused}
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started.{type SpellStarted}
import genesis_prime/step.{ConnectionId, LogDebug}
import gleam/bool
import gleam/list
import gleam/option.{None}
import gleam/result
import owned_test
import qcheck

const first_server_id = 2_147_483_648

fn refusal(frame: Frame) -> spell_cast_refused.SpellCastRefused {
  assert frame.message_id == 0x07FC
  let assert Ok(refused) = spell_cast_refused.decode(frame.body)
    as "0x7fc decodes"
  refused
}

fn started_of(frame: Frame) -> SpellStarted {
  assert frame.message_id == 0x07FF
  let assert Ok(started) = spell_started.decode(frame.body) as "0x7ff decodes"
  started
}

/// The refusal a press at the time gets, from a state that has done the steps given.
fn refused_with(
  state state: cast.State,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> spell_cast_refused.SpellCastRefused {
  let #(_, effects) = support.pressed(state:, bag_index:, target:, at: ms)
  let assert [frame] = support.writes(effects:)
    as "a refused press writes one 0x7fc and nothing else"
  assert support.tells(effects:) == [] && support.started_timers(effects:) == []
  refusal(frame)
}

pub fn a_0x9a_with_client_cast_id_0_ends_the_connection_and_a_press_bit_of_0_is_logged_and_ignored_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast.take(
      cast: cast.new(),
      message: cast.Pressed,
      body: support.press_body(
        client_cast_id: 0,
        bag_index: 3,
        target: 0,
        press: 1,
      ),
      caster: support.caster(),
      plans: support.plans(),
      now: support.at(ms: 1000),
    )
    == Error(cast.NoClientCastId)
    as "opcode.0x9a: the cast id is the client's counter, never 0"
  let assert Ok(#(_, effects)) =
    cast.take(
      cast: cast.new(),
      message: cast.Pressed,
      body: support.press_body(
        client_cast_id: 9,
        bag_index: 3,
        target: 0,
        press: 0,
      ),
      caster: support.caster(),
      plans: support.plans(),
      now: support.at(ms: 1000),
    )
    as "a press bit of 0 is the hold-to-cast setting, not a refusal"
  assert support.writes(effects:) == [] && support.tells(effects:) == []
    as "ignored: nothing is written or told"
  assert list.length(effects) == 1 as "and one log line says so"
}

pub fn a_bag_index_the_player_does_not_hold_is_refused_with_spell_id_0_and_result_4_test() -> Nil {
  use <- owned_test.run(5000)
  assert refused_with(state: cast.new(), bag_index: 99, target: 0, at: 1000)
    == SpellCastRefused(client_cast_id: 9, spell4_id: 0, result: SpellUnknown)
    as "0x14039a040 gives 4 (SpellUnknown) for a bag index past the bag: the server's choice, which the client allows"
}

pub fn a_press_while_a_cast_is_live_is_refused_13_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: 1000)
  assert refused_with(state:, bag_index: 3, target: 0, at: 1500)
    == SpellCastRefused(
      client_cast_id: 9,
      spell4_id: 58_591,
      result: SpellAlreadyCasting,
    )
    as "0x1403afb10: 13 while the caster's current cast is live; Telekinetic Strike's 1250 ms cast is"
}

pub fn a_press_with_more_than_500_ms_of_the_global_cooldown_left_is_refused_14_for_kinds_0_and_2_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 5, target: 0, at: 1000)
  assert refused_with(state:, bag_index: 10, target: 0, at: 1100).result
    == SpellGlobalCooldown
    as "Gate (kind 1, SpellCoolDown 155: 750 ms) started the global cooldown at the accept; 650 ms is left, and a kind 2 spell is refused while it runs (0x1403b14c0)"
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 5, target: 0, at: 1000)
  assert refused_with(state:, bag_index: 0, target: 0, at: 1100).result
    == SpellGlobalCooldown
    as "kind 0 (Telekinetic Strike) is refused while it runs too"
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 3, target: 0, at: 1000)
  let #(_, effects) =
    support.pressed(state:, bag_index: 10, target: 0, at: 1100)
  assert accepted(effects:)
    as "Kick has kind 3, which starts no global cooldown (0x14046afc0)"
}

pub fn a_press_with_more_than_500_ms_of_its_own_cooldown_left_is_refused_15_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 3, target: 0, at: 1000)
  assert refused_with(state:, bag_index: 3, target: 0, at: 10_000)
    == SpellCastRefused(
      client_cast_id: 9,
      spell4_id: 58_591,
      result: SpellCooldown,
    )
    as "Spell4.58591: a cooldown of 20 s, started by the go at 1000, has 11 s left at 10000"
}

pub fn a_press_during_staggers_child_with_no_cast_bar_is_accepted_and_one_during_a_cast_bar_is_refused_13_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    support.pressed(state: cast.new(), bag_index: 4, target: 0, at: 1000)
  let assert [_, ..] = support.started_timers(effects:)
    as "Stagger's child 38780 is a Multiphase spell with phases to come, so it is live for 700 ms"
  let #(_, effects) = support.pressed(state:, bag_index: 3, target: 0, at: 1100)
  assert accepted(effects:)
    as "0x14053dd00: only a spell with a cast bar is the unit's current cast, and Spell4Base 23162 has castBarType 0 and no cast time, so 13 is not given while it is live (0x1403afb10)"
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: 1000)
  assert refused_with(state:, bag_index: 3, target: 0, at: 1100).result
    == SpellAlreadyCasting
    as "a press during Telekinetic Strike's cast bar is refused 13"
  assert refused_with(state:, bag_index: 3, target: 0, at: 1700).result
    == SpellAlreadyCasting
    as "with 550 ms of the cast left, more than the queue window of 500: refused 13, the server's choice (cast.press_queue: the client never refuses an ability press with 13)"
}

pub fn a_0x801_clears_the_current_cast_whatever_cast_it_names_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: 1000)
  let assert Ok(#(state, _)) =
    cast.take(
      cast: state,
      message: cast.Cancelled,
      body: support.cancel_body(
        cast_id: 2_147_483_648,
        reason: SpellCancelled,
        bit: 1,
      ),
      caster: support.caster(),
      plans: support.plans(),
      now: support.at(ms: 1100),
    )
    as "a cancel of an id that is no live cast of the caster is accepted"
  let #(_, effects) = support.pressed(state:, bag_index: 3, target: 0, at: 1200)
  assert accepted(effects:)
    as "cast.current_cast: the client clears the player's current cast before every 0x801 it sends, whatever cast that is, so Telekinetic Strike no longer counts as casting"
}

pub fn a_live_cast_whose_spell_lets_a_press_through_does_not_block_it_and_the_go_of_a_normal_cast_frees_the_caster_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 8, target: 0, at: 1000)
  let #(_, effects) = support.pressed(state:, bag_index: 3, target: 0, at: 1100)
  assert accepted(effects:)
    as "0x1403afb10: a live cast with the spell flags 0x20, 8 or 4 gives no 13 (a planted spell with a cast bar and the flag)"
  let #(state, effects) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: 1000)
  let #(state, _) = support.run_timers(state:, effects:, from_ms: 1000)
  let #(_, effects) = support.pressed(state:, bag_index: 3, target: 0, at: 2300)
  assert accepted(effects:)
    as "0x14053e5a0: the go of a Normal cast clears the current cast, and its finish follows at once"
}

fn refusal_result(frame: Frame) -> cast_result.CastResult {
  refusal(frame).result
}

pub fn a_spell_that_needs_the_weapon_is_refused_169_when_slot_16_holds_none_test() -> Nil {
  use <- owned_test.run(5000)
  let unarmed = cast.Caster(..support.caster(), weapon: None)
  let #(_, effects) =
    support.pressed_by(
      state: cast.new(),
      caster: unarmed,
      bag_index: 9,
      target: 0,
      at: 1000,
    )
  assert list.map(support.writes(effects:), refusal_result) == [WeaponSlot]
    as "0x1403afb10: weapon slot 1 (Zap) needs an item in slot 16"
  let #(_, effects) =
    support.pressed_by(
      state: cast.new(),
      caster: unarmed,
      bag_index: 3,
      target: 0,
      at: 1000,
    )
  assert accepted(effects:)
    as "Kick needs no weapon (Spell4Base 38017: weaponSlot 0)"
}

pub fn a_press_that_lacks_the_weapon_and_meets_a_live_cast_is_refused_13_not_169_test() -> Nil {
  use <- owned_test.run(5000)
  let unarmed = cast.Caster(..support.caster(), weapon: None)
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: 1000)
  let #(_, effects) =
    support.pressed_by(
      state:,
      caster: unarmed,
      bag_index: 7,
      target: 0,
      at: 1100,
    )
  assert list.map(support.writes(effects:), refusal_result)
    == [SpellAlreadyCasting]
    as "0x1403afb10 checks the current cast (line 87) before the weapon (line 689), so Electrocute (weapon slot 1, propertyFlags 0x4000042: no casting exemption) is refused 13 during Telekinetic Strike's cast"
}

pub fn with_500_ms_or_less_of_a_cooldown_left_the_press_is_held_and_starts_when_it_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 5, target: 0, at: 1000)
  let #(state, effects) =
    support.pressed(state:, bag_index: 10, target: 0, at: 1300)
  assert support.writes(effects:) == [] && support.tells(effects:) == []
    as "0x1403b14c0: 450 ms of the global cooldown is within the queue window, so the client sent the press and the server answers nothing yet"
  let assert [#(timer, after_ms)] = support.started_timers(effects:)
  assert after_ms == 450
    as "the held press starts when the cooldown ends: 1000 + 750 - 1300"
  assert refused_with(state:, bag_index: 3, target: 0, at: 1400).result
    == SpellAlreadyCasting
    as "a second press while one is held is refused 13 (the design's choice)"
  let #(_, effects) = support.fired(state:, timer:, at: 1750)
  assert accepted(effects:) as "the held press is accepted when its timer fires"
}

pub fn an_accepted_press_answers_0x7fd_to_the_caster_and_tells_0x7ff_with_root_own_id_and_parent_0_to_each_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    support.pressed(state: cast.new(), bag_index: 8, target: 40, at: 1000)
  let assert [frame] = support.writes(effects:)
  assert frame.message_id == 0x07FD
  let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
    as "0x7fd decodes"
  assert confirmed.client_cast_id == 9
    as "opcode.0x7fd: the client's id comes back"
  assert confirmed.primary_target_unit_id == 7
    as "Spell4TargetMechanics.targetType: the caster is the target of a spell that needs none, whatever the press names (target 40)"
  assert confirmed.initial_positions == []
    && confirmed.telegraph_positions == []
    as "spell.empty_lists"
  assert confirmed.server_cast_id >= first_server_id
    && cast.caster_of(cast_id: confirmed.server_cast_id) == 7
    as "the id is the caster's own mint: 2^31 and the unit's number above it"
  let assert [
    #(ConnectionId(2), CastStarted(start: first)),
    #(ConnectionId(3), CastStarted(start: second)),
  ] = support.tells(effects:)
    as "each viewer is told the start, in connection order"
  assert first == second
  assert first.cast_id == confirmed.server_cast_id
  assert first.spell4_id == 1
    && first.root_spell4_id == 1
    && first.parent_spell4_id == 0
    as "opcode.0x7ff.root_parent: the pressed spell is its own root and has no parent"
  assert first.caster_unit_id == 7 && first.primary_target_unit_id == 7
  assert first.field_6 == 0 && first.field_12 == 1 && first.field_13 == 0
    as "opcode.0x7ff.caster_item_level, opcode.0x7ff.own_cast and opcode.0x7ff.activate: 0, 1 and 0"
  assert first.initial_positions == [] && first.telegraph_positions == []
}

/// The server id 0x7fd gave the pressed cast.
fn pressed_id_of(effects effects: List(cast.Effect)) -> Int {
  let assert [confirmed, ..] = support.writes(effects:)
    as "a press writes its 0x7fd first"
  cast_id_of(confirmed)
}

/// What the client is sent and each viewer told of each cast, by the cast's id:
/// the messages in order.
fn per_cast(effects: List(cast.Effect)) -> List(#(Int, List(Int))) {
  let frames =
    list.map(support.writes(effects:), fn(frame) {
      #(cast_id_of(frame), frame.message_id)
    })
  let ids = list.unique(list.map(frames, fn(pair) { pair.0 }))
  list.map(ids, fn(id) {
    #(
      id,
      list.filter_map(frames, fn(pair) {
        case pair.0 == id {
          True -> Ok(pair.1)
          False -> Error(Nil)
        }
      }),
    )
  })
}

fn cast_id_of(frame: Frame) -> Int {
  case frame.message_id {
    0x07FF -> started_of(frame).cast_id
    0x07FD -> {
      let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
      confirmed.server_cast_id
    }
    0x07F4 -> {
      let assert Ok(go) = spell_go.decode(frame.body)
      go.cast_id
    }
    _ -> support.finished_cast_id(frame)
  }
}

pub fn each_start_gets_one_go_then_one_finish_to_the_caster_and_the_audience_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, pressed) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: 1000)
  let #(_, fired) = support.run_timers(state:, effects: pressed, from_ms: 1000)
  let effects = list.append(pressed, list.flat_map(fired, fn(step) { step.1 }))
  list.each(per_cast(effects), fn(sent) {
    assert list.filter(sent.1, fn(id) { id == 0x07F4 }) |> list.length == 1
      as "opcode.0x7f4: one go for each cast of a spell that is not Multiphase"
    assert list.last(sent.1) == Ok(0x07FE)
      as "opcode.0x7fe: the finish comes after the go"
  })
  let told = support.tells(effects:)
  list.each([ConnectionId(2), ConnectionId(3)], fn(viewer) {
    let kinds =
      list.filter_map(told, fn(pair) {
        case pair.0 == viewer {
          True ->
            Ok(case pair.1 {
              CastStarted(..) -> "start"
              CastWent(..) -> "go"
              CastFinished(..) -> "finish"
              client_connection.Appeared(..)
              | client_connection.CreatureAppeared(..)
              | client_connection.Moving(..)
              | client_connection.Health(..)
              | client_connection.Died
              | client_connection.CastMissed(..)
              | client_connection.CastTargetsRemoved(..)
              | client_connection.CastStackRemoved(..)
              | client_connection.Removed
              | client_connection.CreatureMoved(..)
              | client_connection.CreaturePlaced(..)
              | client_connection.Targeting(..)
              | client_connection.Threat(..)
              | client_connection.CombatState(..)
              | client_connection.CameBack
              | client_connection.DeathLogged
              | client_connection.CameBackLogged
              | client_connection.Shield(..)
              | client_connection.CrowdControlApplied(..)
              | client_connection.CrowdControlEnded(..)
              | client_connection.InterruptArmor(..) -> "other"
            })
          False -> Error(Nil)
        }
      })
    assert list.filter(kinds, fn(kind) { kind == "go" }) |> list.length
      == list.filter(kinds, fn(kind) { kind == "start" }) |> list.length
      && list.filter(kinds, fn(kind) { kind == "finish" }) |> list.length
      == list.filter(kinds, fn(kind) { kind == "start" }) |> list.length
      as "each viewer is told one go and one finish for each start (opcode.0x7fe, 0x140561c30)"
  })
}

pub fn cast_ids_are_above_2_pow_31_hold_the_unit_and_never_repeat_among_one_units_numbers_test() -> Nil {
  use <- owned_test.run(10_000)
  assert cast.cast_id(unit_id: 7, number: 0) == 2_147_497_984
    as "2^31 + 7 x 2^11 + 0 (the design's mint)"
  assert cast.cast_id(unit_id: 7, number: 2049) == 2_147_497_985
    as "the number counts mod 2^11"
  assert cast.caster_of(cast_id: 2_147_483_648 + 7 * 2048 + 5) == 7
    as "2^31 + 7 x 2^11 + n names unit 7 for every n below 2^11"
  assert cast.caster_of(cast_id: 2_147_483_648 + 1_048_575 * 2048 + 2047)
    == 1_048_575
    as "the highest unit and number: the id is still below 2^32"
  assert cast.mint(unit_id: 7, number: 0, live: [
      cast.cast_id(unit_id: 7, number: 0),
    ])
    == 2_147_497_985
    as "a live id is skipped: the next number's"
  assert cast.mint(unit_id: 7, number: 2048, live: [
      cast.cast_id(unit_id: 7, number: 0),
    ])
    == 2_147_497_985
    as "number 2048 is 0 mod 2^11, which a live cast holds, so the mint skips to 1"
  use #(unit_id, number, live_numbers) <- qcheck.given(qcheck.tuple3(
    qcheck.bounded_int(from: 1, to: 1_048_575),
    qcheck.bounded_int(from: 0, to: 100_000),
    qcheck.generic_list(
      qcheck.bounded_int(from: 0, to: 4096),
      qcheck.bounded_int(from: 0, to: 6),
    ),
  ))
  let live =
    list.map(live_numbers, fn(live_number) {
      cast.cast_id(unit_id:, number: live_number)
    })
  let minted = cast.mint(unit_id:, number:, live:)
  assert !list.contains(live, minted)
    as "the id of a new cast is none a live cast of the caster holds (0x140561c30: the client's table of casts keys by id)"
  assert cast.caster_of(cast_id: minted) == unit_id
  let id = cast.cast_id(unit_id:, number:)
  assert id >= first_server_id && id < 4_294_967_296
    as "never 0 and 32 bits (opcode.0x7ff: the cast id is 32 bits, 0 makes only a stray pending cast)"
  assert cast.caster_of(cast_id: id) == unit_id
    as "the id names its caster, so no two units' casts share one (0x140561c30: one table for every unit)"
  assert cast.cast_id(unit_id:, number: number + 1) != id
    as "the next number is another id"
}

pub fn telekinetic_strike_goes_1250_ms_after_the_accept_then_finishes_and_its_child_starts_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let foe = [cast.Hit(unit_id: 10, descriptions: [], controls: [])]
  let #(state, effects) =
    support.pressed_striking(
      state: cast.new(),
      bag_index: 0,
      struck: foe,
      at: 1000,
    )
  let assert [#(_, 1250)] = support.started_timers(effects:)
    as "Spell4.32893: castTime 1250, the go's timer"
  let #(_, fired) =
    support.run_timers_striking(state:, effects:, from_ms: 1000, struck: foe)
  let assert [#(2250, step)] = fired
    as "the go, its child and the finish come from the one timer, 1250 ms after the accept"
  assert ids_of(effects: step) == [0x07F4, 0x07FF, 0x07F4, 0x07FE, 0x07FE]
    as "the go of 32893, the start, go and finish of the child 30900 (Spell4Effects.effectType.26: a Proxy starts its spell as its own cast), then the finish of 32893"
  let assert [go_frame, child_frame, ..] = support.writes(effects: step)
  let assert Ok(go) = spell_go.decode(go_frame.body)
  assert list.map(go.targets, fn(target) { #(target.unit_id, target.flags) })
    == [#(10, 0)]
    && go.phase == 0
    && go.ignore_cooldown == 0
    as "opcode.0x7f4: the go names the one struck unit, target flags 0"
  let child = started_of(child_frame)
  assert child.spell4_id == 30_900
    && child.root_spell4_id == 32_893
    && child.parent_spell4_id == 32_893
    as "opcode.0x7ff.root_parent: root the pressed spell, parent the spell whose Proxy fired"
  assert child.caster_unit_id == 7 && child.primary_target_unit_id == 10
    as "Spell4Effects 62204 has targetFlags 4 in the client's table, so its Proxy starts 30900 on each struck unit (an earlier decode read 1: the tooltip says the caster gains the Psi Point, which the live sitting checks)"
  assert child.cast_id != go.cast_id
    && cast.caster_of(cast_id: child.cast_id) == 7
}

pub fn crush_starts_42297_100_ms_after_its_go_with_root_crush_and_parent_crush_test() -> Nil {
  use <- owned_test.run(5000)
  let foe = [cast.Hit(unit_id: 10, descriptions: [], controls: [])]
  let #(state, effects) =
    support.pressed_striking(
      state: cast.new(),
      bag_index: 1,
      struck: foe,
      at: 1000,
    )
  assert ids_of(effects:) == [0x07FD, 0x07F4, 0x07FE]
    as "Spell4.32812: instant, so the go and finish come at the accept"
  let assert [#(100, _)] =
    list.map(support.started_timers(effects:), fn(t) { #(t.1, t.0) })
    as "Spell4.32812: the Proxy's delayTime is 100, and its one foe is struck"
  let #(_, fired) =
    support.run_timers_striking(state:, effects:, from_ms: 1000, struck: foe)
  let assert [#(1100, step)] = fired
  let assert [child_frame, ..] = support.writes(effects: step)
  let child = started_of(child_frame)
  assert child.spell4_id == 42_297
    && child.root_spell4_id == 32_812
    && child.parent_spell4_id == 32_812
  assert ids_of(effects: step) == [0x07FF, 0x07F4, 0x07FE]
    as "the child's start (to the caster too), go and finish"
}

pub fn stagger_starts_38780_whose_four_phase_gos_each_start_38781_with_root_38791_and_parent_38780_test() -> Nil {
  use <- owned_test.run(5000)
  let foe = [cast.Hit(unit_id: 10, descriptions: [], controls: [])]
  let #(state, effects) =
    support.pressed_striking(
      state: cast.new(),
      bag_index: 4,
      struck: foe,
      at: 1000,
    )
  let assert [multiphase_frame] =
    list.filter(support.writes(effects:), fn(frame) {
      frame.message_id == 0x07FF
    })
    as "Stagger's go is followed by one start, of its Proxy 38780"
  let multiphase = started_of(multiphase_frame)
  assert multiphase.spell4_id == 38_780
    && multiphase.root_spell4_id == 38_791
    && multiphase.parent_spell4_id == 38_791
    as "Spell4.38791: the Proxy starts the Multiphase spell 38780"
  let #(_, fired) =
    support.run_timers_striking(state:, effects:, from_ms: 1000, struck: foe)
  let phase_gos =
    list.flat_map(fired, fn(step) {
      list.filter_map(support.writes(effects: step.1), fn(frame) {
        phase_of(frame:, cast_id: multiphase.cast_id, at_ms: step.0 - 1000)
      })
    })
  assert phase_gos == [#(166, 0), #(366, 1), #(533, 2), #(700, 3)]
    as "SpellPhase 3717 to 3720: delays of 166, 200, 167 and 167 ms, each the gap after the phase before: the client sums the delays into a cast's duration when its castTime is 0 (0x14053d1f0) and schedules no phase itself, so the go times are the server's choice"
  let children =
    list.flat_map(fired, fn(step) {
      list.filter_map(support.writes(effects: step.1), fn(frame) {
        case frame.message_id == 0x07FF {
          True -> Ok(started_of(frame))
          False -> Error(Nil)
        }
      })
    })
  assert list.length(children) == 4
    as "one 38781 for each phase (Spell4Effects 83823 to 83826: phaseFlags 1, 2, 4, 8)"
  list.each(children, fn(child) {
    assert child.spell4_id == 38_781
      && child.root_spell4_id == 38_791
      && child.parent_spell4_id == 38_780
      as "opcode.0x7ff.root_parent: root 38791, parent 38780"
  })
  let assert Ok(last) = list.last(fired)
  assert list.last(ids_of(effects: last.1)) == Ok(0x07FE)
    as "38780's finish comes after its last phase"
  let every_start =
    list.append(
      list.filter_map(support.writes(effects:), fn(frame) {
        case frame.message_id == 0x07FF {
          True -> Ok(started_of(frame).cast_id)
          False -> Error(Nil)
        }
      }),
      list.map(children, fn(child) { child.cast_id }),
    )
  assert list.length(list.unique([pressed_id_of(effects:), ..every_start])) == 6
    as "Stagger, 38780 and the four 38781 are six casts of one caster, each with an id of its own (0x140561c30: one table for every unit)"
}

pub fn gate_casts_starts_its_cooldown_and_sends_no_target_in_any_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    support.pressed(state: cast.new(), bag_index: 5, target: 0, at: 1000)
  let gos =
    list.filter_map(support.writes(effects:), fn(frame) {
      case frame.message_id == 0x07F4 {
        True -> {
          let assert Ok(go) = spell_go.decode(frame.body)
          Ok(go.targets)
        }
        False -> Error(Nil)
      }
    })
  assert gos != [] && list.all(gos, fn(targets) { targets == [] })
    as "Spell4.34355: Gate deals no damage and this step strikes nothing: every go names no target"
  assert list.map(support.started_timers(effects:), fn(started) { started.1 })
    == [200, 140]
    as "Spell4Effects 67778 and 67779: the Proxies to 25190 and 30436 start 200 and 140 ms after the go"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  let children =
    list.flat_map(fired, fn(step) {
      list.filter_map(support.writes(effects: step.1), fn(frame) {
        case frame.message_id == 0x07FF {
          True -> Ok(started_of(frame).spell4_id)
          False -> Error(Nil)
        }
      })
    })
  assert children == [30_436, 25_190]
    as "the 140 ms Proxy (30436) starts before the 200 ms one (25190)"
  assert refused_with(state:, bag_index: 5, target: 0, at: 10_000).result
    == SpellCooldown
    as "Spell4.34355: a cooldown of 30 s from the go"
}

pub fn the_spells_own_cooldown_runs_from_its_first_go_not_from_the_accept_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    support.pressed(state: cast.new(), bag_index: 11, target: 0, at: 1000)
  let #(state, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  let assert [#(2000, _)] = fired
    as "the planted slow spell's go is 1000 ms after the accept"
  assert refused_with(state:, bag_index: 11, target: 0, at: 6000).result
    == SpellCooldown
    as "5000 ms from the go at 2000 ends at 7000; from the accept it would have ended at 6000 (0x14046b1e0: cooldowns start at a Normal cast's first go)"
  let #(_, held) = support.pressed(state:, bag_index: 11, target: 0, at: 6600)
  assert support.writes(effects: held) == []
    && list.map(support.started_timers(effects: held), fn(t) { t.1 }) == [400]
    as "400 ms left is within the queue window: held until 7000"
}

pub fn a_non_normal_ability_is_refused_285_and_logged_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    support.pressed(
      state: cast.new(),
      bag_index: support.unbuilt_bag_index,
      target: 0,
      at: 1000,
    )
  assert list.map(support.writes(effects: first), refusal_result)
    == [IllegalSpellCast]
    as "Spell.CodeEnumCastMethod: a PressHold spell is not cast by a method the rule builds, and 285 is what the design gives it"
  let logs = fn(effects) {
    list.filter(effects, fn(effect) {
      case effect {
        cast.Log(..) -> True
        cast.Send(..)
        | cast.Tell(..)
        | cast.StartTimer(..)
        | cast.CancelTimer(..)
        | cast.Strike(..)
        | cast.Pay(..)
        | cast.Gain(..) -> False
      }
    })
  }
  assert list.length(logs(first)) == 1 as "logged for the coverage measure"
  let #(_, second) =
    support.pressed(
      state:,
      bag_index: support.unbuilt_bag_index,
      target: 0,
      at: 2000,
    )
  assert logs(second) == [] as "once on the connection, not for each press"
}

pub fn a_press_at_a_negative_monotonic_time_meets_no_cooldown_that_never_started_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: -5000)
  assert accepted(effects:)
    as "the monotonic clock can be negative (step.Now), so no cooldown is running for a spell never cast"
  let #(state, _) =
    support.pressed(state: cast.new(), bag_index: 5, target: 0, at: -5000)
  assert refused_with(state:, bag_index: 10, target: 0, at: -4900).result
    == SpellGlobalCooldown
    as "and one that started is still counted from its start: 650 ms of Gate's 750 ms are left"
}

pub fn a_0x801_ends_that_cast_with_its_timers_cancelled_and_0x7fe_to_all_and_no_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, pressed) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: 1000)
  let assert [#(go_timer, _)] = support.started_timers(effects: pressed)
  let assert [frame, ..] = support.writes(effects: pressed)
  let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
  let id = confirmed.server_cast_id
  let cancel = fn(state, reason, bit) {
    cast.take(
      cast: state,
      message: cast.Cancelled,
      body: support.cancel_body(cast_id: id, reason:, bit:),
      caster: support.caster(),
      plans: support.plans(),
      now: support.at(ms: 1500),
    )
  }
  let assert Ok(#(after, effects)) = cancel(state, SpellCancelled, 1)
    as "opcode.0x801: the client sends 6 and the bit 1 when the player's cast ends"
  assert support.cancelled_timers(effects:) == [go_timer]
  assert ids_of(effects:) == [0x07FE]
  assert list.map(support.tells(effects:), fn(pair) { pair.0 })
    == [ConnectionId(2), ConnectionId(3)]
  assert list.all(support.tells(effects:), fn(pair) {
    pair.1 == CastFinished(cast_id: id)
  })
    as "the audience is told the finish; no go and no strike"
  let #(_, again) =
    support.pressed(state: after, bag_index: 3, target: 0, at: 1600)
  assert accepted(effects: again)
    as "the cast is over, so the caster no longer counts as casting"
  let assert Ok(#(_, same)) = cancel(after, SpellCancelled, 1)
    as "a cast that is not live is no change"
  assert support.writes(effects: same) == []
    && support.tells(effects: same) == []
  assert is_one_debug_line(same) as "and a debug line"
  let assert Ok(#(_, threshold)) = cancel(state, Other(0), 0)
    as "(0, 0) is the ChargeRelease threshold's cancel, which the client sends with the threshold's value (opcode.0x801)"
  assert support.writes(effects: threshold) == []
    && support.cancelled_timers(effects: threshold) == []
  assert is_one_debug_line(threshold)
    as "(0, 0) names a threshold that is not open (the cast is Telekinetic Strike's), so the cancel is no change and a debug line"
  assert cancel(state, Other(11), 1) |> result.is_ok
    as "reason 11 (SpellInterrupted) with the bit 1 is sent by the input mode change"
  assert cancel(state, SpellAlreadyCasting, 1)
    == Error(cast.UnknownCancel(reason: 13, bit: 1))
    as "any other reason ends the connection"
  assert cancel(state, SpellCancelled, 0)
    == Error(cast.UnknownCancel(reason: 6, bit: 0))
    as "reason 6 is sent with the bit 1 only"
}

/// Whether the press was taken: its first write is the 0x7fd.
fn accepted(effects effects: List(cast.Effect)) -> Bool {
  list.first(ids_of(effects:)) == Ok(0x07FD)
}

fn is_one_debug_line(effects: List(cast.Effect)) -> Bool {
  case effects {
    [cast.Log(level: LogDebug, ..)] -> True
    _ -> False
  }
}

/// The time and phase of a go of the cast, from a frame of its step.
fn phase_of(
  frame frame: Frame,
  cast_id cast_id: Int,
  at_ms at_ms: Int,
) -> Result(#(Int, Int), Nil) {
  use <- bool.guard(when: frame.message_id != 0x07F4, return: Error(Nil))
  let assert Ok(go) = spell_go.decode(frame.body) as "0x7f4 decodes"
  case go.cast_id == cast_id {
    True -> Ok(#(at_ms, go.phase))
    False -> Error(Nil)
  }
}

fn ids_of(effects effects: List(cast.Effect)) -> List(Int) {
  support.ids(frames: support.writes(effects:))
}

pub fn the_player_leaving_the_world_cancels_every_timer_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, pressed) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: 1000)
  let assert [#(go_timer, _)] = support.started_timers(effects: pressed)
  let #(_, effects) = cast.left(cast: state)
  assert support.cancelled_timers(effects:) == [go_timer]
  assert support.writes(effects:) == [] && support.tells(effects:) == []
    as "the viewers' connections write each cast's 0x7fe before the unit's 0x355 (genesis_prime/game/connection)"
}

// ------------------------------------------- a dead caster
//
// Expected values come from the design of step G and its shape review: the
// client checks a press against the spell's caster condition row
// (`Spell4.spell4ConditionsIdCaster`, Spell4Conditions bit 0) and refuses a dead
// caster's press of a spell whose row has the dead bit with 57
// Caster_CannotBeDead; a living caster's press of one that must be cast dead is
// refused 58 Caster_MustBeDead; any other press is cast as for the living
// (`cast.dead_player`). Telekinetic Strike's row is caster condition 43 (mask
// 1249, value 0: the dead bit). A player that dies ends its own casts with 0x7fe
// to every player told their start (the Design's sequence, "A player dies" 3).

/// The tests' caster, dead.
fn dead_caster() -> cast.Caster {
  cast.Caster(..support.caster(), dead: True)
}

pub fn a_dead_casters_casts_end_with_their_timers_cancelled_and_0x7fe_to_the_caster_and_its_audience_test() -> Nil {
  use <- owned_test.run(5000)
  // Telekinetic Strike goes 1250 ms after the accept, so its go waits on a timer.
  let #(state, pressed) =
    support.pressed(state: cast.new(), bag_index: 0, target: 0, at: 1000)
  let assert [#(go_timer, _)] = support.started_timers(effects: pressed)
  let assert [frame, ..] = support.writes(effects: pressed)
  let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
  let id = confirmed.server_cast_id
  let #(after, effects) = cast.died(cast: state, now: support.at(ms: 1500))
  assert support.cancelled_timers(effects:) == [go_timer]
    as "the waiting go is cancelled: no go and no strike"
  assert ids_of(effects:) == [0x07FE] as "0x7fe to the caster's own client"
  assert support.tells(effects:)
    == [
      #(ConnectionId(2), CastFinished(cast_id: id)),
      #(ConnectionId(3), CastFinished(cast_id: id)),
    ]
    as "and to every viewer told the cast's start"
  let #(_, again) =
    support.pressed(state: after, bag_index: 3, target: 0, at: 1600)
  assert accepted(effects: again) as "no cast is live after the death"
}

pub fn a_dead_casters_press_of_a_spell_that_cannot_be_cast_dead_is_refused_57_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(#(after, effects)) =
    cast.take(
      cast: cast.new(),
      message: cast.Pressed,
      body: support.press_body(
        client_cast_id: 9,
        bag_index: 0,
        target: 0,
        press: 1,
      ),
      caster: dead_caster(),
      plans: support.plans(),
      now: support.at(ms: 1000),
    )
  let assert [frame] = support.writes(effects:)
    as "a refused press writes one 0x7fc and nothing else"
  assert refusal(frame).result == CasterCannotBeDead
    as "57 Caster_CannotBeDead: Telekinetic Strike's caster row has the dead bit"
  assert support.tells(effects:) == []
    && support.started_timers(effects:) == []
    && after == cast.new()
    as "the state is unchanged"
}

pub fn a_dead_casters_press_of_a_spell_without_the_dead_bit_is_cast_as_for_the_living_test() -> Nil {
  use <- owned_test.run(5000)
  // Caster condition 4 (mask 0) has no dead bit: the client sends such a press
  // while dead, and the server judges it as for the living.
  let plans =
    support.with_spells(plans: support.plans(), spells: [
      spell_plan.Spell(
        ..support.ability(base: 19_102),
        caster_death: spell_plan.AliveOrDead,
      ),
    ])
  let dead =
    support.pressed_in(
      plans:,
      state: cast.new(),
      caster: dead_caster(),
      bag_index: 0,
      target: 0,
      at: 1000,
    )
  let living =
    support.pressed_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: 0,
      target: 0,
      at: 1000,
    )
  assert accepted(effects: dead.1) && dead == living
    as "the press is cast, step for step as the living's"
}

pub fn a_living_casters_press_of_a_spell_that_must_be_cast_dead_is_refused_58_test() -> Nil {
  use <- owned_test.run(5000)
  // The value bit 1 of the dead bit asks the caster to be dead, as for Spell4
  // 2643 and 39624 (`Spell4.spell4ConditionsIdCaster`).
  let plans =
    support.with_spells(plans: support.plans(), spells: [
      spell_plan.Spell(
        ..support.ability(base: 19_102),
        caster_death: spell_plan.MustBeDead,
      ),
    ])
  let #(after, effects) =
    support.pressed_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: 0,
      target: 0,
      at: 1000,
    )
  let assert [frame] = support.writes(effects:)
  assert refusal(frame).result == Other(58) as "58 Caster_MustBeDead"
  assert after == cast.new()
}
