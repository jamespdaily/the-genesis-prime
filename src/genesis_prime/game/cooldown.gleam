//// A unit's running spell cooldowns and the modifiers that change them, as the
//// client keeps its own (`Spell4Effects.effectType.73`). Pure: the cast rule
//// (genesis_prime/game/cast) keeps one `Book` for the player and asks it.
////
//// ```
//// a go starts a spell's cooldown         start ─▶ running ─▶ left_ms ─▶ a press is refused or held
////                                            ▲        ▲
//// kept modifiers, in the order added ────────┘        │
////                                                     │
//// a type 73 row (delay, then lifetime)   keep ─▶ lasting      modify ─▶ every running cooldown
////                                        drop ◀─ the row's end        the selector picks
//// ```
////
//// - **Which cooldowns a modifier picks:** a running cooldown's spell, by its Spell4Base
////   (selector 0), its Spell4 (1), one of its spell groups (2) or one of its cooldown
////   groups (3); any other selector value picks every spell. The ids are compared and
////   never looked up (`0x14046b920`).
//// - **The operations** run in 32-bit floats on the time left in milliseconds `L`, and
////   `f` is the row's float: 0 gives `min(L, trunc(L x f))`, which never lengthens; 1
////   `trunc(L x f)`; 2 `L + trunc(f)`, not below 0 and at most 2^31 - 1; 3 `trunc(f)`;
////   any other operation leaves `L` (`0x14046ba60` to `0x14046babc`). The 32-bit
////   product is rounded once from the exact 64-bit product of two 32-bit values.
//// - **A time of 0 ends the cooldown** (`0x1407a0320`, `0x1407a0390`), and a new
////   cooldown is made only for a time above 0 (`0x14046a3d0`).
//// - **A go starts the spell's own cooldown and each of its cooldown groups** (type 1
////   and type 2 entries, `0x14046b1e0`), only while no entry carries the spell's id,
////   its own or a group's. A group is looked up by its id when a press is checked
////   (`0x1403b14c0`), whichever spell started it, and a modifier picks it with the spell
////   that started it (`0x14046b920`). A group set again while it runs takes the new time
////   as it is, and a time of 0 ends it (`opcode.0x804`, `0x14046a3d0`).
//// - **A new cooldown's time** goes through the kept modifiers in the order they were
////   added (`0x14046a890`).
//// - **The global cooldown is not here:** its entry has spell id 0, which a modifier
////   skips (`0x14046b920`), so the cast rule keeps it apart.
////
//// Gaps: no cooldown rate (unit properties 0xa04 and 0x88), so the server is never
//// stricter than the client, which refuses a press the server would accept; no ability
//// charges. The client's 32-bit wrap of a result outside 0 to 2^31 - 1 is not modelled,
//// because no row reaches it: the result is held inside the range. A source kept again
//// is held once, at the end of the list: the server's choice.

import genesis_prime/game/unit_properties.{type Source}
import genesis_prime/message/float32
import genesis_prime/table/id.{type Spell4BaseId, type Spell4Id}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list

