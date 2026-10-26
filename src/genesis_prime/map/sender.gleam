//// One sender of a map's pool: a process that holds no state and does one
//// thing, sending a delivery the map process has decided on to each of its
//// recipients, in the order the recipients are listed.
////
//// The map process picks the sender by the id of the unit a delivery is about,
//// so everything said about one unit passes through one sender, and the
//// sender's mailbox keeps it in the order the map process decided it. A
//// restart rebuilds nothing, because there is nothing to rebuild; deliveries
//// that were waiting in the dead sender's mailbox are lost.

import genesis_prime/map/delivery.{type Delivery}
import genesis_prime/map/heap_limit.{type HeapLimit}
import genesis_prime/telemetry/log
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

/// How long a sender has to stop, in milliseconds: it holds nothing to save,
/// so it has the second every worker that flushes no saves has.
const shutdown_milliseconds = 1000

/// How long a sender has to start, in milliseconds.
const start_deadline_milliseconds = 5000

/// Every message a sender can receive: a delivery to send, or something else,
/// which is logged as a bug.
pub opaque type Message {
  /// Sends the delivery to each recipient, in list order.
  Send(delivery: Delivery, recipients: List(Subject(Delivery)))
  Unexpected(received: Dynamic)
}

/// Who a sender's lines are from: the process, by its kind, and the map by the
/// id of its world.
fn sender_who(world_id: Int) -> log.Who {
  log.Who(
    account: None,
    actor: None,
    place: Some(log.Map(world_id)),
    message: None,
    peer: None,
  )
}

/// The child specification for a sender of the map of the world with the id,
/// registered under `name`, killed when its heap passes `limit`. The map process
/// reaches the sender through the name, so a restarted sender is reached too.
pub fn supervised(
  name name: process.Name(Message),
  limit limit: HeapLimit,
  world_id world_id: Int,
) -> ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(name:, limit:, world_id:) })
  |> supervision.timeout(ms: shutdown_milliseconds)
}

/// Starts a sender registered under `name`, which sets `limit` on itself in
/// its initialiser.
fn start(
  name name: process.Name(Message),
  limit limit: HeapLimit,
  world_id world_id: Int,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(start_deadline_milliseconds, fn(self) {
    heap_limit.apply(limit)
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_other(Unexpected)
    actor.initialised(world_id)
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.named(name)
  |> actor.on_message(handle)
  |> actor.start
}

/// Asks a sender to send `delivery` to each of `recipients`, in order, and
/// returns at once.
pub fn send(
  sender sender: Subject(Message),
  delivery delivery: Delivery,
  recipients recipients: List(Subject(Delivery)),
) -> Nil {
  process.send(sender, Send(delivery:, recipients:))
}

fn handle(world_id: Int, message: Message) -> actor.Next(Int, Message) {
  case message {
    Send(delivery:, recipients:) -> {
      list.each(recipients, fn(recipient) { process.send(recipient, delivery) })
      actor.continue(world_id)
    }
    Unexpected(..) -> {
      log.error(
        sender_who(world_id),
        "a map's sender received a message it does not handle",
      )
      actor.continue(world_id)
    }
  }
}
