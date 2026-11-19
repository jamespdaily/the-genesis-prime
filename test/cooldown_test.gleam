//// The running cooldowns of a unit and the modifiers that change them
//// (`genesis_prime/game/cooldown`). Expected values come from these places:
//// - `0x14046b920` ModifyRunningCooldowns: a modifier's selector picks the running
////   cooldowns whose spell it names (0 by Spell4Base, 1 by Spell4, 2 by spell group, 3 by
////   cooldown group, any other value every spell), and its operation changes the time
////   left.
//// - `0x14046ba60` to `0x14046babc`: the operations run in 32-bit floats: 0 multiplies
////   and never lengthens, 1 multiplies, 2 adds whole milliseconds (never below 0, at most
////   2^31 - 1), 3 sets, any other value leaves the time. Ten thousand times the float
////   0.9 (0.89999998) is 9000, where the 64-bit product truncates to 8999.
//// - `0x1407a0320` and `0x1407a0390`: a new time of 0 fires the entry's end, so the
////   cooldown is over.
//// - `0x14046b1e0` StartSpellCooldowns: nothing starts while the spell has a cooldown;
////   `0x14046a3d0` SetSpellCooldown: a new cooldown is made only for a time above 0.
//// - `0x14046a890` ApplyCooldownModifiers: a new cooldown's time goes through the lasting
////   modifiers in the order they were added.
//// - The server's choice: a source kept again is held once, as a unit's property
////   modifiers are (`genesis_prime/game/unit_properties`).

import cast_support
import genesis_prime/game/cooldown.{
  type Book, type Operation, AddMs, Base, CooldownGroup, EverySpell, Modifier,
  Multiply, NoLonger, SetMs, Spell, SpellGroup, Unchanged,
}
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import gleam/list
import owned_test

/// Charged Shot, Spell4 34718 of Spell4Base 20684, with its cooldown group 133
/// (`table_rows -- Spell4 34718`).
fn charged_shot_keys() -> cooldown.Keys {
  cooldown.keys(
    spell4_id: Spell4Id(34_718),
    spell4_base_id: Spell4BaseId(20_684),
    spell_groups: [],
    cooldown_groups: [cooldown.Group(id: 133, time_ms: 0)],
  )
}

fn charged_shot_running(for_ms for_ms: Int, at now_ms: Int) -> Book {
  cooldown.start(
    book: cooldown.new(),
    keys: charged_shot_keys(),
    cooldown_ms: for_ms,
    now_ms:,
  )
}

/// The time left of Charged Shot's cooldown after a cooldown of `from_ms` has an
/// operation applied to every spell of its base.
fn left_after(operation operation: Operation, from_ms from_ms: Int) -> Int {
  let book =
    cooldown.modify(
      book: charged_shot_running(for_ms: from_ms, at: 0),
      modifier: Modifier(selector: Base(Spell4BaseId(20_684)), operation:),
      now_ms: 0,
    )
  cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 0)
}

// ---- the operations ----

pub fn operation_0_multiplies_the_time_left_and_never_lengthens_it_test() -> Nil {
  use <- owned_test.run(5000)
  // 0.4 as the client's row 80979 holds it: bits 0x3ECCCCCD.
  assert left_after(operation: NoLonger(0.4000000059604645), from_ms: 10_000)
    == 4000
    as "10000 x 0.4 is 4000"
  // 0.9 as the 32-bit float: 0x3F666666.
  assert left_after(operation: NoLonger(0.8999999761581421), from_ms: 10_000)
    == 9000
    as "the 32-bit product is 9000; the 64-bit product 8999.99976 would truncate to 8999"
  assert left_after(operation: NoLonger(1.5), from_ms: 10_000) == 10_000
    as "a factor above 1 would lengthen the time, which operation 0 never does"
  assert left_after(operation: NoLonger(0.0), from_ms: 10_000) == 0
    as "the row 80977 multiplies by 0.0, which ends the cooldown"
}

pub fn operation_1_multiplies_the_time_left_and_may_lengthen_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert left_after(operation: Multiply(2.0), from_ms: 10_000) == 20_000
  assert left_after(operation: Multiply(0.5), from_ms: 10_000) == 5000
}

pub fn operation_2_adds_milliseconds_and_stops_at_zero_test() -> Nil {
  use <- owned_test.run(5000)
  assert left_after(operation: AddMs(-1500.0), from_ms: 10_000) == 8500
    as "the row 180712 takes 1500 ms off"
  assert left_after(operation: AddMs(-1500.0), from_ms: 1000) == 0
    as "a sum below 0 is 0, and a time of 0 ends the cooldown"
  assert left_after(operation: AddMs(2_000_000_000.0), from_ms: 2_000_000_000)
    == 2_147_483_647
    as "the sum is capped at 2^31 - 1 (cmovg against 0x7fffffff, 0x14046ba60 to 0x14046babc)"
}

