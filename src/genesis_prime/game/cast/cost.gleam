//// Whether a press may start a cast: the spell's conditions, what it costs and the verdict of each check.
////
//// - **The refusals** are the client's own checks, answered 0x7fc with the
////   client's result and clearing the client's global cooldown: 57 for a dead
////   caster's press of a spell whose caster condition row has the dead bit, and
////   58 for a living caster's press of one whose row asks for a dead caster
////   (`Spell4.spell4ConditionsIdCaster`, `cast.dead_player`; the row's other
////   conditions are not checked); 13 while the
////   caster's current cast is live (below); the caster result of the lowest state the
////   caster holds that the spell's Spell4CCConditions caster row masks (73 for Stun,
////   302 for Ability Restriction, and so on, `crowd_control.caster_result`) while a cast
////   of the caster holds it on the caster, checked after 13 and before the cooldowns
////   (`CheckSpellCCConditions`, `0x1403b2c40`; `0x1403afb10.order`); 14 while the global cooldown has more
////   than 500 ms left, for kinds 0 and 2; 15 while the spell's own cooldown has
////   more than 500 ms left (`0x1403b14c0`); a caster requirement's result when the
////   caster's resource fails it and the spell's waiver does not pass (`0x1403b1780`,
////   `Rampage` 51 below 250 Kinetic Energy unless the caster is under Overdrive 42908);
////   50 + the resource slot for a cost the caster's class
////   resource cannot pay (`0x1403b3320`, `0x1405e7980`,
////   `Spell4CastResult.vital_cost`); 169 for a spell that needs the weapon when
////   slot 16 holds none (`0x1403afb10`); 151 for a spell whose CasterCast fails and
////   281 for one whose TargetCast does, the last checks of the press (`0x1403ace00`,
////   below); and 285 for a spell whose method is not
////   one of Normal, Multiphase, Channeled, RapidTap and ChargeRelease
////   (`Spell.CodeEnumCastMethod`). A cost in a vital the server does not hold, a cast
////   condition it cannot read and a method not built are each logged once on the
////   connection for the coverage measure. The caster's checks run in the client's
////   order (`Verdict`). A class vital cost (types 4, 12, 13, 14, 18 and 19 on a Spell4
////   row, 18 and 19 on a threshold row) is looked up in the casting class's own slots
////   (`Class.vitalEnumResource00` to `07`, `class_resource.class_cost` and
////   `row_class_cost`): the innate cost passes at the first slot naming the vital whose
////   value less the cost lies in [0, that slot's maximum] and pays from it, and is
////   refused with the last such slot's 50 + slot (177 for slot 7); a class with no slot
////   naming the vital passes and pays nothing (`0x1405e7980`). A threshold row's cost
////   passes at most the whole points of the first slot holding above 0, with no maximum,
////   and is refused with that slot's result, or 175 when the vital's slots hold nothing
////   (`0x1403c0620`, `0x1405e78c0`, `0x1403d3650`).
//// - **The cast conditions** are the spell's prerequisiteIdCasterCast and
////   prerequisiteIdTargetCast, which the client checks after every other check of the
////   press, CasterCast first (`0x1403ace00`, `Spell4.prerequisiteIdCasterCast`), so a press
////   that fails several gets the client's first failure; the check runs only on the path
////   that would accept, since a press the client queues (317) is sent unchecked. The first
////   unit is the caster, and the second unit too: the server reads no target and the client
////   makes the caster the target of every spell it presses. A press held for a cooldown or
////   behind the current cast is checked when it starts, as one the client sent unchecked is
////   (`Spell4.prerequisiteIdCasterCast`), and a held key's repeat each time. A spell with a
////   caster requirement block and propertyFlags bit 2 is not gated by its CasterCast: that
////   prerequisite only waives a failed requirement (`0x1403b1780`). A condition of a type
////   the server does not read, or a type 37 roll (a press draws none), refuses with the
////   check's result and a warning once for the spell (the server's choice, as for a cost in
////   a vital it does not hold).
//// - **A cost is checked at the accept and paid at the cast's first go** (`Pay`): the
////   client checks a cost only before it sends a press, lowers no resource itself and
////   shows only what 0x935 says, so when to pay is the server's
////   (`Spell4.innateCost0.timing`), and a retail video shows the Actuators of Gamma
////   Rays dropping when its beams go off. The accept checks the costs against the slot
////   less what the live casts have reserved (`unreserved`) and keeps them on its live
////   cast (`Live.reserved`); the first go pays them as its strike begins, so the round's
////   hits are always paid for and the go's gates and gains read the paid caster, as
////   one 0x935. A cast that ends before its first go (a 0x801, death, leaving) pays
////   nothing, and its reservation ends with it. A spell whose first go is at once, or
////   that has no go of its own, pays at its accept, in the step of its check
////   (`pays_at_accept`). A second press taken in the same step is checked against what
////   the first left (genesis_prime/game/class_resource).
//// - **A spend of every point held** (`spell_plan.SpendAllCost`, genesis_prime/game/spend):
////   the check is of the base cost alone, as the client's is (`0x1403b3320`), and the
////   accept then reserves every whole point the slot holds less the reserved, which the
////   first go takes and whose new value the client is sent (`opcode.0x935`). The points
////   above the base cost are the cast's n, fixed at the accept (at the start of a held
////   press, which is checked and reserved then), kept on
////   the live cast, and read at each go: the go's strike (`GoAsked.spent`), gains and
////   Proxies are the ones whose tag holds for n. A child a Proxy starts has no n and
////   keeps every effect. A cost with an EMM id the server does not read
////   (`spell_plan.UnreadSpendCost`) is refused with the cost's result and logged once.

