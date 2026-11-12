//// A request to talk to a creature that only a quest objective names
//// (`genesis_prime/game/interaction` with the targets `genesis_prime/game/objective`
//// reads from the log). Expected values come from these places.
//// - `0x140479560.quest_kinds` and `0x140553110`: the client marks a unit with the
////   talk kind (37) while an objective of type 3 of a quest in its log names the
////   unit's Creature2 id and is neither done nor unreachable, whether or not the
////   creature has a quest of its own, so the client sends the request for it.
//// - `opcode.0x357`: the dialog opens when the server answers with 0x357 alone; a
////   creature that offers a quest and is a target opens once.
//// - `opcode.0x7ea` and `0x1403ad690`: the request is answered within 9.0 of the
////   creature's edge, and any creature the client would not mark is declined and
////   logged, as before this change.
////
//// The client's rows in the fixture: quest 3668's objective 0 (4744) is type 3 for
//// Creature2 12484 (Scientist Lusk), whose row gives and receives no quest; quest 9428
//// has objective 17988 (type 3, creature 59216, flags 3) and 17989 (type 12, creature
//// 58487, flags 3, which waits for the objective before it). No real row has an
//// unreachable type 3 objective for a creature in the fixture, so that case changes 17989
//// to type 3 (`QuestObjective.type`), a talk to a creature that waits for the
//// objective before it.
////
//// A Simple unit (world spawn type 10, shown as an object) is clicked the same way: the
//// client's `0x14047a060` (the kinds a unit offers) and `0x1403add00` (the request's
//// check) read the unit's life, disposition and range and never its unit type, and
//// `opcode.0x262.simple` creates a type 10 unit alive. The rows used: Creature2 73422
//// (faction 219) is the TargetGroup 14368 creature of quest 10525's type 18 objective 1,
//// and Creature2 73604 (faction 171) is the creature of quest 10528's type 3 objective 21326.

import character_tables
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/game/interaction.{Closes, Offered, OpenDialog, TalkedTo}
import genesis_prime/game/objective
import genesis_prime/game/quest_log
import genesis_prime/game/shown
import genesis_prime/game/start_place
import genesis_prime/game/target_group
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/step.{LogWarning}
import genesis_prime/store.{type QuestRow}
import genesis_prime/table/creature2
import genesis_prime/table/id
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_life.{Attackable, Hostile}
import genesis_prime/world_map/creature_path
import gleam/dict
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import quest_support
import simple_unit_support
import vendor_support

const talk_target = 12_484

const unit = 40

/// The unit the player talked to, as the client's group test reads it: the creature, the
/// Faction2 its 0x262 gave it (the picture here gives 0) and the UnitRace of its row.
fn unit_of(
  tables tables: table_store.Tables,
  creature creature: Int,
) -> target_group.Unit {
  let assert Ok(row) = creature2.get(tables, id.Creature2Id(creature))
    as "the fixture holds the creature's row"
  target_group.Unit(
    creature_id: id.Creature2Id(creature),
    faction_id: id.Faction2Id(0),
    unit_race_id: creature2.unit_race_id(row),
  )
}

/// The edge gap a request is answered up to (`opcode.0x7ea`).
const reach = 9.0

/// The hit radius the picture gives the creature; the gap is worked from it.
const creature_radius = 1.0

/// The creature as unit 40 in a picture, `gap` from the player's edge straight ahead of
/// the player at the entry place.
fn picture_with(creature_id creature_id: Int, gap gap: Float) -> shown.Picture {
  let entry = connection_support.entry_place()
  let place =
    start_place.moved(
      place: entry,
      x: start_place.x(entry),
      y: start_place.y(entry),
      z: start_place.z(entry)
        -. { gap +. vendor_support.player_radius +. creature_radius },
    )
  dict.from_list([
    #(
      unit,
      shown.ShownCreature(
        creature_id: id.Creature2Id(creature_id),
        faction_id: 0,
        checklist_index: 0,
        path: creature_path.Standing(at: place),
        life: 4,
        alive: True,
        hit_radius: creature_radius,
        attackable: Attackable(exile: False, dominion: False),
        hostile_to: Hostile(exile: False, dominion: False),
        in_combat: False,
      ),
    ),
  ])
}

