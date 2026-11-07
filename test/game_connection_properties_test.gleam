//// A player's properties on the game connection
//// (`genesis_prime/game/connection/properties`): a property modifier of the player's
//// own spell starts at its go and ends after its duration, the player's client and
//// each viewer are told the property's base and value, a viewer that arrives while it
//// lasts is created with the value, and the life follows the maxima. Expected values
//// come from these places.
//// - `opcode.0x93a`: the message holds the unit and an entry for each property, its
////   UnitProperty2 id, its base and its value as 32-bit floats; the client stores them
////   as sent, so a viewer's client holds what the server worked out.
//// - `Spell4Effects.effectType.11.change`: a value is x * dataBits02 + dataBits03; the
////   tables' rows are 135954 (BaseCritChance 0.0, multiplier 1.0, flat 0.08 = 0x3da3d70a,
////   8000 ms) as the client holds it, and a planted row of BaseHealth +100.0 for 2000 ms
////   (`character_tables.shared_with_property_modifiers`); the Medic presses Paralytic
////   Surge, whose go has no target here and goes at once.
//// - `UnitProperty2.client_value`: a viewer's property is the value its 0x262 or the
////   last 0x93a sent, so a viewer arriving mid-buff is created with the value.
//// - The health regeneration of `player_life`: a tick adds floor(maximum x 0.025 x
////   HealthRegenMultiplier 1.0), so the maximum a modifier raises changes the tick.

import character_tables
import connection_rule_support
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
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map.{SeenBy}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test

/// 135954's flat amount as the 32-bit float its row holds.
const point_zero_eight_bits = 0x3DA3D70A

const crit_chance = 102

const base_health = 7

fn medic_entering(
  saved saved: Option(Int),
) -> #(game_connection.State, ConnectionStep(Request)) {
  let tables = character_tables.shared_with_property_modifiers()
  let fresh = support.accepted(Settings(..support.settings(), tables:)).0
  support.entered_saved(
    in_character_select: support.in_select_from(fresh),
    character: Character(..support.world_character(), class_id: ClassId(4)),
    saved_health: saved,
  )
}

/// The player's level 1 maximum health: CreatureLevel row 1's Base Health, 135.97, and
/// the Novice armor's 600, rounded (`player.level1_base_health`,
/// `game_connection_support.full_health`). It is the BaseHealth base the player's 0x262
/// and the 0x93a carry.
fn maximum_health() -> Float {
  int.to_float(support.full_health)
}

fn pressed(
  state state: game_connection.State,
) -> #(game_connection.State, ConnectionStep(Request)) {
  support.press_paralytic_surge(state:, client_cast_id: 1)
}

/// The entries of each 0x93a a step writes to the player's client, in order.
fn written_properties(
  taken taken: ConnectionStep(Request),
) -> List(List(UnitProperty)) {
  support.decoded(
    support.heard(taken, support.keyed()),
    0x093A,
    unit_properties_changed.decode,
  )
  |> list.map(fn(message: unit_properties_changed.UnitPropertiesChanged) {
    assert message.unit_id == support.own_unit_id
      as "the message names the player's own unit"
    message.properties
  })
}

/// The news a step tells the viewer connection `viewer`, in order.
fn news_told(
  taken taken: ConnectionStep(Request),
  viewer viewer: Int,
) -> List(News) {
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
}

fn bits(value value: Float) -> Int {
  float32.to_bits(value)
}

