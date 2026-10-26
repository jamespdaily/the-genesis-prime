-module(released_child_ffi).
-export([open_program/3, signal_term/1, kill_if_running/1, os_pid/1]).

%% The Gleam types of test/released_child.gleam: Child is the port of the
%% child's operating system process.

%% The variables the server reads its settings from. A child gets exactly the
%% ones a test gives it: the others are removed from the environment it would
%% inherit from this VM.
-define(SETTINGS, [
    "PGHOST", "PGPORT", "PGUSER", "PGDATABASE", "PGPASSWORD", "GENESIS_TABLE_DIR"
]).

%% Opens the program at an absolute path with the given arguments and the given
%% variables added to this VM's environment, less the server's settings that
%% are not given, its output read as whole lines, errors included, and its
%% exit status reported.
-spec open_program(binary(), [binary()], [{binary(), binary()}]) -> port().
open_program(Program, Arguments, Environment) ->
    Given = [
        {binary_to_list(Name), binary_to_list(Value)}
     || {Name, Value} <- Environment
    ],
    Removed = [
        {Name, false}
     || Name <- ?SETTINGS, not lists:keymember(Name, 1, Given)
    ],
    open_port(
        {spawn_executable, binary_to_list(Program)},
        [
            {args, [binary_to_list(Argument) || Argument <- Arguments]},
            {env, Given ++ Removed},
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
            try
                port_close(Port)
            catch
                error:badarg -> ok
            end,
            nil;
        none ->
            nil
    end.
