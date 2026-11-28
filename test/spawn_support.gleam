//// Spawns for a test to stand a creature at, in World 3460, Warfare Woods, and
//// the `WorldSpawns` a world's term holds them in. The values are the client's
//// for Creature2 73464, the Virtual Battle Beast (the creature trace of the
//// combat core: level 1, faction 1441, display 26565, Base Health 52.6205
//// truncated to 52), so a test of the rule reads what the real spawn would carry
//// without the client's tables.

import character_tables
import class_resource_support
import database_support
import genesis_prime/content/class_resource as content_class_resource
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/objective_set
import genesis_prime/content/projector_landing as content_projector_landing
import genesis_prime/content/server_proxy as content_server_proxy
import genesis_prime/content/spawn as content_spawn
import genesis_prime/content/terrain as content_terrain
import genesis_prime/content/tutorial_quest as content_tutorial_quest
import genesis_prime/content/vendor as content_vendor
import genesis_prime/content/zone_welcome as content_zone_welcome
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/vendor
import genesis_prime/shared/area
import genesis_prime/shared/creature_combat.{
  type Attack, Attack, Attackable, Combat, Hostile, Instant,
}
import genesis_prime/shared/creature_guard_spells
import genesis_prime/shared/creature_kind.{type Kinds, Kind, Kinds}
import genesis_prime/shared/creature_special
import genesis_prime/shared/creature_unit_type.{NonPlayer}
import genesis_prime/shared/hit.{Blow, Defence, Offence, Worked}
import genesis_prime/shared/strike_tell
import genesis_prime/shared/telegraph_entries
import genesis_prime/shared/unit_fields
import genesis_prime/table/creature2
import genesis_prime/table/id.{type UnitProperty2Id, Creature2Id, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/terrain
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/game_number.{type GameNumbers, GameNumbers}
import genesis_prime/world_map/spawn.{type Row, type Spawn, Row, Spawn}
import genesis_prime/world_map/spawn_id.{type SpawnId, LoadedSpawns, SpawnId}
import genesis_prime/world_map/spawn_source.{Summoned}
import genesis_prime/world_map/static_object.{type StaticObject, StaticObject}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/set
import owned_key
import place_support
import projector_support
import rating_support
import server_proxy_support
import tutorial_support
import zone_welcome_support

/// Warfare Woods, WorldZone 5967 (Quest2.10518).
pub const warfare_woods = 5967

/// The game numbers migrations 0010 and 0015 seed: an aggro range of 10, a leash
/// range of 55, an aggro threat of 1, a chase stop fraction of 0.5, a health regen
/// fraction of 0.025 and a health regen tick of 500 ms.
pub const numbers: GameNumbers =
  GameNumbers(
    aggro_range: 10.0,
    leash_range: 55.0,
    aggro_threat: 1.0,
    chase_stop_fraction: 0.5,
    health_regen_fraction: 0.025,
    health_regen_tick_ms: 500,
    interrupt_armor_refill_ms: 10_000,
    kill_experience_fraction: 0.25,
    kill_experience_multipliers: [0.0, 0.25, 0.5, 0.75, 1.0, 1.1, 1.2, 1.3, 1.4],
    daily_quest_reset_ms: 36_000_000,
    weekly_quest_reset_ms: 122_400_000,
    starting_credits: 1000,
    used_object_release_ms: 30_000,
  )

/// The spawn numbered `number` of a Virtual Battle Beast, `x` units along the
/// world's x axis.
pub fn battle_beast(number number: Int, x x: Float) -> Spawn {
  Spawn(
    id: SpawnId(number),
    creature_id: Creature2Id(73_464),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: warfare_woods,
      x:,
      y: 0.0,
      z: 0.0,
    ),
    level: 1,
    health: 52,
    health_source: unit_fields.ClientDefault,
    faction_id: 1441,
    base_faction_id: 1441,
    display_info_id: 26_565,
    outfit_info_id: 0,
    vendor: False,
    unit_type: NonPlayer,
    world_object_id: 0,
    visibility: option.None,
    combat: beast_combat(),
    bases: loaded_beast().bases,
    context: loaded_beast().context,
    checklist_index: 0,
  )
}

/// The Virtual Battle Beast as the load builds it from the client's committed rows: the
/// summon of Creature2 73464 at its own level, whose `bases` and `context` a test's spawn
/// carries and whose `combat` is what `beast_combat` states by hand.
pub fn loaded_beast() -> Spawn {
  database_support.once("spawn_support_loaded_beast", fn() {
    let assert Ok(beast) =
      spawn.summoned(
        checks: summon_checks(),
        summoned: Summoned(
          id: SpawnId(-1),
          creature_id: Creature2Id(73_464),
          level: option.None,
          place: place_support.at(
            world_id: 3460,
            world_zone_id: warfare_woods,
            x: 0.0,
            y: 0.0,
            z: 0.0,
          ),
        ),
      )
      as "the Virtual Battle Beast passes the summon checks over the client's committed rows"
    beast
  })
}

