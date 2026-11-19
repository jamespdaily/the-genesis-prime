//// What the cast rule keeps and how it names things: its types, its constants, the ids of casts and timers, and the helpers every other part of the rule shares.
////
//// - **The cast id** is 2^31 + unit id x 2^11 + n mod 2^11, skipping an id a live
////   cast of the caster holds: unique among the live casts of every unit, since
////   the client keeps one table of casts (`0x140561c30`) and unit ids are below
////   2^20, and never 0. The client's own counter makes no collision: its
////   pending casts live apart (`cast.pending_table`). A child takes the next id.
//// - **Timers** are the connection's: this rule starts them with ids from
////   `first_timer`, one for each go, finish, child, held press, threshold window
////   and charge level waiting, and owns the ids from there up (`owns`).
////

import genesis_prime/client_connection.{type News}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/activate
import genesis_prime/game/class_resource.{type Payment, type Resources}
import genesis_prime/game/cooldown
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/forced_move
import genesis_prime/game/heal_split
import genesis_prime/game/hit
import genesis_prime/game/lasting
import genesis_prime/game/look
import genesis_prime/game/prerequisite
import genesis_prime/game/proc
import genesis_prime/game/quest_advance
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/shortcut_spell
import genesis_prime/game/spell_area
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type Proxy, type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/ticking
import genesis_prime/game/unit_properties
import genesis_prime/game/unit_state
import genesis_prime/message/cast_result
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/float32
import genesis_prime/message/item_place.{type ItemPlace}
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription,
}
import genesis_prime/message/spell_position.{type SpellPosition, SpellPosition}
import genesis_prime/step.{
  type ConnectionId, type LogLevel, type TimerId, TimerId,
}
import genesis_prime/table/id.{
  type Item2Id, type Spell4BaseId, type Spell4EffectsId, type Spell4Id,
}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

/// The messages of a player's casts, which the client sends inside 0x038C
/// (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x009A, the press of an ability.
  Pressed
  /// 0x04DB, the key or button of an ability goes down or up under the client's
  /// hold-to-continue-casting setting, which is on by default.
  KeyHeld
  /// 0x0801, the client ends one of its player's casts.
  Cancelled
  /// 0x0805, the client's answer to its client-side interaction of a cast.
  Answered
}

/// The Vital id of Health and of Shield Capacity in `Caster.life_vitals`
/// (`Prerequisite.prerequisiteTypeId.71`: Vital.tbl ids 1 and 3).
pub const health_vital = 1

pub const shield_vital = 3

/// The player that casts, as the connection holds it when it takes an input.
pub type Caster {
  Caster(
    unit_id: Int,
    /// Where the player stands now.
    place: Place,
    /// The abilities the player holds, as Spell4Base ids in bag order
    /// (genesis_prime/game/loadout).
    abilities: List(Spell4BaseId),
    /// The ability book as the client holds it once its 0x1a0 is read: the bag, then the
    /// alternate each bag ability names (`spell_plan.book`). A swap under Spell Surge needs
    /// the alternate's base in it (`GetAbilityBookSpell`, `0x1403bad30`).
    book: List(Spell4BaseId),
    /// Spell Surge's spell, GameFormula 913's dataint0 (`spell_surge.spell`): a node of it on
    /// the player's unit is the surge (`IsSpellSurgeActive`, `0x1405e7d10`).
    surge_spell: Spell4Id,
    /// The item in the equipped slot 16, when there is one.
    weapon: Option(Item2Id),
    /// The connections whose players see this one.
    audience: Set(ConnectionId),
    /// Whether the player is dead (genesis_prime/game/player_life), which the
    /// client checks a press against (`cast.dead_player`).
    dead: Bool,
    /// The player's class resource (genesis_prime/game/class_resource), which a
    /// press's costs and requirements are checked against and paid from, and whose
    /// slots are the vitals 5 to 11 of a prerequisite.
    resources: Resources,
    /// Whether a creature holds the player on its threat list
    /// (genesis_prime/game/player_life), which a type 28 prerequisite reads.
    in_combat: Bool,
    /// The player's health (Vital 1) and shield (Vital 3), by Vital id, which a
    /// type 71 or 73 prerequisite reads beside the class resource's slots.
    life_vitals: Dict(Int, prerequisite.Vital),
    /// The player's faction and base faction, the two faction fields of its 0x262, which
    /// the type 4 and 250 prerequisites read.
    factions: prerequisite.Factions,
    /// What a damage or heal formula reads of the player: its level and its Assault
    /// and Support Rating (genesis_prime/game/damage).
    stats: damage.Attacker,
    /// The player's health and shield with their maxima, which a heal's formula reads
    /// (genesis_prime/game/damage `value_on_caster`).
    vitals: damage.Vitals,
    /// The two heal multipliers and the shield conversion a heal of the player's own
    /// vital reads of it, with which the go works out the amount and overheal it tells
    /// the client (genesis_prime/game/heal_split).
    heal_scaling: heal_split.Scaling,
    /// The player's quest log, which the quest conditions of a prerequisite (types 6,
    /// 68, 43 and 22 to 36) read: the client reads the checking player's own log.
    quests: QuestLog,
    /// The player's race, class, path, gender, level, World and zones, which the
    /// prerequisite types on the player (1, 2, 3, 10, 26, 39, 52 and 109) read.
    player: prerequisite.Player,
    /// What the player holds of its own, which the prerequisite types on the player's
    /// items (13, 14 and 246), ability book (214) and world difficulty (143) read.
    checker: prerequisite.Checker,
  )
}

/// What a caster's spell changes on the caster itself, which starts after the effect's
/// delay: the payload of `CasterChangeStarts` and `Due.ModifierStart`. A change that ends
/// has its end tied to its source alone (`CasterChangeEnds`, `Due.ModifierEnd`), which
/// each owner of a change takes by its source and ignores when it holds none; a shield
/// heal has no end.
pub type CasterChange {
  /// A property modifier (a UnitPropertyModifier or UnitPropertyConversion effect): the
  /// connection applies it to the player's properties (genesis_prime/game/unit_properties `apply`).
  Property(modifier: unit_properties.Modifier)
  /// An absorb pool (an Absorption effect): the connection gives the player's life a pool of
  /// `amount` that takes the damage types of `mask` (bit 1 Physical, 2 Tech, 4 Magic) before
  /// its shield and health (genesis_prime/game/player_life `absorb_started`). The amount is
  /// worked out at the go from the caster's stats, as a heal's is, and the pool lasts until
  /// its end or it is used up (`Spell4Effects.effectType.29`).
  Absorb(amount: Int, mask: Int)
  /// A disguise (a DisguiseOutfit effect): the connection starts it on the player's look,
  /// writes the slots that changed to the player's client and tells its viewers
  /// (genesis_prime/game/look `start`). It ends with the modifiers' own end,
  /// `CasterChangeEnds`.
  Look(disguise: look.Disguise)
  /// A heal (a Heal or HealShields effect): the connection raises the player's `vital`
  /// by `amount`, the formula's value worked out at the go, and the life applies the heal
  /// multipliers and the shield conversion to it and caps each vital at its maximum
  /// (genesis_prime/game/player_life `healed`); the go's 0x7f4 shows the result of the
  /// same split (genesis_prime/game/heal_split).
  Heal(vital: effect_kind.Vital, amount: Int)
}

