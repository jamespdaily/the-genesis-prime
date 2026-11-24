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
import client_tables
import genesis_prime/game/activate
import genesis_prime/game/cast
import genesis_prime/game/cast/gate
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/heal_split
import genesis_prime/game/held_changes
import genesis_prime/game/lasting
import genesis_prime/game/player_address.{type PlayerAddress, PlayerAddress}
import genesis_prime/game/player_state.{PlayerState}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Plans, type Spell, Always, Spell}
import genesis_prime/game/spend
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_casts
import genesis_prime/game/unit_properties.{type Source}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_started
import genesis_prime/step.{type ConnectionId, type TimerId, ConnectionId}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
import map_support
import owned_test
import player_state_support
import prerequisite_support
import spell_tables
import unitest

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

/// The Esper as `esper_seeing` has it, in a group with each of the players, so that a spell
/// that needs its target in the caster's group (`press_target.group_refusal`: a child a Proxy
/// starts on an ally has the bit) is not refused when it is pressed at one.
fn esper_grouped_with(players players: List(Int)) -> Caster {
  let caster = esper_seeing(players:)
  cast_state.Caster(
    ..caster,
    group_id: 1,
    other_players: dict.map_values(caster.other_players, fn(_, player) {
      PlayerState(..player, group_id: 1)
    }),
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

/// What a step tells other players about the changes of the cast `cast_id` and its go, in
/// order, as `starts ROW`, `ends ROW` and `went`.
fn trail(effects effects: List(Effect), cast_id cast_id: Int) -> List(String) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.OtherPlayerChangeStarts(source:, ..)
        if source.cast_id == cast_id
      -> Ok("starts " <> int.to_string(source.effect_id.value))
      cast_state.OtherPlayerChangeEnds(source:, ..)
        if source.cast_id == cast_id
      -> Ok("ends " <> int.to_string(source.effect_id.value))
      cast_state.OtherPlayerCastWent(cast_id: went_id, ..)
        if went_id == cast_id
      -> Ok("went")
      _ -> Error(Nil)
    }
  })
}

/// The tells of a cast's go to the players the effects hold, in order.
fn wents(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      cast_state.OtherPlayerCastWent(..) -> True
      _ -> False
    }
  })
}

fn source_of(cast_id cast_id: Int, effect_id effect_id: Int) -> Source {
  support.source_of(cast_id:, effect_id:)
}

/// The effect of a row of Phantasmal Armor tier 9 as the go at `go_ms` tells it: 10 000 ms
/// from the go, no delay (rows 130470 and 130474, `table_rows -- Spell4Effects 130470
/// 130474`).
fn held_effect_of_armor(
  effect_id effect_id: Int,
  go_ms go_ms: Int,
) -> unit_casts.HeldEffect {
  unit_casts.HeldEffect(
    effect_id: Spell4EffectsId(effect_id),
    starts_ms: go_ms,
    ends: unit_casts.EndsAt(ms: go_ms + 10_000),
  )
}

/// The absorb pool of row 130470 told for the cast at the go `go_ms`: 139 of every damage
/// type, for the spell Phantasmal Armor tier 9, Spell4 54806.
fn pool_starts(
  cast_id cast_id: Int,
  sight sight: held_changes.Sight,
  go_ms go_ms: Int,
) -> Effect {
  cast_state.OtherPlayerChangeStarts(
    address: address(),
    source: source_of(cast_id:, effect_id: absorb_id),
    change: held_changes.Absorb(amount: 139, mask: 7),
    sight:,
    spell4_id: Spell4Id(54_806),
    effect: held_effect_of_armor(effect_id: absorb_id, go_ms:),
  )
}

/// The modifier of row 130474 told for the cast at the go `go_ms`: property 161 by 0.86f.
fn armor_starts(
  cast_id cast_id: Int,
  sight sight: held_changes.Sight,
  go_ms go_ms: Int,
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
    spell4_id: Spell4Id(54_806),
    effect: held_effect_of_armor(effect_id: modifier_id, go_ms:),
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
      pool_starts(cast_id: id, sight: kept, go_ms: 1000),
      armor_starts(cast_id: id, sight: kept, go_ms: 1000),
    ]
  }
  let modifier_only = fn(id) {
    [armor_starts(cast_id: id, sight: kept, go_ms: 1000)]
  }
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
          pool_starts(cast_id: id, sight: ends_with_sight, go_ms: 1000),
          armor_starts(cast_id: id, sight: ends_with_sight, go_ms: 1000),
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
      #(2000, [armor_starts(cast_id: id, sight: kept, go_ms: 2000)]),
      #(12_000, [
        cast_state.OtherPlayerChangeEnds(
          address: address(),
          source: source_of(cast_id: id, effect_id: modifier_id),
        ),
      ]),
    ]
    as "the second go tells the modifier again, and the one end is told 10 000 ms after it, none at the first go's end"
  // The tier a player presses names its own Spell4 in the tell: Phantasmal Armor tier 1,
  // Spell4 32823, tells its absorb 62024 (10 000 ms, no delay, `table_rows -- Spell4Effects
  // spellId=32823`) for that spell, from the go's time to the go plus 10 000.
  let tier_one = as_base_3(spell4_id: 32_823)
  let #(_, pressed, went) =
    pressed_and_gone_in(
      plans: plans_of(spell: tier_one),
      bag: bag_of_base_3,
      state: cast_state.new(),
      at_press: esper_seeing(players: [ally]),
      at_go: esper_seeing(players: [ally]),
      rolls: [],
      at: 1000,
    )
  let tier_one_id = support.pressed_id(effects: pressed)
  let assert [tier_one_told] =
    list.filter(told(effects: went), fn(change) {
      case change {
        cast_state.OtherPlayerChangeStarts(source:, ..) ->
          source.cast_id == tier_one_id
        _ -> False
      }
    })
    as "tier 1 tells its one absorb"
  let assert cast_state.OtherPlayerChangeStarts(
    source:,
    spell4_id:,
    effect:,
    ..,
  ) = tier_one_told
  assert source.effect_id == Spell4EffectsId(62_024)
  assert spell4_id == Spell4Id(32_823)
    as "the tell names the pressed tier's Spell4, not Phantasmal Armor tier 9's"
  assert effect
    == unit_casts.HeldEffect(
      effect_id: Spell4EffectsId(62_024),
      starts_ms: 1000,
      ends: unit_casts.EndsAt(ms: 11_000),
    )
    as "the effect starts at the go and ends 10 000 ms after it"
  // What the ledger of the ally lists from those tells is what the caster's own node on the
  // ally lists (`cast_state.views`): the same effects with the same delay and time left at
  // the go and later, so the caster's create and the ally's create cannot disagree.
  let #(state, pressed, went) =
    pressed_and_gone(
      spell: support.armor_spell(rows: support.armor_rows()),
      state: cast_state.new(),
      at_press: esper_seeing(players: [ally]),
      at_go: esper_seeing(players: [ally]),
      rolls: [],
      at: 1000,
    )
  let id = support.pressed_id(effects: pressed)
  let ledger = ledger_told(effects: went)
  let assert [from_ledger] =
    held_changes.cast_views(held: ledger, holder_unit_id: ally, now_ms: 1000)
    as "the ledger lists the one cast"
  let assert [from_caster] =
    list.filter(cast_state.views(cast: state, caster_unit_id: 7), fn(view) {
      view.cast_id == id
    })
    as "the caster lists the one cast"
  let on_ally =
    unit_casts.CastView(
      ..from_caster,
      targets: list.filter(from_caster.targets, fn(target) {
        target.unit_id == ally
      }),
    )
  assert from_ledger == on_ally
    as "the ledger's view of the cast is the caster's view of its node on the ally"
  list.each([1000, 4000, 10_999], fn(now_ms) {
    assert unit_casts.entry_of(view: from_ledger, now_ms:)
      == unit_casts.entry_of(view: on_ally, now_ms:)
      as "and so is the entry at every clock"
  })
  // The go's third tell: after the rows a cast lands on the player, one went for the cast and
  // the player, with the audience the caster told the cast's 0x7ff, so the ally can start the
  // cast for the viewers outside it. Phantasmal Armor tier 1 (Spell4 32823) lands its absorb
  // 62024 and tier 9 (Spell4 54806) its absorb 130470 and its modifier 130474 (`table_rows --
  // Spell4Effects spellId=32823 spellId=54806`); the committed rows hold no other tier with
  // two rows.
  let told_the_0x7ff = set.from_list([ConnectionId(2), ConnectionId(3)])
  let #(one_id, one_went) =
    pressed_with_audience_changes(
      spell: as_base_3(spell4_id: 32_823),
      joined: [],
      left: [],
    )
  assert trail(effects: one_went, cast_id: one_id) == ["starts 62024", "went"]
    as "tier 1: its one change is told and then one went, after it"
  assert wents_of(effects: one_went, cast_id: one_id)
    == [
      cast_state.OtherPlayerCastWent(
        address: address(),
        cast_id: one_id,
        audience: told_the_0x7ff,
      ),
    ]
    as "the went names the ally's address, the cast and the connections told the cast's 0x7ff"
  let #(nine_id, nine_went) =
    pressed_with_audience_changes(
      spell: support.armor_spell(rows: support.armor_rows()),
      joined: [],
      left: [],
    )
  assert trail(effects: nine_went, cast_id: nine_id)
    == ["starts 130470", "starts 130474", "went"]
    as "tier 9: both changes are told, then exactly one went, after the last: one for the cast, not one for each change"
  // A cast that shows its cast bar is the caster's current cast until its go, so a create of
  // the caster lists it and the connection that came into sight joins its audience.
  let #(moved_id, moved_went) =
    pressed_with_audience_changes(
      spell: Spell(
        ..as_base_3(spell4_id: 32_823),
        cast_time_ms: 1500,
        cast_bar: spell_plan.ShowsCastBar,
      ),
      joined: [ConnectionId(5)],
      left: [ConnectionId(3)],
    )
  assert wents_of(effects: moved_went, cast_id: moved_id)
    == [
      cast_state.OtherPlayerCastWent(
        address: address(),
        cast_id: moved_id,
        audience: set.from_list([ConnectionId(2), ConnectionId(5)]),
      ),
    ]
    as "the audience is the live cast's: a connection that joined by a create listing the cast is in it, one that left is not"
  let #(_, _, at_oneself) =
    pressed_at_and_gone_in(
      plans: plans_of(spell: as_base_3(spell4_id: 32_823)),
      bag: bag_of_base_3,
      target: 7,
      state: cast_state.new(),
      at_press: esper_seeing(players: [ally]),
      at_go: esper_seeing(players: [ally]),
      rolls: [],
      at: 1000,
    )
  assert wents(effects: at_oneself) == []
    as "a press at oneself lands its change on the caster, not on another player: no went"
  let #(_, _, out_of_sight) =
    pressed_and_gone(
      spell: as_base_3(spell4_id: 32_823),
      state: cast_state.new(),
      at_press: esper_seeing(players: [ally]),
      at_go: esper_seeing(players: []),
      rolls: [],
      at: 1000,
    )
  assert wents(effects: out_of_sight) == []
    as "an ally out of the caster's sight at the go is told no change and no went"
}

