//// The builder's save, 0xB1, on the game connection (`genesis_prime/game/connection`): the rule
//// is `limited_action_set_test`'s; this tests the connection's own job, one case per path: the
//// answer written in order, the bar kept for the session, the player's life, combat and level
//// read live, a body the client's reader refuses, and a message before the world. Expected
//// values come from these places.
//// - `opcode.0xb1` and the sitting's four saves (`limited_action_set_support.save_a` and the
////   others): the client sends one 0xB1 inside 0x038C from the world.
//// - `opcode.0xb2`: the builder redraws from the bar the server has set with 0x019D, so the
////   answer is 0x019D then 0xB2.
//// - `0x1407580e0`: the client refuses a save of a dead player and one in combat itself and
////   never sends them, so a server that is told one is told by a modified client or in a race.
//// - `connection/casting.caster_of`: where the connection reads the player's level, life and
////   combat.
//// - `genesis_prime/game/connection/world` ("Saving the place"): every end with the player in
////   the world saves the place, and each save carries the bars the connection holds; the
////   connection takes no other input while a save waits (`asking`).

import ability_book_support
import ability_points_support
import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/client_connection.{AskStore}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/strike_tell
import genesis_prime/step.{OwnEvent, TimerFired, TimerId, WatchEnded, WatchId}
import genesis_prime/store.{ActionSets, CharacterId, Move, SavePlace}
import genesis_prime/table/id.{ClassId}
import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import limited_action_set_support as limited
import owned_test

/// A Spellslinger of the level in the world.
fn in_world_at_level(level level: Int) -> game_connection.State {
  connection_support.entered_as(
    store.Character(
      ..connection_support.world_character(),
      class_id: ClassId(limited.spellslinger),
      faction_id: limited.faction,
      level:,
    ),
  ).0
}

/// A 0xB1 with this body, inside 0x038C.
fn saved(body body: BitArray) -> BitArray {
  connection_support.world_message(message_id: 0x00B1, body:)
}

/// The connection after a 0xB1 of this body, the step and the frames it wrote to the player.
fn sent(
  state state: game_connection.State,
  body body: BitArray,
) -> #(
  game_connection.State,
  step.ConnectionStep(client_connection.Request),
  List(Frame),
) {
  let #(state, taken) = connection_support.read(state:, bytes: saved(body:))
  #(state, taken, connection_support.written(taken:))
}

/// The result of the 0x019D a 0xB1 of this body is answered with.
fn result_of(state state: game_connection.State, body body: BitArray) -> Int {
  let #(_, _, frames) = sent(state:, body:)
  limited.the_action_set(frames:).result
}

/// The ids the connection holds as the player's bar, read from the 0x019D of a refusal: a save
/// of 20718 in slot 4, which opens at level 5, is refused at every level the tests use.
fn held_ids(state state: game_connection.State) -> List(Int) {
  let #(_, _, frames) =
    sent(
      state:,
      body: limited.body(ids: [0, 0, 0, 0, 20_718, 0, 0, 0, 0, 0, 0, 0], set: 0),
    )
  list.map(limited.the_action_set(frames:).shortcuts, fn(shortcut) {
    shortcut.object_id
  })
}

pub fn a_0xb1_in_the_world_is_answered_0x19d_then_0xb2_and_kept_in_entered_test() -> Nil {
  use <- owned_test.run(120_000)
  let state = in_world_at_level(level: 4)
  assert held_ids(state:) == limited.class_bar
    as "a player who has saved nothing holds the class's bar"
  let #(state, taken, frames) = sent(state:, body: limited.hex(limited.save_a))
  assert list.map(frames, fn(frame) { frame.message_id })
    == [0x019D, 0x01A0, 0x0169, 0x00B2]
    as "opcode.0xb2: the builder redraws from the set, so the set comes first, then the tiers and the points"
  assert support.asked(taken) == None as "nothing waits on the store"
  assert held_ids(state:) == limited.ids_a
    as "the set of the first save is held"
  let #(state, _, _) = sent(state:, body: limited.hex(limited.save_b))
  assert held_ids(state:) == limited.ids_b as "the second save replaces it"
}

