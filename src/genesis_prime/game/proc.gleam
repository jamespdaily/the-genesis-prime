//// The rule of a held Proc effect (`Spell4Effects.effectType.14`): whether one event of its
//// holder fires it. A pure function of the proc's plan, its fires so far, the event and the
//// draws it was given: the cast rule (genesis_prime/game/cast) keeps the fires, raises the
//// events and starts the spells, and the connection draws the random values. No client code
//// reads a Proc row (`Spell4Effects.effectType.14.client_evaluation`), so each reading is
//// the one the plan marks (genesis_prime/shared/spell_plan).
////
//// The checks run in a fixed order: the limit, the filter, the holder gate, the event gate
//// and the chance. Each proc that matches the event's trigger takes its draw and its gate
//// rolls whether or not an earlier check stopped it, so the number to draw before a pass is
//// known (`draws_needed`).

import genesis_prime/random
import genesis_prime/shared/prerequisite
import genesis_prime/shared/spell_plan.{type ProcRow}
import genesis_prime/table/id.{type Spell4BaseId, type Spell4Id}
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// An event of a proc's holder. `other_unit` is the unit the event concerns besides the
/// holder, the creature a hit struck, none for stealth, combat, death and a heal;
/// `spell` is the spell that made it, none for an event no spell makes. `holder` is the
/// unit the proc is held on when it is not the caster's own, the ally whose blow raised
/// the event, and none for the caster's own events.
pub type Event {
  Event(
    trigger: spell_plan.Trigger,
    other_unit: Option(Int),
    spell: Option(EventSpell),
    holder: Option(Int),
  )
}

/// The spell of an event: its Spell4, its Spell4Base (`Spell4.spell4BaseIdBaseSpell`), its
/// spell groups (`Spell4GroupList`) and its school (`Spell4Base.school`).
pub type EventSpell {
  EventSpell(
    spell4_id: Spell4Id,
    spell4_base_id: Spell4BaseId,
    groups: List(Int),
    school: Int,
  )
}

/// What one event gives a proc.
pub type Verdict {
  /// The proc fires: its spell goes to the unit `at` after `delay_ms`.
  Fires(at: Int, delay_ms: Int)
  /// The proc has fired as often as its limit allows.
  OutOfLimit
  /// The event's spell is not one the proc's filter names, or the event has none.
  FilteredOut
  /// The holder gate fails against the holder.
  HolderGateFails
  /// The event gate fails against the event's unit.
  EventGateFails
  /// A gate's condition is of a type the server does not read, so it cannot tell, and
  /// the proc does not fire.
  CannotTell(why: String)
  /// The draw is not below the chance.
  MissedChance
}

/// What a proc takes for one event whose trigger it matches: chance draws (one 32-bit
/// word, none for a chance of 1.0) and gate rolls (those the holder gate's and the event
/// gate's type 37 conditions take, `prerequisite.rolls_needed`).
pub fn draws_needed(row row: ProcRow) -> #(Int, Int) {
  let words = case row.chance >=. 1.0 {
    True -> 0
    False -> 1
  }
  #(words, gate_rolls(gate: row.holder_gate) + gate_rolls(gate: row.event_gate))
}

fn gate_rolls(gate gate: Option(prerequisite.Prerequisite)) -> Int {
  case gate {
    Some(gate) -> prerequisite.rolls_needed(prerequisite: gate)
    None -> 0
  }
}

/// The fires of a proc that still count at `now_ms`: for a window, those made less than
/// `window_ms` ago (a fire exactly `window_ms` ago is outside the window); for a proc's
/// life, all of them.
pub fn counted(
  limit limit: spell_plan.ProcLimit,
  fires_ms fires_ms: List(Int),
  now_ms now_ms: Int,
) -> List(Int) {
  case limit {
    spell_plan.InWindow(window_ms:, ..) ->
      list.filter(fires_ms, fn(fired_ms) { fired_ms > now_ms - window_ms })
    spell_plan.ForLife(..) -> fires_ms
  }
}

fn count_of(limit limit: spell_plan.ProcLimit) -> Int {
  case limit {
    spell_plan.InWindow(count:, ..) | spell_plan.ForLife(count:) -> count
  }
}