import genesis_prime/game/cast/state.{
  type Caster, type CostRefusal, type Effect, type Paid, type State,
  type Verdict, Activated, CancelTimer, Caster, CasterChangeEnds,
  CasterChangeStarts, CreatureDespawns, ForcedMoveStarts, Gain, Log, NotBuilt,
  Paid, Pay, PrerequisitesIssue, Refuse, Send, ShortcutCast, StartTimer,
  StealthChanged, Strike, TargetChangeEnds, TargetChangeStarts, Tell, TickStrike,
  Unheld, Unpaid, UnreadSpend,
}
import genesis_prime/game/class_resource.{type Payment, type Resources, Payment}
import genesis_prime/game/cooldown
import genesis_prime/game/crowd_control
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/message/cast_result
import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The result the caster's own held states give a press whose caster conditions mask one
/// of them: the lowest masked state's Caster_CannotBe result (`CheckSpellCCConditions`,
/// `0x1403b2c40`, called by `CheckCastCaster` at `0x1403affa2`), none when the mask holds
/// none of them. Gap: the client's cast request word at 0x48 is read as 0 for every
/// press, so the check always applies; the client sets it for the presses the ride spells
/// make, which this server does not read.
pub fn restricted(
  cast cast: State,
  spell spell: Spell,
) -> Option(cast_result.CastResult) {
  dict.values(cast.restrictions)
  |> list.map(fn(restriction) { restriction.state })
  |> crowd_control.first_masked(mask: spell.caster_cc_mask, held: _)
  |> result.map(fn(state) {
    cast_result.from_value(crowd_control.caster_result(state:))
  })
  |> option.from_result
}

/// Ends a verdict with the refusal `refusal` names, or goes on when it names none.
pub fn refuse_when(
  refusal refusal: Option(cast_result.CastResult),
  otherwise otherwise: fn() -> Verdict,
) -> Verdict {
  case refusal {
    Some(result) -> Refuse(result:)
    None -> otherwise()
  }
}

/// What a Prerequisite column of the spell makes of the subject; a spell with none passes.
pub fn column_verdict(
  gate gate: Option(prerequisite.Prerequisite),
  subject subject: prerequisite.Subject,
) -> prerequisite.Verdict {
  case gate {
    None -> prerequisite.Passes
    Some(gate) -> prerequisite.check(prerequisite: gate, subject:)
  }
}

/// The refusal a cast condition gives when it fails or cannot be read, none when it
/// passes or the spell has none.
pub fn condition_verdict(
  gate gate: Option(prerequisite.Prerequisite),
  subject subject: prerequisite.Subject,
  result result: cast_result.CastResult,
) -> Option(Verdict) {
  case column_verdict(gate:, subject:) {
    prerequisite.Passes -> None
    prerequisite.Fails -> Some(Refuse(result:))
    prerequisite.NotRead(prerequisite_type:) ->
      Some(NotBuilt(
        result:,
        why: "has a cast condition of the PrerequisiteType "
          <> int.to_string(prerequisite_type)
          <> ", which the server does not read",
        issue: PrerequisitesIssue,
      ))
  }
}

