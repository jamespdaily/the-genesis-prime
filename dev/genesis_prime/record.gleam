//// Records a live session of the real client: a relay that listens where the
//// client connects, passes each connection through to the server and writes
//// one recording file for it. Run it once for each of the server's roles:
////
//// `gleam run -m genesis_prime/record -- <listen port> <server host> <server port> <session folder> <role>`
////
//// - `listen port`: the port the client connects to; the client's address
////   arguments name this machine and this port.
//// - `server host` and `server port`: the server the relay passes each
////   connection to.
//// - `session folder`: the folder the recordings are written into, made when
////   it is missing; by convention `test/recording/<date>-<flow>`.
//// - `role`: `sts`, `auth` or `game`, written into each recording's header.
////
//// The relay runs until the process is stopped. It listens on every IPv4
//// address of the machine, so a client on another machine can reach it.
//// A recording's header holds the client's build, today's date, the role and
//// the commit that is checked out in the directory the relay runs from.

/// Starts the relay from the command line and keeps the node alive.
pub fn main() -> Nil {
  panic as "shape only: not built"
}