/// The tiers above 1 the 0x01A0 among frames holds in set 0, as (Spell4Base, tier).
fn raised_in(frames frames: List(Frame)) -> List(#(Int, Int)) {
  ability_book_support.tiers_in(frames:)
  |> list.filter(fn(entry) { entry.tier > 1 })
  |> list.map(fn(entry) { #(entry.spell4_base_id, entry.tier) })
}

/// The sitting's first bar with these tier changes, set 0.
fn tiering(changes: List(#(Int, Int))) -> BitArray {
  limited.body_with(
    ids: limited.ids_a,
    set: 0,
    tier_changes: changes,
    amp_ids: [],
  )
}

pub fn a_0xb1_with_tier_changes_is_answered_in_order_and_a_save_the_points_cannot_cover_is_refused_on_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  // A Spellslinger of level 10 has 1 point (XpPerLevel). Quick Draw (27638) to tier 2 costs
  // 1 and Charged Shot (20684) to tier 2 costs 1 (Spell4 abilityPointCost).
  let state = in_world_at_level(level: 10)
  let #(state, taken, frames) = sent(state:, body: tiering([#(27_638, 2)]))
  assert list.map(frames, fn(frame) { frame.message_id })
    == [0x019D, 0x01A0, 0x0169, 0x00B2]
    as "opcode.0x169 before 0xB2, which clears the client's own count"
  assert limited.the_action_set(frames:).result == 1
  assert raised_in(frames:) == [#(27_638, 2)]
    as "the 0x01A0 names Quick Draw at tier 2 in set 0"
  assert ability_points_support.points_in(frames:) == [#(0, 1)]
    as "the one point of level 10 is spent"
  assert support.asked(taken) == None as "nothing waits on the store"
  let #(state, taken, frames) = sent(state:, body: tiering([#(20_684, 2)]))
  assert list.map(frames, fn(frame) { frame.message_id }) == [0x019D, 0x00B2]
    as "a refusal is the held set and 0xB2 only: no 0x01A0 and no 0x0169"
  assert limited.the_action_set(frames:).result == 42
    as "Charged Shot's tier 2 costs 1 point and the one point of level 10 is spent on Quick Draw"
  assert limited.the_answer_bit(frames:) == 0
  assert !support.stops(taken)
  let #(_, _, frames) =
    sent(state:, body: tiering([#(27_638, 2), #(20_684, 1)]))
  assert limited.the_action_set(frames:).result == 1
    as "the held tier and a tier 1 are accepted"
  assert raised_in(frames:) == [#(27_638, 2)]
    as "the first save's tier is kept in the connection"
  assert ability_points_support.points_in(frames:) == [#(0, 1)]
    as "and its point is still spent"
}

pub fn a_refused_save_is_answered_with_the_held_bar_and_the_players_life_and_level_are_read_live_test() -> Nil {
  use <- owned_test.run(120_000)
  let state = in_world_at_level(level: 4)
  let #(after, taken, frames) =
    sent(
      state:,
      body: limited.body(ids: [0, 0, 0, 0, 20_718, 0, 0, 0, 0, 0, 0, 0], set: 0),
    )
  assert list.map(frames, fn(frame) { frame.message_id }) == [0x019D, 0x00B2]
  assert limited.the_action_set(frames:).result == 2
    as "slot 4 opens at level 5"
  assert limited.the_answer_bit(frames:) == 0
  assert !support.stops(taken)
  assert held_ids(state: after) == limited.class_bar
    as "a refusal leaves the bar as it was"
  // A dead player, and one a creature holds on its threat list, each sending the sitting's
  // first save.
  let #(dead, _) = connection_support.killed(in_world_at_level(level: 4))
  assert result_of(state: dead, body: limited.hex(limited.save_a)) == 27
    as "a dead player: the connection reads the player's life as casting does"
  let #(fighting, _) =
    connection_support.feed(
      state: in_world_at_level(level: 4),
      event: connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  assert result_of(state: fighting, body: limited.hex(limited.save_a)) == 30
    as "a player in combat"
  // A player of level 3 who rises to level 4 in the session: the same save is refused and then
  // taken, so the level the connection reads is the one a level-up moves.
  let experience = ability_book_support.experience_of(level: 4) - 1
  let at_three =
    ability_book_support.entered_at(
      class_id: limited.spellslinger,
      level: 3,
      saved_experience: experience,
    )
  assert result_of(state: at_three, body: limited.hex(limited.save_a)) == 2
    as "at level 3 slot 3 is not open"
  let #(risen, _) =
    ability_book_support.level_up(
      class_id: limited.spellslinger,
      from: 3,
      to: 4,
    )
  assert result_of(state: risen, body: limited.hex(limited.save_a)) == 1
    as "after the rise slot 3 is open and the level 4 ability is in the book"
}

pub fn a_0xb1_the_decoder_refuses_ends_the_connection_test() -> Nil {
  use <- owned_test.run(120_000)
  let state = in_world_at_level(level: 4)
  let body = limited.hex(limited.save_a)
  let assert Ok(cut) = bit_array.slice(body, 0, 50)
  list.each(
    [
      #(cut, "50 of the 51 bytes end inside the last field"),
      #(bit_array.append(body, <<0>>), "a byte after the layout's last bit"),
    ],
    fn(case_) {
      let #(body, why) = case_
      let #(_, taken, frames) = sent(state:, body:)
      let assert [line] = support.logs_of(step: taken, level: step.LogError)
        as why
      assert support.says(line, "0x00B1") as why
      assert frames == [] as why
      let assert AskStore(Move(SavePlace(character_id: CharacterId(42), ..))) =
        connection_support.ask_request(taken)
        as "the place is saved as for any refused message, then the connection ends"
    },
  )
}

pub fn a_0xb1_before_the_world_is_logged_unhandled_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(_, taken) =
    connection_support.read(
      state: connection_support.in_select(),
      bytes: saved(body: limited.hex(limited.save_a)),
    )
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x00B1))]
    as "no row takes a 0xB1 at character select"
  assert support.writes(taken) == []
  assert !support.stops(taken)
}

/// The action slots the place save a step asks the store for carries.
fn action_sets_asked(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> store.ActionSets {
  let assert AskStore(Move(SavePlace(action_sets:, ..))) =
    connection_support.ask_request(taken)
    as "the step asks the store to save the place"
  action_sets
}

/// The state after the 60 s timer fires and the save is asked.
fn timer_save(
  state state: game_connection.State,
) -> #(game_connection.State, step.ConnectionStep(client_connection.Request)) {
  connection_support.feed(state:, event: OwnEvent(TimerFired(TimerId(2))))
}

/// The slots of a saved set the way the store holds them: twelve rows of set 0.
fn slots_of_set_0(ids ids: List(Int)) -> store.ActionSets {
  ActionSets(slots: limited.rows_of(set: 0, ids:))
}

pub fn every_save_of_the_place_carries_the_set_and_a_save_with_no_answer_is_carried_again_test() -> Nil {
  use <- owned_test.run(120_000)
  let after_a =
    sent(state: in_world_at_level(level: 4), body: limited.hex(limited.save_a)).0
  list.each(
    [
      #("(a) the 60 s timer", fn(state) { timer_save(state:).1 }),
      #("(b) the camp finishing", fn(state) {
        let #(state, _) =
          connection_support.read(
            state:,
            bytes: connection_support.camp_request_message(True),
          )
        connection_support.read(
          state:,
          bytes: connection_support.camp_finished_message(),
        ).1
      }),
      #("(c) the map's end", fn(state) {
        connection_support.feed(state:, event: WatchEnded(WatchId(2))).1
      }),
      #("(d) a takeover", fn(state) {
        connection_support.feed(state:, event: connection_support.taken_over()).1
      }),
    ],
    fn(row) {
      let #(why, save) = row
      assert action_sets_asked(taken: save(after_a))
        == slots_of_set_0(ids: limited.ids_a)
        as why
    },
  )
  list.each(connection_support.no_answers(), fn(outcome) {
    let #(state, taken) = timer_save(state: after_a)
    assert action_sets_asked(taken:) == slots_of_set_0(ids: limited.ids_a)
      as "(e) the first timer save carries the set"
    let #(state, _) = connection_support.answer(state:, taken:, outcome:)
    let #(_, taken) = timer_save(state:)
    assert action_sets_asked(taken:) == slots_of_set_0(ids: limited.ids_a)
      as "(e) the save asked again after one with no answer holds the same twelve rows"
  })
  let #(_, taken) = timer_save(state: in_world_at_level(level: 4))
  assert action_sets_asked(taken:) == ActionSets(slots: [])
    as "(f) a player who saved nothing saves no row, so the class's bar stays the default"
}

