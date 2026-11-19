//// The player's use of a consumable on the game connection (`genesis_prime/game/cast`
//// `use_item`, `genesis_prime/game/connection/item_spend`): the item's spell is cast on the
//// player, the store is asked to spend one of the stack, and what the client sees is the
//// spell's own heal or buff. Expected values come from these places.
//// - Item2 14838 (Basic Medishot: Instant Healing) -> Spell4 34985, whose Heal row 69917 is
////   parameter 18 x 200.0; the item's power level is 5, where the family-33 curve
////   (GameFormula 991) is 5.0 + 0.3 x 5 = 6.5, so the heal is 1,300 (`cast_item_use_test`).
//// - Item2 4730 -> Spell4 3792: Spell4Effects 6403, a type 11 modifier of property 7
////   (BaseHealth, `table_rows -- UnitProperty2 7`) for 900,000 ms.
//// - `opcode.0x943` (`StartItemUseCast` 0x140398cc0): the press names the player's own unit
////   as its target for a spell cast on its user (`PickCastTarget` 0x14055bdc0).
//// - `opcode.0x7fd`, `opcode.0x7f4`, `opcode.0x92f` and `opcode.0x93a`: the cast's
////   confirmation, its go with the heal listed as a damage description, the player's new
////   health and the player's changed properties.
//// - `opcode.0x7ff.activate`: a viewer is told the item's cast with the creature-activate
////   bit clear, and the item's level (`opcode.0x7ff.caster_item_level`).
//// - The order the coordinator chose for an item's use: the spend is saved, then the inventory
////   frame is written, then the cast's effects are released (`item_charge`).

import connection_rule_support as support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request, CastStarted}
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_result
import genesis_prime/message/item_count_changed
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/item_use.{ItemUse}
import genesis_prime/message/player_health
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/unit_properties_changed
import genesis_prime/step.{type ConnectionStep, OwnEvent}
import genesis_prime/store.{AccountId, CharacterId, SpendItem}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import item_charge_support as support_items
import owned_test
import spawn_support

/// What a scene's use shows the client.
type Shows {
  /// The go lists the heal row `effect_id` with this amount, and the health rises by it.
  Heals(effect_id: Int, amount: Int, item_level: Int)
  /// The go starts a change of this property, which ends this long after.
  Buffs(property_id: Int, ends_after_ms: Int, item_level: Int)
}

type Scene {
  Scene(why: String, item2: Int, count: Int, shows: Shows)
}

const the_place = ItemPlace(location: 1, bag_index: 0)

/// A level-1 player's full health (`player.level1_base_health`).
const full = 736

