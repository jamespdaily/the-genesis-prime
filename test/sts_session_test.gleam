//// The rule of one STS connection, run through the client's login in the
//// order it sends it. The account is the SRP vector's (jim, secret, salt
//// 01 .. 10, the server's b = 51 .. 70; fact file
//// `vector.StsConnLib64.MT.dll!0x18002d4e0.srp`), so each answer holds the
//// bytes the library's own code made. The order of the requests and what each
//// answer holds are the records `StsConnLib64.MT.dll!0x180006fb0` (LoginStart),
//// `0x18000a350` (KeyData and the cipher), `0x1800043d0` (LoginFinish),
//// `0x180004950` (ListMyAccounts) and `0x180004ac0` (RequestGameToken); the
//// refusal's code is HandleLoginStartResult 0x1400b2f20 and
//// HandleLoginFinishResult 0x1400b3070.

import genesis_prime/login/account.{type Account, Account, Identity}
import genesis_prime/login/guid
import genesis_prime/login/srp
import genesis_prime/login/sts_message.{
  Connect, ConnectionOpened, GameAccount, KeyData, ListMyAccounts, LoginFinish,
  LoginStart, Ping, RequestGameToken, Transaction,
}
import genesis_prime/login/sts_session.{
  End, ExchangeFailed, FindAccount, IssueGameToken, OutOfOrder, Send,
  StartCipher, UnknownAccount, WrongIdentity,
}
import gleam/list
import gleam/option
import login_vectors as vector
import message_support
import owned_test

const user_id_text = "00112233-4455-6677-8899-aabbccddeeff"

const created = "2026-01-02T03:04:05Z"

fn user_id() -> guid.Guid {
  let assert Ok(parsed) = guid.from_text(user_id_text) as "a GUID text"
  parsed
}

fn account() -> Account {
  Account(
    name: vector.name,
    user_id: user_id(),
    salt: vector.salt(),
    verifier: vector.verifier(),
    created:,
  )
}

fn login_start() -> sts_message.Incoming {
  Transaction(
    1,
    LoginStart(login_name: vector.name, net_address: "192.168.1.5"),
  )
}

fn key_data(bytes: BitArray) -> sts_message.Incoming {
  Transaction(2, KeyData(bytes))
}

/// The session after LoginStart and the account's lookup.
fn after_the_first_key_data() -> sts_session.Session {
  let #(session, _) = sts_session.receive(sts_session.new(), login_start())
  let #(session, _) =
    sts_session.account_found(session, Ok(account()), vector.server_secret())
  session
}

/// The session after the client proved its password.
fn after_the_proof() -> sts_session.Session {
  let #(session, _) =
    sts_session.receive(
      after_the_first_key_data(),
      key_data(vector.client_key_data()),
    )
  session
}

fn after_login_finish() -> sts_session.Session {
  let #(session, _) =
    sts_session.receive(after_the_proof(), Transaction(3, LoginFinish))
  session
}

fn after_the_list() -> sts_session.Session {
  let #(session, _) =
    sts_session.receive(
      after_login_finish(),
      Transaction(
        4,
        ListMyAccounts(user_id: user_id_text, game_code: sts_message.game_code),
      ),
    )
  session
}

fn refusal(sequence: Int) -> sts_session.Effect {
  Send(
    sts_message.encode(sts_message.Refused(
      sequence:,
      code: sts_session.invalid_login_code,
    )),
  )
}

pub fn the_refusal_code_is_one_the_client_maps_to_its_invalid_login_event_test() -> Nil {
  use <- owned_test.run(5000)
  assert list.contains([10, 11, 3002], sts_session.invalid_login_code)
    as "HandleLoginStartResult 0x1400b2f20 maps 10, 11 and 3002 to event 16, and HandleLoginFinishResult 0x1400b3070 maps 10, 11, 3002, 3010 and 3310 to it"
}

pub fn login_start_asks_for_the_account_of_that_name_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = sts_session.receive(sts_session.new(), login_start())
  assert effects == [FindAccount("jim")]
    as "StsConnLib64.MT.dll!0x180006fb0: LoginStart names the account by LoginName, and the server holds its verifier"
}

pub fn an_account_that_is_found_gets_the_vectors_first_key_data_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) = sts_session.receive(sts_session.new(), login_start())
  let #(_, effects) =
    sts_session.account_found(session, Ok(account()), vector.server_secret())
  assert effects
    == [
      Send(
        sts_message.encode(sts_message.KeyDataAnswer(
          sequence: 1,
          key_data: vector.server_key_data(),
        )),
      ),
    ]
    as "vector.StsConnLib64.MT.dll!0x18002d4e0.srp: the server's first KeyData (the salt and B) in the reply to sequence 1 (StsConnLib64.MT.dll!0x18000a350)"
}

