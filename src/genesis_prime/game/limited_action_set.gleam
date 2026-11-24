//// The ability builder's save: the client's 0xB1 holds the twelve Spell4Base ids of the
//// action set's slots and the tier edits of the tier pips, which the client sends without
//// checking that a slot is open, that the player holds the ability, that an id appears once,
//// that a tier exists or that the points cover it. The rule judges it and answers with the bar
//// and the tiers the player has, which is the only way the client's bar and book tiers change.
//// The client's name for the builder's set is "limited action set" (`ActionSetLib`); a feature
//// of the game connection's rule (genesis_prime/game/connection) taken from inside 0x038C
//// with the player in the world.
////
//// ```
//// load: ActionSlotPrereq rows + their Prerequisite rows ─▶ Unlocks (slot ─▶ the levels it opens at)
//// load: Spell4 + Spell4TierRequirements ─▶ SpellTiers (genesis_prime/game/spell_tier)
//// 0xB1 {12 ids, set, tier changes, AMP ids} ─▶ take(unlocks, tiers, player, saved, class_bar, body)
////      a body the client's reader refuses ─▶ Refusal: the connection ends
////      every check passes  ─▶ Saved' and 0x019D (the 12 shortcuts, result 1), 0x01A0 (the book's tiers
////                             in set 0), 0x0169 (the points left), 0x00B2 (bit 1)
////      a check fails       ─▶ Saved as it was, 0x019D (the held bar, the result), 0x00B2 (bit 0), a warning
//// place save ─▶ rows(saved) ─▶ the store's slot rows, 12 for each saved set, and tier rows
//// entry      ─▶ entering(unlocks, tiers, points_total, level, book, rows) ─▶ Saved, or a RowError
////               that ends the entry
//// ```
////
//// - **The client checks little before it sends** (`0x1407580e0`): the player exists, the
////   list holds 12 numbers, no Update Action Set cast runs, the player is not dead or in
////   combat or in a PvP restriction, and each large slot's tier 1 spell is a Class -
////   Ability one (`0x1404aacb0`). It never checks that a slot is open, that an ability is
////   held or active, of the player's class, or that an id appears once: the rule refuses those.
//// - **The checks, in order**, each with the result the client names it by
////   (`lua.ActionSetLib.CodeEnumLimitedActionSetResult`): not 12 ids 25, a dead player 27, a
////   player in combat 30, a set other than the active one 40, then slot by slot: an id in
////   slot 8 or later 18, an id in a slot not open at the player's level 2, an id the book
////   does not hold 18, and last an id twice 13. The client makes 25, 27 and 30 itself and never
////   sends them, in that order (`0x1407580e0`); 2, 13, 18 and 40 are the server's mapping,
////   since the client names the checks and does not make them, and the order of 40, 18, 2 and
////   13 is the server's own choice too. The code the server picks is invisible to the
////   player: the client shows a text only for result 39.
//// - **The tier checks** come after the bar's, one tier change at a time in the save's order,
////   then the points: an ability the book does not hold 18, an ability twice 13, a tier the
////   ability has no row for or the player's level does not reach 41, and tiers costing more
////   than the level's points 42 (`lua.ActionSetLib.CodeEnumLimitedActionSetResult`; the order and
////   the mapping are the server's, since the stock client stops below a tier it cannot take,
////   `0x140748390`). A fall is allowed to any tier that has a row (the client takes a lower
////   tier whatever its row, and no real base lacks a row below its highest), a change to the
////   held tier changes nothing, and the points are judged on the tiers the save leaves. Any refusal refuses the whole save, bar
////   included. A tier belongs to the ability in the set, so a save that takes an ability off the
////   bar keeps its tier. What a tier costs and needs is genesis_prime/game/spell_tier.
//// - **The tiers are saved** with the place, as the bars are: `rows` carries a row for each
////   ability held above tier 1 in each set, whole, so a tier returned to 1 is no row and the
////   store deletes the stored one. A map change, a Holocrypt rejoin and a login take them
////   back through `entering`.
//// - **A saved tier is kept at entry** only while the book holds its ability, the Spell4 rows
////   hold that tier and the level reaches it; a set whose kept tiers cost more than the level's
////   points has every tier reset to tier 1 and its points refunded (the server's choice, since the
////   client never reads a stored tier), so a table change or a lower level cannot show a tier the
////   player cannot hold or spend below 0 points. A row outside the table's checks (a
////   set above 3, an ability of 0 or beyond 18 bits, a tier outside 2 to 15, a second row for
////   one ability of one set) is a `RowError`.
//// - **A slot opens** by the client's own reading of its ActionSlotPrereq row's Prerequisite
////   row (`ActionSlotPrereq.prerequisiteIdUnlock`): the conditions the client keeps are all
////   of type 177 (the unit's level) and each holds at the player's level
////   (`Prerequisite.prerequisiteTypeId.177`).
//// - **The book** is what the player holds: the bag and the alternates the plans add
////   (genesis_prime/game/ability_book `book`). The gadget and path slots (8 and 9) hold none, so an id there is refused with 18 although the
////   client calls it InvalidSlot 24 (`0x1404aacb0`).
//// - **The answer** is the active set (0) and the held bar of twelve shortcuts, an empty slot
////   as type 0 so the client clears it; for an accepted save then 0x01A0 with every ability of
////   the book in set 0 at its held tier, and 0x0169 with the points left (the client keeps both
////   and clears its own edits with the 0xB2 after them, `opcode.0x169`, `opcode.0xb2`); last 0xB2,
////   whose bit is 1 for an accepted save and 0 for a refused one. The bit is a guess: the client
////   only adds a combat log line for it. A refused save is answered with the held bar and the
////   0xB2 only, since the client then reads the book's tiers and the last 0x0169 again.
//// - **A saved bar is kept at entry** only for the slots still open at the player's level
////   and the abilities the book still holds, the same two tests a save passes, so a table
////   change or a lower level cannot show an ability the player does not hold; a slot it drops
////   is empty and the next save writes it so. A set with rows is saved, even when all twelve
////   are empty, and a set with none shows the class's bar. A row outside the table's checks
////   (set 0 to 3, slot 0 to 11, ability of 18 bits, one row for a slot) is a `RowError`.
//// - **The load fails** for an ActionSlotPrereq row with a slot index outside 0 to 11, a slot with
////   no row or two, and a row whose Prerequisite row is missing, which includes the prerequisite
////   id 0 that the client reads as "always open" (`0x140758020`): no row holds it.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/ability_book_frame
import genesis_prime/game/ability_points
import genesis_prime/game/prerequisite.{type Relation}
import genesis_prime/game/spell_tier
import genesis_prime/gap
import genesis_prime/message/action_set_save
import genesis_prime/step.{type LogLevel, LogDebug, LogWarning}
import genesis_prime/store.{
  type AbilityTierRow, type ActionSets, type ActionSlotRow, AbilityTierRow,
  ActionSets, ActionSlotRow,
}
import genesis_prime/table/action_slot_prereq
import genesis_prime/table/id.{type Spell4BaseId, PrerequisiteId, Spell4BaseId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// How many slots a bar holds: the client's list of ids is exactly this long
/// (`0x1407580e0`).
const slots_in_a_bar = 12

/// The slots that hold abilities of the book: the eight large slots. Slots 8 and 9 are the
/// gadget and the path ability; 10 and 11 are never filled (`opcode.0xb1`).
const ability_slots = 8

/// The action sets there are (`AbilityBook.CodeEnumSpecConstant`, MaxNumSpecs).
const action_sets = 4

/// The largest Spell4Base id the 18 bits of the ability messages carry (`opcode.0x1a0`).
const largest_ability_id = 262_143

/// The largest tier the 4 bits of the ability book's message carry (`opcode.0x1a0`).
const largest_tier = 15

/// The bar of an action set: twelve slots, slot 0 first, each an ability or empty. Built by
/// `take`, `bar_of` or `entering`, read by `slots`.
pub opaque type Bar {
  Bar(slots: List(Option(Spell4BaseId)))
}

/// The slots of a bar, slot 0 first.
pub fn slots(bar bar: Bar) -> List(Option(Spell4BaseId)) {
  bar.slots
}

/// Which action set: 0 to 3 (`AbilityBook.CodeEnumSpecConstant`).
pub opaque type SetIndex {
  SetIndex(number: Int)
}

/// The set index of a number, or `Error(Nil)` for a number above 3.
fn set_index(number number: Int) -> Result(SetIndex, Nil) {
  use <- bool.guard(
    when: number < 0 || number >= action_sets,
    return: Error(Nil),
  )
  Ok(SetIndex(number:))
}

/// The set a connection starts with and the one the client treats as active until a message
/// changes it (`opcode.0x19d`): the only set the server judges a save for.
pub fn first_set() -> SetIndex {
  SetIndex(number: 0)
}

/// The number of a set, as the client's messages carry it.
pub fn set_number(set set: SetIndex) -> Int {
  set.number
}

/// The bars the player has saved, by set, and the tiers above tier 1 the player holds, by set
/// and ability. A set with no entry has the class's bar, and an ability with no entry is at
/// tier 1.
pub opaque type Saved {
  Saved(bars: Dict(Int, Bar), tiers: Dict(Int, Dict(Spell4BaseId, Int)))
}

/// A player who has saved no bar and holds no tier above 1.
pub fn none() -> Saved {
  Saved(bars: dict.new(), tiers: dict.new())
}

/// The tier an ability is at in a set: 1 unless the player raised it.
fn tier_of(saved saved: Saved, set set: Int, base base: Spell4BaseId) -> Int {
  dict.get(saved.tiers, set)
  |> result.try(dict.get(_, base))
  |> result.unwrap(1)
}

/// The tier the book shows for an ability in a set (the 0x01A0 of the entry and of a save): the
/// tier the player holds, except for an alternate, which shows the tier of the ability of the book
/// that names it (`spell_tier.alternate_of`), 1 when that ability holds none. The client's surged
/// press reads the alternate's own book entry (`0x1405e7e50`, `0x140565090`) and the server
/// casts the alternate inside the held tier's plan (genesis_prime/game/held_tier), so the two
/// agree only when the alternate shows its ability's tier. The alternate's own saved tier
/// never counts. The reverse lookup is one-to-one only by the data (genesis_prime/game/spell_tier).
pub fn book_tier_of(
  tiers tiers: spell_tier.SpellTiers,
  saved saved: Saved,
  set set: Int,
  book book: List(Spell4BaseId),
  base base: Spell4BaseId,
) -> Int {
  case naming_ability(tiers:, book:, base:) {
    Ok(ability) -> tier_of(saved:, set:, base: ability)
    Error(Nil) -> tier_of(saved:, set:, base:)
  }
}

/// The ability of the book that names this base as its alternate, or `Error(Nil)` for a base
/// that is no alternate of the book.
fn naming_ability(
  tiers tiers: spell_tier.SpellTiers,
  book book: List(Spell4BaseId),
  base base: Spell4BaseId,
) -> Result(Spell4BaseId, Nil) {
  list.find(book, fn(ability) {
    spell_tier.alternate_of(tiers:, base: ability) == Ok(base)
  })
}

/// The abilities of a set held above tier 1 with their tiers, in Spell4Base order.
pub fn held_tiers(
  saved saved: Saved,
  set set: Int,
) -> List(#(Spell4BaseId, Int)) {
  dict.get(saved.tiers, set)
  |> result.map(dict.to_list)
  |> result.unwrap([])
  |> list.sort(fn(a, b) { int.compare({ a.0 }.value, { b.0 }.value) })
}

/// The points the player's set 0 tiers cost: the sum of what each held tier costs from tier 1.
pub fn points_spent(
  tiers tiers: spell_tier.SpellTiers,
  saved saved: Saved,
) -> Int {
  spell_tier.spent(tiers:, held: held_tiers(saved:, set: first_set().number))
}

/// The bar the player has in a set: the saved one, or the class's level-1 abilities in
/// slots 0 to 2 with the rest empty when none is saved.
pub fn bar_of(
  saved saved: Saved,
  set set: SetIndex,
  class_bar class_bar: List(Spell4BaseId),
) -> Bar {
  case dict.get(saved.bars, set.number) {
    Ok(bar) -> bar
    Error(Nil) ->
      Bar(slots: list.append(
        list.map(class_bar, Some),
        list.repeat(None, slots_in_a_bar - list.length(class_bar)),
      ))
  }
}

/// A saved row the table's checks cannot hold, which the load never gives.
pub type RowError {
  /// A row whose set, slot or ability is outside the table's checks.
  RowOutsideTable(row: ActionSlotRow)
  /// Two rows for one slot of one set.
  RowRepeated(row: ActionSlotRow)
  /// A tier row whose set, ability or tier is outside the table's checks.
  TierRowOutsideTable(row: AbilityTierRow)
  /// Two tier rows for one ability of one set.
  TierRowRepeated(row: AbilityTierRow)
}

/// The rows a player's saved bars and tiers are written as: twelve slot rows for each saved
/// set, in set then slot order, an empty slot with no ability; and a tier row for each ability
/// held above tier 1 in each set, in set then Spell4Base order. None when nothing is saved.
/// Every save of the place carries the whole of it: the store deletes the tier rows a save
/// leaves out.
pub fn rows(saved saved: Saved) -> ActionSets {
  ActionSets(
    slots: dict.to_list(saved.bars)
      |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
      |> list.flat_map(fn(saved_set) {
        let #(action_set, bar) = saved_set
        list.index_map(bar.slots, fn(slot_held, slot) {
          ActionSlotRow(
            action_set:,
            slot:,
            spell4_base_id: option.map(slot_held, fn(base) { base.value }),
          )
        })
      }),
    tiers: dict.keys(saved.tiers)
      |> list.sort(int.compare)
      |> list.flat_map(fn(action_set) {
        list.map(held_tiers(saved:, set: action_set), fn(held) {
          AbilityTierRow(
            action_set:,
            spell4_base_id: { held.0 }.value,
            tier: held.1,
          )
        })
      }),
  )
}

/// The bars a player has from the rows the store loaded, judged as at entry: a saved
/// ability stays in its slot only while the player's book still holds it and the slot is
/// open at the player's level, and any other slot is empty (the next save writes it so).
/// A set with rows is saved, even when every slot of it is empty, and a slot with no row in
/// a saved set is empty. `Error` for a row the table's checks cannot hold.
///
/// A saved tier stays only while the player's book holds its ability, the Spell4 rows hold
/// that tier of it, the player's level reaches the tier (`Spell4TierRequirements`) and the
/// points the level gives cover it; any other is dropped and the next save deletes its row.
/// Judging is for each set on its own. For a set whose tiers, once those are dropped, cost
/// more points than the level gives (only a changed table or an edited database can make it),
/// the server chooses to reset every tier of the set to tier 1 and refund all its points, so
/// the player chooses again; the client never reads a stored tier. The entry's points left are never below 0 and every tier it
/// holds has a cost, which `ability_points.points_frame` and `spell_tier.spent` need.
pub fn entering(
  unlocks unlocks: Unlocks,
  tiers tiers: spell_tier.SpellTiers,
  points_total points_total: Int,
  level level: Int,
  book book: List(Spell4BaseId),
  rows rows: ActionSets,
) -> Result(Saved, RowError) {
  use sets <- result.try(sets_of(rows: rows.slots))
  use stored <- result.map(tier_sets_of(rows: rows.tiers))
  let open = open_slots(unlocks:, level:)
  Saved(
    bars: dict.map_values(sets, fn(_, slot_ids) {
      Bar(
        slots: list.repeat(Nil, slots_in_a_bar)
        |> list.index_map(fn(_, slot) {
          case dict.get(slot_ids, slot) {
            Ok(Some(id)) ->
              case
                list.contains(open, slot),
                list.contains(book, Spell4BaseId(id))
              {
                True, True -> Some(Spell4BaseId(id))
                _, _ -> None
              }
            _ -> None
          }
        }),
      )
    }),
    tiers: dict.map_values(stored, fn(_, held) {
      tiers_kept(held:, tiers:, points_total:, level:, book:)
    })
      |> dict.filter(fn(_, held) { !dict.is_empty(held) }),
  )
}

/// The tiers of one set the entry keeps: those the book, the Spell4 rows and the level allow,
/// or none when their cost is over the points the level gives (the server's choice: refund
/// and let the player choose again).
fn tiers_kept(
  held held: Dict(Spell4BaseId, Int),
  tiers tiers: spell_tier.SpellTiers,
  points_total points_total: Int,
  level level: Int,
  book book: List(Spell4BaseId),
) -> Dict(Spell4BaseId, Int) {
  let allowed =
    dict.to_list(held)
    |> list.filter(fn(entry) {
      let #(base, tier) = entry
      list.contains(book, base)
      && result.is_ok(spell_tier.change_cost(tiers:, base:, from: 1, to: tier))
      && case spell_tier.level_needed(tiers:, tier:) {
        Ok(needed) -> level >= needed
        Error(Nil) -> False
      }
    })
  case spell_tier.spent(tiers:, held: allowed) > points_total {
    True -> dict.new()
    False -> dict.from_list(allowed)
  }
}

/// The tier rows of each set by ability, or the first row the table's checks cannot hold: a
/// set above 3, an ability of 0 or beyond 18 bits, a tier outside 2 to 15 (the 4 bits of the
/// ability book's message, `opcode.0x1a0`) or a second row for one ability of one set.
fn tier_sets_of(
  rows rows: List(AbilityTierRow),
) -> Result(Dict(Int, Dict(Spell4BaseId, Int)), RowError) {
  list.try_fold(rows, dict.new(), fn(sets, row) {
    use <- bool.guard(
      when: row.action_set < 0
        || row.action_set >= action_sets
        || row.spell4_base_id < 1
        || row.spell4_base_id > largest_ability_id
        || row.tier < 2
        || row.tier > largest_tier,
      return: Error(TierRowOutsideTable(row:)),
    )
    let base = Spell4BaseId(row.spell4_base_id)
    let held = result.unwrap(dict.get(sets, row.action_set), dict.new())
    use <- bool.guard(
      when: dict.has_key(held, base),
      return: Error(TierRowRepeated(row:)),
    )
    Ok(dict.insert(sets, row.action_set, dict.insert(held, base, row.tier)))
  })
}

/// The rows of each set by slot, or the first row the table's checks cannot hold.
fn sets_of(
  rows rows: List(ActionSlotRow),
) -> Result(Dict(Int, Dict(Int, Option(Int))), RowError) {
  list.try_fold(rows, dict.new(), fn(sets, row) {
    use <- bool.guard(
      when: row.action_set < 0
        || row.action_set >= action_sets
        || row.slot < 0
        || row.slot >= slots_in_a_bar
        || !fits_the_message(ability: row.spell4_base_id),
      return: Error(RowOutsideTable(row:)),
    )
    let held = result.unwrap(dict.get(sets, row.action_set), dict.new())
    use <- bool.guard(
      when: dict.has_key(held, row.slot),
      return: Error(RowRepeated(row:)),
    )
    Ok(dict.insert(
      sets,
      row.action_set,
      dict.insert(held, row.slot, row.spell4_base_id),
    ))
  })
}

/// Whether a saved ability is none or an id the 18 bits of the message carry
/// (`opcode.0x1a0`), which the table's check holds.
fn fits_the_message(ability ability: Option(Int)) -> Bool {
  case ability {
    None -> True
    Some(id) -> id >= 1 && id <= largest_ability_id
  }
}

/// A sentence that says which row the load gave that the table's checks cannot hold.
pub fn describe_row(error error: RowError) -> String {
  case error {
    RowOutsideTable(row:) ->
      describe_slot(row:) <> " is outside what the table allows"
    RowRepeated(row:) -> describe_slot(row:) <> " is there twice"
    TierRowOutsideTable(row:) ->
      describe_tier(row:) <> " is outside what the table allows"
    TierRowRepeated(row:) -> describe_tier(row:) <> " is there twice"
  }
}

fn describe_slot(row row: ActionSlotRow) -> String {
  "the saved action slot row of set "
  <> int.to_string(row.action_set)
  <> " slot "
  <> int.to_string(row.slot)
}

fn describe_tier(row row: AbilityTierRow) -> String {
  "the saved ability tier row of set "
  <> int.to_string(row.action_set)
  <> " ability "
  <> int.to_string(row.spell4_base_id)
}

/// What the slots of a bar open at, one for each of the twelve.
pub opaque type Unlocks {
  Unlocks(slots: List(Opening))
}

/// When a slot opens: while every condition holds at the player's level, or never.
type Opening {
  /// Every condition's relation to the level and its value.
  OpensWhen(conditions: List(#(Relation, Int)))
  /// A row the rule does not read: its conditions are not all of type 177, or any one is
  /// enough.
  NeverOpens
}

const unlocks_key: table_store.DerivedKey(Unlocks) =
  table_store.DerivedKey("ActionSlotUnlocks")

/// Why the unlocks cannot be built from the tables.
type BuildError {
  /// An ActionSlotPrereq row names a slot the bar does not have.
  NoSuchSlot(row_id: Int, slot_index: Int)
  /// Two ActionSlotPrereq rows name the same slot.
  SlotRepeated(slot_index: Int)
  /// No ActionSlotPrereq row names the slot.
  NoSlotRow(slot_index: Int)
  /// The row's prerequisite is not a Prerequisite row.
  NoPrerequisite(slot_index: Int, prerequisite_id: Int)
}

/// The unlocks as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`).
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: unlocks_key, build: fn(tables) {
    build(tables:) |> result.map_error(describe_build)
  })
}

/// The unlocks the tables' load built.
pub fn unlocks(tables tables: table_store.Tables) -> Unlocks {
  table_store.derived(tables:, key: unlocks_key)
}

fn build(tables tables: table_store.Tables) -> Result(Unlocks, BuildError) {
  use by_slot <- result.try(
    list.try_fold(action_slot_prereq.all(tables), dict.new(), fn(by_slot, row) {
      case row.slot_index >= 0 && row.slot_index < slots_in_a_bar {
        False -> Error(NoSuchSlot(row_id: row.id, slot_index: row.slot_index))
        True ->
          case dict.has_key(by_slot, row.slot_index) {
            True -> Error(SlotRepeated(slot_index: row.slot_index))
            False -> Ok(dict.insert(by_slot, row.slot_index, row))
          }
      }
    }),
  )
  list.repeat(Nil, slots_in_a_bar)
  |> list.index_map(fn(_, slot_index) { slot_index })
  |> list.try_map(fn(slot_index) {
    use row <- result.try(
      dict.get(by_slot, slot_index)
      |> result.replace_error(NoSlotRow(slot_index:)),
    )
    let prerequisite_id = row.prerequisite_id_unlock
    prerequisite_table.get(tables:, id: PrerequisiteId(prerequisite_id))
    |> result.replace_error(NoPrerequisite(slot_index:, prerequisite_id:))
    |> result.map(opening_of)
  })
  |> result.map(fn(openings) { Unlocks(slots: openings) })
}

/// A slot's opening from its Prerequisite row, as the client keeps it: the conditions
/// before the first of type 0, all of type 177 (the unit's level, compared by the
/// condition's own relation), none of them optional.
fn opening_of(row row: prerequisite_table.Prerequisite) -> Opening {
  let kept = prerequisite.kept_conditions(row:)
  let level_type = 177
  case
    kept != []
    && !prerequisite.is_any(row:)
    && list.all(kept, fn(condition) { condition.0 == level_type })
  {
    True ->
      OpensWhen(
        conditions: list.map(kept, fn(condition) {
          let #(_, comparison, _, value) = condition
          #(prerequisite.relation_of(code: comparison), value)
        }),
      )
    False -> NeverOpens
  }
}

fn describe_build(error error: BuildError) -> String {
  case error {
    NoSuchSlot(row_id:, slot_index:) ->
      "the table ActionSlotPrereq row "
      <> int.to_string(row_id)
      <> " names slot "
      <> int.to_string(slot_index)
      <> ", and a bar has slots 0 to "
      <> int.to_string(slots_in_a_bar - 1)
    SlotRepeated(slot_index:) ->
      "the table ActionSlotPrereq has two rows for slot "
      <> int.to_string(slot_index)
    NoSlotRow(slot_index:) ->
      "the table ActionSlotPrereq has no row for slot "
      <> int.to_string(slot_index)
    NoPrerequisite(slot_index:, prerequisite_id:) ->
      "the table ActionSlotPrereq row of slot "
      <> int.to_string(slot_index)
      <> " names Prerequisite "
      <> int.to_string(prerequisite_id)
      <> ", which the table Prerequisite does not have"
  }
}

/// The slots open at a level, in slot order.
pub fn open_slots(unlocks unlocks: Unlocks, level level: Int) -> List(Int) {
  unlocks.slots
  |> list.index_map(fn(opening, slot) { #(slot, opening) })
  |> list.filter_map(fn(slot) {
    case opens(opening: slot.1, level:) {
      True -> Ok(slot.0)
      False -> Error(Nil)
    }
  })
}

fn opens(opening opening: Opening, level level: Int) -> Bool {
  case opening {
    NeverOpens -> False
    OpensWhen(conditions:) ->
      list.all(conditions, fn(condition) {
        prerequisite.compare(
          relation: condition.0,
          measured: level,
          value: condition.1,
        )
      })
  }
}

/// What the rule knows of the player: the level that opens slots, the book of abilities it
/// holds, and whether it is dead or in combat.
pub type Player {
  Player(
    level: Int,
    points_total: Int,
    book: List(Spell4BaseId),
    dead: Bool,
    in_combat: Bool,
  )
}

/// What the rule asks the connection to do, in order.
pub type Effect {
  /// Write a frame to the client.
  Send(frame: Frame)
  /// Write a log line.
  Log(level: LogLevel, text: String)
}

/// Why a save is refused with the connection ended: the client's own code never writes it.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
}

/// A check a save fails, with the result the client names it by.
type Fault {
  InvalidActionSetTable(ids: Int)
  PlayerIsDead
  InCombat
  InvalidSpecIndex(set: Int)
  BadSpellInActionSet(slot: Int, id: Int)
  SlotUnlockPrereqFalse(slot: Int, id: Int, level: Int)
  DuplicateSpell(id: Int)
  TierOfUnheldAbility(id: Int)
  TierChangedTwice(id: Int)
  InvalidSpellTier(id: Int, tier: Int, level: Int)
  InsufficientAbilityPoints(spent: Int, total: Int)
}

/// The client's number for the result (`lua.ActionSetLib.CodeEnumLimitedActionSetResult`).
fn result_of(fault fault: Fault) -> Int {
  case fault {
    InvalidActionSetTable(..) -> 25
    PlayerIsDead -> 27
    InCombat -> 30
    InvalidSpecIndex(..) -> 40
    BadSpellInActionSet(..) -> 18
    SlotUnlockPrereqFalse(..) -> 2
    DuplicateSpell(..) -> 13
    TierOfUnheldAbility(..) -> 18
    TierChangedTwice(..) -> 13
    InvalidSpellTier(..) -> 41
    InsufficientAbilityPoints(..) -> 42
  }
}

fn describe_fault(fault fault: Fault) -> String {
  case fault {
    InvalidActionSetTable(ids:) ->
      "the save holds "
      <> int.to_string(ids)
      <> " ids, not 12 (InvalidActionSetTable)"
    PlayerIsDead -> "the player is dead (PlayerIsDead)"
    InCombat -> "the player is in combat (InCombat)"
    InvalidSpecIndex(set:) ->
      "the save is for action set "
      <> int.to_string(set)
      <> ", and the active set is 0 (InvalidSpecIndex)"
    BadSpellInActionSet(slot:, id:) ->
      "slot "
      <> int.to_string(slot)
      <> " holds Spell4Base "
      <> int.to_string(id)
      <> ", which the player's book does not offer that slot (BadSpellInActionSet)"
    SlotUnlockPrereqFalse(slot:, id:, level:) ->
      "slot "
      <> int.to_string(slot)
      <> " holds Spell4Base "
      <> int.to_string(id)
      <> " and is not open at level "
      <> int.to_string(level)
      <> " (SlotUnlockPrereqFalse)"
    DuplicateSpell(id:) ->
      "Spell4Base "
      <> int.to_string(id)
      <> " is in the save twice (DuplicateSpell)"
    TierOfUnheldAbility(id:) ->
      "a tier change names Spell4Base "
      <> int.to_string(id)
      <> ", which the player's book does not hold (BadSpellInActionSet)"
    TierChangedTwice(id:) ->
      "Spell4Base "
      <> int.to_string(id)
      <> " has two tier changes in the save (DuplicateSpell)"
    InvalidSpellTier(id:, tier:, level:) ->
      "Spell4Base "
      <> int.to_string(id)
      <> " has no tier "
      <> int.to_string(tier)
      <> " the player can take at level "
      <> int.to_string(level)
      <> " (InvalidSpellTier)"
    InsufficientAbilityPoints(spent:, total:) ->
      "the tiers of the save cost "
      <> int.to_string(spent)
      <> " ability points and the level gives "
      <> int.to_string(total)
      <> " (InsufficientAbilityPoints)"
  }
}

/// What the client's 0xB1 is answered with: the bar the player has afterwards and the
/// frames and log lines that say so, or the refusal for a body the client's reader refuses.
/// `class_bar` is the class's level-1 abilities, the bar a player who has saved none holds.
/// A save that fails a check leaves the bar and the tiers as they were and is answered with
/// the result and the held bar; an accepted save is answered with the bar, the book's tiers in
/// set 0 and the points left. The AMP ids a save carries are read and not applied.
pub fn take(
  unlocks unlocks: Unlocks,
  tiers tiers: spell_tier.SpellTiers,
  player player: Player,
  saved saved: Saved,
  class_bar class_bar: List(Spell4BaseId),
  body body: BitArray,
) -> Result(#(Saved, List(Effect)), Refusal) {
  action_set_save.decode(body)
  |> client_connection.decoded(message_id: action_set_save.message_id)
  |> result.map_error(NotDecoded)
  |> result.map(fn(save) {
    case
      fault_of(unlocks:, player:, save:)
      |> result.try(fn(_) { tiers_after(tiers:, player:, saved:, save:) })
    {
      Ok(held) -> accepted(tiers:, player:, saved:, save:, held:)
      Error(fault) -> refused(saved:, class_bar:, fault:)
    }
  })
}

/// The saved bars with the save's bar in the active set and the tiers it leaves, answered with
/// the bar, the book's tiers in the active set and the points left.
fn accepted(
  tiers tiers: spell_tier.SpellTiers,
  player player: Player,
  saved saved: Saved,
  save save: action_set_save.ActionSetSave,
  held held: Dict(Spell4BaseId, Int),
) -> #(Saved, List(Effect)) {
  let bar =
    Bar(
      slots: list.map(save.spell4_base_ids, fn(id) {
        case id {
          0 -> None
          id -> Some(Spell4BaseId(id))
        }
      }),
    )
  let set = first_set().number
  let saved =
    Saved(
      bars: dict.insert(saved.bars, set, bar),
      tiers: case dict.is_empty(held) {
        True -> dict.delete(saved.tiers, set)
        False -> dict.insert(saved.tiers, set, held)
      },
    )
  let spent = points_spent(tiers:, saved:)
  #(
    saved,
    list.flatten([
      [
        Send(answer(bar:, result: ability_book_frame.action_set_ok)),
        Send(
          ability_book_frame.tiers(
            abilities: player.book,
            sets: [set],
            tier_of: fn(set, base) {
              book_tier_of(tiers:, saved:, set:, book: player.book, base:)
            },
          ),
        ),
        Send(ability_points.points_frame(total: player.points_total, spent:)),
        Send(ability_book_frame.action_set_saved(add_combat_log_line: True)),
      ],
      dropped_edits(save:),
    ]),
  )
}

