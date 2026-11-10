//// A player's requests that change the quest log: to accept a quest, 0x035B, to retry a
//// botched one, 0x0365, to abandon one, 0x035A, to mention or withdraw one, 0x0360, to
//// track one, 0x0364, and to ignore or stop ignoring one, 0x035E: a feature of the game
//// connection's rule (genesis_prime/game/connection) taken from inside 0x038C with the
//// player in the world. The client sends each only after its own check, and changes no
//// state until the server answers 0x035C (an accept, a retry, an abandon or an ignore) or,
//// for a mention and a track, at once.
////
//// ```
//// 0x35B {item, quest}, 0x365 {quest} ─▶ take(...) ─▶ a quest the client has, a source it
////                                                    would have started it from, and every
////                                                    check passing: the log gains the active
////                                                    entry and 0x35C {quest, 1, 0} is sent
//// 0x35A {quest}                      ─▶ a quest `CanAbandonQuest` lets go: the log holds it
////                                       Abandoned and 0x35C {quest, 6, 0} is sent
//// 0x360 {quest, bit}                 ─▶ the log holds the quest Mentioned, no answer
//// 0x364 {quest, bit}                 ─▶ the active entry's tracked flag is set, no answer
//// 0x35E {quest, bit}                 ─▶ bit 1: Ignored, 0x35C {quest, 7, 0}; bit 0: Mentioned,
////                                       0x35C {quest, 5, 0}
////                                    ─▶ any other: a log line, nothing written
//// ```
////
//// - **The source** is what the client starts a quest from. The dialog's accept sends
////   location 300 and bag index -1 (`opcode.0x35b`): it needs a shown, alive creature,
////   not Hostile to the player, whose Creature2 row gives the quest, within reach, or a
////   quest of the communicator (Quest2 flags 4) the log holds a state of 4 to 7 for. Any other
////   place is a held item there whose Item2 `quest2IdActivation` is the quest. A retry
////   carries no place, so it takes any of the three.
//// - **The checks** are the client's, in its order, and the first that does not pass
////   decides: `can_accept` gives the code the client would show, or the gap it names when
////   the server does not read what the check needs (reputation, a prerequisite item's
////   per-item counter, an unread prerequisite type, a drawn periodic quest, a contract;
////   the quest log step, #334). A quest the server cannot say a gap of is never accepted.
//// - **Abandon** follows `CanAbandonQuest` (`0x140552930`): a Botched quest (4) may always
////   be let go, otherwise Quest2 flags 0x4000 forbid it and an Achieved quest (2) with flags
////   0x8000 may not be, and past those only an Accepted, Achieved or Botched quest (1, 2, 4)
////   passes. The log keeps the quest in the client's second list as Abandoned (6), where
////   check 2 of `CanAcceptQuest` lets it be taken again (`0x140552490`).
//// - **Mention, track and ignore** are the client's own wishes (`opcode.0x360`,
////   `opcode.0x364`, `opcode.0x35e`): the client sends a mention (bit 1) for a quest it holds
////   no state of or holds Ignored, and a withdrawal (bit 0) for one held Botched, Mentioned
////   or Abandoned, and keeps the quest Mentioned either way; a track for a quest of its active
////   list; an ignore (bit 1) for an Abandoned or Mentioned quest and a stop (bit 0) for an
////   Ignored one, which the server answers with state 7 and state 5.
//// - **The log** reads each quest's stored state (`quest_log.stored_state`), which the
////   checks that compare it only against absent, 1 to 3 and 4 to 7 get the same from as
////   the state derived from the objectives.
//// - **A request the client would not send** is logged once on the connection for each
////   reason, a warning and then debug lines, and answered with nothing; the connection
////   goes on. A body the client's own reader refuses ends it.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/game/equip_requirement
import genesis_prime/game/interaction
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/shown.{
  type Picture, ShownCreature, ShownObject, ShownPlayer,
}
import genesis_prime/message/item_place
import genesis_prime/message/quest_abandon
import genesis_prime/message/quest_accept
import genesis_prime/message/quest_ignore
import genesis_prime/message/quest_mention
import genesis_prime/message/quest_retry
import genesis_prime/message/quest_track
import genesis_prime/step.{type LogLevel}
import genesis_prime/store.{type HeldItem}
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/episode
import genesis_prime/table/episode_quest
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type Item2Id, EpisodeId, GameFormulaId, Item2Id, PeriodicQuestGroupId,
  PrerequisiteId, Quest2Id,
}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/periodic_quest_group
import genesis_prime/table/quest2.{type Quest2}
import genesis_prime/world_map/spawn
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/set.{type Set}

/// The quest messages of the player in the world, which the client sends inside 0x038C
/// (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x035B, the player accepts a quest.
  Accept
  /// 0x0365, the player retries a botched quest.
  Retry
  /// 0x035A, the player abandons a quest.
  Abandon
  /// 0x0360, the player mentions a quest, or withdraws the mention.
  Mention
  /// 0x0364, the player tracks a quest, or stops tracking it.
  Track
  /// 0x035E, the player ignores a quest, or stops ignoring it.
  Ignore
}

/// What the server does not read that a check of the client's needs. Each is a
/// gap of the quests, zones and prerequisites step (#334).
pub type Gap {
  /// The reputation a quest requires (Quest2 `factionIdPreq`): the server holds none.
  Reputation
  /// A prerequisite item the client may count in its per-item inventory counter,
  /// which the server does not hold.
  PrerequisiteItemCounter
  /// A prerequisite condition of this PrerequisiteType.
  PrerequisiteType(prerequisite_type: Int)
  /// A periodic quest of a group that offers only some of its quests or limits how
  /// many a player holds: the draw is not read.
  PeriodicDraw(group_id: Int)
  /// A quest of the contracts manager (Quest2 flags 0x80000).
  Contract
}

/// What the client's `CanAcceptQuest` gives.
pub type Verdict {
  /// Every check passes.
  Acceptable
  /// The first check that fails, with the code the client shows for it.
  Refused(code: Int)
  /// The first check the server cannot decide.
  NotRead(gap: Gap)
}

/// What the checks read of the player: the player the conditions read, the factions,
/// the log and the held items.
pub type Asker {
  Asker(
    player: prerequisite.Player,
    factions: prerequisite.Factions,
    log: QuestLog,
    items: List(HeldItem),
  )
}

