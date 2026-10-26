//// Adds an account to the database, run as
//// `gleam run -m genesis_prime/create_account -- <name> <password>`. The
//// database is the one PGHOST, PGPORT, PGUSER, PGDATABASE and PGPASSWORD name
//// (`pool.from_environment`). The name is saved in lower case, as the client
//// sends it, and only the password's SRP salt and verifier are saved. The
//// password is on the command line, so the tool is for test accounts.

/// Creates the account and prints its UserId, or says why it could not.
pub fn main() -> Nil {
  todo as "create the account the arguments name"
}
