//// A player's chat in the world: say, yell, emote, zone and whisper, a feature
//// of the game connection's rule (genesis_prime/game/connection). It keeps the
//// speaker, the zone channel and the whispers waiting for a reply, and decides
//// what 0x1c3 and 0x1d4 are answered with and what a tell from another
//// connection (genesis_prime/game/chat_tell) writes. Every send is a tell:
//// the effects are writes, tells, watches and group joins, never an ask.
////
//// ```
//// 0x1c3 (say/yell/emote) ─▶ 0x1c2; TellSay ─▶ map ─▶ 0x1c8 to each viewer
//// 0x1c3 (zone) ─▶ 0x1c2; Tell ZoneChannel(run, top) ─▶ 0x1c8 to each member in it
//// entry ─▶ 0x1da, 0x1bc, JoinGroup; 0xF2/0x63A ─▶ move or leave; camp ─▶ leave
//// 0x1d4 ─▶ Watch + TellWatched on the folded name ─▶ 0x1c8, Heard ─▶ 0x1c2; else 0x1d9
//// ```
////
//// - A line must name a held channel: the client's own (id 0) or Zone by its
////   0x1bc; another is refused (`0x140404ee0`, `ChatChannel.flags`).
//// - The zone channel is named by 0x1da after the top zone and given by 0x1bc,
////   id 1 in every world (`opcode.0x1da`, `opcode.0x1bc`, `chat.zone_channel_id`).
//// - The first 0xF2 of a stay writes 0x1bc again: the burst's ChatJoin can reach
////   no handler (`chat.zone_join_trigger`, `lua.ChatLog.OnChatJoin`, `0x1400ea400`).
//// - A zone report (0xF2, 0x63A) is rolled up to its top zone; 0 or no row is
////   no zone (`opcode.0xf2`, `opcode.0x63a`, `0x140403670`, `chat.zone_reach`).
//// - The speaker is answered 0x1c2 (a whisper's names the target), never sent
////   its own 0x1c8; bCrossFaction is 1 when the `faction_id`s differ
////   (`opcode.0x1c2`, `opcode.0x1c8`, `chat.cross_faction`).
//// - A local line goes to the players that see the speaker (`chat.range`, a server choice).
//// - A line is 1 to 501 UTF-16 units, its formats in range and of a type the
////   client's text makes (`chat.sent_text_length`, `chat.format_bounds`).
//// - Text and formats are relayed as sent (`0x140c45f50`).
//// - A whisper's target is found by its folded name, the fold of the database's
////   unique index (migration 0005, `opcode.0x1d4`, genesis_prime/game/character_name).
//// - An account whisper (bit 1) is answered 0x1d9 with bit 1 (`opcode.0x1d4`).
//// - Every 0x1c3 and 0x1d4 gets one answer. A pending whisper is kept by the
////   connection's own number and told through its own watch (`TellWatched`); an
////   empty whisper is answered only when its target is missing (`0x140405cb0`, `0x140405e00`).
//// - A `!` line on Say is a development command when `dev_commands` is on
////   (genesis_prime/game/dev_command, a server choice).
//// - A format of type 12 to 15 is unreadable: the connection ends (`0x140085ca0`).
//// - No timer: every whisper path ends in `Heard`, `NotHeard` or `WatchEnded`.
//// - No chat flow sends player-info 0x597, 0x598 or 0x599 (`chat.name_lookup`).

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/character_name
import genesis_prime/game/chat_channel.{type ChannelType}
import genesis_prime/game/chat_tell.{
  type Line, type Said, type Speaker, type Tell, Line,
}
import genesis_prime/game/dev_command
import genesis_prime/game/top_zone.{type TopZones}
import genesis_prime/message/bit_stream
import genesis_prime/message/chat_channel_joined.{ChatChannelJoined}
import genesis_prime/message/chat_channel_result.{
  type ChatChannelResult, DoesntExist, InvalidMessageText, NoPermissions,
  NotInGroup,
}
import genesis_prime/message/chat_format.{type ChatFormat}
import genesis_prime/message/chat_line.{ChatLine}
import genesis_prime/message/chat_line_accepted.{ChatLineAccepted}
import genesis_prime/message/chat_result.{ChatResult}
import genesis_prime/message/chat_zone_named.{ChatZoneNamed}
import genesis_prime/message/send_chat_line.{type SendChatLine}
import genesis_prime/message/send_whisper.{type SendWhisper}
import genesis_prime/message/whisper_failed.{WhisperFailed}
import genesis_prime/step.{type Address, type ConnectionId, type WatchId}
import genesis_prime/table/chat_channel.{type ChatChannel} as chat_channel_table
import genesis_prime/table/id.{ChatChannelId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/stay.{type Stay}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// The chat messages of the player in the world, which the client sends inside
/// 0x038C (genesis_prime/game/routing's table says which id is which).
pub type Message {
  /// 0x01C3, a line on a channel the client holds.
  LineSent
  /// 0x01D4, a whisper by name.
  WhisperSent
}

/// What chat makes the game connection's rule carry out.
pub type Effect {
  /// Send this message to the client, in the game wrapper under the
  /// connection's cipher.
  Send(frame: Frame)
  /// Tell the process at `to` a chat tell (genesis_prime/step `Tell`).
  Tell(to: Address, tell: Tell)
  /// Tell the speaker's map, the run its `Said` names, a line of local chat from the player
  /// of `connection` in its stay `stay`, for the map to relay to each player that sees the
  /// speaker, for that player's stay, so that a line queued across a re-entry of the same
  /// run is dropped at the connection (genesis_prime/client_connection `TellSay`).
  TellSay(connection: ConnectionId, stay: Stay, said: Said)
  /// Tell the process the open watch `watch` found, through that watch
  /// (genesis_prime/step `TellWatched`): a whisper to its target.
  TellWatched(watch: WatchId, tell: Tell)
  /// The WorldZone id is one the table holds no row for, which the client
  /// accepts (0x1da names no channel then, `0x140403670`): the rule logs a warning,
  /// once for each zone on a connection.
  UnknownZone(world_zone_id: Int)
  /// Watch the process at `target`, a whisper's target; its end or absence comes
  /// back as `WatchEnded` (genesis_prime/step `Watch`).
  Watch(watch: WatchId, target: Address)
  /// Stop watching (genesis_prime/step `Unwatch`).
  Unwatch(watch: WatchId)
  /// Join the registry's group at the address (genesis_prime/step `JoinGroup`).
  JoinGroup(address: Address)
  /// Leave the registry's group at the address (genesis_prime/step `LeaveGroup`).
  LeaveGroup(address: Address)
  /// The channel is one the server does not build: the rule logs it as
  /// unhandled once per channel on a connection.
  Unhandled(channel_type: ChannelType)
  /// A development command line of the player that the tables allow: the
  /// connection carries the command out (genesis_prime/game/connection/dev_command)
  /// and writes its system line. The rule gives it last among the effects of a
  /// line, since a command can end the step with an ask.
  RunCommand(command: dev_command.Command)
}

/// Why a chat message is refused so that the connection ends: the client's own
/// reader would refuse its body.
pub type Refusal {
  /// A body the client's own reader would refuse, a format of type 12 to 15
  /// among them.
  NotDecoded(undecoded: client_connection.Undecoded)
}

/// The id of the zone channel in every world and run: the client has no rule
/// on it, and one id is one ChatLog save entry (`chat.zone_channel_id`, a server
/// choice).
const zone_channel_id = 1

/// The zone the client reported and the top zone it falls under.
pub type Zone {
  /// Zone 0, or the player has reported none: in no zone channel.
  NoZone
  InZone(world_zone_id: Int, top_zone_id: Int)
}

/// A whisper sent and not yet answered, by the speaker's own number: the slot
/// the client keeps the line in, the target's name as sent, which 0x1d9 names,
/// and whether it has a text: an empty whisper is answered only when its target
/// is not found.
pub type PendingWhisper {
  PendingWhisper(chat_message_id: Int, target_name: List(Int), with_text: Bool)
}

/// One player's chat while in the world: who speaks, where it stands in zones,
/// whether the first 0xF2 of the stay has written the zone channel again, the
/// number of its next whisper and the whispers waiting for a reply. Each whisper
/// is watched under a `WatchId` of its own, above the connection's own watches,
/// made from its number.
pub opaque type Chat {
  Chat(
    speaker: Speaker,
    zone_channel_joined: Bool,
    zone_channel_rejoined: Bool,
    zone: Zone,
    next_whisper: Int,
    whispers: Dict(Int, PendingWhisper),
  )
}

/// The chat of a player that has just entered the world: in no zone, with no
/// whisper waiting. `next_whisper` is the number of the connection's next
/// whisper, which counts for the connection's life (`next_whisper` gives it
/// back).
pub fn new(speaker speaker: Speaker, next_whisper next_whisper: Int) -> Chat {
  Chat(
    speaker:,
    zone_channel_joined: False,
    zone_channel_rejoined: False,
    zone: NoZone,
    next_whisper:,
    whispers: dict.new(),
  )
}

/// The number of the connection's next whisper, which the connection keeps when
/// the player leaves the world so the next stay's numbers go on from it.
pub fn next_whisper(chat chat: Chat) -> Int {
  chat.next_whisper
}

/// What the entry burst adds once 0x61 is written: the player joins
/// `CharacterNamed(its folded name)`, 0x1da names the zone channel after the top
/// zone of the place's zone `world_zone_id`, 0x1bc gives the client the zone
/// channel and the player joins `ZoneChannel(its run, that top zone)`. A place
/// zone that is 0 or that the table holds no row for leaves the player in no
/// zone: 0x1da with 0, 0x1bc still written, no zone group, and the `UnknownZone`
/// effect for a zone with no row.
pub fn entered_world(
  chat chat: Chat,
  world_zone_id world_zone_id: Int,
  top_zones top_zones: TopZones,
) -> #(Chat, List(Effect)) {
  let #(zone, warning) = zone_of(world_zone_id:, top_zones:)
  let chat = Chat(..chat, zone_channel_joined: True, zone:)
  #(
    chat,
    list.flatten([
      [JoinGroup(address: step.CharacterNamed(folded_name: folded(chat)))],
      warning,
      [
        Send(zone_named_frame(zone)),
        Send(zone_joined_frame()),
        ..join_zone(chat:, zone:)
      ],
    ]),
  )
}

