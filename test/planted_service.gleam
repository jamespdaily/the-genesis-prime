//// Stand-in services for the tests of how the server is split into nodes and
//// supervision subtrees: a login service, a world subtree and a top
//// supervisor holding both, started under the real top supervisor's settings.
//// They exist so a test can break one service the way a real one could break
//// and watch whether another keeps answering.
////
//// Nothing here has a fixed name or a fixed restart setting: the names, the
//// restart settings, the fault, the heap ceiling and the subjects that report
//// each start are all in `Settings`, made again for every test.

import genesis_prime/server
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Builder, type Supervisor}
import gleam/otp/supervision

/// How many restarts a supervisor allows, and in how many seconds, before it
/// gives up and stops with its children.
pub type Restarts {
  Restarts(intensity: Int, period: Int)
}

/// What the planted world worker that crashes on request does when it starts.
/// `Healthy` waits for a request. `CrashesAfterEveryStart` crashes right after
/// it has started, on every start, so the subtree has a fault that a restart
/// cannot clear.
pub type Fault {
  Healthy
  CrashesAfterEveryStart
}

/// The registered names of the planted workers. A name survives a restart, so
/// a test finds the current worker through its name after the supervisor has
/// replaced it.
pub type Names {
  Names(
    login: Name(LoginMessage),
    crasher: Name(CrashMessage),
    grower: Name(GrowMessage),
  )
}

/// Where each planted worker reports its pid when it starts, once for every
/// start, so a test waits for a replacement by receiving instead of sleeping.
/// The subjects belong to the process that made them: the test.
pub type Starts {
  Starts(login: Subject(Pid), crasher: Subject(Pid), grower: Subject(Pid))
}

/// Everything a planted tree is started with.
///
/// - `login_restarts` and `world_restarts` are the restart settings of the
///   login subtree's supervisor and the world subtree's supervisor. The top
///   supervisor's own settings are the real top supervisor's.
/// - `world_fault` is what the crashing world worker does when it starts.
/// - `max_heap_words` is the ceiling, in words, the growing world worker sets
///   on its own heap, with kill on. It is a planted limit, not the server's.
pub type Settings {
  Settings(
    login_restarts: Restarts,
    world_restarts: Restarts,
    world_fault: Fault,
    max_heap_words: Int,
    names: Names,
    starts: Starts,
  )
}

/// The planted login service's messages.
pub type LoginMessage {
  Ping(reply: Subject(Pong))
}

/// The login service's answer to a `Ping`.
pub type Pong {
  Pong
}

/// The planted world worker that crashes on request.
pub type CrashMessage {
  Crash
}

/// The planted world worker whose heap grows without end once asked.
pub type GrowMessage {
  Grow
}

/// New settings for one test: fresh names, fresh start subjects owned by the
/// caller, restarts of 3 in 5 seconds for both subtrees (the same numbers as
/// the real top supervisor, so a subtree is not more patient than the server),
/// a healthy world, and a heap ceiling of 100,000 words. Change a field with a
/// record update.
pub fn settings() -> Settings {
  todo as "body in the build commit"
}

/// Starts the planted top supervisor, built from `server.supervisor()` so it
/// has the real top supervisor's strategy and restart settings, with two
/// children: the login subtree and the world subtree. The caller owns the
/// supervisor through the link, so it stops with the test.
pub fn start_top(
  settings: Settings,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  server.supervisor()
  |> static_supervisor.add(
    static_supervisor.supervised(login_subtree(settings)),
  )
  |> static_supervisor.add(
    static_supervisor.supervised(world_subtree(settings)),
  )
  |> static_supervisor.start
}

/// Sends a `Ping` to the login service and waits for its `Pong`. Error when no
/// answer comes in `within` milliseconds.
pub fn ping(login: Subject(LoginMessage), within: Int) -> Result(Nil, Nil) {
  todo as "body in the build commit"
}

/// Tells the world worker that crashes on request to crash, with an abnormal
/// exit.
pub fn crash(crasher: Subject(CrashMessage)) -> Nil {
  todo as "body in the build commit"
}

/// Tells the world worker that grows to start growing its heap without end. It
/// stops only when the runtime kills it at the ceiling in `max_heap_words`.
pub fn grow(grower: Subject(GrowMessage)) -> Nil {
  todo as "body in the build commit"
}

/// The pid of the next start reported on one of `Starts`, waiting up to
/// `within` milliseconds. Error when none comes.
pub fn next_start(starts: Subject(Pid), within: Int) -> Result(Pid, Nil) {
  todo as "body in the build commit"
}

/// The login subtree: a supervisor of the login service alone, with
/// `login_restarts`.
fn login_subtree(settings: Settings) -> Builder {
  static_supervisor.new(static_supervisor.OneForOne)
  |> restarts(settings.login_restarts)
  |> static_supervisor.add(supervision.worker(fn() { start_login(settings) }))
}

/// The world subtree: a supervisor of the worker that crashes on request and
/// the worker that grows, with `world_restarts`. One for one, so one worker's
/// crash restarts that worker alone.
fn world_subtree(settings: Settings) -> Builder {
  static_supervisor.new(static_supervisor.OneForOne)
  |> restarts(settings.world_restarts)
  |> static_supervisor.add(supervision.worker(fn() { start_crasher(settings) }))
  |> static_supervisor.add(supervision.worker(fn() { start_grower(settings) }))
}

fn restarts(builder: Builder, restarts: Restarts) -> Builder {
  static_supervisor.restart_tolerance(
    builder,
    intensity: restarts.intensity,
    period: restarts.period,
  )
}

/// Starts the login service under `names.login`, answering each `Ping` with a
/// `Pong`, and reports its pid on `starts.login`.
fn start_login(
  settings: Settings,
) -> Result(actor.Started(Subject(LoginMessage)), actor.StartError) {
  todo as "body in the build commit"
}

/// Starts the crashing world worker under `names.crasher` and reports its pid
/// on `starts.crasher`. A `Crash` stops it abnormally; with
/// `CrashesAfterEveryStart` it sends itself one as soon as it has started.
fn start_crasher(
  settings: Settings,
) -> Result(actor.Started(Subject(CrashMessage)), actor.StartError) {
  todo as "body in the build commit"
}

/// Starts the growing world worker under `names.grower`. Before it reports its
/// pid on `starts.grower` it sets its own heap ceiling to `max_heap_words`.
fn start_grower(
  settings: Settings,
) -> Result(actor.Started(Subject(GrowMessage)), actor.StartError) {
  todo as "body in the build commit"
}

/// Sets the calling process's `max_heap_size` to `words` words, with kill on,
/// so the runtime kills the process when its heap would pass that size.
@external(erlang, "planted_service_ffi", "set_max_heap_size")
fn set_max_heap_size(words: Int) -> Nil
