//// A scripted client that plays a new Exile through the training simulation's quests in
//// the order the client's tables give them, takes the Departures Terminal's yes and
//// ends at the landing in the Northern Wilds. Each step is a named stretch of the path:
//// a step that cannot go on gives the `Stuck` that names it, and a step that waits on a
//// frame that never comes is named to the test that owns the process (`open_wait`).
////
//// ```
//// entry ─▶ 10513 visits ─▶ 10527 hoverboard, finish line, projector 73735
////       ─▶ 10518 beasts, mines, two turrets, ring ─▶ 10529 Dorian ─▶ 10525 projector 73741, talks
////       ─▶ 10540 projector 73743 ─▶ 10519 three presses ─▶ 10520 places, boss, projector 73745
////       ─▶ 10528 Rhoda, the terminal's yes ─▶ the 0xAD of the Northern Wilds
//// ```
////
//// The bot sends what the client sends and nothing the server did not cause: it moves
//// only to a place or to a unit it sees, answers each 0x636 with 0x635, and reports a
//// zone (0x63A) and its terrain (0xF2) after a projector's move. Time moves only by the
//// `advance` of its `Env`, which the caller gives, so a step waits on the server's
//// frames and never on a fixed time.

import bot_frames
import fight_bot
import game_client.{type Game}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/bit_stream
import genesis_prime/message/client_control_granted
import genesis_prime/message/combat_log_immunity
import genesis_prime/message/interaction_result
import genesis_prime/message/quest_objective_progress
import genesis_prime/message/quest_state
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_static
import genesis_prime/message/world_zone_changed.{WorldZoneChanged}
import genesis_prime/world_map/sight
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string
import open_wait
import quest_bot

/// What the caller gives the bot to move the world on.
pub type Env {
  Env(
    /// Moves the clock the server's timers run on by that many milliseconds.
    advance: fn(Int) -> Nil,
    /// Returns when the creature of that unit has taken all it was sent, so a timer its
    /// last step started is on the clock.
    settled: fn(Int) -> Nil,
  )
}

/// The path played to its end: every frame the server wrote, in the order read,
/// beginning with the entry's.
pub type Played {
  Played(frames: List(Frame))
}

/// The step the path stopped at, and why.
pub type Stuck {
  Stuck(step: String, reason: String)
}

/// Why a step cannot go on.
type Blocked {
  Blocked(reason: String)
}

/// A position as the client reports it: x, y, z.
type Point =
  #(Float, Float, Float)

/// A projector (Creature2) and where its press leaves the player: the cast time of its
/// activate spell, the landing's WorldLocation2 position and that row's WorldZone.
type Projector {
  Projector(creature: Int, cast_ms: Int, landing: Point, zone: Int)
}

/// The Sim-Turret (Creature2 73494).
const turret_creature = 73_494

/// The Departures Terminal of the Northern Wilds (Creature2 73606).
const northern_wilds_terminal = 73_606

/// The base of the terminal's activate spell (Spell4 34680 `spell4BaseIdBaseline`), the
/// base its window opens for.
const northern_wilds_terminal_base = 20_650

/// Dorian Walker, who gives and takes the simulation's quests (Creature2 73491).
const dorian = 73_491

/// The same, on the last island (Creature2 74812).
const dorian_on_the_last_island = 74_812

/// The zone the training simulation's first area is in (WorldLocation2 of the entry,
/// WorldZone 6009).
const entry_zone = 6009

/// The distance from a unit at which the bot stands to use it, talk to it or turn in
/// to it: well inside the activate range, which is measured edge to edge less both
/// hit radii.
const use_distance = 1.0

/// The global cooldown a press waits out before the next press: the cooldownTime of
/// SpellCoolDown 100, the `spellCoolDownIdGlobal` of every activate spell it presses
/// (Spell4 85452, 86744, 87061), which is longer than Paralytic Surge's 500 (SpellCoolDown
/// 154).
const global_cooldown_ms = 1500

/// How far beyond a creature the bot stands to fight it: inside the 11 m reach of
/// Paralytic Surge's cone (TelegraphDamage 2889, outer radius 11) and outside the
/// creatures' aggro range of 10.
const fight_distance = 10.5

/// How far beyond a Sim-Turret the bot stands: inside its aggro range of 10, so it
/// charges.
const turret_distance = 8.0

/// The projector of the hoverboard run (Creature2 73735), whose landing is WorldLocation2
/// 51615.
const first_projector =
  Projector(
    creature: 73_735,
    cast_ms: 1000,
    landing: #(-50.5335, -861.401, 307.808),
    zone: 5967,
  )

/// The projector to the talks (Creature2 73741), whose landing is WorldLocation2 51617.
const talks_projector =
  Projector(
    creature: 73_741,
    cast_ms: 1000,
    landing: #(1177.16, -493.389, 223.459),
    zone: 5969,
  )

/// The projector to the Solitude of Secrets (Creature2 73743), whose landing is
/// WorldLocation2 51616.
const solitude_projector =
  Projector(
    creature: 73_743,
    cast_ms: 1000,
    landing: #(476.463, -393.812, 254.228),
    zone: 5968,
  )

