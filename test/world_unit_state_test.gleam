//// A unit state a player's cast holds on a creature, through the real processes: the map, the
//// creature under its supervisor, two or three players' connections, and the cast rule's go and
//// press, on a clock the test drives. Expected values come from these places.
//// - Spell4Effects row 64365 (Spell4 32683 "Stun/Immune - 8 seconds"): a UnitStateSet row of
////   state 6, targetFlags 2, durationTime 8500, delay 0, phaseFlags 1
////   (`table_rows -- Spell4Effects 64365`). It is planted on the spell tree the plan tests
////   build on, as the despawn rows are; no client row starts that spell on a unit a go struck.
//// - What state 6 does is the reading table in `genesis_prime/shared/unit_state` (a guess from
////   spell names): a hostile press at a creature that shows it is refused with 306, a beneficial
////   one is not, a strike with blows is answered `Immune`, and the end is the go's time plus the
////   row's delay and duration, kept by the creature.
//// - Spell4 64944 (Spell4Base 42972: cast group TargetGroup 8755; Spell4TargetMechanics 3: flags
////   16, bit 0 clear) is the hostile aimed press, a button of quest 9373's objective, and the
////   same spell with the mechanics' flags 9 (bit 0 set) the beneficial one
////   (`unit_state.cast_refusal`'s rule on `Spell4TargetMechanics.flags`, a guess). The
////   tables each connection holds clear its target cast prerequisite (28001, a type the server
////   does not read) and give the cast group the Battle Beast, as the objective-cast tests plant them.
//// - `opcode.0x7fc` (a refused press), `opcode.0x7f4` (the go), `opcode.0x247.immunity` (combat
////   log type 18) and `opcode.0x937` (health) are what the players are sent.
//// Each press is made by a real connection (`game_connection`): it is handed the creature's
//// 0x262 and the unit-state news the creature sent, as the map and the creature sent them, and
//// its own picture of the creature, through the viewers and `casting.usable`, judges the press.
//// Every wait is for an event, and the clock moves only when the test advances it.

import cast_support
import driven_time
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Message, ForStay, SentByPeer}

import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection as game_connection
import genesis_prime/game/start_place
import genesis_prime/message/cast_objective_ability.{CastObjectiveAbility}
import genesis_prime/message/cast_result
import genesis_prime/message/combat_log
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_result
import genesis_prime/message/spell_effect_info
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/shared/spell_plan
import genesis_prime/shared/strike_tell.{Landed}
import genesis_prime/shared/unit_news.{type PeerNews, PeerNews}
import genesis_prime/shared/unit_state
import genesis_prime/step.{OwnEvent}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/table/loader/store as store_tables
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/registry.{type MapProcess}
import genesis_prime/world_map/relay
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test
import place_support
import planted_table.{Integer}
import quest_support
import spawn_support
import spell_tables
import world_support.{type World}
import world_watch_support.{type Watched}

/// The aimed shortcut spell the presses name, a button of quest 9373, and the quest.
const aimed_spell = 64_944

const aimed_quest = 9373

/// Spell4TargetMechanics row 3 of the spell, and the flags of the beneficial reading.
const aimed_mechanics = 3

const hostile_flags = 16

const beneficial_flags = 9

/// The cast group of the spell, which the tables give the Battle Beast.
const aimed_cast_group = 8755

const battle_beast = 73_464

/// The gap from the player's edge to the beast's, the spell's range being 3 to 30.
const gap = 10.0

/// The cast id the client gives its presses.
const clients_cast_id = 7

/// The caster of the cast rule's pure go (`cast_support.caster`).
const the_caster = 7

// ---- the go that holds the state ----

/// The UnitStateSet row of Spell4Effects 64365, planted under its own id: state 6 for 8500 ms
/// from the go, no delay, in phase 1, aimed at the target.
fn state_6_row() -> spell_plan.UnitState {
  let assert Ok(planned) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: spell_tables.effect_row_with(
          id: 64_365,
          effect_type: 15,
          target_flags: 2,
          columns: [
            #("dataBits00", Integer(6)),
            #("durationTime", Integer(8500)),
            #("delayTime", Integer(0)),
            #("phaseFlags", Integer(1)),
          ],
        ),
      ),
    )
  let assert [row] =
    spell_plan.payloads(spell: planned, as_kind: spell_plan.as_unit_state)
    as "the plan reads the planted row as one unit state"
  assert row.row == unit_state.Row(state: 6, delay_ms: 0, duration_ms: 8500)
    && row.effect_id == Spell4EffectsId(64_365)
    as "with the row's own state, delay and duration"
  row
}

