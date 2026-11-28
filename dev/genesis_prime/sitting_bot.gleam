//// The sitting bot: a second player for a live sitting, played against a server
//// that is already running, so the person at the real client sees another
//// character appear in the same map, move, talk and leave.
////
//// ```
//// gleam run -m genesis_prime/sitting_bot -- --near "<character name>" [--minutes N] [--walk follow|circle] [--as "<bot character name>"] [--press "<ability name or Spell4Base id>" --at "<character name>" [--press-every SECONDS]]
//// ```
////
//// ```
////  the play database ◀── seat ── this tool ── TCP, as a client ──▶ the play server
////  (the named character's        │  sit: log in, enter, walk (follow the named
////   place, the bot's own)        │  character's moves or a circle), a chat line
////                                │  every 10 s, a whisper every 30 s, read what
////                                ▼  the server writes, print one line each
////                          stdout, and a summary when it leaves
////
////  --press: the faction of --at ─▶ ability.resolve ─▶ ability.equip (class, level,
////  faction, Novice set) ─▶ every --press-every s, 0x009A at --at's unit while in sight
//// ```
////
//// The database is the one the server uses, from PGHOST, PGPORT, PGUSER,
//// PGPASSWORD and PGDATABASE (so the play server's `genesis_play`); the server
//// is on this machine at the client's own ports, 6600 (STS), 23115 (auth) and
//// 24000 (game), which is where the play server listens whatever address it
//// hands the client (GENESIS_PLAY_ADDRESS, GENESIS_GAME_ADDRESS). The tool is
//// refused when the named character does not exist or has no saved place.
////
//// - The bot is the account `sitting-bot` with its character `Sitting Bot`, made
////   on the first run and used again after it, in one transaction that leaves one
////   of each however many runs begin together (`genesis_prime/add_account`'s
////   credentials; race 1, sex 1, class 1 and faction 167 of CharacterCreation
////   row 466). Before it logs in, its saved place is put at
////   the named character's own, in the same world and zone. Only a character of
////   the account `sitting-bot` is taken for the bot's or moved: a character of
////   that name that another account has refuses the run. `--as` gives the bot
////   another character name and so another account (`sitting-bot-` and the name
////   in lower case with hyphens), which is how a second bot runs beside the first.
//// - It logs in and enters the world as the load player does
////   (`genesis_prime/load_player`), reports the zone it stands in (0xF2) as the
////   client does when its terrain loads, and walks. `--walk follow` (the
////   default) replays the named character's own movement commands 2 s later, on
////   the same path (`genesis_prime/sitting_bot/follow`), so the bot walks on the
////   ground the real client walked, animated by the commands that client sent,
////   and stands still while the character does. `--walk circle` walks a
////   circle of 3 units through its place, a move (0x0637) every 125 ms, the
////   client's own send interval (opcode.0xf1), for when no one is there to
////   follow.
//// - Every 10 s it sends one chat line in turn on Say, Yell, Emote and Zone, each
////   text naming the channel and the number of the line ("bot say 1"), and every
////   30 s a whisper to the named character ("bot whisper 1"). Its chat message
////   ids count from 1, as the client's do (0x140405cb0).
//// - It prints a line with the time for each unit it is shown (0x0262), the
////   first move of another unit and every 20th after it (0x0638), each removal
////   (0x0355), each chat line it reads (0x01C8), each answer to its own lines
////   (0x01C2, 0x01D3, 0x01D9), and each line that shows no sender name, where the
////   client would send 0x0597 to ask for it (chat.name_lookup).
//// - It prints a line for each cast message it is told, from its entry on (0x07FC, 0x07FD, 0x07FF,
////   0x07FE), each go (0x07F4) and tick (0x07F8) with the heal or hit of each
////   effect (its amount, overheal, absorbed and shield absorbed), each unit
////   taken off a cast (0x0811), its own health (0x092F), each stat that
////   changes (0x0938: level, shield, interrupt armor, absorption) and each
////   property change (0x093A), which is how a buff sets and restores them. A line
////   names the spell and caster as the cast's own 0x07FF gave them
////   (`genesis_prime/sitting_bot/effects`). Without `--press` the bot presses
////   nothing and stays as its last run left its class, level and faction (a new
////   bot is class 1, faction 167), so a person presses at it; a spell refused
////   between factions (99) never reaches it.
//// - `--press` and `--at` come together. Before the bot is seated, the faction of
////   the `--at` character is read, and the ability is found among what each class
////   holds at that faction (`genesis_prime/sitting_bot/ability`: a name in en-US.bin
////   in any case, or a Spell4Base id; a name two classes or bases hold is refused
////   with the choices listed). The bot's character is then made that class at the
////   level that gives the ability, in that faction, with that class's Novice set
////   and no saved bar, and it enters the world reading the bag index the server
////   gives the ability (the 0x0111 messages of the entry, opcode.0x9a). The tables
////   and the language file are read from `GENESIS_TABLE_DIR` and
////   `GENESIS_CLIENT_FILES_DIR` (about 7 s). `--at` naming the bot is refused.
//// - Every `--press-every` seconds (20 when not given) after the start, while the
////   `--at` character's unit is in sight (shown by 0x0262, not yet removed by
////   0x0355), it sends a press (0x009A) naming that unit, with its own cast ids
////   from 2 counting up (0x140c1e71c), and prints "sent press"; a press due while
////   the character is not in sight prints "press skipped" and sends nothing. What
////   the server answers prints as the cast lines above (a refusal 0x07FC with its
////   result number). Gap: the bot sends no facing, so a Targeted spell with an arc
////   of less than 360 degrees is refused 101 when it stands on its target's point.
//// - It ends after `--minutes` (30 when not given), on SIGTERM, or when the
////   server closes its connection. It prints the node's process id when it starts
////   (`stop with: kill <pid>`): SIGTERM must go to that pid, since `gleam run`
////   does not pass a signal on to the node it starts. When it ends it closes its
////   own connection, so the player sees its unit go, and prints how many lines
////   it sent, answers it got, lines it heard, units it was shown, effects it was
////   told and presses it sent. The Erlang runtime cannot catch Ctrl-C (SIGINT) as
////   a signal: it opens the VM's break menu, whose `a` ends the node with the
////   connection closed by the operating system, so the player sees the bot
////   leave, and no summary is printed.

