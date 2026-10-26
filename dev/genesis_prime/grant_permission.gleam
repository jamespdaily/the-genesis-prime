//// Gives a game master permission to an account, or takes one away, run as
//// `gleam run -m genesis_prime/grant_permission -- <arguments>`. The database
//// is the one PGHOST, PGPORT, PGUSER, PGDATABASE and PGPASSWORD name
//// (`pool.from_environment`). Three forms:
////
//// - `first <account>` gives the account `grant` while no account holds it,
////   so a fresh database can get its first game master; it is refused after.
//// - `grant <by> <account> <permission>` and `revoke <by> <account>
////   <permission>` run the command as the account `<by>`, so the rule checks
////   that account's permissions and the use is logged. The tool does not ask
////   for a password: it is for a developer's own database.
////
//// Account names are the names `create_account` saved, in lower case.

import argv

/// What the command line asks for.
pub type Request {
  /// Give the first `grant`.
  First(account: String)
  /// Run the grant command as `by`.
  Give(by: String, account: String, permission: String)
  /// Run the revoke command as `by`.
  Take(by: String, account: String, permission: String)
}

/// Reads the command line, or says it is none of the three forms.
pub fn parse(arguments arguments: List(String)) -> Result(Request, Nil) {
  todo as "the three forms of the command line"
}

/// Runs the request and prints how it ended, or says why it could not.
pub fn main() -> Nil {
  case parse(arguments: argv.load().arguments) {
    Ok(request) -> run(request)
    Error(Nil) ->
      todo as "print the usage and halt with status 1, as create_account does"
  }
}

fn run(request: Request) -> Nil {
  todo as "start the pool, look the accounts up, run the request"
}
