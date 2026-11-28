//// Which spells of the retail record's pages a spawned creature gets as its own
//// auto-attacks and specials: the rule of the retail-record import
//// (`genesis_prime/import_retail_record`), pure, so the import's database and file
//// work stays apart from its decisions.
////
//// ```
//// spawned creature ─▶ its client name ({p:..} plural marks stripped)
////     ─▶ the pages of that name with a spawn in a world of the page's zone
////     ─▶ pages that differ: the zone holding a spawn's area, else refused
////     ─▶ each listed spell: an auto-attack, a special, or left out with its rule
//// ```
////
//// - **Name and world match a page to a creature,** the server's choice (no client table
////   links a creature to a page). A Jabbithole zone is a MapZone id
////   (298 of the 299 zones on pages with an Abilities tab are rows of the client's MapZone
////   table, and 296 of those carry the client's own text of the name); the client's
////   MapZoneWorldJoin maps a zone to its worlds. A name alone matches a creature of another
////   zone with the same name.
//// - **The zone holding a spawn's area settles pages that differ.** A spawn's area is a
////   WorldZone id, and a MapZone names a WorldZone (`MapZone.worldZoneId`) that is the area
////   or one of its parents (`WorldZone.parentZoneId`).
//// - **A listed spell is an auto-attack** when the client's Spell4 description starts
////   `[AUTO-ATTACK]`, its cast time is 0 and the load's own check of an auto-attack
////   (`creature_auto_attack.refusal_of`) passes. No client table links a creature to a
////   spell, so the role is read from that description.
//// - **Any other listed spell is a special** when the load's own check of a special
////   (`creature_special.refusal_of`) passes.
//// - **One tier of a family is kept:** the lowest `tierIndex` listed of a Spell4Base.
//// - **Orders and the cooldown are guesses**: the auto-attacks by
////   their number in the description then the Spell4 id, the specials as the page lists them,
////   a special's cooldown a fixed 10,000 ms.

import genesis_prime/jabbithole_page.{type Ability, type Page}
import genesis_prime/shared/creature_auto_attack
import genesis_prime/shared/creature_special
import genesis_prime/shared/spell_plan
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/map_zone
import genesis_prime/table/map_zone_world_join
import genesis_prime/table/spell4
import genesis_prime/table/world_zone
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// The time in milliseconds from a special's cast until the creature may cast it again:
/// a guess, as the client holds no cadence for a special.
const special_cooldown_ms = 10_000

/// Where creatures with a spawn stand: how many spawns a creature has in one area of one
/// world.
pub type Spawned {
  Spawned(creature_id: Int, world_id: Int, area_id: Int, spawns: Int)
}

/// One auto-attack to write.
pub type Auto {
  Auto(creature_id: Int, spell4_id: Int, order_index: Int)
}

/// One special to write.
pub type Special {
  Special(creature_id: Int, spell4_id: Int, order_index: Int, cooldown_ms: Int)
}

/// Why a listed spell is not written.
pub type Refusal {
  NoSpellRow
  /// Another tier of the spell's Spell4Base is listed, and the lowest tier is the one kept.
  OtherTierKept
  /// The content load's own check of the row refuses the spell: its sentence.
  Refused(sentence: String)
}

/// A listed spell that is not written, with the rule that left it out.
pub type SpellLeftOut {
  SpellLeftOut(spell4_id: Int, why: Refusal)
}

/// Why a creature gets no page.
pub type Why {
  NotInTheClientTable
  NoNameInTheClient
  NoPageByName
  NoPageInTheCreatureWorlds
  /// The pages of the creature's worlds list different spells even after the zone holding
  /// a spawn's area is taken: their addresses.
  PagesDisagree(urls: List(String))
}

/// What the rule did with one spawned creature.
pub type Outcome {
  Matched(
    creature_id: Int,
    spawns: Int,
    name: String,
    pages: List(Page),
    autos: List(Auto),
    specials: List(Special),
    left_out: List(SpellLeftOut),
  )
  Unmatched(creature_id: Int, spawns: Int, why: Why)
}

/// What the rule reads: the client's tables, the texts of the creatures' names by text id,
/// the pages, and the creatures whose own `creature_kind` row names their attack.
pub type Inputs {
  Inputs(
    tables: table_store.Tables,
    texts: Dict(Int, String),
    pages: List(Page),
    kind_creature_ids: Set(Int),
  )
}