/// What the rule asks the connection to do, in order.
pub type Effect {
  /// Write a message to the caster's client.
  Send(frame: Frame)
  /// Tell the connection of a player who sees the caster the news of a cast.
  Tell(to: ConnectionId, news: News)
  StartTimer(timer: TimerId, after_ms: Int)
  CancelTimer(timer: TimerId)
  Log(level: LogLevel, text: String)
  /// A go is asked: the connection selects its targets, strikes them
  /// (genesis_prime/game/strike) and, when the round closes, answers with `cast.went`.
  /// The go's 0x7f4 waits for that answer.
  Strike(asked: GoAsked)
  /// A tick of a periodic damage row is due on a unit: the connection strikes it
  /// (genesis_prime/game/strike `begin_tick`) and, when the round closes, answers with
  /// `cast.ticked`. The tick's 0x7f8 waits for that answer.
  TickStrike(asked: TickAsked)
  /// A cast's costs are taken from the caster's class resource, at its first go, or
  /// at the accept of a spell that goes at once (genesis_prime/game/class_resource
  /// `pay`).
  Pay(payments: List(Payment))
  /// A go's resource gains are given to the caster's class resource
  /// (genesis_prime/game/class_resource `gain`).
  Gain(gains: List(class_resource.Gain))
  /// A change of the caster's spell on the caster itself starts: the connection applies a
  /// property modifier to the player's properties and tells its client and its viewers
  /// the entries that changed (genesis_prime/game/unit_properties `apply`), and raises
  /// the health or shield for a heal (genesis_prime/game/player_life `healed`) and gives
  /// the life an absorb pool for an `Absorb` (genesis_prime/game/player_life `absorb_started`).
  CasterChangeStarts(source: unit_properties.Source, change: CasterChange)
  /// A change of the caster's spell ends, or is told ended for a source the connection may
  /// hold nothing for: it is told by source alone to each owner of a caster change, the
  /// properties (`unit_properties.remove`), the look (`look.end`) and the life
  /// (`player_life.absorb_ended`), and an owner that holds nothing for the source changes
  /// nothing. A source names one cast and one Spell4Effects row, so at most one owner holds it.
  CasterChangeEnds(source: unit_properties.Source)
  /// A property modifier of the caster's spell starts on the creature `unit_id` whose
  /// life the go struck, at the monotonic time `struck_at_ms` the go struck it
  /// (`HitCreature`): the connection tells the creature
  /// (genesis_prime/client_connection `TellTargetChange`), which applies it to its own
  /// properties and tells its viewers the entries that changed. A creature of another
  /// life drops it, and so does one that lies dead or has stood again from its corpse
  /// since the go struck.
  TargetChangeStarts(
    unit_id: Int,
    life: Int,
    struck_at_ms: Int,
    source: unit_properties.Source,
    modifier: unit_properties.Modifier,
  )
  /// The ForcedMove row of the caster's spell throws the creature `unit_id` whose life the
  /// go struck, at the monotonic time `struck_at_ms` the go struck it (`HitCreature`): the
  /// connection draws the two fractions of `forced_move.Draws` from its seed, takes the
  /// player's place now and race radius as the `forced_move.Reference` and tells the
  /// creature (genesis_prime/client_connection `TellThrown`). A creature of another life
  /// drops it, and so does one that lies dead or has stood again since the go struck.
  ForcedMoveStarts(
    unit_id: Int,
    life: Int,
    struck_at_ms: Int,
    move: forced_move.Move,
  )
  /// The DespawnUnit row of the caster's spell removes the creature `unit_id` whose life the
  /// go struck, `delay_ms` after `went_at_ms`, the monotonic time of the go; `struck_at_ms`,
  /// the monotonic time the round struck it (`HitCreature`), tells which life of the creature
  /// that was. The connection tells the creature
  /// (genesis_prime/client_connection `TellDespawn`), which owns the delay, so the caster's
  /// leaving or dying changes nothing. A creature of another life drops it, and so does one
  /// that lies dead, is already gone, or has stood again since the round struck it.
  CreatureDespawns(
    unit_id: Int,
    life: Int,
    struck_at_ms: Int,
    went_at_ms: Int,
    delay_ms: Int,
  )
  /// The UnitStateSet rows of the caster's spell hold their states on the creature `unit_id`
  /// whose life the go struck, each from `went_at_ms`, the monotonic time of the go, plus its
  /// delay for its duration; `struck_at_ms`, the monotonic time the round struck it
  /// (`HitCreature`), tells which life of the creature that was. `rows` are the go's rows for
  /// the creature in row order. The connection tells the creature
  /// (genesis_prime/client_connection `TellUnitStates`), which owns the end of each state, so
  /// the caster's leaving or dying changes nothing. A creature of another life drops it, and
  /// so does one that lies dead, is already gone, or has stood again since the round struck it.
  CreatureHoldsUnitStates(
    unit_id: Int,
    life: Int,
    struck_at_ms: Int,
    went_at_ms: Int,
    rows: List(unit_state.Row),
  )
  /// A property modifier the caster's spell started on the creature `unit_id` ends: the
  /// node's end, a removal of the cast, its push off or the caster's death. A creature
  /// that holds nothing for the source changes nothing.
  TargetChangeEnds(unit_id: Int, life: Int, source: unit_properties.Source)
  /// The caster entered or left stealth, the last effect of the input that moved it:
  /// the connection writes 0x8f5 to the caster's client and tells each viewer
  /// (`opcode.0x8f5`, genesis_prime/client_connection `Stealth`).
  StealthChanged(stealthed: Bool)
  /// The last go of an activate cast: the player activated the creature or static object
  /// `unit_id`, of the Creature2 row `creature_id`, which lived when the press started the
  /// cast or did not (`alive_at_press`). The cast is an item's when `by_item`, the
  /// creature's own activate cast otherwise; `cast_id` is that cast, none for the use of a unit
  /// with no activate spell, which casts nothing. An item's cast of a spell with no Activate row
  /// raises none: the Activate effect is what makes a use.
  Activated(
    unit_id: Int,
    creature_id: Int,
    alive_at_press: Bool,
    by_item: Bool,
    cast_id: Option(Int),
  )
  /// The first go of a cast of a quest button's spell (`cast.shortcut`), by its Spell4 id, and
  /// the unit the press aimed it at: none for a spell that takes the caster.
  ShortcutCast(spell4_id: Int, target: Option(PressedAt))
  /// The QuestAdvanceObjective rows of the caster's spell applied: the connection advances the
  /// player's quest objectives (genesis_prime/game/quest_advance), skipping each one the cast's
  /// own use or cast (`with`) counts, which is raised before this effect in the same go.
  QuestAdvanced(advances: List(quest_advance.Advance), with: AdvanceWith)
}

/// The use or cast a QuestAdvanceObjective row was applied with, which counts the objectives
/// it names itself (genesis_prime/game/quest_advance): the activate cast of the unit, as
/// `Activated` raises it, or the quest button's cast, as `ShortcutCast` raises it, or none for
/// a cast that raises neither.
pub type AdvanceWith {
  WithUse(unit_id: Int, creature_id: Int, alive_at_press: Bool, by_item: Bool)
  WithCast(spell4_id: Int, target: Option(PressedAt))
  WithNothing
}

/// The unit a press of a quest button's spell aimed it at (`opcode.0x9d`).
pub type PressedAt {
  PressedAt(
    unit_id: Int,
    /// Whether the unit lived when the press started the cast. The client cancels the cast
    /// only when its target dies during it (`SetUnitDeathState` 0x14045e740), so a cast at
    /// a unit that died is not counted.
    alive_at_press: Bool,
  )
}

/// A go of a live cast that waits for its targets: which cast and phase, the spell,
/// the cast's primary target, which a child cast on a struck unit holds as that
/// unit and any other cast as its caster, and the points the cast spent above its
/// base cost, which choose the effects the go strikes with
/// (genesis_prime/game/spend); none for a cast that spends no more than its cost.
pub type GoAsked {
  GoAsked(
    cast_id: Int,
    phase: Int,
    spell4_id: Spell4Id,
    primary_target: Int,
    spent: Option(Int),
  )
}

/// A tick of a periodic damage row that waits for its unit's answer: which cast, spell
/// and row, the unit in the life the go struck, which go of the cast on the unit started
/// the schedule (counted from 1: a later go starts it again), which tick of that
/// schedule, and the row's damage, which the tick strikes with alone.
pub type TickAsked {
  TickAsked(
    cast_id: Int,
    spell4_id: Spell4Id,
    effect_id: Spell4EffectsId,
    unit_id: Int,
    life: Int,
    go: Int,
    tick: Int,
    blow: spell_area.DamageEffect,
  )
}

/// A unit a go names, from the round that closed (genesis_prime/game/strike).
pub type Struck {
  /// The unit is named in the 0x7f4 with the damage that landed on it, which is
  /// none for a spell that only selects it (Crush's first spell), and the
  /// crowd-control states it took, each listed as an effect of the go with the
  /// instance id its tell gave (genesis_prime/game/strike_tell `Landed`).
  Hit(
    unit_id: Int,
    unit: HitUnit,
    descriptions: List(hit.Description),
    controls: List(strike_tell.ControlLanded),
    /// The interrupt armor the strike took off the unit, which the go's combat log
    /// shows (genesis_prime/game/strike_tell `Landed`).
    armor_removed: Int,
    /// The periodic damage rows of the go whose aim reaches the unit: the go lists each
    /// with a bit result, and each ticks on the unit (`cast.ticked`).
    ticking: List(spell_area.TickingDamage),
  )
  /// The unit deflected the strike: an entry of the 0x7fb, no description and no
  /// child (`opcode.0x7fb`).
  Deflected(unit_id: Int)
  /// The creature took no damage from the strike's blows because it is guarded
  /// (genesis_prime/world_map/creature_guard): named in the 0x7f4 as a `Hit` with no
  /// description, with the states it took, and followed by a combat log entry of type 18
  /// for the striker (`opcode.0x247.immunity`).
  Immune(
    unit_id: Int,
    unit: HitUnit,
    controls: List(strike_tell.ControlLanded),
    armor_removed: Int,
    /// The periodic damage rows of the go whose aim reaches the unit, as on a `Hit`:
    /// an immune unit is still ticked, since the guard may end.
    ticking: List(spell_area.TickingDamage),
  )
}