/// The zone a WorldZone id puts a player in, and the effect that says the id has
/// no row: zone 0 and a zone with no row are no zone, and only the second is
/// named.
fn zone_of(
  world_zone_id world_zone_id: Int,
  top_zones top_zones: TopZones,
) -> #(Zone, List(Effect)) {
  case top_zone.of(top_zones, world_zone_id) {
    Ok(top_zone_id) -> #(InZone(world_zone_id:, top_zone_id:), [])
    Error(Nil) ->
      case world_zone_id {
        0 -> #(NoZone, [])
        _ -> #(NoZone, [UnknownZone(world_zone_id:)])
      }
  }
}

/// The player's name folded as the database's unique index folds it
/// (migration 0005): the key of the group a whisper finds the player by.
fn folded(chat: Chat) -> String {
  character_name.fold(name: chat.speaker.name)
}

/// The group of the player's run and top zone, which the player joins; none when
/// it is in no zone.
fn zone_group(chat chat: Chat, zone zone: Zone) -> Result(Address, Nil) {
  case zone {
    NoZone -> Error(Nil)
    InZone(top_zone_id:, ..) ->
      Ok(step.ZoneChannel(
        map: chat.speaker.map,
        incarnation: chat.speaker.incarnation,
        top_zone_id:,
      ))
  }
}