/// The press of `spell` at the ally and its go for a caster whose audience is the connections
/// 2 and 3, after the connections `joined` joined the audience by a create that listed the
/// cast and the connections `left` left it: the pressed cast's id and the go's effects.
fn pressed_with_audience_changes(
  spell spell: Spell,
  joined joined: List(ConnectionId),
  left left: List(ConnectionId),
) -> #(Int, List(Effect)) {
  let #(state, pressed) =
    pressed_at_in(
      plans: plans_of(spell:),
      bag: bag_of_base_3,
      target: ally,
      state: cast_state.new(),
      caster: esper_seeing(players: [ally]),
      at: 1000,
    )
  let state =
    list.fold(joined, state, fn(state, viewer) {
      cast_state.audience_joined(cast: state, viewer:, caster_unit_id: 7)
    })
  let state =
    list.fold(left, state, fn(state, viewer) {
      cast_state.audience_left(cast: state, viewer:)
    })
  let #(state, went) =
    support.answered_each(
      caster: esper_seeing(players: [ally]),
      state:,
      effects: pressed,
      at: 1000,
      struck_of: fn(_) { [] },
      rolls: [],
      poses: dict.new(),
    )
  // A spell with a cast time goes on a timer of its own, at the press plus the cast time.
  let on_time = case spell.cast_time_ms > 0 {
    True -> {
      let #(_, steps) =
        support.run_timers_each(
          caster: esper_seeing(players: [ally]),
          state:,
          effects: list.append(pressed, went),
          from_ms: 1000,
          struck_of: fn(_) { [] },
        )
      list.flat_map(steps, fn(step) {
        case step.0 <= 1000 + spell.cast_time_ms {
          True -> step.1
          False -> []
        }
      })
    }
    False -> []
  }
  #(support.pressed_id(effects: pressed), list.append(went, on_time))
}

/// The wents of the cast `cast_id` among the effects.
fn wents_of(
  effects effects: List(Effect),
  cast_id cast_id: Int,
) -> List(Effect) {
  list.filter(wents(effects:), fn(effect) {
    case effect {
      cast_state.OtherPlayerCastWent(cast_id: went_id, ..) -> went_id == cast_id
      _ -> False
    }
  })
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
              pool_starts(
                cast_id: second,
                sight: held_changes.KeptWhenUnseen,
                go_ms: 1100,
              ),
              armor_starts(
                cast_id: second,
                sight: held_changes.KeptWhenUnseen,
                go_ms: 1100,
              ),
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
  // The same paths for the allies a press did not name, found by the area of a spell shaped as
  // Barrier's child (`barrier_shaped`): the press is on the caster, the round hit two allies,
  // and each ally's change ends once by each path that ends its cast's node. A change of a spell
  // that holds propertyFlags 0x100 (Barrier's 0x2100) is kept when the ally leaves the caster's
  // sight and ends by its timer.
  let both_see = esper_seeing(players: [ally, second_ally])
  let kept = barrier_shaped(outlives_caster: True)
  let area_ends = fn(units) {
    fn(cast_id) {
      list.map(units, fn(unit_id) { barrier_change_ends(unit_id:, cast_id:) })
    }
  }
  let area_paths = [
    AreaPath(
      why: "time: each end timer fires at the go plus 5000 and tells its ally's end, in the round's order, and the node's end in the same millisecond tells nothing more but writes the 0x7fe",
      spell: kept,
      run: fn(state, _) {
        fired_in_order(
          state:,
          timers: list.append(
            player_end_timers(state:),
            nodes_end_timers(state:),
          ),
          seeing: [ally, second_ally],
          at: 6000,
        )
      },
      ends: area_ends([second_ally, ally]),
      finishes: True,
      removed: [],
      left_after: area_ends([]),
    ),
    AreaPath(
      why: "time, the node's end first: it ends both allies' changes, and the end timers, late, tell nothing more",
      spell: kept,
      run: fn(state, _) {
        fired_in_order(
          state:,
          timers: list.append(
            nodes_end_timers(state:),
            player_end_timers(state:),
          ),
          seeing: [ally, second_ally],
          at: 6000,
        )
      },
      ends: area_ends([second_ally, ally]),
      finishes: True,
      removed: [],
      left_after: area_ends([]),
    ),
    AreaPath(
      why: "the caster's death ends both allies' changes and writes the 0x7fe",
      spell: kept,
      run: fn(state, _) {
        cast.died(
          cast: state,
          caster: support.dead_caster(),
          now: support.at(ms: 1100),
        )
      },
      ends: area_ends([second_ally, ally]),
      finishes: True,
      removed: [],
      left_after: area_ends([]),
    ),
    AreaPath(
      why: "the caster leaving ends both allies' changes and writes nothing",
      spell: kept,
      run: fn(state, _) { cast_tick.left(cast: state) },
      ends: area_ends([second_ally, ally]),
      finishes: False,
      removed: [],
      left_after: area_ends([]),
    ),
    AreaPath(
      why: "the ally leaving the caster's sight, for a spell that does not hold 0x100, ends its change alone; the other ally's change stays and ends with the caster's leaving",
      spell: barrier_shaped(outlives_caster: False),
      run: fn(state, _) {
        cast_proc.unit_removed(cast: state, unit_id: ally, now_ms: 1100)
      },
      ends: area_ends([ally]),
      finishes: False,
      removed: [],
      left_after: area_ends([second_ally]),
    ),
    AreaPath(
      why: "the ally leaving the caster's sight, for a spell that holds 0x100 (Barrier's 0x2100), ends nothing then; each end timer tells its ally's end at the go plus 5000",
      spell: kept,
      run: fn(state, _) {
        let #(state, removal) =
          cast_proc.unit_removed(cast: state, unit_id: ally, now_ms: 1100)
        assert told(effects: removal) == []
          as "a change of a spell that outlives its caster's sight is kept at the removal"
        let #(state, ended) =
          fired_in_order(
            state:,
            timers: player_end_timers(state:),
            seeing: [],
            at: 6000,
          )
        #(state, list.append(removal, ended))
      },
      ends: area_ends([second_ally, ally]),
      finishes: False,
      removed: [],
      left_after: area_ends([]),
    ),
    AreaPath(
      why: "a type 80 removal of the cast's node on one ally ends that ally's change, writes the 0x811 that takes the node off it and cancels its end timer, so the timer tells nothing at the go plus 5000; the other ally's change stays",
      spell: kept,
      run: fn(state, _) {
        let timers = player_end_timers(state:)
        let #(state, _, removal) =
          pressed_and_gone_in(
            plans: armor_and_its_removal(spell: kept),
            bag: bag_of_base_1,
            state:,
            at_press: both_see,
            at_go: both_see,
            rolls: [],
            at: 1100,
          )
        assert list.length(player_end_timers(state:)) == 1
          as "the removal cancels the removed ally's end timer"
        let #(state, late) =
          fired_in_order(
            state:,
            timers: list.drop(timers, 1),
            seeing: [ally, second_ally],
            at: 6000,
          )
        assert told(effects: late) == []
          as "and the cancelled end timer, late, tells nothing"
        #(state, list.append(removal, late))
      },
      ends: area_ends([ally]),
      finishes: False,
      removed: [ally],
      left_after: area_ends([second_ally]),
    ),
  ]
  list.each(area_paths, fn(path) {
    let #(state, pressed) =
      pressed_at_in(
        plans: plans_of(spell: path.spell),
        bag: bag_of_base_3,
        target: 7,
        state: cast_state.new(),
        caster: both_see,
        at: 1000,
      )
    let #(state, went) =
      support.answered_each(
        caster: both_see,
        state:,
        effects: pressed,
        at: 1000,
        struck_of: fn(asked) {
          case asked.spell4_id == path.spell.spell4_id {
            True -> [
              ally_selected(unit_id: second_ally),
              ally_selected(unit_id: ally),
            ]
            False -> []
          }
        },
        rolls: [],
        poses: dict.new(),
      )
    let id = support.pressed_id(effects: pressed)
    assert list.length(told(effects: went)) == 2
      as "the go told each ally its change"
    let #(state, effects) = path.run(state, id)
    assert told(effects:) == path.ends(id) as path.why
    assert list.filter(support.finished_ids(support.writes(effects:)), fn(done) {
        done == id
      })
      == case path.finishes {
        True -> [id]
        False -> []
      }
      as { path.why <> ": the cast's 0x7fe" }
    assert list.all(path.removed, fn(unit_id) {
      list.contains(
        support.removed_targets(support.writes(effects:)),
        #(id, [unit_id]),
      )
    })
      as { path.why <> ": the 0x811 of the ally" }
    assert told(effects: cast_tick.left(cast: state).1) == path.left_after(id)
      as {
        path.why <> ": and the caster's leaving afterwards ends what is left"
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
        pool_starts(cast_id: second, sight: kept, go_ms: 3000),
        armor_starts(cast_id: second, sight: kept, go_ms: 3000),
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
  // A planted target apply prerequisite of type 15 (`TargetOfLiveCast`) on the parent
  // itself, Spell4 90001: comparison 1 passes for a unit that is the target of a live cast
  // of it, comparison 2 for one that is not. The gate's first unit is the unit the child is
  // made on, the caster second (`Spell4Effects.prerequisiteIdTargetApply`): for a child on
  // the ally the ally is the unit read, as the caster's picture shows it, which holds none
  // of its casts (`prerequisite.of_struck`), while the caster's own unit holds them. No
  // client row holds such a gate on a Proxy aimed at the primary target.
  let gated_by_the_live_cast = fn(comparison) {
    on_the_target(
      spell_plan.GatedOnTarget(
        prerequisite: prerequisite_support.single(id: 900_010, condition: #(
          15,
          comparison,
          0,
          90_001,
        )),
      ),
    )
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
    Child(
      why: "a Proxy aimed at the primary target behind 'the unit is the target of a live cast of the pressed spell', pressed at the ally: the gate reads the ally as the caster's picture shows it, which holds no casts, so type 15 is not read and no child starts",
      parent: gated_by_the_live_cast(1),
      target: ally,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      child: 90_003,
      starts: [],
      debug: ["900010", "of type 15", "is not read"],
    ),
    Child(
      why: "the same Proxy behind 'the unit is not the target of a live cast of the pressed spell': the caster's own subject would pass it for the ally, which the picture cannot tell, so no child starts and a line says so",
      parent: gated_by_the_live_cast(2),
      target: ally,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      child: 90_003,
      starts: [],
      debug: ["900010", "of type 15", "is not read"],
    ),
    Child(
      why: "the first gate in a press at oneself starts the child on the caster, the target of its own cast",
      parent: gated_by_the_live_cast(1),
      target: 7,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      child: 90_003,
      starts: [#(1000, 7)],
      debug: [],
    ),
    Child(
      why: "the second gate in a press at oneself starts no child",
      parent: gated_by_the_live_cast(2),
      target: 7,
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      child: 90_003,
      starts: [],
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
  let child_id = support.started_cast_id(effects: went, spell4_id: 76_766)
  let assert [child_told] =
    list.filter(told(effects: went), fn(change) {
      case change {
        cast_state.OtherPlayerChangeStarts(source:, ..) ->
          source.cast_id == child_id
        _ -> False
      }
    })
    as "the child tells its one row"
  let assert cast_state.OtherPlayerChangeStarts(
    source:,
    spell4_id:,
    effect:,
    ..,
  ) = child_told
  assert source.effect_id == Spell4EffectsId(199_192)
  assert spell4_id == Spell4Id(76_766)
    as "the tell names the child's own Spell4, whose cast the viewer holds, not the pressed tier's"
  assert effect
    == unit_casts.HeldEffect(
      effect_id: Spell4EffectsId(199_192),
      starts_ms: 1000,
      ends: unit_casts.EndsAt(ms: 6000),
    )
    as "Interrupt Armor row 199192 lasts 5000 ms from the child's go"
  // The child is a cast of its own: its went carries its own cast id and the audience it was
  // started with (the caster's at its go), not the pressed cast's, which is the connections
  // told the press's 0x7ff.
  let went_audience =
    set.from_list([ConnectionId(2), ConnectionId(3), ConnectionId(6)])
  let #(state, pressed) =
    pressed_at_in(
      plans: plans_of(spell: armor),
      bag: bag_of_base_3,
      target: ally,
      state: cast_state.new(),
      caster: esper_seeing(players: [ally]),
      at: 1000,
    )
  let #(_, went) =
    support.answered_each(
      caster: cast_state.Caster(
        ..esper_seeing(players: [ally]),
        audience: went_audience,
      ),
      state:,
      effects: pressed,
      at: 1000,
      struck_of: fn(_) { [] },
      rolls: [],
      poses: dict.new(),
    )
  let pressed_id = support.pressed_id(effects: pressed)
  let child_id = support.started_cast_id(effects: went, spell4_id: 76_766)
  assert trail(effects: went, cast_id: child_id) == ["starts 199192", "went"]
    as "the child tells its row and then its own went"
  assert wents_of(effects: went, cast_id: child_id)
    == [
      cast_state.OtherPlayerCastWent(
        address: address(),
        cast_id: child_id,
        audience: went_audience,
      ),
    ]
    as "the child's went names its own cast and the audience the child was started with"
  assert wents_of(effects: went, cast_id: pressed_id)
    == [
      cast_state.OtherPlayerCastWent(
        address: address(),
        cast_id: pressed_id,
        audience: set.from_list([ConnectionId(2), ConnectionId(3)]),
      ),
    ]
    as "and the pressed cast's own went names its own audience: the two differ"
  // A press whose Proxy starts a child on each of two allies in sight (Runes of Protection,
  // Spell4 39092: Proxy 206357 starts 78708, whose absorb is row 206315,
  // `table_rows -- Spell4Effects 206357 206315`): each child tells its own ally the absorb and
  // then its own went, and no ally is told the other's.
  let other_ally = 41
  let runes = as_base_3(spell4_id: 39_092)
  let #(state, pressed) =
    pressed_at_in(
      plans: plans_of(spell: runes),
      bag: bag_of_base_3,
      target: 7,
      state: cast_state.new(),
      caster: esper_seeing(players: [ally, other_ally]),
      at: 1000,
    )
  let #(_, went) =
    support.answered_each(
      caster: esper_seeing(players: [ally, other_ally]),
      state:,
      effects: pressed,
      at: 1000,
      struck_of: fn(asked) {
        case asked.spell4_id == runes.spell4_id {
          True -> [
            ally_selected(unit_id: ally),
            ally_selected(unit_id: other_ally),
          ]
          False -> []
        }
      },
      rolls: [],
      poses: dict.new(),
    )
  assert support.refusal_results(effects: pressed) == []
    as "the press is accepted"
  // The spell also starts a child on the caster, which tells no player: the children that
  // tell a player are those with a went.
  let child_ids =
    list.filter_map(support.started_in(effects: went), fn(start) {
      case
        start.spell4_id == 78_708
        && wents_of(effects: went, cast_id: start.cast_id) != []
      {
        True -> Ok(start.cast_id)
        False -> Error(Nil)
      }
    })
  assert list.length(child_ids) == 2
    as "one child of Runes of Protection for each ally tells its ally"
  let assert [first_child, second_child] = child_ids
  let on = fn(unit_id) { PlayerAddress(..address(), unit_id:) }
  assert trail(effects: went, cast_id: first_child) == ["starts 206315", "went"]
    as "each child tells its absorb and then its own went"
  assert trail(effects: went, cast_id: second_child)
    == ["starts 206315", "went"]
    as "each child tells its absorb and then its own went"
  let went_ally = fn(cast_id) {
    list.filter_map(wents_of(effects: went, cast_id:), fn(effect) {
      case effect {
        cast_state.OtherPlayerCastWent(address:, ..) -> Ok(address)
        _ -> Error(Nil)
      }
    })
  }
  assert [went_ally(first_child), went_ally(second_child)]
    == [[on(ally)], [on(other_ally)]]
    as "each child's went names the ally the child was started on, and no ally is told the other's cast"
  let absorb_ally = fn(cast_id) {
    list.filter_map(went, fn(effect) {
      case effect {
        cast_state.OtherPlayerChangeStarts(address:, source:, ..)
          if source.cast_id == cast_id
        -> Ok(address)
        _ -> Error(Nil)
      }
    })
  }
  assert [absorb_ally(first_child), absorb_ally(second_child)]
    == [[on(ally)], [on(other_ally)]]
    as "each child tells its absorb to the ally the child was started on, and no ally is told the other's absorb"
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
  // 82438), so its changes end when the caster stops seeing the ally. Spell4Effects 229006
  // (Spell4 87531) is a type 29 absorb of 3000 ms with mask 7, 0.1 of Support Power and
  // propertyFlags 0 (`table_rows -- Spell4Effects 229006`): a Novice's Support Power is
  // 13.921875, and the stat part is rounded alone (`0x140565600`), round(0.1 x 13.921875) = 1.
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
      why: "the absorb 229006 of 87531 started on the ally is told to the ally as the Esper's pool, listed on it and ending with the caster's sight, and starts nothing on the caster",
      parent: started_by(spell_tables.client_spell(spell4_id: 87_531)),
      target: ally,
      child: 87_531,
      listed_on_ally: [229_006],
      told: [
        #(
          229_006,
          held_changes.Absorb(amount: 1, mask: 7),
          held_changes.EndsWhenUnseen,
        ),
      ],
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
          cast_state.OtherPlayerChangeStarts(
            address:,
            source:,
            change:,
            sight:,
            ..,
          ) ->
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
        pool_starts(
          cast_id: third,
          sight: held_changes.KeptWhenUnseen,
          go_ms: 5000,
        ),
        armor_starts(
          cast_id: third,
          sight: held_changes.KeptWhenUnseen,
          go_ms: 5000,
        ),
      ],
    ])
    as "the third press pushes off the oldest cast on the ally, the kept one, and only that one: the second keeps its node and its changes"
}

// ---- a periodic Proxy aimed at the primary target ----

/// The ally's answer to a heal tick of Bolster's row 123122: a heal of 10, all of it health.
fn ally_healed() -> cast_state.Struck {
  cast_state.Hit(
    unit_id: ally,
    unit: cast_state.HitOtherPlayer(heals: [
      strike_tell.HealLanded(
        effect_id: Spell4EffectsId(123_122),
        vital: effect_kind.Health,
        split: heal_split.Split(amount: 10, shield: 0, health: 10, overheal: 0),
      ),
    ]),
    descriptions: [],
    controls: [],
    armor_removed: 0,
    ticking: [],
  )
}

/// Each heal tick the effects ask of the ally answered with `ally_healed`.
fn heal_ticks_answered(
  state state: State,
  caster caster: Caster,
  effects effects: List(Effect),
  at ms: Int,
) -> #(State, List(Effect)) {
  support.ticks_closed(state:, effects:, close: fn(state, asked) {
    cast.ticked(
      cast: state,
      caster:,
      now: support.at(ms:),
      asked:,
      struck: Some(ally_healed()),
    )
  })
}

