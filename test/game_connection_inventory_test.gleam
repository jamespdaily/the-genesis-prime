//// The game connection's rule (`genesis_prime/game/connection`) on an item move
//// (`genesis_prime/game/inventory`): the client's 0x182 asks the store and the
//// connection waits for its answer. Expected values come from these places.
//// - `opcode.0x182`: the client sends one move at a time and refuses the others
////   with PlayerBusy until 0x569, 0x568, 0x56A or 0x17F clears its wait, so the
////   answer is the next thing the connection writes for the player.
//// - `opcode.0x569`: the answer to a move to an empty place is the item's guid and
////   its place, location * 256 + bag index: the chest piece (guid 1, the first of
////   the Engineer's Novice set, `novice_tables`) unequipped to inventory slot 0 is
////   guid 1 at place 256.
//// - `opcode.0x1c2`: a chat line is answered with the speaker's own line.
//// - `opcode.0x111.guid`: a split makes a stack whose guid only the store knows, so
////   the client's next 0x182 of that stack, sent while the split's ask is out, is
////   taken after the answer and finds the stack by its place with that guid.
//// - `step.EffectsThenAsk`: the effects before an ask are written before the ask is
////   made, and the shell takes no other input while an ask is out, so the frames
////   the client sent meanwhile are held and taken after the answer.
//// - The same rule as the summon's: the player is in the world while the store
////   moves the item, so a close then saves the place as in the world.
//// - Failure table, `inventory.answered`'s row for a store that is unavailable or
////   past its deadline: the move's outcome is unknown, so the connection ends and
////   the client is told 0x036A reason 8 (LostUserServer), as for any server fault.

import character_support
import character_tables
import connection_rule_support as support
import experience_support
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{
  type Request, AskStore, FromMap, FromStore,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/gear
import genesis_prime/game/unit_news.{LookChanged, PropertiesChanged}
import genesis_prime/message/bit_stream
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/item_action_failed.{ItemActionFailed}
import genesis_prime/message/item_delete
import genesis_prime/message/item_moved.{ItemMoved}
import genesis_prime/message/item_place
import genesis_prime/message/item_split.{ItemSplit}
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/player_health
import genesis_prime/message/send_chat_line.{SendChatLine}
import genesis_prime/message/spell_started
import genesis_prime/message/unit_item_visuals_changed
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_shield
import genesis_prime/step.{
  type ConnectionStep, EndedBeforeAnswer, LogError, NoAnswerInTime, NotRunning,
  OwnEffect, OwnEvent, StartTimer, TimerId, Unwatch, Watch,
}
import genesis_prime/store.{
  type HeldItem, AccountId, CharacterId, ForItems, HeldItem, ItemMade, ItemMove,
  ItemPlace, Items, ItemsNotSaved, ItemsSaved, MoveItems, SaveRefused, SplitItem,
}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/list
import gleam/option.{None, Some}
import item_flags_support
import owned_test
import vendor_support
import world_entry_support
import worn_item_support

/// A 0x182 of the chest piece from the worn slot 0 to inventory slot 0, as the
/// client sends it, inside 0x038C.
fn chest_unequipped() -> BitArray {
  game_connection_support.item_moved_message(
    from: item_place.ItemPlace(location: 0, bag_index: 0),
    to: item_place.ItemPlace(location: 1, bag_index: 0),
  )
}

/// A 0x1c3 of the Say channel, as the client sends it.
fn say_hello() -> BitArray {
  let assert Ok(body) =
    send_chat_line.encode(SendChatLine(
      channel_type: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("Hello"),
      formats: [],
      chat_message_id: 1,
    ))
  game_connection_support.world_message(send_chat_line.message_id, body)
}

/// The store's ask for the chest piece's move: the tests' account and character,
/// the epoch their load gave, and the one move.
fn move_asked() -> client_connection.Request {
  AskStore(
    Items(
      MoveItems(
        account_id: AccountId(7),
        character_id: CharacterId(42),
        session_epoch: character_support.epoch(1),
        moves: [
          ItemMove(
            item_guid: 1,
            from: ItemPlace(location: 0, bag_index: 0),
            to: ItemPlace(location: 1, bag_index: 0),
            flags_set: 0,
          ),
        ],
      ),
    ),
  )
}

pub fn a_move_answer_comes_before_the_frames_after_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      chest_unequipped(),
    )
  assert game_connection_support.ask_request(taken) == move_asked()
    as "opcode.0x182: the accepted move is the store's ask, fenced by the login's epoch"
  assert support.writes(taken) == []
    as "nothing is written before the store has moved the item"
  let #(state, held) = game_connection_support.read(state, say_hello())
  assert support.writes(held) == [] && support.asked(held) == None
    as "step.EffectsThenAsk: the client's frames are held while the ask is out"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(ItemsSaved))),
    )
  assert game_connection_support.written_ids(answered)
    == [0x0569, 0x0933, 0x093A, 0x092F, 0x01C2]
    as "opcode.0x569, then the chest's look, properties and capped health (health_above_the_new_maximum_is_capped_and_told_test), then opcode.0x1c2: the move's answer goes out first, then the held line is taken and answered"
  let assert [first, ..] = game_connection_support.written(answered)
  assert item_moved.decode(first.body)
    == Ok(ItemMoved(item_guid: 1, place: 256))
    as "opcode.0x569: guid 1 at location 1, bag index 0, which is 256"
}

