//// An engine's declaration set against what the client's data requires.

import genesis_prime/coverage/engine.{type EngineDeclaration}
import genesis_prime/coverage/type_count
import genesis_prime/table/loader/store
import gleam/list

/// One type of an engine's kind in the client's data.
pub type TypeLine {
  TypeLine(
    type_number: Int,
    rows: Int,
    /// The part of the engine's non-zero rows, from 0.0 to 1.0.
    share: Float,
    /// Whether the engine's declaration lists the type.
    handled: Bool,
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
    /// The declared types that no row uses.
    breaches: List(Int),
  )
  /// The engine's types are not recorded; `needed` says what must be.
  Unmeasured(engine: EngineDeclaration, needed: String)
}

/// Measures one engine against the loaded tables: the types its source holds
/// counted by rows, each marked handled or not, and the declared types no row
/// uses. An engine whose source does not record its types is not measured.
pub fn measure(
  engine engine: EngineDeclaration,
  tables tables: store.Tables,
) -> Measurement {
  case engine.source {
    engine.TableColumns(values:, ..) ->
      from_values(engine:, values: values(tables))
    engine.Cases(ids:, ..) -> from_values(engine:, values: ids)
    engine.CasesNotRecorded(needed:, ..) -> Unmeasured(engine:, needed:)
  }
}

/// Measures one engine over the type values of its source, one value per row
/// of the type column. An engine whose source does not record its types is not
/// measured, whatever the values.
pub fn from_values(
  engine engine: EngineDeclaration,
  values values: List(Int),
) -> Measurement {
  case engine.source {
    engine.CasesNotRecorded(needed:, ..) -> Unmeasured(engine:, needed:)
    engine.TableColumns(..) ->
      measured(engine:, values:, zero: type_count.EmptySlot)
    engine.Cases(..) ->
      measured(engine:, values:, zero: type_count.ATypeLikeAnyOther)
  }
}

fn measured(
  engine engine: EngineDeclaration,
  values values: List(Int),
  zero zero: type_count.ZeroMeans,
) -> Measurement {
  let count = type_count.count(values:, zero:)
  let types =
    list.map(count.types, fn(counted) {
      TypeLine(
        type_number: counted.type_number,
        rows: counted.rows,
        share: counted.share,
        handled: list.contains(engine.handled, counted.type_number),
      )
    })
  let breaches =
    list.filter(engine.handled, fn(declared) {
      !list.any(count.types, fn(counted) { counted.type_number == declared })
    })
  Measured(
    engine:,
    types:,
    rows: count.rows,
    zero_values: count.zero_values,
    breaches:,
  )
}
