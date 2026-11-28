//// A creature's health, death, corpse and respawn: the feature of the creature's
//// rule (genesis_prime/world_map/creature) that takes a strike and decides what it
//// does to the creature. The creature's process owns its health, so every 0x937 and
//// 0x88c of the unit comes from one sender, in the order the strikes landed.
////
//// ```
//// Alive(health) ── Strike ──▶ the hit rule (genesis_prime/shared/hit)
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

import genesis_prime/shared/creature_combat.{
  type Attack, type Combat, type GoStrike,
}
import genesis_prime/shared/damage
import genesis_prime/shared/hit.{type Offence}
import genesis_prime/shared/strike_tell.{
  type Answered, type Tell, Answered, CreatureStriker, Landed, PlayerStriker,
  Refused,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// The attack's offence for one go: its blows that the go names, with the attack's critical
/// hit chance and severity and its strikethrough.
pub fn offence_of_go(
  attack attack: Attack,
  strike strike: GoStrike,
) -> Offence {
  hit.Offence(
    ..attack.offence,
    blows: list.filter(attack.offence.blows, fn(blow) {
      list.contains(strike.spell4_effects_ids, blow.spell4_effects_id)
    }),
  )
}

/// A creature's fixed values for a fight: its health, what it brings and its kind's
/// respawn time (genesis_prime/shared/creature_kind).
pub type Body {
  Body(max_health: Int, combat: Combat, respawn_ms: Int)
}

/// Whether the creature stands, lies dead or has been removed from the field by a DespawnUnit
/// effect, and its health. A despawned creature is gone as a dead one is (`is_dead`) and leaves
/// no corpse (`is_shown`): its viewers are sent no 0x262 until the corpse timer stands it again.
pub opaque type Life {
  Alive(health: Int)
  Dead
  Despawned
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
    Dead | Despawned -> 0
  }
}

/// The life under a maximum health of `max_health`: a creature above it falls to it,
/// one at or below it, or dead, keeps its health. A raised maximum adds none.
pub fn clamped(life life: Life, max_health max_health: Int) -> Life {
  case life {
    Alive(health:) -> Alive(health: int.min(health, max_health))
    Dead -> Dead
    Despawned -> Despawned
  }
}

/// Whether the creature lies dead or has been removed from the field: a strike, a throw, a
/// modifier and the fight treat both as gone.
pub fn is_dead(life life: Life) -> Bool {
  case life {
    Alive(..) -> False
    Dead | Despawned -> True
  }
}

/// Whether a viewer is sent the creature's unit: false for a despawned creature, which is
/// shown again when its corpse timer stands it.
pub fn is_shown(life life: Life) -> Bool {
  case life {
    Alive(..) | Dead -> True
    Despawned -> False
  }
}

/// A DespawnUnit effect reaches the creature: the life it leaves the field with and the time in
/// milliseconds the corpse timer starts for (the kind's respawn time), or none for a creature
/// that lies dead or is already gone, which the effect does not reach.
pub fn despawned(life life: Life, body body: Body) -> Option(#(Life, Int)) {
  case life {
    Alive(..) -> Some(#(Despawned, body.respawn_ms))
    Dead | Despawned -> None
  }
}

/// A strike on the creature: the hit rule on its health and defence, or a refusal
/// for a corpse.
pub fn struck(
  life life: Life,
  body body: Body,
  strike strike: Tell,
) -> Reaction {
  case life {
    Dead ->
      Reaction(
        life:,
        answer: Answered(
          key: strike.key,
          outcome: Refused(why: strike_tell.Dead),
        ),
        news: [],
        corpse_for_ms: None,
      )
    Despawned ->
      Reaction(
        life:,
        answer: Answered(
          key: strike.key,
          outcome: Refused(why: strike_tell.Despawned),
        ),
        news: [],
        corpse_for_ms: None,
      )
    Alive(health:) ->
      case
        hit.apply(
          target: damage.Vitals(
            health:,
            max_health: body.max_health,
            shield: 0,
            max_shield: 0,
          ),
          absorbs: [],
          offence: strike.offence,
          defence: body.combat.defence,
          rolls: rolls_of(strike),
        )
      {
        hit.Deflected ->
          Reaction(
            life:,
            answer: Answered(
              key: strike.key,
              outcome: strike_tell.Deflected(gates_passed: []),
            ),
            news: [],
            corpse_for_ms: None,
          )
        hit.Landed(descriptions:, health: left, killed: True, ..) ->
          Reaction(
            life: Dead,
            answer: Answered(
              key: strike.key,
              outcome: Landed(
                descriptions:,
                controls: [],
                armor_removed: 0,
                gates_passed: [],
              ),
            ),
            news: [Health(health: left, dead: True), Died],
            corpse_for_ms: Some(body.respawn_ms),
          )
        hit.Landed(descriptions:, health: left, killed: False, ..) ->
          Reaction(
            life: Alive(health: left),
            answer: Answered(
              key: strike.key,
              outcome: Landed(
                descriptions:,
                controls: [],
                armor_removed: 0,
                gates_passed: [],
              ),
            ),
            news: [Health(health: left, dead: False)],
            corpse_for_ms: None,
          )
      }
  }
}

/// The rolls of a strike on a creature: a player's, from its seed. A creature
/// never strikes a creature.
fn rolls_of(strike: Tell) -> hit.Rolls {
  case strike.striker {
    PlayerStriker(rolls:, ..) -> rolls
    CreatureStriker(..) -> panic as "a creature struck a creature"
  }
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
  case life {
    Alive(..) -> StopNow
    Dead | Despawned -> StopAtRespawn
  }
}

/// What the corpse timer's firing leads to.
pub type AtCorpse {
  /// The creature lies dead or despawned and its map starts the next life: it tells the
  /// map it expired and stops.
  Expires
  /// The creature was told to retire while dead: it stops, with no viewer to tell.
  Ends
}

/// The corpse timer fired: the creature expires, or ends when it was told to retire while
/// dead (`death.creature_respawn`: the creature comes back full under its map's next life).
/// The timer is armed only at a kill and a despawn, so a creature that stands is a bug.
pub fn corpse_timer_fired(
  life life: Life,
  retiring retiring: Bool,
) -> AtCorpse {
  case life, retiring {
    Dead, True | Despawned, True -> Ends
    Dead, False | Despawned, False -> Expires
    Alive(..), _ ->
      panic as "a corpse timer fires only for a creature that lies dead or despawned"
  }
}