pub fn a_connection_that_ends_while_a_move_waits_saves_its_place_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.read(
      game_connection_support.in_world(),
      chest_unequipped(),
    )
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "the player is in the world while the store moves the item, so its place is saved as in InWorld"
}

pub fn a_move_the_store_cannot_answer_ends_the_connection_with_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(store.Unavailable)),
      NotRunning,
      NoAnswerInTime,
      EndedBeforeAnswer,
    ],
    fn(outcome) {
      let #(state, taken) =
        game_connection_support.read(
          game_connection_support.in_world(),
          chest_unequipped(),
        )
      let #(state, answered) =
        game_connection_support.answer(state:, taken:, outcome:)
      assert list.length(support.logs_of(step: answered, level: LogError)) == 1
        as "a move whose outcome is unknown is an error line"
      assert game_connection_support.written_ids(answered) == []
        as "no 0x569, 0x568 or 0x56A: nothing says whether the item moved"
      let #(_, saved) =
        game_connection_support.answer(
          state:,
          taken: answered,
          outcome: game_connection_support.place_saved(),
        )
      assert game_connection_support.disconnect(
          saved,
          game_connection_support.keyed(),
        )
        == LostUserServer
        as "the player's place is saved, then 0x036A reason 8"
    },
  )
}

/// Item2 1039, a stackable item of the client's tables that holds 20.
const stackable_item2 = 1039

/// The Engineer's seven worn items and a stack of 10 of Item2 1039 in inventory
/// slot 1, guid 20.
fn stack() -> HeldItem {
  HeldItem(
    item_guid: 20,
    item2_id: Item2Id(fixture_tables.root("Item2", stackable_item2)),
    location: 1,
    bag_index: 1,
    stack_count: 10,
    words: store.ItemWords(
      random_stats: 0,
      charges: 0,
      item_flags: 0,
      expires_at_unix_ms: None,
    ),
  )
}

fn holding_a_stack() -> game_connection.State {
  game_connection_support.in_world_holding(
    items: list.append(
      world_entry_support.novice_items(
        character: game_connection_support.world_character(),
      ),
      [stack()],
    ),
  )
}

/// A 0x17d of 3 of the stack to the empty inventory slot 2, inside 0x038C.
fn three_split_off() -> BitArray {
  let assert Ok(body) =
    item_split.encode(ItemSplit(
      item_guid: 20,
      to: item_place.ItemPlace(location: 1, bag_index: 2),
      count: 3,
    ))
  game_connection_support.world_message(
    message_id: item_split.message_id,
    body:,
  )
}

/// A 0x182 of whatever is in inventory slot 2 to the empty inventory slot 3.
fn slot_2_to_slot_3() -> BitArray {
  game_connection_support.item_moved_message(
    from: item_place.ItemPlace(location: 1, bag_index: 2),
    to: item_place.ItemPlace(location: 1, bag_index: 3),
  )
}

pub fn a_split_answer_comes_before_the_frames_after_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(holding_a_stack(), three_split_off())
  assert game_connection_support.ask_request(taken)
    == AskStore(
      Items(SplitItem(
        account_id: AccountId(7),
        character_id: CharacterId(42),
        session_epoch: character_support.epoch(1),
        source: stack(),
        count: 3,
        to: ItemPlace(location: 1, bag_index: 2),
      )),
    )
    as "opcode.0x17d: the accepted split is the store's ask, fenced by the login's epoch and the stack as held"
  assert support.writes(taken) == []
    as "nothing is written before the store has made the stack"
  let #(state, held) = game_connection_support.read(state, slot_2_to_slot_3())
  assert support.writes(held) == [] && support.asked(held) == None
    as "step.EffectsThenAsk: the 0x182 of the new stack is held while the split's ask is out"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(ItemMade(item_guid: 77)))),
    )
  assert game_connection_support.written_ids(answered) == [0x017F, 0x0111]
    as "opcode.0x17f then opcode.0x111: the source's count and the new stack, with the store's guid, go out before the held 0x182 is handled"
  assert game_connection_support.ask_request(answered)
    == AskStore(
      Items(
        MoveItems(
          account_id: AccountId(7),
          character_id: CharacterId(42),
          session_epoch: character_support.epoch(1),
          moves: [
            ItemMove(
              item_guid: 77,
              from: ItemPlace(location: 1, bag_index: 2),
              to: ItemPlace(location: 1, bag_index: 3),
              flags_set: 0,
            ),
          ],
        ),
      ),
    )
    as "opcode.0x111.guid: the held 0x182 finds the new stack at its slot, and asks for it by the guid the store made"
}

/// Item2 50770, a chest piece whose required level is 3
/// (`equip_requirement_test`).
const level_3_chest = 50_770

