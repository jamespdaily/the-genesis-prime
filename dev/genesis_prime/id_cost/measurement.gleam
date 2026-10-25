//// The runtime's own clock and counters, read by the id-cost benchmark.

/// The size of one Erlang term in three measures.
pub type TermSizes {
  TermSizes(
    /// Words the term takes on the heap, a sub-term used twice counted once.
    heap_words: Int,
    /// Words the term would take if copied to another process, each use of a
    /// sub-term counted.
    copied_words: Int,
    /// Bytes of the term in the external term format.
    external_bytes: Int,
  )
}

/// The monotonic clock, in nanoseconds.
@external(erlang, "id_cost_ffi", "monotonic_nanoseconds")
pub fn monotonic_nanoseconds() -> Int

/// Garbage collects the calling process, so what it holds afterwards is only
/// what it still uses.
@external(erlang, "id_cost_ffi", "collect")
pub fn collect() -> Nil

/// The reductions the calling process has executed.
@external(erlang, "id_cost_ffi", "reductions")
pub fn reductions() -> Int

/// Starts counting the words the calling process allocates, after a garbage
/// collection that gives the count its starting point.
@external(erlang, "id_cost_ffi", "start_counting_allocation")
pub fn start_counting_allocation() -> Nil

/// Stops the count and returns the words the calling process allocated since
/// it started. The count comes from the used size of the young heap at each of
/// the process's garbage collections, so it is exact whatever the collections
/// kept.
@external(erlang, "id_cost_ffi", "stop_counting_allocation")
pub fn stop_counting_allocation() -> Int

/// Measures a term.
pub fn sizes_of(term: anything) -> TermSizes {
  TermSizes(
    heap_words: heap_words(term),
    copied_words: copied_words(term),
    external_bytes: external_bytes(term),
  )
}

@external(erlang, "erts_debug", "size")
fn heap_words(term: anything) -> Int

@external(erlang, "erts_debug", "flat_size")
fn copied_words(term: anything) -> Int

@external(erlang, "erlang", "external_size")
fn external_bytes(term: anything) -> Int
