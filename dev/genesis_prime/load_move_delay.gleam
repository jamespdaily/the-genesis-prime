//// The mover-to-viewer delay of the movement load run (`genesis_prime/load_moves`):
//// how long after a player sends a move a player who sees it has it in hand.
////
//// ```
//// probe 1 ── 0x0637 (step k at z = base + 0.01 k) ──▶ server ──▶ 0x0638 ──▶ probes 2, 3, 4
////        └ stamps k's send                                     └ each stamps k's receipt
//// ```
////
//// A few clients of the real protocol, the probes, join the map among the walkers.
//// Each sends a 0x0637 every 125 ms like a walker, but the position of its step `k`
//// is the walkers' own z plus 0.01 `k`, so a 0x0638 that carries it names the step
//// (`step_of`), and each probe reads its socket as the frames arrive, so it stamps a
//// receipt when the client's side of the socket has it and not at its next send. The
//// delay of a move to a viewer is the viewer's stamp of the 0x0638 minus the mover's
//// stamp just before it wrote the 0x0637, both on this node's monotonic clock in
//// microseconds.
////
//// What it measures is the path a walker's move takes to a viewer's socket plus the
//// clients' own scheduling (the clients share four schedulers with the walkers), so a
//// run is compared with another by the same instrument and not with a bound of the
//// client's. The probes are clients like the walkers, so they add to the map's players
//// (100 walkers and the probes). A move a viewer never read is counted, not left out of
//// the number of moves expected.
////
//// The probes begin when the walkers have all arrived, are all in the world by `sync_ms`
//// (a probe that is not stops the run), send for `window_ms` and leave.

import exception
import game_client
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/load_player.{type Account}
import genesis_prime/load_sample
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement
import genesis_prime/step/runtime
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import login_client.{type Ports}
import mug

/// How often a probe sends a move: the walkers' and the client's.
const move_every_ms = 125

/// The z of the walkers' moves (World 3460, WorldLocation2 row 51596), which a
/// probe's step `k` adds 0.01 `k` to.
const base_z = -560.18798828125