/// The Engineer at level 2 with 1709 experience, the most of level 2
/// (XpPerLevel.minXpForLevel: 655 for level 2, 1710 for level 3), wearing the
/// Novice set but no chest piece, and holding the level 3 chest piece in
/// inventory slot 0 (guid 9).
fn holding_a_level_3_chest() -> game_connection.State {
  let character = game_connection_support.world_character()
  let worn =
    list.filter(world_entry_support.novice_items(character:), fn(item) {
      item.bag_index != 0
    })
  let #(state, taken) =
    game_connection_support.joining_holding_items(
      in_character_select: game_connection_support.in_select(),
      character: store.Character(..character, level: 2),
      saved_health: None,
      saved_experience: Some(1709),
      quests: [],
      items: list.append(worn, [
        HeldItem(
          item_guid: 9,
          item2_id: Item2Id(fixture_tables.root(
            table: "Item2",
            id: level_3_chest,
          )),
          location: 1,
          bag_index: 0,
          stack_count: 1,
          words: store.ItemWords(
            random_stats: 0,
            charges: 0,
            item_flags: 0,
            expires_at_unix_ms: None,
          ),
        ),
      ]),
    )
  game_connection_support.answer(
    state:,
    taken:,
    outcome: step.Answer(FromMap(game_connection_support.map_answer(taken))),
  ).0
}

/// A 0x182 of inventory slot 0 to the worn chest slot, inside 0x038C.
fn chest_equipped() -> BitArray {
  game_connection_support.item_moved_message(
    from: item_place.ItemPlace(location: 1, bag_index: 0),
    to: item_place.ItemPlace(location: 0, bag_index: 0),
  )
}

pub fn an_equip_is_checked_against_the_entered_character_test() -> Nil {
  use <- owned_test.run(10_000)
  // The level the check reads is the entered character's own, which a kill's
  // level-up changes (0x1403b4710: the unit's level). A kill of 5 takes 1709
  // experience to 1714, which is level 3 (XpPerLevel.minXpForLevel 1710). The
  // level 3 chest piece, Item2 50770 (requiredLevel 3), is refused with 42
  // (Item_LevelToLow) at level 2 and equipped at level 3. The brief starts at
  // level 1, which no single kill takes to level 3, so the character starts at
  // level 2.
  let #(state, refused) =
    game_connection_support.read(holding_a_level_3_chest(), chest_equipped())
  assert support.asked(refused) == None
    as "a refused equip asks the store for nothing"
  let assert [failed] = game_connection_support.written(refused)
    as "the refusal is the one frame written"
  assert failed.message_id == 0x056A
    as "opcode.0x56a: a refused move is answered 0x56A"
  assert item_action_failed.decode(failed.body)
    == Ok(ItemActionFailed(unread_1: 9, code: 42))
    as "Item_LevelToLow, with the guid of the item at the source"
  let #(state, credit) =
    experience_support.credited(state:, creature_id: 73_464, level: 1)
  assert list.map(experience_support.level_writes(taken: credit), fn(write) {
      write.1
    })
    == [3]
    as "the kill takes the character to level 3"
  let #(state, taken) = game_connection_support.read(state, chest_equipped())
  assert game_connection_support.ask_request(taken)
    == AskStore(
      Items(
        MoveItems(
          account_id: AccountId(7),
          character_id: CharacterId(42),
          session_epoch: character_support.epoch(1),
          moves: [
            ItemMove(
              item_guid: 9,
              from: ItemPlace(location: 1, bag_index: 0),
              to: ItemPlace(location: 0, bag_index: 0),
              flags_set: 1,
            ),
          ],
        ),
      ),
    )
    as "at level 3 the same move is the store's ask; Item2 50770 binds on equip (bindFlags 16), so the ask sets bit 0"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(ItemsSaved))),
    )
  let worn_chest =
    gear.of_items(tables: fixture_tables.shared(), level: 3, items: [
      HeldItem(
        item_guid: 9,
        item2_id: Item2Id(level_3_chest),
        location: 0,
        bag_index: 0,
        stack_count: 1,
        words: store.ItemWords(
          random_stats: 0,
          charges: 0,
          item_flags: 0,
          expires_at_unix_ms: None,
        ),
      ),
    ])
  assert worn_chest.unread == []
    as "Item2 50770 has ItemStat 414, whose only entry is kind 2, a random stat (ItemBudget 3 gives it a share of 1.0): the reader reads the chest, and its random stat gives nothing until issue 665"
  assert game_connection_support.written_ids(answered)
    == [0x0569, 0x0567, 0x0933, 0x093A]
    as "the move's frame, the binding (Item2 50770 binds on equip), the look with the chest shown, and the properties the chest gives"
  assert properties_written(taken: answered)
    == [
      [
        game_connection_support.property(id: 7, number: 1017.0),
        game_connection_support.property(id: 35, number: 207.5625),
        game_connection_support.property(id: 42, number: 281.25),
      ],
    ]
    as "the chest's own properties at power level 3: Base Health 225 and Armor 93.75 (GameFormula 67 and 547 give 60 and 20 for each level, ItemSlot 1's 1.25 and the armor category's 1.25) and Assault Rating 13.5, over the worn Novice set without a chest (450, 187.5, 194.0625) and CreatureLevel row 3's Base Health 342.09"
  let assert [moved, ..] = game_connection_support.written(answered)
  assert item_moved.decode(moved.body) == Ok(ItemMoved(item_guid: 9, place: 0))
    as "opcode.0x569: guid 9 at location 0, bag index 0, which is 0"
}

