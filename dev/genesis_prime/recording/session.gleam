//// What a session folder holds besides the recordings, which a replay needs
//// and a recording does not carry: which connection each recording was made
//// by, the random draws each connection made, and the account rows the logins
//// used.
////
//// A server that records a session writes each draw of random bytes with the
//// connection that made it (`draws`), and each account a login found
//// (`accounts`). A connection is the listener it reached, its peer address and
//// the order it started in (`random_source.Connection`); the same peer address
//// can reach both listeners at once and can be used again later in a session,
//// so the three together name it. The relay writes, for each recording, the
//// same three in the terms it knows (`<role>-<number>.connection`): the role,
//// the address it connected to the server from, which is the peer address the
//// server saw, and the incarnation, how many earlier connections of that role
//// and address the folder holds. A replay finds a recording's draws by that
//// key and supplies them, in order, to the connection it replays. The server's
//// start orders are ranked within a role and an address to give the
//// incarnations, so a connection that made no draw is not counted by the
//// ranking, and one that came before another of the same role and address
//// moves the other's incarnation in the relay's count but not in the server's.
////
//// The layout of `draws` and `accounts`: a list of entries with nothing between
//// them, every integer unsigned and big-endian. A text is its length in bytes
//// (16 bits) and that many bytes of UTF-8; a byte string is its length (16 bits)
//// and its bytes.
//// - a draw: the connection as one byte, 0 for none or 1 followed by the
////   role (one byte, 0 for STS and 1 for auth), the peer address as a text and
////   the start order (64 bits, signed); and then the bytes drawn.
//// - an account: the name as a text, the user id as a text in the GUID's
////   written form, the salt and the verifier as byte strings.
//// The `.connection` file holds, as text, the role's name, the address and the
//// incarnation, separated by single spaces.
////
//// A file that ends inside an entry is read as an error naming the offset
//// where the entry began, so a session stopped between two writes can be read
//// up to there.

import genesis_prime/login/random_source
import genesis_prime/recording.{type Role}
import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile.{type FileError}

/// One draw of random bytes and the connection that made it, or none when the
/// socket had no peer.
pub type Draw {
  Draw(connection: Option(random_source.Connection), bytes: BitArray)
}

/// A connection as a replay looks for it: the role it reached, its peer
/// address, and its incarnation, 0 for the first connection of that role and
/// address in the session, 1 for the next, and so on.
pub type Key {
  Key(role: Role, peer: String, incarnation: Int)
}

/// An account row a login used: what a replay inserts into a fresh database
/// for the login to find. `user_id` is the GUID in its written form.
pub type UsedAccount {
  UsedAccount(name: String, user_id: String, salt: BitArray, verifier: BitArray)
}

/// What a session folder holds: the draws in the order they were written, and
/// the accounts, one for each name.
pub type Session {
  Session(draws: List(Draw), accounts: List(UsedAccount))
}

/// Why a file of the session could not be written or read.
pub type SessionError {
  /// A file ends inside an entry, which began `offset` bytes from its start.
  Truncated(file: String, offset: Int)
  /// A text in a file is not UTF-8.
  NotText(file: String, offset: Int)
  /// The connection flag of a draw is neither 0 nor 1.
  UnknownFlag(file: String, offset: Int, value: Int)
  /// A value does not fit its width in the file: a text or a byte string
  /// longer than 65535 bytes.
  TooLong(field: String, size: Int)
  /// The file system refused a read or a write.
  FileFailed(path: String, error: FileError)
}

/// The folder's file of draws.
const draws_file = "draws"

/// The folder's file of accounts.
const accounts_file = "accounts"

/// The suffix of a recording's file name, and of the file beside it that holds
/// the address its connection was made from.
const recording_suffix = ".recording"

const connection_suffix = ".connection"

/// The most bytes a text or a byte string holds: what 16 bits count.
const longest = 65_535

/// Adds a draw to the end of the folder's `draws` file, which is made when
/// missing.
pub fn append_draw(
  folder _folder: String,
  draw _draw: Draw,
) -> Result(Nil, SessionError) {
  panic as "shape only: built after the tests"
}

/// Adds an account to the end of the folder's `accounts` file, which is made
/// when missing.
pub fn append_account(
  folder folder: String,
  account account: UsedAccount,
) -> Result(Nil, SessionError) {
  use name <- result.try(encode_text("name", account.name))
  use user_id <- result.try(encode_text("user id", account.user_id))
  use salt <- result.try(encode_bytes("salt", account.salt))
  use verifier <- result.try(encode_bytes("verifier", account.verifier))
  append(folder <> "/" <> accounts_file, <<
    name:bits,
    user_id:bits,
    salt:bits,
    verifier:bits,
  >>)
}

fn append(path: String, bytes: BitArray) -> Result(Nil, SessionError) {
  simplifile.append_bits(path, bytes)
  |> result.map_error(FileFailed(path:, error: _))
}

fn encode_text(field: String, text: String) -> Result(BitArray, SessionError) {
  encode_bytes(field, bit_array.from_string(text))
}

fn encode_bytes(
  field: String,
  bytes: BitArray,
) -> Result(BitArray, SessionError) {
  let size = bit_array.byte_size(bytes)
  use <- bool.guard(size > longest, Error(TooLong(field:, size:)))
  Ok(<<size:size(16), bytes:bits>>)
}

