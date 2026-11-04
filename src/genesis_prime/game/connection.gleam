//// The rule of one game connection: the client's connection to the game
//// server, from the hello through character select to the player in the
//// world. It decides everything; its connection shell carries it out
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
////   (same read, session key)      hand-off, then Sessions, answer
////   Taken(holder)                 watches Sessions                ─▶ sessions: Claim(account, connection)
////   Claimed                       the bytes are taken again       ─▶ store: ListCharacters(account)
////     Characters(rows)         ◀─ 0x3DC{0x0036 level}, 0x3DC{0x0117 character_list}, session key
//// 0x244{0x025C{0x025B}}        ─▶ checked                         ─▶ store: CreateCharacter(..)
////     CharacterCreated(id)     ◀─ 0x3DC{0x00DC create result}, session key
//// 0x244{0x07DD}                ─▶ world entry                     ─▶ store: LoadCharacter(account, id)
////     CharacterLoaded(row, epoch)                                 ─▶ map MapId(world, 0): Join(connection, row, place)
////       Joined(unit record)    ◀─ 0xAD, 0x262, 0x19B, 0x6BC, 0x636, 0xF1, 0x61; watches the map (watch 2)
////     NotTheAccounts, or no place ◀─ 0x3DC{0x0162 refused}       ─▶ store: ListCharacters(account)
////       Characters(rows)       ◀─ 0x0036, 0x0117, as above
//// in the world, inside 0x038C: 0x637, 0x63A, 0xD5, 0x63B, 0xF2, 0xFB, 0xFC
////                              ─▶ the movement keeps the place or refuses a command
////                                 (genesis_prime/game/movement); 0x635 is logged as unhandled
//// 0x244{0x038C{0xBF 1}}        ─▶ in the world, the camp runs  ◀─ 0x3DC{0x0092 countdown, cancel 0, bonuses 0}
//// 0x244{0x038C{0xBF 0}}        ─▶ the camp is cleared; nothing is written
//// 0x244{0x038C{0xC0}}          ─▶ camp finished; the save timer is cancelled  ─▶ store: SavePlace(account, character, epoch, sequence, place)
////     answered, whatever it is   ─▶ map run (map, incarnation): Leave(connection)
////       Left, NotRunning or EndedBeforeAnswer ◀─ 0x3DC{0x0594 bit 1, reason 0}; the map watch is dropped;
////                                the connection is in character select again
//// 0x244{0x07E0}                ─▶ the list, as at login: 0x0036, 0x0117 (no new claim)
//// every 60 s (save timer)      ─▶ store: SavePlace(account, character, epoch, sequence, place)
//// the map ends (watch 2)       ─▶ store: SavePlace   ◀─ 0x3DC{0x036A reason 8}; the connection ends
//// 0x244{0x038C{kind, inner}}  ─▶ the inner message logged as unhandled under its own id,
////                                 but the player's movement and camp messages in the world
//// 0x244{0x0241}                ─▶ logged as unhandled
//// ping 0x0, bare               ◀─ pong 0x1, bare
//// Sessions: TakenOver          ─▶ in the world, store: SavePlace  ◀─ 0x3DC{0x036A reason 19}, session key; the connection ends
//// ```
////
//// - **The hello** is the first thing written: any game server message before
////   it ends the client's login with 0x801B2 (0x1400370d0). It is the
////   connection's first input, `OwnEvent(Accepted)`, that writes it, in the game
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
////   the hand-off's and Sessions' answers, and 0x038C and 0x0241 after the
////   store's.
//// - **The claim** makes this connection the account's one session
////   (genesis_prime/account_session). It follows the hand-off's answer, since the
////   account is known only then, and comes before the list, so a client that
////   reaches character select holds the slot. The rule opens its one watch
////   on Sessions (watch 1) with each claim. Sessions answers `Claimed` to the
////   newest login's claim, sending the previous holder `TakenOver` first, and
////   answers `TakenOver` to a claim older than the holder's.
//// - **Taken over.** `Woken(TakenOver)`, when the connection holds the slot or
////   is claiming it again, or Sessions' answer `TakenOver` to a claim, writes
////   0x036A reason 19 (AccountDisconnected) under
////   the cipher the connection holds, logs the takeover at info and ends the
////   connection, after the save of the player's place when one is in the world. The client drops to its error screen and shows "This account
////   has been disconnected" (0x1400168a0, which only picks the text by the
////   reason). The message is taken between steps, never while an ask is out:
////   a takeover that arrives while the connection waits on an ask that then
////   fails is never taken, because the failure ends the connection, so that
////   client gets the failure's text (reason 8) and not the account's. Both
////   texts end the connection; taking a delivery during an ask would make the
////   shell decide by a message's content.
//// - **Sessions ending.** When the watch on Sessions ends (`WatchEnded`) the
////   connection waits `claim_wait_ms` on a timer, since a restarted Sessions
////   is not yet there, then claims again (`TimerFired`), with the frames it
////   holds waiting for the answer; the client sees nothing. The end of a watch
////   is taken only between steps, when no ask of character select is out and
////   its state is at rest, so the connection resumes in a new one. When a
////   newer login of the account claimed first, Sessions answers the claim
////   `TakenOver` and the connection ends as a takeover does. A claim that finds Sessions not running (the
////   outcome `NotRunning`) drops its watch and waits again, up to
////   `claim_retries` times, before the client is told the server failed. A
////   claim Sessions does not answer, or that ends before its answer, is that
////   failure at once. The wait is its own status (`WaitingToClaim`), so the
////   timer's firing is taken only there, and an answer only while the claim's
////   ask is out (`ClaimingSession`); either in the other is a bug.
//// - **The character list and creating a character** are character select's
////   own feature (genesis_prime/game/character_select): it makes its own store
////   asks and takes the store's answers, and the rule turns its effects into
////   writes in the game wrapper, log lines and the ask. The rule decodes what
////   the client sent into typed values first: 0x025C carries the whole frame
////   of 0x025B (opcode.0x25c), and 0x07DD is the client's play request. The
////   failures every ask shares (no answer, or the store unavailable) are the
////   rule's, so a request added to character select adds no status here.
//// - **The server never ends a connection after the hello without telling
////   the client**, which waits for the list with no timeout and would stay on
////   its prompt otherwise (lua.Character.OnCharacterList): 0x036A in the game
////   wrapper under the cipher the connection holds at that moment, then the
////   close. Every reason drops the client to its error screen and only picks
////   the text (0x1400168a0):
////   - reason 19, "This account has been disconnected", when the hand-off
////     does not hold the session key (never put, taken, or expired), with a
////     warning naming the peer;
////   - reason 19 again, with an info line, for a connection taken over by a
////     newer login of its account;
////   - reason 8, "Lost connection with user server.", for the server's own
////     failure, with a warning: the hand-off, Sessions or the store is not
////     running, ended before it answered, gave no answer by the settings' ask
////     deadline, or the store answers `Unavailable`; and with no log for the
////     server stopping, whether it is waiting on an ask (`StoppedWaiting`) or
////     not (`Stopping`).
////   A client that breaks the protocol, closes, or whose socket fails is not
////   told: the rule logs the break and ends the connection.
//// - **A process dying or a deadline passing.** The rule holds no process:
////   a restart of the hand-off, Sessions or the store is seen only as an ask's
////   outcome (`NotRunning`, `EndedBeforeAnswer`), or, for Sessions, as the end
////   of its watch; a late answer gives the rule no input, a late `Claimed` too,
////   which leaves the slot claimed by a connection that has ended and is freed
////   by Sessions' watch on it. A crash of the connection's own process
////   drops the client, which connects again from the login.
//// - **Entering the world** is world entry's own feature
////   (genesis_prime/game/world_entry), as character select is: it asks the
////   store and the map, and the rule turns its effects into writes, the asks
////   and its watch on the map. The map's ask goes through Maps, which starts
////   the map when it is not running (genesis_prime/world_map/registry); a map
////   that cannot be reached, ends before its answer or gives none in time
////   ends the connection with reason 8, as the store does.
//// - **In the world** the connection watches its map (watch 2): the map's
////   end, a crash or a restart of Maps, ends the connection with 0x036A
////   reason 8, since the player is gone from the world. The map watches the
////   connection, so a connection that ends leaves its map. A takeover ends
////   it with reason 19, as in character select.
//// - **Sessions ending in the world.** The claim again keeps where the
////   client is: character select, or the player in the world, whose save timer
////   is cancelled while the claim waits and started again when it is answered.
//// - **Which feature takes a message** is the routing table's row
////   (genesis_prime/game/routing): the id, how it arrives, the stage it is taken
////   in and the feature's own kind of message. The connection keeps the shared
////   part (the hello, the re-key, the claim, the asks, the saves and every
////   ending); each feature decodes its messages and returns its decisions as
////   effects the connection carries out: a write, a warning, an ask of the
////   store or the map, the watch on the map, the save timer, and the leave of
////   the world (`Decided`), or the refusal that ends the connection; an accepted
////   0x0637 also tells the map that the player moved (`Tell`, which the shell
////   sends with no answer). The player
////   camps (genesis_prime/game/camp), moves (genesis_prime/game/movement), picks
////   a character (genesis_prime/game/character_select) and plays one
////   (genesis_prime/game/world_entry) by those rows.
//// - **A 0xC0 leaves the world in this order**: the save timer is cancelled and
////   the place saved (`SavingPlace` with `Camped`), the map's run is asked to
////   take the player out (`LeavingMap`; the 0x355 of its unit is sent to each
////   viewer in the step that asks), the watch on the map is dropped and
////   0x0594 is written with the bit set and reason 0 (opcode.0x594). The client
////   can pick a character only after 0x0594, so a play never meets a save still
////   out. The client's 0x07E0 is then answered as at login, on the same
////   connection and claim (opcode.0x594.character_select).
//// - **A save or a leave that fails goes on** when the player is no longer in a
////   map: a save with no answer is a warning, and a leave answered `Left`, to a
////   map that is not running or that ended before its answer is done. A leave
////   with no answer in time, or whose find Maps does not answer in time
////   (genesis_prime/world_map/registry `ask_run`), ends the connection with
////   0x036A reason 8: the map may still hold the player, and drops it by its
////   watch on the connection. The server stopping, and an answer that is none
////   the ask's, end it too, with no second save.
//// - **The connection stays the player's process** through a camp: the client
////   asks for nothing that needs a character to outlive its connection, and
////   no text says how long one stays (`LocalizedEnum.8879`). The camp is the
////   connection's own state, so a character is in the world only while its
////   connection is.
//// - **A refused message** (a command the client's own code never sends, a move
////   speed setting above 2, or a body the client's reader would refuse) ends the
////   connection: an error line, the last good place saved, nothing written.
//// - **Saving the place.** The connection is the player's own process, so it
////   keeps the place and saves it: every `movement.save_period_ms`, and when
////   any end reaches a connection that holds a player in the world or claims
////   again with one (`end_with`), whatever the cause: the client closing, a
////   socket that fails, a takeover, the map's end, the server stopping, a
////   client that breaks the protocol, a timer or watch the rule did not open. A
////   save is one store ask with the settings' deadline, and the connection
////   takes no other input while it waits. The 60 s save leaves the player in the
////   world whatever the answer, a warning when there is none; an end writes its
////   notice and stops when the answer comes, whatever it is, so a store that does
////   not answer cannot keep a connection open. Its status stays `SavingPlace`, so
////   no input after it, a failed write of the notice among them, saves a second
////   time. The server's stop gives the save the shorter of the settings' deadline
////   and the time its own deadline leaves, and asks nothing when none is left
////   (a warning says the place was not saved). The rate and held-bytes limits end
////   the connection inside `client_connection` and save nothing: the last 60 s
////   save stands, which is all a crash of the connection's process leaves too.
////   A stop that cuts the claim short with the player in the world goes back to
////   the world, and the stop that follows saves.
//// - **0x038C** carries a 5-bit kind in its first byte, then exactly one whole
////   frame (0x14007e180, opcode.0x38c): every message the client sends in the
////   world is inside one (0x1403f4900 nests 0x637 in it). The inner message is
////   routed by the table, and logged as unhandled under its own id when it has
////   no row at the stage. A body that holds no whole frame, or
////   bytes after it, is one the client never writes, and ends the connection.
//// - **Other players' units.** The map decides who sees whom
////   (genesis_prime/world_map/map) and tells the connection of each player in
////   it, as the message `SentByMap`, who sees its player (`Watched(by)` when a
////   player comes to see it, `Unwatched(by)` when one stops), and `Gone(unit)`
////   when a player's connection has ended. The connection keeps
////   the connections that see its player as its viewers, in the player's
////   `Entered`, and sends everything about its own unit to them itself, as
////   `SentByPeer` through the registry (the same path the map's sends take,
////   `genesis_prime/server`'s `connection_reach`); the map sends no unit:
////
////   ```
////   owner's connection (player in the world)                       viewer's connection             client
////   Watched(by v) from the map ─▶ Tell(v, Appeared(0x262 at its place))  ─▶ writes 0x262 if not shown ─▶ the unit is created
////   0x637 accepted             ─▶ Tell(map, Moved(place)); Tell(each viewer, Moving(0x638)) ─▶ writes 0x638 if shown ─▶ the unit moves
////   Unwatched(by v)            ─▶ Tell(v, Removed)                    ─▶ writes 0x355 if shown   ─▶ the unit is removed
////   its camp (0xC0)            ─▶ Tell(each viewer, Removed), then Leave
////   its connection ends        ─▶ nothing: the map sends each viewer Unwatched, and every player Gone(unit)
////                                                                     Gone(unit) ─▶ writes 0x355 if shown, and the unit is gone
////   ```
////
////   The shell takes a send between steps, after an ask's outcome and the step it
////   starts, and entering the world writes its whole burst in the one step that
////   takes the map's `Joined`, so no send reaches the connection between the
////   answer and the end of the burst: no status holds sends during entry, and a
////   0x262 of another unit never lands while the client waits on 0x636 (0x1403d9760).
////   A send that arrives while any ask is out, a save among them, waits for its
////   outcome. With no player in the world (after the camp's leave, say) a send is
////   dropped and nothing is written for other units; a player that enters again
////   starts with no viewers and no units shown, and the map's new join sends it a
////   `Watched` for each player in sight, whose owners then send it their 0x262s.
//// - **What a viewer writes** is what its client can take, kept by the player's
////   `Entered` for the current run of the map: `shown`, the units it has written
////   a 0x262 of and not a 0x355, and `gone`, the units the map reported `Gone`. A
////   0x262 is written for a unit not shown and not gone, and it is then shown (the
////   client keeps one unit per id until its 0x355, and a unit id 0 would be the
////   controlled unit, 0x1403d9760); a 0x638 and a 0x355 are written for a shown
////   unit only, a 0x355 ends it; `Gone` writes a 0x355 for a shown unit and marks
////   the unit gone, so a 0x262 from the owner that ended, which lands after it,
////   shows no ghost. A message names the map and the run of the map it is about,
////   and one for another run or map is dropped: the unit id there may name
////   another unit.
//// - **A creature's unit** reaches a viewer the same way, as news from the
////   creature's own process (`CreatureAppeared`, then `Removed`), and is shown,
////   removed and marked gone by the same rules: the viewer neither knows nor asks
////   whose process owns a unit (genesis_prime/world_map/creature).
//// - **Order.** For one viewer, an owner's 0x262, 0x638s and 0x355 are that
////   owner's messages only, which the BEAM delivers in the order sent (it orders
////   the signals of one sender to one receiver); the map's `Watched` and
////   `Unwatched` to one owner are the map's only, so the owner's viewers change in
////   order. The one case two senders speak of a unit, `Gone` after the owner has
////   ended, is the viewer's `gone`.
//// - **A unit's 0x638 and 0x262** are stamped with the map's clock: the connection
////   holds the origin `Joined` carried and takes the time of the input from it
////   (`world_map/map.server_time`, mod 2^32), in the order it takes its inputs, so
////   for a viewer the times of one unit only go forward. More than 31 commands are sent as several 0x638s
////   in order, each of at most 31 (its count is 5 bits, opcode.0x638). A move with
////   no viewer sends none, and one with nothing to relay sends none and tells the
////   map nothing. A viewer that has just been `Unwatched`, or gone, may still be
////   sent one: a send to a process that has ended is dropped, and one for a unit
////   the viewer does not show is dropped by it.
//// - **Chat** is a feature of its own (genesis_prime/game/chat): the player's
////   `Entered` keeps its chat, the routing table sends 0x1c3 and 0x1d4 to it from
////   inside 0x038C with the player in the world, and 0xF2 and 0x63A give it the
////   WorldZone id the client reports (the first 0xF2 of a stay also writes the
////   zone channel's 0x1BC again). The rule turns its effects into writes,
////   tells (`TellChat`, to a viewer's `Connection`, to a `ZoneChannel` and to a
////   whisper's `CharacterNamed`), the watch on a whisper's target and the
////   `JoinGroup` and `LeaveGroup` of the player's groups. What other
////   connections tell it (`SentByChat`) is taken by the chat with the player in
////   the world: a whisper that finds none is answered `NotHeard`, and any other
////   tell is dropped. The player joins its groups as the entry burst is written
////   and leaves them in the step that starts the camp's leave, so a new entry
////   joins again (genesis_prime/game/chat has the sequences, the refusals and
////   the failure table).
//// - **Casts** are a feature of their own (genesis_prime/game/cast): the player's
////   `Entered` keeps its cast state, the routing table sends 0x9a, 0x4DB and 0x801 to it
////   from inside 0x038C with the player in the world, and the timers `cast.owns`
////   names are its (`other_timer_fired`). The rule turns its
////   effects into writes to the caster, tells of news to the viewers
////   (`CastStarted`, `CastWent`, `CastFinished`, in the run of the player's map),
////   timers and log lines. A viewer writes a 0x7ff only for a caster it shows, and
////   a go or finish only for a start it wrote (`casts_written`, by cast id, kept
////   with the caster's unit id, so a removed unit's casts are finished before its
////   0x355 is written).
//// - **Strikes** are a feature of their own (genesis_prime/game/strike): a go the cast
////   rule asks for (`cast.Strike`) selects its targets from the units the client
////   shows, draws the caster's rolls from the connection's seed, and tells each
////   creature a `TellStrike` through the creature registry with no watch. The creature
////   answers by a send, taken as `SentByTarget`; the round closes when each answer is in
////   or the one strike timer, `strike.strike_timer`, fires for its deadline, and the
////   closed round is the cast rule's `went`. A viewer writes a creature's health and
////   death (`Health`, `Died`) for a creature it shows, whatever its own casts.
//// - **Network messages** are answered before any wrapper is read: a ping 0
////   gets a pong 1 (opcode.0x0), a pong or close notice nothing
////   (genesis_prime/client_connection, genesis_prime/connection/network_message).
//// - **Unhandled messages** are logged as a warning the first time an id comes
////   on the connection, and at debug for each repeat of it, since the client
////   sends some of them again and again. A message with no row at the stage is
////   unhandled: the movement and camp messages are taken only with the player in
////   the world, and in any other state they are.
//// - **Log lines** carry the connection, the peer and the account once the
////   hand-off has named it, and in the world the map and the character.
//// - **Limits.** Each ends the connection with nothing written, since a
////   client past one is no client: a frame longer than 131,070 bytes
////   (MessageSizeLimit 0x140335ec0), refused at its length field; more than
////   `client_connection.held_limit` bytes not yet taken, which an ask or the
////   claim's wait lets pile up, with an error log; and more frames than the
////   rate allows (`Settings.rate`, a bucket counted in whole frames when they
////   are taken), with a warning.
//// - **Out of order.** A frame the client's reader would refuse ends the
////   connection, as does a 0x025C that holds no 0x025B or a 0x025B or 0x07DD
////   whose body is cut; a whole frame of a message the rule does not take,
////   0x038C with 0x082D inside it, 0x0241 and any other, is logged as
////   unhandled and the connection goes on (opcode.0x241).