/// The projector to the last island (Creature2 73745, cast time 2000), whose landing is
/// WorldLocation2 51658.
const last_projector =
  Projector(
    creature: 73_745,
    cast_ms: 2000,
    landing: #(-4338.952, -445.6, -4104.568),
    zone: 5998,
  )

/// Everything the bot keeps between steps.
type Bot {
  Bot(
    game: Game,
    env: Env,
    have: BitArray,
    /// The frames read, the latest chunk first.
    chunks: List(List(Frame)),
    /// The Creature2 of each unit the bot has seen created.
    creatures: Dict(Int, Int),
    /// Where each unit the client holds stands.
    others: game_client.Others,
    /// The units the bot has used up: a unit counts once for an objective.
    spent: Set(Int),
    at: Point,
    zone: Int,
    clock: Int,
    cast_id: Int,
    own: Int,
  )
}

/// Plays the path from the world entry (`entry`, the frames up to its 0x1BC and the
/// 0x35C after it, with the bytes beyond them in `have`) to the landing in the Northern
/// Wilds, and gives every frame the server wrote, or the step it stopped at.
pub fn play(
  game game: Game,
  have have: BitArray,
  entry entry: List(Frame),
  env env: Env,
) -> Result(Played, Stuck) {
  let own = game_client.unit_create_player_in(frames: entry)
  let bot =
    took(
      bot: Bot(
        game:,
        env:,
        have:,
        chunks: [],
        creatures: dict.new(),
        others: dict.new(),
        spent: set.new(),
        at: game_client.placed_at(unit: own),
        zone: entry_zone,
        clock: 100,
        cast_id: 1,
        own: own.unit_id,
      ),
      frames: entry,
      have:,
    )
  use bot <- step(bot, "enter the simulation", entered)
  use bot <- step(bot, "10513: visit the three places", the_first_visits)
  use bot <- step(
    bot,
    "10527: hoverboard, finish line, projector",
    hoverboard_run,
  )
  use bot <- step(
    bot,
    "10518: beasts, mines, turrets, ring",
    the_training_fights,
  )
  use bot <- step(bot, "10529 and 10525: Dorian, the talks", the_talks)
  use bot <- step(bot, "10540: the Solitude of Secrets", the_solitude)
  use bot <- step(bot, "10519: the three presses", the_presses)
  use bot <- step(bot, "10520: places, boss, last projector", the_last_island)
  use bot <- step(bot, "10528: Rhoda, the terminal's yes", the_departure)
  Ok(Played(frames: list.flatten(list.reverse(bot.chunks))))
}

/// Runs the step and goes on with what it leaves, or stops the path at it.
fn step(
  bot bot: Bot,
  name name: String,
  run run: fn(Bot) -> Result(Bot, Blocked),
  then then: fn(Bot) -> Result(Played, Stuck),
) -> Result(Played, Stuck) {
  case open_wait.named(name, fn() { run(bot) }) {
    Ok(bot) -> then(bot)
    Error(Blocked(reason:)) -> Error(Stuck(step: name, reason:))
  }
}

/// The client's answer to the entry: 0x635 for the 0x636 it holds, and the first 0xF2
/// of the zone, which puts the player in the rings.
fn entered(bot: Bot) -> Result(Bot, Blocked) {
  let granted =
    bot_frames.decoded(
      list.flatten(bot.chunks),
      client_control_granted.message_id,
      client_control_granted.decode,
    )
  case granted {
    [granted, ..] -> {
      game_client.echo_control(game: bot.game, echo_value: granted.echo_value)
      load_terrain(bot, zone: entry_zone)
      Ok(settle(bot))
    }
    [] -> Error(Blocked("the entry held no 0x636 to answer"))
  }
}

fn the_first_visits(bot: Bot) -> Result(Bot, Blocked) {
  // WorldLocation2 51735, 51736 and 51737, the places of 10513's objectives 21271,
  // 21279 and 21272.
  use bot <- result.try(
    list.try_fold(
      [
        #(32.5895, -854.5823, -544.84),
        #(54.0913, -854.5638, -540.177),
        #(48.8309, -851.7351, -519.369),
      ],
      bot,
      fn(bot, place) { visit(bot:, quest_id: 10_513, place:) },
    ),
  )
  let bot = await_state(bot:, quest_id: 10_513, state: 3)
  Ok(await_state(bot:, quest_id: 10_527, state: 1))
}