pub fn a_client_that_proves_its_password_gets_m2_and_then_the_cipher_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    sts_session.receive(
      after_the_first_key_data(),
      key_data(vector.client_key_data()),
    )
  assert effects
    == [
      Send(
        sts_message.encode(sts_message.KeyDataAnswer(
          sequence: 2,
          key_data: vector.second_server_key_data(),
        )),
      ),
      StartCipher(vector.session_key()),
    ]
    as "vector.StsConnLib64.MT.dll!0x18002d4e0.srp: M2 and K; StsConnLib64.MT.dll!0x18000a350: the library puts RC4 under K on the connection after the exchange, from the next byte, so M2 goes out in the clear first"
}

pub fn login_finish_answers_with_the_user_id_and_the_name_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    sts_session.receive(after_the_proof(), Transaction(3, LoginFinish))
  assert effects
    == [
      Send(
        sts_message.encode(sts_message.LoginFinished(
          sequence: 3,
          user_id: user_id_text,
          user_name: "jim",
        )),
      ),
    ]
    as "StsConnLib64.MT.dll!0x1800043d0: the reply holds AuthType 0, and the client keeps UserId and UserName; the account's GUID is the UserId"
}

pub fn the_account_list_holds_exactly_the_one_game_account_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    sts_session.receive(
      after_login_finish(),
      Transaction(
        4,
        ListMyAccounts(user_id: user_id_text, game_code: sts_message.game_code),
      ),
    )
  assert effects
    == [
      Send(
        sts_message.encode(
          sts_message.GameAccounts(sequence: 4, accounts: [
            GameAccount(alias: "jim", created:, game_account_id: user_id_text),
          ]),
        ),
      ),
    ]
    as "HandleListMyAccountsResult 0x1400b36c0 and StsConnLib64.MT.dll!0x180004950: exactly one game account is required, with Alias, Created and GameAccountId"
}

pub fn a_game_token_is_issued_for_the_logged_in_identity_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    sts_session.receive(
      after_the_list(),
      Transaction(
        5,
        RequestGameToken(
          user_id: user_id_text,
          game_code: sts_message.game_code,
          account_alias: "jim",
        ),
      ),
    )
  assert effects == [IssueGameToken(Identity(name: "jim", user_id: user_id()))]
    as "StsConnLib64.MT.dll!0x180004ac0 and opcode.0x592: the token the reply holds is the second GUID of the login request, which is checked against the STS login"
}

pub fn the_issued_token_is_the_reply_as_a_guid_text_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) =
    sts_session.receive(
      after_the_list(),
      Transaction(
        5,
        RequestGameToken(
          user_id: user_id_text,
          game_code: sts_message.game_code,
          account_alias: "jim",
        ),
      ),
    )
  let token = message_support.hex("33221100 5544 7766 8899 aabbccddeeff")
  let #(_, effects) = sts_session.game_token_issued(session, token)
  assert effects
    == [
      Send(
        sts_message.encode(sts_message.GameToken(
          sequence: 5,
          token: "00112233-4455-6677-8899-aabbccddeeff",
        )),
      ),
    ]
    as "HandleRequestGameTokenResult 0x1400b3a50 and SendAuthLoginRequest 0x14003a620: the client keeps the Token text and 0x592 parses its second GUID from it with UuidFromStringA, so the text of the token's 16 wire bytes is what names them"
}

pub fn an_account_that_does_not_exist_is_refused_with_the_invalid_login_code_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) = sts_session.receive(sts_session.new(), login_start())
  let #(_, effects) =
    sts_session.account_found(session, Error(Nil), vector.server_secret())
  assert effects == [refusal(1), End(UnknownAccount("jim"))]
    as "HandleLoginStartResult 0x1400b2f20: 10, 11 and 3002 raise event 16; the same refusal as a wrong secret tells a client nothing of which accounts exist"
}

pub fn a_wrong_secret_is_refused_and_no_cipher_starts_test() -> Nil {
  use <- owned_test.run(5000)
  let other = srp.verifier(name: "jim", password: "Secret", salt: vector.salt())
  let #(session, _) = sts_session.receive(sts_session.new(), login_start())
  let #(session, _) =
    sts_session.account_found(
      session,
      Ok(Account(..account(), verifier: other)),
      vector.server_secret(),
    )
  let #(_, effects) =
    sts_session.receive(session, key_data(vector.client_key_data()))
  assert effects == [refusal(2), End(ExchangeFailed("jim", srp.ProofRefused))]
    as "vector.StsConnLib64.MT.dll!0x18002d4e0.srp: M1 holds the verifier, so a client that typed another password cannot make it; the failure of the KeyData step is a refusal with the invalid login code"
}