// ---- the gear after a worn item changes ----
//
// The Engineer of faction 166 (`game_connection_support.world_character`) wears the
// Novice set of `gear_test`: its sums are Base Health 600 (the chest's quarter is 150, the
// boots' three twentieths of the five slot modifiers 90), Armor 250 (62.5 and 37.5),
// Assault Rating 203.0625 (the chest's 9.0) and the shield's four properties. A maximum
// health is CreatureLevel row 1's 135.97 and the worn Base Health, rounded: 736 worn and
// 586 without the chest (`player.level1_base_health`). The look names the empty slot with
// display 0 (`opcode.0x933.empty_display`); the chest's ItemSlot is 1, the boots' 5, and
// the Engineer of faction 166 shows display 3842 on the chest (`novice_tables.worn_displays`).

/// The 0x933 the step writes: its visuals, after checking it names the player's unit.
fn looks_written(
  taken taken: ConnectionStep(Request),
) -> List(List(ItemVisual)) {
  list.map(
    game_connection_support.decoded(
      game_connection_support.written(taken),
      0x0933,
      unit_item_visuals_changed.decode,
    ),
    fn(message) {
      assert message.unit_id == game_connection_support.own_unit_id
      message.item_visuals
    },
  )
}

/// The entries of each 0x93a the step writes, after checking it names the player's unit.
fn properties_written(
  taken taken: ConnectionStep(Request),
) -> List(List(UnitProperty)) {
  list.map(
    game_connection_support.decoded(
      game_connection_support.written(taken),
      0x093A,
      unit_properties_changed.decode,
    ),
    fn(message) {
      assert message.unit_id == game_connection_support.own_unit_id
      message.properties
    },
  )
}

/// The health each 0x92f the step writes gives.
fn health_written(taken taken: ConnectionStep(Request)) -> List(Int) {
  list.map(
    game_connection_support.decoded(
      game_connection_support.written(taken),
      0x092F,
      player_health.decode,
    ),
    fn(message) { message.health },
  )
}

/// The player in the world, watched by the viewers 2 and 3, that has asked the store for
/// `message` and is given its answer: the saved step.
fn saved_after(
  state state: game_connection.State,
  message message: BitArray,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, taken) = game_connection_support.read(state, message)
  game_connection_support.answer(
    state:,
    taken:,
    outcome: step.Answer(FromStore(ForItems(ItemsSaved))),
  )
}

fn watched() -> game_connection.State {
  game_connection_support.watched_by(
    state: game_connection_support.in_world(),
    viewers: [2, 3],
  )
}

/// The Engineer's properties with its chest: 736, 203.0625 and 250.
fn with_the_chest() -> List(UnitProperty) {
  [
    game_connection_support.property(id: 7, number: 736.0),
    game_connection_support.property(id: 35, number: 203.0625),
    game_connection_support.property(id: 42, number: 250.0),
  ]
}

pub fn unequipping_the_chest_sends_0x569_then_0x933_then_0x93a_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, answered) =
    saved_after(state: watched(), message: chest_unequipped())
  assert list.take(game_connection_support.written_ids(answered), 3)
    == [0x0569, 0x0933, 0x093A]
    as "record D: the move's own frame, then the look, then the properties"
  assert looks_written(taken: answered)
    == [[game_connection_support.look(slot: 1, display: 0)]]
    as "opcode.0x933.empty_display: the chest's slot 1 is emptied"
  assert properties_written(taken: answered)
    == [game_connection_support.without_the_chest()]
    as "opcode.0x93a: the three properties the chest gave, in property order, base and value as worked out"
  let told = game_connection_support.news_broadcast(answered)
  assert list.take(told, 2)
    == [
      LookChanged(item_visuals: [
        game_connection_support.look(slot: 1, display: 0),
      ]),
      PropertiesChanged(properties: game_connection_support.without_the_chest()),
    ]
    as "opcode.0x93a.other_unit: each viewer is told the same look and entries"
}

pub fn equipping_the_chest_back_restores_the_entry_properties_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = saved_after(state: watched(), message: chest_unequipped())
  let #(_, answered) = saved_after(state:, message: chest_equipped())
  assert game_connection_support.written_ids(answered)
    == [0x0569, 0x0933, 0x093A]
    as "the move's frame, the look, the properties; the health stays below the raised maximum, which tells nothing"
  assert looks_written(taken: answered)
    == [[game_connection_support.look(slot: 1, display: 3842)]]
    as "the chest's display comes back on slot 1"
  assert properties_written(taken: answered) == [with_the_chest()]
    as "the values the player's own 0x262 listed at entry (player.level1_gear_properties)"
}

pub fn health_above_the_new_maximum_is_capped_and_told_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, answered) =
    saved_after(state: watched(), message: chest_unequipped())
  assert health_written(taken: answered) == [586]
    as "a player at full health, 736, is capped at the new maximum, 586, by the health path"
  assert list.contains(
    game_connection_support.news_broadcast(answered),
    unit_news.Health(health: 586, dead: False),
  )
    as "each viewer is told the capped health"
}

/// A 0x182 of the shield from worn slot 15 to inventory slot 0, inside 0x038C.
fn shield_unequipped() -> BitArray {
  game_connection_support.item_moved_message(
    from: item_place.ItemPlace(location: 0, bag_index: 15),
    to: item_place.ItemPlace(location: 1, bag_index: 0),
  )
}

/// A 0x182 of inventory slot 0 to the worn shield slot 15, inside 0x038C.
fn shield_equipped() -> BitArray {
  game_connection_support.item_moved_message(
    from: item_place.ItemPlace(location: 1, bag_index: 0),
    to: item_place.ItemPlace(location: 0, bag_index: 15),
  )
}

