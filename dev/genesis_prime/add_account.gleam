//// Adds an account a client can log in with: the login name in lower case, as
//// the client sends it, a fresh 32-byte salt, the SRP verifier of the name
//// and password (genesis_prime/login/srp), and a fresh game account GUID. The
//// password is never kept.
////
//// `gleam run -m genesis_prime/add_account -- <login name> <password>`
////
//// The database is the one the server uses, from PGHOST, PGPORT, PGUSER,
//// PGPASSWORD and PGDATABASE. A login name already taken is refused with the
//// constraint that refused it.

pub fn main() -> Nil {
  todo as "the build follows the shape commit"
}
