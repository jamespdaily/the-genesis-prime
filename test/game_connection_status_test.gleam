//// The connection's status and the player it holds in the world
//// (`genesis_prime/game/connection/state`): which statuses hold a player, which of them
//// a write by `with_entered` reaches and which only a write by `with_entered_in_any_status`
//// reaches, whose record of what the connection already did an answer's handler reads back.

import cast_support
import game_connection_support as support
import genesis_prime/game/activate
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/character_select
import genesis_prime/game/connection/state.{
  type Status, AwaitingHelloReply, Buying, Camped, ClaimingSession,
  EnteringWorld, FromCharacterSelect, Granting, InCharacterSelect, InWorld,
  Leaving, LeavingMap, MovingItem, Playing, ResumeSelect, ResumeWorld,
  SavingPlace, Selling, SpendingCharge, Summoning, TakingSessionKey,
  ToCharacterSelect, TurningIn, WaitingToClaim,
} as connection_state
import genesis_prime/game/dev_command
import genesis_prime/game/experience
import genesis_prime/game/inventory
import genesis_prime/game/item_charge
import genesis_prime/game/quest_turn_in
import genesis_prime/game/unit_casts
import genesis_prime/game/vendor_purchase
import genesis_prime/game/vendor_sale
import genesis_prime/game/world_entry
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/store.{AccountId, HeldItem}
import genesis_prime/table/id.{Item2Id}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import owned_test
import quest_support
import world_entry_support

fn an_item() -> store.HeldItem {
  HeldItem(
    item_guid: 4_000_001,
    item2_id: Item2Id(1),
    location: 0,
    bag_index: 0,
    stack_count: 1,
    words: store.plain_words,
  )
}

/// What the compare of a cast leaves in `creature_told`: the Beast's node told at life 1.
fn told() -> dict.Dict(#(Int, Int), cast_state.Told) {
  dict.from_list([
    #(
      #(5, 40),
      cast_state.Told(
        life: 1,
        struck_at_ms: 100,
        target: unit_casts.ViewTarget(unit_id: 40, count: 1, effects: []),
      ),
    ),
  ])
}

fn telling(entered: world_entry.Entered) -> world_entry.Entered {
  world_entry.Entered(
    ..entered,
    cast: cast_state.State(..entered.cast, creature_told: told()),
  )
}

fn forgetting(entered: world_entry.Entered) -> world_entry.Entered {
  world_entry.Entered(
    ..entered,
    cast: cast_state.State(..entered.cast, creature_told: dict.new()),
  )
}

/// A row of the table: a status, whether it holds the player in the world, and whether a
/// write by `with_entered` reaches it (`InWorld` and the claim that waits on its timer with
/// the player in the world: the statuses that take a send).
type Row {
  Row(name: String, status: Status, holds_player: Bool, takes_a_send: Bool)
}

