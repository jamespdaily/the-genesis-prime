//// The cast rule's absorb and property modifier on another player the press named
//// (`genesis_prime/game/cast` `OtherPlayerChangeStarts`, `OtherPlayerChangeEnds`): the go
//// tells the player's connection each change and lists the row on the player, and every
//// path that ends the cast's node on the player tells the end once. Expected values come
//// from these places.
//// - Phantasmal Armor tier 9, Spell4 54806 (`table_rows -- Spell4 54806`): castTime 0,
////   propertyFlags 257 (0x100), stack group 387; its Absorption row 130470 (effectType 29,
////   targetFlags 2, mask 7, durationTime 10000, delayTime 0, phaseFlags 1, formula 2.6053 of
////   the Support Power and 103.41 a level) and its UnitPropertyModifier row 130474
////   (effectType 11, targetFlags 2, property 161, mode 3, multiplier 0.86f, durationTime
////   10000, delayTime 0, phaseFlags -1), neither with a gate. A level-1 Novice has Support
////   Rating 55.6875, Support Power 13.921875, so the pool is round(round(2.6053 x 13.921875)
////   + 103.41 x 1) = round(36 + 103.41) = 139 (the stat part is rounded alone,
////   `0x140565600`, as `cast_heal_test` works Mind Over Body's).
//// - `cast.target_node_end`: no timer of the client ends a node or a buff; the 0x811 ends a
////   unit's node, the 0x7fe the cast's, the removal of a caster's unit keeps a cast whose
////   spell holds propertyFlags 0x100, and a unit's death is not a path.
//// - The server's choices, in the cast rule's doc: a change on another player ends when the
////   cast's node on that player ends (by time, a removal, a push off by the stack rule), when
////   the caster dies or leaves, and, for a spell that outlives its caster's sight, by a timer
////   of its own after the caster loses sight of the player.
//// The ally is unit 40, in connection 2's stay 2; the caster is the default caster's unit 7.

import attacker_support
import cast_support as support
import genesis_prime/game/activate
import genesis_prime/game/cast
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/held_changes
import genesis_prime/game/lasting
import genesis_prime/game/player_address.{type PlayerAddress, PlayerAddress}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Plans, type Spell, Always, Spell}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{type Source}
import genesis_prime/step.{type TimerId, ConnectionId}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import map_support
import owned_test
import player_state_support
import prerequisite_support
import spell_tables

const ally = 40

const bag_of_base_1 = 8

const bag_of_base_3 = 11

const absorb_id = 130_470

const modifier_id = 130_474

fn address() -> PlayerAddress {
  PlayerAddress(
    connection: ConnectionId(2),
    unit_id: ally,
    stay: map_support.stay(count: 2),
  )
}

/// The Novice Esper, who holds 1000 Focus (Phantasmal Armor's cost) and sees these players.
fn esper_seeing(players players: List(Int)) -> Caster {
  cast_state.Caster(
    ..support.caster(),
    resources: support.holding_focus(class_id: 3, focus: 1000.0),
    stats: attacker_support.novice(),
    other_players: player_state_support.in_range_of_the_caster(units: players),
    players_in_sight: dict.from_list(
      list.map(players, fn(unit_id) {
        #(unit_id, PlayerAddress(..address(), unit_id:))
      }),
    ),
  )
}

/// What each unit is to the caster: the ally a player, any other unit unseen.
fn picture(unit_id: Int) -> activate.Target {
  case unit_id == ally {
    True -> activate.AnotherPlayer
    False -> activate.Unseen
  }
}

fn plans_of(spell spell: Spell) -> Plans {
  support.with_spells(plans: support.plans(), spells: [spell])
}

/// A 0x9a at the unit `target` of the ability in bag slot `bag` of `plans`, taken by the rule.
fn pressed_at_in(
  plans plans: Plans,
  bag bag: Int,
  target target: Int,
  state state: State,
  caster caster: Caster,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    cast.take(
      cast: state,
      message: cast_state.Pressed,
      body: support.press_body(
        client_cast_id: 9,
        bag_index: bag,
        target:,
        press: 1,
      ),
      caster:,
      plans:,
      target_of: picture,
      now: support.at(ms:),
    )
    as "the press in sight is taken"
  taken
}

/// The press at the unit `target` and its go of the ability in bag slot `bag` of `plans`,
/// answered by a round that struck nobody (the ally is no creature and answers nothing), for
/// the caster at the go: the state after, the press's effects and the go's, with the rolls
/// the go's type 37 conditions take.
fn pressed_at_and_gone_in(
  plans plans: Plans,
  bag bag: Int,
  target target: Int,
  state state: State,
  at_press at_press: Caster,
  at_go at_go: Caster,
  rolls rolls: List(Int),
  at ms: Int,
) -> #(State, List(Effect), List(Effect)) {
  let #(state, pressed) =
    pressed_at_in(plans:, bag:, target:, state:, caster: at_press, at: ms)
  let #(state, went) =
    support.answered_each(
      caster: at_go,
      state:,
      effects: pressed,
      at: ms,
      struck_of: fn(_) { [] },
      rolls:,
      poses: dict.new(),
    )
  #(state, pressed, went)
}

/// The press at the ally and its go of the ability in bag slot `bag` of `plans`.
fn pressed_and_gone_in(
  plans plans: Plans,
  bag bag: Int,
  state state: State,
  at_press at_press: Caster,
  at_go at_go: Caster,
  rolls rolls: List(Int),
  at ms: Int,
) -> #(State, List(Effect), List(Effect)) {
  pressed_at_and_gone_in(
    plans:,
    bag:,
    target: ally,
    state:,
    at_press:,
    at_go:,
    rolls:,
    at: ms,
  )
}

/// The press and its go of the spell, as `pressed_and_gone_in` has them for its ability.
fn pressed_and_gone(
  spell spell: Spell,
  state state: State,
  at_press at_press: Caster,
  at_go at_go: Caster,
  rolls rolls: List(Int),
  at ms: Int,
) -> #(State, List(Effect), List(Effect)) {
  pressed_and_gone_in(
    plans: plans_of(spell:),
    bag: bag_of_base_3,
    state:,
    at_press:,
    at_go:,
    rolls:,
    at: ms,
  )
}

/// The changes a step tells other players, in order.
fn told(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      cast_state.OtherPlayerChangeStarts(..)
      | cast_state.OtherPlayerChangeEnds(..) -> True
      _ -> False
    }
  })
}

fn source_of(cast_id cast_id: Int, effect_id effect_id: Int) -> Source {
  support.source_of(cast_id:, effect_id:)
}

/// The absorb pool of row 130470 told for the cast: 139 of every damage type.
fn pool_starts(
  cast_id cast_id: Int,
  sight sight: held_changes.Sight,
) -> Effect {
  cast_state.OtherPlayerChangeStarts(
    address: address(),
    source: source_of(cast_id:, effect_id: absorb_id),
    change: held_changes.Absorb(amount: 139, mask: 7),
    sight:,
  )
}