/// The spawn numbered `number` of Dorian Walker, standing at `place`: Creature2
/// 74812, a quest giver and receiver (`questIdGiven00` 10528, `questIdReceive00`
/// 10520), faction 171, display 25510 (the one entry of display group 28097, hit
/// radius 1.1) and outfit 8952 (the first of outfit group 9759). Faction 171 is
/// level 10 to Exile 167 and level 0 to Dominion 166 (Faction2Relationship 771
/// and 685), so only the Dominion may attack him and he fights only the
/// Dominion on sight. The Beast's numbers fill the rest, which no test of a
/// quest giver reads.
pub fn dorian_walker(number number: Int, place place: Place) -> Spawn {
  let beast = battle_beast(number:, x: 0.0)
  Spawn(
    ..beast,
    creature_id: Creature2Id(74_812),
    place:,
    faction_id: 171,
    base_faction_id: 171,
    display_info_id: 25_510,
    outfit_info_id: 8952,
    combat: Combat(
      ..beast.combat,
      hit_radius: 1.1,
      attackable: Attackable(exile: False, dominion: True),
      hostile_to: Hostile(exile: False, dominion: True),
    ),
  )
}

/// The spawn numbered `number` of a Virtual Defense Dagun, the Dominion Novice's
/// first enemy, `x` units along the world's x axis: Creature2 73465, faction 1442,
/// display 26578 of hit radius 2.0, hostile to the Dominion (1442-166 level 0) and
/// friendly to Exiles (1442-167 level 10) (`Creature2.73465`), with the Beast's
/// level, health, defence and attack but its own reach, 5.0 + 2.0.
pub fn dagun(number number: Int, x x: Float) -> Spawn {
  let beast = battle_beast(number:, x:)
  Spawn(
    ..beast,
    creature_id: Creature2Id(73_465),
    faction_id: 1442,
    base_faction_id: 1442,
    display_info_id: 26_578,
    combat: Combat(
      ..beast.combat,
      hit_radius: 2.0,
      attackable: Attackable(exile: False, dominion: True),
      hostile_to: Hostile(exile: False, dominion: True),
      attack: Attack(..beast.combat.attack, reach: 7.0),
    ),
  )
}

/// The static object numbered `number` of a Holoring (Creature2 73416, a type 10
/// object of world 3460's start, the trace's) standing at `place`: no recorded
/// level or health, both factions 0, display 1. A test changes what it checks by
/// record update.
pub fn holoring(number number: Int, place place: Place) -> StaticObject {
  StaticObject(
    id: SpawnId(number),
    unit_type: static_object.Simple,
    creature_id: Creature2Id(73_416),
    place:,
    level: option.None,
    health: option.None,
    faction_id: 0,
    base_faction_id: 0,
    display_info_id: 1,
    outfit_info_id: 0,
    checklist_index: 0,
    world_object_id: 0,
    world_socket_id: 0,
    visibility: option.None,
  )
}

/// The object as the map tells a player who sees it (`ObjectsSeen`): its spawn's id and
/// its 0x262 under the unit id `unit_id`, stamped with the time 0.
pub fn seen(
  object object: StaticObject,
  unit_id unit_id: Int,
) -> #(SpawnId, static_object.Created) {
  #(
    object.id,
    static_object.create(object:, unit_id:, server_time_estimate_start: 0),
  )
}

/// The spawn numbered `number` of a Virtual Battle Beast standing at `place`.
pub fn beast_at(number number: Int, place place: Place) -> Spawn {
  Spawn(..battle_beast(number:, x: 0.0), place:)
}

/// A Beast standing at `place` that never deflects, so no roll of a caster's seed
/// changes what a hit does to it: every hit lands for the damage the formula gives. Its
/// BaseAvoidChance (101) and Rating_AvoidIncrease (33) are 0, so a deflect chance worked
/// out again from changed properties (`spawn.values_of`) is 0 too, as its stated one is.
pub fn beast_without_deflect_at(
  number number: Int,
  place place: Place,
) -> Spawn {
  let beast = beast_at(number:, place:)
  let never_avoids = fn(entry: #(UnitProperty2Id, Float)) {
    case entry.0.value {
      101 | 33 -> #(entry.0, 0.0)
      _ -> entry
    }
  }
  Spawn(
    ..beast,
    bases: list.map(beast.bases, never_avoids),
    combat: Combat(
      ..beast.combat,
      defence: Defence(..beast.combat.defence, deflect_chance: 0.0),
    ),
  )
}

