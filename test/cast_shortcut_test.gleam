//// The cast rule's shortcut cast (`genesis_prime/game/cast.shortcut`): the player's press of
//// the button an open cast-a-spell objective gave it, on the client's own rows and a clock the
//// test drives. Expected values come from these places:
//// - `opcode.0x9d`: the press names the client's cast id (never 0), the Spell4 id of the
////   shortcut and a target.
//// - `0x14039b340`: the client refuses a press of a spell it holds no shortcut for with result
////   1 (`UnableToCreateSpell`).
//// - `0x14055bdc0`: a spell of targetType 0, 2, 6 or 7 takes the caster, and 1, 3, 5 or 8 the
////   player's target.
//// - `opcode.0x9d.target_checks`, `CheckCast 0x1403ae8c0`, `CheckCastAndPrerequisites
////   0x1403ace00`, `CheckCastActivateSpell 0x1403b44b0`, `CheckCastUnitTargetRange
////   0x1403b2240`: what the client tests of a unit a press names, in its order: 91 for no
////   unit, 32 for the caster, 106 and 107, 108, 102, 89, the range (104, 105), then the
////   caster's and the target's cast conditions (151, 281).
//// - Spell4 25306 (Q3915): castTime 2000, Spell4Base 11896... the objective 5197's spell.
//// - Spell4 34448 (row 10349's spell): prerequisiteIdCasterCast 11700, `0x1403ace00`.
//// - Spell4 70503 (row 18165's spell): Spell4Base 47487, castMethod 5 (a client-side
////   interaction), whose answer 0x805 carries the Spell4Base id plus 1 (`opcode.0x805.fields`).
//// - Spell4 30173 (row 6761's spell): targetType 1, a CC state 9 the plans cannot hold.

import cast_support as support
import client_tables
import fixture_tables
import genesis_prime/client_connection.{CastStarted}
import genesis_prime/game/activate.{type Target, Body, Usable}
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/shortcut_spell
import genesis_prime/game/shown
import genesis_prime/game/start_place
import genesis_prime/message/cast_objective_ability.{CastObjectiveAbility}
import genesis_prime/message/cast_result
import genesis_prime/message/client_side_interaction_result.{
  ClientSideInteractionResult,
}
import genesis_prime/message/crowd_control_state.{type CrowdControlState, Stun}
import genesis_prime/message/interaction_result
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_cast_refused
import genesis_prime/step.{LogWarning}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/item_special
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4
import genesis_prime/world_map/creature_life.{Attackable, Hostile}
import genesis_prime/world_map/creature_path
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleam/string
import owned_test
import place_support
import planted_table.{Integer}
import unitest

const the_self_spell = 25_306

const the_prerequisite_spell = 34_448

const the_interaction_spell = 70_503

/// Spell4Base 47487 plus 1, the word the client's 0x805 carries for spell 70503.
const the_interaction_word = 47_488

const clients_cast_id = 7

/// The caster's own unit id (`support.caster`).
const the_caster = 7

const the_hologram_spell = 42_735

/// The edge of a creature's body, whatever it is: the gap tests below are edge to edge.
const creature_radius = 1.0

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

/// A creature the caster's client shows: its unit id, its Creature2 row, its faction and how
/// far its edge stands from the caster's edge, to the east.
type Unit {
  Unit(
    unit_id: Int,
    creature_id: Int,
    faction_id: Int,
    gap: Float,
    alive: Bool,
    in_combat: Bool,
    /// The crowd-control states the caster's client was told the creature holds.
    held: List(CrowdControlState),
  )
}

/// What the caster's client shows: creatures and other players, by unit id.
type Scene {
  Scene(units: List(Unit), players: List(Int))
}

fn nothing_shown() -> Scene {
  Scene(units: [], players: [])
}

fn unit(id unit_id: Int, of creature_id: Int, at gap: Float) -> Unit {
  Unit(
    unit_id:,
    creature_id:,
    faction_id: 0,
    gap:,
    alive: True,
    in_combat: False,
    held: [],
  )
}

