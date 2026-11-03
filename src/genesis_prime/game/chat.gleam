//// A player's chat in the world: say, yell, emote, zone and whisper, a feature
//// of the game connection's rule (genesis_prime/game/connection) as the
//// player's movement and camp are. It keeps what one player's chat holds
//// (its speaker, its zone channel, its whispers waiting for a reply), decides
//// what the client's 0x1c3 and 0x1d4 are answered with, and what a line another
//// connection told this one (genesis_prime/game/chat_tell) writes; the rule
//// turns its effects into writes, tells, watches and group joins. No new
//// process and no change to the map: every send is a tell, so no connection
//// asks another.
////
//// ```
////                 say / yell / emote                       zone                                          whisper
//// speaker conn ─ Tell each viewer ─▶ viewer conns    ─ Tell ZoneChannel(run, top) ─▶ each member conn   ─ Watch + Tell CharacterNamed(n) ─▶ target conn
////  writes 0x1c2 itself                writes 0x1c8      (a pg group each conn joins)   writes 0x1c8          writes 0x1c8, Tells the speaker Heard
////                                                                                                         the speaker writes 0x1c2, or 0x1d9 on WatchEnded
//// ```
////
//// Say, yell and emote (the same rules, each on its own channel type, with id 0):
////
//// ```
//// speaker client       speaker conn                       viewer conn                        viewer client
//// 0x1c3 (t,0) id n  ─▶ checks pass (t = 4, 5 or 8)
////                      Tell(each viewer, Said(line))  ─▶ same map run? write 0x1c8 (t,0) ─▶ shows the line; a bubble on 4 and 5 if it holds the unit
////                  ◀── 0x1c2 id n, own name, own unit
//// ```
////
//// Zone:
////
//// ```
//// entry burst, after 0x61:   0x1da top(place zone),  0x1bc (9, Z, "", 0, 0, 0),  JoinGroup(ZoneChannel(run, top))
////                            Z = the map's world id; it is the same in every run, so a new entry joins the same channel
////
//// 0xF2 or 0x63A, new zone r:
////   same top as before   ─▶ keep r; nothing written
////   another top t2       ─▶ LeaveGroup(old), JoinGroup(ZoneChannel(run, t2)), write 0x1da t2   (Z stays: the client only renames)
////   r = 0                ─▶ LeaveGroup(old), write 0x1da 0
////   r has no row         ─▶ the connection ends
////
//// speaker client        speaker conn                                     each member conn
//// 0x1c3 (9,Z) id k   ─▶ checks pass
////                       Tell(ZoneChannel(run, top), ZoneLine(line))   ─▶ from itself? drop
////                                                                        another run or top than its own now? drop
////                                                                        else write 0x1c8 (9,Z)
////                   ◀── 0x1c2 id k
//// ```
////
//// Whisper:
////
//// ```
//// speaker conn                                      registry (pg)                target conn
//// 0x1d4 "B Name", realm, text, id m
////   checks pass; w = next whisper number
////   Watch(w, CharacterNamed("b name"))  ─▶ find ─▶ no member ─▶ WatchEnded(w) ─▶ 0x1d9 "B Name", 0, m
////                                              └▶ member pid: Tellable
////   Tell(CharacterNamed, Whisper(w, from, line)) ───────────────────────────────▶ in the world?
////                                                                                yes: write 0x1c8 (6,0), Tell(speaker, Heard(w, own name))
////                                                                                no:  Tell(speaker, NotHeard(w))
////   Heard(w, name)    ─▶ Unwatch(w); 0x1c2 id m, name = the target's
////   NotHeard(w)       ─▶ Unwatch(w); 0x1d9
////   WatchEnded(w)     ─▶ 0x1d9 (the target ended first)
//// ```
////
//// What the rules are, each with its evidence:
//// - **Channels the client holds.** It makes Say, Yell, Emote, Whisper and
////   AccountWhisper itself, each with id 0, and Zone only by 0x1bc, so a line
////   names a held channel or is refused (`0x140404ee0`, `ChatChannel.flags`).
//// - **No 0x1bc for a channel the client makes itself**: it would print a join
////   again (`opcode.0x1bc`, `0x140404ee0`).
//// - **The zone channel's name** is the top zone 0x1da last gave, set before
////   0x1bc, so the new channel takes it (`opcode.0x1da`, `opcode.0x1bc`).
//// - **The zone the client reports** (0xF2 once, 0x63A on each change) is the most
////   specific WorldZone the terrain names, never a parent; the server rolls it up
////   to its top zone (`opcode.0xf2`, `opcode.0x63a`, `0x140403670`,
////   `chat.zone_reach`: Jim, 2026-11-03). Zone 0 means no zone: no group, 0x1da
////   with 0 (`0x14036d040`, `0x140403670`). A zone with no row ends the
////   connection (CLAUDE.md: refuse what the client's tables would not allow).
//// - **The old value of 0x63A is not checked**: whether the client's kept value
////   outlives a camp is not read (`opcode.0x63a`); a server choice.
//// - **The speaker gets 0x1c2 and never a 0x1c8 of its own line**
////   (`opcode.0x1c2`, `opcode.0x1c8`); a whisper's 0x1c2 names the target.
//// - **The viewers are the players the speaker sees** (sight, 1024 units): the
////   client holds no say range and shows a bubble only over a unit it holds
////   (`chat.range`; the coordinator, 2026-11-03). Yell and Emote share it (Jim,
////   2026-11-03).
//// - **0x1c8's fields**: channel type and id as the line's; bGM, bSelf,
////   bAutoResponse, presence, premium tier and the unread 16-bit value 0; the
////   speaker's realm and character id and name, an empty realm name (the same
////   realm); bCrossFaction 1 only when the speaker's and the reader's
////   `faction_id` differ, on every channel; the speaker's unit id
////   (`opcode.0x1c8`, `chat.cross_faction`: Jim, 2026-11-03).
//// - **Text and formats are relayed as sent**: no format is added and no line is
////   refused for its words (`0x140c45f50`). Item links are relayed unchanged;
////   0x1c2 carries no item record (`opcode.0x1c2`).
//// - **The target's name is folded** with `string.lowercase`, the fold of the
////   database's unique index (migration 0005); a name that is not a full name by
////   rule 0 gets 0x1d9 at once with no watch (`opcode.0x1d4`,
////   genesis_prime/game/character_name). A realm name that is neither empty nor
////   the server's own, compared without case, gets 0x1d9 (`opcode.0x1d4`).
//// - **A whisper to oneself** writes 0x1c8 and 0x1c2 in the speaker's own step,
////   with no watch: a server choice.
//// - **An empty whisper** gets 0x1d9 when the target is not found, and otherwise
////   no answer: the client frees the slot silently after 30 s (`0x140405cb0`).
//// - **A pending whisper is kept by the speaker's own number `w`**, not by the
////   client's chat message id; a late or doubled reply finds no `w` and is
////   dropped. The client ignores an answer for an id it does not hold
////   (`0x140405e00`). The numbers count for the connection's life, not for one
////   stay in the world, so a reply to a whisper of an earlier stay never meets a
////   new whisper's number.
//// - **A whisper is told through its own watch** (`TellWatched`), not by the
////   address: two whispers to one name, one made before the target logged in
////   again and one after, each reach the process their own watch found.
//// - **A text is relayed as the client sent it**, in UTF-16 units: a format's
////   range is checked against the unit count, and a lone surrogate, which the
////   client's own check lets through (`0x1403e0ae0`), is neither dropped nor
////   refused.
//// - **The place's zone is server data, not a client report.** A place zone that
////   is 0 or has no WorldZone row leaves the player in no zone (0x1da with 0,
////   0x1bc still written, no zone group), with a warning for a missing row; the
////   connection does not end for it.
//// - **No timer.** Every whisper path ends in `Heard`, `NotHeard` or `WatchEnded`;
////   a target busy on an ask takes the whisper after the ask's outcome, which has
////   a deadline.
//// - **Account whispers** (bit 1) get 0x1d9 with bit 1: no account friends exist
////   (`opcode.0x1d4`).
//// - **No player info** is written or asked: no chat flow sends 0x597, 0x598 or
////   0x599 (`chat.name_lookup`).
////
//// Results and refusals: every 0x1c3 and 0x1d4 gets exactly one answer, except
//// an empty whisper to a target that is found (`opcode.0x1c2`).
////
//// | Case | Answer | Evidence |
//// |---|---|---|
//// | Text over 499 characters, a character ParseChatText drops, or an empty 0x1c3 | 0x1d3 result 17 | `0x140402720`, `vector.0x140402720.lines` |
//// | A format whose start is past its end, or past the text's end | 0x1d3 result 17 | `0x140085ca0` |
//// | A format of type 12 to 15 | the frame is unreadable: the connection ends | `0x140085ca0`; CLAUDE.md |
//// | Chat message id 0 | 0x1d3 result 17 | `0x140405cb0`: ids start at 1 |
//// | A channel the player does not hold (a wrong id, Zone before its 0x1bc, Guild) | 0x1d3 result 1 (DoesntExist) | `0x140401cb0`, `ChatChannel.flags` |
//// | A row without flag 4, or type 6 or 34 in a 0x1c3 | 0x1d3 result 3 (NoPermissions) | `ChatChannel.flags` |
//// | Party (7): the client holds it, but no group exists | 0x1d3 result 8 (NotInGroup) | `lua.ChatSystemLib.ChatChannelResult`; server choice |
//// | Support (19), Instance (32): the client holds them, the server builds none | 0x1d3 result 3, and the channel logged as unhandled once per connection | Jim, 2026-11-03 |
//// | Account whisper (bit 1) | 0x1d9 with bit 1 | `opcode.0x1d4` |
//// | A whisper with an empty text | 0x1d9 when the target is not found; otherwise no answer | `0x140405cb0` |
////
//// What each failure does:
////
//// | Step | Killed there / runs twice / times out | What happens |
//// |---|---|---|
//// | Whisper: target found, then ends before the tell lands | the tell to a dead process is dropped | the watch's DOWN is `WatchEnded(w)`: 0x1d9 |
//// | Whisper: target ends after writing 0x1c8, before `Heard` | `Heard` is sent before the end, or not at all | if sent: 0x1c2; if not: `WatchEnded` gives 0x1d9, though the target's client showed the line. Rare; stated |
//// | Whisper: takeover leaves two members of one name for a moment | `find_named` gives one process | if it is the older login, that one is ending: its DOWN gives 0x1d9, and the speaker may whisper again |
//// | Whisper: speaker ends before the reply | the reply to a dead process is dropped | nothing; the target's line stands |
//// | Whisper: target in camp's leave or in character select | not in the world | `NotHeard`: 0x1d9 |
//// | Whisper: target busy on an ask (a save) | the whisper waits in its mailbox | taken after the ask's outcome, bounded by the ask's deadline |
//// | Two players whisper each other at once | both are tells | neither waits |
//// | Say: a viewer has just been `Unwatched`, or has ended | the tell may still be sent | dropped by the VM, or written: channel (t, 0) is always held |
//// | Say: a viewer is in another map run | the line names the run | dropped |
//// | Zone: a zone change races a zone line | the speaker's tell read the group's members before a member's `LeaveGroup` took effect | the member gets the line, sees it is for another top zone or run than its own now, and drops it. A member that joined just after the read misses the line. Both are stated |
//// | Zone: the speaker's own top zone changes as it speaks | the line is told to the group of the top zone it held when it took the 0x1c3 | the line reaches that zone; the change is the next input |
//// | Zone: camp | `LeaveGroup` in the step that starts the camp's leave | no zone line reaches it after the leave; a new entry joins again |
//// | Zone: a crash of a member's connection | `pg` drops its memberships when the process ends | later lines skip it; a line sent before is dropped by the VM |
//// | Zone and whisper: `pg:join` or `pg:leave` while the registry scope is restarting | the call exits | the connection crashes; the scope's restart already restarts the listener and every connection |
//// | Zone: report 0, or a zone with no row | as above | 0: no group, 0x1da 0; no row: the connection ends |
//// | Zone: the place's zone is 0 or has no row | server data, not a report | no zone: 0x1da 0, 0x1bc, no group; a warning for no row |
//// | Zone: enter, change zone, camp, enter again | each step joins and leaves its own groups | exactly one membership per group: `join_group` skips a group the process is in |
//// | Whisper: pending when Sessions ends and the connection claims again | the player is held in the claim's wait or its ask | the reply, the watch's end and a tell are taken for every status that holds a player, so the speaker still gets 0x1c2 or 0x1d9 |
//// | Whisper: a reply to a whisper of an earlier stay | the number is not held | dropped; numbers never repeat on one connection |
//// | Whisper: two whispers to one name across the target's relog | each is told through its own watch | each reaches the process its watch found; a watch on the ending login ends and gives 0x1d9 |
//// | Whisper: `find_named` with two members | the newest member is found | pinned: the older login's end is its watcher's |

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/chat_channel.{type ChannelType}
import genesis_prime/game/chat_tell.{type Speaker, type Tell}
import genesis_prime/game/top_zone.{type TopZones}
import genesis_prime/step.{type Address, type ConnectionId, type WatchId}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/set.{type Set}

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
  /// Tell the process the open watch `watch` found, through that watch
  /// (genesis_prime/step `TellWatched`): a whisper to its target.
  TellWatched(watch: WatchId, tell: Tell)
  /// A line for the log at warning level.
  Warning(text: String)
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
}

