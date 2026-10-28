//// The coverage measure: the count of the client's rows by type against what
//// each engine declares it handles. The planted tests write small tables laid
//// out by the generated schemas and run everywhere; the real run reads the
//// client's extracted tables and is skipped where `GENESIS_NO_CLIENT=1`.
////
//// Expected values and their sources:
//// - the measure's rule: a type's rows are the non-zero values of the engine's
////   type column(s) that equal it, heaviest first, ties by the lower type
////   number; a zero names no type and is counted apart; a share is a type's
////   rows over all the engine's non-zero rows.
//// - the engine's type columns are the client's own column names in each
////   table's schema (`game_table.schema` in the fact file): Prerequisite
////   `prerequisiteTypeId0` to `2`, QuestObjective `type`, Spell4Effects
////   `effectType`, Creature2 `CreationTypeEnum`. The client's file holds each
////   value as a signed 32-bit integer at the column's record offset
////   (`game_table.file`, `game_table.column_type`).
//// - the message dispatcher has a case for each id from 97 to 2418 whose table
////   entry is not the default: 2,322 entries, 1,677 of them the default, so
////   645 ids with a case (fact 0x1403f1344; fact 0x1403ec6a0: "645 of those
////   ids have a handler").

import client_tables
import genesis_prime/coverage/checklist
import genesis_prime/coverage/engine.{type EngineDeclaration, EngineDeclaration}
import genesis_prime/coverage/measurement.{
  type Measurement, type TypeLine, Measured, TypeLine, Unmeasured,
}
import genesis_prime/table/creature2
import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file.{type Schema}
import genesis_prime/table/prerequisite
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4_effects
import gleam/bit_array
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/string
import owned_test
import planted_table.{Integer}
import unitest

