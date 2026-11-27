//// The spells a kind of creature casts besides its attack, as the content load reads
//// them (the creature_special table, genesis_prime/content/creature_special) and
//// checks, and what the kind holds of them (genesis_prime/world_map/creature_kind
//// `Kind.specials`). The client lists no spell for a creature and no cadence
//// (`creature.ai_data`), so each row is a server choice from a retail record, and its
//// cooldown a guess.
////
//// ```
//// creature_special rows ─▶ refusal_of(row, tables, sources) ─▶ Refusal(table: "creature_special", row: RowId(creature_id), rule)
//// creature_kind.select(rows, special_rows, tables) ─▶ refs_of(rows, creature_id) ─▶ Kind.specials
//// ```
////
//// - **A row names a Creature2 the client holds, never row 0**: a special for the default
////   kind would be cast by every creature. A creature with no `creature_kind` row of its own
////   takes the default kind's fields and its own specials (`creature_kind` builds an entry
////   for the union of the two tables' creature ids).
//// - **A row's refusal names its Spell4**: the key is `(creature_id, spell4_id)` and a
////   `RowId` holds one integer, so the sentence carries the Spell4.
//// - **The load refuses** a Spell4 the client lacks; a cooldown below the strike deadline
////   (`strike_tell.deadline_ms`), since two rounds would be open at once; and a spell
////   `creature_attack.special_checked` refuses: a ChanneledField cast with a cast time of 0
////   or a channel with a finish after its last pulse (`creature_attack.channel_carried`),
////   no readable area (rows
////   placed apart, on the caster and the target or drawn where the cast starts and following a
////   unit, are not readable: `spell_area.PlacedApart`; a row on each struck unit, the ground or
////   two units: `spell_area.TelegraphOnStruckUnits`, `spell_area.TelegraphNotOnCaster`; an area
////   row that selects by health, orders 4 and 5: `spell_area.SelectionNeedsHealth`; a hit row
////   of shape 8 with a box: `spell_area.ShapeNotBuilt`; a drawn hit row timed from a go:
////   `spell_area.TelegraphTimedFromAGo`), an effect
////   type other than 8 (damage) and 35 (NpcExecutionDelay), no damage phase, a phase flag
////   naming no go, an empty or non-increasing go schedule, a delay row the plan leaves out
////   (aimed at another unit, or with no duration) or one that names a go other than the
////   cast's last, a target condition (`spell4CCConditionsIdTarget`) other than 0, a delay row
////   behind a prerequisite, and any caster prerequisite the attack rule refuses. A bad row is
////   refused, never left out silently.
//// - **A cast strikes at each go its damage rows name**: with those rows' blows, inside the hit
////   rows the client is drawing at the go's time, and, for a cast whose phase the client
////   compares, that its phase names (`spell_area.hit_shapes_by_go`). A go whose damage rows all
////   fail the creature's difficulty, or at which no hit row is drawn, strikes nobody; the special
////   still loads when another go can strike, and is refused when none can
////   (`creature_attack.NoGoCanStrike`). The hold follows the cast's last go.
//// - **A special is cast whatever its `castTime`**: it has the gos of its plan, which may be
////   many, the first possibly at 0, whatever its cast time: 0, or above it (Haymaker 66285, a
////   Multiphase cast, has 3033) (`spawn` `attack_of`); the client draws the cast bar by the spell's own rows.
//// - **The formula is read**: a special whose damage formula the creature rule does not
////   read for the creature's difficulty is refused (`creature_attack.loadable`), which the
////   spawn load would refuse later.
//// - **`order_index` is not null and unique for a creature**: it orders the list `chosen`
////   walks (genesis_prime/world_map/creature_fight).

import genesis_prime/game/strike_tell
import genesis_prime/gap
import genesis_prime/shared/spell_plan
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/world_map/creature_attack
import gleam/int
import gleam/list

/// The table's name in a refusal.
pub const table = "creature_special"

/// One row of the creature_special table as the load reads it: the Creature2 id, the
/// Spell4 it casts, its place in the creature's list and the time in milliseconds from a
/// cast's start until it may be cast again.
pub type Row {
  Row(creature_id: Int, spell4_id: Int, order_index: Int, cooldown_ms: Int)
}

/// What a kind holds of one special: the Spell4 and its cooldown. The spawn works the
/// spell out into a `creature_life.Special` (genesis_prime/world_map/spawn).
pub type Ref {
  Ref(spell4_id: Int, cooldown_ms: Int)
}

