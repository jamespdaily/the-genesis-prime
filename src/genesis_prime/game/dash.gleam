//// The player's dash: the client's 0x015C names a direction, and the server pays the
//// dash's cost from the dash energy. A feature of the game connection's rule
//// (genesis_prime/game/connection) taken from inside 0x038C with the player in the world.
////
//// ```
//// load: GameFormula 477 to 480 ─▶ Spell4 of each direction ─▶ its innate costs ─▶ Dashes
//// 0x015C {direction} ─▶ take(dashes, life, resources, body)
////      alive, the cost held                ─▶ Pays(payments): the connection pays them (class_resource.pay),
////                                             0x935 of stat 9 to the player, nothing to viewers
////      dead, or the energy below the cost  ─▶ Dropped(reason): a log line, the true value sent again
////      a direction the client never sends  ─▶ a refusal that ends the connection
////      a body the client's reader refuses  ─▶ a refusal that ends the connection
//// ```
////
//// - **The dash is the client's own movement.** It sets a local dash state and sends only
////   0x015C; no cast is created, so the server answers with no cast and no 0x7ff. Its
////   movement reaches the server in 0x637 and viewers through the movement relay
////   (`dash.client_movement`).
//// - **The direction** 1 to 4 names GameFormula 479, 480, 477 and 478, whose dataint0 is the
////   Spell4 of the dash: Forward 28772, Backward 28773, Left 28770 and Right 28771
////   (`opcode.0x15c`, `0x14039f590`). The spell's cost is its innate cost, 100 of type 16, which
////   reads resource slot 7, the dash energy (genesis_prime/shared/spell_plan).
//// - **A dash the server cannot pay** is dropped: the client's own press check refuses a dash
////   below 100 or from a dead player before it sends, so only a client holding a stale energy
////   or a stale death state sends one. The connection writes a log line and the true energy
////   again so the client corrects its meter (the server's choice).
//// - **A knockdown dash and the passives that trigger on a dash** are not handled: the dash
////   spells' effect (type 27, CC state 8) has no reader in the client, and no event of the
////   cast rule fires a dash's procs (`gaps`).

import genesis_prime/client_connection.{type Undecoded, type Unwritten}
import genesis_prime/game/cast/cost
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/player_life
import genesis_prime/gap
import genesis_prime/message/dash
import genesis_prime/shared/class_resource.{type Payment, type Resources}
import genesis_prime/shared/spell_plan.{type Cost}
import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

/// The dash of each direction: its Spell4 and what the press pays.
pub opaque type Dashes {
  Dashes(by_direction: Dict(Int, Dash))
}

type Dash {
  Dash(spell4_id: Int, costs: List(Cost))
}

const dashes_key: table_store.DerivedKey(Dashes) =
  table_store.DerivedKey("Dashes")

/// Each direction the client sends and the GameFormula row that names its dash spell:
/// 1 Forward 479, 2 Backward 480, 3 Left 477, 4 Right 478 (`0x14039f590`).
const direction_formulas = [#(1, 479), #(2, 480), #(3, 477), #(4, 478)]

/// What a 0x015C the client may send asks for.
pub type Taken {
  /// Pay these from the dash energy.
  Pays(payments: List(Payment))
  /// A dash the client's own checks would have refused: dropped.
  Dropped(reason: Dropped)
}

/// Why a dash is dropped, for the log line.
pub type Dropped {
  /// The player is dead.
  PlayerDead
  /// The energy held is below the cost: the result the client's check gives.
  EnergyBelowCost(result: Int)
  /// The cost is one the server holds no energy for, with the result its check gives.
  CostNotHeld(result: Int)
}

/// Why a 0x015C is refused: the client's own code never sends it. The connection ends.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
  /// A direction the client never writes.
  UnknownDirection(unwritten: Unwritten)
}

/// Why the dashes cannot be built from the tables.
type BuildError {
  /// A GameFormula row of a direction is missing.
  NoFormula(id: Int)
  /// The Spell4 a GameFormula row names is missing.
  NoSpell(formula_id: Int, spell4_id: Int)
  /// The spell's costs cannot be read.
  CostNotPlanned(spell4_id: Int, error: spell_plan.PlanError)
}

/// The dashes as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`). A missing GameFormula or Spell4 row
/// fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: dashes_key, build: fn(tables) {
    build(tables:) |> result.map_error(describe_build)
  })
}

/// The dashes the tables' load built.
pub fn dashes(tables tables: table_store.Tables) -> Dashes {
  table_store.derived(tables:, key: dashes_key)
}