fn join_zone(chat chat: Chat, zone zone: Zone) -> List(Effect) {
  case zone_group(chat:, zone:) {
    Ok(address) -> [JoinGroup(address:)]
    Error(Nil) -> []
  }
}

fn leave_zone(chat chat: Chat) -> List(Effect) {
  case zone_group(chat:, zone: chat.zone) {
    Ok(address) -> [LeaveGroup(address:)]
    Error(Nil) -> []
  }
}

/// 0x1da naming the zone channel after the zone's top zone, or after none (0), so
/// the client shows the channel with an empty name (opcode.0x1da, 0x140403670).
fn zone_named_frame(zone: Zone) -> Frame {
  let world_zone_id = case zone {
    NoZone -> 0
    InZone(top_zone_id:, ..) -> top_zone_id
  }
  let body =
    bit_stream.must(ChatZoneNamed(world_zone_id:), chat_zone_named.encode)
  Frame(message_id: chat_zone_named.message_id, body:)
}

/// 0x1bc giving the client the zone channel: type 9, id 1, an empty name and
/// three zeros (opcode.0x1bc).
fn zone_joined_frame() -> Frame {
  let body =
    bit_stream.must(
      ChatChannelJoined(
        channel_type: chat_channel.id(chat_channel.Zone),
        channel_id: zone_channel_id,
        name: "",
        unread_4: 0,
        custom_channel_slot: 0,
        unread_6: 0,
      ),
      chat_channel_joined.encode,
    )
  Frame(message_id: chat_channel_joined.message_id, body:)
}

/// What one chat message of the client does: its body is decoded and the line or
/// the whisper is answered, told to the map or its target, or refused. `stay` is the stay of
/// the speaker's connection in the world, which a line carries to the map, `realm_name` the server's own,
/// `tables` the client's ChatChannel rows, and `dev_commands` whether a Say line
/// that starts with `!` is a development command
/// (genesis_prime/game/dev_command). A body the client's reader would refuse is
/// the refusal that ends the connection.
pub fn take(
  chat chat: Chat,
  message message: Message,
  body body: BitArray,
  stay stay: Stay,
  realm_name realm_name: String,
  connection connection: ConnectionId,
  tables tables: table_store.Tables,
  dev_commands dev_commands: Bool,
) -> Result(#(Chat, List(Effect)), Refusal) {
  case message {
    LineSent ->
      line_sent(chat:, body:, connection:, stay:, tables:, dev_commands:)
    WhisperSent -> whisper_sent(chat:, body:, realm_name:, connection:)
  }
}

/// The first watch id a whisper uses; the connection's own watches are below it.
const first_whisper_watch = 100

/// The watch that waits on whisper `whisper`'s target.
fn whisper_watch(whisper: Int) -> WatchId {
  step.WatchId(first_whisper_watch + whisper)
}

/// What a 0x1d4 is answered with and told to: refused as a line, delivered at
/// once to the speaker itself, or sent to the target by its name through a watch.
fn whisper_sent(
  chat chat: Chat,
  body body: BitArray,
  realm_name realm_name: String,
  connection connection: ConnectionId,
) -> Result(#(Chat, List(Effect)), Refusal) {
  use sent <- result.map(
    send_whisper.decode(body)
    |> client_connection.decoded(message_id: send_whisper.message_id)
    |> result.map_error(NotDecoded),
  )
  let channel_type = case sent.account {
    1 -> chat_channel.AccountWhisper
    _ -> chat_channel.Whisper
  }
  use <- bool.lazy_guard(
    when: sent.chat_message_id == 0
      || !is_a_line(text: sent.text, formats: sent.formats, empty_allowed: True),
    return: fn() {
      #(chat, [
        Send(chat_result_frame(
          channel_type: chat_channel.id(channel_type),
          channel_id: 0,
          chat_message_id: sent.chat_message_id,
          result: InvalidMessageText,
        )),
      ])
    },
  )
  let target = case
    sent.account == 1
    || !is_the_realm(named: sent.target_realm_name, own: realm_name)
  {
    True -> Error(Nil)
    False ->
      bit_stream.from_utf16(sent.target_name) |> result.replace_error(Nil)
  }
  case target {
    Error(Nil) -> #(chat, [Send(whisper_failed_frame(sent:))])
    Ok(target_name) -> {
      let line =
        Line(
          channel_type: chat_channel.Whisper,
          channel_id: 0,
          text: sent.text,
          formats: sent.formats,
        )
      let folded_target = character_name.fold(name: target_name)
      case folded_target == folded(chat) {
        True -> #(chat, whisper_to_oneself(chat:, sent:, line:))
        False ->
          whisper_to_another(chat:, sent:, line:, folded_target:, connection:)
      }
    }
  }
}

