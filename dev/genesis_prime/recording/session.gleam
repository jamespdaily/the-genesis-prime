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

import gleam/option.{type Option}
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
  folder _folder: String,
  account _account: UsedAccount,
) -> Result(Nil, SessionError) {
  panic as "shape only: built after the tests"
}

/// The draws and the accounts of the folder. A file that is not there is empty,
/// as a session recorded without the recording server has neither. An account
/// written more than once is read once, as its first entry holds it.
pub fn read(folder _folder: String) -> Result(Session, SessionError) {
  panic as "shape only: built after the tests"
}

/// The bytes of the draws one connection made, in the order it made them.
pub fn draws_of(
  session _session: Session,
  connection _connection: String,
) -> List(BitArray) {
  panic as "shape only: built after the tests"
}

/// Writes the address a recording's connection reached the server from beside
/// the recording at `recording_path`, in the file that has the recording's name
/// with `.connection` for `.recording`.
pub fn write_connection(
  recording_path _recording_path: String,
  connection _connection: String,
) -> Result(Nil, SessionError) {
  panic as "shape only: built after the tests"
}

/// The address the recording at `recording_path` was made from, as the relay
/// wrote it.
pub fn read_connection(
  recording_path _recording_path: String,
) -> Result(String, SessionError) {
  panic as "shape only: built after the tests"
}
