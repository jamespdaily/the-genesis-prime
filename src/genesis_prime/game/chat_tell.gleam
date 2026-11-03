//// What one game connection tells another about chat, with no answer awaited
//// (genesis_prime/step `Tell`): a line to a reader, and a whisper's two
//// replies. Every send of chat is one of these, so two players who whisper
//// each other at once never wait on each other. The connection rule
//// (genesis_prime/game/connection) sends and takes them; the chat feature
//// (genesis_prime/game/chat) decides what each does.
////
//// ```
//// speaker conn ── Said ────────────────▶ each viewer conn
//// speaker conn ── ZoneLine ─────────────▶ each member conn of ZoneChannel(run, top)
//// speaker conn ── Whisper ──────────────▶ the target's conn (CharacterNamed, through a watch)
//// target conn  ── Heard | NotHeard ─────▶ the speaker's conn (Connection)
//// ```

import genesis_prime/game/chat_channel.{type ChannelType}
import genesis_prime/message/chat_format.{type ChatFormat}
import genesis_prime/step.{type ConnectionId}
import genesis_prime/world_map/map_id.{type MapId}

/// Who speaks, as a reader's 0x1c8 shows the speaker, and where: the run of the
/// map the speaker is in, so a reader in another run or map drops the line
/// (the unit id there may name another unit).
pub type Speaker {
  Speaker(
    realm_id: Int,
    character_id: Int,
    name: String,
    faction_id: Int,
    unit_id: Int,
    map: MapId,
    incarnation: Int,
  )
}

/// A line as the speaker's client sent it and the rule accepted it: the channel
/// it was sent on, its text, in UTF-16 units as the client sent them, and its
/// formats unchanged (the server adds no format and refuses no line for its
/// words, `0x140c45f50`).
pub type Line {
  Line(
    channel_type: ChannelType,
    channel_id: Int,
    text: List(Int),
    formats: List(ChatFormat),
  )
}

/// A tell from one game connection to another.
pub type Tell {
  /// A Say, Yell or Emote line, to a connection whose player sees the speaker.
  Said(speaker: Speaker, line: Line)
  /// A Zone line, to every member of the zone channel of the speaker's run and
  /// top zone `top_zone_id`. A member whose own run or top zone is another by
  /// now drops it, and so does the speaker's own connection.
  ZoneLine(speaker: Speaker, top_zone_id: Int, line: Line)
  /// A whisper, to the connection whose player is named: `whisper` is the
  /// speaker's own number of it, which the replies carry, and `from` the
  /// speaker's connection, which they go to.
  Whisper(whisper: Int, speaker: Speaker, from: ConnectionId, line: Line)
  /// The whisper reached the target's client: `name` is the target's own name,
  /// which the speaker's 0x1c2 shows.
  Heard(whisper: Int, name: String)
  /// The named connection holds no player in the world, so the whisper reached
  /// no one.
  NotHeard(whisper: Int)
}
