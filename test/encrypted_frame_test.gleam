//// The wrapper messages 0x0244 (client), 0x0076 (auth server) and 0x03DC (game
//// server): an outer frame around one inner frame whose 32-bit length is in the
//// clear and whose bytes after it are ciphered (fact file, opcode.0x244,
//// opcode.0x76 and opcode.0x3dc). The expected bytes come from the emulator
//// vectors in the fact file: the whole 0x7E0 frame is
//// vector.opcode.0x7e0.frame, and the ciphered bytes of the others are the
//// vector.0x1400c2d10 outputs for the counting bytes 00 01 02 ...

import connection_vectors as vectors
import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame.{
  AuthWrapper, BadFrame, ClientWrapper, CreateCharacterWrapper, GameWrapper,
  NotAWrapper,
}
import genesis_prime/connection/frame.{Frame}
import gleam/bit_array
import gleam/int
import owned_test
import seeded

fn base_cipher() -> cipher.Cipher {
  let assert Ok(built) = cipher.new(cipher.base_key)
    as "the base key builds a cipher"
  built
}

fn session_cipher() -> cipher.Cipher {
  let assert Ok(built) = cipher.new(vectors.session_key)
    as "the session key builds a cipher"
  built
}

/// An inner frame of id 0x0100 whose id and body, after the length, are the
/// bytes 00 01 02 .. of `ciphered` bytes: the id 0x0100 is 00 01 on the wire.
fn inner_of_counting_bytes(ciphered: Int) -> frame.Frame {
  let assert Ok(after_the_id) =
    bit_array.slice(vectors.counting_bytes(ciphered), 2, ciphered - 2)
    as "the inner frame holds at least its id"
  Frame(0x0100, after_the_id)
}

pub fn the_wrappers_are_the_clients_three_message_ids_test() -> Nil {
  use <- owned_test.run(5000)
  assert encrypted_frame.message_id(ClientWrapper) == 0x0244
    as "opcode.0x244: registered at 0x14006c2d2 mov edx, 0x244"
  assert encrypted_frame.message_id(AuthWrapper) == 0x0076
    as "opcode.0x76: registered at 0x14006c306 lea edx, [r9+0x76]"
  assert encrypted_frame.message_id(GameWrapper) == 0x03DC
    as "opcode.0x3dc: registered at 0x14006c33d mov edx, 0x3dc"
}

pub fn the_clients_0x7e0_in_a_0x244_wrapper_is_its_recorded_twelve_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  let expected = <<0x0C, 0, 0, 0, 0x44, 0x02, 0x06, 0, 0, 0, 0x03, 0x89>>
  assert encrypted_frame.wrap(ClientWrapper, Frame(0x07E0, <<>>), base_cipher())
    == Ok(expected)
    as "vector.opcode.0x7e0.frame: 0c 00 00 00 44 02 06 00 00 00 03 89 (the inner length 6 in the clear, the id e0 07 encrypted to 03 89 under the base key)"
}

pub fn the_servers_reading_of_that_frame_gives_message_0x7e0_back_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(#([outer], <<>>)) =
    frame.decode(<<0x0C, 0, 0, 0, 0x44, 0x02, 0x06, 0, 0, 0, 0x03, 0x89>>)
    as "the recorded bytes are one frame"
  assert outer == Frame(0x0244, <<0x06, 0, 0, 0, 0x03, 0x89>>)
    as "vector.opcode.0x7e0.frame: the 0x244 frame's body is the inner frame"
  assert encrypted_frame.unwrap(outer, base_cipher()) == Ok(Frame(0x07E0, <<>>))
    as "vector.opcode.0x7e0.frame: 03 89 decrypts to the id e0 07 (DecryptMessageBody 0x1400c2de0)"
}

pub fn only_the_bytes_after_the_inner_length_are_ciphered_test() -> Nil {
  use <- owned_test.run(5000)
  assert encrypted_frame.wrap(
      ClientWrapper,
      inner_of_counting_bytes(7),
      base_cipher(),
    )
    == Ok(<<
      0x11, 0, 0, 0, 0x44, 0x02, 0x0B, 0, 0, 0, 0x25, 0xB9, 0x65, 0x84, 0x48,
      0x43, 0x19,
    >>)
    as "opcode.0x244: the inner length 11 stays in the clear; the 7 bytes after it (00 01 .. 06) encrypt to 25b96584484319 (vector.0x1400c2d10.base_key, n = 7)"
}