/// Plants a QuestObjective table with one row per type value, ids from 1, and
/// measures the engine over it.
fn measured_over_planted_objectives(
  engine: EngineDeclaration,
  types: List(Int),
) -> Measurement {
  let rows =
    list.index_map(types, fn(type_number, index) {
      planted_table.row(quest_objective.schema, [
        #("ID", Integer(index + 1)),
        #("type", Integer(type_number)),
      ])
    })
  let file =
    planted_table.bytes(planted_table.table(quest_objective.schema, rows))
  use folder <- planted_table.in_folder([#("QuestObjective", file)])
  let assert Ok(tables) =
    store.load(
      under: reference.new(),
      from: folder,
      entries: [quest_objective.entry()],
      requirements: [],
    )
    as "a planted QuestObjective table loads"
  let measured = measurement.measure(engine, tables)
  store.unload(tables)
  measured
}

/// The declaration of the engine with this name.
fn engine_named(name: String) -> EngineDeclaration {
  let assert Ok(found) =
    list.find(engine.all(), fn(declaration) { declaration.name == name })
    as { "no engine is named " <> name }
  found
}

fn lines(measured: Measurement) -> List(#(Int, Int, Float)) {
  let assert Measured(types:, ..) = measured
    as "the engine's source is a table, so it is measured"
  list.map(types, fn(line) { #(line.type_number, line.rows, line.share) })
}

/// Eight rows with a type (7 four times, 2 twice, 5 and 9 once) and three
/// rows with none; the shares are exact in binary.
const planted_types = [7, 0, 2, 7, 5, 7, 0, 9, 2, 7, 0]

pub fn types_are_counted_by_rows_heaviest_first_with_ties_by_type_number_test() -> Nil {
  use <- owned_test.run(10_000)
  let measured =
    measured_over_planted_objectives(
      engine_named("Quest objectives"),
      planted_types,
    )
  assert lines(measured)
    == [#(7, 4, 0.5), #(2, 2, 0.25), #(5, 1, 0.125), #(9, 1, 0.125)]
    as "the rule: most rows first; 5 and 9 have one row each, so the lower type number comes first; each share is rows over the 8 non-zero rows"
  let assert Measured(rows:, zero_values:, ..) = measured
    as "the planted table is measured"
  assert rows == 8 as "eight planted rows have a type"
  assert zero_values == 3
    as "three planted rows hold 0, which is no type and is counted apart"
}

pub fn a_prerequisite_counts_the_values_of_its_three_type_columns_test() -> Nil {
  use <- owned_test.run(10_000)
  // Prerequisite.prerequisiteTypeId0 to 2: each row holds up to three
  // conditions, so the table's types are the values of all three columns.
  let triples = [#(4, 5, 7), #(4, 0, 0), #(5, 4, 6), #(4, 0, 0)]
  let rows =
    list.index_map(triples, fn(triple, index) {
      planted_table.row(prerequisite.schema, [
        #("ID", Integer(index + 1)),
        #("prerequisiteTypeId0", Integer(triple.0)),
        #("prerequisiteTypeId1", Integer(triple.1)),
        #("prerequisiteTypeId2", Integer(triple.2)),
      ])
    })
  let file = planted_table.bytes(planted_table.table(prerequisite.schema, rows))
  use folder <- planted_table.in_folder([#("Prerequisite", file)])
  let assert Ok(tables) =
    store.load(
      under: reference.new(),
      from: folder,
      entries: [prerequisite.entry()],
      requirements: [],
    )
    as "a planted Prerequisite table loads"
  let measured = measurement.measure(engine_named("Prerequisites"), tables)
  store.unload(tables)
  assert lines(measured)
    == [#(4, 4, 0.5), #(5, 2, 0.25), #(6, 1, 0.125), #(7, 1, 0.125)]
    as "4 is in the first column of three rows and the second of one; 5 twice; 6 and 7 once; eight conditions in all"
  let assert Measured(rows:, zero_values:, ..) = measured
    as "the planted table is measured"
  assert rows == 8 as "eight conditions with a type"
  assert zero_values == 4
    as "four of the twelve type values are 0: the empty second and third conditions"
}

pub fn a_handled_type_is_marked_and_every_other_keeps_its_share_test() -> Nil {
  use <- owned_test.run(10_000)
  let declared =
    EngineDeclaration(..engine_named("Quest objectives"), handled: [7, 2])
  let assert Measured(types:, breaches:, ..) =
    measured_over_planted_objectives(declared, planted_types)
    as "the planted table is measured"
  assert types
    == [
      TypeLine(type_number: 7, rows: 4, share: 0.5, handled: True),
      TypeLine(type_number: 2, rows: 2, share: 0.25, handled: True),
      TypeLine(type_number: 5, rows: 1, share: 0.125, handled: False),
      TypeLine(type_number: 9, rows: 1, share: 0.125, handled: False),
    ]
    as "the engine declares 7 and 2, so those two are handled and 5 and 9 are not, each with the share it has without the declaration"
  assert breaches == [] as "7 and 2 are types some row uses"
}

pub fn a_declared_type_no_row_uses_is_a_breach_test() -> Nil {
  use <- owned_test.run(10_000)
  let declared =
    EngineDeclaration(..engine_named("Quest objectives"), handled: [7, 99, 0])
  let assert Measured(types:, breaches:, ..) =
    measured_over_planted_objectives(declared, planted_types)
    as "the planted table is measured"
  assert breaches == [99, 0]
    as "the rule: a declared type must be a type some row uses; no row has 99, and 0 is no type"
  assert list.filter(types, fn(line) { line.handled })
    |> list.map(fn(line) { line.type_number })
    == [7]
    as "only 7 is both declared and used"
}

/// Each engine's table and the schema of it, to check the declared columns
/// against.
fn schema_of(table_name: String) -> Schema {
  case table_name {
    "Prerequisite" -> prerequisite.schema
    "QuestObjective" -> quest_objective.schema
    "Spell4Effects" -> spell4_effects.schema
    "Creature2" -> creature2.schema
    _ -> panic as { "no schema is known for the table " <> table_name }
  }
}

pub fn every_engine_declares_its_area_and_the_type_columns_its_table_has_test() -> Nil {
  use <- owned_test.run(10_000)
  let declared = engine.all()
  assert list.map(declared, fn(declaration) { declaration.area_issue })
    == [47, 48, 49, 50, 51]
    as "Milestone 2's area issues: prerequisites 47, quest objectives 48, spell effects 49, unit types 50, messages 51"
  assert list.map(declared, fn(declaration) { declaration.name })
    == [
      "Prerequisites",
      "Quest objectives",
      "Spell effects",
      "Unit types",
      "Client message routing",
    ]
    as "the engines' names in the milestone's table"
  let columns =
    list.filter_map(declared, fn(declaration) {
      case declaration.source {
        engine.TableColumns(table:, columns:, evidence:, ..) -> {
          assert evidence != "" as { table <> " declares no evidence" }
          let names =
            list.map(schema_of(table).columns, fn(column) { column.name })
          list.each(columns, fn(column) {
            assert list.contains(names, column)
              as { table <> " has no column " <> column }
          })
          Ok(#(table, columns))
        }
        engine.Cases(..) | engine.CasesNotRecorded(..) -> Error(Nil)
      }
    })
  assert columns
    == [
      #("Prerequisite", [
        "prerequisiteTypeId0",
        "prerequisiteTypeId1",
        "prerequisiteTypeId2",
      ]),
      #("QuestObjective", ["type"]),
      #("Spell4Effects", ["effectType"]),
      #("Creature2", ["CreationTypeEnum"]),
    ]
    as "the client's column names in each table's schema (game_table.schema)"
}

/// How many of a column's values in the client's own file are not zero, and
/// how many are zero, read from the file's bytes without the code under test:
/// the record count at 0x30, the record block's offset at 0x40 (counted from
/// 0x60) and each column's offset in the record by the client's layout.
fn counted_by_the_file(
  file file: String,
  schema schema: Schema,
  columns columns: List(String),
) -> #(Int, Int) {
  let bytes = client_tables.read(file)
  let assert <<
    _:bytes-size(0x30),
    record_count:size(64)-little,
    _:bytes-size(8),
    block_offset:size(64)-little,
    _:bits,
  >> = bytes
    as "the client's table file is shorter than its header"
  let #(fields, record_size) = tbl_file.layout(schema.columns)
  let offsets =
    list.filter_map(fields, fn(field) {
      case list.contains(columns, field.column.name) {
        True -> Ok(field.offset)
        False -> Error(Nil)
      }
    })
  assert list.length(offsets) == list.length(columns)
    as "every declared column is in the schema"
  let values =
    int.range(from: 0, to: record_count, with: [], run: fn(found, record) {
      list.fold(offsets, found, fn(found, offset) {
        let assert Ok(<<value:size(32)-little-signed>>) =
          bit_array.slice(
            bytes,
            0x60 + block_offset + record * record_size + offset,
            4,
          )
          as "the value lies outside the file"
        [value, ..found]
      })
    })
  let zeros = list.count(values, fn(value) { value == 0 })
  #(list.length(values) - zeros, zeros)
}

fn heaviest_first(types: List(TypeLine)) -> Bool {
  list.window_by_2(types)
  |> list.all(fn(pair) {
    let #(heavier, lighter) = pair
    heavier.rows > lighter.rows
    || {
      heavier.rows == lighter.rows && heavier.type_number < lighter.type_number
    }
  })
}

pub fn every_engine_of_the_clients_tables_gets_a_list_adding_up_to_its_non_zero_rows_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(engine.all(), fn(declared) {
    let measured = measurement.measure(declared, tables)
    case declared.source {
      engine.TableColumns(table:, columns:, ..) -> {
        let assert Measured(types:, rows:, zero_values:, breaches:, ..) =
          measured
          as { table <> " is a table the client has, so it is measured" }
        let #(non_zero, zero) =
          counted_by_the_file(file: table, schema: schema_of(table), columns:)
        assert non_zero > 0 as { table <> ": the client's file has types" }
        assert int.sum(list.map(types, fn(line) { line.rows })) == non_zero
          as {
            table
            <> ": the rows of the types add up to the non-zero values the file holds"
          }
        assert rows == non_zero
          as { table <> ": the total of the non-zero rows" }
        assert zero_values == zero
          as { table <> ": the zero values the file holds, counted apart" }
        assert heaviest_first(types)
          as { table <> ": heaviest first, ties by the lower type number" }
        assert breaches == []
          as { table <> ": every declared type is one some row uses" }
      }
      engine.Cases(ids:, ..) -> {
        let assert Measured(types:, rows:, ..) = measured
          as "message ids that are recorded are measured"
        assert list.length(ids) == 352
          as "fact 0x1403309a0: the client sends 352 ids in all"
        assert list.length(types) == 352
          as "one row for each id the client sends"
        assert rows == 352 as "each id is one row"
        assert list.all(ids, fn(id) { id >= 0 && id <= 0xFFFF })
          as "a frame's message id is 16 bits (fact 0x140332920, WriteMessageFrame)"
      }
      engine.CasesNotRecorded(needed:, ..) -> {
        assert measured == Unmeasured(engine: declared, needed:)
          as "ids nobody recorded are reported with what is needed, not guessed"
      }
    }
  })
}

fn quest_objectives_over(types: List(Int)) -> Measurement {
  measurement.from_values(
    EngineDeclaration(..engine_named("Quest objectives"), handled: [7, 2]),
    types,
  )
}

pub fn the_checklist_lists_each_type_heaviest_first_with_its_rows_share_and_whether_it_is_handled_test() -> Nil {
  use <- owned_test.run(10_000)
  let text = checklist.render([quest_objectives_over(planted_types)])
  let expected_lines = [
    "- [x] type 7: 4 rows (50.0%)",
    "- [x] type 2: 2 rows (25.0%)",
    "- [ ] type 5: 1 row (12.5%)",
    "- [ ] type 9: 1 row (12.5%)",
  ]
  assert string.contains(text, string.join(expected_lines, "\n"))
    as "the area's checklist: a line per type, [x] when handled, heaviest first, a type with one row written 'row'"
  assert string.starts_with(text, "## Quest objectives (#48)\n")
    as "the heading names the engine and its area issue"
  assert string.contains(text, "QuestObjective.type")
    as "the heading's text names the column that holds the type"
  assert string.contains(
    text,
    "8 rows over 4 types; 3 zero values left out; 2 of 4 types handled (75.0% of rows)",
  )
    as "the totals: 8 non-zero rows, 4 types, 3 zeros, the two handled types carry 6 of the 8 rows"
}

pub fn the_totals_give_each_engine_its_types_rows_zeros_and_handled_types_test() -> Nil {
  use <- owned_test.run(10_000)
  let text =
    checklist.totals([
      quest_objectives_over(planted_types),
      Unmeasured(
        engine: engine_named("Client message routing"),
        needed: "the ids",
      ),
    ])
  assert text
    == string.join(
      [
        "| Engine | Types in use | Rows | Zero values | Types handled |",
        "| --- | --- | --- | --- | --- |",
        "| Quest objectives (#48) | 4 | 8 | 3 | 2 |",
        "| Client message routing (#51) | not measured | | | |",
      ],
      "\n",
    )
    as "one row per engine; an engine whose types are not recorded is not measured"
}

pub fn an_engine_whose_cases_are_not_recorded_says_what_is_needed_test() -> Nil {
  use <- owned_test.run(10_000)
  let text =
    checklist.render([
      Unmeasured(
        engine: engine_named("Client message routing"),
        needed: "the 645 ids",
      ),
    ])
  assert string.starts_with(text, "## Client message routing (#51)\n")
    as "the heading names the engine and its area issue"
  assert string.contains(text, "Not measured: the 645 ids")
    as "no list is made from ids nobody recorded; the text says what is needed"
  assert !string.contains(text, "- [")
    as "no checklist line for an unmeasured engine"
}

pub fn the_message_checklist_says_each_id_the_client_sends_is_one_row_test() -> Nil {
  use <- owned_test.run(10_000)
  let text =
    checklist.render([
      measurement.from_values(
        EngineDeclaration(..engine_named("Client message routing"), handled: [
          1,
        ]),
        [0, 1, 2, 0x244],
      ),
    ])
  assert string.starts_with(text, "## Client message routing (#51)\n")
    as "the heading names the engine and its area issue"
  assert string.contains(
    text,
    "Type: the message ids the client sends to the server, one row for each id.",
  )
    as "the header says what a row is: an id the client sends, as the facts of its send paths give it"
  assert string.contains(
    text,
    "- [ ] type 0: 1 row (25.0%)\n- [x] type 1: 1 row (25.0%)\n- [ ] type 2: 1 row (25.0%)\n- [ ] type 580: 1 row (25.0%)",
  )
    as "equal rows: the lower id first, and 1 is declared handled so it is checked; 580 is 0x244; a quarter each; id 0 is an id like any other, the network layer's own (fact 0x140332580)"
}