pub fn operation_3_sets_the_time_and_may_lengthen_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert left_after(operation: SetMs(60_000.0), from_ms: 10_000) == 60_000
  assert left_after(operation: SetMs(7.9), from_ms: 10_000) == 7
    as "the float is truncated to whole milliseconds"
}

pub fn an_operation_the_client_has_no_case_for_leaves_the_time_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4Effects 50869 holds the operation 219.
  assert left_after(operation: Unchanged(operation: 219), from_ms: 10_000)
    == 10_000
}

pub fn a_time_of_zero_ends_the_cooldown_so_the_spell_can_start_one_again_test() -> Nil {
  use <- owned_test.run(5000)
  let ended =
    cooldown.modify(
      book: charged_shot_running(for_ms: 10_000, at: 0),
      modifier: Modifier(
        selector: Base(Spell4BaseId(20_684)),
        operation: NoLonger(0.0),
      ),
      now_ms: 0,
    )
  let again =
    cooldown.start(
      book: ended,
      keys: charged_shot_keys(),
      cooldown_ms: 10_000,
      now_ms: 1000,
    )
  assert cooldown.left_ms(
      book: again,
      spell4_id: Spell4Id(34_718),
      now_ms: 1000,
    )
    == 10_000
    as "StartSpellCooldowns starts a cooldown when none runs, and the ended one is none"
}

pub fn the_clock_may_be_negative_test() -> Nil {
  use <- owned_test.run(5000)
  // The monotonic clock can be negative (`cast`): the time left is a difference.
  let book =
    cooldown.modify(
      book: charged_shot_running(for_ms: 10_000, at: -5000),
      modifier: Modifier(
        selector: Base(Spell4BaseId(20_684)),
        operation: NoLonger(0.4000000059604645),
      ),
      now_ms: -2000,
    )
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: -2000)
    == 2800
    as "7000 ms are left at -2000, and 7000 x 0.4 is 2800"
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 800) == 0
    as "the cooldown ends at -2000 + 2800"
}

// ---- the selectors ----

/// Three spells with 10000 ms of cooldown from 0: 100 of base 10, spell group 7 and
/// cooldown group 50; 200 of base 10, spell group 8 and cooldown group 51; 300 of base
/// 30, spell group 7 and cooldown group 52. Planted ids, not client rows.
fn three_running() -> Book {
  list.fold(
    [#(100, 10, 7, 50), #(200, 10, 8, 51), #(300, 30, 7, 52)],
    cooldown.new(),
    fn(book, spell) {
      cooldown.start(
        book:,
        keys: cooldown.keys(
          spell4_id: Spell4Id(spell.0),
          spell4_base_id: Spell4BaseId(spell.1),
          spell_groups: [spell.2],
          cooldown_groups: [cooldown.Group(id: spell.3, time_ms: 0)],
        ),
        cooldown_ms: 10_000,
        now_ms: 0,
      )
    },
  )
}

/// The spells of the three whose cooldown a selector set to 1000 ms.
fn picked_by(selector selector: cooldown.Selector) -> List(Int) {
  let book =
    cooldown.modify(
      book: three_running(),
      modifier: Modifier(selector:, operation: SetMs(1000.0)),
      now_ms: 0,
    )
  list.filter([100, 200, 300], fn(spell) {
    cooldown.left_ms(book:, spell4_id: Spell4Id(spell), now_ms: 0) == 1000
  })
}

pub fn selector_0_picks_the_spells_of_a_spell4base_test() -> Nil {
  use <- owned_test.run(5000)
  assert picked_by(selector: Base(Spell4BaseId(10))) == [100, 200]
    as "0x14046b920: the spell record's word 1, Spell4.spell4BaseIdBaseSpell"
  assert picked_by(selector: Base(Spell4BaseId(0))) == []
    as "a base no spell has matches nothing: 15 rows of the client name base 0"
}

pub fn selector_1_picks_one_spell4_test() -> Nil {
  use <- owned_test.run(5000)
  assert picked_by(selector: Spell(Spell4Id(200))) == [200]
  assert picked_by(selector: Spell(Spell4Id(999))) == []
    as "an id no spell has matches nothing: the client compares ids and looks up no row"
}

pub fn selector_2_picks_the_spells_of_a_spell_group_test() -> Nil {
  use <- owned_test.run(5000)
  assert picked_by(selector: SpellGroup(7)) == [100, 300]
    as "IsSpellInGroup, built from Spell4GroupList"
  assert picked_by(selector: SpellGroup(9)) == []
}

pub fn selector_3_picks_the_spells_of_a_cooldown_group_test() -> Nil {
  use <- owned_test.run(5000)
  assert picked_by(selector: CooldownGroup(52)) == [300]
    as "words 1 to 3 of the spell's cooldown array, spellCoolDownId00 to 02"
  assert picked_by(selector: CooldownGroup(53)) == []
}

pub fn any_other_selector_value_picks_every_spell_test() -> Nil {
  use <- owned_test.run(5000)
  assert picked_by(selector: EverySpell(selector: 4)) == [100, 200, 300]
    as "0x14046b920: the final else branch runs the operation for any other selector value"
}

// ---- starting a cooldown ----

pub fn a_cooldown_does_not_start_while_the_spell_has_one_running_test() -> Nil {
  use <- owned_test.run(5000)
  let book =
    cooldown.start(
      book: charged_shot_running(for_ms: 10_000, at: 0),
      keys: charged_shot_keys(),
      cooldown_ms: 5000,
      now_ms: 2000,
    )
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 2000)
    == 8000
    as "0x14046b1e0: StartSpellCooldowns does nothing when the spell already has a cooldown"
  let later =
    cooldown.start(
      book:,
      keys: charged_shot_keys(),
      cooldown_ms: 5000,
      now_ms: 10_000,
    )
  assert cooldown.left_ms(
      book: later,
      spell4_id: Spell4Id(34_718),
      now_ms: 10_000,
    )
    == 5000
    as "it starts once the first is over"
}

