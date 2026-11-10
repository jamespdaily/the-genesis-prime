//// The shell of a service: a process with no socket that other processes
//// ask, running one rule. A singleton (the hand-off, Sessions) registers a
//// name; a map is one of many and registers none: Maps holds the subject
//// its start returns (genesis_prime/world_map/registry), since a name is an atom
//// and maps come and go. Like a connection's shell
//// (genesis_prime/connection/shell), it turns everything that reaches the
//// process into the rule's inputs, carries out the rule's effects in order
//// and decides nothing. It is a gleam_otp actor under a supervisor. How an
//// asker reaches a service, the `Call` a service takes, is in
//// genesis_prime/service.
////
//// One service, from start to end:
////
//// ```
//// supervisor starts it ─▶ the actor registers its name (a named one), joins
////                          its address (one found at an address), traps exits
////   OwnEvent(Started)                               ─▶ step ─▶ effects
////   after each step's effects, before the mailbox is read:
////     a creature that did not start ─▶ OwnEvent(CreatureNotStarted(id, reason)) ─▶ step ─▶ effects
////     a watch of a target no process holds ─▶ WatchEnded(id) ─▶ step ─▶ effects
////   loop:
////     Call(message, reply)  ─▶ OwnEvent(Asked(CallerId(n), message)) ─▶ step ─▶ effects
////     TellCall(message)     ─▶ OwnEvent(Told(message))                 ─▶ step ─▶ effects
////       (sent to the subject, or through the settings' scope: `group_registry`)
////     a timer's firing      ─▶ OwnEvent(ServiceTimerFired(id))        ─▶ step ─▶ effects
////     a watched process's DOWN ─▶ WatchEnded(id)           ─▶ step ─▶ effects
////     the parent's exit     ─▶ Stopping(now + shutdown_ms) ─▶ step ─▶ effects
////   Reply(CallerId(n), answer): the shell calls that call's reply with the
////     answer and forgets the caller
//// ```
////
//// An ask, from the asker's side (the connection shell carries it out):
////
//// ```
//// asker                         directory                 service
////   EffectsThenAsk(.., ask) ─▶ service.call(name, message, reply)
////                                 name not registered ─▶ Error(Nil): NotRunning
////                                 else monitor, send ──▶ Call(message, reply)
////   waits until the ask's deadline                          Asked ─▶ step
////   ◀── {ask answer, tag, answer} ◀─────────────────────────── Reply
////   Answered(ask, Answer(answer))
//// ```
////
//// - **CallerId.** The shell numbers the calls it takes from 1, in the order
////   they arrive, so a recording names each caller with no process id.
//// - **A tell** has no caller and no reply: the shell numbers none for it. It
////   comes from a connection's `Tell` effect (genesis_prime/step), which the
////   connection's shell sends as a `TellCall`.
//// - **A reply nobody waits for.** An answer after the asker's deadline
////   reaches the asker's shell, which drops it with no input to the asker's
////   rule (genesis_prime/connection/shell); one to an asker that has ended is
////   lost. The service never knows either way.
//// - **A crash.** The rule's crash ends the process; the supervisor restarts
////   it from the rule's `new`, so the service's state is lost. An asker
////   waiting on it gets `EndedBeforeAnswer`; one asking while it restarts gets
////   `NotRunning`.
//// - **The server stopping.** The shell traps exits, so the supervisor's stop
////   arrives as `Stopping`, with a deadline of the child's shutdown time from
////   when the shell takes the exit, which is after it arrived when a step is
////   running. A rule that has not stopped by whichever deadline comes first,
////   this or the supervisor's own, is killed.
//// - **A message no selector takes.** The shell drops it and logs a warning
////   that names the message's kind (its tag or its shape) and never its
////   contents, which could hold a secret.
//// - **Stop.** The shell carries out the step's other effects, then the
////   process exits with the reason `shutdown`, never `normal`:
////   a supervisor reports a permanent child that exits `normal` while it
////   shuts down as a failure, and restarts one that exits `shutdown` at any
////   other time. A watch's end held by a step that stops the process is
////   not taken, since the process has ended.
//// - **Send.** `Send(to, message)` looks `to` up with the settings' `reach` and
////   hands the message to the process found, in the form its shell takes (a
////   connection takes it as `Woken`). An address with no process running
////   drops the message, with no input and no log line: a rule that must know
////   watches the receiver.
//// - **Watch.** `Watch(id, target)` finds `target` with the settings' `locate`
////   and monitors it, keeping the monitor under `id` in the shell. The target's
////   end comes back once as `WatchEnded(id)` and the shell forgets the watch. A
////   target no process holds when the watch begins is monitored by nothing:
////   the shell holds the id, and takes `WatchEnded(id)` as its next input
////   once the step's effects are carried out, before it reads its mailbox,
////   with the ends of the step's other such watches in the order opened (a
////   rule's step that those inputs start takes its own the same way); one
////   that ends between the lookup and the monitor fires the monitor at once. A
////   rule's id that is already open, monitored or held, ends the process with
////   an error log: an id is unique among the open watches (genesis_prime/step/watch).
//// - **Unwatch.** `Unwatch(id)` drops the monitor of `id` and flushes its DOWN
////   from the mailbox, or drops an id held for a target no process holds, so
////   no `WatchEnded` follows; an id with no open watch does nothing.
//// - **A watch's end and a restart.** A watch lives in the process: a restarted
////   service has no watches, and a rule that needs one opens it again from
////   what it learns of its processes (Sessions has none to open: the
////   connections claim again).
//// - **StartCreature.** `StartCreature(watch, creature)` has the settings'
////   `reach` start the creature, which returns once the creature runs and is found
////   at its address (genesis_prime/world_map/creature_supervisor); the shell then
////   opens the watch on that address as `Watch` does. A creature that did not
////   start opens no watch: the shell keeps its watch and the supervisor's reason,
////   and takes `CreatureNotStarted(watch, reason)` as the next input once the
////   step's effects are carried out, in the order named, before any
////   `WatchEnded` the step's watches held to end give.
//// - **Timers.** `StartServiceTimer(id, ms)` starts a timer on the service's
////   scheduler (`Settings.time`; the operating system's timer, `script.operating_system_timer`,
////   for a server), kept under `id` with the reference its
////   firing carries (genesis_prime/step/timer); the firing comes back once as
////   `ServiceTimerFired(id)`, and the shell forgets the timer. `CancelServiceTimer(id)`
////   cancels it, so no firing follows: a firing whose reference is not the
////   current timer's of that id, such as a cancelled timer's, is dropped. An id
////   already running ends the process with an error log. A timer lives in the
////   process: a restarted service has none, and a rule that needs one starts it
////   again.
//// - **Effects and inputs of the other kind.** A service's own effects are
////   `Reply`, `Send`, `StartCreature` and the timers, and its own inputs are
////   `Started`, `Asked`, `Told`, `ServiceTimerFired` and `CreatureNotStarted`
////   (`ServiceEffect` and `ServiceEvent`). It has no `Write`, `StartTimer` or
////   `CancelTimer`, and takes no `Woken`, `TimerFired` or `Answered`, which are a
////   connection's, so a rule that writes to a socket or takes those inputs does
////   not compile against this shell. It makes no ask: its request type, `NoAsk`,
////   has no values, so no rule can build a step that ends in one; the shell's
////   case for such a step is unreachable.

