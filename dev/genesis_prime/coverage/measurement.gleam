//// An engine's declaration set against what the client's data requires.

import genesis_prime/coverage/engine.{type EngineDeclaration}
import genesis_prime/coverage/starting_ability.{type MissingRow}
import genesis_prime/coverage/type_count
import genesis_prime/table/loader/store
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result

/// Where one type stands in an engine.
pub type Status {
  /// A rule of the engine handles the type.
  Handled
  /// A rule of the engine handles the type with a gap: what it does not handle, the
  /// fact file's key of the client's reading, and how many of the type's rows no rule
  /// reads (they are not handled).
  HandledWithGap(reason: String, fact_key: String, unread_rows: Int)
  /// The client's code was read for the type and the engine does not handle it:
  /// what it lacks and the fact file's key of the reading.
  DecodedMissing(reason: String, fact_key: String)
  /// The client's code was not read for the type.
  NotDecoded
}

/// One type of an engine's kind in the client's data.
pub type TypeLine {
  TypeLine(
    type_number: Int,
    rows: Int,
    /// The part of the engine's non-zero rows, from 0.0 to 1.0.
    share: Float,
    status: Status,
    /// The rows of the type among the starting abilities' spells; 0 for an engine
    /// the starting abilities do not use.
    starting_abilities: Int,
    /// How many of those rows no rule reads, which the starting abilities' column counts as
    /// not handled.
    starting_unread: Int,
  )
}

/// The measure of one engine.
pub type Measurement {
  /// The types in use, heaviest first.
  Measured(
    engine: EngineDeclaration,
    types: List(TypeLine),
    /// The non-zero values, all types together.
    rows: Int,
    /// The zero values, left out of every type.
    zero_values: Int,
    /// The types the engine's declaration names that no row uses: the ids it
    /// lists as handled and the types it lists as missing.
    breaches: List(Int),
    /// The types the engine both handles and lists as missing, and the types it lists
    /// as partial that it does not handle.
    conflicts: List(Int),
    /// The rows the starting abilities' trees name that the tables lack: the
    /// starting abilities' column is then empty and the measure fails.
    missing_rows: List(MissingRow),
  )
  /// The engine's types are not recorded; `needed` says what must be.
  Unmeasured(engine: EngineDeclaration, needed: String)
}

/// Measures one engine against the loaded tables: the types its source holds
/// counted by rows, each marked handled, decoded and missing, or not decoded, and
/// the declared types no row uses. An engine whose source does not record its
/// types is not measured.
pub fn measure(
  engine engine: EngineDeclaration,
  tables tables: store.Tables,
) -> Measurement {
  let #(starting, missing_rows) = case engine.starting_abilities {
    Some(values) ->
      case values(tables) {
        Ok(found) -> #(found, [])
        Error(missing) -> #([], missing)
      }
    None -> #([], [])
  }
  let unread = engine.unread_rows(tables, _)
  // A walk the tables cannot finish has no starting rows either, and `missing_rows`
  // below reports it, so a count it cannot make is 0.
  let unread_starting = fn(type_number) {
    engine.unread_starting_rows(tables, type_number) |> result.unwrap(0)
  }
  let measured = case engine.source {
    engine.TableColumns(values:, ..) ->
      from_values_reading(
        engine:,
        values: values(tables),
        starting:,
        unread:,
        unread_starting:,
      )
    engine.Cases(ids:, ..) ->
      from_values_reading(
        engine:,
        values: ids,
        starting:,
        unread:,
        unread_starting:,
      )
    engine.CasesNotRecorded(needed:, ..) -> Unmeasured(engine:, needed:)
  }
  case measured {
    Measured(..) -> Measured(..measured, missing_rows:)
    Unmeasured(..) -> measured
  }
}

/// Measures one engine over the type values of its source, one value per row
/// of the type column, and over the type values of the starting abilities' spells.
/// An engine whose source does not record its types is not measured, whatever
/// the values.
pub fn from_values(
  engine engine: EngineDeclaration,
  values values: List(Int),
  starting starting: List(Int),
) -> Measurement {
  from_values_reading(
    engine:,
    values:,
    starting:,
    unread: fn(_) { 0 },
    unread_starting: fn(_) { 0 },
  )
}