/// What `event` gives the proc `row`, which the holder `holder_unit` holds and has fired
/// at `fires_ms` (`counted`). `holder_subject` is the holder as a prerequisite sees it and
/// `event_subject` the event's unit, the other unit or, for an event with none, the
/// holder; `draw` is the chance word (none for a chance of 1.0) and `rolls` the gate rolls
/// (`draws_needed`, the holder gate's first).
pub fn decide(
  row row: ProcRow,
  fires_ms fires_ms: List(Int),
  now_ms now_ms: Int,
  event event: Event,
  holder_unit holder_unit: Int,
  holder_subject holder_subject: prerequisite.Subject,
  event_subject event_subject: prerequisite.Subject,
  draw draw: Option(Int),
  rolls rolls: List(Int),
) -> Verdict {
  let holder_rolls = gate_rolls(gate: row.holder_gate)
  let #(for_holder, for_event) = list.split(rolls, holder_rolls)
  let in_limit =
    list.length(counted(limit: row.limit, fires_ms:, now_ms:))
    < count_of(limit: row.limit)
  use <- bool.guard(!in_limit, OutOfLimit)
  use <- bool.guard(!passes_filter(filter: row.filter, event:), FilteredOut)
  case
    gate_verdict(
      gate: row.holder_gate,
      subject: holder_subject,
      rolls: for_holder,
    )
  {
    prerequisite.Fails -> HolderGateFails
    prerequisite.NotRead(prerequisite_type:) ->
      cannot_tell(row:, which: "holder gate", prerequisite_type:)
    prerequisite.Passes ->
      decide_by_event(
        row:,
        event:,
        holder_unit:,
        event_subject:,
        draw:,
        rolls: for_event,
      )
  }
}

/// The event gate and the chance of a row whose limit, filter and holder gate passed.
fn decide_by_event(
  row row: ProcRow,
  event event: Event,
  holder_unit holder_unit: Int,
  event_subject event_subject: prerequisite.Subject,
  draw draw: Option(Int),
  rolls rolls: List(Int),
) -> Verdict {
  case gate_verdict(gate: row.event_gate, subject: event_subject, rolls:) {
    prerequisite.Fails -> EventGateFails
    prerequisite.NotRead(prerequisite_type:) ->
      cannot_tell(row:, which: "event gate", prerequisite_type:)
    prerequisite.Passes ->
      case chance_met(chance: row.chance, draw:) {
        False -> MissedChance
        True ->
          Fires(
            at: case row.aim, event.other_unit {
              spell_plan.AtOtherUnit, Some(unit) -> unit
              spell_plan.AtOtherUnit, None | spell_plan.AtHolder, _ ->
                holder_unit
            },
            delay_ms: row.delay_ms,
          )
      }
  }
}

fn cannot_tell(
  row row: ProcRow,
  which which: String,
  prerequisite_type prerequisite_type: Int,
) -> Verdict {
  CannotTell(
    why: "the Proc effect "
    <> int.to_string(row.effect_id.value)
    <> " is behind a "
    <> which
    <> " with a condition of type "
    <> int.to_string(prerequisite_type)
    <> ", which is not read, so it does not fire",
  )
}

/// Whether the event's spell is one the filter names: in its group, its Spell4 or a Spell4 of
/// its Spell4Base. An event with no spell passes only `AnySpell`.
fn passes_filter(
  filter filter: spell_plan.ProcFilter,
  event event: Event,
) -> Bool {
  case filter, event.spell {
    spell_plan.AnySpell, _ -> True
    spell_plan.InGroup(group_id:), Some(spell) ->
      list.contains(spell.groups, group_id)
    spell_plan.OneSpell(spell4_id:), Some(spell) -> spell.spell4_id == spell4_id
    spell_plan.OfBase(spell4_base_id:), Some(spell) ->
      spell.spell4_base_id == spell4_base_id
    spell_plan.InGroup(..), None
    | spell_plan.OneSpell(..), None
    | spell_plan.OfBase(..), None
    -> False
  }
}

/// A gate checked against its subject with its rolls; no gate passes.
fn gate_verdict(
  gate gate: Option(prerequisite.Prerequisite),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> prerequisite.Verdict {
  case gate {
    None -> prerequisite.Passes
    Some(gate) ->
      prerequisite.check(
        prerequisite: gate,
        subject: prerequisite.Subject(..subject, rolls:),
      )
  }
}

/// Whether the draw falls below the chance: the 32-bit word's fraction
/// (`random.fraction`) is below it. A chance of 1.0 takes no draw and always holds.
fn chance_met(chance chance: Float, draw draw: Option(Int)) -> Bool {
  case draw {
    Some(word) -> random.fraction(word) <. chance
    None -> chance >=. 1.0
  }
}
