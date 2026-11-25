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

import genesis_prime/game/area.{type Anchor, type Inside, type Row}
import genesis_prime/game/damage
import genesis_prime/game/hit.{type Defence, type Offence}
import genesis_prime/game/strike_tell.{
  type Answered, type Tell, Answered, CreatureStriker, Landed, PlayerStriker,
  Refused,
}
import genesis_prime/game/telegraph_entries.{type Draw}
import genesis_prime/table/id.{type Spell4Id}
import gleam/float
import gleam/int
import gleam/list
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
/// choice, checked live); and how the spell is cast (`cast`). A creature whose `run_speed`
/// is 0 never moves.
pub type Attack {
  Attack(
    spell4_id: Spell4Id,
    offence: Offence,
    run_speed: Float,
    reach: Float,
    /// Whether the target's hit radius is added to `reach`, as the client ranges a cast on a
    /// unit from edge to edge (`0x1403b2240`: the distance less both radii is held to
    /// `targetMaxRange`). It is set for a charge on its target whose spell has a
    /// `targetMaxRange`; a charge with none takes the area row's `maxRange` as `reach`, a
    /// server choice the client's check does not cover, and an instant attack's reach is a
    /// server choice too.
    adds_target_radius: Bool,
    cast: Cast,
    /// The crowd-control states that refuse the attack's cast: the ccStateMask of the
    /// Spell4CCConditions row the attack spell's caster column names, 0 for no row; bit n
    /// is the state n (`CheckSpellCCConditions`, `0x1403b2c40`).
    caster_cc_mask: Int,
    /// The crowd-control states that stop the creature's run, as a mask: the states whose
    /// CCStates flags hold the value 2, the states under which the client drops a unit's
    /// own movement (genesis_prime/game/crowd_control `stopping_mask`).
    run_stopped_by: Int,
  )
}

/// How a creature's attack spell is cast: by the spell's `castTime` for an auto-attack, and
/// as a charge whatever the time for a special.
pub type Cast {
  /// An auto-attack with a cast time of 0: it strikes its target at once.
  Instant
  /// A special, or an auto-attack with a cast time above 0: a charge, which strikes each
  /// fighter inside the area of each of its strike gos (`Go.strike`). `area` is the row that chooses the fighters, `inside` the union
  /// of the cast's shapes the reach is read from, and `anchor` where the area is centred
  /// (genesis_prime/game/spell_area `area_of_spell`); a spell with a cast time and no area it
  /// can read fails the load. `draws` are the spell's telegraph rows the client makes, from
  /// which the cast's 0x7ff names the positions the picture is drawn at
  /// (genesis_prime/game/telegraph_entries). `aims_at_target` is the spell's
  /// `Spell4.propertyFlags` bit 0x2: a creature that cannot move keeps turning its aim
  /// toward its 0x908 target through a cast of such a spell, and holds the aim it had at
  /// the cast's start through any other (`0x14046cdc0.turret_cast_aim`). `gos` is the
  /// cast's timeline (`Go`): never empty, each `at_ms` above the one before; a go strikes
  /// when damage rows name it, they apply to the creature's difficulty and a hit row is drawn
  /// then (a spell with no hit row strikes at every go it names, inside its area row).
  /// `hold_ms` is how long the creature then stands still before it attacks again:
  /// the summed `delay_ms + duration_ms` of the NpcExecutionDelay rows (Spell4Effects type
  /// 35) whose phase flags name the cast's last go, 0 for none; the load refuses a delay row
  /// that names another go. The hold counts from the cast's close, after the last go and
  /// every round of its strikes. An attack that is not a special has one go, at `cast_ms`,
  /// that strikes, and no hold. A special's `cast_ms` is its spell's castTime, which may be 0,
  /// and its `gos` are its plan's whatever that time is; the first go may be at 0.
  Charged(
    cast_ms: Int,
    area: Row,
    inside: Inside,
    anchor: Anchor,
    draws: List(Draw),
    aims_at_target: Bool,
    gos: List(Go),
    hold_ms: Int,
  )
}

/// One go of a cast (0x7f4), by the Spell4's phases (genesis_prime/game/spell_plan
/// `go_times_ms`): when it goes, counted from the cast's start, and what it strikes. The go's
/// index in `gos` is the phase its 0x7f4 carries. A go with no `strike` is a go of the
/// cast bar only.
pub type Go {
  Go(at_ms: Int, strike: Option(GoStrike))
}

/// What a go strikes: the Spell4Effects ids of the damage rows that name the go, whose
/// blows of the attack's offence it strikes with (`offence_of_go`), and the shapes the fighters
/// must stand inside at the go.
pub type GoStrike {
  GoStrike(spell4_effects_ids: List(Int), inside: Inside)
}

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

/// A spell a creature casts besides its attack, chosen by its kind's list
/// (genesis_prime/world_map/creature_kind `specials`): the spell as an `Attack` (always
/// `Charged`), and the time from the cast's start until it may be cast again, a server
/// choice.
pub type Special {
  Special(attack: Attack, cooldown_ms: Int)
}

/// A creature's Interrupt Armor maximum, unit property 44
/// (`UnitProperty2.InterruptArmor_Threshold`): its Creature2OverrideProperties value
/// when one is listed (-1 is infinite), else its level's value times its archetype's,
/// difficulty's and tier's multipliers, 0 for most ordinary difficulties. The client
/// decides nothing with it; the server's rule for a state landing on armor is
/// genesis_prime/world_map/creature_control's.
pub type InterruptArmor {
  /// A maximum of 0: the creature takes every crowd-control state.
  NoArmor
  /// A maximum above 0, in points.
  Armor(points: Int)
  /// A maximum of -1: no state wears it down.
  InfiniteArmor
}

/// The armor a property-44 value of a creature means: below 0 is infinite, 0 none,
/// else its points rounded.
pub fn interrupt_armor_of(maximum maximum: Float) -> InterruptArmor {
  case maximum <. 0.0, float.round(maximum) {
    True, _ -> InfiniteArmor
    False, 0 -> NoArmor
    False, points -> Armor(points:)
  }
}

/// What a creature brings to a fight, worked out when the content loads
/// (genesis_prime/world_map/spawn): the hit radius of its display
/// (Creature2DisplayInfo.hitRadius), whom it may be attacked by, whom it fights on
/// sight, its defence, its own attack, the auto-attacks it strikes with after it in turn,
/// its specials and its Interrupt Armor. `fights` is False for a creature the client draws as
/// a lying body (`Creature2.uiFlags.bit8`) that no kill objective counts: it takes no part in
/// combat, so it aggroes no one, no strike starts a fight with it and no area picks it;
/// `attackable` and `hostile_to` stay the faction's, which a click and a quest offer read.
pub type Combat {
  Combat(
    hit_radius: Float,
    attackable: Attackable,
    hostile_to: Hostile,
    fights: Bool,
    defence: Defence,
    attack: Attack,
    alternates: List(Attack),
    specials: List(Special),
    interrupt_armor: InterruptArmor,
  )
}

/// A creature's fixed values for a fight: its health, what it brings and its kind's
/// respawn time (genesis_prime/world_map/creature_kind).
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
