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
import code_rule/syntax
import glance
import gleam/list
import gleam/result
import gleam/string

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
  breaches_of(
    rows:,
    families: list.map(told, fn(type_) {
      #(type_, case file_of(sources:, module: type_.0) {
        Ok(file) -> syntax.variants_of(file:, type_names: [type_.1])
        Error(Nil) -> []
      })
    }),
    sources:,
  )
}

/// What the rows break over the families `#(#(module, name), members)`: the same
/// breaches as `breaches`, for inputs that are the variants of a type or are read some
/// other way from the source (`connection_timers`). A row names its family by its
/// `module` and `type_name`.
pub fn breaches_of(
  rows rows: List(Row),
  families families: List(#(#(String, String), List(String))),
  sources sources: List(SourceFile),
) -> List(String) {
  let declared = fn(module, type_name) {
    case list.key_find(families, #(module, type_name)) {
      Ok(members) -> members
      Error(Nil) -> []
    }
  }
  let told_variants =
    list.flat_map(families, fn(family) {
      list.map(family.1, fn(name) { #(family.0, name) })
    })
  let covered =
    list.flat_map(rows, fn(row) {
      list.map(row.variants, fn(name) { #(#(row.module, row.type_name), name) })
    })
  list.flatten([
    list.filter(told_variants, fn(entry) { !list.contains(covered, entry) })
      |> list.map(fn(entry) { "no row for " <> entry.1 }),
    list.flat_map(rows, fn(row) {
      list.filter(row.variants, fn(name) {
        !list.contains(declared(row.module, row.type_name), name)
      })
      |> list.map(fn(name) { "a row for no variant: " <> name })
    }),
    list.unique(covered)
      |> list.filter(fn(entry) {
        list.count(covered, fn(other) { other == entry }) > 1
      })
      |> list.map(fn(entry) { "in two rows: " <> entry.1 }),
    list.flat_map(rows, fn(row) { cover_breaches(row:, sources:) }),
  ])
}

/// What one row's cover breaks.
fn cover_breaches(
  row row: Row,
  sources sources: List(SourceFile),
) -> List(String) {
  case row.cover {
    Independent(reason:) ->
      case list.length(words(reason)) < 3 {
        True ->
          list.map(row.variants, fn(name) {
            "the reason is no sentence: " <> name
          })
        False -> []
      }
    Owner(test_name:) ->
      case public_test(sources:, test_name:) {
        Ok(_) -> []
        Error(Nil) -> ["the test is missing or private: " <> test_name]
      }
    Order(test_name:) ->
      case public_test(sources:, test_name:) {
        Error(Nil) -> ["the test is missing or private: " <> test_name]
        Ok(file) -> {
          let named = names_in(file:, sources:)
          list.filter(row.variants, fn(name) { !list.contains(named, name) })
          |> list.map(fn(name) {
            "the test never names " <> name <> ": " <> test_name
          })
        }
      }
  }
}

/// What the failure table rows of the file break: a row naming no test and no
/// `cannot happen:` reason, and a row naming a test that is no public `_test` function
/// of the sources. A failure table is a doc table headed `Point | What happens`; each
/// of its rows names tests in backticks, as `module.function` or as the function alone.
pub fn failure_breaches(
  file file: SourceFile,
  sources sources: List(SourceFile),
) -> List(String) {
  failure_rows(file:)
  |> list.flat_map(fn(row) {
    let #(point, what) = row
    let tests = tests_named(what)
    let reasoned = case string.split_once(what, "cannot happen:") {
      Ok(#(_, reason)) -> list.length(words(reason)) >= 3
      Error(Nil) -> False
    }
    case tests, reasoned {
      [], False -> ["a failure row names no test and no reason: " <> point]
      _, _ ->
        list.filter(tests, fn(name) {
          result.is_error(public_test(sources:, test_name: name))
        })
        |> list.map(fn(name) {
          "a failure row names a missing or private test: " <> name
        })
    }
  })
}

/// The point and the what-happens cell of each row of each failure table of the file.
fn failure_rows(file file: SourceFile) -> List(#(String, String)) {
  let #(rows, _) =
    list.fold(string.split(file.text, "\n"), #([], False), fn(state, line) {
      let #(rows, inside) = state
      case string.starts_with(line, "//// |") {
        False -> #(rows, False)
        True ->
          case row_cells(line) {
            ["Point", "What happens"] -> #(rows, True)
            [point, what] if inside -> #([#(point, what), ..rows], True)
            _ -> #(rows, inside)
          }
      }
    })
  list.reverse(rows)
}

/// The cells of a `//// | a | b |` doc table line.
fn row_cells(line: String) -> List(String) {
  string.drop_start(line, 6)
  |> string.trim
  |> string.remove_suffix(" |")
  |> string.split(" | ")
}

/// The names in backticks that end `_test`, as written.
fn tests_named(text: String) -> List(String) {
  string.split(text, "`")
  |> list.index_map(fn(part, index) { #(part, index) })
  |> list.filter(fn(entry) {
    entry.1 % 2 == 1 && string.ends_with(entry.0, "_test")
  })
  |> list.map(fn(entry) { entry.0 })
}

/// The file of the module among the sources.
fn file_of(
  sources sources: List(SourceFile),
  module module: String,
) -> Result(SourceFile, Nil) {
  list.find(sources, fn(file) { syntax.module_name(file.path) == module })
}

/// The file with a public `_test` function written `module.function`, or the first of
/// the sources that has one of that name when written alone.
fn public_test(
  sources sources: List(SourceFile),
  test_name test_name: String,
) -> Result(SourceFile, Nil) {
  let #(files, function) = case string.split_once(test_name, ".") {
    Ok(#(module, function)) -> #(
      list.filter(sources, fn(file) { syntax.module_name(file.path) == module }),
      function,
    )
    Error(Nil) -> #(sources, test_name)
  }
  list.find(files, fn(file) {
    string.ends_with(function, "_test")
    && list.any(syntax.parse(file).functions, fn(definition) {
      definition.definition.name == function
      && definition.definition.publicity == glance.Public
    })
  })
}

/// The identifiers the file's text holds and those of each module it imports that is
/// among the sources.
fn names_in(
  file file: SourceFile,
  sources sources: List(SourceFile),
) -> List(String) {
  let supports =
    list.filter_map(syntax.imported_modules(file), fn(module) {
      file_of(sources:, module:)
    })
  list.flat_map([file, ..supports], fn(each) { identifiers(each.text) })
}

/// The identifiers of a text: its runs of letters, digits and underscores.
fn identifiers(text: String) -> List(String) {
  string.to_graphemes(text)
  |> list.map(fn(grapheme) {
    case is_identifier_grapheme(grapheme) {
      True -> grapheme
      False -> " "
    }
  })
  |> string.concat
  |> words
}

fn is_identifier_grapheme(grapheme: String) -> Bool {
  string.contains(
    "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    grapheme,
  )
}

fn words(text: String) -> List(String) {
  string.split(text, " ") |> list.filter(fn(word) { word != "" })
}

/// The timers the connection rule tells apart, read from its source (`game/connection`):
/// the `_timer` names `timer_due` compares the fired timer with, the module of each
/// `owns` check of `other_timer_fired`, and `claim`, the timer no `owns` check claims.
pub fn connection_timers(file file: SourceFile) -> List(String) {
  let _ = file
  []
}

/// The CamelCase names written in backticks in the cells of the file's failure tables
/// that are no type and no variant declared in `src/` (and no prelude name).
pub fn unknown_names(
  file file: SourceFile,
  sources sources: List(SourceFile),
) -> List(String) {
  let _ = sources
  let declared = []
  failure_rows(file:)
  |> list.flat_map(fn(row) { backticked_names(row.0 <> " " <> row.1) })
  |> list.unique
  |> list.filter(fn(name) {
    !list.contains(declared, name) && !list.contains(prelude_names, name)
  })
  |> list.map(fn(name) { "a failure row names no type or variant: " <> name })
}

/// The names the prelude gives, which no file of `src/` declares.
const prelude_names = ["True", "False", "Nil", "Ok", "Error"]

/// The CamelCase identifiers of two letters or more inside the backticks of a text: a
/// single capital (`V`) is a name the row gives a viewer or a player, not a type.
fn backticked_names(text: String) -> List(String) {
  string.split(text, "`")
  |> list.index_map(fn(part, index) { #(part, index) })
  |> list.filter(fn(entry) { entry.1 % 2 == 1 })
  |> list.flat_map(fn(entry) { identifiers(entry.0) })
  |> list.filter(fn(word) {
    case string.first(word) {
      Ok(first) -> first != string.lowercase(first) && string.length(word) > 1
      Error(Nil) -> False
    }
  })
}
