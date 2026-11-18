//// The level-up fanfare's rule (`genesis_prime/game/level_up`): which tier of the Level Up
//// spell answers the client's 0x07A5, and what is refused. Expected values come from these
//// places:
//// - `Spell4.tierIndex.level_up`: Spell4Base 53378 holds 49 Spell4 rows, tierIndex 1 to 49,
////   and tier n is the fanfare of level n + 1; the Spell4 ids are not consecutive (77398,
////   77407, 77409 to 77455), so a tier is found by tierIndex. The rows are
////   `level_up_support.tiers`, written from `table_rows`.
//// - `opcode.0x7a5` and `lua.LevelUpUnlocks.ReplayLevelUp`: the client sends its unit's
////   level 2000 ms after a rise, and the Replay button sends any level 2 to 50 not above its
////   unit's (`0x140703b5b ja` skips a higher one); the stock picker starts at 2.
//// - CLAUDE.md, "a missing row fails the load".

import client_tables
import fixture_tables
import genesis_prime/client_connection
import genesis_prime/game/level_up
import genesis_prime/game/spell_plan
import genesis_prime/message/bit_stream
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/sound_event
import genesis_prime/table/spell4
import genesis_prime/table/spell4_visual
import genesis_prime/table/spell4_visual_group
import genesis_prime/table/visual_effect
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import level_up_support.{Tier}
import owned_test
import planted_table.{Integer}
import unitest

fn spell_id_of(
  fanfares fanfares: level_up.Fanfares,
  level level: Int,
) -> Result(Int, Nil) {
  level_up.spell_of(fanfares:, level:)
  |> result.map(fn(spell) { spell.spell4_id.value })
}

pub fn a_levels_fanfare_is_the_tier_one_below_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let fanfares = level_up.fanfares(tables: fixture_tables.shared())
  list.each(level_up_support.tiers, fn(tier) {
    let Tier(level:, spell4_id:, effect_id:) = tier
    let assert Ok(spell) = level_up.spell_of(fanfares:, level:)
      as { "level " <> int.to_string(level) <> " has a fanfare" }
    assert spell.spell4_id.value == spell4_id
      as { "Spell4.tierIndex.level_up: level " <> int.to_string(level) }
    let assert [lasting] =
      spell_plan.payloads(spell:, as_kind: spell_plan.as_lasting)
    assert lasting.effect_id.value == effect_id
      as { "the tier's one row, level " <> int.to_string(level) }
  })
  assert level_up.spell_of(fanfares:, level: 1) == Error(Nil)
    as "level 1 has no tier: tierIndex 1 is level 2"
  assert level_up.spell_of(fanfares:, level: 51) == Error(Nil)
    as "the highest level is 50 (GameFormula 145), so tierIndex 49 is the last"
  // The ids of the tiers are not in the order of the levels when two rows swap their
  // tierIndex: the level follows the tierIndex, never the id.
  let assert Ok(swapped) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Spell4",
      id: 77_398,
      with: [#("tierIndex", Integer(2))],
    )
  let assert Ok(swapped) =
    fixture_tables.change(rows: swapped, table: "Spell4", id: 77_407, with: [
      #("tierIndex", Integer(1)),
    ])
  fixture_tables.on_rows(rows: swapped, reaching: [], body: fn(tables) {
    let fanfares = level_up.fanfares(tables:)
    assert spell_id_of(fanfares:, level: 2) == Ok(77_407)
      as "level 2 is the row whose tierIndex is 1, whatever its id"
    assert spell_id_of(fanfares:, level: 3) == Ok(77_398)
      as "level 3 is the row whose tierIndex is 2"
  })
  // A Spell4 of another base with tierIndex 1 is not level 2's: the lookup is by
  // Spell4Base 53378 only. 19102 is Telekinetic Strike's base.
  fixture_tables.added(
    table: "Spell4",
    copy_of: 77_398,
    id: 99_077,
    with: [#("spell4BaseIdBaseSpell", Integer(19_102))],
    body: fn(tables) {
      let fanfares = level_up.fanfares(tables:)
      assert spell_id_of(fanfares:, level: 2) == Ok(77_398)
        as "the Spell4 of another base with tierIndex 1 is not the fanfare"
    },
  )
}

pub fn every_tiers_announcer_is_named_for_its_level_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let fanfares = level_up.fanfares(tables:)
  let tiers =
    list.filter(spell4.all(tables), fn(row) {
      row.spell4_base_id_base_spell == 53_378
    })
  assert list.length(tiers) == 49
  list.each(tiers, fn(row) {
    let level = row.tier_index + 1
    let name = "level " <> int.to_string(level)
    assert spell_id_of(fanfares:, level:) == Ok(row.id)
      as { name <> ": the rule's tier is the client's row of that tierIndex" }
    let assert Ok(group) =
      spell4_visual_group.get(tables:, id: spell4.spell4_visual_group_id(row))
      as { name <> ": the tier's visual group" }
    let assert Ok(visual) =
      spell4_visual.get(
        tables:,
        id: spell4_visual_group.spell4_visual_id_visual08(group),
      )
      as { name <> ": the ninth visual" }
    let assert Ok(effect) =
      visual_effect.get(tables:, id: spell4_visual.visual_effect_id(visual))
      as { name <> ": its visual effect" }
    assert effect.prerequisite_id == 3977
      as { name <> ": Prerequisite 3977 (type 63): the player's own unit only" }
    let assert Ok(sound) =
      sound_event.get(tables:, id: visual_effect.sound_event_id00(effect))
      as { name <> ": its sound event" }
    assert sound.name
      == "Play_GameEvent_Announcer_LevelUp_" <> two_digits(level:)
      as { name <> ": the announcer says the level of the tier" }
  })
}

