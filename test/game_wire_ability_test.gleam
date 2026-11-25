//// The abilities a level gives, on the whole server: the new ability a level-up makes castable
//// and a relog keeps, the point a level gives, the level-up cast a watcher reads and the action
//// bar the client saves with 0x00B1.
//// Every wait is for bytes the server writes, with a deadline a passing test never
//// reaches. The tree, the logins and the players come from `game_wire_support`.

import ability_book_support
import ability_points_support
import cast_support
import character_support
import content_support
import driven_time
import fight_bot
import fixture_tables
import game_client
import game_wire_support.{
  a_medic_of_a_level_at_the_marker_ring, a_player_of_a_level_at_the_marker_ring,
  destroyed_units, kills_the_target_at_slot_0, location_4_items,
  new_player_at_level, on_rows_without_paralytic_surges_recharge, refusals,
  ring_slot, send_play, targets_in, the_target_at_slot_0, world_with_numbers,
  world_with_the_markers_creatures,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers
import genesis_prime/message/float32
import genesis_prime/message/item_added
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_go
import genesis_prime/message/spell_position
import genesis_prime/message/spell_started
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_level.{UnitStatLevel}
import genesis_prime/table/id.{XpPerLevelId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/xp_per_level
import genesis_prime/world_map/game_number.{GameNumbers}
import gleam/bool
import gleam/list
import gleam/option.{Some}
import gleam/result
import level_up_support
import limited_action_set_support as limited
import login_support
import owned_test
import planted_table
import pog

/// The Medic of the marker ring that levels from 3 to 4 on the kill at slot 0: its abilities
/// are the level-1 three and the innate, then SpellLevel 614's base 26038 (Fissure) at bag
/// index 4, written after the level and before the properties, on the whole server and again
/// at the entry of the relog. Fissure is planned (its second spell's hit telegraphs 2996 to 2998
/// are placed by flag 8, the position the cast holds), so the press of slot 4 is accepted: it is
/// confirmed, not refused, and the child's start carries the press pose. The Medic stands 8 m
/// from the ring's other creature and faces it. Which creatures each go strikes is the job of
/// the strike tests and of the whole-server test of Fissure among still Beasts. The clock is
/// driven and nothing waits on real time.
pub fn a_medic_that_levels_from_3_to_4_holds_fissure_castable_and_a_relog_at_4_holds_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  // The saved experience is one short of level 4 (XpPerLevel row 4, minXpForLevel 2860), so
  // the one kill, which gives at least 1, reaches it.
  let assert Ok(level_four) = xp_per_level.get(tables:, id: XpPerLevelId(4))
    as "XpPerLevel has a row 4"
  let #(game, frames, have, character) =
    a_medic_of_a_level_at_the_marker_ring(
      started:,
      sixth: 0,
      level: 3,
      saved_experience: Some(level_four.min_xp_for_level - 1),
    )
  let other =
    list.find(targets_in(frames:), fn(creature) {
      creature.unit_id != the_target_at_slot_0(frames:).unit_id
    })
  let assert Ok(other) = other as "the ring's second 73492 stands at slot 2"
  let #(killed, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  let #(rest, have) =
    game_client.read_until(game:, have:, found: fn(rest) {
      list.any(list.append(killed, rest), fn(frame) {
        frame.message_id == 0x01A0
      })
    })
  let risen =
    list.filter(list.append(killed, rest), fn(frame) {
      list.contains([0x01AC, 0x0938, 0x0111, 0x01A0], frame.message_id)
      && !is_other_stat(frame:)
    })
  assert list.map(risen, fn(frame) { frame.message_id })
    == [0x01AC, 0x0938, 0x0111, 0x01A0]
    as "the experience, then the level, then the ability the level grants and its book entry (opcode.0x111.ability_level_up)"
  let assert [_, level, ability, book] = risen
  assert unit_stat_changed.decode(level.body)
    |> result.map(fn(changed) { changed.change })
    == Ok(unit_stat_change.Level(UnitStatLevel(value: 4)))
    as "opcode.0x938: stat 10 is 4, written before the ability the client checks it for (0x1403bb040)"
  let assert Ok(added) = item_added.decode(ability.body)
  assert #(
      added.held_item.item.location,
      added.held_item.item.bag_index,
      added.held_item.item.item_id,
      added.held_item.reason,
    )
    == #(4, 4, 26_038, 49)
    as "opcode.0x111.ability_level_up: SpellLevel 614's base at the slot after the bag of 4, reason 49"
  let assert Ok(tiers) = ability_tiers.decode(book.body)
  assert tiers.tiers
    == list.map([0, 1, 2, 3], fn(action_set_index) {
      AbilityTier(spell4_base_id: 26_038, tier: 1, action_set_index:)
    })
    as "opcode.0x1a0: tier 1 of the base in each of the four action sets"
  // The Medic walks to 8 m from the ring's other creature, which stands alive and untouched,
  // and faces it: it is 8 m ahead of the press pose, inside the first rectangle of Fissure's
  // rows (TelegraphDamage 2998: 10 wide, from 1 to 15 m ahead).
  let creature_at = game_client.placed_by_tail(tail: other.tail)
  let press_at = #(creature_at.0 +. 8.0, creature_at.1, creature_at.2)
  game_client.move_to(
    game:,
    clock: 200,
    x: press_at.0,
    y: press_at.1,
    z: press_at.2,
  )
  let facing_the_creature =
    game_client.yaw_toward(from: #(press_at.0, press_at.2), target: #(
      creature_at.0,
      creature_at.2,
    ))
  game_client.face(game:, yaw: facing_the_creature, clock: 210)
  let #(_, have) = game_client.read_until_pong(game:, have:, number: 8)
  // The last Paralytic Surge lingers 2700 ms (`fight_bot.paralytic_surge_lingers_ms`) and holds
  // the press of any other ability inside the 500 ms queue window (`cast_press.verdict`), so the
  // clock moves past that lingering first.
  driven_time.advance(time:, ms: 3000)
  game_client.press_ability(
    game:,
    client_cast_id: 50,
    bag_index: 4,
    target: other.unit_id,
  )
  // The connection writes the confirm and the child's start before its pong, so a press that is
  // held or refused ends this wait at the assertions below; the first go comes from the cast's
  // timer, which a confirmed press has armed.
  let #(first_go, have) = game_client.read_until_pong(game:, have:, number: 10)
  assert refusals(frames: first_go) == []
    as "opcode.0x7fc: Fissure is planned, so the press is not refused"
  let assert Ok(confirmed_frame) =
    list.find(first_go, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the press is confirmed; none came, so the press was held behind a lingering cast or not made"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed_frame.body)
  let starts =
    list.filter(first_go, fn(frame) { frame.message_id == 0x07FF })
    |> list.map(fn(frame) {
      let assert Ok(started) = spell_started.decode(frame.body)
        as "0x7ff decodes"
      started
    })
  let assert Ok(child_started) =
    list.find(starts, fn(started) { started.spell4_id == 41_844 })
    as "opcode.0x7ff: the child 41844 starts"
  assert #(child_started.root_spell4_id, child_started.parent_spell4_id)
    == #(41_843, 41_843)
    as "Spell4Effects 94215 starts child 41844 of the pressed 41843"
  let held =
    spell_position.SpellPosition(
      x: float32.to_bits(press_at.0),
      y: float32.to_bits(press_at.1),
      z: float32.to_bits(press_at.2),
    )
  assert confirmed.position == held && child_started.position == held
    as "opcode.0x7fd, opcode.0x7ff: the position the cast holds is the Medic's place at the press"
  assert confirmed.yaw == float32.to_bits(facing_the_creature)
    && child_started.yaw == float32.to_bits(facing_the_creature)
    as "opcode.0x7fd, opcode.0x7ff: the yaw the client turns the picture by is the facing the Medic had at the press (the client's own yaw is the caster's facing, a marked guess)"
  // The relog at level 4 holds the same five abilities, the new one in slot 4.
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert location_4_items(frames: second_entry)
    == [
      #(0, 38_201),
      #(1, 16_322),
      #(2, 26_543),
      #(3, 46_615),
      #(4, 26_038),
    ]
    as "the entry's location-4 items are the level-1 three, the innate and Fissure's base in slot 4: a relog holds the book a rise made"
  game_client.close(game:)
  login_support.stop(started)
}

