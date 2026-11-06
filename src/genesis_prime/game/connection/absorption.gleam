//// The player's own absorb pools on the game connection (genesis_prime/game/connection):
//// what the cast rule's `CasterChangeStarts` of an `Absorb` and its `CasterChangeEnds`
//// ask, carried out on the player's life, which holds the pools
//// (genesis_prime/game/player_life).
////
//// ```
//// the cast rule's CasterChangeStarts(source, Absorb(amount, mask))
////   ─▶ player_life.absorb_started ─▶ 0x938 {P, 22, sum} to the player's client
////                                  ─▶ Absorption news to each viewer
//// the cast rule's CasterChangeEnds(source)
////   ─▶ connection/properties.ended: unit_properties.remove(source), which holds nothing
////      for a pool's source
////   ─▶ player_life.absorb_ended   ─▶ 0x938 {P, 22, sum} and the news, when the sum moved
//// ```
////
//// - **An end is told by source to each owner of a caster change**, the properties and the
////   life, and each ignores a source it holds nothing for. A source is one cast and one
////   Spell4Effects row, so at most one owner holds it, and the cast rule needs no
////   knowledge of which: its death, its node's removal and its timers name sources only.
//// - **The amount is the cast rule's**, worked out at the go from the caster's stats; the
////   life keeps the pool, spends it by the hit rule (genesis_prime/game/hit) and drops it
////   when it is used up, at its end and at the player's death.
//// - **A pool that moves nothing** (a dead player, an amount of 0, an end for a source not
////   held) writes nothing (genesis_prime/game/player_life).
//// - **A player not held in the world** (a save, a leave) takes no pool: the life goes with
////   its `Entered`.

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/life_effect
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/player_life
import genesis_prime/game/unit_properties
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}

/// The player's life takes the pool of the cast effect `source` (genesis_prime/game/cast
/// `Absorb`): the life is kept and what it decided is written to the player's client and
/// told to its viewers. With no player in the world it is dropped.
pub fn started(
  session session: Session,
  now now: Now,
  source source: unit_properties.Source,
  amount amount: Int,
  mask mask: Int,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  life_effect.life_changed(session:, now:, change: fn(entered) {
    player_life.absorb_started(life: entered.life, source:, amount:, mask:)
  })
}

/// The pool of the cast effect `source` ends (genesis_prime/game/cast
/// `CasterChangeEnds`): the life drops it when it holds it and tells the new sum. A source
/// the life holds nothing for changes nothing.
pub fn ended(
  session session: Session,
  now now: Now,
  source source: unit_properties.Source,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  life_effect.life_changed(session:, now:, change: fn(entered) {
    player_life.absorb_ended(life: entered.life, source:)
  })
}
