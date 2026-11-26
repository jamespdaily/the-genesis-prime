//// Every order in which the BEAM may deliver what processes send each other, for a scene
//// of rules that supplies its own delivery. One scheduler serves `legal_order_support` and
//// `player_scene_support`. Expected values come from these places.
//// - OTP orders the signals of one sender to one receiver, and no others: a receiver's
////   mailbox holds one first-in-first-out queue for each sender and it takes the head of
////   any of them next. A delivery here is the head of one such queue (`heads`).
//// - A delivery changes only its receiver's state, takes the head of a queue of that
////   receiver and puts mail in queues whose sender is that receiver. So two deliveries to
////   different receivers commute, and two to the same receiver are the only dependent
////   pair. An outcome is what each receiver took, in order: the scenes of two orders with
////   the same outcome are the same scene. Each receiver keeps a clock of its own
////   (`Clocks`), so a step's time does not depend on the other receivers' deliveries and
////   the commuting is exact.
//// - `orders` walks the deliveries depth first with sleep sets (Godefroid): after a
////   delivery has been explored from a scene, it sleeps in the scenes of the later
////   deliveries and is not taken again until a delivery to its receiver wakes it, since
////   every order that takes it later is an order of its own subtree. The heads are taken
////   in the order of their queues' names, a fixed order, so each outcome is reached by
////   one walk. There is no cap on the walk and no sampling.
//// - `orders_in_full` walks every state with no reduction, merging states by what each
////   receiver took and the mail in flight; it is the reference the reduced walk is
////   checked against.
////
//// ```
//// scheduler(mail, deliver, taken) ─▶ orders(scene) ─▶ one scene for each outcome
////                                   orders_in_full(scene) ─▶ one scene for each outcome, unreduced
//// ```

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// One message in a mailbox: its receiver, its sender, what it is and its name, which the
/// tests read the order of deliveries by.
pub type Mail(receiver, sender, input) {
  Mail(to: receiver, from: sender, input: input, name: String)
}

/// What a receiver took: from whom, and the name of the message.
pub type Taken(receiver, sender) {
  Taken(by: receiver, from: sender, name: String)
}

/// What a scene gives the explorer: the mail in flight in the order it was sent, the
/// scene after a receiver takes one mail (the rule's step, and what it sends put in the
/// mail behind what is there), what the receivers took so far in order, and the name of
/// the queue a sender has at a receiver, which orders the walk.
pub type Scheduler(scene, receiver, sender, input) {
  Scheduler(
    mail: fn(scene) -> List(Mail(receiver, sender, input)),
    deliver: fn(scene, Mail(receiver, sender, input)) -> scene,
    taken: fn(scene) -> List(Taken(receiver, sender)),
    queue_name: fn(receiver, sender) -> String,
  )
}

