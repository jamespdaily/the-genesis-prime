//// The content tables: data the server owns, kept in Postgres and loaded once at
//// start into persistent terms. Behaviour stays in code (rules, the client's
//// formulas, message layouts, client facts); `spawn` is the first content table
//// (genesis_prime/content/spawn), `creature_kind` the second
//// (genesis_prime/content/creature_kind), `game_number` the third
//// (genesis_prime/content/game_number), `class_resource` the fourth
//// (genesis_prime/content/class_resource), `server_proxy` the fifth
//// (genesis_prime/content/server_proxy), and every later one follows the same
//// pattern; `creature_faction` (genesis_prime/content/creature_faction) is read
//// beside the kinds, and the spawns, the placed objective creatures and the summons
//// are checked with it.
//// The kinds are selected before the spawns, since a spawn's attack is its kind's
//// spell.
////
//// - **Where a row comes from.** Every content table has `source` (a row of the
////   `content_source` table: `world_database`, `retail_record`, `server_choice`,
////   `game_master`, `client`), `source_row` (the row's id in its source file) and `reason`,
////   and the checks that a world-database row names its source row and any other
////   row states its reason (migration 0008).
//// - **How rows get in.** A world-database row comes through the import tool
////   (`genesis_prime/import_world_data`), which has one importer for each file
////   and records each import in `content_import`; a server choice is seeded by a
////   migration. CI seeds planted rows the same ways.
//// - **One load at start, before the tree.** `load` runs in `main`, once the
////   client's tables are loaded and before the supervision tree starts, so the
////   listeners open after it.
//// - **Each table's pure check** turns a row into a typed record or a refusal
////   naming the table, the id and the rule; the client's tables are the
////   reference. Nothing queries a content table during play.
////
//// ```
//// main ─▶ load_content ─▶ content.load(tables, migrations, pool, ask settings, key)
////           tables: the content-only ones, loaded beside the server's own (which hold the creatures)
////           starts a pool of its own: one connection, not the tree's
////           waits for the database as readiness does (readiness.await with no tree):
////             attempts of attempt_ms, pause_ms between them, a warning each within_ms
////           compares the migrations the database recorded with the files (genesis_prime/migration)
////           for each table, in order:
////             its one query ─▶ rows ─▶ its pure check ─▶ typed records and refusals
////           every refusal of every table logged; any ─▶ Error(Refused(all of them))
////           else each table's terms put under key; the coverage logged
////           ends its pool
////        ─▶ Ok: starts the tree (pool, store, ..., listeners) ─▶ readiness ask ─▶ ready line
////        ─▶ Error: main stops with the sentences; no tree, no listener, status 1
//// ```
////
//// - **Why before the tree.** A map reads its world's term when it starts, and
////   the first player can arrive when the listeners open, so the term must exist
////   by then. The tree's own pool starts inside the tree, so the load has a pool
////   of its own and the tree starts clean after it.
//// - **The wait is readiness's** (genesis_prime/readiness), with no tree to watch:
////   attempts of 2 s with 250 ms between them, a warning each 30 s, and then the
////   same again, so a database that comes up late works. With the database down
////   at start nothing listens until it answers, where the tree used to start first
////   and answer `Unavailable` meanwhile. The migration comparison is readiness's
////   too (`migration.check`): a database that ran other migrations stops the
////   start with the difference, as the ready line's does.
//// - **Every refusal is collected.** One bad row shows its neighbours: all are
////   logged, then the start stops, as a client table that fails to load does.
//// - **The terms** are put once, one for each table and world, under `key`
////   (genesis_prime/content/term); a world of the client's World table with no
////   spawn gets an empty one, so a missing term is a bug and crashes its reader.
//// - **The server's Proxies** are planned over the ability trees the tables' load derived
////   (genesis_prime/game/server_proxy), so a row naming a base, a go or a spell those trees
////   lack is refused with the plan's reason.
//// - **The zones' welcomes** are checked against the client's WorldZone and Tutorial rows
////   (genesis_prime/game/zone_welcome): a row naming a zone or a Tutorial row the tables
////   lack, a Tutorial row that is not of category 29, or a parent chain that is a cycle
////   is refused.
//// - **The tutorial quests** are checked against the client's Quest2, QuestObjective and
////   Creature2 rows (genesis_prime/game/tutorial): a row naming a quest or an objective the
////   tables lack, a quest a creature gives or receives, or a faction whose rows are not one
////   chain from one start is refused.
//// - **The projector landings** are checked against the client's Creature2, WorldLocation2,
////   QuestObjective, Quest2 and WorldZone rows (genesis_prime/game/projector): a creature
////   that does not cast the projector spell, a landing outside World 3460, an objective that
////   is not the creature's use or a zone the landing lies in, or one of the other faction's
////   quests is refused.
//// - **The vendors** are checked against the client's Creature2 and Item2 rows
////   (genesis_prime/game/vendor): a vendor naming a creature, an item naming an Item2 row
////   the tables lack, or an item of a creature with no vendor row is refused.
//// - **Content-only tables.** The faction, outfit and world tables the selection
////   reads are read beside the server's own tables on the caller's heap
////   (`server_table.load_content_tables`: the creature tables are read where they
////   already are, so nothing loads twice), and stored nowhere: they are not in the
////   server's tables, whose digest a recording's header holds.
////
//// What happens at each failure point of the load:
////
//// | Point | What happens |
//// |---|---|
//// | the database answers late | the load waits and warns each 30 s, and asks again; the tree starts after it |
//// | the migrations differ | the start stops with the difference |
//// | a row is refused | the start stops with the reason |
//// | several rows are refused | every refusal is logged, then the start stops |
//// | a query fails | the start stops with the database's reason |

