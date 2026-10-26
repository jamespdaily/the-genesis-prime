//// A message's frame on the wire: a 32-bit length, a 16-bit message id, then
//// the body, both header fields little-endian. The length counts the whole
//// frame, its own 4 bytes and the id's 2 included, and no frame is over 131,070
//// bytes (WriteMessageFrame 0x1403355e0, MessageSizeLimit 0x140335ec0). The
//// decoder reads frames from the bytes received so far, as the client's
//// frame reader does: a frame may span reads and one read may hold several
//// (ReadConnectionMessages 0x1403321a0, ReadMessageFrame 0x140331990).
////
//// A message id is a plain `Int` here, not a typed id: the frame is read for
//// every packet, and a typed id costs about 5% of a hot path's time (median
//// +5.09%, about 20 ns per message) and 3 words per id held (the typed-id
//// benchmark in `dev/genesis_prime/id_cost.gleam`). The message layer above
//// turns the id into its own type.

/// The bytes of a frame before its body: the 32-bit length and the 16-bit id
/// (WriteMessageFrame 0x1403355e0 writes widths 0x20 and 0x10).
pub const header_size = 6

/// The most bytes a whole frame may hold, header included. The client's size
/// limit is 131070 (0x1FFFE) for every message in the decode (MessageSizeLimit
/// 0x140335ec0).
pub const size_limit = 131_070

/// One message: its id and the body bytes after the header.
pub type Frame {
  Frame(message_id: Int, body: BitArray)
}

/// Why bytes are not a frame. Every one ends the connection.
pub type FrameError {
  /// A frame held whole has fewer bytes than the header.
  ShorterThanHeader(bytes: Int)
  /// The length field is below the 6 bytes of the header
  /// (ParseWrappedMessage 0x140331620 refuses a length under 6).
  LengthBelowHeader(length: Int)
  /// The length field is above the size limit.
  LengthOverLimit(length: Int)
  /// A frame held whole has a different number of bytes than its length field
  /// says.
  LengthDisagrees(length: Int, bytes: Int)
  /// A message id that does not fit in 16 bits.
  MessageIdOutOfRange(message_id: Int)
}

/// The bytes of a frame for a message id and body: the length, the id, then
/// the body. Fails when the id does not fit in 16 bits or the whole frame
/// would be over the size limit, which the client does not write either.
pub fn encode(
  message_id message_id: Int,
  body body: BitArray,
) -> Result(BitArray, FrameError) {
  todo as "encode a frame"
}

/// Splits the bytes received so far into their whole frames and the bytes left
/// over: the start of a frame whose end has not arrived. A length below the
/// header or over the size limit is an error as soon as its 4 bytes have
/// arrived, so a huge claimed length is never waited for.
pub fn decode(
  received received: BitArray,
) -> Result(#(List(Frame), BitArray), FrameError) {
  todo as "decode the received frames"
}

/// Reads one frame held whole in memory, such as the inner frame of a wrapper
/// message. Its length field must equal the number of bytes.
pub fn parse(whole whole: BitArray) -> Result(Frame, FrameError) {
  todo as "parse a whole frame"
}
