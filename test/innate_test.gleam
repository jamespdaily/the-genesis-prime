//// A class's level-1 innate (`genesis_prime/game/innate`): which spells a Class
//// row holds and what refuses the load; and the client's switch 0x16F
//// (`genesis_prime/game/innate_choice`). Expected values come from these places.
//// - `Class.spell4IdInnateAbilityActive00` and `Class.spell4IdInnateAbilityPassive00`:
////   Warrior (1) 46867 with passive 44926, Engineer (2) 47866 with 45000, Esper
////   (3) 58586, Medic (4) 69450 and Spellslinger (7) 47273 with none, Stalker (5)
////   46073 with 45057; slot 0 has no gate in any row, and the client takes the
////   slots in order, stopping at the first with no active spell (`0x1405e7330`).
//// - The Spell4Base ids (`table_rows -- Spell4 <id>`, spell4BaseIdBaseSpell):
////   46867 is 30828, 44926 is 29035, 47866 is 31779, 45000 is 29076, 58586 is
////   38012, 69450 is 46615, 46073 is 30075, 45057 is 29131 and 47273 is 31213.
//// - `0x1405e73e0`: a slot is unlocked when its gate prerequisite passes, so a
////   gate on slot 0 would need the server to check it; no row has one.
//// - `0x1405e7490` (SetInnateIndex): the client refuses an index at or above the
////   unlocked count and sends 0x16F only after switching itself, and
////   `opcode.0x16f` says it never sends the index it already holds.

import client_tables
import genesis_prime/client_connection.{Undecoded}
import genesis_prime/game/innate.{
  type Innate, Innate, InnateAlsoAnAbility, NoSpell, Passive, SlotZeroGated,
}
import genesis_prime/game/innate_choice.{NotHeld}
import genesis_prime/message/bit_stream
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{
  type Spell4BaseId, type Spell4Id, Spell4BaseId, Spell4Id,
}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import unitest

/// The Spell4Base id of each spell the Class rows name, as the client's Spell4
/// rows hold them.
fn base_of(spell4_id: Spell4Id) -> Result(Spell4BaseId, Nil) {
  case spell4_id.value {
    46_867 -> Ok(Spell4BaseId(30_828))
    44_926 -> Ok(Spell4BaseId(29_035))
    47_866 -> Ok(Spell4BaseId(31_779))
    45_000 -> Ok(Spell4BaseId(29_076))
    58_586 -> Ok(Spell4BaseId(38_012))
    69_450 -> Ok(Spell4BaseId(46_615))
    46_073 -> Ok(Spell4BaseId(30_075))
    45_057 -> Ok(Spell4BaseId(29_131))
    47_273 -> Ok(Spell4BaseId(31_213))
    _ -> Error(Nil)
  }
}

fn warrior() -> Innate {
  Innate(
    active: Spell4Id(46_867),
    active_base: Spell4BaseId(30_828),
    passive: Some(Passive(
      spell4_id: Spell4Id(44_926),
      spell4_base_id: Spell4BaseId(29_035),
    )),
  )
}

pub fn the_class_rows_give_each_classs_held_innate_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let assert Ok(held) = innate.held(client_tables.shared())
    as "the client's Class rows name Spell4 rows the table holds, with no gate on slot 0"
  assert dict.to_list(held) |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    == [
      #(1, warrior()),
      #(
        2,
        Innate(
          active: Spell4Id(47_866),
          active_base: Spell4BaseId(31_779),
          passive: Some(Passive(
            spell4_id: Spell4Id(45_000),
            spell4_base_id: Spell4BaseId(29_076),
          )),
        ),
      ),
      #(
        3,
        Innate(
          active: Spell4Id(58_586),
          active_base: Spell4BaseId(38_012),
          passive: None,
        ),
      ),
      #(
        4,
        Innate(
          active: Spell4Id(69_450),
          active_base: Spell4BaseId(46_615),
          passive: None,
        ),
      ),
      #(
        5,
        Innate(
          active: Spell4Id(46_073),
          active_base: Spell4BaseId(30_075),
          passive: Some(Passive(
            spell4_id: Spell4Id(45_057),
            spell4_base_id: Spell4BaseId(29_131),
          )),
        ),
      ),
      #(
        7,
        Innate(
          active: Spell4Id(47_273),
          active_base: Spell4BaseId(31_213),
          passive: None,
        ),
      ),
    ]
    as "Class.spell4IdInnateAbilityActive00 and Passive00: slot 0 of each class; slots 1 and 2 (47022 and 44932, 47881 and 41504, 46074 and 45058, 38782 and 46059) are not held"
}

pub fn a_class_row_with_no_active_spell_in_slot_0_holds_no_innate_test() -> Nil {
  use <- owned_test.run(5000)
  assert innate.of_slot_zero(
      class_id: 3,
      active: 0,
      passive: 44_926,
      gate: 0,
      base_of:,
    )
    == Ok(None)
    as "0x1405e7330: the client takes the slots in order and stops at the first with no active spell, so a passive beside no active is never held"
}

