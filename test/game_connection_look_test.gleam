//// A player's look on the game connection (`genesis_prime/game/connection/look`,
//// `viewers` and `frames`): an Engineer's Mode: Eradicate puts the ExoSuit on it for
//// 10,250 ms, its client and each viewer's are written 0x933, and a viewer that first
//// sees it mid-suit is created with the suit. Expected values come from these places:
//// - `Spell4Effects.effectType.112`: Mode: Eradicate (Spell4 47866, of Spell4Base 31779)
////   starts 47860 by its Proxy 112552; 47860 holds 112543 (ItemDisplay 4807, behind
////   prerequisite 30100, base faction 167, the Exiles) and 178142 (7221, behind 30101,
////   166, the Dominion), each on the caster for 10,250 ms (`-- Spell4Effects
////   spellId=47860`). The slot of both displays is 64, EngineerMechSuit (`-- ItemDisplay
////   4807 7221`, `-- Item2Type 346`).
//// - `opcode.0x933` and `opcode.0x933.empty_display`: the message names the unit and the
////   visuals; the client ignores an unknown unit; display 0 empties slot 64, so the end
////   writes slot 64 with display 0, colour set 0 and dye 0.
//// - `opcode.0x262.worn_visuals`: a unit's item visuals in its 0x262 are what its model
////   wears, so a viewer that first sees the Engineer mid-suit is created with slot 64
////   set and needs no 0x933; the Engineer of faction 166's Novice set is chest 3842 in
////   slot 1 and the weapon 3409 in slot 20 (`Item2.novice_visuals`).
//// - `opcode.0x355`: the camp removes the unit from each viewer's client.
//// - The server's choices, in the look and viewer modules: the player and each viewer are
////   told the same visuals, a news for a unit not shown or of an earlier stay is dropped.
//// - **Two worlds run each owner-side test.** The planted one (`character_tables.
////   shared_with_disguise`) gives the Medic's Paralytic Surge, at bag index 2, the two
////   ExoSuit rows as the client holds them, so the tests run in CI; the Medic is test data,
////   no Engineer, and is of faction 166, so its suit is 7221. The client's tables give
////   the Engineer's own Mode: Eradicate, at bag index 3, and are skipped where they are not
////   on the machine.

import character_tables
import client_tables
import game_connection_support as support
import genesis_prime/client_connection.{
  type News, type Request, Appeared, FromMap, LookChanged, PeerNews, Removed,
}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/loadout
import genesis_prime/message/item_visual.{type ItemVisual, ItemVisual}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_item_visuals_changed.{UnitItemVisualsChanged}
import genesis_prime/step.{type ConnectionStep, ConnectionId}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId, Spell4BaseId}
import genesis_prime/world_map/map.{SeenBy, UnseenBy}
import gleam/list
import gleam/option.{None}
import owned_test
import unitest

/// Slot 64 as 0x933 carries it: the display with colour set 0 and dye 0, and display 0
/// for the empty slot (`opcode.0x933.empty_display`).
fn suit(display display: Int) -> ItemVisual {
  ItemVisual(slot: 64, display_id: display, item_color_set_id: 0, dye: 0)
}

/// A player in the world watched by the viewers 2 and 3, the bag index of the ability
/// that puts the suit on it, and the display it is shown for its faction.
type World {
  World(state: game_connection.State, bag_index: Int, suit: Int)
}

/// The planted Medic of faction 166, whose Paralytic Surge, at bag index 2, holds the
/// two ExoSuit rows (`character_tables.shared_with_disguise`).
fn planted_world() -> World {
  let settings =
    Settings(
      ..support.settings(),
      tables: character_tables.shared_with_disguise(),
    )
  let #(state, _) =
    support.entered_saved(
      in_character_select: support.in_select_from(support.accepted(settings).0),
      character: Character(..support.world_character(), class_id: ClassId(4)),
      saved_health: None,
    )
  World(
    state: support.watched_by(state:, viewers: [2, 3]),
    bag_index: 2,
    suit: 7221,
  )
}

