-module(released_node_ffi).
-export([
    open/2,
    next_event/2,
    end_child/1,
    ask/2,
    free_port/0,
    with_cleanup/2,
    accepts_connections/1,
    names_at/1,
    kill_epmd/1,
    report/2
]).

%% The Gleam types of test/released_node.gleam:
%%   Process is the port of the child VM.
%%   Event: Line(text) is {line, Text}, ExitStatus(status) is {exit_status,
%%   Status} and Silent is silent.

%% How long a child may take to end once it is told to stop, in milliseconds,
%% before it is killed, and how long it may then take to be gone. Its exit
%% status announces the end, so these are deadlines for a child that hangs,
%% never a wait.
-define(CHILD_STOP_DEADLINE_MS, 10000).
-define(CHILD_KILL_DEADLINE_MS, 5000).

%% How long the epmd of a child may take to let go of a node that has ended,
%% in milliseconds, and how often it is asked again. No message announces that
%% the epmd has dropped the node, so the kill is asked until it is allowed.
%% The same deadline holds for the epmd to stop answering once it is killed.
-define(KILL_DEADLINE_MS, 10000).
-define(KILL_RETRY_MS, 50).

%% How long the child's survey waits for a query through the server's pool to
%% be answered or the top supervisor to end, and how often a failed query is
%% asked again meanwhile, in milliseconds. The deadline is for a pool that
%% neither answers nor ends, never a wait: an answer or the end stops it.
-define(SURVEY_DEADLINE_MS, 20000).
-define(QUERY_RETRY_MS, 20).

%%% The test's side.

%% Opens the child: the erl of this installation with this VM's code paths
%% outside OTP, the given arguments, and the given variables added to this
%% VM's environment. The output comes as whole lines, errors included.
-spec open([binary()], [{binary(), binary()}]) -> port().
open(Arguments, Environment) ->
    Erl = filename:join([code:root_dir(), "bin", "erl"]),
    OtpLibraries = code:lib_dir(),
    Paths = [
        Path
     || Path <- code:get_path(),
        Path =/= ".",
        not lists:prefix(OtpLibraries, Path)
    ],
    open_port(
        {spawn_executable, Erl},
        [
            {args, ["-pa" | Paths] ++ [binary_to_list(Argument) || Argument <- Arguments]},
            {env, [
                {binary_to_list(Name), binary_to_list(Value)}
             || {Name, Value} <- Environment
            ]},
            {line, 65536},
            use_stdio,
            stderr_to_stdout,
            exit_status,
            binary
        ]
    ).

%% The next line the child wrote, its exit status, or silent when it wrote
%% nothing for Within milliseconds.
-spec next_event(port(), non_neg_integer()) ->
    {line, binary()} | {exit_status, integer()} | silent.
next_event(Port, Within) ->
    receive
        {Port, {data, {eol, Line}}} -> {line, Line};
        {Port, {data, {noeol, Line}}} -> {line, Line};
        {Port, {exit_status, Status}} -> {exit_status, Status}
    after Within -> silent
    end.

%% Writes one line to the child's input, which is how the test asks it to
%% survey itself. A child that has ended has closed its port already.
-spec ask(port(), binary()) -> nil.
ask(Port, Line) ->
    true = port_command(Port, [Line, $\n]),
    nil.

%% Ends the child and waits for its operating system process to exit, which
%% its port reports as an exit status. The child is told to stop on its input,
%% the one way every program of it ends, and is killed when it has not exited
%% by the deadline; either way the exit is waited for, and a child that is
%% still there after the kill is an error. A child that has ended has closed
%% its port already, and nothing is done.
-spec end_child(port()) -> nil.
end_child(Port) ->
    case erlang:port_info(Port, os_pid) of
        undefined ->
            nil;
        {os_pid, OsPid} ->
            _ = catch port_command(Port, [<<"stop">>, $\n]),
            case await_exit(Port, ?CHILD_STOP_DEADLINE_MS) of
                {exit_status, _} ->
                    nil;
                timeout ->
                    _ = os:cmd("kill -9 " ++ integer_to_list(OsPid)),
                    case await_exit(Port, ?CHILD_KILL_DEADLINE_MS) of
                        {exit_status, _} ->
                            nil;
                        timeout ->
                            error({child_would_not_end, OsPid, ?CHILD_STOP_DEADLINE_MS})
                    end
            end
    end.

%% The exit status of the port's process, or timeout when it has not exited
%% within Within milliseconds. What the child still writes is dropped.
await_exit(Port, Within) ->
    Deadline = erlang:monotonic_time(millisecond) + Within,
    await_exit_by(Port, Deadline).

