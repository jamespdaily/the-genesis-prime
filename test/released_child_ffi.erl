-module(released_child_ffi).
-export([open_program/3, signal_term/1, kill_if_running/1, os_pid/1]).

%% The Gleam types of test/released_child.gleam: Child is the port of the
%% child's operating system process.

%% Opens the program at an absolute path with the given arguments and the given
%% variables added to this VM's environment, its output read as whole lines,
%% errors included, and its exit status reported.
-spec open_program(binary(), [binary()], [{binary(), binary()}]) -> port().
open_program(Program, Arguments, Environment) ->
    open_port(
        {spawn_executable, binary_to_list(Program)},
        [
            {args, [binary_to_list(Argument) || Argument <- Arguments]},
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

%% The operating system process id of the child, or none when it has ended.
-spec os_pid(port()) -> {some, integer()} | none.
os_pid(Port) ->
    case erlang:port_info(Port, os_pid) of
        {os_pid, Pid} -> {some, Pid};
        undefined -> none
    end.

%% Sends SIGTERM to the child's operating system process, as a host stopping
%% the server does.
-spec signal_term(port()) -> nil.
signal_term(Port) ->
    {some, Pid} = os_pid(Port),
    "" = os:cmd("kill -TERM " ++ integer_to_list(Pid)),
    nil.

%% Kills the child's operating system process if it is still running, and
%% closes its port. A child that has ended has closed its port already.
-spec kill_if_running(port()) -> nil.
kill_if_running(Port) ->
    case os_pid(Port) of
        {some, Pid} ->
            _ = os:cmd("kill -KILL " ++ integer_to_list(Pid)),
            catch port_close(Port),
            nil;
        none ->
            nil
    end.
