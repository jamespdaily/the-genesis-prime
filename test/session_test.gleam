//// The session folder's own files. The expected values are the issue's test 3:
//// the folder holds the accounts its logins used (the salt, the verifier and
//// the user id, which the login reads from the account's row and the STS reply
//// carries), and it reads back as written. The layout is the one written in the
//// doc comment of `genesis_prime/recording/session`.

import genesis_prime/login/account.{type Account, Account}
import genesis_prime/login/guid
import genesis_prime/login/random_source.{Draw}
import genesis_prime/recording/draw_log
import genesis_prime/recording/session.{Draw as SavedDraw, UsedAccount}
import gleam/bit_array
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor
import owned_test
import recording_support
import seeded
import simplifile

/// The account rows of two logins: names, user ids, salts (16 bytes, as
/// `account_store` draws them) and verifiers (128 bytes, an SRP value).
fn accounts() -> #(Account, Account) {
  let assert Ok(jim_id) = guid.from_text("3c6d9a52-1f4e-4b7a-9d2c-8e5a7b1c0f34")
    as "a GUID"
  let assert Ok(sam_id) = guid.from_text("a1b2c3d4-0000-4000-8000-00000000abcd")
    as "a GUID"
  let #(jim_salt, state) = seeded.bytes(state: 11, count: 16)
  let #(jim_verifier, state) = seeded.bytes(state:, count: 128)
  let #(sam_salt, state) = seeded.bytes(state:, count: 16)
  let #(sam_verifier, _) = seeded.bytes(state:, count: 128)
  #(
    Account(
      id: 1,
      name: "jim",
      user_id: jim_id,
      salt: jim_salt,
      verifier: jim_verifier,
      created: "2026-10-26T00:00:00Z",
    ),
    Account(
      id: 2,
      name: "sam",
      user_id: sam_id,
      salt: sam_salt,
      verifier: sam_verifier,
      created: "2026-10-26T00:00:00Z",
    ),
  )
}

fn used(account: Account) -> session.UsedAccount {
  UsedAccount(
    name: account.name,
    user_id: guid.to_text(account.user_id),
    salt: account.salt,
    verifier: account.verifier,
  )
}

pub fn the_session_folder_holds_the_accounts_its_logins_used_and_reads_back_test() -> Nil {
  use <- owned_test.run(30_000)
  let folder = recording_support.new_folder()
  let log_name = process.new_name("session_draw_log")
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(draw_log.supervised(name: log_name, folder:))
    |> static_supervisor.start
    as "the log process did not start"
  let random = draw_log.source(log_name)
  let #(jim, sam) = accounts()

  // Jim logs in twice, a wrong password and then the right one, and Sam once:
  // each login's SRP draw carries the row its login read.
  list.each([jim, sam, jim], fn(account) {
    let drawn =
      random_source.bytes(
        random,
        Draw(
          count: 32,
          connection: Some("127.0.0.1:" <> account.name),
          account: Some(account),
        ),
      )
    assert bit_array.byte_size(drawn) == 32 as "the draw is as long as asked"
  })

  let assert Ok(saved) = session.read(folder) as "the session folder reads back"
  assert saved.accounts == [used(jim), used(sam)]
    as "the folder holds each account its logins used once, with the salt, the verifier and the user id its login read"
  assert list.length(saved.draws) == 3 as "every draw was written"
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder is removed"
  Nil
}

pub fn a_login_for_an_account_that_is_not_found_leaves_no_account_in_the_folder_test() -> Nil {
  use <- owned_test.run(30_000)
  let folder = recording_support.new_folder()
  let log_name = process.new_name("session_draw_log")
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(draw_log.supervised(name: log_name, folder:))
    |> static_supervisor.start
    as "the log process did not start"
  let _ =
    random_source.bytes(
      draw_log.source(log_name),
      Draw(count: 32, connection: Some("127.0.0.1:1"), account: None),
    )
  let assert Ok(saved) = session.read(folder) as "the session folder reads back"
  assert saved.accounts == []
    as "a login that found no account used no row, so the folder holds none"
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder is removed"
  Nil
}

pub fn draws_accounts_and_a_connection_file_read_back_as_written_test() -> Nil {
  use <- owned_test.run(30_000)
  let folder = recording_support.new_folder()
  let #(jim, sam) = accounts()
  let draws = random_draws(count: 25, seed: 72)
  list.each(draws, fn(draw) {
    let assert Ok(Nil) = session.append_draw(folder:, draw:)
      as "a draw was written"
  })
  list.each([used(jim), used(sam)], fn(account) {
    let assert Ok(Nil) = session.append_account(folder:, account:)
      as "an account was written"
  })
  let path = folder <> "/sts-001.recording"
  let assert Ok(Nil) =
    session.write_connection(
      recording_path: path,
      connection: "127.0.0.1:40001",
    )
    as "the connection file was written"

  assert session.read(folder)
    == Ok(session.Session(draws:, accounts: [used(jim), used(sam)]))
    as "the draws, some with no connection, and the accounts read back in the order they were written"
  assert session.read_connection(recording_path: path) == Ok("127.0.0.1:40001")
    as "the connection file reads back"
  assert simplifile.read(folder <> "/sts-001.connection")
    == Ok("127.0.0.1:40001")
    as "the file beside `sts-001.recording` is `sts-001.connection` and holds the address as text"
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder is removed"
  Nil
}

fn random_draws(count count: Int, seed seed: Int) -> List(session.Draw) {
  let #(draws, _) =
    int.range(from: 1, to: count + 1, with: #([], seed), run: fn(built, number) {
      let #(draws, state) = built
      let #(length, state) = seeded.up_to(state:, most: 40)
      let #(bytes, state) = seeded.bytes(state:, count: length)
      let connection = case number % 4 {
        0 -> None
        _ -> Some("127.0.0.1:" <> int.to_string(number))
      }
      #([SavedDraw(connection:, bytes:), ..draws], state)
    })
  list.reverse(draws)
}

pub fn a_draws_file_that_ends_inside_an_entry_is_read_as_truncated_where_the_entry_began_test() -> Nil {
  use <- owned_test.run(30_000)
  let folder = recording_support.new_folder()
  // The layout in the doc comment: a draw with a connection is the flag 1, the
  // text (16-bit length and its bytes), and the bytes (16-bit length and bytes).
  // This one is 1 + 2 + 5 + 2 + 3 = 13 bytes, and the second starts at 13.
  let assert Ok(Nil) =
    session.append_draw(
      folder:,
      draw: SavedDraw(connection: Some("a:123"), bytes: <<1, 2, 3>>),
    )
    as "a draw was written"
  let assert Ok(Nil) =
    session.append_draw(
      folder:,
      draw: SavedDraw(connection: None, bytes: <<9, 9>>),
    )
    as "a second draw was written"
  let assert Ok(whole) = simplifile.read_bits(folder <> "/draws")
    as "the draws file reads"
  assert bit_array.byte_size(whole) == 13 + 1 + 2 + 2
    as "the second draw, with no connection, is the flag 0, the length and two bytes"
  let assert Ok(cut) = bit_array.slice(whole, 0, 17)
    as "one byte less than the file"
  let assert Ok(Nil) = simplifile.write_bits(folder <> "/draws", cut)
    as "the file is cut"
  assert session.read(folder)
    == Error(session.Truncated(file: "draws", offset: 13))
    as "the second entry began at byte 13 and the file ends inside it"
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder is removed"
  Nil
}