/// Whether the caster's slot meets the requirement: its amount, or its percentage
/// of its maximum, compared with the value by the eval (`0x1403b1780`,
/// `0x1407a1750`). The client divides by a maximum of 0 as a float: a slot above 0
/// is then infinitely many percent, and one at 0 is no number, which every
/// comparison fails.
pub fn meets(
  requirement requirement: spell_plan.Requirement,
  resources resources: Resources,
) -> Bool {
  let current = class_resource.value(resources:, slot: requirement.slot)
  let max = class_resource.max(resources:, slot: requirement.slot)
  let value = int.to_float(requirement.value)
  case requirement.measure, max == 0.0 {
    spell_plan.Amount, _ ->
      compares(comparison: requirement.comparison, current:, value:)
    spell_plan.PercentOfMax, False ->
      compares(
        comparison: requirement.comparison,
        current: current *. 100.0 /. max,
        value:,
      )
    spell_plan.PercentOfMax, True ->
      current >. 0.0
      && case requirement.comparison {
        spell_plan.Greater | spell_plan.AtLeast -> True
        spell_plan.Equal
        | spell_plan.Less
        | spell_plan.AtMost
        | spell_plan.NeverPasses(..) -> False
      }
  }
}

/// CompareByEval (`0x1407a1750`): the current value against the requirement's.
fn compares(
  comparison comparison: spell_plan.Comparison,
  current current: Float,
  value value: Float,
) -> Bool {
  case comparison {
    spell_plan.Equal -> current == value
    spell_plan.Greater -> current >. value
    spell_plan.AtLeast -> current >=. value
    spell_plan.Less -> current <. value
    spell_plan.AtMost -> current <=. value
    spell_plan.NeverPasses(..) -> False
  }
}

/// The spell's costs checked in order against the caster's resources, each against
/// the slots as they stand before the press, as the client checks them
/// (`0x1403b1de0`): the first refusal, or what the press pays. A cost that spends
/// every point held is checked against its base amount alone (`0x1403b3320`) and
/// pays every whole point the slot holds; the points above the base are the spend,
/// the first such cost's when the spell has several.
pub fn costs_paid(
  costs costs: List(spell_plan.Cost),
  resources resources: Resources,
) -> Result(Paid, CostRefusal) {
  list.try_fold(costs, Paid(payments: [], spent: None), fn(paid, cost) {
    cost_taken(paid:, cost:, resources:)
  })
  |> result.map(fn(paid) { Paid(..paid, payments: list.reverse(paid.payments)) })
}

/// One cost checked and added to what the press pays.
fn cost_taken(
  paid paid: Paid,
  cost cost: spell_plan.Cost,
  resources resources: Resources,
) -> Result(Paid, CostRefusal) {
  case cost {
    spell_plan.UnheldCost(result:) -> Error(Unheld(result:))
    spell_plan.UnreadSpendCost(result:, emm_id:) ->
      Error(UnreadSpend(result:, emm_id:))
    spell_plan.SlotCost(slot:, amount:, result:) ->
      case whole_points(resources:, slot:) < int.absolute_value(amount) {
        True -> Error(Unpaid(result:))
        False -> Ok(adding(paid:, payment: Payment(slot:, amount:)))
      }
    spell_plan.SpendAllCost(slot:, amount:, result:) ->
      spend_all(paid:, slot:, amount:, result:, resources:)
    spell_plan.ClassVitalCost(vital:, amount:) ->
      class_cost_taken(
        paid:,
        amount:,
        checked: class_resource.class_cost(resources:, vital:, amount:),
      )
    spell_plan.RowClassCost(vital:, amount:) ->
      class_cost_taken(
        paid:,
        amount:,
        checked: class_resource.row_class_cost(resources:, vital:, amount:),
      )
  }
}

/// A class cost's check added to what the press pays: paid from the slot that passed,
/// nothing paid when the class has no slot for the vital, refused with the check's
/// result otherwise.
fn class_cost_taken(
  paid paid: Paid,
  amount amount: Int,
  checked checked: Result(Option(Int), Int),
) -> Result(Paid, CostRefusal) {
  case checked {
    Ok(Some(slot)) -> Ok(adding(paid:, payment: Payment(slot:, amount:)))
    Ok(None) -> Ok(paid)
    Error(result) -> Error(Unpaid(result:))
  }
}

/// A cost that spends every point held: refused when the slot holds less than the
/// base amount, else it takes every whole point and the points above the base are
/// the spend, kept from the first such cost.
fn spend_all(
  paid paid: Paid,
  slot slot: Int,
  amount amount: Int,
  result result: Int,
  resources resources: Resources,
) -> Result(Paid, CostRefusal) {
  let held = whole_points(resources:, slot:)
  let base = int.absolute_value(amount)
  use <- bool.guard(when: held < base, return: Error(Unpaid(result:)))
  let paid = adding(paid:, payment: Payment(slot:, amount: held))
  Ok(Paid(..paid, spent: option.or(paid.spent, Some(held - base))))
}

/// The payment added to what the press pays, newest first.
fn adding(paid paid: Paid, payment payment: Payment) -> Paid {
  Paid(..paid, payments: [payment, ..paid.payments])
}