pub fn key_data_that_is_not_a_and_m1_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    sts_session.receive(after_the_first_key_data(), key_data(<<1, 2, 3>>))
  assert effects
    == [refusal(2), End(ExchangeFailed("jim", srp.KeyDataMalformed))]
    as "StsConnLib64.MT.dll!0x18002d4e0: the client's answer is a length and A, then a length and M1"
}

pub fn a_request_out_of_the_logins_order_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let fresh = sts_session.new()
  assert sts_session.receive(fresh, Transaction(3, LoginFinish)).1
    == [End(OutOfOrder("LoginFinish"))]
    as "StsConnLib64.MT.dll!0x1800043d0: LoginFinish follows the SRP exchange"
  assert sts_session.receive(fresh, key_data(<<>>)).1
    == [End(OutOfOrder("KeyData"))]
    as "StsConnLib64.MT.dll!0x18000a350: KeyData answers the first key data of LoginStart"
  assert sts_session.receive(
      after_the_proof(),
      Transaction(
        4,
        ListMyAccounts(user_id: user_id_text, game_code: sts_message.game_code),
      ),
    ).1
    == [End(OutOfOrder("ListMyAccounts"))]
    as "HandleLoginFinishResult 0x1400b3070: the client sends ListMyAccounts after LoginFinish's reply"
  assert sts_session.receive(
      after_login_finish(),
      Transaction(
        5,
        RequestGameToken(
          user_id: user_id_text,
          game_code: sts_message.game_code,
          account_alias: "jim",
        ),
      ),
    ).1
    == [End(OutOfOrder("RequestGameToken"))]
    as "HandleListMyAccountsResult 0x1400b36c0: the client sends RequestGameToken after ListMyAccounts's reply"
  assert sts_session.receive(after_the_proof(), login_start()).1
    == [End(OutOfOrder("LoginStart"))]
    as "StsConnLib64.MT.dll!0x180006fb0: the login starts once"
}

pub fn a_request_for_another_user_id_game_code_or_alias_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let other_id = "ffeeddcc-bbaa-9988-7766-554433221100"
  assert sts_session.receive(
      after_login_finish(),
      Transaction(
        4,
        ListMyAccounts(user_id: other_id, game_code: sts_message.game_code),
      ),
    ).1
    == [End(WrongIdentity("ListMyAccounts"))]
    as "StsConnLib64.MT.dll!0x180004950: ListMyAccounts carries the UserId LoginFinish's reply gave"
  assert sts_session.receive(
      after_login_finish(),
      Transaction(4, ListMyAccounts(user_id: user_id_text, game_code: "other")),
    ).1
    == [End(WrongIdentity("ListMyAccounts"))]
    as "GetNcAppGroupCode 0x140018aa0: the game code is wildstar"
  assert sts_session.receive(
      after_the_list(),
      Transaction(
        5,
        RequestGameToken(
          user_id: user_id_text,
          game_code: sts_message.game_code,
          account_alias: "someone",
        ),
      ),
    ).1
    == [End(WrongIdentity("RequestGameToken"))]
    as "StsConnLib64.MT.dll!0x180004ac0: the alias is the one game account's Alias, which ListMyAccounts gave"
}

pub fn no_game_token_is_issued_after_a_refusal_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) = sts_session.receive(sts_session.new(), login_start())
  let #(session, _) =
    sts_session.account_found(session, Error(Nil), vector.server_secret())
  let #(_, effects) =
    sts_session.receive(
      session,
      Transaction(
        5,
        RequestGameToken(
          user_id: user_id_text,
          game_code: sts_message.game_code,
          account_alias: "jim",
        ),
      ),
    )
  assert effects == []
    as "after an End effect the rule has no more effects, so no game token is issued for a login that was refused"
}

pub fn connect_and_ping_are_accepted_at_any_point_and_change_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let connect =
    ConnectionOpened(Connect(
      connection_type: 1281,
      connection_product_type: 0,
      connection_app_index: 0,
      connection_deployment: 0,
      connection_epoch: 0,
      address: option.None,
      product_type: 0,
      app_index: 0,
      deployment: 0,
      epoch: 0,
      program: 0,
      build: 0,
      process: 0,
      notify_flags: 0,
      version_flags: 0,
    ))
  assert sts_session.receive(sts_session.new(), connect).1 == []
    as "StsConnLib64.MT.dll!0x18002f410: Connect is one-way, no reply is awaited"
  assert sts_session.receive(after_the_proof(), Ping).1 == []
    as "StsConnLib64.MT.dll!0x18002f370: Ping is a one-way keep-alive, no reply is awaited"
}

pub fn the_reasons_say_what_ended_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  assert sts_session.describe(UnknownAccount("jim"))
    != sts_session.describe(ExchangeFailed("jim", srp.ProofRefused))
    as "each reason is its own sentence"
}
