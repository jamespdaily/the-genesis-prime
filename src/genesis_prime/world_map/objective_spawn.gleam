//// The creatures a kill objective needs and the stored spawn table does not
//// hold: for each kill objective with a marker (QuestObjective types 2, 8 and
//// 16, whose worldLocationsIdIndicator00 to 03 name WorldLocation2 circles) in a
//// world the server holds spawns for (a world one stored row is in), a creature
//// with no stored spawn in the marker's world stands in the circle, as many as
//// the objective counts, so the player sees it, kills it and the objective
//// counts. The rows are placed once at the start, beside the stored
//// ones, and the map starts them as it starts a stored row (`spawn.select`).
////
//// - The client's tables set what is needed: type 2's data is a Creature2 id,
////   types 8 and 16's a TargetGroup whose creatures count (`target_group`), and
////   the marker is the circle the quest pane shows (`WorldLocation2.position0`
////   to 2, `radius`, facing0 to 3 a quaternion read as `start_place` does).
//// - The tutorial's markers show where the client wants the creatures
////   (`WorldLocation2.npe_battle_markers`). The client lifts a unit onto the
////   ground when it is at most 2 units below it and draws it at the height sent
////   above it, and it gives the server no ground height
////   (`unit.ground_lift`, `terrain_height.server_view`), so a creature stands at
////   its marker's height.
//// - Where a creature stands in the circle, and which creature of a group takes
////   which place, are the server's choice. The objective's count is dealt to
////   its markers one at a time in column order; a marker that gets one stands
////   it at its centre with its facing, and one that gets k stands them on the
////   circle of half its radius at the angles 2 pi s / k from the +x axis
////   towards +z, each facing the centre. The creatures of a group are dealt to
////   the places in that order and in the group's order, cycling. An objective
////   whose markers lie in different worlds is placed in each world with its
////   whole count; objectives of the same creatures and markers are placed once
////   with the largest count.
//// - A creature stands with what `spawn.creature_row` gives its Creature2 row:
////   the unit type (entity type 13 for a turret creature), the faction, the first
////   display and outfit of its groups, no stored health and its minLevel.
//// - A placed row takes an id above every stored one, counting up. No saved
////   table keys on a spawn id but `spawn_stat` (its own `spawn_id` column,
////   content that only a stored row has), so a placed row's id is the map's
////   alone, and its creature respawns at its place as a stored row's does.
////
//// A pair that is not placed is reported once at the start (`Skipped`): a
//// creature with no Creature2 row, a group that lists no creature, a marker with
//// no WorldLocation2 row, a marker in a world with no stored spawn and a turret
//// creature with no creature_kind row. Kill
//// types 15 and 46 and the tutorial's other objective types name no creature to
//// place here.
////
//// The creatures of a click objective (QuestObjective types 5 and 32, whose
//// creature `objective_link.links` ties to the objective) are placed the same
//// way (`Placed.click_rows`), where no stored row serves the marker: every
//// stored row of the creature, whatever its unit type, serves the one marker of
//// the creature's objectives that it stands nearest to in its own world (a tie
//// goes to the lower marker id), and each marker no row serves gets the creature
//// at its centre, height and facing, as the unit type its CreationTypeEnum pairs
//// with (the same number, but 19 for 18 and 32 for 20, as the world database
//// stores them).
//// Several creatures at one marker stand on its half-radius ring in creature id
//// order. The click rows are numbered after the kill rows. A pair is skipped and
//// reported (`click_skipped`) for a marker with no WorldLocation2 row, a marker
//// in a world with no stored spawn, and a creature whose unit type
//// `spawn.select` does not start (`spawn.starts_entity_type`). A link of a creature
//// that names no objective is reported too (`unread_links`): a quest with no
//// Quest2 row, an index the quest has no objective at, or a quest slot with no
//// QuestObjective row; a link to an objective of another type names none to place
//// and is not. A placed creature stays after it is used.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/objective
import genesis_prime/game/objective_link
import genesis_prime/game/place_objective
import genesis_prime/game/quest_log
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/game/target_group
import genesis_prime/message/float32
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/id.{Creature2Id, QuestObjectiveId, WorldLocation2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective.{type QuestObjective}
import genesis_prime/table/world_location2.{type WorldLocation2}
import genesis_prime/world_map/creature_faction.{type Factions}
import genesis_prime/world_map/creature_kind.{type Kinds}
import genesis_prime/world_map/creature_unit_type.{NonPlayer, Turret}
import genesis_prime/world_map/spawn.{type Row}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam_community/maths

/// The rows placed, in the order of the objectives that need them, and the pairs
/// that were not.
pub type Placed {
  Placed(
    rows: List(Row),
    skipped: List(Skipped),
    click_rows: List(Row),
    click_skipped: List(Skipped),
    unread_links: List(UnreadLink),
  )
}

/// A click link of a creature that names no objective the tables hold, and why.
pub type UnreadLink {
  UnreadLink(creature_id: Int, quest_id: Int, index: Int, why: LinkWhy)
}

/// Why a creature's link names no objective.
pub type LinkWhy {
  /// The client has no Quest2 row for the quest.
  NoQuestRow
  /// The quest has no objective at the index: past its last, or below 0.
  NoObjectiveAtIndex
  /// A slot of the quest names a QuestObjective row the client's table lacks.
  NoObjectiveRow(objective_id: Int)
}

/// An objective's creature or marker that was left out, and why.
pub type Skipped {
  Skipped(objective_id: Int, why: Why)
}

/// Why a creature or a marker was left out.
pub type Why {
  /// The creature has no Creature2 row.
  NoCreatureRow(creature_id: Int)
  /// The objective's TargetGroup has no row or lists no creature.
  NamesNoCreature(group_id: Int)
  /// The marker has no WorldLocation2 row.
  NoMarkerRow(marker_id: Int)
  /// The marker is in a world the server holds no stored spawn for.
  NoSpawnsInWorld(marker_id: Int, world_id: Int)
  /// The creature's row makes it a turret (Creature2.creationTypeEnum 13) and the
  /// server has no creature_kind row for it, so it would stand as a static object.
  TurretHasNoKind(creature_id: Int)
  /// The unit type the creature's CreationTypeEnum pairs with is one the server does
  /// not start (`spawn.select`).
  NotStarted(creature_id: Int, unit_type: Int)
}

/// The objective types of a kill that names a creature or a group of them, with
/// a marker: 2 names a Creature2 id, 8 and 16 a TargetGroup.
fn is_placed_kind(objective objective: QuestObjective) -> Bool {
  objective.type_ == 2 || objective.type_ == 8 || objective.type_ == 16
}

/// A marker of an objective: its row and the place its centre is.
type Marker {
  Marker(row: WorldLocation2, place: Place)
}

/// What one objective asks for, as far as the tables let it: the creatures with
/// a Creature2 row, the markers with a row in a world with a stored spawn, and its
/// count.
/// `key` is the creature ids and the marker ids it names, each sorted, which two
/// objectives that ask the same thing share.
type Job {
  Job(
    key: #(List(Int), List(Int)),
    creatures: List(Creature2),
    markers: List(Marker),
    count: Int,
  )
}

/// The rows to stand for the kill objectives, given the rows the stored spawn
/// table holds: only a marker in a world one of them is in gets creatures, and a
/// creature a stored spawn of that world already stands as a creature (`held_by`)
/// is left to it. A creature stands with its chosen faction when it has one
/// (`factions`), and as the unit type its Creature2 row gives it; a turret creature
/// with no kind of its own is left out (`TurretHasNoKind`), since no server fight
/// would run it.
/// Pure: the tables, the chosen factions, the kinds and the stored rows are all it reads.
pub fn place(
  tables tables: table_store.Tables,
  stored stored: List(Row),
  factions factions: Factions,
  kinds kinds: Kinds,
) -> Placed {
  let objectives =
    quest_objective.all(tables)
    |> list.filter(fn(objective) { is_placed_kind(objective:) })
  let worlds = set.from_list(list.map(stored, fn(row) { row.world_id }))
  let planned =
    list.map(objectives, fn(objective) {
      plan(tables:, worlds:, kinds:, objective:)
    })
  let skipped =
    planned
    |> list.flat_map(fn(pair) { pair.1 })
    |> list.unique
  let jobs =
    planned
    |> list.filter_map(fn(pair) { option.to_result(pair.0, Nil) })
    |> merged
  let held = held_by(stored:, kinds:)
  let looks = spawn.looks(tables:)
  let rows =
    list.flat_map(jobs, fn(job) { rows_of(job:, held:, looks:, factions:) })
  let first = highest_id(stored:) + 1
  let rows =
    list.index_map(rows, fn(row, index) {
      spawn.Row(..row, id: SpawnId(first + index))
    })
  let #(click_rows, click_skipped, unread_links) =
    click_placed(
      tables:,
      worlds:,
      stored:,
      factions:,
      first: first + list.length(rows),
    )
  Placed(rows:, skipped:, click_rows:, click_skipped:, unread_links:)
}

/// An objective's marker a creature is linked to (`objective_link.links`): the
/// creature stands there for the objective's use to count.
type Want {
  Want(objective_id: Int, creature: Creature2, marker_id: Int, marker: Marker)
}

/// The objective types a use counts for (`objective.counts`): the scripted and the
/// collectible objective.
fn is_click_kind(objective held: quest_log.Objective) -> Bool {
  held.type_ == objective.scripted_type
  || held.type_ == objective.collectible_type
}

/// The rows to stand for the click targets, from id `first` up, and the pairs that
/// were not placed. Every creature that `objective_link.links` ties to a type 5 or 32
/// objective with a marker is wanted at each marker. A stored row of the creature of
/// any unit type serves the one marker it stands nearest in its own world, and a
/// marker no row serves gets the creature at its centre, as the unit type its
/// CreationTypeEnum pairs with (`paired_unit_type`), several creatures of one marker
/// on its half-radius ring in creature-id order. A pair of a marker with no row or
/// no stored spawn in its world is skipped as the kill path skips it, and one whose
/// unit type the server does not start is skipped as `NotStarted`.
fn click_placed(
  tables tables: table_store.Tables,
  worlds worlds: Set(Int),
  stored stored: List(Row),
  factions factions: Factions,
  first first: Int,
) -> #(List(Row), List(Skipped), List(UnreadLink)) {
  let #(pairs, unread_links) = click_pairs(tables:)
  let #(wants, marker_skips) =
    list.map(pairs, fn(pair) {
      let #(objective_id, creature, marker_id) = pair
      case marker_of(tables:, worlds:, marker_id:) {
        Ok(marker) -> Ok(Want(objective_id:, creature:, marker_id:, marker:))
        Error(why) -> Error(Skipped(objective_id, why))
      }
    })
    |> partitioned
  let served = served_by(stored:, wants:)
  let unserved =
    list.filter(wants, fn(want) {
      !set.contains(served, #(want.creature.id, want.marker_id))
    })
  let #(started, unstarted) =
    list.partition(unserved, fn(want) {
      spawn.starts_entity_type(entity_type: paired_unit_type(
        creature: want.creature,
      ))
    })
  let not_started =
    list.map(unstarted, fn(want) {
      Skipped(
        want.objective_id,
        NotStarted(
          creature_id: want.creature.id,
          unit_type: paired_unit_type(creature: want.creature),
        ),
      )
    })
  let looks = spawn.looks(tables:)
  let rows =
    started
    |> list.sort(fn(a, b) {
      int.compare(a.marker_id, b.marker_id)
      |> order.break_tie(int.compare(a.creature.id, b.creature.id))
    })
    |> once_each
    |> list.chunk(fn(want) { want.marker_id })
    |> list.flat_map(fn(group) {
      let slots = list.length(group)
      list.index_map(group, fn(want, slot) {
        spawn.Row(
          ..spawn.creature_row(
            looks:,
            factions:,
            id: SpawnId(0),
            creature: want.creature,
            place: slot_place(marker: want.marker, slot:, slots:),
            level: None,
          ),
          entity_type: paired_unit_type(creature: want.creature),
        )
      })
    })
    |> list.index_map(fn(row, index) {
      spawn.Row(..row, id: SpawnId(first + index))
    })
  #(rows, list.unique(list.append(marker_skips, not_started)), unread_links)
}

/// Every (objective, creature, marker) a creature's link and its objective's markers
/// name, over the objectives of types 5 and 32, in creature order, and the links that
/// name no objective the tables hold (the index counts the quest's filled slots, as
/// `objective.counts` reads it). A link to an objective of another type is no pair and
/// is not reported.
fn click_pairs(
  tables tables: table_store.Tables,
) -> #(List(#(Int, Creature2, Int)), List(UnreadLink)) {
  let linked =
    creature2.all(tables)
    |> list.filter(fn(creature) { objective_link.has_link(row: creature) })
    |> list.map(fn(creature) {
      let links =
        objective_link.links(tables:, creature_id: Creature2Id(creature.id))
        |> list.map(fn(link) { #(link, click_objective(tables:, link:)) })
      let pairs =
        list.filter_map(links, fn(entry) {
          case entry.1 {
            Ok(Ok(objective)) -> Ok(objective)
            Ok(Error(Nil)) | Error(_) -> Error(Nil)
          }
        })
        |> list.unique
        |> list.flat_map(fn(objective) {
          place_objective.marker_ids(objective:)
          |> list.map(fn(marker_id) { #(objective.id, creature, marker_id) })
        })
      let unread =
        list.filter_map(links, fn(entry) {
          let #(#(quest_id, index), read) = entry
          case read {
            Error(why) ->
              Ok(UnreadLink(creature_id: creature.id, quest_id:, index:, why:))
            Ok(_) -> Error(Nil)
          }
        })
      #(pairs, unread)
    })
  #(
    list.flat_map(linked, fn(entry) { entry.0 }),
    list.flat_map(linked, fn(entry) { entry.1 }),
  )
}

/// The objective at the index of the quest when a use counts for its type, `Error(Nil)`
/// inside when the objective is of another type, and why the tables name none.
fn click_objective(
  tables tables: table_store.Tables,
  link link: #(Int, Int),
) -> Result(Result(QuestObjective, Nil), LinkWhy) {
  let #(quest_id, index) = link
  use quest <- result.try(
    quest_log.quest_of(tables:, id: quest_id)
    |> result.map_error(fn(error) {
      case error {
        quest_log.NoQuestRow -> NoQuestRow
        quest_log.NoObjectiveRow(objective_id:) -> NoObjectiveRow(objective_id:)
      }
    }),
  )
  // `list.drop` with a negative count keeps the whole list.
  use objective <- result.try(
    case index < 0 {
      True -> Error(Nil)
      False -> list.drop(quest.objectives, index) |> list.first
    }
    |> result.replace_error(NoObjectiveAtIndex),
  )
  case is_click_kind(objective:) {
    False -> Ok(Error(Nil))
    True ->
      quest_objective.get(tables:, id: QuestObjectiveId(objective.objective_id))
      |> result.replace_error(NoObjectiveRow(
        objective_id: objective.objective_id,
      ))
      |> result.map(Ok)
  }
}

/// The (creature, marker) pairs the stored rows serve: each row serves the nearest
/// marker of its creature's wants in its own world, in (x, z), the lower marker id
/// on a tie.
fn served_by(
  stored stored: List(Row),
  wants wants: List(Want),
) -> Set(#(Int, Int)) {
  let by_creature = list.group(wants, fn(want) { want.creature.id })
  list.filter_map(stored, fn(row) {
    use held <- result.try(dict.get(by_creature, row.creature_id))
    use want <- result.map(nearest(row:, wants: held))
    #(row.creature_id, want.marker_id)
  })
  |> set.from_list
}

/// The want whose marker is in the row's world and nearest it in (x, z), the lowest
/// marker id first so that a tie keeps it.
fn nearest(row row: Row, wants wants: List(Want)) -> Result(Want, Nil) {
  let distance = fn(want: Want) {
    let dx = row.x -. start_place.x(want.marker.place)
    let dz = row.z -. start_place.z(want.marker.place)
    dx *. dx +. dz *. dz
  }
  wants
  |> list.filter(fn(want) { want.marker.row.world_id == row.world_id })
  |> list.sort(fn(a, b) { int.compare(a.marker_id, b.marker_id) })
  |> list.fold(Error(Nil), fn(best, want) {
    case best {
      Ok(held) ->
        case distance(want) <. distance(held) {
          True -> Ok(want)
          False -> best
        }
      Error(Nil) -> Ok(want)
    }
  })
}

/// The wants, sorted, with each (creature, marker) once: two objectives that name the
/// same pair place one row.
fn once_each(wants wants: List(Want)) -> List(Want) {
  list.fold(wants, #([], set.new()), fn(state, want) {
    let #(kept, seen) = state
    let key = #(want.creature.id, want.marker_id)
    case set.contains(seen, key) {
      True -> state
      False -> #([want, ..kept], set.insert(seen, key))
    }
  }).0
  |> list.reverse
}

/// The unit type a creature stands as at a click marker: its CreationTypeEnum, but
/// 18 (BindPoint) is unit type 19 and 20 (SimpleCollidable) is unit type 32, which
/// the world database stores as it does (`static_unit_type`).
fn paired_unit_type(creature creature: Creature2) -> Int {
  case creature.creation_type_enum {
    18 -> 19
    20 -> 32
    other -> other
  }
}

/// What the objective asks for and what is wrong with it. An objective with no
/// marker asks for nothing and is not reported: it is no pair.
fn plan(
  tables tables: table_store.Tables,
  worlds worlds: Set(Int),
  kinds kinds: Kinds,
  objective objective: QuestObjective,
) -> #(option.Option(Job), List(Skipped)) {
  let marker_ids = place_objective.marker_ids(objective:)
  case marker_ids {
    [] -> #(None, [])
    _ -> {
      let creature_ids = case objective.type_ {
        2 -> [objective.data]
        _ -> target_group.listed_creatures(tables:, group: objective.data)
      }
      let no_group = case creature_ids {
        [] -> [Skipped(objective.id, NamesNoCreature(group_id: objective.data))]
        _ -> []
      }
      let #(found, rowless) =
        list.map(creature_ids, fn(creature_id) {
          creature2.get(tables, Creature2Id(creature_id))
          |> result.replace_error(creature_id)
        })
        |> partitioned
      let #(rows, kindless) =
        list.partition(found, fn(creature) {
          !is_unrun_turret(creature:, kinds:)
        })
      let no_rows =
        list.append(
          list.map(rowless, fn(creature_id) {
            Skipped(objective.id, NoCreatureRow(creature_id:))
          }),
          list.map(kindless, fn(creature) {
            Skipped(objective.id, TurretHasNoKind(creature_id: creature.id))
          }),
        )
      let #(markers, marker_skips) =
        list.map(marker_ids, fn(marker_id) {
          marker_of(tables:, worlds:, marker_id:)
          |> result.map_error(fn(why) { Skipped(objective.id, why) })
        })
        |> partitioned
      let job = case rows, markers {
        [], _ | _, [] -> None
        _, _ ->
          option.Some(Job(
            key: #(
              list.sort(creature_ids, int.compare),
              list.sort(marker_ids, int.compare),
            ),
            creatures: rows,
            markers:,
            count: objective.count,
          ))
      }
      #(job, list.flatten([no_group, no_rows, marker_skips]))
    }
  }
}

