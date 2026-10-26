-module(connection_load_ffi).
-export([start_distribution/0, stop_distribution/0, start_peer/0, stop_peer/1,
         start_clients/5, stop_clients/1, connected/1, stop_tree/1, new_counter/0, increment/1,
         counter_value/1, cpu_milliseconds/0, wall_milliseconds/0, owners/1,
         read_owners/1, burn/0, connect/1, send/2, send_if_open/2, close/1]).

%% How long a call to the peer, or the start of it, may take before the
%% benchmark stops with a message instead of hanging.
-define(DEADLINE_MS, 60000).

%% The measured processes: owner pids with the sums and largest values read
%% from them.
-type reading() :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}.

-spec start_distribution() -> {ok, node()} | {error, nil}.
start_distribution() ->
    Name = list_to_atom("connection_load_" ++ os:getpid()),
    case net_kernel:start(Name, #{name_domain => shortnames}) of
        {ok, _Pid} ->
            {ok, node()};
        {error, Reason} ->
            io:format(standard_error, "distribution did not start: ~p~n",
                      [Reason]),
            {error, nil}
    end.

-spec stop_distribution() -> nil.
stop_distribution() ->
    ok = net_kernel:stop(),
    nil.

%% A peer node of this project that holds the clients, so their cost is not in
%% the server's CPU time. The peer runs with the same code path as this node.
-spec start_peer() -> {ok, {pid(), node()}} | {error, nil}.
start_peer() ->
    Root = code:root_dir(),
    Paths = [Path || Path <- code:get_path(),
                     Path =/= ".",
                     not lists:prefix(Root, Path)],
    Options = #{name => peer:random_name("connection_load_clients"),
                args => ["-pa" | Paths],
                wait_boot => ?DEADLINE_MS},
    case peer:start_link(Options) of
        {ok, Controller, Node} ->
            {ok, {Controller, Node}};
        {error, Reason} ->
            io:format(standard_error, "peer did not start: ~p~n", [Reason]),
            {error, nil}
    end.

-spec stop_peer({pid(), node()}) -> nil.
stop_peer({Controller, _Node}) ->
    ok = peer:stop(Controller),
    nil.

%% Connects `Count` clients to `Port` from the peer and has each send a frame of
%% `FrameBytes` bytes (header included) `FramesPerSecond` times a second, its
%% first send at a random moment within its first period. Clients connect in
%% batches of 40 every 100 ms, so the listening socket's backlog is never full.
%% Returns the handle to stop them with, and how many connected.
-spec start_clients({pid(), node()}, non_neg_integer(), non_neg_integer(),
                    non_neg_integer(), non_neg_integer()) ->
    {ok, {node(), pid(), non_neg_integer()}} | {error, nil}.
start_clients({_Controller, Node}, Port, Count, FramesPerSecond, FrameBytes) ->
    Caller = self(),
    Ref = make_ref(),
    Supervisor = spawn(Node,
                       fun() ->
                               run_clients(Caller, Ref, Port, Count,
                                           FramesPerSecond, FrameBytes)
                       end),
    receive
        {Ref, connected, Connected} -> {ok, {Node, Supervisor, Connected}}
    after ?DEADLINE_MS ->
        {error, nil}
    end.

-spec stop_clients({node(), pid(), non_neg_integer()}) -> nil.
stop_clients({_Node, Supervisor, _Connected}) ->
    Monitor = monitor(process, Supervisor),
    Supervisor ! stop,
    receive {'DOWN', Monitor, _, _, _} -> nil
    after ?DEADLINE_MS -> nil
    end.

%% Runs on the peer.
run_clients(Caller, Ref, Port, Count, FramesPerSecond, FrameBytes) ->
    Frame = <<FrameBytes:32/little, 16#0244:16/little,
              (binary:copy(<<0>>, FrameBytes - 6))/binary>>,
    PeriodMicroseconds = 1000000 div FramesPerSecond,
    Parent = self(),
    Pids = connect_in_batches(Count, Port, Frame, PeriodMicroseconds, Parent, []),
    Connected = length(Pids),
    Caller ! {Ref, connected, Connected},
    [Pid ! go || Pid <- Pids],
    receive stop -> [Pid ! stop || Pid <- Pids], ok end,
    lists:foreach(fun(Pid) ->
                          Monitor = monitor(process, Pid),
                          receive {'DOWN', Monitor, _, _, _} -> ok end
                  end, Pids).

connect_in_batches(0, _Port, _Frame, _Period, _Parent, Pids) ->
    Pids;
connect_in_batches(Remaining, Port, Frame, Period, Parent, Pids) ->
    Batch = min(Remaining, 40),
    New = [client(Port, Frame, Period) || _ <- lists:seq(1, Batch)],
    timer:sleep(100),
    connect_in_batches(Remaining - Batch, Port, Frame, Period, Parent,
                       [Pid || Pid <- New, is_pid(Pid)] ++ Pids).