import argv
import game_client.{type Chatter, type Game, type HeardLine}
import genesis_prime/add_account
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/dev_database
import genesis_prime/load_player.{type Account, Account}
import genesis_prime/message/chat_channel_result
import genesis_prime/message/chat_line_accepted
import genesis_prime/message/chat_result
import genesis_prime/message/relayed_movement
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_movement
import genesis_prime/message/whisper_failed
import genesis_prime/shared/chat_channel.{type ChannelType}
import genesis_prime/sitting_bot/ability
import genesis_prime/sitting_bot/effects.{type Book, type Effect}
import genesis_prime/sitting_bot/follow.{type Following}
import genesis_prime/sitting_bot/sql
import genesis_prime/step/runtime
import gleam/erlang/process.{type Pid}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import gleam_community/maths
import login_client.{type Ports, Ports}
import mug
import pog

// ---- what the bot is run with ----

/// What the tool is given: the name of the character to sit near, how long to
/// sit, how to walk, the bot's own character name, and the ability to press at
/// a named player with how often.
type Options {
  Options(
    near: String,
    minutes: Int,
    walk: Walk,
    bot_name: String,
    press: Option(PressOptions),
  )
}

/// `--press` and `--at`: the ability's name or Spell4Base id, the player it is
/// pressed at, and the seconds between presses.
type PressOptions {
  PressOptions(ability: String, at: String, every_s: Int)
}

/// How the bot walks.
pub type Walk {
  /// Replay the named character's movement commands, delayed by `delay_ms`
  /// after the server stamped them.
  Follow(delay_ms: Int)
  /// A circle through the bot's place, a move every `move_every_ms`.
  Circle(move_every_ms: Int)
}

/// The follow walk's own delay: 2 s.
const client_follow = Follow(delay_ms: 2000)

/// The circle walk's own interval: the client's movement send interval, 125 ms
/// (opcode.0xf1).
pub const client_circle = Circle(move_every_ms: 125)

/// Why the arguments are not a run.
type Usage {
  MissingNear
  NotMinutes(text: String)
  NotAWalk(text: String)
  NotSeconds(text: String)
  MissingValue(flag: String)
  PressNeedsAt
  AtNeedsPress
  AtIsTheBot(name: String)
  UnknownArgument(text: String)
}

/// How long the bot sits when it is not told, in minutes.
const default_minutes = 30

/// How long the bot waits between presses when it is not told, in seconds.
const default_press_every_s = 20

/// The arguments read so far.
type Raw {
  Raw(
    near: Option(String),
    minutes: Int,
    walk: Walk,
    bot_name: String,
    ability: Option(String),
    at: Option(String),
    press_every_s: Int,
  )
}

/// The options the arguments make: `--near <name>` and, optionally, `--minutes
/// <N>` for N of 1 or more, `--walk follow` or `--walk circle` (follow when
/// not given), `--as <character name>` for the bot's own character, and `--press
/// <ability>` with `--at <name>`, which come together, and `--press-every <N>`
/// seconds for N of 1 or more.
fn parse_arguments(arguments: List(String)) -> Result(Options, Usage) {
  parse(
    arguments:,
    raw: Raw(
      near: None,
      minutes: default_minutes,
      walk: client_follow,
      bot_name: default_character_name,
      ability: None,
      at: None,
      press_every_s: default_press_every_s,
    ),
  )
}

fn parse(
  arguments arguments: List(String),
  raw raw: Raw,
) -> Result(Options, Usage) {
  case arguments {
    [] -> finished(raw:)
    ["--near", name, ..rest] if name != "" ->
      parse(arguments: rest, raw: Raw(..raw, near: Some(name)))
    ["--near", ..] -> Error(MissingNear)
    ["--minutes", text, ..rest] ->
      case int.parse(text) {
        Ok(minutes) if minutes >= 1 ->
          parse(arguments: rest, raw: Raw(..raw, minutes:))
        Ok(_) | Error(Nil) -> Error(NotMinutes(text:))
      }
    ["--minutes"] -> Error(NotMinutes(text: ""))
    ["--walk", "follow", ..rest] ->
      parse(arguments: rest, raw: Raw(..raw, walk: client_follow))
    ["--walk", "circle", ..rest] ->
      parse(arguments: rest, raw: Raw(..raw, walk: client_circle))
    ["--walk", text, ..] -> Error(NotAWalk(text:))
    ["--walk"] -> Error(NotAWalk(text: ""))
    ["--as", name, ..rest] if name != "" ->
      parse(arguments: rest, raw: Raw(..raw, bot_name: name))
    ["--as", ..] -> Error(MissingValue(flag: "--as"))
    ["--press", ability, ..rest] if ability != "" ->
      parse(arguments: rest, raw: Raw(..raw, ability: Some(ability)))
    ["--press", ..] -> Error(MissingValue(flag: "--press"))
    ["--at", name, ..rest] if name != "" ->
      parse(arguments: rest, raw: Raw(..raw, at: Some(name)))
    ["--at", ..] -> Error(MissingValue(flag: "--at"))
    ["--press-every", text, ..rest] ->
      case int.parse(text) {
        Ok(press_every_s) if press_every_s >= 1 ->
          parse(arguments: rest, raw: Raw(..raw, press_every_s:))
        Ok(_) | Error(Nil) -> Error(NotSeconds(text:))
      }
    ["--press-every"] -> Error(NotSeconds(text: ""))
    [other, ..] -> Error(UnknownArgument(text: other))
  }
}

/// The options the arguments read make, or what is wrong with them.
fn finished(raw raw: Raw) -> Result(Options, Usage) {
  use near <- result.try(option.to_result(raw.near, MissingNear))
  use press <- result.map(case raw.ability, raw.at {
    None, None -> Ok(None)
    Some(_), None -> Error(PressNeedsAt)
    None, Some(_) -> Error(AtNeedsPress)
    Some(ability), Some(at) ->
      case string.lowercase(at) == string.lowercase(raw.bot_name) {
        True -> Error(AtIsTheBot(name: at))
        False ->
          Ok(Some(PressOptions(ability:, at:, every_s: raw.press_every_s)))
      }
  })
  Options(
    near:,
    minutes: raw.minutes,
    walk: raw.walk,
    bot_name: raw.bot_name,
    press:,
  )
}