import genesis_prime/account_session
import genesis_prime/client_connection.{
  type Answer, type Bucket, type Link, type Message, type Request, AskHandOff,
  AskMap, AskMapRun, AskSessions, AskStore, Asking, Broken, Bytes, Connect,
  Continue, Done, FromHandOff, FromMap, FromSessions, FromStore, Inside,
  Otherwise, SentByChat, SentByFoe, SentByMap, SentByPeer, SentBySessions,
  SentByTarget, Settled, TellChat, TellMoved, TellPeer,
}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{type Frame, type FrameError, Frame}
import genesis_prime/connection/hello
import genesis_prime/game/area.{Pose}
import genesis_prime/game/camp
import genesis_prime/game/cast
import genesis_prime/game/character_select
import genesis_prime/game/chat
import genesis_prime/game/chat_channel
import genesis_prime/game/chat_tell
import genesis_prime/game/damage
import genesis_prime/game/movement
import genesis_prime/game/rating
import genesis_prime/game/routing
import genesis_prime/game/shown.{ShownCreature, ShownPlayer}
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike
import genesis_prime/game/strike_tell.{type Answered}
import genesis_prime/game/top_zone
import genesis_prime/game/world_entry
import genesis_prime/game_settings.{type GameSettings}
import genesis_prime/hand_off.{type Holder, SessionKey, Take}
import genesis_prime/login/guid
import genesis_prime/message/bit_stream
import genesis_prime/message/create_character
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/disconnect_reason.{
  type DisconnectReason, AccountDisconnected, LostUserServer,
}
import genesis_prime/message/game_hello_reply
import genesis_prime/message/leave_world.{LeaveWorld}
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_death_state.{UnitDeathState}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_health.{UnitHealth}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/world_message
import genesis_prime/step.{
  type About, type ConnectionEffect, type ConnectionEvent, type ConnectionId,
  type ConnectionInput, type ConnectionRule, type ConnectionStep, type Effect,
  type Event, type Now, type Outcome, type TimerId, type WatchId, About,
  CancelTimer, Effects, LogDebug, LogInfo, LogWarning, OwnEffect, OwnEvent,
  Sessions, StartTimer, Stop, Stopping, TimerFired, TimerId, Unwatch, Watch,
  WatchEnded, WatchId, Woken, Write,
}
import genesis_prime/store
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

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
    /// The game's own settings: the characters an account may have and the
    /// camp's countdown (genesis_prime/game_settings).
    game: GameSettings,
    /// The realm's name, the one a whisper's realm name must equal, compared
    /// without case, for the whisper to be for this realm (opcode.0x1d4).
    realm_name: String,
    /// The client's game tables, which a create request and the list's body
    /// visuals are read from.
    tables: table_store.Tables,
    /// How long an ask to the hand-off, Sessions or the store may take.
    ask_deadline_ms: Int,
    /// How fast the client may send its frames
    /// (`genesis_prime/client_connection.Bucket`).
    rate: Bucket,
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
    /// The ids of the messages already logged as unhandled on this
    /// connection: the first of an id is a warning, a repeat a debug line.
    unhandled_logged: Set(Int),
    /// The kinds of movement command already named in a log line as not
    /// relayed to other players on this connection.
    unrelayed_logged: Set(Int),
    /// The ids of the chat channel types already logged as unhandled on this
    /// connection (`chat.Unhandled`): once for each.
    unhandled_channels_logged: Set(Int),
    /// The WorldZone ids already logged as having no row on this connection.
    unknown_zones_logged: Set(Int),
    /// The number of the next whisper the connection's players make: it counts
    /// for the connection's life, so a reply to a whisper of an earlier stay in
    /// the world never meets a new whisper (genesis_prime/game/chat).
    next_whisper: Int,
    status: Status,
  )
}

/// The connection's one status.
type Status {
  /// The hello is sent; waiting for 0x058F.
  AwaitingHelloReply
  /// The hand-off is asked to take the session key.
  TakingSessionKey
  /// Sessions is asked to make the connection the account's session, and its
  /// answer is awaited. `resume` is where the client is after the answer: a
  /// new character select for the first claim; a new one again, or its player
  /// in the world, for a later one. `retries` is how many times Sessions was
  /// not running for this claim.
  ClaimingSession(holder: Holder, resume: Resume, retries: Int)
  /// The connection waits on the claim timer before it asks Sessions again,
  /// with `resume` and `retries` as `ClaimingSession` holds them. No ask is
  /// out, so no answer is taken here.
  WaitingToClaim(holder: Holder, resume: Resume, retries: Int)
  /// The session key was held for `holder` and Sessions holds the account's
  /// slot for this connection; the client is in character select, which holds
  /// its own state, asks the store itself and says when its answer is awaited.
  InCharacterSelect(holder: Holder, select: character_select.State)
  /// The client asked to play a character; world entry asks the store, then
  /// the map. A refusal hands the client back to a new character select.
  EnteringWorld(holder: Holder, entry: world_entry.State)
  /// The player is in the world, in `entered`'s map, which the connection
  /// watches (`map_watch`).
  InWorld(holder: Holder, entered: world_entry.Entered)
  /// The store is asked to save where the player stands, and its answer is
  /// awaited; `then` says what follows it. A connection in this status ends
  /// without a second save: the save out is the one its end waits for.
  SavingPlace(holder: Holder, entered: world_entry.Entered, then: AfterSave)
  /// The camp's place is saved and the map's run is asked to take the player
  /// out (`world_map/map.Leave`), and its answer is awaited. A connection in this
  /// status ends without a save: the place is already saved, and the map drops
  /// a player whose connection ends.
  LeavingMap(holder: Holder, entered: world_entry.Entered)
}

/// What a save of the player's place is for, so its answer knows what comes
/// next.
type AfterSave {
  /// The save the timer asked for: the player goes on playing.
  Playing
  /// The connection ends once the save is answered, whatever the answer:
  /// `notice` is written first when there is one, then the connection stops.
  Leaving(notice: Option(DisconnectReason))
  /// The player camps: once the save is answered, whatever the answer, the map's
  /// run is asked to take the player out (`LeavingMap`).
  Camped
}

/// Where a claim made again after Sessions ended puts the client back. The
/// shell takes the end of a watch only between steps, so no ask of character
/// select is out then, and a character select resumes as a new one.
type Resume {
  ResumeSelect
  ResumeWorld(entered: world_entry.Entered)
}

/// How long a connection waits before it claims again after Sessions ended or
/// was not running. A restarted Sessions is started by its supervisor at once,
/// so a short wait finds it; the client's screen shows nothing meanwhile.
const claim_wait_ms = 100

/// How many times a claim that finds Sessions not running is made again.
/// With the wait, it bounds how long a client waits on its prompt for a
/// Sessions that does not come back: half a second, then it is told the
/// server failed, as for the store.
const claim_retries = 5

/// The watch on Sessions: the connection's only one. A watch that ends is
/// forgotten by the shell, and one dropped with `Unwatch` leaves nothing behind,
/// so the id is free whenever a claim opens it again, and a watch left open is
/// caught by the shell's refusal of an id already open.
const sessions_watch = WatchId(1)

/// The watch on the player's map, open while the player is in the world.
const map_watch = WatchId(2)

/// The timer a connection waits on before it claims again; one runs at a
/// time.
const claim_timer = TimerId(1)

/// The timer that saves the player's place every `movement.save_period_ms`
/// while the player is in the world.
const save_timer = TimerId(2)

/// The longest the rule can hold the client's frames untaken, given how long
/// an ask may take: frames that arrive while an ask is out or the claim waits
/// are counted against the rate only when the answer comes. The longest run
/// without a frame taken is two asks in a row (the hand-off's then the claim,
/// or the store's then the map's) and the waits between the claims a Sessions
/// that is not running gets, `claim_retries` of `claim_wait_ms`. A rate's burst
/// must hold what a client sends at its rate through that
/// (`genesis_prime/client_connection.bucket`).
pub fn longest_wait_ms(ask_deadline_ms ask_deadline_ms: Int) -> Int {
  2 * ask_deadline_ms + claim_wait_ms * claim_retries
}

/// The rule as its connection shell runs it.
pub fn rule(
  settings: Settings,
) -> ConnectionRule(Settings, State, Request, Message, Answer) {
  step.Rule(name: rule_name, settings:, new:, step:)
}

/// The rule's first state.
pub fn new(settings: Settings) -> State {
  NotAccepted(settings:)
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: ConnectionInput(Message, Answer),
) -> #(State, ConnectionStep(Request)) {
  case state {
    NotAccepted(settings:) ->
      case
        client_connection.hear(input.event, about: step.no_one, stopping: fn() {
          []
        })
      {
        Connect(connection:, peer:, seed:) -> #(
          Connected(Session(
            settings:,
            link: client_connection.link(
              connection:,
              peer:,
              seed:,
              bucket: settings.rate,
              now: input.now,
            ),
            pending: <<>>,
            cipher: cipher.base(),
            unhandled_logged: set.new(),
            unrelayed_logged: set.new(),
            unhandled_channels_logged: set.new(),
            unknown_zones_logged: set.new(),
            next_whisper: 1,
            status: AwaitingHelloReply,
          )),
          Effects([OwnEffect(Write(hello_bytes(settings)))]),
        )
        Bytes(..) | client_connection.Outcome(..) -> #(
          state,
          client_connection.before_accepted(rule: "game"),
        )
        Otherwise(step:) -> #(state, step)
      }
    Connected(session:) ->
      connected(session:, now: input.now, event: input.event)
  }
}