fn hoverboard_run(bot: Bot) -> Result(Bot, Blocked) {
  // WorldLocation2 51703 (objective 21321) and 51734 (the finish line, 21323).
  use bot <- result.try(
    visit(bot:, quest_id: 10_527, place: #(57.3973, -847.1022, -504.7461)),
  )
  use bot <- result.try(press(bot:, creature: 73_419, cast_ms: 1500))
  use bot <- result.try(
    visit(bot:, quest_id: 10_527, place: #(48.0406, -830.3301, 156.467)),
  )
  use bot <- result.try(project(bot, projector: first_projector))
  let bot = await_state(bot:, quest_id: 10_527, state: 3)
  Ok(await_state(bot:, quest_id: 10_518, state: 1))
}

fn the_training_fights(bot: Bot) -> Result(Bot, Blocked) {
  use bot <- result.try(slay(bot:, creatures: [73_464], kills: 5))
  use bot <- result.try(press(bot:, creature: 73_463, cast_ms: 2000))
  use bot <- result.try(press(bot:, creature: 73_667, cast_ms: 2000))
  use bot <- result.try(press(bot:, creature: 73_668, cast_ms: 2000))
  use bot <- result.try(destroy_a_turret(bot))
  use bot <- result.try(destroy_a_turret(bot))
  use bot <- result.try(slay(bot:, creatures: [73_492, 73_567], kills: 3))
  let bot = await_state(bot:, quest_id: 10_518, state: 3)
  Ok(await_state(bot:, quest_id: 10_529, state: 1))
}

fn the_talks(bot: Bot) -> Result(Bot, Blocked) {
  let #(bot, dorian_unit, at) = find(bot, [dorian])
  let bot = approach(bot:, at:)
  let #(answer, have) =
    quest_bot.use_unit(game: bot.game, have: bot.have, unit_id: dorian_unit)
  let bot = took(bot:, frames: answer.frames, have:)
  let bot = await_state(bot:, quest_id: 10_529, state: 3)
  use bot <- result.try(accept_from(
    bot:,
    givers: [dorian],
    quest_id: 10_525,
    mention: False,
  ))
  use bot <- result.try(project(bot, projector: talks_projector))
  // Quest2 10525's objective slots 1 to 4 are objectives 21319 (TargetGroup 14368, Creature2
  // 73422, twice), 21332 (14369, 73662, twice), 21333 (73663) and 21334 (73664).
  use bot <- result.try(talk_for_objective(
    bot,
    creature: 73_422,
    quest_id: 10_525,
    objective_index: 1,
  ))
  use bot <- result.try(talk_for_objective(
    bot,
    creature: 73_422,
    quest_id: 10_525,
    objective_index: 1,
  ))
  use bot <- result.try(talk_for_objective(
    bot,
    creature: 73_662,
    quest_id: 10_525,
    objective_index: 2,
  ))
  use bot <- result.try(talk_for_objective(
    bot,
    creature: 73_662,
    quest_id: 10_525,
    objective_index: 2,
  ))
  use bot <- result.try(talk_for_objective(
    bot,
    creature: 73_663,
    quest_id: 10_525,
    objective_index: 3,
  ))
  use bot <- result.try(talk_for_objective(
    bot,
    creature: 73_664,
    quest_id: 10_525,
    objective_index: 4,
  ))
  // WorldLocation2 52819, the place of 10525's objective 21382, at Creature2 73421.
  use bot <- result.try(
    visit(bot:, quest_id: 10_525, place: #(1357.56, -493.6102, 166.48)),
  )
  turn_in(bot:, quest_id: 10_525, receivers: [73_421])
}

fn the_solitude(bot: Bot) -> Result(Bot, Blocked) {
  use bot <- result.try(accept_from(
    bot:,
    givers: [73_421],
    quest_id: 10_540,
    mention: False,
  ))
  use bot <- result.try(project(bot, projector: solitude_projector))
  turn_in(bot:, quest_id: 10_540, receivers: [dorian])
}

fn the_presses(bot: Bot) -> Result(Bot, Blocked) {
  use bot <- result.try(accept_from(
    bot:,
    givers: [dorian],
    quest_id: 10_519,
    mention: False,
  ))
  use bot <- result.try(press(bot:, creature: 73_498, cast_ms: 2000))
  use bot <- result.try(press(bot:, creature: 74_745, cast_ms: 2000))
  use bot <- result.try(press(bot:, creature: 74_746, cast_ms: 2000))
  turn_in(bot:, quest_id: 10_519, receivers: [dorian])
}

fn the_last_island(bot: Bot) -> Result(Bot, Blocked) {
  // Quest2 10520 has accept flag 0x400, so the client mentions it before the accept.
  use bot <- result.try(accept_from(
    bot:,
    givers: [dorian],
    quest_id: 10_520,
    mention: True,
  ))
  // WorldLocation2 51698, 51699 and 51700 (the three visits of objective 21294) and
  // 51674 (21295).
  use bot <- result.try(
    list.try_fold(
      [
        #(508.5964, -424.2453, 294.0719),
        #(482.6148, -416.2688, 296.1966),
        #(465.2186, -405.4728, 280.6568),
        #(472.994, -393.19, 255.803),
      ],
      bot,
      fn(bot, place) { visit(bot:, quest_id: 10_520, place:) },
    ),
  )
  use bot <- result.try(slay(bot:, creatures: [73_499], kills: 1))
  use bot <- result.try(project(bot, projector: last_projector))
  turn_in(bot:, quest_id: 10_520, receivers: [dorian_on_the_last_island])
}

fn the_departure(bot: Bot) -> Result(Bot, Blocked) {
  use bot <- result.try(accept_from(
    bot:,
    givers: [dorian_on_the_last_island],
    quest_id: 10_528,
    mention: False,
  ))
  // Quest2 10528's objective slot 0 is objective 21326, a talk to Creature2 73604.
  use bot <- result.try(talk_for_objective(
    bot,
    creature: 73_604,
    quest_id: 10_528,
    objective_index: 0,
  ))
  depart(bot)
}

// Reading

/// What the bot holds after the frames it read and the bytes beyond them.
fn took(bot bot: Bot, frames frames: List(Frame), have have: BitArray) -> Bot {
  Bot(
    ..bot,
    have:,
    chunks: [frames, ..bot.chunks],
    others: list.fold(frames, bot.others, fn(others, frame) {
      game_client.observe(others:, frame:)
    }),
    creatures: list.fold(frames, bot.creatures, learn),
  )
}

/// The Creature2 of the unit a 0x262 creates, when it creates a creature or an object.
fn learn(creatures: Dict(Int, Int), frame: Frame) -> Dict(Int, Int) {
  case frame.message_id {
    0x0262 ->
      case game_client.created_unit(body: frame.body) {
        Ok(game_client.CreatureCreated(unit:)) ->
          dict.insert(creatures, unit.unit_id, unit.creature_id)
        Ok(game_client.ObjectCreated(unit_id:, ..)) ->
          unit_create_static.decode(frame.body)
          |> result.map(fn(object) {
            dict.insert(creatures, unit_id, object.creature_id)
          })
          |> result.unwrap(or: creatures)
        Ok(game_client.PlayerCreated(..)) | Error(Nil) -> creatures
      }
    _ -> creatures
  }
}

/// Reads all the connection wrote before it took a ping.
fn settle(bot: Bot) -> Bot {
  let #(frames, have) =
    game_client.read_until_pong(game: bot.game, have: bot.have, number: 1)
  took(bot:, frames:, have:)
}

/// Reads until the frames read here satisfy `found`, which waits for `what`: the name
/// the test shows when its deadline passes in this wait.
fn read_until(
  bot: Bot,
  what what: String,
  found found: fn(List(Frame)) -> Bool,
) -> Bot {
  let #(frames, have) =
    open_wait.named(what, fn() {
      game_client.read_until(game: bot.game, have: bot.have, found:)
    })
  took(bot:, frames:, have:)
}

/// Returns once the quest has told its state: at once when an earlier read held it,
/// else when it comes.
fn await_state(bot bot: Bot, quest_id quest_id: Int, state state: Int) -> Bot {
  let told = fn(frames) {
    list.any(
      bot_frames.decoded(frames, quest_state.message_id, quest_state.decode),
      fn(told) { told.quest_id == quest_id && told.state == state },
    )
  }
  case told(list.flatten(bot.chunks)) {
    True -> bot
    False ->
      read_until(
        bot,
        what: "0x35c of quest "
          <> int.to_string(quest_id)
          <> " in state "
          <> int.to_string(state),
        found: told,
      )
  }
}

// Moving

/// Moves to the position and reads all the connection wrote in answer.
fn move(bot: Bot, to to: Point) -> Bot {
  game_client.move_to(
    game: bot.game,
    clock: bot.clock,
    x: to.0,
    y: to.1,
    z: to.2,
  )
  settle(Bot(..bot, at: to, clock: bot.clock + 100))
}

/// Moves to where a unit at `at` is within reach of use.
fn approach(bot bot: Bot, at at: Point) -> Bot {
  move(bot, to: #(at.0 +. use_distance, at.1, at.2))
}

/// Moves to the place and reads the objective's progress, which the move counts.
fn visit(
  bot bot: Bot,
  quest_id quest_id: Int,
  place place: Point,
) -> Result(Bot, Blocked) {
  game_client.move_to(
    game: bot.game,
    clock: bot.clock,
    x: place.0,
    y: place.1,
    z: place.2,
  )
  let bot = Bot(..bot, at: place, clock: bot.clock + 100)
  let progressed = fn(frames) {
    list.any(
      bot_frames.decoded(
        frames,
        quest_objective_progress.message_id,
        quest_objective_progress.decode,
      ),
      fn(progress) { progress.quest_id == quest_id },
    )
  }
  Ok(
    settle(read_until(
      bot,
      what: "0x361 of quest " <> int.to_string(quest_id) <> " after a visit",
      found: progressed,
    )),
  )
}

// Units

/// The nearest unit of one of the creatures that the bot has not used and that stands
/// within sight, waiting for its creation when none is known yet.
fn find(bot: Bot, creatures: List(Int)) -> #(Bot, Int, Point) {
  let candidates =
    list.filter_map(dict.to_list(bot.others), fn(held) {
      let #(unit_id, at) = held
      case dict.get(bot.creatures, unit_id) {
        Ok(creature) ->
          case
            list.contains(creatures, creature)
            && !set.contains(bot.spent, unit_id)
            && squared_distance(at, bot.at) <=. sight.range *. sight.range
          {
            True -> Ok(#(unit_id, at))
            False -> Error(Nil)
          }
        Error(Nil) -> Error(Nil)
      }
    })
    |> list.sort(fn(left, right) {
      case
        float.compare(
          squared_distance(left.1, bot.at),
          squared_distance(right.1, bot.at),
        )
      {
        order.Eq -> int.compare(left.0, right.0)
        other -> other
      }
    })
  case candidates {
    [#(unit_id, at), ..] -> #(bot, unit_id, at)
    [] ->
      find(
        read_until(
          bot,
          what: "0x262 of a unit of Creature2 "
            <> string.join(list.map(creatures, int.to_string), " or "),
          found: fn(frames) {
            list.any(frames, fn(frame) { frame.message_id == 0x0262 })
          },
        ),
        creatures,
      )
  }
}

// Quests

/// Opens the quest giver's dialog and accepts the quest at it, mentioning it first
/// when the client does.
fn accept_from(
  bot bot: Bot,
  givers givers: List(Int),
  quest_id quest_id: Int,
  mention mention: Bool,
) -> Result(Bot, Blocked) {
  let #(bot, unit_id, at) = find(bot, givers)
  let bot = approach(bot:, at:)
  let #(talked, have) = quest_bot.talk(game: bot.game, have: bot.have, unit_id:)
  let bot = took(bot:, frames: talked.frames, have:)
  let bot = case mention {
    True -> {
      let #(mentioned, have) =
        quest_bot.mention(game: bot.game, have: bot.have, quest_id:)
      took(bot:, frames: mentioned.frames, have:)
    }
    False -> bot
  }
  let #(accepted, have) =
    quest_bot.accept(game: bot.game, have: bot.have, quest_id:)
  let bot = took(bot:, frames: accepted.frames, have:)
  case accepted.states {
    [] ->
      Error(Blocked(
        "the accept of quest "
        <> int.to_string(quest_id)
        <> " gave no quest state",
      ))
    _ -> Ok(bot)
  }
}

/// Talks to a unit of the creature the objective counts, and uses it up. The talk must
/// progress the objective in slot `objective_index` of the quest (Quest2.objective0 to
/// objective05), else the step is blocked at once: a talk that counts for another
/// objective leaves this one short.
fn talk_for_objective(
  bot: Bot,
  creature creature: Int,
  quest_id quest_id: Int,
  objective_index objective_index: Int,
) -> Result(Bot, Blocked) {
  let #(bot, unit_id, at) = find(bot, [creature])
  let bot = approach(bot:, at:)
  let #(talked, have) = quest_bot.talk(game: bot.game, have: bot.have, unit_id:)
  let bot = took(bot:, frames: talked.frames, have:)
  let bot = Bot(..bot, spent: set.insert(bot.spent, unit_id))
  case
    list.any(talked.progress, fn(progress) {
      progress.quest_id == quest_id
      && progress.objective_index == objective_index
    })
  {
    True -> Ok(bot)
    False ->
      Error(Blocked(
        "the talk to unit "
        <> int.to_string(unit_id)
        <> " of Creature2 "
        <> int.to_string(creature)
        <> " did not progress objective slot "
        <> int.to_string(objective_index)
        <> " of quest "
        <> int.to_string(quest_id),
      ))
  }
}

/// Opens the receiver's dialog and turns the quest in, with no reward chosen.
fn turn_in(
  bot bot: Bot,
  quest_id quest_id: Int,
  receivers receivers: List(Int),
) -> Result(Bot, Blocked) {
  let #(bot, unit_id, at) = find(bot, receivers)
  let bot = approach(bot:, at:)
  let #(talked, have) = quest_bot.talk(game: bot.game, have: bot.have, unit_id:)
  let bot = took(bot:, frames: talked.frames, have:)
  let #(turned, have) =
    quest_bot.turn_in(game: bot.game, have: bot.have, quest_id:, reward_id: 0)
  Ok(took(bot:, frames: turned.frames, have:))
}

// Presses

/// Presses the activate spell of the nearest unit of the creature, lets its cast time
/// pass and reads what its go counts.
fn press(
  bot bot: Bot,
  creature creature: Int,
  cast_ms cast_ms: Int,
) -> Result(Bot, Blocked) {
  use #(bot, _) <- result.try(pressed(bot, creature:))
  bot.env.advance(cast_ms)
  let #(went, have) = quest_bot.went(game: bot.game, have: bot.have)
  Ok(took(bot:, frames: went.frames, have:))
}

/// Presses the activate spell of the nearest unit of the creature, and gives what the
/// server confirmed of the cast.
fn pressed(bot: Bot, creature creature: Int) -> Result(#(Bot, Int), Blocked) {
  let #(bot, unit_id, at) = find(bot, [creature])
  let bot = approach(bot:, at:)
  bot.env.advance(global_cooldown_ms)
  let #(answer, have) =
    quest_bot.activate(
      game: bot.game,
      have: bot.have,
      client_cast_id: bot.cast_id,
      unit_id:,
    )
  let bot =
    Bot(
      ..took(bot:, frames: answer.frames, have:),
      cast_id: bot.cast_id + 1,
      spent: set.insert(bot.spent, unit_id),
    )
  case answer.confirmed {
    [confirmed, ..] -> Ok(#(bot, confirmed.server_cast_id))
    [] ->
      Error(Blocked(
        "the press on Creature2 "
        <> int.to_string(creature)
        <> " was not confirmed with a 0x7fd; the server refused it with the results "
        <> string.join(
          list.filter_map(
            game_client.casts_in(frames: answer.frames),
            fn(event) {
              case event {
                game_client.CastRefused(result:, ..) ->
                  Ok(int.to_string(result))
                _ -> Error(Nil)
              }
            },
          ),
          " ",
        ),
      ))
  }
}

/// Presses a projector, lets its cast time pass and does what the client does at the
/// landing: answers the 0x636 of the move with 0x635, stands at the landing, reports
/// the zone it left and entered (0x63A) and its terrain (0xF2).
fn project(bot: Bot, projector projector: Projector) -> Result(Bot, Blocked) {
  use #(bot, _) <- result.try(pressed(bot, creature: projector.creature))
  bot.env.advance(projector.cast_ms)
  let bot =
    read_until(bot, what: "0x636 after the projector's go", found: fn(frames) {
      list.any(frames, fn(frame) {
        frame.message_id == client_control_granted.message_id
      })
    })
  let granted =
    bot_frames.decoded(
      list.flatten(list.reverse(bot.chunks)),
      client_control_granted.message_id,
      client_control_granted.decode,
    )
  case list.last(granted) {
    Error(Nil) -> Error(Blocked("the projector's go wrote no 0x636"))
    Ok(granted) -> {
      game_client.echo_control(game: bot.game, echo_value: granted.echo_value)
      let bot = move(bot, to: projector.landing)
      report_zone(bot, new: projector.zone)
      load_terrain(bot, zone: projector.zone)
      Ok(settle(Bot(..bot, zone: projector.zone)))
    }
  }
}

/// The client's 0x63A: the zone it left and the zone it entered.
fn report_zone(bot: Bot, new new: Int) -> Nil {
  let assert Ok(body) =
    world_zone_changed.encode(WorldZoneChanged(
      old_world_zone_id: bot.zone,
      new_world_zone_id: new,
    ))
    as "0x063A encodes"
  game_client.send_world(
    game: bot.game,
    message_id: world_zone_changed.message_id,
    body:,
  )
}

/// The client's 0xF2: the terrain of the zone is loaded.
fn load_terrain(bot: Bot, zone zone: Int) -> Nil {
  let assert Ok(body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: zone))
    as "0x00F2 encodes"
  game_client.send_world(
    game: bot.game,
    message_id: terrain_loaded.message_id,
    body:,
  )
}

/// Presses the terminal, answers its window with yes and reads the move to the
/// landing, up to its last message of the entry and the pong after it.
fn depart(bot: Bot) -> Result(Bot, Blocked) {
  use #(bot, server_cast_id) <- result.try(pressed(
    bot,
    creature: northern_wilds_terminal,
  ))
  let #(answered, have) =
    quest_bot.answer_window(
      game: bot.game,
      have: bot.have,
      cast_id: server_cast_id,
      spell4_base_id: northern_wilds_terminal_base,
      result: interaction_result.Succeeded,
    )
  let bot = took(bot:, frames: answered.frames, have:)
  // The yes starts the departure's timer, which fires with no delay.
  bot.env.advance(0)
  // The settle reads the entry's writes up to the pong, so the clock moves on only after
  // the connection has written all of them.
  Ok(
    settle(
      read_until(bot, what: "0x1bc of the landing", found: fn(frames) {
        list.any(frames, fn(frame) { frame.message_id == 0x01BC })
      }),
    ),
  )
}

// Fights

/// Kills at least `kills` units of the creatures: for the nearest unit the bot has not
/// killed it stands beyond it, faces it and presses Paralytic Surge until it dies. The
/// press strikes every unit inside its cone and its box, so each unit of the creatures
/// read dead in the fight is a kill, as the quest counts it.
fn slay(
  bot bot: Bot,
  creatures creatures: List(Int),
  kills kills: Int,
) -> Result(Bot, Blocked) {
  use <- bool.guard(when: kills <= 0, return: Ok(bot))
  let #(bot, unit_id, at) = find(bot, creatures)
  let stands = #(at.0 +. fight_distance, at.1, at.2)
  let bot = move(bot, to: stands)
  face(bot:, from: stands, target: at)
  let bot = Bot(..bot, clock: bot.clock + 100)
  use #(seen, have) <- result.try(result.map_error(
    fight_bot.presses_until_the_target_dies(
      advance: bot.env.advance,
      game: bot.game,
      have: bot.have,
      target: unit_id,
      cast_id: bot.cast_id,
      seen: [],
    ),
    refused,
  ))
  let dead =
    list.filter_map(game_client.deaths_in(frames: seen), fn(death) {
      case death.1 {
        True -> Ok(death.0)
        False -> Error(Nil)
      }
    })
  let bot =
    Bot(
      ..took(bot:, frames: seen, have:),
      cast_id: bot.cast_id + 100,
      spent: set.union(bot.spent, set.from_list(dead)),
    )
  let killed =
    list.count(dead, fn(unit) {
      case dict.get(bot.creatures, unit) {
        Ok(creature) -> list.contains(creatures, creature)
        Error(Nil) -> False
      }
    })
  case list.contains(dead, unit_id) {
    True -> slay(bot: settle(bot), creatures:, kills: kills - killed)
    False ->
      Error(Blocked("the unit " <> int.to_string(unit_id) <> " did not die"))
  }
}

/// Why a press the server refused (0x7fc) ends the path.
fn refused(refused: fight_bot.Refused) -> Blocked {
  Blocked(
    "the press with client cast id "
    <> int.to_string(refused.client_cast_id)
    <> " was refused with the results "
    <> string.join(list.map(refused.results, int.to_string), " "),
  )
}

fn face(bot bot: Bot, from from: Point, target target: Point) -> Nil {
  game_client.face(
    game: bot.game,
    yaw: game_client.yaw_toward(from: #(from.0, from.2), target: #(
      target.0,
      target.2,
    )),
    clock: bot.clock,
  )
}