/// A table row a check needs and the client's tables lack.
pub type CheckError {
  /// The prerequisite the quest names cannot be loaded.
  PrerequisiteNotLoaded(id: Int, error: prerequisite.LoadError)
  /// The quest's episode has no Episode row.
  NoEpisodeRow(episode_id: Int)
  /// The quest's periodic group has no PeriodicQuestGroup row.
  NoPeriodicGroupRow(group_id: Int)
}

/// Why a check stops the walk.
type Stop {
  Refuse(code: Int)
  Unread(gap: Gap)
  Broken(error: CheckError)
}

/// The Quest2 flag of a quest that needs a mention (the communicator's), so that a
/// player without a state of 4 to 7 cannot accept it.
const needs_mention_flag = 0x400

/// The Quest2 flag of a quest that may not be abandoned unless it is Botched
/// (`0x140552930`).
const no_abandon_flag = 0x4000

/// The Quest2 flag of a quest that may not be abandoned once it is Achieved
/// (`0x140552930`).
const kept_when_achieved_flag = 0x8000

/// The Quest2 flag of a quest the creature that gives it starts with a click that
/// activates the unit, so it shows no dialog (`0x1405a8d40`, interaction kind 12).
const instant_flag = 0x800

/// The Quest2 flag of a quest its receiver shows once the player may accept it
/// (`0x1405a8d40`).
const receivable_flag = 0x1

/// The Quest2 flag of a quest that comes by the communicator.
const communicator_flag = 0x4

/// The Quest2 flag of a quest that repeats.
const repeats_flag = 0x20

/// The Quest2 flag of a contract.
const contract_flag = 0x80000

/// The Episode flag that lets any of its quests be taken.
const episode_open_flag = 0x10

/// The EpisodeQuest flag that leaves the quest out of the episode's order.
const episode_left_out_flag = 0x1

/// The `can_accept` mask bit of the level check.
const level_bit = 0x2

/// The `can_accept` mask bit of the prerequisite-quests check.
const prerequisite_quests_bit = 0x40

/// The prerequisite-quest flag that needs only one of the quests, not all.
const any_quest_flag = 0x1

/// The prerequisite-quest flag that joins the level and the quests in one check.
const joined_flag = 0x2

/// The prerequisite flag that refuses an exclusion only when every one is taken.
const all_excluded_flag = 0x20

/// The GameFormula row of the most active quests a player may hold.
const quest_limit_formula = 655

/// The limit when the row is missing, as the client's own default is.
const default_quest_limit = 40

/// The PeriodicQuestGroup value of a group that offers every quest, and of one with no
/// limit on how many a player holds.
const all_offered = 0xffffffff

/// The Faction2 ids of the player factions.
const exile = 167

const dominion = 166

/// The client's refusal codes of `CanAcceptQuest`.
const already_has = 2

const level_low = 3

const wrong_race = 4

const wrong_class = 5

const prerequisite_quests_missing = 8

const excluded = 9

const episode_holds_back = 10

const not_mentioned = 11

const prerequisite_unmet = 12

const wrong_path = 13

const wrong_faction = 14

const log_full = 15

const periodic_refused = 16

/// The mask that asks every check of `CanAcceptQuest` (`0x140552550`).
pub const every_check = 0xffff_ffff

/// The mask the client's marking of a creature's quests passes (`0x1405a8d40`, `mov edx,
/// 0xffffdfff` at `0x1405a8e26`): every check but the one for a full log (bit 13).
const giver_checks = 0xffff_dfff

/// Whether the player may accept the quest, with the checks the mask asks for, in the
/// client's order (`0x140552550`): the first that fails or is not read decides. The
/// mask has a bit for each check: 0 already held, 1 level, 2 race, 3 class, 4
/// reputation, 5 prerequisite item, 6 prerequisite quests, 7 exclusions, 8 episode, 9
/// mentioned, 10 prerequisite, 11 path, 12 faction, 13 log full, 14 periodic, 15
/// contract. The level (bit 1) and the prerequisite quests (bit 6) are separate checks,
/// each run on its own bit; a quest with the joined flag, asked for both, refuses only
/// when both fail. A table row a check needs that the
/// tables lack is an error.
pub fn can_accept(
  tables tables: table_store.Tables,
  quest quest: Quest2,
  asker asker: Asker,
  mask mask: Int,
) -> Result(Verdict, CheckError) {
  let checks = [
    #(0x200, fn() { mentioned(quest:, asker:) }),
    #(0x1, fn() { not_held(quest:, asker:) }),
    #(0x1000, fn() { faction(quest:, asker:) }),
    #(0x4, fn() { race(quest:, asker:) }),
    #(0x8, fn() { class(quest:, asker:) }),
    #(0x100, fn() { episode_allows(tables:, quest:, asker:) }),
    #(0x42, fn() { level_and_quests(quest:, asker:, mask:) }),
    #(0x80, fn() { exclusions(quest:, asker:) }),
    #(0x10, fn() { reputation(quest:) }),
    #(0x20, fn() { prerequisite_item(quest:, asker:) }),
    #(0x400, fn() { prerequisite_met(tables:, quest:, asker:) }),
    #(0x800, fn() { path(quest:, asker:) }),
    #(0x2000, fn() { log_has_room(tables:, quest:, asker:) }),
    #(0x4000, fn() { periodic(tables:, quest:) }),
    #(0x8000, fn() { contract(quest:) }),
  ]
  case
    list.try_each(checks, fn(check) {
      case int.bitwise_and(mask, check.0) != 0 {
        True -> check.1()
        False -> Ok(Nil)
      }
    })
  {
    Ok(Nil) -> Ok(Acceptable)
    Error(Refuse(code:)) -> Ok(Refused(code:))
    Error(Unread(gap:)) -> Ok(NotRead(gap:))
    Error(Broken(error:)) -> Error(error)
  }
}

