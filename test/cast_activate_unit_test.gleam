//// The cast rule's use of a unit with no activate spell (`genesis_prime/game/cast.activate_unit`),
//// the client's 0xb3. Expected values come from these places.
//// - `opcode.0xb3` and `0x14039d510`: the client sends 0xb3 only when the unit's activate
////   spell is 0 (the creature's pick, `0x14046c580`); a unit that has a spell is cast at
////   with 0x97 (`cast_activate_test`). The use is at once, with no cast.
//// - `0x14039d2c0` (ClickInteraction) and `0x140c48c48` (the interaction kind table's
////   entry of kind 39, Interact): the client sends 0xb3 only for a unit whose interaction
////   entry is active and within the entry's range, which is 5.0 for the entry's 0.0, measured
////   edge to edge in three dimensions with no height limit (`0x1403ebe80`).
//// - Creature2 26462 (the Seaspine Mollusk): activate spell 1817 behind Prerequisite 9358,
////   and the default activate spell 8 when that fails (`cast_activate_test`).
//// - Creature2 73500 (the primal manifestation of quest 10520's objective 21294): it has
////   no activate column.
//// - Creature2 34758 (a market terminal): activate spell 38925 behind Prerequisite 13244, a
////   type 94 condition (comparison 2) on quest 7153's objective 0: the spell is picked
////   while the unit's checklist bit is clear, and the default spell 8 once it is set.

import cast_support as support
import fixture_tables
import genesis_prime/game/activate
import genesis_prime/game/cast.{type Effect}
import genesis_prime/game/objective_link
import genesis_prime/game/quest_log
import genesis_prime/message/client_activate_unit.{ClientActivateUnit}
import genesis_prime/step.{LogWarning}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import gleam/dict
import gleam/string
import owned_test
import place_support
import quest_support

const the_mollusk = 26_462

const a_manifestation = 73_500

const a_market_terminal = 34_758

const a_linked_creature = 10_036

const market_quest = 7153

const its_unit = 5000

// Hit radii of exactly representable size: the player's and the unit's.
const caster_radius = 0.5

const unit_radius = 0.25

/// The caster stands at a place of exactly representable numbers.
fn standing() -> cast.Caster {
  cast.Caster(
    ..support.caster(),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 4096.0,
      y: 0.0,
      z: 512.0,
    ),
  )
}

/// The unit of the creature, `east` units east of the standing caster.
fn unit(
  creature creature: Int,
  checklist_index checklist_index: Int,
  east east: Float,
  offered offered: Bool,
) -> cast.UsedUnit {
  let assert Ok(row) =
    creature2.get(fixture_tables.shared(), Creature2Id(creature))
    as "the fixture holds the creature's row"
  cast.UsedUnit(
    creature_id: creature,
    creature: activate.creature_of(row:),
    checklist_index:,
    link: activate.NoLink,
    body: activate.Body(
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 4096.0 +. east,
        y: 0.0,
        z: 512.0,
      ),
      radius: unit_radius,
    ),
    alive: True,
    offered:,
  )
}

/// What the caster's 0xb3 for `unit_id` gives, when the units its client shows are these,
/// by unit id.
fn used_by(
  caster caster: cast.Caster,
  seen seen: List(#(Int, cast.UsedUnit)),
  unit_id unit_id: Int,
) -> List(Effect) {
  let units = dict.from_list(seen)
  let assert Ok(body) =
    client_activate_unit.encode(ClientActivateUnit(unit_id:))
    as "a unit id fits the message"
  let assert Ok(effects) =
    cast.activate_unit(
      cast: cast.new(),
      body:,
      caster:,
      activations: activate.activations(tables: fixture_tables.shared()),
      unit_of: fn(unit) { dict.get(units, unit) },
      caster_radius:,
    )
    as "a 0xb3 that fits the message is taken"
  effects
}

fn used(
  seen seen: List(#(Int, cast.UsedUnit)),
  unit_id unit_id: Int,
) -> List(Effect) {
  used_by(caster: standing(), seen:, unit_id:)
}

/// The one warning a refused 0xb3 gives: nothing else is done.
fn refusal_text(effects effects: List(Effect)) -> String {
  let assert [cast.Log(level: LogWarning, text:)] = effects
    as "a refused use is logged and nothing else: no Activated, no write"
  text
}

pub fn a_client_activate_unit_on_a_unit_with_no_activate_spell_is_used_at_once_test() -> Nil {
  use <- owned_test.run(10_000)
  assert used(
      seen: [
        #(
          its_unit,
          unit(
            creature: a_manifestation,
            checklist_index: 2,
            east: 1.0,
            offered: True,
          ),
        ),
      ],
      unit_id: its_unit,
    )
    == [
      cast.Activated(
        unit_id: its_unit,
        creature_id: a_manifestation,
        alive_at_press: True,
      ),
    ]
    as "a creature with no activate column is used with no cast and no wait"
}

pub fn a_client_activate_unit_on_a_unit_with_an_activate_spell_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let text =
    used(
      seen: [
        #(
          its_unit,
          unit(
            creature: the_mollusk,
            checklist_index: 0,
            east: 1.0,
            offered: True,
          ),
        ),
      ],
      unit_id: its_unit,
    )
    |> refusal_text
  assert string.contains(text, "0x97")
    as "the log says the client casts such a unit with 0x97"
}

