-module(shutdown_ffi).
-behaviour(gen_event).

%% The runtime calls `genesis_prime/shutdown` makes that no Gleam package
%% binds: the node's SIGTERM handler, the logger, and ending the node.
-export([handle_sigterm/1, log_info/1, log_warning/1, log_error/1, end_node/1]).
%% The handler of `erl_signal_server` that `handle_sigterm` adds.
-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2, code_change/3]).

%% Makes SIGTERM call the function instead of stopping the node with
%% `init:stop()`, which is what the VM's own handler, `erl_signal_handler`, does
%% (Kernel's `erl_signal_server`; `os:set_signal/2`). The VM's handler is
%% replaced by one that gives every other signal to it, so SIGUSR1 and SIGQUIT
%% do what they did. The function runs in `erl_signal_server`, so it must only
%% send a message.
-spec handle_sigterm(fun(() -> nil)) -> nil.
handle_sigterm(OnSigterm) ->
    ok = os:set_signal(sigterm, handle),
    case gen_event:delete_handler(erl_signal_server, erl_signal_handler, []) of
        {error, module_not_found} -> ok;
        {error, Reason} -> error({signal_handler_not_deleted, Reason});
        _Terminated -> ok
    end,
    ok = gen_event:add_handler(erl_signal_server, ?MODULE, OnSigterm),
    nil.

%% Logs through Erlang's logger, the text as one message.
-spec log_info(binary()) -> nil.
log_info(Text) ->
    logger:info("~ts", [Text]),
    nil.

-spec log_warning(binary()) -> nil.
log_warning(Text) ->
    logger:warning("~ts", [Text]),
    nil.

-spec log_error(binary()) -> nil.
log_error(Text) ->
    logger:error("~ts", [Text]),
    nil.

%% Ends the node with the status through the VM's orderly stop, which stops
%% the applications and flushes the logger before the VM halts. Returns at
%% once; the VM ends a moment later.
-spec end_node(non_neg_integer()) -> nil.
end_node(Status) ->
    ok = init:stop(Status),
    nil.

init(OnSigterm) ->
    {ok, Default} = erl_signal_handler:init([]),
    {ok, {OnSigterm, Default}}.

handle_event(sigterm, {OnSigterm, _Default} = State) ->
    OnSigterm(),
    {ok, State};
handle_event(Signal, {OnSigterm, Default}) ->
    {ok, Next} = erl_signal_handler:handle_event(Signal, Default),
    {ok, {OnSigterm, Next}}.

handle_call(_Request, State) ->
    {ok, ok, State}.

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Arg, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
