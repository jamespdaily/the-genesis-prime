//// An engine's declaration set against what the client's data requires.

import genesis_prime/coverage/engine.{type EngineDeclaration}
import genesis_prime/table/loader/store

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

/// Measures one engine against the loaded tables.
pub fn measure(engine: EngineDeclaration, tables: store.Tables) -> Measurement {
  todo as "measures an engine"
}

/// Measures one engine over the type values of its source.
pub fn from_values(
  engine: EngineDeclaration,
  values: List(Int),
) -> Measurement {
  todo as "measures an engine over values"
}
