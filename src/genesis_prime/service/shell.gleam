//// The shell of a service: a gleam_otp actor under a supervisor, running one
//// rule with no socket: it turns everything that reaches the process into the
//// rule's inputs, carries out the rule's effects in order and decides nothing.
//// A named service registers its name; an unnamed one's subject is held by its
//// starter (maps: genesis_prime/world_map/registry). Its `Call` and the ask path
//// are in genesis_prime/service; the connection's shell: genesis_prime/connection/shell.
////
//// One service, from start to end:
////
//// ```
//// supervisor starts it ─▶ the actor registers its name (a named one), joins
////                          its address (one found at an address), traps exits
////   OwnEvent(Started)                               ─▶ step ─▶ effects
////   after each step's effects, before the mailbox is read:
////     a creature not started ─▶ OwnEvent(CreatureNotStarted(id, reason)) ─▶ step ─▶ effects
////     a watch of a target no process holds ─▶ WatchEnded(id) ─▶ step ─▶ effects
////   loop:
////     Call(message, reply)  ─▶ OwnEvent(Asked(CallerId(n), message)) ─▶ step ─▶ effects
////     TellCall(message)     ─▶ OwnEvent(Told(message))                 ─▶ step ─▶ effects
////     a timer's firing      ─▶ OwnEvent(ServiceTimerFired(id))        ─▶ step ─▶ effects
////     a watched process's DOWN ─▶ WatchEnded(id)           ─▶ step ─▶ effects
////     the parent's exit     ─▶ Stopping(now + shutdown_ms) ─▶ step ─▶ effects
////   Reply(CallerId(n), answer) ─▶ that call's reply(answer); the caller is forgotten
//// ```
////
//// - **CallerId.** Calls are numbered from 1 as they arrive, so a recording names each caller.
//// - **A tell** has no caller and no reply: a connection's `Tell` effect sent as `TellCall`.
//// - **A late reply** the asker's shell drops with no rule input; the service never knows.
//// - **A crash** restarts the service from `new`: askers get `EndedBeforeAnswer` or `NotRunning`.
//// - **Stopping** gives the rule now + `shutdown_ms` to stop; past the deadline it is killed.
//// - **A stray message** is dropped and logged by its kind, never contents (a possible secret).
//// - **Stop** runs the other effects, then exits `shutdown`; `normal` is a supervisor failure.
//// - **Send** finds `to` through the settings' `reach`; no process there drops it silently.
//// - **Watch** monitors what `locate` finds, ending once as `WatchEnded(id)`; repeated ids crash.
//// - **Unwatch** drops the monitor and flushes its DOWN; an id with no open watch does nothing.
//// - **A restart** drops the process's watches and timers; a rule opens what it needs again.
//// - **StartCreature** has `reach` start it and watches it; failure is `CreatureNotStarted`.
//// - **A timer** fires once as `ServiceTimerFired(id)` on `Settings.time`; repeated ids crash.
//// - **`CancelServiceTimer`** cancels it: no firing follows, and a stale firing is dropped.
//// - **Kinds.** Effects `ServiceEffect`, inputs `ServiceEvent`; no ask: `NoAsk` has no values.

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
    /// The scope it is told through, with the address it is found at when it joins
    /// one, or `None` for a service told only by its subject.
    found_at: Option(Reached(message, outgoing)),
    /// Where it reads the time of each input and starts its timers.
    time: ServiceTime,
  )
}

/// How a service is told through a scope of genesis_prime/group_registry. Either way
/// its selector takes what `deliver_*` and `deliver_to` send it.
pub type Reached(message, outgoing) {
  /// Found by an address: the shell joins the address before its rule's first
  /// step, so any process that has what the service sends can find it.
  FoundAt(scope: Scope(Call(message, outgoing)), address: Address)
  /// Joins no address: a process that holds the service's pid (a creature holds its
  /// map's run) tells it with `group_registry.deliver_to`, and the scope fixes the
  /// type of what it is told.
  ToldThrough(scope: Scope(Call(message, outgoing)))
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
    Some(ToldThrough(..)) | None -> Nil
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
