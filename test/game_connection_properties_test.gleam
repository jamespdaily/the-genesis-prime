//// A player's properties on the game connection
//// (`genesis_prime/game/connection/properties`): a property modifier of the player's
//// own spell starts at its go and ends after its duration, the player's client and
//// each viewer are told the property's base and value, a viewer that arrives while it
//// lasts is created with the value, and the life follows the maxima. Expected values
//// come from these places.
//// - `opcode.0x93a`: the message holds the unit and an entry for each property, its
////   UnitProperty2 id, its base and its value as 32-bit floats; the client stores them
////   as sent, so a viewer's client holds what the server worked out.
//// - `Spell4Effects.effectType.11.change`: a value is x * dataBits02 + dataBits03. The
////   Spellslinger's Gate 34355 holds the client's row 67777: FallingDamageMultiplier
////   (property 134), multiplier 0.0, flat 0.0, 400 ms, aimed at the caster, so the
////   property goes from its UnitProperty2 default 1.0 to 0.0. A row of BaseHealth
////   +100.0 for 2000 ms is added to Gate for these tests (`fixture_tables.added`),
////   since no row of a level-1 ability changes a maximum. The crit buff 135954 of
////   Crit Sev Buff 57030 (Mind Burst's Proxy 135961) is not pressable at level 1: its
////   Proxy sits behind Prerequisite 23344, type 50 value 57027, a node the level-1
////   Esper does not hold, so `cast_modifier_test` reads it at the rule's level.
//// - `UnitProperty2.client_value`: a viewer's property is the value its 0x262 or the
////   last 0x93a sent, so a viewer arriving mid-buff is created with the value.
//// - The health regeneration of `player_life`: a tick adds floor(maximum x 0.025 x
////   HealthRegenMultiplier 1.0), so the maximum a modifier raises changes the tick.

import connection_rule_support
import fixture_tables
import game_connection_support as support
import genesis_prime/client_connection.{
  type News, type Request, Appeared, PeerNews, PropertiesChanged,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/message/float32
import genesis_prime/message/player_health
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/step.{
  type ConnectionStep, ConnectionId, OwnEvent, TimerFired, TimerId,
}
import genesis_prime/table/loader/store as store_tables
import genesis_prime/world_map/map.{SeenBy}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test
import planted_table

/// UnitProperty2 134's default 0x3f800000 (1.0) and the value 67777 gives it, 0.0.
const one_bits = 0x3F800000

const falling_damage = 134

const base_health = 7

/// The Spellslinger's place of Gate in its bag (Class 7's level-1 SpellLevel rows 1011,
/// 1036 and 1236: the bases of 43468, 34718 and 34355, in that order).
const gate = 2

/// Runs the body on the client's tables with BaseHealth +100.0 for 2000 ms added to Gate
/// beside its row 67777, a copy of that row: no row of a level-1 ability changes a
/// maximum, so the BaseHealth case needs a row of its own.
fn with_the_health_modifier(body body: fn(store_tables.Tables) -> a) -> a {
  fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 67_777,
    id: 99_901,
    with: [
      #("dataBits00", planted_table.Integer(base_health)),
      #("dataBits02", planted_table.Integer(1_065_353_216)),
      #("dataBits03", planted_table.Integer(1_120_403_456)),
      #("durationTime", planted_table.Integer(2000)),
    ],
    body:,
  )
}

/// A Spellslinger of these tables in the world.
fn spellslinger(
  tables tables: store_tables.Tables,
  saved saved: Option(Int),
) -> game_connection.State {
  support.entered_with(
    settings: Settings(..support.settings(), tables:),
    class_id: 7,
    saved_health: saved,
  ).0
}

/// The player's level 1 maximum health: CreatureLevel row 1's Base Health, 135.97, and
/// the Novice armor's 600, rounded (`player.level1_base_health`,
/// `game_connection_support.full_health`). It is the BaseHealth base the player's 0x262
/// and the 0x93a carry.
fn maximum_health() -> Float {
  int.to_float(support.full_health)
}

/// Gate pressed at 1 s and the cast's timers up to 1.4 s, each strike landing: the steps
/// that take the modifiers' start.
fn pressed(
  state state: game_connection.State,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  support.pressed_until(
    state:,
    bag_index: gate,
    client_cast_id: 1,
    ms: 1000,
    until_ms: 1400,
  )
}

/// The entries of each 0x93a a step writes to the player's client, in order.
fn written_properties(
  steps steps: List(ConnectionStep(Request)),
) -> List(List(UnitProperty)) {
  list.flat_map(steps, fn(taken) {
    support.decoded(
      support.heard(taken, support.keyed()),
      0x093A,
      unit_properties_changed.decode,
    )
  })
  |> list.map(fn(message: unit_properties_changed.UnitPropertiesChanged) {
    assert message.unit_id == support.own_unit_id
      as "the message names the player's own unit"
    message.properties
  })
}

/// The news the steps tell the viewer connection `viewer`, in order.
fn news_told(
  steps steps: List(ConnectionStep(Request)),
  viewer viewer: Int,
) -> List(News) {
  list.flat_map(steps, fn(taken) {
    list.filter_map(support.peer_tells(taken), fn(tell) {
      case tell.0 == viewer {
        True -> {
          let PeerNews(unit_id:, news:) = tell.1
          assert unit_id == support.own_unit_id
            as "the news names the player's own unit"
          Ok(news)
        }
        False -> Error(Nil)
      }
    })
  })
}

fn bits(value value: Float) -> Int {
  float32.to_bits(value)
}