fn two_digits(level level: Int) -> String {
  string.pad_start(int.to_string(level), to: 2, with: "0")
}

type Outcome {
  Cast(spell4_id: Int)
  Nothing(level: Int)
  Refused(why: String)
}

fn outcome_of(
  fanfares fanfares: level_up.Fanfares,
  player_level player_level: Int,
  body body: BitArray,
) -> Outcome {
  case level_up.take(fanfares:, player_level:, body:) {
    Ok(level_up.Fanfare(spell:)) -> Cast(spell4_id: spell.spell4_id.value)
    Ok(level_up.NoFanfare(level:)) -> Nothing(level:)
    Error(level_up.AbovePlayerLevel(..)) -> Refused(why: "above")
    Error(level_up.NotDecoded(..)) -> Refused(why: "not decoded")
  }
}

pub fn a_replay_is_answered_up_to_the_players_level_and_refused_above_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let fanfares = level_up.fanfares(tables: fixture_tables.shared())
  list.each(
    [
      // (player level, requested level, outcome, why)
      #(4, 4, Cast(77_409), "the fanfare of the level just reached"),
      #(4, 2, Cast(77_398), "a Replay of the first level the picker lists"),
      #(4, 3, Cast(77_407), "a Replay of an earlier level, or a stale request"),
      #(50, 50, Cast(77_455), "the highest level"),
      #(4, 1, Nothing(1), "an addon's own call: the stock picker starts at 2"),
      #(4, 0, Nothing(0), "an addon's own call"),
      #(1, 1, Nothing(1), "a level-1 player has no fanfare"),
      #(4, 5, Refused("above"), "the client sends none above its unit's level"),
      #(4, 50, Refused("above"), "the picker lists it, but the button is off"),
      #(4, 0xFFFFFFFF, Refused("above"), "the largest 32-bit value"),
    ],
    fn(case_) {
      let #(player_level, requested, expected, why) = case_
      assert outcome_of(
          fanfares:,
          player_level:,
          body: level_up_support.replay_body(level: requested),
        )
        == expected
        as {
          "player level "
          <> int.to_string(player_level)
          <> ", asks for "
          <> int.to_string(requested)
          <> ": "
          <> why
        }
    },
  )
  list.each(
    [
      #(<<>>, "an empty body ends inside the level"),
      #(<<4, 0, 0>>, "three bytes end inside the level"),
      #(
        <<4, 0, 0, 0, 0>>,
        "the client's writer adds 32 bits, so five bytes are longer",
      ),
    ],
    fn(case_) {
      let #(body, why) = case_
      assert outcome_of(fanfares:, player_level: 4, body:)
        == Refused("not decoded")
        as why
    },
  )
  let assert Error(refusal) =
    level_up.take(
      fanfares:,
      player_level: 4,
      body: level_up_support.replay_body(level: 5),
    )
  let text = level_up.describe(refusal:)
  assert string.contains(text, "0x07A5")
    && string.contains(text, "level 5")
    && string.contains(text, "level 4")
    && string.contains(text, "never a level above")
    as "the sentence names the message, both levels and what the client does"
  let assert Error(refusal) =
    level_up.take(fanfares:, player_level: 4, body: <<4, 0, 0>>)
  assert level_up.describe(refusal:)
    == client_connection.describe_undecoded(
      undecoded: client_connection.Undecoded(
        message_id: 0x07A5,
        error: bit_stream.EndOfData,
      ),
    )
    as "a body the client's reader refuses is described as any such body is"
}

fn rows_without(table table: String, id id: Int) -> fixture_tables.Rows {
  let assert Ok(rows) =
    fixture_tables.remove(rows: fixture_tables.rows(), table:, id:)
    as "the client's rows hold the row"
  rows
}

fn why_the_load_fails(rows rows: fixture_tables.Rows) -> String {
  let assert Error(table_store.DerivationFailed(
    name: "LevelUpFanfares",
    reason:,
  )) = fixture_tables.load(rows:)
    as "the load without a row the fanfares read fails in their build"
  reason
}

pub fn a_level_with_no_tier_fails_the_load_test() -> Nil {
  use <- owned_test.run(120_000)
  // Spell4 77413 is tierIndex 7 and so level 8 (`table_rows -- Spell4 77413`).
  let missing_tier =
    why_the_load_fails(rows: rows_without(table: "Spell4", id: 77_413))
  assert string.contains(missing_tier, "Spell4Base 53378")
    && string.contains(missing_tier, "tierIndex 7")
    && string.contains(missing_tier, "level 8")
    as {
      "the reason names the base, the tierIndex and the level: " <> missing_tier
    }
  // Spell4Effects 202346 is the one row of Spell4 77410, level 5: a tier with no row
  // would show nothing.
  let missing_row =
    why_the_load_fails(rows: rows_without(table: "Spell4Effects", id: 202_346))
  assert string.contains(missing_row, "level 5")
    && string.contains(missing_row, "Spell4 77410")
    as { "the reason names the level and the spell: " <> missing_row }
}
