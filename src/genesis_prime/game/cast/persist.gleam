//// The persistence checks of a lasting cast: whether what it needs still holds, and the end when it does not.
////
//// - **Persistence** is the server's alone: the client never evaluates
////   prerequisiteIdCasterPersistence or prerequisiteIdTargetPersistence, which it keeps
////   to word the results 282 and 283 (`Spell4.prerequisiteIdCasterPersistence`,
////   `0x1405648a0`). The connection calls `cast.persisted` at the end of each input of a player
////   in the world, which is exact and needs no timer or interval (the tables give none).
////   Each live or lingering cast, lowest id first, whose spell's condition fails ends
////   (checked again after each end, since one can break another's): 0x7f9 {cast id, 282 or
////   283, the caster, 0}, which destroys the nodes the cast holds so its buff goes and leaves
////   the cast filed, then the 0x7fe that takes it out of the client's table, told to the
////   audience as a finish (`opcode.0x7f9`, `cast.target_node_end`; which message retail sent
////   is not known). The cast's go, finish and NodesEnd timers are cancelled, its property
////   modifiers and cooldown effects end, its stealth sources drop (the input's last effect
////   is `StealthChanged`), the current cast clears when it was this one, an open threshold
////   it is the base cast of closes as a 0x801 closes it, and a press held for the clear
////   starts. CasterPersistence (282) is checked before TargetPersistence (283), the caster
////   the first unit and the cast's primary target the second; TargetPersistence is checked
////   only for a cast whose primary target is the caster, since the connection holds no
////   creature's state. A condition of a type not read, a roll and a creature target keep the
////   cast, with one debug line for the spell.

import genesis_prime/game/cast/cost as cast_cost
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/state.{
  type Caster, type Effect, type Holder, type State, Log, Send, State,
} as cast_state
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/message/cast_result
import genesis_prime/step.{LogDebug}
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set

/// Whether some live or lingering cast holds a spell with a persistence column, so
/// `cast.persisted` has something to check: the connection asks before it builds the caster,
/// since most inputs find nothing.
pub fn persists(cast cast: State) -> Bool {
  list.any(cast_state.holders(cast:), fn(entry) {
    has_persistence(spell: { entry.1 }.spell)
  })
}

fn has_persistence(spell spell: Spell) -> Bool {
  option.is_some(spell.caster_persistence)
  || option.is_some(spell.target_persistence)
}

/// The first cast, in the order given, whose persistence fails, with its result and the
/// debug lines of the casts checked on the way.
pub fn first_failing_persistence(
  cast cast: State,
  caster caster: Caster,
  subject subject: prerequisite.Subject,
  holders holders: List(#(Int, Holder)),
  logs logs: List(Effect),
) -> #(State, List(Effect), Option(#(Int, cast_result.CastResult))) {
  case holders {
    [] -> #(cast, logs, None)
    [#(cast_id, holder), ..rest] -> {
      let #(cast, more, failing) =
        persistence_of(cast:, caster:, subject:, holder:)
      let logs = list.append(logs, more)
      case failing {
        Some(result) -> #(cast, logs, Some(#(cast_id, result)))
        None ->
          first_failing_persistence(
            cast:,
            caster:,
            subject:,
            holders: rest,
            logs:,
          )
      }
    }
  }
}

/// The result a cast's persistence fails with, none when it holds or cannot be read.
fn persistence_of(
  cast cast: State,
  caster caster: Caster,
  subject subject: prerequisite.Subject,
  holder holder: Holder,
) -> #(State, List(Effect), Option(cast_result.CastResult)) {
  let spell = holder.spell
  let #(cast, caster_logs, caster_fails) =
    persistence_column(
      cast:,
      spell:,
      result: cast_result.PrereqCasterPersistence,
      gate: spell.caster_persistence,
      subject: prerequisite.Subject(
        ..subject,
        second_unit: Some(holder.primary_target),
      ),
    )
  use <- bool.guard(when: caster_fails, return: #(
    cast,
    caster_logs,
    Some(cast_result.PrereqCasterPersistence),
  ))
  let #(cast, target_logs, target_fails) = case
    holder.primary_target == caster.unit_id
  {
    True ->
      persistence_column(
        cast:,
        spell:,
        result: cast_result.PrereqTargetPersistence,
        gate: spell.target_persistence,
        subject:,
      )
    False ->
      case spell.target_persistence {
        None -> #(cast, [], False)
        Some(_) -> {
          let #(cast, log) =
            logged_once(
              cast:,
              spell:,
              result: cast_result.PrereqTargetPersistence,
              text: "has a target persistence on a creature, whose state this connection does not hold, so it is not checked",
            )
          #(cast, log, False)
        }
      }
  }
  #(cast, list.append(caster_logs, target_logs), case target_fails {
    True -> Some(cast_result.PrereqTargetPersistence)
    False -> None
  })
}

/// One persistence column checked: whether it fails, and the debug line when it cannot
/// be read, once for the spell.
fn persistence_column(
  cast cast: State,
  spell spell: Spell,
  result result: cast_result.CastResult,
  gate gate: Option(prerequisite.Prerequisite),
  subject subject: prerequisite.Subject,
) -> #(State, List(Effect), Bool) {
  case cast_cost.column_verdict(gate:, subject:) {
    prerequisite.Passes -> #(cast, [], False)
    prerequisite.Fails -> #(cast, [], True)
    prerequisite.NotRead(prerequisite_type:) -> {
      let #(cast, log) =
        logged_once(
          cast:,
          spell:,
          result:,
          text: "has a persistence of the PrerequisiteType "
            <> int.to_string(prerequisite_type)
            <> ", which the server does not read, so its casts go on",
        )
      #(cast, log, False)
    }
  }
}

/// A debug line about the spell's persistence column of this result, unless one was
/// written already on this connection.
fn logged_once(
  cast cast: State,
  spell spell: Spell,
  result result: cast_result.CastResult,
  text text: String,
) -> #(State, List(Effect)) {
  let key = #(spell.spell4_id.value, cast_result.to_value(result))
  use <- bool.guard(
    when: set.contains(cast.persistence_logged, key),
    return: #(cast, []),
  )
  #(
    State(..cast, persistence_logged: set.insert(cast.persistence_logged, key)),
    [
      Log(
        level: LogDebug,
        text: "the cast of Spell4 "
          <> int.to_string(spell.spell4_id.value)
          <> " "
          <> text,
      ),
    ],
  )
}

/// 0x7f9 for a cast that failed with this result: the bit is the 0 the 0x7fe path passes
/// (`opcode.0x7f9`). The unit is the caster, not the 0 the 0x7fe path passes: FinishCast
/// releases the threshold of a RapidTap cast ended with a result other than 6 or 8 only
/// when the end names another unit (`0x14053e1b0`), and this rule keeps the threshold of a
/// stage it ends open (only a charge's base cast closes its own), so the unit must not be
/// another; the 0x7fe path's result 8 never touches a threshold, which is why 0 is safe
/// there.
pub fn failed_effect(
  cast_id cast_id: Int,
  result result: cast_result.CastResult,
  unit_id unit_id: Int,
) -> Effect {
  Send(frame: cast_frame.failed_frame(cast_id:, result:, unit_id:))
}
