//// The message module rule (the Design artifact of issue 1483, section 3.1): a message
//// module holds the inbox type of a process and the types its constructors carry, and no
//// function, so no function of it can read or change a state. A breach is a function of
//// the module, at its first line, and a type the module is meant to hold and does not.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/int
import gleam/list

/// A breach for each function of the file, at the function's line, and for each of the
/// `types` that the file does not define, at line 1.
pub fn breaches(
  file file: SourceFile,
  types types: List(String),
) -> List(Breach) {
  let module = syntax.parse(file)
  let functions =
    module.functions
    |> list.map(fn(definition) {
      Breach(
        path: file.path,
        line: syntax.line_of(
          text: file.text,
          byte_offset: definition.definition.location.start,
        ),
        rule: "a message module holds no function, and "
          <> definition.definition.name
          <> " is one",
      )
    })
  let missing =
    types
    |> list.filter(fn(name) {
      !list.any(module.custom_types, fn(definition) {
        definition.definition.name == name
      })
    })
    |> list.map(fn(name) {
      Breach(
        path: file.path,
        line: 1,
        rule: "the message module defines no type " <> name,
      )
    })
  list.append(
    missing,
    list.sort(functions, fn(first, second) {
      int.compare(first.line, second.line)
    }),
  )
}