fn connected(
  session session: Session,
  now now: Now,
  event event: Event(ConnectionEvent(Message, Answer)),
) -> #(State, ConnectionStep(Request)) {
  case event {
    OwnEvent(Woken(message: SentBySessions(message:))) ->
      settled(handled: sessions_sent(session:, now:, message:), now:)
    OwnEvent(Woken(message: SentByMap(message:))) ->
      settled(handled: map_sent(session:, now:, message:), now:)
    OwnEvent(Woken(message: SentByPeer(news:))) ->
      settled(handled: peer_sent(session:, news:), now:)
    OwnEvent(Woken(message: SentByChat(tell:))) ->
      settled(handled: chat_sent(session:, tell:), now:)
    OwnEvent(Woken(message: SentByTarget(answered:))) ->
      settled(handled: target_sent(session:, now:, answered:), now:)
    OwnEvent(Woken(message: SentByFoe(fight:))) ->
      settled(handled: foe_sent(session:, now:, fight:), now:)
    WatchEnded(watch:) ->
      settled(handled: watch_ended(session:, now:, watch:), now:)
    OwnEvent(TimerFired(timer:)) if timer == save_timer ->
      settled(handled: save_due(session:, now:), now:)
    OwnEvent(TimerFired(timer:)) ->
      settled(handled: other_timer_fired(session:, now:, timer:), now:)
    OwnEvent(step.PeerClosed)
    | OwnEvent(step.ReadFailed(failure: step.Closed))
    | OwnEvent(step.WriteFailed(failure: step.Closed)) ->
      leaves_or_hears(
        session:,
        now:,
        event:,
        ending: Ending(log: None, notice: None),
        within_ms: session.settings.ask_deadline_ms,
      )
    OwnEvent(step.ReadFailed(failure:))
    | OwnEvent(step.WriteFailed(failure:)) ->
      leaves_or_hears(
        session:,
        now:,
        event:,
        ending: Ending(
          log: Some(#(LogWarning, client_connection.socket_failed_text(failure))),
          notice: None,
        ),
        within_ms: session.settings.ask_deadline_ms,
      )
    Stopping(deadline_ms:) ->
      leaves_or_hears(
        session:,
        now:,
        event:,
        ending: Ending(log: None, notice: Some(LostUserServer)),
        within_ms: int.min(
          session.settings.ask_deadline_ms,
          deadline_ms - now.monotonic_ms,
        ),
      )
    OwnEvent(step.Accepted(..))
    | OwnEvent(step.Read(..))
    | OwnEvent(step.Answered(..)) -> heard(session:, now:, event:)
  }
}

/// An input that ends the connection when it is taken by one that holds a
/// player in the world: the end is `ending`, after the save of the player's
/// place within `within_ms`. In any other state it is the same input every
/// client connection rule takes (`heard`). The game rule takes these inputs
/// itself, before `client_connection.hear`, which ends the connection at once
/// for every rule.
fn leaves_or_hears(
  session session: Session,
  now now: Now,
  event event: Event(ConnectionEvent(Message, Answer)),
  ending ending: Ending,
  within_ms within_ms: Int,
) -> #(State, ConnectionStep(Request)) {
  case holds_a_player(session.status) {
    Some(_) ->
      settled(handled: end_with(session:, now:, ending:, within_ms:), now:)
    None -> heard(session:, now:, event:)
  }
}

/// An input the client's side or an ask's outcome gives, sorted by what every
/// client connection rule does alike.
fn heard(
  session session: Session,
  now now: Now,
  event event: Event(ConnectionEvent(Message, Answer)),
) -> #(State, ConnectionStep(Request)) {
  case
    client_connection.hear(event, about: about_of(session), stopping: fn() {
      server_stopping(session)
    })
  {
    Bytes(bytes:) ->
      case
        client_connection.hold(
          session:,
          held: session.pending,
          bytes:,
          about: about_of(session),
        )
      {
        Error(handled) -> settled(handled:, now:)
        Ok(pending) -> {
          let session = Session(..session, pending:)
          case asking(session.status) {
            // A frame is taken only once the answer to the ask in flight comes.
            True -> #(Connected(session), Effects([]))
            False ->
              client_connection.drive(session:, flow: flow(now), carried: [])
          }
        }
      }
    client_connection.Outcome(outcome:) ->
      settled(handled: answered(session:, now:, outcome:), now:)
    Connect(..) -> #(
      Connected(session),
      client_connection.accepted_again(about: about_of(session), rule: "game"),
    )
    Otherwise(step:) -> #(Connected(session), step)
  }
}

/// What an input decided, carried out as the rule takes the client's frames at
/// the time of the input.
fn settled(
  handled handled: client_connection.Handled(Session),
  now now: Now,
) -> #(State, ConnectionStep(Request)) {
  client_connection.settle(handled:, flow: flow(now), carried: [])
}

/// Whether an ask is in flight, so the frames after the one that asked wait.
fn asking(status: Status) -> Bool {
  case status {
    TakingSessionKey
    | ClaimingSession(..)
    | WaitingToClaim(..)
    | EnteringWorld(..)
    | SavingPlace(..)
    | LeavingMap(..) -> True
    InCharacterSelect(select:, ..) -> character_select.waiting(select)
    AwaitingHelloReply | InWorld(..) -> False
  }
}

/// How the rule takes the client's frames, at the time of an input.
fn flow(now: Now) -> client_connection.Flow(Session, Frame, FrameError, State) {
  client_connection.Flow(
    pending: fn(session: Session) { session.pending },
    take: frame.take,
    taking: fn(session, whole, rest) {
      handle(session: Session(..session, pending: rest), now:, frame: whole)
    },
    refused: fn(session, error) {
      end_for(
        session:,
        now:,
        text: "the bytes are no frame: " <> frame.describe(error),
      )
    },
    charged: fn(session) {
      client_connection.charge(
        session:,
        link: session.link,
        now:,
        about: about_of(session),
        relinked: fn(link) { Session(..session, link:) },
      )
    },
    connected: Connected,
  )
}

/// The hello, in the game wrapper under the base key (genesis_prime/connection/hello).
fn hello_bytes(settings: Settings) -> BitArray {
  client_connection.wrapped(
    GameWrapper,
    hello.frame(realm_id: settings.realm_id),
    cipher.base(),
  )
}

/// A message in the game wrapper under the cipher the connection holds.
fn to_client(
  session: Session,
  inner: Frame,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(
    Write(client_connection.wrapped(GameWrapper, inner, session.cipher)),
  )
}

/// 0x036A with the reason, in the game wrapper under the cipher the
/// connection holds, so the client leaves its prompt.
fn notice(
  session session: Session,
  reason reason: DisconnectReason,
) -> Effect(ConnectionEffect(Request)) {
  let assert Ok(body) = disconnect_notice.encode(DisconnectNotice(reason:))
    as "a reason is within 5 bits"
  to_client(session, Frame(disconnect_notice.message_id, body))
}

/// What a connection writes before it ends when the server stops: the notice
/// that the server failed, so the client leaves its prompt. A stop is no
/// failure, so no log line comes with it.
fn server_stopping(
  session: Session,
) -> List(Effect(ConnectionEffect(Request))) {
  [notice(session:, reason: LostUserServer)]
}

/// What one whole frame does: the network layer's messages first, then the
/// message in the client's wrapper.
fn handle(
  session session: Session,
  now now: Now,
  frame whole: Frame,
) -> client_connection.Handled(Session) {
  case
    client_connection.open(
      session:,
      about: about_of(session),
      server: "game",
      frame: whole,
      cipher: session.cipher,
    )
  {
    Settled(handled:) -> handled
    Inside(inner:) -> inner_message(session:, now:, inner:)
    Broken(text:) -> end_for(session:, now:, text: text)
  }
}

/// Where the connection stands when a message of the client's reaches it:
/// what the message's feature needs of the status.
type Standing {
  /// The hello is sent; 0x058F is awaited.
  Greeting
  /// The client is in character select, for `holder`'s account.
  Selecting(holder: Holder)
  /// The player is in the world.
  Present(holder: Holder, entered: world_entry.Entered)
  /// An ask is out or the claim waits, so no frame is taken: `text` is why
  /// that frame ends the connection.
  Busy(text: String)
}

fn standing(status: Status) -> Standing {
  case status {
    AwaitingHelloReply -> Greeting
    InCharacterSelect(holder:, ..) -> Selecting(holder:)
    InWorld(holder:, entered:) -> Present(holder:, entered:)
    TakingSessionKey
    | ClaimingSession(..)
    | EnteringWorld(..)
    | SavingPlace(..)
    | LeavingMap(..) -> Busy(text: "a frame was taken while an ask was out")
    WaitingToClaim(..) ->
      Busy(text: "a frame was taken while the claim waited on its timer")
  }
}

/// What the message in the client's wrapper does: the routing table says
/// which feature takes it at the connection's stage (genesis_prime/game/routing),
/// and the feature decides. Before the hello reply any other message ends the
/// connection; at any later stage a message with no row is logged as unhandled.
fn inner_message(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case standing(session.status) {
    Busy(text:) -> end_for(session:, now:, text:)
    Greeting -> routed(session:, now:, inner:, stage: routing.BeforeHelloReply)
    Selecting(..) ->
      routed(session:, now:, inner:, stage: routing.AtCharacterSelect)
    Present(..) -> routed(session:, now:, inner:, stage: routing.AtWorld)
  }
}

/// A message in the client's wrapper at a stage, given to the feature the
/// table names, or logged as unhandled when it has no row there.
fn routed(
  session session: Session,
  now now: Now,
  inner inner: Frame,
  stage stage: routing.Stage,
) -> client_connection.Handled(Session) {
  case
    routing.route(
      stage:,
      arrival: routing.OnItsOwn,
      message_id: inner.message_id,
    )
  {
    Ok(routing.Hello) -> hello_message(session:, now:, inner:)
    Ok(routing.CharacterSelect(message:)) ->
      select_message(session:, now:, inner:, message:)
    Ok(routing.WorldEntry) -> play_requested(session:, now:, inner:)
    Ok(routing.WorldMessage) -> world_carried(session:, now:, inner:)
    Ok(routing.Movement(..))
    | Ok(routing.Camp(..))
    | Ok(routing.Chat(..))
    | Ok(routing.Cast(..)) -> misrouted(session:, now:, inner:)
    Error(Nil) ->
      case stage {
        routing.BeforeHelloReply ->
          end_for(
            session:,
            now:,
            text: "the first message of a game connection is 0x058F, not "
              <> client_connection.message_text(inner.message_id),
          )
        routing.AtCharacterSelect | routing.AtWorld ->
          unhandled(session:, message_id: inner.message_id)
      }
  }
}

/// A message the table routes to a feature at a stage that feature cannot
/// take it in: a bug of the table, so the connection ends.
fn misrouted(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  end_for(
    session:,
    now:,
    text: "the routing table sent "
      <> client_connection.message_text(inner.message_id)
      <> " to a feature that does not take it here",
  )
}

/// The client's 0x058F: the first one is the hello's reply, and a second ends
/// the connection.
fn hello_message(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case standing(session.status) {
    Greeting -> hello_replied(session:, now:, inner:)
    Selecting(..) | Present(..) | Busy(..) ->
      end_for(session:, now:, text: "0x058F was sent a second time")
  }
}

/// What a message of character select's does (genesis_prime/game/character_select):
/// its effects are carried out, and a body the client's reader would refuse
/// ends the connection.
fn select_message(
  session session: Session,
  now now: Now,
  inner inner: Frame,
  message message: character_select.Message,
) -> client_connection.Handled(Session) {
  case standing(session.status) {
    Selecting(holder:) ->
      case
        character_select.take(
          message:,
          account_id: holder.account_id,
          body: inner.body,
          tables: session.settings.tables,
          character_slots: session.settings.game.character_slots,
        )
      {
        Ok(step) -> select_step(session:, now:, holder:, step:)
        Error(refusal) ->
          end_for(session:, now:, text: character_select.describe(refusal))
      }
    Greeting | Present(..) | Busy(..) -> misrouted(session:, now:, inner:)
  }
}

/// What the player's movement messages do, taken from inside 0x038C, in the
/// world (genesis_prime/game/movement): the movement keeps the place or
/// refuses, and a refusal ends the connection.
fn movement_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: movement.Message,
) -> client_connection.Handled(Session) {
  case movement.take(entered.movement, message, inner.body) {
    Ok(movement.Kept(state:)) ->
      Continue(moving(session:, holder:, entered:, state:), [])
    Ok(movement.Reported(state:, world_zone_id:, by:)) -> {
      let session = moving(session:, holder:, entered:, state:)
      let top_zones = top_zone.top_zones(session.settings.tables)
      let #(session, ready) = case by, entered.readiness {
        movement.ReportedByTerrainReady, world_entry.ClientLoading ->
          tells_the_map_ready(session:, entered:)
        movement.ReportedByTerrainReady, world_entry.ClientReady
        | movement.ReportedByZoneChanged, _
        -> #(session, [])
      }
      let #(updated, effects) = case by {
        movement.ReportedByTerrainReady ->
          chat.terrain_ready(chat: entered.chat, world_zone_id:, top_zones:)
        movement.ReportedByZoneChanged ->
          chat.world_zone_reported(
            chat: entered.chat,
            world_zone_id:,
            top_zones:,
          )
      }
      let #(session, written) =
        chat_effects(session: with_chat(session:, chat: updated), effects:)
      Continue(session, list.append(ready, written))
    }
    Ok(movement.Relayed(state:, place:, commands:, unrelayed:)) -> {
      let new_kinds =
        list.filter(unrelayed, fn(kind) {
          !set.contains(session.unrelayed_logged, kind)
        })
      let entered =
        world_entry.Entered(..entered, move_seq: entered.move_seq + 1)
      let session =
        Session(
          ..moving(session:, holder:, entered:, state:),
          unrelayed_logged: list.fold(
            new_kinds,
            session.unrelayed_logged,
            set.insert,
          ),
        )
      Continue(
        session,
        list.flatten([
          list.map(new_kinds, fn(kind) {
            log(
              session:,
              level: LogInfo,
              text: "kind "
                <> int.to_string(kind)
                <> " of 0x0637 is not relayed to the players who see this one",
            )
          }),
          case commands {
            [] -> []
            [_, ..] ->
              list.append(
                [
                  tells_the_map_moved(
                    connection: client_connection.connection(session.link),
                    entered:,
                    place:,
                  ),
                ],
                sends_the_move_to_the_viewers(entered:, now:, commands:),
              )
          },
        ]),
      )
    }
    Error(refusal) -> end_for(session:, now:, text: movement.describe(refusal))
  }
}