/// A Medic of level 9 whose saved experience is one short of level 10 (XpPerLevel row 10,
/// minXpForLevel 23860) kills the target at ring slot 0: the 0x0169 of its entry holds 0 and 0
/// before 0x025E, the rise to 10 sends 1 and 1 after the level (`XpPerLevel.abilityPointsPerLevel`
/// is 1 from ID 10; `opcode.0x169`), and the relog at 10 sends 1 and 1 again in the same place.
/// The clock is driven and nothing waits on real time.
pub fn a_medic_that_levels_from_9_to_10_receives_one_point_and_a_relog_at_10_sends_it_again_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started =
    world_with_kill_experience_below_the_fourth_level_gap(tables:, time:)
  let assert Ok(level_ten) = xp_per_level.get(tables:, id: XpPerLevelId(10))
    as "XpPerLevel has a row 10"
  let #(game, frames, have, character) =
    a_medic_of_a_level_at_the_marker_ring(
      started:,
      sixth: 0,
      level: 9,
      saved_experience: Some(level_ten.min_xp_for_level - 1),
    )
  assert ability_points_support.points_in(frames:) == [#(0, 0)]
    as "XpPerLevel.abilityPointsPerLevel: IDs 1 to 9 give none, so the entry's 0x0169 holds 0 and 0"
  assert entry_places_the_points_between_the_reward_properties_and_the_state(
    frames:,
  )
    as "lua.Abilities.UpdateInterfaceMenuAlerts: before 0x025E, after 0x092C"
  let #(killed, have) = kills_the_target_at_slot_0(game:, have:, frames:, time:)
  let #(rest, have) =
    game_client.read_until(game:, have:, found: fn(rest) {
      list.any(list.append(killed, rest), fn(frame) {
        frame.message_id == 0x0169
      })
    })
  let from_the_kill = list.append(killed, rest)
  assert ability_points_support.points_in(frames: from_the_kill) == [#(1, 1)]
    as "the rise to 10 sends a 0x0169 of 1 and 1"
  let rise =
    list.filter(from_the_kill, fn(frame) {
      list.contains([0x01AC, 0x0938, 0x0169], frame.message_id)
      && !is_other_stat(frame:)
    })
  assert list.map(rise, fn(frame) { frame.message_id })
    == [0x01AC, 0x0938, 0x0169]
    as "the experience, the level, then the points: the client re-reads the points when it raises PlayerLevelChange, after the level's stat"
  let assert [_, level, _] = rise
  assert unit_stat_changed.decode(level.body)
    |> result.map(fn(changed) { changed.change })
    == Ok(unit_stat_change.Level(UnitStatLevel(value: 10)))
    as "opcode.0x938: stat 10 is 10"
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert ability_points_support.points_in(frames: second_entry) == [#(1, 1)]
    as "the relog at 10 sends one 0x0169 of 1 and 1"
  assert entry_places_the_points_between_the_reward_properties_and_the_state(
    frames: second_entry,
  )
    as "the relog's entry sends it in the same place"
  game_client.close(game:)
  login_support.stop(started)
}

/// The marker world whose kills give experience to a player four or more levels above the
/// creature. The ring's creatures are level 2 and the level 9 Medic's gap clamps to -4, whose
/// multiplier (`kill_experience_multiplier_below_4`, a `game_number` server choice: the client
/// has no kill formula) is 0 in the content; only that one is set to 1, so the test changes
/// the server's content and no client rule.
fn world_with_kill_experience_below_the_fourth_level_gap(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  world_with_numbers(
    folder: content_support.fixture_folder,
    tables:,
    time:,
    tutorial: False,
    numbers: fn(numbers) {
      GameNumbers(..numbers, kill_experience_multipliers: [
        1.0,
        ..list.drop(numbers.kill_experience_multipliers, up_to: 1)
      ])
    },
  )
}

/// Whether 0x0169 follows 0x092C and comes before 0x025E in the frames.
fn entry_places_the_points_between_the_reward_properties_and_the_state(
  frames frames: List(Frame),
) -> Bool {
  list.window(cast_support.ids(frames:), 3)
  |> list.contains([0x092C, 0x0169, 0x025E])
}

/// The Spellslinger of the marker ring that levels from 3 to 4 on the kill at slot 0 with
/// its slot 0 ability (SpellLevel 1011's Spell4 43468, base 27638, castTime 1000), then casts
/// SpellLevel 1012's base 20718 (Spell4 34756: castTime 1000, no cost, a living target; the
/// plan holds it) at the ring's other creature, and again after a relog at level 4: the
/// press of slot 4 is confirmed (0x07FD) and not refused (`opcode.0x7fd`, `opcode.0x7fc`).
/// The clock is driven and nothing waits on real time.
pub fn a_spellslinger_that_levels_from_3_to_4_casts_its_new_ability_and_a_relog_at_4_casts_it_too_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let tables = fixture_tables.shared()
  let started = world_with_the_markers_creatures(tables:, time:)
  let assert Ok(level_four) = xp_per_level.get(tables:, id: XpPerLevelId(4))
    as "XpPerLevel has a row 4"
  let #(game, frames, have, character) =
    a_player_of_a_level_at_the_marker_ring(
      started:,
      class_id: 7,
      sixth: 0,
      level: 3,
      saved_experience: Some(level_four.min_xp_for_level - 1),
    )
  assert location_4_items(frames:)
    == [#(0, 27_638), #(1, 20_684), #(2, 20_325), #(3, 31_213)]
    as "SpellLevel 1011, 1036 and 1236 (level 1, in id order) then Class 7's innate Spell4 47273 (base 31213)"
  let target = the_target_at_slot_0(frames:)
  let assert Ok(other) =
    list.find(targets_in(frames:), fn(creature) {
      creature.unit_id != target.unit_id
    })
    as "the ring's second 73492 stands at slot 2"
  let slot = ring_slot(index: 0)
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(slot.0 +. 12.0, slot.2), target: #(
      slot.0,
      slot.2,
    )),
    clock: 100,
  )
  let assert Ok(#(killed, have)) =
    fight_bot.presses_until_the_target_dies(
      // `lingers_ms` holds the 1000 ms global cooldown, not an effect duration: the
      // press that leaves the creature alive waits that long before the next press.
      ability: fight_bot.Ability(
        bag_index: 0,
        cast_ms: spellslinger_cast_ms,
        lingers_ms: spellslinger_cast_ms,
      ),
      advance: driven_time.advance(time:, ms: _),
      recharge_ms: 0,
      game:,
      have:,
      target: target.unit_id,
      cast_id: 1,
      seen: [],
    )
  let #(rest, have) =
    game_client.read_until(game:, have:, found: fn(rest) {
      list.any(list.append(killed, rest), fn(frame) {
        frame.message_id == 0x01A0
      })
    })
  let risen =
    list.filter(list.append(killed, rest), fn(frame) {
      list.contains([0x0111, 0x01A0], frame.message_id)
    })
  let assert [ability, book] = list.drop(risen, list.length(risen) - 2)
  let assert Ok(added) = item_added.decode(ability.body)
  assert #(
      added.held_item.item.location,
      added.held_item.item.bag_index,
      added.held_item.item.item_id,
      added.held_item.reason,
    )
    == #(4, 4, 20_718, 49)
    as "opcode.0x111.ability_level_up: SpellLevel 1012's base at the slot after the bag of 4, reason 49"
  let assert Ok(tiers) = ability_tiers.decode(book.body)
  assert tiers.tiers
    == list.flat_map([20_718, 54_909], fn(base) {
      list.map([0, 1, 2, 3], fn(action_set_index) {
        AbilityTier(spell4_base_id: base, tier: 1, action_set_index:)
      })
    })
    as "opcode.0x1a0: tier 1 of the base and of its alternate (Spell4Base 54909) in each of the four action sets"
  // The press of slot 4 at the ring's other creature, which stands alive and untouched,
  // once the global cooldown of the last press of the fight has run.
  driven_time.advance(time:, ms: spellslinger_cast_ms)
  game_client.press_ability(
    game:,
    client_cast_id: 50,
    bag_index: 4,
    target: other.unit_id,
  )
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 8)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: the press of the new ability is not refused"
  assert result.is_ok(game_client.confirmed_cast_of(
    frames: pressed,
    client_cast_id: 50,
  ))
    as "opcode.0x7fd: the press of the new ability is confirmed"
  // The relog at level 4 holds the new ability in slot 4 and casts it.
  let #(second_entry, have) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert location_4_items(frames: second_entry)
    == [
      #(0, 27_638),
      #(1, 20_684),
      #(2, 20_325),
      #(3, 31_213),
      #(4, 20_718),
    ]
    as "a relog holds the book a rise made, in its order"
  // The ring's other creature is shown to the player again, alive, before the press. The map
  // tells the connection of it and the connection itself writes the 0x01BC the entry read ends
  // on: two senders, so the creature may already be in the entry's frames, and the wait looks
  // in them too.
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(shown) {
      list.any(
        targets_in(frames: list.append(second_entry, shown)),
        fn(creature) { creature.unit_id == other.unit_id },
      )
    })
  game_client.press_ability(
    game:,
    client_cast_id: 60,
    bag_index: 4,
    target: other.unit_id,
  )
  let #(pressed, _) = game_client.read_until_pong(game:, have:, number: 9)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: the press after the relog is not refused"
  assert result.is_ok(game_client.confirmed_cast_of(
    frames: pressed,
    client_cast_id: 60,
  ))
    as "opcode.0x7fd: the press after the relog is confirmed"
  game_client.close(game:)
  login_support.stop(started)
}