/// What the rule answers a request to talk to unit 40 with, for a player whose log holds
/// these rows, whose picture shows this creature `gap` away, and whose creature's row
/// offers `offer`.
fn taken_for(
  tables tables: table_store.Tables,
  rows rows: List(QuestRow),
  creature_id creature_id: Int,
  gap gap: Float,
  offer offer: interaction.Offer,
) -> interaction.Taken {
  taken_in(
    tables:,
    log: quest_support.log_of(rows:),
    picture: picture_with(creature_id:, gap:),
    offer:,
  )
}

/// The same for a log and a picture as they are.
fn taken_in(
  tables tables: table_store.Tables,
  log log: quest_log.QuestLog,
  picture picture: shown.Picture,
  offer offer: interaction.Offer,
) -> interaction.Taken {
  let assert Ok(body) =
    interaction_request.encode(InteractionRequest(unit_id: unit, kind: 37))
    as "a unit id and a 7-bit kind fit the message"
  let assert Ok(taken) =
    interaction.take(
      message: interaction.Requested,
      body:,
      player: interaction.Player(
        race_id: id.RaceId(3),
        faction: shown.Exile,
        place: connection_support.entry_place(),
      ),
      picture:,
      tables:,
      vendors: vendor_support.stocking(creature_ids: []),
      now_ms: 0,
      offers: fn(_) { offer },
      talk_targets: objective.talk_targets(log:, tables:),
      logged: set.new(),
    )
    as "the body is one the client's reader takes"
  taken
}

fn assert_declined(
  taken taken: interaction.Taken,
  words words: String,
  what what: String,
) -> Nil {
  let assert [interaction.Log(level: LogWarning, text:)] = taken.effects
    as { what <> " is logged and unanswered, and counts no talk" }
  assert string.contains(text, words) as { what <> " says why: " <> words }
}

