//// What the tests of the connection rules (STS, auth and game) share: the
//// account of the library's vector, the inputs a shell gives, the client's
//// bare ping, the effects of a step found by a helper, and the random bytes a
//// seed gives, computed from their definition
//// (block n = HMAC-SHA256(key: seed, data: n as 64 bits big-endian)) and not
//// by `genesis_prime/random`.

import frame_reader
import genesis_prime/client_connection.{type Bucket}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/login/guid.{type Guid}
import genesis_prime/step.{
  type Address, type Ask, type CallerId, type ConnectionStep, type Effect,
  type Event, type Input, type LogLevel, type LogLine, type ServiceStep,
  type Step, type WatchId, CancelTimer, Connection, ConnectionId, Effects,
  EffectsThenAsk, Input, Log, Now, OwnEffect, Peer, Reply, Send, StartTimer,
  Stop, Unwatch, Watch, Write,
}
import genesis_prime/store.{type Account, Account, AccountId}
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import login_vectors as vector

/// The peer every rule test's connection comes from.
pub const peer = Peer(address: "192.168.1.5", port: 50_000)

/// The monotonic time every input of a rule test carries, in milliseconds.
pub const now_ms = 1000

/// The most bytes a connection holds that it has not taken as frames: the
/// client's frame limit, 131,070 (MessageSizeLimit 0x140335ec0), which one
/// whole frame may fill, and one read of 16,384, the server's choice for the
/// socket's buffer.
pub const held_limit = 147_454

/// A bucket for a test of the rate, which no ask waits on.
pub fn bucket(burst burst: Int, per_second per_second: Int) -> Bucket {
  let assert Ok(bucket) =
    client_connection.bucket(burst:, per_second:, longest_wait_ms: 0)
    as "a test's bucket holds one and fills by one a second at least"
  bucket
}

/// The rate of a rule test that is not about the rate: every input carries the
/// same time, so the bucket never refills, and it holds more than any test
/// sends.
pub fn roomy() -> Bucket {
  bucket(burst: 100_000, per_second: 100_000)
}

/// The account of the library's vector: `jim`, password `secret`, salt 01 .. 10
/// and the vector's verifier.
pub fn jim() -> Account {
  Account(
    account_id: AccountId(7),
    login_name: vector.name,
    srp_salt: vector.salt(),
    srp_verifier: vector.verifier(),
    game_account_id: guid_of(0x11),
  )
}

/// A GUID whose 16 wire bytes count up from `first`, so a GUID read in the
/// wrong byte order is another GUID.
pub fn guid_of(first: Int) -> Guid {
  let assert Ok(guid) =
    guid.from_wire(counting(next: first, remaining: 16, built: <<>>))
    as "sixteen bytes are a GUID"
  guid
}

/// A 32-byte seed whose bytes count up from `first`.
pub fn seed(first first: Int) -> BitArray {
  counting(next: first, remaining: 32, built: <<>>)
}

fn counting(
  next next: Int,
  remaining remaining: Int,
  built built: BitArray,
) -> BitArray {
  case remaining {
    0 -> built
    _ ->
      counting(next: next + 1, remaining: remaining - 1, built: <<
        built:bits,
        { next % 256 },
      >>)
  }
}

/// An input at `now_ms` with the system time 0.
pub fn input(event: Event(own)) -> Input(own) {
  input_at(filetime: 0, event:)
}

/// An input at this monotonic time, in milliseconds, with the system time 0.
pub fn input_at_ms(ms ms: Int, event event: Event(own)) -> Input(own) {
  Input(now: Now(monotonic_ms: ms, filetime: 0), event:)
}

/// An input at `now_ms` with this system time, as a Windows FILETIME.
pub fn input_at(filetime filetime: Int, event event: Event(own)) -> Input(own) {
  Input(now: Now(monotonic_ms: now_ms, filetime:), event:)
}

/// The bytes of the client's bare ping with this number (opcode.0x0: 0 to 19).
pub fn ping(number: Int) -> BitArray {
  let assert Ok(bytes) = frame.encode(0x0000, <<number>>)
    as "a ping number is one byte"
  bytes
}

/// The bytes of `count` of the client's bare pings, numbered from 0 and back to
/// 0 after 19 (opcode.0x0: 0 to 19), and each ping's pong (opcode.0x1).
pub fn pings(count count: Int) -> BitArray {
  int.range(from: 0, to: count, with: <<>>, run: fn(bytes, number) {
    <<bytes:bits, ping(number % 20):bits>>
  })
}

/// The pong a ping with this number is answered with, bare (opcode.0x1: 07 00
/// 00 00 01 00 and the number).
pub fn pong(number: Int) -> BitArray {
  <<7, 0, 0, 0, 1, 0, { number % 20 }>>
}

