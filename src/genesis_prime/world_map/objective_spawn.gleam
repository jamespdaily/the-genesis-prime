//// The creatures a kill objective needs and the stored spawn table does not
//// hold: for each kill objective with a marker (QuestObjective types 2, 8 and
//// 16, and the type 5 rows of the kill table, whose reward pane is the group;
//// worldLocationsIdIndicator00 to 03 name WorldLocation2 circles) in a
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
////   (`unit.ground_lift`, `terrain_height.server_view`), so the server sends
////   the height: the marker's own at its centre (the ground there, where the
////   marker is on the ground), and on its ring the ground the server reads
////   (`terrain.height_at`) at the slot when the marker's centre stands on the
////   ground (its height within the client's lift of 2 of the ground read at the
////   centre) and that read is within the ring's radius plus 2 of the marker's
////   height, the server's choice for the ground of a slope no steeper than 45
////   degrees from the centre. A marker below or above the ground at its centre
////   (an interior, a cave, a prop) keeps its own height at every slot, and so does
////   a slot the ground has no read at or whose read is outside that band (a pit, a
////   cliff, terrain under props).
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
//// - Objectives that share a marker place one set of creatures there (a server
////   choice: the client's tables name no place for a creature). A marker stands
////   the creatures the first objective deals it, then of each later objective
////   those it deals more of than the marker holds, so each objective keeps what
////   it asked of the marker, a creature two objectives ask of it stands once (the
////   larger number), and the creatures of one marker, the click targets of the
////   marker after them, fill one ring, no two on one place.
//// - A creature stands with what `spawn.creature_row` gives its Creature2 row:
////   the unit type (entity type 13 for a turret creature), the faction, the first
////   display and outfit of its groups, no stored health and its minLevel.
//// - A placed row's id is `first_placed_id` plus the rank of its kind (kill or click),
////   marker, creature and nth row of that creature at that marker (`rank_space`), fixed by
////   the client's tables alone, so no stored row added or deleted moves it and a quest's
////   used objects of it (genesis_prime/game/quest_log) are kept across a login and a
////   re-import. The load refuses a stored row whose id is at or above `first_placed_id`
////   (`refusals`). The other saved table that keys on a spawn id is `spawn_stat` (its own
////   `spawn_id` column, content that only a stored row has). Its creature respawns at its
////   place as a stored row's does.
////
//// A pair that is not placed is reported once at the start (`Skipped`): a
//// creature with no Creature2 row, a group that lists no creature, a marker with
//// no WorldLocation2 row, a marker in a world with no stored spawn and a turret
//// creature with no creature_kind row. Kill
//// types 15 and 46 and the tutorial's other objective types name no creature to
//// place here.
////
//// The creatures of a click objective (QuestObjective types 5 and 32, whose
//// creature `objective_link.links` ties to the objective, and the type 5 rows of the
//// click table, whose reward pane's creatures the client offers a click on,
//// `activate.offers_click`) are placed the same
//// way (`Placed.click_rows`), where no stored row serves the marker: every
//// stored row of the creature, whatever its unit type, serves the one marker of
//// the creature's objectives that it stands nearest to in its own world (a tie
//// goes to the lower marker id), and each marker no row serves gets the creature
//// at its centre, height and facing, as the unit type its CreationTypeEnum pairs
//// with (the same number, but 19 for 18 and 32 for 20, as the world database
//// stores them).
//// Several creatures at one marker stand on its half-radius ring in creature id
//// order, after the kill creatures of the marker. The click rows are numbered after the kill rows. A pair is skipped and
//// reported (`click_skipped`) for a marker with no WorldLocation2 row, a marker
//// in a world with no stored spawn, and a creature whose unit type
//// `spawn.select` does not start (`spawn.starts_entity_type`). A link of a creature
//// that names no objective is reported too (`unread_links`): a quest with no
//// Quest2 row, an index the quest has no objective at, or a quest slot with no
//// QuestObjective row; a link to an objective of another type names none to place
//// and is not. A placed creature stays after it is used.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/activate
import genesis_prime/game/objective_kind
import genesis_prime/game/objective_link
import genesis_prime/game/place_objective
import genesis_prime/game/quest_log
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/game/target_group
import genesis_prime/gap
import genesis_prime/message/float32
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/id.{Creature2Id, QuestObjectiveId, WorldLocation2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective.{type QuestObjective}
import genesis_prime/table/world_location2.{type WorldLocation2}
import genesis_prime/terrain.{type Ground}
import genesis_prime/world_map/creation_type
import genesis_prime/world_map/creature_faction.{type Factions}
import genesis_prime/world_map/creature_kind.{type Kinds}
import genesis_prime/world_map/creature_unit_type.{NonPlayer, Turret}
import genesis_prime/world_map/spawn.{type Row}
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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

/// A marker of an objective: its row and the place its centre is.
type Marker {
  Marker(row: WorldLocation2, place: Place)
}

/// What one objective asks for, as far as the tables let it: the creatures with
/// a Creature2 row, the markers with a row in a world with a stored spawn, and its
/// count.
type Job {
  Job(creatures: List(Creature2), markers: List(Marker), count: Int)
}

/// The rows to stand for the kill objectives, given the rows the stored spawn
/// table holds: only a marker in a world one of them is in gets creatures, and a
/// creature a stored spawn of that world already stands as a creature (`held_by`)
/// is left to it. A creature stands with its chosen faction when it has one
/// (`factions`), and as the unit type its Creature2 row gives it; a turret creature
/// with no kind of its own is left out (`TurretHasNoKind`), since no server fight
/// would run it.
/// `kills` is the kill table's objectives (genesis_prime/game/kill_objective), whose reward
/// pane names the creatures to place as a type 8 or 16 objective's data does, and `clicks`
/// the click table's (genesis_prime/game/click_objective), whose pane's clickable creatures
/// stand at the marker as a linked creature does. Both sets hold type 5 objectives only: a
/// placed spawn's id is the rank of its kind, marker and creature, and the ranks are worked
/// out for the type 5 objectives, so another type's objective in either set crashes the
/// placement.
/// Pure: the tables, the chosen factions, the kinds, the two tables and the stored rows are
/// all it reads.
pub fn place(
  tables tables: table_store.Tables,
  stored stored: List(Row),
  factions factions: Factions,
  kinds kinds: Kinds,
  kills kills: Set(Int),
  clicks clicks: Set(Int),
  grounds grounds: Dict(Int, Ground),
) -> Placed {
  let worlds = set.from_list(list.map(stored, fn(row) { row.world_id }))
  let planned = planned_jobs(tables:, kills:, worlds:, kinds: Some(kinds))
  let skipped =
    planned
    |> list.flat_map(fn(pair) { pair.1 })
    |> list.unique
  let jobs =
    planned
    |> list.filter_map(fn(pair) { option.to_result(pair.0, Nil) })
  let held = held_by(stored:, kinds:)
  let looks = spawn.looks(tables:)
  let stands =
    jobs
    |> list.flat_map(fn(job) { stands_of(job:, held:) })
    |> combined
  let #(click_stands, click_skipped, unread_links) =
    click_stands(tables:, clicks:, worlds:, stored:)
  let sizes = ring_sizes(stands:, click_stands:)
  let ranks = rank_space(tables:)
  let rows =
    list.flat_map(stands, fn(stand) {
      list.index_map(stand.creatures, fn(creature, slot) {
        spawn.creature_row(
          looks:,
          factions:,
          id: placed_id(
            blocks: ranks.kills,
            marker: stand.marker,
            creature:,
            nth: list.count(list.take(stand.creatures, slot), fn(earlier) {
              earlier.id == creature.id
            }),
          ),
          creature:,
          place: slot_place(
            marker: stand.marker,
            slot:,
            slots: ring_size(sizes:, marker: stand.marker),
            grounds:,
          ),
          level: None,
        )
      })
    })
  let kill_slots = kill_slot_counts(stands:)
  let click_rows =
    list.flat_map(click_stands, fn(stand) {
      let taken = result.unwrap(dict.get(kill_slots, stand.marker.row.id), 0)
      list.index_map(stand.wants, fn(want, index) {
        spawn.Row(
          ..spawn.creature_row(
            looks:,
            factions:,
            id: placed_id(
              blocks: ranks.clicks,
              marker: stand.marker,
              creature: want.creature,
              nth: 0,
            ),
            creature: want.creature,
            place: slot_place(
              marker: stand.marker,
              slot: taken + index,
              slots: ring_size(sizes:, marker: stand.marker),
              grounds:,
            ),
            level: None,
          ),
          entity_type: paired_unit_type(creature: want.creature),
        )
      })
    })
  Placed(rows:, skipped:, click_rows:, click_skipped:, unread_links:)
}

/// What each kill objective asks for, with what is wrong with it (`plan`): the objectives
/// of the kill table (`kills`, whose reward pane is the group), and types 2, 8 and 16.
fn planned_jobs(
  tables tables: table_store.Tables,
  kills kills: Set(Int),
  worlds worlds: Set(Int),
  kinds kinds: Option(Kinds),
) -> List(#(Option(Job), List(Skipped))) {
  quest_objective.all(tables)
  |> list.filter_map(fn(objective) {
    case set.contains(kills, objective.id) {
      True ->
        Ok(#(
          objective,
          objective_kind.GroupOf(
            target_group_id: quest_objective.target_group_id_reward_pane(
              objective,
            ),
          ),
        ))
      False ->
        result.map(
          objective_kind.placed_target(objective_kind.of_row(objective)),
          fn(named) { #(objective, named) },
        )
    }
  })
  |> list.map(fn(pair) {
    plan(tables:, worlds:, kinds:, objective: pair.0, named: pair.1)
  })
}

/// The id of the first spawn the server places for a quest, 1,000,000,000: a placed
/// spawn's id is this plus its rank (`rank_space`), above every id a stored row is
/// allowed (`refusals`) and inside the 32-bit integer of the spawn table's id and of a
/// quest's used spawns (migrations 0008 and 0052). A spawn a run alone makes has a negative
/// id (genesis_prime/world_map/spawn_source).
const first_placed_id = 1_000_000_000

/// The stored rows whose id is one the server places from: each is refused, so that a
/// placed spawn's id never names a stored row too.
pub fn refusals(stored stored: List(Row)) -> List(Refusal) {
  list.filter_map(stored, fn(row) {
    case number_of(row:) >= first_placed_id {
      True ->
        Ok(refusal.Refusal(
          table: "spawn",
          row: refusal.RowId(number_of(row:)),
          rule: "its id is at or above "
            <> int.to_string(first_placed_id)
            <> ", where the spawns the server places begin",
        ))
      False -> Error(Nil)
    }
  })
}

/// Where the ranks of one (marker, creature) start and how many it holds.
type Block {
  Block(start: Int, size: Int)
}

/// The ranks of every (marker WorldLocation2 id, Creature2 id) a placement can ask for,
/// the kill rows' and the click rows' apart. A kill row of a creature at a marker takes
/// the block's `start` plus its nth stand there; a click row stands once.
type RankSpace {
  RankSpace(kills: Dict(#(Int, Int), Block), clicks: Dict(#(Int, Int), Block))
}

/// The ranks of the client's tables alone, so that no stored row, added or deleted, moves
/// a placed spawn's id and a quest's used objects of it are kept across a login. A triple
/// of (kind, marker, creature) holds a block of ranks for each creature a kill objective
/// (types 2, 8 and 16, and every type 5 objective as one that asks to kill) or a click
/// objective (every type 5 objective that asks to click, and the creatures that
/// `objective_link.links` ties to an objective of type 5 or 32) can stand at a marker. They
/// are worked out as the placement works them out, in every world as if it held a stored
/// row, with no stored row to serve a marker and no turret creature left out, so that no
/// server table but the client's decides a rank. The kill triples come first, each kind in
/// marker then creature order. A block holds as many ranks as the most any objective deals
/// that creature at that marker (`slots_of`), which a marker's stand never exceeds: it
/// takes the largest count of each creature over its objectives, not their sum.
fn rank_space(tables tables: table_store.Tables) -> RankSpace {
  let every_type_5 =
    quest_objective.all(tables)
    |> list.filter(fn(objective) {
      objective_kind.of_row(objective) == objective_kind.Scripted
    })
    |> list.map(fn(objective) { objective.id })
    |> set.from_list
  let worlds =
    world_location2.all(tables)
    |> list.map(fn(row) { row.world_id })
    |> set.from_list
  let kill_sizes =
    planned_jobs(tables:, kills: every_type_5, worlds:, kinds: None)
    |> list.filter_map(fn(pair) { option.to_result(pair.0, Nil) })
    |> list.fold(dict.new(), job_sizes)
  let click_sizes =
    click_stands(tables:, clicks: every_type_5, worlds:, stored: []).0
    |> list.flat_map(fn(stand) {
      list.map(stand.wants, fn(want) {
        #(stand.marker.row.id, want.creature.id)
      })
    })
    |> list.map(fn(key) { #(key, 1) })
    |> dict.from_list
  let #(kills, kill_ranks) = blocks_from(sizes: kill_sizes, start: 0)
  let #(clicks, _) = blocks_from(sizes: click_sizes, start: kill_ranks)
  RankSpace(kills:, clicks:)
}

/// `sizes` with, for each creature of the job at each marker, the ranks the job deals it
/// there (`slots_of`) when that is more than `sizes` holds.
fn job_sizes(
  sizes sizes: Dict(#(Int, Int), Int),
  job job: Job,
) -> Dict(#(Int, Int), Int) {
  list.fold(markers_by_world(job:), sizes, fn(sizes, world) {
    let markers = world.1
    list.index_fold(markers, sizes, fn(sizes, marker, index) {
      let slots =
        slots_of(count: job.count, markers: list.length(markers), index:)
      list.fold(job.creatures, sizes, fn(sizes, creature) {
        dict.upsert(sizes, #(marker.row.id, creature.id), fn(held) {
          int.max(option.unwrap(held, 0), slots)
        })
      })
    })
  })
}

/// The blocks of these sizes in key order, the first starting at `start`, and the rank
/// the next block would start at.
fn blocks_from(
  sizes sizes: Dict(#(Int, Int), Int),
  start start: Int,
) -> #(Dict(#(Int, Int), Block), Int) {
  let #(blocks, next) =
    dict.to_list(sizes)
    |> list.sort(fn(a, b) {
      int.compare(a.0.0, b.0.0)
      |> order.break_tie(int.compare(a.0.1, b.0.1))
    })
    |> list.fold(#([], start), fn(state, entry) {
      let #(blocks, at) = state
      #([#(entry.0, Block(start: at, size: entry.1)), ..blocks], at + entry.1)
    })
  #(dict.from_list(blocks), next)
}

/// The id of the `nth` row (from 0) of the creature at the marker among those of its
/// kind, `blocks` being the kind's. A triple the ranks lack, or an nth past its block,
/// is a bug of `rank_space`, whose triples hold every row the stands can make.
fn placed_id(
  blocks blocks: Dict(#(Int, Int), Block),
  marker marker: Marker,
  creature creature: Creature2,
  nth nth: Int,
) -> SpawnId {
  let assert Ok(Block(start:, size:)) =
    dict.get(blocks, #(marker.row.id, creature.id))
    as "the rank space holds a block for every creature a marker stands"
  assert nth < size
    as "the rank space holds a block as large as the creature's stands at the marker"
  SpawnId(first_placed_id + start + nth)
}

/// The creatures one marker stands for the kill objectives, in the order of its
/// ring's slots.
type Stand {
  Stand(marker: Marker, creatures: List(Creature2))
}

/// The click targets one marker stands, in creature id order, after the creatures
/// of its kill `Stand`.
type ClickStand {
  ClickStand(marker: Marker, wants: List(Want))
}

/// The stands of the jobs with each marker's made one: a marker two jobs ask
/// creatures of stands the creatures of the first job as it dealt them, then
/// of each later job those it asks of more than the stand holds, so each job keeps
/// what it asked at the marker, a creature two jobs ask once stands once (the larger
/// count), and no two creatures share a ring slot. The markers are in the order
/// they first show.
fn combined(stands stands: List(Stand)) -> List(Stand) {
  list.fold(stands, [], fn(kept: List(Stand), stand: Stand) {
    case
      list.any(kept, fn(other) { other.marker.row.id == stand.marker.row.id })
    {
      True ->
        list.map(kept, fn(other) {
          case other.marker.row.id == stand.marker.row.id {
            True ->
              Stand(
                ..other,
                creatures: with_largest_counts(
                  held: other.creatures,
                  added: stand.creatures,
                ),
              )
            False -> other
          }
        })
      False -> [stand, ..kept]
    }
  })
  |> list.reverse
}

/// The creatures held, then each creature of `added` as many times as `added` has it
/// beyond the times it is held.
fn with_largest_counts(
  held held: List(Creature2),
  added added: List(Creature2),
) -> List(Creature2) {
  let times = fn(creatures: List(Creature2), creature: Creature2) {
    list.count(creatures, fn(one) { one.id == creature.id })
  }
  list.unique(added)
  |> list.flat_map(fn(creature) {
    list.repeat(creature, times(added, creature) - times(held, creature))
  })
  |> list.append(held, _)
}

/// How many creatures of kill objectives each marker stands, by the marker's id.
fn kill_slot_counts(stands stands: List(Stand)) -> Dict(Int, Int) {
  list.map(stands, fn(stand) {
    #(stand.marker.row.id, list.length(stand.creatures))
  })
  |> dict.from_list
}

/// How many creatures each marker stands in all, kill and click, by the marker's id:
/// the slots of its ring.
fn ring_sizes(
  stands stands: List(Stand),
  click_stands click_stands: List(ClickStand),
) -> Dict(Int, Int) {
  let add = fn(sizes: Dict(Int, Int), marker: Marker, more: Int) {
    dict.upsert(sizes, marker.row.id, fn(held) { option.unwrap(held, 0) + more })
  }
  let with_kills =
    list.fold(stands, dict.new(), fn(sizes, stand) {
      add(sizes, stand.marker, list.length(stand.creatures))
    })
  list.fold(click_stands, with_kills, fn(sizes, stand) {
    add(sizes, stand.marker, list.length(stand.wants))
  })
}

/// The slots of the marker's ring. Every marker that has a row to place is in
/// `sizes` (`ring_sizes` counts the creatures of each stand's marker).
fn ring_size(sizes sizes: Dict(Int, Int), marker marker: Marker) -> Int {
  let assert Ok(size) = dict.get(sizes, marker.row.id)
    as "a marker that stands a creature has a ring size"
  size
}

/// An objective's marker a creature is linked to (`objective_link.links`): the
/// creature stands there for the objective's use to count.
type Want {
  Want(objective_id: Int, creature: Creature2, marker_id: Int, marker: Marker)
}

/// The click targets to stand, marker by marker in marker id order, and the pairs that
/// were not placed. Every creature that `objective_link.links` ties to a type 5 or 32
/// objective with a marker is wanted at each marker. A stored row of the creature of
/// any unit type serves the one marker it stands nearest in its own world, and a
/// marker no row serves gets the creature, as the unit type its
/// CreationTypeEnum pairs with (`paired_unit_type`), several creatures of one marker
/// in creature-id order. A pair of a marker with no row or
/// no stored spawn in its world is skipped as the kill path skips it, and one whose
/// unit type the server does not start is skipped as `NotStarted`.
fn click_stands(
  tables tables: table_store.Tables,
  clicks clicks: Set(Int),
  worlds worlds: Set(Int),
  stored stored: List(Row),
) -> #(List(ClickStand), List(Skipped), List(UnreadLink)) {
  let #(linked_pairs, unread_links) = click_pairs(tables:)
  let pairs = list.append(linked_pairs, pane_pairs(tables:, clicks:))
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
  let stands =
    started
    |> list.sort(fn(a, b) {
      int.compare(a.marker_id, b.marker_id)
      |> order.break_tie(int.compare(a.creature.id, b.creature.id))
    })
    |> once_each
    |> list.chunk(fn(want) { want.marker_id })
    |> list.map(fn(group) {
      let assert [first, ..] = group
        as "a chunk of a list holds at least one element"
      ClickStand(marker: first.marker, wants: group)
    })
  #(stands, list.unique(list.append(marker_skips, not_started)), unread_links)
}

/// Every (objective, creature, marker) of the click table's objectives: each creature of
/// the reward pane that the client offers a click on (`activate.offers_click`), at each of
/// the objective's markers, in objective order.
fn pane_pairs(
  tables tables: table_store.Tables,
  clicks clicks: Set(Int),
) -> List(#(Int, Creature2, Int)) {
  quest_objective.all(tables)
  |> list.filter(fn(objective) { set.contains(clicks, objective.id) })
  |> list.flat_map(fn(objective) {
    target_group.listed_creatures(
      tables:,
      group: quest_objective.target_group_id_reward_pane(objective).value,
    )
    |> list.unique
    |> list.filter_map(fn(creature_id) {
      creature2.get(tables, Creature2Id(creature_id))
      |> result.try(fn(row) {
        case activate.offers_click(row:) {
          True -> Ok(row)
          False -> Error(Nil)
        }
      })
    })
    |> list.flat_map(fn(creature) {
      place_objective.marker_ids(objective:)
      |> list.map(fn(marker_id) { #(objective.id, creature, marker_id) })
    })
  })
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
  case objective_kind.is_linked_use(objective.kind) {
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
  creation_type.unit_type(creation_type.kind_of(creature.creation_type_enum))
}

/// What the objective asks for and what is wrong with it. An objective with no
/// marker asks for nothing and is not reported: it is no pair. With `kinds` of `None` no
/// creature is left out as a turret with no kind.
fn plan(
  tables tables: table_store.Tables,
  worlds worlds: Set(Int),
  kinds kinds: Option(Kinds),
  objective objective: QuestObjective,
  named named: objective_kind.PlacedTarget,
) -> #(option.Option(Job), List(Skipped)) {
  let marker_ids = place_objective.marker_ids(objective:)
  case marker_ids {
    [] -> #(None, [])
    _ -> {
      let creature_ids = target_group.placed_creatures(tables:, placed: named)
      let no_group = case creature_ids {
        [] -> [
          Skipped(
            objective.id,
            NamesNoCreature(group_id: case named {
              objective_kind.GroupOf(target_group_id:) -> target_group_id.value
              objective_kind.OneCreature(..) -> objective.data
            }),
          ),
        ]
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
          option.Some(Job(creatures: rows, markers:, count: objective.count))
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

/// Whether the creature's row makes it a turret (`creature_unit_type.of_creation_type`) the
/// server has no kind for: it would stand as a static object, not fight. Never when there
/// are no `kinds` to ask.
fn is_unrun_turret(
  creature creature: Creature2,
  kinds kinds: Option(Kinds),
) -> Bool {
  case
    creature_unit_type.of_creation_type(
      creation_type: creature.creation_type_enum,
    ),
    kinds
  {
    Turret, Some(kinds) -> !dict.has_key(kinds.by_creature, creature.id)
    Turret, None | NonPlayer, _ -> False
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

/// The markers of the job in each world they are in, worlds in the order their markers
/// first show them and each world's markers in column order.
fn markers_by_world(job job: Job) -> List(#(Int, List(Marker))) {
  job.markers
  |> list.map(fn(marker) { marker.row.world_id })
  |> list.unique
  |> list.map(fn(world_id) {
    #(
      world_id,
      list.filter(job.markers, fn(marker) { marker.row.world_id == world_id }),
    )
  })
}

/// The stands of one job, world by world.
fn stands_of(job job: Job, held held: Set(#(Int, Int))) -> List(Stand) {
  list.flat_map(markers_by_world(job:), fn(world) {
    let #(world_id, markers) = world
    let creatures =
      list.filter(job.creatures, fn(creature) {
        !set.contains(held, #(world_id, creature.id))
      })
    stands_in_world(creatures:, markers:, count: job.count)
  })
}

/// How many of `count` the marker at `index` of `markers` markers is dealt, the count
/// going to the markers one at a time.
fn slots_of(count count: Int, markers markers: Int, index index: Int) -> Int {
  count
  / markers
  + case index < count % markers {
    True -> 1
    False -> 0
  }
}

/// The stands of one world: the count dealt to the markers one at a time, and the
/// creatures to the places in that order, cycling. A marker dealt none has no stand.
fn stands_in_world(
  creatures creatures: List(Creature2),
  markers markers: List(Marker),
  count count: Int,
) -> List(Stand) {
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
        let slots = slots_of(count:, markers: marker_count, index:)
        let dealt =
          list.repeat(Nil, slots)
          |> list.index_map(fn(_, slot) { slot })
          |> list.filter_map(fn(slot) {
            // The place the count's dealing gives this slot: marker `index` is
            // dealt places index, index + markers, index + 2 markers, ...
            let turn = index + slot * marker_count
            dict.get(by_turn, turn % creature_count)
          })
        Stand(marker:, creatures: dealt)
      })
      |> list.filter(fn(stand) { stand.creatures != [] })
  }
}

/// How far above a unit the client's ground reaches to lift it: a unit at most this
/// far below the ground is lifted onto it (`unit.ground_lift`).
const ground_lift_reach = 2.0

/// The place of slot `slot` of the `slots` a marker's ring holds: the marker's own
/// place for one, else a point of the circle of half its radius, facing the centre.
/// Positions and the facing are 32-bit floats, as a row's are. A ring slot stands at
/// the ground read at its point when the marker's centre stands on the ground (the
/// marker's height within the client's lift of the ground read at its centre) and
/// the ground has a read at the point; any other slot keeps the marker's height.
fn slot_place(
  marker marker: Marker,
  slot slot: Int,
  slots slots: Int,
  grounds grounds: Dict(Int, Ground),
) -> Place {
  case slots {
    1 -> marker.place
    _ -> {
      let angle = 2.0 *. maths.pi() *. int.to_float(slot) /. int.to_float(slots)
      let reach = marker.row.radius /. 2.0
      let centre = marker.place
      let slot_x =
        float32.rounded(start_place.x(centre) +. reach *. maths.cos(angle))
      let slot_z =
        float32.rounded(start_place.z(centre) +. reach *. maths.sin(angle))
      start_place.moved(
        place: centre,
        x: slot_x,
        y: ring_height(marker:, slot_x:, slot_z:, grounds:),
        z: slot_z,
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

/// The height a ring slot at (`slot_x`, `slot_z`) stands at: the ground read there
/// when the marker's centre stands on the ground and the read is within the ring's
/// band of the marker's height (the ring's radius plus the client's lift: the ground
/// of a slope no steeper than 45 degrees from the centre, a server choice), else the
/// marker's height. A read outside the band is a pit, a cliff or terrain under props.
fn ring_height(
  marker marker: Marker,
  slot_x slot_x: Float,
  slot_z slot_z: Float,
  grounds grounds: Dict(Int, Ground),
) -> Float {
  let centre = marker.place
  let marker_height = start_place.y(centre)
  let band = marker.row.radius /. 2.0 +. ground_lift_reach
  let on_the_ground = {
    use ground <- result.try(
      dict.get(grounds, marker.row.world_id)
      |> result.replace_error(Nil),
    )
    use under_centre <- result.try(
      terrain.height_at(
        ground:,
        x: start_place.x(centre),
        z: start_place.z(centre),
      )
      |> result.replace_error(Nil),
    )
    use <- bool.guard(
      when: float.absolute_value(marker_height -. under_centre)
        >. ground_lift_reach,
      return: Error(Nil),
    )
    use under_slot <- result.try(
      terrain.height_at(ground:, x: slot_x, z: slot_z)
      |> result.replace_error(Nil),
    )
    case float.absolute_value(under_slot -. marker_height) <=. band {
      True -> Ok(under_slot)
      False -> Error(Nil)
    }
  }
  case on_the_ground {
    Ok(height) -> float32.rounded(height)
    Error(Nil) -> marker_height
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

/// What the placement leaves undone, for the coverage measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Objective creature placement",
      missing: "the ground under the ring of a marker whose centre is not on the ground (an interior, a cave, a prop) or has no ground read: its creatures stand at the marker's height, which may be off the ground the client draws",
    ),
    gap.Entry(
      area: "Objective creature placement",
      missing: "the ground at a ring slot that has no ground read (a hole cell, a chunk with no layer) or whose ground is farther from the marker's height than the ring's radius plus 2: the creature stands at the marker's height, which may be off the ground the client draws",
    ),
  ]
}