/// The first rule the row breaks, as the refusal's sentence, or `Error(Nil)` for a row the
/// load takes (as `creature_kind`'s own refusals are read). `sources` are the plan's rows,
/// grouped once for all the rows (`spell_plan.sources_of`). The sentence names the special's
/// Spell4, since the key `RowId` holds only the creature.
pub fn refusal_of(
  row row: Row,
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
) -> Result(String, Nil) {
  let spell = int.to_string(row.spell4_id)
  let creature = int.to_string(row.creature_id)
  let checks = [
    fn() {
      case row.creature_id == 0 {
        True ->
          Ok(
            "the default kind, row 0, would cast the special of Spell4 "
            <> spell
            <> " for every creature",
          )
        False -> Error(Nil)
      }
    },
    fn() {
      case creature2.get(tables:, id: Creature2Id(row.creature_id)) {
        Error(Nil) ->
          Ok(
            "the client's Creature2 table has no creature "
            <> creature
            <> ", the caster of Spell4 "
            <> spell,
          )
        Ok(..) -> Error(Nil)
      }
    },
    fn() {
      case spell4.get(tables:, id: Spell4Id(row.spell4_id)) {
        Error(Nil) ->
          Ok(
            "the special Spell4 "
            <> spell
            <> " of Creature2 "
            <> creature
            <> " has no row in the client's Spell4 table",
          )
        Ok(..) -> Error(Nil)
      }
    },
    fn() {
      case row.cooldown_ms < strike_tell.deadline_ms {
        True ->
          Ok(
            "the cooldown of "
            <> int.to_string(row.cooldown_ms)
            <> " ms of the special Spell4 "
            <> spell
            <> " is below the strike deadline of "
            <> int.to_string(strike_tell.deadline_ms)
            <> " ms, so two of the creature's strike rounds would be open at once",
          )
        False -> Error(Nil)
      }
    },
    fn() {
      case
        creature_attack.special_checked(
          tables:,
          sources:,
          spell4_id: row.spell4_id,
        )
      {
        Error(unevaluated) ->
          Ok(
            "the special Spell4 "
            <> spell
            <> " of Creature2 "
            <> creature
            <> " is refused: "
            <> creature_attack.describe(unevaluated:),
          )
        Ok(Nil) -> Error(Nil)
      }
    },
    fn() {
      let assert Ok(found) =
        creature2.get(tables:, id: Creature2Id(row.creature_id))
        as "the creature's own check came first"
      case
        creature_attack.loadable(
          tables:,
          spell4_id: row.spell4_id,
          difficulty: found.creature2_difficulty_id,
        )
      {
        Error(unevaluated) ->
          Ok(
            "the special Spell4 "
            <> spell
            <> " of Creature2 "
            <> creature
            <> " is refused for its difficulty "
            <> int.to_string(found.creature2_difficulty_id)
            <> ": "
            <> creature_attack.describe(unevaluated:),
          )
        Ok(Nil) -> Error(Nil)
      }
    },
  ]
  list.find_map(checks, fn(check) { check() })
}

/// The refs of the rows of one creature, in `order_index` order.
pub fn refs_of(
  rows rows: List(Row),
  creature_id creature_id: Int,
) -> List(Ref) {
  rows
  |> list.filter(fn(row) { row.creature_id == creature_id })
  |> list.sort(fn(first, second) {
    int.compare(first.order_index, second.order_index)
  })
  |> list.map(fn(row) {
    Ref(spell4_id: row.spell4_id, cooldown_ms: row.cooldown_ms)
  })
}

/// What the load of the specials leaves undone, for the coverage measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Creature specials",
      missing: "a multi-hit special with no cast bar is broken by a stun or a knockdown as one with a bar is: the client has no rule for it, so it is a server choice",
    ),
    gap.Entry(
      area: "Creature specials",
      missing: "a special whose cast lasts as long as its cooldown is cast again as soon as its hold ends, so such a creature may never use its auto-attack",
    ),
    gap.Entry(
      area: "Creature specials",
      missing: "a ChanneledField special with a cast time of 0 is refused, as the number of gos the client expects of it is not settled",
    ),
    gap.Entry(
      area: "Creature specials",
      missing: "a ChanneledField special with a cast time above 0 (Spell4 47518 and 47627) is cast as the one go at its cast time, 200 ms, although the client keeps a 20 s channel record for each: the number of gos the client expects of it is not settled",
    ),
    gap.Entry(
      area: "Creature specials",
      missing: "a channel whose last pulse falls before its channelMaxTime, where the client's cast ends, is refused, as the creature's round writes its 0x7fe after the last go and has no later finish",
    ),
    gap.Entry(
      area: "Creature specials",
      missing: "a creature spell taken from a retail record has an order and a cooldown the server guessed: an auto-attack's place is its description number and then its Spell4 id, a special's place is the order its retail page lists it in with a cooldown of 10000 ms, and a page is matched to a creature by its name and world, as no client table links a creature to a page; of a spell a page lists at several tiers the lowest tier is kept, as the client holds no creature spell list",
    ),

    gap.Entry(
      area: "Creature specials",
      missing: "an auto-attack the importer lists as a special because its description lacks the auto-attack marker is read as a special when it loads (4 spells) and is refused for having no area row otherwise (203 unmarked `Auto-Attack #n` spells)",
    ),
  ]
}
