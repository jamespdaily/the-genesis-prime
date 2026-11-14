//// What a CCStateSet effect (`Spell4Effects.effectType.4`) is to the server before
//// any creature holds it: the columns of its row and the instance id its go gives
//// it. The caster's strike carries the row's state to the creature that owns the
//// struck unit (genesis_prime/game/strike_tell `ControlTell`), the creature holds it
//// and ends it (genesis_prime/world_map/creature_control), and the cast rule lists
//// it in the go (genesis_prime/game/cast).
////
//// - **The state** is the row's dataBits00 (`Unit.CodeEnumCCState`): the plan reads
////   all 28 states, 0 to 27, and fails the load for any other value
////   (genesis_prime/game/spell_plan). The caster's own state is held by the cast rule
////   until its cast ends (genesis_prime/game/cast `restrictions`), a creature's by the
////   creature (genesis_prime/world_map/creature_control).
//// - **The results** a held state gives a press are the client's own, per state
////   (`caster_result`, `target_result`). The state a mask refuses first is the lowest
////   masked state held (`first_masked`), as the client's check takes its bits in order.
//// - **The instance id** names one effect on one unit. The client finds the effect a
////   0x87f waits for by instance id alone among every effect held on the unit, from
////   any caster, and 0 matches the first effect found (`cc_state.instance_id`), so an
////   id is non-zero and no two effects on a unit share one. It is made from the
////   caster's unit id and a count of the states it told (`instance_id`). Two counters
////   number them: `strike.controls_told` for the states on the creatures its strikes
////   select, and `cast.restrictions_told` for the states on the caster itself. They
////   number the states of different units, a creature's and the caster's own.

