//// The rule of the network layer's own messages, without a socket: a ping is
//// answered with the pong that carries its number, a pong and a close notice
//// are accepted with no answer, and every other frame is not the network
//// layer's (records opcode.0x0, opcode.0x1, opcode.0x2; ReadMessageFrame
//// 0x140331990). The frame the live login recorded is the
//// client's own first ping, 07 00 00 00 00 00 00.

import frame_reader
import genesis_prime/connection/frame.{Frame}
import genesis_prime/connection/network_message.{
  Accepted, Answer, Malformed, NotNetwork,
}
import genesis_prime/coverage/sent_message
import genesis_prime/message/bit_stream
import gleam/int
import gleam/list
import owned_test

pub fn a_ping_is_answered_with_a_bare_pong_that_carries_its_number_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(#([recorded], <<>>)) =
    frame_reader.decode(<<7, 0, 0, 0, 0, 0, 0>>)
    as "the client's first ping of the live login is one frame"
  assert network_message.handle(recorded) == Answer(<<7, 0, 0, 0, 1, 0, 0>>)
    as "opcode.0x1: the pong is 07 00 00 00 01 00 and the ping's number"
  assert network_message.handle(Frame(message_id: 0, body: <<19>>))
    == Answer(<<7, 0, 0, 0, 1, 0, 19>>)
    as "opcode.0x0: 19 is the largest number, and the pong echoes it"
}

pub fn a_pong_and_a_close_notice_are_accepted_with_no_answer_test() -> Nil {
  use <- owned_test.run(5000)
  assert network_message.handle(Frame(message_id: 1, body: <<5>>)) == Accepted
    as "opcode.0x1: a pong to a ping of the server is ignored"
  assert network_message.handle(Frame(message_id: 1, body: <<200>>)) == Accepted
    as "opcode.0x1: the client ignores a pong of 20 or more, so the server does too"
  assert network_message.handle(Frame(message_id: 2, body: <<>>)) == Accepted
    as "opcode.0x2: a close notice is dropped"
}

pub fn a_network_message_that_does_not_decode_is_malformed_test() -> Nil {
  use <- owned_test.run(5000)
  assert network_message.handle(Frame(message_id: 0, body: <<20>>))
    == Malformed(
      message_id: 0,
      error: bit_stream.UnexpectedValue("sequence_number", 20),
    )
    as "opcode.0x0: a ping of 20 is not one the client sends"
  assert network_message.handle(Frame(message_id: 0, body: <<>>))
    == Malformed(message_id: 0, error: bit_stream.EndOfData)
    as "opcode.0x0: a ping holds one byte"
  assert network_message.handle(Frame(message_id: 0, body: <<1, 2>>))
    == Malformed(message_id: 0, error: bit_stream.TrailingBytes(1))
    as "opcode.0x0: a ping holds one byte and no more"
  assert network_message.handle(Frame(message_id: 2, body: <<1>>))
    == Malformed(message_id: 2, error: bit_stream.TrailingBytes(1))
    as "opcode.0x2: a close notice has an empty body"
}

pub fn any_other_message_is_not_the_network_layers_test() -> Nil {
  use <- owned_test.run(5000)
  assert network_message.handle(Frame(message_id: 0x0244, body: <<>>))
    == NotNetwork
    as "opcode.0x244: the wrapper is for the session to open"
  assert network_message.handle(Frame(message_id: 3, body: <<>>)) == NotNetwork
    as "the registrations in 0x14006c290 hold no id below 3, so message 3 is the first of the game's"
}

pub fn the_network_layer_takes_exactly_the_ids_it_names_among_those_the_client_sends_test() -> Nil {
  use <- owned_test.run(10_000)
  assert list.sort(network_message.taken_message_ids(), int.compare)
    == [0, 1, 2]
    as "fact 0x140332580: the network layer's own ids 0, 1 and 2, sent bare and never registered"
  list.each(sent_message.all(), fn(id) {
    let is_network =
      network_message.handle(Frame(message_id: id, body: <<>>)) != NotNetwork
    assert is_network == list.contains([0, 1, 2], id)
      as {
        "id "
        <> int.to_string(id)
        <> ": the network layer's own exactly when named"
      }
  })
}
