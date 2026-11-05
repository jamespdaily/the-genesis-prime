//// An engine's declaration set against what the client's data requires.

import genesis_prime/coverage/engine.{type EngineDeclaration}
import genesis_prime/coverage/type_count
import genesis_prime/table/loader/store
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

/// Where one type stands in an engine.
pub type Status {
  /// A rule of the engine handles the type.
  Handled
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
    /// The types the engine both handles and lists as missing.
    conflicts: List(Int),
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
  let starting = case engine.starting_abilities {
    Some(values) -> values(tables)
    None -> []
  }
  case engine.source {
    engine.TableColumns(values:, ..) ->
      from_values(engine:, values: values(tables), starting:)
    engine.Cases(ids:, ..) -> from_values(engine:, values: ids, starting:)
    engine.CasesNotRecorded(needed:, ..) -> Unmeasured(engine:, needed:)
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
  case engine.source {
    engine.CasesNotRecorded(needed:, ..) -> Unmeasured(engine:, needed:)
    engine.TableColumns(..) ->
      measured(engine:, values:, starting:, zero: type_count.EmptySlot)
    engine.Cases(..) ->
      measured(engine:, values:, starting:, zero: type_count.ATypeLikeAnyOther)
  }
}

fn measured(
  engine engine: EngineDeclaration,
  values values: List(Int),
  starting starting: List(Int),
  zero zero: type_count.ZeroMeans,
) -> Measurement {
  let count = type_count.count(values:, zero:)
  let in_starting =
    list.fold(starting, dict.new(), fn(counts, type_number) {
      dict.upsert(counts, type_number, fn(found) {
        case found {
          Some(so_far) -> so_far + 1
          None -> 1
        }
      })
    })
  let types =
    list.map(count.types, fn(counted) {
      TypeLine(
        type_number: counted.type_number,
        rows: counted.rows,
        share: counted.share,
        status: status_of(engine:, type_number: counted.type_number),
        starting_abilities: dict.get(in_starting, counted.type_number)
          |> option.from_result
          |> option.unwrap(0),
      )
    })
  let used = fn(declared) {
    list.any(count.types, fn(counted) { counted.type_number == declared })
  }
  let unused_handled = case engine.handled {
    engine.Listed(ids:) -> list.filter(ids, fn(declared) { !used(declared) })
    engine.Decoded(..) -> []
  }
  let unused_missing =
    list.filter(engine.missing, fn(missing) { !used(missing.type_number) })
    |> list.map(fn(missing) { missing.type_number })
  let conflicts =
    list.filter_map(engine.missing, fn(missing) {
      case engine.handles(engine:, type_number: missing.type_number) {
        True -> Ok(missing.type_number)
        False -> Error(Nil)
      }
    })
  Measured(
    engine:,
    types:,
    rows: count.rows,
    zero_values: count.zero_values,
    breaches: list.append(unused_handled, unused_missing),
    conflicts:,
  )
}

/// Where the type stands: handled when the engine handles it, else decoded and
/// missing when the engine lists it so, else not decoded.
fn status_of(
  engine engine: EngineDeclaration,
  type_number type_number: Int,
) -> Status {
  use <- bool.guard(
    when: engine.handles(engine:, type_number:),
    return: Handled,
  )
  case
    list.find(engine.missing, fn(missing) { missing.type_number == type_number })
  {
    Ok(missing) ->
      DecodedMissing(reason: missing.reason, fact_key: missing.fact_key)
    Error(Nil) -> NotDecoded
  }
}
