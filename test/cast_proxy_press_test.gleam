//// A press of a RapidTap or ChargeRelease ability whose thresholdTime is 0 casts the first
//// Proxy its caster passes (`genesis_prime/game/cast`). Expected values come from these
//// places, each named at its assertion:
//// - ResolveProxyByCasterApply `0x1403d3520`: the press walks the ability's effects in row
////   order, skips every row that is not a Proxy or whose caster apply prerequisite is 0
////   (`0x1403d35c3`), and takes the dataBits00 spell of the first whose caster apply passes
////   for the player and the player's target. With none it returns the press's own spell,
////   which the 285 test of ResolveThresholdSpell `0x1403bfd60` refuses (fact
////   `cast.proxy_press`).
//// - CastAbilityBagSpell `0x14039a040`: the Surge swap (SpellslingerSurgedSpell
////   `0x1405e7e50`) comes before the resolve, and the cast goes on with the resolved spell.
//// - Fact `cast.stage_root_parent`: a base cast has parent 0 and the ability as root.
//// - The client's rows (`table_rows -- Spell4Effects 96985 96992 96993 78288 128339 130591
////   177914 66751 69036 69037`, `-- Prerequisite 16450 16451 16452 5060 7863 11164 10937`):
////   - Spell4 42603 (Spell4Base 26793, RapidTap, thresholdTime 0): Proxy rows 96985
////     (orderIndex 0, spell 42604, caster apply 16450), 96992 (1, 42605, 16451) and 96993
////     (2, 42606, 16452). Each gate is one type 59 condition on Spell4 42607's stack
////     count by comparison 1 (equal): 16450 is 0 (no value), 16451 is 1 and 16452 is 2.
////   - Spell4 42607 (one lasting row 96998, 5000 ms, on the caster) is the stack the gates
////     count.
////   - Spell4 36942 and 54281 (Spell4Base 22327, ChargeRelease, thresholdTime 0): Proxy
////     rows to spell 32822 gated by 5060, one condition of type 28 (in combat, comparison
////     1); 54281 holds the ungated Proxy 130591 (spell 83517) between its gated rows
////     128339 and 177914.
////   - Spell4 34032 (Spell4Base 20006, ChargeRelease, thresholdTime 0): Proxy row 66751 to
////     spell 34011 behind gate 7863 (type 15, comparison 2: no live cast has the caster as
////     its target). Spell4 34011 (Spell4Base 19986, ChargeRelease) has thresholdTime 4000
////     and Spell4Thresholds 107, 83, 84 and 85 (spells 34144, 34012, 34013, 34021).
////   - Spell4 34717 (Spell4Base 20683, ChargeRelease, thresholdTime 0) names the alternate
////     34719 (Spell4Base 20685, thresholdTime 7100) and holds the Proxy rows 69036 (spell
////     34718, gate 11164) and 69037 (spell 34719, gate 10937), each gate three type 64
////     conditions on resource slots 1 to 3.
////   - Spell4 42605 (Spell4Base 26795, thresholdTime 0) holds one Proxy row, 97000, to 42607
////     on struck units with no caster apply; Prerequisite 4585 is one type 37 condition
////     (comparison 6, value 50), which draws one roll
////     (`table_rows -- Spell4Effects 97000`, `-- Prerequisite 4585`).

import cast_support as support
import fixture_tables
import genesis_prime/client_connection.{CastStarted}
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/spell_plan.{type Plans, type Spell}
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{type Spell4BaseId, Spell4BaseId}
import genesis_prime/table/loader/store
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import planted_table

/// The planted stack spell: Spell4 42607 on a base the bag holds, with its one lasting row.
const stack_base = 26_797

/// The press of Spell4 42603.
const press_base = 26_793

const stack_bag = 0

const press_bag = 1

fn bag() -> List(Spell4BaseId) {
  [Spell4BaseId(stack_base), Spell4BaseId(press_base)]
}

/// The player holding the stack spell and the press, in or out of combat.
fn caster_of(in_combat in_combat: Bool) -> Caster {
  cast.Caster(
    ..support.caster_in_combat(in_combat:),
    abilities: bag(),
    book: bag(),
  )
}