pub fn a_cooldown_of_zero_starts_none_test() -> Nil {
  use <- owned_test.run(5000)
  let book = charged_shot_running(for_ms: 0, at: 0)
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 0) == 0
    as "0x14046a3d0: a new entry is made only for a time above 0"
}

pub fn a_cooldown_that_has_ended_is_none_left_test() -> Nil {
  use <- owned_test.run(5000)
  let book = charged_shot_running(for_ms: 10_000, at: 1000)
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 4000)
    == 7000
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 11_000)
    == 0
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 12_000)
    == 0
    as "a time left is never below 0"
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(1), now_ms: 4000) == 0
    as "a spell that never started one has none"
}

// ---- the cooldown groups ----

/// Basic Medishot, Spell4 34985 of base 20834, with no cooldown of its own and the group
/// 130, whose SpellCoolDown row holds 180,000 ms (`table_rows -- Spell4 34985`,
/// `-- SpellCoolDown 130`).
fn medishot_keys() -> cooldown.Keys {
  cooldown.keys(
    spell4_id: Spell4Id(34_985),
    spell4_base_id: Spell4BaseId(20_834),
    spell_groups: [],
    cooldown_groups: [cooldown.Group(id: 130, time_ms: 180_000)],
  )
}

fn group_130() -> List(cooldown.Group) {
  [cooldown.Group(id: 130, time_ms: 180_000)]
}

/// The time the group `id` has left at `now_ms`.
fn group_left(book book: Book, id id: Int, at now_ms: Int) -> Int {
  cooldown.group_left_ms(
    book:,
    groups: [cooldown.Group(id:, time_ms: 0)],
    now_ms:,
  )
}

pub fn a_go_starts_each_cooldown_group_for_its_own_time_test() -> Nil {
  use <- owned_test.run(5000)
  // Three groups of planted times and the spell's own 5000 ms, started at 0.
  let book =
    cooldown.start(
      book: cooldown.new(),
      keys: cooldown.keys(
        spell4_id: Spell4Id(7),
        spell4_base_id: Spell4BaseId(7),
        spell_groups: [],
        cooldown_groups: [
          cooldown.Group(id: 130, time_ms: 180_000),
          cooldown.Group(id: 182, time_ms: 25_000),
          cooldown.Group(id: 133, time_ms: 0),
        ],
      ),
      cooldown_ms: 5000,
      now_ms: 0,
    )
  list.each(
    [
      #("group 130 holds its row's time", 130, 1000, 179_000),
      #("group 182 holds its row's time", 182, 1000, 24_000),
      #("a group time of 0 starts none (0x14046a3d0)", 133, 1000, 0),
      #("group 182 ends at its time", 182, 25_000, 0),
      #(
        "group 130 runs on after the spell's own cooldown",
        130,
        25_000,
        155_000,
      ),
    ],
    fn(row) {
      assert group_left(book:, id: row.1, at: row.2) == row.3 as row.0
    },
  )
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(7), now_ms: 1000) == 4000
    as "the spell's own cooldown runs beside its groups"
}

