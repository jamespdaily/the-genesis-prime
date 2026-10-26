//// The STS text framing against the bytes the NC platform library writes: fact
//// file `vector.StsConnLib64.MT.dll!0x180022cb0.messages` (the library's own
//// writers run on Ghidra's p-code emulator) and the records
//// `StsConnLib64.MT.dll!0x180022cb0` (request line and percent-encoding),
//// `0x180023290` (the `l` header), `0x180023550` (the `s` header),
//// `0x1800277f0` (how headers are read: duplicates refused, spaces around the
//// colon allowed) and `0x180024dd0` (the status line).

import genesis_prime/login/sts_wire.{Request}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test

const ping = "POST /Sts/Ping STS/1.0\r\nl:0\r\n\r\n"

const login_start =
  "POST /Auth/LoginStart STS/1.0\r\ns:1\r\nl:85\r\n\r\n<Request>\n<LoginName>jim</LoginName>\n<NetAddress>192.168.1.5</NetAddress>\n</Request>\n"

const key_data =
  "POST /Auth/KeyData STS/1.0\r\ns:2\r\nl:57\r\n\r\n<Request>\n<KeyData>AAECAwQFBgcICQ==</KeyData>\n</Request>\n"

const login_finish =
  "POST /Auth/LoginFinish STS/1.0\r\ns:3\r\nl:11\r\n\r\n<Request/>\n"

fn decode_all(
  text: String,
) -> Result(#(List(sts_wire.Request), BitArray), sts_wire.WireError) {
  sts_wire.decode(<<text:utf8>>)
}

pub fn the_ping_the_library_writes_is_a_request_with_no_sequence_and_no_body_test() -> Nil {
  use <- owned_test.run(5000)
  assert decode_all(ping)
    == Ok(
      #(
        [Request(sequence: None, protocol: "Sts", command: "Ping", body: <<>>)],
        <<>>,
      ),
    )
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: Ping is POST /Sts/Ping STS/1.0, l:0 and no body"
}

pub fn the_login_start_the_library_writes_decodes_to_its_sequence_and_body_test() -> Nil {
  use <- owned_test.run(5000)
  let body = <<
    "<Request>\n<LoginName>jim</LoginName>\n<NetAddress>192.168.1.5</NetAddress>\n</Request>\n":utf8,
  >>
  assert decode_all(login_start)
    == Ok(
      #(
        [
          Request(
            sequence: Some(1),
            protocol: "Auth",
            command: "LoginStart",
            body:,
          ),
        ],
        <<>>,
      ),
    )
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: LoginStart with sequence 1 and l:85"
  assert bit_array.byte_size(body) == 85
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: the body is the 85 bytes l:85 names"
}

pub fn the_key_data_and_login_finish_the_library_writes_decode_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(#([key_data_request], <<>>)) = decode_all(key_data)
    as "KeyData is one request"
  assert key_data_request.sequence == Some(2)
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: KeyData has sequence 2"
  assert key_data_request.command == "KeyData"
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: POST /Auth/KeyData"
  assert bit_array.byte_size(key_data_request.body) == 57
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: l:57"
  assert decode_all(login_finish)
    == Ok(
      #(
        [
          Request(
            sequence: Some(3),
            protocol: "Auth",
            command: "LoginFinish",
            body: <<"<Request/>\n":utf8>>,
          ),
        ],
        <<>>,
      ),
    )
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: LoginFinish with sequence 3 and the 11-byte body <Request/>"
}

pub fn a_final_reply_is_a_status_line_a_sequence_with_r_and_a_length_test() -> Nil {
  use <- owned_test.run(5000)
  let body = "<Reply>\n<Token>a&amp;b&lt;c</Token>\n</Reply>\n"
  assert sts_wire.encode(sts_wire.Success(sequence: 5, body:))
    == <<"STS/1.0 200 OK\r\ns:5R\r\nl:45\r\n\r\n":utf8, body:utf8>>
    as "vector.StsConnLib64.MT.dll!0x180022cb0.messages: a final reply to sequence 5 is STS/1.0 200 OK, s:5R, l:45"
}

