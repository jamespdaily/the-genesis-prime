%% Ranch's protocol callback for a connection shell, and the socket and clock
%% calls the shell makes. Ranch calls start_link/3, an Erlang behaviour callback
%% Gleam cannot declare; the process it starts hands over to
%% genesis_prime@connection@shell:run/2.
-module(connection_shell_ffi).
-behaviour(ranch_protocol).

-export([start_link/3, start_listener/4]).

%% Starts the connection's process, linked to Ranch's connection supervisor.
start_link(_Ref, _Transport, _Settings) ->
    erlang:error(shape_only).

%% Starts a listener under the caller's supervisor: Ranch's embedded supervisor
%% for the given port and connection settings.
start_listener(_Ref, _Port, _ShutdownMs, _Settings) ->
    erlang:error(shape_only).
