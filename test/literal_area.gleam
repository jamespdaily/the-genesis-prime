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
//// - **A load waits for the collector.** Erasing a persistent term does not free
////   it: the VM frees it once every process has been asked whether it still
////   reads it, one erased term at a time, each its own round over all processes
////   (`erts_literal_area_collector`). Until then the allocator still holds it,
////   and a new load needs room beside it. A test that erases thousands of terms
////   (a world's content) keeps the rounds going for seconds, and each load that
////   starts meanwhile adds its bytes to the held ones. A load starts only when
////   what the allocator holds beyond the live terms is at most
////   `pending_limit_bytes` (`wait_until_released`, called by every key
////   `owned_key` makes), and a process that holds no load starts one only while
////   `owned_key.loads_held_limit` processes hold or are about to hold one.
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

/// `tables_held_twice` over the given keys and terms instead of the VM's.
@external(erlang, "literal_area_ffi", "names_held_twice")
pub fn names_held_twice(in terms: List(#(key, term))) -> List(String)

/// The names of every table term the VM holds, of any size, in order.
@external(erlang, "literal_area_ffi", "table_names")
pub fn table_names() -> List(String)

/// The bytes the literal allocator holds that no persistent term lives in: the
/// terms erased and waiting for the literal area collector to release them (it
/// takes one erased term at a time and asks every process whether it still reads
/// it), and the VM's own literals. The allocator's allocated blocks less the
/// persistent terms' live memory.
@external(erlang, "literal_area_ffi", "pending_bytes")
pub fn pending_bytes() -> Int

/// The most `pending_bytes` that `wait_until_released` leaves a new load with.
@external(erlang, "literal_area_ffi", "pending_limit_bytes")
pub fn pending_limit_bytes() -> Int

/// Returns once `pending_bytes` is at most `pending_limit_bytes`, checking again
/// every millisecond: the wait is for the collector to catch up, which it does
/// whatever the tests do, so it ends. Every key a test makes for a load
/// (`owned_key`) calls it first.
@external(erlang, "literal_area_ffi", "wait_until_released")
pub fn wait_until_released() -> Nil

/// How many times `wait_until_released` has returned in this VM.
@external(erlang, "literal_area_ffi", "admissions")
pub fn admissions() -> Int