/// A whisper to another character: it is kept by the speaker's next number,
/// whose watch waits on the target's name, and told to the target through that
/// watch. Nothing is written until the reply.
fn whisper_to_another(
  chat chat: Chat,
  sent sent: SendWhisper,
  line line: Line,
  folded_target folded_target: String,
  connection connection: ConnectionId,
) -> #(Chat, List(Effect)) {
  let whisper = chat.next_whisper
  let watch = whisper_watch(whisper)
  #(
    Chat(
      ..chat,
      next_whisper: whisper + 1,
      whispers: dict.insert(
        chat.whispers,
        whisper,
        PendingWhisper(
          chat_message_id: sent.chat_message_id,
          target_name: sent.target_name,
          with_text: sent.text != [],
        ),
      ),
    ),
    [
      Watch(watch:, target: step.CharacterNamed(folded_name: folded_target)),
      TellWatched(
        watch:,
        tell: chat_tell.Whisper(
          whisper:,
          speaker: chat.speaker,
          from: connection,
          line:,
        ),
      ),
    ],
  )
}

/// A whisper to the speaker's own name, which is shown and answered in the
/// speaker's own step with no watch (server choice); an empty one shows nothing.
fn whisper_to_oneself(
  chat chat: Chat,
  sent sent: SendWhisper,
  line line: Line,
) -> List(Effect) {
  case sent.text {
    [] -> []
    [_, ..] -> [
      Send(line_frame(chat:, speaker: chat.speaker, line:)),
      Send(accepted_as(
        name: chat.speaker.name,
        chat:,
        chat_message_id: sent.chat_message_id,
      )),
    ]
  }
}

/// Whether the realm name a whisper names is this realm: empty, or the server's
/// own, compared without case (opcode.0x1d4). A name that is not valid UTF-16 is
/// no realm's.
fn is_the_realm(named named: List(Int), own own: String) -> Bool {
  named == []
  || {
    bit_stream.from_utf16(named)
    |> result.map(fn(realm) { string.lowercase(realm) == string.lowercase(own) })
    |> result.unwrap(or: False)
  }
}

/// 0x1d9 for a whisper that was not delivered: the target's name as sent, the
/// account bit and the slot (opcode.0x1d9).
fn whisper_failed_frame(sent sent: SendWhisper) -> Frame {
  failed_frame(
    target_name: sent.target_name,
    account: sent.account,
    chat_message_id: sent.chat_message_id,
  )
}

fn failed_frame(
  target_name target_name: List(Int),
  account account: Int,
  chat_message_id chat_message_id: Int,
) -> Frame {
  let body =
    bit_stream.must(
      WhisperFailed(target_name:, account:, chat_message_id:),
      whisper_failed.encode,
    )
  Frame(message_id: whisper_failed.message_id, body:)
}

/// The most UTF-16 units the client sends in one line: ParseChatText cuts at 499
/// once for each pass, so a link or waypoint tag at 498 units adds its three
/// characters and the sent text reaches 501 (`chat.sent_text_length`,
/// `0x140402720`, `vector.0x140402720.lines`).
const longest_line = 501

/// The end an unclosed type 1 or 2 format goes on the wire with: nothing closes
/// it (`chat.format_bounds`).
const unclosed_end = 65_535

/// What a 0x1c3 is answered with and told to.
fn line_sent(
  chat chat: Chat,
  body body: BitArray,
  connection connection: ConnectionId,
  stay stay: Stay,
  tables tables: table_store.Tables,
  dev_commands dev_commands: Bool,
) -> Result(#(Chat, List(Effect)), Refusal) {
  use sent <- result.map(
    send_chat_line.decode(body)
    |> client_connection.decoded(message_id: send_chat_line.message_id)
    |> result.map_error(NotDecoded),
  )
  let channel_type = chat_channel.from_id(id: sent.channel_type)
  let is_command =
    dev_commands
    && channel_type == chat_channel.Say
    && dev_command.is_command(text: sent.text)
  case checked(chat:, sent:, channel_type:, tables:) {
    Error(Refused(result:, unhandled:)) -> #(chat, [
      Send(chat_result_frame(
        channel_type: sent.channel_type,
        channel_id: sent.channel_id,
        chat_message_id: sent.chat_message_id,
        result:,
      )),
      ..case unhandled {
        True -> [Unhandled(channel_type:)]
        False -> []
      }
    ])
    Ok(Say) if is_command -> #(chat, [
      Send(accepted_frame(chat:, chat_message_id: sent.chat_message_id)),
      ..command_line(text: sent.text, tables:)
    ])
    Ok(reach) -> {
      let line =
        Line(
          channel_type:,
          channel_id: sent.channel_id,
          text: sent.text,
          formats: sent.formats,
        )
      #(chat, [
        Send(accepted_frame(chat:, chat_message_id: sent.chat_message_id)),
        ..case reach {
          Say -> [
            TellSay(
              connection:,
              stay:,
              said: chat_tell.Said(speaker: chat.speaker, line:),
            ),
          ]
          Zone ->
            case chat.zone {
              NoZone -> []
              InZone(top_zone_id:, ..) -> [
                Tell(
                  to: step.ZoneChannel(
                    map: chat.speaker.map,
                    incarnation: chat.speaker.incarnation,
                    top_zone_id:,
                  ),
                  tell: chat_tell.ZoneLine(
                    speaker: chat.speaker,
                    top_zone_id:,
                    line:,
                  ),
                ),
              ]
            }
        }
      ])
    }
  }
}

