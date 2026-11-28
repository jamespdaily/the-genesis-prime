//// What a creature brings to a fight, worked out when the content loads
//// (genesis_prime/world_map/spawn) from its tables: whom it fights on sight, its attack and
//// specials, its interrupt armor and its defence. The creature's life and fight rules
//// (genesis_prime/world_map/creature_life, creature_fight) read these types.

import genesis_prime/shared/area.{type Anchor, type Inside, type Row}
import genesis_prime/shared/hit.{type Defence, type Offence}
import genesis_prime/shared/telegraph_entries.{type Draw}
import genesis_prime/table/id.{type Spell4Id}
import gleam/float
import gleam/option.{type Option}

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
/// (genesis_prime/shared/creature_kind): the Spell4 it casts; the offence each
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
    /// own movement (genesis_prime/shared/crowd_control `stopping_mask`).
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
  /// (genesis_prime/shared/spell_area `area_of_spell`); a spell with a cast time and no area it
  /// can read fails the load. `draws` are the spell's telegraph rows the client makes, from
  /// which the cast's 0x7ff names the positions the picture is drawn at
  /// (genesis_prime/shared/telegraph_entries). `aims_at_target` is the spell's
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

/// One go of a cast (0x7f4), by the Spell4's phases (genesis_prime/shared/spell_plan
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

/// A spell a creature casts besides its attack, chosen by its kind's list
/// (genesis_prime/shared/creature_kind `specials`): the spell as an `Attack` (always
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

/// The armor a property-44 value of a creature means: below 0 is infinite, 0 none,
/// else its points rounded.
pub fn interrupt_armor_of(maximum maximum: Float) -> InterruptArmor {
  case maximum <. 0.0, float.round(maximum) {
    True, _ -> InfiniteArmor
    False, 0 -> NoArmor
    False, points -> Armor(points:)
  }
}