/// The session with the player's movement replaced.
fn moving(
  session session: Session,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  state state: movement.State,
) -> Session {
  Session(
    ..session,
    status: InWorld(
      holder:,
      entered: world_entry.Entered(..entered, movement: state),
    ),
  )
}

/// The tell to the run of the player's map that the player moved: it names
/// the player's connection, the place the movement now keeps and the move's
/// sequence number, for the map to decide who sees whom and whose ring the player
/// stands in, and no answer comes (`step.Tell`).
fn tells_the_map_moved(
  connection connection: ConnectionId,
  entered entered: world_entry.Entered,
  place place: Place,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Map(map: entered.map, incarnation: entered.incarnation),
    request: TellMoved(connection:, place:, seq: entered.move_seq),
  ))
}

/// The stay's first 0xF2: the player is ready, and its map is told `Ready`, so a
/// creature may fight it from now on.
fn tells_the_map_ready(
  session session: Session,
  entered entered: world_entry.Entered,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  todo as "tells_the_map_ready: the build fills it in"
}

/// What a creature fighting the player sent (genesis_prime/game/player_life): its
/// threat, its release or its strike, taken with the player in the world.
fn foe_sent(
  session session: Session,
  now now: Now,
  fight fight: strike_tell.Fight,
) -> client_connection.Handled(Session) {
  todo as "foe_sent: the build fills it in"
}

/// The move sent to each connection that sees the player, as news of 0x638s of
/// at most 31 relayed commands each, in order, stamped with the map's clock at the
/// time of the input (`map.server_time`, from the origin `Joined` carried): a send
/// through the registry that the shell makes with no answer. None when no
/// player sees this one.
fn sends_the_move_to_the_viewers(
  entered entered: world_entry.Entered,
  now now: Now,
  commands commands: List(RelayedMovement),
) -> List(Effect(ConnectionEffect(Request))) {
  use <- bool.guard(when: set.is_empty(entered.viewers), return: [])
  let moves =
    client_connection.peer_moves(
      map: entered.map,
      incarnation: entered.incarnation,
      unit_id: entered.unit_id,
      server_time_ms: map.server_time(
        origin_ms: entered.clock_origin_ms,
        monotonic_ms: now.monotonic_ms,
      ),
      commands:,
    )
  list.flat_map(set.to_list(entered.viewers), fn(viewer) {
    list.map(moves, fn(news) {
      OwnEffect(step.Tell(to: step.Connection(viewer), request: TellPeer(news:)))
    })
  })
}

/// What the camp messages do, taken from inside 0x038C, in the world
/// (genesis_prime/game/camp): the camp is kept, its effects are carried out,
/// and a refusal ends the connection.
fn camp_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: camp.Message,
) -> client_connection.Handled(Session) {
  case
    camp.take(
      camp: entered.camp,
      message:,
      body: inner.body,
      countdown_ms: session.settings.game.camp_countdown_ms,
    )
  {
    Ok(#(running, effects)) ->
      carry_out(
        session: Session(
          ..session,
          status: InWorld(
            holder:,
            entered: world_entry.Entered(..entered, camp: running),
          ),
        ),
        now:,
        effects: list.map(effects, from_camp),
        written: [],
      )
    Error(refusal) -> end_for(session:, now:, text: camp.describe(refusal))
  }
}

/// What the chat messages do, taken from inside 0x038C, in the world
/// (genesis_prime/game/chat): the line or whisper is answered, told or refused,
/// the effects are carried out, and a refusal ends the connection.
fn chat_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: chat.Message,
) -> client_connection.Handled(Session) {
  case
    chat.take(
      chat: entered.chat,
      message:,
      body: inner.body,
      viewers: entered.viewers,
      realm_name: session.settings.realm_name,
      connection: client_connection.connection(session.link),
      tables: session.settings.tables,
    )
  {
    Ok(#(updated, effects)) ->
      carry_chat(session: with_chat(session:, chat: updated), effects:)
    Error(refusal) -> end_for(session:, now:, text: chat.describe(refusal))
  }
}

/// What the cast messages do, taken from inside 0x038C, in the world
/// (genesis_prime/game/cast): the press is refused or accepted and its writes,
/// tells and timers are carried out, the cancel ends a cast, and a refusal ends
/// the connection.
fn cast_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: cast.Message,
) -> client_connection.Handled(Session) {
  case
    cast.take(
      cast: entered.cast,
      message:,
      body: inner.body,
      caster: caster_of(entered:),
      plans: spell_plan.plans(session.settings.tables),
      now:,
    )
  {
    Ok(#(updated, effects)) ->
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    Error(refusal) -> end_for(session:, now:, text: cast.describe(refusal))
  }
}

/// A timer fired that is not the save timer's: a cast's, or the claim's.
fn other_timer_fired(
  session session: Session,
  now now: Now,
  timer timer: TimerId,
) -> client_connection.Handled(Session) {
  case cast.owns(timer), strike.owns(timer) {
    True, _ -> cast_due(session:, now:, timer:)
    False, True -> strike_due(session:, now:)
    False, False -> claim_wait_over(session:, now:, timer:)
  }
}

/// A creature's answer to a strike this player told: the strike rule files it in
/// the round it belongs to, and a round that closes is the cast rule's `went`; an
/// answer with no player in the world, or for a round that is closed, is dropped
/// (genesis_prime/game/strike).
fn target_sent(
  session session: Session,
  now now: Now,
  answered answered: Answered,
) -> client_connection.Handled(Session) {
  case held_in_the_world(session.status) {
    None -> Continue(session, [])
    Some(entered) -> {
      let #(updated, effects) =
        strike.answered(strike: entered.strike, answer: answered, now:)
      let #(session, written) =
        carry_strike(
          session: with_strike(session:, strike: updated),
          now:,
          effects:,
        )
      Continue(session, written)
    }
  }
}

/// The strike timer fired: the rounds whose deadline has passed close with the
/// units that answered (genesis_prime/game/strike `timer_fired`).
fn strike_due(
  session session: Session,
  now now: Now,
) -> client_connection.Handled(Session) {
  case held_in_the_world(session.status) {
    None -> Continue(session, [])
    Some(entered) -> {
      let #(updated, effects) = strike.timer_fired(strike: entered.strike, now:)
      let #(session, written) =
        carry_strike(
          session: with_strike(session:, strike: updated),
          now:,
          effects:,
        )
      Continue(session, written)
    }
  }
}

/// A timer of the player's cast rule fired: its go, child cast or held press.
/// With no player in the world to take it, it is dropped.
fn cast_due(
  session session: Session,
  now now: Now,
  timer timer: TimerId,
) -> client_connection.Handled(Session) {
  case held_in_the_world(session.status) {
    None -> Continue(session, [])
    Some(entered) -> {
      let #(updated, effects) =
        cast.timer_fired(
          cast: entered.cast,
          timer:,
          caster: caster_of(entered:),
          now:,
        )
      carry_cast(session: with_cast(session:, cast: updated), now:, effects:)
    }
  }
}

/// The player as its cast rule takes it: who it is, where it stands, what it
/// holds, who sees it and the units its client shows.
fn caster_of(entered entered: world_entry.Entered) -> cast.Caster {
  cast.Caster(
    unit_id: entered.unit_id,
    place: movement.place(entered.movement),
    abilities: entered.loadout.abilities,
    weapon: Some(entered.loadout.weapon),
    audience: entered.viewers,
  )
}

/// The session with the player's cast state replaced.
fn with_cast(session session: Session, cast cast: cast.State) -> Session {
  with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, cast:)
  })
}

/// What the cast rule decided, carried out in order.
fn carry_cast(
  session session: Session,
  now now: Now,
  effects effects: List(cast.Effect),
) -> client_connection.Handled(Session) {
  let #(session, written) = cast_effects(session:, now:, effects:)
  Continue(session, written)
}

/// The connection's effects for what the cast rule decided, with the session as
/// they leave it: a write, a tell of news to a viewer in the run of the player's
/// map, a timer or a log line, and a go asked, which selects and strikes its targets
/// (`strike_begins`). A tell with no player in the world is dropped.
fn cast_effects(
  session session: Session,
  now now: Now,
  effects effects: List(cast.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  list.fold(effects, #(session, []), fn(so_far, effect) {
    let #(session, done) = so_far
    let #(session, more) = case effect, entered_of(session.status) {
      cast.Send(frame:), _ -> #(session, [to_client(session, frame)])
      cast.Tell(to:, news:), Some(entered) -> #(session, [
        news_to(entered:, viewer: to, news:),
      ])
      cast.Tell(..), None -> #(session, [])
      cast.StartTimer(timer:, after_ms:), _ -> #(session, [
        OwnEffect(StartTimer(timer:, after_ms:)),
      ])
      cast.CancelTimer(timer:), _ -> #(session, [
        OwnEffect(CancelTimer(timer:)),
      ])
      cast.Log(level:, text:), _ -> #(session, [log(session:, level:, text:)])
      cast.Strike(asked:), Some(entered) ->
        strike_begins(session:, now:, entered:, asked:)
      cast.Strike(..), None -> #(session, [])
    }
    #(session, list.append(done, more))
  })
}

/// A go asked: its targets are selected from the units the client shows, the
/// caster's rolls are drawn from the connection's seed, and the strike rule begins
/// its round (genesis_prime/game/strike).
fn strike_begins(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  asked asked: cast.GoAsked,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let tables = session.settings.tables
  let attacker = attacker_of(session:, entered:)
  let selection =
    strike.select(
      asked:,
      attacker:,
      picture: entered.shown,
      areas: spell_area.areas(tables:),
      now_ms: now.monotonic_ms,
    )
  let #(link, entropy) =
    client_connection.draw(session.link, strike.entropy_needed(selection:))
  let #(updated, effects) =
    strike.begin(
      strike: entered.strike,
      selection:,
      attacker:,
      formulas: rating.formulas(tables:),
      entropy:,
      now:,
    )
  carry_strike(
    session: with_strike(session: Session(..session, link:), strike: updated),
    now:,
    effects:,
  )
}

/// The player as its strikes take it: who it is, where it stands and faces, which
/// player faction it is of and what its damage reads of it (its level and the
/// ratings its gear gives).
fn attacker_of(
  session session: Session,
  entered entered: world_entry.Entered,
) -> strike.Attacker {
  let place = movement.place(entered.movement)
  let assert Ok(faction) = shown.faction_of(entered.unit.tail.faction_id)
    as "a character's faction is Exile or Dominion (start_place)"
  let level =
    unit_fields.stat(tail: entered.unit.tail, stat_id: unit_fields.level_stat)
    |> result.unwrap(1)
  strike.Attacker(
    unit_id: entered.unit_id,
    connection: client_connection.connection(session.link),
    pose: Pose(at: area.point_of(place), yaw: start_place.facing(place).yaw),
    place:,
    move_seq: entered.move_seq,
    faction:,
    stats: damage.Attacker(
      level:,
      assault_rating: entered.loadout.properties.assault_rating,
      support_rating: entered.loadout.properties.support_rating,
    ),
  )
}

/// The session with the player's strike state replaced.
fn with_strike(
  session session: Session,
  strike strike: strike.State,
) -> Session {
  with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, strike:)
  })
}

/// What the strike rule decided, carried out in order, with the session as they leave
/// it: a strike told to a creature through the creature registry, a timer, a closed
/// round's go (the cast rule's `went`), the news held for the round's units, or a log
/// line.
fn carry_strike(
  session session: Session,
  now now: Now,
  effects effects: List(strike.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  list.fold(effects, #(session, []), fn(so_far, effect) {
    let #(session, done) = so_far
    let #(session, more) = case effect, entered_of(session.status) {
      _, None -> #(session, [])
      strike.TellStrike(unit_id:, life:, tell:), Some(entered) -> #(session, [
        OwnEffect(step.Tell(
          to: step.Creature(
            map: entered.map,
            incarnation: entered.incarnation,
            unit_id:,
            life:,
          ),
          request: client_connection.TellStrike(tell:),
        )),
      ])
      strike.StartTimer(timer:, after_ms:), Some(_) -> #(session, [
        OwnEffect(StartTimer(timer:, after_ms:)),
      ])
      strike.CancelTimer(timer:), Some(_) -> #(session, [
        OwnEffect(CancelTimer(timer:)),
      ])
      strike.Went(asked:, struck:), Some(entered) -> {
        let #(updated, cast_effects_out) =
          cast.went(
            cast: entered.cast,
            caster: caster_of(entered:),
            now:,
            cast_id: asked.cast_id,
            phase: asked.phase,
            struck:,
          )
        cast_effects(
          session: with_cast(session:, cast: updated),
          now:,
          effects: cast_effects_out,
        )
      }
      strike.Released(unit_id:, news:), Some(entered) -> #(
        session,
        creature_news_frames(session:, entered:, unit_id:, news:),
      )
      strike.Log(level:, text:), Some(_) -> #(session, [
        log(session:, level:, text:),
      ])
    }
    #(session, list.append(done, more))
  })
}

/// 0x0594 with the bit set and reason 0: the client leaves the world and
/// starts character select on the same connection (opcode.0x594).
fn leave_world_frame() -> Frame {
  let assert Ok(body) = leave_world.encode(LeaveWorld(returning: 1, reason: 0))
    as "a bit and a reason of 0 fit the message"
  Frame(message_id: leave_world.message_id, body:)
}

/// A whole frame of a message the rule does not take, logged as unhandled:
/// a warning the first time its id comes on the connection, and a debug line
/// for each repeat, since the client sends some of them on every move.
fn unhandled(
  session session: Session,
  message_id message_id: Int,
) -> client_connection.Handled(Session) {
  let level = case set.contains(session.unhandled_logged, message_id) {
    True -> LogDebug
    False -> LogWarning
  }
  let session =
    Session(
      ..session,
      unhandled_logged: set.insert(session.unhandled_logged, message_id),
    )
  client_connection.unhandled(
    session:,
    about: about_of(session),
    server: "game",
    message_id:,
    level:,
  )
}