pub fn a_modifier_starting_at_a_go_writes_0x93a_to_the_player_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, _) = medic_entering(saved: None)
  let maximum = maximum_health()
  let state = support.watched_by(state:, viewers: [2, 3])
  let #(_, taken) = pressed(state:)
  let crit =
    UnitProperty(
      property_id: crit_chance,
      base: 0x00000000,
      value: point_zero_eight_bits,
    )
  let health =
    UnitProperty(
      property_id: base_health,
      base: bits(value: maximum),
      value: bits(value: maximum +. 100.0),
    )
  let written = written_properties(taken:)
  assert list.length(written) == 2 as "one 0x93a for each property that changed"
  assert list.contains(written, [crit])
    as "BaseCritChance goes from 0.0 to 0.08, base and value"
  assert list.contains(written, [health])
    as "BaseHealth goes from its maximum to 100 more"
  list.each([2, 3], fn(viewer) {
    let told = news_told(taken:, viewer:)
    assert list.contains(told, PropertiesChanged(properties: [crit]))
      as "each viewer is told the same entries"
    assert list.contains(told, PropertiesChanged(properties: [health]))
  })
}

pub fn the_modifiers_end_writes_0x93a_with_the_value_back_at_its_base_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, _) = medic_entering(saved: None)
  let maximum = maximum_health()
  let state = support.watched_by(state:, viewers: [2])
  let #(state, started) = pressed(state:)
  // The press started the end of each modifier (2000 and 8000 ms) among its timers.
  let #(_, ended) =
    list.fold(
      connection_rule_support.timers_started(started),
      #(state, []),
      fn(so_far, timer) {
        let #(state, steps) = so_far
        let #(state, taken) = support.feed(state, OwnEvent(TimerFired(timer)))
        #(state, [taken, ..steps])
      },
    )
  let crit_again =
    UnitProperty(property_id: crit_chance, base: 0x00000000, value: 0x00000000)
  let health_again =
    UnitProperty(
      property_id: base_health,
      base: bits(value: maximum),
      value: bits(value: maximum),
    )
  let written = list.flat_map(ended, fn(taken) { written_properties(taken:) })
  assert list.length(written) == 2 as "each modifier's end is told once"
  assert list.contains(written, [crit_again])
  assert list.contains(written, [health_again])
    as "with the value back at its base"
  let told = list.flat_map(ended, fn(taken) { news_told(taken:, viewer: 2) })
  assert list.contains(told, PropertiesChanged(properties: [crit_again]))
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
  use <- owned_test.run(120_000)
  let #(state, _) = medic_entering(saved: None)
  let maximum = maximum_health()
  let #(state, started) = pressed(state:)
  let assert [#(4, PeerNews(news: Appeared(unit:), ..))] =
    support.peer_tells(arriving(state:, viewer: 4))
    as "the player's connection sends the arriving viewer its 0x262"
  let property = fn(id) {
    list.find(unit.tail.properties, fn(property) { property.property_id == id })
  }
  assert property(crit_chance)
    == Ok(UnitProperty(
      property_id: crit_chance,
      base: 0x00000000,
      value: point_zero_eight_bits,
    ))
    as "the 0x262 carries the value the buff gives, which the client holds as sent"
  assert property(base_health)
    == Ok(UnitProperty(
      property_id: base_health,
      base: bits(value: maximum),
      value: bits(value: maximum +. 100.0),
    ))
  // After every modifier ended the next viewer is created with the bases.
  let #(state, _) =
    list.fold(
      connection_rule_support.timers_started(started),
      #(state, Nil),
      fn(so_far, timer) {
        #(support.feed(so_far.0, OwnEvent(TimerFired(timer))).0, Nil)
      },
    )
  let assert [#(5, PeerNews(news: Appeared(unit: later), ..))] =
    support.peer_tells(arriving(state:, viewer: 5))
  assert list.find(later.tail.properties, fn(property) {
      property.property_id == crit_chance
    })
    == Error(Nil)
    as "BaseCritChance is no longer listed: its value is its table default again"
}

pub fn the_players_health_ticks_by_the_maximum_a_modifier_raised_test() -> Nil {
  use <- owned_test.run(120_000)
  // Saved at 300 of a maximum above it, the player regenerates floor(maximum x 0.025)
  // a tick; while BaseHealth is 100 higher the tick is floor((maximum + 100) x 0.025).
  let #(state, _) = medic_entering(saved: Some(300))
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
