-module(planted_shutdown_ffi).
-export([listen/0, accept/1, give/2, close/1, refuses/1, connect/1, await_closed/2]).

%% The Gleam types of test/planted_shutdown.gleam: Socket is a gen_tcp socket,
%% and a listening socket and a connected one are the same type.

%% A listening socket on a port of the loopback chosen by the system, and the
%% port.
-spec listen() -> {port(), inet:port_number()}.
listen() ->
    {ok, Listen} = gen_tcp:listen(0, [binary, inet, {ip, {127, 0, 0, 1}}, {active, false}]),
    {ok, Port} = inet:port(Listen),
    {Listen, Port}.

%% The next connection to the listening socket, or an error when the socket is
%% closed.
-spec accept(port()) -> {ok, port()} | {error, nil}.
accept(Listen) ->
    case gen_tcp:accept(Listen) of
        {ok, Socket} -> {ok, Socket};
        {error, closed} -> {error, nil}
    end.

%% Hands the socket to the process that owns it from now on.
-spec give(port(), pid()) -> nil.
give(Socket, Pid) ->
    ok = gen_tcp:controlling_process(Socket, Pid),
    nil.

-spec close(port()) -> nil.
close(Socket) ->
    ok = gen_tcp:close(Socket),
    nil.

%% Whether a connection to the port on the loopback is refused, which is what a
%% port nothing listens on answers; a connection that is accepted is closed.
-spec refuses(inet:port_number()) -> boolean().
refuses(Port) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 5000) of
        {ok, Socket} ->
            ok = gen_tcp:close(Socket),
            false;
        {error, econnrefused} ->
            true
    end.

%% A connection from this VM to the port on the loopback.
-spec connect(inet:port_number()) -> port().
connect(Port) ->
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}], 5000),
    Socket.

%% Whether the other end closes the connection within Within milliseconds: a
%% read that ends with `closed` is the peer's close, and a read that times out
%% is a peer that kept it open. Bytes the peer sent are not expected.
-spec await_closed(port(), non_neg_integer()) -> boolean().
await_closed(Socket, Within) ->
    case gen_tcp:recv(Socket, 0, Within) of
        {error, closed} -> true;
        {error, timeout} -> false
    end.
