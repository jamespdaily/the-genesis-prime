//// The random-stat word of an item: one 64-bit integer that says which row of its
//// random stat group each kind-2 entry of the item's ItemStat takes
//// (`opcode.0x111.shared_item_random_stats`). The item's maker writes it
//// (`genesis_prime/game/random_stat`); the item's properties read it
//// (`genesis_prime/game/item_property`).
////
//// ```
//// bits 56..63   version (1)
//// bits 40..55   unused, 0
//// bits  0..39   five choices of 8 bits; choice i is entry i's 1-based row in its group
//// ```
////
//// The client has data when the word has any bit set other than bit 56
//// (0x14040e6d0), so version 1 with every choice 0 has none, and version 0 with
//// choices is cleared to none (0x14040bdf0).

import gleam/bool
import gleam/int
import gleam/list

/// The version the server writes (`opcode.0x111.shared_item_random_stats`).
const version = 1

/// The word of the choices of the five entries, 0 for none: 0 when every choice is 0,
/// so an item that rolled nothing keeps the word that means none.
pub fn of_choices(choices choices: List(Int)) -> Int {
  use <- bool.guard(list.all(choices, fn(choice) { choice == 0 }), 0)
  list.index_fold(
    choices,
    int.bitwise_shift_left(version, 56),
    fn(word, choice, index) {
      int.bitwise_or(word, int.bitwise_shift_left(choice, 8 * index))
    },
  )
}

/// Whether the client reads the word as holding data: its version is not 0 and
/// a bit other than the version's bit 56 is set (0x14040e6d0, 0x14040bdf0).
pub fn has_data(word word: Int) -> Bool {
  int.bitwise_shift_right(word, 56) != 0
  && int.bitwise_and(word, 0xfeffffffffffffff) != 0
}

/// Entry `entry`'s choice (0 to 4): its 1-based row in its group, 0 for none.
pub fn choice(word word: Int, entry entry: Int) -> Int {
  int.bitwise_and(int.bitwise_shift_right(word, 8 * entry), 0xff)
}