/// What `plan` builds once for all the creatures.
type Context {
  Context(
    tables: table_store.Tables,
    sources: spell_plan.Sources,
    texts: Dict(Int, String),
    pages_by_name: Dict(String, List(Page)),
    zone_worlds: Dict(Int, Set(Int)),
    zone_world_zone: Dict(Int, Int),
    parents: Dict(Int, Int),
    kind_creature_ids: Set(Int),
  )
}

/// The text of a creature's name as the client shows it: the plural mark `{p:..}` is the
/// text for a stack of the thing, which a creature's name does not use.
pub fn without_plural_marks(text text: String) -> String {
  case string.split_once(text, "{p:") {
    Error(Nil) -> text
    Ok(#(before, rest)) ->
      case string.split_once(rest, "}") {
        Error(Nil) -> text
        Ok(#(_, after)) -> without_plural_marks(text: before <> after)
      }
  }
}

/// The outcome for each spawned creature, in creature id order.
pub fn plan(
  inputs inputs: Inputs,
  spawned spawned: List(Spawned),
) -> List(Outcome) {
  let context =
    Context(
      tables: inputs.tables,
      sources: spell_plan.sources_of(inputs.tables),
      texts: inputs.texts,
      pages_by_name: list.group(inputs.pages, fn(page) { page.name })
        |> dict.map_values(fn(_, pages) { list.reverse(pages) }),
      zone_worlds: list.fold(
        map_zone_world_join.all(inputs.tables),
        dict.new(),
        fn(zones, row) {
          dict.upsert(zones, row.map_zone_id, fn(worlds) {
            set.insert(option.unwrap(worlds, set.new()), row.world_id)
          })
        },
      ),
      zone_world_zone: map_zone.all(inputs.tables)
        |> list.map(fn(row) { #(row.id, row.world_zone_id) })
        |> dict.from_list,
      parents: world_zone.all(inputs.tables)
        |> list.map(fn(row) { #(row.id, row.parent_zone_id) })
        |> dict.from_list,
      kind_creature_ids: inputs.kind_creature_ids,
    )
  list.group(spawned, fn(row) { row.creature_id })
  |> dict.to_list
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(entry) { of_creature(context:, spawned: entry.1) })
}

/// What a creature's pages are: its name and the pages it takes spells from.
type Found {
  Found(name: String, pages: List(Page))
}

fn of_creature(
  context context: Context,
  spawned spawned: List(Spawned),
) -> Outcome {
  let assert [first, ..] = spawned as "a group holds a row"
  let creature_id = first.creature_id
  let spawns = list.fold(spawned, 0, fn(total, row) { total + row.spawns })
  case found_for(context:, creature_id:, spawned:) {
    Error(why) -> Unmatched(creature_id:, spawns:, why:)
    Ok(Found(name:, pages:)) ->
      matched(context:, creature_id:, name:, spawns:, pages:)
  }
}

fn found_for(
  context context: Context,
  creature_id creature_id: Int,
  spawned spawned: List(Spawned),
) -> Result(Found, Why) {
  use creature <- result.try(
    creature2.get(tables: context.tables, id: Creature2Id(creature_id))
    |> result.replace_error(NotInTheClientTable),
  )
  use text <- result.try(
    dict.get(context.texts, creature.localized_text_id_name)
    |> result.replace_error(NoNameInTheClient),
  )
  let name = without_plural_marks(text:)
  use named <- result.try(
    dict.get(context.pages_by_name, name)
    |> result.replace_error(NoPageByName),
  )
  use pages <- result.map(pages_of(context:, spawned:, named:))
  Found(name:, pages:)
}

/// The pages the creature takes its spells from: those of its name with a spawn of its in
/// a world of their zone, and when they list different spells, those whose zone holds a
/// spawn's area.
fn pages_of(
  context context: Context,
  spawned spawned: List(Spawned),
  named named: List(Page),
) -> Result(List(Page), Why) {
  let worlds = set.from_list(list.map(spawned, fn(row) { row.world_id }))
  let in_worlds =
    list.filter(named, fn(page) {
      case dict.get(context.zone_worlds, page.zone) {
        Ok(zone_worlds) -> !set.is_empty(set.intersection(zone_worlds, worlds))
        Error(Nil) -> False
      }
    })
  use <- bool.guard(
    when: list.is_empty(in_worlds),
    return: Error(NoPageInTheCreatureWorlds),
  )
  use <- bool.guard(when: agree(in_worlds), return: Ok(in_worlds))
  let areas = areas_of(context:, spawned:)
  let in_areas =
    list.filter(in_worlds, fn(page) {
      case dict.get(context.zone_world_zone, page.zone) {
        Ok(world_zone_id) -> set.contains(areas, world_zone_id)
        Error(Nil) -> False
      }
    })
  let settled = case in_areas {
    [] -> in_worlds
    [_, ..] -> in_areas
  }
  case agree(settled) {
    True -> Ok(settled)
    False ->
      Error(PagesDisagree(
        list.map(settled, fn(page) { page.url }) |> list.sort(string.compare),
      ))
  }
}

/// Whether the pages list the same spells at the same tiers.
fn agree(pages: List(Page)) -> Bool {
  case list.map(pages, fn(page) { listed(page) }) |> list.unique {
    [_] | [] -> True
    _ -> False
  }
}

fn listed(page: Page) -> List(#(Int, Int)) {
  page.abilities
  |> list.map(fn(ability) { #(ability.spell4_id, ability.tier) })
  |> list.sort(fn(first, second) {
    case int.compare(first.0, second.0) {
      order.Eq -> int.compare(first.1, second.1)
      other -> other
    }
  })
}

/// Every WorldZone a spawn's area is or sits inside.
fn areas_of(
  context context: Context,
  spawned spawned: List(Spawned),
) -> Set(Int) {
  list.fold(spawned, set.new(), fn(areas, row) {
    inside(parents: context.parents, area: row.area_id, areas:, steps: 32)
  })
}

fn inside(
  parents parents: Dict(Int, Int),
  area area: Int,
  areas areas: Set(Int),
  steps steps: Int,
) -> Set(Int) {
  use <- bool.guard(
    when: area == 0 || steps == 0 || set.contains(areas, area),
    return: areas,
  )
  inside(
    parents:,
    area: result.unwrap(dict.get(parents, area), 0),
    areas: set.insert(areas, area),
    steps: steps - 1,
  )
}

/// A spell of the page that is a candidate, with what the rules read of it.
type Listed {
  Listed(ability: Ability, row: spell4.Spell4)
}

fn matched(
  context context: Context,
  creature_id creature_id: Int,
  name name: String,
  spawns spawns: Int,
  pages pages: List(Page),
) -> Outcome {
  let assert [page, ..] = pages as "a creature's pages are not empty"
  let #(found, missing) =
    page.abilities
    |> first_of_each_spell
    |> list.map(fn(ability) {
      case spell4.get(tables: context.tables, id: Spell4Id(ability.spell4_id)) {
        Ok(row) -> Ok(Listed(ability:, row:))
        Error(Nil) -> Error(SpellLeftOut(ability.spell4_id, NoSpellRow))
      }
    })
    |> result.partition
  let is_auto = fn(listed: Listed) {
    string.starts_with(listed.row.description, "[AUTO-ATTACK]")
    && listed.row.cast_time == 0
  }
  let #(auto_candidates, special_candidates) = list.partition(found, is_auto)
  let #(family_left_out, special_candidates) = lowest_tiers(special_candidates)
  let #(autos, autos_left_out) =
    list.map(auto_candidates, fn(listed) {
      auto_loads(context:, creature_id:, listed:)
      |> result.map(fn(_) { listed })
      |> result.map_error(fn(why) {
        SpellLeftOut(listed.ability.spell4_id, why)
      })
    })
    |> result.partition
  let #(specials, specials_left_out) =
    list.map(special_candidates, fn(listed) {
      special_loads(context:, creature_id:, listed:)
      |> result.map(fn(_) { listed })
      |> result.map_error(fn(why) {
        SpellLeftOut(listed.ability.spell4_id, why)
      })
    })
    |> result.partition
  let ordered_autos =
    list.sort(autos, fn(first, second) {
      case int.compare(number_of(first.row), number_of(second.row)) {
        order.Eq ->
          int.compare(first.ability.spell4_id, second.ability.spell4_id)
        other -> other
      }
    })
  Matched(
    creature_id:,
    name:,
    spawns:,
    pages:,
    autos: list.index_map(ordered_autos, fn(listed, index) {
      Auto(
        creature_id:,
        spell4_id: listed.ability.spell4_id,
        order_index: index,
      )
    }),
    specials: list.index_map(specials, fn(listed, index) {
      Special(
        creature_id:,
        spell4_id: listed.ability.spell4_id,
        order_index: index,
        cooldown_ms: special_cooldown_ms,
      )
    }),
    left_out: list.flatten([
      missing,
      family_left_out,
      autos_left_out,
      specials_left_out,
    ]),
  )
}

/// The abilities with a spell listed twice kept once, at its first place.
fn first_of_each_spell(abilities: List(Ability)) -> List(Ability) {
  list.fold(abilities, #([], set.new()), fn(state, ability) {
    case set.contains(state.1, ability.spell4_id) {
      True -> state
      False -> #([ability, ..state.0], set.insert(state.1, ability.spell4_id))
    }
  })
  |> fn(state) { list.reverse(state.0) }
}

/// The other tiers of one family listed, which are not written.
fn lowest_tiers(
  candidates: List(Listed),
) -> #(List(SpellLeftOut), List(Listed)) {
  let lowest =
    list.fold(candidates, dict.new(), fn(lowest, listed) {
      dict.upsert(
        lowest,
        listed.row.spell4_base_id_base_spell,
        fn(found: Option(Listed)) {
          case found {
            Some(before) if before.row.tier_index <= listed.row.tier_index ->
              before
            _ -> listed
          }
        },
      )
    })
  let #(kept, others) =
    list.partition(candidates, fn(listed) {
      dict.get(lowest, listed.row.spell4_base_id_base_spell) == Ok(listed)
    })
  #(
    list.map(others, fn(listed) {
      SpellLeftOut(listed.ability.spell4_id, OtherTierKept)
    }),
    kept,
  )
}

fn auto_loads(
  context context: Context,
  creature_id creature_id: Int,
  listed listed: Listed,
) -> Result(Nil, Refusal) {
  let row =
    creature_auto_attack.Row(
      creature_id:,
      spell4_id: listed.ability.spell4_id,
      order_index: 0,
    )
  case
    creature_auto_attack.refusal_of(
      row:,
      tables: context.tables,
      kind_creature_ids: context.kind_creature_ids,
    )
  {
    Ok(sentence) -> Error(Refused(sentence:))
    Error(Nil) -> Ok(Nil)
  }
}

fn special_loads(
  context context: Context,
  creature_id creature_id: Int,
  listed listed: Listed,
) -> Result(Nil, Refusal) {
  let row =
    creature_special.Row(
      creature_id:,
      spell4_id: listed.ability.spell4_id,
      order_index: 0,
      cooldown_ms: special_cooldown_ms,
    )
  case
    creature_special.refusal_of(
      row:,
      tables: context.tables,
      sources: context.sources,
    )
  {
    Ok(sentence) -> Error(Refused(sentence:))
    Error(Nil) -> Ok(Nil)
  }
}

/// The number the description gives an auto-attack (`Auto-Attack #2`), or a number past any
/// real one for a description with none, so unnumbered ones come last.
fn number_of(row: spell4.Spell4) -> Int {
  case string.split_once(row.description, "#") {
    Ok(#(_, after)) ->
      string.to_graphemes(after)
      |> list.take_while(fn(character) {
        string.contains("0123456789", character)
      })
      |> string.concat
      |> int.parse
      |> result.unwrap(unnumbered)
    Error(Nil) -> unnumbered
  }
}

const unnumbered = 1_000_000

/// The sentence for a refusal.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NoSpellRow -> "the client's Spell4 table has no such spell"
    OtherTierKept ->
      "another tier of its Spell4Base is listed, and the lowest tier is the one kept"
    Refused(sentence:) -> sentence
  }
}

/// The sentence of a refusal with its numbers replaced by `N`, so spells left out by one
/// rule are counted together; the special check's prefix naming the spell and the creature
/// is left off.
pub fn rule_of(refusal refusal: Refusal) -> String {
  let sentence = describe(refusal:)
  let named_by_the_load =
    string.starts_with(sentence, "the special Spell4 ")
    || string.starts_with(sentence, "the auto-attack Spell4 ")
  let rule = case named_by_the_load {
    True ->
      case string.split_once(sentence, ": ") {
        Ok(#(_, rest)) -> rest
        Error(Nil) -> sentence
      }
    False -> sentence
  }
  string.to_graphemes(rule)
  |> list.fold(#([], False), fn(state, character) {
    let #(kept, in_number) = state
    case string.contains("0123456789", character) {
      True ->
        case in_number {
          True -> state
          False -> #(["N", ..kept], True)
        }
      False -> #([character, ..kept], False)
    }
  })
  |> fn(state) { list.reverse(state.0) }
  |> string.concat
}