/// The values and the errors of the results, each in the order given
/// (`result.partition` reverses them).
fn partitioned(results results: List(Result(a, e))) -> #(List(a), List(e)) {
  let #(values, errors) = result.partition(results)
  #(list.reverse(values), list.reverse(errors))
}

/// The marker, or why it cannot hold a creature: no row, or a world no stored
/// spawn is in (a row in world 0 is none either, and no stored spawn is in it).
fn marker_of(
  tables tables: table_store.Tables,
  worlds worlds: Set(Int),
  marker_id marker_id: Int,
) -> Result(Marker, Why) {
  use row <- result.try(
    world_location2.get(tables:, id: WorldLocation2Id(marker_id))
    |> result.replace_error(NoMarkerRow(marker_id:)),
  )
  let no_spawns = NoSpawnsInWorld(marker_id:, world_id: row.world_id)
  use <- bool.guard(
    when: !set.contains(worlds, row.world_id),
    return: Error(no_spawns),
  )
  use place <- result.try(
    start_place.of_row(row:) |> result.replace_error(no_spawns),
  )
  Ok(Marker(row:, place:))
}

/// The jobs with those that ask the same thing made one, the largest count kept,
/// in the order of the first.
fn merged(jobs jobs: List(Job)) -> List(Job) {
  list.fold(jobs, [], fn(kept: List(Job), job: Job) {
    case list.any(kept, fn(other: Job) { other.key == job.key }) {
      True ->
        list.map(kept, fn(other: Job) {
          case other.key == job.key {
            True -> Job(..other, count: int.max(other.count, job.count))
            False -> other
          }
        })
      False -> [job, ..kept]
    }
  })
  |> list.reverse
}

