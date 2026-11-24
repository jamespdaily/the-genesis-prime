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
//// - **The opener's flag.** The opener gives 0 when the first strike's threat has not
////   reached the player by the last go's round: the go's selection finds no creature that
////   threatened (the creature left the area between go 1 and go 3), the rounds close at
////   their 1 s deadline before a late `Threatened`, or the creature died before the last
////   go. A host with a single go gives 0 at the opener, as the answer closes its round
////   before the threat.
//// - **A row is refused** when its base has no plan (it is not a class's level-1
////   ability or innate), when its phase is not a go of that plan
////   (`spell_plan.go_count`, the length of `spell_plan.go_times_ms`), or when its spell has no row or its tree cannot be
////   planned, for the plan's own reason; a tree that leads back to the ability or to the
////   spell that strikes fails as a cycle.
//// - **Every tier plan of the ability is checked as tier 1's is**, since a player who holds a
////   tier casts that tier's plan (genesis_prime/game/held_tier): the phase is a go of it, its
////   Proxy finds the host tier 1's finds, and the child plans in its chain. A refusal names
////   the row and the tier. `planted_into` plants into whichever plan sits under the base.
//// - **The areas are the client's.** The planted spell has no area row of its own, so
////   its go strikes nobody (genesis_prime/game/strike `select`).
////
//// What happens at each failure point:
////
//// | Point | What happens |
//// |---|---|
//// | a row names a base with no plan | the load stops, naming `server_proxy` and the row |
//// | a row names a phase the ability does not go at | the load stops, naming the row |
//// | a tier of the ability does not go at the phase, or has another host for the Proxy | the load stops, naming the row and the tier |
//// | a row names a Spell4 the tables lack, or a tree the plan refuses | the load stops, naming the row and the plan's reason |
//// | the plans hold the base's ability but no go starts a child at once | the Proxy is planted into the ability's own go |

import genesis_prime/content/refusal.{type Refusal, Refusal, RowName}
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type Plans, type Proxy, type Spell}
import genesis_prime/game/spell_tier
import genesis_prime/gap
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
  /// The ability's plan holds a spell started at once for the Proxy to go with at the phase, and
  /// the plan of one of its tiers holds none (or the other way round), so the Proxy would be
  /// planted into another go for that tier than for tier 1.
  HostDiffers(phase: Int)
  /// Its spell has no row, or its tree cannot be planned.
  CannotPlan(error: spell_plan.PlanError)
  /// The plan of a tier of the ability (the tier's Spell4 row) is refused as `why`.
  InTier(tier: Int, spell4_id: Int, why: NotPlanned)
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
    HostDiffers(phase:) ->
      "phase "
      <> int.to_string(phase)
      <> " starts no spell at once on the caster in this plan, though the other plans of the ability do (or the other way round), so the Proxy would go with another go"
    CannotPlan(error:) ->
      "its spell cannot be planned: " <> spell_plan.describe(error:)
    InTier(tier:, spell4_id:, why:) ->
      "in tier "
      <> int.to_string(tier)
      <> " (Spell4 "
      <> int.to_string(spell4_id)
      <> "): "
      <> describe(not_planned: why)
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
  use planned <- result.try(planned_in(row:, tables:, sources:, ability:))
  use Nil <- result.map(tiers_planned(row:, tables:, sources:, ability:))
  planned
}

/// The row planned into every tier plan of its ability: a player who holds a tier casts that
/// tier's plan (genesis_prime/game/held_tier), so the phase must be a go of it, the Proxy must
/// find the host it finds in tier 1, and the spell must plan in the tier's own chain. A tier the
/// plans leave out is not checked: it plays a lower tier, which is.
fn tiers_planned(
  row row: Row,
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  ability ability: Spell,
) -> Result(Nil, NotPlanned) {
  let tiers = spell_tier.tiers(tables:)
  let tier_plans = spell_plan.tier_plans(tables)
  let base = Spell4BaseId(row.spell4_base_id)
  let has_host = result.is_ok(host_of(ability:, phase: row.phase))
  case spell_tier.highest(tiers:, base:) {
    Ok(highest) if highest >= 2 ->
      int.range(from: highest, to: 1, with: [], run: list.prepend)
      |> list.try_each(fn(tier) {
        let plan =
          spell_tier.spell4_id(tiers:, base:, tier:)
          |> result.try(fn(spell4_id) {
            spell_plan.in_tier_plans(tier_plans:, spell4_id:)
          })
        case plan {
          Error(Nil) -> Ok(Nil)
          Ok(plan) ->
            tier_checked(row:, tables:, sources:, plan:, has_host:)
            |> result.map_error(fn(why) {
              InTier(tier:, spell4_id: plan.spell4_id.value, why:)
            })
        }
      })
    Ok(_) | Error(Nil) -> Ok(Nil)
  }
}