/// A unit's running cooldowns and its kept modifiers.
pub opaque type Book {
  Book(
    /// The cooldowns of spells that run, by the Spell4 id of the spell that started each.
    running: Dict(Int, Running),
    /// The cooldowns of groups that run, by the group's SpellCoolDown id. Each carries the
    /// keys of the spell that started it, so a selector picks it with that spell.
    grouped: Dict(Int, Running),
    /// The kept modifiers in the order they were added, each with what keeps it.
    lasting: List(#(Source, Modifier)),
  )
}

/// A cooldown that runs: the monotonic time it ends at and the ids a selector tests.
type Running {
  Running(ends_ms: Int, keys: Keys)
}

/// The ids of a spell that a selector tests: its Spell4, its Spell4Base, its spell
/// groups and its cooldown groups, each with the time it runs.
pub opaque type Keys {
  Keys(
    spell4_id: Spell4Id,
    spell4_base_id: Spell4BaseId,
    spell_groups: List(Int),
    cooldown_groups: List(Group),
  )
}

/// A cooldown group of a spell (a SpellCoolDown row named by `spellCoolDownId00` to `02`)
/// and the time it runs from the spell's go: the row's `cooldownTime`, or the spell's own
/// cooldown when the row holds 0 and the client scales the spell's cooldowns
/// (`spell_plan.cooldown_groups_of`). A time of 0 starts none.
pub type Group {
  Group(id: Int, time_ms: Int)
}

/// Which running cooldowns a modifier picks (`Spell4Effects.effectType.73`: dataBits00
/// names the case and dataBits01 the id).
pub type Selector {
  Base(Spell4BaseId)
  Spell(Spell4Id)
  SpellGroup(Int)
  CooldownGroup(Int)
  /// The client's branch for any other selector value: every spell.
  EverySpell(selector: Int)
}

/// What a modifier does to a time left in milliseconds; each float is the finite value
/// of a 32-bit float (dataBits03).
pub type Operation {
  /// Multiplies, and never lengthens.
  NoLonger(factor: Float)
  Multiply(factor: Float)
  AddMs(amount: Float)
  SetMs(time: Float)
  /// The client's branch for any other operation value: the time is left.
  Unchanged(operation: Int)
}

/// One cooldown effect: the cooldowns it picks and what it does to them.
pub type Modifier {
  Modifier(selector: Selector, operation: Operation)
}

/// A unit with no cooldown running and no modifier kept.
pub fn new() -> Book {
  Book(running: dict.new(), grouped: dict.new(), lasting: [])
}

/// The ids of a spell that its cooldown carries, for a selector to test.
pub fn keys(
  spell4_id spell4_id: Spell4Id,
  spell4_base_id spell4_base_id: Spell4BaseId,
  spell_groups spell_groups: List(Int),
  cooldown_groups cooldown_groups: List(Group),
) -> Keys {
  Keys(spell4_id:, spell4_base_id:, spell_groups:, cooldown_groups:)
}

/// The spell's own cooldown of `cooldown_ms` and each of its cooldown groups start now,
/// unless an entry that carries the spell's id runs already, its own or a group's
/// (`0x14046b1e0`). Each time goes through the kept modifiers in the order they were
/// added, and a result of 0 starts none (`0x14046a3d0`). A group that runs already is set
/// to the new time as it is, which ends it for 0 (`opcode.0x804`).
pub fn start(
  book book: Book,
  keys keys: Keys,
  cooldown_ms cooldown_ms: Int,
  now_ms now_ms: Int,
) -> Book {
  use <- bool.guard(
    when: carries(book:, spell4_id: keys.spell4_id, now_ms:),
    return: book,
  )
  let book = case cooldown_ms > 0 {
    True ->
      Book(
        ..book,
        running: started(
          entries: book.running,
          key: keys.spell4_id.value,
          lasting: book.lasting,
          keys:,
          time_ms: cooldown_ms,
          now_ms:,
        ),
      )
    False -> book
  }
  list.fold(keys.cooldown_groups, book, fn(book, group) {
    Book(..book, grouped: case dict.get(book.grouped, group.id) {
      Ok(running) if running.ends_ms > now_ms ->
        set(entries: book.grouped, group:, running:, now_ms:)
      Ok(_) | Error(Nil) ->
        started(
          entries: book.grouped,
          key: group.id,
          lasting: book.lasting,
          keys:,
          time_ms: group.time_ms,
          now_ms:,
        )
    })
  })
}

/// Whether an entry that runs carries the spell's id: the spell's own cooldown, or a
/// group's that the spell started.
fn carries(
  book book: Book,
  spell4_id spell4_id: Spell4Id,
  now_ms now_ms: Int,
) -> Bool {
  left_ms(book:, spell4_id:, now_ms:) > 0
  || list.any(dict.values(book.grouped), fn(running) {
    running.keys.spell4_id == spell4_id && running.ends_ms > now_ms
  })
}

/// A new entry of `time_ms` through the kept modifiers, made only for a time above 0;
/// a stale entry under the key is taken out.
fn started(
  entries entries: Dict(Int, Running),
  key key: Int,
  lasting lasting: List(#(Source, Modifier)),
  keys keys: Keys,
  time_ms time_ms: Int,
  now_ms now_ms: Int,
) -> Dict(Int, Running) {
  let time_ms = case time_ms > 0 {
    True -> through_kept(lasting:, keys:, time_ms:)
    False -> 0
  }
  case time_ms > 0 {
    True -> dict.insert(entries, key, Running(ends_ms: now_ms + time_ms, keys:))
    False -> dict.delete(entries, key)
  }
}

/// A group entry that runs set to the group's time as it is, without the kept modifiers;
/// a time of 0 ends it. The entry keeps the keys of the spell that first started it: the
/// client re-arms only the timer of an entry that exists (`0x14046a3d0`).
fn set(
  entries entries: Dict(Int, Running),
  group group: Group,
  running running: Running,
  now_ms now_ms: Int,
) -> Dict(Int, Running) {
  case group.time_ms > 0 {
    True ->
      dict.insert(
        entries,
        group.id,
        Running(..running, ends_ms: now_ms + group.time_ms),
      )
    False -> dict.delete(entries, group.id)
  }
}

/// A new cooldown's time put through the kept modifiers in the order they were added:
/// each one that picks the spell applies its operation (`0x14046a890`).
fn through_kept(
  lasting lasting: List(#(Source, Modifier)),
  keys keys: Keys,
  time_ms time_ms: Int,
) -> Int {
  list.fold(lasting, time_ms, fn(time_ms, kept) {
    let #(_, modifier) = kept
    case picks(selector: modifier.selector, keys:) {
      True -> changed(operation: modifier.operation, left_ms: time_ms)
      False -> time_ms
    }
  })
}

/// The time the spell's cooldown has left at `now_ms`, 0 when it has none.
pub fn left_ms(
  book book: Book,
  spell4_id spell4_id: Spell4Id,
  now_ms now_ms: Int,
) -> Int {
  left(entries: book.running, key: spell4_id.value, now_ms:)
}

/// The longest time any of the groups has left at `now_ms`, 0 when none runs: the
/// client's press check looks each group of the spell up by its id, whichever spell
/// started it (`0x1403b14c0`).
pub fn group_left_ms(
  book book: Book,
  groups groups: List(Group),
  now_ms now_ms: Int,
) -> Int {
  list.fold(groups, 0, fn(longest, group) {
    int.max(longest, left(entries: book.grouped, key: group.id, now_ms:))
  })
}

fn left(
  entries entries: Dict(Int, Running),
  key key: Int,
  now_ms now_ms: Int,
) -> Int {
  case dict.get(entries, key) {
    Ok(running) -> int.max(0, running.ends_ms - now_ms)
    Error(Nil) -> 0
  }
}

/// Changes the time left of every cooldown that runs, a spell's or a group's, and that
/// the modifier's selector picks; a new time of 0 ends the cooldown (`0x14046b920`).
pub fn modify(
  book book: Book,
  modifier modifier: Modifier,
  now_ms now_ms: Int,
) -> Book {
  Book(
    ..book,
    running: modified(entries: book.running, modifier:, now_ms:),
    grouped: modified(entries: book.grouped, modifier:, now_ms:),
  )
}

fn modified(
  entries entries: Dict(Int, Running),
  modifier modifier: Modifier,
  now_ms now_ms: Int,
) -> Dict(Int, Running) {
  dict.fold(entries, dict.new(), fn(kept, key, running) {
    let left_ms = running.ends_ms - now_ms
    case left_ms > 0 && picks(selector: modifier.selector, keys: running.keys) {
      False -> dict.insert(kept, key, running)
      True ->
        case changed(operation: modifier.operation, left_ms:) {
          0 -> kept
          new_left_ms ->
            dict.insert(
              kept,
              key,
              Running(..running, ends_ms: now_ms + new_left_ms),
            )
        }
    }
  })
}

/// A modifier kept for the cooldowns that start from now on (`0x14046b7f0`), after the
/// ones kept before it. A source that is kept again replaces its earlier entry.
pub fn keep(
  book book: Book,
  source source: Source,
  modifier modifier: Modifier,
) -> Book {
  Book(
    ..book,
    lasting: list.append(without(lasting: book.lasting, source:), [
      #(source, modifier),
    ]),
  )
}

/// The modifier a source kept taken out of the list; a source that kept none changes
/// nothing. The cooldowns it changed stay changed.
pub fn drop(book book: Book, source source: Source) -> Book {
  Book(..book, lasting: without(lasting: book.lasting, source:))
}

/// Every kept modifier taken out of the list.
pub fn drop_all(book book: Book) -> Book {
  Book(..book, lasting: [])
}

fn without(
  lasting lasting: List(#(Source, Modifier)),
  source source: Source,
) -> List(#(Source, Modifier)) {
  list.filter(lasting, fn(kept) { kept.0 != source })
}

/// Whether the selector picks a spell with these ids.
fn picks(selector selector: Selector, keys keys: Keys) -> Bool {
  case selector {
    Base(base) -> keys.spell4_base_id == base
    Spell(spell4_id) -> keys.spell4_id == spell4_id
    SpellGroup(group) -> list.contains(keys.spell_groups, group)
    CooldownGroup(id) ->
      list.any(keys.cooldown_groups, fn(group) { group.id == id })
    EverySpell(..) -> True
  }
}

/// The largest time the client holds: 2^31 - 1 milliseconds.
const largest_ms = 2_147_483_647

/// The new time left from the old one, in the client's 32-bit float arithmetic.
fn changed(operation operation: Operation, left_ms left_ms: Int) -> Int {
  case operation {
    // The client compares the product with the time as unsigned numbers, so a negative
    // product is above every time and leaves it.
    NoLonger(factor:) ->
      case product(left_ms:, factor:) {
        negative if negative < 0 -> left_ms
        multiplied -> int.min(left_ms, multiplied)
      }
    Multiply(factor:) -> within(product(left_ms:, factor:))
    AddMs(amount:) -> within(left_ms + float.truncate(amount))
    SetMs(time:) -> within(float.truncate(time))
    Unchanged(..) -> left_ms
  }
}

/// The 32-bit product of the time and the factor, truncated: the time as a 32-bit
/// float times the factor, rounded once to 32 bits. The 64-bit product of two 32-bit
/// values is exact, so rounding it gives the 32-bit product.
fn product(left_ms left_ms: Int, factor factor: Float) -> Int {
  float.truncate(float32.product(
    left: float32.rounded(int.to_float(left_ms)),
    right: factor,
  ))
}

fn within(time_ms: Int) -> Int {
  int.clamp(time_ms, min: 0, max: largest_ms)
}
