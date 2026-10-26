//// One sender of prototype C's pool: a process that holds no state and does
//// one thing, sending a delivery the map process has decided on to each of
//// its recipients, in the order the recipients are listed.
////
//// The map process picks the sender by the id of the unit a delivery is about,
//// so everything said about one unit passes through one sender, and the
//// sender's mailbox keeps it in the order the map process decided it. A
//// restart rebuilds nothing, because there is nothing to rebuild; deliveries
//// that were waiting in the dead sender's mailbox are lost.

import genesis_prime/topology/update.{type Delivery}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

/// Every message a sender can receive. Its selector covers all of them;
/// anything else is logged.
pub type Message {
  /// Sends the delivery to each recipient, in list order.
  Send(delivery: Delivery, recipients: List(Subject(Delivery)))
  /// Asks the process to answer, to show that it handles messages.
  Probe(reply_with: Subject(Nil))
}

/// The child specification for a sender registered under `name`. The map
/// process reaches the sender through the name, so a restarted sender is
/// reached too.
pub fn supervised(
  name name: process.Name(Message),
) -> ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(name) })
}

/// Starts a sender registered under `name`.
pub fn start(
  name: process.Name(Message),
) -> actor.StartResult(Subject(Message)) {
  actor.new(Nil)
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

fn handle(state: Nil, message: Message) -> actor.Next(Nil, Message) {
  case message {
    Send(delivery:, recipients:) -> {
      let _ = delivery
      let _ = recipients
      todo as "body in the build commit"
    }
    Probe(reply_with:) -> {
      process.send(reply_with, Nil)
      actor.continue(state)
    }
  }
}