/// Every gap the quest's own columns reach, for any player: the reputation it names,
/// its contract flag, the per-item counter of its prerequisite item, the group's draw
/// of a periodic quest, and each unread type of its prerequisite and the rows that
/// prerequisite nests. A check stops on the first of these a player meets; this is
/// the whole of what the quest needs the server to read. A prerequisite or periodic
/// group row the table lacks is the error.
pub fn gaps(
  tables tables: table_store.Tables,
  quest quest: Quest2,
) -> Result(List(Gap), CheckError) {
  use own <- result.try(
    list.try_fold(
      [reputation(quest:), contract(quest:), periodic(tables:, quest:)],
      [],
      fn(found, checked) {
        case checked {
          Error(Unread(gap:)) -> Ok([gap, ..found])
          Error(Broken(error:)) -> Error(error)
          Ok(Nil) | Error(Refuse(..)) -> Ok(found)
        }
      },
    ),
  )
  let item = case quest.preq_item {
    0 -> []
    _ -> [PrerequisiteItemCounter]
  }
  use types <- result.try(case quest.prerequisite_id {
    0 -> Ok([])
    _ ->
      case loaded_prerequisite(tables:, quest:) {
        Ok(loaded) ->
          Ok(
            list.map(
              prerequisite.unread_types(prerequisite: loaded),
              fn(type_id) { PrerequisiteType(prerequisite_type: type_id) },
            ),
          )
        Error(error) ->
          Error(PrerequisiteNotLoaded(id: quest.prerequisite_id, error:))
      }
  })
  Ok(list.flatten([list.reverse(own), item, types]))
}

