//// The dashboard's key and the file that holds its entry URL.
////
//// The key is 32 bytes from the operating system's random source, in base64url,
//// made at each start. The entry URL (the address with the key) is kept in
//// `dashboard/entry-url` under `GENESIS_HOME`, in a folder only its owner
//// enters (0700) and a file only its owner reads (0600); the play container
//// has no mount of that folder and so cannot read it, and `open "$(cat
//// ~/.genesis-prime/dashboard/entry-url)"` opens the dashboard.
////
//// ```text
//// prepare_entry ──► folder 0700 ──► entry-url.pending 0600 holding the URL
////        │                                      │
////    (server binds the port)           publish: rename over entry-url
////        │                                      │
////   discard if it did not                 the new start's key is the file's
//// ```
////
//// The file is written before the server binds, so a key that cannot be kept
//// is never served, and published after, so a second dashboard that finds the
//// port busy never replaces the first one's file.

import gleam/bit_array
import gleam/result
import simplifile

/// Why the entry file could not be kept.
pub type EntryError {
  FolderNotPrepared(folder: String, reason: simplifile.FileError)
  FileNotWritten(path: String, reason: simplifile.FileError)
  FileNotPublished(path: String, reason: simplifile.FileError)
}

/// An entry file written under another name, not yet the entry file.
pub opaque type PendingEntry {
  PendingEntry(pending_path: String, final_path: String)
}

/// The number of random bytes in a key.
const key_size = 32

/// Makes a key from `random_bytes`, which gives the number of bytes it is
/// asked for: base64url text, with no padding, of 32 bytes.
pub fn make(random_bytes random_bytes: fn(Int) -> BitArray) -> String {
  bit_array.base64_url_encode(random_bytes(key_size), False)
}

/// Where the entry file is under `home`.
pub fn entry_path(home: String) -> String {
  folder_path(home) <> "/entry-url"
}

fn folder_path(home: String) -> String {
  home <> "/dashboard"
}

/// Makes the folder private and writes `url` to a private file beside the
/// entry file.
pub fn prepare_entry(
  home home: String,
  url url: String,
) -> Result(PendingEntry, EntryError) {
  let folder = folder_path(home)
  let pending_path = entry_path(home) <> ".pending"
  let folder_failure = fn(reason) { FolderNotPrepared(folder:, reason:) }
  let file_failure = fn(reason) { FileNotWritten(path: pending_path, reason:) }
  use _ <- result.try(
    simplifile.create_directory_all(folder) |> result.map_error(folder_failure),
  )
  use is_folder <- result.try(
    simplifile.is_directory(folder) |> result.map_error(folder_failure),
  )
  use _ <- result.try(case is_folder {
    True -> Ok(Nil)
    False -> Error(folder_failure(simplifile.Enotdir))
  })
  use _ <- result.try(
    simplifile.set_permissions_octal(folder, 0o700)
    |> result.map_error(folder_failure),
  )
  // A leftover file of an earlier start is removed so the new one is made with
  // the mode set here, never an old one's.
  use _ <- result.try(remove(pending_path) |> result.map_error(file_failure))
  use _ <- result.try(
    simplifile.create_file(pending_path) |> result.map_error(file_failure),
  )
  use _ <- result.try(
    simplifile.set_permissions_octal(pending_path, 0o600)
    |> result.map_error(file_failure),
  )
  use _ <- result.try(
    simplifile.write(pending_path, url <> "\n")
    |> result.map_error(file_failure),
  )
  Ok(PendingEntry(pending_path:, final_path: entry_path(home)))
}

/// Deletes a file; one that is not there is as good as deleted.
fn remove(path: String) -> Result(Nil, simplifile.FileError) {
  case simplifile.delete(path) {
    Ok(Nil) | Error(simplifile.Enoent) -> Ok(Nil)
    Error(reason) -> Error(reason)
  }
}

/// Makes the pending file the entry file, replacing the one of an earlier
/// start in one step.
pub fn publish(entry entry: PendingEntry) -> Result(Nil, EntryError) {
  case simplifile.rename(at: entry.pending_path, to: entry.final_path) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(FileNotPublished(path: entry.final_path, reason:))
  }
}

/// Removes the pending file of a start that did not serve. A file this start
/// made, in a folder it made private, that cannot be removed has no cure here.
pub fn discard(entry entry: PendingEntry) -> Nil {
  let assert Ok(Nil) = remove(entry.pending_path)
    as "the pending entry file could not be removed"
  Nil
}
