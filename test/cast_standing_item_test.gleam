//// A worn item's standing spell (`genesis_prime/game/cast` `standing_changed`) carries the item it
//// is worn from: the key of the standing cast holds it, its 0x7ff tells the item's level and its
//// children read the item's passed-in value. The spells here are planted except the Chua
//// deflector's, whose rows are the client's. Expected values come from these places.
//// - `opcode.0x7ff.caster_item_level`: the start's 16-bit item level is what the client's buff
////   tooltip reads in place of the player's level (`GetBuffTooltip` 0x1405ba2f0,
////   `EvaluateEffectToken` 0x1404de8d0), and the viewer in sight at the start is told the same
////   start as the owner; 0 is the client's own "no item".
//// - `opcode.0x7fe`: a cast the client holds lasts until its 0x7fe.
//// - `Spell4Effects` 216628 of Spell4 82325 (Item2 91747 and 85762, ItemSpecial 9402): a Proc of
////   kind 115 (shield depleted), at once, casting Spell4 82326 on the holder; 216629 of 82326 is
////   a Heal of 61.0 x the passed-in value (parameter type 18).
//// - The passed-in value is the family-33 curve at the level (GameFormula 991 below 50, 65 above;
////   `passed_in_value_test`): 5.0 + 0.3 x level, so 6.5 at the deflector's level 5 and 20.0 at
////   the player's level 50, and 20 x e^(0.01 x 66) = 38.6958 at Item2 85762's level 116.
//// - The server's choices, in the rule's doc: a standing cast of another item level is another
////   cast, and a cast lasting after a death keeps what its children read.

import cast_support as support
import fixture_tables
import genesis_prime/game/cast
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/proc as event_proc
import genesis_prime/game/unit_news.{CastStarted}
import genesis_prime/shared/damage
import genesis_prime/shared/effect_kind
import genesis_prime/shared/prerequisite
import genesis_prime/shared/spell_effect
import genesis_prime/shared/spell_plan.{type Spell}
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test
import properties_support

const spell = 250_101

/// The item level and passed-in value of Item2 91747 (power level 5, GameFormula 991: 5.0 + 0.3 x 5).
fn level_5() -> cast_state.PressedFrom {
  cast_state.Item(item_level: 5, passed_in: 6.5)
}

/// The item level and passed-in value of Item2 85762 (power level 116, GameFormula 65: 20 x e^0.66).
fn level_116() -> cast_state.PressedFrom {
  cast_state.Item(item_level: 116, passed_in: 38.6958)
}

fn wanting(
  from from: Option(cast_state.PressedFrom),
) -> List(cast_state.Standing) {
  [cast_state.Standing(spell: support.standing_spell(spell), from:)]
}

fn standing(
  cast cast: State,
  caster caster: Caster,
  wanted wanted: List(cast_state.Standing),
  at ms: Int,
) -> #(State, List(Effect)) {
  cast.standing_changed(cast:, caster:, wanted:, now: support.at(ms:))
}

fn message_ids(effects effects: List(Effect)) -> List(Int) {
  list.map(support.writes(effects:), fn(frame) { frame.message_id })
}

type Change {
  /// The second list changes no state and writes nothing.
  NothingChanges
  /// The first cast ends with its 0x7fe and the second starts with its 0x7ff, in that order.
  Swaps
}

pub fn a_standing_spell_is_keyed_by_its_spell_and_its_item_so_another_item_level_is_another_standing_spell_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster = support.caster()
  list.each(
    [
      #(
        "the same spell from the same item again",
        Some(level_5()),
        Some(level_5()),
        NothingChanges,
      ),
      #(
        "the same spell from an item of another level",
        Some(level_5()),
        Some(level_116()),
        Swaps,
      ),
      #("a spell from no item, then from an item", None, Some(level_5()), Swaps),
      #("a spell from an item, then from no item", Some(level_5()), None, Swaps),
    ],
    fn(row) {
      let #(why, first, second, change) = row
      let #(state, started) =
        standing(
          cast: cast_state.new(),
          caster:,
          wanted: wanting(from: first),
          at: 1000,
        )
      let assert [first_cast] =
        list.map(support.started_in(effects: started), fn(start) {
          start.cast_id
        })
        as why
      let #(again, effects) =
        standing(cast: state, caster:, wanted: wanting(from: second), at: 2000)
      case change {
        NothingChanges -> {
          assert again == state as why
          assert effects == [] as why
        }
        Swaps -> {
          assert message_ids(effects:) == [0x07FE, 0x07FF]
            as {
              why
              <> ": the 0x7fe of the first cast comes before the 0x7ff of the second"
            }
          assert support.finished_ids(support.writes(effects:)) == [first_cast]
            as why
          assert list.map(dict.values(again.standing), fn(key) { key.from })
            == [second]
            as { why <> ": the cast that stands is the second's" }
        }
      }
    },
  )
}