pub fn a_shield_put_back_below_its_maximum_starts_the_reboot_timer_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = saved_after(state: watched(), message: shield_unequipped())
  let #(_, answered) = saved_after(state:, message: shield_equipped())
  assert list.filter_map(support.effects_of(answered), fn(effect) {
      case effect {
        OwnEffect(StartTimer(timer:, after_ms:)) -> Ok(#(timer, after_ms))
        OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
          Error(Nil)
      }
    })
    == [#(TimerId(9), 5125)]
    as "player_life's rule for a shield below its maximum (shield_rebooted): the shield worn again is at 0 of 450, so ShieldRebootTime 5125 of the shield item starts its clock"
}

pub fn removing_the_shield_sets_stat_20_to_0_and_its_properties_to_the_defaults_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, answered) =
    saved_after(state: watched(), message: shield_unequipped())
  assert properties_written(taken: answered)
    == [
      [
        game_connection_support.property(id: 41, number: 0.0),
        game_connection_support.property(id: 175, number: 0.0),
        game_connection_support.property(id: 176, number: 0.25),
        game_connection_support.property(id: 178, number: 2500.0),
      ],
    ]
    as "UnitProperty2's defaultValue of ShieldCapacityMax 0, ShieldMitigationMax 0, ShieldRegenPct 0.25 and ShieldRebootTime 2500, where the shield's own 450, 0.625, 0.15 and 5125 were"
  assert list.map(
      game_connection_support.decoded(
        game_connection_support.written(answered),
        0x0938,
        unit_stat_changed.decode,
      ),
      fn(message) { message.change },
    )
    == [unit_stat_change.Shield(unit_stat_shield.UnitStatShield(value: 0))]
    as "opcode.0x938: the full shield of 450 is cut to the maximum 0, stat 20"
}

/// A 0x149 of the boots at worn slot 4, inside 0x038C.
fn boots_deleted() -> BitArray {
  let assert Ok(body) =
    item_delete.encode(
      item_delete.ItemDelete(place: item_place.ItemPlace(
        location: 0,
        bag_index: 4,
      )),
    )
  game_connection_support.world_message(
    message_id: item_delete.message_id,
    body:,
  )
}

pub fn deleting_a_worn_item_sends_0x148_then_0x933_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, answered) = saved_after(state: watched(), message: boots_deleted())
  assert list.take(game_connection_support.written_ids(answered), 3)
    == [0x0148, 0x0933, 0x093A]
    as "record B: the delete's 0x148, then the look, then the properties"
  assert looks_written(taken: answered)
    == [[game_connection_support.look(slot: 5, display: 0)]]
    as "opcode.0x933.empty_display: the boots' slot 5 is emptied"
  let assert [entries] = properties_written(taken: answered)
  assert list.map(entries, fn(entry) { entry.property_id }) == [7, 35, 42]
    as "the boots' Base Health, Assault Rating and Armor"
  assert list.filter(entries, fn(entry) { entry.property_id != 35 })
    == [
      game_connection_support.property(id: 7, number: 646.0),
      game_connection_support.property(id: 42, number: 212.5),
    ]
    as "the boots hold 0.75 of the five slot modifiers' 5.0: 90 of the 600 and 37.5 of the 250"
}

pub fn a_worn_item_move_the_store_has_not_answered_ends_the_connection_and_the_next_entry_builds_from_the_saved_items_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      chest_unequipped(),
    )
  let #(state, answered) =
    game_connection_support.answer(state:, taken:, outcome: NoAnswerInTime)
  assert game_connection_support.written_ids(answered) == []
    as "no 0x569, 0x933 or 0x93a: nothing says whether the chest moved, so the look and the properties stay as they are"
  let #(_, saved) =
    game_connection_support.answer(
      state:,
      taken: answered,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.disconnect(
      saved,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "the connection ends with 0x036A reason 8"
  // The store never saved the move, so the next entry holds the chest still.
  let character = game_connection_support.world_character()
  let #(_, entered) =
    world_entry_support.entry(tables: character_tables.shared(), character:)
  assert entered.gear.properties.armor == 250.0
    as "the next entry builds its gear from the items the store holds: the chest is worn, so the Engineer's armor is 250"
}

pub fn two_moves_of_worn_items_in_a_row_wait_behind_each_other_and_rebuild_the_gear_after_each_save_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first_ask) =
    game_connection_support.read(
      game_connection_support.in_world(),
      chest_unequipped(),
    )
  // The boots (worn slot 4) go to the second bag slot while the first move's ask is out.
  let #(state, held) = game_connection_support.read(state, boots_unequipped())
  assert support.writes(held) == [] && support.asked(held) == None
    as "step.EffectsThenAsk: the second move is held while the first's ask is out"
  let #(state, first_saved) =
    game_connection_support.answer(
      state:,
      taken: first_ask,
      outcome: step.Answer(FromStore(ForItems(ItemsSaved))),
    )
  assert game_connection_support.written_ids(first_saved)
    == [0x0569, 0x0933, 0x093A, 0x092F]
    as "the first save's answer goes out with the look, the properties and the capped health (736 to 586) of the gear without the chest only"
  assert properties_written(taken: first_saved)
    == [game_connection_support.without_the_chest()]
    as "the chest's three entries: the boots are still worn when the first is saved"
  assert support.asked(first_saved) != None
    as "the held second move is taken after the first's answer and asks the store"
  let #(_, second_saved) =
    game_connection_support.answer(
      state:,
      taken: first_saved,
      outcome: step.Answer(FromStore(ForItems(ItemsSaved))),
    )
  assert game_connection_support.written_ids(second_saved)
    == [0x0569, 0x0933, 0x093A, 0x092F]
    as "the second save's answer goes out with its own look, properties and capped health (586 to 496)"
  assert looks_written(taken: second_saved)
    == [[game_connection_support.look(slot: 5, display: 0)]]
    as "opcode.0x933.empty_display: the boots' slot 5 is emptied"
  let assert [entries] = properties_written(taken: second_saved)
  assert list.filter(entries, fn(entry) { entry.property_id != 35 })
    == [
      game_connection_support.property(id: 7, number: 496.0),
      game_connection_support.property(id: 42, number: 150.0),
    ]
    as "the gear after both moves: the chest's 150 and the boots' 90 off the 600 (736 less 240), and their 62.5 and 37.5 off the armor 250"
}