import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/table/id.{Spell4CCConditionsId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_cc_conditions
import gleam/int
import gleam/list
import gleam/result

/// The columns of a CCStateSet row that decide how long and how a state lands:
/// its state (dataBits00), delayTime and durationTime in milliseconds, and the
/// Interrupt Armor it removes (dataBits03). The client's own lifetime for the effect
/// scales durationTime by the target's CC resilience, which is 0 for every creature
/// (`cc_state.duration_on_creature`), so a creature holds the state for durationTime.
pub type Row {
  Row(
    state: CrowdControlState,
    delay_ms: Int,
    duration_ms: Int,
    armor_removed: Int,
    /// The row's flags bit 2: the state never times out, it lasts until its cast's
    /// effects end (`Spell4Effects.flags`, `cc_state.instance_id`).
    until_removed: Bool,
  )
}

/// How many numbers of one caster the encoding holds: 1 to 4095 in the low 12 bits.
const numbers_per_caster = 4095

/// The instance id of the `count`th state the unit `caster_unit_id` told: its unit id
/// times 4096 plus `count` wrapped into 1 to 4095.
///
/// - Within 32 bits: a unit id is below 2^20, the bound `cast.cast_id` already holds
///   (its 2^31 + unit id x 2^11 stays in 32 bits), and 4095 + 4096 x (2^20 - 1) is
///   2^32 - 1.
/// - Non-zero: the low part is 1 to 4095, and unit ids start at 1, so an id is also
///   4096 or more, which no damage or Fluff instance id is (those number from 1 for
///   each unit in one go, `cast.target_info`).
/// - Unique on a unit across casters: two casters differ in the quotient by 4096,
///   since the low part is below 4096.
/// - Unique for one caster: two of its ids on one unit are equal only when its counts
///   are 4095 apart, which needs 4095 more states told while the first is still held
///   (a state lasts seconds).
pub fn instance_id(
  caster_unit_id caster_unit_id: Int,
  count count: Int,
) -> Int {
  caster_unit_id * 4096 + { count - 1 } % numbers_per_caster + 1
}

/// The Spell4CastResult a held state on the caster gives a press whose caster
/// conditions mask it (Caster_CannotBe...): the client's `CheckSpellCCConditions`
/// (`0x1403b2c40`, called by `CheckCastCaster` at `0x1403affa2`) gives these for the
/// states 0 to 27 (`Spell4CCConditions.results`).
pub fn caster_result(state state: CrowdControlState) -> Int {
  results_of(state).0
}

/// The Spell4CastResult a held state on the target gives a press whose target
/// conditions mask it (Target_CannotBe...): the same check's results for the target,
/// called by `CheckCastUnitTargetRange` at `0x1403b2240` line 224
/// (`Spell4CCConditions.results`).
pub fn target_result(state state: CrowdControlState) -> Int {
  results_of(state).1
}

/// The held state a ccStateMask refuses first: the lowest masked state of `held` (bit n of
/// the mask is state n, `CheckSpellCCConditions`, `0x1403b2c40`, which takes the bits in
/// order), or `Error(Nil)` when it masks none of them.
pub fn first_masked(
  mask mask: Int,
  held held: List(CrowdControlState),
) -> Result(CrowdControlState, Nil) {
  held
  |> list.filter(fn(state) {
    int.bitwise_and(
      mask,
      int.bitwise_shift_left(1, crowd_control_state.to_value(state)),
    )
    != 0
  })
  |> list.sort(by: fn(first, second) {
    int.compare(
      crowd_control_state.to_value(first),
      crowd_control_state.to_value(second),
    )
  })
  |> list.first
}

/// The caster and target results of a state, `Spell.CodeEnumCastResult` (`0x140c2f290`).
/// State 10 (VulnerabilityWithAct) gives state 9's, as the client's check does. A value
/// that is no state of `Unit.CodeEnumCCState` is never held: the plan fails the load for
/// it, so reaching it is a bug that ends the process.
fn results_of(state: CrowdControlState) -> #(Int, Int) {
  case state {
    crowd_control_state.Stun -> #(73, 122)
    crowd_control_state.Sleep -> #(75, 124)
    crowd_control_state.Root -> #(77, 126)
    crowd_control_state.Disarm -> #(79, 128)
    crowd_control_state.Silence -> #(81, 130)
    crowd_control_state.Polymorph -> #(200, 201)
    crowd_control_state.Fear -> #(85, 134)
    crowd_control_state.Hold -> #(204, 205)
    crowd_control_state.Knockdown -> #(158, 161)
    crowd_control_state.Vulnerability
    | crowd_control_state.VulnerabilityWithAct -> #(159, 160)
    crowd_control_state.Disorient -> #(208, 209)
    crowd_control_state.Disable -> #(212, 213)
    crowd_control_state.Taunt -> #(216, 217)
    crowd_control_state.Detaunt -> #(220, 221)
    crowd_control_state.Blind -> #(224, 225)
    crowd_control_state.Knockback -> #(228, 229)
    crowd_control_state.Pushback -> #(232, 233)
    crowd_control_state.Pull -> #(236, 237)
    crowd_control_state.PositionSwitch -> #(240, 241)
    crowd_control_state.Tether -> #(244, 245)
    crowd_control_state.Snare -> #(248, 249)
    crowd_control_state.Interrupt -> #(260, 261)
    crowd_control_state.Daze -> #(266, 267)
    crowd_control_state.Subdue -> #(271, 272)
    crowd_control_state.Grounded -> #(292, 293)
    crowd_control_state.DisableCinematic -> #(297, 298)
    crowd_control_state.AbilityRestriction -> #(302, 303)
    crowd_control_state.Other(number) ->
      panic as {
        "the state "
        <> int.to_string(number)
        <> " is no state of Unit.CodeEnumCCState, which the plan fails the load for"
      }
  }
}

/// The ccStateMask of the Spell4CCConditions row a Spell4 conditions id names, which is
/// the states that spell's press refuses (bit n is state n): 0 for the id 0, none; an id
/// whose row the table lacks is an error, never a mask of 0 that would let a held unit
/// act (`Spell4.spell4CCConditionsIdCaster`, `Spell4.spell4CCConditionsIdTarget`).
pub fn mask_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Int, Nil) {
  case id {
    0 -> Ok(0)
    id ->
      spell4_cc_conditions.get(tables:, id: Spell4CCConditionsId(id))
      |> result.map(fn(row) { row.cc_state_mask })
  }
}

/// The load's check that no Spell4CCConditions row asks for a held state
/// (`ccStateFlagsRequired`, the column that makes `CheckSpellCCConditions` give a
/// Caster_MustBe or Target_MustBe result): the client's 12 rows hold 0, and the server
/// reads no MustBe result, so a row that asks fails the load naming its id (issue 336).
pub fn requirements() -> List(table_store.Requirement) {
  [
    table_store.Requirement(
      from_table: "Spell4CCConditions",
      column: "ccStateFlagsRequired, which asks for a held state and gives a MustBe result that the server does not read (#336)",
      to_table: "a Spell4CCConditions row whose ccStateFlagsRequired is 0",
      missing: fn(tables) {
        spell4_cc_conditions.all(tables)
        |> list.filter(fn(row) { row.cc_state_flags_required != 0 })
        |> list.map(fn(row) { row.id })
      },
    ),
  ]
}