pub fn a_worn_spells_start_tells_the_items_level_to_the_owner_and_to_every_viewer_in_sight_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster = support.caster()
  list.each(
    [
      #("from the level 116 item", Some(level_116()), 116),
      #("from the level 5 item", Some(level_5()), 5),
      #("from no item (the innate passive, a level-scaled item)", None, 0),
    ],
    fn(row) {
      let #(why, from, level) = row
      let #(_, effects) =
        standing(
          cast: cast_state.new(),
          caster:,
          wanted: wanting(from:),
          at: 1000,
        )
      let assert [owner] = support.started_in(effects:) as why
      assert owner.caster_item_level == level
        as { why <> ": the owner's 0x7ff" }
      let told = support.tells(effects:)
      assert list.length(told) == 1 as { why <> ": the map is told once" }
      list.each(told, fn(tell) {
        let assert CastStarted(start:) = tell as why
        assert start.caster_item_level == level
          as { why <> ": the viewer's start" }
      })
    },
  )
}

pub fn a_holder_takes_the_item_its_live_cast_was_pressed_from_and_its_lingering_cast_keeps_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let caster = support.caster()
  let #(live, started) =
    standing(
      cast: cast_state.new(),
      caster:,
      wanted: wanting(from: Some(level_116())),
      at: 1000,
    )
  let assert [cast_id] =
    list.map(support.started_in(effects: started), fn(start) { start.cast_id })
  let assert Ok(before_go) = cast_state.holder_of(cast: live, cast_id:)
  assert before_go.handed_down == Some(level_116())
    as "the live cast hands down the item it was pressed from"
  let #(lingering, _) =
    support.answered_as(
      caster:,
      state: live,
      effects: started,
      at: 1000,
      struck: [],
      rolls: [],
    )
  let assert Ok(after_go) = cast_state.holder_of(cast: lingering, cast_id:)
  assert after_go.phase == cast_state.LastGoGone
    && after_go.handed_down == Some(level_116())
    as "the lingering cast it becomes keeps it"
  let from_button =
    cast_state.State(
      ..live,
      casts: dict.map_values(live.casts, fn(_, cast) {
        cast_state.Live(..cast, pressed: Some(cast_state.QuestButton))
      }),
    )
  let assert Ok(button) = cast_state.holder_of(cast: from_button, cast_id:)
  assert button.handed_down == None
    as "a cast pressed from a quest button hands nothing down: only the cast itself counts its objective"
  let #(dead, _) =
    cast.died(cast: lingering, caster:, now: support.at(ms: 2000))
  let assert Ok(restored) = cast_state.holder_of(cast: dead, cast_id:)
  assert restored.handed_down == Some(level_116())
    as "a death sets the cast aside and puts it back with the item"
  assert list.map(dict.values(dead.standing), fn(key) { key.from })
    == [Some(level_116())]
    as "and its key still names the item"
}

// ---- the children of the deflector's proc, from the client's rows ----

/// The player at level 50 whose own passed-in value is 20.0 (GameFormula 991: 5.0 + 0.3 x 50),
/// with its shield and health low enough that no heal is cut short, no Support Rating and no
/// heal scaling.
fn player_at_level_50() -> Caster {
  let caster = support.caster()
  cast_state.Caster(
    ..caster,
    player: prerequisite.Player(..caster.player, level: 50),
    stats: damage.attacker_of(
      properties: properties_support.fresh(level: 50),
      level: 50,
      passed_in: 20.0,
    ),
    vitals: damage.Vitals(
      health: 1000,
      max_health: 100_000,
      shield: 0,
      max_shield: 100_000,
    ),
  )
}

/// The deflector's root as the client's rows plan it.
fn deflector_root() -> Spell {
  let assert Ok(root) =
    dict.get(spell_plan.standing_plans(fixture_tables.shared()), 82_325)
    as "Spell4 82325 is a planned standing root"
  root
}