import genesis_prime/connection/script.{type Elapsed, type Scheduler}
import genesis_prime/group_registry.{type Scope}
import genesis_prime/service.{type Call, type Reach, Call, TellCall}
import genesis_prime/step.{
  type Address, type CreatureStart, type Effect, type Event, type Now,
  type ServiceEffect, type ServiceEvent, type ServiceRule, type TimerId,
  type WatchId, Asked, CallerId, CancelServiceTimer, CreatureNotStarted, Effects,
  EffectsThenAsk, Input, LogError, OwnEffect, OwnEvent, Reply, Send,
  ServiceTimerFired, StartCreature, StartServiceTimer, Started, Stopping, Told,
  WatchEnded,
}
import genesis_prime/step/runtime.{Shutdown}
import genesis_prime/step/timer as timer_book
import genesis_prime/step/watch.{type Watches}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// The clock a service's inputs take their `Now` from and the scheduler its
/// timers start on. A server's is `real_time()`; a whole-server test gives the
/// service the driven clock's (`driven_time.service_time`), so a timer fires
/// only when the test advances the clock.
pub type ServiceTime {
  ServiceTime(clock: fn() -> Now, schedule: Scheduler)
}

/// The node's own clock and the operating system's timer.
pub fn real_time() -> ServiceTime {
  ServiceTime(clock: runtime.now, schedule: script.operating_system_timer)
}

