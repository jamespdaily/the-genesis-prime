//// A viewer's connection (`genesis_prime/game/connection/viewers`) and the lasting
//// effects of a cast it was told: the 0x811 and 0x813 of a cast of a unit its client
//// shows, written only for a cast whose start the viewer wrote, as a go is
//// (`opcode.0x811`: the client drops a message that names a cast it does not hold;
//// `opcode.0x813`: the same). Expected values come from those records.

import game_connection_support
import genesis_prime/client_connection.{Appeared, CastStarted}
import genesis_prime/message/spell_position
import genesis_prime/message/spell_stack_removed.{SpellStackRemoved}
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed.{SpellTargetsRemoved}
import owned_test

/// 0x7ff for the cast `cast_id` of `caster`, as a caster's rule tells it.
fn started_of(
  cast_id cast_id: Int,
  caster caster: Int,
) -> spell_started.SpellStarted {
  spell_started.SpellStarted(
    cast_id:,
    spell4_id: 42_569,
    root_spell4_id: 58_832,
    parent_spell4_id: 80_382,
    caster_unit_id: caster,
    field_6: 0,
    primary_target_unit_id: caster,
    position: spell_position.SpellPosition(x: 0, y: 0, z: 0),
    yaw: 0,
    initial_positions: [],
    telegraph_positions: [],
    field_12: 1,
    field_13: 0,
  )
}

pub fn a_viewer_writes_0x811_and_0x813_only_for_a_cast_whose_start_it_wrote_test() -> Nil {
  use <- owned_test.run(10_000)
  let start = started_of(cast_id: 2_147_497_985, caster: 9)
  let removed =
    game_connection_support.news_of(
      unit_id: 9,
      news: client_connection.CastTargetsRemoved(
        removed: SpellTargetsRemoved(cast_id: start.cast_id, unit_ids: [9]),
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