/// The ability of the client's spell as the plan loads it.
fn ability_of(tables tables: store.Tables, spell4_id spell4_id: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.ability_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id:,
    )
    as "the spell plans as an ability"
  spell
}

fn stack_spell() -> Spell {
  support.client_lasting(spell4_id: 42_607, base: stack_base, effect_ids: [
    96_998,
  ])
}

/// The plans holding the press and the stack spell.
fn plans_of_press(press press: Spell) -> Plans {
  support.with_spells(plans: support.plans(), spells: [press, stack_spell()])
}

/// The state after this many presses of the stack spell, one every 100 ms from 1000 ms:
/// each leaves one node of Spell4 42607 on the caster.
fn stacked(
  plans plans: Plans,
  caster caster: Caster,
  stacks stacks: Int,
) -> State {
  list.repeat(Nil, stacks)
  |> list.index_fold(cast.new(), fn(state, _, index) {
    let #(state, effects) =
      support.press_as(
        plans:,
        state:,
        caster:,
        bag: stack_bag,
        at: 1000 + 100 * index,
      )
    assert support.refusal_results(effects:) == [] as "the stack spell is cast"
    state
  })
}

/// What the viewer 2 is told started, as (spell, root, parent), in order.
fn started(effects effects: List(Effect)) -> List(#(Int, Int, Int)) {
  list.filter_map(support.tells(effects:), fn(tell) {
    case tell {
      #(ConnectionId(2), CastStarted(start:)) ->
        Ok(#(start.spell4_id, start.root_spell4_id, start.parent_spell4_id))
      _ -> Error(Nil)
    }
  })
}

/// The press of the bag index at 5000 ms, past every global cooldown of the stack presses.
fn press_at_5000(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag bag: Int,
) -> List(Effect) {
  let #(_, effects) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag,
      target: 0,
      at: 5000,
    )
  effects
}

pub fn threshold_press_casts_the_first_passing_proxy_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans =
    plans_of_press(press: ability_of(
      tables: fixture_tables.shared(),
      spell4_id: 42_603,
    ))
  let caster = caster_of(in_combat: False)
  let effects =
    press_at_5000(
      plans:,
      state: stacked(plans:, caster:, stacks: 1),
      caster:,
      bag: press_bag,
    )
  assert support.refusal_results(effects:) == []
    as "gate 16451 passes at one stack, so the press is not refused"
  assert started(effects:) == [#(42_605, 42_603, 0)]
    as "one node of 42607 passes only 16451 (type 59, equal 1): 0x1403d3520 takes row 96992's spell 42605; the root is the ability 42603 and the parent 0 (cast.stage_root_parent)"
}

