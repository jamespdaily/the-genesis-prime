-module(driven_time_ffi).
-export([keep_mailbox_off_heap/0, pid_text/1]).

%% The calling process keeps its mailbox outside its heap, whatever the node's
%% default is.
keep_mailbox_off_heap() ->
    _ = process_flag(message_queue_data, off_heap),
    nil.

%% The process's id as text, for a message that names it.
pid_text(Pid) ->
    list_to_binary(pid_to_list(Pid)).
