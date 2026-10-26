//// The coverage measure as Markdown: one checklist per engine, to post on its
//// area issue and on the milestone's issue.

import genesis_prime/coverage/measurement.{type Measurement}

/// The Markdown of every engine's measure: a heading, the source and totals,
/// then one line per type, heaviest first: `- [ ] type N: R rows (S%)`, with
/// `[x]` when the engine handles the type.
pub fn render(measurements: List(Measurement)) -> String {
  todo as "renders the checklists"
}

/// A Markdown table with a row per engine: the types in use, the rows, the
/// zero values left out and the types handled. An engine whose types are not
/// recorded is "not measured".
pub fn totals(measurements: List(Measurement)) -> String {
  todo as "renders the totals"
}
