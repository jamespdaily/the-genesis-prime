//// Every test body runs inside `owned_test.run`.

import code_rule/source.{type Breach, type SourceFile}

/// Each public test function in the file whose body does not start inside the helper.
pub fn breaches(file: SourceFile) -> List(Breach) {
  todo as "body in the build commit"
}