/// What the Virtual Battle Beast brings to a fight: the hit radius of its display, 3.0
/// (`Spell4.32812.area`); whom it may be attacked by (hostile to Exiles, `Creature2.73464`;
/// the Dominion's level is not read, and no test asserts it); whom it fights on sight:
/// Exiles, at level 0 to faction 167, and not the Dominion, at level 10 to 166
/// (Faction2Relationship 2943 and 2944, `Creature2.73464`); a deflect chance of 0.016,
/// no critical deflect, glance or mitigation (`Creature2.73464.crit_deflect_glance`,
/// `Creature2.73464.mitigation`); and its attack (`beast_attack`), with the crowd-control
/// masks the load reads for it (`loaded_beast`), so a test of what a held state refuses
/// takes the client's rows and not a number made up here.
pub fn beast_combat() -> creature_combat.Combat {
  Combat(
    hit_radius: 3.0,
    attackable: Attackable(exile: True, dominion: True),
    hostile_to: Hostile(exile: True, dominion: False),
    defence: Defence(
      deflect_chance: 0.016,
      crit_deflect_chance: 0.0,
      glance_chance: 0.0,
      glance_amount: 0.0,
      physical_mitigation: 0.0,
      tech_mitigation: 0.0,
      magic_mitigation: 0.0,
      shield_mitigation_max: 0.0,
      physical_taken: hit.as_dealt,
      tech_taken: hit.as_dealt,
      magic_taken: hit.as_dealt,
    ),
    attack: loaded_attack(),
    alternates: [],
    specials: [],
    interrupt_armor: creature_combat.NoArmor,
    fights: True,
  )
}

/// The attack of `beast_attack` with the crowd-control masks of the attack the load builds
/// from the client's rows.
fn loaded_attack() -> Attack {
  let loaded = loaded_beast().combat.attack
  Attack(
    ..beast_attack(),
    caster_cc_mask: loaded.caster_cc_mask,
    run_stopped_by: loaded.run_stopped_by,
  )
}

/// What a summon is checked with: the content tables, the rating formulas and
/// the kinds of `kinds`.
pub fn summon_checks() -> spawn.SummonChecks {
  spawn.summon_checks(
    tables: character_tables.content_tables(),
    formulas: rating_support.formulas(),
    kinds: kinds(),
    factions: creature_faction.none(),
    vendor_creatures: set.new(),
  )
}

/// The summon checks over these tables, built as the running server builds them:
/// from the given tables with the committed rows of the tables only the content
/// load reads added beside them, and the test's formulas and kinds.
pub fn summon_checks_over(
  tables tables: table_store.Tables,
) -> spawn.SummonChecks {
  spawn.summon_checks(
    tables: character_tables.content_over(tables:),
    formulas: rating_support.formulas(),
    kinds: kinds(),
    factions: creature_faction.none(),
    vendor_creatures: set.new(),
  )
}

/// The chosen factions migration 0027 leaves: the tutorial boss, Creature2 73499,
/// stands with faction 233, taken through the load's own check against these tables.
pub fn the_boss_is_given_233(
  tables tables: table_store.Tables,
) -> creature_faction.Factions {
  let assert Ok(factions) =
    creature_faction.select(
      rows: [creature_faction.Row(creature_id: 73_499, faction_id: 233)],
      tables:,
    )
    as "Creature2 73499 and Faction2 233 are rows of the client's tables"
  factions
}

/// The kinds migration 0010 leaves: row 0 alone, a respawn of 60 000 ms and an
/// attack of Spell4 5649 every 1500 ms.
pub fn kinds() -> Kinds {
  Kinds(
    default: Kind(
      respawn_ms: 60_000,
      attack_spell4_id: Spell4Id(5649),
      alternate_spell4_ids: [],
      attack_interval_ms: 1500,
      guard: option.None,
      specials: [],
    ),
    by_creature: dict.new(),
  )
}

/// The kinds with the Virtual Battle Beast (Creature2 73464) given these specials
/// (`kinds_with_specials`).
pub fn kinds_with_beast_specials(spell4_ids spell4_ids: List(Int)) -> Kinds {
  kinds_with_specials(creature_id: 73_464, spell4_ids:)
}

/// The kinds with the Virtual Battle Beast (Creature2 73464) given these auto-attacks in turn
/// (`kinds_with_autos`).
pub fn kinds_with_beast_autos(spell4_ids spell4_ids: List(Int)) -> Kinds {
  kinds_with_autos(creature_id: 73_464, spell4_ids:)
}

