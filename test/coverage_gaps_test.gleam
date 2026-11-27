//// The gaps section of the coverage measure (`genesis_prime/coverage/gaps`). Expected values
//// are the section's own layout: a first line with the counts, then each area in the order
//// it is first met with a bullet for each of its entries in the order they were given; an
//// empty list says "no gaps". The registry's entries are checked by what they must be (plain,
//// not repeated, free of change-log words) and for one fixed entry of the quest module.

import genesis_prime/coverage/gaps
import genesis_prime/gap.{Entry}
import gleam/list
import gleam/string
import owned_test
import simplifile
import unitest

pub fn the_gaps_section_groups_entries_by_area_in_declared_order_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("coverage")
  let entries = [
    Entry(area: "Quest acceptance", missing: "first quest sentence"),
    Entry(area: "Vendors", missing: "first vendor sentence"),
    Entry(area: "Quest acceptance", missing: "second quest sentence"),
    Entry(area: "Items", missing: "item sentence"),
    Entry(area: "Vendors", missing: "second vendor sentence"),
  ]
  assert gaps.render(entries:)
    == string.join(
      [
        "Gaps the server has: 5 entries in 3 areas",
        "Quest acceptance:",
        "- first quest sentence",
        "- second quest sentence",
        "Vendors:",
        "- first vendor sentence",
        "- second vendor sentence",
        "Items:",
        "- item sentence",
      ],
      "\n",
    )
    as "one heading per area in first-seen order, the entries of an area in declared order"
}

pub fn the_gaps_section_counts_entries_and_areas_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("coverage")
  assert gaps.render(entries: [
      Entry(area: "Items", missing: "one"),
      Entry(area: "Items", missing: "two"),
    ])
    == "Gaps the server has: 2 entries in 1 areas\nItems:\n- one\n- two"
    as "the first line counts the entries and the areas"
  assert gaps.render(entries: []) == "Gaps the server has: no gaps"
    as "an empty list says so and is not blank"
}

pub fn the_registry_is_not_empty_and_each_entry_is_plain_and_unique_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["coverage", "gaps"])
  let entries = gaps.registry()
  assert list.contains(
    entries,
    Entry(
      area: "Quest acceptance",
      missing: "the reputation a quest needs, which the server does not hold",
    ),
  )
    as "the registry holds the quest module's reputation entry"
  assert gaps.breaches(entries:) == []
    as "no area or sentence is empty or only white space, no sentence holds a change-log word, no entry is listed twice"
  let plain = Entry(area: "Items", missing: "a sentence of what is missing")
  assert gaps.breaches(entries: [plain]) == [] as "a plain entry is no breach"
  assert list.length(gaps.breaches(entries: [plain, plain])) == 1
    as "a planted duplicate is one breach"
  assert list.length(
      gaps.breaches(entries: [
        Entry(area: "Items", missing: "   "),
        Entry(area: "\n", missing: "a sentence"),
      ]),
    )
    == 2
    as "a white-space area or sentence is a breach"
  assert list.length(
      gaps.breaches(entries: [
        Entry(area: "Items", missing: "the price is not read yet"),
        Entry(area: "Items", missing: "the server does it for now"),
        Entry(area: "Items", missing: "a known price"),
      ]),
    )
    == 2
    as "a change-log word is a breach, and a word that holds one (known) is not"
}

pub fn the_registry_holds_the_spell_plans_and_the_creatures_entries_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["registry", "coverage", "gaps"])
  let entries = gaps.registry()
  let known = [
    Entry(
      area: "Forced moves",
      missing: "a PositionSwitch forced move, which moves a player and has no data in the client",
    ),
    Entry(
      area: "Procs",
      missing: "a Proc on landing a critical heal, which never fires because no heal is rolled a critical",
    ),
    Entry(
      area: "Property modifiers",
      missing: "a conversion into the source of a conversion that started earlier: the earlier one does not see the change, so a chain of conversions does not settle",
    ),
    Entry(
      area: "Creature crowd control",
      missing: "a crowd-control state held by a creature when a viewer arrives: the viewer is not told of it, since the 0x262 does not carry it",
    ),
  ]
  list.each(known, fn(entry) {
    assert list.contains(entries, entry) as entry.missing
  })
}