/// The modifier of row 130474 told for the cast: property 161 by 0.86f.
fn armor_starts(
  cast_id cast_id: Int,
  sight sight: held_changes.Sight,
) -> Effect {
  let assert spell_plan.StruckChange(modifier:, ..) =
    support.armor_modifier_row(
      id: modifier_id,
      aim: spell_plan.AimsAtPrimaryTarget,
    ).change
    as "row 130474 is a StruckChange"
  cast_state.OtherPlayerChangeStarts(
    address: address(),
    source: source_of(cast_id:, effect_id: modifier_id),
    change: held_changes.Property(modifier:),
    sight:,
  )
}

fn chance_gate() -> prerequisite.Prerequisite {
  prerequisite_support.single(id: 4585, condition: #(37, 6, 0, 50))
}

/// What one press at the ally comes to at its go: the spell, the caster at the go, the rolls
/// the go's type 37 conditions take, the effect ids the 0x7f4 lists on the ally, the changes
/// told (the cast id gives their sources) and the words of the debug lines.
type Go {
  Go(
    why: String,
    spell: Spell,
    at_go: Caster,
    rolls: List(Int),
    listed: List(Int),
    told: fn(Int) -> List(Effect),
    debug: List(String),
  )
}

/// Phantasmal Armor's spell with its absorb row changed by `absorb`.
fn armor_with(
  absorb absorb: fn(spell_plan.PropertyModifier) -> spell_plan.PropertyModifier,
) -> Spell {
  let assert [absorb_row, modifier_row] = support.armor_rows()
    as "the armor has an absorb row and a modifier row"
  support.armor_spell(rows: [absorb(absorb_row), modifier_row])
}

pub fn a_go_tells_the_absorb_and_the_modifier_of_a_press_on_a_player_in_sight_and_lists_them_on_that_player_test() -> Nil {
  use <- owned_test.run(5000)
  let kept = held_changes.KeptWhenUnseen
  let ends_with_sight = held_changes.EndsWhenUnseen
  let both = fn(id) {
    [
      pool_starts(cast_id: id, sight: kept),
      armor_starts(cast_id: id, sight: kept),
    ]
  }
  let modifier_only = fn(id) { [armor_starts(cast_id: id, sight: kept)] }
  let gated = fn(condition) {
    armor_with(absorb: fn(row) {
      spell_plan.PropertyModifier(..row, condition:)
    })
  }
  let rows = [
    Go(
      why: "Phantasmal Armor tier 9 at the ally in sight: both rows are listed on the ally and each told in the plan's row order, the pool of 139 and the modifier, kept when unseen because the spell holds propertyFlags 0x100",
      spell: support.armor_spell(rows: support.armor_rows()),
      at_go: esper_seeing(players: [ally]),
      rolls: [],
      listed: [absorb_id, modifier_id],
      told: both,
      debug: [],
    ),
    Go(
      why: "the ally out of the caster's sight at the go: nothing is listed on it, nothing is told, and a debug line names each row",
      spell: support.armor_spell(rows: support.armor_rows()),
      at_go: esper_seeing(players: []),
      rolls: [],
      listed: [],
      told: fn(_) { [] },
      debug: ["130470", "130474", "not in the caster's sight"],
    ),
    Go(
      why: "a spell whose propertyFlags lack 0x100: the changes end when the caster is unseen",
      spell: Spell(
        ..support.armor_spell(rows: support.armor_rows()),
        outlives_caster: False,
      ),
      at_go: esper_seeing(players: [ally]),
      rolls: [],
      listed: [absorb_id, modifier_id],
      told: fn(id) {
        [
          pool_starts(cast_id: id, sight: ends_with_sight),
          armor_starts(cast_id: id, sight: ends_with_sight),
        ]
      },
      debug: [],
    ),
    Go(
      why: "a row behind a caster apply prerequisite whose roll fails (4585: type 37, at most 50, roll 80) is not listed and not told",
      spell: gated(spell_plan.GatedOnCaster(gates: [chance_gate()])),
      at_go: esper_seeing(players: [ally]),
      rolls: [80],
      listed: [modifier_id],
      told: modifier_only,
      debug: [],
    ),
    Go(
      why: "the same gate with a roll of 30 passes: the row is listed and told",
      spell: gated(spell_plan.GatedOnCaster(gates: [chance_gate()])),
      at_go: esper_seeing(players: [ally]),
      rolls: [30],
      listed: [absorb_id, modifier_id],
      told: both,
      debug: [],
    ),
    Go(
      why: "a row behind a target apply prerequisite whose roll fails is decided once at the go, for the ally: not listed, not told",
      spell: gated(spell_plan.GatedOnTarget(prerequisite: chance_gate())),
      at_go: esper_seeing(players: [ally]),
      rolls: [80],
      listed: [modifier_id],
      told: modifier_only,
      debug: [],
    ),
    Go(
      why: "a row behind a target apply prerequisite of a type the server does not read cannot be told: not listed, not told, and a debug line says so",
      spell: gated(
        spell_plan.GatedOnTarget(
          prerequisite: prerequisite_support.unread_row(),
        ),
      ),
      at_go: esper_seeing(players: [ally]),
      rolls: [],
      listed: [modifier_id],
      told: modifier_only,
      debug: ["130470", "which is not read"],
    ),
    Go(
      why: "a row with a delay lands nothing on a player (stated gap: none of the 14 rows has one): not listed, not told, a debug line",
      spell: armor_with(absorb: fn(row) {
        spell_plan.PropertyModifier(
          ..row,
          row: lasting.LastingRow(
            delay_ms: 1000,
            duration_ms: 10_000,
            until_removed: False,
          ),
        )
      }),
      at_go: esper_seeing(players: [ally]),
      rolls: [],
      listed: [modifier_id],
      told: modifier_only,
      debug: ["130470", "delay"],
    ),
  ]
  list.each(rows, fn(row) {
    let #(_, pressed, went) =
      pressed_and_gone(
        spell: row.spell,
        state: cast_state.new(),
        at_press: esper_seeing(players: [ally]),
        at_go: row.at_go,
        rolls: row.rolls,
        at: 1000,
      )
    let id = support.pressed_id(effects: pressed)
    let on_ally =
      list.filter(support.listed_by_unit(effects: went), fn(unit) {
        unit.0 == ally
      })
      |> list.flat_map(fn(unit) { unit.1 })
    assert on_ally == row.listed as row.why
    assert told(effects: went) == row.told(id) as row.why
    assert support.caster_change_starts(effects: went) == []
      && support.target_changes(effects: went) == []
      as { row.why <> ": no change is told for the caster or a creature" }
    let lines = support.debug_lines(effects: went)
    assert list.all(row.debug, fn(words) {
      list.any(lines, string.contains(_, words))
    })
      as { row.why <> ": the debug lines say " <> string.join(row.debug, ", ") }
    assert row.debug != [] || lines == []
      as { row.why <> ": and none is written otherwise" }
  })
  // The first row's timing: both are listed at delay 0, and the cast's node on the ally
  // lives the rows' 10 000 ms, so its 0x7fe is at the go plus 10 000.
  let #(state, pressed, went) =
    pressed_and_gone(
      spell: support.armor_spell(rows: support.armor_rows()),
      state: cast_state.new(),
      at_press: esper_seeing(players: [ally]),
      at_go: esper_seeing(players: [ally]),
      rolls: [],
      at: 1000,
    )
  assert support.listed_with_delays(effects: went)
    == [#(ally, [#(absorb_id, 0), #(modifier_id, 0)])]
    as "opcode.0x7f4.target_info: both rows are listed on the ally with delay 0"
  let id = support.pressed_id(effects: pressed)
  let #(_, fired) =
    support.run_timers_each(
      caster: esper_seeing(players: [ally]),
      state:,
      effects: list.append(pressed, went),
      from_ms: 1000,
      struck_of: fn(_) { [] },
    )
  assert list.filter_map(fired, fn(step) {
      case support.finished_ids(support.writes(effects: step.1)) {
        [finished] if finished == id -> Ok(step.0)
        _ -> Error(Nil)
      }
    })
    == [11_000]
    as "the node on the ally lives the rows' 10 000 ms: the cast's 0x7fe is at the go plus 10 000"
  // A second go of the same cast tells the change again, and its end timer replaces the
  // first's: the one end is told at the second go plus 10 000.
  let two_gos =
    Spell(
      ..support.armor_spell(rows: [
        support.armor_modifier_row(
          id: modifier_id,
          aim: spell_plan.AimsAtPrimaryTarget,
        ),
      ]),
      phase_delays_ms: [0, 1000],
    )
  let #(state, pressed, went) =
    pressed_and_gone(
      spell: two_gos,
      state: cast_state.new(),
      at_press: esper_seeing(players: [ally]),
      at_go: esper_seeing(players: [ally]),
      rolls: [],
      at: 1000,
    )
  let id = support.pressed_id(effects: pressed)
  let #(_, fired) =
    support.run_timers_each(
      caster: esper_seeing(players: [ally]),
      state:,
      effects: list.append(pressed, went),
      from_ms: 1000,
      struck_of: fn(_) { [] },
    )
  assert list.filter_map(fired, fn(step) {
      case told(effects: step.1) {
        [] -> Error(Nil)
        changes -> Ok(#(step.0, changes))
      }
    })
    == [
      #(2000, [armor_starts(cast_id: id, sight: kept)]),
      #(12_000, [
        cast_state.OtherPlayerChangeEnds(
          address: address(),
          source: source_of(cast_id: id, effect_id: modifier_id),
        ),
      ]),
    ]
    as "the second go tells the modifier again, and the one end is told 10 000 ms after it, none at the first go's end"
}

/// The timers waiting for the end of a change on a player, in the order they started.
fn player_end_timers(state state: State) -> List(TimerId) {
  list.filter_map(cast_state.timers_in_order(cast: state), fn(entry) {
    case entry.1 {
      cast_state.PlayerChangeEnd(..) -> Ok(entry.0)
      _ -> Error(Nil)
    }
  })
}

/// The timers waiting for the end of the cast's nodes.
fn nodes_end_timers(state state: State) -> List(TimerId) {
  list.filter_map(cast_state.timers_in_order(cast: state), fn(entry) {
    case entry.1 {
      cast_state.NodesEnd(..) -> Ok(entry.0)
      _ -> Error(Nil)
    }
  })
}

/// Each timer fired at `at`, in order, for a caster who sees these players: the state after
/// and the effects of every step.
fn fired_in_order(
  state state: State,
  timers timers: List(TimerId),
  seeing seeing: List(Int),
  at ms: Int,
) -> #(State, List(Effect)) {
  list.fold(timers, #(state, []), fn(so_far, timer) {
    let #(state, done) = so_far
    let #(state, more) =
      support.fired_raw_as(
        caster: esper_seeing(players: seeing),
        state:,
        timer:,
        at: ms,
      )
    #(state, list.append(done, more))
  })
}