/// The same, with `unread` giving how many rows of a partial type no rule reads.
fn from_values_reading(
  engine engine: EngineDeclaration,
  values values: List(Int),
  starting starting: List(Int),
  unread unread: fn(Int) -> Int,
  unread_starting unread_starting: fn(Int) -> Int,
) -> Measurement {
  case engine.source {
    engine.CasesNotRecorded(needed:, ..) -> Unmeasured(engine:, needed:)
    engine.TableColumns(..) ->
      measured(
        engine:,
        values:,
        starting:,
        zero: type_count.EmptySlot,
        unread:,
        unread_starting:,
      )
    engine.Cases(..) ->
      measured(
        engine:,
        values:,
        starting:,
        zero: type_count.ATypeLikeAnyOther,
        unread:,
        unread_starting:,
      )
  }
}

fn measured(
  engine engine: EngineDeclaration,
  values values: List(Int),
  starting starting: List(Int),
  zero zero: type_count.ZeroMeans,
  unread unread: fn(Int) -> Int,
  unread_starting unread_starting: fn(Int) -> Int,
) -> Measurement {
  let count = type_count.count(values:, zero:)
  let in_starting =
    type_count.count(values: starting, zero:).types
    |> list.map(fn(counted) { #(counted.type_number, counted.rows) })
    |> dict.from_list
  let types =
    list.map(count.types, fn(counted) {
      let starting_rows =
        dict.get(in_starting, counted.type_number)
        |> option.from_result
        |> option.unwrap(0)
      TypeLine(
        type_number: counted.type_number,
        rows: counted.rows,
        share: counted.share,
        status: status_of(engine:, type_number: counted.type_number, unread:),
        starting_abilities: starting_rows,
        starting_unread: case starting_rows {
          0 -> 0
          _ -> unread_starting(counted.type_number)
        },
      )
    })
  let used = fn(declared) {
    list.any(count.types, fn(counted) { counted.type_number == declared })
  }
  let unused_handled = case engine.handled {
    engine.Listed(ids:) -> list.filter(ids, fn(declared) { !used(declared) })
    engine.Decoded(..) -> []
  }
  let unused = fn(gaps: List(engine.Missing)) {
    list.filter(gaps, fn(gap) { !used(gap.type_number) })
    |> list.map(fn(gap) { gap.type_number })
  }
  let handled_gaps = fn(gaps: List(engine.Missing), handled: Bool) {
    list.filter(gaps, fn(gap) {
      engine.handles(engine:, type_number: gap.type_number) == handled
    })
    |> list.map(fn(gap) { gap.type_number })
  }
  let conflicts =
    list.append(
      handled_gaps(engine.missing, True),
      handled_gaps(engine.partial, False),
    )
  Measured(
    engine:,
    types:,
    rows: count.rows,
    zero_values: count.zero_values,
    breaches: list.flatten([
      unused_handled,
      unused(engine.missing),
      unused(engine.partial),
    ]),
    conflicts:,
    missing_rows: [],
  )
}

/// Whether a rule handles the type, with a gap or without.
pub fn is_handled(status status: Status) -> Bool {
  case status {
    Handled | HandledWithGap(..) -> True
    DecodedMissing(..) | NotDecoded -> False
  }
}

/// Where the type stands: handled when the engine handles it, with its gap when the
/// engine lists it as partial, else decoded and missing when the engine lists it so,
/// else not decoded.
fn status_of(
  engine engine: EngineDeclaration,
  type_number type_number: Int,
  unread unread: fn(Int) -> Int,
) -> Status {
  use <- bool.guard(
    when: engine.handles(engine:, type_number:),
    return: case
      list.find(engine.partial, fn(partial) {
        partial.type_number == type_number
      })
    {
      Ok(partial) ->
        HandledWithGap(
          reason: partial.reason,
          fact_key: partial.fact_key,
          unread_rows: unread(type_number),
        )
      Error(Nil) -> Handled
    },
  )
  case
    list.find(engine.missing, fn(missing) { missing.type_number == type_number })
  {
    Ok(missing) ->
      DecodedMissing(reason: missing.reason, fact_key: missing.fact_key)
    Error(Nil) -> NotDecoded
  }
}