pub fn the_registry_holds_the_item_refund_and_the_kind_4_point_count_entries_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["registry", "coverage", "gaps"])
  let entries = gaps.registry()
  let known = [
    Entry(
      area: "Item records",
      missing: "the length of the refund window a bought item gets and the message that asks for a refund: the server writes a refund window of 0 and no refund price, so no item can be refunded",
    ),
    Entry(
      area: "Movement paths",
      missing: "that a kind 4 command read from the client holds the number of points its path type needs: the codec does not check the count",
    ),
  ]
  list.each(known, fn(entry) {
    assert list.contains(entries, entry) as entry.missing
  })
}

pub fn the_measure_prints_the_gaps_section_with_every_registered_entry_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["coverage", "gaps"])
  let section = gaps.report()
  let entries = gaps.registry()
  assert entries != [] as "the registry is not empty"
  assert string.starts_with(section, "Gaps the server has: ")
  list.each(entries, fn(entry) {
    assert string.contains(section, entry.area <> ":\n")
      as { "the area of " <> entry.missing }
    assert string.contains(section, "- " <> entry.missing <> "\n")
      || string.ends_with(section, "- " <> entry.missing)
      as { "the sentence " <> entry.missing }
  })
}

pub fn the_dev_command_gap_entry_is_printed_by_the_registry_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["registry", "coverage", "gaps"])
  let proxy =
    Entry(
      area: "Development commands",
      missing: "`!item` of a proxy item, whose stack limit and deletable flag the client reads from another item",
    )
  assert list.contains(gaps.registry(), proxy)
    as "dev_command.gaps() is registered"
  assert string.contains(
    gaps.report(),
    "Development commands:\n- " <> proxy.missing,
  )
    as "the gaps section prints the entry under its area"
}

pub fn the_registry_holds_the_channel_pulse_and_the_unread_gain_column_gaps_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["registry", "coverage", "gaps"])
  let entries = gaps.registry()
  [
    #(
      "Spell phases",
      [
        "spellChannelFlags",
        "phaseFlags 1",
        "tickTime",
        "mask",
        "castMethod 3",
        "CrowdControl",
      ],
      "a channel without bit 1 fires a phaseFlags 1 row at every pulse, which leaves the masks, the tickTime rows, castMethod 3 and the unchecked crowd-control rows unread",
    ),
    #(
      "Resource gains",
      ["vital 8", "dataBits05", "0 points"],
      "a vital 8 gain of no points and a float in dataBits05 gives 0 points",
    ),
    #(
      "Resource gains",
      ["dataBits01", "dataBits02", "Focus"],
      "a Focus gain's points are read from dataBits02 where dataBits01 differs",
    ),
  ]
  |> list.each(fn(row) {
    let #(area, words, limit) = row
    assert list.any(entries, fn(entry) {
      entry.area == area
      && list.all(words, fn(word) { string.contains(entry.missing, word) })
    })
      as { limit <> " is stated as a gap" }
  })
}

pub fn the_registry_holds_the_objective_placement_ground_gaps_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["registry", "coverage", "gaps"])
  let entries = gaps.registry()
  [
    #(
      ["marker", "not on the ground", "has no ground read", "marker's height"],
      "a creature on the ring of a marker not on the ground, or with no ground read at its centre, stands at the marker's height",
    ),
    #(
      ["ring slot", "no ground read", "farther", "ring's radius plus 2"],
      "a ring slot with no ground read, or whose ground is outside the band of the ring's radius plus 2, stands at the marker's height",
    ),
  ]
  |> list.each(fn(row) {
    let #(words, limit) = row
    assert list.any(entries, fn(entry) {
      entry.area == "Objective creature placement"
      && list.all(words, fn(word) { string.contains(entry.missing, word) })
    })
      as { limit <> " is stated as a gap" }
  })
  assert !list.any(entries, fn(entry) {
    entry.area == "Objective creature placement"
    && string.contains(entry.missing, "used-object record")
  })
    as "a placed creature's used objects are kept across a login (its id is fixed by the client's tables), so no gap says they are not"
}

/// The words of a kind: `instance_run` is an instance run.
fn kind_words(kind kind: String) -> String {
  string.replace(kind, "_", " ")
}

