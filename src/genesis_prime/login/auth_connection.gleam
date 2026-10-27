//// The rule of one auth connection: the login the client makes with the game
//// token from the STS login, to the hand-off to a game server. It decides
//// everything; its connection shell carries it out
//// (genesis_prime/connection/shell).
////
//// ```
//// client                          rule                              asks
//// connects                     ◀─ hello 0x3, bare
////                              ◀─ the planted frame, when the dev start sets one
//// 0x592 in 0x244               ─▶ build 16042? else 0x63d 19
////                                                                ─▶ hand-off: Take(GameToken)
////   Taken(holder), UserId is the holder's   ─▶ session key from the seed
////                                                                ─▶ hand-off: Put(SessionKey)
////     Kept                     ◀─ 0x591, then 0x3db, each in 0x76
////   NoHolder, or another UserId ◀─ 0x63d 16, then the connection ends
//// ping 0x0                     ◀─ pong 0x1, bare
//// ```
////
//// - **The hello** carries build 16042 and checksum 0x097998A0, which the
////   client checks (0x140037b70), the realm's id, and 0 in every field the
////   client never reads (opcode.0x3).
//// - **0x591** is not disconnected for lag (opcode.0x591). **0x3db** names the
////   game server, the session key, the account's id (stable per account: the
////   client names the addon save folder after it), the realm's name, flags 0,
////   PvE and no realm note (opcode.0x3db).
//// - **Refusals** are 0x63d, then the connection ends: reason 16, "Invalid
////   Login Token", for a token never kept, already taken or expired, or a
////   UserId other than the token's account; 19 for a build other than 16042;
////   12, "NCSoft login service finish timeout", with a warning, when the
////   hand-off gives no answer, since the failure is the server's
////   (opcode.0x63d).
//// - **Ciphers.** The hello and the ping's pong travel bare; every other
////   frame each way travels in the wrapper (0x244 from the client, 0x76 to it)
////   under the client's base key (genesis_prime/connection/encrypted_frame).
//// - **Out of order.** A frame the client's reader would refuse ends the
////   connection; a whole frame of a message the rule does not take is logged
////   as unhandled and the connection goes on.

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/hand_off.{type Holder}
import genesis_prime/login.{type Answer, type Request}
import genesis_prime/message/bit_stream.{type Endpoint}
import genesis_prime/random.{type Random}
import genesis_prime/step.{type Input, type Step}
import gleam/option.{type Option}

/// The realm the client is handed to.
pub type Realm {
  Realm(
    /// The realm's id, the same the game server's realm messages carry.
    id: Int,
    /// Its name, which also names the client's realm settings file.
    name: String,
    /// The game server the client connects to next.
    game_server: Endpoint,
  )
}

/// What every auth connection is made with, at start.
pub type Settings {
  Settings(
    realm: Realm,
    /// How long an ask to the hand-off may take.
    ask_deadline_ms: Int,
    /// How long a session key stays good in the hand-off: the client shows
    /// it to the game server right after it gets it.
    session_key_lifetime_ms: Int,
    /// A frame sent right after the hello, in the auth wrapper, that the
    /// client does not handle; only the dev start sets it, to prove the
    /// client's failure log brings back its id.
    planted: Option(Frame),
  )
}

/// Where the login is.
pub opaque type State {
  State(
    settings: Settings,
    /// `None` until the connection is accepted.
    random: Option(Random),
    /// Bytes of a frame not yet whole, and whole frames not yet taken while
    /// an ask is out.
    pending: BitArray,
    status: Status,
  )
}

/// The login's one status.
type Status {
  /// No socket yet.
  NotAccepted
  /// The hello is sent; waiting for 0x592.
  AwaitingLoginRequest
  /// The hand-off is asked to take the game token of this UserId.
  TakingToken(user_id: BitArray)
  /// The hand-off is asked to keep the session key for the holder.
  KeepingSessionKey(holder: Holder, session_key: BitArray)
  /// 0x591 and 0x3db are sent; the client goes on to the game server.
  HandedOff
}

/// The rule's first state.
pub fn new(settings: Settings) -> State {
  todo as "the build follows the shape commit"
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: Input(Nil, Answer),
) -> #(State, Step(Nil, Request)) {
  todo as "the build follows the shape commit"
}