pub fn a_refused_save_leaves_what_the_next_place_save_carries_unchanged_test() -> Nil {
  use <- owned_test.run(120_000)
  let refused =
    limited.body(ids: [0, 0, 0, 0, 20_718, 0, 0, 0, 0, 0, 0, 0], set: 0)
  let after_a =
    sent(state: in_world_at_level(level: 4), body: limited.hex(limited.save_a)).0
  let #(after_refusal, _, frames) = sent(state: after_a, body: refused)
  assert limited.the_action_set(frames:).result == 2
    as "slot 4 opens at level 5: the body is refused"
  assert action_sets_asked(taken: timer_save(state: after_refusal).1)
    == slots_of_set_0(ids: limited.ids_a)
    as "the next save carries the rows of the set of A"
  let #(from_nothing, _, frames) =
    sent(state: in_world_at_level(level: 4), body: refused)
  assert limited.the_action_set(frames:).result == 2
  assert action_sets_asked(taken: timer_save(state: from_nothing).1)
    == ActionSets(slots: [])
    as "a refusal from no saved set leaves no rows to save"
  let #(state, taken) = timer_save(state: in_world_at_level(level: 4))
  let #(state, held) =
    connection_support.read(
      state:,
      bytes: saved(body: limited.hex(limited.save_b)),
    )
  assert connection_support.written(taken: held) == []
    as "the connection takes no other input while a save waits"
  let #(state, taken) =
    connection_support.answer(
      state:,
      taken:,
      outcome: connection_support.place_saved(),
    )
  assert list.map(connection_support.written(taken:), fn(frame) {
      frame.message_id
    })
    == [0x019D, 0x01A0, 0x0169, 0x00B2]
    as "the 0xB1 that waited is answered after the save"
  assert action_sets_asked(taken: timer_save(state:).1)
    == slots_of_set_0(ids: limited.ids_b)
    as "the next save carries the set the waiting 0xB1 made"
}
