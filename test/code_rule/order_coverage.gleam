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
//// - An `Order` row's test takes each variant as the constructor of its type: the test
////   function, or a function of the tests it reaches by name (its own module's, a
////   module's imported unqualified or qualified as imported, alias included), writes the
////   variant in an expression, qualified by its module as that module is imported or
////   imported unqualified from it. A name written in a pattern, a string or a comment, in
////   the code under test, or another module's variant of the same name, is not taken. The
////   weakest check that reads code: a constructor written, not behaviour.
//// - An `Independent` row gives a reason of at least three words.
////
//// The failure tables of a module's doc comment are read by `failure_breaches`: a row
//// names a test that exists, or says `cannot happen:` and a reason.

import code_rule/source.{type SourceFile}
import code_rule/syntax
import glance
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/set
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
      #(type_, variants_in(sources:, module: type_.0, type_name: type_.1))
    }),
    sources:,
  )
}

/// The variants of the type of the module among the sources, in declaration order; none
/// for a module or a type the sources lack.
pub fn variants_in(
  sources sources: List(SourceFile),
  module module: String,
  type_name type_name: String,
) -> List(String) {
  case file_of(sources:, module:) {
    Ok(file) -> syntax.variants_of(file:, type_names: [type_name])
    Error(Nil) -> []
  }
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
  let reached = reached_by_test(rows:, sources:)
  list.flatten([
    list.filter(told_variants, fn(entry) { !list.contains(covered, entry) })
      |> list.map(fn(entry) { "no row for " <> written(entry) }),
    list.flat_map(rows, fn(row) {
      list.filter(row.variants, fn(name) {
        !list.contains(declared(row.module, row.type_name), name)
      })
      |> list.map(fn(name) {
        "a row for no variant: "
        <> written(#(#(row.module, row.type_name), name))
      })
    }),
    list.unique(covered)
      |> list.filter(fn(entry) {
        list.count(covered, fn(other) { other == entry }) > 1
      })
      |> list.map(fn(entry) { "in two rows: " <> written(entry) }),
    list.flat_map(rows, fn(row) { cover_breaches(row:, sources:, reached:) }),
  ])
}

/// The code each `Order` row's test reaches, by the test's name.
fn reached_by_test(
  rows rows: List(Row),
  sources sources: List(SourceFile),
) -> dict.Dict(String, List(glance.Module)) {
  let index =
    dict.from_list(
      list.filter_map(sources, fn(file) {
        case string.starts_with(file.path, "test/") {
          True -> Ok(#(syntax.module_name(file.path), file))
          False -> Error(Nil)
        }
      }),
    )
  list.filter_map(rows, fn(row) {
    case row.cover {
      Order(test_name:) ->
        result.map(public_test(sources:, test_name:), fn(file) {
          #(
            test_name,
            code_reached(
              index:,
              module: syntax.module_name(file.path),
              function: function_of(test_name),
            ),
          )
        })
      Owner(..) | Independent(..) -> Error(Nil)
    }
  })
  |> dict.from_list
}

/// An entry `#(#(module, type name), variant)` as `Type.Variant`.
fn written(entry: #(#(String, String), String)) -> String {
  entry.0.1 <> "." <> entry.1
}

/// What one row's cover breaks.
fn cover_breaches(
  row row: Row,
  sources sources: List(SourceFile),
  reached reached: dict.Dict(String, List(glance.Module)),
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
        Ok(_) -> {
          let code = result.unwrap(dict.get(reached, test_name), [])
          list.filter(row.variants, fn(name) { !takes(code:, row:, name:) })
          |> list.map(fn(name) {
            "the test never takes "
            <> written(#(#(row.module, row.type_name), name))
            <> ": "
            <> test_name
          })
        }
      }
  }
}

/// Whether the code writes the variant `name` of the row's module as a constructor.
fn takes(
  code code: List(glance.Module),
  row row: Row,
  name name: String,
) -> Bool {
  list.any(code, fn(module) {
    syntax.references_to(module:, from: [row.module], named: [name]) != []
  })
}