fn place_of(unit unit: Unit) -> start_place.Place {
  let live = place_support.live_character_place()
  place_support.at(
    world_id: 3460,
    world_zone_id: 6009,
    x: start_place.x(live)
      +. place_support.player_hit_radius
      +. creature_radius
      +. unit.gap,
    y: start_place.y(live),
    z: start_place.z(live),
  )
}

fn picture_of(scene scene: Scene) -> shown.Picture {
  list.map(scene.units, fn(unit) {
    #(
      unit.unit_id,
      shown.ShownCreature(
        creature_id: Creature2Id(unit.creature_id),
        faction_id: unit.faction_id,
        checklist_index: 0,
        path: creature_path.Standing(at: place_of(unit:)),
        life: 100,
        alive: unit.alive,
        hit_radius: creature_radius,
        attackable: Attackable(exile: True, dominion: True),
        hostile_to: Hostile(exile: False, dominion: False),
        in_combat: unit.in_combat,
        held: list.map(unit.held, fn(state) {
          shown.HeldState(state:, instance_id: 1)
        }),
      ),
    )
  })
  |> list.append(list.map(scene.players, fn(id) { #(id, shown.ShownPlayer) }))
  |> dict.from_list
}

/// What the unit is to the caster, as the connection reads it from the picture.
fn target_of(scene scene: Scene) -> fn(Int) -> Target {
  fn(unit_id) {
    case list.contains(scene.players, unit_id) {
      True -> activate.AnotherPlayer
      False ->
        case list.find(scene.units, fn(unit) { unit.unit_id == unit_id }) {
          Error(Nil) -> activate.Unseen
          Ok(unit) -> {
            let assert Ok(row) =
              creature2.get(
                tables: fixture_tables.shared(),
                id: Creature2Id(unit.creature_id),
              )
              as "the creature is a root of the fixture"
            Usable(
              creature_id: unit.creature_id,
              creature: activate.creature_of(row:),
              checklist_index: 0,
              link: activate.NoLink,
              body: Body(place: place_of(unit:), radius: creature_radius),
              alive: unit.alive,
              in_combat: unit.in_combat,
              held: unit.held,
              withheld: None,
            )
          }
        }
    }
  }
}

/// The press of the spell by the standing caster, who holds these buttons and sees this
/// scene.
fn press_in(
  shortcuts shortcuts: shortcut_spell.Shortcuts,
  scene scene: Scene,
  state state: State,
  spell4_id spell4_id: Int,
  held held: Set(Int),
  client_cast_id client_cast_id: Int,
  target target: Int,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
  let picture = picture_of(scene:)
  cast.shortcut(
    cast: state,
    body: press_body(client_cast_id:, spell4_id:, target:),
    caster: support.caster(),
    shortcuts:,
    held:,
    activations: activate.activations(tables: fixture_tables.shared()),
    target_of: target_of(scene:),
    in_cast_group: fn(group, unit_id) {
      shown.in_group(
        tables: fixture_tables.shared(),
        picture:,
        group:,
        unit_id:,
      )
    },
    caster_radius: place_support.player_hit_radius,
    now: support.at(ms:),
  )
}

fn press_holding(
  state state: State,
  spell4_id spell4_id: Int,
  held held: Set(Int),
  client_cast_id client_cast_id: Int,
  target target: Int,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
  press_in(
    shortcuts: shortcuts(),
    scene: nothing_shown(),
    state:,
    spell4_id:,
    held:,
    client_cast_id:,
    target:,
    at: ms,
  )
}

/// The press, at a unit, of a held spell, which the rule must take whatever it answers.
fn press_at(
  scene scene: Scene,
  state state: State,
  spell4_id spell4_id: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  press_at_with(
    shortcuts: shortcuts(),
    scene:,
    state:,
    spell4_id:,
    target:,
    at: ms,
  )
}

/// The same, for the shortcuts of these tables.
fn press_at_with(
  shortcuts shortcuts: shortcut_spell.Shortcuts,
  scene scene: Scene,
  state state: State,
  spell4_id spell4_id: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    press_in(
      shortcuts:,
      scene:,
      state:,
      spell4_id:,
      held: set.from_list([spell4_id]),
      client_cast_id: clients_cast_id,
      target:,
      at: ms,
    )
    as "a 0x9d that fits the message is taken, started or refused"
  taken
}

/// Every effect of a press played out on a clock the test drives: the press's, then each
/// timer's in turn, with each go striking nobody. Returns the time each timer fired at.
fn played(
  state state: State,
  pressed pressed: List(Effect),
  at ms: Int,
) -> #(List(Int), List(Effect)) {
  let #(state, started) =
    support.answered_with_no_targets(state:, effects: pressed, at: ms)
  let #(_, steps) = support.run_timers(state:, effects: started, from_ms: ms)
  #(
    list.map(steps, fn(step) { step.0 }),
    list.append(started, flattened(steps:)),
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
    == [cast.ShortcutCast(spell4_id: the_self_spell, target: None)]
    as "the go raises ShortcutCast for the spell, once, with no unit: it was cast on the caster"
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
    == [cast.ShortcutCast(spell4_id: the_self_spell, target: None)]
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
    == [cast.ShortcutCast(spell4_id: the_interaction_spell, target: None)]
    as "the go raises ShortcutCast for the spell, once"
  let #(_, failed) = answer(interaction_result.Failed)
  assert support.shortcut_casts(effects: failed) == []
    && support.ids(frames: support.writes(effects: failed)) == [0x07F9, 0x07FE]
    as "opcode.0x7fe.csi: a failed interaction fails the cast with 0x7f9 and its finish, and counts nothing"
}

/// The primary target unit of each 0x7fd the effects write.
fn confirmed_targets(effects effects: List(Effect)) -> List(Int) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id == 0x07FD {
      True -> {
        let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
          as "a 0x7fd the rule wrote decodes"
        Ok(confirmed.primary_target_unit_id)
      }
      False -> Error(Nil)
    }
  })
}

