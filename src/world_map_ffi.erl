-module(world_map_ffi).
-export([schedulers_online/0]).

%% The schedulers online now, which the number of senders of a map follows.
-spec schedulers_online() -> pos_integer().
schedulers_online() ->
    erlang:system_info(schedulers_online).