pub fn a_failure_is_status_400_error_with_the_same_sequence_header_test() -> Nil {
  use <- owned_test.run(5000)
  let body =
    "<Error code=\"3002\" server=\"0\" module=\"0\" line=\"0\" text=\"\"/>\n"
  assert sts_wire.encode(sts_wire.Failure(sequence: 7, body:))
    == <<"STS/1.0 400 Error\r\ns:7R\r\nl:60\r\n\r\n":utf8, body:utf8>>
    as "StsConnLib64.MT.dll!0x18002de60: SendStsReply writes status 400 with the reason Error and the s header of the request with R; l is the body's 60 bytes"
}

pub fn requests_that_arrive_together_come_out_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(#(requests, leftover)) =
    decode_all(login_start <> key_data <> login_finish)
    as "three requests in one read"
  assert list.map(requests, fn(request) { request.sequence })
    == [Some(1), Some(2), Some(3)]
    as "StsConnLib64.MT.dll!0x180023550: the client numbers its transactions from 1 in the order sent"
  assert leftover == <<>> as "every byte is in a request"
}

pub fn a_request_split_anywhere_is_the_same_request_test() -> Nil {
  use <- owned_test.run(10_000)
  let whole = <<login_start:utf8, key_data:utf8>>
  let assert Ok(#(expected, <<>>)) = sts_wire.decode(whole)
    as "the two requests decode together"
  let length = bit_array.byte_size(whole)
  int.range(from: 0, to: length + 1, with: Nil, run: fn(_, split) {
    let assert Ok(first) = bit_array.slice(whole, 0, split) as "the first part"
    let assert Ok(second) = bit_array.slice(whole, split, length - split)
      as "the second part"
    let assert Ok(#(before, leftover)) = sts_wire.decode(first)
      as "a prefix of requests is read"
    let assert Ok(#(after, <<>>)) =
      sts_wire.decode(<<leftover:bits, second:bits>>)
      as "the rest completes it"
    assert list.append(before, after) == expected
      as "a stream is read the same however the reads cut it (ReadConnectionMessages-style framing; the library reads one header line at a time, StsConnLib64.MT.dll!0x1800277f0)"
  })
}

pub fn escapes_in_the_request_line_are_decoded_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(#([request], <<>>)) =
    decode_all("POST /Au%74h/Login%20Start STS/1.0\r\nl:0\r\n\r\n")
    as "a request with escapes"
  assert #(request.protocol, request.command) == #("Auth", "Login Start")
    as "StsConnLib64.MT.dll!0x180022cb0: every byte outside A-Z a-z 0-9 - . _ ~ is percent-encoded in the protocol and the command"
}

pub fn spaces_around_the_colon_of_a_header_are_allowed_test() -> Nil {
  use <- owned_test.run(5000)
  assert decode_all("POST /Sts/Ping STS/1.0\r\nl : 0\r\n\r\n")
    == Ok(
      #(
        [Request(sequence: None, protocol: "Sts", command: "Ping", body: <<>>)],
        <<>>,
      ),
    )
    as "StsConnLib64.MT.dll!0x1800277f0: a header is a name, optional spaces, a colon, optional spaces and the value"
}

pub fn a_header_the_server_does_not_know_is_ignored_test() -> Nil {
  use <- owned_test.run(5000)
  assert decode_all("POST /Sts/Ping STS/1.0\r\np:1\r\nl:0\r\n\r\n")
    == Ok(
      #(
        [Request(sequence: None, protocol: "Sts", command: "Ping", body: <<>>)],
        <<>>,
      ),
    )
    as "StsConnLib64.MT.dll!0x1800277f0: any other header is kept by name; SendStsRequest 0x1800351e0 adds a p header on some sockets"
}

pub fn a_header_that_appears_twice_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert decode_all("POST /Sts/Ping STS/1.0\r\nl:0\r\nl:0\r\n\r\n")
    == Error(sts_wire.DuplicateHeader("l"))
    as "StsConnLib64.MT.dll!0x1800277f0: 'InetMsg: duplicate header' is a framing error"
}

