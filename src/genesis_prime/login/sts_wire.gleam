//// The text framing of the STS protocol, the way the client's NC platform
//// library writes and reads it (StsConnLib64.MT.dll). A request is a first
//// line `POST /<Protocol>/<Command> STS/1.0`, one-letter headers, a blank
//// line and a body: `s:<n>` is the transaction's sequence, `l:<n>` the body's
//// length in bytes, every line ends with CR LF (records
//// StsConnLib64.MT.dll!0x180022cb0, 0x180023550, 0x180023290). A reply's
//// first line is `STS/1.0 <code> <text>` and its `s:` header repeats the
//// request's sequence followed by `R`, the reply's last message
//// (StsConnLib64.MT.dll!0x180024dd0, 0x1800277f0, 0x1800328f0).

import gleam/option.{type Option}

/// The most bytes before the blank line that ends a request's headers. The
/// client's longest request line is under 140 bytes and it sends two headers,
/// so this is far above any client; it bounds what a connection makes the
/// server hold while it waits for the end of a head.
pub const head_limit = 1024

/// The most bytes a request's body may hold. The client's bodies are under
/// 400 bytes (the KeyData request is the longest: A and M1 in base64).
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
  todo as "cut the bytes into requests"
}

/// The bytes of a reply: the status line, the `s` header, the `l` header, the
/// blank line and the body.
pub fn encode(reply reply: Reply) -> BitArray {
  todo as "the bytes of a reply"
}

/// A sentence that says why the bytes are not a request, for the log.
pub fn describe(error error: WireError) -> String {
  todo as "the error in words"
}