/// Something that happens at a time of the course besides the timers: a press, a removal, a
/// death. It returns the state and the effects.
type Happening {
  Happening(at_ms: Int, run: fn(State) -> #(State, List(Effect)))
}

/// One course of Bolster tier 9 (Spell4 52142, planted as the base 3 ability): the plans, what
/// happens besides the timers, the caster at each time (what it sees and its Support
/// Rating), when the clock stops, and what the row checks of the run.
type Course {
  Course(
    why: String,
    plans: Plans,
    happenings: List(Happening),
    caster_at: fn(Int) -> Caster,
    until_ms: Int,
    check: fn(Run) -> Nil,
  )
}

/// What a course came to: the state after each happening (the first is the go) and at the
/// end, every step in time order, the happenings' and the timers', and the id of the first
/// cast.
type Run {
  Run(
    after_each: List(State),
    last: State,
    steps: List(#(Int, List(Effect))),
    first_cast_id: Int,
  )
}

/// The effects of every step at the time `ms`.
fn effects_at(run run: Run, ms ms: Int) -> List(Effect) {
  list.flat_map(run.steps, fn(step) {
    case step.0 == ms {
      True -> step.1
      False -> []
    }
  })
}

/// The caster of the course who sees these players and holds this Support Rating.
fn esper_rated(rating rating: Float, seeing seeing: List(Int)) -> Caster {
  cast_state.Caster(
    ..esper_seeing(players: seeing),
    stats: damage.Attacker(..attacker_support.novice(), support_rating: rating),
  )
}

/// A press of the ability at bag slot `bag` at the unit `target`, go included.
fn pressing(
  plans plans: Plans,
  bag bag: Int,
  target target: Int,
  caster_at caster_at: fn(Int) -> Caster,
  at ms: Int,
) -> Happening {
  Happening(at_ms: ms, run: fn(state) {
    let #(state, pressed, went) =
      pressed_at_and_gone_in(
        plans:,
        bag:,
        target:,
        state:,
        at_press: caster_at(ms),
        at_go: caster_at(ms),
        rolls: [],
        at: ms,
      )
    #(state, list.append(pressed, went))
  })
}

/// The run of a course: the happenings in time order and, between them, every timer fired on
/// the driven clock, each go answered as a round that struck nobody and each heal tick on the
/// ally answered with a heal.
fn run_of(course course: Course) -> Run {
  let step = fn(_, state, due, timer) {
    let caster = course.caster_at(due)
    let #(state, raw) =
      cast.timer_fired(cast: state, timer:, caster:, now: support.at(ms: due))
    let #(state, answered) =
      support.answered_each(
        caster:,
        state:,
        effects: raw,
        at: due,
        struck_of: fn(_) { [] },
        rolls: [],
        poses: dict.new(),
      )
    let #(state, effects) =
      heal_ticks_answered(state:, caster:, effects: answered, at: due)
    support.Step(context: Nil, state:, effects:, record: #(due, effects))
  }
  let happenings =
    list.sort(course.happenings, fn(first, second) {
      int.compare(first.at_ms, second.at_ms)
    })
  let #(state, pending, steps, after_each) =
    list.fold(happenings, #(cast_state.new(), [], [], []), fn(so_far, one) {
      let #(state, pending, steps, after_each) = so_far
      let #(_, state, fired, left) =
        support.fire_pending(
          context: Nil,
          state:,
          pending:,
          until_ms: one.at_ms - 1,
          step:,
        )
      let #(state, effects) = one.run(state)
      let cancelled = support.cancelled_timers(effects:)
      #(
        state,
        list.append(
          list.filter(left, fn(waiting) { !list.contains(cancelled, waiting.1) }),
          support.due_of(effects:, now_ms: one.at_ms),
        ),
        list.flatten([steps, fired, [#(one.at_ms, effects)]]),
        list.append(after_each, [state]),
      )
    })
  let #(_, last, fired, _) =
    support.fire_pending(
      context: Nil,
      state:,
      pending:,
      until_ms: course.until_ms,
      step:,
    )
  let assert Ok(first_press) = list.first(steps)
    as "the first happening writes the press"
  Run(
    after_each:,
    last:,
    steps: list.append(steps, fired),
    first_cast_id: support.pressed_id(effects: first_press.1),
  )
}

/// Every 0x7ff of the child Spell4 87531 with the time it is written at.
fn child_starts_of(run run: Run) -> List(#(Int, spell_started.SpellStarted)) {
  support.starts_of(steps: run.steps, spell4_id: 87_531)
}

/// An absorb pool told to the ally: the source it was told with, its amount, when it was
/// told and when each end of it was told.
type Pool {
  Pool(source: Source, amount: Int, started_ms: Int, ended_ms: List(Int))
}

/// Every absorb pool the run told the ally, in the order told.
fn pools_of(run run: Run) -> List(Pool) {
  list.fold(run.steps, [], fn(pools, step) {
    list.fold(step.1, pools, fn(pools, effect) {
      pool_changed(pools:, effect:, at_ms: step.0)
    })
  })
}

/// The pools after one effect: an absorb told to the ally starts a pool, and the end of a
/// pool told to the ally adds its time.
fn pool_changed(
  pools pools: List(Pool),
  effect effect: Effect,
  at_ms ms: Int,
) -> List(Pool) {
  case effect {
    cast_state.OtherPlayerChangeStarts(
      address:,
      source:,
      change: held_changes.Absorb(amount:, ..),
      ..,
    )
      if address.unit_id == ally
    ->
      list.append(pools, [
        Pool(source:, amount:, started_ms: ms, ended_ms: []),
      ])
    cast_state.OtherPlayerChangeEnds(address:, source:)
      if address.unit_id == ally
    ->
      list.map(pools, fn(pool) {
        case pool.source == source {
          True -> Pool(..pool, ended_ms: list.append(pool.ended_ms, [ms]))
          False -> pool
        }
      })
    _ -> pools
  }
}

/// How many pools of the child the ally holds at `ms`: told by then and not ended.
fn held_at(pools pools: List(Pool), ms ms: Int) -> Int {
  list.count(pools, fn(pool) {
    pool.started_ms <= ms && list.all(pool.ended_ms, fn(ended) { ended > ms })
  })
}

/// The tick timers of the state, each as the cast id, the unit and the effect id.
fn tick_timers_of(state state: State) -> List(#(Int, Int, Int)) {
  list.filter_map(cast_state.timers_in_order(cast: state), fn(entry) {
    case entry.1 {
      cast_state.Tick(cast_id:, unit_id:, effect_id:, ..) ->
        Ok(#(cast_id, unit_id, effect_id.value))
      _ -> Error(Nil)
    }
  })
}

/// The units the cast `cast_id` holds a node on in the state.
fn node_units_of(state state: State, cast_id cast_id: Int) -> List(Int) {
  list.filter_map(cast_state.holders(cast: state), fn(entry) {
    case entry.0 == cast_id {
      True -> Ok(dict.keys({ entry.1 }.nodes))
      False -> Error(Nil)
    }
  })
  |> list.flatten
  |> list.sort(int.compare)
}

/// The Spell4 52142 of Bolster tier 9 as the planted base 3 ability, the plans that hold it,
/// and, as base 1, a press at the same player that takes the nodes of its cast off with a
/// type 80 row.
fn bolster() -> Spell {
  as_base_3(spell4_id: 52_142)
}

fn bolster_with_a_removal() -> Plans {
  let spell = bolster()
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

/// The state after the nth happening of the run, counting from 1.
fn after(run run: Run, happening happening: Int) -> State {
  let assert [state, ..] = list.drop(run.after_each, happening - 1)
    as "the course has that many happenings"
  state
}

/// The units the 0x7f4 of the cast `cast_id` among the effects lists, each with the effect
/// ids listed on it.
fn listed_by(
  effects effects: List(Effect),
  cast_id cast_id: Int,
) -> List(#(Int, List(Int))) {
  list.flat_map(support.goes_in(effects:), fn(go) {
    case go.cast_id == cast_id {
      True ->
        list.map(go.targets, fn(unit) {
          #(
            unit.unit_id,
            list.map(unit.effects, fn(info) { info.spell4_effects_id }),
          )
        })
      False -> []
    }
  })
}

/// The cast ids the effects write a 0x7fe for.
fn finished_in(effects effects: List(Effect)) -> List(Int) {
  support.finished_ids(support.writes(effects:))
}

pub fn a_periodic_proxy_aimed_at_the_primary_target_ticks_on_the_player_the_press_named_and_each_tick_starts_its_child_on_that_player_test() -> Nil {
  use <- owned_test.run(30_000)
  // Spell4 52142 (Bolster tier 9, castTime 0, spellCoolDown 1000, stack group 2410 cap 2) holds
  // the heal row 123122 (type 10, targetFlags 2, tickTime 1000, durationTime 8000) and the
  // Proxy 229005 (type 26, targetFlags 2, tickTime 1000, durationTime 8000), which casts
  // Spell4 87531 at each of the 8 ticks; 87531 holds the absorb 229006 (type 29, 3000 ms, 0.1
  // of Support Power, propertyFlags 0, stack group 2411 cap 25) (`table_rows -- Spell4 52142
  // 87531 -- Spell4Effects 123122 229005 229006`). The press is the go (castTime 0), at 1000,
  // and tick k is at 1000 + 1000 k. A Novice's Support Power is 13.921875, so a pool is
  // round(0.1 x 13.921875) = 1; a caster of 400 Support Rating has 100, so a pool of 10. The
  // server's choice: the tick of a Proxy aimed at the primary target starts its child on the
  // player the press named, as the go does. The last node of a cast ends with its 0x7fe and
  // no 0x811: a finish 0x7fe destroys every node of the cast and then the cast
  // (`cast.target_node_end`), so a 0x811 first would add nothing (`opcode.0x811`).
  let go = 1000
  let tick = fn(k) { go + 1000 * k }
  let seeing_ally = fn(_) { esper_seeing(players: [ally]) }
  let plans = plans_of(spell: bolster())
  let press_at = fn(target, ms) {
    pressing(
      plans:,
      bag: bag_of_base_3,
      target:,
      caster_at: seeing_ally,
      at: ms,
    )
  }
  let course = fn(why, check) {
    Course(
      why:,
      plans:,
      happenings: [press_at(ally, go)],
      caster_at: seeing_ally,
      until_ms: tick(8) + 3500,
      check:,
    )
  }
  let all_ticks = list.map([1, 2, 3, 4, 5, 6, 7, 8], tick)
  let child_starts_at = fn(run) {
    list.map(child_starts_of(run:), fn(start) { start.0 })
  }
  let courses = [
    course(
      "the go: both rows tick on the ally and none on the Esper, the 0x7f4 lists the heal row on the ally and no effect for the Proxy, the Esper holds no node of the cast and the cast's 0x7fe comes with the end of the ally's node at the go plus 8000",
      fn(run) {
        let why = "the go"
        assert list.sort(
            tick_timers_of(state: after(run:, happening: 1)),
            fn(first, second) { int.compare(first.2, second.2) },
          )
          == [
            #(run.first_cast_id, ally, 123_122),
            #(run.first_cast_id, ally, 229_005),
          ]
          as { why <> ": the tick timers" }
        assert listed_by(
            effects: effects_at(run:, ms: go),
            cast_id: run.first_cast_id,
          )
          == [#(ally, [123_122])]
          as { why <> ": the 0x7f4 lists the heal row on the ally alone" }
        assert node_units_of(
            state: after(run:, happening: 1),
            cast_id: run.first_cast_id,
          )
          == [ally]
          as { why <> ": the nodes of the cast" }
        assert list.contains(
          finished_in(effects: effects_at(run:, ms: tick(8))),
          run.first_cast_id,
        )
          as { why <> ": the cast's 0x7fe at the go plus 8000" }
        assert list.all(run.steps, fn(step) {
          step.0 >= tick(8)
          || !list.contains(finished_in(effects: step.1), run.first_cast_id)
        })
          as { why <> ": and none before" }
        assert support.removed_targets(
            support.writes(effects: effects_at(run:, ms: tick(8))),
          )
          == []
          as { why <> ": the last node ends with the 0x7fe, no 0x811" }
      },
    ),
    course(
      "tick k: one 0x7ff of 87531 naming the ally as primary target with the Esper as caster and the pressed spell as parent and root, and one pool told to the ally with a source of its own",
      fn(run) {
        let why = "each tick"
        assert child_starts_at(run) == all_ticks
          as { why <> ": the child starts at each tick, once" }
        assert list.all(child_starts_of(run:), fn(start) {
          let start = start.1
          start.primary_target_unit_id == ally
          && start.caster_unit_id == 7
          && start.parent_spell4_id == 52_142
          && start.root_spell4_id == 52_142
        })
          as { why <> ": each names the ally, the Esper and Bolster" }
        let pools = pools_of(run:)
        assert list.map(pools, fn(pool) { pool.started_ms }) == all_ticks
          as { why <> ": one pool told to the ally at each tick" }
        assert list.length(
            list.unique(list.map(pools, fn(pool) { pool.source })),
          )
          == 8
          as { why <> ": each with a source of its own" }
        assert list.all(pools, fn(pool) {
          pool.source.effect_id.value == 229_006
        })
          as { why <> ": the row of the absorb" }
        assert list.all(pools, fn(pool) { pool.amount == 1 })
          as { why <> ": 1 of a Novice's Support Power" }
      },
    ),
    Course(
      ..course(
        "a caster of 400 Support Rating from tick 2: the child's go reads the caster as it is then",
        fn(run) {
          assert list.map(pools_of(run:), fn(pool) { pool.amount })
            == [1, 10, 10, 10, 10, 10, 10, 10]
            as "tick 1's pool is the Novice's, every later one 0.1 of 100"
        },
      ),
      caster_at: fn(ms) {
        case ms >= tick(2) {
          True -> esper_rated(rating: 400.0, seeing: [ally])
          False -> esper_seeing(players: [ally])
        }
      },
    ),
    course(
      "held at once: three pools between ticks, at the go plus 3500, 4500 and 8500, each end told once at its tick plus 3000 and none before, and none pushed off (group 2411, cap 25)",
      fn(run) {
        let why = "the pools"
        let pools = pools_of(run:)
        list.each([go + 3500, go + 4500, go + 8500], fn(ms) {
          assert held_at(pools:, ms:) == 3
            as { why <> ": held at " <> int.to_string(ms) }
        })
        assert list.map(pools, fn(pool) { pool.ended_ms })
          == list.map(all_ticks, fn(ms) { [ms + 3000] })
          as { why <> ": each end told once, at its tick plus 3000" }
      },
    ),
    Course(
      ..course(
        "a type 80 removal of the cast's node on the ally at the go plus 2500: no tick from the go plus 3000 starts a child, and the two pools told stay held to their own ends",
        fn(run) {
          assert child_starts_at(run) == [tick(1), tick(2)]
            as "only the two ticks before the removal start a child"
          assert tick_timers_of(state: run.last) == []
            as "no tick timer is left"
          assert list.map(pools_of(run:), fn(pool) {
              #(pool.started_ms, pool.ended_ms)
            })
            == [#(tick(1), [tick(1) + 3000]), #(tick(2), [tick(2) + 3000])]
            as "each pool ends at its own end, once"
          assert support.removed_targets(
              support.writes(effects: effects_at(run:, ms: go + 2500)),
            )
            == [#(run.first_cast_id, [ally])]
            as "the removal's 0x811 names the ally alone"
        },
      ),
      plans: bolster_with_a_removal(),
      happenings: [
        press_at(ally, go),
        pressing(
          plans: bolster_with_a_removal(),
          bag: bag_of_base_1,
          target: ally,
          caster_at: seeing_ally,
          at: go + 2500,
        ),
      ],
    ),
    Course(
      ..course(
        "the third press at the stack cap of Bolster (group 2410, cap 2) pushes the first cast's node off the ally: its remaining ticks of both rows stop and the children it already started keep their pools",
        fn(run) {
          let third = after(run:, happening: 3)
          let ids =
            list.unique(
              list.map(tick_timers_of(state: third), fn(timer) { timer.0 }),
            )
          assert list.length(ids) == 2 && !list.contains(ids, run.first_cast_id)
            as "after the third press only the second and third casts tick, each with both rows"
          assert list.length(tick_timers_of(state: third)) == 4
            as "two rows for each of the two casts"
          assert list.contains(
            support.removed_targets(
              support.writes(effects: effects_at(run:, ms: go + 3700)),
            ),
            #(run.first_cast_id, [ally]),
          )
            as "the push off's 0x811 names the first cast's node on the ally"
          let before =
            list.filter(pools_of(run:), fn(pool) { pool.started_ms < go + 3700 })
          assert list.length(before) == 5
            as "the first cast's three ticks and the second's two started a pool each before the push off"
          assert list.all(before, fn(pool) {
            pool.ended_ms == [pool.started_ms + 3000]
          })
            as "each keeps its pool to its own end, told once"
        },
      ),
      happenings: [
        press_at(ally, go),
        press_at(ally, go + 1300),
        press_at(ally, go + 3700),
      ],
    ),
    Course(
      ..course(
        "the ally out of the caster's sight at tick 3 and back at tick 4: tick 3 starts no child and a debug line says it is not in the caster's sight, and the ticks go on",
        fn(run) {
          assert child_starts_at(run)
            == [tick(1), tick(2), tick(4), tick(5), tick(6), tick(7), tick(8)]
            as "tick 3 starts nothing and tick 4 starts one again"
          assert list.any(
            support.debug_lines(effects: effects_at(run:, ms: tick(3))),
            fn(line) {
              string.contains(line, "87531")
              && string.contains(line, "not in the caster's sight")
            },
          )
            as "tick 3 writes the line"
        },
      ),
      caster_at: fn(ms) {
        case ms == tick(3) {
          True -> esper_seeing(players: [])
          False -> esper_seeing(players: [ally])
        }
      },
    ),
    Course(
      ..course(
        "a press at oneself: both rows tick on the Esper and each child starts on the Esper, told to nobody",
        fn(run) {
          assert list.sort(
              tick_timers_of(state: after(run:, happening: 1)),
              fn(first, second) { int.compare(first.2, second.2) },
            )
            == [
              #(run.first_cast_id, 7, 123_122),
              #(run.first_cast_id, 7, 229_005),
            ]
            as "both rows tick on the caster"
          assert list.map(child_starts_of(run:), fn(start) {
              #(start.0, start.1.primary_target_unit_id)
            })
            == list.map(all_ticks, fn(ms) { #(ms, 7) })
            as "each child starts on the Esper"
          assert pools_of(run:) == [] as "no pool is told to the ally"
        },
      ),
      happenings: [press_at(7, go)],
    ),
    Course(
      ..course(
        "the Esper dies at the go plus 3500: the ends of the three pools held are told once each at the death and the timers tell none later",
        fn(run) {
          let pools = pools_of(run:)
          assert list.length(pools) == 3
            as "the three ticks before the death started a pool each"
          assert list.all(pools, fn(pool) { pool.ended_ms == [go + 3500] })
            as "each end is told once, at the death"
        },
      ),
      happenings: [
        press_at(ally, go),
        Happening(at_ms: go + 3500, run: fn(state) {
          cast.died(
            cast: state,
            caster: support.dead_caster(),
            now: support.at(ms: go + 3500),
          )
        }),
      ],
    ),
  ]
  list.each(courses, fn(course) {
    let run = run_of(course:)
    course.check(run)
  })
}

// ---- the rows a node lists on the player a press names ----

/// The spells a press at a player starts, from the tree of `spell` (`spell_plan.tree_started`):
/// the spell itself, its stages and each spell a Proxy aimed at one of `aimed` starts on that
/// player, theirs the same way. A spell a proc starts is left out: its primary target is the
/// unit the proc names.
fn started_at_a_player(
  spell spell: Spell,
  aimed aimed: List(spell_plan.ProxyTarget),
) -> List(Spell) {
  spell_plan.tree_started(spell:, started: fn(proxy) {
    list.contains(aimed, proxy.target)
  })
  |> list.filter_map(fn(started) {
    case started.1 {
      spell_plan.Pressed -> Ok(started.0)
      spell_plan.Proxied(target:) ->
        case list.contains(aimed, target) {
          True -> Ok(started.0)
          False -> Error(Nil)
        }
      spell_plan.FromProc(..) -> Error(Nil)
    }
  })
}

/// The ledger of the ally's connection after the changes `effects` tell it, from the caster's
/// connection 1 and its unit 7.
fn ledger_told(effects effects: List(Effect)) -> held_changes.Held {
  list.fold(told(effects:), held_changes.new(), fn(held, change) {
    case change {
      cast_state.OtherPlayerChangeStarts(
        source:,
        sight:,
        spell4_id:,
        effect:,
        ..,
      ) ->
        held_changes.started(
          held:,
          by: ConnectionId(1),
          unit_id: 7,
          source:,
          sight:,
          spell4_id:,
          effect:,
        ).0
      _ -> held
    }
  })
}

/// The effect ids of the rows of `spell` that would land a change on the ally a press names
/// (`gate.modifier_applies`: a modifier, an absorb or an Interrupt Armor row aimed at the
/// primary target), whatever the cast rule decides about the press.
fn changes_the_plan_would_land_on_the_ally(spell spell: Spell) -> List(Int) {
  list.filter_map(spell.effects, fn(planned) {
    case planned.kind {
      spell_plan.ModifierEffect(modifier:) ->
        case
          spell_plan.reaches_primary_target(aim: spell_plan.modifier_aim(
            modifier:,
          ))
          && gate.modifier_applies(
            row: modifier,
            unit_id: ally,
            caster: esper_seeing(players: [ally]),
            struck: [],
            press_target: Some(ally),
            aura_ends_ms: spell_plan.aura_ends_ms(spell:, started_ms: 1000),
            go_ms: 1000,
          )
        {
          True -> Ok(planned.effect_id.value)
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

/// The effect ids the caster's node lists on the ally in the go.
fn listed_on_the_ally(gone gone: GoneOnTheAlly) -> List(Int) {
  list.flat_map(gone.on_the_ally, fn(view) {
    list.flat_map(view.targets, fn(target) {
      list.map(target.effects, fn(effect) { effect.effect_id.value })
    })
  })
}

/// One press of `spell` at the ally and its go, as the cast rule runs it for a caster that
/// sees the ally: the pressed cast's id, the effect ids of the changes the go told the ally,
/// and the view the ally's ledger lists of the cast from those tells beside the view the
/// caster's own node lists of it on the ally (`cast_state.views`), both at the go's time.
type GoneOnTheAlly {
  GoneOnTheAlly(
    told: List(Int),
    in_ledger: List(unit_casts.CastView),
    on_the_ally: List(unit_casts.CastView),
  )
}

/// The go of the press, or `Error(Nil)` when the cast rule refuses the press and sends no go.
fn gone_on_the_ally(spell spell: Spell) -> Result(GoneOnTheAlly, Nil) {
  let #(state, pressed, went) =
    pressed_and_gone(
      spell: Spell(..spell, spell4_base_id: Spell4BaseId(3)),
      state: cast_state.new(),
      at_press: esper_grouped_with(players: [ally]),
      at_go: esper_grouped_with(players: [ally]),
      rolls: [],
      at: 1000,
    )
  // A press the rule refuses has no go: it tells the ally nothing.
  use <- bool.guard(
    when: support.frames_of(
      message_id: spell_cast_confirmed.message_id,
      effects: pressed,
    )
      == [],
    return: Error(Nil),
  )
  let id = support.pressed_id(effects: pressed)
  Ok(GoneOnTheAlly(
    told: list.filter_map(told(effects: went), fn(change) {
      case change {
        cast_state.OtherPlayerChangeStarts(source:, ..)
          if source.cast_id == id
        -> Ok(source.effect_id.value)
        _ -> Error(Nil)
      }
    }),
    in_ledger: list.filter(
      held_changes.cast_views(
        held: ledger_told(effects: went),
        holder_unit_id: ally,
        now_ms: 1000,
      ),
      fn(view) { view.cast_id == id },
    ),
    on_the_ally: list.filter_map(
      list.filter(cast_state.views(cast: state, caster_unit_id: 7), fn(view) {
        view.cast_id == id
      }),
      fn(view) {
        let targets =
          list.filter(view.targets, fn(target) { target.unit_id == ally })
        case targets {
          [] -> Error(Nil)
          _ -> Ok(unit_casts.CastView(..view, targets:))
        }
      },
    ),
  ))
}

pub fn the_rows_a_node_lists_on_a_player_a_press_names_are_the_changes_the_ledger_is_told_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  // An ability is the Spell4Base of a SpellLevel row's spell; each tier of it is a spell of
  // that base.
  let bases =
    spell_level.all(tables)
    |> list.filter_map(fn(level) {
      spell4.get(tables:, id: Spell4Id(level.spell4_id))
    })
    |> list.map(fn(spell) { spell.spell4_base_id_base_spell })
    |> set.from_list
  let tiers =
    list.filter(spell4.all(tables), fn(spell) {
      set.contains(bases, spell.spell4_base_id_base_spell)
    })
    |> list.map(fn(spell) { spell.id })
  assert tiers != [] as "the client's tables hold the abilities' tiers"
  let abilities =
    list.filter_map(tiers, fn(spell4_id) {
      case spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: []) {
        Ok(spell) -> Ok(spell)
        Error(error) -> {
          assert spell_plan.is_unbuilt(error:)
            as "a tier the plan leaves out names an effect or rule the server does not build, never a fault of the data"
          Error(Nil)
        }
      }
    })
  // Each spell a press starts at a player, once, pressed at the ally and gone: what its go
  // told and what the ledger and the caster's node list of it. The Fluff rows (Spell4 bases
  // 26762, 35526, 63087, 19030's child 54912 and 47675's children) are listed on the player
  // and told as no change: the stated gap, which the ledger does not list, so a spell that
  // tells nothing is not compared.
  let gone_after = fn(aimed) {
    list.flat_map(abilities, started_at_a_player(spell: _, aimed:))
    |> list.fold(dict.new(), fn(spells, spell) {
      case dict.has_key(spells, spell.spell4_id.value) {
        True -> spells
        False -> dict.insert(spells, spell.spell4_id.value, spell)
      }
    })
    |> dict.to_list
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(fn(spell) { #(spell.1, gone_on_the_ally(spell: spell.1)) })
  }
  let gone_only = fn(pressed: List(#(Spell, Result(GoneOnTheAlly, Nil)))) {
    list.filter_map(pressed, fn(entry) {
      result.map(entry.1, fn(gone) { #(entry.0, gone) })
    })
  }
  let told_by = fn(pressed: List(#(Spell, Result(GoneOnTheAlly, Nil)))) {
    list.flat_map(gone_only(pressed), fn(spell) { { spell.1 }.told })
    |> list.unique
    |> list.sort(int.compare)
  }
  let at_a_player = gone_after([spell_plan.OnPrimaryTarget])
  assert told_by(at_a_player)
    == list.sort(
      [
        // Phantasmal Armor's absorb of each of its nine tiers.
        62_024,
        123_652,
        123_656,
        123_660,
        123_664,
        123_668,
        123_672,
        123_676,
        130_470,
        // The modifier of tiers 5 to 9.
        203_798,
        203_799,
        203_800,
        203_801,
        130_474,
        // Interrupt Armor, started by every tier's Proxy, and Bolster tier 9's absorb.
        199_192,
        229_006,
      ],
      int.compare,
    )
    as "the changes a press at a player tells it are the 16 rows of Phantasmal Armor, its Interrupt Armor child and Bolster's absorb"
  // A press whose Proxy starts a child on each ally the area selects lands the child's rows
  // on that ally as a press at the ally does.
  let widened = gone_after([spell_plan.OnPrimaryTarget, spell_plan.OnEachAlly])
  assert list.all(told_by(at_a_player), list.contains(told_by(widened), _))
    as "a child on each ally adds to the changes told and takes none away"
  assert list.contains(told_by(widened), 206_315)
    as "Runes of Protection's child 78708 tells its absorb 206315 to the ally"
  assert list.contains(told_by(widened), 199_194)
    as "Barrier's child 76767 tells its Interrupt Armor row 199194 to the ally"
  // A press the cast rule refuses sends no go and tells the ally nothing, so the plan of a
  // refused spell must land no change on the ally: one that did would drop out of the checks
  // below unseen.
  list.each(widened, fn(entry) {
    let #(spell, pressed) = entry
    use <- bool.guard(when: result.is_ok(pressed), return: Nil)
    assert changes_the_plan_would_land_on_the_ally(spell:) == []
      as {
        "Spell4 "
        <> int.to_string(spell.spell4_id.value)
        <> " is refused at the grouped ally and its plan lands no change on the ally"
      }
  })
  list.each(gone_only(widened), fn(entry) {
    let #(spell, gone) = entry
    use <- bool.guard(when: gone.told == [], return: Nil)
    let why = "Spell4 " <> int.to_string(spell.spell4_id.value)
    // The ally starts a cast with a 0x7ff of root = the spell and parent 0, which the
    // client reads only for a threshold cast (`opcode.0x7ff.root_parent`: cast methods 2, 6
    // and 7), and holds one go (`opcode.0x7f4`).
    assert spell.method == spell_plan.Normal
      as { why <> " tells a change and is a Normal cast" }
    assert spell_plan.go_times_ms(spell:) == [0]
      as { why <> " tells a change and has the one go" }
    // What the caster's node lists on the player beside the changes told are the spell's Fluff
    // rows (the plan's `LastingEffect`) and its heal rows (`HealEffect`: Heal, and HealShields,
    // type 118), which the go lists on the player and tells as no change or as a heal: the
    // stated gaps. Every other row the node lists is told, so the ledger lists of the cast
    // what the caster's node lists.
    let not_changes =
      list.filter_map(spell.effects, fn(planned) {
        case
          spell_plan.as_lasting(kind: planned.kind),
          spell_plan.as_heal(kind: planned.kind)
        {
          Error(Nil), Error(Nil) -> Error(Nil)
          _, _ -> Ok(planned.effect_id.value)
        }
      })
    let listed = listed_on_the_ally(gone:)
    assert list.all(listed, fn(id) {
      list.contains(gone.told, id) || list.contains(not_changes, id)
    })
      as {
        why
        <> ": the node lists on the ally only the rows told, Fluff rows and heal rows"
      }
    let told_only =
      list.map(gone.on_the_ally, fn(view) {
        unit_casts.CastView(
          ..view,
          targets: list.map(view.targets, fn(target) {
            unit_casts.ViewTarget(
              ..target,
              effects: list.filter(target.effects, fn(effect) {
                list.contains(gone.told, effect.effect_id.value)
              }),
            )
          }),
        )
      })
    assert gone.in_ledger == told_only
      as {
        why
        <> ": the ledger's view of the cast is the caster's node on the ally, bar the Fluff and heal rows"
      }
  })
  // Of the heal rows a spell that tells a change lists on the ally, one is no change and
  // outside the ledger: the HealShields row 145873 of Spell4 60416 (tier 9 of Protection
  // Probes), which the gap in `landing.gaps` names.
  let heals_listed =
    list.flat_map(gone_only(widened), fn(entry) {
      let #(spell, gone) = entry
      case gone.told {
        [] -> []
        _ ->
          list.filter(listed_on_the_ally(gone:), fn(id) {
            list.any(spell.effects, fn(planned) {
              planned.effect_id.value == id
              && result.is_ok(spell_plan.as_heal(kind: planned.kind))
            })
          })
      }
    })
    |> list.unique
  assert heals_listed == [145_873]
    as "the one heal row a spell that tells a change lists on the ally is Spell4 60416's HealShields row 145873"
}

// ---- a Proxy aimed at the area of a spell that finds allies ----

/// A hit of a go on the player `unit_id` that no row reached: the area selected it for a Proxy,
/// so the strike answered it at once with nothing landed.
fn ally_selected(unit_id unit_id: Int) -> cast_state.Struck {
  cast_state.Hit(
    unit_id:,
    unit: cast_state.HitOtherPlayer(heals: []),
    descriptions: [],
    controls: [],
    armor_removed: 0,
    ticking: [],
  )
}

/// One press at oneself of a parent that holds a Proxy aimed at the area, whose go the round
/// of `hit` answers: whom the caster sees at the go and when the child starts, the rolls of the
/// go, and each start of the child as the time and the primary target it names.
type Selected {
  Selected(
    why: String,
    proxy: spell_plan.Proxy,
    hit: List(cast_state.Struck),
    sees_at_go: List(Int),
    sees_later: List(Int),
    rolls: List(Int),
    starts: List(#(Int, Int)),
    debug: List(String),
  )
}

pub fn a_proxy_at_the_area_starts_one_child_on_each_ally_the_round_hit_naming_that_ally_and_none_on_a_creature_a_foe_spell_hit_test() -> Nil {
  use <- owned_test.run(10_000)
  // A Proxy aimed at the area (targetFlags 4) starts its child on each unit the go hit
  // (`cast.went`). The area of a spell that finds allies selects players, so each child is cast
  // on an ally and names it as its player, whose sight the caster checks when the child starts
  // (`child_started`); the area of a spell that hits foes selects creatures, which are no
  // player and name none. Planted parent, as the union tests' (`cast_union_aim_test`).
  let plain = support.child(spell4_id: 90_003, base: 4)
  let other_ally = 41
  let creature = 20
  let on_allies = fn(delay_ms, condition) {
    proxy_of(child: plain, target: spell_plan.OnEachAlly, delay_ms:, condition:)
  }
  let rows = [
    Selected(
      why: "a round that hit two allies starts two children, each with its ally as primary target, in the round's order",
      proxy: on_allies(0, Always),
      hit: [ally_selected(unit_id: other_ally), ally_selected(unit_id: ally)],
      sees_at_go: [ally, other_ally],
      sees_later: [ally, other_ally],
      rolls: [],
      starts: [#(1000, other_ally), #(1000, ally)],
      debug: [],
    ),
    Selected(
      why: "a Proxy with a delay of 250 ms (Affinity's 207513) starts each child 250 ms on",
      proxy: on_allies(250, Always),
      hit: [ally_selected(unit_id: ally), ally_selected(unit_id: other_ally)],
      sees_at_go: [ally, other_ally],
      sees_later: [ally, other_ally],
      rolls: [],
      starts: [#(1250, ally), #(1250, other_ally)],
      debug: [],
    ),
    Selected(
      why: "an ally out of the caster's sight when the child starts: no child for it, a debug line says so, and the ally in sight gets its own",
      proxy: on_allies(250, Always),
      hit: [ally_selected(unit_id: ally), ally_selected(unit_id: other_ally)],
      sees_at_go: [ally, other_ally],
      sees_later: [other_ally],
      rolls: [],
      starts: [#(1250, other_ally)],
      debug: ["90003", "40", "not in the caster's sight"],
    ),
    Selected(
      why: "an ally out of the caster's sight at the go: no child and the same line",
      proxy: on_allies(0, Always),
      hit: [ally_selected(unit_id: ally)],
      sees_at_go: [],
      sees_later: [],
      rolls: [],
      starts: [],
      debug: ["90003", "40", "not in the caster's sight"],
    ),
    Selected(
      why: "a Proxy behind a caster gate that fails (4585: at most 50, roll 80) starts no child",
      proxy: on_allies(0, spell_plan.GatedOnCaster(gates: [chance_gate()])),
      hit: [ally_selected(unit_id: ally)],
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [80],
      starts: [],
      debug: [],
    ),
    Selected(
      why: "a round that hit no ally starts no child",
      proxy: on_allies(0, Always),
      hit: [],
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      starts: [],
      debug: [],
    ),
    Selected(
      why: "a creature a spell that hits foes struck: the child starts on it and names no player, though the caster sees no creature as one",
      proxy: proxy_of(
        child: plain,
        target: spell_plan.OnEachStruck,
        delay_ms: 0,
        condition: Always,
      ),
      hit: support.hits([creature]),
      sees_at_go: [ally],
      sees_later: [ally],
      rolls: [],
      starts: [#(1000, creature)],
      debug: [],
    ),
  ]
  list.each(rows, fn(row) {
    let parent = parent_of(proxy: row.proxy)
    let #(state, pressed) =
      pressed_at_in(
        plans: plans_of(spell: parent),
        bag: bag_of_base_3,
        target: 7,
        state: cast_state.new(),
        caster: esper_seeing(players: [ally, other_ally]),
        at: 1000,
      )
    let #(state, went) =
      support.answered_each(
        caster: esper_seeing(players: row.sees_at_go),
        state:,
        effects: pressed,
        at: 1000,
        struck_of: fn(asked) {
          case asked.spell4_id == parent.spell4_id {
            True -> row.hit
            False -> []
          }
        },
        rolls: row.rolls,
        poses: dict.new(),
      )
    let #(_, steps) =
      support.run_timers_each(
        caster: esper_seeing(players: row.sees_later),
        state:,
        effects: list.append(pressed, went),
        from_ms: 1000,
        struck_of: fn(_) { [] },
      )
    let started =
      list.flatten([
        starts_of(effects: went, spell4_id: 90_003, at: 1000),
        list.flat_map(steps, fn(step) {
          starts_of(effects: step.1, spell4_id: 90_003, at: step.0)
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
  })
}

// ---- a modifier row aimed at the area of a spell that finds allies ----

/// A second player the caster sees, an ally the round hit beside the ally 40.
const second_ally = 41

/// Spell4Effects 92788, Barrier's property row (Spell4 41369): property 175, flags 5, 5000 ms.
const barrier_row = 92_788

/// A planted spell shaped as Barrier's child 41369: the caster's own `PropertyChange` and the
/// allies' `StruckChange` of row 92788 (targetFlags 5, 5000 ms, no delay), pressed on the caster.
/// The real spell's propertyFlags are 8448 (0x2100), which hold 0x100, so `outlives_caster` is true
/// for it (`held_changes.sight_of`); `outlives_caster: False` plants the same spell without.
fn barrier_shaped(outlives_caster outlives_caster: Bool) -> Spell {
  let assert spell_plan.StruckChange(modifier:, ..) =
    support.armor_modifier_row(id: barrier_row, aim: spell_plan.AimsAtCaster).change
    as "row 130474 is a StruckChange"
  let five_seconds =
    lasting.LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False)
  let caster_part =
    spell_plan.PropertyModifier(
      ..support.armor_modifier_row(
        id: barrier_row,
        aim: spell_plan.AimsAtCaster,
      ),
      change: spell_plan.PropertyChange(modifier),
      row: five_seconds,
    )
  let allies_part =
    spell_plan.PropertyModifier(
      ..support.armor_modifier_row(id: barrier_row, aim: spell_plan.AimsAtArea),
      row: five_seconds,
    )
  Spell(
    ..support.armor_spell(rows: [caster_part, allies_part]),
    spell4_id: Spell4Id(41_369),
    outlives_caster:,
  )
}

fn barrier_change_of(
  unit_id unit_id: Int,
  cast_id cast_id: Int,
  sight sight: held_changes.Sight,
  go_ms go_ms: Int,
) -> Effect {
  let assert spell_plan.StruckChange(modifier:, ..) =
    support.armor_modifier_row(id: barrier_row, aim: spell_plan.AimsAtArea).change
    as "row 130474 is a StruckChange"
  cast_state.OtherPlayerChangeStarts(
    address: PlayerAddress(..address(), unit_id:),
    source: source_of(cast_id:, effect_id: barrier_row),
    change: held_changes.Property(modifier:),
    sight:,
    spell4_id: Spell4Id(41_369),
    effect: unit_casts.HeldEffect(
      effect_id: Spell4EffectsId(barrier_row),
      starts_ms: go_ms,
      ends: unit_casts.EndsAt(ms: go_ms + 5000),
    ),
  )
}

fn barrier_change_ends(unit_id unit_id: Int, cast_id cast_id: Int) -> Effect {
  cast_state.OtherPlayerChangeEnds(
    address: PlayerAddress(..address(), unit_id:),
    source: source_of(cast_id:, effect_id: barrier_row),
  )
}

/// One press on the caster of the Barrier-shaped spell, whose go the round of `hit` answers.
type Area {
  Area(
    why: String,
    outlives_caster: Bool,
    hit: List(cast_state.Struck),
    sees_at_go: List(Int),
    told_to: List(Int),
    listed: List(#(Int, List(Int))),
    debug: List(String),
  )
}

pub fn a_go_tells_a_row_aimed_at_the_area_to_each_ally_the_round_hit_lists_it_and_ends_it_with_the_cast_node_test() -> Nil {
  use <- owned_test.run(10_000)
  // A `StruckChange` aimed at the area (`PropertyModifier` of Barrier's row 92788, text 640545
  // "yourself and N allies in the targeted area") lands on each player the round hit that the
  // caster sees: the caster's connection tells each ally's, for the ally to hold for the
  // caster, in the round's order, and ends it with the cast's node on that ally.
  let kept = held_changes.KeptWhenUnseen
  let rows = [
    Area(
      why: "a round that hit two allies tells each its change in the round's order, kept when the caster no longer sees it (propertyFlags 0x100)",
      outlives_caster: True,
      hit: [
        ally_selected(unit_id: second_ally),
        ally_selected(unit_id: ally),
      ],
      sees_at_go: [ally, second_ally],
      told_to: [second_ally, ally],
      listed: [#(ally, [barrier_row]), #(second_ally, [barrier_row])],
      debug: [],
    ),
    Area(
      why: "an ally out of the caster's sight at the go is told nothing and a debug line says so; the ally in sight is told",
      outlives_caster: True,
      hit: [
        ally_selected(unit_id: ally),
        ally_selected(unit_id: second_ally),
      ],
      sees_at_go: [second_ally],
      told_to: [second_ally],
      listed: [#(ally, []), #(second_ally, [barrier_row])],
      debug: ["92788", "40", "not in the caster's sight"],
    ),
    Area(
      why: "a round that hit no ally tells nobody",
      outlives_caster: True,
      hit: [],
      sees_at_go: [ally, second_ally],
      told_to: [],
      listed: [],
      debug: [],
    ),
  ]
  list.each(rows, fn(row) {
    let sight = case row.outlives_caster {
      True -> kept
      False -> held_changes.EndsWhenUnseen
    }
    let spell = barrier_shaped(outlives_caster: row.outlives_caster)
    let #(state, pressed) =
      pressed_at_in(
        plans: plans_of(spell:),
        bag: bag_of_base_3,
        target: 7,
        state: cast_state.new(),
        caster: esper_seeing(players: [ally, second_ally]),
        at: 1000,
      )
    let #(_, went) =
      support.answered_each(
        caster: esper_seeing(players: row.sees_at_go),
        state:,
        effects: pressed,
        at: 1000,
        struck_of: fn(asked) {
          case asked.spell4_id == spell.spell4_id {
            True -> row.hit
            False -> []
          }
        },
        rolls: [],
        poses: dict.new(),
      )
    let id = support.pressed_id(effects: pressed)
    assert told(effects: went)
      == list.map(row.told_to, fn(unit_id) {
        barrier_change_of(unit_id:, cast_id: id, sight:, go_ms: 1000)
      })
      as row.why
    assert list.length(support.caster_change_starts(effects: went)) == 1
      as { row.why <> ": the caster's own part is its own change, told once" }
    assert list.filter(support.listed_by_unit(effects: went), fn(unit) {
        unit.0 != 7
      })
      == row.listed
      as {
        row.why
        <> ": the go's target info lists each ally the round hit, in unit id order, with the row for the ones it landed on"
      }
    let lines = support.debug_lines(effects: went)
    assert list.all(row.debug, fn(words) {
      list.any(lines, string.contains(_, words))
    })
      as { row.why <> ": the debug lines say " <> string.join(row.debug, ", ") }
    assert row.debug != [] || lines == []
      as { row.why <> ": and none is written otherwise" }
  })
  // The sight a change is held under: a spell without propertyFlags 0x100 ends the change when
  // the caster no longer sees the ally.
  let unkept = barrier_shaped(outlives_caster: False)
  let #(state, pressed) =
    pressed_at_in(
      plans: plans_of(spell: unkept),
      bag: bag_of_base_3,
      target: 7,
      state: cast_state.new(),
      caster: esper_seeing(players: [ally]),
      at: 1000,
    )
  let #(_, went) =
    support.answered_each(
      caster: esper_seeing(players: [ally]),
      state:,
      effects: pressed,
      at: 1000,
      struck_of: fn(_) { [ally_selected(unit_id: ally)] },
      rolls: [],
      poses: dict.new(),
    )
  let id = support.pressed_id(effects: pressed)
  assert told(effects: went)
    == [
      barrier_change_of(
        unit_id: ally,
        cast_id: id,
        sight: held_changes.EndsWhenUnseen,
        go_ms: 1000,
      ),
    ]
    as "a spell without propertyFlags 0x100: the change is held until the caster does not see the ally"
  // The ends: one end timer for each ally, at the go plus 5000 ms, and the cast's node on each
  // ally ends at the same time and tells nothing more.
  let spell = barrier_shaped(outlives_caster: True)
  let #(state, pressed) =
    pressed_at_in(
      plans: plans_of(spell:),
      bag: bag_of_base_3,
      target: 7,
      state: cast_state.new(),
      caster: esper_seeing(players: [ally, second_ally]),
      at: 1000,
    )
  let hit = [ally_selected(unit_id: second_ally), ally_selected(unit_id: ally)]
  let #(state, went) =
    support.answered_each(
      caster: esper_seeing(players: [ally, second_ally]),
      state:,
      effects: pressed,
      at: 1000,
      struck_of: fn(_) { hit },
      rolls: [],
      poses: dict.new(),
    )
  let id = support.pressed_id(effects: pressed)
  assert list.length(player_end_timers(state:)) == 2
    as "one end timer for each ally"
  let #(_, fired) =
    support.run_timers_each(
      caster: esper_seeing(players: [ally, second_ally]),
      state:,
      effects: list.append(pressed, went),
      from_ms: 1000,
      struck_of: fn(_) { [] },
    )
  assert list.filter_map(fired, fn(step) {
      case told(effects: step.1) {
        [] -> Error(Nil)
        ends -> Ok(#(step.0, ends))
      }
    })
    |> list.flat_map(fn(step) { list.map(step.1, fn(end) { #(step.0, end) }) })
    == [
      #(6000, barrier_change_ends(unit_id: second_ally, cast_id: id)),
      #(6000, barrier_change_ends(unit_id: ally, cast_id: id)),
    ]
    as "each ally's end is told once, 5000 ms after the go, in the round's order"
  // A second go of the cast tells the same sources again and replaces the end timers: the one
  // end of each ally is at the second go plus 5000 ms.
  let two_gos = Spell(..spell, phase_delays_ms: [0, 1000])
  let #(state, pressed) =
    pressed_at_in(
      plans: plans_of(spell: two_gos),
      bag: bag_of_base_3,
      target: 7,
      state: cast_state.new(),
      caster: esper_seeing(players: [ally]),
      at: 1000,
    )
  let #(state, went) =
    support.answered_each(
      caster: esper_seeing(players: [ally]),
      state:,
      effects: pressed,
      at: 1000,
      struck_of: fn(_) { [ally_selected(unit_id: ally)] },
      rolls: [],
      poses: dict.new(),
    )
  let id = support.pressed_id(effects: pressed)
  let #(_, fired) =
    support.run_timers_each(
      caster: esper_seeing(players: [ally]),
      state:,
      effects: list.append(pressed, went),
      from_ms: 1000,
      struck_of: fn(_) { [ally_selected(unit_id: ally)] },
    )
  assert list.filter_map(fired, fn(step) {
      case told(effects: step.1) {
        [] -> Error(Nil)
        changes -> Ok(#(step.0, changes))
      }
    })
    == [
      #(2000, [
        barrier_change_of(unit_id: ally, cast_id: id, sight: kept, go_ms: 2000),
      ]),
      #(7000, [barrier_change_ends(unit_id: ally, cast_id: id)]),
    ]
    as "the second go tells the same source again and the end timer is the second go's plus 5000 ms"
}

/// How one path ends the changes told to the allies a round hit: the spell, what the path does
/// to the state the go left (given the cast's id) and the effects it gives, the ends it tells
/// (given the cast's id), whether it writes the cast's 0x7fe, the allies whose 0x811 it writes,
/// and the ends the caster's leaving tells afterwards.
type AreaPath {
  AreaPath(
    why: String,
    spell: Spell,
    run: fn(State, Int) -> #(State, List(Effect)),
    ends: fn(Int) -> List(Effect),
    finishes: Bool,
    removed: List(Int),
    left_after: fn(Int) -> List(Effect),
  )
}

// ---- a change that lasts until removed, on an ally, under an aura ----

/// Spell4Effects 217926, Energy Auger's property row (Spell4 82830, aimed at the area, flags 4,
/// flags bit 2: until removed), whose aura runs 3000 ms and whose propertyFlags are 256 (0x100)
/// (`table_rows -- Spell4Effects 217926`, `-- Spell4 82830`).
const auger_row = 217_926

/// A planted spell shaped as Energy Auger's aura 82830: the allies' `StruckChange` of row 217926
/// that lasts until removed, aimed at the area alone, in a spell that goes `cast_time_ms` after
/// its start and runs out `aura_ms` after it (none: the spell is no aura).
fn auger_shaped(
  outlives_caster outlives_caster: Bool,
  aura_ms aura_ms: option.Option(Int),
) -> Spell {
  let until_removed =
    lasting.LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
  let row =
    spell_plan.PropertyModifier(
      ..support.armor_modifier_row(id: auger_row, aim: spell_plan.AimsAtArea),
      row: until_removed,
    )
  Spell(
    ..support.armor_spell(rows: [row]),
    spell4_id: Spell4Id(82_830),
    cast_time_ms: 500,
    aura_ms:,
    outlives_caster:,
  )
}

/// The change the go at `go_ms` tells the ally: listed until removed, as the caster's own node
/// lists the row.
fn auger_change_of(
  cast_id cast_id: Int,
  sight sight: held_changes.Sight,
  go_ms go_ms: Int,
) -> Effect {
  let assert spell_plan.StruckChange(modifier:, ..) =
    support.armor_modifier_row(id: auger_row, aim: spell_plan.AimsAtArea).change
    as "row 217926 is read as a StruckChange"
  cast_state.OtherPlayerChangeStarts(
    address: address(),
    source: source_of(cast_id:, effect_id: auger_row),
    change: held_changes.Property(modifier:),
    sight:,
    spell4_id: Spell4Id(82_830),
    effect: unit_casts.HeldEffect(
      effect_id: Spell4EffectsId(auger_row),
      starts_ms: go_ms,
      ends: unit_casts.UntilRemoved,
    ),
  )
}

fn auger_change_ends(cast_id cast_id: Int) -> Effect {
  cast_state.OtherPlayerChangeEnds(
    address: address(),
    source: source_of(cast_id:, effect_id: auger_row),
  )
}

/// The press of `spell` on the caster, whose go the round answers with the ally selected, run
/// until `until_ms`: the state, the cast's id and what each step tells the allies.
fn auger_run_until(
  spell spell: Spell,
  until_ms until_ms: Int,
) -> #(State, Int, List(#(Int, List(Effect)))) {
  let seen = esper_seeing(players: [ally])
  let #(state, pressed) =
    pressed_at_in(
      plans: plans_of(spell:),
      bag: bag_of_base_3,
      target: 7,
      state: cast_state.new(),
      caster: seen,
      at: 1000,
    )
  let #(state, fired) =
    support.run_timers_posed(
      caster: seen,
      state:,
      effects: pressed,
      from_ms: 1000,
      struck_at: fn(_, asked) {
        case asked.spell4_id == spell.spell4_id {
          True -> [ally_selected(unit_id: ally)]
          False -> []
        }
      },
      poses: dict.new(),
      until_ms: Some(until_ms),
    )
  #(
    state,
    support.pressed_id(effects: pressed),
    list.map(fired, fn(step) { #(step.at_ms, step.effects) }),
  )
}

/// Each step that tells the allies something: its time and what it tells.
fn auger_told_at(
  steps steps: List(#(Int, List(Effect))),
) -> List(#(Int, List(Effect))) {
  list.filter_map(steps, fn(step) {
    case told(effects: step.1) {
      [] -> Error(Nil)
      changes -> Ok(#(step.0, changes))
    }
  })
}

pub fn a_change_that_lasts_until_removed_on_an_ally_ends_at_the_end_of_the_aura_and_it_ends_once_by_whichever_path_comes_first_test() -> Nil {
  use <- owned_test.run(10_000)
  // The cast starts at 1000 and goes at 1500, so its aura of 3000 ms runs out at 4000: the
  // change told at the go has 2500 ms left (`0x1407180c0`: a buff is timed from the cast's start
  // by the spell's spellDuration).
  let kept = held_changes.KeptWhenUnseen
  let aura = auger_shaped(outlives_caster: True, aura_ms: Some(3000))
  let #(state, id, steps) = auger_run_until(spell: aura, until_ms: 1500)
  assert auger_told_at(steps: steps)
    == [#(1500, [auger_change_of(cast_id: id, sight: kept, go_ms: 1500)])]
    as "a go 500 ms after the cast's start tells the ally the change, listed until removed as the caster's own node lists the row"
  assert list.length(player_end_timers(state:)) == 1
    as "and arms one end timer for the change"
  // Run to the end: the timer and the node's end are both due at 4000.
  let #(_, _, whole) = auger_run_until(spell: aura, until_ms: 100_000)
  assert auger_told_at(steps: whole)
    == [
      #(1500, [auger_change_of(cast_id: id, sight: kept, go_ms: 1500)]),
      #(4000, [auger_change_ends(cast_id: id)]),
    ]
    as "the change ends once, at the aura's end 4000 (the go plus the 2500 ms left), though the timer and the node's end are both due then"
  // Each order of the two ends tells it once, and writes the cast's 0x7fe once.
  let both_orders = [
    #(
      "the timer first",
      list.append(player_end_timers(state:), nodes_end_timers(state:)),
    ),
    #(
      "the node's end first",
      list.append(nodes_end_timers(state:), player_end_timers(state:)),
    ),
  ]
  list.each(both_orders, fn(order) {
    let #(_, ended) =
      fired_in_order(state:, timers: order.1, seeing: [ally], at: 4000)
    assert told(effects: ended) == [auger_change_ends(cast_id: id)]
      as { order.0 <> ": the change ends once" }
    assert list.filter(
        support.finished_ids(support.writes(effects: ended)),
        fn(done) { done == id },
      )
      == [id]
      as { order.0 <> ": the cast's 0x7fe is written once" }
  })
  // The caster no longer sees the ally: a spell with propertyFlags 0x100 keeps the change
  // until its timer.
  let #(left, removal) =
    cast_proc.unit_removed(cast: state, unit_id: ally, now_ms: 2000)
  assert told(effects: removal) == []
    as "the ally leaving the caster's sight before the aura's end ends nothing for a spell with propertyFlags 0x100"
  let #(_, ended) =
    fired_in_order(
      state: left,
      timers: player_end_timers(state: left),
      seeing: [],
      at: 4000,
    )
  assert told(effects: ended) == [auger_change_ends(cast_id: id)]
    as "and the timer ends it at the aura's end, from the go's address"
  // A spell without propertyFlags 0x100 holds the change only while the caster sees the ally.
  let unkept = auger_shaped(outlives_caster: False, aura_ms: Some(3000))
  let #(state, id, _) = auger_run_until(spell: unkept, until_ms: 1500)
  let #(state, removal) =
    cast_proc.unit_removed(cast: state, unit_id: ally, now_ms: 2000)
  assert told(effects: removal) == [auger_change_ends(cast_id: id)]
    as "a spell without propertyFlags 0x100 ends the change when the ally leaves the caster's sight"
  let #(_, late) =
    fired_in_order(
      state:,
      timers: player_end_timers(state:),
      seeing: [],
      at: 4000,
    )
  assert told(effects: late) == []
    as "and its timer, late, finds nothing to end"
  // A go at or after the aura's end gives the row no end: nothing is told, no timer is armed and
  // a debug line says the row lasts until removed. So does a spell that is no aura.
  list.each(
    [
      #("an aura that runs out at the go", Some(500)),
      #("an aura that ran out before the go", Some(400)),
      #("a spell that is no aura", None),
    ],
    fn(row) {
      let spell = auger_shaped(outlives_caster: True, aura_ms: row.1)
      let #(state, _, steps) = auger_run_until(spell:, until_ms: 100_000)
      assert auger_told_at(steps: steps) == []
        as { row.0 <> ": the ally is told nothing" }
      assert player_end_timers(state:) == []
        as { row.0 <> ": and no end timer is armed" }
      assert list.any(
        list.flat_map(steps, fn(step) { support.debug_lines(effects: step.1) }),
        string.contains(_, "lasts until removed"),
      )
        as { row.0 <> ": and a debug line says the row lasts until removed" }
    },
  )
}