/// The kinds the table's check constraint lists, read from the last migration that states it
/// (a later migration drops and adds the constraint again): the quoted words after `in (`.
/// Returns the list's text and its words.
fn held_objective_kinds() -> #(String, List(String)) {
  let folder = "priv/migrations"
  let assert Ok(files) = simplifile.read_directory(folder)
    as "the migration folder is read"
  let texts =
    files
    |> list.filter(string.ends_with(_, ".sql"))
    |> list.sort(string.compare)
    |> list.filter_map(fn(file) {
      let assert Ok(text) = simplifile.read(folder <> "/" <> file)
        as { "the migration " <> file <> " is read" }
      case string.contains(text, "constraint held_objective_kind_is_known") {
        True -> Ok(text)
        False -> Error(Nil)
      }
    })
  let assert Ok(text) = list.last(texts)
    as "a migration states held_objective_kind_is_known"
  let assert Ok(after_name) =
    string.split(text, "constraint held_objective_kind_is_known")
    |> list.last
    as "the constraint name is met in the migration"
  let assert [_, list_and_rest] = string.split(after_name, "in (")
    as "the constraint is a check of kind in a list"
  let assert [kind_list, ..] = string.split(list_and_rest, ")")
  let kinds =
    kind_list
    |> string.split("'")
    |> list.index_map(fn(part, index) { #(index, part) })
    |> list.filter_map(fn(pair) {
      case pair.0 % 2 {
        1 -> Ok(pair.1)
        _ -> Error(Nil)
      }
    })
  #(kind_list, kinds)
}

pub fn the_held_objective_gap_names_each_kind_the_table_holds_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["coverage", "gaps"])
  let #(definition, kinds) = held_objective_kinds()
  assert list.length(kinds) == 3
    as { "the table's kind check lists three kinds: " <> definition }
  let sentences =
    gaps.registry()
    |> list.filter(fn(entry) { entry.area == "Quest objectives" })
    |> list.map(fn(entry) { string.lowercase(entry.missing) })
    |> list.filter(fn(sentence) { string.contains(sentence, "held") })
  assert list.length(sentences) == 1
    as "one Quest objectives entry is about the held objectives"
  let assert [sentence] = sentences
  list.each(kinds, fn(kind) {
    assert string.contains(sentence, kind_words(kind:))
      as { "the entry names the kind " <> kind }
  })
  assert string.contains(sentence, "0x400")
    && string.contains(sentence, "content-finder")
    && string.contains(sentence, "text")
    as "it says what marks a held objective: the objective's flag 0x400, the quest's content-finder type or the objective's text"
  assert !string.contains(sentence, "do not say")
    as "it does not say the client's tables mark none of them"
}

pub fn the_creature_spell_gap_names_the_guessed_order_and_cooldown_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["coverage", "gaps"])
  let sentences =
    gaps.registry()
    |> list.filter(fn(entry) { entry.area == "Creature specials" })
    |> list.map(fn(entry) { string.lowercase(entry.missing) })
    |> list.filter(fn(sentence) { string.contains(sentence, "retail") })
  assert list.length(sentences) == 1
    as "one Creature specials entry is about the retail creature spells"
  let assert [sentence] = sentences
  assert string.contains(sentence, "order")
    && string.contains(sentence, "cooldown")
    && string.contains(sentence, "guess")
    as "it says their order and cooldown are guesses"
  assert string.contains(sentence, "lowest tier")
    as "it says that of a spell listed at several tiers the lowest tier is kept"
}

pub fn the_focus_pool_gap_names_the_flat_pool_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tags(["coverage", "gaps"])
  let sentences =
    gaps.registry()
    |> list.filter(fn(entry) { entry.area == "Focus" })
    |> list.map(fn(entry) { string.lowercase(entry.missing) })
    |> list.filter(fn(sentence) { string.contains(sentence, "flat") })
  assert list.length(sentences) == 1 as "one Focus entry is about the flat pool"
  let assert [sentence] = sentences
  assert string.contains(sentence, "1000") && string.contains(sentence, "flat")
    as "it says the pool is a flat 1000"
  assert string.contains(sentence, "worn items")
    as "it says worn items add to the flat pool"
}
