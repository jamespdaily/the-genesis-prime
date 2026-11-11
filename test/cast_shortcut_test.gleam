//// The cast rule's shortcut cast (`genesis_prime/game/cast.shortcut`): the player's press of
//// the button an open cast-a-spell objective gave it, on the client's own rows and a clock the
//// test drives. Expected values come from these places:
//// - `opcode.0x9d`: the press names the client's cast id (never 0), the Spell4 id of the
////   shortcut and a target.
//// - `0x14039b340`: the client refuses a press of a spell it holds no shortcut for with result
////   1 (`UnableToCreateSpell`).
//// - `0x14055bdc0`: a spell of targetType 0, 2, 6 or 7 takes the caster, and 1, 3, 5 or 8 the
////   player's target (step B, #728).
//// - Spell4 25306 (Q3915): castTime 2000, Spell4Base 11896... the objective 5197's spell.
//// - Spell4 34448 (row 10349's spell): prerequisiteIdCasterCast 11700, `0x1403ace00`.
//// - Spell4 70503 (row 18165's spell): Spell4Base 47487, castMethod 5 (a client-side
////   interaction), whose answer 0x805 carries the Spell4Base id plus 1 (`opcode.0x805.fields`).
//// - Spell4 30173 (row 6761's spell): targetType 1.

import cast_support as support
import fixture_tables
import genesis_prime/client_connection.{CastStarted}
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/shortcut_spell
import genesis_prime/message/cast_objective_ability.{CastObjectiveAbility}
import genesis_prime/message/cast_result
import genesis_prime/message/client_side_interaction_result.{
  ClientSideInteractionResult,
}
import genesis_prime/message/interaction_result
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_cast_refused
import genesis_prime/step.{LogWarning}
import gleam/list
import gleam/set.{type Set}
import gleam/string
import owned_test

const the_self_spell = 25_306

const the_prerequisite_spell = 34_448

const the_interaction_spell = 70_503

/// Spell4Base 47487 plus 1, the word the client's 0x805 carries for spell 70503.
const the_interaction_word = 47_488

const the_targeted_spell = 30_173

const clients_cast_id = 7

fn shortcuts() -> shortcut_spell.Shortcuts {
  shortcut_spell.shortcuts(tables: fixture_tables.shared())
}

