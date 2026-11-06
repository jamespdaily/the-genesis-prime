//// The file the check reads the literal area's peak from.

import character_tables
import event_wait
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import literal_area
import owned_key
import owned_test
import planted_table
import simplifile
import unitest

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

/// Thirty-two megabytes in one term: a list cell takes two words.
fn big_term() -> List(Int) {
  list.repeat(0, 2_000_000)
}

/// What the probe terms are stored under.
type ProbeKey {
  ProbeKey(number: Int)
}

@external(erlang, "persistent_term", "put")
fn put_term(key: ProbeKey, term: List(Int)) -> a

@external(erlang, "persistent_term", "erase")
fn erase_term(key: ProbeKey) -> Bool

const two_megabytes = 2_097_152

pub fn a_live_term_is_not_pending_and_an_erased_one_is_released_by_the_wait_test() -> Nil {
  // The terms of every other test sit in the same VM's allocator, so only the
  // serial run, which has the VM to itself, can read the allocator's whole
  // account.
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  literal_area.wait_until_released()
  let before = literal_area.pending_bytes()
  let _stored = put_term(ProbeKey(1), big_term())
  assert literal_area.pending_bytes() < before + two_megabytes
    as "a term that is live is in the persistent terms' memory, so it is not pending"
  assert erase_term(ProbeKey(1)) as "the probe term was stored"
  literal_area.wait_until_released()
  assert literal_area.pending_bytes() <= literal_area.pending_limit_bytes()
    as "the wait returns only once what the allocator holds beyond the live terms is within the limit"
}

pub fn the_wait_outlasts_erased_terms_that_hold_more_than_the_limit_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  literal_area.wait_until_released()
  let _first = put_term(ProbeKey(1), big_term())
  let _second = put_term(ProbeKey(2), big_term())
  let _third = put_term(ProbeKey(3), big_term())
  assert erase_term(ProbeKey(1))
    && erase_term(ProbeKey(2))
    && erase_term(ProbeKey(3))
    as "the probe terms were stored"
  literal_area.wait_until_released()
  assert literal_area.pending_bytes() <= literal_area.pending_limit_bytes()
    as "96 MB erased at once are released before the wait returns"
}

pub fn a_key_made_for_a_test_load_waits_for_the_collector_first_test() -> Nil {
  use <- owned_test.run(60_000)
  let before = literal_area.admissions()
  let _key = owned_key.new()
  assert literal_area.admissions() > before
    as "owned_key.new calls wait_until_released before it hands the key out"
}

pub fn a_store_key_made_for_a_test_waits_for_the_collector_first_test() -> Nil {
  use <- owned_test.run(60_000)
  let before = literal_area.admissions()
  let _key = owned_key.new_key()
  assert literal_area.admissions() > before
    as "owned_key.new_key calls wait_until_released before it hands the key out"
}

pub fn a_fixture_key_made_for_a_test_waits_for_the_collector_first_test() -> Nil {
  use <- owned_test.run(60_000)
  let before = literal_area.admissions()
  let _key = owned_key.new_fixture_key()
  assert literal_area.admissions() > before
    as "owned_key.new_fixture_key calls wait_until_released before it hands the key out"
}

/// What a planted extra load's terms are stored under.
type ExtraLoadKey {
  ExtraLoadKey(number: Int)
}

@external(erlang, "persistent_term", "put")
fn put_extra_term(key: ExtraLoadKey, term: List(Int)) -> a

@external(erlang, "persistent_term", "erase")
fn erase_extra_term(key: ExtraLoadKey) -> Bool

pub fn a_planted_extra_load_is_in_the_peak_the_check_compares_with_its_limit_test() -> Nil {
  // The allocator's record is the whole VM's, so only the serial run, which has
  // the VM to itself, can tell a rise one test made.
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  let held = literal_area.persistent_term_memory()
  let keys = [
    ExtraLoadKey(1),
    ExtraLoadKey(2),
    ExtraLoadKey(3),
    ExtraLoadKey(4),
  ]
  list.each(keys, fn(key) { put_extra_term(key, big_term()) })
  let peak_with_the_load = literal_area.carriers_peak()
  list.each(keys, fn(key) {
    assert erase_extra_term(key) as "the extra load was stored"
  })
  // Four terms of 2,000,000 list cells, 16 bytes each, held with the terms the
  // VM held before: the carriers hold at least those bytes together.
  assert peak_with_the_load >= held + 4 * 2_000_000 * 16
    as "a load held on top of the live terms is in the highest carriers size, the number ./check fails over its limit (setup_check/test_check_script.py plants a peak over it)"
}