client(Port, Frame, Period) ->
    Parent = self(),
    Pid = spawn(fun() ->
                        Connected = gen_tcp:connect({127, 0, 0, 1}, Port,
                                                    [binary, {active, false},
                                                     {nodelay, true}]),
                        Parent ! {self(), Connected},
                        case Connected of
                            {ok, Socket} ->
                                receive go -> ok end,
                                send_loop(Socket, Frame, Period,
                                          erlang:monotonic_time(microsecond)
                                          + rand:uniform(Period));
                            {error, _} -> ok
                        end
                end),
    receive
        {Pid, {ok, _}} -> Pid;
        {Pid, {error, _}} -> error
    end.

send_loop(Socket, Frame, Period, DueMicroseconds) ->
    Wait = max(0, (DueMicroseconds - erlang:monotonic_time(microsecond)) div 1000),
    receive
        stop -> gen_tcp:close(Socket)
    after Wait ->
        case gen_tcp:send(Socket, Frame) of
            ok -> send_loop(Socket, Frame, Period, DueMicroseconds + Period);
            {error, _} -> ok
        end
    end.

%% Stops a supervisor linked to the caller, and its children in order, as its
%% parent would, and waits until it is gone.
-spec stop_tree(pid()) -> nil.
stop_tree(Supervisor) ->
    Monitor = monitor(process, Supervisor),
    unlink(Supervisor),
    exit(Supervisor, shutdown),
    receive {'DOWN', Monitor, _, _, _} -> nil
    after ?DEADLINE_MS -> nil
    end.

-spec connected({node(), pid(), non_neg_integer()}) -> non_neg_integer().
connected({_Node, _Supervisor, Connected}) ->
    Connected.

-spec new_counter() -> counters:counters_ref().
new_counter() ->
    counters:new(1, [write_concurrency]).

-spec increment(counters:counters_ref()) -> nil.
increment(Counter) ->
    counters:add(Counter, 1, 1),
    nil.

-spec counter_value(counters:counters_ref()) -> integer().
counter_value(Counter) ->
    counters:get(Counter, 1).

%% The CPU time of this runtime system in milliseconds, all its threads.
-spec cpu_milliseconds() -> integer().
cpu_milliseconds() ->
    {Total, _SinceLast} = erlang:statistics(runtime),
    Total.

-spec wall_milliseconds() -> integer().
wall_milliseconds() ->
    erlang:monotonic_time(millisecond).

%% The socket owners under a top supervisor with one listener: the workers of
%% the connection supervisor, which is the child of the listener's supervisor
%% that is a supervisor.
-spec owners(pid()) -> [pid()].
owners(Top) ->
    lists:flatmap(
        fun({_Id, Listener, supervisor, _Modules}) when is_pid(Listener) ->
                lists:flatmap(
                    fun({_, Connections, supervisor, _}) when is_pid(Connections) ->
                            [Pid || {_, Pid, worker, _} <- supervisor:which_children(Connections),
                                    is_pid(Pid)];
                       (_Other) ->
                            []
                    end,
                    supervisor:which_children(Listener));
           (_Other) ->
                []
        end,
        supervisor:which_children(Top)).

%% One reading of the owners: the longest mailbox, the largest heap in words
%% with the shared binaries each holds counted, and the sum of their
%% reductions. A process that has ended is left out.
-spec read_owners([pid()]) -> reading().
read_owners(Owners) ->
    lists:foldl(
        fun(Pid, {Mailbox, Heap, Reductions}) ->
                case process_info(Pid, [message_queue_len, total_heap_size,
                                        binary, reductions]) of
                    [{message_queue_len, Queue}, {total_heap_size, Words},
                     {binary, Binaries}, {reductions, Done}] ->
                        BinaryWords = lists:sum([Size || {_, Size, _} <- Binaries])
                            div 8,
                        {max(Mailbox, Queue), max(Heap, Words + BinaryWords),
                         Reductions + Done};
                    _ ->
                        {Mailbox, Heap, Reductions}
                end
        end,
        {0, 0, 0},
        Owners).

%% A handler's extra work, under a microsecond, for the planted variant.
-spec burn() -> nil.
burn() ->
    lists:foldl(fun(X, Acc) -> Acc + X end, 0, lists:seq(1, 100)),
    nil.

%% A client socket to this machine's listener, for runs that send a few frames.
-spec connect(non_neg_integer()) -> {ok, port()} | {error, nil}.
connect(Port) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port,
                         [binary, {active, false}, {nodelay, true}]) of
        {ok, Socket} -> {ok, Socket};
        {error, _Reason} -> {error, nil}
    end.

-spec send(port(), binary()) -> {ok, nil} | {error, nil}.
send(Socket, Bytes) ->
    case gen_tcp:send(Socket, Bytes) of
        ok -> {ok, nil};
        {error, _Reason} -> {error, nil}
    end.

-spec send_if_open(port(), binary()) -> nil.
send_if_open(Socket, Bytes) ->
    _ = gen_tcp:send(Socket, Bytes),
    nil.

-spec close(port()) -> nil.
close(Socket) ->
    gen_tcp:close(Socket),
    nil.