/// What a service is started with.
pub type Settings(settings, state, message, outgoing) {
  Settings(
    /// The rule. A service makes no ask, so its request type is `NoAsk`, and
    /// it takes no answers; `outgoing` is what it answers and sends with.
    rule: ServiceRule(settings, state, message, outgoing),
    /// How it finds the processes its rule watches and sends to.
    reach: Reach(outgoing),
    /// How long it has to stop once the supervisor stops it; the child's
    /// shutdown timeout.
    shutdown_ms: Int,
    /// The address it is found at and the scope it is told through there, or
    /// `None` for a service told only by its subject.
    found_at: Option(FoundAt(message, outgoing)),
    /// Where it reads the time of each input and starts its timers.
    time: ServiceTime,
  )
}

/// Where a service is found by an address (genesis_prime/group_registry). The
/// shell joins the address before its rule's first step, so any process that
/// has what the service sends can find it.
pub type FoundAt(message, outgoing) {
  FoundAt(scope: Scope(Call(message, outgoing)), address: Address)
}

/// What reaches the actor: a call, an exit signal it traps, a timer's firing,
/// the end of a process it watches, or a message it does not take.
type Mail(message, outgoing) {
  /// A call sent through the service's subject, or a tell sent through its
  /// scope (`group_registry.deliver_one`).
  Called(call: Call(message, outgoing))
  /// A timer fired: its id and the reference of the start it came from
  /// (`script.Elapsed`).
  TimerElapsed(timer: TimerId, reference: Reference)
  Exited(exit: process.ExitMessage)
  /// The end of a process the rule watches, by its monitor.
  Ended(down: process.Down)
  /// A message no other selector takes.
  Stray(message: Dynamic)
}

