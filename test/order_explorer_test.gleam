//// The order explorer (`order_explorer`) on scenes small enough to state: what each
//// receiver may take, in which orders, for senders that send to one receiver, to two, and
//// through a process that only another process's mail sets going. The scenes are plain
//// mailboxes: a delivery puts in the mail what the delivered message says it sends.

import gleam/list
import gleam/set
import order_explorer.{type Mail, type Taken, Mail, Scheduler, Taken}
import owned_test

/// What a delivered message sends on: the mail it puts behind what is in flight.
type Sends {
  Sends(mail: List(Mail(String, String, Sends)))
}

/// The mail in flight and what was taken, in order.
type Scene {
  Scene(
    mail: List(Mail(String, String, Sends)),
    taken: List(Taken(String, String)),
  )
}

/// A message to `to` from `from`, which sends nothing when taken.
fn plain(
  to to: String,
  from from: String,
  name name: String,
) -> Mail(String, String, Sends) {
  Mail(to:, from:, input: Sends([]), name:)
}

/// A message to `to` from `from` that sends `sends` when taken.
fn leading_to(
  to to: String,
  from from: String,
  name name: String,
  sends sends: List(Mail(String, String, Sends)),
) -> Mail(String, String, Sends) {
  Mail(to:, from:, input: Sends(sends), name:)
}

fn scheduler() -> order_explorer.Scheduler(Scene, String, String, Sends) {
  Scheduler(
    mail: fn(scene: Scene) { scene.mail },
    deliver: fn(scene: Scene, mail: Mail(String, String, Sends)) {
      Scene(
        mail: list.append(
          order_explorer.remove_first(mail: scene.mail, taken: mail),
          { mail.input }.mail,
        ),
        taken: list.append(scene.taken, [
          Taken(by: mail.to, from: mail.from, name: mail.name),
        ]),
      )
    },
    taken: fn(scene: Scene) { scene.taken },
    queue_name: fn(receiver, sender) { receiver <> " from " <> sender },
  )
}

/// What `receiver` took in each scene of the orders, one order for each scene, in a set.
fn taken_by(
  scenes scenes: List(Scene),
  receiver receiver: String,
) -> List(List(String)) {
  list.map(scenes, fn(scene) {
    order_explorer.order_at(taken: scene.taken, receiver:)
  })
}

pub fn the_explorer_reaches_every_outcome_of_two_senders_to_one_receiver_and_one_order_of_independent_receivers_test() -> Nil {
  use <- owned_test.run(5000)
  // Each row: the mail in flight, the receiver whose orders are read, the orders of that
  // receiver the explorer must reach (each once), and the number of scenes.
  let rows = [
    #(
      "two senders to one receiver: both orders",
      [
        plain(to: "R", from: "A", name: "from A"),
        plain(to: "R", from: "B", name: "from B"),
      ],
      "R",
      [["from A", "from B"], ["from B", "from A"]],
      2,
    ),
    #(
      "one sender's two messages to one receiver: its order",
      [
        plain(to: "R", from: "A", name: "first of A"),
        plain(to: "R", from: "A", name: "second of A"),
      ],
      "R",
      [["first of A", "second of A"]],
      1,
    ),
    #(
      "two deliveries to two receivers: one order",
      [
        plain(to: "R", from: "A", name: "to R"),
        plain(to: "S", from: "A", name: "to S"),
      ],
      "R",
      [["to R"]],
      1,
    ),
    #(
      "two senders to one receiver and one to another: the first receiver's two orders, no more",
      [
        plain(to: "R", from: "A", name: "from A"),
        plain(to: "R", from: "B", name: "from B"),
        plain(to: "S", from: "A", name: "to S"),
      ],
      "R",
      [["from A", "from B"], ["from B", "from A"]],
      2,
    ),
    #(
      "a client's mail to P that makes P send to R, and a second sender to R: R's two orders",
      [
        leading_to(to: "P", from: "client", name: "client to P", sends: [
          plain(to: "R", from: "P", name: "from P"),
        ]),
        plain(to: "R", from: "B", name: "from B"),
      ],
      "R",
      [["from P", "from B"], ["from B", "from P"]],
      2,
    ),
  ]
  list.each(rows, fn(row) {
    let #(name, mail, receiver, expected, scenes_expected) = row
    let scenes =
      order_explorer.orders(
        scheduler: scheduler(),
        scene: Scene(mail:, taken: []),
      )
    assert set.from_list(taken_by(scenes:, receiver:))
      == set.from_list(expected)
      as { name <> ": the receiver's orders" }
    assert list.length(scenes) == scenes_expected
      as { name <> ": one scene for each outcome" }
    assert list.all(scenes, fn(scene) { scene.mail == [] })
      as { name <> ": every scene delivers all of its mail" }
  })
}
