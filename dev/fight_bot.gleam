//// A scripted client's Paralytic Surge fight: it presses the ability at a unit it
//// faces until the unit's death is read. Time moves only by the `advance` the caller
//// passes, which moves the clock the server's timers run on by that many milliseconds,
//// so a fight waits on the server's frames and never on a fixed time.

import game_client
import genesis_prime/connection/frame.{type Frame}
import gleam/bool
import gleam/list

/// The cast time of Paralytic Surge (Spell4 42352, castTime 0): its go is due at
/// the press.
pub const paralytic_surge_cast_ms = 0

/// How long a hit of Paralytic Surge lasts after its go: the cast ends, with its 0x7fe,
/// when the node of its second effect, Spell4Effects 96126, ends at its durationTime
/// (`Spell4Effects.durationTime`, 2700 ms).
pub const paralytic_surge_lingers_ms = 2700

/// A press the server refused (0x7fc), with the result of each refusal: a caster that
/// is dead or stunned, a target out of range or a cooldown still running gets no go, so
/// no frame the fight waits for would ever come.
pub type Refused {
  Refused(client_cast_id: Int, results: List(Int))
}

/// The results of the refusals (0x7fc) of the press with this client cast id among the
/// frames.
pub fn refusals_in(
  frames frames: List(Frame),
  cast_id cast_id: Int,
) -> List(Int) {
  list.filter_map(game_client.casts_in(frames:), fn(event) {
    case event {
      game_client.CastRefused(client_cast_id:, result:, ..)
        if client_cast_id == cast_id
      -> Ok(result)
      _ -> Error(Nil)
    }
  })
}

/// Presses Paralytic Surge at the unit, facing it, until its death is read, and
/// gives every frame read and the bytes beyond, or the press the server refused. A
/// press that neither struck the unit
/// nor was shown missing it (0x7fb) ends the test; a deflected press is pressed
/// again, since a creature of the client's rows deflects some strikes (the placed
/// Creature2 73492's defence holds a deflect chance of 0.02, so about one run in
/// six sees one in the nine presses its 117 health takes), each on the rolls of the
/// connection's own random seed.
pub fn presses_until_the_target_dies(
  advance advance: fn(Int) -> Nil,
  game game: game_client.Game,
  have have: BitArray,
  target target: Int,
  cast_id cast_id: Int,
  seen seen: List(Frame),
) -> Result(#(List(Frame), BitArray), Refused) {
  presses_at_most(
    advance:,
    game:,
    have:,
    target:,
    cast_id:,
    seen:,
    presses: 1000,
  )
}

/// The same, at most `presses` presses: the frames read and the bytes beyond, the
/// target's death among them or not, or the press the server refused.
pub fn presses_at_most(
  advance advance: fn(Int) -> Nil,
  game game: game_client.Game,
  have have: BitArray,
  target target: Int,
  cast_id cast_id: Int,
  seen seen: List(Frame),
  presses presses: Int,
) -> Result(#(List(Frame), BitArray), Refused) {
  game_client.press_ability(
    game:,
    client_cast_id: cast_id,
    bag_index: 2,
    target: 0,
  )
  let #(taken, have) = game_client.read_until_pong(game:, have:, number: 1)
  advance(paralytic_surge_cast_ms)
  let #(went, have) =
    game_client.read_until(game:, have:, found: fn(went) {
      let heard = list.append(seen, list.append(taken, went))
      refusals_in(frames: list.append(taken, went), cast_id:) != []
      || list.any(game_client.health_in(frames: heard), fn(health) {
        health.0 == target
      })
      || list.any(game_client.missed_in(frames: heard), fn(missed) {
        list.contains(missed.1, target)
      })
      || list.any(
        game_client.go_targets_in(frames: list.append(taken, went)),
        fn(go) { go.1 == [] },
      )
    })
  let #(settled, have) = game_client.read_until_pong(game:, have:, number: 2)
  let refused =
    refusals_in(frames: list.flatten([taken, went, settled]), cast_id:)
  use <- bool.guard(
    when: refused != [],
    return: Error(Refused(client_cast_id: cast_id, results: refused)),
  )
  let seen = list.flatten([seen, taken, went, settled])
  assert list.any(game_client.go_targets_in(frames: seen), fn(go) {
      list.contains(go.1, target)
    })
    || list.any(game_client.missed_in(frames: seen), fn(missed) {
      list.contains(missed.1, target)
    })
    as "a press facing the target strikes it or is shown missing it"
  let dead = list.contains(game_client.deaths_in(frames: seen), #(target, True))
  let at_zero =
    list.any(game_client.health_in(frames: seen), fn(health) {
      health == #(target, 0, True)
    })
  case dead, at_zero {
    True, _ -> Ok(#(seen, have))
    False, True -> {
      let #(more, have) =
        game_client.read_until(game:, have:, found: fn(more) {
          list.contains(game_client.deaths_in(frames: more), #(target, True))
        })
      Ok(#(list.append(seen, more), have))
    }
    False, False if presses <= 1 -> Ok(#(seen, have))
    False, False -> {
      advance(paralytic_surge_lingers_ms)
      let #(later, have) = game_client.read_until_pong(game:, have:, number: 3)
      presses_at_most(
        advance:,
        game:,
        have:,
        target:,
        cast_id: cast_id + 1,
        seen: list.append(seen, later),
        presses: presses - 1,
      )
    }
  }
}