/// The client's 0x038C: a 5-bit kind and one whole inner frame
/// (opcode.0x38c), which is every message the client sends in the world. The
/// routing table says which feature takes the inner message with the player in
/// the world (genesis_prime/game/routing), and any other is logged as unhandled
/// under its own id. A body that holds no whole frame, or bytes after it, is
/// one the client never writes, and ends the connection.
fn world_carried(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case world_message.decode(inner.body) {
    Error(error) ->
      end_for(
        session:,
        now:,
        text: client_connection.describe_undecoded(client_connection.Undecoded(
          message_id: world_message.message_id,
          error:,
        )),
      )
    Ok(carried) ->
      case frame.parse(carried.inner_frame) {
        Error(error) ->
          end_for(
            session:,
            now:,
            text: "0x038C holds no whole frame: " <> frame.describe(error),
          )
        Ok(whole) ->
          case standing(session.status) {
            Present(holder:, entered:) ->
              case
                routing.route(
                  stage: routing.AtWorld,
                  arrival: routing.InsideWorldMessage,
                  message_id: whole.message_id,
                )
              {
                Ok(routing.Movement(message:)) ->
                  movement_message(
                    session:,
                    now:,
                    holder:,
                    entered:,
                    inner: whole,
                    message:,
                  )
                Ok(routing.Camp(message:)) ->
                  camp_message(
                    session:,
                    now:,
                    holder:,
                    entered:,
                    inner: whole,
                    message:,
                  )
                Ok(routing.Chat(message:)) ->
                  chat_message(session:, now:, entered:, inner: whole, message:)
                Ok(routing.Cast(message:)) ->
                  cast_message(session:, now:, entered:, inner: whole, message:)
                Ok(routing.Hello)
                | Ok(routing.CharacterSelect(..))
                | Ok(routing.WorldEntry)
                | Ok(routing.WorldMessage) ->
                  misrouted(session:, now:, inner: whole)
                Error(Nil) -> unhandled(session:, message_id: whole.message_id)
              }
            Greeting | Selecting(..) | Busy(..) ->
              unhandled(session:, message_id: whole.message_id)
          }
      }
  }
}

/// The client's 0x058F: the connection is keyed from the session key at once,
/// as the client keys its own (vector.0x14003827c.session_fold), and the
/// hand-off is asked to take the key.
fn hello_replied(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case game_hello_reply.decode(inner.body) {
    Error(error) ->
      end_for(
        session:,
        now:,
        text: "the game hello reply 0x058F does not decode: "
          <> bit_stream.describe_decode(error:),
      )
    Ok(reply) -> {
      let assert Ok(key) = guid.from_wire(reply.session_key)
        as "the reply's session key is 16 bytes"
      case rekeyed(session_key: reply.session_key) {
        Error(error) ->
          end_for(
            session:,
            now:,
            text: "the session key makes no cipher: "
              <> describe_key_error(error),
          )
        Ok(keyed) ->
          ask(
            session: Session(..session, cipher: keyed, status: TakingSessionKey),
            now:,
            request: AskHandOff(Take(SessionKey(key:))),
            before: [],
          )
      }
    }
  }
}

/// The cipher a game connection is keyed to from the moment the client sends
/// 0x058F: the base key folded with the 16 bytes of the session key the
/// message carries (vector.0x14003827c.session_fold). Every frame after that
/// one, each way, is under it.
pub fn rekeyed(
  session_key session_key: BitArray,
) -> Result(Cipher, cipher.KeyError) {
  cipher.session_key(bytes: session_key, base_key: cipher.base_key)
  |> result.try(cipher.new)
}

fn describe_key_error(error: cipher.KeyError) -> String {
  case error {
    cipher.ZeroKey -> "the key is 0, which the client refuses"
    cipher.SessionKeyNotSixteenBytes(bytes:) ->
      "the session key is " <> int.to_string(bytes) <> " bytes, not 16"
  }
}

/// The ids of the client's messages the rule takes: each row of the routing
/// table (genesis_prime/game/routing), and 0x025B, the create request that
/// 0x025C carries. A stage takes some of them: before the hello reply only
/// 0x058F, in the world 0x038C and, from inside it, the movement and camp
/// messages. The coverage measure counts all of them as handled.
pub fn taken_message_ids() -> List(Int) {
  list.flatten([
    [create_character.message_id],
    routing.message_ids(arrival: routing.OnItsOwn),
    carried_message_ids(),
  ])
}

/// The ids of the client's messages the rule takes only from inside 0x038C with
/// the player in the world: the movement and camp messages. Sent on their own,
/// as the client never does, or with no player in the world, they are logged as
/// unhandled.
pub fn carried_message_ids() -> List(Int) {
  routing.message_ids(arrival: routing.InsideWorldMessage)
}

/// Character select's new state and what it decided, carried out.
fn select_step(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  step step: #(character_select.State, List(character_select.Effect)),
) -> client_connection.Handled(Session) {
  carry_out(
    session: Session(
      ..session,
      status: InCharacterSelect(holder:, select: step.0),
    ),
    now:,
    effects: list.map(step.1, from_select),
    written: [],
  )
}

/// The client's 0x07DD: world entry asks the store for the character, and the
/// connection waits in `EnteringWorld`.
fn play_requested(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case standing(session.status) {
    Selecting(holder:) ->
      case world_entry.take(account_id: holder.account_id, body: inner.body) {
        Ok(#(entry, effects)) ->
          carry_out(
            session: Session(..session, status: EnteringWorld(holder:, entry:)),
            now:,
            effects: list.map(effects, from_entry),
            written: [],
          )
        Error(refusal) ->
          end_for(session:, now:, text: world_entry.describe(refusal))
      }
    Greeting | Present(..) | Busy(..) -> misrouted(session:, now:, inner:)
  }
}

/// What a feature of the rule decided that the rule carries out, in order.
type Decided {
  /// Send the client a message, in the game wrapper under the cipher the
  /// connection holds.
  ToClient(frame: Frame)
  /// Log a warning.
  Warning(text: String)
  /// Make the connection's next ask, which ends the step.
  Asks(request: Request)
  /// Watch the run of the map that holds the player (`map_watch`).
  WatchesMap(map: MapId, incarnation: Int)
  /// Start the timer that saves the player's place (`save_timer`).
  StartsSaveTimer
  /// What the chat decided: writes, tells, watches and group joins.
  Chats(effects: List(chat.Effect))
  /// The player leaves the world for character select: the save timer is
  /// cancelled and the place saved, the map's run is asked to take the player
  /// out, and 0x0594 is written (the camp's finish).
  LeavesWorld
}

fn from_select(effect: character_select.Effect) -> Decided {
  case effect {
    character_select.Send(frame:) -> ToClient(frame:)
    character_select.Warn(text:) -> Warning(text:)
    character_select.Ask(request:) ->
      Asks(request: AskStore(store.Select(request)))
  }
}

fn from_camp(effect: camp.Effect) -> Decided {
  case effect {
    camp.Write(frame:) -> ToClient(frame:)
    camp.LeaveWorld -> LeavesWorld
  }
}

fn from_entry(effect: world_entry.Effect) -> Decided {
  case effect {
    world_entry.Send(frame:) -> ToClient(frame:)
    world_entry.AskStore(request:) ->
      Asks(request: AskStore(store.World(request)))
    world_entry.AskMap(map:, message:) -> Asks(request: AskMap(map:, message:))
    world_entry.WatchMap(map:, incarnation:) -> WatchesMap(map:, incarnation:)
  }
}

/// Turns what a feature decided into writes, log lines and a watch, and into
/// its ask, which ends the step with what was decided before it; `written`
/// are the effects so far, the last first.
fn carry_out(
  session session: Session,
  now now: Now,
  effects effects: List(Decided),
  written written: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  case effects {
    [] -> Continue(session, list.reverse(written))
    [ToClient(frame:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        to_client(session, frame),
        ..written
      ])
    [Warning(text:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        log(session:, level: LogWarning, text:),
        ..written
      ])
    [WatchesMap(map:, incarnation:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        Watch(watch: map_watch, target: step.Map(map:, incarnation:)),
        ..written
      ])
    [Chats(effects: chat_decided), ..rest] -> {
      let #(session, converted) = chat_effects(session:, effects: chat_decided)
      carry_out(
        session:,
        now:,
        effects: rest,
        written: list.append(list.reverse(converted), written),
      )
    }
    [StartsSaveTimer, ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        start_save_timer(),
        ..written
      ])
    [LeavesWorld, ..] ->
      case holds_a_player(session.status) {
        Some(#(holder, entered)) ->
          saving(
            session: Session(
              ..session,
              next_whisper: chat.next_whisper(chat: entered.chat),
            ),
            now:,
            holder:,
            entered:,
            then: Camped,
            before: list.flatten([
              list.reverse(written),
              chat_effects(session:, effects: chat.left(entered.chat)).1,
              cast_effects(
                session:,
                now:,
                effects: cast.left(cast: entered.cast).1,
              ).1,
              carry_strike(
                session:,
                now:,
                effects: strike.left(strike: entered.strike).1,
              ).1,
              [OwnEffect(CancelTimer(timer: save_timer))],
            ]),
            within_ms: session.settings.ask_deadline_ms,
          )
        None ->
          end_for(
            session:,
            now:,
            text: "a feature left the world with no player in it",
          )
      }
    [Asks(request:), ..] ->
      ask(session:, now:, request:, before: list.reverse(written))
  }
}

/// Starts the timer that saves the player's place every `movement.save_period_ms`.
fn start_save_timer() -> Effect(ConnectionEffect(Request)) {
  OwnEffect(StartTimer(timer: save_timer, after_ms: movement.save_period_ms))
}

/// Makes the connection's next ask, after the effects `before`, with the
/// settings' deadline.
fn ask(
  session session: Session,
  now now: Now,
  request request: Request,
  before before: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  ask_within(
    session:,
    now:,
    request:,
    before:,
    within_ms: session.settings.ask_deadline_ms,
  )
}

/// Makes the connection's next ask, after the effects `before`, which gets
/// `within_ms` from the time of the input to be answered.
fn ask_within(
  session session: Session,
  now now: Now,
  request request: Request,
  before before: List(Effect(ConnectionEffect(Request))),
  within_ms within_ms: Int,
) -> client_connection.Handled(Session) {
  let #(link, made) =
    client_connection.ask(session.link, now:, deadline_ms: within_ms, request:)
  Asking(Session(..session, link:), before, made)
}

/// The answer to the ask in flight.
fn answered(
  session session: Session,
  now now: Now,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case session.status {
    TakingSessionKey -> key_taken(session:, now:, outcome:)
    ClaimingSession(holder:, resume:, retries:) ->
      claim_answered(session:, now:, holder:, resume:, retries:, outcome:)
    InCharacterSelect(holder:, select:) ->
      select_answered(session:, now:, holder:, select:, outcome:)
    EnteringWorld(holder:, entry:) ->
      entry_answered(session:, now:, holder:, entry:, outcome:)
    SavingPlace(holder:, entered:, then:) ->
      save_answered(session:, now:, holder:, entered:, then:, outcome:)
    LeavingMap(holder:, ..) -> leave_answered(session:, now:, holder:, outcome:)
    AwaitingHelloReply | WaitingToClaim(..) | InWorld(..) ->
      end_for(session:, now:, text: "an answer came when no ask was out")
  }
}

/// The hand-off's answer to taking the session key: the holder, whose account
/// Sessions is asked to claim, or a client that is told it is disconnected.
fn key_taken(
  session session: Session,
  now now: Now,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromHandOff(hand_off.Taken(holder:))) ->
      claim(session:, now:, holder:, resume: ResumeSelect, retries: 0)
    step.Answer(FromHandOff(hand_off.NoHolder)) ->
      told(
        session:,
        now:,
        reason: AccountDisconnected,
        level: LogWarning,
        text: "the hand-off does not hold the session key",
      )
    step.Answer(FromHandOff(hand_off.Kept))
    | step.Answer(FromHandOff(hand_off.AlreadyHeld))
    | step.Answer(FromStore(..))
    | step.Answer(FromSessions(..))
    | step.Answer(FromMap(..)) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the hand-off's answer is none a Take gets",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "the hand-off", outcome:),
      )
    step.StoppedWaiting -> stopped(session, now)
  }
}

/// Opens a watch on Sessions and asks it to make this connection the account's
/// session; `resume` is where the client is once it answers. The watch is
/// opened with every claim, so a restarted Sessions is watched again.
fn claim(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  resume resume: Resume,
  retries retries: Int,
) -> client_connection.Handled(Session) {
  ask(
    session: Session(
      ..session,
      status: ClaimingSession(holder:, resume:, retries:),
    ),
    now:,
    request: AskSessions(account_session.Claim(
      account: holder.account_id,
      connection: client_connection.connection(session.link),
    )),
    before: [Watch(watch: sessions_watch, target: Sessions)],
  )
}

/// Sessions' answer to the claim: `Claimed` puts the client where it was, in
/// character select or in the world, and the frames held are taken. `TakenOver`
/// means a newer login of the account holds the slot: the connection ends as a
/// takeover does. Sessions not running is waited out up to `claim_retries`
/// times, with the watch dropped; any other failure of the ask tells the client
/// the server failed, as the store's do.
fn claim_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  resume resume: Resume,
  retries retries: Int,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromSessions(account_session.Claimed)) ->
      case resume {
        ResumeSelect ->
          Continue(
            Session(
              ..session,
              status: InCharacterSelect(holder:, select: character_select.new()),
            ),
            [],
          )
        ResumeWorld(entered:) ->
          Continue(Session(..session, status: InWorld(holder:, entered:)), [
            start_save_timer(),
          ])
      }
    step.Answer(FromSessions(account_session.TakenOver)) ->
      taken_over(session, now)
    step.Answer(FromStore(..))
    | step.Answer(FromHandOff(..))
    | step.Answer(FromMap(..)) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "Sessions' answer is none a claim gets",
      )
    step.NotRunning if retries < claim_retries ->
      Done(
        Session(
          ..session,
          status: WaitingToClaim(holder:, resume:, retries: retries + 1),
        ),
        [
          Unwatch(watch: sessions_watch),
          OwnEffect(StartTimer(timer: claim_timer, after_ms: claim_wait_ms)),
        ],
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "Sessions", outcome:),
      )
    step.StoppedWaiting ->
      case resume {
        // The stop that cut the claim short comes as the shell's next input
        // and saves the player, so the player goes back to the world.
        ResumeWorld(entered:) ->
          Done(Session(..session, status: InWorld(holder:, entered:)), [])
        ResumeSelect -> stopped(session, now)
      }
  }
}

/// A newer login of the account holds the session: the client is told its
/// account was disconnected (0x036A reason 19) and the connection ends, after
/// the save of the player's place when it holds one in the world.
fn taken_over(
  session: Session,
  now: Now,
) -> client_connection.Handled(Session) {
  told(
    session:,
    now:,
    reason: AccountDisconnected,
    level: LogInfo,
    text: "a newer login of the account holds the session",
  )
}

