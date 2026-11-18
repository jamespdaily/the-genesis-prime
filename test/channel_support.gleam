//// A channel pressed by a caster and run through its timers, for the tests of what a
//// channel pays and how it ends (`cast_channel_cost_test`, `cast_cost_timing_test`).
////
//// A scene is one spell and one caster that holds a value in the spell's class slot;
//// `run_channel` presses it at `pressed_at_ms` and fires every timer it leads to, each
//// go's round closing on nobody, with each step's payments and gains taken into the
//// caster the next timer meets (`cast_support.run_timers_scripted`). Times are given
//// after the press.

import cast_support as support
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/class_resource.{type Payment}
import genesis_prime/game/spell_plan.{type Plans, type Spell}
import genesis_prime/message/spell_failed
import genesis_prime/step.{type TimerId}
import genesis_prime/table/id.{type Spell4Id}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleam/string

/// The time of the press, on the test's clock.
pub const pressed_at_ms = 1000

/// A spell, the caster that presses it and what the pressed ability is: the plans that
/// hold it, its place in the caster's bag and the units each go strikes. The channel
/// tests press the spell itself, the caster's only ability; `started_scene` presses an
/// ability whose go starts the spell through a Proxy.
pub type Scene {
  Scene(
    spell: Spell,
    caster: Caster,
    plans: Plans,
    bag_index: Int,
    struck: List(cast_state.Struck),
  )
}

/// One step of a run: the time after the press, the goes the rule asked for, how many
/// `SpendsResource` events it raised for the held procs and its effects.
pub type Step {
  Step(
    after_ms: Int,
    asked: List(cast_state.GoAsked),
    spends: Int,
    effects: List(Effect),
  )
}

/// A run: the press and then each timer, the rule's state and the caster after the
/// last step, the cast id the press was given, and every timer the steps started, with
/// the time after the press each is due.
pub type Run {
  Run(
    state: State,
    caster: Caster,
    cast_id: Int,
    steps: List(Step),
    started: List(#(TimerId, Int)),
  )
}

/// The spell as the caster's only ability, held by a caster of the class with this
/// Class id whose slot holds `holding`.
pub fn channel_scene(
  spell spell: Spell,
  class_id class_id: Int,
  holding holding: Float,
) -> Scene {
  Scene(
    spell:,
    caster: cast_state.Caster(
      ..support.caster(),
      abilities: [spell.spell4_base_id],
      resources: support.holding(class_id:, value: holding),
    ),
    plans: support.plans_with(spell:),
    bag_index: 0,
    struck: [],
  )
}

/// The spell as a child a Proxy starts: the caster presses the ability whose go starts it on
/// each unit that go struck (`cast_support.plans_starting_on_each_struck`), and every go
/// strikes the unit 10.
pub fn started_scene(
  spell spell: Spell,
  class_id class_id: Int,
  holding holding: Float,
) -> Scene {
  Scene(
    spell:,
    caster: cast_state.Caster(
      ..support.caster(),
      resources: support.holding(class_id:, value: holding),
    ),
    plans: support.plans_starting_on_each_struck(started: spell),
    bag_index: support.started_bag_index,
    struck: support.hits([10]),
  )
}

/// The press and every timer, no change to the caster and every round closed.
pub fn run_channel(scene scene: Scene) -> Run {
  run_scripted(
    scene:,
    until_after_ms: None,
    before: fn(_, caster) { caster },
    leaves_open: fn(_) { False },
  )
}

/// The same, as a script (`cast_support.run_timers_scripted`) with times after the press:
/// only the timers due at `until_after_ms` or before fire, `before` changes the caster
/// when a timer is due, and a go for which `leaves_open` holds keeps its round open.
pub fn run_scripted(
  scene scene: Scene,
  until_after_ms until_after_ms: Option(Int),
  before before: fn(Int, Caster) -> Caster,
  leaves_open leaves_open: fn(Int) -> Bool,
) -> Run {
  let #(state, raw, spends) = pressed(scene:)
  let #(state, pressed) =
    support.answered_each(
      caster: scene.caster,
      state:,
      effects: raw,
      at: pressed_at_ms,
      struck_of: fn(_) { scene.struck },
      rolls: [],
      poses: dict.new(),
    )
  let press =
    Step(
      after_ms: 0,
      asked: support.goes_asked(effects: raw),
      spends:,
      effects: pressed,
    )
  let #(state, fired, caster) =
    support.run_timers_scripted(
      caster: scene.caster,
      state:,
      effects: pressed,
      from_ms: pressed_at_ms,
      struck: scene.struck,
      until_ms: option.map(until_after_ms, fn(after_ms) {
        pressed_at_ms + after_ms
      }),
      before: fn(at_ms, caster) { before(at_ms - pressed_at_ms, caster) },
      leaves_open: fn(at_ms) { leaves_open(at_ms - pressed_at_ms) },
    )
  let steps =
    list.append(
      [press],
      list.map(fired, fn(step) {
        Step(
          after_ms: step.at_ms - pressed_at_ms,
          asked: step.asked,
          spends: step.spends,
          effects: step.effects,
        )
      }),
    )
  Run(
    state:,
    caster:,
    cast_id: support.pressed_id(effects: pressed),
    steps:,
    started: list.flat_map(steps, fn(step) {
      list.map(support.started_timers(effects: step.effects), fn(started) {
        #(started.0, step.after_ms + started.1)
      })
    }),
  )
}

/// The scene's press as the rule gives it, its goes not yet answered, with the
/// `SpendsResource` events it raised.
pub fn pressed(scene scene: Scene) -> #(State, List(Effect), Int) {
  support.pressed_counting(
    plans: scene.plans,
    state: cast_state.new(),
    caster: scene.caster,
    bag_index: scene.bag_index,
    target: 0,
    at: pressed_at_ms,
  )
}

