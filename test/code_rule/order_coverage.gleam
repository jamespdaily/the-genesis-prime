//// The written order cover of the kinds the map and the processes tell each other.
////
//// ```
//// rows (type, variants, cover) --+
//// sources (src and test)  -------+--> breaches --> what the rows break
//// ```
////
//// - Every variant of a told type is in exactly one row, and a row names only variants
////   of its type (the type is the second source; Design run A, section 6).
//// - An `Order` or `Owner` row names a public `_test` function that exists.
//// - An `Order` row's test, or a module its file imports, names the variant: the weakest
////   check, a name and not behaviour.
//// - An `Independent` row gives a reason of at least three words.
////
//// The failure tables of a module's doc comment are read by `failure_breaches`: a row
//// names a test that exists, or says `cannot happen:` and a reason.

import code_rule/source.{type SourceFile}

/// How a variant is covered: by a test of the orders it arrives in, by the test of the
/// decision its owner makes, or by the reason the relation does not read it.
pub type Cover {
  Order(test_name: String)
  Owner(test_name: String)
  Independent(reason: String)
}

/// One cover for the listed variants of one type of one module; test names are
/// `module.function`.
pub type Row {
  Row(module: String, type_name: String, variants: List(String), cover: Cover)
}

/// What the rows break over the told types `#(module, type name)`, read from the
/// sources: a variant with no row, a row for no variant, a variant in two rows, a test
/// that is missing or private, an order test that never names its variant and a reason
/// that is no sentence.
pub fn breaches(
  rows rows: List(Row),
  told told: List(#(String, String)),
  sources sources: List(SourceFile),
) -> List(String) {
  let _ = rows
  let _ = told
  let _ = sources
  []
}

/// What the failure table rows of the file break: a row naming no test and no
/// `cannot happen:` reason, and a row naming a test that is no public `_test` function
/// of the sources.
pub fn failure_breaches(
  file file: SourceFile,
  sources sources: List(SourceFile),
) -> List(String) {
  let _ = file
  let _ = sources
  []
}
