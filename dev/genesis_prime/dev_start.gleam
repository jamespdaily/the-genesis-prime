//// Starts the server for a live session, as `gleam run` does, with two
//// changes only a developer makes: each STS and auth connection is recorded
//// into a folder, for replay, and the auth server can plant one frame the
//// client does not handle right after its hello, to prove the client's
//// failure log brings back its id.
////
//// `gleam run -m genesis_prime/dev_start -- <recording folder> [<planted message id>]`
////
//// - `recording folder`: where each connection's recording is written, made
////   when it is missing; by convention `test/recording/<date>-<flow>`.
//// - `planted message id`: a message id, such as `0x0914`, sent once with an
////   empty body in the auth wrapper after the hello. Left out, nothing is
////   planted.
////
//// The environment is the one `gleam run` reads (genesis_prime).

pub fn main() -> Nil {
  todo as "the build follows the shape commit"
}