/// Each payment of the run with the time after the press it was made at, in order.
pub fn payments(run run: Run) -> List(#(Int, Payment)) {
  list.flat_map(run.steps, fn(step) {
    list.map(support.payments(effects: step.effects), fn(payment) {
      #(step.after_ms, payment)
    })
  })
}

/// The time after the press of each go the rule asked for, in order.
pub fn goes(run run: Run) -> List(Int) {
  list.flat_map(run.steps, fn(step) {
    list.map(step.asked, fn(_) { step.after_ms })
  })
}

/// The time after the press of each go of the spell with this Spell4 id that the rule
/// asked for, in order.
pub fn goes_of(run run: Run, spell4_id spell4_id: Spell4Id) -> List(Int) {
  list.flat_map(run.steps, fn(step) {
    list.filter_map(step.asked, fn(asked) {
      case asked.spell4_id == spell4_id {
        True -> Ok(step.after_ms)
        False -> Error(Nil)
      }
    })
  })
}

/// What the client reads of the pressed cast, one line each (`cast_support.cast_lines`): the
/// casts a go starts through Proxies have lines of their own, which are left out.
pub fn lines(run run: Run) -> List(String) {
  support.cast_lines(frames: support.writes(effects: effects(run:)))
  |> list.filter(fn(line) {
    case string.split(line, " ") {
      [_, "k1", ..] -> True
      _ -> False
    }
  })
}

/// Every effect of the run, in order.
pub fn effects(run run: Run) -> List(Effect) {
  list.flat_map(run.steps, fn(step) { step.effects })
}

/// How many 0x7f9 frames the run wrote, which the client's `FinishCast` reads as a cast
/// that failed.
pub fn failures(run run: Run) -> Int {
  list.length(support.frames_of(
    message_id: spell_failed.message_id,
    effects: effects(run:),
  ))
}

/// The time after the press of the step that wrote the pressed cast's 0x7fe.
pub fn finished_at(run run: Run) -> Result(Int, Nil) {
  list.find(run.steps, fn(step) {
    list.contains(
      support.finished_ids(support.writes(effects: step.effects)),
      run.cast_id,
    )
  })
  |> result.map(fn(step) { step.after_ms })
}

/// The `SpendsResource` events each step raised, with the time after the press.
pub fn spends(run run: Run) -> List(#(Int, Int)) {
  list.filter_map(run.steps, fn(step) {
    case step.spends {
      0 -> Error(Nil)
      count -> Ok(#(step.after_ms, count))
    }
  })
}

/// The caster's slot value after the run.
pub fn held(run run: Run, slot slot: Int) -> Float {
  class_resource.value(resources: run.caster.resources, slot:)
}

/// The timers the run started that are due after `after_ms`.
pub fn timers_due_after(run run: Run, after_ms after_ms: Int) -> List(TimerId) {
  list.filter_map(run.started, fn(started) {
    case started.1 > after_ms {
      True -> Ok(started.0)
      False -> Error(Nil)
    }
  })
}