/// The draws and the accounts of the folder. A file that is not there is empty,
/// as a session recorded without the recording server has neither. An account
/// written more than once is read once, as its first entry holds it.
pub fn read(folder folder: String) -> Result(Session, SessionError) {
  use draws <- result.try(read_entries(
    folder <> "/" <> draws_file,
    draws_file,
    decode_draw,
  ))
  use accounts <- result.map(read_entries(
    folder <> "/" <> accounts_file,
    accounts_file,
    decode_account,
  ))
  Session(draws:, accounts: first_of_each_name(accounts))
}

/// The accounts with only the first entry of each name, in their order.
fn first_of_each_name(accounts: List(UsedAccount)) -> List(UsedAccount) {
  let #(kept, _) =
    list.fold(accounts, #([], dict.new()), fn(built, account) {
      let #(kept, seen) = built
      case dict.has_key(seen, account.name) {
        True -> built
        False -> #([account, ..kept], dict.insert(seen, account.name, Nil))
      }
    })
  list.reverse(kept)
}

/// The entries of the file at `path`, none when it is not there. `decode` reads
/// one entry from the front of the bytes and gives it with what follows, or
/// the error of an entry that is not whole at `offset`.
fn read_entries(
  path: String,
  file: String,
  decode: fn(BitArray, String, Int) -> Result(#(entry, BitArray), SessionError),
) -> Result(List(entry), SessionError) {
  case simplifile.read_bits(path) {
    Error(simplifile.Enoent) -> Ok([])
    Error(error) -> Error(FileFailed(path:, error:))
    Ok(bytes) -> decode_entries(bytes:, file:, decode:, offset: 0, entries: [])
  }
}

fn decode_entries(
  bytes bytes: BitArray,
  file file: String,
  decode decode: fn(BitArray, String, Int) ->
    Result(#(entry, BitArray), SessionError),
  offset offset: Int,
  entries entries: List(entry),
) -> Result(List(entry), SessionError) {
  case bytes {
    <<>> -> Ok(list.reverse(entries))
    _ -> {
      use #(entry, rest) <- result.try(decode(bytes, file, offset))
      decode_entries(
        bytes: rest,
        file:,
        decode:,
        offset: offset + bit_array.byte_size(bytes) - bit_array.byte_size(rest),
        entries: [entry, ..entries],
      )
    }
  }
}

fn decode_draw(
  bytes _bytes: BitArray,
  file _file: String,
  offset _offset: Int,
) -> Result(#(Draw, BitArray), SessionError) {
  panic as "shape only: built after the tests"
}

fn decode_account(
  bytes bytes: BitArray,
  file file: String,
  offset offset: Int,
) -> Result(#(UsedAccount, BitArray), SessionError) {
  use #(name, after_name) <- result.try(take_text(bytes:, file:, offset:))
  use #(user_id, after_user_id) <- result.try(take_text(
    bytes: after_name,
    file:,
    offset:,
  ))
  use #(salt, after_salt) <- result.try(take_bytes(
    bytes: after_user_id,
    file:,
    offset:,
  ))
  use #(verifier, rest) <- result.map(take_bytes(
    bytes: after_salt,
    file:,
    offset:,
  ))
  #(UsedAccount(name:, user_id:, salt:, verifier:), rest)
}

/// A byte string from the front of `bytes`, and what follows it. The entry it
/// belongs to began at `offset`.
fn take_bytes(
  bytes bytes: BitArray,
  file file: String,
  offset offset: Int,
) -> Result(#(BitArray, BitArray), SessionError) {
  case bytes {
    <<length:size(16), taken:bytes-size(length), rest:bytes>> ->
      Ok(#(taken, rest))
    _ -> Error(Truncated(file:, offset:))
  }
}

fn take_text(
  bytes bytes: BitArray,
  file file: String,
  offset offset: Int,
) -> Result(#(String, BitArray), SessionError) {
  use #(taken, rest) <- result.try(take_bytes(bytes:, file:, offset:))
  case bit_array.to_string(taken) {
    Ok(text) -> Ok(#(text, rest))
    Error(Nil) -> Error(NotText(file:, offset:))
  }
}

/// The role a login listener's connection has in a recording's header.
pub fn role_of(role: random_source.Role) -> Role {
  case role {
    random_source.Sts -> recording.Sts
    random_source.Auth -> recording.Auth
  }
}

/// The bytes of the draws the connection of the key made, in the order it made
/// them.
pub fn draws_of(session _session: Session, key _key: Key) -> List(BitArray) {
  panic as "shape only: built after the tests"
}

/// Every connection of the session that made a draw, as a replay would look
/// for it, in the order the connections started.
pub fn connections(session _session: Session) -> List(Key) {
  panic as "shape only: built after the tests"
}

/// Writes the key of a recording's connection beside the recording at
/// `recording_path`, in the file that has the recording's name with
/// `.connection` for `.recording`: the role, the address the relay connected to
/// the server from, and the incarnation, which is how many connection files of
/// that role and address the folder already holds. A file already there is
/// replaced.
pub fn write_connection(
  recording_path _recording_path: String,
  role _role: Role,
  peer _peer: String,
) -> Result(Nil, SessionError) {
  panic as "shape only: built after the tests"
}

/// The key the recording at `recording_path` was made by, as the relay wrote
/// it.
pub fn read_connection(
  recording_path _recording_path: String,
) -> Result(Key, SessionError) {
  panic as "shape only: built after the tests"
}