fn rows(entered entered: world_entry.Entered) -> List(Row) {
  let holder = support.holder()
  let item = an_item()
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id: 42))
    as "a character id fits the message"
  let assert Ok(#(entering, _)) =
    world_entry.take(account_id: AccountId(7), body:, now_unix_ms: 0)
    as "the client's request to play decodes"
  [
    Row("the hello is sent", AwaitingHelloReply, False, False),
    Row(
      "the session key is taken",
      TakingSessionKey(AccountId(7)),
      False,
      False,
    ),
    Row(
      "a first claim, to character select",
      ClaimingSession(holder:, resume: ResumeSelect, retries: 0),
      False,
      False,
    ),
    Row(
      "a claim again, to character select, waits on its timer",
      WaitingToClaim(holder:, resume: ResumeSelect, retries: 0),
      False,
      False,
    ),
    Row(
      "a claim again, to the world",
      ClaimingSession(holder:, resume: ResumeWorld(entered:), retries: 1),
      True,
      False,
    ),
    Row(
      "a claim again, to the world, waits on its timer",
      WaitingToClaim(holder:, resume: ResumeWorld(entered:), retries: 1),
      True,
      True,
    ),
    Row(
      "character select",
      InCharacterSelect(holder:, select: character_select.new()),
      False,
      False,
    ),
    Row(
      "the world entry asks the store",
      EnteringWorld(holder:, entry: entering, from: FromCharacterSelect),
      False,
      False,
    ),
    Row("in the world", InWorld(holder:, entered:), True, True),
    Row("a creature is summoned", Summoning(holder:, entered:), True, False),
    Row(
      "an item is moved",
      MovingItem(
        holder:,
        entered:,
        moving: inventory.Moving(
          guid: 4_000_001,
          change: inventory.Moved(moves: [], moved: []),
          items: [],
        ),
      ),
      True,
      False,
    ),
    Row(
      "a charge is spent",
      SpendingCharge(
        holder:,
        entered:,
        spending: item_charge.Spending(
          press: cast_state.ItemPress(
            client_cast_id: 1,
            spell4_id: 1,
            place: ItemPlace(location: 0, bag_index: 0),
          ),
          item:,
          spend: item_charge.NothingToSpend,
          start: cast_state.ActivationStart(
            client_cast_id: 1,
            caster: cast_support.caster(),
            spell: cast_support.exempt(),
            role: cast_state.Passive(from: None),
            primary_target: 0,
            dropped: activate.Dropped(
              signals: [],
              despawns: [],
              unit_states: [],
            ),
            paid: cast_state.Paid(payments: [], spent: None),
          ),
        ),
      ),
      True,
      False,
    ),
    Row(
      "an item is bought",
      Buying(
        holder:,
        entered:,
        purchase: vendor_purchase.Purchase(
          kind: vendor_purchase.Given,
          unit_id: 40,
          item2_id: Item2Id(1),
          items_bought: 1,
          cost: 0,
          currency_type_id: 1,
          held: 0,
          grow: [],
          make: [],
        ),
      ),
      True,
      False,
    ),
    Row(
      "a currency is granted",
      Granting(
        holder:,
        entered:,
        grant: dev_command.Grant(currency_type_id: 1, held: 0),
      ),
      True,
      False,
    ),
    Row(
      "an item is sold",
      Selling(
        holder:,
        entered:,
        sale: vendor_sale.Sale(
          unit_id: 40,
          first: vendor_sale.SoldItem(
            item_guid: 4_000_001,
            item2_id: Item2Id(1),
            location: 0,
            held_count: 1,
            sold_count: 1,
            paid: 1,
          ),
          rest: [],
          currency_type_id: 1,
          held: 0,
          after: 1,
        ),
      ),
      True,
      False,
    ),
    Row(
      "a quest is turned in",
      TurningIn(
        holder:,
        entered:,
        turn_in: quest_turn_in.TurnIn(
          quest_id: 1,
          log: quest_support.log_of(rows: []),
          credited: experience.Credited(
            progress: experience.Progress(experience: 0, level: 1),
            effects: [],
          ),
          credits_held: 0,
          credits_after: 0,
          placed: [],
        ),
      ),
      True,
      False,
    ),
    Row(
      "the place is saved and the player goes on playing",
      SavingPlace(holder:, entered:, then: Playing),
      True,
      False,
    ),
    Row(
      "the place is saved and the connection ends",
      SavingPlace(holder:, entered:, then: Leaving(notice: None)),
      True,
      False,
    ),
    Row(
      "the place is saved and the player camps",
      SavingPlace(holder:, entered:, then: Camped),
      True,
      False,
    ),
    Row(
      "the map is asked to take the player out",
      LeavingMap(holder:, entered:, then: ToCharacterSelect),
      True,
      False,
    ),
  ]
}

/// A write by `with_entered_in_any_status` keeps its record in the status of every
/// player the connection holds in the world, an ask's included, and leaves the rest of
/// the status as it was; a status that holds no player is as it was. A write by
/// `with_entered` reaches only the statuses that take a send.
pub fn a_record_written_to_the_player_is_kept_in_each_status_that_holds_one_test() -> Nil {
  use <- owned_test.run(10_000)
  let entered = world_entry_support.entered_after(clock_origin_ms: 600)
  list.each(rows(entered:), fn(row) {
    let session = support.session_in(status: row.status)
    let written =
      connection_state.with_entered_in_any_status(session:, change: telling)
    assert option.is_some(connection_state.entered_of(row.status))
      == row.holds_player
      as { row.name <> ": the status holds a player exactly when the row says" }
    case row.holds_player {
      True -> {
        let assert Some(kept) = connection_state.entered_of(written.status)
          as { row.name <> ": the player is still held" }
        assert kept.cast.creature_told == told()
          as { row.name <> ": the told record is kept" }
        let restored =
          connection_state.with_entered_in_any_status(
            session: written,
            change: forgetting,
          )
        assert restored.status == row.status
          as { row.name <> ": nothing else of the status changed" }
      }
      False -> {
        assert written.status == row.status
          as { row.name <> ": no player is held, so the status is as it was" }
      }
    }
    let sent = connection_state.with_entered(session:, change: telling)
    case row.takes_a_send {
      True -> {
        let assert Some(kept) = connection_state.entered_of(sent.status)
          as { row.name <> ": the player is still held" }
        assert kept.cast.creature_told == told()
          as { row.name <> ": a status that takes a send is written" }
      }
      False -> {
        assert sent.status == row.status
          as { row.name <> ": a status that takes no send is as it was" }
      }
    }
  })
}
