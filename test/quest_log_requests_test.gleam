//// A player's requests that change the quest log: to abandon a quest, 0x035A, to mention
//// or withdraw one, 0x0360, to track one, 0x0364, and to ignore or stop ignoring one,
//// 0x035E (`genesis_prime/game/quest`), and the dialog of a quest giver, 0x07EA of kind 37
//// (`genesis_prime/game/interaction`). Expected values come from these places, and never
//// from the helpers that build the input.
//// - `CanAbandonQuest` (`0x140552930`): a Botched quest (4) may always be abandoned;
////   otherwise Quest2 flags 0x4000 forbid it, and an Achieved quest (2) with flags
////   0x8000 may not be; past those the code takes only the states 1, 2 and 4 (it computes
////   `(state - 1) & ~3` and refuses a non-zero result, and refuses 3), so Mentioned (5),
////   Abandoned (6), Ignored (7), Completed (3) and a quest the log lacks (0) are refused.
//// - `opcode.0x35a`, `0x1405fbdc0`: the answer is 0x35C with state 6, and the client
////   keeps the state in its side list (a quest held Abandoned), where `0x140552490`
////   (CanAcceptQuest check 2) lets the quest be taken again.
//// - `opcode.0x360`, `0x1405fca00`: the client sets Mentioned (5) for both bits and keeps
////   the entry; it waits for no answer. A mention is sent only from `0x14043c1a0`, after
////   `GetQuestState == 0`, so for a quest the log lacks; a withdrawal only from the
////   communicator's refresh `0x1405fccb0`, which walks the quests with Quest2 flags 4 held
////   Botched (4), Mentioned (5) or Abandoned (6).
//// - `opcode.0x364`, `0x1405fcb80`: a tracked flag of a quest of the active list, no answer.
//// - `opcode.0x35e` and Jim's answer: the client sends it for Abandoned or Mentioned
////   quests (bit 1) and for Ignored ones (bit 0) and changes no state itself, so the
////   server answers 0x35C: state 7 for bit 1, state 5 (Mentioned) for bit 0.
//// - `0x1405a8d40` (marks the interaction kinds of a creature, `MarkQuestInteractionKinds`)
////   and `0x140555350`: the client sends the request of kind 37 only for a creature that
////   marks a kind with a click handler. For a quest the creature receives: Achieved (state
////   2), or Quest2 flags 1 with CanAcceptQuest passing, or Accepted (1). For a quest it
////   gives, when Quest2 flags lack 0x800: Accepted or Achieved, or CanAcceptQuest with the
////   mask 0xffffdfff passing; a quest refused within 5 levels marks kinds 91 to 93, which
////   have no handler, and a given quest with flags 0x800 marks kind 12 (ActivateUnit).
////   The server does not read every check (`NotRead`), and a gap opens the dialog.
//// - The quests used here are rows of the committed fixture (`roots.tsv`): 1806 has no
////   flags and one objective (1891); 1805 has flags 0x28000 and two objectives (1890,
////   6807, flags 0); 10528 has flags 0x4000, five objectives and needs 10520 completed;
////   10520 has flags 0x4404 and needs 10519 completed; 1872 has flags 0x404; 2417 has
////   flags 8, no objective, and starts from Item2 4861. Dorian Walker (Creature2 74812)
////   gives 10528 and receives 10520.

