//// A class's innate active pressed from the ability bag (`genesis_prime/game/cast`
//// with the plans of the client's tables). The innate is held at bag index 3, after
//// the three level-1 abilities, so its press is the ability press: 0x9A, or 0x4DB
//// under hold to continue casting, with that index. Expected values come from these
//// places.
//// - `lua.ActionBarFrame.ActionBarInnate`, `0x14077dfa0`: the innate button casts
////   the bag item of the class's slot-0 active, so the press needs no message of
////   its own.
//// - `Spell4.46073` (Stalker, Nano Skin: Lethal): castTime 0, spellCoolDown 25000
////   with cooldown groups 182 and 248, globalCooldownEnum 3 (neither refused while
////   the global cooldown runs nor starting it), Proxy 107792 to 38784 'Stealth - On'
////   behind Prerequisite 7050 (type 116, comparison 2: not stealthed).
//// - `Spell4Effects.45` of 38784: the cooldown effect 159128 clears the toggle's
////   cooldown out of combat (behind Prerequisite 390, type 28 comparison 2), so
////   the toggle's own cooldown stands only in combat.
//// - `Spell4.46867` (Warrior): the effects of type 90 (192556, 192608, 192609) and
////   118 (210834); `Spell4.58586` (Esper): 178144, type 29. No effect type of those is
////   read by the server (`effect_kind.kind_of`), except that 210834 is a periodic
////   HealShields row, which the plan holds and no go lists or applies, so a go lists no
////   row of them and no line says so.
//// - `Spell4.69450` (Medic): 228914, type 118, 0.3 of the missing shield aimed at the
////   caster (`table_rows -- Spell4Effects spellId=69450`): its go lists it with a heal
////   description of the amount.
//// Skipped where the client's tables are not on the machine.

import cast_support as support
import client_tables
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Plans}
import genesis_prime/message/damage_type
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/table/id.{Spell4BaseId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

fn real_plans() -> Plans {
  spell_plan.plans(client_tables.shared())
}

/// A caster of a class: its three level-1 abilities and its innate at bag index 3.
fn caster_with(bag bag: List(Int), in_combat in_combat: Bool) -> Caster {
  cast.Caster(
    ..support.caster(),
    abilities: list.map(bag, Spell4BaseId),
    in_combat:,
  )
}

fn stalker(in_combat in_combat: Bool) -> Caster {
  caster_with(bag: [23_148, 23_161, 23_173, 30_075], in_combat:)
}

/// A press of the bag index, its go answered with no unit struck.
fn pressed(
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans: real_plans(),
      state:,
      caster:,
      bag_index:,
      target: 0,
      at: ms,
    )
  support.answered_as(caster:, state:, effects:, at: ms, struck: [], rolls: [])
}

/// The Spell4 ids of the casts the effects start, in order.
fn started_spells(effects effects: List(Effect)) -> List(Int) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id == spell_started.message_id {
      True -> {
        let assert Ok(start) = spell_started.decode(frame.body)
          as "a 0x7ff the rule wrote decodes"
        Ok(start.spell4_id)
      }
      False -> Error(Nil)
    }
  })
}

/// The Spell4Effects ids every go of the effects lists, in order.
fn listed(effects effects: List(Effect)) -> List(Int) {
  list.filter(support.writes(effects:), fn(frame) {
    frame.message_id == spell_go.message_id
  })
  |> list.flat_map(fn(frame) {
    let assert Ok(go) = spell_go.decode(frame.body)
      as "a go the rule wrote decodes"
    list.flat_map(go.targets, fn(target) {
      list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    })
  })
}

pub fn a_stalkers_press_of_bag_index_3_casts_nano_skin_and_the_go_and_finish_follow_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(_, effects) =
    pressed(
      state: cast.new(),
      caster: stalker(in_combat: False),
      bag_index: 3,
      at: 1000,
    )
  let ids = support.ids(frames: support.writes(effects:))
  assert list.take(ids, 1) == [0x07FD]
    as "opcode.0x7fd: the press is confirmed first"
  assert list.contains(ids, 0x07F4) && list.contains(ids, 0x07FE)
    as "Spell4.46073 casts at once (castTime 0), goes, and its cast ends"
  assert started_spells(effects:) == [38_784]
    as "Proxy 107792 starts 38784, Stealth - On: Prerequisite 7050 passes for a caster that is not stealthed (type 116, comparison 2)"
}

