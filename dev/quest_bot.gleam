//// The quest actions of a scripted client: each encodes its message with the codec,
//// sends it as a world message, reads what the server wrote in answer and gives that
//// decoded. The answer to a talk, an accept and an activate is all the server wrote up
//// to its pong, which is all it wrote before it took the ping
//// (`game_client.read_until_pong`); the go of an activate and a turn-in are answered
//// after the server's own steps, so they wait on the frame that ends them.

import bot_frames
import game_client.{type Game}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/experience_gained.{type ExperienceGained}
import genesis_prime/message/held_item.{type HeldItem}
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/message/item_added
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/quest_accept.{QuestAccept}
import genesis_prime/message/quest_mention.{QuestMention}
import genesis_prime/message/quest_objective_progress.{
  type QuestObjectiveProgress,
}
import genesis_prime/message/quest_state.{type QuestState}
import genesis_prime/message/quest_turn_in.{QuestTurnIn}
import genesis_prime/message/spell_cast_confirmed.{type SpellCastConfirmed}
import genesis_prime/message/unit_dialog_open.{type UnitDialogOpen}
import gleam/list
import gleam/result

/// The interaction kind of a right-click on a unit that gives or takes a quest
/// (opcode.0x7ea).
const quest_talk_kind = 37

/// What the server wrote in answer to an action, each message kind decoded in the
/// order it came, and every frame as it came.
pub type Answer {
  Answer(
    frames: List(Frame),
    /// 0x357: a unit's quest dialog opened.
    dialogs: List(UnitDialogOpen),
    /// 0x35C: a quest's new state.
    states: List(QuestState),
    /// 0x361: an objective's new progress.
    progress: List(QuestObjectiveProgress),
    /// 0x7FD: a cast the server confirmed.
    confirmed: List(SpellCastConfirmed),
    /// 0x1AC: experience gained.
    experience: List(ExperienceGained),
    /// 0x111: an item the character now holds.
    added: List(HeldItem),
  )
}

/// The answer the frames make, each message decoded as the client's reader reads it.
fn answer_in(frames frames: List(Frame)) -> Answer {
  Answer(
    frames:,
    dialogs: bot_frames.decoded(
      frames,
      unit_dialog_open.message_id,
      unit_dialog_open.decode,
    ),
    states: bot_frames.decoded(
      frames,
      quest_state.message_id,
      quest_state.decode,
    ),
    progress: bot_frames.decoded(
      frames,
      quest_objective_progress.message_id,
      quest_objective_progress.decode,
    ),
    confirmed: bot_frames.decoded(
      frames,
      spell_cast_confirmed.message_id,
      spell_cast_confirmed.decode,
    ),
    experience: bot_frames.decoded(
      frames,
      experience_gained.message_id,
      experience_gained.decode,
    ),
    added: bot_frames.decoded(frames, item_added.message_id, fn(body) {
      item_added.decode(body) |> result.map(fn(message) { message.held_item })
    }),
  )
}

/// Right-clicks the unit as a quest giver or receiver: the answer is its dialog.
pub fn talk(
  game game: Game,
  have have: BitArray,
  unit_id unit_id: Int,
) -> #(Answer, BitArray) {
  let assert Ok(body) =
    interaction_request.encode(InteractionRequest(
      unit_id:,
      kind: quest_talk_kind,
    ))
    as "0x7EA encodes"
  acted(game:, have:, message_id: interaction_request.message_id, body:)
}

/// Mentions the quest, which the client sends for a quest it holds no state of
/// (opcode.0x360); the server answers nothing.
pub fn mention(
  game game: Game,
  have have: BitArray,
  quest_id quest_id: Int,
) -> #(Answer, BitArray) {
  let assert Ok(body) =
    quest_mention.encode(QuestMention(quest_id:, mentioned: 1))
    as "0x360 encodes"
  acted(game:, have:, message_id: quest_mention.message_id, body:)
}

/// Accepts the quest at the dialog, which the client sends with no item
/// (location 300 and bag index -1: opcode.0x35b).
pub fn accept(
  game game: Game,
  have have: BitArray,
  quest_id quest_id: Int,
) -> #(Answer, BitArray) {
  let assert Ok(body) =
    quest_accept.encode(QuestAccept(
      item: ItemPlace(location: 300, bag_index: 4_294_967_295),
      quest_id:,
    ))
    as "0x35B encodes"
  acted(game:, have:, message_id: quest_accept.message_id, body:)
}

/// Right-clicks the unit to use it, which presses its activate spell: the answer
/// holds the cast's confirmation, and the go follows when the cast time has passed
/// (`went`).
pub fn activate(
  game game: Game,
  have have: BitArray,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
) -> #(Answer, BitArray) {
  let assert Ok(body) =
    cast_activate.encode(CastActivate(client_cast_id:, target_unit_id: unit_id))
    as "0x97 encodes"
  acted(game:, have:, message_id: cast_activate.message_id, body:)
}

/// Reads what the server writes when the cast of an `activate` goes: up to the
/// objective's new progress and then up to the pong, which follows all the go wrote.
pub fn went(game game: Game, have have: BitArray) -> #(Answer, BitArray) {
  let #(first, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(frames, fn(frame) {
        frame.message_id == quest_objective_progress.message_id
      })
    })
  let #(rest, have) = game_client.read_until_pong(game:, have:, number: 1)
  #(answer_in(frames: list.append(first, rest)), have)
}

/// Turns the quest in with the reward choice. The server saves the character before it
/// answers, so the answer is all it wrote up to the quest's state 3, its last frame.
pub fn turn_in(
  game game: Game,
  have have: BitArray,
  quest_id quest_id: Int,
  reward_id reward_id: Int,
) -> #(Answer, BitArray) {
  let assert Ok(body) =
    quest_turn_in.encode(QuestTurnIn(quest_id:, reward_id:, by_communicator: 0))
    as "0x35D encodes"
  game_client.send_world(game:, message_id: quest_turn_in.message_id, body:)
  let #(frames, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(answer_in(frames:).states, fn(told) {
        told.quest_id == quest_id && told.state == 3
      })
    })
  #(answer_in(frames:), have)
}

fn acted(
  game game: Game,
  have have: BitArray,
  message_id message_id: Int,
  body body: BitArray,
) -> #(Answer, BitArray) {
  game_client.send_world(game:, message_id:, body:)
  let #(frames, have) = game_client.read_until_pong(game:, have:, number: 1)
  #(answer_in(frames:), have)
}
