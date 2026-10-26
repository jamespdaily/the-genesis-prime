//// An account as the login knows it: the name the player types, the GUID the
//// STS login names it by, and the SRP values that stand for its password.
//// The name is lower case because the client lower-cases it before it sends
//// it (StartStsLogin 0x1400b4500), and it is at most 250 UTF-16 units because
//// the login request, message 0x592, cannot hold more (opcode.0x592).

import genesis_prime/login/guid.{type Guid}
import gleam/bool
import gleam/list
import gleam/string

/// An account saved in the database. `salt` and `verifier` are the SRP
/// values from `srp.verifier`, never the password; `created` is the creation
/// time as RFC 3339 text in UTC.
pub type Account {
  Account(
    name: String,
    user_id: Guid,
    salt: BitArray,
    verifier: BitArray,
    created: String,
  )
}

/// Who a login is for, once it has passed a check: what a hand-off holds
/// between one connection and the next.
pub type Identity {
  Identity(name: String, user_id: Guid)
}

/// Why a typed name cannot name an account.
pub type NameError {
  /// The name is empty.
  NameEmpty
  /// The name has more UTF-16 units than message 0x592 can hold.
  NameTooLong(units: Int)
}

/// The most UTF-16 units of an account name: 250, the most the login request
/// writes (opcode.0x592, WriteCountedWideText 0x1400c2f70).
pub const name_unit_limit = 250

/// The name as the client sends it, in lower case, or why it names no
/// account.
pub fn lower_case_name(name name: String) -> Result(String, NameError) {
  let lowered = string.lowercase(name)
  use <- bool.guard(when: lowered == "", return: Error(NameEmpty))
  let units = utf16_units(lowered)
  case units > name_unit_limit {
    True -> Error(NameTooLong(units:))
    False -> Ok(lowered)
  }
}

fn utf16_units(text: String) -> Int {
  list.fold(string.to_utf_codepoints(text), 0, fn(units, codepoint) {
    case string.utf_codepoint_to_int(codepoint) > 0xFFFF {
      True -> units + 2
      False -> units + 1
    }
  })
}

/// What an account holds of the player's identity.
pub fn identity(account account: Account) -> Identity {
  Identity(name: account.name, user_id: account.user_id)
}
