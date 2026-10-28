//// The digest of a rule's types: the full signatures of its `new` and `step`
//// functions, with every type argument, and the definition of every custom
//// type or alias those reach through their constructors' fields, across the
//// project's modules, read from the source with glance. A recording's header
//// holds the digest it was made under; a replay compares it with the digest as
//// the code stands, so a recording from other types fails with "record again"
//// and never folds into a wrong value. A change to a function body leaves the
//// digest as it is. A type from a package is followed into the package's
//// source under `build/packages`, so an upgrade that changes it changes the
//// digest; a prelude type (`Int`, `List` and the like) is named, since the
//// compiler fixes it.

import glance
import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import simplifile

/// Why the digest could not be made.
pub type DigestError {
  /// The rule's module has no `pub fn step` or no `pub fn new`, or one of
  /// them leaves a parameter or its return type unwritten.
  NotARule(module: String)
  /// A module the types reach could not be read or parsed.
  Unreadable(module: String, reason: String)
}

type Modules =
  Dict(String, glance.Module)

/// A module, by its path and its parsed source, for resolving the names
/// written in it.
type Context {
  Context(name: String, module: glance.Module)
}

/// The digest of the rule module's types, read from the folders of
/// `source_roots` (the project's `src`, and `test` for a rule there): the
/// SHA-256 of a canonical print of the two signatures and of each type
/// reached, in a fixed order, as lower-case hexadecimal.
pub fn digest(
  rule_module rule_module: String,
  source_roots source_roots: List(String),
) -> Result(String, DigestError) {
  use packages <- result.try(package_sources())
  let source_roots = list.append(source_roots, packages)
  use #(module, modules) <- result.try(load(
    name: rule_module,
    source_roots:,
    modules: dict.new(),
  ))
  let context = Context(name: rule_module, module:)
  use signatures <- result.try(
    list.try_map(["new", "step"], signature(_, context)),
  )
  let roots =
    list.flat_map(signatures, fn(found) {
      list.flat_map(found.1, named_types(_, context))
    })
  use #(definitions, _) <- result.map(
    follow(queue: roots, source_roots:, modules:, seen: set.new(), printed: []),
  )
  list.map(signatures, fn(found) {
    found.0 <> "(" <> print_all(found.1, context) <> ")"
  })
  |> list.append(list.sort(definitions, string.compare))
  |> string.join("\n")
  |> bit_array.from_string
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base16_encode
  |> string.lowercase
}

/// A public function's name, then its parameter types and its return type.
fn signature(
  name: String,
  context: Context,
) -> Result(#(String, List(glance.Type)), DigestError) {
  let not_a_rule = NotARule(context.name)
  use found <- result.try(
    list.find(context.module.functions, fn(definition) {
      definition.definition.name == name
      && definition.definition.publicity == glance.Public
    })
    |> result.replace_error(not_a_rule),
  )
  let function = found.definition
  use parameters <- result.try(
    list.try_map(function.parameters, fn(parameter) {
      option.to_result(parameter.type_, not_a_rule)
    }),
  )
  use returned <- result.map(option.to_result(function.return, not_a_rule))
  #(name, list.append(parameters, [returned]))
}

fn load(
  name name: String,
  source_roots source_roots: List(String),
  modules modules: Modules,
) -> Result(#(glance.Module, Modules), DigestError) {
  case dict.get(modules, name) {
    Ok(module) -> Ok(#(module, modules))
    Error(Nil) -> {
      use path <- result.try(
        path_of(name, source_roots)
        |> result.replace_error(Unreadable(name, "no source folder holds it")),
      )
      use text <- result.try(
        simplifile.read(path)
        |> result.map_error(fn(error) {
          Unreadable(name, simplifile.describe_error(error))
        }),
      )
      use module <- result.map(
        glance.module(text)
        |> result.replace_error(Unreadable(name, "it does not parse")),
      )
      #(module, dict.insert(modules, name, module))
    }
  }
}

/// The source folder of every package the project's build holds.
fn package_sources() -> Result(List(String), DigestError) {
  simplifile.read_directory("build/packages")
  |> result.map(fn(names) {
    list.sort(names, string.compare)
    |> list.map(fn(name) { "build/packages/" <> name <> "/src" })
  })
  |> result.map_error(fn(error) {
    Unreadable("build/packages", simplifile.describe_error(error))
  })
}

/// The file of a module, in the first source folder that holds it.
fn path_of(
  module_name: String,
  source_roots: List(String),
) -> Result(String, Nil) {
  list.find_map(source_roots, fn(root) {
    let path = root <> "/" <> module_name <> ".gleam"
    case simplifile.is_file(path) {
      Ok(True) -> Ok(path)
      Ok(False) | Error(_) -> Error(Nil)
    }
  })
}

/// Follows each named type to its definition in the project, printing each
/// once. A type whose module is not in the project is not followed.
fn follow(
  queue queue: List(#(String, String)),
  source_roots source_roots: List(String),
  modules modules: Modules,
  seen seen: Set(#(String, String)),
  printed printed: List(String),
) -> Result(#(List(String), Modules), DigestError) {
  case queue {
    [] -> Ok(#(printed, modules))
    [found, ..rest] -> {
      let skip =
        set.contains(seen, found)
        || {
          !dict.has_key(modules, found.0)
          && path_of(found.0, source_roots) == Error(Nil)
        }
      case skip {
        True ->
          follow(
            queue: rest,
            source_roots:,
            modules:,
            seen: set.insert(seen, found),
            printed:,
          )
        False -> {
          use #(module, modules) <- result.try(load(
            name: found.0,
            source_roots:,
            modules:,
          ))
          let #(text, reached) =
            definition(found.1, Context(name: found.0, module:))
          follow(
            queue: list.append(rest, reached),
            source_roots:,
            modules:,
            seen: set.insert(seen, found),
            printed: [text, ..printed],
          )
        }
      }
    }
  }
}

/// The canonical print of one type's definition and the named types its
/// fields reach.
fn definition(
  type_name: String,
  context: Context,
) -> #(String, List(#(String, String))) {
  let qualified = context.name <> "." <> type_name
  let custom =
    list.find(context.module.custom_types, fn(found) {
      found.definition.name == type_name
    })
  let alias =
    list.find(context.module.type_aliases, fn(found) {
      found.definition.name == type_name
    })
  case custom, alias {
    Ok(found), _ -> custom_type(custom: found.definition, qualified:, context:)
    Error(Nil), Ok(found) -> #(
      "alias "
        <> qualified
        <> "("
        <> string.join(found.definition.parameters, ", ")
        <> ") = "
        <> print(found.definition.aliased, context),
      named_types(found.definition.aliased, context),
    )
    Error(Nil), Error(Nil) -> #("missing " <> qualified, [])
  }
}