fn warnings(effects effects: List(Effect)) -> List(String) {
  list.filter_map(support.logs(effects:), fn(line) {
    case line {
      #(LogWarning, text) -> Ok(text)
      _ -> Error(Nil)
    }
  })
}

/// What a press at `target` answers with a unit shown: the refusal results, from a fresh
/// state.
fn refused_at(
  scene scene: Scene,
  spell4_id spell4_id: Int,
  target target: Int,
) -> List(Int) {
  let #(_, effects) =
    press_at(scene:, state: cast.new(), spell4_id:, target:, at: 1000)
  assert support.tells(effects:) == [] && support.started_timers(effects:) == []
    as "a refused press starts no cast"
  support.refusal_results(effects:)
}

fn code(result: cast_result.CastResult) -> Int {
  cast_result.to_value(result)
}

pub fn a_press_of_a_targeted_spell_at_a_cast_group_unit_starts_on_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 900, of: 41_604, at: 10.0)])
  let #(state, pressed) =
    press_at(
      scene:,
      state: cast.new(),
      spell4_id: the_hologram_spell,
      target: 900,
      at: 1000,
    )
  assert support.refusal_results(effects: pressed) == []
    && support.ids(frames: support.writes(effects: pressed)) == [0x07FD]
    as "Spell4 42735 (Spell4Base 26923: cast group 5506 holds Creature2 41604, range 15) at a unit 10 m off passes every check, and the caster is told its cast started"
  assert confirmed_targets(effects: pressed) == [900]
    as "0x14055bdc0: targetType 1 takes the unit the press names"
  let assert [#(_, news), ..] = support.tells(effects: pressed)
    as "the viewers see the start"
  let assert CastStarted(start: started) = news
  assert started.spell4_id == the_hologram_spell
    && started.caster_unit_id == the_caster
    && started.primary_target_unit_id == 900
    as "the viewers see the cast by the caster on the unit"
  let #(_, effects) = played(state:, pressed:, at: 1000)
  assert support.ids(frames: support.writes(effects:))
    == [0x07FD, 0x07F4, 0x07FE]
    as "Spell4 42735 has castTime 0: the start, the go, then the finish"
  assert support.shortcut_casts(effects:)
    == [
      cast.ShortcutCast(
        spell4_id: the_hologram_spell,
        target: Some(cast.PressedAt(unit_id: 900, alive_at_press: True)),
      ),
    ]
    as "the go raises ShortcutCast with the unit the press named, alive"
}

