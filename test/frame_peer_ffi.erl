-module(frame_peer_ffi).
-export([listen/0, write_once_accepted/2, accept/1, write/2, bytes_received/1]).

%% A listening socket on the loopback, on a port the system chooses, and that
%% port. The socket is owned by the process that calls this and closes with it.
-spec listen() -> {port(), inet:port_number()}.
listen() ->
    {ok, Listen} = gen_tcp:listen(0, [binary, {active, false}, {ip, {127, 0, 0, 1}}]),
    {ok, Port} = inet:port(Listen),
    {Listen, Port}.

%% Starts a process, linked to the caller, that accepts one connection on
%% `Listen` and writes `Bytes` to it in a single send, and then keeps the
%% connection open until the caller ends.
-spec write_once_accepted(port(), binary()) -> nil.
write_once_accepted(Listen, Bytes) ->
    Writer = spawn_link(fun() ->
        receive
            go -> ok
        end,
        {ok, Connection} = gen_tcp:accept(Listen, 10000),
        ok = gen_tcp:send(Connection, Bytes),
        receive
            stop -> ok
        end
    end),
    ok = gen_tcp:controlling_process(Listen, Writer),
    Writer ! go,
    nil.

%% The one connection waiting on `Listen`, accepted by the calling process.
-spec accept(port()) -> port().
accept(Listen) ->
    {ok, Connection} = gen_tcp:accept(Listen, 10000),
    Connection.

%% `Bytes` in a single send on an accepted connection.
-spec write(port(), binary()) -> nil.
write(Connection, Bytes) ->
    ok = gen_tcp:send(Connection, Bytes),
    nil.

%% The bytes the client's socket has received from the system so far.
-spec bytes_received(port()) -> non_neg_integer().
bytes_received(Socket) ->
    {ok, [{recv_oct, Received}]} = inet:getstat(Socket, [recv_oct]),
    Received.