/// Why a chat message is refused so that the connection ends: the client's own
/// code never sends it, or the client's tables hold no such zone.
pub type Refusal {
  /// A body the client's own reader would refuse, a format of type 12 to 15
  /// among them.
  NotDecoded(undecoded: client_connection.Undecoded)
  /// A reported zone other than 0 that the WorldZone table holds no row for.
  ZoneWithNoRow(world_zone_id: Int)
}

/// The zone the client reported and the top zone it falls under.
pub type Zone {
  /// Zone 0, or the player has reported none: in no zone channel.
  NoZone
  InZone(world_zone_id: Int, top_zone_id: Int)
}

/// A whisper sent and not yet answered, by the speaker's own number: the slot
/// the client keeps the line in, and the target's name as sent, which 0x1d9
/// names.
pub type PendingWhisper {
  PendingWhisper(chat_message_id: Int, target_name: String)
}

/// One player's chat while in the world: who speaks, the id of its zone channel
/// (the map's world id, the same in every run), where it stands in zones, the
/// number of its next whisper and the whispers waiting for a reply. Each whisper
/// is watched under a `WatchId` of its own, above the connection's own watches,
/// made from its number.
pub opaque type Chat {
  Chat(
    speaker: Speaker,
    zone_channel_id: Int,
    zone: Zone,
    next_whisper: Int,
    whispers: Dict(Int, PendingWhisper),
  )
}

