//// A creature's health, death, corpse and respawn: the feature of the creature's
//// rule (genesis_prime/world_map/creature) that takes a strike and decides what it
//// does to the creature. The creature's process owns its health, so every 0x937 and
//// 0x88c of the unit comes from one sender, in the order the strikes landed.
////
//// ```
//// Alive(health) ── Strike ──▶ the hit rule (genesis_prime/game/hit)
////                             Landed, health' > 0:  Alive(health')    Answered(Landed), news Health(health', alive)
////                             Landed, health' = 0:  Dead              Answered(Landed), news Health(0, dead) then Died
////                                                                     the corpse timer starts: the kind's respawn time
////                             Deflected:            Alive(health)     Answered(Deflected), no news
//// Dead ──── Strike ──▶ Dead                          Answered(Refused(Dead)), no news
//// Dead ──── the corpse timer ──▶ Alive(max health)   news Removed (0x355), then the creature as new (0x262)
//// ```
////
//// - **One strike at a time, in the order they arrive.** Two strikes that cross are
////   answered in turn, and the second finds the first's health, or a corpse and is
////   refused as dead.
//// - **The news** goes to every viewer: Health (0x937: the health after the hit and
////   the dead bit) after each landed hit, and Died (0x88c, dead 1) after the one that
////   takes the health to 0 (`opcode.0x937`, `opcode.0x88c`, `death.corpse`). A deflect
////   changes no health, so it sends none.
//// - **A viewer that arrives while the creature is dead** is sent its 0x262 with stat 0
////   (health) 0, which the client creates dead (`opcode.0x262.creature`).
//// - **The corpse** stays until the creature's own timer ends, whatever its viewers:
////   no client timer removes a dead creature (`death.corpse`). At the respawn the
////   creature sends each viewer 0x355 and a full 0x262 with the same unit id, which
////   the client takes for an id it removed (`death.creature_respawn`).
//// - **A dead creature told to retire** stops at its respawn: its map keeps the spawn
////   retiring until the creature ends, so no viewer is sent a corpse the spawn's next
////   creature does not know.

import genesis_prime/game/hit.{type Defence}
import genesis_prime/game/strike_tell.{type Answered, type Tell}
import gleam/option.{type Option}

/// What a creature brings to a fight, worked out when the content loads
/// (genesis_prime/world_map/spawn `body_of`): its health, its hit radius, its faction
/// levels toward the two player factions, its defence and its kind's respawn time.
pub type Body {
  Body(
    max_health: Int,
    /// Creature2DisplayInfo.hitRadius.
    hit_radius: Float,
    /// The creature's faction level toward the Exile and the Dominion faction
    /// (genesis_prime/world_map/spawn `faction_levels`).
    levels: #(Int, Int),
    defence: Defence,
    /// The kind's respawn time (genesis_prime/world_map/creature_kind).
    respawn_ms: Int,
  )
}

/// Whether the creature stands or lies dead, and its health.
pub opaque type Life {
  Alive(health: Int)
  Dead
}

/// What a viewer is told about the creature's health, which the viewer's connection
/// writes as 0x937 and 0x88c.
pub type News {
  /// The creature's health and whether it is dead: 0x937.
  Health(health: Int, dead: Bool)
  /// The creature died: 0x88c with dead 1.
  Died
}

/// What a strike did: the creature's life after it, the answer to the caster, the
/// news for every viewer in order, and whether the corpse timer starts.
pub type Reaction {
  Reaction(
    life: Life,
    answer: Answered,
    news: List(News),
    /// The time in milliseconds the corpse timer starts for, set when the strike
    /// killed the creature.
    corpse_for_ms: Option(Int),
  )
}

/// A creature standing at full health.
pub fn new(body body: Body) -> Life {
  Alive(health: body.max_health)
}

/// The creature's health: 0 when it lies dead.
pub fn health(life life: Life) -> Int {
  case life {
    Alive(health:) -> health
    Dead -> 0
  }
}

/// Whether the creature lies dead.
pub fn is_dead(life life: Life) -> Bool {
  case life {
    Alive(..) -> False
    Dead -> True
  }
}

/// A strike on the creature: the hit rule on its health and defence, or a refusal
/// for a corpse.
pub fn struck(
  life life: Life,
  body body: Body,
  strike strike: Tell,
) -> Reaction {
  unbuilt(inputs: #(life, body, strike))
}

/// What a creature told to retire does: a creature that stands stops at once, and
/// one that lies dead stops at its respawn, since its map keeps the spawn retiring
/// until it ends.
pub type OnRetire {
  StopNow
  StopAtRespawn
}

/// What the creature does when the map tells it to retire.
pub fn on_retire(life life: Life) -> OnRetire {
  unbuilt(inputs: life)
}

/// What the corpse timer's firing leads to.
pub type AtCorpse {
  /// The creature stands again at full health, and sends each viewer 0x355 and its
  /// 0x262.
  StandsAgain(life: Life)
  /// The creature was told to retire while dead: it stops, with no viewer to tell.
  Ends
}

/// The corpse timer fired: the creature stands again at full health, or ends when
/// it was told to retire while dead.
pub fn corpse_timer_fired(
  life life: Life,
  body body: Body,
  retiring retiring: Bool,
) -> AtCorpse {
  unbuilt(inputs: #(life, body, retiring))
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