/// The client's 0x943 of the item at the place, naming the player's own unit.
fn press(client_cast_id client_cast_id: Int) -> BitArray {
  let assert Ok(body) =
    item_use.encode(ItemUse(
      client_cast_id:,
      item: the_place,
      target_unit_id: connection_support.own_unit_id,
      second_item: ItemPlace(location: 300, bag_index: 0xffffffff),
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  connection_support.world_message(message_id: item_use.message_id, body:)
}

/// A creature's blow of 1000 on the player, before its armor and shield.
fn a_strike() -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  connection_support.foe(
    strike_tell.Attacks(
      tell: strike_tell.Strike(
        key: strike_tell.Key(
          cast_id: 2_147_500_000,
          occasion: strike_tell.AtGo(phase: 0),
          unit_id: connection_support.own_unit_id,
        ),
        from: connection_support.fighter(),
        striker: spawn_support.beast_striker(),
        offence: spawn_support.dealing(
          offence: spawn_support.beast_attack().offence,
          damage: 1000,
        ),
        controls: [],
        gates: [],
      ),
    ),
  )
}

fn healths(taken taken: ConnectionStep(Request)) -> List(Int) {
  connection_support.decoded(
    connection_support.heard(taken, connection_support.keyed()),
    player_health.message_id,
    player_health.decode,
  )
  |> list.map(fn(told) { told.health })
}

/// The properties the step's 0x93a frames carry for this property id, as the value each
/// gives, in order.
fn property_values(
  taken taken: ConnectionStep(Request),
  property_id property_id: Int,
) -> List(Int) {
  connection_support.decoded(
    connection_support.heard(taken, connection_support.keyed()),
    0x093A,
    unit_properties_changed.decode,
  )
  |> list.flat_map(fn(changed) { changed.properties })
  |> list.filter(fn(entry) { entry.property_id == property_id })
  |> list.map(fn(entry) { entry.value })
}

/// The heal description amounts the step's 0x7f4 frames carry for the effect row.
fn described(
  taken taken: ConnectionStep(Request),
  effect_id effect_id: Int,
) -> List(Int) {
  connection_support.decoded(
    connection_support.heard(taken, connection_support.keyed()),
    spell_go.message_id,
    spell_go.decode,
  )
  |> list.flat_map(fn(go) {
    list.flat_map(go.targets, fn(target) { target.effects })
  })
  |> list.filter(fn(effect) { effect.spell4_effects_id == effect_id })
  |> list.map(fn(effect) {
    let assert spell_effect_result.Damage(shown) = effect.result
      as "the heal is listed with a damage description"
    shown.description.health_damage_with_overkill
  })
}

pub fn a_consumables_use_shows_its_heal_or_its_buff_and_spends_one_of_the_stack_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  list.each(
    [
      Scene(
        "Basic Medishot heals 1,300, the health frame carries the new health",
        14_838,
        3,
        Heals(effect_id: 69_917, amount: 1300, item_level: 5),
      ),
      Scene(
        "the buff potion changes BaseHealth for 900,000 ms",
        4730,
        2,
        Buffs(property_id: 7, ends_after_ms: 900_000, item_level: 15),
      ),
    ],
    fn(scene) {
      let held =
        support_items.held(
          guid: 4_000_003,
          item2: scene.item2,
          location: 1,
          bag_index: 0,
          count: scene.count,
          charges: 1,
        )
      let #(state, _) =
        connection_support.entered_with_quests_and_items_on(
          tables:,
          quests: [],
          items: [held],
        )
      let state = connection_support.watched_by(state:, viewers: [2])
      let #(state, _) =
        connection_support.feed(
          state:,
          event: connection_support.foe(strike_tell.Threatened(
            unit_id: 7,
            life: 3,
          )),
        )
      let #(state, struck) = connection_support.feed(state:, event: a_strike())
      let assert [hurt] = healths(taken: struck)
        as "the blow lowers the health: one 0x92f"
      assert hurt < full as scene.why
      let #(state, pressed) =
        connection_support.at(
          state:,
          ms: 1000,
          event: OwnEvent(step.Read(press(client_cast_id: 1))),
        )
      assert support_items.spend_asked(pressed)
        == SpendItem(
          account_id: AccountId(7),
          character_id: CharacterId(42),
          session_epoch: support_items.epoch(),
          item: held,
          stack_count: scene.count - 1,
          charges: 1,
        )
        as scene.why
      assert connection_support.written_ids(pressed) == []
        as "nothing is written before the store has saved the spend"
      let assert Some(ask) = support.asked(pressed) as "the step ends in an ask"
      let #(state, answered) =
        connection_support.at(
          state:,
          ms: 1000,
          event: OwnEvent(step.Answered(
            ask: ask.ask,
            outcome: step.Answer(
              client_connection.FromStore(store.ForItems(store.ItemsSaved)),
            ),
          )),
        )
      let frames =
        connection_support.heard(answered, connection_support.keyed())
      let assert [first, ..] = frames
      let assert Ok(lowered) = item_count_changed.decode(first.body)
        as "the first frame tells the stack's new count"
      assert lowered.count == scene.count - 1 && lowered.reason == 1
        as "the spend is told first: the stack is one lower, ConsumeCharge"
      assert list.contains(
        list.map(frames, fn(frame) { frame.message_id }),
        0x07FD,
      )
        as "the cast is confirmed"
      let assert [CastStarted(start: started), ..] =
        list.filter_map(connection_support.peer_tells(answered), fn(tell) {
          case tell.0 == 2 {
            True -> Ok({ tell.1 }.news)
            False -> Error(Nil)
          }
        })
        as "the viewer is told the cast's start first"
      case scene.shows {
        Heals(effect_id:, amount:, item_level:) -> {
          assert started.creature_activate == 0
            && started.caster_item_level == item_level
            as scene.why
          assert described(taken: answered, effect_id:) == [amount] as scene.why
          assert healths(taken: answered) == [int.min(full, hurt + amount)]
            as scene.why
          let #(_, again) =
            connection_support.at(
              state:,
              ms: 2000,
              event: OwnEvent(step.Read(press(client_cast_id: 2))),
            )
          let assert [refusal] =
            connection_support.heard(again, connection_support.keyed())
            as "a second press inside the group's 180,000 ms is answered with one frame"
          let assert Ok(refused) = spell_cast_refused.decode(refusal.body)
            as "the answer is a 0x7fc"
          assert refusal.message_id == 0x07FC
            && cast_result.to_value(refused.result) == 16
            as "SpellCoolDown 130 holds 180,000 ms: the client refuses it 16 (0x1403b14c0), and the server refuses a press the client would not send"
          assert support.asked(again) == None
            as "a refused press asks the store for nothing: the stack stays"
        }
        Buffs(property_id:, ends_after_ms:, item_level:) -> {
          assert started.creature_activate == 0
            && started.caster_item_level == item_level
            as scene.why
          assert list.length(property_values(taken: answered, property_id:))
            == 1
            as scene.why
          let ends =
            list.filter(
              connection_support.cast_timers(steps: [answered], ms: 1000),
              fn(timer) { timer.0 == 1000 + ends_after_ms },
            )
          assert ends != [] as "the buff's end is on a timer of its duration"
          let ended =
            list.fold(ends, #(state, []), fn(so_far, due) {
              let #(state, taken) = so_far
              let #(state, more) =
                connection_support.fired_at(state:, timer: due.1, ms: due.0)
              #(state, list.append(taken, [more]))
            })
          assert list.flat_map(ended.1, fn(taken) {
              property_values(taken:, property_id:)
            })
            |> list.length
            == 1
            as "the end of the buff writes the property again, once"
        }
      }
    },
  )
}