/// What kind of unit a `Hit` names.
pub type HitUnit {
  /// A creature a player's go struck, in the life the go aimed at
  /// (genesis_prime/game/strike `Aimed`), at the monotonic time `struck_at_ms` the go
  /// struck it: a property modifier the go starts on it is told for that life and
  /// that time (`TargetChangeStarts`).
  HitCreature(life: Int, struck_at_ms: Int)
  /// A player a creature's attack struck (genesis_prime/world_map/creature_fight).
  HitPlayer
}

/// A property modifier a cast started on a creature: the creature's unit, the life
/// the go struck, and the modifier's source. Each end of the cast's node on that unit
/// tells it ended (`TargetChangeEnds`).
pub type OnCreature {
  OnCreature(unit_id: Int, life: Int, source: unit_properties.Source)
}

/// Why the client's message is refused: it ends the connection, because the
/// client's own code never sends it.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: client_connection.Undecoded)
  /// A 0x9a, 0x97 or 0x9d with the client's cast id 0, which its counter never gives
  /// (`opcode.0x9a`, `opcode.0x97`, `opcode.0x9d`).
  NoClientCastId
  /// A 0x801 whose reason and bit are none the client sends together
  /// (`opcode.0x801`).
  UnknownCancel(reason: Int, bit: Int)
  /// A 0x805 whose result is none of the 0, 1, 2 and 3 the client sends
  /// (`opcode.0x805.fields`).
  UnknownAnswer(result: Int)
  /// A 0x805 for a live cast that is not waiting for an interaction's answer: not an
  /// activate cast of castMethod 5, or one already answered (`opcode.0x805.fields`,
  /// `csi.ends`).
  NoInteractionWaits(cast_id: Int)
  /// A 0x805 whose third field is not the waiting cast's Spell4Base id plus 1
  /// (`opcode.0x805.fields`).
  WrongAnswerSpell(cast_id: Int, sent: Int, expected: Int)
  /// A 0x943 for an item that has no spell: the client answers such a use itself and
  /// sends nothing (UseItem `0x1403998e0`).
  NoItemSpell
  /// A 0x943 whose second item is not the one the client sends for the item's spell
  /// (StartItemUseCast `0x140398cc0`).
  NotSentByClient
}

/// What a timer of the rule is for, which `State` keeps by the timer's id.
pub type Due {
  /// The go of phase `phase` of the live cast `cast_id`.
  Go(cast_id: Int, phase: Int)
  /// The live channel `cast_id`'s finish timer: the channel ends at the later of
  /// this timer and the close of its last go's strike round, since the client
  /// expects all of a channel's gos before its 0x7fe (`cast.channel_sequence`).
  Finish(cast_id: Int)
  /// The child cast of `proxy` starts: with the pressed spell as its root and the
  /// spell whose Proxy fired as its parent, which need not be live.
  StartChild(
    root: Spell4Id,
    parent: Spell4Id,
    primary_target: Int,
    proxy: Proxy,
    counted_with: AdvanceWith,
    from: Option(PressedFrom),
  )
  /// The earliest node of the lingering cast `cast_id` ends: its units' 0x811, or
  /// the finish when no node is left.
  NodesEnd(cast_id: Int)
  /// The crowd-control state `state` the cast `spell4_id` put on the unit `unit_id`
  /// ends on the creature: the caster's combat log gets its end entry.
  StateEnd(spell4_id: Spell4Id, unit_id: Int, state: CrowdControlState)
  /// The change of the caster `source` names starts, after its delay.
  ModifierStart(source: unit_properties.Source, change: CasterChange)
  /// The property modifier `on` names starts on its creature, after its delay, for
  /// the go that struck at `struck_at_ms`.
  TargetModifierStart(
    on: OnCreature,
    modifier: unit_properties.Modifier,
    struck_at_ms: Int,
  )
  /// The ForcedMove row `on` names throws its creature, after its delay, for the go that
  /// struck at `struck_at_ms`: it becomes `ForcedMoveStarts`. The end of the cast's node on
  /// the creature cancels it.
  ForcedMoveStart(on: OnCreature, move: forced_move.Move, struck_at_ms: Int)
  /// The property modifier `source` ends, after its duration.
  ModifierEnd(source: unit_properties.Source)
  /// The crowd-control state the caster holds on itself from the effect `source` names
  /// ends, after its delay and duration: the client never ends a state itself, so the
  /// server sends the 0x880 (`cast_control.restriction_ended`).
  RestrictionEnd(source: unit_properties.Source)
  /// The cooldown effect `source` takes effect, after its delay: it changes the
  /// running cooldowns and, when `kept`, the ones that start while it lasts.
  CooldownModifierStarts(
    source: unit_properties.Source,
    modifier: cooldown.Modifier,
    kept: Bool,
  )
  /// The cooldown effect `source` is no longer kept, after its lifetime.
  CooldownModifierEnds(source: unit_properties.Source)
  /// The Proc row `row`, held by `source`, fired for an event of its holder `delay_ms`
  /// ago (`proc.Fires`): its spell is cast at the unit `at`. The fire was counted at the
  /// event. The end of the holder's node cancels it.
  ProcDue(source: unit_properties.Source, row: spell_plan.ProcRow, at: Int)
  /// The QuestAdvanceObjective rows of the go `advances` name apply, after their delay, with the
  /// use or cast of their cast: it becomes `QuestAdvanced`. Neither the cast's end nor the
  /// caster's death cancels it.
  QuestAdvanceDue(advances: List(quest_advance.Advance), with: AdvanceWith)
  /// The held press starts.
  StartHeld
  /// The ability the player holds down casts again: its cooldowns have ended.
  RepeatHeld
  /// The time of the RapidTap threshold of the ability `spell4_id` runs out.
  WindowEnd(spell4_id: Int)
  /// The ChargeRelease threshold of the ability `spell4_id` reaches the charge
  /// level `level`.
  ChargeLevel(spell4_id: Int, level: Int)
  /// Tick `tick` of the periodic row `effect_id` of the cast `cast_id` on the unit
  /// `unit_id` lands (genesis_prime/game/ticking `tick_at_ms`); only the next tick of a
  /// row on a unit is armed.
  Tick(cast_id: Int, effect_id: Spell4EffectsId, unit_id: Int, tick: Int)
}

/// A periodic row of a cast on one unit: the unit, and the Spell4Effects row.
pub opaque type TickKey {
  TickKey(unit_id: Int, effect_id: Spell4EffectsId)
}

/// The key of the periodic row `effect_id` on the unit `unit_id`.
pub fn tick_key(
  unit_id unit_id: Int,
  effect_id effect_id: Spell4EffectsId,
) -> TickKey {
  TickKey(unit_id:, effect_id:)
}

/// The unit the keyed row ticks on.
pub fn key_unit(key key: TickKey) -> Int {
  key.unit_id
}

/// The Spell4Effects row the key names.
pub fn key_effect(key key: TickKey) -> Spell4EffectsId {
  key.effect_id
}

/// The ticks of a periodic row on one unit: what each tick does, the row's schedule,
/// which go of the cast started it (counted from 1) and the monotonic time of that go,
/// which the schedule counts from, the last tick that fired (0 before the first), how
/// many damage tick rounds of the row on the unit are open, an earlier schedule's
/// included, and the life of the unit the go struck. A node whose unit has an open
/// round is held past its end, so the cast's 0x811 or 0x7fe follows the tick's 0x7f8.
pub opaque type Ticking {
  Ticking(
    kind: TickKind,
    schedule: ticking.Schedule,
    go: Int,
    from_ms: Int,
    tick: Int,
    open: Int,
    life: Int,
  )
}

/// The ticks of a row a go starts: no tick has fired, and `open` rounds of an earlier
/// schedule of the row on the unit are still open.
pub fn ticking_started(
  kind kind: TickKind,
  schedule schedule: ticking.Schedule,
  go go: Int,
  from_ms from_ms: Int,
  open open: Int,
  life life: Int,
) -> Ticking {
  Ticking(kind:, schedule:, go:, from_ms:, tick: 0, open:, life:)
}

