%% OTP's pg as the connection registry (genesis_prime/connection/registry): the
%% scope started under a supervisor, a process joining a group, the members
%% of a group and the delivery of a message to a connection's shell. A group
%% is the Gleam value of `step.Address`, `{connection, {connection_id, Id}}`
%% for a connection. Each function returns the Gleam shape its caller declares.
-module(connection_registry_ffi).

-export([start_scope/1, join_group/2, members/2, send_woken/2]).

%% Starts the scope as the calling supervisor's child, registered under the
%% atom the Gleam side made for it; pg links the scope to the supervisor.
start_scope(Scope) ->
    case pg:start_link(Scope) of
        {ok, Pid} -> {ok, Pid};
        {error, Reason} -> {error, {could_not_start, format(Reason)}}
    end.

%% Makes the calling process a member of the group; the scope removes it when it
%% ends.
join_group(Scope, Group) ->
    ok = pg:join(Scope, Group, self()),
    nil.

%% The members of the group on this node.
members(Scope, Group) ->
    pg:get_local_members(Scope, Group).

%% The message as the connection shell takes it between steps, which turns it
%% into a Woken input (connection_shell_ffi:next_event).
send_woken(Pid, Message) ->
    Pid ! {woken, Message},
    nil.

format(Reason) ->
    unicode:characters_to_binary(io_lib:format("~0p", [Reason])).