fn describe_usage(usage: Usage) -> String {
  let how =
    "usage: gleam run -m genesis_prime/sitting_bot -- --near \"<character name>\" [--minutes N] [--walk follow|circle] [--as \"<bot character name>\"] [--press \"<ability name or Spell4Base id>\" --at \"<character name>\" [--press-every SECONDS]]"
  case usage {
    MissingNear -> "no character to sit near is named\n" <> how
    NotMinutes(text:) ->
      "--minutes takes a whole number of 1 or more, not \""
      <> text
      <> "\"\n"
      <> how
    NotAWalk(text:) ->
      "--walk takes follow or circle, not \"" <> text <> "\"\n" <> how
    NotSeconds(text:) ->
      "--press-every takes a whole number of seconds of 1 or more, not \""
      <> text
      <> "\"\n"
      <> how
    MissingValue(flag:) -> flag <> " takes a value\n" <> how
    PressNeedsAt ->
      "--press takes --at, the character it is pressed at\n" <> how
    AtNeedsPress -> "--at takes --press, the ability pressed at it\n" <> how
    AtIsTheBot(name:) ->
      "--at names the bot's own character, " <> name <> "\n" <> how
    UnknownArgument(text:) ->
      "not an argument of the tool: " <> text <> "\n" <> how
  }
}

// ---- where the bot is seated ----

/// A place in a world: the world and zone rows and the position (y is up).
pub type Place {
  Place(world_id: Int, world_zone_id: Int, x: Float, y: Float, z: Float)
}

/// The bot's character, the account it logs in with and the place it was put at.
pub type Seat {
  Seat(character_id: Int, account: Account, place: Place)
}

/// Why the bot was not seated.
pub type SeatFailure {
  /// No character has the name.
  NoSuchCharacter(name: String)
  /// The character is saved in no world (world 0 is no place), so there is no
  /// world to put the bot in.
  NoSavedPlace(name: String)
  Database(failure: dev_database.Failure)
}

/// The bot's character's name when `--as` gives none, which names no other:
/// character names are unique.
const default_character_name = "Sitting Bot"

/// The account of the bot's character with the name: `sitting-bot` for the
/// default name, else `sitting-bot-` and the name in lower case with its spaces
/// as hyphens, so a second bot is a second account. The password is kept in the
/// open: the account exists only in a developer's database, and the tool is no
/// way to anything else.
fn account_of(character_name character_name: String) -> Account {
  let login_name = case character_name == default_character_name {
    True -> "sitting-bot"
    False ->
      "sitting-bot-"
      <> string.replace(string.lowercase(character_name), " ", "-")
  }
  Account(login_name:, password: "sitting-bot", seed: 1, character_name:)
}

/// Puts the bot's character at the named character's saved place, in its world
/// and zone, and gives the bot's character and the place. The bot's account and
/// character are made when the database has none, and used when it has; a name
/// that no character has, a character with no saved place, or a "Sitting Bot"
/// that another account has, is refused and changes nothing.
pub fn seat(
  pool pool: pog.Connection,
  near name: String,
) -> Result(Seat, SeatFailure) {
  seat_as(pool:, near: name, character_name: default_character_name)
}

/// `seat` for the bot whose character has this name (`--as`), on the account
/// that name gives.
fn seat_as(
  pool pool: pog.Connection,
  near name: String,
  character_name character_name: String,
) -> Result(Seat, SeatFailure) {
  let bot = account_of(character_name:)
  use place <- result.try(place_of(pool:, name:))
  use character_id <- result.try(bot_character(pool:, bot:))
  use rows <- result.try(
    sql.seat_character(
      pool,
      character_id,
      place.world_id,
      place.world_zone_id,
      place.x,
      place.y,
      place.z,
      bot.login_name,
    )
    |> result.map_error(database),
  )
  case rows.rows {
    [_] -> Ok(Seat(character_id:, account: bot, place:))
    _ ->
      Error(
        Database(failure: dev_database.NotChanged(
          "the bot's character has no row",
        )),
      )
  }
}

fn database(error: pog.QueryError) -> SeatFailure {
  Database(failure: dev_database.failure_of(error:))
}

/// Where the character with the name is saved.
fn place_of(
  pool pool: pog.Connection,
  name name: String,
) -> Result(Place, SeatFailure) {
  use rows <- result.try(
    sql.character_place(pool, name) |> result.map_error(database),
  )
  case rows.rows {
    [] -> Error(NoSuchCharacter(name:))
    [row, ..] if row.world_id == 0 -> Error(NoSavedPlace(name:))
    [row, ..] ->
      Ok(Place(
        world_id: row.world_id,
        world_zone_id: row.world_zone_id,
        x: row.position_x,
        y: row.position_y,
        z: row.position_z,
      ))
  }
}

/// The id of the bot's character. One transaction makes the bot's account unless
/// it is there (`on conflict do nothing`), takes the account's row lock, makes the
/// character unless the account has it, gives a character that holds nothing
/// its Novice set, and reads it, so a run that begins beside
/// another waits at the lock and finds the character the other made. A
/// "Sitting Bot" that another account holds breaks the name's unique index, the
/// transaction is undone and nothing is made.
fn bot_character(
  pool pool: pog.Connection,
  bot bot: Account,
) -> Result(Int, SeatFailure) {
  let character_name = bot.character_name
  let add_account.Credentials(salt:, verifier:, game_account_id:) =
    add_account.credentials(login_name: bot.login_name, password: bot.password)
  let read =
    pog.transaction(pool, fn(connection) {
      use _ <- result.try(sql.insert_bot_account(
        connection,
        bot.login_name,
        salt,
        verifier,
        game_account_id,
      ))
      use _ <- result.try(sql.lock_bot_account(connection, bot.login_name))
      use _ <- result.try(sql.insert_bot_character(
        connection,
        bot.login_name,
        character_name,
      ))
      use _ <- result.try(sql.insert_bot_items(
        connection,
        bot.login_name,
        character_name,
      ))
      sql.account_character(connection, bot.login_name, character_name)
    })
    |> result.map_error(fn(error) {
      case error {
        pog.TransactionQueryError(error) | pog.TransactionRolledBack(error) ->
          database(error)
      }
    })
  use rows <- result.try(read)
  case rows.rows {
    [row, ..] -> Ok(row.character_id)
    [] ->
      Error(
        Database(failure: dev_database.NotChanged(
          "the bot's character has no row",
        )),
      )
  }
}

// ---- what the bot sends, and when ----