/// What each tick of the row does.
pub fn ticking_kind(row row: Ticking) -> TickKind {
  row.kind
}

/// The row's schedule.
pub fn ticking_schedule(row row: Ticking) -> ticking.Schedule {
  row.schedule
}

/// Which go of the cast started the row, counted from 1.
pub fn ticking_go(row row: Ticking) -> Int {
  row.go
}

/// The monotonic time of the go the schedule counts from.
pub fn ticking_from_ms(row row: Ticking) -> Int {
  row.from_ms
}

/// The last tick that fired, 0 before the first.
pub fn ticking_tick(row row: Ticking) -> Int {
  row.tick
}

/// How many damage tick rounds of the row on the unit are open.
pub fn ticking_open(row row: Ticking) -> Int {
  row.open
}

/// The life of the unit the go struck.
pub fn ticking_life(row row: Ticking) -> Int {
  row.life
}

/// The row with tick `tick` fired.
pub fn with_tick(row row: Ticking, tick tick: Int) -> Ticking {
  Ticking(..row, tick:)
}

/// The row with tick `tick` fired and a damage tick round opened for it.
pub fn round_opened(row row: Ticking, tick tick: Int) -> Ticking {
  Ticking(..row, tick:, open: row.open + 1)
}

/// The row with a damage tick round closed; the count stays at 0 when none is open.
pub fn round_closed(row row: Ticking) -> Ticking {
  Ticking(..row, open: int.max(0, row.open - 1))
}

/// What a tick does: a damage row strikes its unit with its blow; a heal row heals the
/// caster's vital by its formula, read for the caster at the tick.
pub opaque type TickKind {
  DamageTick(blow: spell_area.DamageEffect)
  HealTick(
    vital: effect_kind.Vital,
    formula: damage.Formula,
    passed_in: Option(Float),
  )
}

/// A tick that strikes its unit with `blow`.
pub fn damage_tick(blow blow: spell_area.DamageEffect) -> TickKind {
  DamageTick(blow:)
}

/// A tick that heals the caster's `vital` by `formula`, reading the passed-in value of the
/// item that started the cast when there is one.
pub fn heal_tick(
  vital vital: effect_kind.Vital,
  formula formula: damage.Formula,
  passed_in passed_in: Option(Float),
) -> TickKind {
  HealTick(vital:, formula:, passed_in:)
}

/// What a tick of `kind` does: `damage` gets the blow and `heal` the vital, formula and
/// passed-in value. The one match over the kinds, so a new kind adds an argument here and
/// names each fold.
pub fn on_tick_kind(
  kind kind: TickKind,
  damage damage: fn(spell_area.DamageEffect) -> result,
  heal heal: fn(effect_kind.Vital, damage.Formula, Option(Float)) -> result,
) -> result {
  case kind {
    DamageTick(blow:) -> damage(blow)
    HealTick(vital:, formula:, passed_in:) -> heal(vital, formula, passed_in)
  }
}

/// A periodic row a go starts ticking on one unit: the unit and the life the go struck
/// (0 for the caster), the row, its schedule and what each tick does.
pub type TickingOn {
  TickingOn(
    unit_id: Int,
    life: Int,
    effect_id: Spell4EffectsId,
    schedule: ticking.Schedule,
    kind: TickKind,
  )
}

/// What a press resolved to when it came: the spell it casts, the ability that
/// was pressed, the bag ability the key names (the second spell of the 0x816 a first
/// press opens), which stage of the ability's open threshold it casts (none for the
/// ability's own spell), whether the spell is a Proxy of a press that has no threshold
/// time (cast as the press itself, so its own threshold opens), and the debug lines the
/// resolve gave.
pub type Resolution {
  Resolution(
    spell: Spell,
    ability: Spell,
    bag_spell: Spell4Id,
    stage: Option(Int),
    proxied: Bool,
    logs: List(Effect),
  )
}

/// What a cast is to its ability's threshold.
pub type Role {
  /// A child a Proxy started, or a cast the server starts of its own for no press (the level-up
  /// fanfare): no threshold is touched. It counts its QuestAdvanceObjective rows with the use
  /// or cast of the cast that started it, `counted_with` (none for a child a proc fire or the
  /// server started), and reads an item's passed-in value as the item's cast does: `from` is
  /// the item's use that pressed the cast that started it (`handed_down`), none otherwise.
  Child(counted_with: AdvanceWith, from: Option(PressedFrom))
  /// The ability's own spell, which opens a threshold when its method has one.
  Base(ability: Spell, bag_spell: Spell4Id)
  /// The stage at `index` of the ability's open threshold.
  Stage(ability: Spell, index: Int)
  /// A class's innate passive, which no press made: no threshold is touched, no
  /// global cooldown starts and it is never the current cast.
  Passive
  /// The activate cast of a unit the player right-clicked: no threshold is touched.
  Activation(activating: Activating, interaction: Interaction)
  /// The cast of a spell on its caster, from a quest button (`opcode.0x9d`) or an item's use
  /// (`opcode.0x943`): no threshold is touched. A quest button's first go counts the
  /// objective that holds the button, with the unit the press aimed it at when it takes one.
  Shortcut(
    interaction: Interaction,
    aimed: Option(PressedAt),
    from: PressedFrom,
  )
}

/// What pressed a cast of a spell on its caster.
pub type PressedFrom {
  /// The button of a cast-a-spell objective: its first go raises `ShortcutCast`.
  QuestButton
  /// An item's use, which counts no objective. `item_level` is Item2.powerLevel, the level
  /// the cast's start tells (`opcode.0x7ff.caster_item_level`); `passed_in` is the
  /// passed-in value at that level (genesis_prime/game/passed_in_value), which the cast's
  /// heals and absorbs read in place of the player's own.
  Item(item_level: Int, passed_in: Float)
}

/// The passed-in value the cast's heals and absorbs read in place of the caster's own: an
/// item's, for the item's cast and the children of it.
pub fn passed_in_of(live live: Live) -> Option(Float) {
  case live.pressed {
    Some(Item(passed_in:, ..)) -> Some(passed_in)
    Some(QuestButton) | None -> None
  }
}

/// What a child of this cast takes from what pressed it: an item's use, so the child's
/// heals read the item's value too; never a quest button, whose objective only the cast
/// itself counts.
pub fn handed_down(live live: Live) -> Option(PressedFrom) {
  case live.pressed {
    Some(Item(..) as from) -> Some(from)
    Some(QuestButton) | None -> None
  }
}

/// The unit an activate cast activates and what its go names on it.
pub type Activating {
  Activating(
    unit_id: Int,
    /// The Creature2 row of the unit.
    creature_id: Int,
    /// Whether the unit lived at the press. The client cancels the cast only when its
    /// target dies during it (`SetUnitDeathState` 0x14045e740), not when the target was
    /// dead at the press.
    alive_at_press: Bool,
    /// Whether the cast is an item's (`cast.use_item`) and not the creature's own activate cast.
    by_item: Bool,
    /// The spell's Activate rows, which the go lists on the unit.
    effects: List(activate.ActivateEffect),
  )
}

/// Where the client's interaction of an activate or shortcut cast stands: the go of a
/// castMethod 5 spell waits for the client's answer 1 (`opcode.0x805.fields`), which
/// sends it at once, and for the answer after the cast time when that has run first.
pub type Interaction {
  /// The spell is not of castMethod 5: its go waits for the cast time alone.
  NoInteraction
  /// The client's interaction has not answered 1 yet.
  AwaitingAnswer
  /// The client answered 1.
  AnswerSucceeded
}

