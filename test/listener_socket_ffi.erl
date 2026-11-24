%% What the listener tests read from Ranch and the runtime that Gleam has no
%% call for: the listening sockets a Ranch listener holds, and whether a socket
%% is still open. Each function returns the Gleam shape its caller declares.
-module(listener_socket_ffi).

-export([listening_sockets_of/1, is_open/1]).

%% The listening sockets of the listener Ref: the ports its acceptors'
%% supervisor owns and is linked to (Ranch opens them in that supervisor's
%% init). A suspended listener has no acceptors' supervisor, so none.
listening_sockets_of(Ref) ->
    ListenerSup = ranch_server:get_listener_sup(Ref),
    lists:flatmap(
      fun({ranch_acceptors_sup, Acceptors, supervisor, _}) when is_pid(Acceptors) ->
              {links, Links} = process_info(Acceptors, links),
              [Port || Port <- Links, is_port(Port)];
         (_) ->
              []
      end,
      supervisor:which_children(ListenerSup)).

%% Whether the port is still open: a closed port has no info.
is_open(Port) ->
    erlang:port_info(Port) =/= undefined.
