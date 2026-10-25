//// The client's archive indexes, the `.index` files in its `Patch` folder. The
//// server reads only an index whose build matches the one it is written for.

/// The client build this server is written against. Every archive index the
/// server reads must carry it.
pub const target_build = 16_042

/// Why an index's build could not be read.
pub type IndexError {
  /// The bytes do not start with an archive index's signature.
  NotAnIndex
  /// The index holds no block that names its build.
  NoBuildBlock
  /// The bytes end inside a header or block.
  Truncated
}

/// The build an archive index belongs to, read from its own header.
pub fn build_of_index(bytes: BitArray) -> Result(Int, IndexError) {
  todo as "body in the build commit"
}