pub fn a_class_row_with_a_spell_in_slot_0_holds_it_with_the_passive_it_names_test() -> Nil {
  use <- owned_test.run(5000)
  assert innate.of_slot_zero(
      class_id: 1,
      active: 46_867,
      passive: 44_926,
      gate: 0,
      base_of:,
    )
    == Ok(Some(warrior()))
    as "Class row 1: 46867 with passive 44926"
  assert innate.of_slot_zero(
      class_id: 3,
      active: 58_586,
      passive: 0,
      gate: 0,
      base_of:,
    )
    == Ok(
      Some(Innate(
        active: Spell4Id(58_586),
        active_base: Spell4BaseId(38_012),
        passive: None,
      )),
    )
    as "Class row 3: a passive column of 0 holds none"
}

pub fn a_gate_on_slot_0_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  assert innate.of_slot_zero(
      class_id: 1,
      active: 46_867,
      passive: 44_926,
      gate: 39_778,
      base_of:,
    )
    == Error(SlotZeroGated(class_id: 1, prerequisite_id: 39_778))
    as "0x1405e73e0: a slot with a gate is unlocked only when its prerequisite passes, which the server does not check for slot 0; no client row has one"
}

pub fn a_class_row_naming_a_spell4_row_the_table_lacks_fails_the_load_naming_both_test() -> Nil {
  use <- owned_test.run(5000)
  let missing_active =
    innate.of_slot_zero(
      class_id: 1,
      active: 99_999,
      passive: 0,
      gate: 0,
      base_of:,
    )
  assert missing_active == Error(NoSpell(class_id: 1, spell4_id: 99_999))
    as "an active spell the Spell4 table lacks"
  let missing_passive =
    innate.of_slot_zero(
      class_id: 2,
      active: 47_866,
      passive: 88_888,
      gate: 0,
      base_of:,
    )
  assert missing_passive == Error(NoSpell(class_id: 2, spell4_id: 88_888))
    as "a passive spell the Spell4 table lacks"
  let assert Error(error) = missing_active
  let sentence = innate.describe(error:)
  assert string.contains(sentence, "Class")
    && string.contains(sentence, "99999")
    && string.contains(sentence, "Spell4")
    && string.contains(sentence, " 1")
    as "the sentence names the Class row and the Spell4 row"
}

pub fn an_innate_whose_base_is_also_a_level_1_ability_of_its_class_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  assert innate.not_an_ability(
      class_id: 4,
      innate: Innate(
        active: Spell4Id(69_450),
        active_base: Spell4BaseId(46_615),
        passive: None,
      ),
      abilities: [Spell4BaseId(38_201), Spell4BaseId(46_615)],
    )
    == Error(InnateAlsoAnAbility(class_id: 4, spell4_base_id: 46_615))
    as "the bag would hold two items of one Spell4Base (0x14077dfa0 finds the spell by its base)"
  assert innate.not_an_ability(
      class_id: 4,
      innate: Innate(
        active: Spell4Id(69_450),
        active_base: Spell4BaseId(46_615),
        passive: None,
      ),
      abilities: [
        Spell4BaseId(38_201),
        Spell4BaseId(16_322),
        Spell4BaseId(26_543),
      ],
    )
    == Ok(Nil)
    as "SpellLevel holds no row for 69450 (table_rows -- SpellLevel spell4Id=69450), so the Medic's real abilities do not hold it"
  let assert Error(error) =
    innate.not_an_ability(
      class_id: 4,
      innate: Innate(
        active: Spell4Id(69_450),
        active_base: Spell4BaseId(46_615),
        passive: None,
      ),
      abilities: [Spell4BaseId(46_615)],
    )
  assert string.contains(innate.describe(error:), "46615")
    as "the sentence names the base"
}

// ---- 0x16F ----

fn chosen(
  innate innate: option.Option(Innate),
  index index: Int,
) -> Result(List(innate_choice.Effect), innate_choice.Refusal) {
  innate_choice.take(innate:, message: innate_choice.IndexChosen, body: <<
    index:size(8),
  >>)
}

pub fn index_0_is_taken_with_nothing_written_and_a_debug_line_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok([innate_choice.Log(level:, text:)]) =
    chosen(innate: Some(warrior()), index: 0)
    as "opcode.0x16f: the client sends 0 only before 0x19F has set its index (4), and has already switched itself; the server's index is 0 already, so the one effect is a log line"
  assert level == LogDebug
  assert string.contains(text, "0x016F")
}

pub fn an_index_the_client_would_refuse_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([1, 2, 255], fn(index) {
    assert chosen(innate: Some(warrior()), index:)
      == Error(NotHeld(index:, held: 1))
      as "0x1405e7490: an index at or above the unlocked count is refused and nothing is sent; at level 1 one slot is held, so 1 is refused as slot 1's gate 39778 needs level 6"
  })
}

pub fn a_player_with_no_innate_is_refused_every_index_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([0, 1, 2, 255], fn(index) {
    assert chosen(innate: None, index:) == Error(NotHeld(index:, held: 0))
      as "0x1405e7490: the unlocked count is 0 with no innate, so every index is at or above it"
  })
}

pub fn a_0x16f_body_the_clients_reader_refuses_is_not_decoded_test() -> Nil {
  use <- owned_test.run(5000)
  assert innate_choice.take(
      innate: Some(warrior()),
      message: innate_choice.IndexChosen,
      body: <<>>,
    )
    == Error(
      innate_choice.NotDecoded(undecoded: Undecoded(
        message_id: 0x016F,
        error: bit_stream.EndOfData,
      )),
    )
    as "opcode.0x16f: the body is one byte"
  assert string.contains(
    innate_choice.describe(refusal: NotHeld(index: 1, held: 1)),
    "1",
  )
}
