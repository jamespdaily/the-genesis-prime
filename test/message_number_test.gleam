//// Each generated message module holds the number the client registers its
//// message under: the instruction that loads it into the registration call, as
//// the fact file's opcode record gives it. The messages of character select and
//// entering the world are checked in `character_message_vector_test`.

import genesis_prime/message/character_select_start
import genesis_prime/message/client_wrapper
import genesis_prime/message/enter_world
import genesis_prime/message/game_hello_reply
import genesis_prime/message/game_server_handoff
import genesis_prime/message/login_accepted
import genesis_prime/message/login_request
import genesis_prime/message/movement_send_interval
import genesis_prime/message/realm_handoff
import genesis_prime/message/realm_list
import genesis_prime/message/realm_select_start
import genesis_prime/message/server_hello
import genesis_prime/message/world_message
import owned_test

pub fn each_message_module_of_the_earlier_steps_holds_the_clients_number_test() -> Nil {
  use <- owned_test.run(5000)
  assert server_hello.message_id == 0x0003
    as "opcode.0x3: 0x1400a81d7 lea edx, [rdi+0x3]"
  assert login_request.message_id == 0x0592
    as "opcode.0x592: 0x14006d4ee mov edx, 0x592"
  assert login_accepted.message_id == 0x0591
    as "opcode.0x591: 0x140078555 mov edx, 0x591"
  assert game_server_handoff.message_id == 0x03DB
    as "opcode.0x3db: 0x14006d3e7 mov edx, 0x3db"
  assert game_hello_reply.message_id == 0x058F
    as "opcode.0x58f: 0x14006d593 mov edx, 0x58f"
  assert character_select_start.message_id == 0x07E0
    as "opcode.0x7e0: 0x14006d782 mov edx, 0x7e0"
  assert enter_world.message_id == 0x00AD
    as "opcode.0xad: 0x14006d8eb mov edx, 0xad"
  assert realm_select_start.message_id == 0x07A4
    as "opcode.0x7a4: 0x14006d5ca mov edx, 0x7a4"
  assert realm_list.message_id == 0x0761
    as "opcode.0x761: 0x1400a84b9 mov edx, 0x761"
  assert realm_handoff.message_id == 0x07A1
    as "opcode.0x7a1: 0x1400785e8 mov edx, 0x7a1"
  assert movement_send_interval.message_id == 0x00F1
    as "opcode.0xf1: 0x140078d86 mov edx, 0xf1"
  assert client_wrapper.message_id == 0x0244
    as "opcode.0x244: 0x14006c2d2 mov edx, 0x244"
  assert world_message.message_id == 0x038C
    as "opcode.0x38c: 0x14006d55c mov edx, 0x38c"
}