import character_tables
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/game/interaction
import genesis_prime/game/prerequisite.{Factions}
import genesis_prime/game/quest.{
  type Asker, type Taken, Acceptable, Asker, SendState,
}
import genesis_prime/game/quest_log
import genesis_prime/game/shown
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/quest_abandon.{QuestAbandon}
import genesis_prime/message/quest_accept.{QuestAccept}
import genesis_prime/message/quest_ignore.{QuestIgnore}
import genesis_prime/message/quest_mention.{QuestMention}
import genesis_prime/message/quest_track.{QuestTrack}
import genesis_prime/step.{LogDebug, LogWarning}
import genesis_prime/store.{type HeldItem, type QuestRow, HeldItem}
import genesis_prime/table/id.{Item2Id, Quest2Id, RaceId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import gleam/dict
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import prerequisite_support
import quest_support
import vendor_support

const exile = 167

fn tables() -> table_store.Tables {
  character_tables.shared()
}

/// A level 20 Exile of race 3, class 5 and path 1 whose log holds these rows.
fn asker(log log: List(QuestRow)) -> Asker {
  Asker(
    player: prerequisite_support.player(),
    factions: Factions(current: exile, base: exile),
    log: quest_support.log_of(rows: log),
    items: [],
  )
}

fn standing() -> interaction.Player {
  interaction.Player(
    race_id: RaceId(3),
    faction: shown.Exile,
    place: connection_support.entry_place(),
  )
}

fn item(location location: Int) -> HeldItem {
  HeldItem(
    item_guid: 1,
    item2_id: Item2Id(4861),
    location:,
    bag_index: 0,
    stack_count: 1,
  )
}

/// The request's answer and log for a body, over no picture.
fn took(
  message message: quest.Message,
  body body: BitArray,
  asker asker: Asker,
) -> Taken {
  let assert Ok(taken) =
    quest.take(
      message:,
      body:,
      asker:,
      standing: standing(),
      picture: dict.new(),
      tables: tables(),
      now_ms: 0,
      logged: set.new(),
    )
    as "the body is one the client's reader takes"
  taken
}

/// A request that is answered with nothing: one warning line naming the quest, and the
/// log as it was.
fn assert_declined(
  taken taken: Taken,
  what what: String,
  quest quest_id: Int,
  log log: QuestLog,
) -> Nil {
  let assert [quest.Log(level: LogWarning, text:)] = taken.effects
    as { what <> " is logged and answered with nothing" }
  assert string.contains(text, "quest " <> int.to_string(quest_id))
    as { what <> ": the line names the quest" }
  assert quest_log.rows(log: taken.log, now_ms: 0)
    == quest_log.rows(log:, now_ms: 0)
    as { what <> " leaves the log as it was" }
  Nil
}

type QuestLog =
  quest_log.QuestLog

fn abandon_body(quest_id quest_id: Int) -> BitArray {
  let assert Ok(body) = quest_abandon.encode(QuestAbandon(quest_id:))
    as "the request fits its fields"
  body
}

fn mention_body(quest_id quest_id: Int, mentioned mentioned: Int) -> BitArray {
  let assert Ok(body) =
    quest_mention.encode(QuestMention(quest_id:, mentioned:))
    as "the request fits its fields"
  body
}

fn track_body(quest_id quest_id: Int, tracked tracked: Int) -> BitArray {
  let assert Ok(body) = quest_track.encode(QuestTrack(quest_id:, tracked:))
    as "the request fits its fields"
  body
}

fn ignore_body(quest_id quest_id: Int, ignored ignored: Int) -> BitArray {
  let assert Ok(body) = quest_ignore.encode(QuestIgnore(quest_id:, ignored:))
    as "the request fits its fields"
  body
}

/// A quest held accepted with these progress values, untracked.
fn accepted(quest_id: Int, progress progress: List(Int)) -> QuestRow {
  quest_support.accepted(quest_id:, progress:)
}

/// A quest held in the active list in this state, with these objectives done.
fn active(
  quest_id quest_id: Int,
  state state: Int,
  done_mask done_mask: Int,
  progress progress: List(Int),
  tracked tracked: Bool,
) -> QuestRow {
  quest_support.active(
    quest_id:,
    state:,
    placeholder: 0,
    tracked:,
    done_mask:,
    progress:,
  )
}

pub fn abandon_follows_the_client_rule_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each case: what it is, the quest, the row the log holds of it (none for a quest the
  // log lacks) and whether `CanAbandonQuest` (`0x140552930`) allows it.
  let cases = [
    #(
      "an Accepted quest with no flag",
      1806,
      [accepted(1806, progress: [0])],
      True,
    ),
    #(
      "an Achieved quest with no flag",
      1806,
      [
        active(
          quest_id: 1806,
          state: 2,
          done_mask: 1,
          progress: [4],
          tracked: False,
        ),
      ],
      True,
    ),
    #(
      "a Botched quest with no flag",
      1806,
      [quest_support.known(1806, 4)],
      True,
    ),
    #(
      "a Botched quest with flags 0x4000, which a Botched quest may always abandon",
      10_528,
      [quest_support.known(10_528, 4)],
      True,
    ),
    #(
      "a Botched quest with flags 0x8000",
      1805,
      [quest_support.known(1805, 4)],
      True,
    ),
    #(
      "an Accepted quest with flags 0x8000 whose objectives are open: only an Achieved one is held back",
      1805,
      [accepted(1805, progress: [0, 0])],
      True,
    ),
    #(
      "an Accepted quest with flags 0x4000",
      10_528,
      [accepted(10_528, progress: [0, 0, 0, 0, 0])],
      False,
    ),
    #(
      "an Achieved quest with flags 0x4000",
      10_528,
      [
        active(
          quest_id: 10_528,
          state: 2,
          done_mask: 31,
          progress: [1, 1, 1, 1, 1],
          tracked: False,
        ),
      ],
      False,
    ),
    #(
      "an Achieved quest with flags 0x8000",
      1805,
      [
        active(
          quest_id: 1805,
          state: 2,
          done_mask: 3,
          progress: [2, 3],
          tracked: False,
        ),
      ],
      False,
    ),
    #(
      "an Accepted quest with flags 0x8000 whose objectives are all done, which the client reads as Achieved",
      1805,
      [
        active(
          quest_id: 1805,
          state: 1,
          done_mask: 3,
          progress: [2, 3],
          tracked: False,
        ),
      ],
      False,
    ),
    #("a quest the log lacks", 1806, [], False),
    #(
      "a Completed quest",
      1806,
      [quest_support.completed(1806, at: 1000)],
      False,
    ),
    #("a Mentioned quest", 1806, [quest_support.known(1806, 5)], False),
    #("an Abandoned quest", 1806, [quest_support.known(1806, 6)], False),
    #("an Ignored quest", 1806, [quest_support.known(1806, 7)], False),
  ]
  use #(what, quest_id, rows, allowed) <- list.each(cases)
  let held = asker(log: rows)
  let taken =
    took(message: quest.Abandon, body: abandon_body(quest_id:), asker: held)
  case allowed {
    True -> {
      assert taken.effects == [SendState(quest_id:, state: 6, objective_id: 0)]
        as { what <> " is answered with 0x35C state 6 (opcode.0x35a)" }
      assert taken.logged == set.new() as { what <> " logs nothing" }
    }
    False -> assert_declined(taken:, what:, quest: quest_id, log: held.log)
  }
}