/// What Sessions sent the connection: `TakenOver` tells the client its account
/// was disconnected (0x036A reason 19) and ends the connection. `Claimed` is
/// an answer, never sent, and is a bug, as is a takeover before the connection
/// has claimed.
fn sessions_sent(
  session session: Session,
  now now: Now,
  message message: account_session.Outgoing,
) -> client_connection.Handled(Session) {
  case message, session.status {
    account_session.TakenOver, InCharacterSelect(..)
    | account_session.TakenOver, ClaimingSession(..)
    | account_session.TakenOver, WaitingToClaim(..)
    | account_session.TakenOver, EnteringWorld(..)
    | account_session.TakenOver, InWorld(..)
    | account_session.TakenOver, SavingPlace(..)
    | account_session.TakenOver, LeavingMap(..)
    -> taken_over(session, now)
    account_session.TakenOver, AwaitingHelloReply
    | account_session.TakenOver, TakingSessionKey
    ->
      end_for(session:, now:, text: "Sessions sent a takeover before the claim")
    account_session.Claimed, _ ->
      end_for(session:, now:, text: "Sessions sent an answer as a message")
  }
}

/// What the map sent the connection, while its player is in the world or its
/// claim is made again with the player in it: who sees its player (`Watched`,
/// `Unwatched`), and a unit whose owner's connection ended (`Gone`). A connection
/// sends everything about its own unit itself: told `Watched(by)` it sends `by` its
/// 0x262 at its current place, told `Unwatched(by)` its 0x355. The shell takes a
/// send between steps, after the ask's outcome and the step it starts are done
/// (genesis_prime/connection/shell), and world entry writes its whole burst in the
/// one step that takes the map's `Joined`, so a send of the map, which comes after
/// its answer, is always taken after the burst: no status holds sends during
/// entry. With no player in the world (the player left the map, or never joined)
/// the send is dropped, since the client holds no world. `Joined` and `Left` are
/// answers, never sends, and are a bug.
fn map_sent(
  session session: Session,
  now now: Now,
  message message: map.Outgoing,
) -> client_connection.Handled(Session) {
  case message, held_in_the_world(session.status) {
    map.Joined(..), _
    | map.NotJoined(..), _
    | map.Left, _
    | map.Retire, _
    | map.Approached(..), _
    | map.Withdrew(..), _
    ->
      end_for(
        session:,
        now:,
        text: "the map sent an answer, or a creature's word, as a message",
      )
    map.Watched(..), None | map.Unwatched(..), None | map.Gone(..), None ->
      Continue(session, [])
    map.Watched(by:), Some(entered) ->
      Continue(viewers_changed(session:, change: set.insert(_, by)), [
        news_to(
          entered:,
          viewer: by,
          news: client_connection.Appeared(unit: appearance(entered:, now:)),
        ),
      ])
    map.Unwatched(by:), Some(entered) ->
      Continue(
        viewers_changed(session:, change: set.delete(_, by)),
        case set.contains(entered.viewers, by) {
          True -> [
            news_to(entered:, viewer: by, news: client_connection.Removed),
          ]
          False -> []
        },
      )
    map.Gone(unit_id:), Some(entered) -> {
      let session = marked_gone(session:, unit_id:)
      use <- bool.guard(
        when: !dict.has_key(entered.shown, unit_id),
        return: Continue(session, []),
      )
      Continue(
        session,
        list.append(finishes_of_forgotten_casts(session:, entered:, unit_id:), [
          to_client(session, unit_removed_frame(unit_id:)),
        ]),
      )
    }
  }
}

/// What another player's connection told this one about chat
/// (genesis_prime/game/chat_tell): taken with the player in the world, and by
/// `chat.told`. A whisper that finds no player in the world is answered
/// `NotHeard`; any other tell is dropped.
fn chat_sent(
  session session: Session,
  tell tell: chat_tell.Tell,
) -> client_connection.Handled(Session) {
  case held_in_the_world(session.status) {
    Some(entered) -> {
      let #(updated, effects) = chat.told(chat: entered.chat, tell:)
      carry_chat(session: with_chat(session:, chat: updated), effects:)
    }
    None ->
      case tell {
        chat_tell.Whisper(whisper:, from:, ..) ->
          Continue(session, [
            OwnEffect(step.Tell(
              to: step.Connection(from),
              request: TellChat(chat_tell.NotHeard(whisper:)),
            )),
          ])
        chat_tell.Said(..)
        | chat_tell.ZoneLine(..)
        | chat_tell.Heard(..)
        | chat_tell.NotHeard(..) -> Continue(session, [])
      }
  }
}

/// The session with the chat of the player in the world replaced.
fn with_chat(session session: Session, chat chat: chat.Chat) -> Session {
  with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, chat:)
  })
}

/// Turns what the chat decided into writes, tells, watches, group joins and log
/// lines. A channel the server does not build is logged as unhandled once for
/// each channel on the connection.
fn carry_chat(
  session session: Session,
  effects effects: List(chat.Effect),
) -> client_connection.Handled(Session) {
  let #(session, written) = chat_effects(session:, effects:)
  Continue(session, written)
}

/// The connection's effects for what the chat decided, in order, and the session
/// with the channels it logged as unhandled.
fn chat_effects(
  session session: Session,
  effects effects: List(chat.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let #(session, written) =
    list.fold(effects, #(session, []), fn(so_far, effect) {
      let #(session, written) = so_far
      case effect {
        chat.Send(frame:) -> #(session, [to_client(session, frame), ..written])
        chat.Tell(to:, tell:) -> #(session, [
          OwnEffect(step.Tell(to:, request: TellChat(tell))),
          ..written
        ])
        chat.TellWatched(watch:, tell:) -> #(session, [
          OwnEffect(step.TellWatched(watch:, request: TellChat(tell))),
          ..written
        ])
        chat.Watch(watch:, target:) -> #(session, [
          Watch(watch:, target:),
          ..written
        ])
        chat.Unwatch(watch:) -> #(session, [Unwatch(watch:), ..written])
        chat.JoinGroup(address:) -> #(session, [
          OwnEffect(step.JoinGroup(address:)),
          ..written
        ])
        chat.LeaveGroup(address:) -> #(session, [
          OwnEffect(step.LeaveGroup(address:)),
          ..written
        ])
        chat.UnknownZone(world_zone_id:) ->
          case set.contains(session.unknown_zones_logged, world_zone_id) {
            True -> #(session, written)
            False -> #(
              Session(
                ..session,
                unknown_zones_logged: set.insert(
                  session.unknown_zones_logged,
                  world_zone_id,
                ),
              ),
              [
                log(
                  session:,
                  level: LogWarning,
                  text: "WorldZone "
                    <> int.to_string(world_zone_id)
                    <> " has no row in the client's table, so the player is in no zone channel",
                ),
                ..written
              ],
            )
          }
        chat.Unhandled(channel_type:) -> {
          let id = chat_channel.id(channel_type)
          case set.contains(session.unhandled_channels_logged, id) {
            True -> #(session, written)
            False -> #(
              Session(
                ..session,
                unhandled_channels_logged: set.insert(
                  session.unhandled_channels_logged,
                  id,
                ),
              ),
              [
                log(
                  session:,
                  level: LogWarning,
                  text: "chat channel "
                    <> int.to_string(id)
                    <> " is not built: a line on it is refused with result 3",
                ),
                ..written
              ],
            )
          }
        }
      }
    })
  #(session, list.reverse(written))
}

/// What another player's connection sent about the unit it owns, written while
/// this player is in the world, in the run of the map the news names, and only
/// as the client can take it (`viewer_takes`). News from another run or another
/// map is dropped: it names a unit id that may be another unit here.
fn peer_sent(
  session session: Session,
  news news: client_connection.PeerNews,
) -> client_connection.Handled(Session) {
  case held_in_the_world(session.status) {
    None -> Continue(session, [])
    Some(entered) -> {
      use <- bool.guard(
        when: entered.map != news.map || entered.incarnation != news.incarnation,
        return: Continue(session, []),
      )
      viewer_takes(session:, entered:, news:)
    }
  }
}

/// What a viewer writes of news of a unit, from the units this connection has
/// shown and the ones the map reported gone: a 0x262 for a unit not shown and not
/// gone, which is then shown (the client keeps one unit per id until its 0x355,
/// and a unit that is gone would be a ghost); a 0x638 for a shown unit; a 0x355
/// for a shown unit, which is then no longer shown. Anything else is dropped. A
/// 0x262 or 0x355 that names unit 0 or this player's own unit is refused with an
/// error line, and writes nothing: the client makes the controlled unit of a
/// 0x262 with either id (0x1403d9760) and removes a unit with a 0x355
/// (0x1403d9590).
fn viewer_takes(
  session session: Session,
  entered entered: world_entry.Entered,
  news news: client_connection.PeerNews,
) -> client_connection.Handled(Session) {
  let unit_id = news.unit_id
  let shown = dict.has_key(entered.shown, unit_id)
  let creates_or_removes = case news.news {
    client_connection.Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Removed -> True
    client_connection.Moving(..)
    | client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastMissed(..)
    | client_connection.CastFinished(..)
    | client_connection.Health(..)
    | client_connection.Died
    | client_connection.CreatureMoved(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..) -> False
  }
  use <- bool.guard(
    when: creates_or_removes && { unit_id == 0 || unit_id == entered.unit_id },
    return: Continue(session, [
      log(
        session:,
        level: step.LogError,
        text: "a unit's owner sent a 0x262 or 0x355 naming unit "
          <> int.to_string(unit_id)
          <> ", which is this player's own unit or none, so it is refused",
      ),
    ]),
  )
  case news.news {
    client_connection.Appeared(unit:) -> {
      use <- bool.guard(
        when: shown || set.contains(entered.gone, unit_id),
        return: Continue(session, []),
      )
      Continue(
        shown_changed(session:, change: dict.insert(_, unit_id, ShownPlayer)),
        [to_client(session, world_entry.unit_created_frame(unit:))],
      )
    }
    client_connection.CreatureAppeared(
      unit:,
      life:,
      place:,
      hit_radius:,
      attackable:,
    ) -> {
      use <- bool.guard(
        when: shown || set.contains(entered.gone, unit_id),
        return: Continue(session, []),
      )
      Continue(
        shown_changed(session:, change: dict.insert(
          _,
          unit_id,
          ShownCreature(
            path: creature_path.Standing(at: place),
            life:,
            alive: creature_unit.health_of(unit:) > 0,
            hit_radius:,
            attackable:,
          ),
        )),
        [to_client(session, creature_created_frame(unit:))],
      )
    }
    client_connection.Moving(server_time_ms:, commands:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(session, [
        to_client(
          session,
          unit_moved_frame(unit_id:, server_time_ms:, commands:),
        ),
      ])
    }
    client_connection.Removed -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(
        unit_forgotten(session:, unit_id:),
        list.append(finishes_of_forgotten_casts(session:, entered:, unit_id:), [
          to_client(session, unit_removed_frame(unit_id:)),
        ]),
      )
    }
    client_connection.CastStarted(start:) -> {
      use <- bool.guard(when: !shown, return: Continue(session, []))
      Continue(
        with_entered(session:, change: fn(entered) {
          world_entry.Entered(
            ..entered,
            casts_written: dict.insert(
              entered.casts_written,
              start.cast_id,
              unit_id,
            ),
          )
        }),
        [to_client(session, cast.started_frame(start:))],
      )
    }
    client_connection.CastWent(go:) -> {
      use <- bool.guard(
        when: !dict.has_key(entered.casts_written, go.cast_id),
        return: Continue(session, []),
      )
      Continue(session, [to_client(session, cast.went_frame(go:))])
    }
    client_connection.CastMissed(missed:) -> {
      use <- bool.guard(
        when: !dict.has_key(entered.casts_written, missed.cast_id),
        return: Continue(session, []),
      )
      Continue(session, [to_client(session, cast.missed_frame(missed:))])
    }
    client_connection.CastFinished(cast_id:) -> {
      use <- bool.guard(
        when: !dict.has_key(entered.casts_written, cast_id),
        return: Continue(session, []),
      )
      Continue(
        with_entered(session:, change: fn(entered) {
          world_entry.Entered(
            ..entered,
            casts_written: dict.delete(entered.casts_written, cast_id),
          )
        }),
        [to_client(session, cast.finished_frame(cast_id:))],
      )
    }
    client_connection.Health(health:, dead:) ->
      creature_news(
        session:,
        entered:,
        unit_id:,
        news: client_connection.Health(health:, dead:),
      )
    client_connection.Died ->
      creature_news(session:, entered:, unit_id:, news: client_connection.Died)
    client_connection.CreatureMoved(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..) ->
      todo as "the fight's news: the build writes 0x638, 0x908, 0x90a, 0x89a and 0x938 for a shown unit"
  }
}

/// A creature's health or death news, for a creature this client shows: its picture
/// marks the creature dead at once, which a selection reads, and the frame is
/// written, or held until the go of the caster's own round that names the unit is
/// written, so the client shows the number before the death it caused
/// (genesis_prime/game/strike). Another watcher's connection is not held: it is told
/// the news and the cast by two senders, which no order holds.
fn creature_news(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  news news: client_connection.News,
) -> client_connection.Handled(Session) {
  use <- bool.guard(
    when: !dict.has_key(entered.shown, unit_id),
    return: Continue(session, []),
  )
  let session = case news {
    client_connection.Died | client_connection.Health(dead: True, ..) ->
      shown_changed(session:, change: fn(picture) {
        shown.with_alive(picture:, unit_id:, alive: False)
      })
    client_connection.Health(dead: False, ..)
    | client_connection.Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Moving(..)
    | client_connection.Removed
    | client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastMissed(..)
    | client_connection.CastFinished(..)
    | client_connection.CreatureMoved(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..) -> session
  }
  case strike.holds(strike: entered.strike, unit_id:) {
    True ->
      Continue(
        with_strike(
          session:,
          strike: strike.hold(strike: entered.strike, unit_id:, news:),
        ),
        [],
      )
    False ->
      Continue(
        session,
        creature_news_frames(session:, entered:, unit_id:, news:),
      )
  }
}

