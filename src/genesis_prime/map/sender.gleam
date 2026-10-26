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
import gleam/erlang/process.{type Subject}
import gleam/otp/supervision.{type ChildSpecification}

/// Every message a sender can receive. Its selector covers all of them;
/// anything else is logged.
pub opaque type Message {
  /// Sends the delivery to each recipient, in list order.
  Send(delivery: Delivery, recipients: List(Subject(Delivery)))
}

/// The child specification for a sender registered under `name`, killed when
/// its heap passes `limit`. The map process reaches the sender through the
/// name, so a restarted sender is reached too. A sender holds nothing to save,
/// so it has the second every worker has to stop.
pub fn supervised(
  name name: process.Name(Message),
  limit limit: HeapLimit,
) -> ChildSpecification(Subject(Message)) {
  todo as "the child specification of a sender"
}

/// Asks a sender to send `delivery` to each of `recipients`, in order, and
/// returns at once.
pub fn send(
  sender sender: Subject(Message),
  delivery delivery: Delivery,
  recipients recipients: List(Subject(Delivery)),
) -> Nil {
  todo as "asks a sender to send"
}
