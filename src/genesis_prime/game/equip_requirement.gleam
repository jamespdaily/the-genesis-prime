//// Whether a character may wear an item, by the checks the client runs before
//// it sends an equip (CheckEquipRequirements 0x1403b4710), in its order. The
//// rule is pure: the connection supplies the character as a `Wearer`.
////
//// ```
//// Item2 row, its ItemSpecial, the category's ItemProficiency ─▶ requirements
//// a Wearer ─▶ race 39 ▶ class 40 ▶ faction 132 ▶ prerequisites 144 ▶
////             proficiency 41 ▶ level 42 ─▶ Wearable | Refused(code)
//// ```
////
//// - **Race and class:** the item's raceRequired and classRequired are masks
////   with bit `race - 1` and `class - 1`; a mask of 0 allows any
////   (`Item2.raceRequired`, `Item2.classRequired`).
//// - **Faction:** an item with a faction2IdRequired needs that faction.
//// - **Prerequisites:** the item's own and its ItemSpecial's (when that special
////   has a spell to activate) must each pass. A prerequisite whose condition the
////   server does not read is refused and named in `PrerequisiteNotRead`: the
////   client would decide it, the server cannot, and the cast rule makes the same
////   choice (genesis_prime/game/prerequisite `NotRead`).
//// - **Proficiency:** the item category's ItemProficiency mask must be among the
////   wearer's item proficiencies; no row or a mask of 0 needs none
////   (`0x1403ca2b0`).
//// - **Level:** the wearer's level must reach the item's required level, which is
////   1 for an item whose requiredLevel is 0 or whose flags hold bit 0.
////
//// The codes are the client's `GameLib.CodeEnumGenericError`.

