//// The spells the server casts on the caster with a go of an ability where the client's
//// tables link none: the Proxies the `server_proxy` content table plants into the
//// ability trees (genesis_prime/game/spell_plan). The first is the Engineer's
//// Volatility: Pulse Blast's tooltips say it generates 15 Volatility, and the hidden
//// spell 42148 that holds the gain is cast by nothing the client holds
//// (`Spell4.42148`).
////
//// ```
//// content.load: rows ─▶ select(rows, tables, plans) ─▶ ServerProxies | refusals (the load stops)
//// each connection:  plans ─▶ planted_into(plans, proxies) ─▶ the plans the cast rule reads
////
//// Pulse Blast 42276, go 1 (1250 ms)
////   Proxy 95881 ─▶ 37302 (four goes, 1 ms apart; goes 1 to 3 strike the area)
////                    go 3, the last: server Proxy ─▶ child 42148 on the caster
////                            gain 95337: +15 of slot 1, behind prerequisite 903 (in combat)
//// ```
////
//// - **A row** names an ability by its Spell4Base, one of its goes by index, and the
////   spell cast on the caster at that go. It is a server choice, with its reason
////   (the table's `reason`), until a retail recording says otherwise.
//// - **The Proxy goes with the last go of the spell that strikes.** The Proxy is planted
////   into the first spell the row's go starts at once on the caster with no gate, which is
////   the spell that strikes when the go is a Proxy to its damage spell (Pulse Blast's
////   95881 to 37302, whose damage is in its goes 1 to 3: `Spell4Effects` 79090, 79092,
////   79093), and goes with that spell's last go. A creature that the first go struck has
////   then sent its answer and its `Threatened`, and sent its later answers after both
////   (genesis_prime/world_map/creature `struck`: one process, one order; the strike rounds
////   of a cast close in phase order), so prerequisite 903 (in combat) passes at the
////   opener. A go that starts no such spell takes the Proxy itself.
//// - **The opener's gap.** The opener gives 0 when the first strike's threat has not
////   reached the player by the last go's round: the go's selection finds no creature that
////   threatened (the creature left the area between go 1 and go 3), the rounds close at
////   their 1 s deadline before a late `Threatened`, or the creature died before the last
////   go. A host with a single go gives 0 at the opener, as the answer closes its round
////   before the threat. Turning the flag on from a `Landed` answer, or the answer carrying
////   the threat, would close the gap; it belongs to the step that reads the hit rows'
////   phases.
//// - **A row is refused** when its base has no plan (it is not a class's level-1
////   ability or innate), when its phase is not a go of that plan
////   (`spell_plan.go_times_ms`), or when its spell has no row or its tree cannot be
////   planned, for the plan's own reason; a tree that leads back to the ability or to the
////   spell that strikes fails as a cycle.
//// - **The areas are the client's.** The planted spell has no area row of its own, so
////   its go strikes nobody (genesis_prime/game/strike `select`).
////
//// What happens at each failure point:
////
//// | Point | What happens |
//// |---|---|
//// | a row names a base with no plan | the load stops, naming `server_proxy` and the row |
//// | a row names a phase the ability does not go at | the load stops, naming the row |
//// | a row names a Spell4 the tables lack, or a tree the plan refuses | the load stops, naming the row and the plan's reason |
//// | the plans hold the base's ability but no go starts a child at once | the Proxy is planted into the ability's own go |

import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/game/spell_plan.{type Plans, type Proxy, type Spell}
import genesis_prime/table/id.{Spell4BaseId}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result

/// One row of the server_proxy table as the load reads it: the ability's Spell4Base,
/// the go of its tree, and the spell cast on the caster at that go.
pub type Row {
  Row(spell4_base_id: Int, phase: Int, spell4_id: Int)
}

/// A spell planned to be cast at a go of an ability: the go, and the spell's own tree.
type Planned {
  Planned(phase: Int, spell: Spell)
}

/// Why a row is refused.
type NotPlanned {
  /// Its base is no class's level-1 ability or innate spell.
  NoPlan
  /// Its phase is no go of the ability, which goes `goes` times.
  NotAGo(phase: Int, goes: Int)
  /// Its spell has no row, or its tree cannot be planned.
  CannotPlan(error: spell_plan.PlanError)
}

fn describe(not_planned not_planned: NotPlanned) -> String {
  case not_planned {
    NoPlan ->
      "its base has no plan: it is not a level-1 ability or an innate spell of a class"
    NotAGo(phase:, goes:) ->
      "phase "
      <> int.to_string(phase)
      <> " is not a go of the ability, which goes "
      <> int.to_string(goes)
      <> " times"
    CannotPlan(error:) ->
      "its spell cannot be planned: " <> spell_plan.describe(error:)
  }
}

/// The server's Proxies of every ability, by Spell4Base id, as the load selected them.
pub opaque type ServerProxies {
  ServerProxies(by_base: Dict(Int, List(Planned)))
}