pub fn a_targeted_press_with_no_target_is_refused_91_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 900, of: 41_604, at: 10.0)])
  assert refused_at(scene:, spell4_id: the_hologram_spell, target: 0)
    == [code(cast_result.NoTarget)]
    as "CheckCast 0x1403ae8c0: a press that names no unit is refused 91 (CasterMustHaveTarget is 31, TargetUnknown 90)"
}

pub fn a_targeted_press_at_a_unit_not_shown_is_refused_91_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 900, of: 41_604, at: 10.0)])
  assert refused_at(scene:, spell4_id: the_hologram_spell, target: 901)
    == [code(cast_result.NoTarget)]
    as "a unit the caster's client does not show is refused 91 too"
}

pub fn a_targeted_press_at_the_caster_itself_is_refused_32_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 900, of: 41_604, at: 10.0)])
  assert refused_at(scene:, spell4_id: the_hologram_spell, target: the_caster)
    == [code(cast_result.CasterCannotBePrimaryTarget)]
    as "Spell4TargetMechanics 3's flags are 16, without value 2: the caster cannot be its own primary target (32)"
}

pub fn a_targeted_press_at_a_unit_outside_the_cast_group_is_refused_89_test() -> Nil {
  use <- owned_test.run(10_000)
  let near =
    Scene(..nothing_shown(), units: [unit(id: 902, of: 32_668, at: 10.0)])
  assert refused_at(scene: near, spell4_id: the_hologram_spell, target: 902)
    == [code(cast_result.TargetGroup)]
    as "TargetGroup 5506 holds Creature2 41604, 41609, 41611 and 41613, not 32668"
  let far =
    Scene(..nothing_shown(), units: [unit(id: 902, of: 32_668, at: 40.0)])
  assert refused_at(scene: far, spell4_id: the_hologram_spell, target: 902)
    == [code(cast_result.TargetGroup)]
    as "the cast group is tested before the range, so 40 m off is 89 too, not 105"
}

pub fn with_no_cast_group_a_creature_only_its_own_spells_may_target_test() -> Nil {
  use <- owned_test.run(10_000)
  let own =
    Scene(..nothing_shown(), units: [unit(id: 903, of: 39_073, at: 10.0)])
  let #(_, started) =
    press_at(
      scene: own,
      state: cast.new(),
      spell4_id: 41_218,
      target: 903,
      at: 1000,
    )
  assert support.refusal_results(effects: started) == []
    && confirmed_targets(effects: started) == [903]
    as "Spell4 41218 has no cast group and is Creature2 39073's activate spell (Creature2.spell4IdActivate00): it is taken"
  let other =
    Scene(..nothing_shown(), units: [unit(id: 904, of: 8047, at: 10.0)])
  assert refused_at(scene: other, spell4_id: 41_218, target: 904)
    == [code(cast_result.TargetGroup)]
    as "Creature2 8047's flags bit 0 allows a cast only by its own activate spell (5725): 41218 is refused 89"
  let plain =
    Scene(..nothing_shown(), units: [unit(id: 905, of: 30_233, at: 3.0)])
  let #(_, free) =
    press_at(
      scene: plain,
      state: cast.new(),
      spell4_id: 30_485,
      target: 905,
      at: 1000,
    )
  assert support.refusal_results(effects: free) == []
    && confirmed_targets(effects: free) == [905]
    as "Spell4 30485 has no cast group and Creature2 30233's flags bit 0 is clear: any spell may target it"
}

pub fn a_targeted_press_too_close_or_too_far_is_refused_104_or_105_test() -> Nil {
  use <- owned_test.run(10_000)
  let at = fn(gap) {
    Scene(..nothing_shown(), units: [unit(id: 906, of: 32_668, at: gap)])
  }
  assert refused_at(scene: at(3.0), spell4_id: 36_050, target: 906)
    == [code(cast_result.TargetRangeMin)]
    as "Spell4 36050's targetMinRange is 5: a unit 3 m off is too close (104)"
  assert refused_at(scene: at(20.0), spell4_id: 36_050, target: 906)
    == [code(cast_result.TargetRangeMax)]
    as "Spell4 36050's targetMaxRange is 15: a unit 20 m off is too far (105)"
  let #(_, effects) =
    press_at(
      scene: at(10.0),
      state: cast.new(),
      spell4_id: 36_050,
      target: 906,
      at: 1000,
    )
  assert support.refusal_results(effects:) == []
    && confirmed_targets(effects:) == [906]
    as "10 m is within 5 to 15"
}

