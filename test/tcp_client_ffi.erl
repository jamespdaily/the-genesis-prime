-module(tcp_client_ffi).
-export([connect/1, own_address/1, send/2, send_if_open/2, await_close/2, close/1]).

-spec connect(non_neg_integer()) -> {ok, port()} | {error, nil}.
connect(Port) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port,
                         [binary, {active, false}, {nodelay, true}], 5000) of
        {ok, Socket} -> {ok, Socket};
        {error, _Reason} -> {error, nil}
    end.

%% The client's own address and port as text, which is the peer address the
%% server sees for this connection.
-spec own_address(port()) -> binary().
own_address(Socket) ->
    {ok, {Address, Port}} = inet:sockname(Socket),
    iolist_to_binary([inet:ntoa(Address), ":", integer_to_list(Port)]).

-spec send(port(), binary()) -> {ok, nil} | {error, nil}.
send(Socket, Bytes) ->
    case gen_tcp:send(Socket, Bytes) of
        ok -> {ok, nil};
        {error, _Reason} -> {error, nil}
    end.

-spec send_if_open(port(), binary()) -> nil.
send_if_open(Socket, Bytes) ->
    _ = gen_tcp:send(Socket, Bytes),
    nil.

%% Reads and discards what the server sends until the socket is closed or
%% reset, which is `true`, or until `Within` milliseconds pass with the socket
%% still open, which is `false`.
-spec await_close(port(), non_neg_integer()) -> boolean().
await_close(Socket, Within) ->
    case gen_tcp:recv(Socket, 0, Within) of
        {ok, _Bytes} -> await_close(Socket, Within);
        {error, timeout} -> false;
        {error, _Closed} -> true
    end.

-spec close(port()) -> nil.
close(Socket) ->
    gen_tcp:close(Socket),
    nil.