/// The ends of the two changes of the cast `id` on the ally.
fn ends_of(cast_id cast_id: Int) -> List(Effect) {
  [
    cast_state.OtherPlayerChangeEnds(
      address: address(),
      source: source_of(cast_id:, effect_id: absorb_id),
    ),
    cast_state.OtherPlayerChangeEnds(
      address: address(),
      source: source_of(cast_id:, effect_id: modifier_id),
    ),
  ]
}

/// How one path ends the cast's node on the ally: the spell and the caster at the press and
/// the go, what the path does to the state the go left (given the cast's id) and the effects
/// it gives, whether it writes the cast's 0x7fe, and whether it writes the 0x811 that takes
/// the cast's node off the ally.
type Path {
  Path(
    why: String,
    spell: Spell,
    caster: Caster,
    run: fn(State, Int) -> #(State, List(Effect)),
    finishes: Bool,
    removes_node: Bool,
  )
}

/// Phantasmal Armor tier 9's ability with `caster_persistence` that asks the caster to be in
/// combat (Prerequisite 903, type 28 comparison 1), for the paths that end a cast by its
/// persistence.
fn armor_in_combat(spell spell: Spell) -> Spell {
  Spell(
    ..spell,
    caster_persistence: Some(
      prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0)),
    ),
  )
}

/// The plans of the armor and of a planted spell of base 1 pressed at the same player that
/// takes the armor's cast off it with a type 80 row (SpellForceRemove, a selector of the
/// armor's Spell4, a count of 1, aimed at the primary target).
fn armor_and_its_removal(spell spell: Spell) -> Plans {
  support.with_spells(plans: plans_of(spell:), spells: [
    support.with_effects(
      spell: Spell(
        ..support.child(spell4_id: 301, base: 1),
        targeting: spell.targeting,
      ),
      kinds: [
        spell_plan.RemoveEffect(spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(196_521),
          phase_flags: -1,
          aim: spell_plan.AimsAtPrimaryTarget,
          selector: lasting.Spell(spell.spell4_id),
          count: 1,
          condition: Always,
          tag: spend.always,
        )),
      ],
    ),
  ])
}