pub fn a_type_3_target_opens_its_dialog_and_counts_the_talk_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let open = [quest_support.accepted(quest_id: 3668, progress: [0, 0, 0])]

  let target =
    taken_for(
      tables:,
      rows: open,
      creature_id: talk_target,
      gap: 1.0,
      offer: interaction.NothingToOffer,
    )
  assert target.effects
    == [
      OpenDialog(unit_id: unit),
      TalkedTo(
        target: unit_of(tables:, creature: talk_target),
        checklist_index: 0,
      ),
    ]
    as "a creature with no quest of its own, named by an open type 3 objective, gets 0x357 and then counts the talk (0x140553110, opcode.0x357)"
  assert target.window == Closes
    as "the talk closes a vendor window as any request to talk does"

  let offering =
    taken_for(
      tables:,
      rows: open,
      creature_id: talk_target,
      gap: 1.0,
      offer: Offered,
    )
  assert offering.effects
    == [
      OpenDialog(unit_id: unit),
      TalkedTo(
        target: unit_of(tables:, creature: talk_target),
        checklist_index: 0,
      ),
    ]
    as "a creature that also offers a quest opens its dialog once and counts the talk"

  let edge =
    taken_for(
      tables:,
      rows: open,
      creature_id: talk_target,
      gap: reach -. 0.1,
      offer: interaction.NothingToOffer,
    )
  assert edge.effects
    == [
      OpenDialog(unit_id: unit),
      TalkedTo(
        target: unit_of(tables:, creature: talk_target),
        checklist_index: 0,
      ),
    ]
    as "a target within 6.0 + 3.0 is answered"

  assert_declined(
    taken: taken_for(
      tables:,
      rows: [],
      creature_id: talk_target,
      gap: 1.0,
      offer: interaction.NothingToOffer,
    ),
    words: "no quest",
    what: "a creature no logged objective names",
  )
  assert_declined(
    taken: taken_for(
      tables:,
      rows: [
        quest_support.active(
          quest_id: 3668,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: 0b1,
          progress: [1, 0, 0],
        ),
      ],
      creature_id: talk_target,
      gap: 1.0,
      offer: interaction.NothingToOffer,
    ),
    words: "no quest",
    what: "a creature whose objective is done",
  )
  assert_declined(
    taken: taken_for(
      tables:,
      rows: [quest_support.completed(quest_id: 3668, at: 1000)],
      creature_id: talk_target,
      gap: 1.0,
      offer: interaction.NothingToOffer,
    ),
    words: "no quest",
    what: "a creature whose quest is completed",
  )
  assert_declined(
    taken: taken_for(
      tables:,
      rows: open,
      creature_id: talk_target,
      gap: reach +. 0.1,
      offer: interaction.NothingToOffer,
    ),
    words: "too far",
    what: "a target beyond the reach",
  )

  // 17989 becomes a type 3 objective for creature 58487, flags 3: it waits for 17988.
  use tables <- fixture_tables.changed(
    table: "QuestObjective",
    id: 17_989,
    with: [#("type", Integer(3))],
  )
  let waiting = [quest_support.accepted(quest_id: 9428, progress: [0, 0])]
  assert_declined(
    taken: taken_for(
      tables:,
      rows: waiting,
      creature_id: 58_487,
      gap: 1.0,
      offer: interaction.NothingToOffer,
    ),
    words: "no quest",
    what: "a creature whose objective waits for an earlier one (0x140553790)",
  )
  let reached = [
    quest_support.active(
      quest_id: 9428,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 0b1,
      progress: [1, 0],
    ),
  ]
  assert taken_for(
      tables:,
      rows: reached,
      creature_id: 58_487,
      gap: 1.0,
      offer: interaction.NothingToOffer,
    ).effects
    == [
      OpenDialog(unit_id: unit),
      TalkedTo(target: unit_of(tables:, creature: 58_487), checklist_index: 0),
    ]
    as "the same creature once the earlier objective is done"
}

/// A creature that is Hostile to neither player faction.
const friendly = Hostile(exile: False, dominion: False)

/// The unit the click's talk counts for a Simple creature: its creature, the faction its
/// row gives (Creature2 73422's, 73604's and 12545's `factionId` are 219, 171 and 219) and the
/// UnitRace of its row.
fn simple_unit_of(
  tables tables: table_store.Tables,
  creature creature: Int,
  faction faction: Int,
) -> target_group.Unit {
  target_group.Unit(
    ..unit_of(tables:, creature:),
    faction_id: id.Faction2Id(faction),
  )
}

/// Quest 10525's objective 1 is 21319, a type 18 checklist of TargetGroup 14368
/// (Creature2 73422, a Simple unit of faction 219), count 2, flags 3, which waits for
/// objective 0 (21344, a visit).
pub fn a_click_on_a_simple_type_18_target_counts_the_talk_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let target = 73_422
  let reached = [
    quest_support.active(
      quest_id: 10_525,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 0b1,
      progress: [1, 0, 0, 0, 0, 0],
    ),
  ]
  let picture =
    simple_unit_support.picture(
      creature_id: target,
      faction_id: 219,
      checklist_index: 5,
      gap: 1.0,
      hostile_to: friendly,
    )
  let talked =
    taken_in(
      tables:,
      log: quest_support.log_of(rows: reached),
      picture:,
      offer: interaction.NothingToOffer,
    )
  let event =
    TalkedTo(
      target: simple_unit_of(tables:, creature: target, faction: 219),
      checklist_index: 5,
    )
  assert talked.effects == [OpenDialog(unit_id: unit), event]
    as "a Simple type 18 target whose bit is clear opens its dialog and counts the talk, with the faction and the index its 0x262 carried (0x14047a060, 0x1403add00 and 0x140611680 check no unit type)"
  assert talked.window == Closes
    as "the talk closes a vendor window as any request to talk does"

  let counted =
    objective.advance(
      log: quest_support.log_of(rows: reached),
      tables:,
      event: objective.TalkedTo(
        target: simple_unit_of(tables:, creature: target, faction: 219),
        checklist_index: 5,
      ),
      now_ms: 0,
    )
  assert counted.effects
    == [
      objective.SendProgress(quest_id: 10_525, objective_index: 1, progress: 32),
    ]
    as "the talk sets bit 5 of objective 1's mask"
  assert_declined(
    taken: taken_in(
      tables:,
      log: counted.log,
      picture:,
      offer: interaction.NothingToOffer,
    ),
    words: "no quest",
    what: "a target whose bit is set (the client marks it only while the bit is clear)",
  )
}