import genesis_prime/game/item_property
import genesis_prime/game/prerequisite
import genesis_prime/table/id.{type Item2Id, PrerequisiteId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2_reward.{type Quest2Reward}
import gleam/bool
import gleam/int
import gleam/list
import gleam/result

/// Item_WrongRace.
const wrong_race = 39

/// Item_WrongClass.
const wrong_class = 40

/// Item_FailedProficiency.
const failed_proficiency = 41

/// Item_LevelToLow.
const level_too_low = 42

/// Item_WrongFaction.
const wrong_faction = 132

/// Item_EquipPrereqFailed.
pub const prerequisite_failed = 144

/// Quest2Reward flags bit 0: the row is a choice.
const choice_flag = 1

/// Quest2Reward flags bit 1: the choice is offered to every player.
const offered_to_all_flag = 2

/// Quest2RewardType 1: an item.
const item_reward_type = 1

/// What the checks read of the character: its faction id, its level, the player
/// facts the prerequisites read (race, class, gender, World, zones and the rest;
/// the race and class checks read these too) and the mask of its item proficiencies (`Class.startingItemProficiencies`,
/// what player_character_state sends).
pub type Wearer {
  Wearer(
    faction_id: Int,
    level: Int,
    player: prerequisite.Player,
    item_proficiencies: Int,
    checker: prerequisite.Checker,
  )
}

/// What the checks give.
pub type Verdict {
  /// Every check passes.
  Wearable
  /// The first check that fails, with the client's GenericError code.
  Refused(code: Int)
  /// A prerequisite of the item rests on a condition of this PrerequisiteType,
  /// which the server does not read: refused with the code 144.
  PrerequisiteNotRead(prerequisite_type: Int)
}

/// Why the checks cannot be made: a table has no row for the item or for a
/// prerequisite it names.
pub type CheckError {
  /// The item's properties cannot be given.
  NoItemProperties(error: item_property.ItemPropertyError)
  /// A prerequisite the item names does not load.
  PrerequisiteNotLoaded(id: Int, error: prerequisite.LoadError)
}

/// A sentence that says which row the check could not read, for the log.
pub fn describe(error error: CheckError) -> String {
  case error {
    NoItemProperties(error:) -> item_property.describe(error:)
    PrerequisiteNotLoaded(error:, ..) ->
      prerequisite.describe_load_error(error:)
  }
}

/// Whether the wearer may wear the item. Only a table with no row for the item
/// or for a prerequisite it names is an error.
pub fn check(
  tables tables: table_store.Tables,
  item2_id item2_id: Item2Id,
  wearer wearer: Wearer,
) -> Result(Verdict, CheckError) {
  use required <- result.try(
    item_property.equip_requirements(tables:, item2_id: item2_id.value)
    |> result.map_error(NoItemProperties),
  )
  use <- first_failure(
    fails: !allows(mask: required.race_mask, number: wearer.player.race_id),
    code: wrong_race,
  )
  use <- first_failure(
    fails: !allows(mask: required.class_mask, number: wearer.player.class_id),
    code: wrong_class,
  )
  use <- first_failure(
    fails: required.faction_id != 0 && required.faction_id != wearer.faction_id,
    code: wrong_faction,
  )
  use prerequisites <- result.try(
    list.try_map(required.prerequisite_ids, fn(prerequisite_id) {
      prerequisite.load(
        id: PrerequisiteId(prerequisite_id),
        rows: prerequisite.table_rows(tables:),
        arcs: prerequisite.table_arcs(tables:),
        quests: prerequisite.table_quests(tables:),
      )
      |> result.map_error(PrerequisiteNotLoaded(id: prerequisite_id, error: _))
    }),
  )
  let subject =
    prerequisite.of_wearer(
      factions: prerequisite.Factions(
        current: wearer.faction_id,
        base: wearer.faction_id,
      ),
      player: wearer.player,
      checker: wearer.checker,
    )
  let verdicts =
    list.map(prerequisites, fn(prerequisite) {
      prerequisite.check(prerequisite:, subject:)
    })
  use <- first_unread(verdicts:)
  use <- first_failure(
    fails: list.contains(verdicts, prerequisite.Fails),
    code: prerequisite_failed,
  )
  use <- first_failure(
    fails: !proficient(required:, wearer:),
    code: failed_proficiency,
  )
  use <- first_failure(
    fails: wearer.level < required.required_level,
    code: level_too_low,
  )
  Ok(Wearable)
}

/// Whether a Quest2Reward row is offered to the wearer as a choice, as the client's
/// IsRewardChoiceOffered decides (`0x140551c60`): a row without bit 0, a row with bit 1, or a
/// row that is not an item is offered; an item choice is offered only when its Item2 row
/// exists and the wearer's race, class and item proficiency allow it.
pub fn offered(
  tables tables: table_store.Tables,
  reward reward: Quest2Reward,
  wearer wearer: Wearer,
) -> Bool {
  use <- bool.guard(
    when: int.bitwise_and(reward.flags, choice_flag) == 0
      || int.bitwise_and(reward.flags, offered_to_all_flag) != 0
      || reward.quest2_reward_type_id != item_reward_type,
    return: True,
  )
  item_property.equip_requirements(tables:, item2_id: reward.object_id)
  |> result.map(fn(required) {
    allows(mask: required.race_mask, number: wearer.player.race_id)
    && allows(mask: required.class_mask, number: wearer.player.class_id)
    && proficient(required:, wearer:)
  })
  |> result.unwrap(or: False)
}

/// Whether the wearer has the item's proficiency: an item that needs none is allowed.
fn proficient(
  required required: item_property.EquipRequirements,
  wearer wearer: Wearer,
) -> Bool {
  required.proficiency_mask == 0
  || int.bitwise_and(required.proficiency_mask, wearer.item_proficiencies)
  == required.proficiency_mask
}

/// Whether a mask of races or classes, bit `number - 1` for each, allows the
/// number: a mask of 0 allows any.
fn allows(mask mask: Int, number number: Int) -> Bool {
  mask == 0 || int.bitwise_and(mask, int.bitwise_shift_left(1, number - 1)) != 0
}

/// The refusal with the code when the check fails, else what the rest of the
/// checks give.
fn first_failure(
  fails fails: Bool,
  code code: Int,
  otherwise otherwise: fn() -> Result(Verdict, error),
) -> Result(Verdict, error) {
  bool.lazy_guard(when: fails, return: fn() { Ok(Refused(code:)) }, otherwise:)
}

/// `PrerequisiteNotRead` for the first condition type the server does not read,
/// else what the rest of the checks give.
fn first_unread(
  verdicts verdicts: List(prerequisite.Verdict),
  otherwise otherwise: fn() -> Result(Verdict, error),
) -> Result(Verdict, error) {
  let unread =
    list.find_map(verdicts, fn(verdict) {
      case verdict {
        prerequisite.NotRead(prerequisite_type:) -> Ok(prerequisite_type)
        prerequisite.Passes | prerequisite.Fails -> Error(Nil)
      }
    })
  case unread {
    Ok(prerequisite_type) -> Ok(PrerequisiteNotRead(prerequisite_type:))
    Error(Nil) -> otherwise()
  }
}
