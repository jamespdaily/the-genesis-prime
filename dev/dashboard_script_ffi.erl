%% Runs a script as an operating-system process through a port and returns what
%% `genesis_prime/dashboard/script` describes: `{ok, {finished, Output, Status}}`
%% or `{error, Failure}`. The port merges the script's standard error into its
%% output. A script still running at the deadline gets SIGTERM, and SIGKILL if
%% it has not ended `?end_wait_ms` later, and this returns once it has ended.
-module(dashboard_script_ffi).
-export([run/4, find_on_path/1]).

-define(end_wait_ms, 2000).

-spec run(binary(), [binary()], [{binary(), binary()}], integer()) ->
    {ok, {finished, binary(), integer()}}
    | {error, {not_found, binary()}}
    | {error, {not_executable, binary()}}
    | {error, {not_started, binary(), binary()}}
    | {error, {deadline_reached, integer()}}.
run(Path, Arguments, Environment, DeadlineMs) ->
    Executable = unicode:characters_to_list(Path),
    Env = [
        {unicode:characters_to_list(Name), unicode:characters_to_list(Value)}
     || {Name, Value} <- Environment
    ],
    Args = [unicode:characters_to_list(Argument) || Argument <- Arguments],
    Options = [
        binary, exit_status, stderr_to_stdout, use_stdio, hide, {env, Env}, {args, Args}
    ],
    try open_port({spawn_executable, Executable}, Options) of
        Port ->
            Deadline = erlang:monotonic_time(millisecond) + DeadlineMs,
            collect(Port, Deadline, DeadlineMs, [])
    catch
        error:enoent ->
            {error, {not_found, Path}};
        error:eacces ->
            {error, {not_executable, Path}};
        error:Reason ->
            {error, {not_started, Path, iolist_to_binary(io_lib:format("~p", [Reason]))}}
    end.

collect(Port, Deadline, DeadlineMs, Output) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Data}} ->
            collect(Port, Deadline, DeadlineMs, [Output, Data]);
        {Port, {exit_status, Status}} ->
            {ok, {finished, iolist_to_binary(Output), Status}}
    after Remaining ->
        end_script(Port),
        {error, {deadline_reached, DeadlineMs}}
    end.

%% Ends the script's own process and waits until the port reports that it has
%% ended; the output it printed meanwhile is dropped.
end_script(Port) ->
    case erlang:port_info(Port, os_pid) of
        {os_pid, OsPid} ->
            signal("TERM", OsPid),
            case wait_for_end(Port) of
                ended ->
                    ok;
                still_running ->
                    signal("KILL", OsPid),
                    wait_for_end(Port)
            end;
        undefined ->
            ok
    end,
    catch port_close(Port),
    ok.

signal(Name, OsPid) ->
    os:cmd("kill -" ++ Name ++ " " ++ integer_to_list(OsPid) ++ " 2>/dev/null"),
    ok.

wait_for_end(Port) ->
    receive
        {Port, {data, _}} -> wait_for_end(Port);
        {Port, {exit_status, _}} -> ended
    after ?end_wait_ms ->
        still_running
    end.

%% The path of the executable `Name` on this VM's search path, as the shell would
%% find it.
-spec find_on_path(binary()) -> {ok, binary()} | {error, nil}.
find_on_path(Name) ->
    case os:find_executable(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Path -> {ok, unicode:characters_to_binary(Path)}
    end.