/// A cast of the caster that has started and not finished.
pub type Live {
  Live(
    spell: Spell,
    /// The points the cast spent above its base cost, fixed at its accept; none for a
    /// spell with no spend and for a child a Proxy started.
    spent: Option(Int),
    /// The costs the accept checked and the cast's first go pays: empty once paid,
    /// for a cast whose accept paid them (`cast_cost.pays_at_accept`) and for a child.
    /// A channel's later gos pay its costs again without reserving them
    /// (`cast_cost.pulse_costs`).
    reserved: List(Payment),
    /// The spell the player pressed, the root of every child.
    root: Spell4Id,
    /// The spell whose Proxy started this one; none for the pressed spell.
    parent: Option(Spell4Id),
    primary_target: Int,
    /// The connections told of the start, which its go and finish go to.
    audience: Set(ConnectionId),
    /// How many of its gos have been sent.
    gone: Int,
    /// How many of its gos have been asked: the pulse a channel's cost is paid at is
    /// decided when the go is asked, while `gone` moves when a round closes.
    goes_asked: Int,
    /// The monotonic time the cast started at, which its time left is counted from.
    started_ms: Int,
    /// The ability whose open threshold this cast is a stage of.
    stage_of: Option(Spell),
    /// Whether this cast's finish closes the ability's threshold: a release, and the
    /// last tap.
    closes_threshold: Bool,
    /// The nodes the cast's gos left on units, by unit id: a later go on the same
    /// unit sets its node again (`opcode.0x7f4.instance_count`).
    nodes: Dict(Int, lasting.Node),
    /// The unit the cast activates, for an activate cast.
    activation: Option(Activating),
    /// What the client's interaction has answered, for a spell of castMethod 5 that an
    /// activate or shortcut cast casts.
    interaction: Interaction,
    /// What pressed the cast, for a cast of a spell on its caster and for a child of an item's
    /// cast: a quest button's first go counts its objective, and an item's value is what the
    /// heals and absorbs read in place of the caster's own (`passed_in_of`).
    pressed: Option(PressedFrom),
    /// The unit a quest button's cast was aimed at, when it takes one.
    aimed: Option(PressedAt),
    /// The use or cast the cast's QuestAdvanceObjective rows count with: its own for an activate
    /// or quest button cast, the cast's that started it for a child.
    counted_with: AdvanceWith,
    /// The QuestAdvanceObjective rows an earlier go of the cast applied: a row applies once per
    /// cast, at the first go that reaches it.
    advance_rows_applied: Set(Spell4EffectsId),
    /// Whether a channel's finish timer fired while a go's strike round was still open:
    /// the cast ends when its last go is written, which a round's deadline bounds
    /// (`opcode.0x7f4`: the client counts the gos before its 0x7fe, `cast.channel_sequence`).
    finish_due: Bool,
    /// The periodic rows the cast's gos armed, by unit and row: each lasts while its
    /// unit's node does (`cast_tick.ticks_dropped`).
    ticking: Dict(TickKey, Ticking),
  )
}

/// A cast whose last go has gone and whose nodes still have life left: only its
/// 0x7fe waits until the last node ends, because the client ends no buff on time
/// (`cast.target_node_end`); every other step of its finish has run. `State` keeps it by cast id until a `NodesEnd` timer
/// ends its nodes, a removal takes them off, or the caster dies.
pub type Lingering {
  Lingering(
    spell: Spell,
    /// The connections told of the cast's start, which its 0x811 and 0x7fe go to.
    audience: Set(ConnectionId),
    /// The monotonic time the cast started at: a removal takes the oldest cast
    /// first, and the cast id wraps, so the age is this.
    started_ms: Int,
    /// The unit the cast was aimed at when it started, which its persistence reads.
    primary_target: Int,
    nodes: Dict(Int, lasting.Node),
    /// The periodic rows still ticking, as on its `Live` cast.
    ticking: Dict(TickKey, Ticking),
  )
}

/// An open threshold of one ability: the stage or charge level the next press
/// casts, the bag ability whose press opened it (the second spell of its 0x816, which a
/// press is matched against first), and the id of the base cast, which the client sends
/// back in a 0x801 (`opcode.0x816`).
pub type Threshold {
  Threshold(ability: Spell, bag_spell: Spell4Id, index: Int, cast_id: Int)
}

/// A press the client queued within 500 ms of a cooldown's end, or the server
/// queues within 500 ms of the end of the current cast.
pub type Held {
  Held(client_cast_id: Option(Int), resolution: Resolution, until: HeldUntil)
}

/// The ability whose key the player holds down: it casts when the key goes down
/// and again each time its cast has ended and its cooldowns allow, until the key
/// comes up (`cast.hold_repeat`).
pub type Holding {
  Holding(
    ability: Spell,
    /// The timer that waits for the cooldowns to end, when one runs.
    repeat_timer: Option(TimerId),
    /// The cast the hold started last, once it has started one: until that cast is
    /// over the ability is not cast again, and from then on a cooldown is waited
    /// for and no longer refused.
    last_cast: Option(Int),
  )
}

/// What a held press waits for.
pub type HeldUntil {
  /// The cooldown's end, from a timer.
  CooldownEnds
  /// The go or finish that clears the caster's current cast.
  CastClears
}

/// A Proc row a cast holds on the caster, with the monotonic times of its fires, which
/// its limit counts (`proc.counted`).
pub type HeldProc {
  HeldProc(row: spell_plan.ProcRow, fires_ms: List(Int))
}

/// The press of an item that started a cast: the client's id of the cast (the 0x943's
/// first field, `opcode.0x943`), the Spell4 the item casts and the place of the item the
/// press named. The connection finds the held item at `place` to spend its charge.
pub type ItemPress {
  ItemPress(client_cast_id: Int, spell4_id: Int, place: ItemPlace)
}

/// What an item's press whose checks passed keeps for the start of its cast
/// (`cast.item_started`): the client's id of the cast, the caster as it was checked, the
/// spell with its cast time, the role the cast has and its primary target, the rows an
/// activation drops and the costs the checks found paid. Nothing here is a time: the start
/// stamps the cast with the time it is made at.
pub type ActivationStart {
  ActivationStart(
    client_cast_id: Int,
    caster: Caster,
    spell: Spell,
    role: Role,
    primary_target: Int,
    dropped: activate.Dropped,
    paid: Paid,
  )
}

/// What the rule makes of the caster's 0x943 (`cast.use_item`).
pub type Used {
  /// The press ends here: a refusal's frame, or a press whose id the caster already used.
  /// `cast` and `effects` are applied at once.
  Frames(cast: State, effects: List(Effect))
  /// The press passed its checks and starts a cast, which the rule has not made: the
  /// caster's state is as it was, and the cast is made by `cast.item_started` once the store
  /// has saved the spend of the item's charge (genesis_prime/game/item_charge), at the time
  /// of the answer. It is dropped when the store did not save, so a refused save leaves
  /// the caster as it was.
  Started(press: ItemPress, start: ActivationStart)
}

/// The item the caster holds at the place a 0x943 names: its Item2 and the charges it has
/// left, which the use check reads (`item_use.check`).
pub type ItemAtPlace {
  ItemAtPlace(item2_id: Item2Id, charges: Int)
}