/// A creature of the client's own rows standing at the Beast's place, summoned as the load
/// builds a creature, with the kind of `kinds_with_specials`: the default's fields and the
/// one special `spell4_id`, cast again 10 000 ms after its start (migration 0035's guess).
pub fn special_creature(
  number number: Int,
  creature_id creature_id: Int,
  spell4_id spell4_id: Int,
) -> Spawn {
  summoned_with(
    number:,
    creature_id:,
    kinds: kinds_with_specials(creature_id:, spell4_ids: [spell4_id]),
  )
}

/// A creature of the client's own rows standing at the Beast's place, summoned as the load
/// builds a creature, with the kind of `kinds_with_autos`: the default's fields and these
/// auto-attacks in turn.
pub fn autos_creature(
  number number: Int,
  creature_id creature_id: Int,
  spell4_ids spell4_ids: List(Int),
) -> Spawn {
  summoned_with(
    number:,
    creature_id:,
    kinds: kinds_with_autos(creature_id:, spell4_ids:),
  )
}

/// The creature `creature_id` standing at the Beast's place, summoned over `kinds`.
fn summoned_with(
  number number: Int,
  creature_id creature_id: Int,
  kinds kinds: Kinds,
) -> Spawn {
  let assert Ok(creature) =
    summoned_over(
      tables: character_tables.content_tables(),
      number:,
      creature_id:,
      kinds:,
    )
    as "the creature passes the summon checks over the client's committed rows"
  creature
}

/// The creature `creature_id` standing at the Beast's place, summoned over `kinds` and these
/// content tables, or the summon's refusal.
fn summoned_over(
  tables tables: table_store.Tables,
  number number: Int,
  creature_id creature_id: Int,
  kinds kinds: Kinds,
) -> Result(Spawn, spawn.SummonRefusal) {
  spawn.summoned(
    checks: spawn.summon_checks(
      tables:,
      formulas: rating_support.formulas(),
      kinds:,
      factions: creature_faction.none(),
      vendor_creatures: set.new(),
    ),
    summoned: Summoned(
      id: SpawnId(number),
      creature_id: Creature2Id(creature_id),
      level: option.None,
      place: place_support.at(
        world_id: 3460,
        world_zone_id: warfare_woods,
        x: 0.0,
        y: 0.0,
        z: 0.0,
      ),
    ),
  )
}

/// A creature of the client's own rows standing at the Beast's place with the one special
/// `spell4_id` (`special_creature`), summoned over these content tables (the server's tables
/// with the content load's added, as `character_tables.content_over` or
/// `client_tables.with_content_tables` give them), or the summon's refusal.
pub fn special_creature_over(
  tables tables: table_store.Tables,
  number number: Int,
  creature_id creature_id: Int,
  spell4_id spell4_id: Int,
) -> Result(Spawn, spawn.SummonRefusal) {
  summoned_over(
    tables:,
    number:,
    creature_id:,
    kinds: kinds_with_specials(creature_id:, spell4_ids: [spell4_id]),
  )
}

/// The kinds with the creature `creature_id` given a kind of its own: the default's fields
/// and these auto-attacks in turn, the first its attack and the rest its alternates.
pub fn kinds_with_autos(
  creature_id creature_id: Int,
  spell4_ids spell4_ids: List(Int),
) -> Kinds {
  let kinds = kinds()
  let assert [lead, ..alternates] = list.map(spell4_ids, Spell4Id)
    as "a creature with auto-attacks has at least one"
  Kinds(
    ..kinds,
    by_creature: dict.from_list([
      #(
        creature_id,
        Kind(
          ..kinds.default,
          attack_spell4_id: lead,
          alternate_spell4_ids: alternates,
        ),
      ),
    ]),
  )
}

/// The kinds with the creature `creature_id` given a kind of its own: the default's fields
/// and these specials, each cast again 10 000 ms after its start, in this order.
pub fn kinds_with_specials(
  creature_id creature_id: Int,
  spell4_ids spell4_ids: List(Int),
) -> Kinds {
  let kinds = kinds()
  Kinds(
    ..kinds,
    by_creature: dict.from_list([
      #(
        creature_id,
        Kind(
          ..kinds.default,
          specials: list.map(spell4_ids, fn(spell4_id) {
            creature_special.Ref(spell4_id:, cooldown_ms: 10_000)
          }),
        ),
      ),
    ]),
  )
}

/// The kinds migration 0029 adds to migration 0010's: the Sim-Turrets' charges, Spell4
/// 85469 for Creature2 73494 and Spell4 86978 for 74862, every 3000 ms.
pub fn turret_kinds() -> Kinds {
  Kinds(
    ..kinds(),
    by_creature: dict.from_list([
      #(
        73_494,
        Kind(
          respawn_ms: 60_000,
          attack_spell4_id: Spell4Id(85_469),
          alternate_spell4_ids: [],
          attack_interval_ms: 3000,
          guard: option.None,
          specials: [],
        ),
      ),
      #(
        74_862,
        Kind(
          respawn_ms: 60_000,
          attack_spell4_id: Spell4Id(86_978),
          alternate_spell4_ids: [],
          attack_interval_ms: 3000,
          guard: option.None,
          specials: [],
        ),
      ),
    ]),
  )
}

