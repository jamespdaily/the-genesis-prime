//// The file the check reads the literal area's peak from.

import character_tables
import event_wait
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import literal_area
import owned_test
import planted_table
import simplifile

/// The peak the file holds, or 0 while the sampler has not written it yet.
fn peak_in(file: String) -> Int {
  let text = result.unwrap(simplifile.read(file), "0")
  case int.parse(string.trim(text)) {
    Ok(peak) -> peak
    Error(Nil) -> panic as { "the file holds no whole number: " <> text }
  }
}

pub fn the_sampler_writes_a_peak_no_lower_than_the_persistent_terms_held_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- planted_table.in_folder([])
  let file = folder <> "/peak"
  // The VM's carriers hold at least the bytes of its persistent terms: the
  // terms are blocks in them. Read before the sampler starts, so the file
  // cannot hold a peak older than it.
  let held = literal_area.persistent_term_memory()
  literal_area.record_peak(into: file)
  event_wait.until("the sampler wrote a peak of at least the terms held", fn() {
    peak_in(file) >= held
  })
}

pub fn the_peak_in_the_file_never_falls_below_a_peak_it_has_shown_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- planted_table.in_folder([])
  let file = folder <> "/peak"
  literal_area.record_peak(into: file)
  event_wait.until("the sampler wrote a peak", fn() { peak_in(file) > 0 })
  let shown = peak_in(file)
  assert literal_area.carriers_peak() >= shown
    as "the allocator's own record is never lower than what the file showed"
}

/// What a load's table term is stored under in the persistent terms, as
/// genesis_prime/table/loader/store writes it: `{Load, {table_term, Name}}`.
type TermName {
  TableTerm(name: String)
}

/// A term of more than a megabyte: a list cell takes two words.
fn megabyte_term(cells: Int) -> List(Int) {
  list.repeat(0, cells)
}

pub fn a_planted_table_named_as_a_real_one_is_not_a_second_copy_of_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let real = #(#(1, TableTerm("Spell4Effects")), megabyte_term(80_000))
  let planted = #(#(2, TableTerm("Spell4Effects")), megabyte_term(70_000))
  assert literal_area.names_held_twice(in: [real, planted]) == []
    as "a planted Spell4Effects over a megabyte (character_tables.shared_with_spell_trees) differs in size from the client's, so it is not the client's table loaded twice"
}

pub fn the_same_table_under_two_loads_is_held_twice_test() -> Nil {
  use <- owned_test.run(60_000)
  let first = #(#(1, TableTerm("Creature2")), megabyte_term(70_000))
  let second = #(#(2, TableTerm("Creature2")), megabyte_term(70_000))
  assert literal_area.names_held_twice(in: [first, second]) == ["Creature2"]
    as "two loads of one file hold terms of the same name and size"
}

pub fn the_held_twice_pattern_matches_the_keys_the_store_writes_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shared planted load is held for the whole run (database_support.once).
  let _tables = character_tables.shared()
  assert list.contains(literal_area.table_names(), "WorldLocation2")
    as "the store writes a table's term under {Load, {table_term, Name}}, the pattern tables_held_twice reads: a change to the store's key would make the held-twice count match nothing and pass"
}