/// How long a Sim-Turret stays open after an interrupt: the Fluff effect of Spell4 85472's
/// opening lasts 15 s (Spell4Effects 224715).
const opening_ms = 15_000

/// The Paralytic Surge presses that fit in a Sim-Turret's opening, each 2700 ms after the
/// last (Spell4Effects 96126): the presses at 2700 to 13500 ms after the interrupt.
const presses_in_the_opening = 5

/// The openings a bot of level 1 may take to destroy a turret: the turret's 0x937 health
/// falls 14 a press from 150, so eleven presses destroy it, which takes three openings of
/// five. The fourth is a spare for a deflected press: a turret deflects a strike with
/// chance 0.016 (CreatureLevel 101's 0.05 times Creature2Difficulty 1's multiplier 0.32),
/// and each deflect costs one of the fifteen presses of the three openings.
const openings_to_destroy_a_turret = 4

/// Walks in range of the nearest Sim-Turret and destroys it: one press interrupts each of
/// its charges, and the presses within the opening that follows are all the damage it takes
/// (its guard takes none), so a turret stays up through several openings.
fn destroy_a_turret(bot: Bot) -> Result(Bot, Blocked) {
  let #(bot, turret, place) = find(bot, [turret_creature])
  let guarded = fn(frames) { guards_of(frames:, turret:) != [] }
  let bot = case guarded(list.flatten(bot.chunks)) {
    True -> bot
    False ->
      read_until(bot, what: "the turret's guard cast (0x7ff)", found: guarded)
  }
  let stands = #(place.0 +. turret_distance, place.1, place.2)
  game_client.move_to(
    game: bot.game,
    clock: bot.clock,
    x: stands.0,
    y: stands.1,
    z: stands.2,
  )
  let bot = Bot(..bot, at: stands, clock: bot.clock + 100)
  face(bot:, from: stands, target: place)
  let bot = Bot(..bot, clock: bot.clock + 100)
  let own = bot.own
  let bot =
    read_until(bot, what: "the turret's aggro on the player", found: fn(frames) {
      list.contains(
        game_client.fight_in(frames:),
        game_client.Targeted(unit_id: turret, target_unit_id: own, threat: 1),
      )
    })
  use bot <- result.map(
    open_and_press(
      bot:,
      turret:,
      openings: openings_to_destroy_a_turret,
      broken: [],
    ),
  )
  // The kill's credit comes from the creature after its death is written.
  settle(Bot(..bot, spent: set.insert(bot.spent, turret)))
}