/// The cast time of the Spellslinger's slot 0 ability (Spell4 43468) and of the level 4
/// one (Spell4 34756): 1000 ms each, with a global cooldown of 1000 ms.
const spellslinger_cast_ms = 1000

/// Whether the frame is a 0x938 of a stat other than the level.
fn is_other_stat(frame frame: Frame) -> Bool {
  use <- bool.guard(when: frame.message_id != 0x0938, return: False)
  let assert Ok(changed) = unit_stat_changed.decode(frame.body)
    as "the server's 0x938 decodes"
  case changed.change {
    unit_stat_change.Level(..) -> False
    unit_stat_change.Shield(..)
    | unit_stat_change.InterruptArmor(..)
    | unit_stat_change.Absorption(..) -> True
  }
}

/// The cast id of the cast of `spell4_id` that the frames both start and send the go of, and
/// the unit its start names as caster.
fn started_and_gone(
  frames frames: List(Frame),
  spell4_id spell4_id: Int,
) -> Result(#(Int, Int), Nil) {
  let events = game_client.casts_in(frames:)
  use #(cast_id, caster) <- result.try(
    list.first(game_client.starts_of(events:, spell4_id:)),
  )
  case
    list.any(events, fn(event) {
      event == game_client.CastWent(cast_id:, phase: 0)
    })
  {
    True -> Ok(#(cast_id, caster))
    False -> Error(Nil)
  }
}