fn build(tables tables: table_store.Tables) -> Result(Dashes, BuildError) {
  list.try_map(direction_formulas, fn(entry) {
    let #(direction, formula_id) = entry
    use formula <- result.try(
      game_formula.get(tables:, id: GameFormulaId(formula_id))
      |> result.replace_error(NoFormula(id: formula_id)),
    )
    let spell4_id = formula.dataint0
    use row <- result.try(
      spell4.get(tables:, id: Spell4Id(spell4_id))
      |> result.replace_error(NoSpell(formula_id:, spell4_id:)),
    )
    use costs <- result.map(
      spell_plan.innate_costs(row:)
      |> result.map_error(CostNotPlanned(spell4_id:, error: _)),
    )
    #(direction, Dash(spell4_id:, costs:))
  })
  |> result.map(fn(entries) { Dashes(by_direction: dict.from_list(entries)) })
}

fn describe_build(error error: BuildError) -> String {
  case error {
    NoFormula(id:) ->
      "the table GameFormula has no row "
      <> int.to_string(id)
      <> ", which names a dash spell"
    NoSpell(formula_id:, spell4_id:) ->
      "the table Spell4 has no row "
      <> int.to_string(spell4_id)
      <> ", the dash spell GameFormula "
      <> int.to_string(formula_id)
      <> " names"
    CostNotPlanned(spell4_id:, error:) ->
      "the cost of the dash spell "
      <> int.to_string(spell4_id)
      <> " cannot be read: "
      <> spell_plan.describe(error:)
  }
}

/// The Spell4 the dash of a direction is, `Error(Nil)` for a direction the client never sends.
pub fn spell4_id_of(
  dashes dashes: Dashes,
  direction direction: Int,
) -> Result(Int, Nil) {
  dict.get(dashes.by_direction, direction)
  |> result.map(fn(dash) { dash.spell4_id })
}

/// The innate costs of the dash of a direction, `Error(Nil)` for a direction the client never
/// sends.
pub fn costs_of(
  dashes dashes: Dashes,
  direction direction: Int,
) -> Result(List(Cost), Nil) {
  dict.get(dashes.by_direction, direction)
  |> result.map(fn(dash) { dash.costs })
}

/// What the client's 0x015C asks for: the payment of the dash's cost, or why it is dropped
/// or refused.
pub fn take(
  dashes dashes: Dashes,
  life life: player_life.State,
  resources resources: Resources,
  body body: BitArray,
) -> Result(Taken, Refusal) {
  use asked <- result.try(
    dash.decode(body)
    |> client_connection.decoded(message_id: dash.message_id)
    |> result.map_error(NotDecoded),
  )
  use costs <- result.try(
    costs_of(dashes:, direction: asked.direction)
    |> result.replace_error(
      UnknownDirection(client_connection.Unwritten(
        message_id: dash.message_id,
        field: "the direction",
        value: asked.direction,
      )),
    ),
  )
  case life {
    player_life.Dead -> Ok(Dropped(reason: PlayerDead))
    player_life.Alive ->
      case cost.costs_paid(costs:, resources:) {
        Ok(paid) -> Ok(Pays(payments: paid.payments))
        Error(cast_state.Unpaid(result:)) ->
          Ok(Dropped(reason: EnergyBelowCost(result:)))
        Error(cast_state.Unheld(result:))
        | Error(cast_state.UnreadSpend(result:, ..)) ->
          Ok(Dropped(reason: CostNotHeld(result:)))
      }
  }
}

/// A sentence that says why a dash is dropped, for the log.
pub fn describe_dropped(reason reason: Dropped) -> String {
  case reason {
    PlayerDead ->
      "0x015C from a dead player is dropped: the client's own check refuses a dash then"
    EnergyBelowCost(result:) ->
      "0x015C with the dash energy below its cost (result "
      <> int.to_string(result)
      <> ") is dropped: the client's own check refuses a dash then, so its energy is stale"
    CostNotHeld(result:) ->
      "0x015C is dropped: its cost is one the server holds no energy for (result "
      <> int.to_string(result)
      <> ")"
  }
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    UnknownDirection(unwritten:) ->
      client_connection.describe_unwritten(unwritten:)
  }
}

/// What the dash leaves undone, for the coverage measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Dash",
      missing: "a dash out of a knockdown (the dash spells' effect is of a type the client has no reader for) and the passive abilities that trigger on a dash are not handled: the server has no knockdown of a player and no event of the cast rule fires a dash's procs",
    ),
    gap.Entry(
      area: "Dash",
      missing: "the 500 ms window after a dash in which the client allows no second dash, and the global cooldown a dash press starts, are not kept: the server takes a paid dash at any time and starts no cooldown (GameFormula 482 and 483, SpellCoolDown 114)",
    ),
  ]
}
