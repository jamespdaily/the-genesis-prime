//// What an account may do as a game master. A permission is saved by name,
//// one row for each permission an account holds, and every game master
//// command names the permission its rule requires. A new account holds none.

/// One thing a game master may do. `Grant` is the right to give a permission
/// to an account and to take one away. `Other` is a name read from a row or a
/// command line that this code has no permission for; it is kept so the name
/// is not lost, and no rule gives it.
pub type Permission {
  Grant
  Other(name: String)
}

/// The name a permission is saved under and typed as.
pub fn to_name(permission permission: Permission) -> String {
  todo as "the name of each permission"
}

/// The permission of a saved or typed name, `Other` when the code has none by
/// that name.
pub fn from_name(name name: String) -> Permission {
  todo as "Grant for its name, Other for any other"
}