/// The saved bars as they were, answered with the held bar and the check the save failed.
fn refused(
  saved saved: Saved,
  class_bar class_bar: List(Spell4BaseId),
  fault fault: Fault,
) -> #(Saved, List(Effect)) {
  let held = bar_of(saved:, set: first_set(), class_bar:)
  #(saved, [
    Send(answer(bar: held, result: result_of(fault:))),
    Send(ability_book_frame.action_set_saved(add_combat_log_line: False)),
    Log(
      level: LogWarning,
      text: "0xB1 refused with result "
        <> int.to_string(result_of(fault:))
        <> ": "
        <> describe_fault(fault:),
    ),
  ])
}

/// The 0x019D of the active set with every slot of a bar.
fn answer(bar bar: Bar, result result: Int) -> Frame {
  ability_book_frame.action_set(
    set: first_set().number,
    result:,
    slots: bar.slots,
    shortcuts: ability_book_frame.EverySlot,
  )
}

/// The debug line of the AMP ids of an accepted save, which are not applied.
fn dropped_edits(save save: action_set_save.ActionSetSave) -> List(Effect) {
  case save.amp_ids {
    [] -> []
    amps -> [
      Log(
        level: LogDebug,
        text: "0xB1 carries "
          <> int.to_string(list.length(amps))
          <> " AMPs, which are not applied",
      ),
    ]
  }
}