/// What a `!` line on Say does when the setting is on: nothing is told to the
/// players who see the speaker, the speaker's slot is answered by the 0x1c2 the
/// caller writes (every 0x1c3 gets one answer, `opcode.0x1c2`), and the command
/// is carried out (`RunCommand`) or refused with one system line
/// (`system_line_frame` of `dev_command.describe`), by the grammar or by the
/// tables.
fn command_line(
  text text: List(Int),
  tables tables: table_store.Tables,
) -> List(Effect) {
  case
    result.try(dev_command.parse(text:), dev_command.checked(
      command: _,
      tables:,
    ))
  {
    Ok(command) -> [RunCommand(command:)]
    Error(refusal) -> [
      Send(system_line_frame(text: dev_command.describe(refusal:))),
    ]
  }
}

/// 0x1c8 as a system line: a line of the client's System channel (row 2 of
/// ChatChannel, type 2, which the client makes itself with id 0 and shows in its
/// chat window, `0x140404ee0`, `ChatChannel.flags`, `chat.system_line`), with
/// `text` and no speaker: no realm, character, name or unit, no GM mark, no
/// format and no cross-faction colour, so the line shows the channel's name and
/// then the text (`opcode.0x1c8`, `chat.system_line`). A server choice for the
/// development commands' answers. The text is a fixed sentence with numbers and
/// names from a `!` line of at most 501 units (`is_a_line`) or from the
/// client's tables, far under the 32,767 units the text field holds.
pub fn system_line_frame(text text: String) -> Frame {
  let body =
    bit_stream.must(
      ChatLine(
        channel_type: system_channel_type,
        channel_id: 0,
        gm: 0,
        from_self: 0,
        auto_response: 0,
        sender_realm_id: 0,
        sender_character_id: 0,
        sender_name: "",
        sender_realm_name: "",
        presence_state: 0,
        text: bit_stream.utf16_units(text),
        formats: [],
        cross_faction: 0,
        field_14: 0,
        unit_id: 0,
        premium_tier: 0,
      ),
      chat_line.encode,
    )
  Frame(message_id: chat_line.message_id, body:)
}

/// The ChatChannel row of the System channel, the type of a system line
/// (`ChatChannel.flags`: row 2 `System`, flags 8).
const system_channel_type = 2

/// A line the rule refuses, with the result the client is answered with, and
/// whether the channel is one the server does not build.
type Refused {
  Refused(result: ChatChannelResult, unhandled: Bool)
}

/// Where an accepted line goes.
type Reach {
  /// To the players who see the speaker.
  Say
  /// To the players of the speaker's run under its top zone.
  Zone
}

/// Whether a line is one the client would send and the player may send on its
/// channel, in the order the design's table gives its answers.
fn checked(
  chat chat: Chat,
  sent sent: SendChatLine,
  channel_type channel_type: ChannelType,
  tables tables: table_store.Tables,
) -> Result(Reach, Refused) {
  let invalid = Refused(result: InvalidMessageText, unhandled: False)
  use <- bool.guard(when: sent.chat_message_id == 0, return: Error(invalid))
  use <- bool.guard(
    when: !is_a_line(
      text: sent.text,
      formats: sent.formats,
      empty_allowed: False,
    ),
    return: Error(invalid),
  )
  let refused = fn(result) { Error(Refused(result:, unhandled: False)) }
  case channel_row(tables:, channel_type:) {
    Error(Nil) -> refused(DoesntExist)
    Ok(row) -> {
      use <- bool.guard(
        when: !is_held(chat:, row:, channel_type:, channel_id: sent.channel_id),
        return: refused(DoesntExist),
      )
      use <- bool.guard(
        when: int.bitwise_and(row.flags, may_send) == 0,
        return: refused(NoPermissions),
      )
      case channel_type {
        chat_channel.Say | chat_channel.Yell | chat_channel.Emote -> Ok(Say)
        chat_channel.Whisper | chat_channel.AccountWhisper ->
          refused(NoPermissions)
        chat_channel.Party -> refused(NotInGroup)
        chat_channel.Support | chat_channel.Instance ->
          Error(Refused(result: NoPermissions, unhandled: True))
        chat_channel.Zone -> Ok(Zone)
        chat_channel.Other(..) -> refused(NoPermissions)
      }
    }
  }
}

/// The ChatChannel row flags the chat rule reads (`ChatChannel.flags`).
const may_send = 4

const made_by_the_client = 8

const joined_by_the_server = 0x80

