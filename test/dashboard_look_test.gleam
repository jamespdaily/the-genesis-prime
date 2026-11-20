//// The dashboard's look and its packages, read from the files. Expected
//// values are the look's rule (the stylesheet and the views name a colour or
//// a font only by role, and a palette file is the one place that gives a
//// value, so a new look is a swap of that file) and the shipment's rule (the
//// image holds no development dependency).

import dashboard_support
import gleam/dict
import gleam/list
import gleam/set
import gleam/string
import owned_test
import simplifile
import tom

/// The 23 roles a palette defines: 20 colours and 3 fonts.
const roles = [
  "--ground", "--surface", "--raised", "--line", "--line-strong", "--text",
  "--text-dim", "--text-faint", "--log-ground", "--accent", "--accent-wash",
  "--on-accent", "--data", "--data-wash", "--ok", "--warn", "--warn-wash",
  "--bad", "--bad-wash", "--idle", "--font-title", "--font-text", "--font-code",
]

const stylesheet_folder = "dev/dashboard"

fn read(path: String) -> String {
  let assert Ok(text) = simplifile.read(path) as { "could not read " <> path }
  text
}

fn palette_files() -> List(String) {
  let assert Ok(names) = simplifile.read_directory(stylesheet_folder)
    as "the stylesheet folder could not be read"
  list.filter(names, fn(name) {
    string.starts_with(name, "palette") && string.ends_with(name, ".css")
  })
  |> list.sort(string.compare)
  |> list.map(fn(name) { stylesheet_folder <> "/" <> name })
}

