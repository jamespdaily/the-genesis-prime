-module(socket_watch_ffi).
-export([mailbox_length/1]).

-spec mailbox_length(pid()) -> non_neg_integer().
mailbox_length(Pid) ->
    {message_queue_len, Length} = process_info(Pid, message_queue_len),
    Length.
