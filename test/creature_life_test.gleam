//// A creature's health, death, corpse and respawn (`genesis_prime/world_map/creature_life`),
//// run as the pure rule it is. Expected values come from these places.
//// - The Virtual Battle Beast: 52 health (Base Health 52.6205 truncated,
////   `Creature2.creature2ArcheTypeId`, `opcode.0x262.creature`), a deflect chance of
////   0.016 (`Creature2.73464.crit_deflect_glance`), no mitigation
////   (`Creature2.73464.mitigation`).
//// - The respawn time: the kind's 60 000 ms default (migration 0009, row 0).
//// - The rule's doc comment: health stays in [0, max]; the killed bit is set exactly
////   when a blow takes the health to 0; the overkill is the damage beyond the health
////   before the blow; a deflect changes no health and sends no news; a corpse refuses
////   every strike as dead; the news is Health after each landed hit and Died after the
////   one that kills (`opcode.0x937`, `opcode.0x88c`, `death.corpse`).
//// - A creature told to retire while dead stops at its respawn, and one that
////   stands stops at once; at its respawn a creature that was told to retire ends
////   and any other stands again at full health (`death.creature_respawn`).

import genesis_prime/game/hit.{Blow, Offence, Rolls}
import genesis_prime/game/strike_tell.{
  Answered, Dead, Deflected, Key, Landed, Refused, Strike,
}
import genesis_prime/step.{ConnectionId}
import genesis_prime/world_map/creature_life.{
  type Life, Body, Died, Health, StandsAgain, StopAtRespawn, StopNow,
}
import gleam/list
import gleam/option.{None, Some}
import map_support
import owned_test
import place_support
import spawn_support

fn beast() -> creature_life.Body {
  Body(max_health: 52, combat: spawn_support.beast_combat(), respawn_ms: 60_000)
}

/// A strike of one blow of `damage`, which no roll turns into a critical hit or a
/// deflect unless the rolls say so.
fn strike_of(
  damage damage: Int,
  rolls rolls: hit.Rolls,
  cast_id cast_id: Int,
) -> strike_tell.Tell {
  Strike(
    key: Key(cast_id:, phase: 0, unit_id: 20),
    from: step.Connection(ConnectionId(2)),
    offence: Offence(
      blows: [
        Blow(
          spell4_effects_id: 1,
          damage_type: 3,
          damage:,
          delay_ms: 0,
          threat_multiplier: 1.0,
        ),
      ],
      crit_chance: 0.0,
      crit_severity: 1.5,
      strikethrough: 0.0,
    ),
    striker: strike_tell.PlayerStriker(
      unit_id: 1,
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 5967,
        x: 0.0,
        y: 0.0,
        z: 0.0,
      ),
      seq: 1,
      stay: map_support.stay(count: 1),
      hit_radius: place_support.player_hit_radius,
      rolls:,
    ),
    controls: [],
  )
}

const no_luck = Rolls(crit: 0.5, deflect: 0.5, glance: 0.5)

pub fn a_hit_that_leaves_health_sends_the_new_health_and_no_death_test() -> Nil {
  use <- owned_test.run(5000)
  let life = creature_life.new(body: beast())
  let reaction =
    creature_life.struck(
      life:,
      body: beast(),
      strike: strike_of(damage: 18, rolls: no_luck, cast_id: 1),
    )
  assert creature_life.health(reaction.life) == 34
    as "52 - 18: Telekinetic Strike's 18 at level 1 (Spell4.32893)"
  assert reaction.news == [Health(health: 34, dead: False)]
  assert reaction.corpse_for_ms == None
  let assert Answered(
    key: Key(cast_id: 1, ..),
    outcome: Landed(descriptions: [description], controls: [], armor_removed: 0),
  ) = reaction.answer
  assert description.damage.killed == 0
}

pub fn a_creatures_life_passes_no_absorb_test() -> Nil {
  use <- owned_test.run(5000)
  // A creature holds no pool (`Spell4Effects.effectType.29`'s gap: no rule gives one, and a
  // creature casts only its attack), so a blow of any damage type reaches its health whole:
  // the Beast has no mitigation (`Creature2.73464.mitigation`), so nothing is absorbed, the
  // health takes all 18 and no shield takes any.
  let taken = fn(damage_type) {
    let reaction =
      creature_life.struck(
        life: creature_life.new(body: beast()),
        body: beast(),
        strike: Strike(
          ..strike_of(damage: 18, rolls: no_luck, cast_id: 1),
          offence: Offence(
            blows: [
              Blow(
                spell4_effects_id: 1,
                damage_type:,
                damage: 18,
                delay_ms: 0,
                threat_multiplier: 1.0,
              ),
            ],
            crit_chance: 0.0,
            crit_severity: 1.5,
            strikethrough: 0.0,
          ),
        ),
      )
    let assert Answered(outcome: Landed(descriptions: [description], ..), ..) =
      reaction.answer
    #(
      creature_life.health(reaction.life),
      description.damage.absorbed,
      description.damage.shield_absorbed,
      description.damage.health_damage_with_overkill,
    )
  }
  assert list.map([1, 2, 3], taken)
    == [#(34, 0, 0, 18), #(34, 0, 0, 18), #(34, 0, 0, 18)]
    as "Physical, Tech and Magic: 52 less 18, nothing absorbed"
}

