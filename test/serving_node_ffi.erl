%% Starts an operating-system process of its own running the Erlang VM the tests
%% run on, with the code the tests loaded, started as `gleam run` starts a
%% program (`genesis_prime@@main:run(Module)`: the application first, then the
%% module's `main`). It is the only way to see how a node ends: its exit status,
%% what it printed, and what SIGTERM does to it. The port belongs to the process
%% that started the node, which reads the node's output and exit status from its
%% mailbox, so every call here is made by that process.
-module(serving_node_ffi).
-export([start/2, await_output/2, terminate/1, await_exit/1, output/1, root_ended/0]).

%% Whether the application's root has ended: the node sets its status to stopping
%% before it stops the application, so a node that is stopping may still have
%% its root, and a tree started then is stopped with it.
root_ended() ->
    whereis(genesis_prime_root) =:= undefined.

%% Starts the node running Module's main with the environment, a list of name
%% and value pairs added to the test VM's own. A guardian ends the node when the
%% process that started it ends, however it ends.
start(Module, Environment) ->
    Erl = filename:join([code:root_dir(), "bin", "erl"]),
    Paths = fresh_node_ffi:project_paths(),
    Eval = "genesis_prime@@main:run(" ++ binary_to_list(Module) ++ ")",
    Port = open_port({spawn_executable, Erl},
                     [{args, ["-noshell", "-pa" | Paths] ++ ["-eval", Eval]},
                      {env, database_support_ffi:environment(Environment)},
                      exit_status, stderr_to_stdout, binary]),
    {os_pid, OsPid} = erlang:port_info(Port, os_pid),
    Owner = self(),
    spawn(fun() ->
        Watched = erlang:monitor(process, Owner),
        receive {'DOWN', Watched, process, Owner, _} ->
            os:cmd("kill -KILL " ++ integer_to_list(OsPid))
        end
    end),
    {node, Port, OsPid}.

%% Whether the node printed Text before it ended. The wait has no limit of its
%% own: a node that neither prints it nor ends leaves the test's deadline to end
%% the wait.
await_output(Node, Text) ->
    wait_for(Node, binary_to_list(Text)).

wait_for({node, Port, _} = Node, Text) ->
    case string:find(binary_to_list(output(Node)), Text) of
        nomatch ->
            case exit_status(Port) =:= none of
                true -> pump(Port), wait_for(Node, Text);
                false -> false
            end;
        _ -> true
    end.

%% Sends the node SIGTERM, as the host does.
terminate({node, _Port, OsPid}) ->
    os:cmd("kill -TERM " ++ integer_to_list(OsPid)),
    nil.

%% The node's exit status, once it has ended. The wait has no limit of its own.
await_exit({node, Port, _}) ->
    exit_loop(Port).

exit_loop(Port) ->
    case exit_status(Port) of
        none -> pump(Port), exit_loop(Port);
        Status -> Status
    end.

%% Everything the node printed so far, as the process has read it.
output({node, Port, _}) ->
    case get({output, Port}) of
        undefined -> <<>>;
        Bytes -> Bytes
    end.

%% Takes the node's next output or its exit status from the mailbox, and waits
%% for one of them.
pump(Port) ->
    receive
        {Port, {data, Bytes}} ->
            put({output, Port}, <<(output({node, Port, 0}))/binary, Bytes/binary>>);
        {Port, {exit_status, Status}} ->
            put({exit, Port}, Status)
    end.

exit_status(Port) ->
    case get({exit, Port}) of
        undefined -> none;
        Status -> Status
    end.
