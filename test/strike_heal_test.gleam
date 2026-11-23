//// A go's heal rows told to the player that is its primary target
//// (`genesis_prime/game/strike`), run as the pure rule it is on a driven clock: which go
//// selects a player, the tell its connection is sent, and the answer that fills the
//// player's place in the round. Expected values come from these places.
//// - The client's rows, kept in the fixture (`table_rows -- Spell4Effects 62019`,
////   `-- Spell4 32820 32893`): Mind Over Body (Spell4 32820) holds one heal, Spell4Effects
////   62019 (type 10, targetFlags 2 = the primary target, no tickTime, no delay, parameter
////   13 x 0.3281 and 10 x 17.51); Telekinetic Strike (Spell4 32893) holds none.
//// - The caster of level 5 and 400 Support Rating gives that row round(0.3281 x 100) +
////   17.51 x 5 = 33 + 87.55 = 121 (the stat part is rounded alone, `0x140565600`; the
////   doc of `healing_caster` in `test/cast_heal_test.gleam`).
//// - The strike rule's own doc comment and `strike_tell`'s: a strike is told once for each
////   place; a round closes when each place is filled or its 1 s deadline is processed; the
////   go lists the units in selection order; an answer for a round that is closed or a
////   place that is filled is dropped.

import attacker_support
import cast_support
import genesis_prime/game/cast/state.{GoAsked} as cast_state
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/heal_split.{Split}
import genesis_prime/game/player_address.{type PlayerAddress, PlayerAddress}
import genesis_prime/game/shown
import genesis_prime/game/spell_area
import genesis_prime/game/strike.{
  type Attacker, type Effect, type Selection, Selection,
}
import genesis_prime/game/strike_tell.{
  type PlayerOutcome, HealLanded, HealsLanded, PlayerAnswered, PlayerDead,
}
import genesis_prime/game/unit_properties
import genesis_prime/step.{ConnectionId, Now}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id, UnitProperty2Id}
import genesis_prime/world_map/creature_life.{Attackable}
import gleam/dict
import gleam/list
import gleam/option.{None}
import map_support
import owned_test
import properties_support
import rating_support
import spell_tables
import strike_support

const mind_over_body = 32_820

const telekinetic_strike = 32_893

/// The player the map named: connection 3, in the stay its notice named.
fn ally(unit_id unit_id: Int) -> PlayerAddress {
  PlayerAddress(
    connection: ConnectionId(3),
    unit_id:,
    stay: map_support.stay(count: 2),
  )
}

/// The areas of the fixture's rows with the area of Mind Over Body: the fixture's plans
/// hold the level-1 trees only, so Mind Over Body (an Esper's at level 6) is planned on its
/// own, in an area of no row, as the load builds a spell with no `Spell4AoeTargetConstraints`
/// row.
fn areas() -> spell_area.Areas {
  dict.insert(
    spell_tables.fixture_areas(),
    mind_over_body,
    spell_tables.area_alone(spell4_id: mind_over_body),
  )
}

fn area_of(spell4_id spell4_id: Int) -> spell_area.SpellArea {
  let assert Ok(area) =
    spell_area.of_spell(areas: areas(), spell4_id: Spell4Id(spell4_id))
    as "the spell is in the areas"
  area
}

/// The instant heal rows Mind Over Body's first phase tells a player.
fn mind_over_body_heals() -> List(spell_area.InstantHeal) {
  let assert Ok(phase) =
    spell_area.phase(
      spell: area_of(spell4_id: mind_over_body),
      phase: 0,
      spent: None,
    )
    as "Mind Over Body has a first phase"
  phase.heals
}

fn go(
  primary_target primary_target: Int,
  spell4_id spell4_id: Int,
) -> cast_state.GoAsked {
  GoAsked(
    cast_id: 5,
    phase: 0,
    spell4_id: Spell4Id(spell4_id),
    primary_target:,
    spent: None,
    started_at: strike_support.start_pose(),
  )
}

