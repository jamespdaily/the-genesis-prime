-module(genesis_prime_socket_ffi).
-export([listen/1, listening_port/1, accept/1, give_to/2, arm_once/1, arm_count/2, send/2, close/1,
         peer/1, monotonic_milliseconds/0,
         keep_messages_off_heap/0, data_tag/0,
         closed_tag/0, error_tag/0, passive_tag/0]).

%% The connections a listening socket holds for the acceptor while it is busy.
%% It is above the connection cap (`capacity:connection_cap`), so a crowd of
%% clients that connect together is not dropped before the acceptor reaches
%% them. The operating system lowers it to its own limit when that is smaller.
-define(BACKLOG, 1024).

%% How long a write may wait for a peer that does not read, in milliseconds. The
%% socket owner writes in its own process, so a peer that never reads would
%% hold it; past this the write fails and the socket closes.
-define(SEND_TIMEOUT_MS, 5000).

-spec listen(non_neg_integer()) -> {ok, port()} | {error, term()}.
listen(Port) ->
    result(gen_tcp:listen(Port, [binary, {packet, raw}, {active, false},
                                 {reuseaddr, true}, {nodelay, true},
                                 {send_timeout, ?SEND_TIMEOUT_MS},
                                 {send_timeout_close, true},
                                 {backlog, ?BACKLOG}])).

-spec listening_port(port()) -> {ok, non_neg_integer()} | {error, term()}.
listening_port(Socket) ->
    result(inet:port(Socket)).

-spec accept(port()) -> {ok, port()} | {error, term()}.
accept(Listening) ->
    result(gen_tcp:accept(Listening)).

-spec give_to(port(), pid()) -> {ok, nil} | {error, term()}.
give_to(Socket, Owner) ->
    unit(gen_tcp:controlling_process(Socket, Owner)).

-spec arm_once(port()) -> {ok, nil} | {error, term()}.
arm_once(Socket) ->
    unit(inet:setopts(Socket, [{active, once}])).

-spec arm_count(port(), pos_integer()) ->
    {ok, nil} | {error, term()}.
arm_count(Socket, Reads) ->
    unit(inet:setopts(Socket, [{active, Reads}])).

%% Writes the bytes, which returns once the runtime has taken them; a peer that
%% does not read for ?SEND_TIMEOUT_MS fails the write and closes the socket.
-spec send(port(), binary()) -> {ok, nil} | {error, term()}.
send(Socket, Bytes) ->
    unit(gen_tcp:send(Socket, Bytes)).

-spec close(port()) -> nil.
close(Socket) ->
    gen_tcp:close(Socket),
    nil.


%% The peer's address and port as text, or none when the socket has no peer
%% (it is closed or not connected).
-spec peer(port()) -> {some, binary()} | none.
peer(Socket) ->
    case inet:peername(Socket) of
        {ok, {Address, Port}} ->
            {some, iolist_to_binary([inet:ntoa(Address), ":", integer_to_list(Port)])};
        {error, _Reason} ->
            none
    end.

-spec monotonic_milliseconds() -> integer().
monotonic_milliseconds() ->
    erlang:monotonic_time(millisecond).

%% The calling process's waiting messages are kept off its heap.
-spec keep_messages_off_heap() -> nil.
keep_messages_off_heap() ->
    process_flag(message_queue_data, off_heap),
    nil.

%% The tags of the messages `gen_tcp` sends a socket's owner.
-spec data_tag() -> tcp.
data_tag() -> tcp.

-spec closed_tag() -> tcp_closed.
closed_tag() -> tcp_closed.

-spec error_tag() -> tcp_error.
error_tag() -> tcp_error.

-spec passive_tag() -> tcp_passive.
passive_tag() -> tcp_passive.

result({ok, Value}) -> {ok, Value};
result({error, Reason}) -> {error, reason(Reason)}.

unit(ok) -> {ok, nil};
unit({error, Reason}) -> {error, reason(Reason)}.

%% A `gen_tcp` error as the Gleam type `socket.Reason`.
reason(closed) -> closed;
reason(timeout) -> timeout;
reason(eaddrinuse) -> address_in_use;
reason(econnreset) -> connection_reset;
reason(Posix) when is_atom(Posix) -> {other, atom_to_binary(Posix)};
reason(Other) -> {other, iolist_to_binary(io_lib:format("~p", [Other]))}.
