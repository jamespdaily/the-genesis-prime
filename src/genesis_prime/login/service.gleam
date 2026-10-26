//// The login's subtree of the supervision tree: the two hand-offs the
//// connections of the login share, one for the game tokens and one for the
//// session keys. It is one for one with 3 restarts in 5 seconds, like the
//// top level, so a fault that survives three rebuilds stops the subtree and
//// reaches the top.

import genesis_prime/login/account.{type Identity}
import genesis_prime/login/handoff
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision

/// What the subtree starts with: the settings of each hand-off.
pub type Settings {
  Settings(
    game_tokens: handoff.Settings(Identity),
    session_keys: handoff.Settings(Identity),
  )
}

/// The login's subtree as a child of the top supervisor.
pub fn supervised(
  settings settings: Settings,
) -> supervision.ChildSpecification(Supervisor) {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
  |> static_supervisor.add(handoff.supervised(settings.game_tokens))
  |> static_supervisor.add(handoff.supervised(settings.session_keys))
  |> static_supervisor.supervised
}
