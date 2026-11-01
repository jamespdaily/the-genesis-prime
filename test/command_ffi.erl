%% Runs an executable found on the PATH and waits for it to end, for a test
%% that builds and runs a scratch project. The Gleam types are in command.gleam.
-module(command_ffi).
-export([run/4]).

run(Executable, Arguments, Directory, TimeoutMs) ->
    case os:find_executable(binary_to_list(Executable)) of
        false ->
            {error, executable_not_found};
        Path ->
            Port = open_port({spawn_executable, Path},
                             [{args, [binary_to_list(Argument) || Argument <- Arguments]},
                              {cd, binary_to_list(Directory)},
                              exit_status, stderr_to_stdout, binary, hide]),
            Timer = erlang:send_after(TimeoutMs, self(), {command_timeout, Port}),
            Result = collect(Port, Timer, <<>>),
            erlang:cancel_timer(Timer),
            Result
    end.

collect(Port, Timer, Output) ->
    receive
        {Port, {data, Data}} ->
            collect(Port, Timer, <<Output/binary, Data/binary>>);
        {Port, {exit_status, Status}} ->
            {ok, {ran, Status, Output}};
        {command_timeout, Port} ->
            try port_close(Port) catch error:badarg -> ok end,
            {error, timed_out}
    end.