/// The first check the save fails, in the order of the rule's doc. Only 25 before 27 before
/// 30 is the client's own order (`0x1407580e0`); where 40 sits and the order of 18, 2 and 13
/// are the server's choice, since the client makes none of those checks.
fn fault_of(
  unlocks unlocks: Unlocks,
  player player: Player,
  save save: action_set_save.ActionSetSave,
) -> Result(Nil, Fault) {
  let ids = save.spell4_base_ids
  use <- bool.guard(
    when: list.length(ids) != slots_in_a_bar,
    return: Error(InvalidActionSetTable(ids: list.length(ids))),
  )
  use <- bool.guard(when: player.dead, return: Error(PlayerIsDead))
  use <- bool.guard(when: player.in_combat, return: Error(InCombat))
  use <- bool.guard(
    when: set_index(number: save.action_set_index) != Ok(first_set()),
    return: Error(InvalidSpecIndex(set: save.action_set_index)),
  )
  let open = open_slots(unlocks:, level: player.level)
  use <- slot_fault(ids:, player:, open:)
  let held = list.filter(ids, fn(id) { id != 0 })
  case
    list.find(held, fn(id) { list.count(held, fn(other) { other == id }) > 1 })
  {
    Ok(id) -> Error(DuplicateSpell(id:))
    Error(Nil) -> Ok(Nil)
  }
}