/// A running service: its settings, its parent, the rule's state, the calls
/// not yet answered by the number the shell gave each, the monitor of each
/// watch the rule has open, the timers it has running with the subject their
/// firings arrive on, and the creatures that did not start in the step being
/// carried out, each with the watch it was to be under, in the order named.
type Running(settings, state, message, outgoing) {
  Running(
    settings: Settings(settings, state, message, outgoing),
    parent: Pid,
    state: state,
    callers: Dict(Int, fn(outgoing) -> Nil),
    next_caller: Int,
    watches: Watches(Nil),
    timers: timer_book.Timers,
    elapsed: Subject(Elapsed),
    unstarted: List(#(WatchId, String)),
  )
}

/// Why a service could not start.
type StartFailure {
  NameTaken
}

/// The service as a permanent child of a supervisor, registered under `name`,
/// with `shutdown_ms` as its shutdown timeout. Askers find it by the name.
pub fn supervised(
  name name: Name(Call(message, outgoing)),
  settings settings: Settings(settings, state, message, outgoing),
) -> ChildSpecification(Nil) {
  // The supervisor runs the start function, so its own pid is the parent.
  supervision.worker(fn() {
    start(settings:, parent: process.self(), name: Some(name))
    |> result.map(fn(started) { actor.Started(pid: started.pid, data: Nil) })
  })
  |> supervision.restart(supervision.Permanent)
  |> supervision.timeout(ms: settings.shutdown_ms)
}

/// Starts a service with no name as a child of the supervisor that runs this
/// function, such as the map supervisor, giving the subject askers send their
/// calls to.
pub fn start_unnamed(
  settings: Settings(settings, state, message, outgoing),
) -> actor.StartResult(Subject(Call(message, outgoing))) {
  start(settings:, parent: process.self(), name: None)
}

fn start(
  settings settings: Settings(settings, state, message, outgoing),
  parent parent: Pid,
  name name: Option(Name(Call(message, outgoing))),
) -> actor.StartResult(Subject(Call(message, outgoing))) {
  actor.new_with_initialiser(5000, fn(_subject) {
    initialise(settings:, parent:, name:) |> result.map_error(explain)
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// The selector with what is told through the scope added, when the service has
/// one.
fn select_told(
  selector selector: process.Selector(Mail(message, outgoing)),
  scope scope: Option(Scope(Call(message, outgoing))),
) -> process.Selector(Mail(message, outgoing)) {
  case scope {
    Some(scope) -> group_registry.select_delivered(scope, selector, Called)
    None -> selector
  }
}

/// Registers the name (a named service) or makes the subject its callers send
/// to (an unnamed one), joins its address when it is found at one, traps exits
/// and takes `Started`.
fn initialise(
  settings settings: Settings(settings, state, message, outgoing),
  parent parent: Pid,
  name name: Option(Name(Call(message, outgoing))),
) -> Result(
  actor.Initialised(
    Running(settings, state, message, outgoing),
    Mail(message, outgoing),
    Subject(Call(message, outgoing)),
  ),
  StartFailure,
) {
  use calls <- result.try(case name {
    Some(name) ->
      process.register(process.self(), name)
      |> result.replace(process.named_subject(name))
      |> result.replace_error(NameTaken)
    None -> Ok(process.new_subject())
  })
  case settings.found_at {
    Some(FoundAt(scope:, address:)) ->
      group_registry.join(scope:, group: address, pid: process.self())
    None -> Nil
  }
  process.trap_exits(True)
  let elapsed = process.new_subject()
  let rule = settings.rule
  let running =
    take(
      running: Running(
        settings:,
        parent:,
        state: rule.new(rule.settings),
        callers: dict.new(),
        next_caller: 1,
        watches: watch.new(),
        timers: timer_book.new(),
        elapsed:,
        unstarted: [],
      ),
      now: settings.time.clock(),
      event: OwnEvent(Started),
    )
  let selector =
    process.new_selector()
    |> process.select_other(Stray)
    |> process.select_map(calls, Called)
    |> select_told(
      scope: option.map(settings.found_at, fn(found_at) { found_at.scope }),
    )
    |> process.select_map(elapsed, fn(fired) {
      TimerElapsed(timer: fired.timer, reference: fired.reference)
    })
    |> process.select_trapped_exits(Exited)
    |> process.select_monitors(Ended)
  Ok(
    actor.initialised(running)
    |> actor.selecting(selector)
    |> actor.returning(calls),
  )
}

fn handle(
  running: Running(settings, state, message, outgoing),
  mail: Mail(message, outgoing),
) -> actor.Next(
  Running(settings, state, message, outgoing),
  Mail(message, outgoing),
) {
  case mail {
    Called(Call(message:, reply:)) -> {
      let number = running.next_caller
      let running =
        Running(
          ..running,
          callers: dict.insert(running.callers, number, reply),
          next_caller: number + 1,
        )
      actor.continue(take(
        running:,
        now: running.settings.time.clock(),
        event: OwnEvent(Asked(caller: CallerId(number), message:)),
      ))
    }
    Called(TellCall(message:)) ->
      actor.continue(take(
        running:,
        now: running.settings.time.clock(),
        event: OwnEvent(Told(message:)),
      ))
    TimerElapsed(timer:, reference:) ->
      case timer_book.fired(timers: running.timers, timer:, reference:) {
        Ok(timers) ->
          actor.continue(take(
            running: Running(..running, timers:),
            now: running.settings.time.clock(),
            event: OwnEvent(ServiceTimerFired(timer:)),
          ))
        Error(Nil) -> actor.continue(running)
      }
    Ended(down:) -> actor.continue(watch_ended(running:, down:))
    Stray(message:) -> {
      runtime.log_stray(message:, shell: "service shell")
      actor.continue(running)
    }
    Exited(exit:) ->
      case exit.pid == running.parent {
        True -> {
          let now = running.settings.time.clock()
          actor.continue(take(
            running:,
            now:,
            event: Stopping(
              deadline_ms: now.monotonic_ms + running.settings.shutdown_ms,
            ),
          ))
        }
        False -> actor.continue(running)
      }
  }
}

/// Folds one input through the rule, then carries out the step.
/// Each creature the step named that did not start is then taken as
/// `CreatureNotStarted`, in the order named, and the end of each watch of a
/// target no process holds that the step opened as `WatchEnded`, in the order
/// opened, each as the next input before the mailbox is read.
fn take(
  running running: Running(settings, state, message, outgoing),
  now now: step.Now,
  event event: Event(ServiceEvent(message)),
) -> Running(settings, state, message, outgoing) {
  let rule = running.settings.rule
  let #(state, step) = rule.step(running.state, Input(now:, event:))
  let running = Running(..running, state:)
  let running = case step {
    Effects(effects:) -> carry(running:, effects:, ending: False)
    EffectsThenAsk(..) ->
      panic as "a service step ended in an ask, which its request type has no value for"
  }
  case running.unstarted {
    [#(watch, reason), ..later] ->
      take(
        running: Running(..running, unstarted: later),
        now: running.settings.time.clock(),
        event: OwnEvent(CreatureNotStarted(watch:, reason:)),
      )
    [] ->
      case watch.next_unheld_end(running.watches) {
        Ok(#(watch, watches)) ->
          take(
            running: Running(..running, watches:),
            now: running.settings.time.clock(),
            event: WatchEnded(watch:),
          )
        Error(Nil) -> running
      }
  }
}

/// Carries out the effects in order. A `Stop` among them does not end the
/// step: the effects after it are carried out, then the process ends.
fn carry(
  running running: Running(settings, state, message, outgoing),
  effects effects: List(Effect(ServiceEffect(outgoing))),
  ending ending: Bool,
) -> Running(settings, state, message, outgoing) {
  case effects {
    [] ->
      case ending {
        True -> stop()
        False -> running
      }
    [effect, ..later] ->
      case effect {
        OwnEffect(Reply(caller: CallerId(number), answer:)) ->
          case dict.get(running.callers, number) {
            Ok(reply) -> {
              reply(answer)
              carry(
                running: Running(
                  ..running,
                  callers: dict.delete(running.callers, number),
                ),
                effects: later,
                ending:,
              )
            }
            Error(Nil) ->
              panic as "a rule replied to a caller it was not asked by, or answered one twice"
          }
        step.Log(line:) -> {
          runtime.log(line.level, line.text, line.about)
          carry(running:, effects: later, ending:)
        }
        step.Stop -> carry(running:, effects: later, ending: True)
        OwnEffect(Send(to:, message:)) ->
          carry(
            running: deliver(running:, to:, message:),
            effects: later,
            ending:,
          )
        OwnEffect(StartServiceTimer(timer:, after_ms:)) ->
          carry(
            running: start_timer(running:, timer:, after_ms:),
            effects: later,
            ending:,
          )
        OwnEffect(CancelServiceTimer(timer:)) ->
          carry(
            running: Running(
              ..running,
              timers: timer_book.cancel(timers: running.timers, timer:),
            ),
            effects: later,
            ending:,
          )
        OwnEffect(StartCreature(watch:, creature:)) ->
          carry(
            running: start_creature(running:, watch:, creature:),
            effects: later,
            ending:,
          )
        step.Watch(watch:, target:) ->
          carry(
            running: open_watch(running:, watch:, target:),
            effects: later,
            ending:,
          )
        step.Unwatch(watch:) ->
          carry(running: close_watch(running:, watch:), effects: later, ending:)
      }
  }
}

/// Hands the message to the process at the address, or drops it when no
/// process runs there.
fn deliver(
  running running: Running(settings, state, message, outgoing),
  to to: step.Address,
  message message: outgoing,
) -> Running(settings, state, message, outgoing) {
  let _delivered = running.settings.reach.send(to, message)
  running
}

/// Starts the timer the rule named, whose firing arrives with a reference of its
/// own; an id already running is a bug, and ends the process.
fn start_timer(
  running running: Running(settings, state, message, outgoing),
  timer timer: TimerId,
  after_ms after_ms: Int,
) -> Running(settings, state, message, outgoing) {
  let started =
    timer_book.start(timers: running.timers, timer:, schedule: fn(reference) {
      running.settings.time.schedule(
        running.elapsed,
        timer,
        reference,
        after_ms,
      )
    })
  case started {
    Ok(timers) -> Running(..running, timers:)
    Error(Nil) -> {
      runtime.log(
        LogError,
        "a rule started a timer whose id is already running, which the service shell does not carry out",
        step.no_one,
      )
      panic as "a rule started a timer whose id is already running"
    }
  }
}

/// Starts the creature through the settings' `reach`, and watches it under the
/// rule's watch when it runs; one that did not start is kept to be given to the
/// rule as `CreatureNotStarted` once the step's effects are carried out.
fn start_creature(
  running running: Running(settings, state, message, outgoing),
  watch watch: WatchId,
  creature creature: CreatureStart,
) -> Running(settings, state, message, outgoing) {
  case running.settings.reach.start_creature(creature) {
    Ok(Nil) ->
      open_watch(
        running:,
        watch:,
        target: step.Creature(
          map: creature.map,
          incarnation: creature.incarnation,
          unit_id: creature.unit_id,
          life: creature.life,
        ),
      )
    Error(error) ->
      Running(
        ..running,
        unstarted: list.append(running.unstarted, [
          #(watch, service.describe_start_child_error(error)),
        ]),
      )
  }
}

/// Monitors the process at the address under the watch's id.
fn open_watch(
  running running: Running(settings, state, message, outgoing),
  watch watch: WatchId,
  target target: step.Address,
) -> Running(settings, state, message, outgoing) {
  Running(
    ..running,
    watches: watch.open(
      watches: running.watches,
      watch:,
      address: target,
      target: result.map(running.settings.reach.locate(target), watch.Watched),
      shell: "service shell",
    ),
  )
}

/// Drops the watch's monitor, and the DOWN already waiting for it.
fn close_watch(
  running running: Running(settings, state, message, outgoing),
  watch watch: WatchId,
) -> Running(settings, state, message, outgoing) {
  Running(..running, watches: watch.close(watches: running.watches, watch:))
}

/// Takes the end of a watched process as `WatchEnded` with the id of its
/// watch, and forgets the watch; the DOWN of a monitor the shell does not hold
/// is dropped.
fn watch_ended(
  running running: Running(settings, state, message, outgoing),
  down down: process.Down,
) -> Running(settings, state, message, outgoing) {
  let monitor = runtime.down_monitor(down)
  case watch.ended(watches: running.watches, monitor:) {
    Ok(#(watch, watches)) ->
      take(
        running: Running(..running, watches:),
        now: running.settings.time.clock(),
        event: WatchEnded(watch:),
      )
    Error(Nil) -> running
  }
}

/// Exits with the reason `shutdown`.
fn stop() -> a {
  runtime.exit_now(Shutdown)
}

fn explain(_failure: StartFailure) -> String {
  "the service's name is already registered"
}
