//// The XML of an STS body as the NC platform library writes and reads it:
//// records `StsConnLib64.MT.dll!0x180029470` (how elements and text are
//// written) and `StsConnLib64.MT.dll!0x1800248a0` (a body must end with a line
//// feed), and the messages of
//// `vector.StsConnLib64.MT.dll!0x180022cb0.messages`.

import genesis_prime/login/sts_xml.{Element, Empty, Parent, Text}
import owned_test

pub fn text_is_written_with_ampersand_and_less_than_escaped_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.render(Parent("Reply", [Text("Token", "a&b<c")]))
    == "<Reply>\n<Token>a&amp;b&lt;c</Token>\n</Reply>\n"
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: the reply with Token a&b<c is <Reply><LF><Token>a&amp;b&lt;c</Token><LF></Reply><LF>"
}

pub fn an_empty_element_is_one_tag_and_a_line_feed_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.render(Empty("Request")) == "<Request/>\n"
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: LoginFinish's body is <Request/><LF>"
}

pub fn children_are_written_one_to_a_line_without_indentation_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.render(
      Parent("Request", [
        Text("LoginName", "jim"),
        Text("NetAddress", "192.168.1.5"),
      ]),
    )
    == "<Request>\n<LoginName>jim</LoginName>\n<NetAddress>192.168.1.5</NetAddress>\n</Request>\n"
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: LoginStart's body, no indentation and no declaration"
}

pub fn a_parent_inside_a_parent_closes_on_its_own_line_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.render(
      Parent("Reply", [Parent("GameAccount", [Text("Alias", "jim")])]),
    )
    == "<Reply>\n<GameAccount>\n<Alias>jim</Alias>\n</GameAccount>\n</Reply>\n"
    as "StsConnLib64.MT.dll!0x180029470: an element with children opens with a line feed after its tag and closes with </Name> and a line feed"
}

pub fn a_body_of_the_library_parses_to_its_root_and_children_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.parse(<<
      "<Request>\n<LoginName>jim</LoginName>\n<NetAddress>192.168.1.5</NetAddress>\n</Request>\n":utf8,
    >>)
    == Ok(
      Element(name: "Request", text: "", children: [
        Element(name: "LoginName", text: "jim", children: []),
        Element(name: "NetAddress", text: "192.168.1.5", children: []),
      ]),
    )
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: LoginStart's body"
}

pub fn escaped_text_is_read_back_unescaped_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.parse(<<
      "<Reply>\n<Token>a&amp;b&lt;c</Token>\n</Reply>\n":utf8,
    >>)
    == Ok(
      Element(name: "Reply", text: "", children: [
        Element(name: "Token", text: "a&b<c", children: []),
      ]),
    )
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: the Token a&b<c written as a&amp;b&lt;c"
}

pub fn an_empty_element_parses_with_no_text_and_no_children_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.parse(<<"<Request/>\n":utf8>>)
    == Ok(Element(name: "Request", text: "", children: []))
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: LoginFinish's body"
}

pub fn a_body_that_does_not_end_with_a_line_feed_has_no_root_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.parse(<<"<Request/>":utf8>>) == Error(sts_xml.NoRootElement)
    as "StsConnLib64.MT.dll!0x1800248a0: a body whose last byte is not 0x0a has no root element"
}

pub fn an_empty_body_has_no_root_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.parse(<<>>) == Error(sts_xml.NoRootElement)
    as "StsConnLib64.MT.dll!0x1800248a0: a body of 0 bytes has no root element"
}

pub fn a_body_that_is_not_well_formed_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.parse(<<"<Request><Name></Request>\n":utf8>>)
    == Error(sts_xml.NotWellFormed)
    as "StsConnLib64.MT.dll!0x1800248a0: a body that does not parse records an error and the message has no root"
}

pub fn an_entity_other_than_the_five_predefined_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.parse(<<"<a>&x;</a>\n":utf8>>) == Error(sts_xml.NotWellFormed)
    as "StsConnLib64.MT.dll!0x180029470: the library writes only &amp; and &lt; as escapes, so a reference to an entity the body never declares is not the client's"
}

pub fn a_document_type_is_refused_before_its_entities_are_expanded_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_xml.parse(<<
      "<!DOCTYPE a [<!ENTITY x \"y\">]>\n<a>&x;</a>\n":utf8,
    >>)
    == Error(sts_xml.HasDocumentType)
    as "StsConnLib64.MT.dll!0x180029470: the library writes no declaration and no document type, so a body with one is not the client's and could declare entities"
}

pub fn the_first_child_of_a_name_is_found_test() -> Nil {
  use <- owned_test.run(5000)
  let root =
    Element(name: "Reply", text: "", children: [
      Element(name: "A", text: "1", children: []),
      Element(name: "B", text: "2", children: []),
      Element(name: "A", text: "3", children: []),
    ])
  assert sts_xml.child(root, "A") == Ok(Element("A", "1", []))
    as "StsConnLib64.MT.dll!0x18000a350: the library takes the child by name, XmlChildBase64"
  assert sts_xml.child(root, "C") == Error(Nil)
    as "StsConnLib64.MT.dll!0x18000a350: a reply with no such child fails the step"
}
