-module(database_support_ffi).
-export([once/2, run_identifier/0, run_command/3, open_watcher/3]).

%% Runs Create once in this VM, whichever test asks first, and gives every
%% later caller the same value. The value lives in a persistent term, written
%% once per key; a global lock makes a second caller wait for the first.
once(Key, Create) ->
    Slot = {?MODULE, Key},
    case persistent_term:get(Slot, none) of
        {value, Value} ->
            Value;
        none ->
            global:trans(
                {Slot, self()},
                fun() ->
                    case persistent_term:get(Slot, none) of
                        {value, Value} ->
                            Value;
                        none ->
                            Value = Create(),
                            persistent_term:put(Slot, {value, Value}),
                            Value
                    end
                end,
                [node()],
                infinity
            )
    end.

%% The operating system process id and start time of this VM, as one word that
%% is safe in a database name.
run_identifier() ->
    iolist_to_binary([
        os:getpid(), "_", integer_to_list(erlang:system_time(millisecond))
    ]).

%% Runs a program to its end with the given arguments and environment,
%% returning its combined output; an error holds the output of a program that
%% failed or was not found.
run_command(Program, Arguments, Environment) ->
    case os:find_executable(binary_to_list(Program)) of
        false ->
            {error, {command_failed, <<"program not found: ", Program/binary>>}};
        Executable ->
            Port = open_port(
                {spawn_executable, Executable},
                [
                    {args, [binary_to_list(Argument) || Argument <- Arguments]},
                    {env, environment(Environment)},
                    exit_status,
                    stderr_to_stdout,
                    binary
                ]
            ),
            collect(Port, <<>>)
    end.

collect(Port, Output) ->
    receive
        {Port, {data, Data}} -> collect(Port, <<Output/binary, Data/binary>>);
        {Port, {exit_status, 0}} -> {ok, Output};
        {Port, {exit_status, _}} -> {error, {command_failed, Output}}
    end.

%% Starts a shell that waits for its input to close, which happens when this
%% VM ends however it ends, and then runs the script. The calling process must
%% live as long as the VM, because the input closes when it ends too.
open_watcher(Script, Arguments, Environment) ->
    open_port(
        {spawn_executable, "/bin/sh"},
        [
            {args, ["-c", binary_to_list(Script), "watcher"] ++
                [binary_to_list(Argument) || Argument <- Arguments]},
            {env, environment(Environment)},
            use_stdio,
            binary
        ]
    ),
    nil.

environment(Environment) ->
    [{binary_to_list(Name), binary_to_list(Value)} || {Name, Value} <- Environment].