pub fn a_modifier_starting_at_a_go_writes_0x93a_to_the_player_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_the_health_modifier
  let state = spellslinger(tables:, saved: None)
  let maximum = maximum_health()
  let state = support.watched_by(state:, viewers: [2, 3])
  let #(_, taken) = pressed(state:)
  let falling =
    UnitProperty(property_id: falling_damage, base: one_bits, value: 0x00000000)
  let health =
    UnitProperty(
      property_id: base_health,
      base: bits(value: maximum),
      value: bits(value: maximum +. 100.0),
    )
  let written = written_properties(steps: taken)
  assert list.length(written) == 2 as "one 0x93a for each property that changed"
  assert list.contains(written, [falling])
    as "FallingDamageMultiplier goes from 1.0 to 0.0, base and value"
  assert list.contains(written, [health])
    as "BaseHealth goes from its maximum to 100 more"
  list.each([2, 3], fn(viewer) {
    let told = news_told(steps: taken, viewer:)
    assert list.contains(told, PropertiesChanged(properties: [falling]))
      as "each viewer is told the same entries"
    assert list.contains(told, PropertiesChanged(properties: [health]))
  })
}

pub fn the_modifiers_end_writes_0x93a_with_the_value_back_at_its_base_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_the_health_modifier
  let state = spellslinger(tables:, saved: None)
  let maximum = maximum_health()
  let state = support.watched_by(state:, viewers: [2])
  let #(state, started) = pressed(state:)
  // The press started the end of each modifier (400 and 2000 ms) among its timers.
  let #(_, ended) =
    list.fold(
      list.flat_map(started, connection_rule_support.timers_started),
      #(state, []),
      fn(so_far, timer) {
        let #(state, steps) = so_far
        let #(state, taken) = support.feed(state, OwnEvent(TimerFired(timer)))
        #(state, [taken, ..steps])
      },
    )
  let falling_again =
    UnitProperty(property_id: falling_damage, base: one_bits, value: one_bits)
  let health_again =
    UnitProperty(
      property_id: base_health,
      base: bits(value: maximum),
      value: bits(value: maximum),
    )
  let written = written_properties(steps: ended)
  assert list.length(written) == 2 as "each modifier's end is told once"
  assert list.contains(written, [falling_again])
  assert list.contains(written, [health_again])
    as "with the value back at its base"
  let told = news_told(steps: ended, viewer: 2)
  assert list.contains(told, PropertiesChanged(properties: [falling_again]))
    as "and told to the viewer"
  assert list.contains(told, PropertiesChanged(properties: [health_again]))
}

/// The step in which the map tells the player's connection that viewer `viewer` sees it.
fn arriving(
  state state: game_connection.State,
  viewer viewer: Int,
) -> ConnectionStep(Request) {
  support.feed(
    state,
    support.sent_by_the_map(SeenBy(
      by: ConnectionId(viewer),
      stay: support.viewer_stay(viewer),
    )),
  ).1
}

pub fn a_viewer_arriving_while_the_buff_lasts_is_created_with_the_value_in_its_0x262_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_the_health_modifier
  let state = spellslinger(tables:, saved: None)
  let maximum = maximum_health()
  let #(state, started) = pressed(state:)
  let assert [#(4, PeerNews(news: Appeared(unit:), ..))] =
    support.peer_tells(arriving(state:, viewer: 4))
    as "the player's connection sends the arriving viewer its 0x262"
  let property = fn(id) {
    list.find(unit.tail.properties, fn(property) { property.property_id == id })
  }
  assert property(falling_damage)
    == Ok(UnitProperty(
      property_id: falling_damage,
      base: one_bits,
      value: 0x00000000,
    ))
    as "the 0x262 carries the value the modifier gives, which the client holds as sent"
  assert property(base_health)
    == Ok(UnitProperty(
      property_id: base_health,
      base: bits(value: maximum),
      value: bits(value: maximum +. 100.0),
    ))
  // After every modifier ended the next viewer is created with the bases.
  let #(state, _) =
    list.fold(
      list.flat_map(started, connection_rule_support.timers_started),
      #(state, Nil),
      fn(so_far, timer) {
        #(support.feed(so_far.0, OwnEvent(TimerFired(timer))).0, Nil)
      },
    )
  let assert [#(5, PeerNews(news: Appeared(unit: later), ..))] =
    support.peer_tells(arriving(state:, viewer: 5))
  assert list.find(later.tail.properties, fn(property) {
      property.property_id == falling_damage
    })
    == Error(Nil)
    as "FallingDamageMultiplier is no longer listed: its value is its table default again"
}

pub fn the_players_health_ticks_by_the_maximum_a_modifier_raised_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- with_the_health_modifier
  // Saved at 300 of a maximum above it, the player regenerates floor(maximum x 0.025)
  // a tick; while BaseHealth is 100 higher the tick is floor((maximum + 100) x 0.025).
  let state = spellslinger(tables:, saved: Some(300))
  let maximum = support.full_health
  let #(state, _) = pressed(state:)
  let #(_, tick) = support.feed(state, OwnEvent(TimerFired(TimerId(8))))
  let assert [health] =
    support.decoded(
      support.heard(tick, support.keyed()),
      0x092F,
      player_health.decode,
    )
    as "one health tick"
  let raised = float.truncate(int.to_float(maximum + 100) *. 0.025)
  let plain = float.truncate(int.to_float(maximum) *. 0.025)
  assert raised != plain
    as "the two maxima give different ticks, so the test can tell them apart"
  assert health.health == 300 + raised
    as "the health the life kept, 300, plus a share of the raised maximum"
}