fn press_body(
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
  target target: Int,
) -> BitArray {
  let assert Ok(body) =
    cast_objective_ability.encode(CastObjectiveAbility(
      client_cast_id:,
      spell4_id:,
      target_unit_id: target,
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  body
}

/// The press of the spell by the standing caster, who holds these buttons.
fn press_holding(
  state state: State,
  spell4_id spell4_id: Int,
  held held: Set(Int),
  client_cast_id client_cast_id: Int,
  target target: Int,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
  cast.shortcut(
    cast: state,
    body: press_body(client_cast_id:, spell4_id:, target:),
    caster: support.caster(),
    shortcuts: shortcuts(),
    held:,
    now: support.at(ms:),
  )
}

/// The press of a held spell, which the rule must take.
fn press(
  state state: State,
  spell4_id spell4_id: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    press_holding(
      state:,
      spell4_id:,
      held: set.from_list([spell4_id]),
      client_cast_id: clients_cast_id,
      target: 0,
      at: ms,
    )
    as "a 0x9d that fits the message is taken"
  taken
}

fn flattened(steps steps: List(#(Int, List(Effect)))) -> List(Effect) {
  list.flat_map(steps, fn(step) { step.1 })
}

pub fn a_press_of_a_held_self_spell_casts_on_the_caster_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    press(state: cast.new(), spell4_id: the_self_spell, at: 1000)
  assert support.ids(frames: support.writes(effects: pressed)) == [0x07FD]
    as "opcode.0x9d: the caster is told its cast started"
  let assert [frame] = support.writes(effects: pressed)
  let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
  assert confirmed.client_cast_id == clients_cast_id
    && confirmed.primary_target_unit_id == 7
    as "0x14055bdc0: targetType 0 takes the caster, unit 7, whatever the press names"
  let assert [#(_, news), ..] = support.tells(effects: pressed)
    as "the viewers see the start"
  let assert CastStarted(start: started) = news
  assert started.spell4_id == the_self_spell
    && started.caster_unit_id == 7
    && started.primary_target_unit_id == 7
    as "the viewers see Spell4 25306 cast by the caster on itself"
  assert support.shortcut_casts(effects: pressed) == []
    as "nothing counts at the press: a cast counts when the spell lands"
  let #(_, steps) = support.run_timers(state:, effects: pressed, from_ms: 1000)
  assert list.map(steps, fn(step) { step.0 }) == [3000]
    as "Spell4 25306's castTime is 2000"
  let effects = flattened(steps:)
  assert support.ids(frames: support.writes(effects:)) == [0x07F4, 0x07FE]
    as "the go, then the finish"
  let before_the_count =
    list.take_while(effects, fn(effect) {
      support.shortcut_casts(effects: [effect]) == []
    })
  assert support.ids(frames: support.writes(effects: before_the_count))
    == [0x07F4, 0x07FE]
    as "the go's finish 0x7fe is written before the count its go raises"
  assert support.shortcut_casts(effects:)
    == [cast.ShortcutCast(spell4_id: the_self_spell)]
    as "the go raises ShortcutCast for the spell, once"
}

pub fn a_press_of_a_spell_not_held_is_refused_with_result_1_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(#(state, effects)) =
    press_holding(
      state: cast.new(),
      spell4_id: the_self_spell,
      held: set.new(),
      client_cast_id: clients_cast_id,
      target: 0,
      at: 1000,
    )
    as "a press of a spell not held is refused, not an error"
  let assert [frame] = support.writes(effects:)
    as "a refused press writes one 0x7fc and nothing else"
  let assert Ok(refused) = spell_cast_refused.decode(frame.body)
  assert refused.client_cast_id == clients_cast_id
    && refused.spell4_id == the_self_spell
    && cast_result.to_value(refused.result) == 1
    as "0x14039b340: the client's own refusal of a spell it holds no shortcut for is result 1"
  assert support.tells(effects:) == [] && support.started_timers(effects:) == []
    as "no cast starts"
  assert state == cast.new() as "the state is unchanged"
}

pub fn a_shortcut_press_with_cast_id_0_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  assert press_holding(
      state: cast.new(),
      spell4_id: the_self_spell,
      held: set.from_list([the_self_spell]),
      client_cast_id: 0,
      target: 0,
      at: 1000,
    )
    == Error(cast.NoClientCastId)
    as "opcode.0x9d: the cast id is the client's counter, which never gives 0"
}

pub fn a_cancelled_shortcut_cast_counts_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    press(state: cast.new(), spell4_id: the_self_spell, at: 1000)
  let #(_, left_alone) =
    support.run_timers(state:, effects: pressed, from_ms: 1000)
  assert support.shortcut_casts(effects: flattened(steps: left_alone))
    == [cast.ShortcutCast(spell4_id: the_self_spell)]
    as "the same press left alone counts at its go, so the nothing below is the cancel's"
  let id = support.pressed_id(effects: pressed)
  let assert Ok(#(cancelled, effects)) =
    support.cancelled(
      state:,
      cast_id: id,
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: 1500,
    )
    as "opcode.0x801: 6 with the bit 1 is what the client sends for a cast that ends"
  assert support.shortcut_casts(effects:) == []
    && support.ids(frames: support.writes(effects:)) == [0x07FE]
    as "the cast ends with its finish, and counts nothing"
  let assert [#(timer, _)] = support.started_timers(effects: pressed)
  let #(_, late) = support.fired(state: cancelled, timer:, at: 3000)
  assert support.shortcut_casts(effects: late) == []
    as "the go's timer firing after the cancel raises nothing"
}

pub fn a_shortcut_press_whose_caster_cast_prerequisite_fails_is_refused_151_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, effects) =
    press(state: cast.new(), spell4_id: the_prerequisite_spell, at: 1000)
  assert support.refusal_results(effects:)
    == [cast_result.to_value(cast_result.PrereqCasterCast)]
    as "Spell4 34448's prerequisiteIdCasterCast is Prerequisite 11700, which the caster with no quest fails: 0x1403ace00 refuses with 151"
  assert support.tells(effects:) == [] && support.started_timers(effects:) == []
    as "no cast starts"
}

pub fn a_client_side_interaction_shortcut_cast_counts_after_its_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    press(state: cast.new(), spell4_id: the_interaction_spell, at: 1000)
  assert support.ids(frames: support.writes(effects: pressed)) == [0x07FD]
    as "opcode.0x7fd.csi: the caster is told the start, and no go: the cast waits for the client's answer"
  assert support.started_timers(effects: pressed) == []
    && support.shortcut_casts(effects: pressed) == []
    as "castMethod 5 has no cast time to wait out, and nothing counts yet"
  let id = support.pressed_id(effects: pressed)
  let answer = fn(result) {
    let assert Ok(body) =
      client_side_interaction_result.encode(ClientSideInteractionResult(
        cast_id: id,
        result:,
        spell4_base_id_plus_one: the_interaction_word,
      ))
      as "the answer fits the message"
    let assert Ok(taken) =
      cast.take(
        cast: state,
        message: cast.Answered,
        body:,
        caster: support.caster(),
        plans: support.plans(),
        now: support.at(ms: 1200),
      )
      as "an answer naming the waiting interaction and its spell is taken"
    taken
  }
  let #(answered, asked) = answer(interaction_result.Succeeded)
  // The go asks the picture for the units it strikes; the caster's own cast strikes none.
  let #(_, succeeded) =
    support.answered_with_no_targets(state: answered, effects: asked, at: 1200)
  assert support.ids(frames: support.writes(effects: succeeded))
    == [0x07F4, 0x07FE]
    as "the success answer sends the go, then the finish"
  assert support.shortcut_casts(effects: succeeded)
    == [cast.ShortcutCast(spell4_id: the_interaction_spell)]
    as "the go raises ShortcutCast for the spell, once"
  let #(_, failed) = answer(interaction_result.Failed)
  assert support.shortcut_casts(effects: failed) == []
    && support.ids(frames: support.writes(effects: failed)) == [0x07F9, 0x07FE]
    as "opcode.0x7fe.csi: a failed interaction fails the cast with 0x7f9 and its finish, and counts nothing"
}

