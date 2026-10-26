//// How a message body is written and read: a stream of bits, each value in the
//// least significant bit first, so a value that starts on a byte boundary and
//// is 16, 32 or 64 bits wide lands as little-endian bytes, and a field may
//// start and end anywhere in a byte (WriteBits 0x140336380, ReadBits32
//// 0x14006c090). A body ends on a byte boundary, the last byte padded with
//// zero bits (WriteMessageFrame 0x1403355e0).
////
//// The generated message modules call these functions in the order of their
//// fields. A writer keeps the first error, and every later write leaves it
//// alone, so a generated encoder is one pipeline and `finish` gives the bytes
//// or that error. A reader returns each value with the reader after it, so a
//// generated decoder stops at the first field the bytes cannot hold.

/// A server's address and port as the client reads them (ReadIpv4Endpoint
/// 0x1400a8980): the address as a number, so 127.0.0.1 is 0x7F000001, and the
/// port.
pub type Endpoint {
  Endpoint(address: Int, port: Int)
}

/// Why a value could not be written. Each is the caller's value being wrong,
/// not the bytes, so nothing is sent.
pub type EncodeError {
  /// A value is negative or needs more than the field's bits.
  ValueDoesNotFit(field: String, bits: Int, value: Int)
  /// Raw bytes or a GUID are not the field's fixed number of bytes.
  WrongByteCount(field: String, expected: Int, actual: Int)
  /// A text has more UTF-16 units than its form can count (WriteWideText
  /// 0x140336040 counts them in 15 bits, WriteCountedWideText 0x1400c2f70 in a
  /// given maximum).
  TextTooLong(field: String, units: Int, limit: Int)
  /// A counted text holds a zero, where the client's writer would stop.
  TextHoldsZero(field: String)
  /// A whole frame's first 32 bits are not its length in bytes, or it is not
  /// whole bytes (WriteWholeFrameBody 0x140079f30).
  InnerFrameDisagrees(field: String)
}

/// Why bytes are not a body. A decode error ends the connection.
pub type DecodeError {
  /// The bytes end inside a field; the client's reader fails the same way with
  /// 0x80070026 (ReadBitsSlow 0x140336d60).
  EndOfData
  /// Whole bytes are left after the last field.
  TrailingBytes(count: Int)
  /// A text is not valid UTF-16: a surrogate without its pair.
  InvalidText
  /// A counted text does not end in its zero, holds a zero before it, or is
  /// longer than its maximum.
  InvalidCountedText
  /// A whole frame's length is below the 4 bytes of the length itself.
  InnerFrameTooShort(length: Int)
}

/// A body being written: the whole bytes written, the bits that do not fill
/// a byte, and the first error.
pub opaque type Writer {
  Writer(
    whole_bytes: BitArray,
    pending: Int,
    pending_bits: Int,
    failure: Result(Nil, EncodeError),
  )
}

/// A body being read: the bytes and the bit position of the next value.
pub opaque type Reader {
  Reader(bytes: BitArray, position: Int)
}

/// A writer with nothing written.
pub fn new_writer() -> Writer {
  todo
}

/// The bytes written, the last one padded with zero bits, or the first error.
pub fn finish(writer: Writer) -> Result(BitArray, EncodeError) {
  todo
}

/// Writes an unsigned value in `bits` bits, 1 to 64; a value that is negative
/// or does not fit is an error.
pub fn write_unsigned(
  writer writer: Writer,
  field field: String,
  value value: Int,
  bits bits: Int,
) -> Writer {
  todo
}

/// Writes the bits of a 32-bit float, kept as the number they are (ReadFloat
/// 0x14006c1c0): no conversion, so every bit pattern round-trips.
pub fn write_float32_bits(
  writer writer: Writer,
  field field: String,
  bits bits: Int,
) -> Writer {
  todo
}

/// Writes a wide text: one bit that is set when it has more than 127 UTF-16
/// units, their count in 7 bits or 15 bits, then each unit in 16 bits
/// (WriteWideText 0x140336040).
pub fn write_wide_text(
  writer writer: Writer,
  field field: String,
  text text: String,
) -> Writer {
  todo
}

/// Writes a counted wide text: the count of units plus one in 16 bits, then the
/// units and a terminating zero in 16 bits each (WriteCountedWideText
/// 0x1400c2f70). `max_units` is the most units the message allows.
pub fn write_counted_wide_text(
  writer writer: Writer,
  field field: String,
  text text: String,
  max_units max_units: Int,
) -> Writer {
  todo
}

