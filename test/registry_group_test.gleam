//// The registry's groups of a character's name and of a zone channel
//// (genesis_prime/connection/registry), proven with plain processes that join
//// and leave on a message. Expected values come from the module's doc comment
//// and from OTP's `pg`: a process that ends leaves its groups by itself, and
//// `pg:join` of a group the process is in adds it again unless the registry
//// skips it. A message that must not arrive is shown by a later message to the
//// same process arriving without it: a sender's messages arrive in order.

import ask_support
import event_wait
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/step
import genesis_prime/world_map/map_id.{MapId}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/static_supervisor as supervisor
import open_wait
import owned_test

/// What a member process is told to do, or was delivered.
type Command {
  Join(address: step.Address)
  Leave(address: step.Address)
  Stop
  Delivered(message: Int)
}

/// The last message of a test, which ends each member's list.
const last = 99

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

/// A member process: it joins and leaves groups as it is told, answers each
/// command on `done` once it has carried it out, and tells `got` each message
/// the registry delivers to it.
type Member {
  Member(commands: Subject(Command), done: Subject(Nil), got: Subject(Int))
}

fn member(scope scope: Registry(Int)) -> Member {
  let ready = process.new_subject()
  let done = process.new_subject()
  let got = process.new_subject()
  let _pid =
    process.spawn_unlinked(fn() {
      let commands = process.new_subject()
      process.send(ready, commands)
      let selector =
        process.new_selector()
        |> process.select(commands)
        |> registry.select_delivered(scope, _, Delivered)
      loop(scope:, selector:, done:, got:)
    })
  let commands = open_wait.received(from: ready, what: "the member to start")
  Member(commands:, done:, got:)
}

fn loop(
  scope scope: Registry(Int),
  selector selector: process.Selector(Command),
  done done: Subject(Nil),
  got got: Subject(Int),
) -> Nil {
  case process.selector_receive_forever(selector) {
    Join(address:) -> {
      registry.join_group(scope, address)
      process.send(done, Nil)
      loop(scope:, selector:, done:, got:)
    }
    Leave(address:) -> {
      registry.leave_group(scope, address)
      process.send(done, Nil)
      loop(scope:, selector:, done:, got:)
    }
    Delivered(message:) -> {
      process.send(got, message)
      loop(scope:, selector:, done:, got:)
    }
    Stop -> Nil
  }
}

fn told(member: Member, command: Command) -> Nil {
  process.send(member.commands, command)
  let Nil =
    open_wait.received(
      from: member.done,
      what: "the member to carry the command out",
    )
  Nil
}

/// The messages the member got up to and not including `last`.
fn got_before_last(member: Member) -> List(Int) {
  collect(member.got, [])
}

fn collect(got: Subject(Int), found: List(Int)) -> List(Int) {
  let message = open_wait.received(from: got, what: "the last message")
  case message == last {
    True -> list.reverse(found)
    False -> collect(got, [message, ..found])
  }
}

fn zone(top_zone_id: Int) -> step.Address {
  step.ZoneChannel(
    map: MapId(world_id: 1, instance: 0),
    incarnation: 1,
    top_zone_id:,
  )
}

pub fn a_joined_character_name_finds_its_member_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = started()
  let one = member(scope:)
  assert registry.find_named(scope, "ab cd") == Error(Nil)
    as "no connection holds the name"
  told(one, Join(step.CharacterNamed("ab cd")))
  let assert Ok(_) = registry.find_named(scope, "ab cd")
    as "the process that joined is the group's member"
  Nil
}

pub fn a_second_member_of_a_name_is_the_one_found_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = started()
  let older = member(scope:)
  let newer = member(scope:)
  let name = step.CharacterNamed("ab cd")
  told(older, Join(name))
  let assert Ok(older_pid) = registry.find_named(scope, "ab cd")
  told(newer, Join(name))
  let assert Ok(newer_pid) = registry.find_named(scope, "ab cd")
  assert older_pid != newer_pid
    as "pg lists the latest join first, so the newest login is the one found; the older is ending (a takeover) and its watcher's end answers"
  told(newer, Leave(name))
  assert registry.find_named(scope, "ab cd") == Ok(older_pid)
    as "with the newer gone, the older is found"
}

pub fn a_process_that_joins_a_group_twice_is_one_member_and_one_leave_removes_it_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = started()
  let one = member(scope:)
  told(one, Join(zone(7)))
  told(one, Join(zone(7)))
  assert registry.deliver_group(scope, zone(7), 1) == Ok(Nil)
  assert registry.deliver_group(scope, zone(7), last) == Ok(Nil)
  assert got_before_last(one) == [1]
    as "a group holds a process once, so the line arrives once: enter, change zone, camp and enter again leave one membership per group"
  told(one, Leave(zone(7)))
  assert registry.deliver_group(scope, zone(7), 3) == Error(Nil)
    as "one leave empties the group"
}

pub fn a_message_to_a_zone_channel_reaches_each_member_once_and_an_empty_group_gets_none_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = started()
  let first = member(scope:)
  let second = member(scope:)
  let other = member(scope:)
  assert registry.deliver_group(scope, zone(7), 1) == Error(Nil)
    as "nothing is sent to a group with no member"
  told(first, Join(zone(7)))
  told(second, Join(zone(7)))
  told(other, Join(zone(8)))
  assert registry.deliver_group(scope, zone(7), 42) == Ok(Nil)
  assert registry.deliver_group(scope, zone(7), last) == Ok(Nil)
  assert registry.deliver_group(scope, zone(8), last) == Ok(Nil)
  assert got_before_last(first) == [42] as "each member got it once"
  assert got_before_last(second) == [42] as "each member got it once"
  assert got_before_last(other) == []
    as "a member of another top zone's group got nothing"
}

pub fn a_member_that_ends_is_no_longer_in_its_groups_and_later_messages_go_to_the_others_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = started()
  let first = member(scope:)
  let second = member(scope:)
  told(first, Join(zone(7)))
  told(second, Join(zone(7)))
  told(first, Join(step.CharacterNamed("ab cd")))
  process.send(first.commands, Stop)
  event_wait.until("the scope noticed the end by itself", fn() {
    registry.find_named(scope, "ab cd") == Error(Nil)
  })
  assert registry.deliver_group(scope, zone(7), 5) == Ok(Nil)
  assert registry.deliver_group(scope, zone(7), last) == Ok(Nil)
  assert got_before_last(second) == [5]
    as "the member that is left got the line"
}

pub fn a_leave_of_a_group_the_process_is_not_in_does_nothing_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = started()
  let one = member(scope:)
  told(one, Leave(zone(3)))
  assert registry.deliver_group(scope, zone(3), 1) == Error(Nil)
    as "the group is still empty"
}