/// The ids of the frames of one cast: the start, the go, the removal of its nodes and the
/// finish, which each begin with the cast id in 32 bits.
fn frames_of_cast(
  frames frames: List(Frame),
  cast_id cast_id: Int,
) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id, frame.body {
      0x07FF, <<id:32-little, _:bits>>
      | 0x07F4, <<id:32-little, _:bits>>
      | 0x0811, <<id:32-little, _:bits>>
      | 0x07FE, <<id:32-little, _:bits>>
      | 0x07FD, <<_:32-little, id:32-little, _:bits>>
        if id == cast_id
      -> Ok(frame.message_id)
      _, _ -> Error(Nil)
    }
  })
}

/// A Medic of level 3 one experience short of level 4 kills the creature at ring slot 0 in
/// sight of a second player and, as the client does 2000 ms after the rise, asks for the
/// fanfare of level 4 with 0x07A5: it is answered with the start and the go of Spell4 77409,
/// Level Up tier 3 (`Spell4.tierIndex.level_up`), which lists its own unit with the tier's one
/// effect row 202345, with no 0x07FD (that answers a press), and both players read the 0x07FE
/// of that cast 5000 ms after the go, the effect's life (`spell.level_up.cast`).
/// A Replay of level 2 is answered with Spell4 77398, and a level above the player's ends the
/// connection, which the second player reads as a leave. The full-screen text, the announcer's
/// voice and the "Level Up!" box are the client's own drawing and are not observable here. The
/// clock is driven and nothing waits on real time.
pub fn a_level_ups_0x07a5_is_answered_with_the_level_up_cast_and_a_player_in_sight_reads_the_same_cast_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- on_rows_without_paralytic_surges_recharge()
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let assert Ok(level_four) = xp_per_level.get(tables:, id: XpPerLevelId(4))
    as "XpPerLevel has a row 4"
  let #(first, frames, first_have, _) =
    a_medic_of_a_level_at_the_marker_ring(
      started:,
      sixth: 0,
      level: 3,
      saved_experience: Some(level_four.min_xp_for_level - 1),
    )
  let first_unit = game_client.unit_create_player_in(frames:).unit_id
  // A second player stands 14 units beyond the first, in sight of it.
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let slot = ring_slot(index: 0)
  let #(second, second_character) =
    new_player_at_level(
      started:,
      number: 2,
      character_name: "Ab Cd",
      class_id: 4,
      level: 9,
    )
  character_support.move_to(
    pool:,
    character_id: second_character,
    world_id: 3460,
    world_zone_id: 5967,
    position: #(slot.0 +. 14.0, slot.1, slot.2),
  )
  send_play(game: second, character_id: second_character)
  let #(_, second_have) =
    game_client.read_until(game: second, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  let #(_, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.any(frames, fn(frame) {
        frame.message_id == 0x0262
        && case game_client.created_unit(body: frame.body) {
          Ok(game_client.PlayerCreated(unit:)) -> unit.unit_id != first_unit
          _ -> False
        }
      })
    })
  let #(killed, first_have) =
    kills_the_target_at_slot_0(game: first, have: first_have, frames:, time:)
  let #(rest, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(rest) {
      list.any(list.append(killed, rest), fn(frame) {
        frame.message_id == 0x01A0
      })
    })
  assert list.any(list.append(killed, rest), fn(frame) {
    frame.message_id == 0x0938 && !is_other_stat(frame:)
  })
    as "the kill raised the level to 4 (opcode.0x938), as the 0x07A5 of the fanfare follows it"
  // The client's fanfare asks 2000 ms after the rise; the clock is driven, so the test
  // does not wait.
  game_client.replay_level_up(game: first, level: 4)
  let #(answered, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      result.is_ok(started_and_gone(frames:, spell4_id: 77_409))
    })
  let assert Ok(#(cast_id, caster)) =
    started_and_gone(frames: answered, spell4_id: 77_409)
  assert caster == first_unit
    as "opcode.0x7ff: the cast is the player's own, started on the player's unit"
  assert frames_of_cast(frames: answered, cast_id:) == [0x07FF, 0x07F4]
    as "spell.level_up.cast: the start and the go, and no 0x07FD (it answers a press)"
  assert game_client.go_targets_in(frames: answered)
    |> list.filter(fn(go) { go.0 == cast_id })
    == [#(cast_id, [first_unit])]
    as "opcode.0x7f4: the go names the player's own unit"
  let assert [go_frame] =
    list.filter(answered, fn(frame) {
      frame.message_id == 0x07F4
      && case frame.body {
        <<id:32-little, _:bits>> -> id == cast_id
        _ -> False
      }
    })
  let assert Ok(go) = spell_go.decode(go_frame.body)
  let assert [info] = go.targets
  assert list.map(info.effects, fn(effect) { effect.spell4_effects_id })
    == [level_up_support.tier(level: 4).effect_id]
    as "Spell4Effects 202345, the one row of tier 3 (Spell4.tierIndex.level_up)"
  let #(seen, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      result.is_ok(started_and_gone(frames:, spell4_id: 77_409))
    })
  let assert Ok(#(seen_id, seen_caster)) =
    started_and_gone(frames: seen, spell4_id: 77_409)
  assert seen_id == cast_id && seen_caster == first_unit
    as "a player in sight reads the same cast, started by the first player's unit"
  assert game_client.go_targets_in(frames: seen)
    |> list.filter(fn(go) { go.0 == cast_id })
    == [#(cast_id, [first_unit])]
  assert frames_of_cast(frames: seen, cast_id:) == [0x07FF, 0x07F4]
    as "and no 0x07FD"
  // The effect's life is over 5000 ms after the go.
  driven_time.advance(time:, ms: 5000)
  let #(first_end, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.contains(frames_of_cast(frames:, cast_id:), 0x07FE)
    })
  assert frames_of_cast(frames: first_end, cast_id:) == [0x07FE]
    as "spell.level_up.cast: the finish, and nothing else of the cast"
  let #(second_end, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.contains(frames_of_cast(frames:, cast_id:), 0x07FE)
    })
  assert frames_of_cast(frames: second_end, cast_id:) == [0x07FE]
    as "a player in sight reads the same end"
  // A Replay of level 2 is answered with the tier of level 2.
  game_client.replay_level_up(game: first, level: 2)
  let #(replayed, _) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      result.is_ok(started_and_gone(frames:, spell4_id: 77_398))
    })
  assert result.is_ok(started_and_gone(frames: replayed, spell4_id: 77_398))
    as "lua.LevelUpUnlocks.ReplayLevelUp: the Replay button asks for an earlier level and gets that tier"
  // A level above the player's is refused: the connection ends, and the second player
  // reads the first leave.
  game_client.replay_level_up(game: first, level: 5)
  game_client.await_closed(game: first)
  let #(left, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.contains(destroyed_units(frames:), first_unit)
    })
  assert list.contains(destroyed_units(frames: left), first_unit)
    as "opcode.0x355: the player whose connection ended leaves the other's sight"
  game_client.close(game: second)
  login_support.stop(started)
}

