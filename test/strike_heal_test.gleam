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
import client_tables
import fixture_tables
import genesis_prime/game/cast/state.{GoAsked} as cast_state
import genesis_prime/game/heal_split.{Split}
import genesis_prime/game/player_address.{type PlayerAddress, PlayerAddress}
import genesis_prime/game/player_state
import genesis_prime/game/shown
import genesis_prime/game/strike.{
  type Attacker, type Effect, type Selection, Selection,
}
import genesis_prime/shared/area
import genesis_prime/shared/damage
import genesis_prime/shared/effect_kind
import genesis_prime/shared/spell_area
import genesis_prime/shared/spell_plan
import genesis_prime/shared/strike_tell.{
  type PlayerAnswered, type PlayerOutcome, HealLanded, HealsLanded,
  PlayerAnswered, PlayerDead,
}
import genesis_prime/shared/target_mechanic
import genesis_prime/shared/unit_properties
import genesis_prime/step.{ConnectionId, Now}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id, UnitProperty2Id}
import genesis_prime/world_map/creature_life.{Attackable}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import map_support
import owned_test
import place_support
import planted_table
import player_state_support
import properties_support
import rating_support
import spell_tables
import strike_support
import unitest

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
    fired: False,
  )
}

fn at(ms ms: Int) -> step.Now {
  Now(monotonic_ms: ms, filetime: 0)
}

/// The caster of level 5 and 400 Support Rating, with the healing multiplier outgoing 162
/// at 1.25 and `sight` its players in sight by unit id.
fn healer(sight sight: List(PlayerAddress)) -> Attacker {
  healer_with(sight:, support_rating: 400.0, outgoing: 1.25)
}

/// The same with this Support Rating and this healing multiplier outgoing.
fn healer_with(
  sight sight: List(PlayerAddress),
  support_rating support_rating: Float,
  outgoing outgoing: Float,
) -> Attacker {
  let properties =
    properties_support.with_modifier(
      properties: properties_support.fresh(level: 1),
      source: cast_support.source_of(cast_id: 162, effect_id: 1900),
      modifier: unit_properties.Change(
        property: UnitProperty2Id(162),
        mode: 1,
        multiplier: outgoing,
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
      support_rating:,
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
    #(9, shown.ShownPlayer(state: player_state_support.a_player())),
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

// ---- the allies of a friendly area ----

/// A player of the picture at (`x`, `z`) in the caster's world and zone, Friendly to it, whom a
/// caster at the origin facing -z has `z` metres behind it when `z` is positive.
fn player_at(x x: Float, z z: Float) -> shown.Shown {
  shown.ShownPlayer(
    state: player_state.PlayerState(
      ..player_state_support.a_player(),
      place: Some(place_support.at(
        world_id: 3460,
        world_zone_id: 5967,
        x:,
        y: 0.0,
        z:,
      )),
    ),
  )
}

/// A player of the picture at (`x`, `z`) as `player_at` has it, missing `missing` health of
/// the maximum `player_state_support.full_health`.
fn hurt_at(x x: Float, z z: Float, missing missing: Int) -> shown.Shown {
  let assert shown.ShownPlayer(state:) = player_at(x:, z:)
    as "`player_at` is a shown player"
  shown.ShownPlayer(
    state: player_state.PlayerState(
      ..state,
      health: player_state_support.full_health - missing,
    ),
  )
}

/// The areas of the fixture's rows with Emission's heal row 141384 aimed at the area alone
/// (targetFlags 4, as Dual Fire's rows 84876 and 126516 are) and its area row 662 ordered by
/// missing health (targetSelection 5) taking `count` units, built as the load builds them.
fn emission_by_health_at_the_area_alone(count count: Int) -> spell_area.Areas {
  emission_by_health(flags: 4, count:, min_range: 0.0)
}

/// The areas of the fixture's rows with Emission's heal row 141384 of the targetFlags `flags`
/// and its area row 662 ordered by missing health (targetSelection 5), taking `count` units
/// from `min_range` metres, built as the load builds them.
fn emission_by_health(
  flags flags: Int,
  count count: Int,
  min_range min_range: Float,
) -> spell_area.Areas {
  emission_by_health_edited(flags:, count:, min_range:, telegraph: [])
}

/// The same with Emission's hit row (TelegraphDamage 3063, a cone drawn on the caster) made a
/// circle of 15 m with no offset drawn on the cast's target, as Warden's and Barrier's children
/// hold theirs: a spell that centres its area on the unit it is cast on and reads no facing, so
/// the load builds it for a child started on an ally (`spell_area.start_placed`).
fn emission_by_health_on_its_target(
  flags flags: Int,
  count count: Int,
  min_range min_range: Float,
) -> spell_area.Areas {
  emission_by_health_edited(flags:, count:, min_range:, telegraph: [
    #("TelegraphDamage", 3063, [
      #("damageShapeEnum", planted_table.Integer(0)),
      #("param00", planted_table.Float(15.0)),
      #("param01", planted_table.Float(0.0)),
      #("param02", planted_table.Float(0.0)),
      #("targetTypeFlags", planted_table.Integer(0)),
    ]),
  ])
}

fn emission_by_health_edited(
  flags flags: Int,
  count count: Int,
  min_range min_range: Float,
  telegraph telegraph: List(#(String, Int, List(#(String, planted_table.Cell)))),
) -> spell_area.Areas {
  fixture_tables.changes(
    edits: [
      #("Spell4Effects", 141_384, [
        #("targetFlags", planted_table.Integer(flags)),
      ]),
      #("Spell4AoeTargetConstraints", 662, [
        #("targetSelection", planted_table.Integer(5)),
        #("targetCount", planted_table.Integer(count)),
        #("minRange", planted_table.Float(min_range)),
      ]),
      ..telegraph
    ],
    body: fn(tables) {
      let assert Ok(areas) = spell_area.build(tables:)
        as "the edited rows build their areas"
      areas
    },
  )
}

/// The fixture's areas with the row of Emission's area (58841: Spell4AoeTargetConstraints 662,
/// 0 to 15 m, 4 targets, Closest) taking `count` units in `order`.
fn emission_areas(
  order order: area.Order,
  count count: Int,
) -> spell_area.Areas {
  let areas = spell_tables.fixture_areas()
  let assert Ok(emission) = dict.get(areas, 58_841)
    as "Emission is in the fixture's areas"
  let assert Some(row) = emission.row as "Emission has an area row"
  dict.insert(
    areas,
    58_841,
    spell_area.SpellArea(
      ..emission,
      row: Some(area.Row(..row, order:, target_count: count)),
    ),
  )
}

