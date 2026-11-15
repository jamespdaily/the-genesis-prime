//// The tutorial bot's choice of the unit to strike (`tutorial_bot.nearest`) over what it
//// has heard (`tutorial_bot.hear`). Expected values come from these places.
//// - A creature's 0x262 is the client's vector of a Virtual Battle Beast
////   (`opcode.0x262.creature`): Creature2 73464 at (-131.5, -875.25, 333.5), its unit id
////   in the first 32 bits. The second unit is the same bytes under another id.
//// - 0x88c marks a unit dead (`opcode.0x88c`: the unit id, then the dead bit); the server
////   writes it for a unit killed by a strike that is no part of the fight that reads it.
//// - The quest counts each unit of its creature that dies while it is open, whichever
////   press killed it: the count the bot keeps is the units marked dead since its slay
////   began.
//// - A dead unit is never struck: a press at it selects no unit, so its go is empty.

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/unit_death_state.{UnitDeathState}
import gleam/dict
import gleam/set
import message_support
import owned_test
import tutorial_bot.{Units}

const battle_beast = 73_464

const beast_at = #(-131.5, -875.25, 333.5)

const beast_vector =
  "01 10 00 00 00 be 47 00 00 02 40 03 00 00 a0 08 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00"

fn created_beast(unit_id unit_id: Int) -> Frame {
  let assert <<_:size(32), rest:bits>> = message_support.hex(beast_vector)
    as "the vector starts with the unit id"
  Frame(message_id: 0x0262, body: <<unit_id:size(32)-little, rest:bits>>)
}

fn death(unit_id unit_id: Int, dead dead: Int) -> Frame {
  let assert Ok(body) =
    unit_death_state.encode(UnitDeathState(
      unit_id:,
      dead:,
      field_3: 0,
      field_4: 0,
    ))
    as "0x88c encodes"
  Frame(message_id: 0x088C, body:)
}

fn heard(frames: List(Frame)) -> tutorial_bot.Units {
  tutorial_bot.hear(
    units: Units(
      creatures: dict.new(),
      others: dict.new(),
      spent: set.new(),
      dead: set.new(),
    ),
    frames:,
  )
}

pub fn a_creature_whose_death_news_came_in_an_earlier_read_is_not_chosen_test() -> Nil {
  use <- owned_test.run(5000)
  let units =
    heard([created_beast(unit_id: 0x1001), created_beast(unit_id: 0x1002)])
  assert tutorial_bot.nearest(units:, from: beast_at, creatures: [battle_beast])
    == Ok(#(0x1001, beast_at))
    as "both stand at the vector's place, so the lower id is the nearest"
  // The collateral kill of an earlier press: its 0x88c is read after that fight closed,
  // among the frames of some other wait.
  let units =
    tutorial_bot.hear(units:, frames: [death(unit_id: 0x1001, dead: 1)])
  assert tutorial_bot.nearest(units:, from: beast_at, creatures: [battle_beast])
    == Ok(#(0x1002, beast_at))
    as "a dead unit is skipped for the next"
}

pub fn a_unit_marked_alive_is_not_a_death_test() -> Nil {
  use <- owned_test.run(5000)
  let units =
    heard([created_beast(unit_id: 0x1001), death(unit_id: 0x1001, dead: 0)])
  assert tutorial_bot.nearest(units:, from: beast_at, creatures: [battle_beast])
    == Ok(#(0x1001, beast_at))
    as "a 0x88c with the dead bit clear marks the unit alive"
}

pub fn a_wanted_death_heard_outside_the_slays_own_reads_counts_toward_its_kills_test() -> Nil {
  use <- owned_test.run(5000)
  let units =
    heard([
      created_beast(unit_id: 0x1001),
      created_beast(unit_id: 0x1002),
      created_beast(unit_id: 0x1003),
    ])
  let before = units.dead
  let units =
    tutorial_bot.hear(units:, frames: [death(unit_id: 0x1001, dead: 1)])
  assert tutorial_bot.kills_since(units:, creatures: [battle_beast], before:)
    == 1
    as "a collateral kill heard between two presses is a kill"
  assert tutorial_bot.kills_since(
      units:,
      creatures: [battle_beast + 1],
      before:,
    )
    == 0
    as "a death of another creature is none"
  let before = units.dead
  let units =
    tutorial_bot.hear(units:, frames: [death(unit_id: 0x1002, dead: 1)])
  assert tutorial_bot.kills_since(units:, creatures: [battle_beast], before:)
    == 1
    as "a death from before the slay began is not counted again"
}