/// The custom properties the `:root` block of a stylesheet defines.
fn defined_roles(css: String) -> List(String) {
  let assert [_, after_root] = string.split(css, ":root")
    as "a palette has one :root block"
  let assert [block, ..] = string.split(after_root, "}")
  string.split(block, "\n")
  |> list.filter_map(fn(line) {
    let line = string.trim(line)
    case string.starts_with(line, "--"), string.split_once(line, ":") {
      True, Ok(#(name, _)) -> Ok(name)
      _, _ -> Error(Nil)
    }
  })
}

pub fn every_palette_defines_every_role_test() -> Nil {
  use <- owned_test.run(5000)
  let files = palette_files()
  let assert [_, ..] = files as "no palette file"
  list.each(files, fn(file) {
    let defined = defined_roles(read(file))
    assert set.from_list(defined) == set.from_list(roles) as file
    assert list.length(defined) == 23 as { file <> " defines a role twice" }
  })
}

/// The CSS named colours (Color Module Level 4).
const colour_names = [
  "aliceblue", "antiquewhite", "aqua", "aquamarine", "azure", "beige", "bisque",
  "black", "blanchedalmond", "blue", "blueviolet", "brown", "burlywood",
  "cadetblue", "chartreuse", "chocolate", "coral", "cornflowerblue", "cornsilk",
  "crimson", "cyan", "darkblue", "darkcyan", "darkgoldenrod", "darkgray",
  "darkgreen", "darkgrey", "darkkhaki", "darkmagenta", "darkolivegreen",
  "darkorange", "darkorchid", "darkred", "darksalmon", "darkseagreen",
  "darkslateblue", "darkslategray", "darkslategrey", "darkturquoise",
  "darkviolet", "deeppink", "deepskyblue", "dimgray", "dimgrey", "dodgerblue",
  "firebrick", "floralwhite", "forestgreen", "fuchsia", "gainsboro",
  "ghostwhite", "gold", "goldenrod", "gray", "green", "greenyellow", "grey",
  "honeydew", "hotpink", "indianred", "indigo", "ivory", "khaki", "lavender",
  "lavenderblush", "lawngreen", "lemonchiffon", "lightblue", "lightcoral",
  "lightcyan", "lightgoldenrodyellow", "lightgray", "lightgreen", "lightgrey",
  "lightpink", "lightsalmon", "lightseagreen", "lightskyblue", "lightslategray",
  "lightslategrey", "lightsteelblue", "lightyellow", "lime", "limegreen",
  "linen", "magenta", "maroon", "mediumaquamarine", "mediumblue", "mediumorchid",
  "mediumpurple", "mediumseagreen", "mediumslateblue", "mediumspringgreen",
  "mediumturquoise", "mediumvioletred", "midnightblue", "mintcream", "mistyrose",
  "moccasin", "navajowhite", "navy", "oldlace", "olive", "olivedrab", "orange",
  "orangered", "orchid", "palegoldenrod", "palegreen", "paleturquoise",
  "palevioletred", "papayawhip", "peachpuff", "peru", "pink", "plum",
  "powderblue", "purple", "rebeccapurple", "red", "rosybrown", "royalblue",
  "saddlebrown", "salmon", "sandybrown", "seagreen", "seashell", "sienna",
  "silver", "skyblue", "slateblue", "slategray", "slategrey", "snow",
  "springgreen", "steelblue", "tan", "teal", "thistle", "tomato", "turquoise",
  "violet", "wheat", "white", "whitesmoke", "yellow", "yellowgreen",
]

const colour_functions = [
  "rgb(", "rgba(", "hsl(", "hsla(", "hwb(", "lab(", "lch(", "oklab(", "oklch(",
  "color(",
]

/// Each colour literal in the text: a `#` and 3, 4, 6 or 8 hex digits, a
/// colour function, or a named colour as a whole word. A word is letters and
/// hyphens, so the property `white-space` is no colour.
fn colour_literals(text: String) -> List(String) {
  let lowered = string.lowercase(text)
  let functions = list.filter(colour_functions, string.contains(lowered, _))
  let names =
    lowered
    |> string.to_graphemes
    |> list.map(fn(grapheme) {
      case string.contains("abcdefghijklmnopqrstuvwxyz-", grapheme) {
        True -> grapheme
        False -> " "
      }
    })
    |> string.concat
    |> string.split(" ")
    |> list.filter(list.contains(colour_names, _))
  list.flatten([hex_literals(lowered), functions, names])
}

fn hex_literals(text: String) -> List(String) {
  case string.split(text, "#") {
    [] -> []
    [_, ..after] ->
      list.filter_map(after, fn(rest) {
        let digits =
          rest
          |> string.to_graphemes
          |> list.take_while(fn(grapheme) {
            string.contains("0123456789abcdef", grapheme)
          })
          |> list.length
        case list.contains([3, 4, 6, 8], digits) {
          True -> Ok("#" <> string.slice(rest, 0, digits))
          False -> Error(Nil)
        }
      })
  }
}

/// A stylesheet's text without its comments.
fn without_comments(css: String) -> String {
  case string.split_once(css, "/*") {
    Error(Nil) -> css
    Ok(#(before, after)) ->
      case string.split_once(after, "*/") {
        Ok(#(_, rest)) -> before <> without_comments(rest)
        Error(Nil) -> before
      }
  }
}

/// The text inside the double quotes of Gleam source: the markup and the
/// styles a view writes.
fn string_literals(source: String) -> String {
  string.split(source, "\"")
  |> list.index_map(fn(part, index) { #(index, part) })
  |> list.filter(fn(pair) { pair.0 % 2 == 1 })
  |> list.map(fn(pair) { pair.1 })
  |> string.join(" ")
}

pub fn no_stylesheet_or_view_holds_a_colour_literal_outside_a_palette_test() -> Nil {
  use <- owned_test.run(5000)
  // The harness can fail: each kind of literal is found.
  assert colour_literals("a { color: #1a2 }") == ["#1a2"]
  assert colour_literals("a { color: #E35FCB }") == ["#e35fcb"]
  assert colour_literals("a { color: rgb(1, 2, 3) }") == ["rgb("]
  assert colour_literals("a { color: hsl(1 2% 3%) }") == ["hsl("]
  assert colour_literals("a { color: red }") == ["red"]
  assert colour_literals("a { white-space: pre-wrap }") == []
  assert colour_literals("a { border-color: red }") == ["red"]
  assert colour_literals(
      "a { color: var(--text); border: 1px solid var(--line) }",
    )
    == []
  assert colour_literals(
      "a { background: color-mix(in srgb, var(--ok) 15%, transparent) }",
    )
    == []

  assert colour_literals(without_comments(read("dev/dashboard/style.css")))
    == []

  // The finder reads every Gleam file of the dashboard at any depth, so a
  // module added later is checked without being named here.
  use home <- dashboard_support.with_home
  let assert Ok(Nil) = simplifile.create_directory_all(home <> "/deeper")
  let assert Ok(Nil) = simplifile.write(home <> "/a.gleam", "")
  let assert Ok(Nil) = simplifile.write(home <> "/deeper/b.gleam", "")
  let assert Ok(Nil) = simplifile.write(home <> "/c.txt", "")
  assert gleam_files(home) == [home <> "/a.gleam", home <> "/deeper/b.gleam"]

  let views = [
    "dev/genesis_prime/dashboard.gleam",
    ..gleam_files("dev/genesis_prime/dashboard")
  ]
  assert list.contains(views, "dev/genesis_prime/dashboard/page.gleam")
  assert list.contains(views, "dev/genesis_prime/dashboard/overview.gleam")
  list.each(views, fn(path) {
    assert colour_literals(string_literals(read(path))) == [] as path
  })
}

/// Every Gleam file under `folder`, at any depth, in name order.
fn gleam_files(folder: String) -> List(String) {
  let assert Ok(files) = simplifile.get_files(folder)
    as { "could not list " <> folder }
  list.filter(files, string.ends_with(_, ".gleam"))
  |> list.sort(string.compare)
}

pub fn the_dashboard_packages_are_development_only_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(parsed) = tom.parse(read("gleam.toml"))
    as "gleam.toml does not parse"
  let assert Ok(development) = tom.get_table(parsed, ["dev_dependencies"])
    as "gleam.toml has no [dev_dependencies]"
  let assert Ok(shipped) = tom.get_table(parsed, ["dependencies"])
    as "gleam.toml has no [dependencies]"
  list.each(["mist", "lustre", "gleam_http"], fn(package) {
    assert dict.has_key(development, package)
      as { package <> " is a development dependency" }
    assert !dict.has_key(shipped, package)
      as { package <> " is not a shipped dependency" }
  })
}
