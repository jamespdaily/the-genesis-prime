//// Where an Erlang file calls or refers to a function, read with Erlang's own
//// scanner (`erl_scan`), for the code rules that read Erlang helpers: a
//// comment, a string, whitespace, a line break, or another module's function
//// of the same name is read as the compiler reads it.

/// A function by its module and name. An `erlang` function also matches
/// unqualified, as an auto-imported BIF.
pub type Target {
  Target(module: String, function: String)
}

/// The line of each call of a target (followed by `(`) and each reference to
/// one as a fun (followed by `/`), in order; text that does not scan gives the
/// line where it stops, so it is never passed unread.
@external(erlang, "erlang_calls_ffi", "lines")
pub fn lines(text: String, targets: List(Target)) -> List(Int)

/// The line of each atom the text writes that is `name` or starts with `name`
/// and an underscore, in order, so `pgo` and `pgo_pool_sup` are the atoms of
/// `pgo`; text that does not scan gives the line where it stops.
@external(erlang, "erlang_calls_ffi", "atom_lines")
pub fn atom_lines(text: String, name: String) -> List(Int)

/// The line of the `after` of each `receive` whose timeout is not the integer
/// 0 or `infinity`, in order, so a receive that waits a time, and not one that
/// only looks or waits for ever, is found; the `after` of a `try` is no
/// timeout. Text that does not scan gives
/// the line where it stops.
@external(erlang, "erlang_calls_ffi", "timed_receive_lines")
pub fn timed_receive_lines(text: String) -> List(Int)
