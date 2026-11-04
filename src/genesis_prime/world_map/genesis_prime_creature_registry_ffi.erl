%% OTP's pg as the creature registry (genesis_prime/world_map/creature_registry):
%% a process, given by its pid, joining a group. A group is the Gleam value of
%% `step.Address`, `{creature, Map, Incarnation, UnitId}` for a creature. The
%% scope and the members of a group are started and read through
%% genesis_prime_connection_registry_ffi.
-module(genesis_prime_creature_registry_ffi).

-export([join_pid/3]).

%% Makes the process a member of the group, unless it is one; the scope removes
%% it when it ends.
join_pid(Scope, Group, Pid) ->
    case lists:member(Pid, pg:get_local_members(Scope, Group)) of
        true -> nil;
        false ->
            ok = pg:join(Scope, Group, Pid),
            nil
    end.