pub fn abandon_keeps_the_quest_abandoned_and_acceptable_test() -> Nil {
  use <- owned_test.run(10_000)
  let started = quest_support.accepted(quest_id: 2417, progress: [])
  let held = Asker(..asker(log: [started]), items: [item(location: 1)])
  let target = fn(asker: Asker) {
    let assert Ok(row) = quest2.get(tables: tables(), id: Quest2Id(2417))
      as "the fixture holds quest 2417"
    let assert Ok(verdict) =
      quest.can_accept(
        tables: tables(),
        quest: row,
        asker:,
        mask: quest.every_check,
      )
      as "the fixture holds every row the checks read"
    verdict
  }
  assert target(held) == quest.Refused(code: 2)
    as "0x140552490: a quest in the active list is already held, code 2"
  let abandoned =
    took(
      message: quest.Abandon,
      body: abandon_body(quest_id: 2417),
      asker: held,
    )
  assert abandoned.effects
    == [SendState(quest_id: 2417, state: 6, objective_id: 0)]
    as "opcode.0x35a: the answer is 0x35C {quest 2417, state 6, objective 0}"
  assert quest_log.rows(log: abandoned.log, now_ms: 0)
    == [quest_support.known(2417, 6)]
    as "0x1405fbdc0: state 6 is kept in the side list, with no active entry"
  let again = Asker(..held, log: abandoned.log)
  assert target(again) == Acceptable
    as "0x140552490: a quest held in the side list in any state passes check 2"
  let accepted_again =
    took(
      message: quest.Accept,
      body: accept_body(location: 1, bag_index: 0, quest_id: 2417),
      asker: again,
    )
  assert accepted_again.effects
    == [SendState(quest_id: 2417, state: 1, objective_id: 0)]
    as "the abandoned quest is taken again from the item it starts from"
  assert quest_log.state(
      log: accepted_again.log,
      quest: quest_log.Quest(id: 2417, objectives: []),
    )
    == 2
    as "a quest with no objective is achieved at once (0x1405fbc40), so the entry is the active one"
}

