//// The owner's copy rule. Expected value is the rule: a player's connection keeps the
//// connections that see its player, each with its stay, unit and generation of the sight, in
//// `Entered.viewers` (genesis_prime/game/world_entry), and that copy has one writer, the
//// map's two notices: `SeenBy` and `UnseenBy`, taken by `map_sent` and `viewer_unseen` of
//// genesis_prime/game/connection/viewers through its one function `viewers_changed`; the
//// entry begins it empty. It has few readers: the mover, through `sorted_viewers`, which
//// addresses each viewer's move with the generation the copy holds, the five readers of an
//// address (`caster_of` twice and `attacker_of` of genesis_prime/game/connection/casting,
//// `changed` and `events_told` of genesis_prime/game/connection/landing), and the viewers'
//// own `map_sent`, `unit_departed` and `viewer_unseen`. A write or a read of the field in
//// another function of `src/genesis_prime/game` is a breach, reported at its line, and so is
//// a call of `viewers_changed` outside `map_sent` and `viewer_unseen`. The rule is shown on a
//// planted file, then read over the real ones.

import code_rule/planted
import code_rule/source.{type SourceFile}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

const game_directory = "src/genesis_prime/game"

const viewers_module = "src/genesis_prime/game/connection/viewers.gleam"

/// The functions that write the copy: the one function of the viewers' module, and the
/// entry, which starts it empty.
const writers = [
  #(viewers_module, "viewers_changed"),
  #("src/genesis_prime/game/world_entry.gleam", "joined"),
]

/// The functions that call the writer: the two notices.
const notice_takers = ["map_sent", "viewer_unseen"]

/// The functions that read the copy.
const readers = [
  #(viewers_module, "map_sent"),
  #(viewers_module, "viewer_unseen"),
  #(viewers_module, "unit_departed"),
  #(viewers_module, "viewers_changed"),
  #("src/genesis_prime/game/connection/state.gleam", "sorted_viewers"),
  #("src/genesis_prime/game/connection/casting.gleam", "caster_of"),
  #("src/genesis_prime/game/connection/casting.gleam", "attacker_of"),
  #("src/genesis_prime/game/connection/landing.gleam", "changed"),
  #("src/genesis_prime/game/connection/landing.gleam", "events_told"),
]

/// What a file does with the copy at a place: it writes it, reads it or calls the writer.
type Touch {
  Writes
  Reads
  CallsTheWriter
}

type Touched {
  Touched(line: Int, function: String, touch: Touch)
}

/// Whether the record update or the call builds an `Entered` with a `viewers:` field.
fn sets_viewers(expression expression: glance.Expression) -> Bool {
  case expression {
    glance.RecordUpdate(constructor:, fields:, ..) ->
      constructor == "Entered"
      && list.any(fields, fn(field) { field.label == "viewers" })
    glance.Call(function:, arguments:, ..) ->
      constructs_entered(function:)
      && list.any(arguments, fn(argument) {
        case argument {
          glance.LabelledField(label: "viewers", ..) -> True
          glance.LabelledField(..)
          | glance.UnlabelledField(..)
          | glance.ShorthandField(..) -> False
        }
      })
    _ -> False
  }
}

fn constructs_entered(function function: glance.Expression) -> Bool {
  case function {
    glance.Variable(name: "Entered", ..) -> True
    glance.FieldAccess(label: "Entered", ..) -> True
    _ -> False
  }
}

/// What the file touches of the copy, with the function that does it.
fn touches(file file: SourceFile) -> List(Touched) {
  let module = syntax.parse(file)
  list.flat_map(module.functions, fn(definition) {
    let function = definition.definition
    let inside =
      syntax.expressions(glance.Module(..module, functions: [definition]))
    list.filter_map(inside, fn(expression) {
      let line = fn(span: glance.Span) {
        syntax.line_of(text: file.text, byte_offset: span.start)
      }
      case expression {
        glance.FieldAccess(label: "viewers", location:, ..) ->
          Ok(Touched(
            line: line(location),
            function: function.name,
            touch: Reads,
          ))
        glance.Call(
          function: glance.Variable(name: "viewers_changed", ..),
          location:,
          ..,
        ) ->
          Ok(Touched(
            line: line(location),
            function: function.name,
            touch: CallsTheWriter,
          ))
        _ ->
          case sets_viewers(expression:) {
            True ->
              Ok(Touched(
                line: line(syntax.span_of(expression)),
                function: function.name,
                touch: Writes,
              ))
            False -> Error(Nil)
          }
      }
    })
  })
}

/// The touches of the file that the rule does not allow, in line order.
fn breaches(file file: SourceFile) -> List(String) {
  list.sort(touches(file:), fn(first, second) {
    int.compare(first.line, second.line)
  })
  |> list.filter_map(fn(touched) {
    let allowed = case touched.touch {
      Writes -> list.contains(writers, #(file.path, touched.function))
      Reads -> list.contains(readers, #(file.path, touched.function))
      CallsTheWriter ->
        file.path == viewers_module
        && list.contains(notice_takers, touched.function)
    }
    case allowed {
      True -> Error(Nil)
      False ->
        Ok(
          file.path
          <> ":"
          <> int.to_string(touched.line)
          <> " "
          <> touched.function
          <> case touched.touch {
            Writes -> " writes the copy"
            Reads -> " reads the copy"
            CallsTheWriter -> " calls the writer"
          },
        )
    }
  })
}

/// The functions of the file that touch the copy, for the check that the rule's lists
/// name real places.
fn touching_functions(file file: SourceFile) -> List(#(String, String)) {
  list.map(touches(file:), fn(touched) { #(file.path, touched.function) })
}

pub fn the_owners_copy_of_its_viewers_is_written_only_by_the_maps_two_notices_and_read_by_the_move_and_the_five_address_readers_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: game_directory <> "/connection/viewers.gleam", lines: [
      "fn map_sent(session, entered) {",
      "  viewers_changed(session:, change: dict.delete(_, by))",
      "}",
      "",
      "fn viewers_changed(session, change) {",
      "  Entered(..entered, viewers: change(entered.viewers))",
      "}",
      "",
      "fn a_stray_write(entered) {",
      "  world_entry.Entered(..entered, viewers: dict.new())",
      "}",
      "",
      "fn a_stray_read(entered) {",
      "  dict.get(entered.viewers, by)",
      "}",
      "",
      "fn a_stray_call(session) {",
      "  viewers_changed(session:, change: identity)",
      "}",
      "",
      "fn another_field(state) {",
      "  state.shown",
      "}",
    ])
  assert breaches(file: planted_file)
    == [
      game_directory
        <> "/connection/viewers.gleam:10 a_stray_write writes the copy",
      game_directory
        <> "/connection/viewers.gleam:14 a_stray_read reads the copy",
      game_directory
        <> "/connection/viewers.gleam:18 a_stray_call calls the writer",
    ]
    as "a write, a read and a call of the writer outside the allowed functions are found, and the writer, its callers and another field are not"
  let files = source.files(under: game_directory)
  assert list.flat_map(files, fn(file) { breaches(file:) }) == []
    as "the copy is written only through viewers_changed, which only the two notices call, and read only by the mover's sorted_viewers, the five readers of an address and the viewers' own notices"
  let touching = list.flat_map(files, fn(file) { touching_functions(file:) })
  assert list.all(list.append(writers, readers), fn(place) {
    list.contains(touching, place)
  })
    as "every function the rule names touches the copy: none of its lists is stale"
  assert string.contains(
    source.read(game_directory <> "/connection/movement.gleam"),
    "sorted_viewers",
  )
    as "the mover reads the copy through sorted_viewers"
}