pub fn a_request_without_a_length_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert decode_all("POST /Sts/Ping STS/1.0\r\ns:1\r\n\r\n")
    == Error(sts_wire.MissingLength)
    as "StsConnLib64.MT.dll!0x180023290: a message with no body still carries l:0"
}

pub fn a_length_or_sequence_that_is_not_a_number_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert decode_all("POST /Sts/Ping STS/1.0\r\nl:abc\r\n\r\n")
    == Error(sts_wire.BadHeader("l"))
    as "StsConnLib64.MT.dll!0x1800277f0: l is the decimal body length"
  assert decode_all("POST /Auth/LoginStart STS/1.0\r\ns:x\r\nl:0\r\n\r\n")
    == Error(sts_wire.BadHeader("s"))
    as "StsConnLib64.MT.dll!0x1800277f0: s is a decimal sequence"
}

pub fn a_request_that_claims_to_be_a_reply_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert decode_all("POST /Auth/LoginStart STS/1.0\r\ns:1R\r\nl:0\r\n\r\n")
    == Error(sts_wire.BadHeader("s"))
    as "StsConnLib64.MT.dll!0x180023550: R and r mark a reply; the client's requests are s:<n>"
}

pub fn a_first_line_that_is_not_a_post_of_two_names_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let refused = [
    "GET /Sts/Ping STS/1.0\r\nl:0\r\n\r\n",
    "POST /Sts STS/1.0\r\nl:0\r\n\r\n",
    "POST /Sts/Ping/Extra STS/1.0\r\nl:0\r\n\r\n",
    "POST /Sts/Ping HTTP/1.1\r\nl:0\r\n\r\n",
    "POST /Sts/Pi%zzng STS/1.0\r\nl:0\r\n\r\n",
    "POST /Sts/Ping\r\nl:0\r\n\r\n",
  ]
  list.each(refused, fn(text) {
    assert decode_all(text) == Error(sts_wire.BadRequestLine)
      as "StsConnLib64.MT.dll!0x180022cb0: a request's first line is POST, /<protocol>/<command> and STS/1.0, with %XX escapes"
  })
}

pub fn bytes_that_cannot_begin_a_request_are_refused_as_soon_as_they_differ_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_wire.decode(<<"G":utf8>>) == Error(sts_wire.BadRequestLine)
    as "StsConnLib64.MT.dll!0x180022cb0: a request's first line begins POST, so a first byte that is not P is not a request's"
  assert sts_wire.decode(<<"POSX":utf8>>) == Error(sts_wire.BadRequestLine)
    as "StsConnLib64.MT.dll!0x180022cb0: POST and a space begin the line"
  assert sts_wire.decode(<<"POS":utf8>>) == Ok(#([], <<"POS":utf8>>))
    as "a prefix of POST waits for more bytes"
  assert sts_wire.decode(<<>>) == Ok(#([], <<>>)) as "no bytes wait for more"
}

pub fn a_head_that_does_not_end_within_the_limit_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let endless = "POST " <> string.repeat("a", sts_wire.head_limit)
  assert sts_wire.decode(<<endless:utf8>>) == Error(sts_wire.HeadTooLong)
    as "the server holds at most head_limit bytes of a head, far above the client's longest head, under 80 bytes (POST /Auth/RequestGameToken STS/1.0 with its two headers)"
}

pub fn a_body_longer_than_the_limit_is_refused_when_its_head_arrives_test() -> Nil {
  use <- owned_test.run(5000)
  assert decode_all("POST /Auth/KeyData STS/1.0\r\ns:2\r\nl:4097\r\n\r\n")
    == Error(sts_wire.BodyTooLong(sts_wire.body_limit + 1))
    as "the server holds at most body_limit (4096) bytes of a body, above the client's longest, KeyData at 265 bytes, and refuses before the body is waited for"
}

pub fn the_errors_say_what_broke_test() -> Nil {
  use <- owned_test.run(5000)
  assert string.contains(sts_wire.describe(sts_wire.DuplicateHeader("l")), "l")
    as "a logged reason names the header"
  assert sts_wire.describe(sts_wire.HeadTooLong)
    != sts_wire.describe(sts_wire.MissingLength)
    as "each reason is its own sentence"
}
