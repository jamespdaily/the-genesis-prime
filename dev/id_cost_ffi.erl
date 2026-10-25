-module(id_cost_ffi).
-export([monotonic_nanoseconds/0, collect/0, reductions/0,
         start_counting_allocation/0, stop_counting_allocation/0]).

monotonic_nanoseconds() ->
    erlang:monotonic_time(nanosecond).

collect() ->
    erlang:garbage_collect(),
    nil.

reductions() ->
    {reductions, Reductions} = process_info(self(), reductions),
    Reductions.

%% Traces the calling process's garbage collections to a collector process,
%% then collects once, which gives the collector a starting point.
start_counting_allocation() ->
    Collector = spawn_link(fun() -> collect_events([]) end),
    put(id_cost_collector, Collector),
    erlang:trace(self(), true, [garbage_collection, {tracer, Collector}]),
    erlang:garbage_collect(),
    nil.

%% Collects once more, stops the trace and returns the words the process
%% allocated since `start_counting_allocation`.
stop_counting_allocation() ->
    erlang:garbage_collect(),
    erlang:trace(self(), false, [garbage_collection]),
    Collector = erase(id_cost_collector),
    Collector ! {stop, self()},
    receive
        {events, Events} -> allocated_words(Events, undefined, 0)
    end.

collect_events(Events) ->
    receive
        {stop, Caller} -> Caller ! {events, lists:reverse(Events)};
        {trace, _, _, _} = Event -> collect_events([Event | Events])
    end.

%% A collection reports the used part of the young heap, and the heap fragments
%% outside it, when it starts and when it ends. What the process
%% allocated between two collections is the used size at the start of the next
%% minus the used size at the end of the last, whatever the collection kept or
%% moved to the old heap. Events before the first collection's end are skipped.
allocated_words([], _, Allocated) ->
    Allocated;
allocated_words([{trace, _, Tag, Info} | Events], Ended, Allocated) ->
    Used = proplists:get_value(heap_size, Info) +
        proplists:get_value(mbuf_size, Info),
    case {lists:member(Tag, [gc_minor_start, gc_major_start]), Ended} of
        {true, undefined} -> allocated_words(Events, Ended, Allocated);
        {true, _} -> allocated_words(Events, Ended, Allocated + Used - Ended);
        {false, _} -> allocated_words(Events, Used, Allocated)
    end.
