//// The maps' sends to one connection held back, for the tests that read what a viewer is
//// written while the map is late: the late map that makes a race between a viewer's picture and the moves told to it happen on demand. A
//// delay is a real time, since no clock reaches a send between two processes of the tree, so
//// the tests that use it assert what holds whatever the timing, and none of them waits a
//// fixed time for a result.
////
//// ```
//// map ── send(to, outgoing) ──▶ forwarder ── to the viewer: held `delay_ms`, in the map's order ──▶ viewer
////                                        └─ to any other: carried out when taken ──────────────────▶ that connection
//// ```

import genesis_prime/map/message as map_message
import genesis_prime/service.{type Reach}
import genesis_prime/step
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import open_wait

/// The reach of a world's maps with every send carried out by one forwarder process
/// (`server.World.maps_reach`): a send to the viewer, the unit of the larger number
/// named by the first notice of sight the map sends (the numbers rise with the order the
/// units joined in, so it is the one that entered second),
/// is carried out `delay_ms` after the map made it and behind the viewer's sends the map made
/// before it; every other send is carried out when the forwarder takes it. The forwarder ends
/// with `owner`, the process of the test.
pub fn delaying(
  owner owner: process.Pid,
  delay_ms delay_ms: Int,
) -> fn(Reach(map_message.Outgoing)) -> Reach(map_message.Outgoing) {
  let forwarder = start_forwarder(owner:, delay_ms:)
  fn(reach: Reach(map_message.Outgoing)) {
    service.Reach(..reach, send: fn(to, outgoing) {
      process.send(forwarder, Sent(Send(to:, outgoing:, carry_out: reach.send)))
      Ok(Nil)
    })
  }
}

/// A send of a map and the way to carry it out.
type Send {
  Send(
    to: step.Address,
    outgoing: map_message.Outgoing,
    carry_out: fn(step.Address, map_message.Outgoing) -> Result(Nil, Nil),
  )
}

/// What the forwarder of a map's sends takes: a send the map made, or the end of a hold, or
/// the end of the test that started it.
type Forwarding {
  Sent(send: Send)
  HoldEnded
  OwnerEnded
}

/// Starts the one process that carries out every send of the world's maps (`delaying`).
fn start_forwarder(
  owner owner: process.Pid,
  delay_ms delay_ms: Int,
) -> process.Subject(Forwarding) {
  let ready = process.new_subject()
  process.spawn_unlinked(fn() {
    let inbox = process.new_subject()
    process.send(ready, inbox)
    let selector =
      process.new_selector()
      |> process.select(inbox)
      |> process.select_specific_monitor(process.monitor(owner), fn(_) {
        OwnerEnded
      })
    forward(selector:, inbox:, delay_ms:, viewer: None, held: [])
  })
  open_wait.received(from: ready, what: "the forwarder of the maps' sends")
}

fn forward(
  selector selector: process.Selector(Forwarding),
  inbox inbox: process.Subject(Forwarding),
  delay_ms delay_ms: Int,
  viewer viewer: Option(UnitAddress),
  held held: List(Send),
) -> Nil {
  case process.selector_receive_forever(selector) {
    OwnerEnded -> Nil
    HoldEnded ->
      case held {
        [Send(to:, outgoing:, carry_out:), ..rest] -> {
          carried_out(sent: carry_out(to, outgoing))
          forward(selector:, inbox:, delay_ms:, viewer:, held: rest)
        }
        [] -> forward(selector:, inbox:, delay_ms:, viewer:, held:)
      }
    Sent(send: Send(to:, outgoing:, carry_out:) as send) -> {
      let viewer = case viewer, to, outgoing {
        None,
          step.Unit(told),
          map_message.Noticed(notice: map_message.SeenBy(by:, ..))
        ->
          Some(
            case
              unit_address.number(address: told)
              > unit_address.number(address: by)
            {
              True -> told
              False -> by
            },
          )
        _, _, _ -> viewer
      }
      case to, viewer {
        step.Unit(told), Some(delayed) if told == delayed -> {
          process.send_after(inbox, delay_ms, HoldEnded)
          forward(
            selector:,
            inbox:,
            delay_ms:,
            viewer:,
            held: list.append(held, [send]),
          )
        }
        _, _ -> {
          carried_out(sent: carry_out(to, outgoing))
          forward(selector:, inbox:, delay_ms:, viewer:, held:)
        }
      }
    }
  }
}

/// A send to a process that has ended finds none there and is dropped, as the shell drops it.
fn carried_out(sent sent: Result(Nil, Nil)) -> Nil {
  case sent {
    Ok(Nil) | Error(Nil) -> Nil
  }
}