pub fn the_end_of_a_change_told_to_a_player_is_told_once_by_each_path_that_ends_its_node_test() -> Nil {
  use <- owned_test.run(5000)
  let seen = esper_seeing(players: [ally])
  let fighting = cast_state.Caster(..seen, in_combat: True)
  let unkept =
    Spell(
      ..support.armor_spell(rows: support.armor_rows()),
      outlives_caster: False,
    )
  let removed = fn(state) {
    cast_proc.unit_removed(cast: state, unit_id: ally, now_ms: 1100)
  }
  let paths = [
    Path(
      why: "time: each change's end timer fires at the go plus 10 000 and tells its end, and the node's end in the same millisecond tells nothing more but writes the 0x7fe",
      spell: support.armor_spell(rows: support.armor_rows()),
      caster: seen,
      run: fn(state, _) {
        fired_in_order(
          state:,
          timers: list.append(
            player_end_timers(state:),
            nodes_end_timers(state:),
          ),
          seeing: [ally],
          at: 11_000,
        )
      },
      finishes: True,
      removes_node: False,
    ),
    Path(
      why: "time, the node's end first: it ends both, and the end timers, late, tell nothing more",
      spell: support.armor_spell(rows: support.armor_rows()),
      caster: seen,
      run: fn(state, _) {
        fired_in_order(
          state:,
          timers: list.append(
            nodes_end_timers(state:),
            player_end_timers(state:),
          ),
          seeing: [ally],
          at: 11_000,
        )
      },
      finishes: True,
      removes_node: False,
    ),
    Path(
      why: "the caster's death ends both and writes the 0x7fe that the client keeps a 0x100 buff for",
      spell: support.armor_spell(rows: support.armor_rows()),
      caster: seen,
      run: fn(state, _) {
        cast.died(
          cast: state,
          caster: support.dead_caster(),
          now: support.at(ms: 1100),
        )
      },
      finishes: True,
      removes_node: False,
    ),
    Path(
      why: "the caster leaving ends both and writes nothing",
      spell: support.armor_spell(rows: support.armor_rows()),
      caster: seen,
      run: fn(state, _) { cast_tick.left(cast: state) },
      finishes: False,
      removes_node: False,
    ),
    Path(
      why: "the ally leaving the caster's sight, for a spell that does not hold 0x100, ends both; a second removal ends nothing more and the end timers, late, tell nothing",
      spell: unkept,
      caster: seen,
      run: fn(state, _) {
        let timers = player_end_timers(state:)
        let #(state, first) = removed(state)
        let #(state, second) = removed(state)
        let #(state, late) =
          fired_in_order(state:, timers:, seeing: [], at: 11_000)
        #(state, list.flatten([first, second, late]))
      },
      finishes: True,
      removes_node: False,
    ),
    Path(
      why: "the ally leaving the caster's sight, for a spell that holds 0x100, ends nothing then; each end timer tells its end at the go plus 10 000, addressed from the go's address though the caster no longer sees the ally",
      spell: support.armor_spell(rows: support.armor_rows()),
      caster: seen,
      run: fn(state, _) {
        let #(state, removal) = removed(state)
        assert told(effects: removal) == []
          as "a change of a spell that outlives its caster's sight is kept at the removal"
        assert list.length(player_end_timers(state:)) == 2
          as "and each change keeps its end timer"
        let #(state, ended) =
          fired_in_order(
            state:,
            timers: player_end_timers(state:),
            seeing: [],
            at: 11_000,
          )
        #(state, list.append(removal, ended))
      },
      finishes: True,
      removes_node: False,
    ),
    Path(
      why: "a type 80 removal of the cast's node on the ally ends both and writes the 0x811 that takes the node off it, and the end timers are cancelled, so they tell nothing at the go plus 10 000",
      spell: support.armor_spell(rows: support.armor_rows()),
      caster: seen,
      run: fn(state, _) {
        let timers = player_end_timers(state:)
        assert list.length(timers) == 2
          as "the go started an end timer for each change"
        let #(state, _, removal) =
          pressed_and_gone_in(
            plans: armor_and_its_removal(
              spell: support.armor_spell(rows: support.armor_rows()),
            ),
            bag: bag_of_base_1,
            state:,
            at_press: seen,
            at_go: seen,
            rolls: [],
            at: 1100,
          )
        assert player_end_timers(state:) == []
          as "the removal cancels both end timers"
        let #(state, late) =
          fired_in_order(state:, timers:, seeing: [ally], at: 11_000)
        assert told(effects: late) == []
          as "and the cancelled end timers, late, tell nothing"
        #(state, list.append(removal, late))
      },
      finishes: False,
      removes_node: True,
    ),
    Path(
      why: "a push off by the stack rule while the node is live (a second press of the same spell, stack group 387 with a cap of 1) ends the first cast's changes before the second cast's start, writes the 0x811, and the first cast's end timers tell nothing more",
      spell: support.armor_spell(rows: support.armor_rows()),
      caster: seen,
      run: fn(state, first) {
        let timers = player_end_timers(state:)
        let #(state, pressed, went) =
          pressed_and_gone(
            spell: support.armor_spell(rows: support.armor_rows()),
            state:,
            at_press: seen,
            at_go: seen,
            rolls: [],
            at: 1100,
          )
        let second = support.pressed_id(effects: pressed)
        assert first != second as "the second press is a cast of its own"
        assert told(effects: went)
          == list.flatten([
            ends_of(cast_id: first),
            [
              pool_starts(cast_id: second, sight: held_changes.KeptWhenUnseen),
              armor_starts(cast_id: second, sight: held_changes.KeptWhenUnseen),
            ],
          ])
          as "the first cast's ends come before the second cast's starts"
        assert list.length(player_end_timers(state:)) == 2
          as "only the second cast's two end timers remain"
        let #(state, late) =
          fired_in_order(state:, timers:, seeing: [ally], at: 11_000)
        assert told(effects: late) == []
          as "the first cast's cancelled end timers, late, tell nothing"
        // The second cast still holds its changes, and the caster's leaving ends them.
        let #(state, left) = cast_tick.left(cast: state)
        assert told(effects: left) == ends_of(cast_id: second)
          as "the second cast's changes end with the caster's leaving"
        // Only the first cast's ends are returned: the second's starts and ends are checked above.
        #(
          state,
          list.filter(list.append(went, late), fn(effect) {
            case effect {
              cast_state.OtherPlayerChangeStarts(..) -> False
              _ -> True
            }
          }),
        )
      },
      finishes: False,
      removes_node: True,
    ),
    Path(
      why: "a persistence that stops holding while the cast lingers for its node on the ally ends both and writes the cast's 0x7fe",
      spell: armor_in_combat(
        spell: support.armor_spell(rows: support.armor_rows()),
      ),
      caster: fighting,
      run: fn(state, _) {
        cast.persisted(
          cast: state,
          caster: cast_state.Caster(..fighting, in_combat: False),
          now: support.at(ms: 1100),
        )
      },
      finishes: True,
      removes_node: False,
    ),
    Path(
      why: "a persistence that stops holding while the cast is live, with a go still to come, ends both and writes the cast's 0x7fe",
      spell: armor_in_combat(
        spell: Spell(
          ..support.armor_spell(rows: support.armor_rows()),
          phase_delays_ms: [
            0,
            1000,
          ],
        ),
      ),
      caster: fighting,
      run: fn(state, _) {
        cast.persisted(
          cast: state,
          caster: cast_state.Caster(..fighting, in_combat: False),
          now: support.at(ms: 1100),
        )
      },
      finishes: True,
      removes_node: False,
    ),
    Path(
      why: "a lingering cast that ends (its activation stopped) ends both and writes the cast's 0x7fe",
      spell: support.armor_spell(rows: support.armor_rows()),
      caster: seen,
      run: fn(state, id) { cast.activation_stopped(cast: state, cast_id: id) },
      finishes: True,
      removes_node: False,
    ),
  ]
  list.each(paths, fn(path) {
    let #(state, pressed, went) =
      pressed_and_gone(
        spell: path.spell,
        state: cast_state.new(),
        at_press: path.caster,
        at_go: path.caster,
        rolls: [],
        at: 1000,
      )
    let id = support.pressed_id(effects: pressed)
    let #(state, effects) = path.run(state, id)
    assert told(effects:) == ends_of(cast_id: id) as path.why
    assert list.filter(support.finished_ids(support.writes(effects:)), fn(done) {
        done == id
      })
      == case path.finishes {
        True -> [id]
        False -> []
      }
      as { path.why <> ": the cast's 0x7fe" }
    assert !path.removes_node
      || list.contains(
        support.removed_targets(support.writes(effects:)),
        #(id, [ally]),
      )
      as { path.why <> ": the 0x811 of the ally" }
    assert told(effects: cast_tick.left(cast: state).1) == []
      as {
        path.why <> ": and the caster's leaving afterwards tells nothing more"
      }
    assert went != [] as "the go happened"
  })
  // The caster leaving writes nothing and leaves no timer waiting.
  let #(state, _, _) =
    pressed_and_gone(
      spell: support.armor_spell(rows: support.armor_rows()),
      state: cast_state.new(),
      at_press: seen,
      at_go: seen,
      rolls: [],
      at: 1000,
    )
  let #(state, left) = cast_tick.left(cast: state)
  assert support.writes(effects: left) == []
    as "the caster's leaving writes no frame"
  assert cast_state.timers_in_order(cast: state) == []
    as "and cancels every timer, the end timers included"
}

