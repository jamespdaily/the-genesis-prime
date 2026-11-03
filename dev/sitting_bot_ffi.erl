%% What the sitting bot needs of the runtime and no Gleam library exposes
%% (genesis_prime/sitting_bot): a stop that a process can be asked for from
%% outside, and the operating system's SIGTERM turned into that stop. OTP's own
%% signal handler answers SIGTERM with init:stop, which ends the VM before the bot
%% can close its connection and print its summary, so the handler is replaced
%% by one that sends the bot its stop instead.
-module(sitting_bot_ffi).
-behaviour(gen_event).
-export([request_stop/1, stop_requested/0, stop_on_sigterm/1]).
-export([init/1, handle_event/2, handle_call/2, handle_info/2]).

%% Asks the process to stop: it finds the request with stop_requested/0.
request_stop(Pid) ->
    Pid ! sitting_bot_stop,
    nil.

%% Whether a stop was asked of the calling process, without waiting.
stop_requested() ->
    receive
        sitting_bot_stop -> true
    after 0 -> false
    end.

%% Makes the SIGTERM the VM receives ask the process for a stop, in place of
%% OTP's handler, which stops the VM.
stop_on_sigterm(Pid) ->
    _ = gen_event:delete_handler(erl_signal_server, erl_signal_handler, []),
    ok = gen_event:add_handler(erl_signal_server, ?MODULE, Pid),
    nil.

init(Pid) ->
    {ok, Pid}.

handle_event(sigterm, Pid) ->
    Pid ! sitting_bot_stop,
    {ok, Pid};
handle_event(_Signal, Pid) ->
    {ok, Pid}.

handle_call(_Request, Pid) ->
    {ok, ok, Pid}.

handle_info(_Info, Pid) ->
    {ok, Pid}.