fn at(ms ms: Int) -> step.Now {
  Now(monotonic_ms: ms, filetime: 0)
}

/// The caster of level 5 and 400 Support Rating, with the healing multiplier outgoing 162
/// at 1.25 and `sight` its players in sight by unit id.
fn healer(sight sight: List(PlayerAddress)) -> Attacker {
  let properties =
    properties_support.with_modifier(
      properties: properties_support.fresh(level: 1),
      source: cast_support.source_of(cast_id: 162, effect_id: 1900),
      modifier: unit_properties.Change(
        property: UnitProperty2Id(162),
        mode: 1,
        multiplier: 1.25,
        flat: 0.0,
        per_level: 0.0,
      ),
    )
  strike.Attacker(
    ..strike_support.attacker(),
    stats: damage.Attacker(
      ..attacker_support.fresh(),
      level: 5,
      assault_rating: 0.0,
      support_rating: 400.0,
    ),
    properties:,
    players_in_sight: dict.from_list(
      list.map(sight, fn(address) { #(address.unit_id, address) }),
    ),
  )
}

fn selected(
  primary_target primary_target: Int,
  spell4_id spell4_id: Int,
  sight sight: List(PlayerAddress),
  picture picture: shown.Picture,
) -> Selection {
  strike.select(
    asked: go(primary_target:, spell4_id:),
    attacker: healer(sight:),
    picture:,
    areas: areas(),
    now_ms: 1000,
  )
}

/// A picture of the player 9 and the creature 20, both shown.
fn picture() -> shown.Picture {
  dict.from_list([
    #(9, shown.ShownPlayer(at: None)),
    #(
      20,
      strike_support.creature_at(
        x: 0.0,
        z: -3.0,
        alive: True,
        attackable: Attackable(exile: True, dominion: True),
      ),
    ),
  ])
}

type SelectRow {
  SelectRow(
    reason: String,
    primary_target: Int,
    spell4_id: Int,
    sight: List(PlayerAddress),
    players: List(PlayerAddress),
    heals: List(Int),
  )
}

pub fn a_go_selects_a_player_primary_target_only_when_it_is_in_sight_and_the_phase_has_heal_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      SelectRow(
        "the primary target is a player in sight and Mind Over Body has the heal row 62019: the player and the row are selected",
        9,
        mind_over_body,
        [ally(unit_id: 9)],
        [ally(unit_id: 9)],
        [62_019],
      ),
      SelectRow(
        "the primary target is a creature the picture shows: no player, no row",
        20,
        mind_over_body,
        [ally(unit_id: 9)],
        [],
        [],
      ),
      SelectRow(
        "the primary target is the caster itself, which is no player in its own sight",
        7,
        mind_over_body,
        [ally(unit_id: 9)],
        [],
        [],
      ),
      SelectRow(
        "the player left the caster's sight between the press and the go: no player, no row",
        9,
        mind_over_body,
        [],
        [],
        [],
      ),
      SelectRow(
        "Telekinetic Strike holds no heal row: the player in sight is not selected",
        9,
        telekinetic_strike,
        [ally(unit_id: 9)],
        [],
        [],
      ),
    ],
    fn(row) {
      let selection =
        selected(
          primary_target: row.primary_target,
          spell4_id: row.spell4_id,
          sight: row.sight,
          picture: picture(),
        )
      assert selection.players == row.players as row.reason
      assert list.map(selection.heals, fn(heal) { heal.effect_id.value })
        == row.heals
        as row.reason
      assert selection.units == []
        as "a player is not among the creatures a strike is told to, and no creature is added for a heal"
    },
  )
}

/// A selection of the player 9 for the heal rows `heals`, with the creatures `units` in
/// the area, each struck by one damage row.
fn selection_of(
  units units: List(Int),
  heals heals: List(spell_area.InstantHeal),
) -> Selection {
  Selection(
    asked: go(primary_target: 9, spell4_id: mind_over_body),
    units: list.map(units, fn(unit_id) { strike.Aimed(unit_id:, life: 3) }),
    area: units,
    blows: case units {
      [] -> []
      [_, ..] -> [strike_support.damage_effect()]
    },
    ticking: [],
    controls: [],
    gates: [],
    players: [ally(unit_id: 9)],
    heals:,
  )
}