fn channel_row(
  tables tables: table_store.Tables,
  channel_type channel_type: ChannelType,
) -> Result(ChatChannel, Nil) {
  chat_channel_table.get(
    tables:,
    id: ChatChannelId(chat_channel.id(channel_type)),
  )
}

/// Whether the client holds a channel of this row with this id: one it makes
/// itself has id 0, and the only one the server joins is the zone channel, held
/// once its 0x1bc is written, under the id that message gave, which is always 1
/// (`0x140404ee0`, `0x1404039f0`).
fn is_held(
  chat chat: Chat,
  row row: ChatChannel,
  channel_type channel_type: ChannelType,
  channel_id channel_id: Int,
) -> Bool {
  case
    int.bitwise_and(row.flags, joined_by_the_server) != 0,
    int.bitwise_and(row.flags, made_by_the_client) != 0
  {
    True, _ ->
      channel_type == chat_channel.Zone
      && chat.zone_channel_joined
      && channel_id == zone_channel_id
    False, True -> channel_id == 0
    False, False -> False
  }
}

/// Whether the text and formats are ones the client's own code sends: from 1
/// (a whisper may be empty: the client sends one for a picked target) to
/// 501 UTF-16 units with no character ParseChatText drops (`0x140402720`), and
/// each format over a range of the text (`0x140085ca0`).
fn is_a_line(
  text text: List(Int),
  formats formats: List(ChatFormat),
  empty_allowed empty_allowed: Bool,
) -> Bool {
  let length = list.length(text)
  { length >= 1 || empty_allowed }
  && length <= longest_line
  && !list.any(text, is_dropped)
  && list.all(formats, fn(format) {
    is_made_by_the_clients_text(format) && is_in_the_text(format:, length:)
  })
}

/// Whether ParseChatText drops the UTF-16 unit: IsTextRuleCharacterAllowed
/// refuses it (`0x1403e0ae0`) and it is not the no-break space 0xa0, which
/// ParseChatText keeps (`0x140402720`).
fn is_dropped(unit: Int) -> Bool {
  unit < 0x1f
  || { unit >= 0x7f && unit <= 0x9f }
  || unit == 0xad
  || unit == 0x2028
  || unit == 0x2029
  || unit == 0xd0a
  || unit == 0xfeff
  || { unit >= 0xfdd0 && unit <= 0xfdef }
  || unit >= 0xfffe
}

/// The start and end of a format's range in the text (`0x140085ca0`).
fn format_range(format: ChatFormat) -> #(Int, Int) {
  case format {
    chat_format.Kind0(format) -> #(format.start, format.end)
    chat_format.Kind1(format) -> #(format.start, format.end)
    chat_format.Kind2(format) -> #(format.start, format.end)
    chat_format.Kind3(format) -> #(format.start, format.end)
    chat_format.ItemId(format) -> #(format.start, format.end)
    chat_format.QuestId(format) -> #(format.start, format.end)
    chat_format.ArticleId(format) -> #(format.start, format.end)
    chat_format.FilterMask(format) -> #(format.start, format.end)
    chat_format.ItemGuid(format) -> #(format.start, format.end)
    chat_format.NavigationPoint(format) -> #(format.start, format.end)
    chat_format.Kind11(format) -> #(format.start, format.end)
    chat_format.ItemRecord(format) -> #(format.start, format.end)
  }
}

/// Whether the format's range is one the client sends for a text of `length`
/// units: it starts within the text, and ends at or after its start and within
/// the text, but an unclosed type 1 or 2 ends at 65535 (`chat.format_bounds`). A
/// note on `chat.format_count`: a line with more than 31 formats misframes the
/// client's own message (the count is 5 bits and every format is written), which
/// no server check can tell from the bytes.
fn is_in_the_text(format format: ChatFormat, length length: Int) -> Bool {
  let #(start, end) = format_range(format)
  let can_be_unclosed = case format {
    chat_format.Kind1(..) | chat_format.Kind2(..) -> True
    chat_format.Kind0(..)
    | chat_format.Kind3(..)
    | chat_format.ItemId(..)
    | chat_format.QuestId(..)
    | chat_format.ArticleId(..)
    | chat_format.FilterMask(..)
    | chat_format.ItemRecord(..)
    | chat_format.ItemGuid(..)
    | chat_format.NavigationPoint(..)
    | chat_format.Kind11(..) -> False
  }
  start <= length
  && {
    { can_be_unclosed && end == unclosed_end }
    || { start <= end && end <= length }
  }
}

/// Whether ParseChatText makes a format of this type: it makes 1, 2, 4, 5, 6, 9,
/// 10 and 11, and no tag makes 0, 3, 7 or 8 (`0x140402720`), so the client never
/// sends those, though its reader accepts them.
fn is_made_by_the_clients_text(format: ChatFormat) -> Bool {
  case format {
    chat_format.Kind1(..)
    | chat_format.Kind2(..)
    | chat_format.ItemId(..)
    | chat_format.QuestId(..)
    | chat_format.ArticleId(..)
    | chat_format.ItemGuid(..)
    | chat_format.NavigationPoint(..)
    | chat_format.Kind11(..) -> True
    chat_format.Kind0(..)
    | chat_format.Kind3(..)
    | chat_format.FilterMask(..)
    | chat_format.ItemRecord(..) -> False
  }
}