/// Whether the creature's row makes it a turret (`creature_unit_type.of_creation_type`) the
/// server has no kind for: it would stand as a static object, not fight.
fn is_unrun_turret(creature creature: Creature2, kinds kinds: Kinds) -> Bool {
  case
    creature_unit_type.of_creation_type(
      creation_type: creature.creation_type_enum,
    )
  {
    Turret -> !dict.has_key(kinds.by_creature, creature.id)
    NonPlayer -> False
  }
}

/// The (world, creature) pairs a stored spawn that starts as a creature stands (a
/// non-player row, or a turret row whose creature has a kind of its own: `spawn.select`).
/// A stored row that is a static object stands no creature, so it holds none.
pub fn held_by(
  stored stored: List(Row),
  kinds kinds: Kinds,
) -> Set(#(Int, Int)) {
  list.filter(stored, fn(row) {
    result.is_ok(spawn.creature_unit_type_of(kinds:, row:))
  })
  |> list.map(fn(row) { #(row.world_id, row.creature_id) })
  |> set.from_list
}

/// The highest stored id, 0 when none is stored.
fn highest_id(stored stored: List(Row)) -> Int {
  list.fold(stored, 0, fn(highest, row) { int.max(highest, number_of(row:)) })
}

/// The rows of one job, world by world in the order its markers first show them.
fn rows_of(
  job job: Job,
  held held: Set(#(Int, Int)),
  looks looks: spawn.Looks,
  factions factions: Factions,
) -> List(Row) {
  job.markers
  |> list.map(fn(marker) { marker.row.world_id })
  |> list.unique
  |> list.flat_map(fn(world_id) {
    let creatures =
      list.filter(job.creatures, fn(creature) {
        !set.contains(held, #(world_id, creature.id))
      })
    let markers =
      list.filter(job.markers, fn(marker) { marker.row.world_id == world_id })
    rows_in_world(creatures:, markers:, count: job.count, looks:, factions:)
  })
}

/// The rows of one world: the count dealt to the markers one at a time, and the
/// creatures to the places in that order, cycling.
fn rows_in_world(
  creatures creatures: List(Creature2),
  markers markers: List(Marker),
  count count: Int,
  looks looks: spawn.Looks,
  factions factions: Factions,
) -> List(Row) {
  let creature_count = list.length(creatures)
  let marker_count = list.length(markers)
  let by_turn =
    dict.from_list(
      list.index_map(creatures, fn(creature, turn) { #(turn, creature) }),
    )
  case creature_count, marker_count {
    0, _ | _, 0 -> []
    _, _ ->
      list.index_map(markers, fn(marker, index) {
        let slots =
          count
          / marker_count
          + case index < count % marker_count {
            True -> 1
            False -> 0
          }
        list.repeat(Nil, slots)
        |> list.index_map(fn(_, slot) { slot })
        |> list.filter_map(fn(slot) {
          // The place the count's dealing gives this slot: marker `index` is
          // dealt places index, index + markers, index + 2 markers, ...
          let turn = index + slot * marker_count
          use creature <- result.map(dict.get(by_turn, turn % creature_count))
          spawn.creature_row(
            looks:,
            factions:,
            id: SpawnId(0),
            creature:,
            place: slot_place(marker:, slot:, slots:),
            level: None,
          )
        })
      })
      |> list.flatten
  }
}

/// The place of slot `slot` of the `slots` a marker holds: the marker's own
/// place for one, else a point of the circle of half its radius, facing the
/// centre. Positions and the facing are 32-bit floats, as a row's are.
fn slot_place(
  marker marker: Marker,
  slot slot: Int,
  slots slots: Int,
) -> Place {
  case slots {
    1 -> marker.place
    _ -> {
      let angle = 2.0 *. maths.pi() *. int.to_float(slot) /. int.to_float(slots)
      let reach = marker.row.radius /. 2.0
      let centre = marker.place
      start_place.moved(
        place: centre,
        x: float32.rounded(start_place.x(centre) +. reach *. maths.cos(angle)),
        y: start_place.y(centre),
        z: float32.rounded(start_place.z(centre) +. reach *. maths.sin(angle)),
      )
      |> start_place.turned(
        // The unit faces (-sin yaw, -cos yaw) in (x, z): towards the centre, from
        // the circle's point at `angle`, that is (-cos angle, -sin angle).
        facing: Facing(
          yaw: float32.rounded(maths.atan2(maths.cos(angle), maths.sin(angle))),
          pitch: 0.0,
          roll: 0.0,
        ),
      )
    }
  }
}

/// The sentence for the log that says what a skipped pair lacked.
fn describe(noun noun: String, skipped skipped: Skipped) -> String {
  let objective = noun <> " " <> int.to_string(skipped.objective_id)
  case skipped.why {
    NoCreatureRow(creature_id:) ->
      objective
      <> " names Creature2 "
      <> int.to_string(creature_id)
      <> ", which the client's table has no row of"
    NamesNoCreature(group_id:) ->
      objective
      <> "'s TargetGroup "
      <> int.to_string(group_id)
      <> " lists no creature"
    NoMarkerRow(marker_id:) ->
      objective
      <> "'s marker "
      <> int.to_string(marker_id)
      <> " has no WorldLocation2 row"
    NoSpawnsInWorld(marker_id:, world_id:) ->
      objective
      <> "'s marker "
      <> int.to_string(marker_id)
      <> " is in World "
      <> int.to_string(world_id)
      <> ", where the server holds no stored spawn"
    TurretHasNoKind(creature_id:) ->
      objective
      <> " names Creature2 "
      <> int.to_string(creature_id)
      <> ", a turret the server has no creature_kind row of"
    NotStarted(creature_id:, unit_type:) ->
      objective
      <> " names Creature2 "
      <> int.to_string(creature_id)
      <> ", which stands as unit type "
      <> int.to_string(unit_type)
      <> ", one the server does not start"
  }
}

/// The sentence for the log that says what a creature's link to an objective lacked.
fn describe_link(link link: UnreadLink) -> String {
  let from =
    "click link of Creature2 "
    <> int.to_string(link.creature_id)
    <> " to Quest2 "
    <> int.to_string(link.quest_id)
    <> " index "
    <> int.to_string(link.index)
  case link.why {
    NoQuestRow -> from <> ": the client's table has no row of the quest"
    NoObjectiveAtIndex -> from <> ": the quest has no objective at the index"
    NoObjectiveRow(objective_id:) ->
      from
      <> ": the quest names QuestObjective "
      <> int.to_string(objective_id)
      <> ", which the client's table has no row of"
  }
}

/// The lines the start logs of a placement: how many creatures it placed for the
/// kill objectives, then each kill pair it skipped, then the same for the click
/// objectives.
pub fn report(placed placed: Placed) -> List(String) {
  list.flatten([
    [
      "kill objectives: placed "
      <> int.to_string(list.length(placed.rows))
      <> " creatures with no stored spawn in their marker's world, skipped "
      <> int.to_string(list.length(placed.skipped))
      <> " pairs",
    ],
    list.map(placed.skipped, fn(skipped) {
      describe(noun: "kill objective", skipped:)
    }),
    [
      "click objectives: placed "
      <> int.to_string(list.length(placed.click_rows))
      <> " creatures with no stored spawn at their marker, skipped "
      <> int.to_string(list.length(placed.click_skipped))
      <> " pairs and "
      <> int.to_string(list.length(placed.unread_links))
      <> " links that name no objective",
    ],
    list.map(placed.click_skipped, fn(skipped) {
      describe(noun: "click objective", skipped:)
    }),
    list.map(placed.unread_links, fn(link) { describe_link(link:) }),
  ])
}

/// The selection's refusals with those of placed rows named as such: a refusal
/// of a row whose id is one this placement gave names the table
/// "kill objective placement" or "click target placement" and the creature, the
/// world and the id, since no database holds a placed row's id. The others are
/// kept. Pass only the selection's own refusals, whose numbered rows are the spawn
/// rows.
pub fn labelled(
  refusals refusals: List(Refusal),
  placed placed: Placed,
) -> List(Refusal) {
  let by_number =
    list.append(
      list.map(placed.rows, fn(row) {
        #(number_of(row:), #("kill objective placement", row))
      }),
      list.map(placed.click_rows, fn(row) {
        #(number_of(row:), #("click target placement", row))
      }),
    )
    |> dict.from_list
  list.map(refusals, fn(refused) {
    case refused.row {
      refusal.RowId(id:) ->
        case dict.get(by_number, id) {
          Ok(#(table, row)) ->
            refusal.Refusal(
              ..refused,
              table:,
              row: refusal.RowName(
                name: "Creature2 "
                <> int.to_string(row.creature_id)
                <> " placed in World "
                <> int.to_string(row.world_id)
                <> " as spawn id "
                <> int.to_string(id),
              ),
            )
          Error(Nil) -> refused
        }
      refusal.RowName(..) -> refused
    }
  })
}

fn number_of(row row: Row) -> Int {
  let SpawnId(number) = row.id
  number
}