pub fn the_auth_and_game_wrappers_carry_the_same_ciphered_inner_frame_test() -> Nil {
  use <- owned_test.run(5000)
  assert encrypted_frame.wrap(
      AuthWrapper,
      inner_of_counting_bytes(17),
      base_cipher(),
    )
    == Ok(<<
      0x1B, 0, 0, 0, 0x76, 0x00, 0x15, 0, 0, 0, 0x19, 0x56, 0x68, 0xF6, 0xFB,
      0x7C, 0xBD, 0x9B, 0x8C, 0x00, 0xB4, 0x7F, 0xB7, 0x6B, 0x89, 0x65, 0xEE,
    >>)
    as "opcode.0x76: id 0x76, the inner length 21 in the clear, then the n = 17 base-key vector 195668f6fb7cbd9b8c00b47fb76b8965ee"
  assert encrypted_frame.wrap(
      GameWrapper,
      inner_of_counting_bytes(17),
      session_cipher(),
    )
    == Ok(<<
      0x1B, 0, 0, 0, 0xDC, 0x03, 0x15, 0, 0, 0, 0xD2, 0x9A, 0x50, 0xDF, 0x3E,
      0x48, 0xE8, 0x69, 0xE3, 0xE0, 0xA6, 0x67, 0xF8, 0xA7, 0xC3, 0x0E, 0xEC,
    >>)
    as "opcode.0x3dc: id 0x3dc, the inner length 21 in the clear, then the n = 17 session-key vector d29a50df3e48e869e3e0a667f8a7c30eec"
}

pub fn unwrapping_what_was_wrapped_gives_the_inner_frame_back_test() -> Nil {
  use <- owned_test.run(20_000)
  let checked =
    int.range(from: 1, to: 201, with: #(7, 0), run: fn(state, _case) {
      let #(random, checked) = state
      let #(id, random) = seeded.up_to(state: random, most: 0xFFFF)
      let #(length, random) = seeded.up_to(state: random, most: 2000)
      let #(body, random) = seeded.bytes(state: random, count: length)
      let inner = Frame(id, body)
      let assert Ok(wrapped) =
        encrypted_frame.wrap(GameWrapper, inner, session_cipher())
        as "a 2000-byte body is within the size limit"
      let assert Ok(#([outer], <<>>)) = frame.decode(wrapped)
        as "a wrapped frame is one frame"
      assert outer.message_id == 0x03DC
        as "opcode.0x3dc: the outer frame is message 0x3dc"
      assert encrypted_frame.unwrap(outer, session_cipher()) == Ok(inner)
        as "DecryptMessageBody 0x1400c2de0 undoes EncryptMessageBody 0x1400c2d10 over the inner frame after its length"
      #(random, checked + 1)
    })
  assert checked.1 == 200 as "every generated frame was checked"
}

pub fn a_frame_that_is_not_a_wrapper_is_not_unwrapped_test() -> Nil {
  use <- owned_test.run(5000)
  assert encrypted_frame.unwrap(Frame(0x07E0, <<>>), base_cipher())
    == Error(NotAWrapper(0x07E0))
    as "HandleServerMessage 0x140014f10: a message other than 0x76 or 0x3dc (or 0x244 from the client) is not an inner frame carrier"
}

pub fn an_inner_length_under_six_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert encrypted_frame.unwrap(Frame(0x0244, <<5, 0, 0, 0, 0>>), base_cipher())
    == Error(BadFrame(frame.LengthBelowHeader(5)))
    as "ParseWrappedMessage 0x140331620: a length under 6 is refused (cmp *buffer, 6 -> error 5)"
  assert encrypted_frame.unwrap(Frame(0x0244, <<0, 0, 0, 0>>), base_cipher())
    == Error(BadFrame(frame.LengthBelowHeader(0)))
    as "ReadWholeFrameBody 0x140079f70: a length of 0 is no inner frame, and 0x140331620 refuses a length under 6"
}

