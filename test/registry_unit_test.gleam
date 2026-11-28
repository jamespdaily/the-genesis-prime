//// The registry's groups of a unit's address (genesis_prime/connection/registry `join_unit`,
//// `leave_unit`, `find_unit`, `deliver_unit`), proven with plain processes. Expected values
//// come from the module's doc comment: the group of a `Unit` has the one connection that
//// hosts it, which the map that issued the address joins and empties, and a send to an
//// address with no member finds none. A message that must not arrive is shown by a later
//// message to the same process arriving without it: a sender's messages arrive in order.

import ask_support
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/step
import genesis_prime/world_map/unit_address
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/static_supervisor as supervisor
import map_support
import open_wait
import owned_test

fn started() -> Registry(Int) {
  let scope = registry.new()
  let assert Ok(tree) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(registry.supervised(scope))
    |> supervisor.start
    as "the scope started"
  process.unlink(tree.pid)
  ask_support.guard(tree.pid)
  scope
}

/// A process that tells `got` each message the registry delivers to it.
fn host(scope scope: Registry(Int)) -> #(Pid, Subject(Int)) {
  let ready = process.new_subject()
  let got = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let selector =
        registry.select_delivered(scope, process.new_selector(), fn(message) {
          message
        })
      process.send(ready, Nil)
      forward(selector:, got:)
    })
  open_wait.received(from: ready, what: "the host to start")
  #(pid, got)
}

fn forward(
  selector selector: process.Selector(Int),
  got got: Subject(Int),
) -> Nil {
  process.send(got, process.selector_receive_forever(selector))
  forward(selector:, got:)
}

pub fn a_message_to_an_address_that_ended_is_dropped_by_the_unit_registry_test() -> Nil {
  use <- owned_test.run(5000)
  let scope = started()
  let #(pid, got) = host(scope:)
  let ended = step.Unit(map_support.address(number: 1))
  let live = step.Unit(map_support.address(number: 2))
  registry.join_unit(scope, ended, pid)
  registry.join_unit(scope, live, pid)
  assert registry.deliver_unit(scope, ended, 1) == Ok(Nil)
    as "positive control: a send to a unit in the group is delivered"
  registry.leave_unit(scope, ended)
  assert registry.deliver_unit(scope, ended, 2) == Error(Nil)
    as "a send to the address once its group is emptied finds no process"
  assert registry.deliver_unit(scope, live, 3) == Ok(Nil)
    as "a second send, to a live address, from the same sender"
  assert open_wait.received(from: got, what: "the first message") == 1
  assert open_wait.received(from: got, what: "the next message") == 3
    as "the host took the message of the live address next: the one to the ended address never came"
}

pub fn a_unit_registered_by_the_map_is_found_by_its_address_only_and_not_after_its_leave_test() -> Nil {
  use <- owned_test.run(5000)
  let scope = started()
  let #(pid, _got) = host(scope:)
  let address = map_support.address(number: 1)
  let other = map_support.address_for(incarnation: 2, number: 1, rank: 1)
  assert unit_address.number(address:) == unit_address.number(address: other)
    as "guard: the two addresses have one number and differ by their run"
  registry.join_unit(scope, step.Unit(address), pid)
  assert registry.find_unit(scope, step.Unit(address)) == Ok(pid)
    as "found by its address"
  assert registry.find_unit(scope, step.Unit(other)) == Error(Nil)
    as "not by another run's address of the same number"
  registry.leave_unit(scope, step.Unit(address))
  assert registry.find_unit(scope, step.Unit(address)) == Error(Nil)
    as "and not after its leave"
}
