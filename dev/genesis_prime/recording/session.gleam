//// What a session folder holds besides the recordings, which a replay needs
//// and a recording does not carry: which connection each recording was made
//// by, the random draws each connection made, and the account rows the logins
//// used.
////
//// A server that records a session writes each draw of random bytes with the
//// peer address of the connection that made it (`draws`), and each account a
//// login found (`accounts`). The relay writes, for each recording, the
//// address it connected to the server from (`<role>-<number>.connection`),
//// which is the peer address the server saw for that connection. A replay
//// finds a recording's draws by that address and supplies them, in order, to
//// the connection it replays.
////
//// The layout of `draws` and `accounts`: a list of entries with nothing between
//// them, every integer unsigned and big-endian. A text is its length in bytes
//// (16 bits) and that many bytes of UTF-8; a byte string is its length (16 bits)
//// and its bytes.
//// - a draw: the connection as one byte, 0 for none or 1 followed by a text,
////   and then the bytes drawn.
//// - an account: the name as a text, the user id as a text in the GUID's
////   written form, the salt and the verifier as byte strings.
//// The `.connection` file holds the address as text, with no length.
////
//// A file that ends inside an entry is read as an error naming the offset
//// where the entry began, so a session stopped between two writes can be read
//// up to there.

import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile.{type FileError}

/// One draw of random bytes and the connection that made it, as the peer
/// address of its socket, or none when the socket had no peer.
pub type Draw {
  Draw(connection: Option(String), bytes: BitArray)
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
  folder folder: String,
  draw draw: Draw,
) -> Result(Nil, SessionError) {
  use connection <- result.try(case draw.connection {
    None -> Ok(<<0>>)
    Some(text) -> {
      use text <- result.map(encode_text("connection", text))
      <<1, text:bits>>
    }
  })
  use bytes <- result.try(encode_bytes("draw", draw.bytes))
  append(folder <> "/" <> draws_file, <<connection:bits, bytes:bits>>)
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
  bytes bytes: BitArray,
  file file: String,
  offset offset: Int,
) -> Result(#(Draw, BitArray), SessionError) {
  case bytes {
    <<0, rest:bytes>> ->
      decode_draw_bytes(connection: None, bytes: rest, file:, offset:)
    <<1, rest:bytes>> -> {
      use #(connection, after) <- result.try(take_text(
        bytes: rest,
        file:,
        offset:,
      ))
      decode_draw_bytes(
        connection: Some(connection),
        bytes: after,
        file:,
        offset:,
      )
    }
    <<value, _:bytes>> -> Error(UnknownFlag(file:, offset:, value:))
    _ -> Error(Truncated(file:, offset:))
  }
}

fn decode_draw_bytes(
  connection connection: Option(String),
  bytes bytes: BitArray,
  file file: String,
  offset offset: Int,
) -> Result(#(Draw, BitArray), SessionError) {
  use #(drawn, rest) <- result.map(take_bytes(bytes:, file:, offset:))
  #(Draw(connection:, bytes: drawn), rest)
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

/// The bytes of the draws one connection made, in the order it made them.
pub fn draws_of(
  session session: Session,
  connection connection: String,
) -> List(BitArray) {
  list.filter_map(session.draws, fn(draw) {
    case draw.connection == Some(connection) {
      True -> Ok(draw.bytes)
      False -> Error(Nil)
    }
  })
}

/// Writes the address a recording's connection reached the server from beside
/// the recording at `recording_path`, in the file that has the recording's name
/// with `.connection` for `.recording`. A file already there is replaced.
pub fn write_connection(
  recording_path recording_path: String,
  connection connection: String,
) -> Result(Nil, SessionError) {
  let path = connection_path(recording_path)
  simplifile.write(path, connection)
  |> result.map_error(FileFailed(path:, error: _))
}

/// The address the recording at `recording_path` was made from, as the relay
/// wrote it.
pub fn read_connection(
  recording_path recording_path: String,
) -> Result(String, SessionError) {
  let path = connection_path(recording_path)
  simplifile.read(path) |> result.map_error(FileFailed(path:, error: _))
}

fn connection_path(recording_path: String) -> String {
  string.remove_suffix(recording_path, recording_suffix) <> connection_suffix
}