pub fn the_innates_own_cooldown_runs_for_25_seconds_in_combat_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: True)
  let #(state, _) = pressed(state: cast.new(), caster:, bag_index: 3, at: 1000)
  let #(_, again) = pressed(state:, caster:, bag_index: 3, at: 20_000)
  assert support.refusal_results(effects: again) == [15]
    as "Spell4.46073: spellCoolDown 25000, so a press 19 s later is refused with the cooldown result 15; Prerequisite 390 (not in combat) fails in combat, so 38784's cooldown effect does not clear it"
  let #(_, later) = pressed(state:, caster:, bag_index: 3, at: 26_000)
  assert support.refusal_results(effects: later) == []
    as "the cooldown ends at 26000"
}

pub fn the_toggles_cooldown_effect_clears_it_out_of_combat_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: False)
  let #(state, _) = pressed(state: cast.new(), caster:, bag_index: 3, at: 1000)
  let #(_, again) = pressed(state:, caster:, bag_index: 3, at: 2000)
  assert support.refusal_results(effects: again) == []
    as "Spell4Effects 159128 of 38784, behind Prerequisite 390 (type 28 comparison 2: not in combat), clears the toggle's cooldown group 182"
}

pub fn the_innates_press_starts_no_global_cooldown_where_an_ordinary_ability_does_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Shred, 23148, is global cooldown kind 0 with SpellCoolDown row 115 (1000 ms): it
  // is refused while the global cooldown runs and starts it (`Spell4.38765`), so its
  // press shows whether one runs. 46073 names the same row 115 with kind 3.
  let caster = stalker(in_combat: True)
  let #(after_ability, _) =
    pressed(state: cast.new(), caster:, bag_index: 0, at: 1000)
  let #(_, second_ability) =
    pressed(state: after_ability, caster:, bag_index: 0, at: 1100)
  assert support.refusal_results(effects: second_ability) == [14]
    as "the control: Shred starts the 1000 ms global cooldown, so a second press 100 ms later is refused 14 (0x1403b14c0)"
  let #(after_innate, _) =
    pressed(state: cast.new(), caster:, bag_index: 3, at: 1000)
  let #(_, ability) =
    pressed(state: after_innate, caster:, bag_index: 0, at: 1100)
  assert support.refusal_results(effects: ability) == []
    as "Spell4.46073: globalCooldownEnum 3 starts none, so an ability pressed 100 ms after the innate is not refused 14"
}

pub fn a_held_key_of_bag_index_3_holds_the_innate_as_any_key_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = stalker(in_combat: True)
  let assert Ok(#(state, effects)) =
    cast.take(
      cast: cast.new(),
      message: cast.KeyHeld,
      body: support.hold_body(bag_index: 3, target: 0, held: 1),
      caster:,
      plans: real_plans(),
      now: support.at(ms: 1000),
    )
    as "a 0x4db of bag index 3 is taken"
  let #(_, effects) =
    support.answered_as(
      caster:,
      state:,
      effects:,
      at: 1000,
      struck: [],
      rolls: [],
    )
  assert started_spells(effects:) == [46_073, 38_784]
    as "opcode.0x4db: the key goes down and casts 46073 with a 0x7ff in place of the 0x7fd (the client made no cast id), whose Proxy starts 38784"
  assert support.frames_of(message_id: 0x07FD, effects:) == []
    as "a held key is no press: the client has no cast id to confirm"
}

pub fn bag_index_4_holds_no_ability_and_is_refused_as_today_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(_, effects) =
    support.pressed_raw_in(
      plans: real_plans(),
      state: cast.new(),
      caster: stalker(in_combat: False),
      bag_index: 4,
      target: 0,
      at: 1000,
    )
  assert support.refusal_results(effects:) == [4]
    as "a bag index past the items held is a spell the client's bag never names: 0x7fc with result 4 (spell unknown)"
  assert started_spells(effects:) == []
}

// ---- unread rows ----

/// A class's innate pressed at bag index 3, its go answered with no unit struck, and
/// the timers it starts fired in turn: every effect of the press and of the casts it
/// starts, in order. The Esper's Spectral Form is pressed in combat, as its cast
/// prerequisite 903 asks (`Spell4.58586`: the client refuses it out of combat with 151).
fn innate_pressed(
  bag bag: List(Int),
  in_combat in_combat: Bool,
) -> List(Effect) {
  innate_pressed_by(caster: caster_with(bag:, in_combat:))
}

