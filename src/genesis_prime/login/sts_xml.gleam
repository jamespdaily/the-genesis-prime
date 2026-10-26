//// The XML of an STS body as the NC platform library writes it and reads it
//// (record StsConnLib64.MT.dll!0x180029470, 0x1800248a0): no declaration and
//// no indentation, an element with children opens with `<Name>` and a line
//// feed, text is written with `&` as `&amp;` and `<` as `&lt;`, an element
//// closes with `</Name>` and a line feed, or is `<Name/>` and a line feed
//// when it is empty. A body must end with a line feed or it has no root
//// element.

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
  /// The body has a document type, which the library never writes and which
  /// could declare entities.
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
}

/// The root element of a body.
pub fn parse(body body: BitArray) -> Result(Element, XmlError) {
  todo as "read the root element"
}

/// The text a node renders to, as the library writes it.
pub fn render(node node: Node) -> String {
  todo as "write a node"
}

/// The first child of an element with this name.
pub fn child(
  element element: Element,
  name name: String,
) -> Result(Element, Nil) {
  todo as "find a child"
}
