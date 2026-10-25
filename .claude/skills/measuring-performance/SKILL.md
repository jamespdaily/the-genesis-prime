---
name: measuring-performance
description: How to measure performance in the-genesis-prime - timing runs on mains power, adding up runs, load runs that take the machine alone, how busy a BEAM process is and where its time goes, inspecting a running process with the runtime's own tools, memory by physical footprint, a BEAM process's heap (live data, collections, tracing, an OTP build with logging), and timing Postgres layer by layer. Use when an issue asks how fast, how much memory or how many players, when a process's memory grows or it falls behind its messages, or when a query looks slow, even if the request only says "measure this".
---

# Measuring performance

Post every measurement on its issue as a dated comment, with numbers. Inspect a running process with the runtime's own tools first: its state, a sampled stack, its collections, a trace of its messages. observer, recon, `sys:get_state` and tracing found every heap and load problem so far.

## Runs

- **A load, timing or memory run takes the machine alone.** No test run or other load run goes beside it; load runs beside test runs skewed their numbers.
- **Time only on mains power,** and record the charger's wattage with every timing figure (`pmset -g batt`, `system_profiler SPPowerDataType`). Runs on a battery that fell to 4% gave CPU and p99 numbers that did not count, and runs on a 140 W and a 45 W charger compare only roughly.
- **Prove a comparison run on main ran** before using its numbers. Stash or delete any scratch module first: an untracked module that fails to compile stops main's build. Check its passed line.
- **A script that stashes code during a run needs an exit trap that pops the stash** (`trap 'git stash pop' EXIT`).
- **Never rebuild while an experiment runs.** Each new runtime loads its code from the build folder, so a rebuild changes the code of the runtimes started later.
- **Add up numbers across runs with a script** that reads the saved output files, never by hand. Check every total and range in a comment against the files before posting it.
- **A load climbs while its simulated players start.** When they start 300 ms apart, 400 of them take two minutes to all be moving. Sample after the last one starts, and record how many players the process holds while sampling.
- **A simulated player's late steps measure its own pace, not the server's.** They read 0 while a map's queue held 11,366 moves. Read the server's queue and memory instead, on the launcher's dashboard.

## How busy a BEAM process is

- **Sample the process's stack from another process,** every 2 ms, with `process_info(Pid, current_stacktrace)`. A sample is idle when its top frame is the actor's receive (`gleam@otp@actor:loop` or `gleam_erlang_ffi:select`); the busy share is the share of samples that are not. Count each function once a sample, and divide its share by the busy share for its share of the work. Raise `backtrace_depth` for the run, or deep frames drop off.
- **Count the messages with a `receive` trace over a few seconds before sampling,** not during it. Busy time per message is the busy share over messages a second, and holds only while the process keeps up.
- **A `receive` trace counts messages as they arrive, not as they are handled.** Once the queue grows, busy time over arrivals understates a message's cost; take the cost from a run that keeps up.
- **Measure again after a fix that changed the process's collections.** A map was busy in 99% of samples while a collector bug grew its heap; with the bug fixed it was 38–48%, and its sight checks set its ceiling.

## Memory

- **Measure an OS process's memory by its physical footprint, not `ps`.** macOS compresses idle pages, and `ps -o rss` leaves them out: one server read 78 MB in `ps` and 2,374 MB in `footprint <pid>`.
- **Memory outside every BEAM process can depend on the operating system.** Each socket's receive buffer is the system's `recbuf`: 400 KB per connection on macOS loopback, 128 KB on Linux. Say which system a number came from.

### A BEAM process's heap

- **Give each figure in words and bytes,** such as "1,093 M words (8.7 GB)". A word is 8 bytes.
- **`process_info(Pid, memory)` and `total_heap_size` count the heap block, not live data.** For live data, collect first with `erlang:garbage_collect(Pid)`, then read `heap_size` from `process_info(Pid, garbage_collection_info)`. Its `recent_size` can be stale: it read 362 M words while the live heap was 3.76 M.
- **`erts_debug:size/1` is too slow for a term of gigabytes;** it timed out after 600 s. `erts_debug:flat_size/1` is fast, but counts shared parts again and walks into persistent terms and literals, so it overstates what a heap holds.
- **`sys:get_state/2` hands back a copy without its sharing,** and a Gleam actor does not answer `sys:replace_state`. Size the fields of the `sys:get_state` copy, and compare the copy's total with the live heap: for a map at 400 players they were 307,703 and 298,417 words. Leave out the persistent terms the state points at.
- **A crash dump lists the terms reachable from a process's stack, not its registers,** so a running process's in-flight data is missing from it.
- **To watch a process's collections, trace it** with `erlang:trace(Pid, true, [garbage_collection, monotonic_timestamp, {tracer, T}])`. Each start and end event gives the heap, old heap, heap fragments (`mbuf_size`) and block sizes. A heap block that grows from collection to collection while a forced collection shows little live data is the collector bug the designing-processes skill describes.
- **`call_count` counts calls in every process.** To count one process's calls, trace that process with `call` and a match spec, such as `[{['$1'], [{'>', {map_size, '$1'}, 1000}], [{message, {caller}}]}]`.
- **To see inside OTP, build it with logging.** Unpack the release tarball for the installed version into the scratch folder, add `erts_fprintf(stderr, ...)` where needed, then `./configure --prefix=<scratch>/install --with-ssl=/opt/homebrew/opt/openssl@3` and `make -j12 && make install`. It takes about 15 minutes; the server needs `crypto`, hence OpenSSL. Run with the build's `bin` first on `PATH`. This is how a map's growth to 25–29 GB was traced to the collector bug.

## Postgres layer by layer

- **Run every query through `EXPLAIN (ANALYZE, BUFFERS)`** on the development database. zsh does not split a variable into words, so wrap psql in a function with the password in the environment: `q() { PGPASSWORD=postgres psql -h 127.0.0.1 -p 5433 -U postgres -d genesis_prime_dev -c "$1"; }`.
- **Time each layer of a slow read:** Postgres alone (the plan's execution time); psql, with its output sent to `/dev/null`; pog with `decode.dynamic`, which is pgo's own cost; pog with the real decoders; then the Gleam code that builds values from the rows. pgo costs about 2 µs a row, so fewer, wider rows usually beat any index.
- **Try an index or a schema change in a transaction you roll back:** `begin; create index ...; analyze ...; explain (analyze) ...; rollback;`. Check afterwards that nothing stayed.
- **Before blaming the planner, compare its row estimates with actual rows.** A high cost with accurate rows comes from the plan's shape, not the statistics.
- **Time the server's real read** with a scratch module in `dev/` over several rounds, the first one cold. Report the spread, not one number, and delete the module afterwards.
