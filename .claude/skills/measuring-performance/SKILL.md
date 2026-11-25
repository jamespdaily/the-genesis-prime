---
name: measuring-performance
description: Sets how timing, memory and load are measured here - runtime inspection, benchmarks in dev/, load runs and judging differences. Use for a timing, memory or load question, or before changing code for speed.
---

# Measuring performance

- Inspect a running process with the runtime's own tools first: its state, a sampled stack, its collections, a trace of its messages.
- Change code for speed only after a benchmark or profile shows the bottleneck. A load run takes the machine alone.
- Before a design or a claim rests on a load or timing number, rule out the instrument's own cost (tracing, profiling, a loaded machine) and check the number against a simple cost model; if it does not fit, rerun with sampling only.
- A benchmark lives in `dev/` and runs with `gleam run -m`: each variant in its own module, a planted change to prove the harness can see one, and rounds paired.
- A prototype or run that fell behind names its measured cause; a trial's test list names the known variants of the design and why each is in or out.
- Judge each difference by its absolute size against what a player or the host would notice, not only relative to the other options.