/// Writes a GUID: 16 bytes in their order (WriteGuid 0x1400a8780).
pub fn write_guid(
  writer writer: Writer,
  field field: String,
  guid guid: BitArray,
) -> Writer {
  todo
}

/// Writes raw bytes at the bit position, with no move to a byte boundary, in
/// order (WriteBytesAsBits 0x1403360d0); there must be exactly `count`.
pub fn write_raw_bytes(
  writer writer: Writer,
  field field: String,
  bytes bytes: BitArray,
  count count: Int,
) -> Writer {
  todo
}

/// Writes a server's address in 32 bits and its port in 16.
pub fn write_endpoint(
  writer writer: Writer,
  field field: String,
  endpoint endpoint: Endpoint,
) -> Writer {
  todo
}

/// Writes a whole inner frame, its 32-bit length counting its own 4 bytes
/// included, after moving to the next whole byte (WriteRawBytes 0x1403365e0).
pub fn write_whole_frame(
  writer writer: Writer,
  field field: String,
  frame frame: BitArray,
) -> Writer {
  todo
}

/// Writes the items' count in `count_bits` bits, then each item through
/// `write_item`.
pub fn write_array(
  writer writer: Writer,
  field field: String,
  items items: List(a),
  count_bits count_bits: Int,
  write_item write_item: fn(Writer, a) -> Writer,
) -> Writer {
  todo
}

/// Writes a count of texts in `count_bits` bits, then each as a wide text.
pub fn write_wide_texts(
  writer writer: Writer,
  field field: String,
  texts texts: List(String),
  count_bits count_bits: Int,
) -> Writer {
  todo
}

/// A reader at the start of a body.
pub fn new_reader(body: BitArray) -> Reader {
  todo
}

/// Whether the body ends where the last field did: only the zero bits of the
/// last byte may be left.
pub fn finish_reading(reader: Reader) -> Result(Nil, DecodeError) {
  todo
}

/// Reads an unsigned value of `bits` bits, 1 to 64.
pub fn read_unsigned(
  reader reader: Reader,
  bits bits: Int,
) -> Result(#(Int, Reader), DecodeError) {
  todo
}

/// Reads the bits of a 32-bit float as the number they are.
pub fn read_float32_bits(
  reader: Reader,
) -> Result(#(Int, Reader), DecodeError) {
  todo
}

/// Reads a wide text written by `write_wide_text`.
pub fn read_wide_text(
  reader: Reader,
) -> Result(#(String, Reader), DecodeError) {
  todo
}

/// Reads a counted wide text with at most `max_units` units.
pub fn read_counted_wide_text(
  reader reader: Reader,
  max_units max_units: Int,
) -> Result(#(String, Reader), DecodeError) {
  todo
}

/// Reads a GUID: 16 bytes in order.
pub fn read_guid(reader: Reader) -> Result(#(BitArray, Reader), DecodeError) {
  todo
}

/// Reads `count` raw bytes at the bit position, in order.
pub fn read_raw_bytes(
  reader reader: Reader,
  count count: Int,
) -> Result(#(BitArray, Reader), DecodeError) {
  todo
}

/// Reads a server's address in 32 bits and its port in 16.
pub fn read_endpoint(
  reader: Reader,
) -> Result(#(Endpoint, Reader), DecodeError) {
  todo
}

/// Reads a whole inner frame: moves to the next whole byte, reads the 32-bit
/// length, and takes that many bytes from the start of the length.
pub fn read_whole_frame(
  reader: Reader,
) -> Result(#(BitArray, Reader), DecodeError) {
  todo
}

/// Reads a count in `count_bits` bits, then that many items through
/// `read_item`.
pub fn read_array(
  reader reader: Reader,
  count_bits count_bits: Int,
  read_item read_item: fn(Reader) -> Result(#(a, Reader), DecodeError),
) -> Result(#(List(a), Reader), DecodeError) {
  todo
}

/// Reads a count of texts in `count_bits` bits, then that many wide texts.
pub fn read_wide_texts(
  reader reader: Reader,
  count_bits count_bits: Int,
) -> Result(#(List(String), Reader), DecodeError) {
  todo
}
