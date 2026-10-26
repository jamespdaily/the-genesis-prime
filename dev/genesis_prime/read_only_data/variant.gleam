//// What every place the tables can live has in common: how it is loaded, what
//// it costs in memory, and how a process opens it for reading. The benchmark
//// drives each variant through these types only.

import genesis_prime/read_only_data/table_data.{type Source}

/// One place the tables can live.
pub type Variant {
  Variant(
    /// The name printed in every table.
    name: String,
    /// Loads the source into this variant, in the calling process, and returns
    /// once every reader can use it. The count is how many holder processes
    /// the owner-state variant starts, each given its own copy; the other
    /// variants ignore it.
    load: fn(Source, Int) -> Loaded,
  )
}

/// A variant with the tables in it.
pub type Loaded {
  Loaded(
    /// What the loaded variant holds, measured now.
    memory: fn() -> Memory,
    /// Opens the tables for reading in the calling process. Persistent terms
    /// and ETS only look the tables up; owner state takes its own copy.
    open_reader: fn() -> Reader,
    /// Frees everything the load made: persistent terms, tables, processes.
    stop: fn() -> Nil,
  )
}

/// A process's way to read the loaded tables.
pub type Reader {
  Reader(
    /// Reads, for each 4 bytes of the stream (table in the first byte, id in
    /// the other three), that table's row with that id, and checks the row's
    /// id is the one asked for. Returns how many rows it read and checked.
    read_all: fn(BitArray) -> Int,
  )
}

/// What a loaded variant holds.
pub type Memory {
  Memory(
    /// The bytes the choosing rule counts.
    bytes: Int,
    /// How `bytes` was measured and what else was measured, for the printed
    /// table.
    detail: String,
  )
}
