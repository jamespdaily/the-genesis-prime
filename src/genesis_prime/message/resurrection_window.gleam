//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01B3 (resurrection_window), server to client: the player's death
//// state and the resurrection window's choices: the unit to control while dead
//// (the ghost), the Wake Here cost in credits, the death penalty in
//// milliseconds, the dead bit, the offered choices, whether a caster has
//// asked, the Wake Here cooldown and the forced-release countdown in
//// milliseconds; the window's choices, cost and timers come only from this
//// message. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x1b3` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x01B3

/// The body of message 0x01B3, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ResurrectionWindow {
  ResurrectionWindow(
    ghost_unit_id: Int,
    wake_here_cost: Int,
    death_penalty_ms: Int,
    dead: Int,
    choices: Int,
    caster_asked: Int,
    wake_here_cooldown_ms: Int,
    forced_release_ms: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ResurrectionWindow) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("ghost_unit_id", message.ghost_unit_id, 32)
  |> bit_stream.write_unsigned("wake_here_cost", message.wake_here_cost, 32)
  |> bit_stream.write_unsigned("death_penalty_ms", message.death_penalty_ms, 32)
  |> bit_stream.write_unsigned("dead", message.dead, 1)
  |> bit_stream.write_unsigned("choices", message.choices, 8)
  |> bit_stream.write_unsigned("caster_asked", message.caster_asked, 1)
  |> bit_stream.write_unsigned(
    "wake_here_cooldown_ms",
    message.wake_here_cooldown_ms,
    32,
  )
  |> bit_stream.write_unsigned(
    "forced_release_ms",
    message.forced_release_ms,
    32,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ResurrectionWindow, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(ghost_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(wake_here_cost, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(death_penalty_ms, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(dead, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(choices, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(caster_asked, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(wake_here_cooldown_ms, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(forced_release_ms, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ResurrectionWindow(
    ghost_unit_id:,
    wake_here_cost:,
    death_penalty_ms:,
    dead:,
    choices:,
    caster_asked:,
    wake_here_cooldown_ms:,
    forced_release_ms:,
  ))
}
