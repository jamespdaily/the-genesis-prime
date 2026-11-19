//// The tests' account store: a pool and the store on a migrated database of the test's own
//// (`test/database_support.gleam`), and the asks the store tests and the connection tests that
//// use the real store share: an account, a created character, a login and the items it holds.

import ask_support
import database_support
import genesis_prime/login/guid
import genesis_prime/service.{ToWorker}
import genesis_prime/store.{
  type AccountId, AccountId, BuyFromVendor, CharacterCreated, CharacterLoaded,
  CreateCharacter, Created, DeleteItem, ForSelect, ForWorld, LoadCharacter,
  LookEntry, MergeItems, MoveItems, NewCharacter, Select, SellToVendor,
  SpendItem, SplitItem, TurnInQuest, World,
}
import genesis_prime/store/worker
import genesis_prime/table/id.{CharacterCustomizationLabelId, ClassId, RaceId}
import gleam/erlang/process
import gleam/list
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor as supervisor
import login_support
import place_support
import pog
import readiness_support

/// A new character with the values of CharacterCreation row 466 (class 1,
/// race 1, sex 1, faction 167), the level 3 of a Veteran row's xp 1710, the
/// path 2, the start place of WorldLocation2 row 51596 and a look and bones.
pub fn a_new_character(name: String) -> store.NewCharacter {
  NewCharacter(
    name:,
    gender: 1,
    race_id: RaceId(1),
    class_id: ClassId(1),
    faction_id: 167,
    level: 3,
    experience: 1710,
    path: 2,
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.128599166870117,
      y: -853.87158203125,
      z: -560.18798828125,
    ),
    look: [
      LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
      LookEntry(label: CharacterCustomizationLabelId(22), value: 4_000_000_000),
    ],
    // 0xBF800000 is -1.0 and has its top bit set; 0x3F800000 is 1.0.
    bones: [0xBF800000, 0x3F800000, 0],
    starting_items: [],
    starting_credits: 1000,
  )
}

/// A create of the character that starts with these items.
pub fn create_holding(
  store store: Store,
  account account: AccountId,
  name name: String,
  slots slots: Int,
  items items: List(store.NewItem),
) -> store.CreateAnswer {
  let assert ForSelect(Created(answer)) =
    ask(
      store:,
      request: Select(CreateCharacter(
        account_id: account,
        character: NewCharacter(..a_new_character(name), starting_items: items),
        character_slots: slots,
      )),
    )
    as "a create is answered with a create's answer"
  answer
}

pub fn insert_account(
  store store: Store,
  login_name login_name: String,
) -> AccountId {
  AccountId(login_support.insert_account(
    pool: store.pool,
    login_name:,
    salt: <<1>>,
    verifier: <<2>>,
    game_account_id: game_account_id_of(login_name),
  ))
}

/// A game account id for each login name, so two accounts differ.
fn game_account_id_of(login_name: String) -> guid.Guid {
  let assert Ok(game_account_id) = case login_name {
    "login-1" -> guid.from_text("01234567-89ab-cdef-0123-456789abcdef")
    _ -> guid.from_text("76543210-89ab-cdef-0123-456789abcdef")
  }
    as "the text is a GUID"
  game_account_id
}

/// A running pool and store: the tree they run in, the pool as a connection
/// for queries and the store's name.
pub type Store {
  Store(
    tree: process.Pid,
    pool: pog.Connection,
    name: process.Name(factory_supervisor.Message(worker.Job, Nil)),
  )
}

/// A pool of `pool_size` connections to a migrated database of its own, and the
/// store on it, started once the pool has its connections.
pub fn start_store(pool_size pool_size: Int) -> Store {
  let shared = database_support.shared()
  start_store_in(
    database: database_support.new_database(on: shared),
    pool_size:,
  )
}

/// A pool of `pool_size` connections to `database`, a migrated database, and
/// the store on it, started once the pool has its connections.
pub fn start_store_in(
  database database: String,
  pool_size pool_size: Int,
) -> Store {
  let config =
    database_support.config(
      for: database_support.shared().settings,
      database:,
      pool_name: process.new_name("account_pool"),
      pool_size:,
    )
  let store = start_store_on(config)
  readiness_support.await(tree: store.tree, store: store.name)
  store
}

/// The pool `config` describes and the store on it, as children of a tree.
pub fn start_store_on(config: pog.Config) -> Store {
  let name = process.new_name("store")
  let pool = pog.named_connection(config.pool_name)
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(pog.supervised(config))
    |> supervisor.add(worker.supervised(name:, pool:))
    |> supervisor.start
    as "the pool and the store started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  Store(tree: started.pid, pool:, name:)
}