/// A 0x182 of the boots from worn slot 4 to inventory slot 1, inside 0x038C.
fn boots_unequipped() -> BitArray {
  game_connection_support.item_moved_message(
    from: item_place.ItemPlace(location: 0, bag_index: 4),
    to: item_place.ItemPlace(location: 1, bag_index: 1),
  )
}

/// Item2 27106 is a level-scaled heavy armor chest (flags bit 3, Item2Category 3 as the
/// Engineer's own chest) whose power level is 1: a level 5 player (4320 experience,
/// XpPerLevel.minXpForLevel) with the Novice set but no chest, holding it in inventory
/// slot 0, equips it, and the 0x93a gives its properties at level 5, not at its power level:
/// Base Health CreatureLevel row 5's 735.861 with the set's 450 and the armor's 375,
/// rounded: 1561; property 34 is 115.625; the Assault Rating 22.5 over the set's 194.0625
/// and the Armor 156.25 over its 187.5: the armor's values are the emulator run
/// `scaled_fill.py 27106 5 5 0 0 0 0 0 0` (FillItemInfo 0x1404445d0, then
/// BuildItemProperties 0x14040c310 with the scaling words 0 and 1 set to 5): 34 = 115.625,
/// Assault Rating 22.5, Armor 156.25, Base Health 375.0.
pub fn equipping_a_level_scaled_item_gives_it_at_the_players_level_test() -> Nil {
  use <- owned_test.run(10_000)
  let character =
    store.Character(..game_connection_support.world_character(), level: 5)
  let worn =
    list.filter(world_entry_support.novice_items(character:), fn(item) {
      item.bag_index != 0
    })
  let state =
    game_connection_support.entered_with_items(
      character:,
      saved_experience: Some(4320),
      items: list.append(worn, [
        HeldItem(
          item_guid: 9,
          item2_id: Item2Id(fixture_tables.root(table: "Item2", id: 27_106)),
          location: 1,
          bag_index: 0,
          stack_count: 1,
          words: store.ItemWords(
            random_stats: 0,
            charges: 0,
            item_flags: 0,
            expires_at_unix_ms: None,
          ),
        ),
      ]),
    )
  let #(state, taken) = game_connection_support.read(state, chest_equipped())
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForItems(ItemsSaved))),
    )
  assert game_connection_support.written_ids(answered)
    == [0x0569, 0x0567, 0x0933, 0x093A]
    as "the move's frame, the binding (Item2 27106 binds on equip, bindFlags 16), the look with the chest shown, and the properties the chest gives"
  assert properties_written(taken: answered)
    == [
      [
        game_connection_support.property(id: 7, number: 1561.0),
        game_connection_support.property(id: 34, number: 115.625),
        game_connection_support.property(id: 35, number: 216.5625),
        game_connection_support.property(id: 42, number: 343.75),
      ],
    ]
    as "the chest's properties at level 5, over the worn Novice set without a chest"
}

/// A 0x182 of the spare chest piece in inventory slot 0 onto the worn chest slot, as the client
/// sends it, inside 0x038C.
fn spare_chest_equipped() -> BitArray {
  game_connection_support.item_moved_message(
    from: item_place.ItemPlace(location: 1, bag_index: 0),
    to: item_place.ItemPlace(location: 0, bag_index: 0),
  )
}