pub fn a_targeted_press_at_a_dead_unit_is_refused_106_and_a_living_one_107_test() -> Nil {
  use <- owned_test.run(10_000)
  let dead = fn(creature, gap) {
    Scene(..nothing_shown(), units: [
      Unit(..unit(id: 907, of: creature, at: gap), alive: False),
    ])
  }
  assert refused_at(scene: dead(32_668, 10.0), spell4_id: 36_050, target: 907)
    == [code(cast_result.TargetCannotBeDead)]
    as "Spell4Conditions 15 tests the target's life (mask 129, value 0): a dead unit is refused 106"
  assert refused_at(scene: dead(32_526, 10.0), spell4_id: 36_050, target: 907)
    == [code(cast_result.TargetCannotBeDead)]
    as "the life test comes before the cast group: a dead unit outside the group is 106, not 89"
  let alive =
    Scene(..nothing_shown(), units: [unit(id: 907, of: 34_081, at: 3.0)])
  assert refused_at(scene: alive, spell4_id: 38_090, target: 907)
    == [code(cast_result.TargetMustBeDead)]
    as "Spell4Conditions 16 (mask 225, value 1) wants the target dead: a living unit is refused 107"
  let #(_, effects) =
    press_at(
      scene: dead(34_081, 3.0),
      state: cast.new(),
      spell4_id: 38_090,
      target: 907,
      at: 1000,
    )
  assert support.refusal_results(effects:) == []
    && confirmed_targets(effects:) == [907]
    as "a dead unit of the group 4075 within 5 m is taken"
}

pub fn a_targeted_press_at_a_unit_in_combat_is_refused_108_test() -> Nil {
  use <- owned_test.run(10_000)
  let fighting = fn(in_combat) {
    Scene(..nothing_shown(), units: [
      Unit(..unit(id: 908, of: 32_526, at: 10.0), in_combat:),
    ])
  }
  assert refused_at(scene: fighting(True), spell4_id: 36_212, target: 908)
    == [code(cast_result.TargetCannotBeInCombat)]
    as "Spell4Conditions 17 (mask 227, value 0) tests the target's combat as well as its life: a unit in combat is refused 108"
  let #(_, effects) =
    press_at(
      scene: fighting(False),
      state: cast.new(),
      spell4_id: 36_212,
      target: 908,
      at: 1000,
    )
  assert support.refusal_results(effects:) == []
    && confirmed_targets(effects:) == [908]
    as "the same unit out of combat is taken"
}

pub fn a_press_at_a_player_is_refused_102_when_the_valid_targets_forbid_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene = Scene(units: [], players: [909])
  assert refused_at(scene:, spell4_id: 27_684, target: 909)
    == [code(cast_result.TargetCannotBePlayer)]
    as "Spell4ValidTargets 10's targetBitmask is 3: bit 0 refuses a player"
}

pub fn a_press_at_a_player_that_reaches_the_faction_test_is_not_built_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene = Scene(units: [], players: [909])
  let #(_, effects) =
    press_at(
      scene:,
      state: cast.new(),
      spell4_id: 30_485,
      target: 909,
      at: 1000,
    )
  assert support.refusal_results(effects:)
    == [code(cast_result.IllegalSpellCast)]
    as "Spell4 30485 (valid targets bitmask 2) lets a player be its target, and a player reaches the client's player faction test (0x1403b4560), which is not built: refused 285"
  let assert [line] = warnings(effects:)
  assert string.contains(
    line,
    "Quests, zones and prerequisites work on the real client",
  )
    as "the log names the open issue"
  let #(_, own) =
    press_at(
      scene: nothing_shown(),
      state: cast.new(),
      spell4_id: 77_268,
      target: the_caster,
      at: 1000,
    )
  assert support.refusal_results(effects: own)
    == [code(cast_result.IllegalSpellCast)]
    as "Spell4TargetMechanics 4's flags (11) have value 2: the caster may be its own target, and then the player faction test judges it: refused 285"
  let assert [own_line] = warnings(effects: own)
  assert string.contains(
    own_line,
    "Quests, zones and prerequisites work on the real client",
  )
    as "the log names the same issue"
}