/// The fixture's areas with Emission's rows (Spell4 58841: its heal row 141384 of targetFlags 5
/// and its area row 662 ordered Closest) made to start Mental Boon's child 33258 on each unit its
/// area selects: the heal row itself turned into a Proxy at the area alone, or, with `heal_too`,
/// the heal row kept and a copy of it turned into that Proxy (row 900501). The area takes `count`
/// units. Emission's channel is cut to one pulse (channelMaxTime equal to channelInitialDelay),
/// since a Proxy at the area that fires at several gos is refused (`ProxyOnEachAllyAtSeveralGos`).
/// The edits stand in for no client row; they are the shape of Sentinel 54395 (a Proxy and no
/// heal) and of a phase that holds both.
fn emission_proxying(
  heal_too heal_too: Bool,
  count count: Int,
) -> spell_area.Areas {
  let as_proxy = [
    #("effectType", planted_table.Integer(26)),
    #("targetFlags", planted_table.Integer(4)),
    #("dataBits00", planted_table.Integer(33_258)),
  ]
  let assert Ok(rows) = case heal_too {
    True ->
      fixture_tables.add(
        rows: fixture_tables.rows(),
        table: "Spell4Effects",
        copy_of: 141_384,
        id: 900_501,
        with: as_proxy,
      )
    False -> Ok(fixture_tables.rows())
  }
    as "the heal row 141384 is in the fixture"
  let assert Ok(rows) =
    fixture_tables.change_all(rows:, edits: [
      #("Spell4", 58_841, [#("channelMaxTime", planted_table.Integer(410))]),
      #("Spell4AoeTargetConstraints", 662, [
        #("targetCount", planted_table.Integer(count)),
      ]),
      ..case heal_too {
        True -> []
        False -> [#("Spell4Effects", 141_384, as_proxy)]
      }
    ])
    as "the edits name rows and columns the fixture holds"
  fixture_tables.on_rows(rows:, reaching: [], body: fn(tables) {
    let assert Ok(areas) = spell_area.build(tables:)
      as "the edited rows build their areas"
    areas
  })
}

/// The fixture's areas with Emission's heal row 141384 made a UnitPropertyModifier of the units
/// its area selects (the cells of Energy Auger's row 217926: property 100, 5000 ms, targetFlags
/// 4), so the phase holds that change and no heal or Proxy, and its area row 662 taking `count`
/// units. The edits stand in for no client row; they are the shape of Energy Auger's phase in
/// the area of a spell that finds allies.
fn emission_changing(count count: Int) -> spell_area.Areas {
  fixture_tables.changes(
    edits: [
      #("Spell4Effects", 141_384, fixture_tables.area_modifier_cells()),
      #("Spell4AoeTargetConstraints", 662, [
        #("targetCount", planted_table.Integer(count)),
      ]),
    ],
    body: fn(tables) {
      let assert Ok(areas) = spell_area.build(tables:)
        as "the edited rows build their areas"
      areas
    },
  )
}

/// The fixture's areas with Emission's heal row 141384 made a Proc held by the units its area
/// selects (the cells of Healing Salve's row 86457, `fixture_tables.area_proc_cells`), so the
/// phase holds that Proc and no heal, Proxy or change, and its area row 662 taking `count` units.
/// The edits stand in for no client row; they are the shape of Healing Salve's phase in the area
/// of a spell that finds allies.
fn emission_procing(count count: Int) -> spell_area.Areas {
  fixture_tables.changes(
    edits: [
      #("Spell4Effects", 141_384, fixture_tables.area_proc_cells()),
      #("Spell4AoeTargetConstraints", 662, [
        #("targetCount", planted_table.Integer(count)),
      ]),
    ],
    body: fn(tables) {
      let assert Ok(areas) = spell_area.build(tables:)
        as "the edited rows build their areas"
      areas
    },
  )
}

