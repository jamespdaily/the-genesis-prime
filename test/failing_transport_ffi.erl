%% A Ranch transport whose handshake fails, as a client that is gone before the
%% handshake finishes makes it fail: ranch:handshake calls handshake/2, and on
%% an error it closes the socket and exits with {shutdown, _}.
-module(failing_transport_ffi).

-export([handshake/2, peername/1, close/1]).

handshake(_Socket, _Timeout) -> {error, closed}.

peername(_Socket) -> {error, einval}.

close(_Socket) -> ok.