pub fn a_re_press_of_the_same_caster_before_the_kept_buff_ends_replaces_the_held_change_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = support.armor_spell(rows: support.armor_rows())
  let seen = esper_seeing(players: [ally])
  let kept = held_changes.KeptWhenUnseen
  let #(state, pressed, _) =
    pressed_and_gone(
      spell:,
      state: cast_state.new(),
      at_press: seen,
      at_go: seen,
      rolls: [],
      at: 1000,
    )
  let first = support.pressed_id(effects: pressed)
  let first_timers = player_end_timers(state:)
  // The ally leaves the caster's sight: the 0x100 changes stay, the cast's node on it is gone.
  let #(state, removal) =
    cast_proc.unit_removed(cast: state, unit_id: ally, now_ms: 1100)
  assert told(effects: removal) == []
    as "the changes of a spell that outlives its caster's sight stay"
  // It comes back and the caster presses the same spell at it again, inside the 10 s.
  let #(state, pressed, went) =
    pressed_and_gone(
      spell:,
      state:,
      at_press: seen,
      at_go: seen,
      rolls: [],
      at: 3000,
    )
  let second = support.pressed_id(effects: pressed)
  assert first != second as "the second press is a cast of its own"
  assert told(effects: went)
    == list.flatten([
      ends_of(cast_id: first),
      [
        pool_starts(cast_id: second, sight: kept),
        armor_starts(cast_id: second, sight: kept),
      ],
    ])
    as "the kept changes of the first cast end before the second cast's start: the stack group 387 holds one cast per caster on a unit, so the ally holds one pool and one modifier, not two"
  let #(_, late) =
    fired_in_order(state:, timers: first_timers, seeing: [ally], at: 11_000)
  assert told(effects: late) == []
    as "the first cast's end timers were cancelled with its changes, so they tell nothing at the go plus 10 000"
}

// ---- a Proxy aimed at the primary target ----

/// A client spell of the fixture as the planted base 3 ability, which the bag holds at
/// `bag_of_base_3`.
fn as_base_3(spell4_id spell4_id: Int) -> Spell {
  Spell(
    ..spell_tables.client_spell(spell4_id:),
    spell4_base_id: Spell4BaseId(3),
  )
}

/// A Proxy row of a planted parent that starts `child` on the unit `target` aims at, after
/// `delay_ms`, behind `condition`.
fn proxy_of(
  child child: Spell,
  target target: spell_plan.ProxyTarget,
  delay_ms delay_ms: Int,
  condition condition: spell_plan.Condition,
) -> spell_plan.Proxy {
  spell_plan.Proxy(
    period: None,
    effect_id: Spell4EffectsId(90_002),
    delay_ms:,
    phase_flags: -1,
    condition:,
    tag: spend.always,
    target:,
    spell: child,
    gains: [],
  )
}

/// A Targeted beneficial parent (Phantasmal Armor's mechanics) of the planted base 3 holding
/// one Proxy.
fn parent_of(proxy proxy: spell_plan.Proxy) -> Spell {
  spell_plan.with_proxies(
    spell: Spell(
      ..support.child(spell4_id: 90_001, base: 3),
      targeting: spell_tables.client_spell(spell4_id: 32_820).targeting,
    ),
    proxies: [proxy],
  )
}