/// An equip the store does not save binds nothing: the answer `ItemsNotSaved` or
/// `SaveRefused` is the 0x56A with the client's code 5 (DbFailure) and no 0x567, and the items
/// stay as held, so the same equip asks the same bits again (`inventory.answered`).
pub fn a_move_the_store_refuses_binds_nothing_and_sends_no_0x567_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- item_flags_support.with_bind_flags(
    item2_id: item_flags_support.chest(),
    bind_flags: item_flags_support.bind_on_equip,
    flags: None,
  )
  let spare =
    item_flags_support.held_with(
      guid: 9,
      item2: item_flags_support.chest(),
      location: 1,
      bag_index: 0,
      item_flags: 0,
    )
  let #(state, _) =
    game_connection_support.entered_with_quests_and_items_on(
      tables:,
      quests: [],
      items: [spare],
    )
  let #(_, first) = game_connection_support.read(state, spare_chest_equipped())
  let asked = game_connection_support.ask_request(first)
  assert asked
    == AskStore(
      Items(
        MoveItems(
          account_id: AccountId(7),
          character_id: CharacterId(42),
          session_epoch: character_support.epoch(1),
          moves: [
            ItemMove(
              item_guid: 9,
              from: ItemPlace(location: 1, bag_index: 0),
              to: ItemPlace(location: 0, bag_index: 0),
              flags_set: 1,
            ),
            ItemMove(
              item_guid: 1,
              from: ItemPlace(location: 0, bag_index: 0),
              to: ItemPlace(location: 1, bag_index: 0),
              flags_set: 0,
            ),
          ],
        ),
      ),
    )
    as "the incoming item binds (bit 0) and the displaced one sets nothing"
  list.each([ItemsNotSaved, SaveRefused(constraint: "a_check")], fn(answer) {
    let #(state, taken) =
      game_connection_support.read(state, spare_chest_equipped())
    assert game_connection_support.ask_request(taken) == asked
      as "the equip asks for the bit on the swap's incoming item"
    let #(state, answered) =
      game_connection_support.answer(
        state:,
        taken:,
        outcome: step.Answer(FromStore(ForItems(answer))),
      )
    assert game_connection_support.written_ids(answered) == [0x056A]
      as "opcode.0x56a only: no 0x569, 0x568 or 0x567"
    let assert [failure] = game_connection_support.written(answered)
    assert item_action_failed.decode(failure.body)
      == Ok(ItemActionFailed(unread_1: 9, code: 5))
      as "the client's code 5, DbFailure, for the item moved"
    let #(_, again) =
      game_connection_support.read(state, spare_chest_equipped())
    assert game_connection_support.ask_request(again) == asked
      as "the item is as it was held: the same equip asks the same bits"
  })
}

/// The tests' Engineer in the world on these tables, wearing the Novice set but its item of
/// `worn_slot` and holding `item2_id` in inventory slot 0.
fn holding_the_item(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
  worn_slot worn_slot: Int,
) -> game_connection.State {
  let character = game_connection_support.world_character()
  let fresh =
    game_connection_support.accepted(
      Settings(..game_connection_support.settings(), tables:),
    ).0
  let #(state, taken) =
    game_connection_support.joining_holding_items(
      in_character_select: game_connection_support.in_select_from(fresh),
      character:,
      saved_health: None,
      saved_experience: None,
      quests: [],
      items: list.append(
        list.filter(world_entry_support.novice_items(character:), fn(item) {
          item.bag_index != worn_slot
        }),
        [
          worn_item_support.held(
            item2_id:,
            item_guid: 50,
            location: 1,
            bag_index: 0,
          ),
        ],
      ),
    )
  game_connection_support.answer(
    state:,
    taken:,
    outcome: step.Answer(FromMap(game_connection_support.map_answer(taken))),
  ).0
}

/// A 0x182 of the item between inventory slot 0 and its worn slot.
fn item_moved(
  from from: item_place.ItemPlace,
  to to: item_place.ItemPlace,
) -> BitArray {
  game_connection_support.item_moved_message(from:, to:)
}

/// The cast id of each 0x7ff among the frames, in order.
fn cast_ids_started(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == spell_started.message_id {
      True -> {
        let assert Ok(start) = spell_started.decode(frame.body)
          as "a spell_started decodes"
        Ok(start.cast_id)
      }
      False -> Error(Nil)
    }
  })
}

/// A worn item with an equip spell: the item and the slot it is worn in, the spell, whether
/// the item's level (Item2.powerLevel), whether the spell holds property modifiers, and the frames, as message ids, that come before the
/// standing frames in an equip and in an unequip. Both start with the move's 0x569 and the
/// gear's 0x93a, and a drawn item adds the look's 0x933. An equip then starts the cast, 0x7ff
/// and its go 0x7f4, and an unequip ends it, 0x7fe; a spell that holds property modifiers
/// writes 0x93a frames of its own, after the go at the start and before the 0x7fe at the end.
type WornCase {
  WornCase(
    name: String,
    item2_id: Int,
    worn_slot: Int,
    spell4_id: Int,
    item_level: Int,
    holds_modifiers: Bool,
    equip_gear_ids: List(Int),
    unequip_gear_ids: List(Int),
  )
}

fn deflector_cases() -> List(WornCase) {
  [
    WornCase(
      "a spell with a Proc row only (the deflector's 82325)",
      worn_item_support.deflector,
      15,
      worn_item_support.deflector_spell,
      5,
      False,
      [0x0569, 0x093A],
      [0x0569, 0x093A],
    ),
    WornCase(
      "a spell whose root holds UnitPropertyModifier rows (Item2 38020's 62538, a weapon with a look)",
      38_020,
      16,
      62_538,
      50,
      True,
      [0x0569, 0x0933, 0x093A],
      [0x0569, 0x0933, 0x093A],
    ),
  ]
}

/// The ids after `before` and before `after`, or nothing when they do not start and end so.
fn ids_between(
  ids ids: List(Int),
  before before: List(Int),
  after after: List(Int),
) -> Result(List(Int), Nil) {
  use <- bool.guard(
    when: list.take(ids, list.length(before)) != before,
    return: Error(Nil),
  )
  let rest = list.drop(ids, list.length(before))
  let kept = list.length(rest) - list.length(after)
  use <- bool.guard(
    when: kept < 0 || list.drop(rest, kept) != after,
    return: Error(Nil),
  )
  Ok(list.take(rest, kept))
}