/// The same kinds as migration 0030 leaves them: both turrets guarded by Spell4 85474 and
/// opened by Spell4 85472, read from the client's tables.
pub fn guarded_turret_kinds() -> Kinds {
  let assert Ok(guard) =
    creature_guard_spells.guard_of(
      guard_spell4_id: 85_474,
      opening_spell4_id: 85_472,
      tables: character_tables.content_tables(),
    )
    as "Spell4 85474 and 85472 are rows of the client's tables the guard applies"
  let kinds = turret_kinds()
  Kinds(
    ..kinds,
    by_creature: dict.map_values(kinds.by_creature, fn(_, kind) {
      Kind(..kind, guard: option.Some(guard))
    }),
  )
}

/// The factions migration 0029 chooses for the Sim-Turrets: 1441 for Creature2 73494
/// and 1442 for 74862.
pub fn the_turrets_are_given_their_factions(
  tables tables: table_store.Tables,
) -> creature_faction.Factions {
  let assert Ok(factions) =
    creature_faction.select(
      rows: [
        creature_faction.Row(creature_id: 73_494, faction_id: 1441),
        creature_faction.Row(creature_id: 74_862, faction_id: 1442),
      ],
      tables:,
    )
    as "Creature2 73494 and 74862 and Faction2 1441 and 1442 are rows of the client's tables"
  factions
}

/// The Exile Sim-Turret, Creature2 73494, as the content load starts it from a stored
/// type 13 row at `place` in World 3460: its own health, factions 1441, its charge Spell4
/// 85469 with the area its rows give, and a run speed of 0. The test stands it where it
/// likes and reads what the load made of it.
pub fn sim_turret(number number: Int, place place: Place) -> Spawn {
  sim_turret_over(tables: character_tables.content_tables(), number:, place:)
}

/// The Exile Sim-Turret as `sim_turret` starts it, over these content tables, for a test
/// that changes a row of the turret's spell.
pub fn sim_turret_over(
  tables tables: table_store.Tables,
  number number: Int,
  place place: Place,
) -> Spawn {
  let assert Ok(creature) = creature2.get(tables, Creature2Id(73_494))
    as "the client holds the Exile Sim-Turret"
  let row =
    Row(
      ..spawn.creature_row(
        looks: spawn.looks(tables:),
        id: SpawnId(number),
        creature:,
        place:,
        level: option.None,
        factions: creature_faction.none(),
      ),
      entity_type: 13,
    )
  let selection =
    spawn.select(
      rows: [row],
      tables:,
      formulas: rating_support.formulas(),
      kinds: turret_kinds(),
      vendor_creatures: set.new(),
      factions: the_turrets_are_given_their_factions(tables:),
    )
  let assert Ok(world) = dict.get(selection.worlds, 3460)
    as "the turret row starts in world 3460"
  let assert Ok(turret) = dict.get(world.by_id, SpawnId(number))
    as "the turret row starts as a creature"
  turret
}

/// The striker of a Virtual Battle Beast's strike: the beast's unit 7 with its attack's
/// spell.
pub fn beast_striker() -> strike_tell.Striker {
  strike_tell.CreatureStriker(unit_id: 7, spell4_id: beast_attack().spell4_id)
}

/// `attack` with its charge changed by `change`, whatever else the attack holds: `change`
/// gets the charge and returns the charge to cast instead.
pub fn attack_with_charged(
  attack attack: creature_combat.Attack,
  change change: fn(creature_combat.Cast) -> creature_combat.Cast,
) -> creature_combat.Attack {
  let assert creature_combat.Charged(..) = attack.cast
    as "only a charged attack has a charge to change"
  creature_combat.Attack(..attack, cast: change(attack.cast))
}

/// `special` with its charge changed by `change` (`attack_with_charged`), whatever else the
/// special holds.
pub fn special_with_charged(
  special special: creature_combat.Special,
  change change: fn(creature_combat.Cast) -> creature_combat.Cast,
) -> creature_combat.Special {
  creature_combat.Special(
    ..special,
    attack: attack_with_charged(attack: special.attack, change:),
  )
}

