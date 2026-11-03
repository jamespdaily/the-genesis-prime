-module(mailbox_support_ffi).
-export([queued/1, call_waiting_from/2, monitored/1, waiting/1, tagged/2, tagged_by_reference/1]).

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
