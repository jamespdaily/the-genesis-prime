//// The crowd-control effects the tests' strikes carry, as the client's rows hold them
//// (`table_rows -- Spell4Effects 140382 83827 100836`): every row removes 1 Interrupt
//// Armor (dataBits03), and each takes the instance id a caster gave it.

import genesis_prime/game/crowd_control.{Row}
import genesis_prime/game/strike_tell.{ControlLanded, ControlTell}
import genesis_prime/message/crowd_control_state.{Knockdown, Stun}

/// Kick's Knockdown, Spell4Effects 140382: delayTime 166, durationTime 3000, state 8.
pub fn kick_knockdown(instance_id instance_id: Int) -> strike_tell.ControlTell {
  ControlTell(
    effect_id: 140_382,
    instance_id:,
    row: Row(
      state: Knockdown,
      delay_ms: 166,
      duration_ms: 3000,
      armor_removed: 1,
      until_removed: False,
    ),
  )
}

/// Stagger's Stun, Spell4Effects 83827: delayTime 0, durationTime 2500, state 0.
pub fn stagger_stun(instance_id instance_id: Int) -> strike_tell.ControlTell {
  ControlTell(
    effect_id: 83_827,
    instance_id:,
    row: Row(
      state: Stun,
      delay_ms: 0,
      duration_ms: 2500,
      armor_removed: 1,
      until_removed: False,
    ),
  )
}

/// Gate's Stun, Spell4Effects 100836: delayTime 0, durationTime 3250, state 0.
pub fn gate_stun(instance_id instance_id: Int) -> strike_tell.ControlTell {
  ControlTell(
    effect_id: 100_836,
    instance_id:,
    row: Row(
      state: Stun,
      delay_ms: 0,
      duration_ms: 3250,
      armor_removed: 1,
      until_removed: False,
    ),
  )
}

/// A Kick Knockdown with the instance id 28673 (unit 7's first) that a creature holds
/// until `ends_at_ms`.
pub fn kick_landed(ends_at_ms ends_at_ms: Int) -> strike_tell.ControlLanded {
  ControlLanded(tell: kick_knockdown(instance_id: 28_673), ends_at_ms:)
}