await_exit_by(Port, Deadline) ->
    Remaining = max(Deadline - erlang:monotonic_time(millisecond), 0),
    receive
        {Port, {exit_status, Status}} -> {exit_status, Status};
        {Port, {data, _}} -> await_exit_by(Port, Deadline)
    after Remaining -> timeout
    end.

%% A port on the loopback with nothing listening, chosen by listening on port
%% 0 and closing the socket again.
-spec free_port() -> inet:port_number().
free_port() ->
    {ok, Listen} = gen_tcp:listen(0, [inet, {ip, {127, 0, 0, 1}}]),
    {ok, Port} = inet:port(Listen),
    ok = gen_tcp:close(Listen),
    Port.

-spec with_cleanup(fun(() -> A), fun(() -> nil)) -> A.
with_cleanup(Body, Cleanup) ->
    try
        Body()
    after
        Cleanup()
    end.

%% Whether a connection to the port on the loopback is accepted. Refused is
%% the one other answer a port with nothing listening gives.
-spec accepts_connections(inet:port_number()) -> boolean().
accepts_connections(Port) ->
    case gen_tcp:connect({127, 0, 0, 1}, Port, [], 5000) of
        {ok, Socket} ->
            ok = gen_tcp:close(Socket),
            true;
        {error, econnrefused} ->
            false
    end.

%% The node names the epmd on the port lists, read from `epmd -names`, which
%% prints one line `name NAME at port PORT` for each; none when there is no
%% epmd on the port.
-spec names_at(inet:port_number()) -> [binary()].
names_at(Port) ->
    Output = epmd(Port, "-names"),
    case string:find(Output, "Cannot connect") of
        nomatch ->
            [
                list_to_binary(Name)
             || Line <- string:split(Output, "\n", all),
                ["name", Name, "at", "port", _] <- [string:lexemes(Line, " ")]
            ];
        _ ->
            []
    end.

%% Kills the epmd on the port, if there is one, once the node that was
%% registered with it has left. epmd refuses while a node is registered
%% ("Killing not allowed - living nodes in database", exit status 1, from
%% `epmd_cli.c`), and drops a node only when it notices the node's connection
%% closed, a moment after the node's process has exited. So a refusal is asked
%% again until the deadline, when it is an error that names the nodes epmd
%% still lists. Once killed, epmd is waited for until it stops accepting
%% connections.
-spec kill_epmd(inet:port_number()) -> nil.
kill_epmd(Port) ->
    Deadline = erlang:monotonic_time(millisecond) + ?KILL_DEADLINE_MS,
    kill_epmd(Port, Deadline).

kill_epmd(Port, Deadline) ->
    {Status, Output} = run_epmd(Port, "-kill"),
    case {Status, kill_answer(Output)} of
        {1, no_epmd} ->
            nil;
        {0, killed} ->
            await_epmd_gone(Port, Deadline);
        {1, refused} ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true ->
                    timer:sleep(?KILL_RETRY_MS),
                    kill_epmd(Port, Deadline);
                false ->
                    error(
                        iolist_to_binary(
                            io_lib:format(
                                "epmd on port ~b would not be killed within ~b ms: "
                                "it still lists the nodes ~p",
                                [Port, ?KILL_DEADLINE_MS, names_at(Port)]
                            )
                        )
                    )
            end;
        _ ->
            error({epmd_failed, Port, "-kill", Status, Output})
    end.

%% What `epmd -kill` said: that it killed epmd, that there is no epmd on the
%% port, that epmd refused because a node is registered, or something else.
kill_answer(Output) ->
    case
        {
            string:find(Output, "Killed"),
            string:find(Output, "Cannot connect"),
            string:find(Output, "living nodes")
        }
    of
        {nomatch, nomatch, nomatch} -> other;
        {nomatch, nomatch, _} -> refused;
        {nomatch, _, nomatch} -> no_epmd;
        {_, nomatch, nomatch} -> killed;
        _ -> other
    end.

%% Waits for the port to stop accepting connections: epmd answers the kill and
%% then exits, so it can accept a connection for a moment after.
await_epmd_gone(Port, Deadline) ->
    case accepts_connections(Port) of
        false ->
            nil;
        true ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true ->
                    timer:sleep(?KILL_RETRY_MS),
                    await_epmd_gone(Port, Deadline);
                false ->
                    error({epmd_still_answers_after_kill, Port})
            end
    end.

%% The output of one epmd command on the port. epmd exits with 0 when it
%% answers and with 1 when there is no epmd on the port; any other result is an
%% error.
epmd(Port, Command) ->
    {Status, Output} = run_epmd(Port, Command),
    case {Status, string:find(Output, "Cannot connect")} of
        {0, _} -> Output;
        {1, Found} when Found =/= nomatch -> Output;
        _ -> error({epmd_failed, Port, Command, Status, Output})
    end.

