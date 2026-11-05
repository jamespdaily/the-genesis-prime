//// A cast's lasting effects: what a Fluff (17) effect leaves on a unit, how long
//// it stays, and what a SpellForceRemove (80) effect takes off. The cast rule
//// (genesis_prime/game/cast) keeps each cast's nodes and sends the messages;
//// this module holds the rules that stand alone: a node's life and what a
//// removal takes off. The rules are pure.
////
//// ```
//// caster's connection               viewer's connection     clients
////  go (round closed)
////    0x7f4 lists 17/80/damage  ──▶ CastWent ─────────────▶ 0x7f4
////    last go, node with life:
////      lingering, timer at end
////  ... timer NodesEnd fires
////    some nodes left           ──▶ CastTargetsRemoved ───▶ 0x811
////    none left                 ──▶ CastFinished ─────────▶ 0x7fe
////  type 80 go on the caster
////    whole count               ──▶ CastTargetsRemoved ───▶ 0x811
////    part                      ──▶ CastStackRemoved ─────▶ 0x813
//// ```
////
//// - **A buff belongs to a cast**, as a target node of the cast on a unit: one
////   buff for each spell and caster, its stacks the sum of the instance counts of
////   its casts on the unit (`Unit.GetBuffs`, `Spell4Effects.effectType.17`,
////   `opcode.0x7f4.instance_count`).
//// - **A node's life** is its longest effect's: delay plus durationTime, the
////   larger of the two for the spells whose record flag 0x10000000 is set, never
////   ending for Spell4Effects flags bit 2 (`opcode.0x7f4.effect_time`).
//// - **The client ends no buff on time**: only 0x7fe, 0x811 and 0x813 end one, so
////   the server holds a cast's 0x7fe while a node has life left and sends the end
////   itself (`cast.target_node_end`).
//// - **A cast that lingers** holds its nodes after its last go and ends them when
////   their time runs out: 0x811 for the units whose node ends, or the finish 0x7fe
////   when no node is left. A node of flags bit 2 never ends by time. Every other
////   step of the finish runs when the cast starts to linger (the current cast
////   cleared, a Channeled or Multiphase cooldown started, a stage's threshold
////   closed, a held repeat ended); only the 0x7fe waits.
//// - **A removal** takes the first `count` stacks of the matching casts on the
////   unit, oldest cast first: a cast that loses its whole count is 0x811 for the
////   unit, one that keeps some is one 0x813 for each stack lost (`opcode.0x811`,
////   `opcode.0x813`, `Spell4Effects.effectType.80`). The oldest first and the
////   choice of 0x813 for a stack are the server's: no client code reads a type 80
////   row.
//// - **Stacking is the server's rule** (Jim's): each caster keeps at most the
////   stack group's cap of its own casts of the group on a unit, and a new cast at
////   the cap takes that caster's oldest off the unit with 0x811, as a removal does;
////   a cap of 0 keeps one cast per spell. The client reads the group only at load
////   and in tooltips (`Spell4.spell4StackGroupId`, `Spell4StackGroup.stackCap`,
////   `Spell4StackGroup.server_rule`).
//// - **A cast left with no node** gets the finish 0x7fe after its 0x811 when its
////   cast method is 1, 3, 8 or 10, since the client keeps such a cast
////   (`opcode.0x811`).
//// - **A prerequisite reads the nodes** a cast holds on the unit as `Held`: type
////   15 any held of the spell, type 50 a held of the spell by the second unit, type
////   59 the sum of the counts (`Prerequisite.prerequisiteTypeId.50`, `.59`).
////
//// What happens at each failure point of a lasting effect:
////
//// | Step | Killed there | Twice at once | Late |
//// |---|---|---|---|
//// | A go lists a lasting effect | the connection restarts from storage and the socket closes, so the client drops every cast | two casts of one spell: two nodes, the stacks add | n/a |
//// | The last go, the cast lingers | as above | a new press of the same spell starts a new cast id; the lingering one stays | n/a |
//// | The `NodesEnd` timer fires | as above | two nodes ending at the same millisecond: one 0x811 naming both | fires after a type 80 took the cast off: no cast, no frame |
//// | A type 80 removes a cast | as above | a removal and the timer in one step: the removal first, the timer finds nothing | n/a |
//// | The caster dies | its live and lingering casts finish with a 0x7fe each (the server's choice: the client has no death path, `cast.target_node_end`) | | |
//// | The caster leaves | nothing is written: the viewers' 0x355 of the caster finishes its casts on their clients (`0x1404550d0`) | | |
//// | A viewer leaves sight | the 0x7fe of each cast it wrote comes before the 0x355 | | |

import genesis_prime/table/id.{type Spell4BaseId, type Spell4Id}