/// How the bot walks and how often it does each other duty, in milliseconds,
/// and the press it makes, if any.
pub type Schedule {
  Schedule(
    walk: Walk,
    chat_every_ms: Int,
    whisper_every_ms: Int,
    press: Option(Press),
  )
}

/// An ability the bot presses at a named player, every `every_ms` while that
/// player is in sight: the Spell4Base id of the ability the bot holds and the
/// player's name.
pub type Press {
  Press(spell4_base_id: Int, at: String, every_ms: Int)
}

/// The walk, a chat line every 10 s and a whisper every 30 s, and no press.
pub fn client_schedule(walk walk: Walk) -> Schedule {
  Schedule(walk:, chat_every_ms: 10_000, whisper_every_ms: 30_000, press: None)
}

/// How many of each duty the bot has done.
type Done {
  Done(moves: Int, lines: Int, whispers: Int, presses: Int)
}

/// A chat line to send: its channel and its text.
type Line {
  Line(channel: ChannelType, text: String)
}

/// One thing the bot does at its time.
type Duty {
  /// The bot's `number`th move, counting from 0.
  Move(number: Int)
  /// A chat line.
  Chat(line: Line)
  /// The bot's `number`th whisper, counting from 1.
  Whisper(number: Int)
  /// The bot's `number`th press, counting from 1.
  PressAt(number: Int)
}

/// The channels the chat lines go on, in turn.
const chat_turns = [
  chat_channel.Say,
  chat_channel.Yell,
  chat_channel.Emote,
  chat_channel.Zone,
]

/// The `number`th chat line, counting from 1: the channels in turn, and a text
/// that names the channel and counts the lines.
fn chat_line(number: Int) -> Line {
  let assert Ok(channel) =
    list.drop(chat_turns, { number - 1 } % list.length(chat_turns))
    |> list.first
    as "the turns are not empty"
  Line(
    channel:,
    text: "bot " <> channel_name(channel) <> " " <> int.to_string(number),
  )
}

/// The next duty and the time it is due, in milliseconds from the start: the
/// first move of a circle is due at 0, the first chat line, the first whisper and
/// the first press after one of their own intervals. Duties due together go chat,
/// whisper, press, move.
/// A follow walk has no move duty: its moves are replays (`follow`).
fn next_duty(schedule schedule: Schedule, done done: Done) -> #(Int, Duty) {
  let line = done.lines + 1
  let whisper = done.whispers + 1
  let presses = done.presses + 1
  let talks = [
    #(line * schedule.chat_every_ms, Chat(line: chat_line(line))),
    #(whisper * schedule.whisper_every_ms, Whisper(number: whisper)),
    ..case schedule.press {
      Some(press) -> [#(presses * press.every_ms, PressAt(number: presses))]
      None -> []
    }
  ]
  let candidates = case schedule.walk {
    Circle(move_every_ms:) ->
      list.append(talks, [
        #(done.moves * move_every_ms, Move(number: done.moves)),
      ])
    Follow(..) -> talks
  }
  let assert [first, ..rest] = candidates as "there are duties"
  list.fold(rest, first, fn(earliest, candidate) {
    case candidate.0 < earliest.0 {
      True -> candidate
      False -> earliest
    }
  })
}

/// What the bot has done after one more duty.
fn after(done done: Done, duty duty: Duty) -> Done {
  case duty {
    Move(..) -> Done(..done, moves: done.moves + 1)
    Chat(..) -> Done(..done, lines: done.lines + 1)
    Whisper(..) -> Done(..done, whispers: done.whispers + 1)
    PressAt(..) -> Done(..done, presses: done.presses + 1)
  }
}

/// How many moves the circle has, so a turn takes 8 s at one move every 125 ms.
const circle_steps = 64

/// The circle's radius in units.
const circle_radius = 3.0

/// The bot's position at its `step`th move: a circle in the ground's plane (x
/// and z; y is up) whose first step is `start` and whose centre is one radius
/// along -x from it, `circle_steps` moves to a turn.
fn circle_position(
  start start: Place,
  step step: Int,
) -> #(Float, Float, Float) {
  let angle =
    maths.tau()
    *. int.to_float(step % circle_steps)
    /. int.to_float(circle_steps)
  #(
    start.x -. circle_radius +. circle_radius *. maths.cos(angle),
    start.y,
    start.z +. circle_radius *. maths.sin(angle),
  )
}

// ---- what the bot reads, prints and sums ----

/// One thing the bot found worth a line: something it sent or read.
pub type Event {
  /// A line the bot sent: the channel's name, its chat message id and its text.
  LineSent(channel: String, chat_message_id: Int, text: String)
  /// 0x0262: a unit shown to the bot.
  UnitShown(unit_id: Int, name: String)
  /// 0x0638: a unit moved.
  UnitMoved(
    unit_id: Int,
    server_time: Int,
    commands: List(relayed_movement.RelayedMovement),
  )
  /// 0x0355: a unit removed.
  UnitRemoved(unit_id: Int)
  /// 0x01C8: a line another player said.
  LineHeard(line: HeardLine)
  /// 0x0597 would be sent: a line with no sender name.
  NameLookupNeeded(line: HeardLine)
  /// 0x01C2: the answer to a line the bot sent.
  LineAccepted(chat_message_id: Int, name: String)
  /// 0x01D3: the refusal of a line the bot sent, with the result's number.
  LineRefused(chat_message_id: Int, channel_type: Int, result: Int)
  /// 0x01D9: the answer to a whisper that found no one.
  WhisperFailed(chat_message_id: Int, target: String)
  /// A cast, heal, absorb, buff or vital of the bot's the server told
  /// (`genesis_prime/sitting_bot/effects`).
  EffectReceived(effect: Effect)
  /// A press the bot sent: its cast id, the bag index and Spell4Base id of the
  /// ability, and the unit it names.
  PressSent(
    client_cast_id: Int,
    bag_index: Int,
    spell4_base_id: Int,
    target_unit_id: Int,
    target_name: String,
  )
  /// A press that was due and sent nothing, since the player is not in sight.
  PressSkipped(target_name: String)
  /// The server ended the connection.
  ServerEnded(reason: String)
}

/// What the bot counts for its summary.
pub type Tally {
  Tally(
    lines_sent: Int,
    answers_got: Int,
    lines_heard: Int,
    units_seen: Int,
    moves_seen: Int,
    effects_seen: Int,
    presses_sent: Int,
  )
}