/// The Proxies of the rows, planned from the client's tables, or every refusal: a row
/// whose base has no plan in `plans`, whose phase is not a go of it, or whose spell
/// cannot be planned.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
  plans plans: Plans,
) -> Result(ServerProxies, List(Refusal)) {
  let sources = spell_plan.sources_of(tables:)
  let #(by_base, refusals) =
    list.fold(rows, #(dict.new(), []), fn(so_far, row) {
      let #(by_base, refusals) = so_far
      case planned_of(row:, tables:, sources:, plans:) {
        Ok(one) -> #(
          dict.upsert(by_base, row.spell4_base_id, fn(held) {
            list.append(result.unwrap(option.to_result(held, Nil), []), [one])
          }),
          refusals,
        )
        Error(not_planned) -> #(by_base, [
          Refusal(
            table: "server_proxy",
            row: RowName(name_of(row:)),
            rule: describe(not_planned:),
          ),
          ..refusals
        ])
      }
    })
  case refusals {
    [] -> Ok(ServerProxies(by_base:))
    [_, ..] -> Error(list.reverse(refusals))
  }
}

fn name_of(row row: Row) -> String {
  int.to_string(row.spell4_base_id)
  <> " "
  <> int.to_string(row.phase)
  <> " "
  <> int.to_string(row.spell4_id)
}

fn planned_of(
  row row: Row,
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  plans plans: Plans,
) -> Result(Planned, NotPlanned) {
  use ability <- result.try(
    spell_plan.in_plans(plans:, base: Spell4BaseId(row.spell4_base_id))
    |> result.replace_error(NoPlan),
  )
  let goes = spell_plan.go_count(spell: ability)
  use <- bool.guard(
    when: row.phase < 0 || row.phase >= goes,
    return: Error(NotAGo(phase: row.phase, goes:)),
  )
  let chain = case host_of(ability:, phase: row.phase) {
    Ok(host) -> [ability.spell4_id.value, host.spell.spell4_id.value]
    Error(Nil) -> [ability.spell4_id.value]
  }
  spell_plan.spell_alone(tables:, sources:, spell4_id: row.spell4_id, chain:)
  |> result.map(fn(spell) { Planned(phase: row.phase, spell:) })
  |> result.map_error(fn(error) { CannotPlan(error:) })
}

/// The Proxy of the ability that starts, at its go `phase`, a spell on the caster at once
/// with no gate: the first of them is the spell that strikes.
fn host_of(ability ability: Spell, phase phase: Int) -> Result(Proxy, Nil) {
  spell_plan.proxies_in_phase(spell: ability, phase:, spent: None)
  |> list.find(fn(proxy) {
    proxy.delay_ms == 0
    && case proxy.target, proxy.condition {
      spell_plan.OnCaster, spell_plan.Always -> True
      spell_plan.OnCaster, spell_plan.GatedOnCaster(..)
      | spell_plan.OnCaster, spell_plan.GatedOnTarget(..)
      | spell_plan.OnCaster, spell_plan.GatedOnCasterAndTarget(..)
      | spell_plan.OnEachStruck, _
      -> False
    }
  })
}

/// The index of a spell's last go; a spell with no go of its own (a charge held until its
/// release) has go 0.
fn last_go_of(spell spell: Spell) -> Int {
  int.max(0, spell_plan.go_count(spell:) - 1)
}

/// The plans with each ability's Proxies of the server's added to its tree: after the
/// ability's own Proxies, in the order of the rows.
pub fn planted_into(
  plans plans: Plans,
  proxies proxies: ServerProxies,
) -> Plans {
  dict.fold(proxies.by_base, plans, fn(plans, base, planned) {
    case dict.get(plans, base) {
      Ok(ability) ->
        dict.insert(plans, base, list.fold(planned, ability, planted_in))
      Error(Nil) -> plans
    }
  })
}

/// The ability with one Proxy added: into the spell its go starts at once, where it goes
/// at that spell's last go, or else into the ability at its own go.
fn planted_in(ability ability: Spell, planned planned: Planned) -> Spell {
  case host_of(ability:, phase: planned.phase) {
    Ok(host) ->
      spell_plan.Spell(
        ..ability,
        proxies: list.map(ability.proxies, fn(proxy) {
          case proxy.effect_id == host.effect_id {
            True ->
              spell_plan.Proxy(
                ..proxy,
                spell: spell_plan.Spell(
                  ..proxy.spell,
                  proxies: list.append(proxy.spell.proxies, [
                    spell_plan.server_proxy(
                      child: planned.spell,
                      phase_flags: spell_plan.phase_bit(phase: last_go_of(
                        spell: proxy.spell,
                      )),
                    ),
                  ]),
                ),
              )
            False -> proxy
          }
        }),
      )
    Error(Nil) ->
      spell_plan.Spell(
        ..ability,
        proxies: list.append(ability.proxies, [
          spell_plan.server_proxy(
            child: planned.spell,
            phase_flags: spell_plan.phase_bit(phase: planned.phase),
          ),
        ]),
      )
  }
}
