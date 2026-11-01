//// What the tests share that start the server's tree under the application's
//// root (`genesis_prime/application`), as the server does.

import gleam/erlang/process.{type Pid}

/// Ends a tree the application's root runs, as the root ends it when the node
/// stops, and waits until it has ended.
@external(erlang, "application_support_ffi", "stop_under_root")
pub fn stop(tree: Pid) -> Nil

/// Ends the tree under the root when the calling process ends, however it
/// ends, so a test whose assertion fails leaves no tree running.
pub fn guard(tree: Pid) -> Nil {
  let owner = process.self()
  let _guardian =
    process.spawn_unlinked(fn() {
      let _down = process.monitor(owner)
      let selector =
        process.new_selector()
        |> process.select_monitors(fn(down) { down })
      let _ended = process.selector_receive_forever(selector)
      stop(tree)
    })
  Nil
}