/// The 0x7ff of Spell4 85474, the guard, that the turret cast, in the order sent: each
/// as the cast's id and the caster.
fn guards_of(
  frames frames: List(Frame),
  turret turret: Int,
) -> List(#(Int, Int)) {
  list.filter(
    game_client.starts_of(
      events: game_client.casts_in(frames:),
      spell4_id: 85_474,
    ),
    fn(guard) { guard.1 == turret },
  )
}

/// The 0x7ff of Spell4 85469, the charge, that the turret cast, in the order sent: each
/// as the cast's id and the caster.
fn charges_of(
  frames frames: List(Frame),
  turret turret: Int,
) -> List(#(Int, Int)) {
  list.filter(
    game_client.starts_of(
      events: game_client.casts_in(frames:),
      spell4_id: 85_469,
    ),
    fn(charge) { charge.1 == turret },
  )
}

/// Takes the turret's charge that is not one of the `broken` ones of the earlier openings,
/// moving the clock to the attack tick only when it has not been read, interrupts it with one
/// press and presses on within the opening until the turret is destroyed; when the opening
/// ends with the turret up, the guard returns and the next charge is the next opening, up to
/// `openings` of them.
fn open_and_press(
  bot bot: Bot,
  turret turret: Int,
  openings openings: Int,
  broken broken: List(Int),
) -> Result(Bot, Blocked) {
  let assert Ok(#(guard_cast, _)) =
    list.last(guards_of(frames: list.flatten(list.reverse(bot.chunks)), turret:))
    as "the turret's guard was read"
  // The attack tick, within 3000 ms of the aggro or the guard's return, opens the charge. The
  // opening's end and a tick that falls at the same instant run in no fixed order: when the
  // guard returns first, the tick charges in the same advance, and the charge's 0x7ff was
  // read with the guard's return, so the charge is looked for in all that was read, and the
  // clock moves on only when it is not there.
  let open_charges = fn(bot: Bot) {
    list.filter(
      charges_of(frames: list.flatten(list.reverse(bot.chunks)), turret:),
      fn(charge) { !list.contains(broken, charge.0) },
    )
  }
  let bot = case open_charges(bot) {
    [_, ..] -> bot
    [] -> {
      turret_settled(bot:, turret:, when: "before the attack tick")
      bot.env.advance(3000)
      settle(bot)
    }
  }
  use charge_cast <- result.try(case open_charges(bot) {
    [#(charge_cast, _), ..] -> Ok(charge_cast)
    [] ->
      Error(Blocked(
        "the turret "
        <> int.to_string(turret)
        <> " opened no charge, 0x7ff of Spell4 85469, in 3000 ms after its aggro or its guard's return",
      ))
  })
  // The press interrupts the charge: Paralytic Surge's stun (Spell4Effects 96126) breaks
  // it, and the turret's guard comes off. The read waits for each message of the
  // interrupt, which the turret and the connection write in no fixed order.
  turret_settled(bot:, turret:, when: "before the interrupting press")
  game_client.press_ability(
    game: bot.game,
    client_cast_id: bot.cast_id,
    bag_index: 2,
    target: 0,
  )
  let interrupt_cast = bot.cast_id
  let interrupted = fn(frames) {
    fight_bot.refusals_in(frames:, cast_id: interrupt_cast) != []
    || list.contains(
      game_client.casts_in(frames:),
      game_client.CastFinished(cast_id: charge_cast),
    )
    && game_client.starts_of(
      events: game_client.casts_in(frames:),
      spell4_id: 85_472,
    )
    != []
    && list.contains(
      game_client.targets_removed_in(frames:),
      #(guard_cast, [
        turret,
      ]),
    )
    && list.any(frames, fn(frame) { frame.message_id == 0x087F })
    && immunity_shown(frames:, turret:)
  }
  let bot =
    read_until(
      bot,
      what: "the interrupt of the turret's charge",
      found: interrupted,
    )
  let refusals =
    fight_bot.refusals_in(
      frames: list.flatten(bot.chunks),
      cast_id: interrupt_cast,
    )
  use <- bool.guard(
    when: refusals != [],
    return: Error(
      refused(fight_bot.Refused(
        client_cast_id: interrupt_cast,
        results: refusals,
      )),
    ),
  )
  turret_settled(bot:, turret:, when: "before the first press of the opening")
  bot.env.advance(fight_bot.paralytic_surge_lingers_ms)
  let bot = settle(bot)
  use #(killed, have) <- result.try(result.map_error(
    fight_bot.presses_at_most(
      advance: bot.env.advance,
      game: bot.game,
      have: bot.have,
      target: turret,
      cast_id: bot.cast_id + 1,
      seen: [],
      presses: presses_in_the_opening,
    ),
    refused,
  ))
  let bot =
    Bot(
      ..took(bot:, frames: killed, have:),
      cast_id: bot.cast_id + presses_in_the_opening + 1,
    )
  case list.contains(game_client.deaths_in(frames: killed), #(turret, True)) {
    True -> Ok(bot)
    False if openings <= 1 ->
      Error(Blocked(
        "the turret " <> int.to_string(turret) <> " was not destroyed",
      ))
    False -> {
      // The opening ends 15000 ms after the interrupt, and the guard is cast anew.
      turret_settled(bot:, turret:, when: "before the opening ends")
      bot.env.advance(
        opening_ms
        - presses_in_the_opening
        * fight_bot.paralytic_surge_lingers_ms,
      )
      // The advance has written the guard's return, which the connection's pong follows.
      let bot = settle(bot)
      let returned = case
        list.last(guards_of(
          frames: list.flatten(list.reverse(bot.chunks)),
          turret:,
        ))
      {
        Ok(#(latest, _)) -> latest != guard_cast
        Error(Nil) -> False
      }
      use <- bool.guard(
        when: !returned,
        return: Error(Blocked(
          "the turret "
          <> int.to_string(turret)
          <> " cast no guard anew when its opening ended",
        )),
      )
      open_and_press(bot:, turret:, openings: openings - 1, broken: [
        charge_cast,
        ..broken
      ])
    }
  }
}