pub fn equipping_an_item_with_an_equip_spell_writes_its_0x7ff_after_the_gear_frames_and_unequipping_it_writes_its_0x7fe_after_them_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  list.each(deflector_cases(), fn(case_) {
    let name = case_.name
    let slot = item_place.ItemPlace(location: 0, bag_index: case_.worn_slot)
    let bag = item_place.ItemPlace(location: 1, bag_index: 0)
    let #(state, equipped) =
      saved_after(
        state: holding_the_item(
          tables:,
          item2_id: case_.item2_id,
          worn_slot: case_.worn_slot,
        ),
        message: item_moved(from: bag, to: slot),
      )
    let modifier_frames_are_only_0x93a = fn(frames: Result(List(Int), Nil)) {
      case frames {
        Ok(ids) ->
          list.all(ids, fn(id) { id == 0x093A })
          && { ids != [] } == case_.holds_modifiers
        Error(Nil) -> False
      }
    }
    assert modifier_frames_are_only_0x93a(
      ids_between(
        ids: game_connection_support.written_ids(equipped),
        before: list.append(case_.equip_gear_ids, [0x07FF, 0x07F4]),
        after: [],
      ),
    )
      as {
        name
        <> ": the move's frame and the gear's properties come first (the equip is legal at level 1), then the standing frames: the equip spell's 0x7ff and go (the server's order: no client fact needs the other, so it is `regeared`'s), then the modifiers' 0x93a frames when the spell holds any"
      }
    assert game_connection_support.started_spells(
        frames: game_connection_support.written(equipped),
      )
      == [case_.spell4_id]
      as { name <> ": the equip spell is the one cast the equip starts" }
    assert game_connection_support.started_item_levels(
        frames: game_connection_support.written(equipped),
      )
      == [#(case_.spell4_id, case_.item_level)]
      as {
        name
        <> ": opcode.0x7ff.caster_item_level: its 0x7ff tells the worn item's level, Item2.powerLevel"
      }
    let #(state, unequipped) =
      saved_after(state:, message: item_moved(from: slot, to: bag))
    assert modifier_frames_are_only_0x93a(
      ids_between(
        ids: game_connection_support.written_ids(unequipped),
        before: case_.unequip_gear_ids,
        after: [0x07FE],
      ),
    )
      as {
        name
        <> ": an unequip writes the move's frame and the gear's properties first, then the modifiers' 0x93a frames when the spell held any and the 0x7fe of the equip spell's cast"
      }
    let #(_, again) =
      saved_after(state:, message: item_moved(from: bag, to: slot))
    let first_cast =
      cast_ids_started(frames: game_connection_support.written(equipped))
    assert cast_ids_started(frames: game_connection_support.written(again))
      != first_cast
      as { name <> ": a second equip starts a new cast" }
  })
}

/// Item2 61522, an ArmorGadget (ItemSlot 46, worn slot 11): its ItemSpecial 9565 names the
/// equip spell 83570 and the use spell 83572. Its `maxCharges` is 0, as every one of the six
/// worn items that hold both a use spell and an equip spell (61522, 61712, 61720, 61723,
/// 61728, 90288) has, so no row spends a charge of a worn item and the spend path of
/// `regeared` has no real row to run on.
const gadget = 61_522

/// A sale takes the worn item out of the held items and calls `inventory.regeared` as an
/// unequip does, so the equip spell ends with its 0x7fe after the sale's own frames, the
/// look and the properties.
pub fn selling_a_worn_item_ends_its_equip_spell_through_the_same_function_as_an_unequip_test() -> Nil {
  use <- owned_test.run(60_000)
  let words =
    store.ItemWords(
      random_stats: 0,
      charges: 0,
      item_flags: 0,
      expires_at_unix_ms: None,
    )
  let worn =
    worn_item_support.held(
      item2_id: gadget,
      item_guid: 60,
      location: 0,
      bag_index: 11,
    )
  let state =
    vendor_support.at_the_vendor(
      state: game_connection_support.in_world_stocking_holding(
        vendors: vendor_support.stocking(creature_ids: [74_812]),
        credits: 100,
        items: [worn],
      ),
    )
  let #(state, taken) =
    game_connection_support.sale_requested(
      state:,
      place: item_place.ItemPlace(location: 0, bag_index: 11),
      quantity: 1,
    )
  let assert AskStore(Items(store.SellToVendor(after:, ..))) =
    game_connection_support.ask_request(taken)
    as "the sale of the worn gadget asks the store"
  let #(_, sold) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForItems(
            store.Sold(amount: after, words: [
              store.SoldWord(item_guid: 60, words:),
            ]),
          ),
        ),
      ),
    )
  let ids = game_connection_support.written_ids(sold)
  assert list.take(ids, 3) == [0x0919, 0x00DD, 0x0148]
    as "the sale's own frames come first: the credits, the gain, the item's removal"
  assert list.last(ids) == Ok(0x07FE)
    as "the equip spell's cast ends with its 0x7fe, after the sale's frames and the gear's"
  assert list.count(ids, fn(id) { id == 0x07FE }) == 1
    as "once, for the one standing cast the gadget put on the player"
}
