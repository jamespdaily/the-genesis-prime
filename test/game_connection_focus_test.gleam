//// A healer's Focus on the game connection (`genesis_prime/game/connection/resource`):
//// held from entry, paid at each go of a Focus spell, recovered on the connection's own
//// timer, kept current when worn items move its maximum, and stopped by death and leaving.
//// Expected values come from these places:
//// - The client: `opcode.0x935` (a 32-bit unit, a 5-bit stat, a float) and `ApplyUnitStat`
////   0x1403d9a60 case 1 (stat 1 is Focus, the unit's +0x218); `opcode.0x93a` (a property's
////   base and value); `GetMaxFocus` 0x14064a810 (the maximum is property 5's value).
//// - The client's rows (`table_rows -- Spell4 58841`): Emission, a Medic's channel, costs 15
////   of type 15 (Focus) with a channel of delay 410, maximum 1250 and pulse 410: 3 gos;
////   (`table_rows -- UnitProperty2 108`, `-- GameFormula 88`): a recovery share of 0.011
////   each 500 ms, so a pool of 1000 recovers 1000 x 0.011 x 0.5 = 5.5 a tick.
//// - The server's choice: the pool is a flat 1000 plus what worn items add, full at
////   entry and when coming back (migration 0048).
//// - `table_rows -- ItemStat 12`, `-- ItemBudget 3`, `-- Item2 11671`: boots whose one
////   budget share of 1.0 is property 5 (valuePerPoint 1.5) at power level 8.

import character_tables
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_news
import genesis_prime/message/float32
import genesis_prime/message/item_place
import genesis_prime/message/unit_float_stat_changed.{
  type UnitFloatStatChanged, UnitFloatStatChanged,
}
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/message/unit_stat.{UnitStat}
import genesis_prime/message/unit_stat_float.{UnitStatFloat}
import genesis_prime/message/unit_stat_value
import genesis_prime/shared/class_resource
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/store.{type HeldItem, Character, HeldItem}
import genesis_prime/table/id.{ClassId, Item2Id}
import gleam/list
import gleam/option.{None}
import gleam/result
import owned_test
import resource_frames_support as resources

/// Emission's base: an ability a Medic is granted at level 6 (SpellLevel row 1221).
const emission_base = 38_210

/// The level at which a Medic first holds a Focus spell: its level grants that cost Focus
/// start at 6 (`table_rows -- SpellLevel`).
const first_level = 6

/// The Focus pool and its Spell4 cost, from the rows and the decision above.
const pool = 1000.0

/// 1000 x 0.011 x 0.5 (UnitProperty2 108 defaults, GameFormula 88).
const tick = 5.5

fn bits(points: Float) -> Int {
  float32.to_bits(points)
}

fn focus_changed(
  unit_id unit_id: Int,
  to points: Float,
) -> UnitFloatStatChanged {
  UnitFloatStatChanged(unit_id:, stat_id: 1, value: bits(points))
}