/// The chat of a player that has just entered the world: in no zone, with no
/// whisper waiting. `zone_channel_id` is the map's world id, and `next_whisper`
/// the number of the connection's next whisper, which counts for the
/// connection's life (`next_whisper` gives it back).
pub fn new(
  speaker speaker: Speaker,
  zone_channel_id zone_channel_id: Int,
  next_whisper next_whisper: Int,
) -> Chat {
  Chat(
    speaker:,
    zone_channel_id:,
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
/// zone: 0x1da with 0, 0x1bc still written, no zone group, and a warning for a
/// zone with no row.
pub fn entered_world(
  chat _chat: Chat,
  world_zone_id _world_zone_id: Int,
  top_zones _top_zones: TopZones,
) -> #(Chat, List(Effect)) {
  panic as "built in the zone step: the entry burst"
}

/// What one chat message of the client does: its body is decoded and the line or
/// the whisper is answered, told to its readers or refused. `viewers` are the
/// connections whose players see this one, `realm_name` the server's own, and
/// `tables` the client's ChatChannel rows. A body the client's reader would
/// refuse is the refusal that ends the connection.
pub fn take(
  chat _chat: Chat,
  message _message: Message,
  body _body: BitArray,
  viewers _viewers: Set(ConnectionId),
  realm_name _realm_name: String,
  tables _tables: table_store.Tables,
) -> Result(#(Chat, List(Effect)), Refusal) {
  panic as "built in the say and whisper steps"
}

/// What a tell from another connection does here, while the player is in the
/// world: a line written as 0x1c8 when it is for this player's run, top zone and
/// faction, a whisper written and answered with `Heard`, and a reply to this
/// player's own whisper written as 0x1c2 or 0x1d9, whose number is then
/// forgotten. A reply for a number not held is dropped.
pub fn told(chat _chat: Chat, tell _tell: Tell) -> #(Chat, List(Effect)) {
  panic as "built in the say, zone and whisper steps"
}

