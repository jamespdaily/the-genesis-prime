//// The literal area of the test VM: the region the VM keeps its persistent
//// terms in (literal_alloc, 1 GiB unless `+MIscs` says otherwise). The suite
//// holds the client's tables there for the whole run, so a test that leaves
//// terms behind, or erases tens of megabytes at once, takes room from every
//// later test, and a full region ends the VM (`literal_alloc: Cannot allocate`)
//// partway through a run.
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

/// The names of the client's tables of which two persistent terms are held, in
/// order: a real table loaded under two keys takes its bytes twice.
@external(erlang, "literal_area_ffi", "tables_held_twice")
pub fn tables_held_twice() -> List(String)