pub fn a_medics_emission_pays_15_focus_at_each_of_its_3_gos_as_0x935_of_stat_1_and_the_pool_recovers_5_5_each_500_ms_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, burst, unit_id, bag_index) =
    game_connection_support.entered_burst_with_spell_trees(
      class_id: 4,
      level: first_level,
      ability: emission_base,
    )
  let own = game_connection_support.player_in(burst)
  assert list.filter(own.tail.stats, fn(stat) { stat.stat_id == 1 })
    == [
      UnitStat(
        stat_id: 1,
        value: unit_stat_value.Float(UnitStatFloat(value: bits(pool))),
      ),
    ]
    as "the player's own 0x262 carries stat 1 in the float form at the pool"
  assert list.map(
      list.filter(own.tail.properties, fn(property) {
        property.property_id == 5
      }),
      fn(property) { #(property.base, property.value) },
    )
    == [#(bits(pool), bits(pool))]
    as "and property 5, the maximum, at the pool"
  let state = game_connection_support.watched_by(state:, viewers: [2, 3])
  let #(state, steps) =
    game_connection_support.pressed_until(
      state:,
      bag_index:,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 2300,
    )
  let assert [pressed, ..gos] = steps as "the press is the first step"
  assert game_connection_support.refusal_results(pressed) == []
    as "Emission is accepted: the Medic holds 1000 Focus of the 15 (0x1403b3320 case 0xe)"
  assert resources.changes_written(pressed) == []
    as "nothing is paid at the press: the first go pays (Spell4.innateCost0.timing)"
  assert list.flat_map(gos, resources.changes_written)
    == [
      focus_changed(unit_id:, to: 985.0),
      focus_changed(unit_id:, to: 970.0),
      focus_changed(unit_id:, to: 955.0),
    ]
    as "the gos at 410, 820 and 1230 ms pay 15 each, one 0x935 of stat 1 each, in that order"
  assert list.flat_map([pressed, ..steps], resources.resource_timers_started)
    == [#(class_resource.focus_timer, 500)]
    as "the first payment below the pool starts the Focus timer at GameFormula 88's 500 ms, and no later go starts a second"
  let #(state, first_tick) =
    game_connection_support.fired_at(
      state:,
      timer: class_resource.focus_timer,
      ms: 2730,
    )
  assert resources.changes_written(first_tick)
    == [focus_changed(unit_id:, to: 955.0 +. tick)]
    as "955 + 5.5: one 0x935 of stat 1"
  assert game_connection_support.tells_to_players_but_moves(first_tick) == []
    as "to the player's own client only: a Focus change is told to no viewer (two are watching)"
  assert resources.resource_timers_started(first_tick)
    == [#(class_resource.focus_timer, 500)]
    as "the pool is still below its maximum: the timer starts again"
  let #(state, ticks) = ticked_until_full(state:, from_ms: 3230, written: [])
  assert list.last(ticks) == Ok(focus_changed(unit_id:, to: pool))
    as "the last tick clamps at the pool"
  let #(_, full) =
    game_connection_support.fired_at(
      state:,
      timer: class_resource.focus_timer,
      ms: 20_000,
    )
  assert resources.changes_written(full) == []
    && resources.resource_timers_started(full) == []
    as "a timer fed at the full pool writes nothing and starts none"
}

/// The Focus timer fed each 500 ms until a tick starts none, with every 0x935 written.
fn ticked_until_full(
  state state: game_connection.State,
  from_ms ms: Int,
  written written: List(UnitFloatStatChanged),
) -> #(game_connection.State, List(UnitFloatStatChanged)) {
  let #(state, taken) =
    game_connection_support.fired_at(
      state:,
      timer: class_resource.focus_timer,
      ms:,
    )
  let written = list.append(written, resources.changes_written(taken))
  case resources.resource_timers_started(taken) {
    [] -> #(state, written)
    [_, ..] -> ticked_until_full(state:, from_ms: ms + 500, written:)
  }
}

/// Item2 11671 (boots, ItemStat 12, ItemBudget 3, the feet slot: bag index 4, ItemSlot 5's
/// flags 16), its guid 9.
fn boots(location location: Int, bag_index bag_index: Int) -> HeldItem {
  HeldItem(
    item_guid: 9,
    item2_id: Item2Id(fixture_tables.root(table: "Item2", id: 11_671)),
    location:,
    bag_index:,
    stack_count: 1,
    words: store.ItemWords(
      random_stats: 0,
      charges: 0,
      item_flags: 0,
      expires_at_unix_ms: None,
    ),
  )
}

fn medic_holding(items items: List(HeldItem)) -> game_connection.State {
  game_connection_support.entered_with_items(
    character: Character(
      ..game_connection_support.world_character(),
      class_id: ClassId(4),
    ),
    saved_experience: None,
    items:,
  )
}

/// The entries of the 0x93a the step writes.
fn properties_written(
  taken taken: ConnectionStep(Request),
) -> List(UnitProperty) {
  list.flat_map(
    game_connection_support.decoded(
      game_connection_support.written(taken),
      0x093A,
      unit_properties_changed.decode,
    ),
    fn(message) { message.properties },
  )
}

fn moved(
  state state: game_connection.State,
  from from: item_place.ItemPlace,
  to to: item_place.ItemPlace,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.item_change_saved(
    state:,
    ms:,
    message: game_connection_support.item_moved_message(from:, to:),
  )
}

pub fn wearing_a_focus_pool_item_raises_property_5_by_0x93a_and_starts_the_timer_that_fills_it_and_taking_it_off_clamps_the_value_with_one_0x935_test() -> Nil {
  use <- owned_test.run(60_000)
  let bag = item_place.ItemPlace(location: 1, bag_index: 0)
  let worn = item_place.ItemPlace(location: 0, bag_index: 4)
  let state = medic_holding(items: [boots(location: 1, bag_index: 0)])
  let #(state, equipped) = moved(state:, from: bag, to: worn, ms: 1000)
  let assert [pool_entry] =
    list.filter(properties_written(taken: equipped), fn(property) {
      property.property_id == 5
    })
    as "0x93a carries property 5, the maximum"
  assert pool_entry.base == pool_entry.value && pool_entry.value > bits(pool)
    as "the boots raise the maximum above the base pool of 1000"
  let maximum = float32_of(bits: pool_entry.value)
  assert maximum >. pool
  assert resources.changes_written(equipped) == []
    as "a raised maximum moves no value: no 0x935"
  assert resources.resource_timers_started(equipped)
    == [#(class_resource.focus_timer, 500)]
    as "the pool is below its new maximum, so the timer that fills it starts"
  let #(state, ticked) =
    game_connection_support.fired_at(
      state:,
      timer: class_resource.focus_timer,
      ms: 1500,
    )
  let assert [tick_written] = resources.changes_written(ticked)
    as "one tick, one 0x935"
  assert tick_written.stat_id == 1
    && near(
      float32_of(bits: tick_written.value),
      pool +. 0.011 *. maximum *. 0.5,
    )
    as "1000 + 0.011 x the new maximum x 0.5 (UnitProperty2 108, GameFormula 88)"
  let #(_, off) = moved(state:, from: worn, to: bag, ms: 2000)
  let assert [lowered] = resources.changes_written(off)
    as "taking the boots off lowers the maximum below the value held: one 0x935"
  assert lowered.stat_id == 1 && lowered.value == bits(pool)
    as "at the new maximum, the base pool"
  assert resources.resource_timers_started(off) == []
    as "the pool is full again: no timer starts"
  assert resources.resource_timers_cancelled(off)
    == [class_resource.focus_timer]
    as "the timer that was filling the pool is cancelled, since the pool is full"
}

fn float32_of(bits bits: Int) -> Float {
  let assert Ok(number) =
    float32.bits(number: bits) |> result.try(float32.value)
    as "the server writes finite 32-bit floats"
  number
}

fn near(first: Float, second: Float) -> Bool {
  first >. second -. 0.001 && first <. second +. 0.001
}

/// The Medic of Emission pressed at 1000 ms, taken to the first go's payment (985 held)
/// at 1500, with a foe that can kill it.
fn medic_below_its_pool() -> #(game_connection.State, Int) {
  let #(state, _, unit_id, bag_index) =
    game_connection_support.entered_burst_with_spell_trees(
      class_id: 4,
      level: first_level,
      ability: emission_base,
    )
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(state, steps) =
    game_connection_support.pressed_until(
      state:,
      bag_index:,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 1500,
    )
  assert list.flat_map(steps, resources.changes_written)
    == [focus_changed(unit_id:, to: 985.0)]
    as "the first go has paid 15, and the Focus timer runs"
  #(state, unit_id)
}

pub fn a_dead_healers_timer_is_cancelled_a_late_fire_or_one_after_leaving_writes_nothing_and_coming_back_writes_one_0x935_at_the_pool_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, unit_id) = medic_below_its_pool()
  let #(state, killed) =
    game_connection_support.feed(
      state,
      game_connection_support.a_killing_strike(),
    )
  assert list.contains(
    resources.resource_timers_cancelled(killed),
    class_resource.focus_timer,
  )
    as "death cancels every running timer, the Focus timer among them"
  assert resources.changes_written(killed) == []
    as "death writes no Focus change"
  let #(state, late) =
    game_connection_support.fired_at(
      state:,
      timer: class_resource.focus_timer,
      ms: 2000,
    )
  assert resources.changes_written(late) == []
    && resources.resource_timers_started(late) == []
    as "a tick that fires after the cancel writes nothing"
  let #(_, back) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.wake_here(),
    )
  assert resources.changes_written(back) == [focus_changed(unit_id:, to: pool)]
    as "coming back refills the pool: one 0x935 at the maximum, as health comes back full"
  let #(state, _) = medic_below_its_pool()
  let #(state, camp_asked) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.camp_request_message(True),
    )
  let #(state, camped) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.camp_finished_message(),
    )
  assert list.contains(
    list.append(
      resources.resource_timers_cancelled(camp_asked),
      resources.resource_timers_cancelled(camped),
    ),
    class_resource.focus_timer,
  )
    as "leaving the stay cancels the running timer"
  assert resources.changes_written(camped) == [] as "and writes nothing"
  let #(_, after) =
    game_connection_support.fired_at(
      state:,
      timer: class_resource.focus_timer,
      ms: 40_000,
    )
  assert resources.changes_written(after) == []
    && resources.resource_timers_started(after) == []
    as "a tick after leaving writes nothing"
}

