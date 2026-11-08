%% What the tests of the connection actor read from the runtime that Gleam has
%% no call for: a module's exports, a process's queue flag, a socket's read
%% mode, a hang-up that is a close or a reset, the handover Ranch makes, and an
%% atom's text. Each function returns the Gleam shape its caller declares.
-module(connection_actor_support_ffi).

-export([exports/1, message_queue_data/1, hang_up/2, hand_over_to_failing_transport/2,
         hand_over_closed_socket/2, kept_asks/1, socket_buffer/1,
         socket_armed/1]).

%% The functions a module exports, as {Name, Arity}, without the module's own
%% module_info.
exports(Module) ->
    [{atom_to_binary(Name), Arity}
     || {Name, Arity} <- Module:module_info(exports),
        Name =/= module_info].

%% Where the process keeps its waiting messages: off_heap or on_heap.
message_queue_data(Pid) ->
    {message_queue_data, Location} = process_info(Pid, message_queue_data),
    Location.

%% The Running record of an open connection, read from the actor's state as
%% OTP's sys:get_state gives it.
running(Pid) ->
    {connection, _Settings, _Parent, _Timers, _HeldReads, _Answers,
     {open, Running}}
        = sys:get_state(Pid),
    Running.

%% How many asks an open connection keeps for a late answer or the end of
%% their target: the Running record's kept dictionary.
kept_asks(Pid) ->
    {running, _Socket, _Script, _State, _Wire, _At, _TakenMs, _Reading, Kept,
     _Watches, _Timers, _Stopping, _ClosedBy}
        = running(Pid),
    maps:size(Kept).

%% The buffer, in bytes, of an open connection's socket, which bounds what one
%% read of it holds: the Running record's socket.
socket_buffer(Pid) ->
    {running, Socket, _Script, _State, _Wire, _At, _TakenMs, _Reading, _Kept,
     _Watches, _Timers, _Stopping, _ClosedBy}
        = running(Pid),
    {ok, [{buffer, Buffer}]} = inet:getopts(Socket, [buffer]),
    Buffer.

%% Whether an open connection's socket is armed for its next read, so the bytes
%% that arrive reach the process as a message: {active, once}.
socket_armed(Pid) ->
    {running, Socket, _Script, _State, _Wire, _At, _TakenMs, _Reading, _Kept,
     _Watches, _Timers, _Stopping, _ClosedBy}
        = running(Pid),
    {ok, [{active, Active}]} = inet:getopts(Socket, [active]),
    Active =:= once.

%% Connects to the port and closes at once: with a FIN (plain) or, with a
%% linger of 0, a reset. Gives the port the client connected from.
hang_up(Port, Kind) ->
    Linger = case Kind of
                 plain -> [];
                 reset -> [{linger, {true, 0}}]
             end,
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port, [{active, false} | Linger]),
    {ok, {_Address, LocalPort}} = inet:sockname(Socket),
    ok = gen_tcp:close(Socket),
    LocalPort.

%% What Ranch sends a connection's process once its start has returned, with a
%% transport whose handshake fails, as a client that is gone makes it fail.
hand_over_to_failing_transport(Pid, Ref) ->
    Pid ! {handshake, Ref, failing_transport_ffi, no_socket, 5000},
    nil.

%% The same with Ranch's TCP transport and a socket that has been closed, whose
%% options cannot be set.
hand_over_closed_socket(Pid, Ref) ->
    {ok, Listener} = gen_tcp:listen(0, []),
    ok = gen_tcp:close(Listener),
    Pid ! {handshake, Ref, ranch_tcp, Listener, 5000},
    nil.