/// The row planned into the plan of one tier, whose Proxy must find a host exactly when tier 1's
/// does (`has_host`).
fn tier_checked(
  row row: Row,
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  plan plan: Spell,
  has_host has_host: Bool,
) -> Result(Nil, NotPlanned) {
  use _planned <- result.try(planned_in(row:, tables:, sources:, ability: plan))
  case result.is_ok(host_of(ability: plan, phase: row.phase)) == has_host {
    True -> Ok(Nil)
    False -> Error(HostDiffers(phase: row.phase))
  }
}

/// The row planned into one plan of its ability: the phase must be one of its gos, and the
/// row's spell must plan in the chain of the ability and the spell it goes with.
fn planned_in(
  row row: Row,
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  ability ability: Spell,
) -> Result(Planned, NotPlanned) {
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
/// with no gate: the first of them is the spell that strikes. A periodic Proxy starts its
/// spell at each tick, not at the go, so it is never chosen.
fn host_of(ability ability: Spell, phase phase: Int) -> Result(Proxy, Nil) {
  spell_plan.in_phase(
    spell: ability,
    phase:,
    spent: None,
    as_kind: spell_plan.as_proxy,
  )
  |> list.find(fn(proxy) {
    proxy.delay_ms == 0
    && proxy.period == None
    && case proxy.target, proxy.condition {
      spell_plan.OnCaster, spell_plan.Always
      | spell_plan.OnPrimaryTarget, spell_plan.Always
      -> True
      spell_plan.OnCaster, spell_plan.GatedOnCaster(..)
      | spell_plan.OnCaster, spell_plan.GatedOnTarget(..)
      | spell_plan.OnCaster, spell_plan.GatedOnCasterAndTarget(..)
      | spell_plan.OnPrimaryTarget, spell_plan.GatedOnCaster(..)
      | spell_plan.OnPrimaryTarget, spell_plan.GatedOnTarget(..)
      | spell_plan.OnPrimaryTarget, spell_plan.GatedOnCasterAndTarget(..)
      | spell_plan.OnEachStruck, _
      | spell_plan.OnEachAlly, _
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
      spell_plan.with_proxies(
        spell: ability,
        proxies: list.map(
          spell_plan.payloads(spell: ability, as_kind: spell_plan.as_proxy),
          fn(proxy) {
            case proxy.effect_id == host.effect_id {
              True ->
                spell_plan.Proxy(
                  ..proxy,
                  spell: spell_plan.with_proxies(
                    spell: proxy.spell,
                    proxies: list.append(
                      spell_plan.payloads(
                        spell: proxy.spell,
                        as_kind: spell_plan.as_proxy,
                      ),
                      [
                        spell_plan.server_proxy(
                          child: planned.spell,
                          phase_flags: spell_effect.phase_bit(phase: last_go_of(
                            spell: proxy.spell,
                          )),
                        ),
                      ],
                    ),
                  ),
                )
              False -> proxy
            }
          },
        ),
      )
    Error(Nil) ->
      spell_plan.with_proxies(
        spell: ability,
        proxies: list.append(
          spell_plan.payloads(spell: ability, as_kind: spell_plan.as_proxy),
          [
            spell_plan.server_proxy(
              child: planned.spell,
              phase_flags: spell_effect.phase_bit(phase: planned.phase),
            ),
          ],
        ),
      )
  }
}

/// What a Proxy's opener does not do that the client's does.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Proxy openers",
      missing: "that a Proxy's opener flag is on when the first strike's threat reaches the player late: the opener gives 0 when the creature left the area between the first and last go, the rounds close at their deadline before the threat, the creature died before the last go, or the host has a single go",
    ),
  ]
}