/// Recharge's base: an ability a Medic is granted at level 14 (SpellLevel row 1224, Spell4
/// 42596).
const recharge_base = 26_786

/// What a viewer is told about a cast: its start, goes, ticks and end.
fn is_cast_news(news: unit_news.News) -> Bool {
  case news {
    unit_news.CastStarted(..)
    | unit_news.CastWent(..)
    | unit_news.CastMissed(..)
    | unit_news.CastTicked(..)
    | unit_news.CastTargetsRemoved(..)
    | unit_news.CastStackRemoved(..)
    | unit_news.CastFinished(..)
    | unit_news.CastInterrupted(..) -> True
    _ -> False
  }
}

pub fn a_medics_recharge_sends_the_pool_back_its_focus_and_the_actuators_to_0_as_0x935_to_the_player_only_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 42596 (Recharge, castTime 2000): its Focus share for 4 Actuators is 0.20 of the
  // maximum (200 of 1000), and its -4 of vital 18 empties the Medic's slot 1 (stat 3). After
  // Emission's three payments the pool is 955, so 955 + 200 clamps at 1000: the wire shows
  // the clamp, which is what the player's client holds.
  let #(state, _, unit_id, emission_index) =
    game_connection_support.entered_burst_with_spell_trees(
      class_id: 4,
      level: 14,
      ability: emission_base,
    )
  let recharge_index =
    game_connection_support.bag_index_of(
      tables: character_tables.shared(),
      class_id: 4,
      level: 14,
      ability: recharge_base,
    )
  let state = game_connection_support.watched_by(state:, viewers: [2, 3])
  let #(state, emission) =
    game_connection_support.pressed_until(
      state:,
      bag_index: emission_index,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 2300,
    )
  assert list.last(list.flat_map(emission, resources.changes_written))
    == Ok(focus_changed(unit_id:, to: 955.0))
    as "Emission's three gos leave 955 of 1000"
  let #(_, steps) =
    game_connection_support.pressed_until(
      state:,
      bag_index: recharge_index,
      client_cast_id: 2,
      ms: 3000,
      until_ms: 5100,
    )
  let assert [pressed, ..gos] = steps as "the press is the first step"
  assert game_connection_support.refusal_results(pressed) == []
    as "Recharge is accepted with 4 Actuators held (prerequisite 24152 needs 1)"
  assert list.flat_map(steps, resources.changes_written)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: bits(0.0)),
      focus_changed(unit_id:, to: pool),
    ]
    as "its go at 5000 ms writes the Actuators to 0 (stat 3) and Focus to the full pool (stat 1), one 0x935 each, the class slot first"
  assert list.flat_map(gos, resources.resource_timers_cancelled)
    == [class_resource.focus_timer]
    as "the pool is full again, so the Focus timer Emission started is cancelled"
  assert list.all(
    list.flat_map(steps, game_connection_support.news_broadcast),
    is_cast_news,
  )
    as "the map is told the cast to relay to the two viewers watching and nothing of the player's resources"
}