/// A watch ended: a whisper's target ended or was never there, so the speaker
/// is answered 0x1d9 and the whisper forgotten. `Error(Nil)` when the watch is
/// none of this chat's whispers.
pub fn watch_ended(
  chat _chat: Chat,
  watch _watch: WatchId,
) -> Result(#(Chat, List(Effect)), Nil) {
  panic as "built in the whisper step"
}

/// The client reported that the player stands in WorldZone `world_zone_id`
/// (0xF2, or 0x63A's new id): nothing for a zone under the same top zone, the
/// group changed and 0x1da written for another top zone, the group left and 0x1da
/// with 0 for zone 0, and the refusal for an id with no row.
pub fn world_zone_reported(
  chat _chat: Chat,
  world_zone_id _world_zone_id: Int,
  top_zones _top_zones: TopZones,
) -> Result(#(Chat, List(Effect)), Refusal) {
  panic as "built in the zone step"
}

/// What the player's camp does to its chat: it leaves `CharacterNamed` and the
/// zone channel and stops watching each pending whisper, so nothing reaches it
/// after the leave.
pub fn left(chat _chat: Chat) -> List(Effect) {
  panic as "built in the zone and whisper steps"
}

/// A sentence that says why a chat message is refused, for the log.
pub fn describe(refusal _refusal: Refusal) -> String {
  panic as "built in the say step"
}
