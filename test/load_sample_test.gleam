//// The load run's sampler (`genesis_prime/load_sample`) read on a node that
//// holds a planted process and the server's real listeners. Expected values
//// are what the test itself planted: the messages it left in a mailbox, the
//// list its process holds, and the connections it opened.
//// - A list cell is two words on the BEAM's heap, so a process holding a list
////   of 100,000 integers has a heap of at least 100,000 words.
//// - The listeners are the tree's STS, auth and game, in that order.

import ask_support
import event_wait
import genesis_prime/load_sample.{Waiting}
import gleam/erlang/process
import gleam/list
import login_client
import login_support
import mailbox_support
import owned_test

pub fn the_sampler_reports_a_planted_processs_mailbox_and_heap_test() -> Nil {
  use <- owned_test.run(60_000)
  let ready = process.new_subject()
  let planted =
    process.spawn_unlinked(fn() {
      let held = list.repeat(1, 100_000)
      process.send(ready, Nil)
      process.sleep_forever()
      list.length(held)
    })
  process.receive_forever(ready)
  mailbox_support.send_raw(to: planted, message: "one")
  mailbox_support.send_raw(to: planted, message: "two")
  mailbox_support.send_raw(to: planted, message: "three")
  let sample = load_sample.take_node()
  let assert [Waiting(mailbox:, heap_words:, ..)] =
    list.filter(sample.waiting, fn(waiting) { waiting.pid == planted })
    as "the planted process is among those with messages waiting"
  assert mailbox == 3
  assert heap_words >= 100_000
  assert sample.largest_heap_words >= heap_words
    as "the largest heap is at least the planted process's"
  process.kill(planted)
}

pub fn the_sampler_reports_each_listeners_connections_and_an_idle_stores_workers_test() -> Nil {
  use <- owned_test.run(60_000)
  let started = login_support.start()
  let ports = login_support.ports(started)
  let login = started.settings.login
  let watch =
    load_sample.Watch(
      listeners: [
        login.sts.listener,
        login.auth.listener,
        started.settings.game.listener,
      ],
      store: started.settings.store,
      pool_size: 2,
    )
  assert load_sample.take(watch).connections == [0, 0, 0]
  let first = login_client.connect(ports.auth_port)
  let second = login_client.connect(ports.auth_port)
  let assert [_] = login_client.read_frames(client: first, have: <<>>, count: 1)
    as "the auth listener greets the first client"
  let assert [_] =
    login_client.read_frames(client: second, have: <<>>, count: 1)
    as "and the second"
  event_wait.until("both clients' connections are held", fn() {
    list.length(ask_support.connections_of(login.auth.listener)) == 2
  })
  let sample = load_sample.take(watch)
  assert sample.connections == [0, 2, 0]
  assert sample.store_waiting == 0 as "no ask is out, so no worker waits"
  login_support.stop(started)
}