/// One press of a parent that holds a Proxy aimed at the primary target or the caster:
/// the unit pressed at, whom the caster sees at the go and later, the rolls of the go, the
/// child's Spell4 and each start of it as the time and the primary target it names.
type Child {
  Child(
    why: String,
    parent: Spell,
    target: Int,
    sees_at_go: List(Int),
    sees_later: List(Int),
    rolls: List(Int),
    child: Int,
    starts: List(#(Int, Int)),
    debug: List(String),
  )
}

/// The time and primary target of each 0x7ff of the Spell4 the effects write.
fn starts_of(
  effects effects: List(Effect),
  spell4_id spell4_id: Int,
  at ms: Int,
) -> List(#(Int, Int)) {
  list.filter_map(support.started_in(effects:), fn(start) {
    case start.spell4_id == spell4_id {
      True -> Ok(#(ms, start.primary_target_unit_id))
      False -> Error(Nil)
    }
  })
}

/// A press of the parent at `target` in the caster's sight of `sees_at_go` and what every
/// timer then does for a caster who sees `sees_later`: the state, the press's effects, the
/// go's and each timer step's time and effects.
fn pressed_and_run(
  child row: Child,
) -> #(State, List(Effect), List(Effect), List(#(Int, List(Effect)))) {
  let #(state, pressed, went) =
    pressed_at_and_gone_in(
      plans: plans_of(spell: row.parent),
      bag: bag_of_base_3,
      target: row.target,
      state: cast_state.new(),
      at_press: esper_seeing(players: [ally]),
      at_go: esper_seeing(players: row.sees_at_go),
      rolls: row.rolls,
      at: 1000,
    )
  let #(state, steps) =
    support.run_timers_each(
      caster: esper_seeing(players: row.sees_later),
      state:,
      effects: list.append(pressed, went),
      from_ms: 1000,
      struck_of: fn(_) { [] },
    )
  #(state, pressed, went, steps)
}

pub fn a_proxy_aimed_at_the_primary_target_starts_its_child_on_the_player_the_press_named_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects 83947 (Spell4 32823, Phantasmal Armor tier 1) is a Proxy aimed at the
  // primary target (targetFlags 2) that starts Spell4 76766; 130872 (Spell4 54904, Mind Over
  // Body tier 9, castTime 1250) is one with a delay of 25 ms that starts 54912 (`table_rows
  // -- Spell4Effects 83947 130872`). Mind Over Body's heal row 130870 is aimed at the ally
  // and lands nothing here, which its debug line says (the healed player's receipt is
  // another step). The client starts no Proxy (`Spell4Effects.effectType.26`): the server
  // starts a Proxy aimed at the primary target on the player a bag press named
  // (`press.at_a_unit`) and, for a press at oneself, a creature or a cast no bag press made,
  // on the caster.
  let armor = as_base_3(spell4_id: 32_823)
  let mind_over_body = as_base_3(spell4_id: 54_904)
  let plain = support.child(spell4_id: 90_003, base: 4)
  let on_the_target = fn(condition) {
    parent_of(proxy: proxy_of(
      child: plain,
      target: spell_plan.OnPrimaryTarget,
      delay_ms: 0,
      condition:,
    ))
  }
  let rows = [
    Child(
      why: "a bag press at the ally in sight starts Phantasmal Armor's Proxy child (83947 to 76766) on the ally",
      parent: armor,
      target: ally,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      child: 76_766,
      starts: [#(1000, ally)],
      debug: [],
    ),
    Child(
      why: "a press at oneself starts the child once, on the caster",
      parent: armor,
      target: 7,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      child: 76_766,
      starts: [#(1000, 7)],
      debug: [],
    ),
    Child(
      why: "a Proxy aimed at the caster in a press at the ally starts its child on the caster",
      parent: parent_of(proxy: proxy_of(
        child: plain,
        target: spell_plan.OnCaster,
        delay_ms: 0,
        condition: Always,
      )),
      target: ally,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      child: 90_003,
      starts: [#(1000, 7)],
      debug: [],
    ),
    Child(
      why: "a Proxy with a delay of 25 ms starts nothing at the go (castTime 1250, so at 2250) and its child, 25 ms later, on the ally (130872 to 54912)",
      parent: mind_over_body,
      target: ally,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      child: 54_912,
      starts: [#(2275, ally)],
      debug: ["130870"],
    ),
    Child(
      why: "the ally out of the caster's sight when the delay ends: no child starts and a debug line says so, as a press at an unseen player is refused 91",
      parent: mind_over_body,
      target: ally,
      sees_at_go: [ally],
      sees_later: [],
      rolls: [],
      child: 54_912,
      starts: [],
      debug: ["130870", "54912", "not in the caster's sight"],
    ),
    Child(
      why: "the ally out of the caster's sight at the go: no child starts either",
      parent: armor,
      target: ally,
      sees_at_go: [],
      sees_later: [],
      rolls: [],
      child: 76_766,
      starts: [],
      debug: ["76766", "not in the caster's sight"],
    ),
    Child(
      why: "a Proxy aimed at the primary target whose caster gate fails (4585: at most 50, roll 80) starts no child",
      parent: on_the_target(spell_plan.GatedOnCaster(gates: [chance_gate()])),
      target: ally,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [80],
      child: 90_003,
      starts: [],
      debug: [],
    ),
    Child(
      why: "the same gate with a roll of 30 passes: the child starts on the ally",
      parent: on_the_target(spell_plan.GatedOnCaster(gates: [chance_gate()])),
      target: ally,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [30],
      child: 90_003,
      starts: [#(1000, ally)],
      debug: [],
    ),
  ]
  list.each(rows, fn(row) {
    let #(_, pressed, went, steps) = pressed_and_run(child: row)
    let started =
      list.flatten([
        starts_of(effects: went, spell4_id: row.child, at: 1000),
        list.flat_map(steps, fn(step) {
          starts_of(effects: step.1, spell4_id: row.child, at: step.0)
        }),
      ])
    assert started == row.starts as row.why
    let lines =
      list.flatten([
        support.debug_lines(effects: went),
        list.flat_map(steps, fn(step) { support.debug_lines(effects: step.1) }),
      ])
    assert list.all(row.debug, fn(words) {
      list.any(lines, string.contains(_, words))
    })
      as { row.why <> ": the debug lines say " <> string.join(row.debug, ", ") }
    assert row.debug != [] || lines == []
      as {
        row.why
        <> ": and none is written otherwise, not "
        <> string.join(lines, "; ")
      }
    assert support.refusal_results(effects: pressed) == []
      as { row.why <> ": the press is accepted" }
  })
  // The first row's start in full: the ally's connection reads the child's 0x7ff with the
  // pressed spell as its parent and root, and no threshold is touched.
  let #(state, pressed, went, _) =
    pressed_and_run(
      child: Child(
        why: "",
        parent: armor,
        target: ally,
        sees_at_go: [ally],
        sees_later: [ally],
        rolls: [],
        child: 76_766,
        starts: [],
        debug: [],
      ),
    )
  let effects = list.append(pressed, went)
  let assert [child_start] =
    list.filter(support.started_in(effects:), fn(start) {
      start.spell4_id == 76_766
    })
    as "the child starts once"
  assert child_start.caster_unit_id == 7
    && child_start.primary_target_unit_id == ally
    && child_start.parent_spell4_id == 32_823
    && child_start.root_spell4_id == 32_823
    as "opcode.0x7ff: the child names the ally as its primary target, the Esper as its caster and the pressed spell as its parent and root"
  assert list.contains(support.started_told_to(effects:, connection: 2), #(
    76_766,
    32_823,
    32_823,
  ))
    as "the ally's connection reads the child's 0x7ff"
  assert state.thresholds == dict.new() as "a child touches no threshold"
}

/// One child a parent started by its go, and what its rows do: where the press was
/// (`target`), the child's Spell4, the effect ids its 0x7f4 lists on the ally and on the
/// caster, the changes it tells the ally (as the row it is for), the changes it starts on the
/// caster and how the changes it tells end when the caster stops seeing the ally.
type Landing {
  Landing(
    why: String,
    parent: Spell,
    target: Int,
    child: Int,
    listed_on_ally: List(Int),
    told: List(#(Int, held_changes.Change, held_changes.Sight)),
    on_the_caster: List(#(Int, cast_state.CasterChange)),
    parent_told: Int,
  )
}

pub fn a_row_of_a_child_started_on_a_player_lands_on_that_player_and_none_of_it_on_the_caster_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects 199192 (Spell4 76766) is Interrupt Armor: effectType 52, dataBits00 1,
  // durationTime 5000, targetFlags 2. 216950 (Spell4 82438) is a type 11 row behind the
  // caster condition Prerequisite 38543, which nothing the Esper holds meets (no table starts
  // Spell4 82431), and 203809 (Spell4 77864) a type 29 row behind the target condition 36645
  // (the unit is not the target of a live cast of Spell4 54806) (`table_rows -- Spell4Effects
  // 199192 216950 203809 -- Prerequisite 38543 36645`). The child's propertyFlags are 0 (76766,
  // 82438), so its changes end when the caster stops seeing the ally.
  let armor = as_base_3(spell4_id: 32_823)
  let started_by = fn(child) {
    parent_of(proxy: proxy_of(
      child:,
      target: spell_plan.OnPrimaryTarget,
      delay_ms: 0,
      condition: Always,
    ))
  }
  let interrupt_armor = support.raising_interrupt_armor_threshold(points: 1.0)
  let rows = [
    Landing(
      why: "the Interrupt Armor row of 76766 started on the ally is told to the ally and listed on it, ending with the caster's sight, and starts nothing on the caster",
      parent: armor,
      target: ally,
      child: 76_766,
      listed_on_ally: [199_192],
      told: [
        #(
          199_192,
          held_changes.Property(modifier: interrupt_armor),
          held_changes.EndsWhenUnseen,
        ),
      ],
      on_the_caster: [],
      parent_told: 1,
    ),
    Landing(
      why: "the same child started on the caster (a press at oneself) is the caster's own change and tells nobody",
      parent: armor,
      target: 7,
      child: 76_766,
      listed_on_ally: [],
      told: [],
      on_the_caster: [
        #(
          199_192,
          cast_state.HeldChange(held_changes.Property(modifier: interrupt_armor)),
        ),
      ],
      parent_told: 0,
    ),
    Landing(
      why: "82438 started on the ally lands nothing: its row's caster condition fails",
      parent: started_by(spell_tables.client_spell(spell4_id: 82_438)),
      target: ally,
      child: 82_438,
      listed_on_ally: [],
      told: [],
      on_the_caster: [],
      parent_told: 0,
    ),
    Landing(
      why: "77864 started on the ally lands nothing: the ally is the target of the live cast of 54806, which its rows' target condition refuses",
      parent: started_by(spell_tables.client_spell(spell4_id: 77_864)),
      target: ally,
      child: 77_864,
      listed_on_ally: [],
      told: [],
      on_the_caster: [],
      parent_told: 0,
    ),
  ]
  list.each(rows, fn(row) {
    let #(_, pressed, went) =
      pressed_at_and_gone_in(
        plans: plans_of(spell: row.parent),
        bag: bag_of_base_3,
        target: row.target,
        state: cast_state.new(),
        at_press: esper_seeing(players: [ally]),
        at_go: esper_seeing(players: [ally]),
        rolls: [],
        at: 1000,
      )
    let parent_id = support.pressed_id(effects: pressed)
    let child_id = support.started_cast_id(effects: went, spell4_id: row.child)
    let own = fn(source: Source) { source.cast_id == child_id }
    assert list.filter_map(told(effects: went), fn(change) {
        case change {
          cast_state.OtherPlayerChangeStarts(address:, source:, change:, sight:) ->
            case own(source) {
              True ->
                Ok(#(address.unit_id, source.effect_id.value, change, sight))
              False -> Error(Nil)
            }
          _ -> Error(Nil)
        }
      })
      == list.map(row.told, fn(change) { #(ally, change.0, change.1, change.2) })
      as { row.why <> ": the changes told to the ally" }
    assert list.filter_map(support.goes_in(effects: went), fn(go) {
        case go.cast_id == child_id {
          True -> Ok(go.targets)
          False -> Error(Nil)
        }
      })
      |> list.flatten
      |> list.filter(fn(unit) { unit.unit_id == ally })
      |> list.flat_map(fn(unit) {
        list.map(unit.effects, fn(effect) { effect.spell4_effects_id })
      })
      == row.listed_on_ally
      as { row.why <> ": the child's 0x7f4 lists these effects on the ally" }
    assert list.filter_map(
        support.caster_change_starts(effects: went),
        fn(start) {
          case own(start.0) {
            True -> Ok(#(start.0.effect_id.value, start.1))
            False -> Error(Nil)
          }
        },
      )
      == row.on_the_caster
      as { row.why <> ": the changes the child starts on the caster" }
    assert list.filter(told(effects: went), fn(change) {
        case change {
          cast_state.OtherPlayerChangeStarts(source:, ..) ->
            source.cast_id == parent_id
          _ -> False
        }
      })
      |> list.length
      == row.parent_told
      as {
        row.why
        <> ": the parent's own rows are told once (the absorb 62024), as in Part 7b, and the child adds its own"
      }
  })
}

/// The plans of the armor (Phantasmal Armor tier 1 as the base 3 ability) and of a planted
/// spell of base 1 pressed at the same player that takes the nodes of the cast of the Spell4
/// `removed` off it with a type 80 row (SpellForceRemove, a selector of that Spell4, a count
/// of 1, aimed at the primary target).
fn armor_and_the_removal_of(removed removed: Int) -> Plans {
  let armor = as_base_3(spell4_id: 32_823)
  support.with_spells(plans: plans_of(spell: armor), spells: [
    support.with_effects(
      spell: Spell(
        ..support.child(spell4_id: 301, base: 1),
        targeting: armor.targeting,
      ),
      kinds: [
        spell_plan.RemoveEffect(spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(196_521),
          phase_flags: -1,
          aim: spell_plan.AimsAtPrimaryTarget,
          selector: lasting.Spell(Spell4Id(removed)),
          count: 1,
          condition: Always,
          tag: spend.always,
        )),
      ],
    ),
  ])
}

/// The ends of the changes the child cast `child_id` (Interrupt Armor, 5000 ms) and the
/// parent cast `parent_id` (the absorb, 10 000 ms) hold on the ally, in the order told.
fn told_ends(
  effects effects: List(Effect),
  child_id child_id: Int,
  parent_id parent_id: Int,
) -> List(String) {
  list.filter_map(told(effects:), fn(change) {
    case change {
      cast_state.OtherPlayerChangeEnds(source:, ..)
        if source.cast_id == child_id
      -> Ok("child")
      cast_state.OtherPlayerChangeEnds(source:, ..)
        if source.cast_id == parent_id
      -> Ok("parent")
      _ -> Error(Nil)
    }
  })
}

/// How one path ends the child's armor and the parent's absorb on the ally: what it does to
/// the state the go left (given the child's cast id and the parent's), and the ends it tells
/// at once and each end the timers still left tell afterwards.
type ChildPath {
  ChildPath(
    why: String,
    run: fn(State, Int, Int) -> #(State, List(Effect)),
    at_once: List(String),
    later: List(#(Int, String)),
  )
}

pub fn the_end_of_the_interrupt_armor_a_child_told_to_the_ally_is_told_once_by_each_path_that_ends_its_node_test() -> Nil {
  use <- owned_test.run(10_000)
  let seen = esper_seeing(players: [ally])
  // The press of the removal waits out the armor's global cooldown (Spell4 32823: 1250 ms).
  // The child's row 199192 lasts 5000 ms and the parent's absorb 62024 lasts 10 000 ms
  // (`table_rows -- Spell4Effects 199192 62024`), each a cast of its own with its own node on
  // the ally, so each ends alone and a removal names one cast.
  let removal_at_2500 = fn(removed) {
    fn(state, _, _) {
      let #(state, _, removal) =
        pressed_and_gone_in(
          plans: armor_and_the_removal_of(removed:),
          bag: bag_of_base_1,
          state:,
          at_press: seen,
          at_go: seen,
          rolls: [],
          at: 2500,
        )
      #(state, removal)
    }
  }
  let paths = [
    ChildPath(
      why: "time: the child's end is told at the go plus 5000 and the parent's, still held then, at the go plus 10 000",
      run: fn(state, _, _) { #(state, []) },
      at_once: [],
      later: [#(6000, "child"), #(11_000, "parent")],
    ),
    ChildPath(
      why: "a type 80 removal naming the child's node on the ally ends the armor once and the parent's absorb stays held",
      run: removal_at_2500(76_766),
      at_once: ["child"],
      later: [#(11_000, "parent")],
    ),
    ChildPath(
      why: "a type 80 removal naming the parent's node on the ally ends the absorb and the child's armor stays held",
      run: removal_at_2500(32_823),
      at_once: ["parent"],
      later: [#(6000, "child")],
    ),
    ChildPath(
      why: "the caster's death ends both, once each",
      run: fn(state, _, _) {
        cast.died(
          cast: state,
          caster: support.dead_caster(),
          now: support.at(ms: 1100),
        )
      },
      at_once: ["parent", "child"],
      later: [],
    ),
    ChildPath(
      why: "the caster leaving ends both, once each",
      run: fn(state, _, _) { cast_tick.left(cast: state) },
      at_once: ["parent", "child"],
      later: [],
    ),
  ]
  list.each(paths, fn(path) {
    let #(state, pressed, went) =
      pressed_and_gone(
        spell: as_base_3(spell4_id: 32_823),
        state: cast_state.new(),
        at_press: seen,
        at_go: seen,
        rolls: [],
        at: 1000,
      )
    let parent_id = support.pressed_id(effects: pressed)
    let child_id = support.started_cast_id(effects: went, spell4_id: 76_766)
    assert told_ends(effects: list.append(pressed, went), child_id:, parent_id:)
      == []
      as { path.why <> ": nothing is told ended by the go" }
    let #(state, effects) = path.run(state, child_id, parent_id)
    assert list.sort(told_ends(effects:, child_id:, parent_id:), string.compare)
      == list.sort(path.at_once, string.compare)
      as { path.why <> ": the ends told at once" }
    // The timers left, each fired at its own time, tell the later ends and nothing more.
    let #(_, fired) =
      support.run_timers_each(
        caster: seen,
        state:,
        effects: list.append(pressed, went),
        from_ms: 1000,
        struck_of: fn(_) { [] },
      )
    assert list.filter_map(fired, fn(step) {
        case told_ends(effects: step.1, child_id:, parent_id:) {
          [] -> Error(Nil)
          ends -> Ok(#(step.0, string.join(ends, ",")))
        }
      })
      == path.later
      as { path.why <> ": the ends the timers tell afterwards" }
  })
}

pub fn at_a_stack_cap_of_two_a_kept_cast_and_a_cast_with_a_node_count_together_test() -> Nil {
  use <- owned_test.run(10_000)
  // The stack rule is the server's (`lasting.stack_pushed_off`): the casts of one stack
  // group on a unit beyond the cap less one are pushed off, oldest first. A change kept after
  // the caster lost sight of the player is held by no node, and a cast with a node holds one:
  // both are casts on the player, so with a cap of 2 the third press pushes the oldest off,
  // the kept one, though each kind alone is under the cap.
  let spell =
    Spell(
      ..support.armor_spell(rows: support.armor_rows()),
      stack: lasting.Stack(group_id: 387, cap: 2),
    )
  let seen = esper_seeing(players: [ally])
  let #(state, pressed, _) =
    pressed_and_gone(
      spell:,
      state: cast_state.new(),
      at_press: seen,
      at_go: seen,
      rolls: [],
      at: 1000,
    )
  let first = support.pressed_id(effects: pressed)
  // The ally leaves the caster's sight: the first cast's changes stay, its node is gone.
  let #(state, removal) =
    cast_proc.unit_removed(cast: state, unit_id: ally, now_ms: 1100)
  assert told(effects: removal) == []
    as "the changes of a spell that outlives its caster's sight stay"
  let #(state, pressed, went) =
    pressed_and_gone(
      spell:,
      state:,
      at_press: seen,
      at_go: seen,
      rolls: [],
      at: 3000,
    )
  let second = support.pressed_id(effects: pressed)
  assert list.filter(told(effects: went), fn(change) {
      case change {
        cast_state.OtherPlayerChangeEnds(..) -> True
        _ -> False
      }
    })
    == []
    as "two casts on the ally are within the cap of 2: the second press pushes nothing off"
  let #(_, pressed, went) =
    pressed_and_gone(
      spell:,
      state:,
      at_press: seen,
      at_go: seen,
      rolls: [],
      at: 5000,
    )
  let third = support.pressed_id(effects: pressed)
  assert first != second && second != third as "each press is a cast of its own"
  assert told(effects: went)
    == list.flatten([
      ends_of(cast_id: first),
      [
        pool_starts(cast_id: third, sight: held_changes.KeptWhenUnseen),
        armor_starts(cast_id: third, sight: held_changes.KeptWhenUnseen),
      ],
    ])
    as "the third press pushes off the oldest cast on the ally, the kept one, and only that one: the second keeps its node and its changes"
}