/// The Virtual Battle Beast's attack: Spell4 5649, whose effect 184741 hits for 12
/// at difficulty 1 (`Spell4Effects.184741`, `0x140565600`), Physical (damage type
/// 1), with no critical hit or strikethrough; a run speed of 10.0
/// (`Creature2.73464`, `0x1405b45e0`) and a reach of the spell's range 5.0 plus the
/// hit radius 3.0.
pub fn beast_attack() -> Attack {
  Attack(
    spell4_id: Spell4Id(5649),
    offence: Offence(
      blows: [
        Blow(
          spell4_effects_id: 184_741,
          damage_type: 1,
          damage: Worked(12),
          delay_ms: 0,
          threat_multiplier: 1.0,
        ),
      ],
      crit_chance: 0.0,
      crit_severity: 1.0,
      strikethrough: 0.0,
    ),
    run_speed: 10.0,
    reach: 8.0,
    adds_target_radius: False,
    cast: Instant,
    caster_cc_mask: 0,
    run_stopped_by: 0,
  )
}

/// A row of the spawn table for a Virtual Battle Beast with no stats, standing
/// in World 3460 at the origin: a test changes the fields it is about with
/// record update.
pub fn beast_row(number number: Int) -> Row {
  Row(
    id: SpawnId(number),
    entity_type: 0,
    creature_id: 73_464,
    world_id: 3460,
    area_id: 0,
    x: 0.0,
    y: 0.0,
    z: 0.0,
    rotation_x: 0.0,
    rotation_y: 0.0,
    rotation_z: 0.0,
    display_info_id: 26_565,
    outfit_info_id: 0,
    faction_id: 1441,
    base_faction_id: 1441,
    world_object_id: 0,
    world_socket_id: 0,
    health: option.None,
    level: option.None,
  )
}

/// The three Dead Crash Survivor rows of Crash Site, as the world database holds them
/// (spawns 18388, 18605 and 18619 of Creature2 13277, 50716 and 50717, faction 171, each
/// with its own display and outfit, uiFlags 0x1AF), in World 3460 in place of their own
/// world 426, whose rows no test of a map needs.
pub fn crash_site_bodies() -> List(Row) {
  let body = fn(number, creature_id, x, y, z, display_info_id, outfit_info_id) {
    Row(
      ..beast_row(number:),
      creature_id:,
      x:,
      y:,
      z:,
      display_info_id:,
      outfit_info_id:,
      faction_id: 171,
      base_faction_id: 171,
    )
  }
  [
    body(18_388, 13_277, 3945.564, -708.157, -5398.904, 27_523, 7800),
    body(18_605, 50_716, 3953.547, -710.021, -5397.297, 25_808, 7804),
    body(18_619, 50_717, 3963.479, -711.057, -5395.523, 25_767, 7805),
  ]
}

/// The row of Creature2 `creature_id` standing at the origin of World 3460, with the first
/// display and the first outfit of its groups, as a summon takes them.
pub fn creature_row_of(
  tables tables: table_store.Tables,
  number number: Int,
  creature_id creature_id: Int,
) -> Row {
  let assert Ok(creature) = creature2.get(tables, Creature2Id(creature_id))
    as "the creature has a Creature2 row"
  spawn.creature_row(
    looks: spawn.looks(tables:),
    factions: creature_faction.none(),
    id: SpawnId(number),
    creature:,
    place: place_support.at(
      world_id: 3460,
      world_zone_id: warfare_woods,
      x: 0.0,
      y: 0.0,
      z: 0.0,
    ),
    level: option.None,
  )
}

/// The spawns `spawn.select` starts of the rows over the client's committed rows, in
/// World 3460, by spawn number.
pub fn started_of(rows rows: List(Row)) -> List(Spawn) {
  started_over(tables: character_tables.content_tables(), rows:)
}

/// The same over these tables, which already hold the content tables
/// (`character_tables.content_over`): a test's edit of the client's rows.
pub fn started_over(
  tables tables: table_store.Tables,
  rows rows: List(Row),
) -> List(Spawn) {
  let selection =
    spawn.select(
      rows:,
      tables:,
      formulas: rating_support.formulas(),
      kinds: kinds(),
      vendor_creatures: set.new(),
      factions: creature_faction.none(),
    )
  let assert Ok(world) = dict.get(selection.worlds, 3460)
    as "the rows are in World 3460"
  dict.values(world.by_id)
  |> list.sort(fn(first, second) {
    let SpawnId(first_number) = first.id
    let SpawnId(second_number) = second.id
    int.compare(first_number, second_number)
  })
}

/// A key whose terms hold these spawns for World 3460 and no spawn for every
/// other world a test's map may run in, as the content load leaves them. It is
/// the test's own, erased when the body ends: a test with no spawns takes
/// `key_without_spawns` and puts nothing.
pub fn key_with(
  spawns spawns: List(Spawn),
  respawn_ms respawn_ms: Int,
) -> table_store.Key {
  key_in(world_id: 3460, spawns:, respawn_ms:)
}

