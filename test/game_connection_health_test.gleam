//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out. These tests cover
//// the health a player leaves with: each save carries it, a save while dead
//// carries 0, and the next entry is at it (a dead entry is the death test's).
////
//// Expected values come from these places.
//// - A level-1 player's full health is 736 (`player.level1_base_health`), and
////   the Beast's 12 against the tests' player (Armor 250) takes the shield 2 of
////   450 and the health 1, so a hit leaves 735 and 448
////   (`player_life_test`, Armor 250).
//// - The client shows stat 0 of the player's 0x262 as the unit's health and
////   Base Health, property 7, as its maximum (`opcode.0x262`,
////   `vector.opcode.0x262.health`).
//// - A save while dead keeps 0, the health the client creates a unit dead at
////   (`0x140457bc5`, `death.enter_dead`); an entry with none saved is at full
////   health, alive. A saved health above the maximum enters at the maximum, and
////   one above 0 at or below it enters at itself: the server's choice, since the
////   client holds no saved health.

import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{Appeared, FromStore, PeerNews}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/float32
import genesis_prime/message/player_health.{PlayerHealth}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/step.{
  type ConnectionStep, ConnectionId, LogError, OwnEvent, PeerClosed, TimerFired,
  TimerId,
}
import genesis_prime/store.{ForMove, HealthRefused}
import genesis_prime/world_map/map.{SeenBy}
import genesis_prime/world_map/unit_fields
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test

/// What the tests' player has left of its full health after one of the Beast's
/// strikes.
const after_a_strike = 735

/// The tests' player in the world, struck once by the Beast.
fn struck() -> game_connection.State {
  game_connection_support.feed(
    game_connection_support.in_world(),
    game_connection_support.a_beast_strike(game_connection_support.own_unit_id),
  ).0
}

/// The tests' player, dead and seen by connection 2.
fn dead() -> game_connection.State {
  game_connection_support.dead_in_world().0
}

/// The step after the 60 s timer fired.
fn timer_fired(
  state: game_connection.State,
) -> ConnectionStep(client_connection.Request) {
  game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(2)))).1
}

/// The step after the client camped: its request, then its finish.
fn camp_finished(
  state: game_connection.State,
) -> ConnectionStep(client_connection.Request) {
  let #(state, _) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.camp_request_message(True),
    )
  game_connection_support.read(
    state:,
    bytes: game_connection_support.camp_finished_message(),
  ).1
}

/// The step after the client's socket closed.
fn dropped(
  state: game_connection.State,
) -> ConnectionStep(client_connection.Request) {
  game_connection_support.feed(state, OwnEvent(PeerClosed)).1
}

/// The 0x262 of the tests' player when the store gave it `saved_health`.
fn entry_unit(saved_health: Option(Int)) -> UnitCreatePlayer {
  game_connection_support.player_in(
    game_connection_support.entered_saved(
      in_character_select: game_connection_support.in_select(),
      character: game_connection_support.world_character(),
      saved_health:,
    ).1,
  )
}

/// Stat 0 of the unit: the health the client shows.
fn health_of(unit: UnitCreatePlayer) -> Result(Int, Nil) {
  unit_fields.stat(tail: unit.tail, stat_id: unit_fields.health_stat)
}

// ---- the saves carry the health ----

pub fn the_60_s_save_carries_the_health_the_player_has_now_test() -> Nil {
  use <- owned_test.run(10_000)
  assert game_connection_support.ask_request(
      timer_fired(game_connection_support.in_world()),
    )
    == game_connection_support.save_asked_keeping(
      sequence: 1,
      place: game_connection_support.entry_place(),
      health: Some(game_connection_support.full_health),
    )
    as "a player that has not been hurt saves its full health"
  assert game_connection_support.ask_request(timer_fired(struck()))
    == game_connection_support.save_asked_keeping(
      sequence: 1,
      place: game_connection_support.entry_place(),
      health: Some(after_a_strike),
    )
    as "a hurt player saves the health it has"
}

pub fn the_camp_save_carries_the_health_the_player_has_now_test() -> Nil {
  use <- owned_test.run(10_000)
  assert game_connection_support.ask_request(camp_finished(struck()))
    == game_connection_support.save_asked_keeping(
      sequence: 1,
      place: game_connection_support.entry_place(),
      health: Some(after_a_strike),
    )
}

pub fn the_drop_save_carries_the_health_the_player_has_now_test() -> Nil {
  use <- owned_test.run(10_000)
  assert game_connection_support.ask_request(dropped(struck()))
    == game_connection_support.save_asked_keeping(
      sequence: 1,
      place: game_connection_support.entry_place(),
      health: Some(after_a_strike),
    )
}

pub fn a_save_while_dead_keeps_0_and_the_place_of_the_body_test() -> Nil {
  use <- owned_test.run(10_000)
  let zero =
    game_connection_support.save_asked_keeping(
      sequence: 1,
      place: game_connection_support.entry_place(),
      health: Some(0),
    )
  assert game_connection_support.ask_request(timer_fired(dead())) == zero
    as "the 60 s save of a dead player keeps 0 and the place where the body lies, so it comes back dead (death.enter_dead)"
  assert game_connection_support.ask_request(camp_finished(dead())) == zero
    as "and so does the camp's"
  assert game_connection_support.ask_request(dropped(dead())) == zero
    as "and the drop's"
}

