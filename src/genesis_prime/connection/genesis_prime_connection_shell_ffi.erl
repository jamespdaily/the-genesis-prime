%% Ranch's protocol callback for a connection shell, and the Ranch and socket
%% calls the shell makes. Ranch calls start_link/3, an Erlang behaviour callback
%% Gleam cannot declare; it starts the shell's gleam_otp actor
%% (genesis_prime@connection@shell:start/2). Every other function here is a call
%% Gleam has no library for (Ranch, gen_tcp and inet) or the decoder of the
%% socket's messages into a Gleam value. Each function returns the Gleam shape
%% its caller declares.
-module(genesis_prime_connection_shell_ffi).
-behaviour(ranch_protocol).

-export([start_link/3, start_listener/5, listener_port/1, suspend_listener/1,
         handshake/3, read_once/1, socket_message/1, send/2, close/1, peer/1]).

%% Starts the connection's process, linked to Ranch's connection supervisor,
%% which is the calling process and the shell's parent. The process is the
%% gleam_otp actor of genesis_prime@connection@shell:start/2, which returns
%% {ok, Pid} or {error, StartError} as Ranch expects.
start_link(Ref, _Transport, Settings) ->
    'genesis_prime@connection@shell':start(Ref, Settings).

%% Starts a listener as a child of the calling supervisor: Ranch's embedded
%% supervisor, with one acceptor, which takes exactly MaxConnections
%% connections (with more acceptors Ranch can take one more for each) and one
%% connection supervisor, so connections are its temporary children and stop
%% within ShutdownMs.
start_listener(Ref, Port, MaxConnections, ShutdownMs, Settings) ->
    {ok, _} = application:ensure_all_started(ranch),
    TransportOptions = #{socket_opts => [{port, Port}],
                         num_acceptors => 1,
                         max_connections => MaxConnections,
                         num_conns_sups => 1,
                         shutdown => ShutdownMs},
    case ranch_embedded_sup:start_link(Ref, ranch_tcp, TransportOptions,
                                       genesis_prime_connection_shell_ffi, Settings) of
        {ok, Pid} -> {ok, Pid};
        {error, Reason} -> {error, {could_not_listen, genesis_prime_step_runtime_ffi:term_text(Reason)}}
    end.

%% The listener's port: `ranch:get_port/1` gives `undefined` for a listener whose
%% socket is closed or that listens on a local socket, and fails with `badarg`
%% for a name Ranch has no listener under (`ets:lookup_element/3` on its table).
%% Result(Int, ListenerError).
listener_port(Ref) ->
    try ranch:get_port(Ref) of
        Port when is_integer(Port) -> {ok, Port};
        undefined -> {error, listener_not_listening}
    catch
        error:badarg -> {error, listener_not_running}
    end.

%% Closes the listener's listening socket, so no new socket is taken, and leaves
%% its connections running: Ranch stops the listener's acceptors and keeps its
%% connection supervisor. A listener already closed gives ok. A name Ranch has no
%% listener under fails with `badarg` (its table has no entry); one whose
%% supervisor has ended fails with `noproc`, and one whose supervisor ends while
%% the call waits fails with `{Reason, {gen_server, call, _}}` for the reason
%% it ended with (`shutdown` from its parent, `killed`); all are no listener
%% running. Anything else Ranch says is the reason. Result(Nil, ListenerError).
suspend_listener(Ref) ->
    try ranch:suspend_listener(Ref) of
        ok -> {ok, nil};
        {error, Reason} -> {error, {ranch_failed, genesis_prime_step_runtime_ffi:term_text(Reason)}}
    catch
        error:badarg -> {error, listener_not_running};
        exit:{_Reason, {gen_server, call, _}} -> {error, listener_not_running}
    end.

%% Takes the socket from Ranch, gives its reads the buffer ReadLimit, so no read
%% holds more bytes than that (without it the size depends on the system), and
%% gives its writes the send deadline, closing it when one passes. A close gives
%% bytes still queued the send deadline, in whole seconds, to go out, then drops
%% them: without a linger, a close to a client that has stopped reading waits
%% for the queue up to 180 s (prim_inet's close_pend_loop). A client gone before
%% the handshake, or a socket that cannot be set up, is an error value and no
%% crash: the shell ends the connection quietly.
handshake(Ref, SendDeadlineMs, ReadLimit) ->
    try ranch:handshake(Ref) of
        {ok, Socket} ->
            LingerSeconds = max(1, (SendDeadlineMs + 999) div 1000),
            case inet:setopts(Socket, [{buffer, ReadLimit},
                                       {send_timeout, SendDeadlineMs},
                                       {send_timeout_close, true},
                                       {linger, {true, LingerSeconds}}]) of
                ok -> {ok, Socket};
                {error, Reason} ->
                    gen_tcp:close(Socket),
                    {error, {socket_options_failed, failure(Reason)}}
            end
    catch
        exit:{shutdown, {Reason, _Peer}} -> {error, {client_gone, failure(Reason)}};
        exit:{shutdown, Reason} -> {error, {client_gone, failure(Reason)}}
    end.

%% Asks the socket for its next read.
read_once(Socket) ->
    case inet:setopts(Socket, [{active, once}]) of
        ok -> {ok, nil};
        {error, Reason} -> {error, failure(Reason)}
    end.

%% A message the socket sent, as the shell's selector takes it: {tcp, Socket,
%% Bytes}, {tcp_closed, Socket} or {tcp_error, Socket, Reason}.
socket_message({tcp, _Socket, Bytes}) -> {read, Bytes};
socket_message({tcp_closed, _Socket}) -> closed_by_peer;
socket_message({tcp_error, _Socket, Reason}) -> {failed_to_read, failure(Reason)}.

%% Writes the bytes; a write that waits past the socket's send deadline fails
%% as send_timed_out and closes the socket.
send(Socket, Bytes) ->
    case gen_tcp:send(Socket, Bytes) of
        ok -> {ok, nil};
        {error, Reason} -> {error, failure(Reason)}
    end.

close(Socket) ->
    gen_tcp:close(Socket),
    nil.

%% The peer's address and port; a socket already closed has none.
peer(Socket) ->
    case inet:peername(Socket) of
        {ok, {Address, Port}} -> {peer, list_to_binary(inet:ntoa(Address)), Port};
        {error, _} -> {peer, <<"unknown">>, 0}
    end.

failure(closed) -> closed;
failure(econnreset) -> reset;
failure(timeout) -> send_timed_out;
failure(Reason) -> {other_socket_failure, genesis_prime_step_runtime_ffi:term_text(Reason)}.