fn accept_body(
  location location: Int,
  bag_index bag_index: Int,
  quest_id quest_id: Int,
) -> BitArray {
  let assert Ok(body) =
    quest_accept.encode(QuestAccept(
      item: ItemPlace(location:, bag_index:),
      quest_id:,
    ))
    as "the request fits its fields"
  body
}

pub fn mention_stores_mentioned_for_both_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  let mentioned = [quest_support.known(1872, 5)]
  // Each case: what it is, the bit, the rows the log holds, and the rows after it.
  let taken = [
    #("a mention of a quest the log lacks", 1, [], mentioned),
    #("a withdrawal of a Mentioned quest", 0, mentioned, mentioned),
    #(
      "a withdrawal of a Botched quest",
      0,
      [quest_support.known(1872, 4)],
      mentioned,
    ),
    #(
      "a withdrawal of an Abandoned quest",
      0,
      [quest_support.known(1872, 6)],
      mentioned,
    ),
  ]
  use #(what, bit, rows, after) <- list.each(taken)
  let result =
    took(
      message: quest.Mention,
      body: mention_body(quest_id: 1872, mentioned: bit),
      asker: asker(log: rows),
    )
  assert result.effects == [] as { what <> " sends no answer (opcode.0x360)" }
  assert quest_log.rows(log: result.log, now_ms: 0) == after
    as { what <> " leaves the quest Mentioned in the log, never removed" }
  // The requests the client would not send: a mention of a quest it holds a state of, a
  // withdrawal of one it holds none of, holds Ignored or in the active list, and a
  // withdrawal of a quest without Quest2 flags 4 (1806 has none), whatever its state.
  let refused = [
    #("a mention of an Ignored quest", 1, [quest_support.known(1872, 7)]),
    #("a mention of a Mentioned quest", 1, [quest_support.known(1872, 5)]),
    #("a mention of a Botched quest", 1, [quest_support.known(1872, 4)]),
    #("a mention of an Accepted quest", 1, [accepted(1872, progress: [])]),
    #("a mention of a Completed quest", 1, [
      quest_support.completed(1872, at: 1000),
    ]),
    #("a withdrawal of a quest the log lacks", 0, []),
    #("a withdrawal of an Ignored quest", 0, [quest_support.known(1872, 7)]),
    #("a withdrawal of an Accepted quest", 0, [accepted(1872, progress: [])]),
  ]
  use #(what, bit, rows) <- list.each(refused)
  let held = asker(log: rows)
  let result =
    took(
      message: quest.Mention,
      body: mention_body(quest_id: 1872, mentioned: bit),
      asker: held,
    )
  assert_declined(taken: result, what:, quest: 1872, log: held.log)
}

