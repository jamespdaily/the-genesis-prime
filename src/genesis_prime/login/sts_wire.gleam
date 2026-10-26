//// The text framing of the STS protocol, the way the client's NC platform
//// library writes and reads it (StsConnLib64.MT.dll). A request is a first
//// line `POST /<Protocol>/<Command> STS/1.0`, one-letter headers, a blank
//// line and a body: `s:<n>` is the transaction's sequence, `l:<n>` the body's
//// length in bytes, every line ends with CR LF (records
//// StsConnLib64.MT.dll!0x180022cb0, 0x180023550, 0x180023290). A reply's
//// first line is `STS/1.0 <code> <text>` and its `s:` header repeats the
//// request's sequence followed by `R`, the reply's last message
//// (StsConnLib64.MT.dll!0x180024dd0, 0x1800277f0, 0x1800328f0).

import gleam/bit_array
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

/// The most bytes of a request's head, the blank line that ends it included. The
/// client's longest head is under 80 bytes: the longest request line,
/// `POST /Auth/RequestGameToken STS/1.0`, and two headers. This is far above
/// any client; it bounds what a connection makes the server hold while it
/// waits for the end of a head.
pub const head_limit = 1024

/// The most bytes a request's body may hold. The client's bodies are under
/// 300 bytes (the KeyData request is the longest, at 265: A and M1 in base64).
pub const body_limit = 4096

/// One request as the client wrote it. `sequence` is the `s` header, absent
/// on the one-way messages Connect and Ping.
pub type Request {
  Request(
    sequence: Option(Int),
    protocol: String,
    command: String,
    body: BitArray,
  )
}

/// Why received bytes are not a request. Each ends the connection.
pub type WireError {
  /// No blank line within `head_limit` bytes.
  HeadTooLong
  /// The first line is not `POST /<Protocol>/<Command> STS/1.0`, or a
  /// percent escape in it is not two hexadecimal digits.
  BadRequestLine
  /// A header line is not a name, a colon and a value, or `l` or `s` does not
  /// hold what it must.
  BadHeader(name: String)
  /// A header appears twice (StsConnLib64.MT.dll!0x1800277f0).
  DuplicateHeader(name: String)
  /// The head has no `l` header, which the library writes on every message.
  MissingLength
  /// The `l` header names more than `body_limit` bytes.
  BodyTooLong(length: Int)
}

/// The reply a request is answered with.
pub type Reply {
  /// A success: status 200 `OK`, the request's sequence with `R`, and an XML
  /// body.
  Success(sequence: Int, body: String)
  /// A failure: status 400 `Error`, the request's sequence with `R`, and the
  /// body the library writes for an error (StsConnLib64.MT.dll!0x18002de60).
  Failure(sequence: Int, body: String)
}

/// The requests whole in the received bytes, and the bytes left over: the
/// start of a request whose end has not arrived.
pub fn decode(
  received received: BitArray,
) -> Result(#(List(Request), BitArray), WireError) {
  collect(received, [])
}

