%% OTP's pg as the connection registry (genesis_prime/connection/registry): the
%% scope started under a supervisor, a process joining a group, the members
%% of a group and the delivery of a message to a connection's shell. A group
%% is the Gleam value of `step.Address`, `{connection, {connection_id, Id}}`
%% for a connection. Each function returns the Gleam shape its caller declares.
-module(genesis_prime_connection_registry_ffi).

-export([start_scope/1, join_group/2, join_once/2, leave_group/2, members/2, send_woken/2,
         woken_message/1]).

%% Starts the scope as the calling supervisor's child, registered under the
%% atom the Gleam side made for it; pg links the scope to the supervisor.
start_scope(Scope) ->
    case pg:start_link(Scope) of
        {ok, Pid} -> {ok, Pid};
        {error, Reason} -> {error, {could_not_start, genesis_prime_step_runtime_ffi:term_text(Reason)}}
    end.

%% Makes the calling process a member of the group; the scope removes it when it
%% ends.
join_group(Scope, Group) ->
    ok = pg:join(Scope, Group, self()),
    nil.

%% Makes the calling process a member of the group unless it is one: a group holds
%% a process once, so a join that repeats leaves one membership.
join_once(Scope, Group) ->
    case lists:member(self(), pg:get_local_members(Scope, Group)) of
        true -> nil;
        false -> join_group(Scope, Group)
    end.

%% Removes the calling process from the group; a process that is not a member is
%% left as it is.
leave_group(Scope, Group) ->
    _ = pg:leave(Scope, Group, self()),
    nil.

%% The members of the group on this node.
members(Scope, Group) ->
    pg:get_local_members(Scope, Group).

%% The message as the connection shell's selector takes it, which turns it into
%% a Woken input (genesis_prime/connection/registry select_delivered).
send_woken(Pid, Message) ->
    Pid ! {woken, Message},
    nil.

%% The message inside what send_woken sent.
woken_message({woken, Message}) -> Message.
