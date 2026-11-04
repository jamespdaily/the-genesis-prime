//// The file the check reads the literal area's peak from.

import event_wait
import gleam/int
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