run_epmd(Port, Command) ->
    Epmd = filename:join([code:root_dir(), "bin", "epmd"]),
    Opened = open_port(
        {spawn_executable, Epmd},
        [{args, ["-port", integer_to_list(Port), Command]}, exit_status, stderr_to_stdout]
    ),
    collect(Opened, []).

collect(Opened, Output) ->
    receive
        {Opened, {data, Data}} -> collect(Opened, [Output, Data]);
        {Opened, {exit_status, Status}} -> {Status, lists:flatten(Output)}
    end.

%%% The child's side, run as `-eval 'released_node_ffi:report(Planted, Program)'`.

%% Starts what Program says, waits until the top supervisor has started every
%% child, opens Planted extra listening sockets, writes the report, and then
%% answers each line the test writes with a survey (see `survey/1`) until the
%% input closes, when the VM ends. The server's entry point runs in a process
%% of its own, as a release runs it, traced for the one event the wait needs:
%% the spawn of the top supervisor, the first process it starts. A call to the
%% supervisor is answered once its children have started, so the answer is the
%% signal that the tree is up. When the entry point ends first, its reason is
%% written and the VM ends with status 1.
-spec report(non_neg_integer(), server | idle | lingering | connecting) -> no_return().
report(Planted, Program) ->
    Tree =
        case Program of
            server -> start_server();
            idle -> none;
            lingering -> none;
            connecting -> none
        end,
    _Sockets = [
        begin
            {ok, Socket} = gen_tcp:listen(0, []),
            Socket
        end
     || _ <- lists:seq(1, Planted)
    ],
    _Connecting = [plant_connect() || Program =:= connecting],
    io:format("node ~s~n", [node()]),
    io:format("net_kernel ~s~n", [service(net_kernel)]),
    io:format("epmd_client ~s~n", [service(erl_epmd)]),
    io:format("listening ~s~n", [
        lists:join(" ", [integer_to_list(Port) || Port <- listening_ports()])
    ]),
    io:format("report-end~n"),
    answer(Tree, Program).

%% An address nothing answers: 10.255.255.1 is in a private range no network
%% routes to a host, so a connect to it is sent and never answered, until the
%% connect's own timeout, set here far past any test.
-define(DROPPED_ADDRESS, {10, 255, 255, 1}).
-define(DROPPED_PORT, 9).
-define(CONNECT_TIMEOUT_MS, 600000).

%% How long a planted connect may take to be seen in progress, in
%% milliseconds, and how often it is looked for meanwhile. A connect is in
%% progress from the moment its process opens the socket until its answer or
%% timeout, and no message announces the start, so it is looked for; the
%% deadline is for a connect that ended at once (a network that refuses the
%% address), never a wait.
-define(PLANT_DEADLINE_MS, 5000).
-define(PLANT_RETRY_MS, 5).

%% Starts a process that connects to an address that drops packets, and
%% returns once its socket is seen connecting: open, with no peer. When the
%% connect ends first, the child ends with an error that says so.
plant_connect() ->
    Connector = spawn(fun() ->
        _ = gen_tcp:connect(?DROPPED_ADDRESS, ?DROPPED_PORT, [], ?CONNECT_TIMEOUT_MS),
        receive
        after infinity -> ok
        end
    end),
    Deadline = erlang:monotonic_time(millisecond) + ?PLANT_DEADLINE_MS,
    await_connecting(Connector, Deadline).

await_connecting(Connector, Deadline) ->
    Connecting = [
        Socket
     || Socket <- erlang:ports(),
        erlang:port_info(Socket, name) =:= {name, "tcp_inet"},
        erlang:port_info(Socket, connected) =:= {connected, Connector},
        {ok, States} <- [prim_inet:getstatus(Socket)],
        lists:member(connecting, States)
    ],
    case {Connecting, erlang:monotonic_time(millisecond) < Deadline} of
        {[_], _} ->
            ok;
        {[], true} ->
            timer:sleep(?PLANT_RETRY_MS),
            await_connecting(Connector, Deadline);
        {[], false} ->
            io:format("stopped the planted connect was not in progress~n"),
            halt(1)
    end.

%% A child ends when its input closes or when it is told to stop, which is how
%% a test's cleanup ends it and waits for its exit. A lingering child ends only
%% when told to stop, so it is alive and registered with its epmd until then.
answer(Tree, Program) ->
    case io:get_line("") of
        eof when Program =:= lingering ->
            receive
            after infinity -> ok
            end;
        eof ->
            halt(0);
        "stop\n" ->
            halt(0);
        "survey\n" ->
            survey(Tree),
            answer(Tree, Program)
    end.