/// The frame of a creature's news, when its client still shows the creature: 0x937
/// for its health, 0x88c for its death.
fn creature_news_frames(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
  news news: client_connection.News,
) -> List(Effect(ConnectionEffect(Request))) {
  use <- bool.guard(when: !dict.has_key(entered.shown, unit_id), return: [])
  case news {
    client_connection.Health(health:, dead:) -> {
      let assert Ok(body) =
        unit_health.encode(
          UnitHealth(unit_id:, health:, dead: case dead {
            True -> 1
            False -> 0
          }),
        )
        as "a unit id of 32 bits, a health of 32 and a bit fit the message"
      [
        to_client(session, Frame(message_id: unit_health.message_id, body:)),
      ]
    }
    client_connection.Died -> {
      let assert Ok(body) =
        unit_death_state.encode(UnitDeathState(
          unit_id:,
          dead: 1,
          field_3: 0,
          field_4: 0,
        ))
        as "a unit id of 32 bits and the safe values fit the message (opcode.0x88c)"
      [
        to_client(
          session,
          Frame(message_id: unit_death_state.message_id, body:),
        ),
      ]
    }
    client_connection.Appeared(..)
    | client_connection.CreatureAppeared(..)
    | client_connection.Moving(..)
    | client_connection.Removed
    | client_connection.CastStarted(..)
    | client_connection.CastWent(..)
    | client_connection.CastMissed(..)
    | client_connection.CastFinished(..)
    | client_connection.CreatureMoved(..)
    | client_connection.Targeting(..)
    | client_connection.Threat(..)
    | client_connection.CombatState(..)
    | client_connection.Shield(..) -> []
  }
}

/// 0x7fe for each cast of the unit that this client was sent the start of and no
/// finish, in cast id order, written before the unit's 0x355: the client keeps a
/// cast that never gets its 0x7fe live (`cast.no_answer`), and a cast id used
/// again restarts it (`opcode.0x7ff`).
fn finishes_of_forgotten_casts(
  session session: Session,
  entered entered: world_entry.Entered,
  unit_id unit_id: Int,
) -> List(Effect(ConnectionEffect(Request))) {
  dict.to_list(entered.casts_written)
  |> list.filter(fn(written) { written.1 == unit_id })
  |> list.map(fn(written) { written.0 })
  |> list.sort(int.compare)
  |> list.map(fn(cast_id) { to_client(session, cast.finished_frame(cast_id:)) })
}

/// The player the client holds in this connection's world, while it holds one:
/// the player in the world, or in the world and waiting to claim again, where a
/// send is taken.
fn held_in_the_world(status: Status) -> Option(world_entry.Entered) {
  use <- bool.guard(when: !holds_the_world(status), return: None)
  entered_of(status)
}

/// The unit of the player's own record as another player is created with it: at
/// the place the player stands at now and stamped from the map's clock, from the
/// origin `Joined` carried (`map.server_time`).
fn appearance(
  entered entered: world_entry.Entered,
  now now: Now,
) -> UnitCreatePlayer {
  let #(position, rotation) =
    player_unit.standing(place: movement.place(entered.movement))
  UnitCreatePlayer(
    ..entered.unit,
    tail: UnitCreateTail(
      ..entered.unit.tail,
      movement_commands: [
        start_movement.Position(position),
        start_movement.Rotation(rotation),
      ],
      server_time_estimate_start: map.server_time(
        origin_ms: entered.clock_origin_ms,
        monotonic_ms: now.monotonic_ms,
      ),
    ),
  )
}

/// The tell of news about the player's own unit to the connection of a player
/// who sees it, in the run of the map the player is in.
fn news_to(
  entered entered: world_entry.Entered,
  viewer viewer: ConnectionId,
  news news: client_connection.News,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Connection(viewer),
    request: TellPeer(news: client_connection.PeerNews(
      map: entered.map,
      incarnation: entered.incarnation,
      unit_id: entered.unit_id,
      news:,
    )),
  ))
}

/// The tells that remove the player's own unit from the client of each player who
/// sees it, for its camp, which sends them before its leave is asked: the map's
/// `Unwatched` after the leave would be a second sender of news of the unit.
fn removes_its_unit_from_the_viewers(
  entered entered: world_entry.Entered,
) -> List(Effect(ConnectionEffect(Request))) {
  list.map(set.to_list(entered.viewers), fn(viewer) {
    news_to(entered:, viewer:, news: client_connection.Removed)
  })
}

/// The session with the player's viewers changed by `change`.
fn viewers_changed(
  session session: Session,
  change change: fn(Set(ConnectionId)) -> Set(ConnectionId),
) -> Session {
  with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, viewers: change(entered.viewers))
  })
}

/// The session with the units its client shows changed by `change`.
fn shown_changed(
  session session: Session,
  change change: fn(shown.Picture) -> shown.Picture,
) -> Session {
  with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, shown: change(entered.shown))
  })
}

/// The session with the unit no longer shown, the casts of it forgotten (the client is
/// written their finish before the unit's 0x355, `finishes_of_forgotten_casts`) and the
/// news held for it dropped.
fn unit_forgotten(session session: Session, unit_id unit_id: Int) -> Session {
  with_entered(session:, change: fn(entered) {
    world_entry.Entered(
      ..entered,
      shown: dict.delete(entered.shown, unit_id),
      casts_written: dict.filter(entered.casts_written, fn(_, caster) {
        caster != unit_id
      }),
      strike: strike.forget(strike: entered.strike, unit_id:),
    )
  })
}

/// The session with the unit marked gone, so it is shown no more, and no longer
/// shown.
fn marked_gone(session session: Session, unit_id unit_id: Int) -> Session {
  let session = unit_forgotten(session:, unit_id:)
  with_entered(session:, change: fn(entered) {
    world_entry.Entered(..entered, gone: set.insert(entered.gone, unit_id))
  })
}

/// The session with the player it holds in the world changed by `change`: the
/// player in the world, or in the world and waiting to claim again, where a send
/// is taken. A status that takes no send, since the shell takes none while an ask
/// is out, or that holds no player in the world, is as it was.
fn with_entered(
  session session: Session,
  change change: fn(world_entry.Entered) -> world_entry.Entered,
) -> Session {
  let status = case session.status {
    InWorld(holder:, entered:) -> InWorld(holder:, entered: change(entered))
    WaitingToClaim(holder:, resume: ResumeWorld(entered:), retries:) ->
      WaitingToClaim(
        holder:,
        resume: ResumeWorld(entered: change(entered)),
        retries:,
      )
    WaitingToClaim(resume: ResumeSelect, ..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey -> session.status
  }
  Session(..session, status:)
}

/// Whether the client holds the player in its world, so another unit's message
/// is written: the player is in the world, or its claim is made again with the
/// player in it. A claim with its ask out, a save and a leave take no send.
fn holds_the_world(status: Status) -> Bool {
  case status {
    InWorld(..) | WaitingToClaim(resume: ResumeWorld(..), ..) -> True
    WaitingToClaim(resume: ResumeSelect, ..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey -> False
  }
}

/// 0x638 for a move of another player's unit, with the reset bit 0 (the unit's
/// movement is not rebuilt) and the kept bit 0 (opcode.0x638).
fn unit_moved_frame(
  unit_id unit_id: Int,
  server_time_ms server_time_ms: Int,
  commands commands: List(RelayedMovement),
) -> Frame {
  let assert Ok(body) =
    unit_movement.encode(UnitMovement(
      unit_id:,
      server_time: server_time_ms,
      reset_movement: 0,
      kept: 0,
      commands:,
    ))
    as "a mover sends at most 31 commands and a time of 32 bits"
  Frame(message_id: unit_movement.message_id, body:)
}

/// 0x262 for a creature, as its process built it.
fn creature_created_frame(unit unit: UnitCreateCreature) -> Frame {
  let assert Ok(body) = unit_create_creature.encode(unit)
    as "a creature's values fit the message's fields: the spawn's checks hold each"
  Frame(message_id: unit_create_creature.message_id, body:)
}

/// 0x355 for another player's unit or a creature, with its one bit 0
/// (opcode.0x355).
fn unit_removed_frame(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_destroyed.encode(UnitDestroyed(unit_id:, field_2: 0))
    as "a unit id of 32 bits fits the message"
  Frame(message_id: unit_destroyed.message_id, body:)
}

/// The end of a watch the rule opened. Sessions' (`sessions_watch`): the
/// connection waits on the claim timer, then claims its account again from
/// where it is, in character select or in the world. The player's map
/// (`map_watch`): the player is gone from the world, so the client is told the
/// server failed (0x036A reason 8) and the connection ends. A watch this rule
/// did not open, or one that ends where the connection holds none, is a bug.
fn watch_ended(
  session session: Session,
  now now: Now,
  watch watch: WatchId,
) -> client_connection.Handled(Session) {
  case held_in_the_world(session.status) {
    Some(entered) ->
      case chat.watch_ended(chat: entered.chat, watch:) {
        Ok(#(updated, effects)) ->
          carry_chat(session: with_chat(session:, chat: updated), effects:)
        Error(Nil) -> own_watch_ended(session:, now:, watch:)
      }
    None -> own_watch_ended(session:, now:, watch:)
  }
}

/// The end of a watch the connection's own rule opened: Sessions or the map.
fn own_watch_ended(
  session session: Session,
  now now: Now,
  watch watch: WatchId,
) -> client_connection.Handled(Session) {
  case session.status, watch {
    InCharacterSelect(holder:, ..), id if id == sessions_watch ->
      waiting_to_claim(session:, holder:, resume: ResumeSelect)
    InWorld(holder:, entered:), id if id == sessions_watch ->
      waiting_to_claim(session:, holder:, resume: ResumeWorld(entered:))
    InWorld(..), id
    | ClaimingSession(resume: ResumeWorld(..), ..), id
    | WaitingToClaim(resume: ResumeWorld(..), ..), id
      if id == map_watch
    ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: "the map the player is in ended",
      )
    InCharacterSelect(..), _
    | InWorld(..), _
    | ClaimingSession(..), _
    | WaitingToClaim(..), _
    | EnteringWorld(..), _
    | SavingPlace(..), _
    | LeavingMap(..), _
    | AwaitingHelloReply, _
    | TakingSessionKey, _
    -> end_for(session:, now:, text: "a watch the rule did not open ended")
  }
}

/// The connection waits on the claim timer before it claims its account
/// again, with the place of the client kept. A player in the world is not
/// saved by the timer meanwhile: the save timer is cancelled, and a firing
/// already waiting is dropped by the shell.
fn waiting_to_claim(
  session session: Session,
  holder holder: Holder,
  resume resume: Resume,
) -> client_connection.Handled(Session) {
  let cancelled = case resume {
    ResumeSelect -> []
    ResumeWorld(..) -> [OwnEffect(CancelTimer(timer: save_timer))]
  }
  Done(
    Session(..session, status: WaitingToClaim(holder:, resume:, retries: 0)),
    list.append(cancelled, [
      OwnEffect(StartTimer(timer: claim_timer, after_ms: claim_wait_ms)),
    ]),
  )
}

/// The claim timer fired: the connection claims again. A timer the rule did
/// not start, or one that fires when the connection is not waiting on it, is
/// a bug.
fn claim_wait_over(
  session session: Session,
  now now: Now,
  timer timer: TimerId,
) -> client_connection.Handled(Session) {
  case session.status {
    WaitingToClaim(holder:, resume:, retries:) if timer == claim_timer ->
      claim(session:, now:, holder:, resume:, retries:)
    WaitingToClaim(..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | InWorld(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey ->
      end_for(session:, now:, text: "a timer the rule did not start fired")
  }
}

/// The save timer fired: the player's place is saved and the timer started
/// again, and the player goes on playing once the store answers. The timer
/// runs only while the player is in the world, so a firing in any other status
/// is a bug.
fn save_due(
  session session: Session,
  now now: Now,
) -> client_connection.Handled(Session) {
  case session.status {
    InWorld(holder:, entered:) ->
      saving(
        session:,
        now:,
        holder:,
        entered:,
        then: Playing,
        before: [start_save_timer()],
        within_ms: session.settings.ask_deadline_ms,
      )
    WaitingToClaim(..)
    | ClaimingSession(..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | SavingPlace(..)
    | LeavingMap(..)
    | AwaitingHelloReply
    | TakingSessionKey ->
      end_for(session:, now:, text: "a timer the rule did not start fired")
  }
}

/// Asks the store to save where the player stands, after the effects `before`,
/// with `within_ms` to be answered: the movement numbers the save, and the
/// connection waits in `SavingPlace` for the answer.
fn saving(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  then then: AfterSave,
  before before: List(Effect(ConnectionEffect(Request))),
  within_ms within_ms: Int,
) -> client_connection.Handled(Session) {
  let #(state, request) =
    movement.save(
      state: entered.movement,
      account_id: holder.account_id,
      character_id: entered.character_id,
    )
  ask_within(
    session: Session(
      ..session,
      status: SavingPlace(
        holder:,
        entered: world_entry.Entered(..entered, movement: state),
        then:,
      ),
    ),
    now:,
    request: AskStore(store.Move(request)),
    before:,
    within_ms:,
  )
}

/// The store's answer to the save of the player's place: what it says is
/// logged, and then the player goes on playing or the connection ends, as
/// `then` says. A save that gets no answer is a warning, as for any store ask.
/// The status of a connection that ends stays `SavingPlace`, so an input after
/// its notice, a failed write among them, never saves a second time.
fn save_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  then then: AfterSave,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  let lines = case outcome {
    step.Answer(FromStore(store.ForMove(answer))) ->
      Ok(list.map(movement.saved(answer), movement_line(session, _)))
    step.Answer(FromStore(store.Unavailable)) ->
      Ok([
        log(
          session:,
          level: LogWarning,
          text: "the place was not saved: the store is unavailable",
        ),
      ])
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      Ok([
        log(
          session:,
          level: LogWarning,
          text: "the place was not saved: "
            <> client_connection.without_answer(who: "the store", outcome:),
        ),
      ])
    step.StoppedWaiting -> Ok([])
    step.Answer(FromStore(store.ForLogin(..)))
    | step.Answer(FromStore(store.ForSelect(..)))
    | step.Answer(FromStore(store.ForWorld(..)))
    | step.Answer(FromHandOff(..))
    | step.Answer(FromSessions(..))
    | step.Answer(FromMap(..)) -> Error(Nil)
  }
  case then, lines {
    Playing, Ok(lines) ->
      case outcome {
        step.StoppedWaiting ->
          Done(Session(..session, status: InWorld(holder:, entered:)), [])
        step.Answer(..)
        | step.NotRunning
        | step.NoAnswerInTime
        | step.EndedBeforeAnswer ->
          Continue(
            Session(..session, status: InWorld(holder:, entered:)),
            lines,
          )
      }
    Playing, Error(Nil) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the answer is none a save of the player's place asked for",
      )
    Leaving(notice:), Ok(lines) -> left(session:, lines:, notice:)
    Leaving(notice:), Error(Nil) ->
      left(
        session:,
        lines: [
          log(
            session:,
            level: step.LogError,
            text: "the answer is none a save of the player's place asked for",
          ),
        ],
        notice:,
      )
    Camped, Ok(lines) ->
      case outcome {
        step.StoppedWaiting -> stopped(session, now)
        step.Answer(..)
        | step.NotRunning
        | step.NoAnswerInTime
        | step.EndedBeforeAnswer ->
          leaving_the_map(session:, now:, holder:, entered:, before: lines)
      }
    Camped, Error(Nil) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the answer is none a save of the player's place asked for",
      )
  }
}

/// The camp's save is answered: the map's run that took the player is asked to
/// take it out, after the effects `before`, and the connection waits in
/// `LeavingMap`.
fn leaving_the_map(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  before before: List(Effect(ConnectionEffect(Request))),
) -> client_connection.Handled(Session) {
  let before = list.append(before, removes_its_unit_from_the_viewers(entered:))
  ask(
    session: Session(..session, status: LeavingMap(holder:, entered:)),
    now:,
    request: AskMapRun(
      map: entered.map,
      incarnation: entered.incarnation,
      message: map.Leave(connection: client_connection.connection(session.link)),
    ),
    before:,
  )
}

/// The map's answer to the camp's leave ask: `Left`, a map that is not running
/// and a run that ended before its answer all put the client back in character
/// select with 0x0594, the map's watch dropped and a new character select; no
/// answer in time ends the connection with 0x036A reason 8, with no second
/// save; the server stopping ends it without one.
fn leave_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromMap(map.Left)) | step.NotRunning | step.EndedBeforeAnswer ->
      Continue(
        Session(
          ..session,
          status: InCharacterSelect(holder:, select: character_select.new()),
        ),
        [
          Unwatch(watch: map_watch),
          to_client(session, leave_world_frame()),
        ],
      )
    step.NoAnswerInTime ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "the map", outcome:),
      )
    step.StoppedWaiting -> stopped(session, now)
    step.Answer(FromMap(map.Joined(..)))
    | step.Answer(FromMap(map.NotJoined(..)))
    | step.Answer(FromMap(map.Watched(..)))
    | step.Answer(FromMap(map.Unwatched(..)))
    | step.Answer(FromMap(map.Gone(..)))
    | step.Answer(FromMap(map.Retire))
    | step.Answer(FromMap(map.Approached(..)))
    | step.Answer(FromMap(map.Withdrew(..)))
    | step.Answer(FromStore(..))
    | step.Answer(FromHandOff(..))
    | step.Answer(FromSessions(..)) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the answer is none the leave of the map asked for",
      )
  }
}