/// The (bag index, Spell4Base id) of the type 4 shortcuts of the one 0x019D among frames.
fn bar_shortcuts(frames frames: List(Frame)) -> List(#(Int, Int)) {
  limited.the_action_set(frames:).shortcuts
  |> list.filter(fn(shortcut) { shortcut.shortcut_type == 4 })
  |> list.map(fn(shortcut) { #(shortcut.bag_index, shortcut.object_id) })
}

/// A Spellslinger of level 4 who sets its bar with the client's own 0xB1 (the 2026-11-19
/// sitting's saves A and C, whose bytes the part 1 tests hold) and plays again after a camp.
/// The class loadout is the three level 1 abilities in slots 0 to 2 (SpellLevel 1011, 1036 and
/// 1236); the saved bar is what the next entry's 0x019D carries (`opcode.0x19d`) and the
/// answer is 0x019D, 0x01A0, 0x0169 then 0x00B2 (`opcode.0xb2`).
pub fn a_bar_saved_with_the_clients_0xb1_is_back_after_a_relog_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: limited.spellslinger,
      level: 4,
    )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  assert bar_shortcuts(frames: entry)
    == [#(0, 27_638), #(1, 20_684), #(2, 20_325)]
    as "a character that saved nothing enters with the class's three abilities"
  game_client.send_world(
    game:,
    message_id: 0x00B1,
    body: limited.hex(limited.save_a),
  )
  let #(answer, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x00B2 })
    })
  assert list.filter_map(answer, fn(frame) {
      case frame.message_id {
        0x019D | 0x00B2 -> Ok(frame.message_id)
        _ -> Error(Nil)
      }
    })
    == [0x019D, 0x00B2]
    as "the answer is the set then 0xB2"
  assert limited.the_action_set(frames: answer).result == 1
    as "the sitting's first save is accepted at level 4"
  assert bar_shortcuts(frames: answer)
    == [#(0, 27_638), #(1, 20_684), #(2, 20_325), #(3, 20_718)]
    as "slots 0 to 3 are the abilities of the save"
  assert limited.the_answer_bit(frames: answer) == 1
  let #(second_entry, have) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert bar_shortcuts(frames: second_entry)
    == [#(0, 27_638), #(1, 20_684), #(2, 20_325), #(3, 20_718)]
    as "the next entry holds the four shortcuts of the save, not the class's three"
  game_client.send_world(
    game:,
    message_id: 0x00B1,
    body: limited.hex(limited.save_c),
  )
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x00B2 })
    })
  let #(third_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert bar_shortcuts(frames: third_entry) == [#(0, 27_638), #(1, 20_684)]
    as "after the sitting's third save and a relog the entry holds 27638 and 20684 only"
  game_client.close(game:)
  login_support.stop(started)
}