/// How long a node stays on its unit.
pub type Life {
  /// No effect of the node has a lifetime: the spell is no buff there.
  NoLife
  /// The node ends at this monotonic time in milliseconds.
  EndsAt(ms: Int)
  /// The node ends only when the server takes it off (flags bit 2).
  UntilRemoved
}

/// A cast's hold on one unit: the node the client keeps for it, with the stacks
/// the cast gave there and the life of its effects.
pub type Node {
  Node(unit_id: Int, count: Int, life: Life)
}

/// The columns of one Fluff row that give a node its life: the effect's delay and
/// durationTime in milliseconds, and whether its flags have bit 2
/// (`Spell4Effects.effectType.17`).
pub type LastingRow {
  LastingRow(delay_ms: Int, duration_ms: Int, until_removed: Bool)
}

/// The life of a node from the effects a go lists for its unit: each effect's
/// delay plus durationTime, counted from `go_ms`, the larger of the two instead of
/// their sum when `longer_of_delay_and_duration` (a spell whose propertyFlags have
/// bit 0x2000, the spell record's flag 0x10000000, `0x140568540`);
/// `UntilRemoved` when any effect has flags bit 2; the longest effect decides;
/// `NoLife` when none has a lifetime (`opcode.0x7f4.effect_time`).
pub fn life_of(
  effects effects: List(LastingRow),
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
  go_ms go_ms: Int,
) -> Life {
  todo as "shape commit: the life of a node"
}

/// What a cast holds on a unit as a prerequisite reads it: the Spell4 it casts,
/// its caster's unit id and the stacks the cast gave there. A live cast whose
/// primary target is the unit holds a node with count 0 (the same test type 15
/// has always made).
pub type Held {
  Held(spell4_id: Spell4Id, caster: Int, count: Int)
}

/// Which casts a type 80 row takes off (`Spell4Effects.effectType.80`, dataBits00
/// 1, 2 or 3 with dataBits01).
pub type Selector {
  /// The spells of a spell group: Spell4GroupList's spellGroupId values.
  Group(spell_group_id: Int)
  /// The Spell4 itself.
  Spell(spell4_id: Spell4Id)
  /// Every Spell4 of the Spell4Base.
  Base(spell4_base_id: Spell4BaseId)
}

/// A spell's stack group and the most casts of the group one caster keeps on a
/// unit (`Spell4.spell4StackGroupId`, `Spell4StackGroup.stackCap`). A cap of 0
/// keeps one cast per spell.
pub type Stack {
  Stack(group_id: Int, cap: Int)
}

/// A cast's node on one unit as removals and stacking read it: the cast, the spell
/// it casts with the Spell4Base, spell groups and stack the rules test, when it
/// started (its age: cast ids wrap, so they do not give it), and the node.
pub type Hold {
  Hold(
    cast_id: Int,
    spell4_id: Spell4Id,
    base: Spell4BaseId,
    groups: List(Int),
    stack: Stack,
    started_ms: Int,
    node: Node,
  )
}

/// What a removal does on one unit.
pub type Removal {
  /// The cast loses its whole node: 0x811.
  NodeOff(cast_id: Int, unit_id: Int)
  /// The cast loses one stack: 0x813.
  StackOff(cast_id: Int, unit_id: Int)
}

/// What a type 80 row with `selector` and `count` takes off the unit `unit_id`,
/// from `holds`, oldest `started_ms` first: each matching hold on the unit loses its
/// whole count while `count` stacks remain to take (`NodeOff`), and the cast that
/// `count` ends inside loses one `StackOff` for each stack left to take. Oldest
/// first is the server's choice.
pub fn removals(
  holds holds: List(Hold),
  selector selector: Selector,
  count count: Int,
  unit_id unit_id: Int,
) -> List(Removal) {
  todo as "shape commit: what a removal takes off"
}

/// The holds a new cast of `spell4_id` with `stack` pushes off the unit `unit_id`
/// when it gives the unit a node with life, from `holds`, the caster's own live and
/// lingering holds on that unit: with a cap of 1 or more, the holds of the same
/// stack group beyond the cap less one, oldest `started_ms` first, each a
/// `NodeOff`; with a cap of 0, those of the same spell. This is Jim's server rule:
/// the client reads a stack group only at load and in tooltips, and the rows give
/// the cap but no rule for a cast at it (`Spell4.spell4StackGroupId`,
/// `Spell4StackGroup.stackCap`, `Spell4StackGroup.server_rule`).
pub fn pushed_off(
  holds holds: List(Hold),
  spell4_id spell4_id: Spell4Id,
  stack stack: Stack,
  unit_id unit_id: Int,
) -> List(Removal) {
  todo as "shape commit: what a new cast at the stack cap pushes off"
}
