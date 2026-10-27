//// The random values a rule draws, all from one seed. A rule takes no random
//// value from anywhere else, so a recording that holds the seed replays every
//// value. The seed comes from the operating system's strong random source
//// when a connection is accepted (`step.Accepted`); each block is
//// HMAC-SHA256(seed, counter), the counter rising by one per block, so no
//// two draws repeat and none tells anything of the seed.

/// A source of random bytes: the seed and the next block's counter.
pub opaque type Random {
  Random(seed: BitArray, counter: Int)
}

/// A source whose first block is the seed's block 0.
pub fn new(seed seed: BitArray) -> Random {
  todo as "the build follows the shape commit"
}

/// The next `count` bytes and the source after them. A draw takes whole
/// blocks of 32 bytes and drops what it does not use, so the bytes of two
/// draws never overlap.
pub fn bytes(random random: Random, count count: Int) -> #(Random, BitArray) {
  todo as "the build follows the shape commit"
}