pub fn threshold_press_with_two_passing_proxies_takes_the_first_in_row_order_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 16450, the gate of Proxy row 96985 (orderIndex 0), made
  // comparison 4 (at least) on value 0, so that one node of 42607 passes it as it passes
  // 16451, the gate of row 96992 (orderIndex 1).
  fixture_tables.changed(
    table: "Prerequisite",
    id: 16_450,
    with: [#("prerequisiteComparisonId0", planted_table.Integer(4))],
    body: fn(tables) {
      let plans = plans_of_press(press: ability_of(tables:, spell4_id: 42_603))
      let caster = caster_of(in_combat: False)
      let effects =
        press_at_5000(
          plans:,
          state: stacked(plans:, caster:, stacks: 1),
          caster:,
          bag: press_bag,
        )
      assert started(effects:) == [#(42_604, 42_603, 0)]
        as "16450 (at least 0) and 16451 (equal 1) both pass at one node; 0x1403d3520 walks the rows in order and takes row 96985 (orderIndex 0), spell 42604, not 96992's 42605"
    },
  )
}

/// The player holding only the healer's ability of Spell4Base 22327, in or out of combat.
fn healer(in_combat in_combat: Bool) -> Caster {
  cast.Caster(
    ..support.caster_in_combat(in_combat:),
    abilities: [Spell4BaseId(22_327)],
    book: [Spell4BaseId(22_327)],
  )
}

/// The press of the healer's only ability at 5000 ms, as the rule gives it.
fn healed(spell4_id spell4_id: Int, in_combat in_combat: Bool) -> List(Effect) {
  let plans =
    support.with_spells(plans: support.plans(), spells: [
      ability_of(tables: fixture_tables.shared(), spell4_id:),
    ])
  press_at_5000(plans:, state: cast.new(), caster: healer(in_combat:), bag: 0)
}

pub fn threshold_press_with_no_passing_proxy_is_refused_285_test() -> Nil {
  use <- owned_test.run(60_000)
  let out_of_combat = healed(spell4_id: 36_942, in_combat: False)
  assert support.cast_lines(frames: support.writes(effects: out_of_combat))
    == ["refused 36942 285"]
    as "gate 5060 is type 28 comparison 1 (in combat) and fails out of combat for both Proxy rows 78288 and 200559: 0x1403bfd60 returns the press's own spell 36942, whose thresholdTime 0 the 285 test refuses (cast.proxy_press)"
  assert started(effects: out_of_combat) == []
    as "nothing is cast, 32822 included"
  assert support.goes_asked(effects: out_of_combat) == []
    as "and no go is waiting"
  let in_combat = healed(spell4_id: 36_942, in_combat: True)
  assert started(effects: in_combat) == [#(32_822, 36_942, 0)]
    as "in combat 5060 passes and 0x1403d3520 takes row 78288's spell 32822"
}

pub fn threshold_press_never_casts_a_proxy_with_caster_apply_zero_test() -> Nil {
  use <- owned_test.run(60_000)
  let out_of_combat = healed(spell4_id: 54_281, in_combat: False)
  assert support.cast_lines(frames: support.writes(effects: out_of_combat))
    == ["refused 54281 285"]
    as "rows 128339 and 177914 fail 5060 out of combat and row 130591 (spell 83517) has caster apply 0, which 0x1403d35c3 skips: no Proxy passes and the 285 test refuses the press"
  assert started(effects: out_of_combat) == [] as "83517 is never cast"
  let in_combat = healed(spell4_id: 54_281, in_combat: True)
  assert started(effects: in_combat) == [#(32_822, 54_281, 0)]
    as "in combat the first row, 128339, passes: 32822, not the ungated row's 83517 that follows it"
}

/// The Spellslinger at 100 Spell Power holding Spell Surge (Spell4Base 31213) and the
/// ability of Spell4Base 20683, whose alternate is Spell4Base 20685.
fn spellslinger() -> Caster {
  cast.Caster(
    ..support.caster_holding(resources: support.holding(
      class_id: 7,
      value: 100.0,
    )),
    abilities: [Spell4BaseId(31_213), Spell4BaseId(20_683)],
    book: [Spell4BaseId(31_213), Spell4BaseId(20_683), Spell4BaseId(20_685)],
  )
}

pub fn surged_press_of_a_proxy_press_casts_the_alternates_own_threshold_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans =
    support.with_spells(plans: support.plans(), spells: [
      ability_of(tables: fixture_tables.shared(), spell4_id: 34_717),
    ])
  let #(surging, surge_press) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: spellslinger(),
      bag: 0,
      at: 1000,
    )
  assert support.refusal_results(effects: surge_press) == []
    as "Spell Surge 47273 is cast at 100 Spell Power"
  let surged =
    press_at_5000(plans:, state: surging, caster: spellslinger(), bag: 1)
  assert support.refusal_results(effects: surged) == []
  assert started(effects: surged) == [#(34_719, 34_719, 0)]
    as "a node of 47439 and base 20685 in the book: 0x14039a040 swaps the press for the alternate 34719 before the resolve (0x1405e7e50), and 34719's thresholdTime 7100 is its own, so the press casts 34719 and none of 34717's Proxy rows"
  let plain =
    press_at_5000(plans:, state: cast.new(), caster: spellslinger(), bag: 1)
  assert support.refusal_results(effects: plain) == []
  assert started(effects: plain) == [#(34_718, 34_717, 0)]
    as "with no Surge the press resolves: gate 11164 (three type 64 conditions, slots 1 to 3 equal 0) passes for a Spellslinger, whose Spell Power is slot 4, so row 69036's spell 34718 is cast, and gate 10937 of row 69037 is not reached"
}

/// The Spell4 id of each cast of a viewer's tells that is a root, in order: the spells a
/// held key's presses and repeats resolved to.
fn root_casts(steps steps: List(List(Effect))) -> List(Int) {
  list.flat_map(steps, fn(effects) {
    list.filter_map(started(effects:), fn(start) {
      case start.2 {
        0 -> Ok(start.0)
        _ -> Error(Nil)
      }
    })
  })
}

/// The key of the press going down at 1000 ms with every strike hitting unit 99, its go
/// answered, and the repeats that follow until the time: each step's effects.
fn held_press(
  plans plans: Plans,
  caster caster: Caster,
  until_ms until_ms: Int,
) -> List(List(Effect)) {
  let assert Ok(#(state, down)) =
    cast.take(
      cast: cast.new(),
      message: cast.KeyHeld,
      body: support.hold_body(bag_index: press_bag, target: 0, held: 1),
      caster:,
      plans:,
      now: support.at(ms: 1000),
    )
    as "a 0x4db that fits the message is taken"
  let #(state, answered) =
    support.answered_as(
      caster:,
      state:,
      effects: down,
      at: 1000,
      struck: support.hits([99]),
      rolls: [],
    )
  let #(_, repeats) =
    support.run_timers_posed(
      caster:,
      state:,
      effects: answered,
      from_ms: 1000,
      struck_at: fn(_, _) { support.hits([99]) },
      poses: dict.new(),
      until_ms: Some(until_ms),
    )
  [down, ..list.map(repeats, fn(repeat) { repeat.effects })]
}

pub fn held_rapid_tap_repeat_resolves_the_proxy_again_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans =
    plans_of_press(press: ability_of(
      tables: fixture_tables.shared(),
      spell4_id: 42_603,
    ))
  let steps =
    held_press(plans:, caster: caster_of(in_combat: False), until_ms: 4500)
  assert root_casts(steps:) == [42_604, 42_604, 42_605, 42_606]
    as "each repeat of the held press resolves again (0x1403d3520) from the nodes the caster holds then: the first repeat falls at the instant of the first cast's go, before the stack that cast adds is placed, so 16450 (no stack) passes again (42604); one stack passes 16451 (42605); two stacks pass 16452 (42606). Each cast of 42604 and 42605 adds one 42607 stack through its Proxy row 97018 or 97000"
  // Kept edit: the value of Prerequisite 16452, the gate of Proxy row 96993 (orderIndex 2),
  // made unreachable, so that two stacks pass no gate.
  fixture_tables.changed(
    table: "Prerequisite",
    id: 16_452,
    with: [#("value0", planted_table.Integer(9))],
    body: fn(tables) {
      let plans = plans_of_press(press: ability_of(tables:, spell4_id: 42_603))
      let steps =
        held_press(plans:, caster: caster_of(in_combat: False), until_ms: 6500)
      assert root_casts(steps:) == [42_604, 42_604, 42_605]
        as "the repeat at 4000 ms finds no passing Proxy and the press is refused 285 (0x1403c0144): the hold ends with it, so nothing repeats after"
      assert list.flat_map(steps, fn(effects) {
          support.cast_lines(frames: support.writes(effects:))
        })
        |> list.filter(string.starts_with(_, "refused"))
        == ["refused 42603 285"]
        as "the refusal names the press's own spell, once"
    },
  )
}

/// The player holding only the ability of Spell4Base 20006, out of combat.
fn charger() -> Caster {
  cast.Caster(
    ..support.caster_in_combat(in_combat: False),
    abilities: [Spell4BaseId(20_006)],
    book: [Spell4BaseId(20_006)],
  )
}

pub fn proxy_child_with_its_own_threshold_opens_that_threshold_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans =
    support.with_spells(plans: support.plans(), spells: [
      ability_of(tables: fixture_tables.shared(), spell4_id: 34_032),
    ])
  let #(state, pressed) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: charger(),
      bag: 0,
      at: 5000,
    )
  assert support.refusal_results(effects: pressed) == []
    as "gate 7863 (type 15, value 30367) passes: no live cast of 30367 targets the caster"
  assert started(effects: pressed) == [#(34_011, 34_032, 0)]
    as "0x1403d3520 takes row 66751's spell 34011, cast as the press itself: root the ability 34032, parent 0"
  assert support.delays_of(effects: pressed) == [750]
    as "34011's Spell4Thresholds rows 107 (index 0), 83 (750 ms), 84 and 85: the cast opens that threshold at its first stage (0x1403bfd60 on the resolved spell)"
  let #(_, released) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster: charger(),
      bag_index: 0,
      target: 0,
      at: 5500,
    )
  assert started(effects: released) == [#(34_144, 34_011, 34_011)]
    as "the second press releases index 0, row 107's spell 34144, with the threshold's ability 34011 as root and parent (cast.stage_root_parent)"
}

pub fn threshold_press_with_no_target_or_a_gone_target_still_resolves_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans =
    plans_of_press(press: ability_of(
      tables: fixture_tables.shared(),
      spell4_id: 42_603,
    ))
  let caster = caster_of(in_combat: False)
  let pressed_at = fn(target) {
    let #(_, effects) =
      support.pressed_raw_in(
        plans:,
        state: stacked(plans:, caster:, stacks: 1),
        caster:,
        bag_index: press_bag,
        target:,
        at: 5000,
      )
    effects
  }
  let none = pressed_at(0)
  let gone = pressed_at(99_999)
  assert support.refusal_results(effects: none) == []
    && support.refusal_results(effects: gone) == []
    as "neither press is refused"
  assert started(effects: none) == [#(42_605, 42_603, 0)]
    as "0x1403d3520 reads the caster's nodes and gates only (16451 at one stack), never the target: with no target it takes row 96992's spell 42605"
  assert started(effects: gone) == started(effects: none)
    as "a target the server does not hold changes nothing: the same spell, root and parent"
}

/// The go the press of the bag index at 5000 ms asks for, with the rolls it needs for
/// strikes that hit unit 99, and the spell the go is for.
fn go_of(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag bag: Int,
) -> #(Int, Int) {
  let #(pressed, raw) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag,
      target: 0,
      at: 5000,
    )
  let #(_, fired) =
    support.run_timers_posed(
      caster:,
      state: pressed,
      effects: raw,
      from_ms: 5000,
      struck_at: fn(_, _) { [] },
      poses: dict.new(),
      until_ms: Some(8000),
    )
  let assert [asked] = list.flat_map(fired, fn(step) { step.asked })
    as "the press asks for exactly one go, its resolved spell's"
  #(
    asked.spell4_id.value,
    cast.rolls_needed(
      cast: pressed,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: support.hits([99]),
    ),
  )
}