pub fn an_inner_length_that_does_not_fill_the_outer_body_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert encrypted_frame.unwrap(
      Frame(0x0244, <<20, 0, 0, 0, 1, 2>>),
      base_cipher(),
    )
    == Error(BadFrame(frame.LengthDisagrees(20, 6)))
    as "ReadWholeFrameBody 0x140079f70 copies the inner frame's length in bytes, so the outer body holds exactly that many"
  assert encrypted_frame.unwrap(
      Frame(0x0244, <<6, 0, 0, 0, 1, 2, 3>>),
      base_cipher(),
    )
    == Error(BadFrame(frame.LengthDisagrees(6, 7)))
    as "WriteWholeFrameBody 0x140079f30 writes the inner frame from its length to the end that length gives and no more"
}

pub fn a_wrapper_around_an_inner_frame_too_big_for_its_outer_frame_is_not_written_test() -> Nil {
  use <- owned_test.run(5000)
  let largest_body = frame.size_limit - 2 * frame.header_size
  let assert Ok(_) =
    encrypted_frame.wrap(
      ClientWrapper,
      Frame(0x0100, <<0:size({ largest_body * 8 })>>),
      base_cipher(),
    )
    as "an outer frame of exactly 131070 bytes is within the limit"
  assert encrypted_frame.wrap(
      ClientWrapper,
      Frame(0x0100, <<0:size({ { largest_body + 1 } * 8 })>>),
      base_cipher(),
    )
    == Error(frame.LengthOverLimit(131_071))
    as "WriteMessageFrame 0x1403355e0 does not write a frame over the size limit 131070 (0x140335ec0), and the wrapper's frame is 6 bytes longer than its inner frame"
}

pub fn the_create_character_carrier_is_message_0x25c_test() -> Nil {
  use <- owned_test.run(5000)
  assert encrypted_frame.message_id(CreateCharacterWrapper) == 0x025C
    as "opcode.0x25c: registered at 0x14006d638 mov edx, 0x25c"
}

pub fn a_create_character_frame_inside_0x25c_is_not_ciphered_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(plain_0x25b_frame) =
    frame.encode(0x025B, <<1, 2, 3, 4, 5, 6, 7>>)
    as "0x25B frames"
  // opcode.0x25c: 0x140079f30 copies the frame's raw bytes into 0x25C's body.
  let assert Ok(carrier) = frame.encode(0x025C, plain_0x25b_frame)
    as "0x25C frames"
  let assert <<length:bytes-size(4), after_the_length:bytes>> = carrier
    as "a frame has its length first"
  // opcode.0x25c: the one cipher call, 0x140024b0c, runs over the whole 0x25C
  // frame after its length, so the cipher's chain runs on from 0x25C's id
  // into the 0x25B frame.
  let expected = <<
    length:bits,
    cipher.encrypt(session_cipher(), after_the_length):bits,
  >>
  let assert Ok(carried) = frame.encode(0x0244, expected) as "0x244 frames"
  assert encrypted_frame.wrap(
      ClientWrapper,
      Frame(0x025C, plain_0x25b_frame),
      session_cipher(),
    )
    == Ok(carried)
    as "opcode.0x25c: 0x244 carries the 0x25C frame ciphered once, over 0x25C's id and the plain 0x25B frame in one pass"
  let assert Ok(#([outer], <<>>)) = frame.decode(carried)
    as "the bytes are one frame"
  let assert Ok(opened) = encrypted_frame.unwrap(outer, session_cipher())
    as "one decryption opens the 0x25C frame"
  assert opened == Frame(0x025C, plain_0x25b_frame)
    as "opcode.0x25c: the body of 0x25C is the 0x25B frame as it stands"
  assert frame.parse(opened.body) == Ok(Frame(0x025B, <<1, 2, 3, 4, 5, 6, 7>>))
    as "opcode.0x25c: no second decryption is needed to read the 0x25B frame"
}
