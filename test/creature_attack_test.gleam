//// A creature's own attack as the content load works it out
//// (`genesis_prime/world_map/creature_attack`, `genesis_prime/world_map/spawn`
//// `Attack`), on the planted tables, which hold the client's rows of the Virtual
//// Battle Beast and of Spell4 5649. Expected values come from these places.
//// - `Spell4Effects.184741`: spell 5649's two Physical damage effects, 184741
////   (Strength 0.55, Assault Power 0.55) for a caster of difficulty at most 6 and
////   184777 (0.8 each) for difficulty at least 7, each threatMultiplier 1.0; the
////   prerequisite type 179 is the caster's difficulty (`0x14049eeb0`).
//// - The creature formula (`0x140565600`, GameFormula 712: 70, 100, 1, 1): the stat
////   part S rounded, held under c = (level x 70 + 100) x the mean of the stat
////   parameters. A level-1 Beast of difficulty 1 has Strength 15.392292 x 0.68 =
////   10.4668 and AssaultRating 61.569168 x 0.68 = 41.867, Assault Power 10.4668
////   (CreatureLevel 1, Creature2Difficulty 1, GameFormula 1266): 0.55 x 10.4668 x 2
////   = 11.51, rounded to 12, under c = 93.5. At difficulty 7 (multipliers 0.7)
////   both are 10.7746: 0.8 x 10.7746 x 2 = 17.24, rounded to 17, under c = 136.
//// - Its run speed is runLand 10.0 times MoveSpeedMultiplier 1.0 (`0x1405b45e0`,
////   `Creature2.73464`), its reach the spell's targetMaxRange 5.0 (`Spell4.5649`)
////   plus its hit radius 3.0, a server choice.
//// - Its critical hit chance is BaseCritChance (CreatureLevel 101's 0.05 x
////   difficulty 1's 0.32 = 0.016), its severity CriticalHitSeverityMultiplier (1.5
////   x tier 1's 0.85 = 1.275), its strikethrough 0 (CreatureLevel 101's 0.0), each
////   with no rating (274's damage trace, `0x140453b60`).

import character_tables
import genesis_prime/game/hit.{Blow}
import genesis_prime/table/creature2_difficulty
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/spawn.{type Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/float
import gleam/list
import owned_key
import owned_test
import planted_table.{Float, Integer}
import rating_support
import spawn_support

/// The Beast of spawn 1 as the planted files select it.
fn beast_of(files files: List(#(String, BitArray))) -> Spawn {
  use folder <- planted_table.in_folder(list.append(
    files,
    character_tables.content_files(),
  ))
  let assert Ok(server) =
    server_table.load_under(under: owned_key.new(), from: folder)
    as "the planted files load as the server's tables"
  let assert Ok(more) =
    server_table.load_content_tables(over: server, from: folder)
    as "the planted files load as the content-only tables"
  let selection =
    spawn.select(
      rows: [spawn_support.beast_row(number: 1)],
      tables: more,
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
    )
  table_store.unload(more)
  table_store.unload(server)
  let assert [] = selection.refusals as "the Beast's row is taken"
  let assert Ok(world) = dict.get(selection.worlds, 3460) as "world 3460"
  let assert Ok(beast) = dict.get(world.by_id, SpawnId(1)) as "spawn 1 starts"
  beast
}

fn close(first: Float, second: Float) -> Bool {
  float.absolute_value(first -. second) <. 0.000001
}

pub fn a_creature_of_difficulty_1_strikes_with_effect_184741_for_12_test() -> Nil {
  use <- owned_test.run(60_000)
  let attack = { beast_of(files: character_tables.files()) }.combat.attack
  assert attack.spell4_id == Spell4Id(5649)
    as "the kind's spell (migration 0010)"
  assert attack.offence.blows
    == [
      Blow(
        spell4_effects_id: 184_741,
        damage_type: 1,
        damage: 12,
        delay_ms: 0,
        threat_multiplier: 1.0,
      ),
    ]
    as "difficulty 1 passes prerequisite 30526 (at most 6) and fails 30527 (at least 7): effect 184741 alone, Physical, 12 by the creature formula"
  assert attack.run_speed == 10.0 && attack.reach == 8.0
    as "runLand 10.0 x 1.0; targetMaxRange 5.0 plus hit radius 3.0"
  assert close(attack.offence.crit_chance, 0.016)
    && close(attack.offence.crit_severity, 1.275)
    && attack.offence.strikethrough == 0.0
    as "BaseCritChance 0.05 x 0.32, severity 1.5 x 0.85, no strikethrough"
}

pub fn a_creature_of_difficulty_7_strikes_with_effect_184777_for_17_test() -> Nil {
  use <- owned_test.run(60_000)
  let difficulty_7 =
    planted_table.row(creature2_difficulty.schema, [
      #("ID", Integer(7)),
      #("unitPropertyMultiplier000", Float(0.699999988079071)),
      #("unitPropertyMultiplier007", Float(1.0)),
      #("unitPropertyMultiplier035", Float(0.699999988079071)),
      #("unitPropertyMultiplier100", Float(1.0)),
      #("unitPropertyMultiplier101", Float(0.3199999928474426)),
      #("unitPropertyMultiplier102", Float(2.0)),
      #("unitPropertyMultiplier104", Float(2.0)),
      #("unitPropertyMultiplier127", Float(1.0)),
    ])
  let files =
    character_tables.files_with_beast_changed(changes: [
      #("creature2DifficultyId", Integer(7)),
    ])
    |> replace(
      file: creature2_difficulty.schema.file,
      with: planted_table.file(creature2_difficulty.schema, [difficulty_7]),
    )
  let attack = { beast_of(files:) }.combat.attack
  assert attack.offence.blows
    == [
      Blow(
        spell4_effects_id: 184_777,
        damage_type: 1,
        damage: 17,
        delay_ms: 0,
        threat_multiplier: 1.0,
      ),
    ]
    as "difficulty 7 (Creature2Difficulty 7, multipliers 0.7) fails 30526 and passes 30527: effect 184777 alone, 17"
}

fn replace(
  files files: List(#(String, BitArray)),
  file name: String,
  with replacement: #(String, BitArray),
) -> List(#(String, BitArray)) {
  list.map(files, fn(file) {
    case file.0 == name {
      True -> replacement
      False -> file
    }
  })
}
