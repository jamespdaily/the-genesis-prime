-module(map_support_ffi).
-export([max_heap_words/1, schedulers_online/0, suspend/1, resume/1,
         registered_name/1, unregister_name/1, monitored_by/1]).

%% The heap ceiling in words that a running process has set on itself
%% (process_info(Pid, max_heap_size), whose `size` is 0 for no ceiling).
-spec max_heap_words(pid()) -> non_neg_integer().
max_heap_words(Pid) ->
    {max_heap_size, #{size := Size}} = process_info(Pid, max_heap_size),
    Size.

%% The schedulers online, which the number of senders of a map follows.
-spec schedulers_online() -> pos_integer().
schedulers_online() ->
    erlang:system_info(schedulers_online).

%% Stops a process from running until `resume`, so a request to it has no
%% answer within its deadline.
-spec suspend(pid()) -> nil.
suspend(Pid) ->
    true = erlang:suspend_process(Pid),
    nil.

-spec resume(pid()) -> nil.
resume(Pid) ->
    true = erlang:resume_process(Pid),
    nil.

%% The name a running process is registered under, as text.
-spec registered_name(pid()) -> {ok, binary()} | {error, nil}.
registered_name(Pid) ->
    case process_info(Pid, registered_name) of
        {registered_name, Name} -> {ok, atom_to_binary(Name)};
        _ -> {error, nil}
    end.

%% Frees the name a running process is registered under, as a process that is
%% between two lives of its name would have it.
-spec unregister_name(pid()) -> nil.
unregister_name(Pid) ->
    {registered_name, Name} = process_info(Pid, registered_name),
    true = unregister(Name),
    nil.

%% The processes that monitor `Pid` now.
-spec monitored_by(pid()) -> [pid()].
monitored_by(Pid) ->
    {monitored_by, Watchers} = process_info(Pid, monitored_by),
    Watchers.