/// The same root with the delay of its proc row changed.
fn with_proc_delay(root root: Spell, delay_ms delay_ms: Int) -> Spell {
  spell_plan.Spell(
    ..root,
    effects: list.map(root.effects, fn(effect) {
      case effect.kind {
        spell_plan.ProcEffect(row) ->
          spell_effect.PlannedEffect(
            ..effect,
            kind: spell_plan.ProcEffect(spell_plan.ProcRow(..row, delay_ms:)),
          )
        _ -> effect
      }
    }),
  )
}

/// The blow that takes the shield from above 0 to 0 (Proc kind 115).
fn shield_depleting_blow() -> cast_proc.BlowTaken {
  cast_proc.BlowLanded(
    striker: 31,
    spell: event_proc.EventSpell(
      spell4_id: Spell4Id(5649),
      spell4_base_id: Spell4BaseId(4947),
      groups: [],
      school: 1,
    ),
    lowered: True,
    critical: False,
    shield_depleted: True,
  )
}

/// What the child of the deflector's proc does once a shield-depleting blow fires the proc: its
/// 0x7ff tells this level and its go heals the caster's health by this amount.
type Child {
  Child(level: Int, heal: Int)
}

/// The child's start and heal after the blow at 2000 ms, the proc's delay passing first when it
/// has one.
fn child_after_the_blow(
  root root: Spell,
  from from: Option(cast_state.PressedFrom),
  delay_ms delay_ms: Int,
) -> Child {
  let caster = player_at_level_50()
  let #(state, started) =
    standing(
      cast: cast_state.new(),
      caster:,
      wanted: [cast_state.Standing(spell: root, from:)],
      at: 1000,
    )
  let #(state, _) =
    support.answered_as(
      caster:,
      state:,
      effects: started,
      at: 1000,
      struck: [],
      rolls: [],
    )
  let #(state, blown) =
    cast.blow_taken(
      cast: state,
      caster:,
      now: support.at(ms: 2000),
      blow: shield_depleting_blow(),
    )
    |> fn(step) { support.then_procs(step:, caster:, at: 2000) }
  let #(state, effects) = case delay_ms {
    0 -> #(state, blown)
    _ -> {
      assert support.started_in(effects: blown) == []
        as "a proc with a delay starts nothing at the blow"
      let assert [#(timer, wait)] = support.started_timers(effects: blown)
        as "and waits its delay"
      assert wait == delay_ms
      support.fired_raw_as(caster:, state:, timer:, at: 2000 + delay_ms)
    }
  }
  let assert [child] =
    list.filter(support.started_in(effects:), fn(start) {
      start.spell4_id == 82_326
    })
    as "the proc starts its spell 82326"
  let #(_, gone) =
    support.answered_as(
      caster:,
      state:,
      effects:,
      at: 2000 + delay_ms,
      struck: [],
      rolls: [],
    )
  let assert [#(_, cast_state.Heal(vital: effect_kind.Health, amount:))] =
    support.caster_change_starts(effects: gone)
    as "the child's go heals the caster's health"
  Child(level: child.caster_item_level, heal: amount)
}

pub fn a_proc_child_of_a_worn_items_spell_heals_by_the_items_level_not_the_players_test() -> Nil {
  use <- owned_test.run(10_000)
  // Row 216629 heals 61.0 x the passed-in value; the caster has no Support Rating and no heal
  // scaling, so the amount is that product alone, rounded half away from zero.
  list.each(
    [
      #(
        "Item2 91747, power level 5: 61 x 6.5 = 396.5",
        deflector_root(),
        Some(level_5()),
        0,
        Child(level: 5, heal: 397),
      ),
      #(
        "Item2 85762, power level 116: 61 x 38.6958 = 2360.45",
        deflector_root(),
        Some(level_116()),
        0,
        Child(level: 116, heal: 2360),
      ),
      #(
        "a level-scaled item or the innate hands down none: the player's own 20.0, 61 x 20 = 1220",
        deflector_root(),
        None,
        0,
        Child(level: 0, heal: 1220),
      ),
      #(
        "a planted delay of 500 ms: the delayed fire reads the item as the immediate one does",
        with_proc_delay(root: deflector_root(), delay_ms: 500),
        Some(level_5()),
        500,
        Child(level: 5, heal: 397),
      ),
    ],
    fn(row) {
      let #(why, root, from, delay_ms, expected) = row
      let child = child_after_the_blow(root:, from:, delay_ms:)
      assert child.level == expected.level as { why <> ": the child's 0x7ff" }
      assert child.heal == expected.heal as { why <> ": the child's heal" }
    },
  )
}
