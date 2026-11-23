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
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import map_support
import owned_test
import prerequisite_support

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

/// The Novice Esper, who sees these players.
fn esper_seeing(players players: List(Int)) -> Caster {
  cast_state.Caster(
    ..support.caster(),
    stats: attacker_support.novice(),
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

/// A 0x9a at the ally of the ability in bag slot `bag` of `plans`, taken by the rule.
fn pressed_at_the_ally_in(
  plans plans: Plans,
  bag bag: Int,
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
        target: ally,
        press: 1,
      ),
      caster:,
      plans:,
      target_of: picture,
      now: support.at(ms:),
    )
    as "the press at the ally in sight is taken"
  taken
}

/// The press and its go of the ability in bag slot `bag` of `plans`, answered by a round
/// that struck nobody (the ally is no creature and answers nothing), for the caster at the
/// go: the state after, the press's effects and the go's, with the rolls the go's type 37
/// conditions take.
fn pressed_and_gone_in(
  plans plans: Plans,
  bag bag: Int,
  state state: State,
  at_press at_press: Caster,
  at_go at_go: Caster,
  rolls rolls: List(Int),
  at ms: Int,
) -> #(State, List(Effect), List(Effect)) {
  let #(state, pressed) =
    pressed_at_the_ally_in(plans:, bag:, state:, caster: at_press, at: ms)
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
