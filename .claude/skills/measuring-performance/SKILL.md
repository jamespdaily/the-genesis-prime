---
name: measuring-performance
description: Runtime inspection, benchmarks and load runs. Use for a timing, memory or load question.
---

# Measuring performance

- Inspect a running process with the runtime's own tools first: its state, a sampled stack, its collections, a trace of its messages.
- Change code for speed only after a benchmark or profile shows the bottleneck. A load run takes the machine alone.
- A benchmark lives in `dev/` and runs with `gleam run -m`. The typed-id benchmark (issue #12) was the pattern: each variant in its own module, a planted change to prove the harness can see one, and rounds paired.
- A result that a prototype or run fell behind, or lost, names its measured cause; a trial's test list names the known variants of the design and why each is in or out.
- A choosing rule judges each difference by its absolute size against what a player or the host would notice, not only relative to the other options.