pub fn withdrawal_is_taken_only_for_a_quest_with_the_communicator_flag_test() -> Nil {
  use <- owned_test.run(10_000)
  // The communicator's refresh (`0x1405fccb0`) walks the quests with Quest2 flags 4, so a
  // withdrawal of a quest without them is one the client does not send, in every state
  // it withdraws from. 1806 has no flags.
  let states = [
    #("Botched", 4),
    #("Mentioned", 5),
    #("Abandoned", 6),
  ]
  use #(name, state) <- list.each(states)
  let held = asker(log: [quest_support.known(1806, state)])
  let result =
    took(
      message: quest.Mention,
      body: mention_body(quest_id: 1806, mentioned: 0),
      asker: held,
    )
  assert_declined(
    taken: result,
    what: "a withdrawal of a " <> name <> " quest without flags 4",
    quest: 1806,
    log: held.log,
  )
}

pub fn track_sets_the_tracked_flag_without_an_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each case: what it is, the bit and the row the log holds, and the row after it.
  let accepted_row = fn(tracked) {
    active(quest_id: 1806, state: 1, done_mask: 0, progress: [0], tracked:)
  }
  let achieved_row = fn(tracked) {
    active(quest_id: 1806, state: 2, done_mask: 1, progress: [4], tracked:)
  }
  let cases = [
    #(
      "tracking an untracked Accepted quest",
      1,
      accepted_row(False),
      accepted_row(True),
    ),
    #(
      "untracking a tracked Accepted quest",
      0,
      accepted_row(True),
      accepted_row(False),
    ),
    #(
      "tracking a tracked Accepted quest",
      1,
      accepted_row(True),
      accepted_row(True),
    ),
    #(
      "untracking an untracked Accepted quest",
      0,
      accepted_row(False),
      accepted_row(False),
    ),
    #("tracking an Achieved quest", 1, achieved_row(False), achieved_row(True)),
    #(
      "untracking an Achieved quest",
      0,
      achieved_row(True),
      achieved_row(False),
    ),
  ]
  use #(what, bit, row, after) <- list.each(cases)
  let result =
    took(
      message: quest.Track,
      body: track_body(quest_id: 1806, tracked: bit),
      asker: asker(log: [row]),
    )
  assert result.effects == [] as { what <> " sends no answer (opcode.0x364)" }
  assert quest_log.rows(log: result.log, now_ms: 0) == [after]
    as { what <> " changes the tracked flag of the entry and nothing else" }
  // A quest outside the active list has no tracker entry for the client to flip.
  let outside = [
    #("a quest the log lacks", []),
    #("a Botched quest", [quest_support.known(1806, 4)]),
    #("a Completed quest", [quest_support.completed(1806, at: 1000)]),
  ]
  use #(what, rows) <- list.each(outside)
  let held = asker(log: rows)
  assert_declined(
    taken: took(
      message: quest.Track,
      body: track_body(quest_id: 1806, tracked: 1),
      asker: held,
    ),
    what:,
    quest: 1806,
    log: held.log,
  )
}

pub fn ignore_answers_ignored_and_stop_ignoring_answers_mentioned_test() -> Nil {
  use <- owned_test.run(10_000)
  // Each case: what it is, the bit, the row the log holds, the state of the answer.
  let answered = [
    #("ignoring an Abandoned quest", 1, quest_support.known(1806, 6), 7),
    #("ignoring a Mentioned quest", 1, quest_support.known(1806, 5), 7),
    #("stopping to ignore an Ignored quest", 0, quest_support.known(1806, 7), 5),
  ]
  use #(what, bit, row, state) <- list.each(answered)
  let result =
    took(
      message: quest.Ignore,
      body: ignore_body(quest_id: 1806, ignored: bit),
      asker: asker(log: [row]),
    )
  assert result.effects == [SendState(quest_id: 1806, state:, objective_id: 0)]
    as {
      what
      <> " is answered with 0x35C of state "
      <> int.to_string(state)
      <> " (opcode.0x35e)"
    }
  assert quest_log.rows(log: result.log, now_ms: 0)
    == [quest_support.known(1806, state)]
    as { what <> " leaves the quest held in that state" }
  // The states the client's UI does not offer the toggle for.
  let refused = [
    #("ignoring an Accepted quest", 1, [accepted(1806, progress: [0])]),
    #("ignoring a Botched quest", 1, [quest_support.known(1806, 4)]),
    #("ignoring an Ignored quest", 1, [quest_support.known(1806, 7)]),
    #("ignoring a Completed quest", 1, [quest_support.completed(1806, at: 1000)]),
    #("ignoring a quest the log lacks", 1, []),
    #("stopping to ignore a Mentioned quest", 0, [quest_support.known(1806, 5)]),
    #("stopping to ignore an Abandoned quest", 0, [quest_support.known(1806, 6)]),
    #("stopping to ignore a quest the log lacks", 0, []),
  ]
  use #(what, bit, rows) <- list.each(refused)
  let held = asker(log: rows)
  assert_declined(
    taken: took(
      message: quest.Ignore,
      body: ignore_body(quest_id: 1806, ignored: bit),
      asker: held,
    ),
    what:,
    quest: 1806,
    log: held.log,
  )
}