pub fn a_press_of_a_held_targeted_spell_is_not_built_yet_test() -> Nil {
  use <- owned_test.run(10_000)
  let press_targeted = fn(state) {
    let assert Ok(taken) =
      press_holding(
        state:,
        spell4_id: the_targeted_spell,
        held: set.from_list([the_targeted_spell]),
        client_cast_id: clients_cast_id,
        target: 5000,
        at: 1000,
      )
      as "the press is taken and refused, not an error"
    taken
  }
  let #(state, first) = press_targeted(cast.new())
  assert support.refusal_results(effects: first)
    == [cast_result.to_value(cast_result.IllegalSpellCast)]
    as "Spell4 30173's Spell4TargetMechanics targetType is 1: it takes the player's target (0x14055bdc0), which the server does not read from the press yet, so the cast is not built"
  assert support.tells(effects: first) == []
    && support.started_timers(effects: first) == []
    as "no cast starts"
  let assert [#(LogWarning, line)] = support.logs(effects: first)
    as "the gap is logged once"
  assert string.contains(line, "30173") && string.contains(line, "#728")
    as "the line names the spell and the issue that will close the gap"
  let #(_, second) = press_targeted(state)
  assert support.logs(effects: second) == []
    && support.refusal_results(effects: second) != []
    as "a second press is refused the same and not logged again"
}