pub fn a_group_cooldown_one_spell_started_is_left_for_every_spell_that_names_the_group_test() -> Nil {
  use <- owned_test.run(5000)
  let book =
    cooldown.start(
      book: cooldown.new(),
      keys: medishot_keys(),
      cooldown_ms: 0,
      now_ms: 1000,
    )
  assert cooldown.group_left_ms(book:, groups: group_130(), now_ms: 2000)
    == 179_000
    as "0x1403b14c0 finds the group entry by the group's id, whatever spell started it"
  assert cooldown.group_left_ms(
      book:,
      groups: [
        cooldown.Group(id: 182, time_ms: 25_000),
        cooldown.Group(id: 130, time_ms: 180_000),
      ],
      now_ms: 2000,
    )
    == 179_000
    as "the longest of a spell's groups that run is what is left"
  assert cooldown.group_left_ms(
      book:,
      groups: [cooldown.Group(id: 182, time_ms: 25_000)],
      now_ms: 2000,
    )
    == 0
    as "a spell of another group meets none"
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_985), now_ms: 2000) == 0
    as "Medishot has no cooldown of its own"
}

pub fn a_spell_whose_group_cooldown_runs_starts_no_cooldown_again_test() -> Nil {
  use <- owned_test.run(5000)
  let own_and_group =
    cooldown.keys(
      spell4_id: Spell4Id(7),
      spell4_base_id: Spell4BaseId(7),
      spell_groups: [],
      cooldown_groups: group_130(),
    )
  let book =
    cooldown.start(
      book: cooldown.new(),
      keys: own_and_group,
      cooldown_ms: 5000,
      now_ms: 0,
    )
  // At 6000 the spell's own 5000 ms are over and its group has 174,000 ms left.
  let again =
    cooldown.start(book:, keys: own_and_group, cooldown_ms: 5000, now_ms: 6000)
  assert again == book
    as "0x14046b1e0 returns when an entry of the unit carries the spell's id, and a group entry does"
  assert group_left(book: again, id: 130, at: 6000) == 174_000
    && cooldown.left_ms(book: again, spell4_id: Spell4Id(7), now_ms: 6000) == 0
    as "neither the group nor the own cooldown starts again"
}

pub fn a_group_time_of_zero_ends_a_group_cooldown_that_runs_test() -> Nil {
  use <- owned_test.run(5000)
  let book =
    cooldown.start(
      book: cooldown.new(),
      keys: medishot_keys(),
      cooldown_ms: 0,
      now_ms: 0,
    )
  let ended =
    cooldown.start(
      book:,
      keys: cooldown.keys(
        spell4_id: Spell4Id(8),
        spell4_base_id: Spell4BaseId(8),
        spell_groups: [],
        cooldown_groups: [cooldown.Group(id: 130, time_ms: 0)],
      ),
      cooldown_ms: 0,
      now_ms: 1000,
    )
  assert group_left(book: ended, id: 130, at: 1000) == 0
    as "0x14046a3d0: a spell that goes with the group's time 0 sets that group to 0, which ends the entry (opcode.0x804 says the same of a time of 0)"
}

pub fn a_modifier_picks_a_group_cooldown_by_the_spell_that_started_it_test() -> Nil {
  use <- owned_test.run(5000)
  let started =
    cooldown.start(
      book: cooldown.new(),
      keys: medishot_keys(),
      cooldown_ms: 0,
      now_ms: 0,
    )
  list.each(
    [
      #("selector 0, the starter's base", Base(Spell4BaseId(20_834)), 90_000),
      #("selector 1, the starter", Spell(Spell4Id(34_985)), 90_000),
      #("selector 3, a group of the starter", CooldownGroup(130), 90_000),
      #("selector 3 of another group", CooldownGroup(182), 180_000),
      #("selector 0 of another base", Base(Spell4BaseId(1)), 180_000),
    ],
    fn(row) {
      let book =
        cooldown.modify(
          book: started,
          modifier: Modifier(selector: row.1, operation: NoLonger(0.5)),
          now_ms: 0,
        )
      assert group_left(book:, id: 130, at: 0) == row.2 as row.0
    },
  )
}

