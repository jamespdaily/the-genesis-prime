//// The player's camp: leaving the world to character select, a feature of the
//// game connection's rule (genesis_prime/game/connection) as the player's
//// movement is (genesis_prime/game/movement). It keeps whether a camp is
//// running and says what the client's two camp messages, 0xBF and 0xC0, are
//// answered with; the rule turns that into writes, the save of the place and
//// the leave of the map.
////
//// ```
//// 0xBF 1  ─▶ requested(camp, True, countdown) ─▶ Answer(countdown): the rule writes 0x92
//// 0xBF 0  ─▶ requested(camp, False, _)        ─▶ Cancelled or Ignored: nothing is written
//// 0xC0    ─▶ finished(camp)                   ─▶ Finished: the rule saves, leaves the map, writes 0x594
////                                                or a refusal that ends the connection
//// ```
////
//// - **The client decides when the camp ends.** The server's countdown only
////   starts the client's window: the client's deadline comes from 0x92 alone,
////   and the client sends 0xC0 when it runs out or the player presses Exit
////   (opcode.0x92.countdown_source, opcode.0xc0). A Quit sends 0xC0 at any
////   time after the 0x92, and the server cannot tell it from a camp's
////   (opcode.0xbf, opcode.0xc0), so a 0xC0 is taken whenever it comes while a
////   camp runs.
//// - **Each 0xBF 1 is answered**, with a 0x92 of the setting's countdown and
////   the cancel bit clear. A second one while a camp runs restarts the
////   client's countdown, which the client allows only before its first 0x92
////   arrives (opcode.0xbf); the server keeps one camp.
//// - **0xBF 0 is never answered.** The client cleared its own camp before it
////   sent it, and a cancelling 0x92 in answer would be answered by another
////   0xBF 0 without end (lua.ExitWindow.OnPlayerCampCancel). With no camp
////   running it changes nothing: the exit window sends it after any cancelling
////   0x92, with no test (lua.ExitWindow.OnPlayerCampCancel).
//// - **0xC0 with no camp running** is a message the client never sends: it
////   sends 0xC0 only while a camp the server started with 0x92 runs
////   (opcode.0xc0). The rule ends the connection, as it does for a refused
////   movement command.
//// - **The server never cancels a camp.** The client cancels on nothing but
////   its exit window (Cancel, close, Escape, the signature buttons and every
////   PlayerCampCancel); moving, casting, combat and a hit do not
////   (lua.ExitWindow.OnCancel), and no record says retail cancelled on any of
////   them. A server cancel would also be a 0x92 with a countdown of 0 and the
////   cancel bit set, which the client always answers with a 0xBF 0
////   (lua.ExitWindow.OnPlayerCampCancel).
//// - **The camp ends with the world.** It is kept in the player's world state
////   (genesis_prime/game/world_entry `Entered`), so a camp that ends in
////   character select leaves no camp behind, and a play after it starts with
////   none, as the client's next world does (opcode.0x594.world_teardown).
//// - **Nothing is stored.** A crash of the connection ends the camp with the
////   connection.

/// Whether the player's camp is running.
pub opaque type Camp {
  Camp(running: Bool)
}

/// What the rule does about a camp message.
pub type Decision {
  /// Write 0x92 with this countdown and the cancel bit clear.
  Answer(countdown_ms: Int)
  /// A running camp was cancelled by the client: nothing is written.
  Cancelled
  /// A cancel with no camp running: nothing is written, nothing changes.
  Ignored
  /// The camp is finished: save the place, leave the map, write 0x594.
  Finished
}

/// Why a camp message is refused: the client's own code never sends it.
pub type Refusal {
  /// 0xC0 with no camp running (opcode.0xc0).
  FinishedWithNoCamp
}

/// No camp: the state of a player who has just entered the world.
pub fn none() -> Camp {
  Camp(running: False)
}

/// The client's 0xBF: `start` is its bit. A start makes a camp run and is
/// answered with `countdown_ms`, the setting's; a cancel clears the camp.
pub fn requested(
  camp _camp: Camp,
  start _start: Bool,
  countdown_ms _countdown_ms: Int,
) -> #(Camp, Decision) {
  panic as "built in the next commit: a start runs a camp and is answered, a cancel clears it and is never answered"
}

/// The client's 0xC0: `Finished` while a camp runs, and the refusal when none
/// does.
pub fn finished(camp _camp: Camp) -> Result(Decision, Refusal) {
  panic as "built in the next commit: finished with a camp running is Finished, with none the refusal"
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal _refusal: Refusal) -> String {
  panic as "built in the next commit: the sentence for each refusal"
}
