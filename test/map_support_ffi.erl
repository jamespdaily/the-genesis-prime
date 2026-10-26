-module(map_support_ffi).
-export([max_heap_words/1, schedulers_online/0, suspend/1, resume/1]).

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