pub fn a_target_condition_reads_the_casts_the_player_holds_on_the_unit_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 910, of: 30_233, at: 3.0)])
  assert refused_at(scene:, spell4_id: 77_268, target: 910)
    == [code(cast_result.PrereqTargetCast)]
    as "Spell4 77268's prerequisiteIdTargetCast is Prerequisite 36053 (type 15, comparison 1, value 77269): the unit holds no cast of 77269, so 0x1403ace00 refuses with 281"
}

/// A press that names a unit reaches a TargetCast of type 38 only through a spell that an
/// objective, a creature's activate column or an item names. The 16 Spell4 rows whose
/// TargetCast holds a type 38 condition (Spell4 31373, 31532, 33392 and 13 more) are none of
/// them, so a real row cannot be pressed at a creature; the test below plants the shape of
/// the client's Prerequisite 8895 on a spell an objective names, and this one fails when a
/// real row of that kind appears.
pub fn no_real_spell_a_press_reaches_has_a_creature_id_target_cast_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let with_type_38 =
    prerequisite.all(tables)
    |> list.filter(fn(row) {
      list.contains(
        [
          row.prerequisite_type_id0,
          row.prerequisite_type_id1,
          row.prerequisite_type_id2,
        ],
        38,
      )
    })
    |> list.map(fn(row) { row.id })
  let pressed_at_a_unit =
    list.flatten([
      objective_spells(tables:),
      creature2.all(tables)
        |> list.flat_map(fn(row) {
          [
            row.spell4_id_activate00,
            row.spell4_id_activate01,
            row.spell4_id_activate02,
            row.spell4_id_activate03,
          ]
        }),
      item_special.all(tables)
        |> list.map(fn(row) { row.spell4_id_on_activate }),
    ])
  let reaching =
    spell4.all(tables)
    |> list.filter(fn(row) {
      list.contains(with_type_38, row.prerequisite_id_target_cast)
      && list.contains(pressed_at_a_unit, row.id)
    })
    |> list.map(fn(row) { row.id })
  assert reaching == []
    as "no spell an objective, a creature's activate column or an item names has a TargetCast with a type 38 condition, so a test of the creature id reaching that check plants the row"
}

fn objective_spells(tables tables: table_store.Tables) -> List(Int) {
  quest_objective.all(tables)
  |> list.filter(fn(row) {
    row.type_ == shortcut_spell.cast_type && row.data != 0
  })
  |> list.map(fn(row) { row.data })
}

pub fn a_pressed_creatures_id_reaches_its_target_check_test() -> Nil {
  use <- owned_test.run(10_000)
  // No real row can be pressed at a creature with a type 38 TargetCast (the test above), so
  // Spell4 77268's TargetCast, Prerequisite 36053, takes the shape of the client's
  // Prerequisite 8895 (`table_rows -- Prerequisite 8895`, of Spell4 31532): flags 1 (any of)
  // and two conditions of type 38 comparison 1, on Creature2 ids. The type compares the
  // first unit's Creature2 id with the value (0x14049ecc0), and a pressed creature's id is
  // `Usable.creature_id`.
  use tables <- fixture_tables.changed(table: "Prerequisite", id: 36_053, with: [
    #("flags", Integer(1)),
    #("prerequisiteTypeId0", Integer(38)),
    #("prerequisiteTypeId1", Integer(38)),
    #("prerequisiteComparisonId0", Integer(1)),
    #("prerequisiteComparisonId1", Integer(1)),
    #("value0", Integer(52_428)),
    #("value1", Integer(30_233)),
  ])
  let shortcuts = shortcut_spell.shortcuts(tables:)
  let scene =
    Scene(..nothing_shown(), units: [
      unit(id: 910, of: 30_233, at: 3.0),
      unit(id: 911, of: 41_884, at: 3.0),
    ])
  let #(_, at_the_creature) =
    press_at_with(
      shortcuts:,
      scene:,
      state: cast.new(),
      spell4_id: 77_268,
      target: 910,
      at: 1000,
    )
  assert support.refusal_results(effects: at_the_creature) == []
    && confirmed_targets(effects: at_the_creature) == [910]
    as "a press at the creature of Creature2 30233 meets the second condition, and flags 1 takes either: the cast starts"
  let #(_, at_another) =
    press_at_with(
      shortcuts:,
      scene:,
      state: cast.new(),
      spell4_id: 77_268,
      target: 911,
      at: 1000,
    )
  assert support.refusal_results(effects: at_another)
    == [code(cast_result.PrereqTargetCast)]
    as "a press at a creature of Creature2 41884 (flags 16388, bit 0 clear, so it passes the cast group of Spell4Base 53267, which has none) meets neither condition (52428, 30233): refused 281"
  assert warnings(effects: at_another) == []
    as "the condition is read, so no warning about an unread condition is written"
}