/// The same with the spawns in the term of the World row `world_id`, which a test's
/// players are in when they are not in World 3460.
pub fn key_in(
  world_id spawns_world: Int,
  spawns spawns: List(Spawn),
  respawn_ms respawn_ms: Int,
) -> table_store.Key {
  key_in_with_objects(world_id: spawns_world, spawns:, objects: [], respawn_ms:)
}

/// The same with the static objects of that world as well as its spawns, as
/// `spawn.select` keeps them.
pub fn key_in_with_objects(
  world_id spawns_world: Int,
  spawns spawns: List(Spawn),
  objects objects: List(StaticObject),
  respawn_ms respawn_ms: Int,
) -> table_store.Key {
  let key = owned_key.new_fixture_key()
  put_worlds(key:, spawns_world:, spawns:, objects:, respawn_ms:)
  key
}

/// The key every test with no spawns shares: the terms are put once per run and
/// never erased, as the content load leaves them for a database with no spawn.
pub fn key_without_spawns() -> table_store.Key {
  database_support.once("spawn_support_key_without_spawns", fn() {
    let key = owned_key.new_shared_key()
    put_worlds(
      key:,
      spawns_world: 3460,
      spawns: [],
      objects: [],
      respawn_ms: 60_000,
    )
    key
  })
}

fn put_worlds(
  key key: table_store.Key,
  spawns_world spawns_world: Int,
  spawns spawns: List(Spawn),
  objects objects: List(StaticObject),
  respawn_ms respawn_ms: Int,
) -> Nil {
  content_game_number.put(key:, numbers:)
  content_spawn.put_summon_checks(key:, checks: summon_checks())
  content_spawn.put_visibility(key:, visibility: dict.new())
  content_spawn.put_reused_unit_objectives(key:, objectives: set.new())
  content_spawn.put_loaded_spawns(
    key:,
    loaded: LoadedSpawns(
      ids: set.from_list(list.append(
        list.map(spawns, fn(spawn) { spawn.id }),
        list.map(objects, fn(object) { object.id }),
      )),
    ),
  )
  content_class_resource.put(key:, classes: class_resource_support.classes())
  content_server_proxy.put(key:, proxies: server_proxy_support.none())
  content_zone_welcome.put(key:, welcomes: zone_welcome_support.none())
  content_tutorial_quest.put(key:, chain: tutorial_support.none())
  list.each(objective_set.tables(), fn(table) {
    objective_set.put(key:, table:, objectives: set.new())
  })
  content_projector_landing.put(key:, landings: projector_support.none())
  content_vendor.put(key:, vendors: vendor.none())
  content_creature_kind.put(
    key:,
    kinds: Kinds(..kinds(), default: Kind(..kinds().default, respawn_ms:)),
  )
  content_terrain.put(
    key:,
    grounds: dict.from_list(
      list.map(character_tables.content_worlds(), fn(world_id) {
        #(world_id, terrain.empty())
      }),
    ),
  )
  list.each(character_tables.content_worlds(), fn(world_id) {
    content_spawn.put_world(
      key:,
      world_id:,
      spawns: case world_id == spawns_world {
        True -> spawn.world_spawns(spawns:, objects:)
        False -> spawn.no_spawns()
      },
    )
  })
}

/// The offence with every blow dealing `damage`: planted test data, for a fight
/// whose test is of a death, not of the number.
pub fn dealing(
  offence offence: hit.Offence,
  damage damage: Int,
) -> hit.Offence {
  Offence(
    ..offence,
    blows: list.map(offence.blows, fn(blow) {
      Blow(..blow, damage: Worked(damage))
    }),
  )
}

/// The spawn with every blow of its attack dealing `damage` (`dealing`).
pub fn spawn_dealing(spawn spawn: Spawn, damage damage: Int) -> Spawn {
  let attack = spawn.combat.attack
  Spawn(
    ..spawn,
    combat: Combat(
      ..spawn.combat,
      attack: Attack(
        ..attack,
        offence: dealing(offence: attack.offence, damage:),
      ),
    ),
  )
}