/// 12 seed bytes of zeros for each creature.
fn zeros(units units: List(Int)) -> BitArray {
  list.fold(units, <<>>, fn(bytes, _) { <<bytes:bits, 0:size(96)>> })
}

fn begun(
  state state: strike.State,
  selection selection: Selection,
) -> #(strike.State, List(Effect)) {
  strike.begin(
    strike: state,
    selection:,
    attacker: healer(sight: [ally(unit_id: 9)]),
    formulas: rating_support.formulas(),
    entropy: zeros(
      units: list.map(selection.units, fn(aimed) { aimed.unit_id }),
    ),
    gate: strike_support.passes_all(),
    now: at(ms: 1000),
  )
}

/// What a begun round tells, in order: a creature's unit, or a player's unit and its strike.
type Told {
  ToldCreature(unit_id: Int)
  ToldPlayer(address: PlayerAddress, strike: strike_tell.PlayerStrike)
  Started(after_ms: Int)
}

fn told(effects effects: List(Effect)) -> List(Told) {
  list.filter_map(effects, fn(effect) {
    case effect {
      strike.TellStrike(unit_id:, ..) -> Ok(ToldCreature(unit_id:))
      strike.TellPlayerStrike(address:, strike:) ->
        Ok(ToldPlayer(address:, strike:))
      strike.StartTimer(after_ms:, ..) -> Ok(Started(after_ms:))
      strike.CancelTimer(..)
      | strike.Went(..)
      | strike.Ticked(..)
      | strike.Released(..)
      | strike.Log(..) -> Error(Nil)
    }
  })
}