pub fn a_target_condition_the_server_does_not_hold_refuses_as_not_built_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 911, of: 41_884, at: 5.0)])
  let #(state, first) =
    press_at(
      scene:,
      state: cast.new(),
      spell4_id: 43_164,
      target: 911,
      at: 1000,
    )
  assert support.refusal_results(effects: first)
    == [code(cast_result.PrereqTargetCast)]
    as "Spell4 43164's TargetCast is Prerequisite 17071, whose first condition is type 71, which the server does not read: refused as the cast cannot be judged"
  let assert [line] = warnings(effects: first)
  assert string.contains(line, "43164") && string.contains(line, "71")
    as "the log names the spell and the type"
  assert string.contains(line, "(#334)") && !string.contains(line, "(#336)")
    as "a prerequisite the server does not read is the issue of the prerequisites, #334"
  let #(_, second) =
    press_at(scene:, state:, spell4_id: 43_164, target: 911, at: 2000)
  assert support.refusal_results(effects: second)
    == [code(cast_result.PrereqTargetCast)]
    && warnings(effects: second) == []
    as "a second press is refused the same and not logged again"
}

pub fn a_caster_condition_of_an_unread_type_refuses_as_not_built_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 912, of: 27_545, at: 10.0)])
  let #(_, effects) =
    press_at(
      scene:,
      state: cast.new(),
      spell4_id: 32_581,
      target: 912,
      at: 1000,
    )
  assert support.refusal_results(effects:)
    == [code(cast_result.PrereqCasterCast)]
    as "Spell4 32581's CasterCast is Prerequisite 28094, a type 16 the server does not read"
  let assert [line] = warnings(effects:)
  assert string.contains(line, "16") as "the log names the type"
  assert string.contains(line, "(#334)")
    as "a caster condition the server does not read is the issue of the prerequisites, #334"
}

pub fn a_press_of_a_targeted_spell_that_cannot_be_planned_stays_not_built_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 913, of: 32_668, at: 10.0)])
  let #(_, effects) =
    press_at(
      scene:,
      state: cast.new(),
      spell4_id: 35_436,
      target: 913,
      at: 1000,
    )
  assert support.refusal_results(effects:)
    == [code(cast_result.IllegalSpellCast)]
    as "Spell4 35436's Vulnerability row on another unit lasts until removed or by a persistence prerequisite, which the plans do not read yet (#803, #787): refused 285"
  let assert [line] = warnings(effects:)
  assert string.contains(line, "35436") && string.contains(line, "(#336)")
    as "the log names the spell and the issue that will close the gap, #336"
}

pub fn a_press_of_a_target_type_3_spell_tests_its_faction_cast_group_test() -> Nil {
  use <- owned_test.run(10_000)
  let of_faction = fn(faction_id) {
    Scene(..nothing_shown(), units: [
      Unit(..unit(id: 914, of: 30_233, at: 10.0), faction_id:),
    ])
  }
  let #(_, effects) =
    press_at(
      scene: of_faction(390),
      state: cast.new(),
      spell4_id: 30_832,
      target: 914,
      at: 1000,
    )
  assert support.refusal_results(effects:) == []
    && confirmed_targets(effects:) == [914]
    as "Spell4 30832's cast group 2591 is type 3 (a faction) holding Faction2 390: a unit of faction 390 is taken"
  assert refused_at(scene: of_faction(1017), spell4_id: 30_832, target: 914)
    == [code(cast_result.TargetGroup)]
    as "a unit of another faction is refused 89"
}