pub fn a_save_the_database_refused_for_the_health_is_an_error_and_the_player_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(TimerFired(TimerId(2))),
    )
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForMove(HealthRefused))),
    )
  let assert [line] = support.logs(taken)
  assert line.level == LogError
    as "the rule never asks to keep a health below 0, so a refusal is a bug"
  assert !support.stops(taken)
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(2))))
  assert support.asked(taken) != None
    as "the player goes on, and the timer tries again"
}

// ---- the entry is at the saved health ----

pub fn a_saved_health_below_the_maximum_is_the_stat_0_of_the_players_own_0x262_and_the_maximum_stays_property_7_test() -> Nil {
  use <- owned_test.run(10_000)
  let unit = entry_unit(Some(500))
  assert health_of(unit) == Ok(500)
    as "opcode.0x262: stat 0 is the health the client shows"
  let bits = float32.to_bits(int.to_float(game_connection_support.full_health))
  assert list.contains(
    unit.tail.properties,
    UnitProperty(property_id: 7, base: bits, value: bits),
  )
    as "Base Health, the maximum Unit:GetMaxHealth reads, stays full"
  assert unit_fields.stat(tail: unit.tail, stat_id: unit_fields.shield_stat)
    == Ok(450)
    as "the shield enters full as before"
}

pub fn a_saved_health_at_the_maximum_enters_at_the_maximum_test() -> Nil {
  use <- owned_test.run(10_000)
  assert health_of(entry_unit(Some(game_connection_support.full_health)))
    == Ok(game_connection_support.full_health)
}

pub fn a_saved_health_above_the_maximum_enters_at_the_maximum_test() -> Nil {
  use <- owned_test.run(10_000)
  assert health_of(entry_unit(Some(game_connection_support.full_health + 1)))
    == Ok(game_connection_support.full_health)
    as "a row that holds more than the level gives is capped at entry"
  assert health_of(entry_unit(Some(1_000_000)))
    == Ok(game_connection_support.full_health)
}

pub fn a_character_with_no_saved_health_enters_at_full_health_test() -> Nil {
  use <- owned_test.run(10_000)
  assert health_of(entry_unit(None)) == Ok(game_connection_support.full_health)
    as "nothing saved, as for a character never saved: alive at full health"
}

pub fn a_player_that_entered_with_less_health_is_struck_from_there_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.entered_saved(
      in_character_select: game_connection_support.in_select(),
      character: game_connection_support.world_character(),
      saved_health: Some(500),
    )
  let #(_, struck) =
    game_connection_support.feed(
      state,
      game_connection_support.a_beast_strike(
        game_connection_support.own_unit_id,
      ),
    )
  assert game_connection_support.decoded(
      game_connection_support.heard(struck, game_connection_support.keyed()),
      0x092F,
      player_health.decode,
    )
    == [
      PlayerHealth(
        unit_id: game_connection_support.own_unit_id,
        health: 499,
        reason_mask: 0,
      ),
    ]
    as "the Beast's 12 takes the shield 2 and the health 1, from 500"
}

pub fn a_viewer_that_arrives_gets_the_health_the_player_entered_with_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.entered_saved(
      in_character_select: game_connection_support.in_select(),
      character: game_connection_support.world_character(),
      saved_health: Some(500),
    )
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(3),
        stay: game_connection_support.viewer_stay(3),
      )),
    )
  let assert [#(3, PeerNews(news: Appeared(unit:), ..))] =
    game_connection_support.peer_tells(taken)
  assert health_of(unit) == Ok(500)
    as "stat 0 of the viewer's 0x262 is the health the player has now"
}

pub fn the_holocrypts_join_after_a_death_enters_at_full_health_whatever_the_login_entered_with_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.entered_saved(
      in_character_select: game_connection_support.in_select(),
      character: game_connection_support.world_character(),
      saved_health: Some(500),
    )
  let dead =
    game_connection_support.killed(
      game_connection_support.watched_by(state:, viewers: [2]),
    ).0
  let #(_, taken) = game_connection_support.at_the_holocrypt_from(dead:)
  assert health_of(game_connection_support.player_in(taken))
    == Ok(game_connection_support.full_health)
    as "the death step's full health on coming back (death.server_choices): the saved health is the login's entry's"
}

pub fn wake_here_after_an_entry_with_less_health_comes_back_at_full_health_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.entered_saved(
      in_character_select: game_connection_support.in_select(),
      character: game_connection_support.world_character(),
      saved_health: Some(500),
    )
  let dead =
    game_connection_support.killed(
      game_connection_support.watched_by(state:, viewers: [2]),
    ).0
  let #(_, taken) =
    game_connection_support.read(dead, game_connection_support.wake_here())
  assert game_connection_support.decoded(
      game_connection_support.heard(taken, game_connection_support.keyed()),
      0x092F,
      player_health.decode,
    )
    == [
      PlayerHealth(
        unit_id: game_connection_support.own_unit_id,
        health: game_connection_support.full_health,
        reason_mask: 0,
      ),
    ]
    as "death.server_choices: full health, not the saved one"
}
