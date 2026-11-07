//// A viewer's connection (`genesis_prime/game/connection/viewers`) and the lasting
//// effects of a cast it was told: the 0x811 and 0x813 of a cast of a unit its client
//// shows, written only for a cast whose start the viewer wrote, as a go is
//// (`opcode.0x811`: the client drops a message that names a cast it does not hold;
//// `opcode.0x813`: the same). Expected values come from those records.

import character_tables
import game_connection_support
import genesis_prime/client_connection.{Appeared, CastStarted}
import genesis_prime/message/spell_stack_removed.{SpellStackRemoved}
import genesis_prime/message/spell_targets_removed.{SpellTargetsRemoved}
import genesis_prime/step
import gleam/list
import owned_test

pub fn a_viewer_writes_0x811_and_0x813_only_for_a_cast_whose_start_it_wrote_test() -> Nil {
  use <- owned_test.run(10_000)
  let start =
    game_connection_support.spell_started_of(cast_id: 2_147_497_985, caster: 9)
  let removed =
    game_connection_support.news_of(
      unit_id: 9,
      news: client_connection.CastTargetsRemoved(
        removed: SpellTargetsRemoved(cast_id: start.cast_id, unit_ids: [9]),
        destroyed: False,
      ),
    )
  let stack =
    game_connection_support.news_of(
      unit_id: 9,
      news: client_connection.CastStackRemoved(removed: SpellStackRemoved(
        cast_id: start.cast_id,
        unit_id: 9,
      )),
    )
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: Appeared(game_connection_support.another_unit()),
      )),
    )
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(removed),
    )
  assert game_connection_support.written_ids(taken) == []
    as "the viewer did not write the cast's start: the client would drop a 0x811 for a cast it does not hold"
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(stack),
    )
  assert game_connection_support.written_ids(taken) == []
    as "and a 0x813 for it"
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: CastStarted(start:),
      )),
    )
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(removed),
    )
  assert game_connection_support.written_ids(taken) == [0x0811]
    as "a cast it wrote the start of is taken off the units on the viewer's client too"
  assert game_connection_support.decoded(
      game_connection_support.heard(taken, game_connection_support.keyed()),
      0x0811,
      spell_targets_removed.decode,
    )
    == [SpellTargetsRemoved(cast_id: start.cast_id, unit_ids: [9])]
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(stack),
    )
  assert game_connection_support.written_ids(taken) == [0x0813]
  assert game_connection_support.decoded(
      game_connection_support.heard(taken, game_connection_support.keyed()),
      0x0813,
      spell_stack_removed.decode,
    )
    == [SpellStackRemoved(cast_id: start.cast_id, unit_id: 9)]
  Nil
}

pub fn a_cast_the_client_destroyed_with_a_0x811_is_forgotten_and_no_stale_finish_is_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let start =
    game_connection_support.spell_started_of(cast_id: 2_147_497_985, caster: 9)
  let removed =
    game_connection_support.news_of(
      unit_id: 9,
      news: client_connection.CastTargetsRemoved(
        removed: SpellTargetsRemoved(cast_id: start.cast_id, unit_ids: [9]),
        destroyed: True,
      ),
    )
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: Appeared(game_connection_support.another_unit()),
      )),
    )
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: CastStarted(start:),
      )),
    )
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(removed),
    )
  assert game_connection_support.written_ids(taken) == [0x0811]
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: client_connection.Removed,
      )),
    )
  assert game_connection_support.written_ids(taken) == [0x0355]
    as "opcode.0x811: a cast left with no target and a method other than 1, 3, 8 and 10 is destroyed on the client, so the unit's removal writes no 0x7fe for it"
}

/// What the viewer connection 2 is told of a cast, in order.
fn told_to_the_viewer(
  taken taken: step.ConnectionStep(client_connection.Request),
) -> List(client_connection.News) {
  list.filter_map(game_connection_support.peer_tells(taken), fn(tell) {
    case tell.0 == 2 {
      True -> Ok({ tell.1 }.news)
      False -> Error(Nil)
    }
  })
}

pub fn a_creatures_0x355_drops_its_nodes_and_the_lingering_cast_left_with_none_finishes_test() -> Nil {
  use <- owned_test.run(60_000)
  // Paralytic Surge with a Fluff on the units its area strikes, until removed: the
  // Beast 40 holds a node of the cast, which lingers with no 0x7fe.
  let state =
    game_connection_support.watched_by(
      game_connection_support.medic_with_beast_in_world(
        character_tables.shared_with_a_lasting_effect(),
      ),
      [2],
    )
  let #(state, pressed) =
    game_connection_support.press_paralytic_surge(state:, client_cast_id: 1)
  let assert [client_connection.CastStarted(start:)] =
    told_to_the_viewer(taken: pressed)
  let assert [#(40, key)] = game_connection_support.strikes_told(pressed)
  let #(state, gone) =
    game_connection_support.feed(state, game_connection_support.landed(key:))
  assert !list.contains(game_connection_support.written_ids(gone), 0x07FE)
    as "the Beast's node has no end by time: the cast lingers and writes no 0x7fe (cast.target_node_end)"
  let #(_, removed) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 40,
        news: client_connection.Removed,
      )),
    )
  assert game_connection_support.written_ids(removed) == [0x0355, 0x07FE]
    as "the client dropped the Beast's nodes with its 0x355 (0x1404550d0): the lingering cast has none left and ends with its 0x7fe"
  assert list.contains(
    told_to_the_viewer(taken: removed),
    client_connection.CastFinished(cast_id: start.cast_id),
  )
    as "the viewer told the cast's start is told its finish"
}