/// What the rule keeps for one player: its cooldowns, its live casts, its open
/// thresholds and what waits on a timer, and the counters its cast ids and timer
/// ids are made from.
pub type State {
  State(
    /// The monotonic time the global cooldown ends at, once one has started. The
    /// monotonic clock can be negative, so 0 never means none.
    global_cooldown_ends_ms: Option(Int),
    /// The running cooldowns of the caster's spells and the cooldown effects kept for
    /// the ones that start later (genesis_prime/game/cooldown). The global cooldown is
    /// the field above: no cooldown effect changes it.
    cooldowns: cooldown.Book,
    casts: Dict(Int, Live),
    /// The casts whose last go has gone and whose nodes still have life left, by
    /// cast id.
    lingering: Dict(Int, Lingering),
    /// The caster's current cast, which a press is refused against (13).
    current: Option(Int),
    /// The open thresholds, by the Spell4 id of the ability.
    thresholds: Dict(Int, Threshold),
    timers: Dict(TimerId, Due),
    held: Option(Held),
    holding: Option(Holding),
    /// How many casts the player has started, which the cast ids are made from.
    presses: Int,
    /// How many timers the rule has started, which the timer ids are made from.
    timers_started: Int,
    /// What the rule has already logged as unbuilt on this connection.
    logged: Set(Unbuilt),
    /// The Stealth rows the caster's casts hold on it, by cast id and effect id, each
    /// with whether damage ends it; the caster is stealthed while this is not empty.
    stealth: Dict(unit_properties.Source, spell_plan.Breaks),
    /// The Proc rows the caster's casts hold on it, by cast id and effect id, each with the
    /// monotonic times of its fires; a proc leaves where a stealth source does
    /// (`cast_proc.procs_dropped`).
    procs: Dict(unit_properties.Source, HeldProc),
    /// The events of the caster that no proc has been matched against yet, in the order
    /// they happened: each input records its own (`cast.settled`), and the connection draws what
    /// they need (`cast_proc.proc_draws_needed`) and has them matched (`cast.procs_fire`).
    pending: List(proc.Event),
    /// The id of the cast of the player's innate passive, once `cast.passive_started` has
    /// started it: the one cast a death leaves.
    passive: Option(Int),
    /// The persistence columns already logged as not read or not checked on this
    /// connection, by Spell4 id and result (282 or 283): one debug line for each.
    persistence_logged: Set(#(Int, Int)),
    /// The property modifiers the caster's casts started on creatures and have not
    /// ended, by cast id, in the order they started: the node's end by time
    /// (`NodesEnd`), a type 80 removal, a push off by the stack rule, the caster's
    /// death and its leaving each tell `TargetChangeEnds` for those of the cast and
    /// unit they end.
    on_creatures: Dict(Int, List(OnCreature)),
    /// The crowd-control states the caster's casts hold on the caster itself (a CCStateSet
    /// row aimed at the caster, `spell_plan.restrictions_in_phase`), by cast id and effect
    /// id: a press of a spell whose caster conditions mask a held state is refused
    /// (`cast_cost.restricted`), and the state ends with its row (`RestrictionEnd`) or with its
    /// cast's node (`cast_proc.effects_ended`), whichever comes first.
    restrictions: Dict(unit_properties.Source, HeldRestriction),
    /// How many such states the caster has told, which their instance ids are made from
    /// (genesis_prime/game/crowd_control `instance_id`).
    restrictions_told: Int,
    /// The highest client cast id of the item presses the caster's state took, once one
    /// has been. The client's id of a cast is its counter's next value, which rises with
    /// every cast and never resets (`0x140c1e71c`), and a connection cannot press the 2^32
    /// times that would wrap it, so a press whose id is not above this one is a repeat
    /// and starts and spends nothing.
    item_press_watermark: Option(Int),
  )
}

/// A crowd-control state the caster holds on itself: the state, the instance id the 0x87f
/// named it by, and the connections that were told it, which its end is told to.
pub type HeldRestriction {
  HeldRestriction(
    state: CrowdControlState,
    instance_id: Int,
    audience: Set(ConnectionId),
  )
}

/// The timer id the rule's first timer takes; the connection's own are below it.
const first_timer = 1000

/// The queue window: a press with this much of a cooldown left or less is sent
/// by the client and held by the server (`player.abilityQueueMax`, `0x1403b14c0`).
pub const queue_window_ms = 500

/// The cast ids start here: 2^31, above where a client counter can reach.
const first_cast_id = 2_147_483_648

/// Each unit has this many cast ids: 2^11.
const ids_per_unit = 2048

/// A player that has cast nothing.
pub fn new() -> State {
  State(
    global_cooldown_ends_ms: None,
    cooldowns: cooldown.new(),
    casts: dict.new(),
    lingering: dict.new(),
    current: None,
    thresholds: dict.new(),
    timers: dict.new(),
    held: None,
    holding: None,
    presses: 0,
    timers_started: 0,
    logged: set.new(),
    stealth: dict.new(),
    procs: dict.new(),
    pending: [],
    passive: None,
    persistence_logged: set.new(),
    on_creatures: dict.new(),
    restrictions: dict.new(),
    restrictions_told: 0,
    item_press_watermark: None,
  )
}

/// Whether an item press with this client cast id is a repeat: its id is not above the
/// highest the caster's state took.
pub fn item_press_refused(
  cast cast: State,
  client_cast_id client_cast_id: Int,
) -> Bool {
  case cast.item_press_watermark {
    Some(watermark) -> client_cast_id <= watermark
    None -> False
  }
}

/// The state with the item press's client cast id taken: the watermark rises to it.
pub fn item_press_recorded(
  cast cast: State,
  client_cast_id client_cast_id: Int,
) -> State {
  State(..cast, item_press_watermark: Some(client_cast_id))
}

/// Whether the caster is stealthed: some Stealth row of its casts holds. The client
/// is told by 0x8f5 and 0x262's create flag 16, and a type 116 prerequisite reads it.
pub fn stealthed(cast cast: State) -> Bool {
  !dict.is_empty(cast.stealth)
}

/// Whether the timer is one of this rule's, for the connection to hand it to
/// `cast.timer_fired`.
pub fn owns(timer timer: TimerId) -> Bool {
  let TimerId(number) = timer
  number >= first_timer
}

/// The id of the `number`th cast of the unit `unit_id`: 2^31 + unit id x 2^11 +
/// number mod 2^11.
pub fn cast_id(unit_id unit_id: Int, number number: Int) -> Int {
  first_cast_id + unit_id * ids_per_unit + number % ids_per_unit
}

/// The number mod 2^11 a cast id was made from: the number after it is the next
/// one a unit's rule offers `mint`, so a rule advances past the id it got, not past
/// the one it asked for.
pub fn number_of(cast_id cast_id: Int) -> Int {
  { cast_id - first_cast_id } % ids_per_unit
}

/// The unit a cast id was made for, which is how a viewer finds the casts of a
/// unit it stops showing.
pub fn caster_of(cast_id cast_id: Int) -> Int {
  { cast_id - first_cast_id } / ids_per_unit
}

/// The first id from the `number`th of the unit `unit_id` that none of the live
/// casts `live` holds: the id the rule gives the next cast. A unit holds at most
/// 2^11 ids, and a caster's live casts are far fewer.
pub fn mint(
  unit_id unit_id: Int,
  number number: Int,
  live live: List(Int),
) -> Int {
  mint_from(unit_id:, number:, live:, tried: 0)
}

fn mint_from(
  unit_id unit_id: Int,
  number number: Int,
  live live: List(Int),
  tried tried: Int,
) -> Int {
  let id = cast_id(unit_id:, number:)
  case list.contains(live, id) && tried < ids_per_unit {
    True -> mint_from(unit_id:, number: number + 1, live:, tried: tried + 1)
    False -> id
  }
}

/// The open issue that owns a gap the server logs as not built.
pub type Issue {
  /// The cast conditions and prerequisites the server does not read.
  PrerequisitesIssue
  /// The spells the server cannot plan or whose states it does not judge.
  SpellsIssue
  /// The items' charges and the checks of an item's use the server does not build.
  ItemsIssue
  /// The crowd-control states that last until removed, which no rule ends with their spell.
  UntilRemovedIssue
}

/// What an aimed press carries through the client's checks.
pub type AimedPress {
  AimedPress(
    cast: State,
    caster: Caster,
    caster_radius: Float,
    now_ms: Int,
    client_cast_id: Int,
    unit_id: Int,
    spell: Spell,
    aim: shortcut_spell.Aim,
    activations: activate.Activations,
    in_cast_group: fn(Int, Int) -> Bool,
    held: List(CrowdControlState),
    /// The unit states the target creature is shown to hold, by number
    /// (genesis_prime/game/unit_state).
    unit_states: List(Int),
  )
}

/// A unit the caster's 0xb3 names, as the caster's connection knows it.
pub type UsedUnit {
  UsedUnit(
    /// The id of the unit's Creature2 row.
    creature_id: Int,
    /// What the row says of its activate cast.
    creature: activate.Creature,
    /// The checklist index its 0x262 carried, the bit a type 94 condition of its activate
    /// pick reads.
    checklist_index: Int,
    /// Whether the caster's quest log opens the creature's link to an objective.
    link: activate.Link,
    /// Where the unit stands and its hit radius.
    body: activate.Body,
    /// Whether the unit lives: a creature the caster's client shows dead is not offered its
    /// interaction (`0x140c48c48`: the interaction kind 39 entry's dead-unit flag is clear).
    /// A static object has no death and is alive.
    alive: Bool,
    /// Whether the server offers the unit's use now: an open objective counts it and its
    /// bit is clear (`objective.use_targets`). The client sends 0xb3 only for a unit whose
    /// interaction it offers.
    offered: Bool,
  )
}

/// What a log of a cast the server does not build is kept once for.
pub type Unbuilt {
  /// A spell, by Spell4 id.
  UnbuiltSpell(spell4_id: Int)
  /// A prerequisite type the server does not read.
  UnreadPrerequisite(prerequisite_type: Int)
  /// A prerequisite type the server does not read, in the prerequisite of a creature's
  /// link to an objective.
  UnreadLinkPrerequisite(prerequisite_type: Int)
  /// The RavelSignal effects an activate cast drops, by the Spell4 id.
  DroppedSignals(spell4_id: Int)
  /// The DespawnUnit effects an activate cast drops, by the Spell4 id.
  DroppedDespawns(spell4_id: Int)
  /// The UnitStateSet effects an activate cast drops, by the Spell4 id.
  DroppedUnitStates(spell4_id: Int)
  /// The crowd-control effects the plan drops from a spell, by the Spell4 id.
  DroppedControls(spell4_id: Int)
  /// A quest button's spell, by Spell4 id.
  UnbuiltShortcut(spell4_id: Int)
  /// A quest button's cast at a creature whose activate pick rests on a prerequisite
  /// type the server does not read, by that type.
  UnreadShortcutPick(prerequisite_type: Int)
  /// A quest button's cast of a spell, by Spell4 id, at another player or at the caster
  /// itself, whose checks (the player faction test `0x1403b4560`, a player's life and
  /// combat, a cast group's test of a player) the server does not build.
  UnbuiltPlayerTarget(spell4_id: Int)
  /// The spell of an item that is used, by Spell4 id.
  UnbuiltItemSpell(spell4_id: Int)
  /// A prerequisite type the server does not read, in the prerequisite of an item.
  UnreadItemPrerequisite(prerequisite_type: Int)
}

/// A fact about the holder the connection saw outside a cast: it started to move, or a class
/// resource slot changed from one value to another.
pub type Fact {
  StartedMoving
  ResourceMoved(slot: Int, from: Float, to: Float)
}

/// The slot of the Stalker's class resource, suit power: 3 of the class's eight slots
/// (genesis_prime/game/class_resource, `LocalizedEnum.CRB_StalkerResource`).
pub const suit_power_slot = 3

/// Spell4CastResult 58, Caster_MustBeDead: a living caster's press of a spell
/// whose caster row asks for a dead one (`Spell4.spell4ConditionsIdCaster`).
pub const caster_must_be_dead = 58

/// What the client's checks make of a press, in its order: the caster's death, a
/// press held already and the method, then CheckCastCaster's own in its order
/// (`0x1403afb10.order`): the current cast, the cooldowns (a press within the queue
/// window passing as the client's 317 does), the caster requirements (waived by the
/// spell's waiver), the innate costs, the weapon and, last, the spell's own cast conditions
/// (`0x1403ace00`).
pub type Verdict {
  /// The press is accepted, and its cast pays these costs at its first go (at the
  /// accept when it goes at once).
  Accept(paid: Paid)
  Refuse(result: cast_result.CastResult)
  /// The press is within the queue window of a cooldown's end; its costs are
  /// checked again and paid when it starts.
  Hold(wait_ms: Int)
  /// The caster's current cast has 500 ms or less left: the press waits for the go
  /// or finish that clears it, which is the server's choice (`cast.press_queue`).
  HoldForCast
  /// The spell waits for a later step: its method is not built, its cost needs a
  /// vital the server does not hold, or a cast condition or waiver is of a type the
  /// server does not read. It is refused, and logged once with the issue that owns it.
  NotBuilt(result: cast_result.CastResult, why: String, issue: Issue)
}

/// Why a press's costs are not paid.
pub type CostRefusal {
  /// The caster's slot holds too little: refused with the cost's result.
  Unpaid(result: Int)
  /// The cost is in a vital the server does not hold.
  Unheld(result: Int)
  /// The cost's EMM id is one the server does not read (genesis_prime/game/spend).
  UnreadSpend(result: Int, emm_id: Int)
}

/// What an accepted press pays and the points it spent above its base cost, which are
/// the cast's n; none when no cost of the spell spends every point held.
pub type Paid {
  Paid(payments: List(Payment), spent: Option(Int))
}

/// Every timer whose purpose `matching` accepts is forgotten and cancelled.
pub fn cancel_timers(
  cast cast: State,
  matching matching: fn(Due) -> Bool,
) -> #(State, List(Effect)) {
  let waiting = dict.filter(cast.timers, fn(_, due) { matching(due) })
  #(
    State(..cast, timers: dict.drop(cast.timers, dict.keys(waiting))),
    list.map(dict.keys(waiting), fn(timer) { CancelTimer(timer:) }),
  )
}

