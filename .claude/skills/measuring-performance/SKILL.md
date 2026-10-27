---
name: measuring-performance
description: Runtime inspection, benchmarks and load runs. Use for a timing, memory or load question.
---

# Measuring performance

- Inspect a running process with the runtime's own tools first: its state, a sampled stack, its collections, a trace of its messages.
- Change code for speed only after a benchmark or profile shows the bottleneck. A load run takes the machine alone.
- A benchmark lives in `dev/` and runs with `gleam run -m`. The typed-id benchmark (issue #12) was the pattern: each variant in its own module, a planted change to prove the harness can see one, and rounds paired.
