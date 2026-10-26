//// A scripted NC platform client for the login flow tests: the requests the
//// library writes, the replies it reads and its side of the SRP exchange,
//// written from the fact file's records (StsConnLib64.MT.dll!0x180022cb0,
//// 0x180023290, 0x180023550, 0x180029470 for the text; 0x18002d4e0 and
//// 0x18002d3b0 for the exchange) and not from the server's code, so a login
//// run against the server is checked by a second reading of the records. It
//// shares only the group's constants, the number bytes, the session-key
//// derivation and the RC4 stream with the server, each tested against the
//// library's own vectors.

import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame.{ClientWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/login/guid
import genesis_prime/login/srp
import genesis_prime/login/sts_xml.{type Element}
import genesis_prime/message/login_request.{LoginRequest}
import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The bytes of a request as the library writes it.
pub fn request(
  sequence sequence: Option(Int),
  protocol protocol: String,
  command command: String,
  body body: String,
) -> BitArray {
  let length = bit_array.byte_size(<<body:utf8>>)
  let sequence_header = case sequence {
    Some(number) -> "s:" <> int.to_string(number) <> "\r\n"
    None -> ""
  }
  <<
    "POST /":utf8,
    protocol:utf8,
    "/":utf8,
    command:utf8,
    " STS/1.0\r\n":utf8,
    sequence_header:utf8,
    "l:":utf8,
    int.to_string(length):utf8,
    "\r\n\r\n":utf8,
    body:utf8,
  >>
}

/// A reply the library reads: its status, the sequence it answers and its
/// root element.
pub type Reply {
  Reply(status: Int, sequence: Int, root: Element)
}

/// The reply in the bytes: `STS/1.0 <code> <text>`, the `s` header with R, the
/// `l` header, a blank line and the body (StsConnLib64.MT.dll!0x180024dd0,
/// 0x1800277f0).
pub fn read_reply(bytes: BitArray) -> Result(Reply, Nil) {
  use text <- result.try(bit_array.to_string(bytes))
  use #(head, body) <- result.try(string.split_once(text, "\r\n\r\n"))
  case string.split(head, "\r\n") {
    [status_line, sequence_line, length_line] -> {
      use status <- result.try(status_of(status_line))
      use sequence <- result.try(sequence_of(sequence_line))
      use length <- result.try(length_of(length_line))
      use <- bool.guard(
        when: bit_array.byte_size(<<body:utf8>>) != length,
        return: Error(Nil),
      )
      use root <- result.map(
        sts_xml.parse(<<body:utf8>>) |> result.replace_error(Nil),
      )
      Reply(status:, sequence:, root:)
    }
    _ -> Error(Nil)
  }
}

fn status_of(line: String) -> Result(Int, Nil) {
  case string.split(line, " ") {
    ["STS/1.0", code, ..] -> int.parse(code)
    _ -> Error(Nil)
  }
}

fn sequence_of(line: String) -> Result(Int, Nil) {
  use <- bool.guard(
    when: !{ string.starts_with(line, "s:") && string.ends_with(line, "R") },
    return: Error(Nil),
  )
  int.parse(string.slice(line, 2, string.length(line) - 3))
}

fn length_of(line: String) -> Result(Int, Nil) {
  use <- bool.guard(when: !string.starts_with(line, "l:"), return: Error(Nil))
  int.parse(string.drop_start(line, 2))
}

/// The text of a named child of a reply's root.
pub fn child_text(
  reply reply: Reply,
  name name: String,
) -> Result(String, Nil) {
  sts_xml.child(reply.root, name) |> result.map(fn(found) { found.text })
}

/// What the client computes in the SRP exchange once it has the server's first
/// key data: its key data to send, the session key and the M2 it expects.
pub type Exchange {
  Exchange(key_data: BitArray, session_key: BitArray, expected_m2: BitArray)
}

@external(erlang, "genesis_prime_login_ffi", "mod_pow")
fn mod_pow(base: Int, exponent: Int, modulus: Int) -> Int

fn hash(parts: List(BitArray)) -> BitArray {
  crypto.hash(crypto.Sha256, bit_array.concat(parts))
}

fn number_from(bytes: BitArray) -> Int {
  let bits = bit_array.bit_size(bytes)
  let assert <<number:size(bits)-little>> = bytes as "whole bytes"
  number
}

/// A digest as the library reads it: eight 4-byte groups, the first the most
/// significant, each a little-endian word (StsConnLib64.MT.dll!0x18002d0f0).
fn digest_number(digest: BitArray) -> Int {
  digest_words(digest, 0)
}

fn digest_words(digest: BitArray, built: Int) -> Int {
  case digest {
    <<word:size(32)-little, rest:bytes>> ->
      digest_words(rest, built * 4_294_967_296 + word)
    _ -> built
  }
}

/// The client's side of the exchange for a name and password, with `secret` the
/// 32 random bytes of its value a, answering the server's key data
/// (StsConnLib64.MT.dll!0x18002d4e0).
pub fn exchange(
  name name: String,
  password password: String,
  secret secret: BitArray,
  server_key_data server_key_data: BitArray,
) -> Result(Exchange, Nil) {
  case server_key_data {
    <<
      salt_length:size(32)-little,
      salt:bytes-size(salt_length),
      server_length:size(32)-little,
      server_bytes:bytes-size(server_length),
    >> -> {
      let prime = srp.group_prime()
      let multiplier = srp.multiplier()
      let private_a = number_from(secret)
      let server_value = number_from(server_bytes)
      let client_value = mod_pow(2, private_a, prime)
      let client_bytes = srp.number_bytes(client_value)
      let scrambler =
        digest_number(hash([client_bytes, srp.number_bytes(server_value)]))
      let password_hash = hash([<<name:utf8>>, <<":":utf8>>, <<password:utf8>>])
      let private_x =
        digest_number(
          hash([srp.number_bytes(number_from(salt)), password_hash]),
        )
      let base =
        { server_value - multiplier * mod_pow(2, private_x, prime) % prime }
        |> add_until_not_negative(prime)
      let shared =
        mod_pow(base, { private_a + scrambler * private_x } % prime, prime)
      let key = srp.session_key(srp.number_bytes(shared))
      let proof =
        hash([
          xor(hash([srp.number_bytes(prime)]), hash([srp.number_bytes(2)])),
          hash([<<name:utf8>>]),
          srp.number_bytes(number_from(salt)),
          client_bytes,
          srp.number_bytes(server_value),
          key,
        ])
      Ok(Exchange(
        key_data: <<
          { bit_array.byte_size(client_bytes) }:size(32)-little,
          client_bytes:bits,
          32:size(32)-little,
          proof:bits,
        >>,
        session_key: key,
        expected_m2: hash([client_bytes, proof, key]),
      ))
    }
    _ -> Error(Nil)
  }
}

fn add_until_not_negative(value: Int, prime: Int) -> Int {
  use <- bool.guard(when: value >= 0, return: value)
  add_until_not_negative(value + prime, prime)
}

fn xor(left: BitArray, right: BitArray) -> BitArray {
  case left, right {
    <<first, left_rest:bytes>>, <<second, right_rest:bytes>> -> <<
      int.bitwise_exclusive_or(first, second),
      xor(left_rest, right_rest):bits,
    >>
    _, _ -> <<>>
  }
}

/// What a completed STS login gives the client: the UserId and the game token
/// as their texts.
pub type StsLogin {
  StsLogin(user_id: String, token: String, name: String)
}

/// The client's side of the auth connection for an STS login: the login
/// request the client writes, with its UserId and its game token parsed from
/// their texts as UuidFromStringA does, in a 0x244 wrapper under the base key.
pub fn login_request_frame(login login: StsLogin, build build: Int) -> Frame {
  let assert Ok(user_id) = guid.from_text(login.user_id)
    as "the UserId is a GUID text"
  let assert Ok(token) = guid.from_text(login.token)
    as "the token is a GUID text"
  let request =
    LoginRequest(
      build:,
      files_digest: 0x0807060504030201,
      account_name: login.name,
      field_4: guid.to_wire(user_id),
      field_5: guid.to_wire(token),
      field_6: 0,
      field_7: 0,
      field_8: 0,
      field_9: 0,
      processor_manufacturer: "a",
      processor_name: "bc",
      processor_description: "",
      processor_family: 0,
      processor_level: 0,
      processor_revision: 0,
      processor_clock_speed: 0,
      processor_core_count: 0,
      memory_mebibytes: 0,
      video_adapter_description: "d",
      video_adapter_vendor_id: 0,
      video_adapter_device_id: 0,
      video_adapter_subsystem_id: 0,
      video_adapter_revision: 0,
      video_adapter_memory_mebibytes: 0,
      processor_architecture: 0,
      windows_version: 0,
      service_pack: 0,
      os_flags: 0,
      realm_data_center_id: 0,
    )
  let assert Ok(body) = login_request.encode(request) as "the request encodes"
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key"
  let assert Ok(bytes) =
    encrypted_frame.wrap(ClientWrapper, Frame(0x0592, body), base)
    as "the frame wraps"
  let assert Ok(#([outer], <<>>)) = frame.decode(bytes) as "one frame"
  outer
}