/// The whole points the slot holds, as an absolute value (`0x1403b3320` reads a slot
/// as a whole number).
fn whole_points(resources resources: Resources, slot slot: Int) -> Int {
  float.truncate(class_resource.value(resources:, slot:))
  |> int.absolute_value
}

/// The effect that pays these costs, none for no costs.
pub fn paying(payments payments: List(Payment)) -> List(Effect) {
  case payments {
    [] -> []
    [_, ..] -> [Pay(payments:)]
  }
}

/// Whether a press's costs are paid at its accept: a cast whose first go is at once
/// and a cast with no go of its own (a charge held until its release) have no later
/// moment to pay at. Any other cast reserves its costs at the accept and pays them
/// at its first go.
pub fn pays_at_accept(spell spell: Spell) -> Bool {
  case spell_plan.go_times_ms(spell:) {
    [] | [0, ..] -> True
    [_, ..] -> False
  }
}

/// The caster's resources less what the live casts have reserved: what a press's
/// costs are checked against, so a second press cannot be accepted on points a first
/// cast will pay at its go.
pub fn unreserved(
  cast cast: State,
  resources resources: Resources,
) -> Resources {
  class_resource.paid(
    resources:,
    payments: list.flat_map(dict.values(cast.casts), fn(live) { live.reserved }),
  )
}

/// The caster with the payments and gains among the effects taken into its
/// resources, so a second press of the same step, such as a held press a go
/// releases, is checked against what the first left.
pub fn after_payments(
  caster caster: Caster,
  effects effects: List(Effect),
) -> Caster {
  Caster(
    ..caster,
    resources: list.fold(effects, caster.resources, fn(resources, effect) {
      case effect {
        Pay(payments:) -> class_resource.paid(resources:, payments:)
        Gain(gains:) -> class_resource.gain(resources:, gains:).0
        Send(..)
        | Tell(..)
        | StartTimer(..)
        | CancelTimer(..)
        | Log(..)
        | Strike(..)
        | TickStrike(..)
        | CasterChangeStarts(..)
        | CasterChangeEnds(..)
        | TargetChangeStarts(..)
        | TargetChangeEnds(..)
        | ForcedMoveStarts(..)
        | CreatureDespawns(..)
        | StealthChanged(..)
        | Activated(..)
        | ShortcutCast(..) -> resources
      }
    }),
  )
}

/// What is left of the global cooldown, when it refuses the spell, and of the
/// spell's own cooldown, in milliseconds.
pub fn cooldown_left_ms(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> #(Int, Int) {
  let global_left = case
    spell.global_cooldown.refused_while_running,
    option.map(cast.global_cooldown_ends_ms, fn(ends_ms) {
      int.max(0, ends_ms - now_ms)
    })
  {
    True, Some(left_ms) -> left_ms
    True, None | False, Some(_) | False, None -> 0
  }
  let own_left =
    cooldown.left_ms(book: cast.cooldowns, spell4_id: spell.spell4_id, now_ms:)
  #(global_left, own_left)
}

/// The methods the rule casts; a spell of any other is refused 285.
///
/// A press of a spell of castMethod 5 (`ClientSideInteraction`) is refused too, and only
/// the activate cast runs one (`cast_press.activation_spell`). Gap: the client opens its interaction
/// on the 0x7fd of any pending cast of the player, an ability's or an item's as well
/// (`opcode.0x7fd.csi`), so a pressed castMethod 5 spell is a cast the client would run;
/// the server does not build it, a gap in the issue "Spells work in depth on the real
/// client: cast times, telegraphs, buffs, crowd control and ticking effects".
pub fn is_built(method: spell_plan.CastMethod) -> Bool {
  case method {
    spell_plan.Normal
    | spell_plan.Multiphase
    | spell_plan.Channeled
    | spell_plan.RapidTap
    | spell_plan.ChargeRelease -> True
    spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> False
  }
}

pub fn lacks_the_weapon(spell spell: Spell, caster caster: Caster) -> Bool {
  case spell.weapon {
    spell_plan.PrimaryWeapon -> option.is_none(caster.weapon)
    spell_plan.Refused -> True
    spell_plan.NoWeaponNeeded | spell_plan.OtherWeaponSlot(..) -> False
  }
}

/// Whether the caster's current cast is live and blocks a press: a live cast of a
/// spell that leaves the caster free never does (`0x1403afb10`,
/// `Spell4.propertyFlags`).
pub fn casting(cast: State) -> Bool {
  case cast.current {
    None -> False
    Some(cast_id) ->
      case dict.get(cast.casts, cast_id) {
        Ok(live) -> !live.spell.free_while_live
        Error(Nil) -> False
      }
  }
}