/// A cast that holds nodes, live or lingering, as the rules of lasting effects read
/// it.
pub type Holder {
  Holder(
    spell: Spell,
    audience: Set(ConnectionId),
    started_ms: Int,
    primary_target: Int,
    nodes: Dict(Int, lasting.Node),
    /// The periodic rows the cast's gos armed, whose open rounds hold their nodes.
    ticking: Dict(TickKey, Ticking),
    /// Whether the cast has gone for the last time and waits for its nodes to end.
    lingering: Bool,
  )
}

/// The cast `cast_id` as a holder of nodes, live or lingering.
pub fn holder_of(
  cast cast: State,
  cast_id cast_id: Int,
) -> Result(Holder, Nil) {
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ ->
      Ok(Holder(
        spell: live.spell,
        audience: live.audience,
        started_ms: live.started_ms,
        primary_target: live.primary_target,
        nodes: live.nodes,
        ticking: live.ticking,
        lingering: False,
      ))
    Error(Nil), Ok(lingering) ->
      Ok(Holder(
        spell: lingering.spell,
        audience: lingering.audience,
        started_ms: lingering.started_ms,
        primary_target: lingering.primary_target,
        nodes: lingering.nodes,
        ticking: lingering.ticking,
        lingering: True,
      ))
    Error(Nil), Error(Nil) -> Error(Nil)
  }
}