fn collect(
  received: BitArray,
  found: List(Request),
) -> Result(#(List(Request), BitArray), WireError) {
  use <- bool.guard(
    when: !could_start_a_request(received),
    return: Error(BadRequestLine),
  )
  let scanned = case bit_array.slice(received, 0, head_limit) {
    Ok(prefix) -> prefix
    Error(Nil) -> received
  }
  case end_of_head(scanned, 0) {
    None ->
      case bit_array.byte_size(received) >= head_limit {
        True -> Error(HeadTooLong)
        False -> Ok(#(list.reverse(found), received))
      }
    Some(head_size) -> {
      let assert <<head:bytes-size(head_size), "\r\n\r\n":utf8, after:bytes>> =
        received
        as "the head's end was found in these bytes"
      use #(request, length) <- result.try(read_head(head))
      use <- bool.guard(
        when: length > body_limit,
        return: Error(BodyTooLong(length:)),
      )
      case after {
        <<body:bytes-size(length), rest:bytes>> ->
          collect(rest, [Request(..request, body:), ..found])
        _ -> Ok(#(list.reverse(found), received))
      }
    }
  }
}

/// Whether the bytes, as far as they go, begin `POST `: a request's first line
/// starts with the method (StsConnLib64.MT.dll!0x180022cb0), so bytes that do
/// not are refused as soon as they differ.
fn could_start_a_request(bytes: BitArray) -> Bool {
  let size = int.min(bit_array.byte_size(bytes), 5)
  case bit_array.slice(bytes, 0, size) {
    Ok(prefix) -> prefix == prefix_of_post(size)
    Error(Nil) -> False
  }
}

fn prefix_of_post(size: Int) -> BitArray {
  case bit_array.slice(<<"POST ":utf8>>, 0, size) {
    Ok(prefix) -> prefix
    Error(Nil) -> <<>>
  }
}

/// The offset of the blank line that ends a head, when the whole of it is
/// within the head limit.
fn end_of_head(bytes: BitArray, offset: Int) -> Option(Int) {
  case bytes {
    <<"\r\n\r\n":utf8, _:bytes>> -> Some(offset)
    <<_, rest:bytes>> -> end_of_head(rest, offset + 1)
    _ -> None
  }
}

/// A head's request, without its body, and the length its `l` header names.
fn read_head(head: BitArray) -> Result(#(Request, Int), WireError) {
  use text <- result.try(
    bit_array.to_string(head) |> result.replace_error(BadRequestLine),
  )
  case string.split(text, "\r\n") {
    [request_line, ..header_lines] -> {
      use #(protocol, command) <- result.try(read_request_line(request_line))
      use headers <- result.try(read_headers(header_lines, dict.new()))
      use length <- result.try(
        dict.get(headers, "l") |> result.replace_error(MissingLength),
      )
      use length <- result.try(
        number(length) |> result.replace_error(BadHeader("l")),
      )
      use sequence <- result.map(case dict.get(headers, "s") {
        Ok(value) ->
          number(value)
          |> result.replace_error(BadHeader("s"))
          |> result.map(Some)
        Error(Nil) -> Ok(None)
      })
      #(Request(sequence:, protocol:, command:, body: <<>>), length)
    }
    [] -> Error(BadRequestLine)
  }
}

/// `POST /<protocol>/<command> STS/1.0`, the two names percent-decoded.
fn read_request_line(line: String) -> Result(#(String, String), WireError) {
  case string.split(line, " ") {
    ["POST", path, "STS/1.0"] ->
      case string.split(path, "/") {
        ["", protocol, command] -> {
          use protocol <- result.try(name(protocol))
          use command <- result.map(name(command))
          #(protocol, command)
        }
        _ -> Error(BadRequestLine)
      }
    _ -> Error(BadRequestLine)
  }
}

fn name(escaped: String) -> Result(String, WireError) {
  case uri.percent_decode(escaped) {
    Ok("") | Error(Nil) -> Error(BadRequestLine)
    Ok(decoded) -> Ok(decoded)
  }
}

/// Each header line as a name and its value, each name once. A name ends at a
/// space, a colon or a tab; spaces may follow it and the colon
/// (StsConnLib64.MT.dll!0x1800277f0).
fn read_headers(
  lines: List(String),
  found: Dict(String, String),
) -> Result(Dict(String, String), WireError) {
  case lines {
    [] -> Ok(found)
    [line, ..rest] -> {
      use #(name, value) <- result.try(read_header(line))
      case dict.has_key(found, name) {
        True -> Error(DuplicateHeader(name:))
        False -> read_headers(rest, dict.insert(found, name, value))
      }
    }
  }
}

fn read_header(line: String) -> Result(#(String, String), WireError) {
  let name_length = name_length(string.to_graphemes(line), 0)
  let header_name = string.slice(line, 0, name_length)
  let after_name = string.drop_start(line, name_length) |> string.trim_start
  case string.starts_with(after_name, ":"), header_name {
    True, "" -> Error(BadHeader(name: line))
    True, _ ->
      Ok(#(header_name, string.drop_start(after_name, 1) |> string.trim_start))
    False, _ -> Error(BadHeader(name: line))
  }
}

fn name_length(graphemes: List(String), counted: Int) -> Int {
  case graphemes {
    [" ", ..] | [":", ..] | ["\t", ..] | [] -> counted
    [_, ..rest] -> name_length(rest, counted + 1)
  }
}

/// A decimal number of digits only, as the library writes `l` and `s`.
fn number(text: String) -> Result(Int, Nil) {
  use <- bool.guard(
    when: text == "" || string.length(text) > 9,
    return: Error(Nil),
  )
  case list.all(string.to_graphemes(text), is_digit) {
    True -> int.parse(text)
    False -> Error(Nil)
  }
}

fn is_digit(grapheme: String) -> Bool {
  string.contains("0123456789", grapheme)
}

/// The bytes of a reply: the status line, the `s` header, the `l` header, the
/// blank line and the body.
pub fn encode(reply reply: Reply) -> BitArray {
  let #(status, sequence, body) = case reply {
    Success(sequence:, body:) -> #("200 OK", sequence, body)
    Failure(sequence:, body:) -> #("400 Error", sequence, body)
  }
  <<
    "STS/1.0 ":utf8,
    status:utf8,
    "\r\ns:":utf8,
    int.to_string(sequence):utf8,
    "R\r\nl:":utf8,
    int.to_string(bit_array.byte_size(<<body:utf8>>)):utf8,
    "\r\n\r\n":utf8,
    body:utf8,
  >>
}

/// A sentence that says why the bytes are not a request, for the log.
pub fn describe(error error: WireError) -> String {
  case error {
    HeadTooLong ->
      "no blank line within " <> int.to_string(head_limit) <> " bytes"
    BadRequestLine -> "the first line is not POST /<protocol>/<command> STS/1.0"
    BadHeader(name:) -> "the header " <> name <> " is not valid"
    DuplicateHeader(name:) -> "the header " <> name <> " appears twice"
    MissingLength -> "the head has no l header"
    BodyTooLong(length:) ->
      "the body is "
      <> int.to_string(length)
      <> " bytes, over the limit of "
      <> int.to_string(body_limit)
  }
}