/// The effects of the go of a spell with this unit state row, pressed at `struck_at_ms` and
/// answered at `went_at_ms` with each creature of `units` (unit id and life) the round hit.
fn state_go(
  row row: spell_plan.UnitState,
  units units: List(#(Int, Int)),
  struck_at_ms struck_at_ms: Int,
  went_at_ms went_at_ms: Int,
) -> List(cast_state.Effect) {
  world_watch_support.effects_of_a_go_on_creatures(
    kind: spell_plan.UnitStateEffect(row),
    units:,
    struck_at_ms:,
    went_at_ms:,
  )
}

/// What the caster's connection does with the go's effects, as the connection and the
/// server carry them out: each creature the go holds states on is told `UnitStates`
/// by its address, to the map. Returns the units told.
fn carried_out(
  run run: MapProcess,
  effects effects: List(cast_state.Effect),
) -> List(Int) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.CreatureHoldsUnitStates(unit_id:, life:, went_at_ms:, rows:) -> {
        world_watch_support.told_creature(
          run:,
          unit_id:,
          life:,
          payload: relay.UnitStates(rows:, went_at_ms:),
        )
        Ok(unit_id)
      }
      _ -> Error(Nil)
    }
  })
}

/// The go of the state-6 spell on the watched beast, whose round opened at the clock's time
/// and whose go comes 250 ms later, so a hold that ran from the round's opening would end
/// early. Returns the units the connection told.
fn state_go_on(watched watched: Watched) -> List(Int) {
  let #(struck_at_ms, went_at_ms) =
    world_watch_support.times_of_a_go_after_250_ms(watched:)
  let told =
    carried_out(
      run: watched.run,
      effects: state_go(
        row: state_6_row(),
        units: [#(watched.beast.unit_id, 2)],
        struck_at_ms:,
        went_at_ms:,
      ),
    )
  // The tell is taken before the clock moves, so the timer it starts is due at the go's
  // time plus the row's duration.
  driven_time.settled(watched.pid)
  told
}

// ---- what the connections are sent ----

/// The unit-state news about the unit a connection was sent, as the state and number held, or
/// `Ended`.
type StateNews {
  Held(state: Int, number: Int)
  Ended(number: Int)
}

fn state_news(unit_id unit_id: Int) -> fn(Message) -> Result(StateNews, Nil) {
  fn(message) {
    case message {
      ForStay(
        sent: SentByPeer(PeerNews(
          unit_id: from,
          news: unit_news.UnitStateHeld(state:, number:),
        )),
        ..,
      )
        if from == unit_id
      -> Ok(Held(state:, number:))
      ForStay(
        sent: SentByPeer(PeerNews(
          unit_id: from,
          news: unit_news.UnitStateEnded(number:),
        )),
        ..,
      )
        if from == unit_id
      -> Ok(Ended(number:))
      ForStay(..)
      | client_connection.SentBySessions(..)
      | client_connection.SentByChat(..) -> Error(Nil)
    }
  }
}

/// The next unit-state news of the unit that the connection was sent.
fn next_state_news(
  received received: Subject(Message),
  unit_id unit_id: Int,
  what what: String,
) -> StateNews {
  world_watch_support.next(received:, what:, wanted: state_news(unit_id:))
}

/// The unit-state news of the unit the connection has already been sent and not taken. A
/// creature sends in the order it acts, and a send is immediate, so news it sent before a
/// message the test has taken from the same creature is here already.
fn state_news_waiting(
  received received: Subject(Message),
  unit_id unit_id: Int,
) -> List(StateNews) {
  case process.receive(received, 0) {
    Ok(message) ->
      case state_news(unit_id:)(message) {
        Ok(news) -> [news, ..state_news_waiting(received:, unit_id:)]
        Error(Nil) -> state_news_waiting(received:, unit_id:)
      }
    Error(Nil) -> []
  }
}

/// The health a creature's 0x937 news tells, when the message is that for `unit_id`.
fn health_of(
  unit_id unit_id: Int,
  message message: Message,
) -> Result(Int, Nil) {
  case message {
    ForStay(
      sent: SentByPeer(PeerNews(
        unit_id: from,
        news: unit_news.Health(health:, ..),
      )),
      ..,
    )
      if from == unit_id
    -> Ok(health)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// The healths of `unit_id` the connection has already been sent and not taken.
fn health_news_waiting(
  received received: Subject(Message),
  unit_id unit_id: Int,
) -> List(Int) {
  case process.receive(received, 0) {
    Ok(message) ->
      case health_of(unit_id:, message:) {
        Ok(health) -> [health, ..health_news_waiting(received:, unit_id:)]
        Error(Nil) -> health_news_waiting(received:, unit_id:)
      }
    Error(Nil) -> []
  }
}

// ---- the press ----

/// Runs the body on the tables a connection of these presses holds: the aimed spell's target
/// cast prerequisite cleared, its cast group holding the Battle Beast, and the target
/// mechanics' flags `flags` (16, hostile, or `beneficial_flags`).
fn press_tables(
  flags flags: Int,
  body body: fn(store_tables.Tables) -> a,
) -> a {
  let rows =
    fixture_tables.rows()
    |> edited(table: "Spell4", id: aimed_spell, with: [
      #("prerequisiteIdTargetCast", Integer(0)),
    ])
    |> edited(table: "TargetGroup", id: aimed_cast_group, with: [
      #("type", Integer(1)),
      #("data0", Integer(battle_beast)),
      #("data1", Integer(0)),
      #("data2", Integer(0)),
    ])
    |> edited(table: "Spell4TargetMechanics", id: aimed_mechanics, with: [
      #("flags", Integer(flags)),
    ])
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

fn edited(
  rows rows: fixture_tables.Rows,
  table table: String,
  id id: Int,
  with changes: List(#(String, planted_table.Cell)),
) -> fixture_tables.Rows {
  let assert Ok(changed) =
    fixture_tables.change(rows:, table:, id:, with: changes)
    as "the row and its columns are the client table's"
  changed
}

/// A real connection of a player standing `gap` from the creature that appeared as `appeared`,
/// holding quest 9373's button, which was sent that appearance and then `news` of the
/// creature's unit states, in order.
fn connection_of(
  tables tables: store_tables.Tables,
  appeared appeared: PeerNews,
  news news: List(StateNews),
) -> game_connection.State {
  let assert PeerNews(
    unit_id:,
    news: unit_news.CreatureAppeared(hit_radius:, place:, ..),
  ) = appeared
    as "the news is a creature's appearance"
  let character =
    Character(
      ..connection_support.world_character(),
      place: Some(start_place.moved(
        place:,
        x: start_place.x(place),
        y: start_place.y(place),
        z: start_place.z(place)
          +. gap
          +. place_support.player_hit_radius
          +. hit_radius,
      )),
    )
  let #(entered, _) =
    connection_support.entered_as_with_quests_on(tables:, character:, quests: [
      quest_support.accepted(quest_id: aimed_quest, progress: [0, 0]),
    ])
  list.fold(
    [appeared, ..list.map(news, state_peer_news(unit_id:, news: _))],
    entered,
    fn(state, told) {
      connection_support.feed(
        state:,
        event: connection_support.sent_by_a_peer(told),
      ).0
    },
  )
}

/// The unit-state news as the creature sent it.
fn state_peer_news(unit_id unit_id: Int, news news: StateNews) -> PeerNews {
  PeerNews(unit_id:, news: case news {
    Held(state:, number:) -> unit_news.UnitStateHeld(state:, number:)
    Ended(number:) -> unit_news.UnitStateEnded(number:)
  })
}

/// The press of the aimed spell at the creature that appeared as `appeared`, by a real
/// connection that was sent that appearance and `news` of its unit states, at the driven
/// clock's time: the results of the 0x7fc refusals and the ids of the frames written.
fn pressed(
  watched watched: Watched,
  tables tables: store_tables.Tables,
  appeared appeared: PeerNews,
  news news: List(StateNews),
) -> #(List(Int), List(Int)) {
  let state = connection_of(tables:, appeared:, news:)
  let assert Ok(body) =
    cast_objective_ability.encode(CastObjectiveAbility(
      client_cast_id: clients_cast_id,
      spell4_id: aimed_spell,
      target_unit_id: appeared.unit_id,
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  let #(_, taken) =
    connection_support.at(
      state:,
      ms: world_watch_support.clock_ms(time: watched.time),
      event: OwnEvent(
        step.Read(connection_support.world_message(
          message_id: cast_objective_ability.message_id,
          body:,
        )),
      ),
    )
  #(
    list.map(connection_support.refusal_results(taken:), cast_result.to_value),
    connection_support.written_ids(taken),
  )
}

/// What a press that goes writes: the 0x7fd that starts the cast.
const goes = #([], [0x07FD])

/// What a refused press writes: the 0x7fc with the result.
fn refused(result result: Int) -> #(List(Int), List(Int)) {
  #([result], [0x07FC])
}

/// The Spell4 id of the cast the effects start (the 0x7ff the map is told).
fn started_spell4_id(effects effects: List(cast_state.Effect)) -> Int {
  let assert [unit_news.CastStarted(start:), ..] = cast_support.tells(effects:)
    as "the press starts a cast, the first thing the map is told"
  start.spell4_id
}

// ---- rows 61 to 67: through the real processes ----

pub fn a_hostile_press_at_a_creature_holding_state_6_is_refused_306_until_the_row_ends_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- press_tables(flags: hostile_flags)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  let unit_id = watched.beast.unit_id
  let told = state_go_on(watched:)
  assert told == [unit_id] as "the go told the one creature it struck"
  let caster_news =
    next_state_news(
      received: watched.caster,
      unit_id:,
      what: "the caster's news of the state",
    )
  let viewer_news =
    next_state_news(
      received: watched.viewer,
      unit_id:,
      what: "the second connection's news of the state",
    )
  assert caster_news == Held(state: 6, number: 1)
    && viewer_news == Held(state: 6, number: 1)
    as "each connection is told the state under the creature's number"
  let press = pressed(watched:, tables:, appeared: watched.appeared, news: _)
  assert press([caster_news]) == refused(result: 306)
    as "the caster's hostile press is refused with 306 (Target_HostileInvulnerability)"
  assert press([viewer_news]) == refused(result: 306)
    as "the second connection's is too"
  driven_time.advance(time: watched.time, ms: 8499)
  assert state_news_waiting(received: watched.caster, unit_id:) == []
    && state_news_waiting(received: watched.viewer, unit_id:) == []
    as "nothing ended at 8499 ms after the go"
  assert press([caster_news]) == refused(result: 306)
    as "still refused at 8499 ms after the go"
  driven_time.advance(time: watched.time, ms: 1)
  let caster_end =
    next_state_news(
      received: watched.caster,
      unit_id:,
      what: "the caster's news of the end",
    )
  let viewer_end =
    next_state_news(
      received: watched.viewer,
      unit_id:,
      what: "the second connection's news of the end",
    )
  assert caster_end == Ended(number: 1) && viewer_end == Ended(number: 1)
    as "the end is told at 8500 ms after the go, by the number it was held under"
  assert press([caster_news, caster_end]) == goes
    as "the same press goes at 8500 ms"
  world_support.stop(world: watched.world)
}

pub fn a_beneficial_press_at_a_creature_holding_state_6_goes_test() -> Nil {
  use <- owned_test.run(60_000)
  use hostile <- press_tables(flags: hostile_flags)
  use beneficial <- press_tables(flags: beneficial_flags)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  let unit_id = watched.beast.unit_id
  let _told = state_go_on(watched:)
  let held =
    next_state_news(
      received: watched.caster,
      unit_id:,
      what: "the caster's news of the state",
    )
  assert held == Held(state: 6, number: 1)
  assert pressed(
      watched:,
      tables: beneficial,
      appeared: watched.appeared,
      news: [held],
    )
    == goes
    as "a beneficial press goes while the creature holds state 6"
  assert pressed(watched:, tables: hostile, appeared: watched.appeared, news: [
      held,
    ])
    == refused(result: 306)
    as "the hostile press is refused at the same moment"
  world_support.stop(world: watched.world)
}

/// A world of two Battle Beasts at x 0 and x 5, each seen by the caster's connection 1 and
/// a second connection 2: the 0x262 of each, as they were sent to each connection.
type TwoBeasts {
  TwoBeasts(
    world: World,
    run: MapProcess,
    time: driven_time.Time,
    caster: Subject(Message),
    viewer: Subject(Message),
    held: #(Int, Int),
    other: #(Int, Int),
  )
}

/// The life the creature is found under in the registry: the number of the watch its map
/// opened on it, which the test does not choose.
fn life_of(
  time time: driven_time.Time,
  world world: World,
  run run: MapProcess,
  unit_id unit_id: Int,
) -> Int {
  let found = fn() {
    list.find([2, 3, 4, 5, 6], fn(life) {
      creature_registry.find(
        world.creatures,
        map: world_watch_support.ship,
        incarnation: run.incarnation,
        unit_id:,
        life:,
      )
      != Error(Nil)
    })
  }
  driven_time.wait_for(
    time:,
    what: "the creature of unit "
      <> int.to_string(unit_id)
      <> " to join its address under a life of 2 to 6",
    condition: fn() { found() != Error(Nil) },
  )
  let assert Ok(life) = found()
  life
}

fn two_beasts() -> TwoBeasts {
  let time = driven_time.new()
  let world =
    world_support.start(
      time:,
      spawns: [
        spawn_support.battle_beast(number: 1, x: 0.0),
        spawn_support.battle_beast(number: 2, x: 5.0),
      ],
      respawn_ms: 60_000,
      idle_stop_ms: world_watch_support.idle_stop_ms,
      sweep_ms: world_watch_support.sweep_ms,
    )
  let run = world_watch_support.started(world)
  let caster = world_support.connection(world:, id: 1)
  let viewer = world_support.connection(world:, id: 2)
  let _caster_unit = world_watch_support.join(run:, connection: 1)
  let _viewer_unit = world_watch_support.join(run:, connection: 2)
  let appear = fn(received) {
    world_watch_support.next(
      received:,
      what: "a beast's 0x262",
      wanted: world_watch_support.appearance,
    )
  }
  let first = appear(caster)
  let second = appear(caster)
  let _first_at_viewer = appear(viewer)
  let _second_at_viewer = appear(viewer)
  TwoBeasts(
    world:,
    run:,
    time:,
    caster:,
    viewer:,
    held: #(first.unit_id, life_of(time:, world:, run:, unit_id: first.unit_id)),
    other: #(
      second.unit_id,
      life_of(time:, world:, run:, unit_id: second.unit_id),
    ),
  )
}

/// The outcome of the strike `cast_id` of the caster's connection on a beast: told through
/// the registry, answered to the connection.
fn struck_outcome(
  beasts beasts: TwoBeasts,
  unit unit: #(Int, Int),
  cast_id cast_id: Int,
) -> strike_tell.Outcome {
  world_watch_support.strike_with(
    run: beasts.run,
    unit_id: unit.0,
    life: unit.1,
    damage_type: 3,
    damage: 10,
    cast_id:,
  )
  world_watch_support.next(
    received: beasts.caster,
    what: "the answer to strike " <> int.to_string(cast_id),
    wanted: fn(message) { world_watch_support.answer_to(message:, cast_id:) },
  )
}

pub fn an_area_go_skips_the_invulnerable_creature_and_logs_type_18_for_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let beasts = two_beasts()
  let #(held_id, held_life) = beasts.held
  let other_id = beasts.other.0
  // A first go holds state 6 on the first beast.
  let struck_at_ms = world_watch_support.clock_ms(time: beasts.time)
  let went_at_ms = struck_at_ms
  let held_pid =
    world_watch_support.creature_pid(
      time: beasts.time,
      world: beasts.world,
      run: beasts.run,
      unit_id: held_id,
      life: held_life,
    )
  let _told =
    carried_out(
      run: beasts.run,
      effects: state_go(
        row: state_6_row(),
        units: [#(held_id, held_life)],
        struck_at_ms:,
        went_at_ms:,
      ),
    )
  driven_time.settled(held_pid)
  // An area go then strikes both: the creature that holds the state answers `Immune`, the
  // other takes the blow.
  let held_outcome = struck_outcome(beasts:, unit: beasts.held, cast_id: 1)
  let other_outcome = struck_outcome(beasts:, unit: beasts.other, cast_id: 2)
  let assert strike_tell.Immune(..) = held_outcome
    as "the creature that holds state 6 answers immune"
  let assert Landed(descriptions: [_], ..) = other_outcome
    as "the other creature takes the blow"
  let struck_unit = fn(unit: #(Int, Int), outcome) {
    let hit_unit = cast_state.HitCreature(life: unit.1)
    case outcome {
      strike_tell.Immune(controls: _, ..) ->
        cast_state.Immune(
          unit_id: unit.0,
          unit: hit_unit,
          controls: [],
          armor_removed: 0,
          ticking: [],
        )
      Landed(descriptions:, ..) ->
        cast_state.Hit(
          unit_id: unit.0,
          unit: hit_unit,
          descriptions:,
          controls: [],
          armor_removed: 0,
          ticking: [],
        )
      strike_tell.Deflected(..) | strike_tell.Refused(..) ->
        panic as "the creatures answer immune or landed here"
    }
  }
  let #(_, effects) =
    cast_support.pressed_striking(
      state: cast_state.new(),
      bag_index: cast_support.pulse_blast,
      struck: [
        struck_unit(beasts.held, held_outcome),
        struck_unit(beasts.other, other_outcome),
      ],
      at: went_at_ms,
    )
  let assert [go_frame, ..] =
    cast_support.frames_of(message_id: spell_go.message_id, effects:)
    as "the go is written to the caster"
  let assert Ok(go) = spell_go.decode(go_frame.body)
  let listed =
    list.map(go.targets, fn(target) { #(target.unit_id, target.effects) })
  assert list.map(listed, fn(one) { one.0 }) == [held_id, other_id]
    as "the 0x7f4 names both creatures"
  let damage_listed = fn(effects: List(spell_effect_info.SpellEffectInfo)) {
    list.any(effects, fn(effect) {
      case effect.result {
        spell_effect_result.Damage(..) -> True
        spell_effect_result.Bit(..) -> False
      }
    })
  }
  let assert [#(_, held_effects), #(_, other_effects)] = listed
    as "the two creatures"
  assert !damage_listed(held_effects) && damage_listed(other_effects)
    as "the creature that holds the state is listed with no damage description, the other with its blow"
  let logged =
    list.map(
      cast_support.frames_of(message_id: combat_log.message_id, effects:),
      fn(frame) {
        let assert Ok(decoded) = combat_log.decode(frame.body)
          as "a 0x247 the rule wrote decodes"
        decoded.entry
      },
    )
  let assert [combat_log_entry.Immunity(immunity)] = logged
    as "one combat log entry of type 18, for the creature that held the state only"
  assert immunity.target_unit_id == held_id
    && immunity.caster_unit_id == the_caster
    && immunity.spell4_id == started_spell4_id(effects:)
    && immunity.combat_result == combat_result.Hit
    as "naming the caster, the creature and the spell"
  // The other creature lost health, and the second viewer saw that and nothing for the
  // creature that holds the state.
  let health_of_other =
    world_watch_support.next(
      received: beasts.viewer,
      what: "the second viewer's 0x937 for the other creature",
      wanted: fn(message) { health_of(unit_id: other_id, message:) },
    )
  assert health_of_other < 52 as "the other creature lost health"
  driven_time.settled(held_pid)
  assert health_news_waiting(received: beasts.viewer, unit_id: held_id) == []
    as "the creature that holds the state sent no 0x937"
  world_support.stop(world: beasts.world)
}

pub fn the_creature_is_struck_normally_once_the_state_ends_test() -> Nil {
  use <- owned_test.run(60_000)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  let unit_id = watched.beast.unit_id
  let _told = state_go_on(watched:)
  let _held = next_state_news(received: watched.caster, unit_id:, what: "held")
  let strike = fn(cast_id) {
    world_watch_support.strike_with(
      run: watched.run,
      unit_id:,
      life: 2,
      damage_type: 3,
      damage: 10,
      cast_id:,
    )
    world_watch_support.next(
      received: watched.caster,
      what: "the answer to strike " <> int.to_string(cast_id),
      wanted: fn(message) { world_watch_support.answer_to(message:, cast_id:) },
    )
  }
  let assert strike_tell.Immune(..) = strike(1)
    as "a strike while the state holds is answered immune"
  driven_time.advance(time: watched.time, ms: 8500)
  let assert Landed(descriptions: [_], ..) = strike(2)
    as "a strike once it ended lands"
  let seen_by = fn(received) {
    world_watch_support.next(
      received:,
      what: "the creature's 0x937",
      wanted: fn(message) { health_of(unit_id:, message:) },
    )
  }
  assert seen_by(watched.caster) < 52 && seen_by(watched.viewer) < 52
    as "health fell and both viewers were sent the 0x937"
  world_support.stop(world: watched.world)
}

pub fn a_unit_state_outlives_the_casters_leaving_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- press_tables(flags: hostile_flags)
  // The creature owns the end (the Design artifact of issue 795, option A): the caster's
  // connection is not needed after the tell.
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  let unit_id = watched.beast.unit_id
  let _told = state_go_on(watched:)
  let held =
    next_state_news(
      received: watched.viewer,
      unit_id:,
      what: "the second viewer's news of the state",
    )
  world_watch_support.left(run: watched.run, connection: 1)
  driven_time.advance(time: watched.time, ms: 8499)
  assert state_news_waiting(received: watched.viewer, unit_id:) == []
    as "nothing ended before the row's end"
  driven_time.advance(time: watched.time, ms: 1)
  let ended =
    next_state_news(
      received: watched.viewer,
      unit_id:,
      what: "the second viewer's news of the end",
    )
  assert ended == Ended(number: 1)
  assert pressed(watched:, tables:, appeared: watched.appeared, news: [
      held,
      ended,
    ])
    == goes
    as "the second viewer's press then goes"
  world_support.stop(world: watched.world)
}

pub fn a_late_viewer_is_told_the_held_state_and_its_press_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- press_tables(flags: hostile_flags)
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  let unit_id = watched.beast.unit_id
  let _told = state_go_on(watched:)
  let _held = next_state_news(received: watched.caster, unit_id:, what: "held")
  driven_time.advance(time: watched.time, ms: 3000)
  let late = world_support.connection(world: watched.world, id: 3)
  let _late_unit = world_watch_support.join(run: watched.run, connection: 3)
  let appeared =
    world_watch_support.next(
      received: late,
      what: "the beast's 0x262 to the late viewer",
      wanted: world_watch_support.appeared_news,
    )
  let told =
    next_state_news(
      received: late,
      unit_id:,
      what: "the late viewer's news of the state",
    )
  assert told == Held(state: 6, number: 1)
    as "a viewer that arrives while the state is held is told it after the 0x262"
  assert pressed(watched:, tables:, appeared:, news: [told])
    == refused(result: 306)
    as "and its hostile press is refused"
  world_support.stop(world: watched.world)
}

pub fn a_creature_that_crashes_holding_a_state_returns_without_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- press_tables(flags: hostile_flags)
  // The map's crash row for a creature (`map.creature_ended`): the players are sent `Gone`
  // and the spawn returns as a new unit after the respawn time, whatever the creature held.
  let respawn_ms = 1000
  let watched = world_watch_support.watched_by_two(respawn_ms:)
  let unit_id = watched.beast.unit_id
  let _told = state_go_on(watched:)
  let _held = next_state_news(received: watched.caster, unit_id:, what: "held")
  process.kill(watched.pid)
  let gone =
    world_watch_support.next(
      received: watched.caster,
      what: "Gone for the creature that held a state",
      wanted: world_watch_support.gone_unit,
    )
  assert gone == unit_id
  // `Gone` is sent before the restart timer starts: the advance's barrier waits for
  // the map to finish that step.
  driven_time.advance(time: watched.time, ms: respawn_ms)
  let returned =
    world_watch_support.next(
      received: watched.caster,
      what: "the returned creature's 0x262",
      wanted: world_watch_support.appeared_news,
    )
  assert returned.unit_id != unit_id as "the spawn returns as a new unit"
  let again =
    world_watch_support.creature_pid(
      time: watched.time,
      world: watched.world,
      run: watched.run,
      unit_id: returned.unit_id,
      life: 4,
    )
  driven_time.settled(again)
  assert state_news_waiting(received: watched.caster, unit_id: returned.unit_id)
    == []
    as "the new unit holds no state"
  assert pressed(watched:, tables:, appeared: returned, news: []) == goes
    as "a hostile press at it goes"
  world_watch_support.strike_with(
    run: watched.run,
    unit_id: returned.unit_id,
    life: 4,
    damage_type: 3,
    damage: 10,
    cast_id: 5,
  )
  let assert Landed(..) =
    world_watch_support.next(
      received: watched.caster,
      what: "the answer to strike 5",
      wanted: fn(message) {
        world_watch_support.answer_to(message:, cast_id: 5)
      },
    )
    as "and a strike lands on it"
  world_support.stop(world: watched.world)
}