/// Every cast that holds nodes, live or lingering, in cast id order.
pub fn holders(cast cast: State) -> List(#(Int, Holder)) {
  list.append(dict.keys(cast.casts), dict.keys(cast.lingering))
  |> list.sort(int.compare)
  |> list.filter_map(fn(cast_id) {
    holder_of(cast:, cast_id:)
    |> result.map(fn(holder) { #(cast_id, holder) })
  })
}

/// The unit ids of nodes, in unit id order.
pub fn sorted_units(nodes: List(#(Int, lasting.Node))) -> List(Int) {
  list.map(nodes, fn(entry) { entry.0 }) |> list.sort(int.compare)
}

/// What a death leaves of the innate passive: its live or lingering cast, the timers
/// that belong to its tree, and the stealth sources and the procs it holds.
pub type Aside {
  Aside(
    id: Int,
    live: Option(Live),
    lingering: Option(Lingering),
    timers: List(#(TimerId, Due)),
    stealth: List(#(unit_properties.Source, spell_plan.Breaks)),
    procs: List(#(unit_properties.Source, HeldProc)),
    on_creatures: List(OnCreature),
  )
}

/// The timers the rule waits on with what each is for, in the order they were started.
pub fn timers_in_order(cast cast: State) -> List(#(TimerId, Due)) {
  dict.to_list(cast.timers)
  |> list.sort(fn(first, second) {
    let TimerId(first_number) = first.0
    let TimerId(second_number) = second.0
    int.compare(first_number, second_number)
  })
}

/// The id the caster's next cast takes: the id of its next press that no live or
/// lingering cast holds (the client keeps a lingering cast until its 0x7fe). `cast.start` and the hold that records the cast it starts both ask this, so
/// they name the same cast.
pub fn next_cast_id(cast cast: State, caster caster: Caster) -> Int {
  mint(
    unit_id: caster.unit_id,
    number: cast.presses,
    live: list.append(dict.keys(cast.casts), dict.keys(cast.lingering)),
  )
}

/// The effects of a go that apply once their gates against the caster have passed: the
/// Fluff, SpellForceRemove, property modifier, forced move, struck move, cooldown, Stealth,
/// RemoveStealth, Proc, heal and crowd-control effects (a Proxy's and a gain's gates are
/// `cast_gate.proxy_gates` and `cast_gate.gains_given`), in the plan's rank order
/// (`spell_plan.kind_rank`), which is the order their gates were checked in.
pub type Applied {
  Applied(passed: List(spell_effect.PlannedEffect(spell_plan.Kind)))
}

/// The rows of one kind among the effects a go let pass, in rank order (`as_kind` is the
/// kind's projection, such as `spell_plan.as_proc`).
pub fn passed_of(
  applied applied: Applied,
  as_kind as_kind: fn(spell_plan.Kind) -> Result(payload, Nil),
) -> List(payload) {
  list.filter_map(applied.passed, fn(planned) { as_kind(planned.kind) })
}

/// What a go lists on one unit beside the damage it struck: the effect, its delay
/// and, for a crowd-control state, the instance id its tell gave (the other effects
/// are numbered by their place in the list, `cast_frame.target_info`) and, for a heal, the
/// damage description that shows it.
pub type Listed {
  Listed(
    effect_id: Spell4EffectsId,
    delay_ms: Int,
    instance_id: Option(Int),
    /// The description a heal carries, in place of the plain bit of the other effects.
    damage: Option(SpellDamageDescription),
  )
}

/// The units a go's applied effects aim at: each Fluff and type 80 row with the unit
/// it aims at, each crowd-control state a unit took with that unit, and the effects
/// listed on each unit in the order the units are listed.
pub type Aimed {
  Aimed(
    units: List(#(Int, List(Listed))),
    /// The effects the go reaches in the plan's rank order, each once for each unit it
    /// reaches (`Reached`): every stage of the go that arms an effect walks this one list.
    reached: List(Reached),
    reach_logs: List(Effect),
    controls: List(#(strike_tell.ControlLanded, Int)),
    restrictions: List(#(Restricting, Int)),
    ticking: List(TickingOn),
    /// The rolls the units' target gates left.
    rolls_left: List(Int),
  )
}

/// One effect of a go that reaches a unit: the planned effect, the unit it stands on (the
/// caster's for a row that stands on the caster alone) and what the reach stage made of it.
pub type Reached {
  Reached(
    effect: spell_effect.PlannedEffect(spell_plan.Kind),
    unit_id: Int,
    product: Product,
  )
}

/// The rows of one kind among the effects a go reached, each with the entry that reached it,
/// in the order they were reached (`as_kind` is the kind's projection, such as
/// `spell_plan.as_modifier`). Every effect of a go that arms or tells something per row
/// starts from this list.
pub fn rows_reached(
  reached reached: List(Reached),
  as_kind as_kind: fn(spell_plan.Kind) -> Result(payload, Nil),
) -> List(#(Reached, payload)) {
  list.filter_map(reached, fn(entry) {
    result.map(as_kind(entry.effect.kind), fn(row) { #(entry, row) })
  })
}

/// What the reach stage made of an effect beside its unit.
pub type Product {
  /// Nothing: the effect stands on its unit as it is.
  Plain
  /// A heal that lands on the caster, worked out at the go.
  Healing(healed: Healed)
  /// Whether a cooldown row is kept for the cooldowns that start after it takes effect
  /// (`cast_control.cooldown_kept`).
  CooldownKept(kept: Bool)
}

/// A CCStateSet row of a go aimed at the caster with the instance id its effect holds;
/// `fresh` when this go gave the state, not a later go of a cast that holds it already.
/// The plan refuses a row with an apply prerequisite (`spell_plan.control_of`), so the
/// go gates none.
pub type Restricting {
  Restricting(row: spell_plan.CrowdControl, instance_id: Int, fresh: Bool)
}

/// A heal a go applies: its row, the vital it restores, its delay, the formula's `amount`
/// worked out at the go from the caster as it stood before the go's own effects
/// (genesis_prime/game/damage `amount_on_caster`), which the change carries, and the
/// `split` of it the go tells the client: the amount after the heal multipliers and the
/// shield conversion, and the part the vitals had no room for
/// (genesis_prime/game/heal_split).
pub type Healed {
  Healed(
    effect_id: Spell4EffectsId,
    vital: effect_kind.Vital,
    delay_ms: Int,
    amount: Int,
    split: heal_split.Split,
  )
}

/// What a target apply prerequisite gives for a unit a row reaches: the check of the
/// prerequisite with that unit first and the caster second, in the caster's picture, with
/// the rolls its type 37 conditions take off the front of the rolls given, and the rolls
/// left (`cast_gate.checked`).
pub type TargetVerdict =
  fn(prerequisite.Prerequisite, Int, List(Int)) ->
    #(prerequisite.Verdict, List(Int))

/// Which gate of a row's condition a strike checks: the caster apply prerequisites, with
/// the caster as both units, or the target apply prerequisite for one unit the row reaches.
pub type Side {
  CasterSide
  UnitSide(unit_id: Int)
}

/// The decision of one side of a row's condition at a strike: the condition, the side,
/// what names the row in a debug line and the rolls its type 37 conditions take off the
/// front; the decision and the rolls left follow (`cast_tick.strike_gate`).
pub type StrikeGate =
  fn(spell_plan.Condition, Side, String, List(Int)) ->
    #(GateDecision, List(Int))

/// The source an effect timer is for: a property modifier's, a shield heal's (a start is
/// the only timer a heal has), a cooldown effect's or a state the caster holds. Effect
/// ids are unique, so a source names one row.
pub fn source_of(due due: Due) -> Option(unit_properties.Source) {
  case due {
    ModifierStart(source:, ..)
    | ModifierEnd(source:)
    | RestrictionEnd(source:)
    | CooldownModifierStarts(source:, ..)
    | CooldownModifierEnds(source:) -> Some(source)
    TargetModifierStart(on:, ..) | ForcedMoveStart(on:, ..) -> Some(on.source)
    Go(..)
    | Finish(..)
    | StartChild(..)
    | NodesEnd(..)
    | StateEnd(..)
    | ProcDue(..)
    | QuestAdvanceDue(..)
    | StartHeld
    | RepeatHeld
    | WindowEnd(..)
    | ChargeLevel(..)
    | Tick(..) -> None
  }
}

/// The effects without the cancels of the timers in `kept`.
pub fn without_cancels(
  effects effects: List(Effect),
  of kept: Dict(TimerId, Due),
) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      CancelTimer(timer:) -> !dict.has_key(kept, timer)
      Send(..)
      | Tell(..)
      | StartTimer(..)
      | Log(..)
      | Strike(..)
      | TickStrike(..)
      | Pay(..)
      | Gain(..)
      | CasterChangeStarts(..)
      | CasterChangeEnds(..)
      | TargetChangeStarts(..)
      | ForcedMoveStarts(..)
      | CreatureDespawns(..)
      | CreatureHoldsUnitStates(..)
      | TargetChangeEnds(..)
      | StealthChanged(..)
      | Activated(..)
      | ShortcutCast(..)
      | QuestAdvanced(..) -> True
    }
  })
}

/// Whether a timer holds QuestAdvanceObjective rows back for their delay, which the caster's
/// death leaves running (`cast.died`).
pub fn is_quest_advance(due due: Due) -> Bool {
  case due {
    QuestAdvanceDue(..) -> True
    Go(..)
    | Finish(..)
    | StartChild(..)
    | NodesEnd(..)
    | StateEnd(..)
    | ModifierStart(..)
    | TargetModifierStart(..)
    | ForcedMoveStart(..)
    | ModifierEnd(..)
    | RestrictionEnd(..)
    | CooldownModifierStarts(..)
    | CooldownModifierEnds(..)
    | ProcDue(..)
    | StartHeld
    | RepeatHeld
    | WindowEnd(..)
    | ChargeLevel(..)
    | Tick(..) -> False
  }
}

/// The timers of the effect `source` cancelled.
pub fn cancel_source_timers(
  cast cast: State,
  source source: unit_properties.Source,
) -> #(State, List(Effect)) {
  cancel_timers(cast:, matching: fn(due) { source_of(due:) == Some(source) })
}

/// A row of a spell that ends with its node on the caster: a property modifier, which
/// is told ended, or a cooldown effect, which is dropped from the kept list.
pub type Ending {
  CasterChangeEnding(source: unit_properties.Source, until_removed: Bool)
  CooldownEnding(source: unit_properties.Source)
}

/// What a gate gives at a go: a Proxy's, or a row's.
pub type GateDecision {
  /// Its child starts.
  Starts
  /// A gate fails: the client's answer, nothing to say.
  GateFails
  /// The server cannot tell, and `why` says so in a debug line.
  CannotTell(why: String)
}

/// What becomes of one gain of a go.
pub type GainVerdict {
  Given(gain: class_resource.Gain)
  /// Its prerequisite fails.
  Withheld
  /// It cannot be given, and `why` says so in a debug line: a ticking gain, or a
  /// prerequisite of a type not read.
  NotApplied(why: String)
}

/// The next timer's id, and the state counting it.
/// The timer of `due` started to fire after `after_ms`: the state that keeps it, its id
/// and the effect that starts it.
pub fn armed(
  cast cast: State,
  due due: Due,
  after_ms after_ms: Int,
) -> #(State, TimerId, Effect) {
  let #(cast, timer) = new_timer(cast:)
  #(
    State(..cast, timers: dict.insert(cast.timers, timer, due)),
    timer,
    StartTimer(timer:, after_ms:),
  )
}

fn new_timer(cast cast: State) -> #(State, TimerId) {
  #(
    State(..cast, timers_started: cast.timers_started + 1),
    TimerId(first_timer + cast.timers_started),
  )
}

pub fn position_of(place place: Place) -> SpellPosition {
  SpellPosition(
    x: float32.to_bits(start_place.x(place)),
    y: float32.to_bits(start_place.y(place)),
    z: float32.to_bits(start_place.z(place)),
  )
}

pub fn yaw_of(place place: Place) -> Int {
  float32.to_bits(start_place.facing(place).yaw)
}

/// An effect a creature's cast puts on a unit: its Spell4Effects row, the instance id the
/// client keeps it by and how long it lasts in milliseconds (0 for one that never ends).
pub type CreatureEffect {
  CreatureEffect(effect_id: Int, instance_id: Int, lifetime_ms: Int)
}
