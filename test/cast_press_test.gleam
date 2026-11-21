//// What a press the server cannot build says: the refusal's log names what is missing
//// and no issue, and a press is logged once for its key.
////
//// - A refused right-click is answered with its result and logged once for its key
////   (`cast_press.not_built_refusal`); the key's family says which cast it was.
//// - The press's own path for an ability is `cast_test`'s
////   `a_non_normal_ability_is_refused_285_and_logged_once_test`.

import cast_support as support
import class_resource_support
import client_tables
import genesis_prime/game/cast/press as cast_press
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/class_resource
import genesis_prime/game/loadout
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan
import genesis_prime/message/cast_result
import genesis_prime/step.{LogWarning}
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import spell_tables
import unitest

/// One family of `Unbuilt` key: the key for Spell4 100, and the log its first press writes.
type Family {
  Family(name: String, key: cast_state.Unbuilt, first_log: String)
}

pub fn a_press_the_server_cannot_build_is_refused_and_logged_once_with_what_is_missing_test() -> Nil {
  use <- owned_test.run(5000)
  let why =
    "has a cast condition of the PrerequisiteType 118, which the server does not read"
  list.each(
    [
      Family(
        "a quest button's shortcut cast",
        cast_state.UnbuiltShortcut(spell4_id: 100),
        "the shortcut cast of Spell4 100 " <> why <> ": it is refused with 285",
      ),
      Family(
        "the use of an item's spell",
        cast_state.UnbuiltItemSpell(spell4_id: 100),
        "the use of an item whose spell is Spell4 100 "
          <> why
          <> ": it is refused with 285",
      ),
      Family(
        "an activate cast",
        cast_state.UnbuiltSpell(spell4_id: 100),
        "the activate cast of Spell4 100 " <> why <> ": it is refused with 285",
      ),
    ],
    fn(family) {
      let refuse = fn(state) {
        let assert Ok(taken) =
          cast_press.not_built_refusal(
            cast: state,
            client_cast_id: 7,
            spell4_id: 100,
            key: family.key,
            result: cast_result.IllegalSpellCast,
            why:,
          )
          as family.name
        taken
      }
      let #(state, first) = refuse(cast_state.new())
      assert support.logs(effects: first) == [#(LogWarning, family.first_log)]
        as family.name
      assert support.refusal_results(effects: first) == [285] as family.name
      let #(_, second) = refuse(state)
      assert support.logs(effects: second) == [] as family.name
      assert support.refusal_results(effects: second)
        == support.refusal_results(effects: first)
        as family.name
      assert !string.contains(string.lowercase(family.first_log), "issue")
        && !string.contains(family.first_log, "#")
        as family.name
    },
  )
}

pub fn the_abilities_a_hit_row_placement_held_back_are_accepted_by_a_press_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let plans = spell_plan.plans_with_later(tables:)
  list.each(
    list.append(
      spell_tables.flag_8_abilities,
      spell_tables.flag_0_or_2_abilities,
    ),
    fn(spell4_id) {
      let assert Ok(row) =
        list.find(spell_level.all(tables), fn(row) {
          row.spell4_id == spell4_id && loadout.is_class_ability(row:)
        })
        as "the ability is a class ability row"
      let assert Ok(spell4_row) = spell4.get(tables:, id: Spell4Id(spell4_id))
        as "the ability is a Spell4 row"
      let base = Spell4BaseId(spell4_row.spell4_base_id_base_spell)
      let assert Ok(ability) = spell_plan.in_plans(plans:, base:)
        as "the plans hold the ability"
      let resource = class_resource_support.resource_of(row.class_id)
      let caster =
        cast_state.Caster(
          ..support.caster(),
          abilities: [base],
          book: [base],
          resources: class_resource.new(
            resource: class_resource.Resource(..resource, start: resource.max),
            properties: class_resource_support.properties_of(
              class_id: row.class_id,
              changes: [],
              level: row.character_level,
            ),
          ),
          player: prerequisite.Player(
            ..support.caster().player,
            class_id: row.class_id,
            level: row.character_level,
          ),
          checker: prerequisite.Checker(
            items: [],
            book: [base],
            world_difficulty: 0,
          ),
        )
      let assert Ok(resolution) =
        cast_press.resolved(
          cast: cast_state.new(),
          caster:,
          bag_spell: ability.spell4_id,
          ability:,
        )
        as "the press resolves to a spell"
      let verdict =
        cast_press.verdict(
          cast: cast_state.new(),
          caster:,
          spell: resolution.spell,
          now_ms: 100_000,
          is_release: False,
          target_subject: None,
        )
      assert case verdict {
        cast_state.Accept(..) -> True
        cast_state.Refuse(..)
        | cast_state.NotBuilt(..)
        | cast_state.Hold(..)
        | cast_state.HoldForCast -> False
      }
        as "a press of the ability is accepted with its class resource full"
    },
  )
}
