%% The two OTP calls the server's start needs that no gleam_erlang or gleam_otp
%% function makes, so the application module (genesis_prime/application) calls
%% them here, each with the Gleam shape it declares.
%%
%% - Starting the tree under the application's root: gleam_otp starts a child of
%%   a factory supervisor through its `Supervisor` handle, which only
%%   `factory_supervisor.start` and `get_by_name` make, and a name made by
%%   `process.new_name` differs in every run, so `main` cannot find the root by
%%   one. `application:get_supervisor/1` finds the root by the application's
%%   name, and `supervisor:start_child/2` starts the tree under it.
%% - The node's own state: gleam_erlang has nothing for `init:get_status/0`.
-module(genesis_prime_application_ffi).

-export([start_tree/1, node_stopping/0]).

%% Starts the server's tree under the application's root with the settings and
%% gives its pid: Result(Pid, StartFailure). The failure is the Gleam value
%% `ApplicationNotRunning` when no root runs, as when the node is stopping, and
%% `TreeNotStarted(StartError)` when the root runs and the tree did not start.
%% The root's template reports a failed start as a Gleam `StartError`; a start
%% that crashed is reported as one that exited.
start_tree(Settings) ->
    case application:get_supervisor(genesis_prime) of
        undefined -> {error, application_not_running};
        {ok, Root} ->
            try supervisor:start_child(Root, [Settings]) of
                {ok, Pid, _Data} -> {ok, Pid};
                {ok, Pid} -> {ok, Pid};
                {error, Reason} -> {error, {tree_not_started, start_error(Reason)}}
            catch
                exit:{noproc, _} -> {error, application_not_running};
                exit:{shutdown, _} -> {error, application_not_running}
            end
    end.

%% The Gleam `StartError` of a failed start: the template's own value, or, for
%% a start that crashed, an exit with the crash's reason.
start_error(init_timeout) -> init_timeout;
start_error({init_failed, _} = Failed) -> Failed;
start_error({init_exited, _} = Exited) -> Exited;
start_error(Reason) -> {init_exited, {abnormal, Reason}}.

%% Whether the node has begun to stop: `init:stop/0`, which SIGTERM makes the
%% VM run, sets the status to `stopping` before it stops any application.
node_stopping() ->
    {Internal, _Provided} = init:get_status(),
    Internal =:= stopping.