pub fn proxy_resolved_cast_needs_the_same_go_rolls_as_its_child_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: the caster apply of Spell4Effects 97000, the Proxy row of Spell4 42605 to
  // 42607 (struck units), made Prerequisite 4585, one type 37 condition (a roll, comparison
  // 6, value 50), so that the go of 42605 needs one roll.
  fixture_tables.changed(
    table: "Spell4Effects",
    id: 97_000,
    with: [#("prerequisiteIdCasterApply", planted_table.Integer(4585))],
    body: fn(tables) {
      let press = ability_of(tables:, spell4_id: 42_603)
      let plans = plans_of_press(press:)
      let caster = caster_of(in_combat: False)
      let through_press =
        go_of(
          plans:,
          state: stacked(plans:, caster:, stacks: 1),
          caster:,
          bag: press_bag,
        )
      assert through_press.0 == 42_605
        as "the press has no go of its own: the go is the resolved spell's, 42605 (one stack, gate 16451)"
      assert through_press.1 == 1
        as "row 97000's caster gate has one type 37 condition: the go draws one roll, as the client draws for the spell the press resolved to"
      let plain =
        go_of(
          plans: support.with_spells(plans: support.plans(), spells: [
            ability_of(tables:, spell4_id: 42_605),
            stack_spell(),
          ]),
          state: cast.new(),
          caster: cast.Caster(
            ..support.caster_in_combat(in_combat: False),
            abilities: [Spell4BaseId(26_795)],
            book: [Spell4BaseId(26_795)],
          ),
          bag: 0,
        )
      assert plain == through_press
        as "the same spell cast on its own asks the same go with the same rolls"
    },
  )
}