/// An Engineer of this faction in the world on the client's tables, with Mode:
/// Eradicate's bag index.
fn engineer_of(faction_id faction_id: Int) -> World {
  let settings = Settings(..support.settings(), tables: client_tables.shared())
  let #(state, taken) =
    support.joining_saved(
      in_character_select: support.in_select_from(support.accepted(settings).0),
      character: Character(
        ..support.world_character(),
        class_id: ClassId(2),
        faction_id:,
      ),
      saved_health: None,
    )
  let #(state, _) =
    support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromMap(support.with_the_tables_loadout(
          tables: client_tables.shared(),
          joined: support.map_answer(taken),
          class_id: 2,
        )),
      ),
    )
  let assert Ok(set) =
    loadout.of(
      tables: client_tables.shared(),
      class_id: ClassId(2),
      faction_id: 166,
    )
    as "the client's tables hold the Engineer's Novice set"
  let assert Ok(bag_index) =
    list.index_map(loadout.bag(loadout: set), fn(base, index) { #(base, index) })
    |> list.key_find(Spell4BaseId(31_779))
    as "the Engineer's bag holds Mode: Eradicate, its innate (Class 2 spell4IdInnateAbilityActive00 47866, Spell4Base 31779)"
  World(
    state: support.watched_by(state:, viewers: [2, 3]),
    bag_index:,
    suit: case faction_id {
      167 -> 4807
      _ -> 7221
    },
  )
}

/// The suit's ability pressed at 1000 ms and the cast timers up to `until_ms`.
fn suited_until(
  world world: World,
  until_ms until_ms: Int,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  support.pressed_until(
    state: world.state,
    bag_index: world.bag_index,
    client_cast_id: 1,
    ms: 1000,
    until_ms:,
  )
}

/// Each 0x933 the steps write to the player's client, in order.
fn written(
  steps steps: List(ConnectionStep(Request)),
) -> List(List(ItemVisual)) {
  list.flat_map(steps, fn(taken) {
    support.decoded(
      support.heard(taken, support.keyed()),
      0x0933,
      unit_item_visuals_changed.decode,
    )
  })
  |> list.map(fn(message: unit_item_visuals_changed.UnitItemVisualsChanged) {
    assert message.unit_id == support.own_unit_id
      as "the message names the player's own unit (opcode.0x933)"
    message.item_visuals
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
        True -> Ok({ tell.1 }.news)
        False -> Error(Nil)
      }
    })
  })
}

/// The visuals a news carries when it is a `LookChanged`, whatever they hold.
fn look_visuals(news news: News) -> Result(List(ItemVisual), Nil) {
  case news {
    LookChanged(item_visuals:) -> Ok(item_visuals)
    Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Moving(..)
    | Removed
    | client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastMissed(..)
    | client_connection.CastTargetsRemoved(..)
    | client_connection.CastStackRemoved(..)
    | client_connection.CastFinished(..)
    | client_connection.Health(..)
    | client_connection.Died
    | client_connection.CreatureMoved(..)
    | client_connection.CreaturePlaced(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.CameBack
    | client_connection.DeathLogged
    | client_connection.CameBackLogged
    | client_connection.Shield(..)
    | client_connection.Absorption(..)
    | client_connection.CrowdControlApplied(..)
    | client_connection.CrowdControlEnded(..)
    | client_connection.InterruptArmor(..)
    | client_connection.PropertiesChanged(..)
    | client_connection.Stealth(..) -> Error(Nil)
  }
}

/// The visuals of every `LookChanged` the steps tell the viewer `viewer`, in order.
fn told(
  steps steps: List(ConnectionStep(Request)),
  viewer viewer: Int,
) -> List(List(ItemVisual)) {
  list.filter_map(news_told(steps:, viewer:), fn(news) { look_visuals(news:) })
}

// ---- the suit on the player and its viewers ----

fn writes_the_suit_then_the_empty_slot(world world: World) -> Nil {
  let #(_, early) = suited_until(world:, until_ms: 10_000)
  assert written(steps: early) == [[suit(display: world.suit)]]
    as "0x933 {the player, [slot 64, the suit's display, colour set 0, dye 0]} once, at the go: the row of the player's faction (112543 behind 30100, base faction 167, or 178142 behind 30101, 166)"
  assert told(steps: early, viewer: 2) == [[suit(display: world.suit)]]
    as "each viewer is told the same visuals"
  assert told(steps: early, viewer: 3) == [[suit(display: world.suit)]]
  let #(_, whole) = suited_until(world:, until_ms: 20_000)
  assert written(steps: whole)
    == [[suit(display: world.suit)], [suit(display: 0)]]
    as "and 10,250 ms later slot 64 with display 0, which empties it (opcode.0x933.empty_display): the player held nothing there"
  assert told(steps: whole, viewer: 2)
    == [[suit(display: world.suit)], [suit(display: 0)]]
}

pub fn a_players_suit_is_written_then_the_empty_slot_to_itself_and_each_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  writes_the_suit_then_the_empty_slot(world: planted_world())
}

pub fn a_dominion_engineers_eradicate_writes_the_suit_then_the_empty_slot_to_itself_and_each_viewer_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  writes_the_suit_then_the_empty_slot(world: engineer_of(faction_id: 166))
}

