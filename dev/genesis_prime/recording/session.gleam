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
import gleam/int
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
  /// The role byte of a draw's connection is neither 0 nor 1.
  UnknownRole(file: String, offset: Int, value: Int)
  /// A connection file does not hold a role, an address and an incarnation.
  BadConnectionFile(path: String)
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
    Some(connection) -> {
      use peer <- result.map(encode_text("peer", connection.peer))
      <<
        1,
        role_byte(connection.role),
        peer:bits,
        connection.started:size(64),
      >>
    }
  })
  use bytes <- result.try(encode_bytes("draw", draw.bytes))
  append(folder <> "/" <> draws_file, <<connection:bits, bytes:bits>>)
}

fn role_byte(role: random_source.Role) -> Int {
  case role {
    random_source.Sts -> 0
    random_source.Auth -> 1
  }
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
    <<1, role, rest:bytes>> -> {
      use role <- result.try(decode_role(value: role, file:, offset:))
      use #(peer, after_peer) <- result.try(take_text(
        bytes: rest,
        file:,
        offset:,
      ))
      case after_peer {
        <<started:signed-size(64), after:bytes>> ->
          decode_draw_bytes(
            connection: Some(random_source.Connection(role:, peer:, started:)),
            bytes: after,
            file:,
            offset:,
          )
        _ -> Error(Truncated(file:, offset:))
      }
    }
    <<1>> -> Error(Truncated(file:, offset:))
    <<value, _:bytes>> -> Error(UnknownFlag(file:, offset:, value:))
    _ -> Error(Truncated(file:, offset:))
  }
}

fn decode_role(
  value value: Int,
  file file: String,
  offset offset: Int,
) -> Result(random_source.Role, SessionError) {
  case value {
    0 -> Ok(random_source.Sts)
    1 -> Ok(random_source.Auth)
    _ -> Error(UnknownRole(file:, offset:, value:))
  }
}

fn decode_draw_bytes(
  connection connection: Option(random_source.Connection),
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

/// The role a login listener's connection has in a recording's header.
pub fn role_of(role: random_source.Role) -> Role {
  case role {
    random_source.Sts -> recording.Sts
    random_source.Auth -> recording.Auth
  }
}

/// The bytes of the draws the connection of the key made, in the order it made
/// them.
pub fn draws_of(session session: Session, key key: Key) -> List(BitArray) {
  case list.find(ranked(session), fn(entry) { entry.0 == key }) {
    Error(Nil) -> []
    Ok(#(_, connection)) ->
      list.filter_map(session.draws, fn(draw) {
        case draw.connection == Some(connection) {
          True -> Ok(draw.bytes)
          False -> Error(Nil)
        }
      })
  }
}

/// Every connection of the session that made a draw, as a replay would look
/// for it, in the order the connections started.
pub fn connections(session session: Session) -> List(Key) {
  list.map(ranked(session), fn(entry) { entry.0 })
}

/// The connections that drew, in the order they started, each with its key: the
/// incarnation is how many connections of the same role and address started
/// before it.
fn ranked(session: Session) -> List(#(Key, random_source.Connection)) {
  let started =
    list.filter_map(session.draws, fn(draw) {
      option.to_result(draw.connection, Nil)
    })
    |> list.unique
    |> list.sort(fn(first, second) {
      int.compare(first.started, second.started)
    })
  let #(ranked, _) =
    list.fold(started, #([], dict.new()), fn(built, connection) {
      let #(ranked, counts) = built
      let role = role_of(connection.role)
      let incarnation =
        dict.get(counts, #(role, connection.peer)) |> result.unwrap(0)
      #(
        [
          #(Key(role:, peer: connection.peer, incarnation:), connection),
          ..ranked
        ],
        dict.insert(counts, #(role, connection.peer), incarnation + 1),
      )
    })
  list.reverse(ranked)
}

/// Writes the key of a recording's connection beside the recording at
/// `recording_path`, in the file that has the recording's name with
/// `.connection` for `.recording`: the role, the address the relay connected to
/// the server from, and the incarnation, which is how many connection files of
/// that role and address the folder already holds. A file already there is
/// replaced.
pub fn write_connection(
  recording_path recording_path: String,
  role role: Role,
  peer peer: String,
) -> Result(Nil, SessionError) {
  let path = connection_path(recording_path)
  use earlier <- result.try(connection_files(path))
  let incarnation =
    list.count(earlier, fn(key) { key.role == role && key.peer == peer })
  simplifile.write(
    path,
    recording.role_name(role)
      <> " "
      <> peer
      <> " "
      <> int.to_string(incarnation),
  )
  |> result.map_error(FileFailed(path:, error: _))
}

/// The keys the connection files beside `path` hold, `path` itself left out.
fn connection_files(path: String) -> Result(List(Key), SessionError) {
  let folder =
    string.join(
      list.reverse(list.drop(list.reverse(string.split(path, "/")), 1)),
      "/",
    )
  use names <- result.try(
    simplifile.read_directory(folder)
    |> result.map_error(FileFailed(path: folder, error: _)),
  )
  list.filter(names, fn(name) {
    string.ends_with(name, connection_suffix) && folder <> "/" <> name != path
  })
  |> list.try_map(fn(name) { read_key(folder <> "/" <> name) })
}

/// The key the recording at `recording_path` was made by, as the relay wrote
/// it.
pub fn read_connection(
  recording_path recording_path: String,
) -> Result(Key, SessionError) {
  read_key(connection_path(recording_path))
}

fn read_key(path: String) -> Result(Key, SessionError) {
  use text <- result.try(
    simplifile.read(path) |> result.map_error(FileFailed(path:, error: _)),
  )
  case string.split(text, " ") {
    [role, peer, incarnation] ->
      case recording.role_from_name(role), int.parse(incarnation) {
        Ok(role), Ok(incarnation) -> Ok(Key(role:, peer:, incarnation:))
        _, _ -> Error(BadConnectionFile(path:))
      }
    _ -> Error(BadConnectionFile(path:))
  }
}

fn connection_path(recording_path: String) -> String {
  string.remove_suffix(recording_path, recording_suffix) <> connection_suffix
}