type AllyRow {
  AllyRow(
    reason: String,
    areas: spell_area.Areas,
    picture: List(#(Int, shown.Shown)),
    sight: List(Int),
    players: List(Int),
  )
}

/// A friendly area selects the allies inside it (`Spell4AoeTargetConstraints.targetSelection`
/// and `.targetCount`; the client selects none itself, `Spell4AoeTargetConstraints.client_use`,
/// and its texts 361096 and 508644 say "yourself and N allies"): Emission's cone 3063 (shape 8,
/// 1 to 15 m over 50 degrees, ahead of the caster) capped by its row, nearest or furthest first,
/// from the players the caster has an address for, and never a creature or the caster. A foe's
/// area (Kick's) selects no player.
pub fn a_friendly_area_selects_the_allies_inside_it_by_its_order_and_count_and_a_hostile_one_selects_no_player_test() -> Nil {
  use <- owned_test.run(60_000)
  let three = [
    #(31, player_at(x: 0.0, z: -10.0)),
    #(32, player_at(x: 0.0, z: -4.0)),
    #(33, player_at(x: 0.0, z: -7.0)),
  ]
  list.each(
    [
      AllyRow(
        "three allies inside, count 2, nearest first: the two nearest, in order of distance",
        emission_areas(order: area.Nearest, count: 2),
        three,
        [31, 32, 33],
        [32, 33],
      ),
      AllyRow(
        "the same, furthest first: the two furthest, furthest first",
        emission_areas(order: area.Furthest, count: 2),
        three,
        [31, 32, 33],
        [31, 33],
      ),
      AllyRow(
        "an ally 40 m away and one 6 m behind the caster, outside the cone, are not selected",
        emission_areas(order: area.Nearest, count: 4),
        [
          #(32, player_at(x: 0.0, z: -4.0)),
          #(34, player_at(x: 0.0, z: -40.0)),
          #(35, player_at(x: 0.0, z: 6.0)),
        ],
        [32, 34, 35],
        [32],
      ),
      AllyRow(
        "the nearest ally has no address in the caster's sight: there is nothing to tell it, so the count of 1 goes to the next",
        emission_areas(order: area.Nearest, count: 1),
        [
          #(32, player_at(x: 0.0, z: -4.0)),
          #(36, player_at(x: 0.0, z: -3.0)),
        ],
        [32],
        [32],
      ),
      AllyRow(
        "a creature inside the cone is not selected, and the caster, shown as a player, is never one of the units of its area",
        emission_areas(order: area.Nearest, count: 4),
        [
          #(7, player_at(x: 0.0, z: -2.0)),
          #(
            20,
            strike_support.creature_at(
              x: 0.0,
              z: -5.0,
              alive: True,
              attackable: Attackable(exile: True, dominion: True),
            ),
          ),
          #(32, player_at(x: 0.0, z: -4.0)),
        ],
        [7, 32],
        [32],
      ),
      AllyRow(
        "by missing health, count 2: the two others missing the most, the most first, and the caster, missing more than any, is not among them (its flag heals it)",
        emission_areas(order: area.MissingMostHealth, count: 2),
        [
          #(7, hurt_at(x: 0.0, z: 0.0, missing: 4000)),
          #(31, hurt_at(x: 0.0, z: -10.0, missing: 100)),
          #(32, hurt_at(x: 0.0, z: -4.0, missing: 900)),
          #(33, hurt_at(x: 0.0, z: -7.0, missing: 500)),
          #(34, hurt_at(x: 0.0, z: -5.0, missing: 0)),
        ],
        [7, 31, 32, 33, 34],
        [32, 33],
      ),
      AllyRow(
        "by missing health, fewer allies than the count: all of them, the unhurt one last",
        emission_areas(order: area.MissingMostHealth, count: 4),
        [
          #(31, hurt_at(x: 0.0, z: -4.0, missing: 0)),
          #(32, hurt_at(x: 0.0, z: -10.0, missing: 300)),
        ],
        [31, 32],
        [32, 31],
      ),
      AllyRow(
        "by missing health, an ally outside the cone is not selected whatever it misses",
        emission_areas(order: area.MissingMostHealth, count: 4),
        [
          #(32, hurt_at(x: 0.0, z: -4.0, missing: 10)),
          #(34, hurt_at(x: 0.0, z: -40.0, missing: 4999)),
          #(35, hurt_at(x: 0.0, z: 6.0, missing: 4999)),
        ],
        [32, 34, 35],
        [32],
      ),
      AllyRow(
        "a heal row aimed at the area alone (targetFlags 4, as Dual Fire's) by missing health, count 2: the two allies missing the most, the most first (the caster's own place among the candidates is the next test's)",
        emission_by_health_at_the_area_alone(count: 2),
        [
          #(32, hurt_at(x: 0.0, z: -4.0, missing: 4000)),
          #(33, hurt_at(x: 0.0, z: -7.0, missing: 4800)),
          #(34, hurt_at(x: 0.0, z: -9.0, missing: 100)),
        ],
        [32, 33, 34],
        [33, 32],
      ),
    ],
    fn(row) {
      let selection =
        strike.select(
          asked: go(primary_target: 7, spell4_id: 58_841),
          attacker: healer(
            sight: list.map(row.sight, fn(unit_id) { ally(unit_id:) }),
          ),
          picture: dict.from_list(row.picture),
          areas: row.areas,
          now_ms: 1000,
        )
      assert list.map(selection.players, fn(address) { address.unit_id })
        == row.players
        as row.reason
      assert selection.units == []
        as "no creature is selected by a friendly area, and a player is no creature a strike is told to"
    },
  )
  // A phase that starts a child on each ally it selects (a Proxy at the area, the shape of
  // Sentinel's and Affinity's rows) selects the allies in the area's order, from the players
  // the caster has an address for, and answers each at once as a hit: no tell, no roll, no
  // seed byte. A heal row beside it tells the allies that pass its gate and the Proxy hits
  // the rest.
  let beside = dict.from_list(three)
  let proxied_by = fn(areas, sight) {
    let attacker =
      healer(sight: list.map(sight, fn(unit_id) { ally(unit_id:) }))
    let selection =
      strike.select(
        asked: go(primary_target: 7, spell4_id: 58_841),
        attacker:,
        picture: beside,
        areas:,
        now_ms: 1000,
      )
    #(attacker, selection)
  }
  let only_proxy = emission_proxying(heal_too: False, count: 2)
  let #(attacker, selection) = proxied_by(only_proxy, [31, 32, 33])
  assert list.map(selection.players, fn(address) { address.unit_id })
    == [32, 33]
    as "a Proxy at the area and no heal row: the two nearest allies, in the area's order"
  assert selection.acts_on_each_unit && selection.heals == []
    as "the phase starts children and tells no heal"
  assert strike.entropy_needed(selection:) == 0
    as "an ally selected for a Proxy takes no seed byte"
  let #(opened, effects) =
    strike.begin(
      strike: strike.new(),
      selection:,
      attacker:,
      formulas: rating_support.formulas(),
      entropy: <<>>,
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  assert strike_support.players_told(effects:) == []
    && strike_support.creatures_told(effects:) == []
    as "no ally is told anything for the selection"
  let assert [#(_, struck, _)] = strike_support.rounds_closed(effects:)
    as "the round has nothing to wait for and closes at once"
  assert struck
    == [hit_of(unit_id: 32, heals: []), hit_of(unit_id: 33, heals: [])]
    as "each ally is answered as a hit with no heal landed, in the area's order"
  assert opened == strike.new() as "no round stays open"
  let #(_, selection) = proxied_by(only_proxy, [31, 33])
  assert list.map(selection.players, fn(address) { address.unit_id })
    == [33, 31]
    as "the nearest ally has no address in the caster's sight: it is out, and the count goes to the next"
  let #(attacker, selection) =
    proxied_by(emission_proxying(heal_too: True, count: 2), [32, 33])
  let refuses_33 = fn(_, side, _, rolls) {
    case side {
      cast_state.UnitSide(unit_id: 33) -> #(cast_state.GateFails, rolls)
      cast_state.UnitSide(..) | cast_state.CasterSide -> #(
        cast_state.Starts,
        rolls,
      )
    }
  }
  let #(state, effects) =
    strike.begin(
      strike: strike.new(),
      selection:,
      attacker:,
      formulas: rating_support.formulas(),
      entropy: zeros(units: []),
      gate: refuses_33,
      now: at(ms: 1000),
    )
  assert list.map(strike_support.players_told(effects:), fn(told) {
      { told.0 }.unit_id
    })
    == [32]
    as "the heal is told to the ally that passes its gate alone"
  let #(_, effects) =
    strike.player_answered(
      strike: state,
      answer: PlayerAnswered(
        key: strike_tell.Key(
          cast_id: 5,
          occasion: strike_tell.AtGo(phase: 0),
          unit_id: 32,
        ),
        outcome: HealsLanded(heals: [first_heal()]),
      ),
      now: at(ms: 1001),
    )
  let assert [#(_, struck, _)] = strike_support.rounds_closed(effects:)
    as "the ally's answer closes the round"
  assert struck
    == [
      hit_of(unit_id: 32, heals: [first_heal()]),
      hit_of(unit_id: 33, heals: []),
    ]
    as "the ally the heal's gate refused is a hit, for the Proxy, with no heal"
  // A phase whose only row changes the units the area selects (the shape of Energy Auger's
  // row 217926, text 263097 "Allies in the field gain ...") selects the allies the same way
  // and answers each at once as a hit: no tell, no roll, no seed byte; the row names no
  // caster, so the caster is not one of them.
  let #(attacker, selection) =
    proxied_by(emission_changing(count: 2), [31, 32, 33])
  assert list.map(selection.players, fn(address) { address.unit_id })
    == [32, 33]
    as "a change of the area's units and no heal or Proxy: the two nearest allies, in the area's order"
  assert selection.acts_on_each_unit && selection.heals == []
    as "the phase answers its allies and tells no heal"
  assert strike.entropy_needed(selection:) == 0
    as "an ally selected for a change takes no seed byte"
  let #(opened, effects) =
    strike.begin(
      strike: strike.new(),
      selection:,
      attacker:,
      formulas: rating_support.formulas(),
      entropy: <<>>,
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  assert strike_support.players_told(effects:) == []
    && strike_support.creatures_told(effects:) == []
    as "no ally is told anything for the selection"
  let assert [#(_, struck, _)] = strike_support.rounds_closed(effects:)
    as "the round has nothing to wait for and closes at once"
  assert struck
    == [hit_of(unit_id: 32, heals: []), hit_of(unit_id: 33, heals: [])]
    as "each ally is answered as a hit with no heal landed, in the area's order"
  assert opened == strike.new() as "no round stays open"
  let around = fn(areas, sight, picture) {
    strike.select(
      asked: go(primary_target: 7, spell4_id: 58_841),
      attacker: healer(sight: list.map(sight, fn(unit_id) { ally(unit_id:) })),
      picture: dict.from_list(picture),
      areas:,
      now_ms: 1000,
    )
    |> fn(selection) {
      list.map(selection.players, fn(address) { address.unit_id })
    }
  }
  let crowd = [
    #(7, player_at(x: 0.0, z: -2.0)),
    #(
      20,
      strike_support.creature_at(
        x: 0.0,
        z: -5.0,
        alive: True,
        attackable: Attackable(exile: True, dominion: True),
      ),
    ),
    #(32, player_at(x: 0.0, z: -4.0)),
    #(33, player_at(x: 0.0, z: -3.0)),
    #(34, player_at(x: 0.0, z: -6.0)),
  ]
  assert around(emission_changing(count: 4), [7, 32, 34], crowd) == [32, 34]
    as "the caster, a creature and an ally with no address in the caster's sight (33) inside the cone are not selected"
  // A phase whose only row is a Proc the area's units hold (the shape of Healing Salve's row
  // 86457, text 315682 "yourself and N allies") selects the allies as the changes above do: it
  // names no caster, so the caster is not one of them, and a creature or an ally the caster has
  // no address for is not.
  assert around(emission_procing(count: 4), [7, 32, 34], crowd) == [32, 34]
    as "a Proc held by the area's units: the caster, a creature and an ally with no address in sight are not selected"
  let #(attacker, selection) =
    proxied_by(emission_procing(count: 2), [31, 32, 33])
  assert list.map(selection.players, fn(address) { address.unit_id })
    == [32, 33]
    as "a Proc held by the area's units and no heal or Proxy: the two nearest allies, in the area's order"
  assert selection.acts_on_each_unit && selection.heals == []
    as "the phase answers its allies and tells no heal"
  assert strike.entropy_needed(selection:) == 0
    as "an ally selected for a Proc takes no seed byte"
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection:,
      attacker:,
      formulas: rating_support.formulas(),
      entropy: <<>>,
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  assert strike_support.players_told(effects:) == []
    as "no ally is told a strike for a Proc: it is held by the cast's change"
  let assert [#(_, struck, _)] = strike_support.rounds_closed(effects:)
    as "the round has nothing to wait for and closes at once"
  assert struck
    == [hit_of(unit_id: 32, heals: []), hit_of(unit_id: 33, heals: [])]
    as "each ally is answered as a hit with no heal landed, in the area's order"
  let assert Ok(emission) = dict.get(emission_changing(count: 2), 58_841)
    as "Emission is in the areas"
  let party_only =
    dict.insert(
      emission_changing(count: 2),
      58_841,
      spell_area.SpellArea(
        ..emission,
        spell: spell_plan.Spell(
          ..emission.spell,
          targeting: target_mechanic.Targeting(
            ..emission.spell.targeting,
            valid_targets: 16,
          ),
        ),
      ),
    )
  assert around(party_only, [31, 32, 33], three) == []
    as "valid targets 16 take the caster's party only (Defense Grid's 54475), and no player has a group, so no ally is selected"
  let kick =
    strike.select(
      asked: go(primary_target: 7, spell4_id: 58_591),
      attacker: healer(sight: [ally(unit_id: 32)]),
      picture: dict.from_list([
        #(32, player_at(x: 0.0, z: -4.0)),
        #(
          20,
          strike_support.creature_at(
            x: 0.0,
            z: -5.0,
            alive: True,
            attackable: Attackable(exile: True, dominion: True),
          ),
        ),
      ]),
      areas: spell_tables.fixture_areas(),
      now_ms: 1000,
    )
  assert kick.players == []
    as "Kick's area is a foe's: it selects creatures only, never the player in its cone"
  assert list.map(kick.units, fn(aimed) { aimed.unit_id }) == [20]
    as "the control: the same picture gives Kick's area the creature 20, so the case above is a friendly area's choice"
}

type CasterRow {
  CasterRow(
    reason: String,
    areas: spell_area.Areas,
    caster_missing: Int,
    picture: List(#(Int, shown.Shown)),
    selected: List(Int),
  )
}

/// A heal row aimed at the area alone (targetFlags 4) does not name the caster, so the
/// caster is one of the candidates of the area, at distance 0 from its centre and with no
/// shape test (the server's choice; the text 195454 of Triage reads "yourself or an
/// ally based on who has the lowest health", and Spell4 27972 "ST smart heal"), ranked by the
/// health it misses from the vitals it holds, as an ally is. A row that names the caster
/// (targetFlags 5 and 7, as Crisis Wave's) heals it by its flag, and a row aimed at the primary
/// target and the area (flags 6) reaches it as the primary target of a spell on itself, so in
/// both the area finds the others only. The caster stands at the centre of Emission's cone,
/// which its 1.2 m hit radius reaches from 1 m ahead, so only the row whose area starts 5 m
/// out (Spell4AoeTargetConstraints 662 edited to minRange 5) puts it outside the hit shape,
/// as it does the ally 2 m ahead. A caster at full health among allies at full health is taken
/// first (distance 0, the first guess marked in `area`).
pub fn a_heal_row_aimed_at_the_area_alone_takes_the_caster_as_a_candidate_by_its_missing_health_and_a_row_that_names_the_caster_does_not_test() -> Nil {
  use <- owned_test.run(60_000)
  let full = fn(x, z) { hurt_at(x:, z:, missing: 0) }
  list.each(
    [
      CasterRow(
        "the caster misses the most, count 1: it is selected and no ally is",
        emission_by_health_at_the_area_alone(count: 1),
        4000,
        [#(32, hurt_at(x: 0.0, z: -4.0, missing: 800))],
        [7],
      ),
      CasterRow(
        "an ally misses more than the caster, count 1: the ally is selected, not the caster",
        emission_by_health_at_the_area_alone(count: 1),
        200,
        [#(32, hurt_at(x: 0.0, z: -4.0, missing: 900))],
        [32],
      ),
      CasterRow(
        "equal missing health, count 1: the caster first, at distance 0",
        emission_by_health_at_the_area_alone(count: 1),
        500,
        [#(32, hurt_at(x: 0.0, z: -4.0, missing: 500))],
        [7],
      ),
      CasterRow(
        "count 2: the caster and the ally missing the most, in the order of their missing health",
        emission_by_health_at_the_area_alone(count: 2),
        500,
        [
          #(32, hurt_at(x: 0.0, z: -4.0, missing: 100)),
          #(33, hurt_at(x: 0.0, z: -7.0, missing: 800)),
        ],
        [33, 7],
      ),
      CasterRow(
        "count 2: an ally behind the caster, outside the cone, is not selected whatever it misses, and the caster standing outside the cone still is",
        emission_by_health_at_the_area_alone(count: 2),
        20,
        [
          #(32, hurt_at(x: 0.0, z: -4.0, missing: 10)),
          #(35, hurt_at(x: 0.0, z: 6.0, missing: 4999)),
        ],
        [7, 32],
      ),
      CasterRow(
        "an area that starts 5 m out leaves the caster, at its centre, outside the hit shape, and the ally 2 m ahead: the caster is still a candidate, the ally in range is selected, and the ally 2 m ahead is not whatever it misses",
        emission_by_health(flags: 4, count: 2, min_range: 5.0),
        4000,
        [
          #(32, hurt_at(x: 0.0, z: -2.0, missing: 4999)),
          #(33, hurt_at(x: 0.0, z: -7.0, missing: 800)),
        ],
        [7, 33],
      ),
      CasterRow(
        "a row aimed at the primary target and the area (targetFlags 6), the caster missing the most, count 1: the area finds the ally, never the caster, which the go reaches as the primary target of a spell on itself",
        emission_by_health(flags: 6, count: 1, min_range: 0.0),
        4000,
        [#(32, hurt_at(x: 0.0, z: -4.0, missing: 800))],
        [32],
      ),
      CasterRow(
        "the caster and every ally at full health, count 1: the caster, at distance 0 (a guess: the client names no order)",
        emission_by_health_at_the_area_alone(count: 1),
        0,
        [#(32, full(0.0, -4.0)), #(33, full(0.0, -7.0))],
        [7],
      ),
      CasterRow(
        "a row that names the caster (Emission's heal row, targetFlags 5), the caster missing the most, count 2: the two allies missing the most, never the caster",
        emission_areas(order: area.MissingMostHealth, count: 2),
        4000,
        [
          #(32, hurt_at(x: 0.0, z: -4.0, missing: 100)),
          #(33, hurt_at(x: 0.0, z: -7.0, missing: 800)),
          #(34, hurt_at(x: 0.0, z: -9.0, missing: 300)),
        ],
        [33, 34],
      ),
    ],
    fn(row) {
      let ids = list.map(row.picture, fn(entry) { entry.0 })
      let attacker =
        healer(sight: list.map(ids, fn(unit_id) { ally(unit_id:) }))
      let selection =
        strike.select(
          asked: go(primary_target: 7, spell4_id: 58_841),
          attacker: strike.Attacker(
            ..attacker,
            vitals: damage.Vitals(
              health: player_state_support.full_health - row.caster_missing,
              max_health: player_state_support.full_health,
              shield: 0,
              max_shield: 0,
            ),
          ),
          picture: dict.from_list(row.picture),
          areas: row.areas,
          now_ms: 1000,
        )
      assert selection.area == row.selected as row.reason
      assert list.map(selection.players, fn(address) { address.unit_id })
        == row.selected
        as row.reason
      assert selection.heals != []
        as "the phase's heal rows are told whenever the area selected a player"
    },
  )
}

/// What `strike.select` of the spell selects for a cast on `primary_target`, by a caster at the
/// origin missing `caster_missing` health, with every unit of the picture in its sight.
fn selected_around(
  areas areas: spell_area.Areas,
  spell4_id spell4_id: Int,
  primary_target primary_target: Int,
  caster_missing caster_missing: Int,
  picture picture: List(#(Int, shown.Shown)),
) -> Selection {
  let ids = list.map(picture, fn(entry) { entry.0 })
  let attacker = healer(sight: list.map(ids, fn(unit_id) { ally(unit_id:) }))
  strike.select(
    asked: go(primary_target:, spell4_id:),
    attacker: strike.Attacker(
      ..attacker,
      vitals: damage.Vitals(
        health: player_state_support.full_health - caster_missing,
        max_health: player_state_support.full_health,
        shield: 0,
        max_shield: 0,
      ),
    ),
    picture: dict.from_list(picture),
    areas:,
    now_ms: 1000,
  )
}

type AllyCentreRow {
  AllyCentreRow(
    reason: String,
    caster_missing: Int,
    picture: List(#(Int, shown.Shown)),
    selected: List(Int),
  )
}

/// A child cast on an ally centres its area on that ally, where the picture puts it
/// (`shown.strike_centre_of`), so the caster, which stands at distance 0 only in an area
/// centred on itself, is one candidate of the area like any ally: the area's own shape tests it
/// from where it stands. Warden's child 36660 (Spell4Effects 76991, a heal of targetFlags 4 at
/// the area 766: order 5, 5 targets, a circle of 12 m, TelegraphDamage 1244 on the cast's
/// target; text 246578: "nearby allies" of "the most injured ally") is cast on the ally 31
/// by its parent's Proxy. Emission's rows stand in for the two cases Warden's do not hold: its
/// area placed on the target as Warden's is (its hit made a circle of 15 m with no offset, which
/// the load builds), with the caster 8 m from the ally inside it,
/// a heal of flags 4 selects the caster and one of flags 5, which names it, never does; and its
/// area on the caster, as the fixture's is, stays centred on the caster whoever the child is
/// cast on, so the caster is found at distance 0 beside the allies of the caster's own cone.
pub fn a_child_cast_on_an_ally_selects_its_area_around_that_ally_and_the_caster_is_a_candidate_only_inside_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let warden_child = 36_660
  let areas = spell_area.areas(tables: client_tables.shared())
  let assert Ok(warden) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(warden_child))
    as "Warden's child is in the areas, since Warden is planned"
  let assert Some(row) = warden.row as "Warden's child has an area row"
  assert row
    == area.Row(
      min_range: 0.0,
      max_range: 12.0,
      degrees: row.degrees,
      target_count: 5,
      order: area.MissingMostHealth,
    )
    as "Spell4AoeTargetConstraints 766 takes 5 units of 12 m, by missing health"
  list.each(
    [
      AllyCentreRow(
        "the allies within 12 m of the ally, by missing health, the ally itself among them; the ally 9 m past the edge is not",
        0,
        [
          #(31, hurt_at(x: 30.0, z: 0.0, missing: 100)),
          #(32, hurt_at(x: 30.0, z: 8.0, missing: 500)),
          #(33, hurt_at(x: 30.0, z: -5.0, missing: 900)),
          #(34, hurt_at(x: 30.0, z: 11.0, missing: 300)),
          #(35, hurt_at(x: 30.0, z: 21.0, missing: 4999)),
        ],
        [33, 32, 34, 31],
      ),
      AllyCentreRow(
        "an ally 10 m from the caster and 20 m from the ally is not selected, whatever it misses",
        0,
        [
          #(31, hurt_at(x: 30.0, z: 0.0, missing: 100)),
          #(35, hurt_at(x: 10.0, z: 0.0, missing: 4000)),
        ],
        [31],
      ),
      AllyCentreRow(
        "the caster 8 m from the ally and missing the most is selected, first",
        4000,
        [#(31, hurt_at(x: 8.0, z: 0.0, missing: 100))],
        [7, 31],
      ),
      AllyCentreRow(
        "the caster 20 m from the ally and missing the most is not selected: it stands at distance 0 only in an area centred on itself",
        4000,
        [#(31, hurt_at(x: 20.0, z: 0.0, missing: 100))],
        [31],
      ),
    ],
    fn(row) {
      let selection =
        selected_around(
          areas:,
          spell4_id: warden_child,
          primary_target: 31,
          caster_missing: row.caster_missing,
          picture: row.picture,
        )
      assert selection.area == row.selected as row.reason
      assert list.map(selection.players, fn(address) { address.unit_id })
        == row.selected
        as row.reason
    },
  )
  // Barrier's child 41369 (Spell4Effects 92788, a change of the allies of its area, beside the
  // Proxy 92796 that starts a child on each) selects its area 429 (360 degrees, 3 targets, by
  // missing health) around the ally 31 the parent's area found, from the units inside its hit
  // circle of 8 m (TelegraphDamage 11329, param00 8.0), whether or not they stand inside the
  // parent's 180 degrees: the ally 32, 7 m from the ally 31 and 4 m behind the caster, is
  // selected, and the ally 33, 11 m from it, is not. Each ally selected is answered at once.
  let barrier_picture = [
    #(31, hurt_at(x: 0.0, z: -3.0, missing: 100)),
    #(32, hurt_at(x: 0.0, z: 4.0, missing: 500)),
    #(33, hurt_at(x: 0.0, z: 8.0, missing: 900)),
  ]
  let barrier =
    selected_around(
      areas:,
      spell4_id: 41_369,
      primary_target: 31,
      caster_missing: 0,
      picture: barrier_picture,
    )
  assert barrier.area == [32, 31]
    as "the ally 32, 7 m from the ally the child is cast on, is selected, and the ally 33, 11 m from it, is not"
  assert list.map(barrier.players, fn(address) { address.unit_id }) == [32, 31]
    as "each ally selected is a player the go answers, once"
  let #(_, effects) =
    strike.begin(
      strike: strike.new(),
      selection: barrier,
      attacker: healer(
        sight: list.map([31, 32, 33], fn(id) { ally(unit_id: id) }),
      ),
      formulas: rating_support.formulas(),
      entropy: <<>>,
      gate: strike_support.passes_all(),
      now: at(ms: 1000),
    )
  let assert [#(_, struck, _)] = strike_support.rounds_closed(effects:)
    as "the round closes at once"
  assert struck
    == [hit_of(unit_id: 32, heals: []), hit_of(unit_id: 31, heals: [])]
    as "each ally selected is answered as a hit, once, in the area's order"
  // The caster is 8 m ahead of the ally 31 (ahead is toward -z), inside Emission's circle of
  // 15 m around it, and the ally 33 is 6 m ahead of it.
  let near_caster = [
    #(31, hurt_at(x: 0.0, z: 8.0, missing: 100)),
    #(33, hurt_at(x: 0.0, z: 2.0, missing: 300)),
  ]
  assert selected_around(
      areas: emission_by_health_on_its_target(
        flags: 4,
        count: 5,
        min_range: 0.0,
      ),
      spell4_id: 58_841,
      primary_target: 31,
      caster_missing: 4000,
      picture: near_caster,
    ).area
    == [7, 33, 31]
    as "the control: a heal aimed at the area alone takes the caster inside the cone around the ally, with the ally and the one 6 m on"
  assert selected_around(
      areas: emission_by_health_on_its_target(
        flags: 5,
        count: 5,
        min_range: 0.0,
      ),
      spell4_id: 58_841,
      primary_target: 31,
      caster_missing: 4000,
      picture: near_caster,
    ).area
    == [33, 31]
    as "a heal that names the caster (flags 5) never takes it as a candidate of the area"
  assert selected_around(
      areas: emission_by_health(flags: 4, count: 5, min_range: 0.0),
      spell4_id: 58_841,
      primary_target: 31,
      caster_missing: 4000,
      picture: [
        #(31, hurt_at(x: 0.0, z: 40.0, missing: 100)),
        #(33, hurt_at(x: 0.0, z: -6.0, missing: 300)),
      ],
    ).area
    == [7, 33]
    as "an area placed on the caster is centred on it, whoever the child is cast on: the caster at distance 0 and the ally in its cone, the ally 40 m off out of it"
}

/// Affinity's Spell4 39063 (Spell4Effects 207513, a Proxy at the area that starts the child
/// 79079 on each unit the area strikes, 250 ms after the go) is beneficial and holds no foe row,
/// so its area finds allies (Closest, 1 target, a beam 3.5 m wide and 34 m long, TelegraphDamage
/// 7664): the ally inside it is
/// selected, to start the child on, and a foe creature inside it is not struck, where a spell
/// that hits foes starts it on each one. The control is the same area read as a foe's.
pub fn a_friendly_areas_proxy_at_the_area_selects_the_allies_and_no_foe_creature_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let affinity = 39_063
  let areas = spell_area.areas(tables: client_tables.shared())
  let assert Ok(friendly) =
    spell_area.of_spell(areas:, spell4_id: Spell4Id(affinity))
    as "Affinity is in the areas"
  assert friendly.finds_allies as "Affinity's area finds allies"
  let assert Ok(phase) =
    spell_area.phase(spell: friendly, phase: 0, spent: None)
    as "Affinity has a first phase"
  assert phase.selects_area
    as "the Proxy that starts its child on each struck unit makes the phase select the area"
  let selected_by = fn(area) {
    strike.select(
      asked: go(primary_target: 7, spell4_id: affinity),
      attacker: healer(sight: [ally(unit_id: 31)]),
      picture: dict.from_list([
        #(
          20,
          strike_support.creature_at(
            x: 0.0,
            z: -10.0,
            alive: True,
            attackable: Attackable(exile: True, dominion: True),
          ),
        ),
        #(31, player_at(x: 0.0, z: -12.0)),
      ]),
      areas: dict.from_list([#(affinity, area)]),
      now_ms: 1000,
    )
  }
  let selection = selected_by(friendly)
  assert list.map(selection.players, fn(address) { address.unit_id }) == [31]
    as "the ally 12 m ahead is selected, to start the child on"
  assert selection.units == []
    as "a foe creature 10 m away is not struck by a friendly area, so no child starts on it"
  let as_foes =
    selected_by(spell_area.SpellArea(..friendly, finds_allies: False))
  assert list.map(as_foes.units, fn(aimed) { aimed.unit_id }) == [20]
    as "the control: read as a foe's area it strikes the creature 20, so the case above is the friendly area's choice"
  assert as_foes.players == [] as "and it selects no player"
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
    acts_on_each_unit: False,
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
  list.map(
    strike_support.only(effects:, kinds: [
      strike_support.CreatureTold,
      strike_support.PlayerTold,
      strike_support.TimerStarted,
    ]),
    fn(effect) {
      case effect {
        strike.TellStrike(unit_id:, ..) -> ToldCreature(unit_id:)
        strike.TellPlayerStrike(address:, strike:) ->
          ToldPlayer(address:, strike:)
        strike.StartTimer(after_ms:, ..) -> Started(after_ms:)
        _ -> panic as "only the tells and the started timers were kept"
      }
    },
  )
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
  // A heal row aimed at the caster and the area, whose area found the allies 11 and 12
  // (Emission's row 141384 is of this aim), is told to each ally in selection order, after
  // the creatures' strikes, and each ally's place is its own: the round stays open until
  // both have answered. An ally whose gate fails has no tell and no place.
  let area_row =
    spell_area.InstantHeal(..health_row, aim: spell_plan.AimsAtCasterAndArea)
  let allies = fn(unit_ids: List(Int)) {
    Selection(
      ..selection_of(units: [10], heals: [area_row]),
      players: list.map(unit_ids, fn(unit_id) { ally(unit_id:) }),
      area: [10, ..unit_ids],
    )
  }
  let heal_strike_on = fn(unit_id) {
    strike_support.heal_strike(
      from: ConnectionId(2),
      stay: map_support.stay(count: 1),
      cast_id: 5,
      unit_id:,
      outgoing: 1.25,
      heals: [#(effect_kind.Health, 121)],
    )
  }
  let refuses_unit_12 = fn(_, side, _, rolls) {
    case side {
      cast_state.UnitSide(unit_id: 12) -> #(cast_state.GateFails, rolls)
      cast_state.UnitSide(..) | cast_state.CasterSide -> #(
        cast_state.Starts,
        rolls,
      )
    }
  }
  let #(state, effects) =
    begun(state: strike.new(), selection: allies([11, 12]))
  assert told(effects:)
    == [
      ToldCreature(unit_id: 10),
      ToldPlayer(address: ally(unit_id: 11), strike: heal_strike_on(11)),
      ToldPlayer(address: ally(unit_id: 12), strike: heal_strike_on(12)),
      Started(after_ms: 1000),
    ]
    as "two allies the area found: one strike each, in selection order, after the creature's"
  let answer = fn(state, unit_id) {
    strike.player_answered(
      strike: state,
      answer: PlayerAnswered(
        key: strike_tell.Key(
          cast_id: 5,
          occasion: strike_tell.AtGo(phase: 0),
          unit_id:,
        ),
        outcome: HealsLanded([first_heal()]),
      ),
      now: at(ms: 1100),
    )
  }
  let #(state, _) =
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
      now: at(ms: 1050),
    )
  let #(state, after_first) = answer(state, 11)
  assert after_first == []
    as "the round waits for the second ally: it holds a place of its own"
  let #(_, after_second) = answer(state, 12)
  assert after_second
    == closed_with(struck: [
      creature_hit(),
      hit_of(unit_id: 11, heals: [first_heal()]),
      hit_of(unit_id: 12, heals: [first_heal()]),
    ])
    as "the go lists the creature, then each ally in selection order"
  let #(state, effects) =
    strike.begin(
      strike: strike.new(),
      selection: allies([11, 12]),
      attacker: healer(sight: [ally(unit_id: 11), ally(unit_id: 12)]),
      formulas: rating_support.formulas(),
      entropy: zeros(units: [10]),
      gate: refuses_unit_12,
      now: at(ms: 1000),
    )
  assert told(effects:)
    == [
      ToldCreature(unit_id: 10),
      ToldPlayer(address: ally(unit_id: 11), strike: heal_strike_on(11)),
      Started(after_ms: 1000),
    ]
    as "the ally whose gate fails is told nothing"
  let #(state, _) =
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
      now: at(ms: 1050),
    )
  let #(_, closed) = answer(state, 11)
  assert closed
    == closed_with(struck: [
      creature_hit(),
      hit_of(unit_id: 11, heals: [first_heal()]),
    ])
    as "the round closes at the one ally's answer: the refused ally has no place to wait for"
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
  /// A creature's answer that its strike landed, under a key that names the unit `unit_id`.
  CreatureLands(unit_id: Int, at_ms: Int)
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
  hit_of(unit_id: 9, heals:)
}

/// The player `unit_id`'s place in the go's list, as it is struck.
fn hit_of(
  unit_id unit_id: Int,
  heals heals: List(strike_tell.HealLanded),
) -> cast_state.Struck {
  cast_state.Hit(
    unit_id:,
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
    unit: cast_state.HitCreature(life: 3),
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
        CreatureLands(unit_id:, at_ms:) ->
          strike.answered(
            strike: state,
            answer: strike_tell.Answered(
              key: strike_tell.Key(
                cast_id: 5,
                occasion: strike_tell.AtGo(phase: 0),
                unit_id:,
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
        "the heals landed close the round: the timer is cancelled and the go lists the player with the heals it applied",
        [],
        [says(outcome: HealsLanded([first_heal(), second_heal()]), at_ms: 1100)],
        [
          closed_with(struck: [player_hit(heals: [first_heal(), second_heal()])]),
        ],
      ),
      AnswerRow(
        "a dead player leaves its place: the go is still written and names no one",
        [],
        [says(outcome: PlayerDead, at_ms: 1100)],
        [closed_with(struck: [])],
      ),
      AnswerRow(
        "the player answers before the creature: the round waits for the creature, then lists the creature first, in selection order",
        [10],
        [
          says(outcome: HealsLanded([first_heal()]), at_ms: 1100),
          CreatureLands(unit_id: 10, at_ms: 1200),
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
          says(outcome: HealsLanded([first_heal()]), at_ms: 1100),
          says(outcome: HealsLanded([second_heal()]), at_ms: 1150),
          CreatureLands(unit_id: 10, at_ms: 1200),
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
          CreatureLands(unit_id: 10, at_ms: 1200),
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
        "a creature's answer under the player's unit finds no place that waits for a creature: it is dropped, and the timer leaves the player out",
        [],
        [
          CreatureLands(unit_id: 9, at_ms: 1100),
          TimerProcessed(at_ms: 2000),
        ],
        [
          [],
          [
            strike.Went(
              asked: go(primary_target: 9, spell4_id: mind_over_body),
              struck: [],
              gates_passed: dict.new(),
            ),
          ],
        ],
      ),
      AnswerRow(
        "an answer processed at 2500, after the deadline of 2000 but before the timer is processed, is taken and listed: the round closes by processing its timer, not by the clock",
        [],
        [says(outcome: HealsLanded([first_heal()]), at_ms: 2500)],
        [closed_with(struck: [player_hit(heals: [first_heal()])])],
      ),
      AnswerRow(
        "an answer processed after the timer closed the round is dropped and the go lists no player",
        [],
        [
          TimerProcessed(at_ms: 2000),
          says(outcome: HealsLanded([first_heal()]), at_ms: 2100),
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

// ---- a tick of a periodic heal on a player ----

/// Bolster's heal row (Spell4Effects 80077: type 10, targetFlags 2, tickTime 1000,
/// parameters 13 x 0.1977 and 10 x 10.54, `table_rows -- Spell4Effects 80077`) as the
/// tick of cast 5's first go asks for it, `tick` being the tick, for the unit 9.
fn heal_tick_asked(
  effect_id effect_id: Int,
  tick tick: Int,
  unit_id unit_id: Int,
) -> cast_state.TickAsked {
  cast_state.TickAsked(
    cast_id: 5,
    spell4_id: Spell4Id(32_821),
    effect_id: Spell4EffectsId(effect_id),
    unit_id:,
    life: 0,
    go: 1,
    tick:,
    what: cast_state.TellHeal(
      vital: effect_kind.Health,
      formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
        damage.Parameter(kind: 13, value: 0.1977),
        damage.Parameter(kind: 10, value: 10.54),
        damage.Parameter(kind: 0, value: 0.0),
        damage.Parameter(kind: 0, value: 0.0),
      ]),
      passed_in: None,
    ),
  )
}

/// A tick of the heal begun at `now_ms` for this caster, with no seed bytes: a heal tick
/// draws none.
fn heal_tick_begun(
  state state: strike.State,
  asked asked: cast_state.TickAsked,
  attacker attacker: Attacker,
  now_ms now_ms: Int,
) -> #(strike.State, List(Effect)) {
  strike.begin_tick(
    strike: state,
    asked:,
    attacker:,
    formulas: rating_support.formulas(),
    entropy: <<>>,
    now: at(ms: now_ms),
  )
}

/// The strike the caster's connection 2 in its first stay tells the player 9 for tick
/// `tick` of the row `effect_id`, in cast 5's first go, with this outgoing multiplier and
/// this amount.
fn tick_strike_of(
  effect_id effect_id: Int,
  tick tick: Int,
  outgoing outgoing: Float,
  amount amount: Int,
) -> strike_tell.PlayerStrike {
  strike_tell.PlayerStrike(
    key: strike_tell.Key(
      cast_id: 5,
      occasion: strike_tell.AtTick(
        effect_id: Spell4EffectsId(effect_id),
        go: 1,
        tick:,
      ),
      unit_id: 9,
    ),
    from: ConnectionId(2),
    stay: map_support.stay(count: 1),
    outgoing:,
    heals: [
      strike_tell.HealTell(
        effect_id: Spell4EffectsId(effect_id),
        vital: effect_kind.Health,
        amount:,
      ),
    ],
  )
}

pub fn a_heal_tick_on_a_player_in_sight_tells_its_connection_the_row_with_the_amount_of_that_tick_test() -> Nil {
  use <- owned_test.run(60_000)
  // Bolster's row at level 5: round(0.1977 x 100) + 10.54 x 5 = 20 + 52.7 = 72.7, which is
  // 73 (the stat part is rounded alone, `0x140565600`; Support Power is a quarter of the
  // 400 Support Rating); at 800 Support Rating the power is 200: 40 + 52.7 = 92.7, which is 93.
  let tick_one = heal_tick_asked(effect_id: 80_077, tick: 1, unit_id: 9)
  let tick_two = heal_tick_asked(effect_id: 80_077, tick: 2, unit_id: 9)
  let second_row = heal_tick_asked(effect_id: 80_078, tick: 1, unit_id: 9)
  let sees = [ally(unit_id: 9)]
  // Each row is the tells of its begun ticks, in order, and the timers its steps start.
  list.each(
    [
      #(
        "one tick: one tell of the row 80077 for its go and tick, the caster's stay and outgoing 1.25 and the amount 73, a 1000 ms timer, and no strike of a creature",
        healer(sight: sees),
        [tick_one],
        [
          ToldPlayer(
            address: ally(unit_id: 9),
            strike: tick_strike_of(
              effect_id: 80_077,
              tick: 1,
              outgoing: 1.25,
              amount: 73,
            ),
          ),
          Started(after_ms: 1000),
        ],
      ),
      #(
        "the caster's Support Rating is 800 at the tick: the tell carries 93, the amount of that tick and not of the go",
        healer_with(sight: sees, support_rating: 800.0, outgoing: 1.25),
        [tick_one],
        [
          ToldPlayer(
            address: ally(unit_id: 9),
            strike: tick_strike_of(
              effect_id: 80_077,
              tick: 1,
              outgoing: 1.25,
              amount: 93,
            ),
          ),
          Started(after_ms: 1000),
        ],
      ),
      #(
        "the caster's outgoing multiplier is 1.5 at the tick: the tell carries 1.5",
        healer_with(sight: sees, support_rating: 400.0, outgoing: 1.5),
        [tick_one],
        [
          ToldPlayer(
            address: ally(unit_id: 9),
            strike: tick_strike_of(
              effect_id: 80_077,
              tick: 1,
              outgoing: 1.5,
              amount: 73,
            ),
          ),
          Started(after_ms: 1000),
        ],
      ),
      #(
        "two rows due together are two tells, each keyed by its own row, and the timer is started once",
        healer(sight: sees),
        [tick_one, second_row],
        [
          ToldPlayer(
            address: ally(unit_id: 9),
            strike: tick_strike_of(
              effect_id: 80_077,
              tick: 1,
              outgoing: 1.25,
              amount: 73,
            ),
          ),
          Started(after_ms: 1000),
          ToldPlayer(
            address: ally(unit_id: 9),
            strike: tick_strike_of(
              effect_id: 80_078,
              tick: 1,
              outgoing: 1.25,
              amount: 73,
            ),
          ),
        ],
      ),
      #(
        "the second tick of the schedule is its own tell, keyed by its tick",
        healer(sight: sees),
        [tick_two],
        [
          ToldPlayer(
            address: ally(unit_id: 9),
            strike: tick_strike_of(
              effect_id: 80_077,
              tick: 2,
              outgoing: 1.25,
              amount: 73,
            ),
          ),
          Started(after_ms: 1000),
        ],
      ),
    ],
    fn(row) {
      let #(reason, attacker, asks, expected) = row
      let #(_, effects) =
        list.fold(asks, #(strike.new(), []), fn(so_far, asked) {
          let #(state, effects) = so_far
          let #(state, more) =
            heal_tick_begun(state:, asked:, attacker:, now_ms: 2000)
          #(state, list.append(effects, more))
        })
      assert told(effects:) == expected as reason
    },
  )
  assert strike.tick_entropy_needed(asked: tick_one) == 0
    as "a heal tick draws no seed bytes: it rolls nothing"
}

/// The first heal tick begun for the player 9 in sight, with its round open at 2000 ms.
fn heal_tick_open(
  sight sight: List(PlayerAddress),
) -> #(strike.State, List(Effect)) {
  heal_tick_begun(
    state: strike.new(),
    asked: heal_tick_asked(effect_id: 80_077, tick: 1, unit_id: 9),
    attacker: healer(sight:),
    now_ms: 2000,
  )
}

fn applied_heal() -> strike_tell.HealLanded {
  HealLanded(
    effect_id: Spell4EffectsId(80_077),
    vital: effect_kind.Health,
    split: Split(amount: 73, shield: 0, health: 60, overheal: 13),
  )
}

/// The tick answer of the player 9 for tick 1 of the row 80077 in the first go.
fn tick_answer(outcome outcome: PlayerOutcome) -> PlayerAnswered {
  PlayerAnswered(
    key: strike_tell.Key(
      cast_id: 5,
      occasion: strike_tell.AtTick(
        effect_id: Spell4EffectsId(80_077),
        go: 1,
        tick: 1,
      ),
      unit_id: 9,
    ),
    outcome:,
  )
}

pub fn a_players_answer_to_a_heal_tick_closes_the_tick_round_and_a_player_gone_dead_or_silent_leaves_it_empty_test() -> Nil {
  use <- owned_test.run(60_000)
  let asked = heal_tick_asked(effect_id: 80_077, tick: 1, unit_id: 9)
  let healed =
    Some(
      cast_state.Hit(
        unit_id: 9,
        unit: cast_state.HitOtherPlayer(heals: [applied_heal()]),
        descriptions: [],
        controls: [],
        armor_removed: 0,
        ticking: [],
      ),
    )
  let #(state, begun) = heal_tick_open(sight: [ally(unit_id: 9)])
  assert told(effects: begun)
    == [
      ToldPlayer(
        address: ally(unit_id: 9),
        strike: tick_strike_of(
          effect_id: 80_077,
          tick: 1,
          outgoing: 1.25,
          amount: 73,
        ),
      ),
      Started(after_ms: 1000),
    ]
    as "the tick's round waits for the ally with one 1000 ms deadline"
  let #(_, answered) =
    strike.player_answered(
      strike: state,
      answer: tick_answer(outcome: HealsLanded([applied_heal()])),
      now: at(ms: 2100),
    )
  assert answered
    == [
      strike.CancelTimer(timer: strike.strike_timer),
      strike.Ticked(asked:, struck: healed),
    ]
    as "the ally's HealsLanded fills the place and closes the round with the ally's hit and the heals it applied"
  let #(_, dead) =
    strike.player_answered(
      strike: state,
      answer: tick_answer(outcome: PlayerDead),
      now: at(ms: 2100),
    )
  assert strike_support.ticks_closed(effects: dead) == [#(asked, None)]
    as "a dead ally leaves the round empty"
  let #(_, silent) = strike.timer_fired(strike: state, now: at(ms: 3000))
  assert strike_support.ticks_closed(effects: silent) == [#(asked, None)]
    as "no answer by the 1 s deadline leaves the round empty"
  let #(_, late) =
    strike.player_answered(
      strike: state,
      answer: tick_answer(outcome: HealsLanded([applied_heal()])),
      now: at(ms: 3500),
    )
  assert strike_support.ticks_closed(effects: late) == [#(asked, healed)]
    as "an answer taken before the timer is processed is listed, whatever the clock says"
  let #(closed, _) = strike.timer_fired(strike: state, now: at(ms: 3000))
  let #(_, after) =
    strike.player_answered(
      strike: closed,
      answer: tick_answer(outcome: HealsLanded([applied_heal()])),
      now: at(ms: 3100),
    )
  assert after == [] as "an answer after the round closed is dropped"
  let #(_, gone) = heal_tick_open(sight: [])
  assert told(effects: gone) == []
    as "an ally no longer in the caster's picture at the tick is told nothing and no timer is started"
  assert strike_support.ticks_closed(effects: gone) == [#(asked, None)]
    as "and its round closes at once with nobody"
  assert list.map(strike_support.lines_logged(effects: gone), fn(line) {
      line.0
    })
    == [step.LogDebug]
    as "with one debug line"
}