/// Whether the client marks the creature with a quest dialog for this player
/// (`0x1405a8d40`): a quest it receives that the player has achieved, or may accept and
/// the quest shows to its receiver, or holds; or a quest it gives that the player holds,
/// or may accept. A quest whose dialog the client does not open is not counted: one that
/// starts with a click that activates the unit, one that needs a mention the player has
/// not had, one the player may not accept yet, and one whose Quest2 row the tables lack.
/// A quest that starts with a click that activates the unit (kind 12) shows no dialog
/// though the creature is marked for another of its quests. Only a refusal hides a quest:
/// one the server cannot decide for a gap in what it reads counts as shown, so that no
/// giver is hidden, and one a table row it needs is missing from is `Undecided`, which
/// the caller logs, unless another quest of the creature shows.
pub fn offers(
  tables tables: table_store.Tables,
  asker asker: Asker,
  creature creature: Creature2,
) -> interaction.Offer {
  let received =
    list.map(named(ids: spawn.received_quest_ids(creature)), fn(quest_id) {
      #(quest_id, receive_shown(tables:, asker:, quest_id:))
    })
  let given =
    list.map(named(ids: spawn.given_quest_ids(creature)), fn(quest_id) {
      #(quest_id, give_shown(tables:, asker:, quest_id:))
    })
  let decided = list.append(received, given)
  case list.any(decided, fn(quest) { quest.1 == Ok(True) }) {
    True -> interaction.Offered
    False ->
      case
        list.find_map(decided, fn(quest) {
          case quest.1 {
            Error(error) -> Ok(#(quest.0, describe(error:)))
            Ok(_) -> Error(Nil)
          }
        })
      {
        Ok(#(quest_id, cause)) -> interaction.Undecided(quest_id:, cause:)
        Error(Nil) -> interaction.NothingToOffer
      }
  }
}

/// Whether the client shows a quest the creature receives (`0x1405a8d40`): the player
/// has achieved it, or it is flagged 1 and the player may accept it, or the player holds
/// it. A quest with no Quest2 row is not marked.
fn receive_shown(
  tables tables: table_store.Tables,
  asker asker: Asker,
  quest_id quest_id: Int,
) -> Result(Bool, CheckError) {
  case quest2.get(tables:, id: Quest2Id(quest_id)) {
    Error(Nil) -> Ok(False)
    Ok(row) -> {
      let state = derived_state(tables:, asker:, quest_id:)
      use <- bool.guard(when: state == 1 || state == 2, return: Ok(True))
      case has_flag(row.flags, receivable_flag) {
        True -> refused(tables:, asker:, row:) |> result.map(bool.negate)
        False -> Ok(False)
      }
    }
  }
}

/// Whether the client shows a quest the creature gives with a dialog (`0x1405a8d40`). A
/// quest with no Quest2 row is not marked.
fn give_shown(
  tables tables: table_store.Tables,
  asker asker: Asker,
  quest_id quest_id: Int,
) -> Result(Bool, CheckError) {
  case quest2.get(tables:, id: Quest2Id(quest_id)) {
    Error(Nil) -> Ok(False)
    Ok(row) -> gives_dialog(tables:, asker:, quest_id:, row:)
  }
}

/// No Quest2 row has a repeat period above 4, so the client's skip of a quest of that
/// kind (`0x1405a8d40`) is not built.
fn gives_dialog(
  tables tables: table_store.Tables,
  asker asker: Asker,
  quest_id quest_id: Int,
  row row: Quest2,
) -> Result(Bool, CheckError) {
  use <- bool.guard(when: has_flag(row.flags, instant_flag), return: Ok(False))
  use waits <- result.try(waits_for_mention(tables:, asker:, quest_id:, row:))
  use <- bool.guard(when: waits, return: Ok(False))
  let state = derived_state(tables:, asker:, quest_id:)
  use <- bool.guard(when: state == 1 || state == 2, return: Ok(True))
  refused(tables:, asker:, row:) |> result.map(bool.negate)
}

/// Whether a quest that needs a mention is acceptable without one, which the client's
/// marking leaves out (`0x1405a8d40`).
fn waits_for_mention(
  tables tables: table_store.Tables,
  asker asker: Asker,
  quest_id quest_id: Int,
  row row: Quest2,
) -> Result(Bool, CheckError) {
  use <- bool.guard(
    when: !has_flag(row.flags, needs_mention_flag)
      || in_second_list(state: state_of(asker:, quest_id:)),
    return: Ok(False),
  )
  can_accept(tables:, quest: row, asker:, mask: giver_checks)
  |> result.map(fn(verdict) { verdict == Acceptable })
}

/// Whether the client's check with the giver's mask refuses the quest. A gap the server
/// does not read is not a refusal.
fn refused(
  tables tables: table_store.Tables,
  asker asker: Asker,
  row row: Quest2,
) -> Result(Bool, CheckError) {
  can_accept(tables:, quest: row, asker:, mask: giver_checks)
  |> result.map(fn(verdict) {
    case verdict {
      Refused(..) -> True
      Acceptable | NotRead(..) -> False
    }
  })
}

/// The state the client derives for a quest of the log, or the stored one when the
/// quest has no readable rows.
fn derived_state(
  tables tables: table_store.Tables,
  asker asker: Asker,
  quest_id quest_id: Int,
) -> Int {
  quest_log.quest_of(tables:, id: quest_id)
  |> result.map(fn(quest) { quest_log.state(log: asker.log, quest:) })
  |> result.unwrap(state_of(asker:, quest_id:))
}

fn refuse_when(when when: Bool, code code: Int) -> Result(Nil, Stop) {
  use <- bool.guard(when:, return: Error(Refuse(code:)))
  Ok(Nil)
}

fn has_flag(flags: Int, flag: Int) -> Bool {
  int.bitwise_and(flags, flag) != 0
}

fn state_of(asker asker: Asker, quest_id quest_id: Int) -> Int {
  quest_log.stored_state(log: asker.log, quest_id:)
}

/// Whether the log holds a state of 4 to 7 of the quest.
fn in_second_list(state state: Int) -> Bool {
  state >= 4 && state <= 7
}

/// Whether a completed quest may be taken again: it repeats or has a period.
fn takes_again(quest quest: Quest2) -> Bool {
  has_flag(quest.flags, repeats_flag) || quest.quest_repeat_period_enum != 0
}

/// Check 11: a quest that needs a mention is taken only once the log holds a state
/// of 4 to 7 for it, or while a completed repeat.
fn mentioned(quest quest: Quest2, asker asker: Asker) -> Result(Nil, Stop) {
  let state = state_of(asker:, quest_id: quest.id)
  refuse_when(
    when: has_flag(quest.flags, needs_mention_flag)
      && !in_second_list(state:)
      && !{ state == 3 && takes_again(quest:) },
    code: not_mentioned,
  )
}

/// Check 2: a quest accepted, achieved, or completed with no repeat is not taken.
fn not_held(quest quest: Quest2, asker asker: Asker) -> Result(Nil, Stop) {
  let state = state_of(asker:, quest_id: quest.id)
  refuse_when(
    when: state == 1 || state == 2 || { state == 3 && !takes_again(quest:) },
    code: already_has,
  )
}

/// Check 14: the quest's faction, 0 Exile, 1 Dominion, 2 either; any other refuses.
fn faction(quest quest: Quest2, asker asker: Asker) -> Result(Nil, Stop) {
  let current = asker.factions.current
  let allowed = case quest.quest_player_faction_enum {
    0 -> current == exile
    1 -> current == dominion
    2 -> True
    _ -> False
  }
  refuse_when(when: !allowed, code: wrong_faction)
}

/// Check 4: the race the quest needs, 0 for none.
fn race(quest quest: Quest2, asker asker: Asker) -> Result(Nil, Stop) {
  refuse_when(
    when: quest.preq_race != 0 && quest.preq_race != asker.player.race_id,
    code: wrong_race,
  )
}

/// Check 5: the class the quest needs, 0 for none.
fn class(quest quest: Quest2, asker asker: Asker) -> Result(Nil, Stop) {
  refuse_when(
    when: quest.preq_class != 0 && quest.preq_class != asker.player.class_id,
    code: wrong_class,
  )
}

/// Check 10: only the lowest-id episode of the quest is asked. It lets the quest
/// through when it is open, or when the quest or any quest of its order that is not
/// Completed is still to take.
fn episode_allows(
  tables tables: table_store.Tables,
  quest quest: Quest2,
  asker asker: Asker,
) -> Result(Nil, Stop) {
  let rows = episode_quest.all(tables)
  let episodes =
    list.filter_map(rows, fn(row) {
      case row.quest_id == quest.id {
        True -> Ok(row.episode_id)
        False -> Error(Nil)
      }
    })
    |> list.sort(int.compare)
  case episodes {
    [] -> Ok(Nil)
    [first, ..] ->
      case episode.get(tables, EpisodeId(first)) {
        Error(Nil) -> Error(Broken(NoEpisodeRow(episode_id: first)))
        Ok(row) ->
          refuse_when(
            when: !has_flag(row.flags, episode_open_flag)
              && !list.any(rows, fn(member) {
              member.episode_id == first
              && !has_flag(member.flags, episode_left_out_flag)
              && {
                member.quest_id == quest.id
                || state_of(asker:, quest_id: member.quest_id) != 3
              }
            }),
            code: episode_holds_back,
          )
      }
  }
}

fn named(ids ids: List(Int)) -> List(Int) {
  list.filter(ids, fn(id) { id != 0 })
}

/// Checks 3 and 8: the level (mask bit 1), and the quests that must be completed, all or
/// any one (mask bit 6), each run on its own bit. With the joined flag and both bits
/// asked they are one check, which refuses only when both fail.
fn level_and_quests(
  quest quest: Quest2,
  asker asker: Asker,
  mask mask: Int,
) -> Result(Nil, Stop) {
  let level_asked = int.bitwise_and(mask, level_bit) != 0
  let quests_asked = int.bitwise_and(mask, prerequisite_quests_bit) != 0
  let too_low = asker.player.level < quest.preq_level
  let required =
    named(ids: [quest.preq_quest0, quest.preq_quest01, quest.preq_quest02])
  let completed = fn(id) { state_of(asker:, quest_id: id) == 3 }
  let met = case required {
    [] -> True
    _ ->
      case has_flag(quest.preq_flags, any_quest_flag) {
        True -> list.any(required, completed)
        False -> list.all(required, completed)
      }
  }
  case has_flag(quest.preq_flags, joined_flag) && level_asked && quests_asked {
    True -> refuse_when(when: too_low && !met, code: level_low)
    False -> {
      use Nil <- result.try(refuse_when(
        when: level_asked && too_low,
        code: level_low,
      ))
      refuse_when(when: quests_asked && !met, code: prerequisite_quests_missing)
    }
  }
}

/// Check 9: the quests named as exclusions that the log holds as accepted, achieved
/// or completed. Any one refuses, or all of them with the all-excluded flag.
fn exclusions(quest quest: Quest2, asker asker: Asker) -> Result(Nil, Stop) {
  let named_ids =
    named(ids: [
      quest.quest_id_exclusion_preq0,
      quest.quest_id_exclusion_preq1,
      quest.quest_id_exclusion_preq2,
    ])
  let taken = fn(id) {
    let state = state_of(asker:, quest_id: id)
    state >= 1 && state <= 3
  }
  case named_ids {
    [] -> Ok(Nil)
    _ ->
      refuse_when(
        when: case has_flag(quest.preq_flags, all_excluded_flag) {
          True -> list.all(named_ids, taken)
          False -> list.any(named_ids, taken)
        },
        code: excluded,
      )
  }
}

/// Check 6: the reputation the quest needs, which the server does not hold.
fn reputation(quest quest: Quest2) -> Result(Nil, Stop) {
  case
    named(ids: [
      quest.faction_id_preq0,
      quest.faction_id_preq01,
      quest.faction_id_preq02,
    ])
  {
    [] -> Ok(Nil)
    _ -> Error(Unread(Reputation))
  }
}

/// The locations check 7 counts: equipped, the bags, and 8 and 9 (mask 0x303 of
/// `0x140552550`).
const counted_locations = [0, 1, 8, 9]

/// How many of the Item2 the player holds in the counted locations: the sum of the
/// stacks there (a stack's `stack_count`), which a collect objective takes as its
/// progress.
pub fn held_count(
  items items: List(HeldItem),
  item2_id item2_id: Item2Id,
) -> Int {
  list.fold(items, 0, fn(total, item) {
    case
      item.item2_id == item2_id
      && list.contains(counted_locations, item.location)
    {
      True -> total + item.stack_count
      False -> total
    }
  })
}

/// Check 7: the item the quest needs, held in one of the counted locations. An item
/// the server does not find there may be in the client's per-item inventory counter,
/// which it does not read.
fn prerequisite_item(
  quest quest: Quest2,
  asker asker: Asker,
) -> Result(Nil, Stop) {
  use <- bool.guard(when: quest.preq_item == 0, return: Ok(Nil))
  case
    list.any(asker.items, fn(item) {
      item.item2_id == Item2Id(quest.preq_item)
      && list.contains(counted_locations, item.location)
    })
  {
    True -> Ok(Nil)
    False -> Error(Unread(PrerequisiteItemCounter))
  }
}

/// The prerequisite the quest names, loaded with the rows it nests.
fn loaded_prerequisite(
  tables tables: table_store.Tables,
  quest quest: Quest2,
) -> Result(prerequisite.Prerequisite, prerequisite.LoadError) {
  prerequisite.load(
    id: PrerequisiteId(quest.prerequisite_id),
    rows: prerequisite.table_rows(tables:),
    arcs: prerequisite.table_arcs(tables:),
    quests: prerequisite.table_quests(tables:),
  )
}

/// Check 12: the prerequisite the quest names, for the player with its log.
fn prerequisite_met(
  tables tables: table_store.Tables,
  quest quest: Quest2,
  asker asker: Asker,
) -> Result(Nil, Stop) {
  use <- bool.guard(when: quest.prerequisite_id == 0, return: Ok(Nil))
  case loaded_prerequisite(tables:, quest:) {
    // A prerequisite id with no row fails (EvaluatePrerequisite 0x1404a1ca0, reached
    // through slot 0x18, CheckPrerequisiteForUnits 0x14049bf10): 2 quests of the game
    // name one, so the check refuses them as the client does.
    Error(prerequisite.NoPrerequisiteRow(..)) ->
      Error(Refuse(prerequisite_unmet))
    Error(error) ->
      Error(Broken(PrerequisiteNotLoaded(id: quest.prerequisite_id, error:)))
    Ok(loaded) -> {
      let subject =
        prerequisite.Subject(
          ..prerequisite.of_wearer(
            factions: asker.factions,
            player: asker.player,
          ),
          quests: Some(asker.log),
        )
      case prerequisite.check(prerequisite: loaded, subject:) {
        prerequisite.Passes -> Ok(Nil)
        prerequisite.Fails -> Error(Refuse(prerequisite_unmet))
        prerequisite.NotRead(prerequisite_type:) ->
          Error(Unread(PrerequisiteType(prerequisite_type:)))
      }
    }
  }
}

/// Check 13: the path of a quest of one (0 to 3), which is the player's; any other
/// value of the unsigned column (-1 is 4294967295) means no path.
fn path(quest quest: Quest2, asker asker: Asker) -> Result(Nil, Stop) {
  let wanted = quest.sub_mission_path_type
  refuse_when(when: wanted < 4 && asker.player.path != wanted, code: wrong_path)
}

/// Check 15: a quest that is not a contract needs a place in the active list, which
/// holds GameFormula 655's dataint0 quests that are not contracts.
fn log_has_room(
  tables tables: table_store.Tables,
  quest quest: Quest2,
  asker asker: Asker,
) -> Result(Nil, Stop) {
  let limit = case
    game_formula.get(tables:, id: GameFormulaId(quest_limit_formula))
  {
    Ok(row) -> row.dataint0
    Error(Nil) -> default_quest_limit
  }
  refuse_when(
    when: !has_flag(quest.flags, contract_flag)
      && quest_log.active_count(log: asker.log, tables:) >= limit,
    code: log_full,
  )
}

/// Check 16: a quest with no repeat period passes. One with weight 0 joins no group
/// and is refused. Any other is in its group, which offers all its quests with no
/// limit on how many a player holds (passes) or draws some or limits the count (not
/// read).
fn periodic(
  tables tables: table_store.Tables,
  quest quest: Quest2,
) -> Result(Nil, Stop) {
  case quest.quest_repeat_period_enum {
    0 -> Ok(Nil)
    _ if quest.periodic_quest_weight == 0 -> Error(Refuse(periodic_refused))
    _ ->
      case periodic_group(tables:, quest:) {
        Error(error) -> Error(Broken(error))
        Ok(group) ->
          case
            group.periodic_quests_offered == all_offered
            && group.max_periodic_quests_allowed == all_offered
          {
            True -> Ok(Nil)
            False -> Error(Unread(PeriodicDraw(group_id: group.id)))
          }
      }
  }
}

/// The group a periodic quest joins: the one its periodicQuestGroupId names or, when
/// no group has that id (0 among them), the group with the lowest id at or above 1
/// (`0x1405a7c90`).
fn periodic_group(
  tables tables: table_store.Tables,
  quest quest: Quest2,
) -> Result(periodic_quest_group.PeriodicQuestGroup, CheckError) {
  case
    periodic_quest_group.get(
      tables:,
      id: PeriodicQuestGroupId(quest.periodic_quest_group_id),
    )
  {
    Ok(group) -> Ok(group)
    Error(Nil) ->
      case
        list.find(periodic_quest_group.all(tables), fn(group) { group.id >= 1 })
      {
        Ok(group) -> Ok(group)
        Error(Nil) ->
          Error(NoPeriodicGroupRow(group_id: quest.periodic_quest_group_id))
      }
  }
}

/// Check 17: a contract is held by the contracts manager, which the server does
/// not have.
fn contract(quest quest: Quest2) -> Result(Nil, Stop) {
  use <- bool.guard(
    when: has_flag(quest.flags, contract_flag),
    return: Error(Unread(Contract)),
  )
  Ok(Nil)
}

/// A sentence that says which row a check could not read, for the log.
fn describe(error error: CheckError) -> String {
  case error {
    PrerequisiteNotLoaded(id:, error:) ->
      equip_requirement.describe(error: equip_requirement.PrerequisiteNotLoaded(
        id:,
        error:,
      ))
    NoEpisodeRow(episode_id:) ->
      "the table Episode has no row " <> int.to_string(episode_id)
    NoPeriodicGroupRow(group_id:) ->
      "the table PeriodicQuestGroup has no row " <> int.to_string(group_id)
  }
}

/// A sentence that says what the server does not read, for the log.
pub fn describe_gap(gap gap: Gap) -> String {
  case gap {
    Reputation -> "the reputation a quest needs, which the server does not hold"
    PrerequisiteItemCounter ->
      "a prerequisite item in the per-item inventory counter, which the server does not read"
    PrerequisiteType(prerequisite_type:) ->
      "a prerequisite condition of type "
      <> int.to_string(prerequisite_type)
      <> ", which the server does not read"
    PeriodicDraw(group_id:) ->
      "the draw of periodic group "
      <> int.to_string(group_id)
      <> ", which the server does not read"
    Contract -> "a contract, which the contracts manager holds"
  }
}

/// What the rule asks the connection to do.
pub type Effect {
  /// Write a log line.
  Log(level: LogLevel, text: String)
  /// Write 0x035C: the quest's new state and the objective it is told of (0 for none).
  SendState(quest_id: Int, state: Int, objective_id: Int)
}

/// Why the message is refused: a body the client's own reader would refuse. The
/// connection ends.
pub type Refusal {
  NotDecoded(undecoded: Undecoded)
}

/// The effects of a message, the log after it and the reasons now logged on the
/// connection.
pub type Taken {
  Taken(effects: List(Effect), log: QuestLog, logged: Set(String))
}

/// Why a request is answered with nothing.
type Declined {
  UnknownQuest(quest_id: Int)
  BadQuestRow(quest_id: Int, error: quest_log.QuestRowError)
  NotBotched(quest_id: Int, state: Int)
  BotchedAccepted(quest_id: Int)
  NoSource(quest_id: Int)
  NotAccepted(quest_id: Int, code: Int)
  GapUnread(quest_id: Int, gap: Gap)
  Unchecked(quest_id: Int, error: CheckError)
  NotAbandonable(quest_id: Int, state: Int)
  CannotMention(quest_id: Int, state: Int, mentioned: Bool)
  NotInActiveList(quest_id: Int, state: Int)
  CannotIgnore(quest_id: Int, state: Int, ignored: Bool)
}

/// The two requests that start a quest.
type Start {
  Accepting
  Retrying
}

/// The lua QuestState of a quest held Mentioned, Abandoned and Ignored.
const mentioned_state = 5

const abandoned_state = 6

const ignored_state = 7

/// The place the dialog's accept sends (`opcode.0x35b`).
const dialog_location = 300

const dialog_bag_index = 0xFFFF_FFFF

/// What the player is at the moment of the request, which the rule reads.
pub type Standing =
  interaction.Player

/// What a message is answered with: 0x035C and the log changed, for a request the client
/// would send (a mention and a track send no answer); a log line, for one it would not; a
/// refusal for a body the client's reader refuses.
pub fn take(
  message message: Message,
  body body: BitArray,
  asker asker: Asker,
  standing standing: Standing,
  picture picture: Picture,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
  logged logged: Set(String),
) -> Result(Taken, Refusal) {
  let answered = fn(outcome) { answer(message:, outcome:, asker:, logged:) }
  // Both requests that start a quest answer 0x035C with state 1 and the log it left.
  let start_answered = fn(start, quest_id, place) {
    answered(
      started(
        start:,
        quest_id:,
        place:,
        asker:,
        standing:,
        picture:,
        tables:,
        now_ms:,
      )
      |> result.map(fn(log) {
        #([SendState(quest_id:, state: 1, objective_id: 0)], log)
      }),
    )
  }
  case message {
    Accept ->
      quest_accept.decode(body)
      |> client_connection.decoded(message_id: quest_accept.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(request) {
        start_answered(Accepting, request.quest_id, Some(request.item))
      })
    Retry ->
      quest_retry.decode(body)
      |> client_connection.decoded(message_id: quest_retry.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(request) {
        start_answered(Retrying, request.quest_id, option.None)
      })
    Abandon ->
      quest_abandon.decode(body)
      |> client_connection.decoded(message_id: quest_abandon.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(request) {
        answered(abandoned(quest_id: request.quest_id, asker:, tables:))
      })
    Mention ->
      quest_mention.decode(body)
      |> client_connection.decoded(message_id: quest_mention.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(request) {
        answered(mentioned_by(
          quest_id: request.quest_id,
          wish: request.mentioned == 1,
          asker:,
          tables:,
        ))
      })
    Track ->
      quest_track.decode(body)
      |> client_connection.decoded(message_id: quest_track.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(request) {
        answered(tracked_by(
          quest_id: request.quest_id,
          wish: request.tracked == 1,
          asker:,
        ))
      })
    Ignore ->
      quest_ignore.decode(body)
      |> client_connection.decoded(message_id: quest_ignore.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(request) {
        answered(ignored_by(
          quest_id: request.quest_id,
          wish: request.ignored == 1,
          asker:,
        ))
      })
  }
}

/// The effects and log of a request the client would send, or the log line of one it
/// would not.
fn answer(
  message message: Message,
  outcome outcome: Result(#(List(Effect), QuestLog), Declined),
  asker asker: Asker,
  logged logged: Set(String),
) -> Taken {
  case outcome {
    Ok(#(effects, log)) -> Taken(effects:, log:, logged:)
    Error(declined) -> {
      let #(line, logged) =
        log_once(
          key: reason_of(declined:),
          text: describe_declined(message:, declined:),
          logged:,
        )
      Taken(effects: [line], log: asker.log, logged:)
    }
  }
}

/// The quest as the client keeps it and its Quest2 row, or why the client has none.
fn read_quest(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> Result(#(quest_log.Quest, Quest2), Declined) {
  use quest <- result.try(
    quest_log.quest_of(tables:, id: quest_id)
    |> result.map_error(fn(error) {
      case error {
        quest_log.NoQuestRow -> UnknownQuest(quest_id:)
        quest_log.NoObjectiveRow(..) -> BadQuestRow(quest_id:, error:)
      }
    }),
  )
  let assert Ok(row) = quest2.get(tables:, id: Quest2Id(quest_id))
    as "a quest the client's rows read has its Quest2 row"
  Ok(#(quest, row))
}

/// Whether `CanAbandonQuest` (`0x140552930`) lets a quest in this state, with these
/// Quest2 flags, be abandoned.
fn can_abandon(state state: Int, flags flags: Int) -> Bool {
  case state, has_flag(flags, no_abandon_flag) {
    4, _ -> True
    _, True -> False
    2, False -> !has_flag(flags, kept_when_achieved_flag)
    1, False -> True
    _, False -> False
  }
}

/// The log with the quest abandoned and the answer, or why the client would not send it.
fn abandoned(
  quest_id quest_id: Int,
  asker asker: Asker,
  tables tables: table_store.Tables,
) -> Result(#(List(Effect), QuestLog), Declined) {
  use #(quest, row) <- result.try(read_quest(tables:, quest_id:))
  let state = quest_log.state(log: asker.log, quest:)
  case can_abandon(state:, flags: row.flags) {
    False -> Error(NotAbandonable(quest_id:, state:))
    True ->
      Ok(#(
        [SendState(quest_id:, state: abandoned_state, objective_id: 0)],
        quest_log.hold(log: asker.log, quest_id:, state: quest_log.Abandoned),
      ))
  }
}

/// The log with the quest held Mentioned, which the client keeps for a mention and a
/// withdrawal alike, or why the client would not send it. The client sends a mention
/// only for a quest it has no state for (`0x14043c1a0`), and a withdrawal only from the
/// communicator's refresh, which walks the quests with the communicator flag
/// (`0x1405fccb0`).
fn mentioned_by(
  quest_id quest_id: Int,
  wish wish: Bool,
  asker asker: Asker,
  tables tables: table_store.Tables,
) -> Result(#(List(Effect), QuestLog), Declined) {
  use #(_, row) <- result.try(read_quest(tables:, quest_id:))
  let state = state_of(asker:, quest_id:)
  let sent = case wish, state {
    True, 0 -> True
    False, 4 | False, 5 | False, 6 -> has_flag(row.flags, communicator_flag)
    _, _ -> False
  }
  case sent {
    True ->
      Ok(#(
        [],
        quest_log.hold(log: asker.log, quest_id:, state: quest_log.Mentioned),
      ))
    False -> Error(CannotMention(quest_id:, state:, mentioned: wish))
  }
}

/// The log with the tracked flag of a quest of the active list set, or why the client
/// would not send it.
fn tracked_by(
  quest_id quest_id: Int,
  wish wish: Bool,
  asker asker: Asker,
) -> Result(#(List(Effect), QuestLog), Declined) {
  let state = state_of(asker:, quest_id:)
  case state {
    1 | 2 ->
      Ok(#([], quest_log.track(log: asker.log, quest_id:, tracked: wish)))
    _ -> Error(NotInActiveList(quest_id:, state:))
  }
}

/// The log with the quest ignored, answered with state 7, or with it taken back to
/// Mentioned, answered with state 5, or why the client would not send it.
fn ignored_by(
  quest_id quest_id: Int,
  wish wish: Bool,
  asker asker: Asker,
) -> Result(#(List(Effect), QuestLog), Declined) {
  let state = state_of(asker:, quest_id:)
  case wish, state {
    True, 5 | True, 6 ->
      Ok(#(
        [SendState(quest_id:, state: ignored_state, objective_id: 0)],
        quest_log.hold(log: asker.log, quest_id:, state: quest_log.Ignored),
      ))
    False, 7 ->
      Ok(#(
        [SendState(quest_id:, state: mentioned_state, objective_id: 0)],
        quest_log.hold(log: asker.log, quest_id:, state: quest_log.Mentioned),
      ))
    _, _ -> Error(CannotIgnore(quest_id:, state:, ignored: wish))
  }
}

/// The log with the quest started, or why the request is answered with nothing.
fn started(
  start start: Start,
  quest_id quest_id: Int,
  place place: option.Option(item_place.ItemPlace),
  asker asker: Asker,
  standing standing: Standing,
  picture picture: Picture,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
) -> Result(QuestLog, Declined) {
  use #(quest, row) <- result.try(read_quest(tables:, quest_id:))
  let state = state_of(asker:, quest_id:)
  use Nil <- result.try(case start, state {
    Accepting, 4 -> Error(BotchedAccepted(quest_id:))
    Retrying, 4 | Accepting, _ -> Ok(Nil)
    Retrying, _ -> Error(NotBotched(quest_id:, state:))
  })
  use Nil <- result.try(
    bool.guard(
      when: !has_source(
        place:,
        quest: row,
        asker:,
        standing:,
        picture:,
        tables:,
        now_ms:,
      ),
      return: Error(NoSource(quest_id:)),
      otherwise: fn() { Ok(Nil) },
    ),
  )
  case can_accept(tables:, quest: row, asker:, mask: every_check) {
    Error(error) -> Error(Unchecked(quest_id:, error:))
    Ok(Refused(code:)) -> Error(NotAccepted(quest_id:, code:))
    Ok(NotRead(gap:)) -> Error(GapUnread(quest_id:, gap:))
    Ok(Acceptable) ->
      Ok(case start {
        Accepting ->
          quest_log.accept(
            log: asker.log,
            quest:,
            max_time_ms: row.max_time_allowed_ms,
            now_ms:,
          )
        Retrying ->
          quest_log.retry(
            log: asker.log,
            quest:,
            max_time_ms: row.max_time_allowed_ms,
            now_ms:,
          )
      })
  }
}

/// Whether the client could have started the quest from this place: a giver in reach
/// or a communicator call for the dialog, a held item for any other place, any of the
/// three for a retry, which carries no place.
fn has_source(
  place place: option.Option(item_place.ItemPlace),
  quest quest: Quest2,
  asker asker: Asker,
  standing standing: Standing,
  picture picture: Picture,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
) -> Bool {
  let dialog = fn() {
    giver_in_reach(quest:, standing:, picture:, tables:, now_ms:)
    || called(quest:, asker:)
  }
  let item = fn(held: HeldItem) { starts(item: held, quest:, tables:) }
  case place {
    option.None -> dialog() || list.any(asker.items, item)
    Some(item_place.ItemPlace(location:, bag_index:)) ->
      case location == dialog_location && bag_index == dialog_bag_index {
        True -> dialog()
        False ->
          list.any(asker.items, fn(held) {
            held.location == location
            && held.bag_index == bag_index
            && item(held)
          })
      }
  }
}

/// Whether the quest comes by the communicator and the log holds a state of 4 to 7
/// for it.
fn called(quest quest: Quest2, asker asker: Asker) -> Bool {
  has_flag(quest.flags, communicator_flag)
  && in_second_list(state: state_of(asker:, quest_id: quest.id))
}

/// Whether the held item starts the quest (Item2 `quest2IdActivation`).
fn starts(
  item item: HeldItem,
  quest quest: Quest2,
  tables tables: table_store.Tables,
) -> Bool {
  case item2.get(tables:, id: item.item2_id) {
    Ok(row) -> row.quest2_id_activation == quest.id
    Error(Nil) -> False
  }
}

/// Whether a shown creature the client would open a dialog with gives the quest: alive,
/// not Hostile to the player, within reach.
fn giver_in_reach(
  quest quest: Quest2,
  standing standing: Standing,
  picture picture: Picture,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
) -> Bool {
  list.any(dict.values(picture), fn(unit) {
    case unit {
      ShownCreature(
        creature_id:,
        path:,
        alive: True,
        hit_radius: creature_radius,
        hostile_to:,
        ..,
      ) ->
        !interaction.hostile_to_player(player: standing, hostile_to:)
        && case creature2.get(tables, creature_id) {
          Ok(row) ->
            list.contains(spawn.given_quest_ids(row), quest.id)
            && interaction.within_reach(
              player: standing,
              tables:,
              path:,
              creature_radius:,
              now_ms:,
            )
          Error(Nil) -> False
        }
      ShownCreature(alive: False, ..) | ShownPlayer | ShownObject(..) -> False
    }
  })
}

/// The reason of a declined request, one for each kind of reason.
fn reason_of(declined declined: Declined) -> String {
  case declined {
    UnknownQuest(..) -> "unknown quest"
    BadQuestRow(..) -> "quest row"
    NotBotched(..) -> "not botched"
    BotchedAccepted(..) -> "botched sent as an accept"
    NoSource(..) -> "no source"
    NotAccepted(code:, ..) -> "refused " <> int.to_string(code)
    GapUnread(gap:, ..) -> "not read " <> describe_gap(gap:)
    Unchecked(..) -> "unchecked"
    NotAbandonable(..) -> "not abandonable"
    CannotMention(mentioned: True, ..) -> "cannot be mentioned"
    CannotMention(mentioned: False, ..) -> "no mention to withdraw"
    NotInActiveList(..) -> "not in the active list"
    CannotIgnore(ignored: True, ..) -> "cannot be ignored"
    CannotIgnore(ignored: False, ..) -> "not ignored"
  }
}

/// A sentence that says why the request is answered with nothing, for the log.
fn describe_declined(
  message message: Message,
  declined declined: Declined,
) -> String {
  let request = case message {
    Accept -> "0x035B"
    Retry -> "0x0365"
    Abandon -> "0x035A"
    Mention -> "0x0360"
    Track -> "0x0364"
    Ignore -> "0x035E"
  }
  let of = fn(quest_id) { " names quest " <> int.to_string(quest_id) }
  let held = fn(state) {
    ", which the log holds in state " <> int.to_string(state)
  }
  case declined {
    NotAbandonable(quest_id:, state:) ->
      request
      <> of(quest_id)
      <> held(state)
      <> ", which the client's CanAbandonQuest refuses: the client would not have sent it"
    CannotMention(quest_id:, state:, mentioned:) ->
      request
      <> of(quest_id)
      <> held(state)
      <> case mentioned {
        True ->
          ", which the client mentions only for a quest it holds no state of: it would not have sent it"
        False ->
          ", which the client withdraws a mention of only for a quest with the communicator flag held botched, mentioned or abandoned: it would not have sent it"
      }
    NotInActiveList(quest_id:, state:) ->
      request
      <> of(quest_id)
      <> held(state)
      <> ", which is not in the active list the client tracks: it would not have sent it"
    CannotIgnore(quest_id:, state:, ignored:) ->
      request
      <> of(quest_id)
      <> held(state)
      <> case ignored {
        True ->
          ", which the client ignores only for an abandoned or mentioned quest: it would not have sent it"
        False ->
          ", which is not ignored: the client stops ignoring only an ignored quest, so it would not have sent it"
      }
    UnknownQuest(quest_id:) ->
      request
      <> of(quest_id)
      <> ", which the client has no Quest2 row for: nothing is answered"
    BadQuestRow(quest_id:, error:) ->
      request
      <> of(quest_id)
      <> ", whose rows are not whole: "
      <> case error {
        quest_log.NoQuestRow -> "no Quest2 row"
        quest_log.NoObjectiveRow(objective_id:) ->
          "the table QuestObjective has no row " <> int.to_string(objective_id)
      }
    NotBotched(quest_id:, state:) ->
      request
      <> of(quest_id)
      <> ", which the log holds in state "
      <> int.to_string(state)
      <> ", not botched: the client sends a retry only for a botched quest"
    BotchedAccepted(quest_id:) ->
      request
      <> of(quest_id)
      <> ", which the log holds botched: the client sends a botched quest only as 0x0365"
    NoSource(quest_id:) ->
      request
      <> of(quest_id)
      <> ", which no giver in reach, communicator call or held item starts: the client would not have sent it"
    NotAccepted(quest_id:, code:) ->
      request
      <> of(quest_id)
      <> ", which the client's check refuses with code "
      <> int.to_string(code)
      <> ": the client would not have sent it"
    GapUnread(quest_id:, gap:) ->
      request
      <> of(quest_id)
      <> ", which needs "
      <> describe_gap(gap:)
      <> " (#334): nothing is answered"
    Unchecked(quest_id:, error:) ->
      request
      <> of(quest_id)
      <> ", which cannot be checked: "
      <> describe(error:)
  }
}

/// The log line for a reason: a warning the first time the key is met on the
/// connection and a debug line after, with the keys met so far.
fn log_once(
  key key: String,
  text text: String,
  logged logged: Set(String),
) -> #(Effect, Set(String)) {
  let #(level, logged) = interaction.log_level(key:, logged:)
  #(Log(level:, text:), logged)
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe_refusal(refusal refusal: Refusal) -> String {
  let NotDecoded(undecoded:) = refusal
  client_connection.describe_undecoded(undecoded:)
}