pub fn an_exile_engineer_gets_the_other_suit_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let world = engineer_of(faction_id: 167)
  let #(_, steps) = suited_until(world:, until_ms: 20_000)
  assert written(steps:) == [[suit(display: 4807)], [suit(display: 0)]]
    as "112543, ItemDisplay 4807, behind 30100 (base faction 167)"
}

// ---- a viewer that first sees the player ----

/// The 0x262 the player's connection sends the viewer `viewer` that arrives now, and
/// the frames it writes in the same step.
fn created_for(
  state state: game_connection.State,
  viewer viewer: Int,
) -> UnitCreatePlayer {
  let assert [#(_, PeerNews(news: Appeared(unit:), ..))] =
    support.peer_tells(
      support.feed(
        state:,
        event: support.sent_by_the_map(SeenBy(
          by: ConnectionId(viewer),
          stay: support.viewer_stay(viewer),
        )),
      ).1,
    )
    as "the player's connection sends the arriving viewer its 0x262, and nothing else"
  unit
}

/// The slot 64 entries of a created unit's item visuals.
fn suits_of(unit unit: UnitCreatePlayer) -> List(ItemVisual) {
  list.filter(unit.tail.item_visuals, fn(visual) { visual.slot == 64 })
}

fn a_late_viewer_gets_the_suit_or_the_base_list(world world: World) -> Nil {
  let base = created_for(state: world.state, viewer: 4).tail.item_visuals
  assert list.filter(base, fn(visual) { visual.slot == 64 }) == []
    as "the player's 0x262 lists nothing in slot 64 (opcode.0x262.worn_visuals)"
  let #(suited, _) = suited_until(world:, until_ms: 10_000)
  let created = created_for(state: suited, viewer: 4)
  assert suits_of(unit: created) == [suit(display: world.suit)]
    as "a viewer that first sees the player mid-suit is created with slot 64 set (opcode.0x262.worn_visuals), so it needs no 0x933"
  assert list.take(created.tail.item_visuals, list.length(base)) == base
    as "and the rest of the list is the base's, as it was"
  let #(ended, _) = suited_until(world:, until_ms: 20_000)
  assert created_for(state: ended, viewer: 5).tail.item_visuals == base
    as "after the end the list is the base's again"
}

pub fn a_viewer_that_arrives_mid_suit_is_created_with_it_and_one_after_the_end_with_the_base_list_test() -> Nil {
  use <- owned_test.run(60_000)
  a_late_viewer_gets_the_suit_or_the_base_list(world: planted_world())
}

pub fn an_engineers_viewer_that_arrives_mid_suit_is_created_with_it_and_one_after_the_end_with_the_base_list_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  a_late_viewer_gets_the_suit_or_the_base_list(world: engineer_of(
    faction_id: 166,
  ))
}

fn a_viewer_that_sees_the_player_again_gets_the_suit(
  world world: World,
) -> Nil {
  let #(suited, _) = suited_until(world:, until_ms: 10_000)
  let #(unseen, _) =
    support.feed(
      state: suited,
      event: support.sent_by_the_map(UnseenBy(by: ConnectionId(2))),
    )
  assert suits_of(unit: created_for(state: unseen, viewer: 2))
    == [suit(display: world.suit)]
    as "the viewer that sees the player again is created with the suit"
}

pub fn a_viewer_that_stops_seeing_the_player_and_sees_it_again_mid_suit_gets_a_new_0x262_with_the_suit_test() -> Nil {
  use <- owned_test.run(60_000)
  a_viewer_that_sees_the_player_again_gets_the_suit(world: planted_world())
}

pub fn a_viewer_that_stops_seeing_the_engineer_and_sees_it_again_mid_suit_gets_a_new_0x262_with_the_suit_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  a_viewer_that_sees_the_player_again_gets_the_suit(world: engineer_of(
    faction_id: 166,
  ))
}

// ---- a viewer ----

pub fn a_viewer_that_shows_the_unit_writes_its_0x933_and_one_that_does_not_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let shown = support.viewer_showing_unit_9()
  let #(_, taken) =
    support.feed(
      shown,
      support.news_sent_by_a_peer(
        unit_id: 9,
        news: LookChanged(item_visuals: [suit(display: 7221)]),
      ),
    )
  let assert [frame] = support.heard(taken, support.keyed())
  assert frame.message_id == 0x0933
  assert unit_item_visuals_changed.decode(frame.body)
    == Ok(
      UnitItemVisualsChanged(unit_id: 9, item_visuals: [suit(display: 7221)]),
    )
    as "the viewer writes the same visuals under the unit it shows (opcode.0x933)"
  let #(_, early) =
    support.feed(
      support.in_world(),
      support.news_sent_by_a_peer(
        unit_id: 9,
        news: LookChanged(item_visuals: [suit(display: 7221)]),
      ),
    )
  assert support.heard(early, support.keyed()) == []
    as "a news before the unit's 0x262 finds no unit shown, and the client would ignore an unknown unit (opcode.0x933)"
  let #(gone, _) =
    support.feed(shown, support.news_sent_by_a_peer(unit_id: 9, news: Removed))
  let #(_, late) =
    support.feed(
      gone,
      support.news_sent_by_a_peer(
        unit_id: 9,
        news: LookChanged(item_visuals: [suit(display: 0)]),
      ),
    )
  assert support.heard(late, support.keyed()) == []
    as "a news after the unit was removed writes nothing"
}