/// The strike the caster's connection 2 in its first stay tells the player 9 for the
/// cast 5 with the caster's outgoing multiplier 1.25.
fn heal_strike_of(
  heals heals: List(#(effect_kind.Vital, Int)),
) -> strike_tell.PlayerStrike {
  strike_support.heal_strike(
    from: ConnectionId(2),
    stay: map_support.stay(count: 1),
    cast_id: 5,
    unit_id: 9,
    outgoing: 1.25,
    heals:,
  )
}

pub fn a_go_at_a_player_tells_its_connection_each_row_once_with_the_casters_outgoing_multiplier_in_plan_order_test() -> Nil {
  use <- owned_test.run(60_000)
  let health_row = {
    let assert [row] = mind_over_body_heals()
      as "Mind Over Body's first phase holds the one heal 62019"
    row
  }
  // No real row is a shield heal of its own formula in a spell that also heals health, so
  // the second row is the real one with another id, vital and a flat formula.
  let shield_row =
    spell_area.InstantHeal(
      ..health_row,
      effect_id: Spell4EffectsId(62_020),
      vital: effect_kind.Shield,
      formula: damage.Formula(multiplier: 1.0, base: 50.0, parameters: []),
    )
  list.each(
    [
      #(
        "one instant health row gives one tell of 121 to connection 3 and one 1000 ms timer, and no strike of a creature",
        selection_of(units: [], heals: [health_row]),
        [
          ToldPlayer(
            address: ally(unit_id: 9),
            strike: heal_strike_of(heals: [#(effect_kind.Health, 121)]),
          ),
          Started(after_ms: 1000),
        ],
      ),
      #(
        "two rows are told in the plan's order, each with its own amount",
        selection_of(units: [], heals: [health_row, shield_row]),
        [
          ToldPlayer(
            address: ally(unit_id: 9),
            strike: heal_strike_of(heals: [
              #(effect_kind.Health, 121),
              #(effect_kind.Shield, 50),
            ]),
          ),
          Started(after_ms: 1000),
        ],
      ),
      #(
        "a creature in the area is told first and the player after it, each unit once",
        selection_of(units: [10], heals: [health_row]),
        [
          ToldCreature(unit_id: 10),
          ToldPlayer(
            address: ally(unit_id: 9),
            strike: heal_strike_of(heals: [#(effect_kind.Health, 121)]),
          ),
          Started(after_ms: 1000),
        ],
      ),
    ],
    fn(row) {
      let #(reason, selection, expected) = row
      let #(_, effects) = begun(state: strike.new(), selection:)
      assert told(effects:) == expected as reason
    },
  )
}

// ---- the player's answer ----

type Input {
  /// The player 9 answers the strike told for key `cast_id`, phase `phase`, unit `unit_id`.
  PlayerSays(
    cast_id: Int,
    phase: Int,
    unit_id: Int,
    outcome: PlayerOutcome,
    at_ms: Int,
  )
  /// The creature 10 answers that its strike landed.
  CreatureLands(at_ms: Int)
  TimerProcessed(at_ms: Int)
}

fn first_heal() -> strike_tell.HealLanded {
  HealLanded(
    effect_id: Spell4EffectsId(62_019),
    vital: effect_kind.Health,
    split: Split(amount: 121, shield: 0, health: 100, overheal: 21),
  )
}

fn second_heal() -> strike_tell.HealLanded {
  HealLanded(
    effect_id: Spell4EffectsId(62_020),
    vital: effect_kind.Shield,
    split: Split(amount: 50, shield: 50, health: 0, overheal: 0),
  )
}

fn says(outcome outcome: PlayerOutcome, at_ms at_ms: Int) -> Input {
  PlayerSays(cast_id: 5, phase: 0, unit_id: 9, outcome:, at_ms:)
}

/// The player 9's place in the go's list, as it is struck.
fn player_hit(heals heals: List(strike_tell.HealLanded)) -> cast_state.Struck {
  cast_state.Hit(
    unit_id: 9,
    unit: cast_state.HitOtherPlayer(heals:),
    descriptions: [],
    controls: [],
    armor_removed: 0,
    ticking: [],
  )
}

fn creature_hit() -> cast_state.Struck {
  cast_state.Hit(
    unit_id: 10,
    unit: cast_state.HitCreature(life: 3, struck_at_ms: 1000),
    descriptions: [],
    controls: [],
    armor_removed: 0,
    ticking: [],
  )
}

/// The go of the round closing with `struck`, after the timer the go started is cancelled.
fn closed_with(struck struck: List(cast_state.Struck)) -> List(Effect) {
  [
    strike.CancelTimer(timer: strike.strike_timer),
    strike.Went(
      asked: go(primary_target: 9, spell4_id: mind_over_body),
      struck:,
      gates_passed: dict.new(),
    ),
  ]
}

type AnswerRow {
  AnswerRow(
    reason: String,
    units: List(Int),
    inputs: List(Input),
    effects: List(List(Effect)),
  )
}

/// Each input applied in turn to the state the one before left, from the round `begin`
/// opens, the effects of each.
fn run(row row: AnswerRow) -> List(List(Effect)) {
  let heals = [
    {
      let assert [heal] = mind_over_body_heals()
        as "Mind Over Body's first phase holds the one heal 62019"
      heal
    },
  ]
  let #(state, _) =
    begun(
      state: strike.new(),
      selection: selection_of(units: row.units, heals:),
    )
  let #(_, taken) =
    list.fold(row.inputs, #(state, []), fn(so_far, input) {
      let #(state, taken) = so_far
      let #(state, effects) = case input {
        PlayerSays(cast_id:, phase:, unit_id:, outcome:, at_ms:) ->
          strike.player_answered(
            strike: state,
            answer: PlayerAnswered(
              key: strike_tell.Key(
                cast_id:,
                occasion: strike_tell.AtGo(phase:),
                unit_id:,
              ),
              outcome:,
            ),
            now: at(ms: at_ms),
          )
        CreatureLands(at_ms:) ->
          strike.answered(
            strike: state,
            answer: strike_tell.Answered(
              key: strike_tell.Key(
                cast_id: 5,
                occasion: strike_tell.AtGo(phase: 0),
                unit_id: 10,
              ),
              outcome: strike_tell.Landed(
                descriptions: [],
                controls: [],
                armor_removed: 0,
                gates_passed: [],
              ),
            ),
            now: at(ms: at_ms),
          )
        TimerProcessed(at_ms:) ->
          strike.timer_fired(strike: state, now: at(ms: at_ms))
      }
      #(state, list.append(taken, [effects]))
    })
  taken
}

