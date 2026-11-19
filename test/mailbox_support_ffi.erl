-module(mailbox_support_ffi).
-export([taken_or_ended/1, queued/1, call_waiting_from/2, monitored/1, waiting/1, tagged/2, tagged_by_reference/1]).

%% Waits until Pid answers sys:suspend, which a process does after taking every
%% message that was in its mailbox before the request, and then lets it go on
%% (sys:resume), or until Pid ends: the call monitors Pid, so an ended process gives
%% an exit of the shape {Reason, {sys, Function, Arguments}} (noproc, normal, a
%% crash) and no message is left behind. The request is not sys:get_state, which
%% copies the process's whole state to the caller: it took about 0.7 ms for each of
%% the tutorial path's 69 participants, where this takes about 3 microseconds.
taken_or_ended(Pid) ->
    try
        ok = sys:suspend(Pid, infinity),
        ok = sys:resume(Pid, infinity),
        nil
    catch
        exit:{_Reason, {sys, _Function, _Arguments}} -> nil
    end.

%% How many waiting messages are tuples whose first element is the atom Tag.
%% The length of a mailbox is no measure of what a shell has taken: a process
%% that writes to a socket has the port's reply to its own write, a tuple
%% {inet_reply, Port, ok, Ref}, in its mailbox from the moment the bytes are
%% sent until it next runs, which may be after the peer has read them.
tagged(Pid, Tag) ->
    {messages, Messages} = process_info(Pid, messages),
    length([Message || Message <- Messages,
                       is_tuple(Message), tuple_size(Message) > 0,
                       element(1, Message) =:= Tag]).

%% How many waiting messages are tuples whose first element is a reference: what
%% reaches a process by a subject, which is tagged with a reference of its own.
tagged_by_reference(Pid) ->
    {messages, Messages} = process_info(Pid, messages),
    length([Message || Message <- Messages,
                       is_tuple(Message), tuple_size(Message) > 0,
                       is_reference(element(1, Message))]).

%% What waits in a process's mailbox, as Erlang prints it, for a failure
%% message.
waiting(Pid) ->
    {messages, Messages} = process_info(Pid, messages),
    unicode:characters_to_binary(io_lib:format("~0p", [Messages])).

%% How many messages wait in a process's mailbox: a process that took every
%% message it was sent has none.
queued(Pid) ->
    {message_queue_len, Length} = process_info(Pid, message_queue_len),
    Length.

%% Whether a gen_server call made by Caller waits in Pid's mailbox: a supervisor
%% that is stopping its children takes none, so a call made to it stays here
%% until it ends. A call's message is {'$gen_call', {Caller, Tag}, Request}. A
%% process that has ended has no mailbox: no call waits in it.
call_waiting_from(Pid, Caller) ->
    case process_info(Pid, messages) of
        {messages, Messages} ->
            lists:any(fun({'$gen_call', {From, _Tag}, _Request}) -> From =:= Caller;
                         (_Other) -> false
                      end, Messages);
        undefined ->
            false
    end.

%% The processes a process holds a monitor on, one entry for each monitor.
%% Monitors of ports and of names are left out.
monitored(Pid) ->
    {monitors, Monitors} = process_info(Pid, monitors),
    [Monitored || {process, Monitored} <- Monitors, is_pid(Monitored)].