pub fn a_look_news_of_an_earlier_stay_is_dropped_test() -> Nil {
  use <- owned_test.run(10_000)
  let shown = support.viewer_showing_unit_9()
  let #(_, taken) =
    support.feed(
      shown,
      support.in_second_stay(support.news_sent_by_a_peer(
        unit_id: 9,
        news: LookChanged(item_visuals: [suit(display: 7221)]),
      )),
    )
  assert support.heard(taken, support.keyed()) == []
    as "the news is for the player's second stay and the connection is in its first (ForStay)"
}

// ---- the end of the player's stay ----

fn the_death_writes_the_restore_to_the_player_and_each_viewer(
  world world: World,
) -> Nil {
  let #(suited, _) = suited_until(world:, until_ms: 5000)
  let #(dead, taken) = support.killed(suited)
  assert written(steps: [taken]) == [[suit(display: 0)]]
    as "the death ends the suit: slot 64 with display 0 goes to the player in the death's step"
  assert told(steps: [taken], viewer: 2) == [[suit(display: 0)]]
  assert told(steps: [taken], viewer: 3) == [[suit(display: 0)]]
  assert suits_of(unit: created_for(state: dead, viewer: 4)) == []
    as "a viewer that comes after the death gets the base list"
}

pub fn the_death_mid_suit_writes_the_restore_to_the_player_and_each_viewer_and_a_later_viewer_gets_the_base_list_test() -> Nil {
  use <- owned_test.run(60_000)
  the_death_writes_the_restore_to_the_player_and_each_viewer(
    world: planted_world(),
  )
}

pub fn the_engineers_death_mid_suit_writes_the_restore_to_the_player_and_each_viewer_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  the_death_writes_the_restore_to_the_player_and_each_viewer(world: engineer_of(
    faction_id: 166,
  ))
}

fn a_camp_tells_the_viewers_removed_and_no_look(world world: World) -> Nil {
  let #(suited, _) = suited_until(world:, until_ms: 5000)
  let #(requested_state, requested) =
    support.read(state: suited, bytes: support.camp_request_message(True))
  let #(finished_state, finished) =
    support.read(state: requested_state, bytes: support.camp_finished_message())
  let #(saved_state, saved) =
    support.answer(
      state: finished_state,
      taken: finished,
      outcome: support.place_saved(),
    )
  let #(camped, left) =
    support.answer(
      state: saved_state,
      taken: saved,
      outcome: step.Answer(FromMap(map.Left)),
    )
  let steps = [requested, finished, saved, left]
  assert written(steps:) == [] as "a camp writes no 0x933 to the player"
  list.each([2, 3], fn(viewer) {
    let news = news_told(steps:, viewer:)
    assert list.filter(news, fn(told) { told == Removed }) == [Removed]
      as "the camp's own steps tell each viewer the unit is removed, once (opcode.0x355)"
    assert list.filter_map(news, fn(told) { look_visuals(news: told) }) == []
      as "and no LookChanged, whatever it carries"
  })
  // The next entry: a fresh Entered from the map's join, whose 0x262 lists the base.
  let #(_, entering) =
    support.entered_from(
      in_character_select: camped,
      character: Character(..support.world_character(), class_id: ClassId(2)),
    )
  assert list.filter(support.player_in(entering).tail.item_visuals, fn(visual) {
      visual.slot == 64
    })
    == []
    as "the next stay's 0x262 holds the base visuals, with no suit"
}

pub fn a_camp_mid_suit_tells_each_viewer_removed_with_no_look_and_the_next_entry_has_the_base_look_test() -> Nil {
  use <- owned_test.run(60_000)
  a_camp_tells_the_viewers_removed_and_no_look(world: planted_world())
}

pub fn an_engineers_camp_mid_suit_tells_each_viewer_removed_with_no_look_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  a_camp_tells_the_viewers_removed_and_no_look(world: engineer_of(
    faction_id: 166,
  ))
}