/// The function a test name `module.function` or `function` names.
fn function_of(test_name: String) -> String {
  case string.split_once(test_name, ".") {
    Ok(#(_, function)) -> function
    Error(Nil) -> test_name
  }
}

/// The modules of the tests among the sources, each cut to the functions the function of the module
/// reaches: by a bare name of its own module, by a name imported unqualified, or qualified
/// by the module's name as imported (alias included), through any number of modules.
fn code_reached(
  index index: dict.Dict(String, SourceFile),
  module module: String,
  function function: String,
) -> List(glance.Module) {
  let reached =
    reach(index:, pending: [#(module, function)], seen: set.new())
    |> set.to_list
    |> list.group(fn(entry) { entry.0 })
  list.filter_map(dict.to_list(reached), fn(entry) {
    use file <- result.try(dict.get(index, entry.0))
    let parsed = syntax.parse(file)
    let functions = list.map(entry.1, fn(each) { each.1 })
    Ok(
      glance.Module(
        ..parsed,
        functions: list.filter(parsed.functions, fn(each) {
          list.contains(functions, each.definition.name)
        }),
      ),
    )
  })
}

/// The `#(module, function)` entries reached from the pending ones.
fn reach(
  index index: dict.Dict(String, SourceFile),
  pending pending: List(#(String, String)),
  seen seen: set.Set(#(String, String)),
) -> set.Set(#(String, String)) {
  case pending {
    [] -> seen
    [entry, ..rest] ->
      case expand(index:, seen:, entry:) {
        Ok(found) ->
          reach(
            index:,
            pending: list.append(rest, found),
            seen: set.insert(seen, entry),
          )
        Error(Nil) -> reach(index:, pending: rest, seen:)
      }
  }
}

/// The entries the function of the entry mentions; none when it is seen, in no test
/// module or no function of its module.
fn expand(
  index index: dict.Dict(String, SourceFile),
  seen seen: set.Set(#(String, String)),
  entry entry: #(String, String),
) -> Result(List(#(String, String)), Nil) {
  use <- bool.guard(when: set.contains(seen, entry), return: Error(Nil))
  let #(module, name) = entry
  use file <- result.try(dict.get(index, module))
  let parsed = syntax.parse(file)
  let only = cut_to(module: parsed, function: name)
  case only.functions {
    [] -> Error(Nil)
    _ -> Ok(mentioned(name: module, module: parsed, only:))
  }
}

/// The module with only the function of that name.
fn cut_to(
  module module: glance.Module,
  function name: String,
) -> glance.Module {
  glance.Module(
    ..module,
    functions: list.filter(module.functions, fn(each) {
      each.definition.name == name
    }),
  )
}

/// The `#(module, function)` a name imported unqualified, under its alias if it has one,
/// stands for.
fn imported_unqualified(
  module module: glance.Module,
  name name: String,
) -> Result(#(String, String), Nil) {
  list.find_map(module.imports, fn(import_) {
    list.find_map(import_.definition.unqualified_values, fn(value) {
      case option.unwrap(value.alias, value.name) == name {
        True -> Ok(#(import_.definition.module, value.name))
        False -> Error(Nil)
      }
    })
  })
}

/// The `#(module, function)` entries the references of `only`, a cut of `module`, name.
fn mentioned(
  name own: String,
  module module: glance.Module,
  only only: glance.Module,
) -> List(#(String, String)) {
  list.filter_map(syntax.references(only), fn(reference) {
    case reference {
      syntax.Unqualified(name:, ..) ->
        result.or(imported_unqualified(module:, name:), Ok(#(own, name)))
      syntax.Qualified(qualifier:, name:, ..) ->
        list.find_map(module.imports, fn(import_) {
          case syntax.import_name(import_.definition) == Some(qualifier) {
            True -> Ok(#(import_.definition.module, name))
            False -> Error(Nil)
          }
        })
    }
  })
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
pub fn row_cells(line: String) -> List(String) {
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
pub fn file_of(
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

fn is_identifier_character(character: String) -> Bool {
  string.contains(
    "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    character,
  )
}

/// The identifiers of a text: its runs of letters, digits and underscores.
fn identifiers(text: String) -> List(String) {
  string.to_graphemes(text)
  |> list.map(fn(grapheme) {
    case is_identifier_character(grapheme) {
      True -> grapheme
      False -> " "
    }
  })
  |> string.concat
  |> words
}

fn words(text: String) -> List(String) {
  string.split(text, " ") |> list.filter(fn(word) { word != "" })
}

/// The timers the connection rule tells apart, read from its source (`game/connection`):
/// the `_timer` names `timer_due` compares the fired timer with, the module of each
/// `owns` check of `other_timer_fired`, and the function its last arm calls, which no
/// `owns` check claims.
pub fn connection_timers(file file: SourceFile) -> List(String) {
  let module = syntax.parse(file)
  let only = fn(name) {
    glance.Module(
      ..module,
      functions: list.filter(module.functions, fn(definition) {
        definition.definition.name == name
      }),
    )
  }
  let compared =
    list.filter_map(syntax.references(only("timer_due")), fn(reference) {
      case reference {
        syntax.Qualified(qualifier: "connection_state", name:, ..) ->
          case string.ends_with(name, "_timer") {
            True -> Ok(name)
            False -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    })
  let owners =
    list.filter_map(syntax.calls(only("other_timer_fired")), fn(call) {
      case call.called {
        syntax.CalledThroughVariable(variable:, label: "owns") -> Ok(variable)
        _ -> Error(Nil)
      }
    })
  list.flatten([compared, owners, fall_through(only("other_timer_fired"))])
}

/// The function the last arm of the function's last `case` calls, the arm no check before
/// it claims: none when the function ends otherwise.
fn fall_through(module: glance.Module) -> List(String) {
  let last_call = {
    use definition <- result.try(list.first(module.functions))
    use statement <- result.try(list.last(definition.definition.body))
    use clauses <- result.try(case statement {
      glance.Expression(glance.Case(clauses:, ..)) -> Ok(clauses)
      _ -> Error(Nil)
    })
    use clause <- result.try(list.last(clauses))
    case clause.body {
      glance.Call(function:, ..) -> Ok(syntax.called(function))
      _ -> Error(Nil)
    }
  }
  case last_call {
    Ok(syntax.CalledByName(name:)) -> [name]
    Ok(syntax.CalledThroughVariable(label:, ..)) -> [label]
    Ok(syntax.CalledOtherwise) | Error(Nil) -> []
  }
}

/// The CamelCase names written in backticks in the cells of the file's failure tables
/// that are no type and no variant declared in `src/` (and no prelude name).
pub fn unknown_names(
  file file: SourceFile,
  sources sources: List(SourceFile),
) -> List(String) {
  let declared =
    list.flat_map(sources, fn(source) {
      case string.starts_with(source.path, "src/") {
        True ->
          list.flat_map(syntax.parse(source).custom_types, fn(definition) {
            [
              definition.definition.name,
              ..list.map(definition.definition.variants, fn(variant) {
                variant.name
              })
            ]
          })
        False -> []
      }
    })
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