/// The abilities the one 0x01A0 among frames holds above tier 1, as (Spell4Base, action set,
/// tier).
fn raised_tiers(frames frames: List(Frame)) -> List(#(Int, Int, Int)) {
  ability_book_support.tiers_in(frames:)
  |> list.filter(fn(entry) { entry.tier > 1 })
  |> list.map(fn(entry) {
    #(entry.spell4_base_id, entry.action_set_index, entry.tier)
  })
}

/// A Spellslinger of level 10 (one ability point) who buys Quick Draw's tier 2 with the client's
/// own 0xB1 (the class's bar and the tier change, `opcode.0xb1`), camps and plays again, then
/// returns Quick Draw to tier 1 and does the same. The entry's 0x01A0 holds the tier in set 0
/// (`opcode.0x1a0`) and its 0x0169 the point spent (`opcode.0x169`); the answer is 0x019D, 0x01A0,
/// 0x0169 then 0x00B2 (`opcode.0xb2`). Quick Draw's tier 2 costs 1 (`Spell4.abilityPointCost`).
pub fn a_tier_bought_in_the_builder_is_back_after_a_camp_and_a_tier_returned_to_1_is_gone_after_the_next_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(10_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: limited.spellslinger,
      level: 10,
    )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  assert raised_tiers(frames: entry) == []
    as "a character that saved nothing enters with every ability at tier 1"
  assert ability_points_support.points_in(frames: entry) == [#(1, 1)]
    as "and the level's one point unspent"
  game_client.send_world(
    game:,
    message_id: 0x00B1,
    body: limited.tiering([#(27_638, 2)]),
  )
  let #(answer, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x00B2 })
    })
  assert list.map(answer, fn(frame) { frame.message_id })
    == [0x019D, 0x01A0, 0x0169, 0x01A3, 0x00B2]
    as "the answer is the set, the tiers, the points, the AMPs, then 0xB2"
  assert raised_tiers(frames: answer) == [#(27_638, 0, 2), #(52_215, 0, 2)]
    as "opcode.0x1a0: Quick Draw at 2 and its alternate 52215, which shows the tier of the ability that names it"
  assert ability_points_support.points_in(frames: answer) == [#(0, 1)]
  let #(second_entry, have) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert raised_tiers(frames: second_entry)
    == [#(27_638, 0, 2), #(52_215, 0, 2)]
    as "the next entry holds Quick Draw and its alternate at tier 2 in set 0 and every other entry at tier 1"
  assert list.map(
      ability_book_support.tiers_in(frames: second_entry),
      fn(entry) { #(entry.spell4_base_id, entry.action_set_index) },
    )
    == list.map(ability_book_support.tiers_in(frames: entry), fn(entry) {
      #(entry.spell4_base_id, entry.action_set_index)
    })
    as "the same abilities in the same order as the first entry"
  assert ability_points_support.points_in(frames: second_entry) == [#(0, 1)]
    as "and the point stays spent"
  game_client.send_world(
    game:,
    message_id: 0x00B1,
    body: limited.tiering([#(27_638, 1)]),
  )
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x00B2 })
    })
  let #(third_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert raised_tiers(frames: third_entry) == []
    as "a tier returned to 1 is gone after the next camp"
  assert ability_points_support.points_in(frames: third_entry) == [#(1, 1)]
    as "and the point is back"
  game_client.close(game:)
  login_support.stop(started)
}

/// The frames among these that the builder's save is answered with, in order.
fn builder_answer(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x019D | 0x01A0 | 0x0169 | 0x01A3 | 0x00B2 -> Ok(frame.message_id)
      _ -> Error(Nil)
    }
  })
}

/// A Spellslinger of level 10 (7 AMP power) who sends the client's own 0xB1 with the AMP list of
/// a Stalker (863, a class the Spellslinger is not), then the class's bar with the chain of
/// category 1 and its tier 1 AMP (220 to 222 and 259, 7 of 7 power), the same again, and 259
/// alone, then camps and plays again. Each answer is the set, the held list and 0xB2, or for an
/// accepted save the set, the tiers, the points, the list and 0xB2 (`opcode.0x1a3`,
/// `opcode.0xb2`). A list the check refuses or one that drops a held AMP changes nothing; a camp
/// forgets the picks, since the place save writes no AMP row.
pub fn an_amp_picked_in_the_builder_is_answered_with_0x1a3_and_a_refused_one_changes_nothing_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(10_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: limited.spellslinger,
      level: 10,
    )
  send_play(game:, character_id: character)
  let #(entry, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x01BC })
    })
  assert limited.amp_lists_in(frames: entry) == []
    as "a character that holds no AMP enters with no 0x01A3"
  let save = fn(have, amp_ids) {
    game_client.send_world(
      game:,
      message_id: 0x00B1,
      body: limited.amps_body(class_id: limited.spellslinger, amp_ids:),
    )
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x00B2 })
    })
  }
  let #(answer, have) = save(have, [863])
  assert limited.the_action_set(frames: answer).result == 4
    as "863 is a Stalker's AMP: the class test is reached, since 4 of 7 power is within the level's"
  assert builder_answer(frames: answer) == [0x019D, 0x01A3, 0x00B2]
    as "the held bar, the held list and 0xB2"
  assert limited.amp_lists_in(frames: answer) == [#(0, [])]
    as "nothing is held, so the list is empty"
  assert limited.the_answer_bit(frames: answer) == 0
  let #(answer, have) = save(have, [259, 220, 221, 222])
  assert limited.the_action_set(frames: answer).result == 1
  assert builder_answer(frames: answer)
    == [0x019D, 0x01A0, 0x0169, 0x01A3, 0x00B2]
    as "the set, the tiers, the points, the AMPs, then 0xB2"
  assert limited.amp_lists_in(frames: answer) == [#(0, [220, 221, 222, 259])]
    as "the list of set 0, ascending"
  assert limited.the_answer_bit(frames: answer) == 1
  let #(again, have) = save(have, [220, 221, 222, 259])
  assert builder_answer(frames: again) == builder_answer(frames: answer)
    as "the same save again is answered the same"
  assert limited.amp_lists_in(frames: again)
    == limited.amp_lists_in(frames: answer)
  let #(dropped, have) = save(have, [259])
  assert limited.the_action_set(frames: dropped).result == 43
    as "259 alone drops the held 220 to 222: removing an AMP is the paid reset"
  assert limited.amp_lists_in(frames: dropped) == [#(0, [220, 221, 222, 259])]
    as "the held list is sent again"
  assert limited.the_answer_bit(frames: dropped) == 0
  let #(second_entry, _) =
    game_client.camp_and_play(game:, have:, character_id: character)
  assert limited.amp_lists_in(frames: second_entry) == []
    as "the place save writes no AMP row, so the entry after a camp holds none"
  game_client.close(game:)
  login_support.stop(started)
  // The Stalker case: a level 10 Stalker picks the chain 770, 771, 772 and 863 and presses
  // Stagger (Spell4Base 23173, bag index 2). The answer is followed by the starts of the AMPs'
  // spells (56845, 56846, 56847 and 59436), and Stagger's fourth phase starts 79229, the Proxy
  // Prerequisite 37037 gates on 59436. The other Proxy it gates, 79220, starts on a struck unit
  // and a strike can be deflected on a seed the repeat job salts, so the cast rule's test holds
  // 79220 and this one asserts 79229 alone.
  let time = driven_time.new()
  let started =
    world_with_the_markers_creatures(tables: fixture_tables.shared(), time:)
  let #(game, entry, have, _) =
    a_player_of_a_level_at_the_marker_ring(
      started:,
      class_id: 5,
      sixth: 0,
      level: 10,
      saved_experience: option.None,
    )
  game_client.send_world_then_ping(
    game:,
    message_id: 0x00B1,
    body: limited.amps_body(class_id: 5, amp_ids: [770, 771, 772, 863]),
    number: 7,
  )
  let #(answer, have) = game_client.read_through_pong(game:, have:, number: 7)
  let amp_spells = [56_845, 56_846, 56_847, 59_436]
  let started_among = fn(frames, spells) {
    list.filter_map(game_client.casts_in(frames:), fn(event) {
      case event {
        game_client.CastStarted(spell4_id:, ..) ->
          case list.contains(spells, spell4_id) {
            True -> Ok(spell4_id)
            False -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    })
  }
  assert limited.the_action_set(frames: answer).result == 1
    as "the Stalker's pick is accepted"
  assert started_among(answer, amp_spells) == amp_spells
    as "the answer is followed by the starts of the picked AMPs' spells"
  let #(before_answer, _) =
    list.split_while(answer, fn(frame) { frame.message_id != 0x00B2 })
  assert started_among(before_answer, amp_spells) == []
    as "and none comes before the answer's 0xB2"
  // The creature at ring slot 0 is the target the phases strike (the Proxy to 79220 starts on a
  // struck unit; a strike can be deflected, so only the child that needs no struck unit is
  // asserted here and 79220's start is the cast rule's test).
  let #(_, have) = game_client.read_until_pong(game:, have:, number: 8)
  let target = the_target_at_slot_0(frames: entry)
  let slot = ring_slot(index: 0)
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(slot.0 +. 12.0, slot.2), target: #(
      slot.0,
      slot.2,
    )),
    clock: 100,
  )
  game_client.press_ability(
    game:,
    client_cast_id: 1,
    bag_index: 2,
    target: target.unit_id,
  )
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 9)
  assert started_among(pressed, [79_229]) == []
    as "the press itself starts no Proxy child: they wait for Stagger's fourth phase"
  driven_time.advance(time:, ms: 1000)
  let #(phases, _) = game_client.read_until_pong(game:, have:, number: 10)
  assert started_among(phases, [79_229]) == [79_229]
    as "Stagger's fourth phase starts the Proxy to 79229 (Spell4Effects 208198, phase 8), which Prerequisite 37037 gates on the AMP's spell standing"
  game_client.close(game:)
  login_support.stop(started)
}