/// Block `counter` of the seed's random stream: HMAC-SHA256 with the seed as
/// the key over the counter as 64 bits big-endian.
pub fn block(seed seed: BitArray, counter counter: Int) -> BitArray {
  crypto.hmac(<<counter:size(64)-big>>, crypto.Sha256, seed)
}

/// The first 16 bytes of a block: what a draw of 16 bytes gives.
pub fn sixteen(seed seed: BitArray, counter counter: Int) -> BitArray {
  let assert Ok(first) = bit_array.slice(block(seed:, counter:), 0, 16)
    as "a block is 32 bytes"
  first
}

/// The effects of a step.
pub fn effects_of(step: Step(request, own)) -> List(Effect(own)) {
  case step {
    Effects(effects:) -> effects
    EffectsThenAsk(effects:, ..) -> effects
  }
}

/// The bytes the step writes, in order.
pub fn writes(step: ConnectionStep(request)) -> List(BitArray) {
  list.filter_map(effects_of(step), fn(effect) {
    case effect {
      OwnEffect(Write(bytes:)) -> Ok(bytes)
      OwnEffect(StartTimer(..))
      | OwnEffect(CancelTimer(..))
      | OwnEffect(step.Tell(..))
      | Watch(..)
      | Unwatch(..)
      | Log(..)
      | Stop -> Error(Nil)
    }
  })
}

/// Every frame the step writes, as the server wrote it.
pub fn written_frames(step: ConnectionStep(request)) -> List(Frame) {
  list.flat_map(writes(step), fn(bytes) {
    let assert Ok(#(frames, <<>>)) = frame_reader.decode(bytes)
      as "the server writes whole frames"
    frames
  })
}

/// The answers the step gives its callers, each with the caller it is for, in
/// order.
pub fn replies(step: ServiceStep(outgoing)) -> List(#(CallerId, outgoing)) {
  list.filter_map(effects_of(step), fn(effect) {
    case effect {
      OwnEffect(Reply(caller:, answer:)) -> Ok(#(caller, answer))
      OwnEffect(Send(..)) | Watch(..) | Unwatch(..) | Log(..) | Stop ->
        Error(Nil)
    }
  })
}

/// What the step sends to connections without waiting: the connection's number
/// and the message, in order.
pub fn sends(step: ServiceStep(outgoing)) -> List(#(Int, outgoing)) {
  list.filter_map(effects_of(step), fn(effect) {
    case effect {
      OwnEffect(Send(to: Connection(ConnectionId(number)), message:)) ->
        Ok(#(number, message))
      OwnEffect(Send(..))
      | OwnEffect(Reply(..))
      | Watch(..)
      | Unwatch(..)
      | Log(..)
      | Stop -> Error(Nil)
    }
  })
}

/// The watches the step opens, each with the process it is on, in order.
pub fn watches(step: Step(request, own)) -> List(#(WatchId, Address)) {
  list.filter_map(effects_of(step), fn(effect) {
    case effect {
      Watch(watch:, target:) -> Ok(#(watch, target))
      OwnEffect(..) | Unwatch(..) | Log(..) | Stop -> Error(Nil)
    }
  })
}

/// The log lines the step writes, in order.
pub fn logs(step: Step(request, own)) -> List(LogLine) {
  list.filter_map(effects_of(step), fn(effect) {
    case effect {
      Log(line:) -> Ok(line)
      OwnEffect(..) | Watch(..) | Unwatch(..) | Stop -> Error(Nil)
    }
  })
}

/// The log lines of one level.
pub fn logs_of(
  step step: Step(request, own),
  level level: LogLevel,
) -> List(LogLine) {
  list.filter(logs(step), fn(line) { line.level == level })
}

/// The message each warning of the step is about, in order: what a rule's
/// unhandled-message lines name.
pub fn unhandled_ids(step: Step(request, own)) -> List(Option(#(String, Int))) {
  list.map(logs_of(step:, level: step.LogWarning), fn(line) {
    line.about.message
  })
}

/// Whether the step ends the connection.
pub fn stops(step: Step(request, own)) -> Bool {
  list.contains(effects_of(step), Stop)
}

/// The ask the step ends with, when it ends with one.
pub fn asked(step: Step(request, own)) -> Option(Ask(request)) {
  case step {
    Effects(..) -> None
    EffectsThenAsk(ask:, ..) -> Some(ask)
  }
}

/// Whether a log line's text holds the words, in any case.
pub fn says(line line: LogLine, words words: String) -> Bool {
  string.contains(string.lowercase(line.text), string.lowercase(words))
}

/// A step's effect that logs `text` as a warning, as every test rule does when
/// it refuses an input.
pub fn warn(text: String) -> Effect(step.ConnectionEffect(request)) {
  Log(step.LogLine(level: step.LogWarning, text:, about: step.no_one))
}