/// A tally of nothing yet.
fn nothing_yet() -> Tally {
  Tally(
    lines_sent: 0,
    answers_got: 0,
    lines_heard: 0,
    units_seen: 0,
    moves_seen: 0,
    effects_seen: 0,
    presses_sent: 0,
  )
}

/// The tally after the event, and whether the event gets a line. Every event
/// does, but a unit's move: the first and every 20th are shown, so the log is
/// readable.
fn note(tally tally: Tally, event event: Event) -> #(Tally, Bool) {
  case event {
    LineSent(..) -> #(Tally(..tally, lines_sent: tally.lines_sent + 1), True)
    LineAccepted(..) | LineRefused(..) | WhisperFailed(..) -> #(
      Tally(..tally, answers_got: tally.answers_got + 1),
      True,
    )
    LineHeard(..) -> #(Tally(..tally, lines_heard: tally.lines_heard + 1), True)
    UnitShown(..) -> #(Tally(..tally, units_seen: tally.units_seen + 1), True)
    UnitMoved(..) -> {
      let moves_seen = tally.moves_seen + 1
      #(Tally(..tally, moves_seen:), moves_seen == 1 || moves_seen % 20 == 0)
    }
    EffectReceived(..) -> #(
      Tally(..tally, effects_seen: tally.effects_seen + 1),
      True,
    )
    PressSent(..) -> #(
      Tally(..tally, presses_sent: tally.presses_sent + 1),
      True,
    )
    UnitRemoved(..)
    | NameLookupNeeded(..)
    | PressSkipped(..)
    | ServerEnded(..) -> #(tally, True)
  }
}

/// The line a person reads for the event.
fn describe(event: Event) -> String {
  case event {
    LineSent(channel:, chat_message_id:, text:) ->
      "sent "
      <> channel
      <> " (id "
      <> int.to_string(chat_message_id)
      <> "): "
      <> text
    UnitShown(unit_id:, name:) ->
      "shown unit " <> int.to_string(unit_id) <> " " <> name
    UnitMoved(unit_id:, ..) -> "unit " <> int.to_string(unit_id) <> " moved"
    UnitRemoved(unit_id:) -> "unit " <> int.to_string(unit_id) <> " removed"
    LineHeard(line:) ->
      "heard "
      <> heard_channel(line)
      <> " from "
      <> line.sender
      <> ": "
      <> line.text
    NameLookupNeeded(line:) ->
      "would send 0x0597 for the name of the sender of: " <> line.text
    LineAccepted(chat_message_id:, name:) ->
      "answer 0x01C2: line "
      <> int.to_string(chat_message_id)
      <> " accepted as "
      <> name
    LineRefused(chat_message_id:, channel_type:, result:) ->
      "answer 0x01D3: line "
      <> int.to_string(chat_message_id)
      <> " refused on "
      <> channel_name(chat_channel.from_id(id: channel_type))
      <> " with result "
      <> int.to_string(result)
    WhisperFailed(chat_message_id:, target:) ->
      "answer 0x01D9: whisper "
      <> int.to_string(chat_message_id)
      <> " to "
      <> target
      <> " failed"
    EffectReceived(effect:) -> effects.describe(effect)
    PressSent(
      client_cast_id:,
      bag_index:,
      spell4_base_id:,
      target_unit_id:,
      target_name:,
    ) ->
      "sent press 0x009A: cast id "
      <> int.to_string(client_cast_id)
      <> " bag index "
      <> int.to_string(bag_index)
      <> " spell4 base "
      <> int.to_string(spell4_base_id)
      <> " at unit "
      <> int.to_string(target_unit_id)
      <> " "
      <> target_name
    PressSkipped(target_name:) ->
      "press skipped: " <> target_name <> " is not in sight"
    ServerEnded(reason:) -> "the server ended the connection: " <> reason
  }
}

/// The channel a heard line came on, by name, with its id when it has one.
fn heard_channel(line: HeardLine) -> String {
  let name = channel_name(chat_channel.from_id(id: line.channel_type))
  case line.channel_id {
    0 -> name
    id -> name <> " " <> int.to_string(id)
  }
}

fn channel_name(channel: ChannelType) -> String {
  case channel {
    chat_channel.Say -> "say"
    chat_channel.Yell -> "yell"
    chat_channel.Emote -> "emote"
    chat_channel.Zone -> "zone"
    chat_channel.Whisper -> "whisper"
    chat_channel.Party -> "party"
    chat_channel.Support -> "support"
    chat_channel.Instance -> "instance"
    chat_channel.AccountWhisper -> "account whisper"
    chat_channel.Other(id:) -> "channel " <> int.to_string(id)
  }
}

/// The one line the bot ends with.
fn summary(tally: Tally) -> String {
  "sitting bot left: lines sent "
  <> int.to_string(tally.lines_sent)
  <> ", answers got "
  <> int.to_string(tally.answers_got)
  <> ", lines heard "
  <> int.to_string(tally.lines_heard)
  <> ", units seen "
  <> int.to_string(tally.units_seen)
  <> ", effects seen "
  <> int.to_string(tally.effects_seen)
  <> ", presses sent "
  <> int.to_string(tally.presses_sent)
}

/// The events a message of the server is: none for a message the bot does not
/// follow.
fn events_of(frame: Frame) -> List(Event) {
  case frame.message_id {
    0x0262 -> {
      let assert Ok(created) = game_client.created_unit(body: frame.body)
        as "0x0262 decodes as a player's, a creature's or a static object's"
      case created {
        game_client.PlayerCreated(unit:) -> [
          UnitShown(unit_id: unit.unit_id, name: unit.name),
        ]
        game_client.CreatureCreated(..) | game_client.ObjectCreated(..) -> []
      }
    }
    0x0638 -> {
      let assert Ok(moved) = unit_movement.decode(frame.body)
        as "0x0638 decodes"
      [
        UnitMoved(
          unit_id: moved.unit_id,
          server_time: moved.server_time,
          commands: moved.commands,
        ),
      ]
    }
    0x0355 -> {
      let assert Ok(gone) = unit_destroyed.decode(frame.body)
        as "0x0355 decodes"
      [UnitRemoved(unit_id: gone.unit_id)]
    }
    0x01C8 -> {
      let assert Ok(line) = game_client.heard_line(frame:) as "0x01C8 is a line"
      case line.sender {
        "" -> [LineHeard(line:), NameLookupNeeded(line:)]
        _ -> [LineHeard(line:)]
      }
    }
    0x01C2 -> {
      let assert Ok(accept) = chat_line_accepted.decode(frame.body)
        as "0x01C2 decodes"
      [LineAccepted(chat_message_id: accept.chat_message_id, name: accept.name)]
    }
    0x01D3 -> {
      let assert Ok(refusal) = chat_result.decode(frame.body)
        as "0x01D3 decodes"
      [
        LineRefused(
          chat_message_id: refusal.chat_message_id,
          channel_type: refusal.channel_type,
          result: chat_channel_result.to_value(refusal.result),
        ),
      ]
    }
    0x01D9 -> {
      let assert Ok(failed) = whisper_failed.decode(frame.body)
        as "0x01D9 decodes"
      [
        WhisperFailed(
          chat_message_id: failed.chat_message_id,
          target: game_client.from_units(failed.target_name),
        ),
      ]
    }
    _ -> []
  }
}

