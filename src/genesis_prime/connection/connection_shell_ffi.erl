%% Ranch's protocol callback for a connection shell, and the socket and ask
%% calls the shell makes. Ranch calls start_link/3, an Erlang behaviour callback
%% Gleam cannot declare; the process it starts hands over to
%% genesis_prime@connection@shell:run/3. Each function returns the Gleam shape
%% its caller declares.
-module(connection_shell_ffi).
-behaviour(ranch_protocol).

-export([start_link/3, start_listener/4, listener_port/1, handshake/2,
         read_once/1, next_event/3, send/2, close/1, peer/1,
         send_answer/3, await_answer/4]).

%% Starts the connection's process, linked to Ranch's connection supervisor,
%% which is the calling process and the shell's parent.
start_link(Ref, _Transport, Settings) ->
    Parent = self(),
    Pid = proc_lib:spawn_link(fun() ->
        'genesis_prime@connection@shell':run(Ref, Parent, Settings)
    end),
    {ok, Pid}.

%% Starts a listener as a child of the calling supervisor: Ranch's embedded
%% supervisor, with one connection supervisor, so connections are its
%% temporary children and stop within ShutdownMs.
start_listener(Ref, Port, ShutdownMs, Settings) ->
    {ok, _} = application:ensure_all_started(ranch),
    TransportOptions = #{socket_opts => [{port, Port}],
                         num_conns_sups => 1,
                         shutdown => ShutdownMs},
    case ranch_embedded_sup:start_link(Ref, ranch_tcp, TransportOptions,
                                       connection_shell_ffi, Settings) of
        {ok, Pid} -> {ok, Pid};
        {error, Reason} -> {error, {could_not_listen, format(Reason)}}
    end.

listener_port(Ref) ->
    try {ok, ranch:get_port(Ref)}
    catch _:_ -> {error, nil}
    end.

%% Takes the socket from Ranch, gives its writes the send deadline, closing it
%% when one passes, and traps the parent's exit so a stop arrives as a message.
%% A close gives bytes still queued the send deadline, in whole seconds, to go
%% out, then drops them: without a linger, a close to a client that has stopped
%% reading waits for the queue up to 180 s (prim_inet's close_pend_loop).
handshake(Ref, SendDeadlineMs) ->
    {ok, Socket} = ranch:handshake(Ref),
    LingerSeconds = max(1, (SendDeadlineMs + 999) div 1000),
    ok = inet:setopts(Socket, [{send_timeout, SendDeadlineMs},
                               {send_timeout_close, true},
                               {linger, {true, LingerSeconds}}]),
    process_flag(trap_exit, true),
    Socket.

%% Asks the socket for its next read.
read_once(Socket) ->
    case inet:setopts(Socket, [{active, once}]) of
        ok -> {ok, nil};
        {error, Reason} -> {error, failure(Reason)}
    end.

%% Waits for what reaches the process next: a read, the peer's close, a read
%% failure, or the parent's stop. Kept maps the tag of each ask whose outcome
%% was NoAnswerInTime or StoppedWaiting to {kept, Ask, Monitor}: its late answer
%% comes as {late_answer, Tag} and its target's end as {kept_ended, Tag}. The
%% answer or end of a tag that is not kept, and another process's exit, are not
%% the shell's and are dropped, so the mailbox never fills with them.
next_event(Socket, Parent, Kept) ->
    receive
        {tcp, Socket, Bytes} -> {read, Bytes};
        {tcp_closed, Socket} -> closed_by_peer;
        {tcp_error, Socket, Reason} -> {failed_to_read, failure(Reason)};
        {'EXIT', Parent, _Reason} -> stop_requested;
        {'EXIT', _Other, _Reason} -> next_event(Socket, Parent, Kept);
        {ask_answer, Tag, _Answer} when is_map_key(Tag, Kept) ->
            {late_answer, Tag};
        {ask_answer, _Tag, _Answer} -> next_event(Socket, Parent, Kept);
        {'DOWN', Monitor, process, _Pid, _Reason} ->
            case kept_with_monitor(Monitor, Kept) of
                {ok, Tag} -> {kept_ended, Tag};
                error -> next_event(Socket, Parent, Kept)
            end
    end.

kept_with_monitor(Monitor, Kept) ->
    case [Tag || {Tag, {kept, _Ask, Kept_monitor}} <- maps:to_list(Kept),
                 Kept_monitor =:= Monitor] of
        [Tag] -> {ok, Tag};
        [] -> error
    end.

%% What an ask's target calls to answer it; it never fails, and an answer to a
%% shell that has ended is dropped.
send_answer(Shell, Tag, Answer) ->
    Shell ! {ask_answer, Tag, Answer},
    nil.

%% Waits for the outcome of an ask: the answer, the target's end, the parent's
%% exit, or the deadline, on the monotonic clock. A deadline already passed ends
%% the wait at once, whatever has arrived. Only this ask's tag and monitor and
%% the parent's exit are taken from the mailbox.
await_answer(Tag, Monitor, Parent, DeadlineMs) ->
    Remaining = DeadlineMs - erlang:monotonic_time(millisecond),
    case Remaining =< 0 of
        true -> deadline_passed;
        false ->
            receive
                {ask_answer, Tag, Answer} ->
                    erlang:demonitor(Monitor, [flush]),
                    {replied, Answer};
                {'DOWN', Monitor, process, _Pid, _Reason} -> target_ended;
                {'EXIT', Parent, _Reason} -> parent_exited
            after Remaining -> deadline_passed
            end
    end.

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
failure(Reason) -> {other_socket_failure, format(Reason)}.

format(Reason) ->
    unicode:characters_to_binary(io_lib:format("~0p", [Reason])).