/// The result of a request to talk to Dorian Walker (unit 40, 1.0 from the player's edge)
/// by a player whose log holds these rows, over these tables.
fn talked_to_walker(
  tables tables: table_store.Tables,
  rows rows: List(QuestRow),
) -> interaction.Taken {
  talked_to_walker_again(tables:, rows:, logged: set.new())
}

/// `talked_to_walker` for a connection that has logged these reasons already.
fn talked_to_walker_again(
  tables tables: table_store.Tables,
  rows rows: List(QuestRow),
  logged logged: set.Set(String),
) -> interaction.Taken {
  let held = asker(log: rows)
  let assert Ok(body) =
    interaction_request.encode(InteractionRequest(unit_id: 40, kind: 37))
    as "a unit id and a 7-bit kind fit the message"
  let assert Ok(taken) =
    interaction.take(
      message: interaction.Requested,
      body:,
      player: standing(),
      picture: vendor_support.picture_with_walker(gap: 1.0),
      tables:,
      vendors: vendor_support.stocking(creature_ids: []),
      now_ms: 0,
      offers: fn(creature) { quest.offers(tables:, asker: held, creature:) },
      talk_targets: set.new(),
      logged:,
    )
    as "the body is one the client's reader takes"
  taken
}

fn assert_opens(taken: interaction.Taken, what what: String) -> Nil {
  assert taken.effects == [interaction.OpenDialog(unit_id: 40)]
    as { what <> " opens the dialog with 0x357 (opcode.0x357)" }
}

fn assert_nothing_offered(taken: interaction.Taken, what what: String) -> Nil {
  let assert [interaction.Log(level: LogWarning, text:)] = taken.effects
    as { what <> " is logged and unanswered" }
  assert string.contains(text, "unit 40") as { what <> " names the unit" }
  assert string.contains(text, "no quest to show")
    as { what <> " says why: nothing is offered" }
}