// ---- the sitting ----

/// The bot at its table: its connection and what it has read but not used, its
/// chat, the zone channel of its entry, and what it has done and counted.
type Sitting {
  Sitting(
    game: Game,
    have: BitArray,
    chatter: Chatter,
    zone_channel: Int,
    seat: Seat,
    near: String,
    schedule: Schedule,
    following: Option(Following),
    bag_index: Option(Int),
    target_unit_id: Option(Int),
    done: Done,
    tally: Tally,
    book: Book,
    started_ms: Int,
    ends_ms: Int,
    report: fn(Event) -> Nil,
  )
}

/// The longest the bot waits for the server before it looks again for a request
/// to stop, in milliseconds.
const stop_check_ms = 100

/// Logs in as the bot's account and plays its character into the world, as the
/// load player does, then sits there until `for_ms` has passed, a stop is asked
/// of this process (`request_stop`, SIGTERM through `stop_on_sigterm`) or the
/// server closes the connection: it sends what the schedule says, tells
/// `report` each event that gets a line, closes its connection and gives what it
/// counted. A step of the server that is not what the client expects stops the
/// process.
pub fn sit(
  ports ports: Ports,
  seat seat: Seat,
  near near: String,
  schedule schedule: Schedule,
  for_ms for_ms: Int,
  report report: fn(Event) -> Nil,
) -> Tally {
  let #(game, auth) = load_player.log_in(account: seat.account, ports:)
  load_player.list_characters(game)
  let #(burst, have) =
    load_player.play_into_world(game:, character_id: seat.character_id)
  let assert Ok(zone_body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: seat.place.world_zone_id))
    as "0xF2 encodes"
  game_client.send_world(game:, message_id: 0x00F2, body: zone_body)
  let started_ms = runtime.now().monotonic_ms
  let sitting =
    Sitting(
      game:,
      have:,
      chatter: game_client.chatter(game:),
      zone_channel: game_client.zone_channel_in(frames: burst),
      seat:,
      near:,
      schedule:,
      following: case schedule.walk {
        Follow(delay_ms:) -> Some(follow.new(near:, delay_ms:))
        Circle(..) -> None
      },
      bag_index: option.map(schedule.press, bag_index_of(burst:, press: _)),
      target_unit_id: None,
      done: Done(moves: 0, lines: 0, whispers: 0, presses: 0),
      tally: nothing_yet(),
      book: effects.new_book(),
      started_ms:,
      ends_ms: started_ms + for_ms,
      report:,
    )
  let tally =
    keep_sitting(
      list.fold(burst, sitting, fn(sitting, frame) { told(sitting:, frame:) }),
    )
  game_client.close(game:)
  let _closed = mug.shutdown(auth)
  tally
}

