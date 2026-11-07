-module(database_support_ffi).
-export([once/2, lock_waiters/1, run_identifier/0, run_command/3, open_watcher/3, environment/1]).

%% Runs Create once in this VM, whichever test asks first, and gives every
%% later caller the same value. The value lives in a persistent term, written
%% once per key; a lock on the key makes a second caller wait for the first and
%% wakes it when the first ends (local_lock_ffi). The atom made from each key is
%% bounded by the repository's files and literals: the keys are literals, and
%% some are made per source file or per label count.
once(Key, Create) ->
    Slot = {?MODULE, Key},
    case persistent_term:get(Slot, none) of
        {value, Value} ->
            Value;
        none ->
            local_lock_ffi:with_lock(
                lock_name(Key),
                fun() ->
                    case persistent_term:get(Slot, none) of
                        {value, Value} ->
                            Value;
                        none ->
                            Value = unlimited_loads(Create),
                            persistent_term:put(Slot, {value, Value}),
                            Value
                    end
                end
            )
    end.

%% The name of the lock on a key.
lock_name(Key) ->
    binary_to_atom(<<"database_support_once ", Key/binary>>).

%% The processes waiting for the lock on Key: those monitoring the gate that
%% holds its name. None when the lock is free.
lock_waiters(Key) ->
    case whereis(lock_name(Key)) of
        undefined ->
            [];
        Gate ->
            case process_info(Gate, monitored_by) of
                {monitored_by, Waiters} -> Waiters;
                undefined -> []
            end
    end.

%% Runs Create while the process holds the lock that every other caller of the
%% same key waits on, so a key it makes for a load is made without waiting for
%% room among the loads held (owned_key_ffi): the processes that hold those
%% loads may be waiting on this lock.
unlimited_loads(Create) ->
    Before = erlang:put(owned_key_unlimited, true),
    try Create() after erlang:put(owned_key_unlimited, Before =:= true) end.

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

%% A program's environment as Erlang's port option wants it: name and value
%% pairs of strings.
environment(Environment) ->
    [{binary_to_list(Name), binary_to_list(Value)} || {Name, Value} <- Environment].
