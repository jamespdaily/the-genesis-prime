//// The dashboard's key and the file that holds its entry URL. Expected values
//// are the gate's rule: a key of 32 random bytes, new at each start, in a
//// file only its owner reads (the play container cannot, since the folder is
//// not mounted into it).

import dashboard_support
import genesis_prime/dashboard/secret
import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/string
import owned_test
import simplifile

fn bytes_of(value: Int) -> fn(Int) -> BitArray {
  fn(size) { list.repeat(<<value:8>>, size) |> bit_array.concat }
}

pub fn the_key_is_new_at_each_start_and_thirty_two_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  // Driven sources: the key is the source's 32 bytes in base64url, without
  // padding or the characters base64 uses beyond it.
  let first = secret.make(bytes_of(251))
  let second = secret.make(bytes_of(250))
  assert first != second
  assert bit_array.base64_url_decode(first) == Ok(bytes_of(251)(32))
  assert bit_array.base64_url_decode(second) == Ok(bytes_of(250)(32))
  list.each([first, second], fn(key) {
    assert !string.contains(key, "+")
    assert !string.contains(key, "/")
    assert !string.contains(key, "=")
  })
  // The operating system's source gives two starts two keys.
  assert secret.make(crypto.strong_random_bytes)
    != secret.make(crypto.strong_random_bytes)
}

fn mode_of(path: String) -> Int {
  let assert Ok(info) = simplifile.file_info(path) as { "no file at " <> path }
  simplifile.file_info_permissions_octal(info)
}

pub fn the_entry_file_is_private_and_holds_the_entry_url_test() -> Nil {
  use <- owned_test.run(5000)
  use home <- dashboard_support.with_home
  let url = "http://127.0.0.1:7700/k/first/"
  let assert Ok(entry) = secret.prepare_entry(home:, url:)
  let assert Ok(Nil) = secret.publish(entry)
  let folder = home <> "/dashboard"
  let file = folder <> "/entry-url"
  assert secret.entry_path(home) == file
  assert mode_of(folder) == 0o700
  assert mode_of(file) == 0o600
  let assert Ok(text) = simplifile.read(file)
  assert string.trim(text) == url

  // A second start replaces it, also when the old file and folder were open
  // to others.
  let assert Ok(Nil) = simplifile.set_permissions_octal(folder, 0o755)
  let assert Ok(Nil) = simplifile.set_permissions_octal(file, 0o644)
  let again = "http://127.0.0.1:7700/k/second/"
  let assert Ok(entry) = secret.prepare_entry(home:, url: again)
  assert !string.contains(read(file), "second")
    as "the file is replaced only when the second start serves"
  let assert Ok(Nil) = secret.publish(entry)
  assert string.trim(read(file)) == again
  assert mode_of(folder) == 0o700
  assert mode_of(file) == 0o600
}

fn read(path: String) -> String {
  let assert Ok(text) = simplifile.read(path) as { "no file at " <> path }
  text
}