/// The connection ends after the save it waited for: the lines the answer made,
/// then the notice when there is one, then the end.
fn left(
  session session: Session,
  lines lines: List(Effect(ConnectionEffect(Request))),
  notice told: Option(DisconnectReason),
) -> client_connection.Handled(Session) {
  Done(
    session,
    list.flatten([
      lines,
      case told {
        Some(reason) -> [notice(session:, reason:)]
        None -> []
      },
      [Stop],
    ]),
  )
}

/// A line the movement's answer to the save gives, as a log line of the
/// connection.
fn movement_line(
  session: Session,
  effect: movement.Effect,
) -> Effect(ConnectionEffect(Request)) {
  case effect {
    movement.Fault(text:) -> log(session:, level: step.LogError, text:)
    movement.Note(text:) -> log(session:, level: LogInfo, text:)
  }
}

/// The store's answer to character select's ask: the failures every store ask
/// shares tell the client the server failed; any other answer is character
/// select's to take. A takeover that waits behind a failing ask is never taken
/// (the connection ends with this failure's text).
fn select_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  select select: character_select.State,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(store.Unavailable)) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: "the store is unavailable",
      )
    step.Answer(FromStore(store.ForSelect(answer))) ->
      select_taken(session:, now:, holder:, taken: case answer {
        store.Listed(characters:) ->
          character_select.listed(
            select,
            characters:,
            filetime: now.filetime,
            realm_id: session.settings.realm_id,
            max_characters: session.settings.max_characters,
            character_slots: session.settings.game.character_slots,
            tables: session.settings.tables,
          )
        store.Created(answer:) -> character_select.created(select, answer)
        store.Deleted(answer:) -> character_select.deleted(select, answer)
        store.Renamed(answer:) -> character_select.renamed(select, answer)
      })
    step.Answer(FromStore(store.ForLogin(..)))
    | step.Answer(FromStore(store.ForWorld(..)))
    | step.Answer(FromStore(store.ForMove(..))) ->
      select_taken(session:, now:, holder:, taken: Error(Nil))
    step.Answer(FromHandOff(..)) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the hand-off's answer is none a store ask gets",
      )
    step.Answer(FromSessions(..)) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "Sessions' answer is none a store ask gets",
      )
    step.Answer(FromMap(..)) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "a map's answer is none a store ask gets",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(who: "the store", outcome:),
      )
    step.StoppedWaiting -> stopped(session, now)
  }
}

/// What character select made of the store's answer: its new state and
/// effects carried out, or, for an answer it has no ask for, the client told
/// the server failed.
fn select_taken(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  taken taken: Result(
    #(character_select.State, List(character_select.Effect)),
    Nil,
  ),
) -> client_connection.Handled(Session) {
  case taken {
    Ok(step) -> select_step(session:, now:, holder:, step:)
    Error(Nil) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: step.LogError,
        text: "the store's answer is none character select asked for",
      )
  }
}

/// The answer to world entry's ask, which is the store's or the map's: the
/// failures every ask shares tell the client the server failed; any other
/// answer is world entry's to take. A refusal hands the client back to
/// character select.
fn entry_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entry entry: world_entry.State,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(store.Unavailable)) ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: "the store is unavailable",
      )
    step.Answer(FromStore(store.ForWorld(answer))) ->
      case
        world_entry.loaded(
          entry,
          answer:,
          connection: client_connection.connection(session.link),
        )
      {
        Ok(world_entry.Join(state:, effects:)) ->
          carry_out(
            session: Session(
              ..session,
              status: EnteringWorld(holder:, entry: state),
            ),
            now:,
            effects: list.map(effects, from_entry),
            written: [],
          )
        Ok(world_entry.Refused(character_id:, warning:)) ->
          select_step(
            session:,
            now:,
            holder:,
            step: refused_play(holder:, character_id:, warning:),
          )
        Error(Nil) -> entry_unasked(session, now)
      }
    step.Answer(FromMap(answer)) ->
      case
        world_entry.joined(
          entry,
          answer:,
          realm_id: session.settings.realm_id,
          next_whisper: session.next_whisper,
        )
      {
        Ok(world_entry.InTheWorld(entered:, effects:)) ->
          in_the_world(session:, now:, holder:, entered:, effects:)
        Ok(world_entry.NotInTheWorld(character_id:, warning:)) ->
          select_step(
            session:,
            now:,
            holder:,
            step: refused_play(holder:, character_id:, warning:),
          )
        Error(Nil) -> entry_unasked(session, now)
      }
    step.Answer(FromStore(store.ForLogin(..)))
    | step.Answer(FromStore(store.ForSelect(..)))
    | step.Answer(FromStore(store.ForMove(..)))
    | step.Answer(FromHandOff(..))
    | step.Answer(FromSessions(..)) -> entry_unasked(session, now)
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      told(
        session:,
        now:,
        reason: LostUserServer,
        level: LogWarning,
        text: client_connection.without_answer(
          who: case world_entry.awaiting(entry) {
            world_entry.AwaitingStore -> "the store"
            world_entry.AwaitingMap -> "the map"
          },
          outcome:,
        ),
      )
    step.StoppedWaiting -> stopped(session, now)
  }
}

/// An answer that is none world entry asked for: a bug, so the client is told
/// the server failed.
fn entry_unasked(
  session: Session,
  now: Now,
) -> client_connection.Handled(Session) {
  told(
    session:,
    now:,
    reason: LostUserServer,
    level: step.LogError,
    text: "the answer is none world entry asked for",
  )
}

/// The play world entry refused: a warning, then character select sends 0x0162
/// and asks for the list again.
fn refused_play(
  holder holder: Holder,
  character_id character_id: Int,
  warning warning: String,
) -> #(character_select.State, List(character_select.Effect)) {
  let #(select, effects) =
    character_select.play_refused(account_id: holder.account_id, character_id:)
  #(select, [character_select.Warn(text: warning), ..effects])
}

/// The player is in the world: the messages that put it there are written,
/// its map is watched and its place is saved every `movement.save_period_ms`.
fn in_the_world(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  effects effects: List(world_entry.Effect),
) -> client_connection.Handled(Session) {
  let #(updated, burst) =
    chat.entered_world(
      chat: entered.chat,
      world_zone_id: start_place.world_zone_id(movement.place(entered.movement)),
      top_zones: top_zone.top_zones(session.settings.tables),
    )
  carry_out(
    session: Session(
      ..session,
      status: InWorld(
        holder:,
        entered: world_entry.Entered(..entered, chat: updated),
      ),
    ),
    now:,
    effects: list.flatten([
      list.map(effects, from_entry),
      [Chats(effects: burst), StartsSaveTimer],
    ]),
    written: [],
  )
}

/// What an end writes and logs, besides the save of the player's place: a log
/// line and the notice 0x036A with a reason, each when there is one.
type Ending {
  Ending(
    log: Option(#(step.LogLevel, String)),
    notice: Option(DisconnectReason),
  )
}

/// The one end of a connection, for every cause. A connection that holds a
/// player in the world (`holds_a_player`) first asks the store to save where the
/// player stands, with `within_ms` to be answered, and ends when the answer
/// comes, whatever it is (`save_answered`); the log line comes before the ask,
/// the notice after the answer. A connection with no player, or one whose save
/// is already out, ends at once, so no end saves twice. When `within_ms` is
/// 0 or less, as the server's stop can leave it, no ask is made, and a warning
/// says the place was not saved.
fn end_with(
  session session: Session,
  now now: Now,
  ending ending: Ending,
  within_ms within_ms: Int,
) -> client_connection.Handled(Session) {
  let reason_line = case ending.log {
    Some(#(level, text)) -> [log(session:, level:, text:)]
    None -> []
  }
  case holds_a_player(session.status) {
    None -> left(session:, lines: reason_line, notice: ending.notice)
    Some(_) if within_ms <= 0 ->
      left(
        session:,
        lines: list.append(reason_line, [
          log(
            session:,
            level: LogWarning,
            text: "the place was not saved: no time was left before the stop's deadline",
          ),
        ]),
        notice: ending.notice,
      )
    Some(#(holder, entered)) ->
      saving(
        session:,
        now:,
        holder:,
        entered:,
        then: Leaving(notice: ending.notice),
        before: reason_line,
        within_ms:,
      )
  }
}

/// The player the connection holds in the world and the holder it plays for,
/// when its place is to be saved by an end: in the world, or claiming its
/// account again with the player in the world. A connection already in
/// `SavingPlace` holds the player too, but its save is out, so its end saves
/// nothing more; in `LeavingMap` the place is already saved.
fn holds_a_player(status: Status) -> Option(#(Holder, world_entry.Entered)) {
  case status {
    InWorld(holder:, entered:)
    | ClaimingSession(holder:, resume: ResumeWorld(entered:), ..)
    | WaitingToClaim(holder:, resume: ResumeWorld(entered:), ..) ->
      Some(#(holder, entered))
    SavingPlace(..)
    | LeavingMap(..)
    | ClaimingSession(resume: ResumeSelect, ..)
    | WaitingToClaim(resume: ResumeSelect, ..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | AwaitingHelloReply
    | TakingSessionKey -> None
  }
}

/// The connection ends after 0x036A with the reason, and a log line saying
/// why.
fn told(
  session session: Session,
  now now: Now,
  reason reason: DisconnectReason,
  level level: step.LogLevel,
  text text: String,
) -> client_connection.Handled(Session) {
  end_with(
    session:,
    now:,
    ending: Ending(log: Some(#(level, text)), notice: Some(reason)),
    within_ms: session.settings.ask_deadline_ms,
  )
}

/// The server is stopping while an ask is out: the client is told, with no
/// log line, since a stop is no failure.
fn stopped(session: Session, now: Now) -> client_connection.Handled(Session) {
  end_with(
    session:,
    now:,
    ending: Ending(log: None, notice: Some(LostUserServer)),
    within_ms: session.settings.ask_deadline_ms,
  )
}

/// The client broke the protocol: an error log line and the end of the
/// connection, with nothing written to a client that is no client.
fn end_for(
  session session: Session,
  now now: Now,
  text text: String,
) -> client_connection.Handled(Session) {
  end_with(
    session:,
    now:,
    ending: Ending(log: Some(#(step.LogError, text)), notice: None),
    within_ms: session.settings.ask_deadline_ms,
  )
}

// ---- log lines ----

fn log(
  session session: Session,
  level level: step.LogLevel,
  text text: String,
) -> Effect(ConnectionEffect(Request)) {
  client_connection.log(about: about_of(session), level:, text:)
}

/// What a log line of the connection is about: the connection, the peer and
/// the account once the hand-off has named it; in the world also the map and
/// the character.
fn about_of(session: Session) -> About {
  let about =
    client_connection.about(
      session.link,
      account_id: account_id_of(session.status),
    )
  case entered_of(session.status) {
    Some(world_entry.Entered(character_id: store.CharacterId(id), map:, ..)) ->
      About(..about, character_id: Some(id), map: Some(map))
    None -> about
  }
}

/// The player in the world, while the connection holds one.
fn entered_of(status: Status) -> Option(world_entry.Entered) {
  case status {
    InWorld(entered:, ..)
    | SavingPlace(entered:, ..)
    | LeavingMap(entered:, ..)
    | ClaimingSession(resume: ResumeWorld(entered:), ..)
    | WaitingToClaim(resume: ResumeWorld(entered:), ..) -> Some(entered)
    ClaimingSession(resume: ResumeSelect, ..)
    | WaitingToClaim(resume: ResumeSelect, ..)
    | InCharacterSelect(..)
    | EnteringWorld(..)
    | AwaitingHelloReply
    | TakingSessionKey -> None
  }
}

/// The id of the account the connection is for, once the hand-off has named
/// the holder.
fn account_id_of(status: Status) -> Option(Int) {
  case status {
    InCharacterSelect(
      holder: hand_off.Holder(account_id: store.AccountId(id), ..),
      ..,
    )
    | EnteringWorld(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | InWorld(holder: hand_off.Holder(account_id: store.AccountId(id), ..), ..)
    | SavingPlace(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | LeavingMap(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | ClaimingSession(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      )
    | WaitingToClaim(
        holder: hand_off.Holder(account_id: store.AccountId(id), ..),
        ..,
      ) -> Some(id)
    AwaitingHelloReply | TakingSessionKey -> None
  }
}