pub fn a_hit_that_kills_sends_health_with_the_dead_bit_then_the_death_and_starts_the_corpse_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let reaction =
    creature_life.struck(
      life: creature_life.new(body: beast()),
      body: beast(),
      strike: strike_of(damage: 60, rolls: no_luck, cast_id: 1),
    )
  assert creature_life.is_dead(reaction.life)
    && creature_life.health(reaction.life) == 0
    as "health stays in [0, max]: 60 damage on 52 health leaves 0"
  assert reaction.news == [Health(health: 0, dead: True), Died]
    as "0x937 with the dead bit, then 0x88c (opcode.0x937, opcode.0x88c)"
  assert reaction.corpse_for_ms == Some(60_000)
    as "the corpse stays for the kind's respawn time"
  let assert Landed(descriptions: [description], controls: [], armor_removed: 0) =
    reaction.answer.outcome
  assert description.damage.killed == 1 && description.damage.overkill == 8
    as "killed exactly at 0; the overkill is the damage beyond the health before: 60 - 52"
}

pub fn two_strikes_that_cross_are_answered_in_turn_and_the_second_finds_a_corpse_test() -> Nil {
  use <- owned_test.run(5000)
  let first =
    creature_life.struck(
      life: creature_life.new(body: beast()),
      body: beast(),
      strike: strike_of(damage: 52, rolls: no_luck, cast_id: 1),
    )
  let second =
    creature_life.struck(
      life: first.life,
      body: beast(),
      strike: strike_of(damage: 52, rolls: no_luck, cast_id: 2),
    )
  assert second.answer
    == Answered(
      key: Key(cast_id: 2, phase: 0, unit_id: 20),
      outcome: Refused(why: Dead),
    )
    as "Spell4ValidTargets.targetBitmask: a dead unit is never struck"
  assert second.news == []
    && second.corpse_for_ms == None
    && creature_life.is_dead(second.life)
    as "a refused strike changes nothing and sends no news"
}

pub fn a_deflected_strike_changes_no_health_and_sends_no_news_test() -> Nil {
  use <- owned_test.run(5000)
  let reaction =
    creature_life.struck(
      life: creature_life.new(body: beast()),
      body: beast(),
      strike: strike_of(
        damage: 18,
        rolls: Rolls(crit: 0.5, deflect: 0.01, glance: 0.5),
        cast_id: 1,
      ),
    )
  assert reaction.answer.outcome == Deflected
    as "a deflect roll of 0.01 is below the deflect chance 0.016"
  assert creature_life.health(reaction.life) == 52 && reaction.news == []
}

pub fn a_creature_that_stands_stops_at_once_when_told_to_retire_and_a_corpse_waits_for_its_respawn_test() -> Nil {
  use <- owned_test.run(5000)
  let alive = creature_life.new(body: beast())
  let dead =
    creature_life.struck(
      life: alive,
      body: beast(),
      strike: strike_of(damage: 52, rolls: no_luck, cast_id: 1),
    ).life
  assert creature_life.on_retire(life: alive) == StopNow
  assert creature_life.on_retire(life: dead) == StopAtRespawn
    as "the map keeps the spawn retiring until the creature ends, so a corpse is never shown to a later viewer"
}

fn stands_at(life life: Life) -> Int {
  creature_life.health(life)
}

pub fn a_corpse_stands_again_at_full_health_at_its_respawn_and_ends_when_it_was_told_to_retire_test() -> Nil {
  use <- owned_test.run(5000)
  let dead =
    creature_life.struck(
      life: creature_life.new(body: beast()),
      body: beast(),
      strike: strike_of(damage: 52, rolls: no_luck, cast_id: 1),
    ).life
  let assert StandsAgain(life:) =
    creature_life.corpse_timer_fired(life: dead, body: beast(), retiring: False)
  assert stands_at(life:) == 52 && !creature_life.is_dead(life)
    as "death.creature_respawn: the creature comes back as the server sends it, full"
  assert creature_life.corpse_timer_fired(
      life: dead,
      body: beast(),
      retiring: True,
    )
    == creature_life.Ends
}

pub fn a_creature_that_lies_dead_is_created_dead_for_a_viewer_that_arrives_test() -> Nil {
  use <- owned_test.run(5000)
  let dead =
    creature_life.struck(
      life: creature_life.new(body: beast()),
      body: beast(),
      strike: strike_of(damage: 52, rolls: no_luck, cast_id: 1),
    ).life
  assert creature_life.health(dead) == 0
    as "opcode.0x262.creature: stat 0 of 0 makes the client create the creature dead"
}
