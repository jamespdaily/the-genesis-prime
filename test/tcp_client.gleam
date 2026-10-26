//// A client socket for tests: connects to a listener on this machine, sends
//// bytes and waits for the server to close it. The bytes a test sends are
//// the client's own frames, built with `frame.encode`.

/// A connected client socket.
pub type Client

/// Connects to the port on this machine's loopback address.
@external(erlang, "tcp_client_ffi", "connect")
pub fn connect(port: Int) -> Result(Client, Nil)

/// The client's own address and port as text, which is the peer address the
/// server sees for this connection.
@external(erlang, "tcp_client_ffi", "own_address")
pub fn own_address(client: Client) -> String

/// Sends the bytes; fails when the server has closed the connection.
@external(erlang, "tcp_client_ffi", "send")
pub fn send(client: Client, bytes: BitArray) -> Result(Nil, Nil)

/// Sends the bytes, and does nothing when the server has already closed the
/// connection, which a test of a limit expects.
@external(erlang, "tcp_client_ffi", "send_if_open")
pub fn send_if_open(client: Client, bytes: BitArray) -> Nil

/// Waits up to `within_ms` for the server to close or reset the connection,
/// reading and discarding what it sends meanwhile: true once it has, false
/// when the time passes with the connection still open.
@external(erlang, "tcp_client_ffi", "await_close")
pub fn await_close(client: Client, within_ms: Int) -> Bool

/// Closes the client's end.
@external(erlang, "tcp_client_ffi", "close")
pub fn close(client: Client) -> Nil

/// Reads exactly `count` bytes the server wrote, waiting at most `within_ms`
/// for them: an error when the time passes or the server closes first.
@external(erlang, "tcp_client_ffi", "receive")
pub fn receive(
  client: Client,
  count: Int,
  within_ms: Int,
) -> Result(BitArray, Nil)