/// Quest 10528's objective 0 is 21326, a type 3 talk to Creature2 73604, a Simple unit of
/// faction 171, count 1.
pub fn a_click_on_a_simple_type_3_target_counts_the_talk_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let target = 73_604
  let open = [
    quest_support.accepted(quest_id: 10_528, progress: [0, 0, 0, 0, 0]),
  ]
  let picture =
    simple_unit_support.picture(
      creature_id: target,
      faction_id: 171,
      checklist_index: 0,
      gap: 1.0,
      hostile_to: friendly,
    )
  let taken =
    taken_in(
      tables:,
      log: quest_support.log_of(rows: open),
      picture:,
      offer: interaction.NothingToOffer,
    )
  assert taken.effects
    == [
      OpenDialog(unit_id: unit),
      TalkedTo(
        target: simple_unit_of(tables:, creature: target, faction: 171),
        checklist_index: 0,
      ),
    ]
    as "a Simple unit named by an open type 3 objective gets 0x357 and then counts the talk (0x140553110, opcode.0x357)"
  assert_declined(
    taken: taken_in(
      tables:,
      log: quest_support.log_of(rows: []),
      picture:,
      offer: interaction.NothingToOffer,
    ),
    words: "no quest",
    what: "a Simple unit no logged objective names",
  )
}

/// Creature2 73422 is a Simple unit of faction 219 whose objective is open here; 170 is
/// the faction the Faction2 rows make Hostile to the Exile.
pub fn a_simple_unit_hostile_to_the_player_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let reached = [
    quest_support.active(
      quest_id: 10_525,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 0b1,
      progress: [1, 0, 0, 0, 0, 0],
    ),
  ]
  let hostile_to_exiles = Hostile(exile: True, dominion: False)
  assert_declined(
    taken: taken_in(
      tables:,
      log: quest_support.log_of(rows: reached),
      picture: simple_unit_support.picture(
        creature_id: 73_422,
        faction_id: 170,
        checklist_index: 5,
        gap: 1.0,
        hostile_to: hostile_to_exiles,
      ),
      offer: interaction.Offered,
    ),
    words: "Hostile",
    what: "a Simple unit Hostile to an Exile, whose objective is open and which is in reach (0x14047a060 drops the quest kinds for it)",
  )
}

/// The client's reach for a request to talk is 6.0 and the request adds 3.0, edge to edge
/// (`opcode.0x7ea`, `0x1403add00`).
pub fn a_simple_unit_beyond_reach_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let reached = [
    quest_support.active(
      quest_id: 10_525,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask: 0b1,
      progress: [1, 0, 0, 0, 0, 0],
    ),
  ]
  let at = fn(gap) {
    taken_in(
      tables:,
      log: quest_support.log_of(rows: reached),
      picture: simple_unit_support.picture(
        creature_id: 73_422,
        faction_id: 219,
        checklist_index: 5,
        gap:,
        hostile_to: friendly,
      ),
      offer: interaction.NothingToOffer,
    )
  }
  assert_declined(
    taken: at(9.5),
    words: "too far",
    what: "a Simple unit 9.5 from the player's edge",
  )
  assert at(8.5).effects
    == [
      OpenDialog(unit_id: unit),
      TalkedTo(
        target: simple_unit_of(tables:, creature: 73_422, faction: 219),
        checklist_index: 5,
      ),
    ]
    as "the same unit 8.5 from the player's edge"
}
