//// No catch-all clause over a type that can gain variants.

import code_rule/source.{type Breach, type SourceFile}

/// Each case clause that is a catch-all beside a constructor of a type that can grow.
pub fn breaches(file: SourceFile) -> List(Breach) {
  todo as "body in the build commit"
}