%% What the node is now, written for each line the test asks with. The tree is
%% read after one of the two events that end the wait: a query through the
%% pool is answered, or the top supervisor ends (a monitor says so). A pool
%% that is being rebuilt answers a query with an error at once, so the query is
%% asked again after `?QUERY_RETRY_MS` until one of the two events, or the
%% deadline `?SURVEY_DEADLINE_MS`, which is an unanswered query.
%% - `query` is `ok` when a query through the pool is answered, or why not.
%% - `tree` is whether the top supervisor of the entry point is running,
%%   `stopped` also for a node that started no entry point.
%% - `applications` are the started applications, sorted.
survey(Tree) ->
    Query = await_query(Tree),
    io:format("query ~s~n", [Query]),
    io:format("tree ~s~n", [tree(Tree)]),
    Applications = lists:sort([Name || {Name, _, _} <- application:which_applications()]),
    io:format("applications ~s~n", [lists:join(" ", [atom_to_list(Name) || Name <- Applications])]),
    io:format("survey-end~n").

tree(none) -> stopped;
tree(Supervisor) ->
    case is_process_alive(Supervisor) of
        true -> running;
        false -> stopped
    end.

await_query(none) ->
    query_through_pool();
await_query(Supervisor) ->
    Monitor = erlang:monitor(process, Supervisor),
    Deadline = erlang:monotonic_time(millisecond) + ?SURVEY_DEADLINE_MS,
    Query = await_query(Supervisor, Monitor, Deadline),
    erlang:demonitor(Monitor, [flush]),
    Query.

await_query(Supervisor, Monitor, Deadline) ->
    case query_through_pool() of
        "ok" ->
            "ok";
        Why ->
            Remaining = Deadline - erlang:monotonic_time(millisecond),
            receive
                {'DOWN', Monitor, process, Supervisor, _} -> Why
            after min(?QUERY_RETRY_MS, max(Remaining, 0)) ->
                case Remaining > 0 of
                    true -> await_query(Supervisor, Monitor, Deadline);
                    false -> Why
                end
            end
    end.

%% Runs `select 1` through the server's database pool, found by its registered
%% name (the entry point makes it with the prefix `database_pool`).
query_through_pool() ->
    Pools = [
        Name
     || Name <- registered(),
        lists:prefix("database_pool", atom_to_list(Name))
    ],
    case Pools of
        [Pool] ->
            try pgo:query(<<"select 1">>, [], #{pool => Pool}) of
                #{rows := [{1}]} -> "ok";
                Other -> io_lib:format("~0p", [Other])
            catch
                Class:Reason -> io_lib:format("~0p", [{Class, Reason}])
            end;
        _ ->
            io_lib:format("pools ~0p", [Pools])
    end.

%% Starts the applications the way Gleam's generated entry point does
%% (`genesis_prime@@main:run_module`: `application:ensure_all_started` of the
%% project's application, before `main`), then the entry point, and returns the
%% top supervisor once its children have started. The applications start in
%% this process, so the one spawn the trace waits for is the entry point's.
start_server() ->
    case application:ensure_all_started(genesis_prime) of
        {ok, _} ->
            ok;
        {error, StartReason} ->
            io:format("stopped ~s~n", [reason_text(StartReason)]),
            halt(1)
    end,
    Main = spawn(fun() ->
        receive
            go -> genesis_prime:main()
        end
    end),
    1 = erlang:trace(Main, true, [procs]),
    Monitor = erlang:monitor(process, Main),
    Main ! go,
    receive
        {trace, Main, spawn, Supervisor, _} ->
            _ = supervisor:which_children(Supervisor),
            Supervisor;
        {'DOWN', Monitor, process, Main, Reason} ->
            io:format("stopped ~s~n", [reason_text(Reason)]),
            halt(1)
    end.

%% The message of a crash made by `panic as`, which is a map with a `message`
%% key; any other reason as it is.
reason_text(#{message := Message}) -> Message;
reason_text(Reason) -> io_lib:format("~0p", [Reason]).

service(Name) ->
    case whereis(Name) of
        undefined -> stopped;
        _ -> running
    end.

%% The ports of the node's listening TCP sockets: a socket whose states
%% (`inet:info/1`, `states`) include `listen`. A socket with an address of its
%% own and no peer is not enough: one that is still connecting has both, as
%% the server's database pool's sockets do while it opens its connections. A
%% socket that has closed meanwhile reports the state `closed` and is not
%% counted.
listening_ports() ->
    lists:usort([
        Port
     || Socket <- erlang:ports(),
        erlang:port_info(Socket, name) =:= {name, "tcp_inet"},
        #{states := States} <- [inet:info(Socket)],
        lists:member(listen, States),
        {ok, {_, Port}} <- [inet:sockname(Socket)]
    ]).
