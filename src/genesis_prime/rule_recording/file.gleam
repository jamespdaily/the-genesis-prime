//// Writes a connection's recording to a file, record by record as the shell
//// takes each input, in the layout of genesis_prime/rule_recording. A
//// `Recorder` is made only by the dev start; the server's own start has none.

import genesis_prime/rule_recording.{type Header, type Record}

/// Where and how each connection of a listener is recorded: a folder, and the
/// header every recording starts with.
pub opaque type Recorder(settings) {
  Recorder(folder: String, header: Header(settings))
}

/// One open recording file.
pub opaque type Writer {
  Writer(device: Device, count: Int)
}

type Device

/// Why a recording file could not be opened or written.
pub type FileError {
  FileError(path: String, reason: String)
}

/// A recorder that writes one file per connection into `folder`. The dev
/// start is its only caller.
pub fn recorder(
  folder folder: String,
  header header: Header(settings),
) -> Recorder(settings) {
  Recorder(folder:, header:)
}

/// Opens the file of one connection and writes its header.
pub fn open(
  recorder: Recorder(settings),
  connection connection: Int,
) -> Result(Writer, FileError) {
  todo as "the build follows the shape commit"
}

/// Appends one record.
pub fn append(
  writer: Writer,
  record: Record(message, answer, outgoing, request),
) -> Result(Writer, FileError) {
  todo as "the build follows the shape commit"
}

/// Writes `End` with the count of records and closes the file.
pub fn finish(writer: Writer) -> Result(Nil, FileError) {
  todo as "the build follows the shape commit"
}