/// 0x1d3 for the line, with the result and the line's own channel and slot.
fn chat_result_frame(
  channel_type channel_type: Int,
  channel_id channel_id: Int,
  chat_message_id chat_message_id: Int,
  result result: ChatChannelResult,
) -> Frame {
  let body =
    bit_stream.must(
      ChatResult(channel_type:, channel_id:, result:, chat_message_id:),
      chat_result.encode,
    )
  Frame(message_id: chat_result.message_id, body:)
}

/// 0x1c2 for the speaker's own line: the slot, the speaker's name, an empty realm
/// name and its unit, with no item record (opcode.0x1c2).
fn accepted_frame(
  chat chat: Chat,
  chat_message_id chat_message_id: Int,
) -> Frame {
  accepted_as(name: chat.speaker.name, chat:, chat_message_id:)
}

/// 0x1c2 showing `name` as the line's author: the speaker's own for a line, the
/// target's for a whisper (opcode.0x1c2).
fn accepted_as(
  name name: String,
  chat chat: Chat,
  chat_message_id chat_message_id: Int,
) -> Frame {
  let body =
    bit_stream.must(
      ChatLineAccepted(
        chat_message_id:,
        gm: 0,
        name:,
        realm_name: "",
        unit_id: chat.speaker.unit_id,
        premium_tier: 0,
      ),
      chat_line_accepted.encode,
    )
  Frame(message_id: chat_line_accepted.message_id, body:)
}

/// 0x1c8 for a line of another player, as this player's client shows it: the
/// design's fields, with bCrossFaction 1 when the factions differ
/// (opcode.0x1c8, chat.cross_faction).
fn line_frame(
  chat chat: Chat,
  speaker speaker: Speaker,
  line line: Line,
) -> Frame {
  let body =
    bit_stream.must(
      ChatLine(
        channel_type: chat_channel.id(line.channel_type),
        channel_id: line.channel_id,
        gm: 0,
        from_self: 0,
        auto_response: 0,
        sender_realm_id: speaker.realm_id,
        sender_character_id: speaker.character_id,
        sender_name: speaker.name,
        sender_realm_name: "",
        presence_state: 0,
        text: line.text,
        formats: line.formats,
        cross_faction: case speaker.faction_id == chat.speaker.faction_id {
          True -> 0
          False -> 1
        },
        field_14: 0,
        unit_id: speaker.unit_id,
        premium_tier: 0,
      ),
      chat_line.encode,
    )
  Frame(message_id: chat_line.message_id, body:)
}

/// What a line of local chat that the map relayed does here, while the player is in the
/// world: written as 0x1c8 when it is for this player's run.
pub fn said(chat chat: Chat, said said: Said) -> List(Effect) {
  let chat_tell.Said(speaker:, line:) = said
  case is_in_my_run(chat:, speaker:) {
    True -> [Send(line_frame(chat:, speaker:, line:))]
    False -> []
  }
}

/// What a tell from another connection does here, while the player is in the
/// world: a zone line written as 0x1c8 when it is for this player's run, top zone and
/// faction, a whisper written and answered with `Heard`, and a reply to this
/// player's own whisper written as 0x1c2 or 0x1d9, whose number is then
/// forgotten. A reply for a number not held is dropped.
pub fn told(chat chat: Chat, tell tell: Tell) -> #(Chat, List(Effect)) {
  case tell {
    chat_tell.ZoneLine(speaker:, top_zone_id:, line:) ->
      case
        speaker.character_id != chat.speaker.character_id
        && is_in_my_run(chat:, speaker:)
        && is_in_my_top_zone(chat:, top_zone_id:)
      {
        True -> #(chat, [Send(line_frame(chat:, speaker:, line:))])
        False -> #(chat, [])
      }
    chat_tell.Whisper(whisper:, speaker:, from:, line:) -> #(
      chat,
      list.append(
        case line.text {
          [] -> []
          [_, ..] -> [Send(line_frame(chat:, speaker:, line:))]
        },
        [
          Tell(
            to: step.Connection(from),
            tell: chat_tell.Heard(whisper:, name: chat.speaker.name),
          ),
        ],
      ),
    )
    chat_tell.Heard(whisper:, name:) ->
      answered(chat:, whisper:, answer: fn(pending) {
        case pending.with_text {
          True -> [
            Send(accepted_as(
              name:,
              chat:,
              chat_message_id: pending.chat_message_id,
            )),
          ]
          False -> []
        }
      })
    chat_tell.NotHeard(whisper:) ->
      answered(chat:, whisper:, answer: fn(pending) {
        undelivered(pending:, target_is_missing: True)
      })
  }
}

/// The reply to whisper number `whisper`: its watch is dropped, it is forgotten,
/// and `answer` says what the speaker is written. A number not held is a late or
/// doubled reply, which is dropped.
fn answered(
  chat chat: Chat,
  whisper whisper: Int,
  answer answer: fn(PendingWhisper) -> List(Effect),
) -> #(Chat, List(Effect)) {
  case dict.get(chat.whispers, whisper) {
    Ok(pending) -> #(
      Chat(..chat, whispers: dict.delete(chat.whispers, whisper)),
      [Unwatch(watch: whisper_watch(whisper)), ..answer(pending)],
    )
    Error(Nil) -> #(chat, [])
  }
}