pub fn stop(store: Store) -> Nil {
  let _reason = ask_support.stop_tree(store.tree)
  Nil
}

/// Asks the store and waits for the answer.
pub fn ask(store store: Store, request request: store.Request) -> store.Answer {
  let #(sent, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      worker.ask(store.name, request, reply)
    })
  let assert ToWorker(_) = sent as "the store started a worker"
  answer
}

/// The items the store loads for the character, in the order it sends them.
pub fn held_by(
  store store: Store,
  account account: AccountId,
  character_id character_id: store.CharacterId,
) -> List(store.HeldItem) {
  let assert ForWorld(CharacterLoaded(items:, ..)) =
    ask(store:, request: World(LoadCharacter(account, character_id, 0)))
    as "the account's character loads"
  items
}

/// A login: the epoch it is told and the items it finds. Each load raises the
/// epoch, so a request is made under the epoch of the login just before it.
pub fn login(
  store store: Store,
  account account: AccountId,
  character_id character_id: store.CharacterId,
) -> #(Int, List(store.HeldItem)) {
  let assert ForWorld(CharacterLoaded(session_epoch:, items:, ..)) =
    ask(store:, request: World(LoadCharacter(account, character_id, 0)))
    as "the account's character loads"
  #(store.session_epoch_number(session_epoch), items)
}

/// A character the real store holds, with its account.
pub type Stored {
  Stored(store: Store, account: AccountId, character_id: store.CharacterId)
}

/// A stored character holding the `worn` items and these `items` in its bags, on a store of
/// its own.
pub fn stored_holding(
  worn worn: List(store.NewItem),
  items items: List(store.NewItem),
) -> Stored {
  stored_holding_credits(
    worn:,
    items:,
    starting_credits: a_new_character("Ab Cd").starting_credits,
  )
}

/// As `stored_holding`, for a character created with `starting_credits`: with 0 it has no
/// credits row (`create_character.sql` makes one only above 0).
pub fn stored_holding_credits(
  worn worn: List(store.NewItem),
  items items: List(store.NewItem),
  starting_credits starting_credits: Int,
) -> Stored {
  let store = start_store(pool_size: 2)
  let account = insert_account(store:, login_name: "login-1")
  let assert ForSelect(Created(CharacterCreated(character_id:))) =
    ask(
      store:,
      request: Select(CreateCharacter(
        account_id: account,
        character: NewCharacter(
          ..a_new_character("Ab Cd"),
          starting_items: list.append(worn, items),
          starting_credits:,
        ),
        character_slots: 1,
      )),
    )
    as "a character holding the worn items and the bag items"
  Stored(store:, account:, character_id:)
}

/// The items the stored character holds now, as a login finds them, with the epoch the login
/// was told. A login raises the character's epoch, so a request is made under the epoch of
/// the login just before it.
pub fn loaded(stored stored: Stored) -> #(Int, List(store.HeldItem)) {
  login(
    store: stored.store,
    account: stored.account,
    character_id: stored.character_id,
  )
}

/// The connection's items request made the stored character's own: its account and id, and
/// the epoch of a login just before it.
pub fn own_request(
  stored stored: Stored,
  request request: store.ItemsRequest,
) -> store.ItemsRequest {
  let #(epoch, _) = loaded(stored:)
  let assert Ok(session_epoch) = store.session_epoch(epoch)
    as "a login's epoch is 1 or more"
  let account_id = stored.account
  let character_id = stored.character_id
  case request {
    MoveItems(..) ->
      MoveItems(..request, account_id:, character_id:, session_epoch:)
    SplitItem(..) ->
      SplitItem(..request, account_id:, character_id:, session_epoch:)
    MergeItems(..) ->
      MergeItems(..request, account_id:, character_id:, session_epoch:)
    DeleteItem(..) ->
      DeleteItem(..request, account_id:, character_id:, session_epoch:)
    SpendItem(..) ->
      SpendItem(..request, account_id:, character_id:, session_epoch:)
    BuyFromVendor(..) ->
      BuyFromVendor(..request, account_id:, character_id:, session_epoch:)
    SellToVendor(..) ->
      SellToVendor(..request, account_id:, character_id:, session_epoch:)
    TurnInQuest(..) ->
      TurnInQuest(..request, account_id:, character_id:, session_epoch:)
  }
}
