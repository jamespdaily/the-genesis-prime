-module(mailbox_support_ffi).
-export([queued/1]).

%% How many messages wait in a process's mailbox: a supervisor that is stopping
%% its children takes none, so a call made to it stays here until it ends, and
%% a process that took every message it was sent has none.
queued(Pid) ->
    {message_queue_len, Length} = process_info(Pid, message_queue_len),
    Length.