/// Earthen Roar as a creature's special, with the hold the delay row 131968 gives (`hold_ms`).
pub fn earthen_roar(hold_ms hold_ms: Int) -> creature_combat.Special {
  let roar_cone =
    area.InsideShapes(placements: [
      area.Placement(
        shape: area.Cone(inner: 0.0, outer: 5.5, degrees: 40.0),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
    ])
  creature_combat.Special(
    attack: creature_combat.Attack(
      spell4_id: Spell4Id(55_317),
      offence: Offence(
        blows: [
          Blow(
            spell4_effects_id: 131_967,
            damage_type: 1,
            damage: Worked(21),
            delay_ms: 0,
            threat_multiplier: 1.0,
          ),
        ],
        crit_chance: 0.0,
        crit_severity: 1.0,
        strikethrough: 0.0,
      ),
      run_speed: 10.0,
      reach: 5.5,
      adds_target_radius: False,
      cast: creature_combat.Charged(
        cast_ms: 3000,
        area: area.Row(
          min_range: 0.0,
          max_range: 10.0,
          degrees: 360.0,
          target_count: 10,
          order: area.Nearest,
        ),
        inside: roar_cone,
        anchor: area.FixedAtCaster,
        draws: telegraph_entries.draws_of(
          tables: character_tables.content_tables(),
          spell4_id: Spell4Id(55_317),
        ),
        aims_at_target: False,
        gos: [
          creature_combat.Go(at_ms: 2500, strike: option.None),
          creature_combat.Go(
            at_ms: 3000,
            strike: option.Some(creature_combat.GoStrike(
              spell4_effects_ids: [131_967],
              inside: roar_cone,
            )),
          ),
        ],
        hold_ms:,
      ),
      caster_cc_mask: 218_960_739,
      run_stopped_by: 0,
    ),
    cooldown_ms: 10_000,
  )
}

/// The cone of a hit row of Ice Breath, TelegraphDamage 7956 and 7957: from 0 to 5.5 m, 20
/// degrees across, on the caster, turned `turn_degrees` (the row's rotationDegrees).
pub fn ice_breath_cone(turn_degrees turn_degrees: Float) -> area.Inside {
  area.InsideShapes(placements: [
    area.Placement(
      shape: area.Cone(inner: 0.0, outer: 5.5, degrees: 20.0),
      ahead: 0.0,
      aside: 0.0,
      turn_degrees:,
    ),
  ])
}

/// Yeti Snowstalker's Ice Breath (Spell4 55635) as a creature's special, with the hold of
/// `hold_ms` (the delay row 132758 gives 500). Its four gos are SpellPhase 11479 to 11482
/// (delays 2600, 400, 500 and 300): the second and third strike, each with the cone of its
/// own row (7956 turned +10 degrees, 7957 turned -10) and the damage row 132757, whose
/// phaseFlags 6 name them; the first and last are the cast bar's. The 10 000 ms cooldown is a
/// guess, as Earthen Roar's.
pub fn ice_breath(hold_ms hold_ms: Int) -> creature_combat.Special {
  creature_combat.Special(
    attack: creature_combat.Attack(
      spell4_id: Spell4Id(55_635),
      offence: Offence(
        blows: [
          Blow(
            spell4_effects_id: 132_757,
            damage_type: 1,
            damage: Worked(21),
            delay_ms: 0,
            threat_multiplier: 1.0,
          ),
        ],
        crit_chance: 0.0,
        crit_severity: 1.0,
        strikethrough: 0.0,
      ),
      run_speed: 10.0,
      reach: 5.5,
      adds_target_radius: False,
      cast: creature_combat.Charged(
        cast_ms: 3800,
        area: area.Row(
          min_range: 0.0,
          max_range: 10.0,
          degrees: 360.0,
          target_count: 10,
          order: area.Nearest,
        ),
        inside: area.InsideShapes(placements: [
          area.Placement(
            shape: area.Cone(inner: 0.0, outer: 5.5, degrees: 20.0),
            ahead: 0.0,
            aside: 0.0,
            turn_degrees: 10.0,
          ),
          area.Placement(
            shape: area.Cone(inner: 0.0, outer: 5.5, degrees: 20.0),
            ahead: 0.0,
            aside: 0.0,
            turn_degrees: -10.0,
          ),
        ]),
        anchor: area.FixedAtCaster,
        draws: telegraph_entries.draws_of(
          tables: character_tables.content_tables(),
          spell4_id: Spell4Id(55_635),
        ),
        aims_at_target: False,
        gos: [
          creature_combat.Go(at_ms: 2600, strike: option.None),
          creature_combat.Go(
            at_ms: 3000,
            strike: option.Some(creature_combat.GoStrike(
              spell4_effects_ids: [132_757],
              inside: ice_breath_cone(turn_degrees: 10.0),
            )),
          ),
          creature_combat.Go(
            at_ms: 3500,
            strike: option.Some(creature_combat.GoStrike(
              spell4_effects_ids: [132_757],
              inside: ice_breath_cone(turn_degrees: -10.0),
            )),
          ),
          creature_combat.Go(at_ms: 3800, strike: option.None),
        ],
        hold_ms:,
      ),
      caster_cc_mask: 218_960_739,
      run_stopped_by: 0,
    ),
    cooldown_ms: 10_000,
  )
}