/// The tiers the set holds above tier 1 after the save's tier changes, or the first check
/// they fail, in the save's order: an ability the book does not hold, or an alternate given a tier
/// above 1 (the book holds it only as part of the ability that names it, and shows that ability's
/// tier; the stock builder never offers one, `0x140748390`), 18, an ability twice 13, a
/// tier the ability has no row for or the player's level does not reach 41, and last tiers that
/// cost more than the level gives 42. A fall is allowed to any tier that has a row, and the
/// points are judged on the tiers the save leaves, so one save may free points on one ability
/// and spend them on another.
/// The tier checks are the server's mapping: the client names the results and does not make
/// them (`lua.ActionSetLib.CodeEnumLimitedActionSetResult`).
fn tiers_after(
  tiers tiers: spell_tier.SpellTiers,
  player player: Player,
  saved saved: Saved,
  save save: action_set_save.ActionSetSave,
) -> Result(Dict(Spell4BaseId, Int), Fault) {
  let held =
    dict.get(saved.tiers, first_set().number) |> result.unwrap(dict.new())
  use #(after, _) <- result.try(
    list.try_fold(save.tier_changes, #(held, []), fn(state, change) {
      let #(now, seen) = state
      let base = Spell4BaseId(change.spell4_base_id)
      let tier = change.tier
      use <- bool.guard(
        when: !list.contains(player.book, base),
        return: Error(TierOfUnheldAbility(id: base.value)),
      )
      use <- bool.guard(
        when: tier != 1
          && result.is_ok(naming_ability(tiers:, book: player.book, base:)),
        return: Error(TierOfUnheldAbility(id: base.value)),
      )
      use <- bool.guard(
        when: list.contains(seen, base),
        return: Error(TierChangedTwice(id: base.value)),
      )
      let held_tier = result.unwrap(dict.get(now, base), 1)
      let reachable =
        spell_tier.change_cost(tiers:, base:, from: 1, to: tier) |> result.is_ok
      let level_reached = case tier > held_tier {
        True ->
          case spell_tier.level_needed(tiers:, tier:) {
            Ok(needed) -> player.level >= needed
            Error(Nil) -> False
          }
        False -> True
      }
      use <- bool.guard(
        when: !reachable || !level_reached,
        return: Error(InvalidSpellTier(
          id: base.value,
          tier:,
          level: player.level,
        )),
      )
      Ok(
        #(
          case tier {
            1 -> dict.delete(now, base)
            tier -> dict.insert(now, base, tier)
          },
          [base, ..seen],
        ),
      )
    }),
  )
  let spent = spell_tier.spent(tiers:, held: dict.to_list(after))
  use <- bool.guard(
    when: spent > player.points_total,
    return: Error(InsufficientAbilityPoints(spent:, total: player.points_total)),
  )
  Ok(after)
}

