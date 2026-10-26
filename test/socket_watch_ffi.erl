-module(socket_watch_ffi).
-export([trace_reads/1, await_reads/2, mailbox_length/1, read_buffer_bytes/1]).

%% The socket port a process owns, or an error when it owns none.
-spec port_of(pid()) -> {ok, port()} | error.
port_of(Owner) ->
    case [Port || Port <- erlang:ports(),
                  erlang:port_info(Port, connected) =:= {connected, Owner},
                  erlang:port_info(Port, name) =:= {name, "tcp_inet"}] of
        [Port] -> {ok, Port};
        _ -> error
    end.

%% Makes the calling process the tracer of what the owner's socket port sends:
%% each send of the port is a message of the runtime to its owner. Waiting for
%% those sends waits for the runtime's own events.
-spec trace_reads(pid()) -> {ok, nil} | {error, nil}.
trace_reads(Owner) ->
    case port_of(Owner) of
        {ok, Port} ->
            1 = erlang:trace(Port, true, [send, {tracer, self()}]),
            {ok, nil};
        error ->
            {error, nil}
    end.

%% Waits until `Count` reads and passive notices have been sent by the traced
%% port, each as `read` or `reads_used_up` in the order they were sent, and
%% fails when `Within` milliseconds pass without the next one. Control
%% messages of the port (the answer to a setopts call) are not reads.
-spec await_reads(non_neg_integer(), non_neg_integer()) ->
    {ok, [read | reads_used_up]} | {error, nil}.
await_reads(Count, Within) ->
    await_reads(Count, Within, []).

await_reads(0, _Within, Seen) ->
    {ok, lists:reverse(Seen)};
await_reads(Count, Within, Seen) ->
    receive
        {trace, _Port, send, {tcp, _Port2, _Bytes}, _To} ->
            await_reads(Count - 1, Within, [read | Seen]);
        {trace, _Port, send, {tcp_passive, _Port2}, _To} ->
            await_reads(Count - 1, Within, [reads_used_up | Seen]);
        {trace, _Port, send, _Other, _To} ->
            await_reads(Count, Within, Seen)
    after Within ->
        {error, nil}
    end.

-spec mailbox_length(pid()) -> non_neg_integer().
mailbox_length(Pid) ->
    {message_queue_len, Length} = process_info(Pid, message_queue_len),
    Length.

%% The size in bytes of one read of the owner's socket (`buffer`).
-spec read_buffer_bytes(pid()) -> pos_integer().
read_buffer_bytes(Owner) ->
    {ok, Port} = port_of(Owner),
    {ok, [{buffer, Bytes}]} = inet:getopts(Port, [buffer]),
    Bytes.