/// What a pending whisper that ends undelivered is answered with: 0x1d9, except
/// an empty whisper whose target is not known to be missing, which gets no answer
/// (the client frees the slot silently after 30 s, `0x140405cb0`). The target is
/// known to be missing when no connection holds its name or it is not in the
/// world; a camp that drops the whisper knows nothing of it.
fn undelivered(
  pending pending: PendingWhisper,
  target_is_missing target_is_missing: Bool,
) -> List(Effect) {
  case pending.with_text || target_is_missing {
    True -> [Send(not_delivered_frame(pending))]
    False -> []
  }
}

fn not_delivered_frame(pending: PendingWhisper) -> Frame {
  failed_frame(
    target_name: pending.target_name,
    account: 0,
    chat_message_id: pending.chat_message_id,
  )
}

/// Whether this player is in the zone channel of this top zone now: it may have
/// changed zone since the speaker read the group's members.
fn is_in_my_top_zone(chat chat: Chat, top_zone_id top_zone_id: Int) -> Bool {
  case chat.zone {
    NoZone -> False
    InZone(top_zone_id: mine, ..) -> mine == top_zone_id
  }
}

/// Whether the speaker is in the run of the map this player is in: a line from
/// another run or map is dropped, as unit news is, since a unit id there may name
/// another unit.
fn is_in_my_run(chat chat: Chat, speaker speaker: Speaker) -> Bool {
  speaker.map == chat.speaker.map
  && speaker.incarnation == chat.speaker.incarnation
}

/// A watch ended: a whisper's target ended or was never there, so the speaker
/// is answered 0x1d9 and the whisper forgotten. `Error(Nil)` when the watch is
/// none of this chat's whispers.
pub fn watch_ended(
  chat chat: Chat,
  watch watch: WatchId,
) -> Result(#(Chat, List(Effect)), Nil) {
  let step.WatchId(number) = watch
  let whisper = number - first_whisper_watch
  case dict.get(chat.whispers, whisper) {
    Ok(pending) ->
      Ok(#(
        Chat(..chat, whispers: dict.delete(chat.whispers, whisper)),
        undelivered(pending:, target_is_missing: True),
      ))
    Error(Nil) -> Error(Nil)
  }
}

/// The client reported that the player stands in WorldZone `world_zone_id`
/// (0xF2, or 0x63A's new id): nothing for a zone under the same top zone, the
/// group changed and 0x1da written for another top zone, and the group left and
/// 0x1da with 0 for zone 0 or for a zone the table holds no row for. The client
/// accepts such a zone (0x1da names no channel for it, `0x140403670`), so it is
/// no refusal: it is no zone, and an `UnknownZone` effect says so.
pub fn world_zone_reported(
  chat chat: Chat,
  world_zone_id world_zone_id: Int,
  top_zones top_zones: TopZones,
) -> #(Chat, List(Effect)) {
  let #(zone, unknown) = zone_of(world_zone_id:, top_zones:)
  let moved = Chat(..chat, zone:)
  #(
    moved,
    list.append(unknown, case chat.zone, zone {
      NoZone, NoZone -> []
      InZone(top_zone_id: held, ..), InZone(top_zone_id: now, ..)
        if held == now
      -> []
      InZone(..), _ | NoZone, InZone(..) ->
        list.flatten([
          leave_zone(chat:),
          join_zone(chat: moved, zone:),
          [Send(zone_named_frame(zone))],
        ])
    }),
  )
}

/// What the client's 0xF2 does: the zone it reports is taken as
/// `world_zone_reported` takes it, and the first 0xF2 of the stay writes the
/// zone channel's 0x1bc again, after the zone's own writes. ChatLog registers
/// for ChatJoin after the burst's 0x1bc, which then reaches no handler; 0xF2 is
/// sent once the interface has started (`chat.zone_join_trigger`). Later 0xF2s
/// write no 0x1bc.
pub fn terrain_ready(
  chat chat: Chat,
  world_zone_id world_zone_id: Int,
  top_zones top_zones: TopZones,
) -> #(Chat, List(Effect)) {
  let #(reported, effects) =
    world_zone_reported(chat:, world_zone_id:, top_zones:)
  case reported.zone_channel_rejoined {
    True -> #(reported, effects)
    False -> #(
      Chat(..reported, zone_channel_rejoined: True),
      list.append(effects, [Send(zone_joined_frame())]),
    )
  }
}

/// What the player's camp does to its chat: it leaves `CharacterNamed` and the
/// zone channel, and stops watching each pending whisper and answers it 0x1d9, so
/// every whisper keeps its one answer and nothing reaches the player after the
/// leave.
pub fn left(chat chat: Chat) -> List(Effect) {
  list.flatten([
    [LeaveGroup(address: step.CharacterNamed(folded_name: folded(chat)))],
    leave_zone(chat:),
    list.flat_map(list.sort(dict.keys(chat.whispers), int.compare), fn(whisper) {
      case dict.get(chat.whispers, whisper) {
        Ok(pending) -> [
          Unwatch(watch: whisper_watch(whisper)),
          ..undelivered(pending:, target_is_missing: False)
        ]
        Error(Nil) -> []
      }
    }),
  ])
}

/// A sentence that says why a chat message is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  let NotDecoded(undecoded:) = refusal
  client_connection.describe_undecoded(undecoded:)
}