import genesis_prime/content/class_resource as content_class_resource
import genesis_prime/content/creature_faction as content_creature_faction
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/projector_landing as content_projector_landing
import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/content/server_proxy as content_server_proxy
import genesis_prime/content/spawn as content_spawn
import genesis_prime/content/tutorial_quest as content_tutorial_quest
import genesis_prime/content/vendor as content_vendor
import genesis_prime/content/zone_welcome as content_zone_welcome
import genesis_prime/game/class_resource
import genesis_prime/game/place_objective
import genesis_prime/game/projector
import genesis_prime/game/rating
import genesis_prime/game/server_proxy
import genesis_prime/game/spell_plan
import genesis_prime/game/tutorial
import genesis_prime/game/vendor
import genesis_prime/game/zone_welcome
import genesis_prime/migration.{type Migration}
import genesis_prime/readiness
import genesis_prime/step
import genesis_prime/step/runtime
import genesis_prime/store/worker
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/table/quest_objective.{type QuestObjective}
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/creature_kind
import genesis_prime/world_map/game_number
import genesis_prime/world_map/objective_spawn
import genesis_prime/world_map/sight
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import pog

/// Why the load did not finish.
pub type LoadError {
  /// The database recorded other migrations than the files.
  MigrationsDiffer(refusal: migration.Refusal)
  /// A query failed, for the reason the database gave.
  QueryFailed(table: String, reason: String)
  /// These rows are refused, all of them from every table.
  Refused(refusals: List(Refusal))
}

/// How the load asks its pool whether the database answers: the probe of the
/// store's worker, run on the pool (`worker.probe_pool`). A test passes a probe of
/// its own to script a database that answers late.
pub fn pool_probe(db db: pog.Connection) -> readiness.Probe {
  fn(reply) { worker.probe_pool(pool: db, reply:) }
}

