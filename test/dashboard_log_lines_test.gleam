//// The lines the Logs page shows, made from the bytes of a log file. Expected
//// values are the scripts' own output (`dev/play_service/lib.sh` writes one
//// stamped line a message, and the real logs hold every shape the level rows
//// name), the project's text-only rule for the dashboard (a line is text,
//// whatever its bytes), and the invariant that how a read was split into
//// chunks never changes the lines.

import dashboard_otp_log_support as support
import genesis_prime/dashboard/log_lines.{LaunchdLog, UpdaterLog}
import gleam/bit_array
import gleam/list
import gleam/string
import owned_test
import qcheck
import simplifile

const cap = 4096

pub fn the_followed_files_are_the_files_the_scripts_write_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(library) = simplifile.read("dev/play_service/lib.sh")
  let assert Ok(installer) = simplifile.read("dev/play_service/install.sh")

  // `log_file=$home/NAME` in lib.sh.
  let assert Ok(log_name) = after_prefix(library, "log_file=$home/")
  assert Ok(log_name) == log_lines.file_name(UpdaterLog)

  // `<key>StandardOutPath</key><string>$home/NAME</string>` in install.sh,
  // and the same name for standard error.
  let assert Ok(out_name) =
    after_prefix(installer, "<key>StandardOutPath</key><string>$home/")
  let assert Ok(error_name) =
    after_prefix(installer, "<key>StandardErrorPath</key><string>$home/")
  assert Ok(out_name) == log_lines.file_name(LaunchdLog)
  assert error_name == out_name as "launchd's two keys name one file"
}

/// The text after the first line's `prefix` up to the end of the line or the
/// next `<`.
fn after_prefix(text: String, prefix: String) -> Result(String, Nil) {
  case string.split_once(text, prefix) {
    Error(Nil) -> Error(Nil)
    Ok(#(_, rest)) -> {
      let assert [line, ..] = string.split(rest, "\n")
      let assert [name, ..] = string.split(line, "<")
      Ok(string.trim(name))
    }
  }
}

/// The bytes the property draws from: lines end often, and each of the other
/// bytes is one the logs or a hostile writer may hold (an escape and its
/// bracket, a control byte, the three bytes of a euro sign, a byte that is not
/// UTF-8).
fn alphabet(index: Int) -> Int {
  let assert Ok(byte) =
    list.drop(
      [0x0A, 0x0A, 0x0D, 0x1B, 0x5B, 0x41, 0x00, 0x20, 0xE2, 0x82, 0xAC, 0xFF],
      index,
    )
    |> list.first
  byte
}

pub fn the_lines_do_not_depend_on_how_the_bytes_were_split_test() -> Nil {
  use <- owned_test.run(60_000)
  // Up to six runs of one byte each, together past the cap, so the long-line
  // cut is reached.
  let draws =
    qcheck.tuple2(
      qcheck.generic_list(
        elements_from: qcheck.tuple2(
          qcheck.bounded_int(from: 0, to: 11),
          qcheck.bounded_int(from: 1, to: 2500),
        ),
        length_from: qcheck.bounded_int(from: 0, to: 6),
      ),
      qcheck.generic_list(
        elements_from: qcheck.bounded_int(from: 0, to: 20_000),
        length_from: qcheck.bounded_int(from: 0, to: 8),
      ),
    )
  qcheck.run(
    qcheck.default_config() |> qcheck.with_test_count(100),
    draws,
    fn(drawn) {
      let #(runs, points) = drawn
      let whole =
        list.map(runs, fn(run) {
          let #(index, length) = run
          list.repeat(<<alphabet(index):8>>, length) |> bit_array.concat
        })
        |> bit_array.concat
      support.reads_do_not_change_the_entries(
        source: UpdaterLog,
        bytes: whole,
        points:,
        cap_bytes: cap,
      )
    },
  )
}