/// The Blows the 0x7f4 among the frames list, by Spell4Effects id.
fn blow_effect_ids(frames frames: List(Frame)) -> List(Int) {
  list.flat_map(game_client.fight_in(frames:), fn(event) {
    case event {
      game_client.Went(targets:, ..) ->
        list.flat_map(targets, fn(target) {
          list.map(target.1, fn(blow) { blow.effect_id })
        })
      _ -> []
    }
  })
}

/// A Medic of level 10 (one ability point) saves Paralytic Surge at tier 2 with the client's
/// own 0xB1 (the class's bar, 38201, 16322 and 26543, and the tier change), faces the creature at
/// ring slot 0 and presses Paralytic Surge at bag index 2 (`fight_bot.paralytic_surge`) until the
/// creature dies, since a creature of the client's rows deflects some strikes and a deflected
/// press has a 0x7f4 with no blow. The presses are confirmed by 0x7fd, and the 0x7f4 blows hold
/// the damage effect of the tier 2 row (Spell4 51979 holds Spell4Effects 122793 and 122794,
/// `table_rows -- Spell4Effects spellId=51979`), never tier 1's 96125. Tier 2 needs level 10 and costs 1 point (`Spell4TierRequirements`,
/// `XpPerLevel`). The clock is driven and nothing waits on real time.
pub fn a_medic_that_saves_tier_2_of_paralytic_surge_casts_the_tier_2_spell_test() -> Nil {
  use <- owned_test.run(10_000)
  // The tier 2 row has its own recharge (51979, 25000 ms like tier 1's 42352), which would refuse
  // every press after the first: both rows' recharge is taken off.
  use tables <- fixture_tables.changes(edits: [
    #("Spell4", 42_352, [#("spellCoolDown", planted_table.Integer(0))]),
    #("Spell4", 51_979, [#("spellCoolDown", planted_table.Integer(0))]),
  ])
  let time = driven_time.new()
  let started = world_with_the_markers_creatures(tables:, time:)
  let #(game, entry, have, _character) =
    a_medic_of_a_level_at_the_marker_ring(
      started:,
      sixth: 0,
      level: 10,
      saved_experience: option.None,
    )
  game_client.send_world(
    game:,
    message_id: 0x00B1,
    body: limited.body_with(
      ids: [38_201, 16_322, 26_543, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      set: 0,
      tier_changes: [#(26_543, 2)],
      amp_ids: [],
    ),
  )
  let #(answer, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x00B2 })
    })
  assert limited.the_action_set(frames: answer).result == 1
    as "the save is accepted: tier 2 needs level 10 and costs the level's one point"
  let #(cast, _) =
    kills_the_target_at_slot_0(game:, have:, frames: entry, time:)
  assert refusals(frames: cast) == []
    as "opcode.0x7fc: no press of the held tier is refused"
  assert list.any(cast, fn(frame) { frame.message_id == 0x07FD })
    as "opcode.0x7fd: the press is confirmed"
  let effects = blow_effect_ids(frames: cast)
  assert list.contains(effects, 122_793)
    as "the go strikes with tier 2's damage row 122793"
  assert !list.contains(effects, 96_125) as "and not with tier 1's 96125"
  game_client.close(game:)
  login_support.stop(started)
}