pub fn a_press_of_a_target_type_5_spell_starts_on_its_target_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 915, of: 26_145, at: 10.0)])
  let #(state, pressed) =
    press_at(
      scene:,
      state: cast.new(),
      spell4_id: 25_207,
      target: 915,
      at: 1000,
    )
  assert confirmed_targets(effects: pressed) == [915]
    && support.shortcut_casts(effects: pressed) == []
    as "the caster is told at once, and nothing counts before the go"
  let #(times, effects) = played(state:, pressed:, at: 1000)
  assert times == [3000] as "Spell4 25207's castTime is 2000, pressed at 1000"
  assert support.shortcut_casts(effects:)
    == [
      cast.ShortcutCast(
        spell4_id: 25_207,
        target: Some(cast.PressedAt(unit_id: 915, alive_at_press: True)),
      ),
    ]
    as "the go at 3000 raises ShortcutCast with the unit"
}

pub fn a_channelled_objective_spell_goes_twice_and_raises_one_cast_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene =
    Scene(..nothing_shown(), units: [unit(id: 916, of: 8047, at: 5.0)])
  let #(state, pressed) =
    press_at(scene:, state: cast.new(), spell4_id: 5725, target: 916, at: 1000)
  let #(_, effects) = played(state:, pressed:, at: 1000)
  assert support.ids(frames: support.writes(effects: pressed)) == [0x07FD]
    as "the caster is told its cast started"
  assert support.ids(frames: support.writes(effects:))
    == [0x07FD, 0x07F4, 0x07F4, 0x07FE]
    as "Spell4 5725 channels 3000 ms: after the start two goes within it, then the finish"
  assert support.shortcut_casts(effects:)
    == [
      cast.ShortcutCast(
        spell4_id: 5725,
        target: Some(cast.PressedAt(unit_id: 916, alive_at_press: True)),
      ),
    ]
    as "a channel counts once, at its first go"
}

/// Spell4 64944 (the spell of quest 9373's objective 17880, Spell4Base 42972: cast group 8755,
/// which holds Creature2 57226 through its first target group) names Spell4CCConditions row 1 for its
/// target: row 1's ccStateMask 218960739 has bit 0, Stun.
const the_stun_refusing_spell = 64_944

const a_creature_of_its_group = 57_226

pub fn an_aimed_press_at_a_held_creature_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let stunned = fn(held, gap) {
    Scene(..nothing_shown(), units: [
      Unit(..unit(id: 920, of: a_creature_of_its_group, at: gap), held:),
    ])
  }
  assert refused_at(
      scene: stunned([Stun], 10.0),
      spell4_id: the_stun_refusing_spell,
      target: 920,
    )
    == [122]
    as "0x1403b2240: the target's Spell4CCConditions mask has bit 0 and the unit holds Stun: Target_CannotBe_Stunned (122)"
  assert refused_at(
      scene: stunned([], 10.0),
      spell4_id: the_stun_refusing_spell,
      target: 920,
    )
    == [code(cast_result.PrereqTargetCast)]
    as "the same creature holding no state passes the state test and meets the next, the spell's target cast Prerequisite 28001 of a type the server does not read (281)"
  assert refused_at(
      scene: stunned([crowd_control_state.Sleep], 10.0),
      spell4_id: the_stun_refusing_spell,
      target: 920,
    )
    == [124]
    as "row 1's mask has bit 1 too: Sleep gives its own Target_CannotBe result (124)"
  assert refused_at(
      scene: stunned([crowd_control_state.Snare], 10.0),
      spell4_id: the_stun_refusing_spell,
      target: 920,
    )
    == [code(cast_result.PrereqTargetCast)]
    as "row 1's mask 218960739 has no bit 21: a held Snare passes the state test"
  assert refused_at(
      scene: stunned([Stun], 400.0),
      spell4_id: the_stun_refusing_spell,
      target: 920,
    )
    == [122]
    as "0x1403b2240 tests the state before the range: a held unit out of range is refused 122, not 105"
}
