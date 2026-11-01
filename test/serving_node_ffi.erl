%% Starts an operating-system process of its own running the Erlang VM the tests
%% run on, with the code the tests loaded, started as `gleam run` starts a
%% program (`genesis_prime@@main:run(Module)`: the application first, then the
%% module's `main`). It is the only way to see how a node ends: its exit status,
%% what it printed, and what SIGTERM does to it. The port belongs to the process
%% that started the node, which reads the node's output and exit status from its
%% mailbox, so every call here is made by that process.
-module(serving_node_ffi).
-export([start/2, await_output/3, terminate/1, await_exit/2, output/1]).

%% Starts the node running Module's main with the environment, a list of name
%% and value pairs added to the test VM's own. A guardian ends the node when the
%% process that started it ends, however it ends.
start(Module, Environment) ->
    Root = code:root_dir(),
    Erl = filename:join([Root, "bin", "erl"]),
    Paths = [Path || Path <- code:get_path(), not lists:prefix(Root, Path)],
    Eval = "genesis_prime@@main:run(" ++ binary_to_list(Module) ++ ")",
    Port = open_port({spawn_executable, Erl},
                     [{args, ["-noshell", "-pa" | Paths] ++ ["-eval", Eval]},
                      {env, [{binary_to_list(Name), binary_to_list(Value)}
                             || {Name, Value} <- Environment]},
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

%% Whether the node has printed Text within TimeoutMs milliseconds.
await_output(Node, Text, TimeoutMs) ->
    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
    wait_for(Node, binary_to_list(Text), Deadline).

wait_for({node, Port, _} = Node, Text, Deadline) ->
    case string:find(binary_to_list(output(Node)), Text) of
        nomatch ->
            Remaining = Deadline - erlang:monotonic_time(millisecond),
            case Remaining > 0 andalso exit_status(Port) =:= none of
                true ->
                    case pump(Port, Remaining) of
                        true -> wait_for(Node, Text, Deadline);
                        false -> false
                    end;
                false -> false
            end;
        _ -> true
    end.

%% Sends the node SIGTERM, as the host does.
terminate({node, _Port, OsPid}) ->
    os:cmd("kill -TERM " ++ integer_to_list(OsPid)),
    nil.

%% The node's exit status, once it has ended within TimeoutMs milliseconds.
await_exit({node, Port, _}, TimeoutMs) ->
    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
    exit_loop(Port, Deadline).

exit_loop(Port, Deadline) ->
    case exit_status(Port) of
        none ->
            Remaining = Deadline - erlang:monotonic_time(millisecond),
            case Remaining > 0 andalso pump(Port, Remaining) of
                true -> exit_loop(Port, Deadline);
                false -> {error, nil}
            end;
        Status -> {ok, Status}
    end.

%% Everything the node printed so far, as the process has read it.
output({node, Port, _}) ->
    case get({output, Port}) of
        undefined -> <<>>;
        Bytes -> Bytes
    end.

%% Takes the node's next output or its exit status from the mailbox, within
%% Remaining milliseconds; false when neither came.
pump(Port, Remaining) ->
    receive
        {Port, {data, Bytes}} ->
            put({output, Port}, <<(output({node, Port, 0}))/binary, Bytes/binary>>),
            true;
        {Port, {exit_status, Status}} ->
            put({exit, Port}, Status),
            true
    after Remaining -> false
    end.

exit_status(Port) ->
    case get({exit, Port}) of
        undefined -> none;
        Status -> Status
    end.