fn custom_type(
  custom custom: glance.CustomType,
  qualified qualified: String,
  context context: Context,
) -> #(String, List(#(String, String))) {
  let field_types =
    list.flat_map(custom.variants, fn(variant) {
      list.map(variant.fields, field_type)
    })
  let variants =
    list.map(custom.variants, fn(variant) {
      let fields =
        list.map(variant.fields, fn(field) {
          case field {
            glance.LabelledVariantField(item:, label:) ->
              label <> ": " <> print(item, context)
            glance.UnlabelledVariantField(item:) -> print(item, context)
          }
        })
      variant.name <> "(" <> string.join(fields, ", ") <> ")"
    })
  #(
    "type "
      <> qualified
      <> "("
      <> string.join(custom.parameters, ", ")
      <> ") = "
      <> string.join(variants, " | "),
    list.flat_map(field_types, named_types(_, context)),
  )
}

fn field_type(field: glance.VariantField) -> glance.Type {
  case field {
    glance.LabelledVariantField(item:, ..) -> item
    glance.UnlabelledVariantField(item:) -> item
  }
}

/// Every named type in a type, each as its module and name.
fn named_types(
  type_: glance.Type,
  context: Context,
) -> List(#(String, String)) {
  case type_ {
    glance.NamedType(name:, module: qualifier, parameters:, ..) -> [
      resolve(name:, qualifier:, context:),
      ..list.flat_map(parameters, named_types(_, context))
    ]
    glance.TupleType(elements:, ..) ->
      list.flat_map(elements, named_types(_, context))
    glance.FunctionType(parameters:, return:, ..) ->
      list.flat_map([return, ..parameters], named_types(_, context))
    glance.VariableType(..) | glance.HoleType(..) -> []
  }
}

/// Types as text, separated by commas.
fn print_all(types: List(glance.Type), context: Context) -> String {
  string.join(list.map(types, print(_, context)), ", ")
}

/// A type as text, each name written with its full module.
fn print(type_: glance.Type, context: Context) -> String {
  case type_ {
    glance.NamedType(name:, module: qualifier, parameters:, ..) -> {
      let #(defined_in, real_name) = resolve(name:, qualifier:, context:)
      let arguments = case parameters {
        [] -> ""
        _ -> "(" <> print_all(parameters, context) <> ")"
      }
      defined_in <> "." <> real_name <> arguments
    }
    glance.TupleType(elements:, ..) ->
      "#(" <> print_all(elements, context) <> ")"
    glance.FunctionType(parameters:, return:, ..) ->
      "fn("
      <> print_all(parameters, context)
      <> ") -> "
      <> print(return, context)
    glance.VariableType(name:, ..) -> name
    glance.HoleType(name:, ..) -> name
  }
}

/// The module that defines a type named in the context's module, and its name
/// there: through a qualified import, an unqualified one, the module itself,
/// or the prelude, written `gleam`.
fn resolve(
  name name: String,
  qualifier qualifier: Option(String),
  context context: Context,
) -> #(String, String) {
  let imports = list.map(context.module.imports, fn(found) { found.definition })
  case qualifier {
    Some(alias) ->
      list.find(imports, fn(found) { import_name(found) == alias })
      |> result.map(fn(found) { #(found.module, name) })
      |> result.unwrap(#(alias, name))
    None ->
      case defined_in(name, context.module) {
        True -> #(context.name, name)
        False ->
          list.find_map(imports, unqualified(_, name))
          |> result.unwrap(#("gleam", name))
      }
  }
}

fn defined_in(name: String, module: glance.Module) -> Bool {
  list.any(module.custom_types, fn(found) { found.definition.name == name })
  || list.any(module.type_aliases, fn(found) { found.definition.name == name })
}

/// The module and real name of a type an import brings in unqualified as
/// `name`.
fn unqualified(
  found: glance.Import,
  name: String,
) -> Result(#(String, String), Nil) {
  list.find_map(found.unqualified_types, fn(item) {
    case item.alias {
      Some(alias) if alias == name -> Ok(#(found.module, item.name))
      None if item.name == name -> Ok(#(found.module, name))
      Some(_) | None -> Error(Nil)
    }
  })
}

/// The name a module is used by where it is imported: its alias, or its last
/// segment.
fn import_name(found: glance.Import) -> String {
  case found.alias {
    Some(glance.Named(alias)) -> alias
    Some(glance.Discarded(alias)) -> alias
    None ->
      string.split(found.module, "/")
      |> list.last
      |> result.unwrap(found.module)
  }
}