pub fn a_new_group_cooldown_goes_through_the_kept_modifiers_test() -> Nil {
  use <- owned_test.run(5000)
  let kept =
    cooldown.keep(
      book: cooldown.new(),
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: Modifier(selector: CooldownGroup(130), operation: NoLonger(0.5)),
    )
  let book =
    cooldown.start(book: kept, keys: medishot_keys(), cooldown_ms: 0, now_ms: 0)
  assert group_left(book:, id: 130, at: 0) == 90_000
    as "0x14046a890 runs a new entry's time, a group's too, through the kept modifiers"
}

// ---- the lasting modifiers ----

fn half() -> cooldown.Modifier {
  Modifier(selector: Base(Spell4BaseId(20_684)), operation: Multiply(0.5))
}

fn minus_a_second() -> cooldown.Modifier {
  Modifier(selector: Base(Spell4BaseId(20_684)), operation: AddMs(-1000.0))
}

pub fn a_new_cooldown_goes_through_the_kept_modifiers_in_the_order_they_were_added_test() -> Nil {
  use <- owned_test.run(5000)
  let kept =
    cooldown.new()
    |> cooldown.keep(
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: half(),
    )
    |> cooldown.keep(
      source: cast_support.source_of(cast_id: 1, effect_id: 2),
      modifier: minus_a_second(),
    )
  let book =
    cooldown.start(
      book: kept,
      keys: charged_shot_keys(),
      cooldown_ms: 10_000,
      now_ms: 0,
    )
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 0) == 4000
    as "0x14046a890: x0.5 first, then -1000 is 4000; the other order would give 4500"
}

pub fn dropping_a_source_takes_its_modifier_out_of_the_next_cooldown_test() -> Nil {
  use <- owned_test.run(5000)
  let kept =
    cooldown.new()
    |> cooldown.keep(
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: half(),
    )
    |> cooldown.keep(
      source: cast_support.source_of(cast_id: 1, effect_id: 2),
      modifier: minus_a_second(),
    )
    |> cooldown.drop(source: cast_support.source_of(cast_id: 1, effect_id: 1))
  let book =
    cooldown.start(
      book: kept,
      keys: charged_shot_keys(),
      cooldown_ms: 10_000,
      now_ms: 0,
    )
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 0) == 9000
    as "only the -1000 is left"
  let unchanged =
    cooldown.drop(
      book: kept,
      source: cast_support.source_of(cast_id: 2, effect_id: 9),
    )
  assert unchanged == kept
    as "a source that was never kept leaves the list as it was"
}

pub fn dropping_every_source_leaves_a_new_cooldown_full_test() -> Nil {
  use <- owned_test.run(5000)
  let kept =
    cooldown.new()
    |> cooldown.keep(
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: half(),
    )
    |> cooldown.keep(
      source: cast_support.source_of(cast_id: 2, effect_id: 2),
      modifier: half(),
    )
    |> cooldown.drop_all
  let book =
    cooldown.start(
      book: kept,
      keys: charged_shot_keys(),
      cooldown_ms: 10_000,
      now_ms: 0,
    )
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 0)
    == 10_000
}

pub fn a_source_kept_again_is_held_once_test() -> Nil {
  use <- owned_test.run(5000)
  let kept =
    cooldown.new()
    |> cooldown.keep(
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: half(),
    )
    |> cooldown.keep(
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: half(),
    )
  let book =
    cooldown.start(
      book: kept,
      keys: charged_shot_keys(),
      cooldown_ms: 10_000,
      now_ms: 0,
    )
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 0) == 5000
    as "the second go of a cast names the same source: one x0.5, not two"
}

pub fn a_kept_modifier_that_makes_the_time_zero_starts_no_cooldown_test() -> Nil {
  use <- owned_test.run(5000)
  let kept =
    cooldown.keep(
      book: cooldown.new(),
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: Modifier(
        selector: Base(Spell4BaseId(20_684)),
        operation: NoLonger(0.0),
      ),
    )
  let book =
    cooldown.start(
      book: kept,
      keys: charged_shot_keys(),
      cooldown_ms: 10_000,
      now_ms: 0,
    )
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 0) == 0
    as "0x14046a3d0 makes a new entry only for a time above 0, after the modifiers"
}

pub fn keeping_a_modifier_changes_no_running_cooldown_test() -> Nil {
  use <- owned_test.run(5000)
  let book =
    cooldown.keep(
      book: charged_shot_running(for_ms: 10_000, at: 0),
      source: cast_support.source_of(cast_id: 1, effect_id: 1),
      modifier: half(),
    )
  assert cooldown.left_ms(book:, spell4_id: Spell4Id(34_718), now_ms: 0)
    == 10_000
    as "0x14046b7f0 keeps the modifier, and changing the running cooldowns is its own call"
}