pub fn a_players_answer_fills_its_place_and_the_go_lists_the_player_with_what_it_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      AnswerRow(
        "the heals landed close the round: the timer is cancelled and the go lists the player with what it applied and no description",
        [],
        [says(HealsLanded([first_heal(), second_heal()]), at_ms: 1100)],
        [
          closed_with(struck: [player_hit(heals: [first_heal(), second_heal()])]),
        ],
      ),
      AnswerRow(
        "a dead player leaves its place: the go is still written and names no one",
        [],
        [says(PlayerDead, at_ms: 1100)],
        [closed_with(struck: [])],
      ),
      AnswerRow(
        "the player answers before the creature: the round waits for the creature, then lists the creature first, in selection order",
        [10],
        [
          says(HealsLanded([first_heal()]), at_ms: 1100),
          CreatureLands(at_ms: 1200),
        ],
        [
          [],
          closed_with(struck: [
            creature_hit(),
            player_hit(heals: [first_heal()]),
          ]),
        ],
      ),
      AnswerRow(
        "a second answer for the same place is dropped and the first answer's heals stand",
        [10],
        [
          says(HealsLanded([first_heal()]), at_ms: 1100),
          says(HealsLanded([second_heal()]), at_ms: 1150),
          CreatureLands(at_ms: 1200),
        ],
        [
          [],
          [],
          closed_with(struck: [
            creature_hit(),
            player_hit(heals: [first_heal()]),
          ]),
        ],
      ),
      AnswerRow(
        "an answer for another cast, another phase or another unit finds no place and is dropped: the player is left out when the timer is processed",
        [10],
        [
          PlayerSays(
            cast_id: 6,
            phase: 0,
            unit_id: 9,
            outcome: HealsLanded([first_heal()]),
            at_ms: 1100,
          ),
          PlayerSays(
            cast_id: 5,
            phase: 1,
            unit_id: 9,
            outcome: HealsLanded([first_heal()]),
            at_ms: 1100,
          ),
          PlayerSays(
            cast_id: 5,
            phase: 0,
            unit_id: 11,
            outcome: HealsLanded([first_heal()]),
            at_ms: 1100,
          ),
          CreatureLands(at_ms: 1200),
          TimerProcessed(at_ms: 2000),
        ],
        [
          [],
          [],
          [],
          [],
          [
            strike.Went(
              asked: go(primary_target: 9, spell4_id: mind_over_body),
              struck: [creature_hit()],
              gates_passed: dict.new(),
            ),
          ],
        ],
      ),
      AnswerRow(
        "an answer processed at 2500, after the deadline of 2000 but before the timer is processed, is taken and listed: the round closes by processing its timer, not by the clock",
        [],
        [says(HealsLanded([first_heal()]), at_ms: 2500)],
        [closed_with(struck: [player_hit(heals: [first_heal()])])],
      ),
      AnswerRow(
        "an answer processed after the timer closed the round is dropped and the go lists no player",
        [],
        [
          TimerProcessed(at_ms: 2000),
          says(HealsLanded([first_heal()]), at_ms: 2100),
        ],
        [
          [
            strike.Went(
              asked: go(primary_target: 9, spell4_id: mind_over_body),
              struck: [],
              gates_passed: dict.new(),
            ),
          ],
          [],
        ],
      ),
    ],
    fn(row) {
      let observed = run(row:)
      // The timer's effects that start with the go are not part of what an input does, so
      // the rows list only what each input's step carries.
      assert observed == row.effects as row.reason
    },
  )
}