/// The same for a caster given.
fn innate_pressed_by(caster caster: Caster) -> List(Effect) {
  let #(state, effects) =
    pressed(state: cast.new(), caster:, bag_index: 3, at: 1000)
  let #(_, steps) = support.run_timers(state:, effects:, from_ms: 1000)
  list.flatten([effects, ..list.map(steps, fn(step) { step.1 })])
}

pub fn the_unread_rows_of_a_pressed_innate_are_listed_nowhere_and_write_no_line_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let warrior =
    innate_pressed(bag: [18_309, 37_968, 38_017, 30_828], in_combat: False)
  let esper =
    innate_pressed(bag: [19_102, 19_019, 19_022, 38_012], in_combat: True)
  let unread = [
    #(warrior, [192_556, 192_608, 192_609, 210_834, 109_482]),
    #(esper, [178_144, 199_192]),
  ]
  list.each(unread, fn(pressed) {
    let #(effects, rows) = pressed
    assert list.all(rows, fn(row) { !list.contains(listed(effects:), row) })
      as "Spell4Effects 192556, 192608 and 192609 (type 90), 109482 (type 18) of the Warrior's, 178144 (type 29) and 199192 (type 52) of the Esper's are not read (effect_kind.kind_of), and 210834 (type 118, tickTime 1000) is held and not applied: no go lists one"
    assert support.frames_of(message_id: 0x07FD, effects:) != []
      as "each press was taken"
    assert list.all(rows, fn(row) {
      list.all(support.logs(effects:), fn(line) {
        !string.contains(line.1, int.to_string(row))
      })
    })
      as "an unread row is counted by the coverage measure and written about by no go: no log line of any level names one"
  })
}

pub fn the_innates_go_lists_only_the_rows_the_server_reads_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let warrior =
    innate_pressed(bag: [18_309, 37_968, 38_017, 30_828], in_combat: False)
  assert listed(effects: warrior) |> list.sort(int.compare)
    == [127_652, 173_869, 173_911, 173_912]
    as "Spell4.46867's own go lists its type 73 row 173869, aimed at the caster; Proxy 127637 starts 42908 after 1 ms, whose go lists its three type 11 properties 127652, 173911 and 173912 (Spell4Effects spellId=42908); the type 18 row 109482 is not read"
  assert started_spells(effects: warrior) == [42_908]
    as "Proxies 147848 to 60915 and 210822 to 79875 are behind Prerequisites 24548 and 37438 (type 50, comparison 1: a live cast of an AMP's spell), which a caster with none fails"
  let esper =
    innate_pressed(bag: [19_102, 19_019, 19_022, 38_012], in_combat: True)
  assert listed(effects: esper) == []
    as "Spell4.58586 holds Proxies 166935, 178143 and 204548 and the type 29 row 178144: the children list no row, and no row of the go itself is read"
  assert started_spells(effects: esper) == [70_369, 76_766]
    as "Proxy 166935 starts 70369 and Proxy 178143 starts 76766; Proxy 204548 to 78078 is behind Prerequisite 36531 (type 15, comparison 1: a live cast of Spell4 41590 on the caster), which a caster with no such cast fails"
  // A Medic with 250 of its 450 shield, struck.
  let medic =
    innate_pressed_by(
      caster: cast.Caster(
        ..caster_with(bag: [38_201, 16_322, 26_543, 46_615], in_combat: False),
        life_vitals: dict.from_list([
          #(3, prerequisite.Vital(current: 250.0, maximum: 450.0)),
        ]),
      ),
    )
  assert listed(effects: medic) == [228_911, 228_912, 228_914]
    as "Spell4.69450's type 11 rows 228911 and 228912 (properties 35 and 36, for 8 s, aimed at the caster) and its type 118 row 228914 are listed"
  let assert [go, ..] =
    support.frames_of(message_id: spell_go.message_id, effects: medic)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert Ok(heal) =
    list.flat_map(decoded.targets, fn(target) { target.effects })
    |> list.find(fn(effect) { effect.spell4_effects_id == 228_914 })
  let assert spell_effect_result.Damage(shown) = heal.result
    as "the heal is listed with a damage description"
  assert shown.description.damage_type == damage_type.HealShields
    && shown.description.health_damage_with_overkill == 60
    as "row 228914 is 0.3 x the missing shield: 0.3 x (450 - 250) = 60"
  assert started_spells(effects: medic) == []
    as "Proxies 228915 and 228917 are behind Prerequisites 24356 and 24445 (type 15, comparison 1: an AMP's spell), which a caster with none fails"
}
