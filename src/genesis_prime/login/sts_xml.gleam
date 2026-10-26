//// The XML of an STS body as the NC platform library writes it and reads it
//// (record StsConnLib64.MT.dll!0x180029470, 0x1800248a0): no declaration and
//// no indentation, an element with children opens with `<Name>` and a line
//// feed, text is written with `&` as `&amp;` and `<` as `&lt;`, an element
//// closes with `</Name>` and a line feed, or is `<Name/>` and a line feed
//// when it is empty. A body must end with a line feed or it has no root
//// element.

import gleam/bit_array
import gleam/list
import gleam/string

/// An element read from a body: its name, its text and its children. The
/// text of an element with children is whatever lies between them.
pub type Element {
  Element(name: String, text: String, children: List(Element))
}

/// Why a body is not an element.
pub type XmlError {
  /// The body is empty or does not end with a line feed
  /// (StsConnLib64.MT.dll!0x1800248a0).
  NoRootElement
  /// The body is not well-formed XML.
  NotWellFormed
  /// The body holds `<!`, a document type, a comment or a CDATA section, none
  /// of which the library writes and which could declare entities.
  HasDocumentType
}

/// An element to write.
pub type Node {
  /// An element with text: `<Name>text</Name>`.
  Text(name: String, text: String)
  /// An element with children.
  Parent(name: String, children: List(Node))
  /// An element with nothing in it: `<Name/>`.
  Empty(name: String)
  /// An element with nothing in it but attributes: `<Name a="1" b="2"/>`.
  Tag(name: String, attributes: List(#(String, String)))
}

/// The root element of a body.
pub fn parse(body body: BitArray) -> Result(Element, XmlError) {
  case body {
    <<>> -> Error(NoRootElement)
    _ ->
      case ends_with_line_feed(body) {
        True ->
          case bit_array.to_string(body) {
            Ok(text) ->
              case string.contains(text, "<!") {
                True -> Error(HasDocumentType)
                False -> read_root(body)
              }
            Error(Nil) -> Error(NotWellFormed)
          }
        False -> Error(NoRootElement)
      }
  }
}

fn ends_with_line_feed(body: BitArray) -> Bool {
  case bit_array.slice(body, bit_array.byte_size(body) - 1, 1) {
    Ok(<<10>>) -> True
    _ -> False
  }
}

@external(erlang, "genesis_prime_login_ffi", "parse_xml")
fn read_root(body: BitArray) -> Result(Element, XmlError)

/// The text a node renders to, as the library writes it.
pub fn render(node node: Node) -> String {
  case node {
    Text(name:, text:) ->
      "<" <> name <> ">" <> escape(text) <> "</" <> name <> ">\n"
    Parent(name:, children:) ->
      "<"
      <> name
      <> ">\n"
      <> string.concat(list.map(children, render))
      <> "</"
      <> name
      <> ">\n"
    Empty(name:) -> "<" <> name <> "/>\n"
    Tag(name:, attributes:) ->
      "<"
      <> name
      <> string.concat(
        list.map(attributes, fn(attribute) {
          " " <> attribute.0 <> "=\"" <> escape_attribute(attribute.1) <> "\""
        }),
      )
      <> "/>\n"
  }
}

/// `&` as `&amp;` and `<` as `&lt;`, the escapes the library writes
/// (StsConnLib64.MT.dll!0x180029470).
fn escape(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
}

/// The escapes of text, and a quote as `&quot;` so it does not end the value.
fn escape_attribute(text: String) -> String {
  escape(text) |> string.replace("\"", "&quot;")
}

/// The first child of an element with this name.
pub fn child(
  element element: Element,
  name name: String,
) -> Result(Element, Nil) {
  list.find(element.children, fn(candidate) { candidate.name == name })
}