/// What each receiver took, in order, with the sender and the name of each message: two
/// scenes with the same outcome are the same scene.
pub type Outcome(receiver, sender) =
  Dict(receiver, List(#(sender, String)))

/// The deliveries a scene allows now: the head of each queue, one for each receiver and
/// sender, in the order they were sent.
pub fn heads(
  mail mail: List(Mail(receiver, sender, input)),
) -> List(Mail(receiver, sender, input)) {
  list.fold(mail, [], fn(heads, mail) {
    case
      list.any(heads, fn(head: Mail(_, _, _)) {
        head.to == mail.to && head.from == mail.from
      })
    {
      True -> heads
      False -> [mail, ..heads]
    }
  })
  |> list.reverse
}

/// The mail without its first message equal to `taken`.
pub fn remove_first(
  mail mail: List(Mail(receiver, sender, input)),
  taken taken: Mail(receiver, sender, input),
) -> List(Mail(receiver, sender, input)) {
  case mail {
    [] -> []
    [first, ..rest] ->
      case first == taken {
        True -> rest
        False -> [first, ..remove_first(mail: rest, taken:)]
      }
  }
}

/// The scene after every delivery is made in the order the heads are found: one order,
/// for a setup the tests do not vary.
pub fn settle(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  scene scene: scene,
) -> scene {
  case heads(mail: scheduler.mail(scene)) {
    [] -> scene
    [mail, ..] -> settle(scheduler:, scene: scheduler.deliver(scene, mail))
  }
}

/// The scenes the deliveries can end in, one for each outcome, in the order the walk
/// reaches them.
pub fn orders(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  scene scene: scene,
) -> List(scene) {
  explore(scheduler:, scene:, asleep: [], finished: []) |> list.reverse
}

/// A queue, by its receiver and its sender.
type Queue(receiver, sender) =
  #(receiver, sender)

fn explore(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  scene scene: scene,
  asleep asleep: List(Queue(receiver, sender)),
  finished finished: List(scene),
) -> List(scene) {
  case heads(mail: scheduler.mail(scene)) {
    [] -> [scene, ..finished]
    enabled ->
      list.sort(enabled, fn(first, second) {
        string.compare(
          scheduler.queue_name(first.to, first.from),
          scheduler.queue_name(second.to, second.from),
        )
      })
      |> list.filter(fn(mail) { !list.contains(asleep, #(mail.to, mail.from)) })
      |> list.fold(#(finished, asleep), fn(so_far, mail) {
        let #(finished, asleep) = so_far
        let woken =
          list.filter(asleep, fn(queue: Queue(receiver, sender)) {
            queue.0 != mail.to
          })
        #(
          explore(
            scheduler:,
            scene: scheduler.deliver(scene, mail),
            asleep: woken,
            finished:,
          ),
          [#(mail.to, mail.from), ..asleep],
        )
      })
      |> fn(done) { done.0 }
  }
}

/// The scenes the deliveries can end in with no reduction: every state is walked, and
/// states with the same outcome so far and the same mail in flight are walked once. One
/// scene for each outcome, in the order the walk reaches them.
pub fn orders_in_full(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  scene scene: scene,
) -> List(scene) {
  let #(finished, _) =
    walk_in_full(scheduler:, scene:, seen: set.new(), finished: [])
  list.reverse(finished)
}

fn walk_in_full(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  scene scene: scene,
  seen seen: Set(
    #(Outcome(receiver, sender), Set(#(receiver, sender, List(String)))),
  ),
  finished finished: List(scene),
) -> #(
  List(scene),
  Set(#(Outcome(receiver, sender), Set(#(receiver, sender, List(String))))),
) {
  let mail = scheduler.mail(scene)
  let key = #(outcome(taken: scheduler.taken(scene)), queues(mail:))
  case set.contains(seen, key) {
    True -> #(finished, seen)
    False -> {
      let seen = set.insert(seen, key)
      case heads(mail:) {
        [] -> #([scene, ..finished], seen)
        enabled ->
          list.fold(enabled, #(finished, seen), fn(so_far, mail) {
            walk_in_full(
              scheduler:,
              scene: scheduler.deliver(scene, mail),
              seen: so_far.1,
              finished: so_far.0,
            )
          })
      }
    }
  }
}

/// The names of the messages in flight, for each queue, in order.
fn queues(
  mail mail: List(Mail(receiver, sender, input)),
) -> Set(#(receiver, sender, List(String))) {
  list.fold(mail, dict.new(), fn(by_queue, mail: Mail(_, _, _)) {
    let queue = #(mail.to, mail.from)
    dict.insert(
      by_queue,
      queue,
      list.append(dict.get(by_queue, queue) |> result.unwrap([]), [mail.name]),
    )
  })
  |> dict.to_list
  |> list.map(fn(entry) { #(entry.0.0, entry.0.1, entry.1) })
  |> set.from_list
}

/// What each receiver took, in order.
pub fn outcome(
  taken taken: List(Taken(receiver, sender)),
) -> Outcome(receiver, sender) {
  list.fold(taken, dict.new(), fn(by_receiver, taken) {
    dict.insert(
      by_receiver,
      taken.by,
      list.append(dict.get(by_receiver, taken.by) |> result.unwrap([]), [
        #(taken.from, taken.name),
      ]),
    )
  })
}

/// The names of what the receiver took, in order.
pub fn order_at(
  taken taken: List(Taken(receiver, sender)),
  receiver receiver: receiver,
) -> List(String) {
  list.filter(taken, fn(taken) { taken.by == receiver })
  |> list.map(fn(taken) { taken.name })
}

/// The monotonic clocks of the receivers of a scene, each its own: a receiver's step is
/// taken at its clock's next millisecond, whatever the other receivers have taken.
pub opaque type Clocks(receiver) {
  Clocks(start_ms: Int, at: Dict(receiver, Int))
}

/// Clocks that all stand at `start_ms`.
pub fn clocks(start_ms start_ms: Int) -> Clocks(receiver) {
  Clocks(start_ms:, at: dict.new())
}

/// The time of the receiver's clock.
pub fn now_ms(
  clocks clocks: Clocks(receiver),
  receiver receiver: receiver,
) -> Int {
  dict.get(clocks.at, receiver) |> result.unwrap(clocks.start_ms)
}

/// The receiver's clock a millisecond on, and the time it stands at then: the time a
/// delivery to the receiver is taken at.
pub fn ticked(
  clocks clocks: Clocks(receiver),
  receiver receiver: receiver,
) -> #(Clocks(receiver), Int) {
  let ms = now_ms(clocks:, receiver:) + 1
  #(Clocks(..clocks, at: dict.insert(clocks.at, receiver, ms)), ms)
}

/// The receiver's clock at `ms`, or where it stands when that is later.
pub fn advanced_to(
  clocks clocks: Clocks(receiver),
  receiver receiver: receiver,
  ms ms: Int,
) -> Clocks(receiver) {
  Clocks(
    ..clocks,
    at: dict.insert(
      clocks.at,
      receiver,
      int.max(now_ms(clocks:, receiver:), ms),
    ),
  )
}
