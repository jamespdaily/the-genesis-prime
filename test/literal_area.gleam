//// The literal area of the test VM: the region the VM keeps its persistent
//// terms in (literal_alloc, 1 GiB unless `+MIscs` says otherwise). The suite
//// holds the client's tables there for the whole run, and a full region ends
//// the VM (`literal_alloc: Cannot allocate`) partway through a run.
////
//// ```text
//// genesis_prime_test.main -- GENESIS_LITERAL_PEAK_FILE set? --> record_peak
////                                                                   |
////      sampler process: every 20 ms reads the allocator's own highest
////      carriers size, and writes the file again when it has grown
////                                                                   |
//// ./check, once the run has ended: reads the file, compares it with its bound
//// ```
////
//// - **The peak is the allocator's own record** of its carriers' size since the
////   VM started, not a sum of blocks: a request needs one free stretch of the
////   region, and the carriers are what hold the region (measured on a fill test
////   in a fresh VM: the carriers fill 97% of the region and no more).
//// - **A test stores nothing and erases nothing.** A stored value is put once,
////   by a shared load (`database_support.once`) or the server's start, and a
////   test's own tables are built on its heap, so no test leaves a term in the
////   area or waits for the collector to release one.

import genesis_prime/table/loader/store.{type Tables}

/// Starts a process that keeps the file holding the literal allocator's highest
/// carriers size so far, in bytes, as decimal digits and a line end. The file
/// is replaced whole, so a reader never sees half a number.
@external(erlang, "literal_area_ffi", "record_peak")
pub fn record_peak(into file: String) -> Nil

/// The literal allocator's highest carriers size since the VM started, in bytes.
@external(erlang, "literal_area_ffi", "carriers_peak")
pub fn carriers_peak() -> Int

/// How many bytes the persistent terms the VM holds take now.
@external(erlang, "literal_area_ffi", "persistent_term_memory")
pub fn persistent_term_memory() -> Int

/// How many persistent terms the VM holds now.
@external(erlang, "literal_area_ffi", "persistent_term_count")
pub fn persistent_term_count() -> Int

/// How many bytes the literal allocator holds in blocks now, whether a persistent
/// term lives in them or not: the terms and the VM's own literals, and what has
/// been erased and not yet released by the collector.
@external(erlang, "literal_area_ffi", "allocated_bytes")
pub fn allocated_bytes() -> Int

/// How many of the tables the first holds the second does not hold as the very
/// same term, the same words and not an equal copy: 0 when the second shares
/// every table of the first.
@external(erlang, "literal_area_ffi", "tables_not_shared")
pub fn tables_not_shared(first: Tables, second: Tables) -> Int
