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

import character_tables
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/game/interaction.{Closes, Offered, OpenDialog, TalkedTo}
import genesis_prime/game/objective
import genesis_prime/game/shown
import genesis_prime/game/start_place
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/step.{LogWarning}
import genesis_prime/store.{type QuestRow}
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
import vendor_support

const talk_target = 12_484

const unit = 40

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
        path: creature_path.Standing(at: place),
        life: 4,
        alive: True,
        hit_radius: creature_radius,
        attackable: Attackable(exile: False, dominion: False),
        hostile_to: Hostile(exile: False, dominion: False),
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
      picture: picture_with(creature_id:, gap:),
      tables:,
      vendors: vendor_support.stocking(creature_ids: []),
      now_ms: 0,
      offers: fn(_) { offer },
      talk_targets: objective.talk_targets(
        log: quest_support.log_of(rows:),
        tables:,
      ),
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
      TalkedTo(creature_id: id.Creature2Id(talk_target)),
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
      TalkedTo(creature_id: id.Creature2Id(talk_target)),
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
      TalkedTo(creature_id: id.Creature2Id(talk_target)),
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
      TalkedTo(creature_id: id.Creature2Id(58_487)),
    ]
    as "the same creature once the earlier objective is done"
}
