//// The guidance-path rule: every repository path that CLAUDE.md, a skill or an
//// agent names exists. Expected values are CLAUDE.md's rule that every
//// requirement lives where it is enforced, so a path the guidance names must
//// be a real one.
////
//// What counts as a path: text between single backticks that holds no space,
//// glob star, angle bracket, colon, brace or parenthesis, does not start with
//// `/` or `~`, and either contains a `/` or names a file with a stem and one
//// of the extensions `gleam`, `md`, `py`, `toml`, `sql`, `json`, `sh`, `erl`,
//// `yml` or `yaml`. A path exists when it, or a directory it opens (with or
//// without a trailing slash), is in the repository list, read from the
//// repository root or from the folder of the guidance file that names it (a
//// skill names its own `references/` and `scripts/` that way). The breach is
//// reported against the guidance file at the line that names the path.
//// Everything else between backticks is not a path: a command, a glob, a
//// placeholder like `jimd/<issue>-<topic>`, a URL, an absolute or home path, a
//// bare extension like `.tbl`, a name with another extension like
//// `WildStar64.exe`.

import code_rule/guidance_path
import code_rule/repository
import gleam/list
import gleam/string
import owned_test

const repository_paths = [
  "CLAUDE.md",
  "gleam.toml",
  "src/planted/server.gleam",
  "src/planted/client_archive.gleam",
  ".claude/skills/planted/SKILL.md",
  ".claude/skills/planted/references/facts.toml",
  ".claude/skills/planted/scripts/check.py",
]

fn breach_lines(guidance: List(#(String, String))) -> List(Int) {
  guidance_path.breaches(guidance, repository_paths)
  |> list.map(fn(breach) { breach.line })
}

pub fn a_path_that_is_not_in_the_repository_is_a_breach_at_its_line_test() -> Nil {
  use <- owned_test.run(5000)
  let text =
    "Intro.\n\nThe server is `src/planted/server.gleam`.\nThe codec is `src/planted/codec.gleam`.\n"
  let breaches =
    guidance_path.breaches([#("CLAUDE.md", text)], repository_paths)
  let assert [breach] = breaches as "expected exactly one breach"
  assert breach.path == "CLAUDE.md"
  assert breach.line == 4
}

pub fn a_path_that_is_in_the_repository_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let text = "See `src/planted/server.gleam`, `gleam.toml` and `CLAUDE.md`.\n"
  assert breach_lines([#("CLAUDE.md", text)]) == []
}

pub fn a_missing_file_named_by_extension_alone_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let text = "The lock is `manifest.toml` and the config is `gleam.toml`.\n"
  assert breach_lines([#("CLAUDE.md", text)]) == [1]
}

pub fn a_directory_the_repository_holds_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let text = "Source is under `src/planted/` and `src/planted`.\n"
  assert breach_lines([#("CLAUDE.md", text)]) == []
}

pub fn a_directory_the_repository_lacks_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let text = "Source is under `src/missing/`.\n"
  assert breach_lines([#("CLAUDE.md", text)]) == [1]
}

pub fn a_skill_may_name_a_path_from_its_own_folder_test() -> Nil {
  use <- owned_test.run(5000)
  let text =
    "The facts are `references/facts.toml`, checked by `scripts/check.py`.\n"
  assert breach_lines([#(".claude/skills/planted/SKILL.md", text)]) == []
}

pub fn a_skill_naming_a_path_missing_from_its_own_folder_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let text =
    "The facts are `references/facts.toml`.\nThe seed is `scripts/seed.py`.\n"
  assert breach_lines([#(".claude/skills/planted/SKILL.md", text)]) == [2]
}

pub fn a_folder_relative_path_does_not_resolve_from_another_guidance_file_test() -> Nil {
  use <- owned_test.run(5000)
  let text = "The facts are `references/facts.toml`.\n"
  assert breach_lines([#("CLAUDE.md", text)]) == [1]
}

pub fn text_between_backticks_that_is_not_a_path_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let text =
    string.join(
      [
        "A branch is `jimd/<issue>-<topic>`.",
        "Run `gleam test -- --test module.fn`.",
        "Match `.claude/skills/**/SKILL.md` and `src/*.gleam`.",
        "Read `https://hexdocs.pm/glance/` or `~/notes/plan.md` or `/etc/hosts`.",
        "The extracted `.tbl` files and `WildStar64.exe` and `[tools.code_rules]`.",
        "A type `Result(a, b)` and a name `code_rules`.",
      ],
      "\n",
    )
  assert breach_lines([#("CLAUDE.md", text)]) == []
}

pub fn a_path_outside_backticks_is_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  let text = "Plain text naming src/planted/missing.gleam is not a reference.\n"
  assert breach_lines([#("CLAUDE.md", text)]) == []
}

pub fn every_path_the_guidance_names_is_in_the_repository_test() -> Nil {
  use <- owned_test.run(10_000)
  let guidance = repository.guidance()
  assert list.length(guidance) >= 5 as "guidance files were not found"
  assert guidance_path.breaches(guidance, repository.tracked_paths()) == []
}