/// The first slot that holds an id it may not: a gadget or path slot, a slot not open at the
/// player's level, or an id the book does not hold.
fn slot_fault(
  ids ids: List(Int),
  player player: Player,
  open open: List(Int),
  then then: fn() -> Result(Nil, Fault),
) -> Result(Nil, Fault) {
  let fault =
    list.index_map(ids, fn(id, slot) { #(slot, id) })
    |> list.find_map(fn(placed) {
      let #(slot, id) = placed
      case id {
        0 -> Error(Nil)
        id ->
          case slot >= ability_slots, list.contains(open, slot) {
            True, _ -> Ok(BadSpellInActionSet(slot:, id:))
            False, False ->
              Ok(SlotUnlockPrereqFalse(slot:, id:, level: player.level))
            False, True ->
              case list.contains(player.book, Spell4BaseId(id)) {
                True -> Error(Nil)
                False -> Ok(BadSpellInActionSet(slot:, id:))
              }
          }
      }
    })
  case fault {
    Ok(fault) -> Error(fault)
    Error(Nil) -> then()
  }
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  let NotDecoded(undecoded:) = refusal
  client_connection.describe_undecoded(undecoded:)
}

/// What the builder's save leaves unchecked or undone, for the coverage measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Ability builder",
      missing: "The AMP ids a save carries are read and not applied: AMP picks are not built.",
    ),
    gap.Entry(
      area: "Ability builder",
      missing: "A held tier the plans cannot cast plays the best lower tier they can: the effects and the tooltip's numbers are the lower tier's (and, for two tiers, an area and a flag) while the client shows the held tier. The coverage measure lists each such tier spell.",
    ),
    gap.Entry(
      area: "Ability builder",
      missing: "The gadget and path slots never open, because the prerequisite types their rows name are not read and no gadget or path ability is in the book; every answer sends them empty, so the client clears them.",
    ),
    gap.Entry(
      area: "Ability builder",
      missing: "Only action set 0 is judged: a save for another set is refused, since the other sets are bought unlocks the server does not give.",
    ),
    gap.Entry(
      area: "Ability builder",
      missing: "A PvP restriction and the Update Action Set cast never apply, so a save is never refused for either.",
    ),
    gap.Entry(
      area: "Ability builder",
      missing: "An alternate in the bar shows its icon and a press does nothing: the client's press finds the bag item by the shortcut's Spell4Base.",
    ),
  ]
}
