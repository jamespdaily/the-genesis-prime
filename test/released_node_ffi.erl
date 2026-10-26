-module(released_node_ffi).
-export([
    open/2,
    next_event/2,
    close/1,
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

%% How long the epmd of a child may take to let go of a node that is ending,
%% in milliseconds, and how often it is asked again. No message announces that
%% the epmd has dropped the node, so the kill is asked until it is allowed.
-define(KILL_DEADLINE_MS, 10000).
-define(KILL_RETRY_MS, 50).

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

%% Closes the child's input, which ends it. A child that has ended has closed
%% its port already.
-spec close(port()) -> nil.
close(Port) ->
    case erlang:port_info(Port) of
        undefined ->
            nil;
        _ ->
            port_close(Port),
            nil
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

%% Kills the epmd on the port, if there is one. epmd refuses while a node is
%% registered with it, and a child that is ending is registered until its VM
%% is gone, so the kill is asked again until it is allowed or the deadline
%% passes, which is an error.
-spec kill_epmd(inet:port_number()) -> nil.
kill_epmd(Port) ->
    Deadline = erlang:monotonic_time(millisecond) + ?KILL_DEADLINE_MS,
    kill_epmd(Port, Deadline).

kill_epmd(Port, Deadline) ->
    Output = epmd(Port, "-kill"),
    case {string:find(Output, "Killed"), string:find(Output, "Cannot connect")} of
        {nomatch, nomatch} ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true ->
                    timer:sleep(?KILL_RETRY_MS),
                    kill_epmd(Port, Deadline);
                false ->
                    error({epmd_would_not_be_killed, Port, Output})
            end;
        _ ->
            nil
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
%% child, opens Planted extra listening sockets, writes the report, and waits
%% for the input to close before the VM ends. The server's entry point runs in
%% a process of its own, as a release runs it, traced for the one event the
%% wait needs: the spawn of the top supervisor, the first process it starts.
%% A call to the supervisor is answered once its children have started, so the
%% answer is the signal that the tree is up. When the entry point ends first,
%% its reason is written and the VM ends with status 1.
-spec report(non_neg_integer(), server | idle) -> no_return().
report(Planted, Program) ->
    case Program of
        server -> start_server();
        idle -> ok
    end,
    _Sockets = [
        begin
            {ok, Socket} = gen_tcp:listen(0, []),
            Socket
        end
     || _ <- lists:seq(1, Planted)
    ],
    io:format("node ~s~n", [node()]),
    io:format("net_kernel ~s~n", [service(net_kernel)]),
    io:format("epmd_client ~s~n", [service(erl_epmd)]),
    io:format("listening ~s~n", [
        lists:join(" ", [integer_to_list(Port) || Port <- listening_ports()])
    ]),
    io:format("report-end~n"),
    eof = io:get_line(""),
    halt(0).

start_server() ->
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
            ok;
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

%% The ports of the node's listening TCP sockets: a socket with an address of
%% its own and no peer, which is what a listening socket is and a connected one
%% is not.
listening_ports() ->
    lists:usort([
        Port
     || Socket <- erlang:ports(),
        erlang:port_info(Socket, name) =:= {name, "tcp_inet"},
        {error, enotconn} =:= inet:peername(Socket),
        {ok, {_, Port}} <- [inet:sockname(Socket)]
    ]).