/// Waits until the turret has taken all it was sent, named for the wait it ends.
fn turret_settled(bot bot: Bot, turret turret: Int, when when: String) -> Nil {
  open_wait.named(
    "the turret "
      <> int.to_string(turret)
      <> " has taken what it was sent "
      <> when,
    fn() { bot.env.settled(turret) },
  )
}

/// Whether a 0x247 shows the turret immune to a hit (combat log entry type 18).
fn immunity_shown(frames frames: List(Frame), turret turret: Int) -> Bool {
  list.any(frames, fn(frame) {
    frame.message_id == 0x0247
    && result.map(
      combat_log_immunity.read(bit_stream.new_reader(frame.body)),
      fn(read) {
        let #(immunity, _) = read
        immunity.target_unit_id == turret
      },
    )
    |> result.unwrap(or: False)
  })
}

// Geometry

/// The squared distance between two points, as the server's sight measures it
/// (`sight.squared_distance`), which takes places: the distance reads only the
/// positions, so the world and the zone of the places made here do not matter.
fn squared_distance(left: Point, right: Point) -> Float {
  sight.squared_distance(first: place_at(left), second: place_at(right))
}

/// A place at the point, for the sight's distance.
fn place_at(point: Point) -> Place {
  let assert Ok(place) =
    start_place.place(
      world_id: 1,
      world_zone_id: 0,
      x: point.0,
      y: point.1,
      z: point.2,
      facing: start_place.unturned,
    )
    as "world 1 is not world 0, which has no place"
  place
}