pub fn giver_dialog_opens_only_for_a_creature_with_a_quest_to_show_test() -> Nil {
  use <- owned_test.run(60_000)
  let walker = fn(rows) { talked_to_walker(tables: tables(), rows:) }
  let done = quest_support.completed(10_520, at: 1000)
  // 10528 is refused for its prerequisite quest (code 8) within 5 levels, which marks
  // kinds 91 to 93, and 10520 is neither held nor flagged 1: nothing to show.
  assert_nothing_offered(
    walker([]),
    what: "a giver whose only quest is held back by a prerequisite (kinds 91 to 93)",
  )
  assert_opens(
    walker([done]),
    what: "a giver whose quest 10528 the player may accept",
  )
  assert_opens(
    walker([accepted(10_520, progress: [0, 0, 0, 0, 0])]),
    what: "a creature that receives quest 10520, which the player holds Accepted",
  )
  assert_opens(
    walker([
      active(
        quest_id: 10_520,
        state: 2,
        done_mask: 31,
        progress: [1, 1, 1, 1, 1],
        tracked: True,
      ),
    ]),
    what: "a creature that receives quest 10520, which the player holds Achieved",
  )
  assert_opens(
    walker([accepted(10_528, progress: [0, 0, 0, 0, 0])]),
    what: "a giver whose quest 10528 the player holds Accepted, which no accept check passes",
  )
  // A gap is not a refusal: with the prerequisite quest and the flag 0x4000 kept but a
  // contract flag (0x80000, `NotRead`) the server cannot decide the checks.
  use tables <- fixture_tables.changed(table: "Quest2", id: 10_528, with: [
    #("preq_quest0", Integer(0)),
    #("flags", Integer(0x84000)),
  ])
  assert_opens(
    talked_to_walker(tables:, rows: []),
    what: "a giver whose quest the server cannot decide (a contract, NotRead)",
  )
  // 0x800 marks QuestInstant (kind 12), whose handler is ActivateUnit: no dialog.
  {
    use tables <- fixture_tables.changed(table: "Quest2", id: 10_528, with: [
      #("flags", Integer(0x4800)),
    ])
    assert_nothing_offered(
      talked_to_walker(tables:, rows: [done]),
      what: "a given quest with flags 0x800, which is acceptable",
    )
  }
  // Flags 1 on a received quest marks QuestReward (11) once the player may accept it.
  use tables <- fixture_tables.changed(table: "Quest2", id: 10_520, with: [
    #("flags", Integer(0x4001)),
  ])
  assert_nothing_offered(
    talked_to_walker(tables:, rows: []),
    what: "a received quest with flags 1 whose prerequisite quest 10519 is not completed",
  )
  use tables <- fixture_tables.changed(table: "Quest2", id: 10_520, with: [
    #("flags", Integer(0x4001)),
    #("preq_quest0", Integer(0)),
  ])
  assert_opens(
    talked_to_walker(tables:, rows: []),
    what: "a received quest with flags 1 that passes CanAcceptQuest",
  )
}

pub fn a_giver_quest_without_a_quest2_row_is_not_shown_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client marks nothing for a quest it has no Quest2 row for (`0x1405a8d40` reads
  // the row before any mark), so Dorian Walker with 10528 swapped for 999999, which no
  // Quest2 row has, and 10520 neither held nor flagged 1 has no quest to show, though
  // the player has completed 10520 for the quest that is gone.
  use tables <- fixture_tables.changed(table: "Creature2", id: 74_812, with: [
    #("questIdGiven00", Integer(999_999)),
  ])
  assert_nothing_offered(
    talked_to_walker(tables:, rows: [quest_support.completed(10_520, at: 1000)]),
    what: "a giver whose only given quest has no Quest2 row",
  )
}

pub fn a_check_that_cannot_run_is_logged_once_and_shows_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // Walker is given quest 5259 in place of 10528. The player holds it Mentioned, so its
  // check 11 passes and check 10 reads the Episode row 411, which is removed: the check
  // cannot run. The quest counts as not shown, and the cause is logged once.
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Creature2",
      id: 74_812,
      with: [#("questIdGiven00", Integer(5259))],
    )
    as "Creature2 74812 and its column are in the fixture"
  let assert Ok(rows) = fixture_tables.remove(rows:, table: "Episode", id: 411)
    as "Episode 411 is in the fixture"
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let held = [quest_support.known(5259, 5)]
  let first = talked_to_walker(tables:, rows: held)
  let assert [interaction.Log(level: LogWarning, text:)] = first.effects
    as "an undecidable quest is logged and unanswered"
  assert string.contains(text, "unit 40") as "the line names the unit"
  assert string.contains(text, "quest 5259") as "the line names the quest"
  assert string.contains(text, "the table Episode has no row 411")
    as "the line says which row is missing"
  let second = talked_to_walker_again(tables:, rows: held, logged: first.logged)
  let assert [interaction.Log(level: LogDebug, ..)] = second.effects
    as "the second request of the reason is a debug line, so it is logged once"
  Nil
}