/// The bag index the entry's 0x0111 messages give the ability to press: the
/// slot a press names (opcode.0x9a), found by the ability's Spell4Base id among
/// the abilities and the innate.
fn bag_index_of(burst burst: List(Frame), press press: Press) -> Int {
  let held = game_client.loadout_in(frames: burst)
  let innate = case held.innate {
    Some(slot) -> [slot]
    None -> []
  }
  let assert Ok(#(bag_index, _)) =
    list.find(list.append(held.abilities, innate), fn(slot) {
      slot.1 == press.spell4_base_id
    })
    as "the entry's ability bag holds the ability the bot was seated to press"
  bag_index
}

fn keep_sitting(sitting: Sitting) -> Tally {
  let now_ms = runtime.now().monotonic_ms
  case stop_requested() || now_ms >= sitting.ends_ms {
    True -> sitting.tally
    False -> {
      let elapsed_ms = now_ms - sitting.started_ms
      let #(due_ms, duty) =
        next_duty(schedule: sitting.schedule, done: sitting.done)
      let echo_wait_ms = case sitting.following {
        Some(following) ->
          option.map(follow.next_due_ms(following), fn(due_ms) {
            due_ms - elapsed_ms
          })
        None -> None
      }
      let wait_ms =
        int.min(due_ms - elapsed_ms, option.unwrap(echo_wait_ms, stop_check_ms))
      case wait_ms <= 0 {
        True ->
          case due_ms <= elapsed_ms {
            True -> keep_sitting(perform(sitting:, duty:))
            False -> keep_sitting(replay(sitting:, elapsed_ms:))
          }
        False ->
          case
            game_client.poll(
              game: sitting.game,
              have: sitting.have,
              wait_ms: int.min(wait_ms, stop_check_ms),
            )
          {
            Ok(#(frames, have)) ->
              keep_sitting(list.fold(frames, Sitting(..sitting, have:), read))
            Error(error) ->
              note_and_report(
                sitting:,
                event: ServerEnded(reason: mug.describe_error(error)),
              ).tally
          }
      }
    }
  }
}

/// Sends the follow walk's next replay, which is due, as the bot's own 0x0637
/// with the bot's clock.
fn replay(sitting sitting: Sitting, elapsed_ms elapsed_ms: Int) -> Sitting {
  let assert Some(following) = sitting.following
    as "a replay is due only in a follow walk"
  let assert Ok(#(commands, following)) =
    follow.take_due(following:, elapsed_ms:)
    as "the replay that was due is waiting"
  game_client.send_world(
    game: sitting.game,
    message_id: 0x0637,
    body: game_client.moves_body(
      client_clock: elapsed_ms,
      commands: follow.stamped(commands:, clock_ms: elapsed_ms),
    ),
  )
  Sitting(..sitting, following: Some(following))
}

/// Does the duty, which is due.
fn perform(sitting sitting: Sitting, duty duty: Duty) -> Sitting {
  let sitting = Sitting(..sitting, done: after(done: sitting.done, duty:))
  case duty {
    Move(number:) -> {
      let #(x, y, z) = circle_position(start: sitting.seat.place, step: number)
      game_client.send_world(
        game: sitting.game,
        message_id: 0x0637,
        body: game_client.moves_body(
          client_clock: runtime.now().monotonic_ms - sitting.started_ms,
          commands: [game_client.position_command(x:, y:, z:)],
        ),
      )
      sitting
    }
    Chat(line:) -> {
      let channel_id = case line.channel {
        chat_channel.Zone -> sitting.zone_channel
        _ -> 0
      }
      let #(chatter, chat_message_id) =
        game_client.line_next(
          chatter: sitting.chatter,
          channel_type: chat_channel.id(line.channel),
          channel_id:,
          text: line.text,
        )
      note_and_report(
        sitting: Sitting(..sitting, chatter:),
        event: LineSent(
          channel: channel_name(line.channel),
          chat_message_id:,
          text: line.text,
        ),
      )
    }
    PressAt(..) -> {
      let assert Some(press) = sitting.schedule.press
        as "a press is due only when the schedule has one"
      press_at(sitting:, press:)
    }
    Whisper(number:) -> {
      let text = "bot whisper " <> int.to_string(number)
      let #(chatter, chat_message_id) =
        game_client.whisper_next(
          chatter: sitting.chatter,
          target: sitting.near,
          text:,
        )
      note_and_report(
        sitting: Sitting(..sitting, chatter:),
        event: LineSent(
          channel: "whisper to " <> sitting.near,
          chat_message_id:,
          text:,
        ),
      )
    }
  }
}

/// Presses the ability at the named player's unit, or reports that the player is
/// not in sight. The client's cast ids start at 2 and count up (0x140c1e71c).
fn press_at(sitting sitting: Sitting, press press: Press) -> Sitting {
  let assert Some(bag_index) = sitting.bag_index
    as "a bot that presses found its ability's bag index at its entry"
  case sitting.target_unit_id {
    Some(target_unit_id) -> {
      let client_cast_id = sitting.tally.presses_sent + 2
      game_client.press_ability(
        game: sitting.game,
        client_cast_id:,
        bag_index:,
        target: target_unit_id,
      )
      note_and_report(
        sitting:,
        event: PressSent(
          client_cast_id:,
          bag_index:,
          spell4_base_id: press.spell4_base_id,
          target_unit_id:,
          target_name: press.at,
        ),
      )
    }
    None ->
      note_and_report(sitting:, event: PressSkipped(target_name: press.at))
  }
}

/// Takes what a message of the server tells.
fn read(sitting: Sitting, frame: Frame) -> Sitting {
  list.fold(events_of(frame), sitting, fn(sitting, event) {
    note_and_report(sitting:, event:)
  })
  |> told(frame:)
}

/// Takes the casts, heals, buffs and vitals a message of the server tells.
fn told(sitting sitting: Sitting, frame frame: Frame) -> Sitting {
  let #(book, received) = effects.read(book: sitting.book, frame:)
  list.fold(received, Sitting(..sitting, book:), fn(sitting, effect) {
    note_and_report(sitting:, event: EffectReceived(effect:))
  })
}

fn note_and_report(sitting sitting: Sitting, event event: Event) -> Sitting {
  let #(tally, shown) = note(tally: sitting.tally, event:)
  case shown {
    True -> sitting.report(event)
    False -> Nil
  }
  let elapsed_ms = runtime.now().monotonic_ms - sitting.started_ms
  Sitting(
    ..sitting,
    tally:,
    following: option.map(sitting.following, followed(_, event:, elapsed_ms:)),
    target_unit_id: pressed_at(sitting:, event:),
  )
}

/// The unit the bot presses at after the event: the named player's unit when it
/// is shown (in any case, as names are unique in any case) and none when it is
/// removed.
fn pressed_at(sitting sitting: Sitting, event event: Event) -> Option(Int) {
  case sitting.schedule.press {
    None -> sitting.target_unit_id
    Some(press) ->
      case event {
        UnitShown(unit_id:, name:) ->
          case string.lowercase(name) == string.lowercase(press.at) {
            True -> Some(unit_id)
            False -> sitting.target_unit_id
          }
        UnitRemoved(unit_id:) ->
          case Some(unit_id) == sitting.target_unit_id {
            True -> None
            False -> sitting.target_unit_id
          }
        LineSent(..)
        | UnitMoved(..)
        | LineHeard(..)
        | NameLookupNeeded(..)
        | LineAccepted(..)
        | LineRefused(..)
        | WhisperFailed(..)
        | EffectReceived(..)
        | PressSent(..)
        | PressSkipped(..)
        | ServerEnded(..) -> sitting.target_unit_id
      }
  }
}

/// What the follow walk takes from an event: the named character's unit shown,
/// moving and removed.
fn followed(
  following following: Following,
  event event: Event,
  elapsed_ms elapsed_ms: Int,
) -> Following {
  case event {
    UnitShown(unit_id:, name:) -> follow.shown(following:, unit_id:, name:)
    UnitMoved(unit_id:, server_time:, commands:) ->
      follow.moved(following:, unit_id:, server_time:, commands:, elapsed_ms:)
    UnitRemoved(unit_id:) -> follow.removed(following:, unit_id:)
    LineSent(..)
    | LineHeard(..)
    | NameLookupNeeded(..)
    | LineAccepted(..)
    | LineRefused(..)
    | WhisperFailed(..)
    | EffectReceived(..)
    | PressSent(..)
    | PressSkipped(..)
    | ServerEnded(..) -> following
  }
}

/// Whether a stop was asked of this process, which the server's SIGTERM (after
/// `stop_on_sigterm`) and `request_stop` both do. The Erlang runtime has no
/// Gleam library for either, and OTP's own handler for SIGTERM ends the node
/// before the bot can leave.
@external(erlang, "sitting_bot_ffi", "stop_requested")
fn stop_requested() -> Bool

/// Asks the process to stop sitting: it leaves, and gives its tally.
@external(erlang, "sitting_bot_ffi", "request_stop")
pub fn request_stop(pid: Pid) -> Nil

/// Makes this node's SIGTERM ask the process for a stop, in place of OTP's
/// handler, which ends the node at once.
@external(erlang, "sitting_bot_ffi", "stop_on_sigterm")
pub fn stop_on_sigterm(pid: Pid) -> Nil

/// The operating system's process id of this node, the one SIGTERM must be sent
/// to: `gleam run` starts the node as a child of its own process, and a signal
/// sent to `gleam run` does not reach the node.
@external(erlang, "sitting_bot_ffi", "os_pid")
fn os_pid() -> String

// ---- the tool ----

/// Why the tool did not run to its end.
type Failure {
  BadArguments(usage: Usage)
  NotSeated(failure: SeatFailure)
  /// The tables or the language file the ability is found in could not be read.
  TablesNotLoaded(failure: ability.LoadFailure)
  /// No character is named as the player to press at.
  NoSuchTarget(name: String)
  NoOneAbility(refusal: ability.Refusal)
  /// The bot's character could not be made a holder of the ability.
  NotEquipped(failure: dev_database.Failure)
}

/// The client's own ports, on this machine: the play server listens on them
/// whatever address it hands the client.
fn local_ports() -> Ports {
  Ports(sts_port: 6600, auth_port: 23_115, game_port: 24_000)
}

pub fn main() -> Nil {
  dev_database.finish(result: run(), describe: describe_failure)
}

fn run() -> Result(String, Failure) {
  use options <- result.try(
    parse_arguments(argv.load().arguments) |> result.map_error(BadArguments),
  )
  use pool <- result.try(
    dev_database.connect()
    |> result.map_error(fn(failure) { NotSeated(Database(failure:)) }),
  )
  use equipment <- result.try(equipment_of(pool:, options:))
  use seat <- result.try(
    seat_as(pool:, near: options.near, character_name: options.bot_name)
    |> result.map_error(NotSeated),
  )
  use press <- result.try(equip(pool:, seat:, equipment:))
  print(
    "seated "
    <> options.bot_name
    <> " in world "
    <> int.to_string(seat.place.world_id)
    <> " zone "
    <> int.to_string(seat.place.world_zone_id)
    <> " at "
    <> float.to_string(seat.place.x)
    <> " "
    <> float.to_string(seat.place.y)
    <> " "
    <> float.to_string(seat.place.z)
    <> ", near "
    <> options.near,
  )
  stop_on_sigterm(process.self())
  print("stop with: kill " <> os_pid())
  let tally =
    sit(
      ports: local_ports(),
      seat:,
      near: options.near,
      schedule: Schedule(..client_schedule(walk: options.walk), press:),
      for_ms: options.minutes * 60_000,
      report: fn(event) { print(describe(event)) },
    )
  Ok(summary(tally))
}

/// What a press needs the bot to hold: the tables, the ability and the faction
/// of the player pressed at.
type Equipment {
  NoEquipment
  Equipment(
    known: ability.Known,
    choice: ability.Choice,
    faction_id: Int,
    options: PressOptions,
  )
}

/// Finds the ability to press at the faction of the player pressed at, before
/// anything is changed, so a refusal leaves the bot as it was.
fn equipment_of(
  pool pool: pog.Connection,
  options options: Options,
) -> Result(Equipment, Failure) {
  case options.press {
    None -> Ok(NoEquipment)
    Some(press) -> {
      use known <- result.try(
        ability.load() |> result.map_error(TablesNotLoaded),
      )
      use faction <- result.try(
        ability.faction_of(pool:, name: press.at)
        |> result.map_error(fn(failure) { NotSeated(Database(failure:)) }),
      )
      use faction_id <- result.try(result.replace_error(
        faction,
        NoSuchTarget(name: press.at),
      ))
      use choice <- result.map(
        ability.resolve(known:, wanted: press.ability, faction_id:)
        |> result.map_error(NoOneAbility),
      )
      Equipment(known:, choice:, faction_id:, options: press)
    }
  }
}

/// Makes the seated bot a holder of the ability, when one is to be pressed, and
/// gives the press the bot makes.
fn equip(
  pool pool: pog.Connection,
  seat seat: Seat,
  equipment equipment: Equipment,
) -> Result(Option(Press), Failure) {
  case equipment {
    NoEquipment -> Ok(None)
    Equipment(known:, choice:, faction_id:, options:) -> {
      use Nil <- result.map(
        ability.equip(
          pool:,
          known:,
          character_id: seat.character_id,
          login_name: seat.account.login_name,
          choice:,
          faction_id:,
        )
        |> result.map_error(NotEquipped),
      )
      print(
        "equipped as class "
        <> int.to_string(choice.class_id)
        <> " level "
        <> int.to_string(choice.level)
        <> " faction "
        <> int.to_string(faction_id)
        <> " to press "
        <> choice.name
        <> " (Spell4Base "
        <> int.to_string(choice.spell4_base_id)
        <> ") at "
        <> options.at
        <> " every "
        <> int.to_string(options.every_s)
        <> " s",
      )
      Some(Press(
        spell4_base_id: choice.spell4_base_id,
        at: options.at,
        every_ms: options.every_s * 1000,
      ))
    }
  }
}

/// Prints a line with the local time.
fn print(line: String) -> Nil {
  let #(_date, time) =
    timestamp.to_calendar(timestamp.system_time(), calendar.local_offset())
  let two = fn(number) { string.pad_start(int.to_string(number), 2, "0") }
  io.println(
    two(time.hours)
    <> ":"
    <> two(time.minutes)
    <> ":"
    <> two(time.seconds)
    <> " "
    <> line,
  )
}

fn describe_failure(failure: Failure) -> String {
  case failure {
    BadArguments(usage:) -> describe_usage(usage)
    NotSeated(failure: NoSuchCharacter(name:)) ->
      "no character is named "
      <> name
      <> ": the bot sits near a character that exists"
    NotSeated(failure: NoSavedPlace(name:)) ->
      name <> " has no saved place: play it into the world once, so it has one"
    NotSeated(failure: Database(failure:)) ->
      dev_database.describe(failure:, change: "seat the sitting bot")
    TablesNotLoaded(failure:) -> ability.describe_load_failure(failure)
    NoSuchTarget(name:) ->
      "no character is named "
      <> name
      <> ": the bot presses at a character that exists"
    NoOneAbility(refusal:) -> ability.describe_refusal(refusal)
    NotEquipped(failure:) ->
      dev_database.describe(failure:, change: "equip the sitting bot")
  }
}
