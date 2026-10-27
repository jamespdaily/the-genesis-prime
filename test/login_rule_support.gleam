//// What the tests of the two login rules share: the account of the library's
//// vector, the inputs a shell gives, the effects of a step found by a helper,
//// and the random bytes a seed gives, computed from their definition
//// (block n = HMAC-SHA256(key: seed, data: n as 64 bits big-endian)) and not
//// by `genesis_prime/random`.

import genesis_prime/login/guid.{type Guid}
import genesis_prime/step.{
  type Ask, type Effect, type Event, type Input, type LogLevel, type LogLine,
  type Step, CancelTimer, Effects, EffectsThenAsk, Input, Log, Now, Peer, Reply,
  Send, StartTimer, Stop, Unwatch, Watch, Write,
}
import genesis_prime/store.{type Account, Account, AccountId}
import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import login_vectors as vector

/// The peer every rule test's connection comes from.
pub const peer = Peer(address: "192.168.1.5", port: 50_000)

/// The monotonic time every input of a rule test carries, in milliseconds.
pub const now_ms = 1000

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

/// An input at `now_ms`.
pub fn input(event: Event(Nil, answer)) -> Input(Nil, answer) {
  Input(now: Now(monotonic_ms: now_ms, filetime: 0), event:)
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
pub fn effects_of(step: Step(outgoing, request)) -> List(Effect(outgoing)) {
  case step {
    Effects(effects:) -> effects
    EffectsThenAsk(effects:, ..) -> effects
  }
}

/// The bytes the step writes, in order.
pub fn writes(step: Step(outgoing, request)) -> List(BitArray) {
  list.filter_map(effects_of(step), fn(effect) {
    case effect {
      Write(bytes:) -> Ok(bytes)
      Send(..)
      | Reply(..)
      | Watch(..)
      | Unwatch(..)
      | StartTimer(..)
      | CancelTimer(..)
      | Log(..)
      | Stop -> Error(Nil)
    }
  })
}

/// The log lines the step writes, in order.
pub fn logs(step: Step(outgoing, request)) -> List(LogLine) {
  list.filter_map(effects_of(step), fn(effect) {
    case effect {
      Log(line:) -> Ok(line)
      Send(..)
      | Reply(..)
      | Watch(..)
      | Unwatch(..)
      | StartTimer(..)
      | CancelTimer(..)
      | Write(..)
      | Stop -> Error(Nil)
    }
  })
}

/// The log lines of one level.
pub fn logs_of(
  step step: Step(outgoing, request),
  level level: LogLevel,
) -> List(LogLine) {
  list.filter(logs(step), fn(line) { line.level == level })
}

/// Whether the step ends the connection.
pub fn stops(step: Step(outgoing, request)) -> Bool {
  list.contains(effects_of(step), Stop)
}

/// The ask the step ends with, when it ends with one.
pub fn asked(step: Step(outgoing, request)) -> Option(Ask(request)) {
  case step {
    Effects(..) -> None
    EffectsThenAsk(ask:, ..) -> Some(ask)
  }
}

/// Whether a log line's text holds the words, in any case.
pub fn says(line line: LogLine, words words: String) -> Bool {
  string.contains(string.lowercase(line.text), string.lowercase(words))
}
