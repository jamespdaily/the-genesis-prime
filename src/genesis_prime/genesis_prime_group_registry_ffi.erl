%% OTP's pg as a registry of process groups (genesis_prime/group_registry): the
%% scope started under a supervisor, a process joining and leaving a group, the
%% members of a group and the delivery of a message to a process's shell. A group
%% is a Gleam value, `{connection, {connection_id, Id}}` for a connection and
%% `{creature, Map, Incarnation, UnitId}` for a creature. Each function returns
%% the Gleam shape its caller declares.
-module(genesis_prime_group_registry_ffi).

-export([start_scope/1, join_once/3, leave/3, members/2, send_woken/2, woken_message/1]).

%% Starts the scope as the calling supervisor's child, registered under the
%% atom the Gleam side made for it; pg links the scope to the supervisor.
start_scope(Scope) ->
    case pg:start_link(Scope) of
        {ok, Pid} -> {ok, Pid};
        {error, Reason} -> {error, {could_not_start, genesis_prime_step_runtime_ffi:term_text(Reason)}}
    end.

%% Makes the process a member of the group unless it is one: a group holds a
%% process once, so a join that repeats leaves one membership. The scope removes
%% the process when it ends.
join_once(Scope, Group, Pid) ->
    case lists:member(Pid, pg:get_local_members(Scope, Group)) of
        true -> nil;
        false ->
            ok = pg:join(Scope, Group, Pid),
            nil
    end.

%% Removes the process from the group; a process that is not a member is left as
%% it is.
leave(Scope, Group, Pid) ->
    _ = pg:leave(Scope, Group, Pid),
    nil.

%% The members of the group on this node.
members(Scope, Group) ->
    pg:get_local_members(Scope, Group).

%% The message as a shell's selector takes it, which turns it into a delivered
%% input (genesis_prime/group_registry select_delivered).
send_woken(Pid, Message) ->
    Pid ! {woken, Message},
    nil.

%% The message inside what send_woken sent.
woken_message({woken, Message}) -> Message.
