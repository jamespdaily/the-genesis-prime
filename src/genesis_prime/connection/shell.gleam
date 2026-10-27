//// The shell of a connection: the process that owns one client socket and
//// runs one rule over it. It turns everything that reaches the process into
//// the rule's inputs, carries out the rule's effects in order and decides
//// nothing, so a recording of its inputs replays every decision with no socket
//// (genesis_prime/rule_recording).
////
//// One connection, from accept to end:
////
//// ```
//// Ranch accepts ─▶ connection_shell_ffi:start_link ─▶ ranch:handshake ─▶ run
////   the recorder, when on, writes the header
////   Socket(Accepted(connection id, peer))        ─▶ step ─▶ effects
////   loop, the socket active once:
////     {tcp, bytes}        ─▶ Socket(Read(bytes))   ─▶ step ─▶ effects ─▶ active once
////     {tcp_closed}        ─▶ Socket(PeerClosed)    ─▶ step ─▶ effects
////     {tcp_error, reason} ─▶ Socket(ReadFailed(_)) ─▶ step ─▶ effects
////   each step: the recorder writes Taken(input, step) before its effects
//// ```
////
//// - **Time.** Each input carries one `Now`, read as the shell takes the
////   input: the monotonic clock in milliseconds and the system time as a
////   FILETIME.
//// - **A failed write.** The step's later effects are not carried out; the
////   next input is `Socket(WriteFailed(_))`. A write that does not finish
////   within the send deadline fails as `SendTimedOut`.
//// - **Stop.** The shell closes the socket, the recorder writes `End` with
////   the count of inputs, and the process ends normally. A rule must return
////   `Stop` after `PeerClosed`, since nothing else reaches the process then.
//// - **A crash.** When the rule's step crashes, the process ends with that
////   reason; Ranch starts connection processes as temporary children, so
////   nothing restarts it and the listener goes on accepting. The socket closes
////   with the process, and its recording has no `End`, so it never replays.
//// - **Effects built later.** `Send`, `Reply`, `Watch`, `Unwatch`,
////   `StartTimer`, `CancelTimer` and a step that ends in an ask need the
////   processes they name, which the login card builds; until then the shell
////   ends the connection with an error naming the effect.

import genesis_prime/rule_recording/file.{type Recorder}
import genesis_prime/step.{type Rule}
import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}

/// What every connection of one listener is started with.
pub type Settings(settings, state, message, answer, outgoing, request) {
  Settings(
    rule: Rule(settings, state, message, answer, outgoing, request),
    /// How long a write may wait for the socket before it fails as
    /// `SendTimedOut`.
    send_deadline_ms: Int,
    /// Where each connection's inputs are recorded; `None` unless the dev
    /// start turns recording on.
    recorder: Option(Recorder(settings)),
  )
}

/// Runs one connection to its end, in the process Ranch started for it.
/// `ranch_ref` is the listener's reference for `ranch:handshake`. Called only
/// by `connection_shell_ffi:start_link`.
pub fn run(
  ranch_ref ranch_ref: Dynamic,
  settings settings: Settings(
    settings,
    state,
    message,
    answer,
    outgoing,
    request,
  ),
) -> Nil {
  todo as "the build follows the shape commit"
}
