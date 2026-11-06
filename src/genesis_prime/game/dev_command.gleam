//// The development chat commands: a Say line that starts with `!`, read as a
//// command when the setting `dev_commands` is on (genesis_prime/game_settings),
//// and a Say line as any other when it is off. A server choice for testing: the
//// client has no such commands, and every one of them reaches the client as a
//// Say line it sent and a system line the server answers it with.
////
//// ```
//// Say "!summon 75048"  ─▶ chat: setting on, channel Say, text starts with `!`
////                          parse ─▶ Summon(Creature2Id 75048) ─▶ chat.AskSummon ─▶ the connection asks the map
////                          parse ─▶ Refusal                   ─▶ one system line (`describe`)
//// ```
////
//// - **The grammar** is `!` then a word, then its arguments, split at spaces.
////   `summon` takes one whole decimal number, a Creature2 id; the word is read
////   as typed, in lower case.
//// - **A word with no command**, and a command whose arguments are not what it
////   takes, are each answered with a system line, never as a Say line, so a
////   mistyped command is not said aloud to the players who see the speaker.

import genesis_prime/table/id.{type Creature2Id}

/// A development command.
pub type Command {
  /// `!summon <Creature2 id>`: start that creature at the player's place and
  /// facing as a run-only spawn (genesis_prime/world_map/map `Summon`).
  Summon(creature2_id: Creature2Id)
}

/// Why a `!` line is no command.
pub type Refusal {
  /// The word after `!` is no command.
  UnknownCommand
  /// The word is `summon`, but what follows is not exactly one whole number.
  SummonTakesACreature2Id
}

/// Whether the text is a command line: its first UTF-16 unit is `!`.
pub fn is_command(text text: List(Int)) -> Bool {
  case text {
    [0x21, ..] -> True
    _ -> False
  }
}

/// The command a `!` line holds, or why it holds none.
pub fn parse(text text: List(Int)) -> Result(Command, Refusal) {
  todo as "split the units at spaces; summon with one whole decimal number is Summon, summon otherwise is SummonTakesACreature2Id, any other word is UnknownCommand"
}

/// The text of the system line that answers a refused command.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    UnknownCommand -> "unknown command"
    SummonTakesACreature2Id ->
      "!summon takes one Creature2 id, as !summon 75048"
  }
}
