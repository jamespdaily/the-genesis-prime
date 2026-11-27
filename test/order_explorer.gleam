//// Every order in which the BEAM may deliver what processes send each other, for a scene
//// of rules that supplies its own delivery. One scheduler serves `legal_order_support` and
//// `player_scene_support`. Expected values come from these places.
//// - OTP orders the signals of one sender to one receiver, and no others: a receiver's
////   mailbox holds one first-in-first-out queue for each sender and it takes the head of
////   any of them next. A delivery here is the head of one such queue (`heads`).
//// - A delivery changes only its receiver's state, takes the head of a queue of that
////   receiver and puts mail in queues whose sender is that receiver. So two deliveries to
////   different receivers commute. Two to the same receiver commute at a scene when taking
////   them in either order from it is possible and ends in the same state of every process
////   and the same mail in every queue (`independent` runs both orders and compares); they
////   are dependent otherwise. Each receiver keeps a clock of its own (`Clocks`), so a
////   step's time does not depend on the other receivers' deliveries.
//// - `orders` walks the deliveries depth first with sleep sets (Godefroid): after a
////   delivery has been explored from a scene, it sleeps in the scenes of the later
////   deliveries. A sleeper passes on to the scene after a delivery only if it is still
////   possible at the scene before it and commutes with that delivery there, checked at
////   every scene on the walk; otherwise it wakes and is taken again. Whatever follows a
////   sleeper's delivery then also follows it in the subtree that took it first, to the
////   same state, so each state the deliveries can end in is reached at least once. A state
////   reached by orders that commute is reached by one of them; the scenes of orders that
////   differ only in what they took at a commuting pair are the same scene. The heads are
////   taken in the order of their queues' names. There is no cap on the walk and no
////   sampling.
//// - `orders_by_receiver` counts every two deliveries to one receiver as dependent; it
////   is the relation `orders` refines, kept so a test shows both end in the same states.
//// - `orders_in_full` walks every state with no reduction, merging states by what each
////   receiver took and the mail in flight; it is the reference the reduced walk is
////   checked against.
////
//// ```
//// scheduler(mail, deliver, taken, same_state) ─▶ orders(scene) ─▶ one scene for each state it ends in
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

/// What a scene gives the explorer: the mail a receiver may take now in the order it was
/// sent, all the mail in flight (taken or not, which a receiver waiting for an answer does
/// not take yet), the
/// scene after a receiver takes one mail (the rule's step, and what it sends put in the
/// mail behind what is there), what the receivers took so far in order, whether two
/// scenes hold the same state in every process (leaving out what was taken and the mail,
/// which the explorer compares itself), and the name of the queue a sender has at a
/// receiver, which orders the walk.
pub type Scheduler(scene, receiver, sender, input) {
  Scheduler(
    mail: fn(scene) -> List(Mail(receiver, sender, input)),
    in_flight: fn(scene) -> List(Mail(receiver, sender, input)),
    deliver: fn(scene, Mail(receiver, sender, input)) -> scene,
    taken: fn(scene) -> List(Taken(receiver, sender)),
    same_state: fn(scene, scene) -> Bool,
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
/// reaches them. Two deliveries to one receiver are independent at a scene when they
/// commute there (`Commuting`).
pub fn orders(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  scene scene: scene,
) -> List(scene) {
  explore(scheduler:, relation: Commuting, scene:, asleep: [], finished: [])
  |> list.reverse
}

/// The scenes the deliveries can end in when every two deliveries to one receiver are
/// dependent (`ByReceiver`): the relation `orders` refines, kept to show the two reach the
/// same scenes.
pub fn orders_by_receiver(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  scene scene: scene,
) -> List(scene) {
  explore(scheduler:, relation: ByReceiver, scene:, asleep: [], finished: [])
  |> list.reverse
}

/// Whether `orders` and `orders_by_receiver` end in the same scenes from `scene`: each
/// ending of one is in the same state (`Scheduler.same_state`) as an ending of the other.
pub fn relations_end_alike(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  scene scene: scene,
) -> Bool {
  let finer = orders(scheduler:, scene:)
  let coarser = orders_by_receiver(scheduler:, scene:)
  let within = fn(scenes, ending) {
    list.any(scenes, fn(other) { scheduler.same_state(ending, other) })
  }
  list.all(finer, within(coarser, _)) && list.all(coarser, within(finer, _))
}

/// When two deliveries are independent at a scene.
type Relation {
  /// Whenever their receivers differ.
  ByReceiver
  /// Whenever their receivers differ, or taking them in either order from the scene is
  /// possible and gives the same state and the same mail.
  Commuting
}

/// Whether two deliveries, both possible at `scene`, are independent there; `after_second`
/// is the scene after the second.
fn independent(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  relation relation: Relation,
  scene scene: scene,
  first first: Mail(receiver, sender, input),
  second second: Mail(receiver, sender, input),
  after_second after_second: scene,
) -> Bool {
  case first.to == second.to, relation {
    False, _ -> True
    True, ByReceiver -> False
    True, Commuting -> {
      let after_first = scheduler.deliver(scene, first)
      let possible = fn(after, mail) {
        list.contains(heads(mail: scheduler.mail(after)), mail)
      }
      case possible(after_first, second), possible(after_second, first) {
        True, True -> {
          let first_then_second = scheduler.deliver(after_first, second)
          let second_then_first = scheduler.deliver(after_second, first)
          scheduler.same_state(first_then_second, second_then_first)
          && same_mail(
            scheduler.in_flight(first_then_second),
            scheduler.in_flight(second_then_first),
          )
        }
        _, _ -> False
      }
    }
  }
}

/// Whether two mailboxes hold the same messages in each queue, in order.
fn same_mail(
  first: List(Mail(receiver, sender, input)),
  second: List(Mail(receiver, sender, input)),
) -> Bool {
  by_queue(mail: first) == by_queue(mail: second)
}

fn by_queue(
  mail mail: List(Mail(receiver, sender, input)),
) -> Dict(#(receiver, sender), List(Mail(receiver, sender, input))) {
  list.fold(list.reverse(mail), dict.new(), fn(by_queue, mail) {
    let queue = #(mail.to, mail.from)
    dict.insert(by_queue, queue, [
      mail,
      ..dict.get(by_queue, queue)
      |> result.unwrap([])
    ])
  })
}

fn explore(
  scheduler scheduler: Scheduler(scene, receiver, sender, input),
  relation relation: Relation,
  scene scene: scene,
  asleep asleep: List(Mail(receiver, sender, input)),
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
      |> list.filter(fn(mail) { !list.contains(asleep, mail) })
      |> list.fold(#(finished, asleep), fn(so_far, mail) {
        let #(finished, asleep) = so_far
        // A sleeper stays asleep after `mail` only while it is still possible here and
        // commutes with `mail` here; the check is made again at every scene.
        let after_mail = scheduler.deliver(scene, mail)
        let staying =
          list.filter(asleep, fn(sleeper) {
            list.contains(enabled, sleeper)
            && independent(
              scheduler:,
              relation:,
              scene:,
              first: sleeper,
              second: mail,
              after_second: after_mail,
            )
          })
        #(
          explore(
            scheduler:,
            relation:,
            scene: after_mail,
            asleep: staying,
            finished:,
          ),
          [mail, ..asleep],
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
  by_queue(mail:)
  |> dict.to_list
  |> list.map(fn(entry) {
    #(
      entry.0.0,
      entry.0.1,
      list.map(entry.1, fn(mail: Mail(_, _, _)) { mail.name }),
    )
  })
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