/// What a probe saw of the others and sent itself, when it finished: its unit, the
/// microsecond it stamped for the send of each step, and the moves of other probes it
/// read, as the unit, the step and the microsecond it stamped.
pub type Probed {
  Probed(unit_id: Int, sent_us: Dict(Int, Int), seen: List(#(Int, Int, Int)))
}

/// A probe's account, the time it logs in, the time all probes are in the world, and
/// how long it sends moves.
pub type Plan {
  Plan(account: Account, begin_ms: Int, sync_ms: Int, window_ms: Int)
}

/// The delays of the moves the probes read, in microseconds, and how many moves a
/// viewer should have read.
pub type Delays {
  Delays(microseconds: List(Int), expected: Int)
}

/// Starts a probe on `plan`, which sends what it saw to `report` when it is done, or
/// what it ended with when it crashed.
pub fn start(
  plan plan: Plan,
  ports ports: Ports,
  report report: Subject(Result(Probed, String)),
) -> Nil {
  let _pid =
    process.spawn_unlinked(fn() {
      case exception.rescue(fn() { run(plan:, ports:) }) {
        Ok(probed) -> process.send(report, Ok(probed))
        Error(crash) -> process.send(report, Error(string.inspect(crash)))
      }
    })
  Nil
}

/// What a probe sent to `report`, waiting up to `within_ms`; a probe that crashed or
/// did not report stops the run with the reason.
pub fn reported(
  report report: Subject(Result(Probed, String)),
  within_ms within_ms: Int,
) -> Probed {
  let assert Ok(found) = process.receive(report, within: within_ms)
    as "every probe reported"
  case found {
    Ok(probed) -> probed
    Error(crash) -> panic as { "a probe crashed: " <> crash }
  }
}

fn run(plan plan: Plan, ports ports: Ports) -> Probed {
  process.sleep(int.max(0, plan.begin_ms - runtime.now().monotonic_ms))
  let #(game, auth) = load_player.log_in(account: plan.account, ports:)
  load_player.list_characters(game)
  let character_id =
    load_player.create_character(game:, name: plan.account.character_name)
  let #(burst, have) = load_player.play_into_world(game:, character_id:)
  assert runtime.now().monotonic_ms <= plan.sync_ms
    as "a probe is in the world by the time the probes begin to send"
  let unit_id = game_client.unit_create_player_in(frames: burst).unit_id
  process.sleep(int.max(0, plan.sync_ms - runtime.now().monotonic_ms))
  let started_us = load_sample.microseconds()
  let probed =
    probe(
      game:,
      have:,
      step: 1,
      started_us:,
      ends_us: started_us + plan.window_ms * 1000,
      probed: Probed(unit_id:, sent_us: dict.new(), seen: []),
    )
  game_client.close(game:)
  let _closed = mug.shutdown(auth)
  probed
}

/// Sends step `step`'s move when it is due and reads and stamps what arrives until
/// then, until `ends_us`.
fn probe(
  game game: game_client.Game,
  have have: BitArray,
  step step: Int,
  started_us started_us: Int,
  ends_us ends_us: Int,
  probed probed: Probed,
) -> Probed {
  let now_us = load_sample.microseconds()
  use <- bool.guard(when: now_us >= ends_us, return: probed)
  let due_us = started_us + { step - 1 } * move_every_ms * 1000
  case now_us >= due_us {
    True -> {
      let sent_us = load_sample.microseconds()
      game_client.send_world(
        game:,
        message_id: 0x0637,
        body: game_client.moves_body(
          client_clock: step * move_every_ms,
          commands: [
            game_client.position_command(
              x: 29.128599166870117 +. int.to_float(step % 10),
              y: -853.87158203125,
              z: base_z +. int.to_float(step) *. 0.01,
            ),
          ],
        ),
      )
      probe(
        game:,
        have:,
        step: step + 1,
        started_us:,
        ends_us:,
        probed: Probed(
          ..probed,
          sent_us: dict.insert(probed.sent_us, step, sent_us),
        ),
      )
    }
    False -> {
      let assert Ok(#(frames, have)) =
        game_client.poll(
          game:,
          have:,
          wait_ms: int.max(1, int.min(5, { due_us - now_us } / 1000)),
        )
        as "the game server's connection held while a probe read it"
      let stamped_us = load_sample.microseconds()
      let seen =
        list.filter_map(frames, fn(frame) {
          step_of(frame)
          |> result.map(fn(moved) { #(moved.0, moved.1, stamped_us) })
        })
      probe(
        game:,
        have:,
        step:,
        started_us:,
        ends_us:,
        probed: Probed(..probed, seen: list.append(seen, probed.seen)),
      )
    }
  }
}

/// The unit and the step a 0x0638 carries, when it is a probe's move: its last kind 2
/// position has z above the walkers' by a whole number of hundredths, which no walker's
/// move has.
fn step_of(frame: Frame) -> Result(#(Int, Int), Nil) {
  use <- bool.guard(when: frame.message_id != 0x0638, return: Error(Nil))
  use moved <- result.try(
    unit_movement.decode(frame.body) |> result.replace_error(Nil),
  )
  list.filter_map(moved.commands, fn(command) {
    case command {
      relayed_movement.Position(placed) -> Ok(placed)
      _ -> Error(Nil)
    }
  })
  |> list.last
  |> result.try(fn(placed) {
    let #(_x, _y, z) = game_client.standing(placed)
    let step = float.round({ z -. base_z } /. 0.01)
    case step >= 1 {
      True -> Ok(#(moved.unit_id, step))
      False -> Error(Nil)
    }
  })
}

/// The delay of each move a probe read: its stamp minus the stamp of the send of the
/// same step by the probe that owns the unit, with the number of moves the probes
/// should have read (each probe's moves, to each other probe).
pub fn delays(probed probed: List(Probed)) -> Delays {
  let senders =
    list.map(probed, fn(one) { #(one.unit_id, one.sent_us) }) |> dict.from_list
  let microseconds =
    list.flat_map(probed, fn(viewer) {
      list.filter_map(viewer.seen, fn(seen) {
        let #(unit_id, step, seen_us) = seen
        use sent_us <- result.try(
          dict.get(senders, unit_id)
          |> result.try(fn(sent_us) { dict.get(sent_us, step) }),
        )
        Ok(seen_us - sent_us)
      })
    })
  Delays(
    microseconds:,
    expected: list.fold(probed, 0, fn(sum, one) {
      sum + dict.size(one.sent_us) * { list.length(probed) - 1 }
    }),
  )
}
