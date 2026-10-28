//// The rule of one game connection: the client's connection to the game
//// server, from the hello to the character list its select screen shows. It
//// decides everything; its connection shell carries it out
//// (genesis_prime/connection/shell). The client reaches it with the session
//// key the auth server's hand-off gave it (genesis_prime/login/auth_connection).
////
//// ```
//// client                          rule                              asks
//// connects                     ◀─ 0x3DC{0x0003 hello, realm id}, base key
//// 0x244{0x058F} (base key)     ─▶ session key from the 16 bytes
////                                 and the base key; the connection is
////                                 re-keyed: every frame after this one,
////                                 each way, is under the session key
////                                                                ─▶ hand-off: Take(SessionKey)
//// 0x244{0x07E0}                   waits in the bytes read until the
////   (same read, session key)      hand-off answers
////   Taken(holder)                 the bytes are taken again       ─▶ store: ListCharacters(account)
////     Characters(rows)         ◀─ 0x3DC{0x0117 character_list}, session key
//// 0x244{0x038C{0x082D}}        ─▶ logged as unhandled
//// 0x244{0x0241}                ─▶ logged as unhandled
//// ping 0x0, bare               ◀─ pong 0x1, bare
//// ```
////
//// - **The hello** is the first thing written: any game server message before
////   it ends the client's login with 0x801B2 (0x1400370d0). It is the
////   connection's first input, `Socket(Accepted)`, that writes it, in the game
////   wrapper under the base key, with the realm's id from the settings
////   (genesis_prime/connection/hello, opcode.0x3).
//// - **The re-key.** The client re-keys at once on sending 0x058F, so the
////   rule does too, before it asks; bytes that arrive after it in the same
////   read are read under the session key
////   (vector.0x14003827c.session_fold). The first client message must be
////   0x058F, and only one is taken: another first message, or a second 0x058F,
////   is logged as an error and ends the connection.
//// - **Reads during an ask.** Frames after the one that asked stay in the
////   bytes read and are taken once the answer comes, so 0x07E0 is taken after
////   the hand-off's answer, and 0x038C and 0x0241 after the store's.
//// - **The character list** is character select's own feature
////   (genesis_prime/game/character_select); the rule turns its effects into
////   writes in the game wrapper and into the store ask.
//// - **Failures** end with 0x036A and the close, since the client waits for
////   the list with no timeout and would stay on its prompt otherwise
////   (lua.Character.OnCharacterList); every reason drops the client to its
////   error screen and only picks the text (0x1400168a0):
////   - reason 19, "This account has been disconnected", when the hand-off
////     does not hold the session key (never put, taken, or expired), with a
////     warning naming the peer;
////   - reason 8, "Lost connection with user server.", for the server's own
////     failure, with a warning: the hand-off or the store is not running, ended
////     before it answered, gave no answer by the settings' ask deadline, or the
////     store answers `Unavailable`. The server stopping while it waits ends the
////     connection with no 0x036A.
//// - **A process dying or a deadline passing.** The rule holds no process:
////   a restart of the hand-off or the store is seen only as an ask's outcome
////   (`NotRunning`, `EndedBeforeAnswer`), and a late answer
////   (`AnsweredLate`) is dropped. A crash of the connection's own process
////   drops the client, which connects again from the login.
//// - **Network messages** are answered before any wrapper is read: a ping 0
////   gets a pong 1 (opcode.0x0), a pong or close notice nothing
////   (genesis_prime/connection/client_frame).
//// - **Out of order.** A frame the client's reader would refuse ends the
////   connection; a whole frame of a message the rule does not take, 0x038C
////   with 0x082D inside it, 0x0241 and any other, is logged as unhandled and
////   the connection goes on (opcode.0x241).

import genesis_prime/client_connection.{type Answer, type Link, type Request}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/game/character_select
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{type Input, type Rule, type Step}

/// The rule's name in a recording's header and in the server's tree.
pub const rule_name = "genesis_prime/game/connection"

/// What every game connection is made with, at start.
pub type Settings {
  Settings(
    /// The realm's id: the hello's, and the character list's, which becomes
    /// the client's current realm when it plays a character (opcode.0x117).
    realm_id: Int,
    /// The number of characters the client's list is told the account may
    /// have; the Lua keeps it and nothing reads it (lua.Character.OnCharacterList).
    max_characters: Int,
    /// How long an ask to the hand-off or the store may take.
    ask_deadline_ms: Int,
  )
}

/// Where the connection is. Once accepted, the state keeps the connection and
/// the peer for every log line it writes.
pub opaque type State {
  NotAccepted(settings: Settings)
  Connected(session: Session)
}

/// What an accepted connection keeps.
type Session {
  Session(
    settings: Settings,
    link: Link,
    /// Bytes of a frame not yet whole, and whole frames not yet taken while
    /// an ask is out.
    pending: BitArray,
    /// The cipher the connection's frames are read and written under: the
    /// base key's until 0x058F re-keys it.
    cipher: Cipher,
    status: Status,
  )
}

/// The connection's one status.
type Status {
  /// The hello is sent; waiting for 0x058F.
  AwaitingHelloReply
  /// The hand-off is asked to take the session key.
  TakingSessionKey
  /// The session key was held for `holder`; the client is in character
  /// select, which holds its own state.
  InCharacterSelect(holder: Holder, select: character_select.State)
}

/// The rule as its connection shell runs it.
pub fn rule(
  settings: Settings,
) -> Rule(Settings, State, Nil, Answer, Nil, Request) {
  step.Rule(name: rule_name, settings:, new:, step:)
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