pub fn a_client_activate_unit_on_a_unit_the_client_does_not_show_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let text =
    used(
      seen: [
        #(
          its_unit,
          unit(
            creature: a_manifestation,
            checklist_index: 2,
            east: 1.0,
            offered: True,
          ),
        ),
      ],
      unit_id: its_unit + 1,
    )
    |> refusal_text
  assert string.contains(text, "no creature or object") as "the log says why"
}

pub fn a_client_activate_unit_is_refused_out_of_the_interaction_range_test() -> Nil {
  use <- owned_test.run(10_000)
  let used_at = fn(east) {
    used(
      seen: [
        #(
          its_unit,
          unit(
            creature: a_manifestation,
            checklist_index: 2,
            east:,
            offered: True,
          ),
        ),
      ],
      unit_id: its_unit,
    )
  }
  assert used_at(5.75)
    == [
      cast.Activated(
        unit_id: its_unit,
        creature_id: a_manifestation,
        alive_at_press: True,
      ),
    ]
    as "the gap between the edges is 5.75 less 0.5 and 0.25, exactly the range 5.0: within it"
  let text = refusal_text(effects: used_at(6.0))
  assert string.contains(text, "range")
    as "the gap of 5.25 is out of the range 5.0: the use is logged and counts nothing"
}

pub fn a_client_activate_unit_on_a_unit_the_server_does_not_offer_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let text =
    used(
      seen: [
        #(
          its_unit,
          unit(
            creature: a_manifestation,
            checklist_index: 2,
            east: 1.0,
            offered: False,
          ),
        ),
      ],
      unit_id: its_unit,
    )
    |> refusal_text
  assert string.contains(text, "not offered")
    as "a unit no open objective counts a use of, or whose bit is set, is not offered its interaction, so the client never sends the use"
}

pub fn a_client_activate_unit_on_a_dead_creature_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let dead =
    cast.UsedUnit(
      ..unit(
        creature: a_manifestation,
        checklist_index: 2,
        east: 1.0,
        offered: True,
      ),
      alive: False,
    )
  let text = used(seen: [#(its_unit, dead)], unit_id: its_unit) |> refusal_text
  assert string.contains(text, "dead")
    as "a creature its client shows dead is not offered its interaction (0x140c48c48), so the client never sends the use: it is logged and counts nothing, though it is within reach and offered"
}

/// What the 0xb3 for the market terminal (index 5) gives a caster whose quest 7153
/// holds this progress for its one objective.
fn market_terminal_used(progress progress: Int) -> List(Effect) {
  used_by(
    caster: cast.Caster(
      ..standing(),
      quests: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: market_quest, progress: [progress]),
      ]),
    ),
    seen: [
      #(
        its_unit,
        unit(
          creature: a_market_terminal,
          checklist_index: 5,
          east: 1.0,
          offered: True,
        ),
      ),
    ],
    unit_id: its_unit,
  )
}

pub fn a_client_activate_unit_picks_with_the_checklist_bit_of_the_unit_test() -> Nil {
  use <- owned_test.run(10_000)
  assert string.contains(
    refusal_text(effects: market_terminal_used(progress: 0)),
    "activate spell is 38925",
  )
    as "bit 5 of quest 7153's objective is clear: Prerequisite 13244 passes and the column's spell is picked"
  assert market_terminal_used(progress: 32)
    == [
      cast.Activated(
        unit_id: its_unit,
        creature_id: a_market_terminal,
        alive_at_press: True,
      ),
    ]
    as "bit 5 is set: the condition fails and the next column, prerequisite 0 with spell 0, wins: no activate spell, so the client's use is at once (0x14046c580)"
}

/// What the 0xb3 for Creature2 10036, which has no activate spell and a questAnim link to
/// quest 3244's objective 0, gives a caster whose quest log is this one, when the server
/// offers the unit by another objective's count: the link is read by the rule that reads
/// it (genesis_prime/game/objective_link `of`).
fn linked_creature_used(quests quests: quest_log.QuestLog) -> List(Effect) {
  let tables = fixture_tables.shared()
  let caster = cast.Caster(..standing(), quests:)
  let assert Ok(row) =
    creature2.get(tables:, id: Creature2Id(a_linked_creature))
    as "the fixture holds the creature's row"
  let link =
    objective_link.of(
      tables:,
      activations: activate.activations(tables:),
      subject: cast.subject_for_use(
        cast: cast.new(),
        caster:,
        unit_id: its_unit,
        checklist_index: 0,
      ),
      quests:,
      row:,
      checklist_index: 0,
    )
  used_by(
    caster:,
    seen: [
      #(
        its_unit,
        cast.UsedUnit(
          ..unit(
            creature: a_linked_creature,
            checklist_index: 0,
            east: 1.0,
            offered: True,
          ),
          link:,
        ),
      ),
    ],
    unit_id: its_unit,
  )
}

pub fn a_use_of_a_creature_with_no_open_link_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  assert linked_creature_used(
      quests: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: 3244, progress: [0]),
      ]),
    )
    == [
      cast.Activated(
        unit_id: its_unit,
        creature_id: a_linked_creature,
        alive_at_press: True,
      ),
    ]
    as "quest 3244 is Accepted with its objective 4242 open: the link is open, and a creature with no activate spell is used at once"
  let text =
    linked_creature_used(
      quests: quest_support.log_of(rows: [
        quest_support.active(
          quest_id: 3244,
          state: 2,
          placeholder: 0,
          tracked: False,
          done_mask: 0b1,
          progress: [1],
        ),
      ]),
    )
    |> refusal_text
  assert string.contains(text, "link")
    as "objective 4242 is done: the client offers the creature nothing, so the use is logged and counts nothing"
}
