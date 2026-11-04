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

import genesis_prime/game/hit.{type Defence, type Offence}
import genesis_prime/game/strike_tell.{
  type Answered, type Tell, Answered, CreatureStriker, Landed, PlayerStriker,
  Refused,
}
import genesis_prime/table/id.{type Spell4Id}
import gleam/option.{type Option, None, Some}

/// Whether a creature may be attacked by a player of each faction, from its
/// faction's level toward that player faction: Hostile or Neutral, 7 or less
/// (`0x1403ad540`), worked out when the content loads.
pub type Attackable {
  Attackable(exile: Bool, dominion: Bool)
}

/// Whether a creature fights a player of each faction that comes near it: its
/// faction's level toward that player faction is Hostile, 0 to 2
/// (FactionDispositionFromLevel, `world_data.creature_disposition`), worked out when
/// the content loads beside `Attackable`. A Neutral creature fights only a player
/// that strikes it.
pub type Hostile {
  Hostile(exile: Bool, dominion: Bool)
}

/// A creature's own attack, worked out when the content loads
/// (genesis_prime/world_map/spawn) from its kind's spell
/// (genesis_prime/world_map/creature_kind): the Spell4 it casts; the offence each
/// cast strikes with, whose blow is the damage effect its difficulty chooses by the
/// effect's caster prerequisite (`0x14049eeb0`: 184741 for difficulty 6 or less,
/// 184777 for 7 or more), valued by the creature formula (`0x140565600`, GameFormula
/// 712), with its critical hit chance, severity and strikethrough from its
/// properties; the speed it runs at, in units a second
/// (Creature2DisplayInfo.runLand times property 100, `0x1405b45e0`); and its reach,
/// centre to centre: the spell's `targetMaxRange` plus its hit radius (a server
/// choice, checked live).
pub type Attack {
  Attack(spell4_id: Spell4Id, offence: Offence, run_speed: Float, reach: Float)
}

/// What a creature brings to a fight, worked out when the content loads
/// (genesis_prime/world_map/spawn): the hit radius of its display
/// (Creature2DisplayInfo.hitRadius), whom it may be attacked by, whom it fights on
/// sight, its defence, and its own attack.
pub type Combat {
  Combat(
    hit_radius: Float,
    attackable: Attackable,
    hostile_to: Hostile,
    defence: Defence,
    attack: Attack,
  )
}

/// A creature's fixed values for a fight: its health, what it brings and its kind's
/// respawn time (genesis_prime/world_map/creature_kind).
pub type Body {
  Body(max_health: Int, combat: Combat, respawn_ms: Int)
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
    Alive(health:) ->
      case
        hit.apply(
          health:,
          shield: 0,
          offence: strike.offence,
          defence: body.combat.defence,
          rolls: rolls_of(strike),
        )
      {
        hit.Deflected ->
          Reaction(
            life:,
            answer: Answered(key: strike.key, outcome: strike_tell.Deflected),
            news: [],
            corpse_for_ms: None,
          )
        hit.Landed(descriptions:, health: left, killed: True, ..) ->
          Reaction(
            life: Dead,
            answer: Answered(key: strike.key, outcome: Landed(descriptions:)),
            news: [Health(health: left, dead: True), Died],
            corpse_for_ms: Some(body.respawn_ms),
          )
        hit.Landed(descriptions:, health: left, killed: False, ..) ->
          Reaction(
            life: Alive(health: left),
            answer: Answered(key: strike.key, outcome: Landed(descriptions:)),
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
    CreatureStriker -> panic as "a creature struck a creature"
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
    Dead -> StopAtRespawn
  }
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
  case life, retiring {
    Dead, True -> Ends
    Dead, False | Alive(..), _ -> StandsAgain(life: new(body:))
  }
}
