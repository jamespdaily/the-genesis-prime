%% What the sitting bot's SIGTERM test needs of the runtime and no Gleam library
%% exposes: the event the VM's signal handling raises on a SIGTERM, raised by
%% hand (the operating system's signal would end the test run's own node), and
%% OTP's own handler put back afterwards, since the bot's replaces it.
-module(sitting_bot_signal_ffi).
-export([send_sigterm/0, restore_signal_handler/0]).

%% Raises what the VM raises when it receives SIGTERM.
send_sigterm() ->
    ok = gen_event:notify(erl_signal_server, sigterm),
    nil.

%% Removes the bot's handler and puts OTP's own back.
restore_signal_handler() ->
    _ = gen_event:delete_handler(erl_signal_server, sitting_bot_ffi, []),
    _ = gen_event:add_handler(erl_signal_server, erl_signal_handler, []),
    nil.
