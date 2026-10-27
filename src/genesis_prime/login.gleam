//// What the login's two rules ask other processes, and what comes back. The
//// STS rule (genesis_prime/login/sts_connection) asks the store for the
//// account and the hand-off to keep the game token; the auth rule
//// (genesis_prime/login/auth_connection) asks the hand-off to take the game
//// token and to keep the session key. The server's directory sends each
//// request to its process and wraps each answer (genesis_prime/server).

import genesis_prime/hand_off
import genesis_prime/store

/// What a login rule asks.
pub type Request {
  AskStore(request: store.Request)
  AskHandOff(message: hand_off.Message)
}

/// What comes back from an ask, by the process asked.
pub type Answer {
  FromStore(answer: store.Answer)
  FromHandOff(answer: hand_off.Answer)
}
