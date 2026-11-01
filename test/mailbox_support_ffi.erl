-module(mailbox_support_ffi).
-export([queued/1, monitored/1]).

%% How many messages wait in a process's mailbox: a supervisor that is stopping
%% its children takes none, so a call made to it stays here until it ends, and
%% a process that took every message it was sent has none.
queued(Pid) ->
    {message_queue_len, Length} = process_info(Pid, message_queue_len),
    Length.

%% The processes a process holds a monitor on, one entry for each monitor.
%% Monitors of ports and of names are left out.
monitored(Pid) ->
    {monitors, Monitors} = process_info(Pid, monitors),
    [Monitored || {process, Monitored} <- Monitors, is_pid(Monitored)].
