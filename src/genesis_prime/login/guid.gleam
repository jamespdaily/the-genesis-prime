//// A GUID as the client sends it and the server keeps it. The client parses
//// each GUID from its text with UuidFromStringA and writes it as a 32-bit,
//// two 16-bit and 8 raw bytes, each integer little-endian, so the 16 bytes on
//// the wire are the Windows GUID structure's bytes (opcode.0x592 and
//// opcode.0x3db: "32, 16 and 16 bits and 8 raw bytes"; SendAuthLoginRequest
//// 0x14003a620). The text is the usual 8-4-4-4-12 hexadecimal: its first group
//// is the structure's 32-bit integer, so it is the first four bytes reversed.

/// A GUID in the order of its wire bytes.
pub opaque type Guid {
  Guid(wire: BitArray)
}

/// Why bytes or a text are not a GUID.
pub type GuidError {
  /// A GUID is 16 bytes on the wire.
  NotSixteenBytes(bytes: Int)
  /// The text is not 8-4-4-4-12 hexadecimal.
  NotGuidText(text: String)
}

/// The GUID whose wire bytes these are.
pub fn from_wire(bytes bytes: BitArray) -> Result(Guid, GuidError) {
  todo as "a GUID from its 16 wire bytes"
}

/// The 16 wire bytes of a GUID.
pub fn to_wire(guid guid: Guid) -> BitArray {
  todo as "the wire bytes"
}

/// The GUID a text names, as UuidFromStringA reads it.
pub fn from_text(text text: String) -> Result(Guid, GuidError) {
  todo as "a GUID from its text"
}

/// The text of a GUID in lower-case hexadecimal, 8-4-4-4-12.
pub fn to_text(guid guid: Guid) -> String {
  todo as "the text of a GUID"
}
