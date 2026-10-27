//// The repository's source tree is read once per test run, whatever the number
//// of whole-tree rules that read it. The expected value is the reason the
//// reading is shared: each rule that read and parsed the tree on its own made
//// a run's cost grow with files times rules, and the comment rule ran past its
//// deadline in CI. Two rules over different directories of the tree are run,
//// and the count of reads from disk, kept by the repository helper for the
//// whole VM, must be one.

import code_rule/catch_all
import code_rule/repository
import code_rule/test_body
import gleam/list
import owned_test
import unitest

pub fn the_tree_is_read_once_whatever_the_number_of_rules_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert list.flat_map(repository.sources(["src"]), catch_all.breaches) == []
  assert list.flat_map(repository.sources(["test"]), test_body.breaches) == []
  assert repository.tree_reads() == 1
    as "the source tree was read more than once in this run"
}