/// Loads every content table into persistent terms under `key`, as the
/// sequence above gives: waits for the database as `ask` says, compares the
/// migrations with `migrations`, checks every row against the client's `tables`,
/// logs every refusal and puts the terms only when there is none. `pool` is the
/// configuration of the load's own pool, which it makes one connection. `probe`
/// asks that pool whether the database answers (`pool_probe`). `tables` are only
/// read: the load stores none of them.
pub fn load(
  tables tables: store.Tables,
  migrations migrations: List(Migration),
  pool pool: pog.Config,
  ask ask: readiness.Settings,
  probe probe: fn(pog.Connection) -> readiness.Probe,
  key key: Key,
) -> Result(Nil, LoadError) {
  let assert Ok(started) = pog.start(pog.pool_size(pool, 1))
    as "the content load's database pool started"
  process.unlink(started.pid)
  let loaded = read(tables:, migrations:, db: started.data, ask:, probe:, key:)
  process.send_abnormal_exit(started.pid, runtime.Shutdown)
  loaded
}

/// The load itself, on the pool: the wait, the migrations, the query, the
/// selection, the log and the terms.
fn read(
  tables tables: store.Tables,
  migrations migrations: List(Migration),
  db db: pog.Connection,
  ask ask: readiness.Settings,
  probe probe: fn(pog.Connection) -> readiness.Probe,
  key key: Key,
) -> Result(Nil, LoadError) {
  use _ready <- result.try(
    wait(db:, migrations:, ask:, probe:) |> result.map_error(MigrationsDiffer),
  )
  use rows <- result.try(
    content_spawn.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_spawn.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use kind_rows <- result.try(
    content_creature_kind.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_creature_kind.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use faction_rows <- result.try(
    content_creature_faction.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_creature_faction.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use number_rows <- result.try(
    content_game_number.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_game_number.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use class_rows <- result.try(
    content_class_resource.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_class_resource.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use proxy_rows <- result.try(
    content_server_proxy.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_server_proxy.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use welcome_rows <- result.try(
    content_zone_welcome.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_zone_welcome.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use tutorial_rows <- result.try(
    content_tutorial_quest.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_tutorial_quest.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use projector_rows <- result.try(
    content_projector_landing.rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_projector_landing.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use vendor_rows <- result.try(
    content_vendor.vendor_rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_vendor.table,
        reason: worker.describe_query_error(error),
      )
    }),
  )
  use vendor_item_rows <- result.try(
    content_vendor.item_rows(db)
    |> result.map_error(fn(error) {
      QueryFailed(
        table: content_vendor.table <> "_item",
        reason: worker.describe_query_error(error),
      )
    }),
  )
  let classes = class_resource.select(rows: class_rows)
  let class_refusals = case classes {
    Ok(..) -> []
    Error(refusals) -> refusals
  }
  let proxies =
    server_proxy.select(
      rows: proxy_rows,
      tables:,
      plans: spell_plan.plans(tables:),
    )
  let proxy_refusals = case proxies {
    Ok(..) -> []
    Error(refusals) -> refusals
  }
  let welcomes = zone_welcome.select(rows: welcome_rows, tables:)
  let welcome_refusals = case welcomes {
    Ok(..) -> []
    Error(refusals) -> refusals
  }
  let tutorials = tutorial.select(rows: tutorial_rows, tables:)
  let tutorial_refusals = result.unwrap_error(tutorials, or: [])
  let projectors = projector.select(rows: projector_rows, tables:)
  let projector_refusals = result.unwrap_error(projectors, or: [])
  let vendors =
    vendor.select(vendors: vendor_rows, items: vendor_item_rows, tables:)
  let vendor_refusals = case vendors {
    Ok(..) -> []
    Error(refusals) -> refusals
  }
  // With a vendor row refused, the spawns are checked as if no creature sold, so the
  // start names a bad spawn too and the vendor refusals stop it.
  let vendors_for_spawns = case vendors {
    Ok(vendors) -> vendors
    Error(..) -> vendor.none()
  }
  let numbers = game_number.select(rows: number_rows, sight_range: sight.range)
  let number_refusals = case numbers {
    Ok(..) -> []
    Error(refusals) -> refusals
  }
  let kinds = creature_kind.select(rows: kind_rows, tables:)
  let kind_refusals = case kinds {
    Ok(..) -> []
    Error(refusals) -> refusals
  }
  // With a kind row refused, the spawns are checked with the kinds the load took,
  // so the start names a bad spawn too; with the default row missing or refused no
  // spawn has a kind, and that refusal alone stops the start.
  let kinds_for_spawns = case kinds {
    Ok(kinds) -> Ok(kinds)
    Error(..) -> creature_kind.taken(rows: kind_rows, tables:)
  }
  let factions = creature_faction.select(rows: faction_rows, tables:)
  let faction_refusals = result.unwrap_error(factions, or: [])
  // With a faction row refused, the spawns are checked with the factions the load
  // took, so the start names a bad spawn too.
  let factions_for_spawns = case factions {
    Ok(factions) -> factions
    Error(..) -> creature_faction.taken_of(rows: faction_rows, tables:)
  }
  // A kill objective's creature with no stored spawn in its marker's world stands in
  // the marker's circle; the placed rows are checked with the stored ones.
  // With no kinds taken the load has refusals and starts nothing, so nothing is placed.
  let placed = case kinds_for_spawns {
    Ok(kinds) ->
      objective_spawn.place(
        tables:,
        stored: rows,
        factions: factions_for_spawns,
        kinds:,
      )
    Error(..) ->
      objective_spawn.Placed(
        rows: [],
        skipped: [],
        click_rows: [],
        click_skipped: [],
        unread_links: [],
      )
  }
  let selection = case kinds_for_spawns {
    Ok(kinds) ->
      spawn.select(
        rows: list.flatten([rows, placed.rows, placed.click_rows]),
        tables:,
        formulas: rating.formulas(tables:),
        kinds:,
        factions: factions_for_spawns,
        vendors: vendors_for_spawns,
      )
    Error(Nil) ->
      spawn.Selection(
        worlds: dict.new(),
        refusals: [],
        out_of_range_levels: [],
        coverage: [],
        visibility: dict.new(),
      )
  }
  case
    list.flatten([
      objective_spawn.labelled(refusals: selection.refusals, placed:),
      kind_refusals,
      faction_refusals,
      number_refusals,
      class_refusals,
      proxy_refusals,
      welcome_refusals,
      tutorial_refusals,
      projector_refusals,
      vendor_refusals,
    ])
  {
    [] -> {
      list.each(selection.coverage, fn(coverage) {
        runtime.log(
          step.LogInfo,
          spawn.describe_coverage(coverage:),
          step.no_one,
        )
      })
      list.each(objective_spawn.report(placed:), fn(line) {
        runtime.log(step.LogInfo, line, step.no_one)
      })
      log_levels_out_of_range(selection)
      log_place_objectives(tables:, selection:)
      content_spawn.put(key:, selection:)
      let assert Ok(kinds_of_summons) = kinds_for_spawns
        as "no kinds were taken, which refuses the kind rows, so the load has refusals and does not reach here"
      content_spawn.put_summon_checks(
        key:,
        checks: spawn.summon_checks(
          tables:,
          formulas: rating.formulas(tables:),
          kinds: kinds_of_summons,
          factions: factions_for_spawns,
          vendors: vendors_for_spawns,
        ),
      )
      case kinds {
        Ok(kinds) -> content_creature_kind.put(key:, kinds:)
        Error(..) -> Nil
      }
      case numbers {
        Ok(numbers) -> content_game_number.put(key:, numbers:)
        Error(..) -> Nil
      }
      case classes {
        Ok(classes) -> content_class_resource.put(key:, classes:)
        Error(..) -> Nil
      }
      case proxies {
        Ok(proxies) -> content_server_proxy.put(key:, proxies:)
        Error(..) -> Nil
      }
      case welcomes {
        Ok(welcomes) -> content_zone_welcome.put(key:, welcomes:)
        Error(..) -> Nil
      }
      case tutorials {
        Ok(chain) -> content_tutorial_quest.put(key:, chain:)
        Error(..) -> Nil
      }
      case projectors {
        Ok(landings) -> content_projector_landing.put(key:, landings:)
        Error(..) -> Nil
      }
      case vendors {
        Ok(vendors) -> content_vendor.put(key:, vendors:)
        Error(..) -> Nil
      }
      Ok(Nil)
    }
    refusals -> {
      list.each(refusals, fn(refused) {
        runtime.log(step.LogError, refusal.describe(refused), step.no_one)
      })
      Error(Refused(refusals:))
    }
  }
}

/// The info line of the spawns whose level lies outside their creature's range.
fn log_levels_out_of_range(selection: spawn.Selection) -> Nil {
  case selection.out_of_range_levels {
    [] -> Nil
    levels ->
      runtime.log(
        step.LogInfo,
        "spawns started with a level outside their creature's range: "
          <> string.join(
          list.map(levels, fn(id) {
            let spawn_id.SpawnId(number) = id
            int.to_string(number)
          }),
          ", ",
        ),
        step.no_one,
      )
  }
}

/// The info lines of the type 22 objectives with no marker or, with one, a count above 1,
/// which an arrival does not complete, and of the place-counted checklist objectives with
/// a place where no spawn of their group stands, where reaching the place counts nothing.
fn log_place_objectives(
  tables tables: store.Tables,
  selection selection: spawn.Selection,
) -> Nil {
  log_objective_ids(
    place_objective.unmarked(tables:),
    "type 22 objectives with no marker, which nothing completes (issue 714)",
  )
  log_objective_ids(
    place_objective.repeated(tables:),
    "type 22 objectives with a count above 1, which an arrival does not complete (issue 714)",
  )
  list.each(
    place_objective.places_without_unit(tables:, worlds: selection.worlds),
    fn(empty) {
      let #(objective_id, places) = empty
      runtime.log(
        step.LogInfo,
        "objective "
          <> int.to_string(objective_id)
          <> " counts nothing at its places "
          <> string.join(list.map(places, int.to_string), ", ")
          <> ", where no spawn of its group stands",
        step.no_one,
      )
    },
  )
}

/// An info line of the objectives' ids after the text, none for no objectives.
fn log_objective_ids(objectives: List(QuestObjective), what: String) -> Nil {
  case objectives {
    [] -> Nil
    _ ->
      runtime.log(
        step.LogInfo,
        what
          <> ": "
          <> string.join(
          list.map(objectives, fn(objective) { int.to_string(objective.id) }),
          ", ",
        ),
        step.no_one,
      )
  }
}

/// Asks the database through the load's pool until it answers, as readiness
/// does at start, warning each window that passes with no answer.
fn wait(
  db db: pog.Connection,
  migrations migrations: List(Migration),
  ask ask: readiness.Settings,
  probe probe: fn(pog.Connection) -> readiness.Probe,
) -> Result(Nil, migration.Refusal) {
  case
    readiness.await(
      probe: probe(db),
      tree: None,
      settings: ask,
      files: migrations,
    )
  {
    readiness.Ready -> Ok(Nil)
    readiness.MigrationsRefused(refusal:) -> Error(refusal)
    readiness.DatabaseUnreachable -> {
      runtime.log(step.LogWarning, "the database is unreachable", step.no_one)
      wait(db:, migrations:, ask:, probe:)
    }
    readiness.TreeEnded(..) ->
      panic as "the content load watches no tree, so none ended"
  }
}

/// A sentence for each way the load can fail, for the message the start stops
/// with: the migrations' difference, the query's reason, or one line for each
/// refused row.
pub fn describe(error error: LoadError) -> String {
  case error {
    MigrationsDiffer(refusal:) -> migration.describe(refusal)
    QueryFailed(table:, reason:) ->
      "the query of the table " <> table <> " failed: " <> reason
    Refused(refusals:) ->
      string.join(list.map(refusals, refusal.describe), "\n")
  }
}
