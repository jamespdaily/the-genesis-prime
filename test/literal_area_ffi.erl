-module(literal_area_ffi).
-export([record_peak/1, carriers_peak/0, persistent_term_memory/0, tables_held_twice/0,
         names_held_twice/1, tables_held_twice_with/1, names_held_twice_with/2,
         table_names/0, pending_bytes/0, pending_limit_bytes/0,
         wait_until_released/0, admissions/0, wait_until/2, wait_bound_ms/0,
         with_the_collector_suspended/1]).

%% Starts a process that writes the literal allocator's highest carriers size
%% since the VM started to File whenever it grows, as decimal digits and a line
%% end. The allocator keeps that record itself, so a peak between two samples is
%% still read by the next one. The file is replaced whole (written beside, then
%% renamed), so a reader never sees half a number. It ends when the file cannot
%% be written or its folder is gone.
record_peak(File) ->
    spawn(fun() -> sample(unicode:characters_to_list(File), 0) end),
    nil.

sample(File, Written) ->
    case filelib:is_dir(filename:dirname(File)) of
        true -> sample_peak(File, Written);
        false -> ok
    end.

sample_peak(File, Written) ->
    Peak = carriers_peak(),
    case Peak > Written of
        true ->
            Beside = File ++ ".writing",
            case file:write_file(Beside, [integer_to_list(Peak), $\n]) of
                ok ->
                    _ = file:rename(Beside, File),
                    timer:sleep(20),
                    sample(File, Peak);
                {error, _Gone} ->
                    ok
            end;
        false ->
            timer:sleep(20),
            sample(File, Written)
    end.

%% The highest carriers size of the literal allocator since the VM started,
%% in bytes: the allocator's own record, from mbcs and sbcs.
carriers_peak() ->
    lists:sum([Peak
               || {instance, _, Properties} <- erlang:system_info({allocator_sizes, literal_alloc}),
                  {Kind, Fields} <- Properties,
                  Kind =:= mbcs orelse Kind =:= sbcs,
                  {carriers_size, _Current, _LastPeak, Peak} <- [lists:keyfind(carriers_size, 1, Fields)]]).

%% How many bytes the persistent terms the VM holds take.
persistent_term_memory() ->
    maps:get(memory, persistent_term:info()).

%% The names of the tables of which two persistent terms of a megabyte or more
%% are held: a table's term is {Load, {table_term, Name}} (genesis_prime/table/
%% loader/store). Two loads of one file hold terms of the same name and size; a
%% planted table can pass a megabyte too (character_tables.
%% shared_with_spell_trees' Spell4Effects), but its size is not the client's.
tables_held_twice() ->
    names_held_twice(persistent_term:get()).

%% The names of the tables of a megabyte or more that Load holds a term of and
%% another load holds a term of the same name and size: the table of Load
%% loaded a second time. Another load of a table of that name with other rows,
%% as a planted load or the fixture's, has another size and is not a copy, and
%% two other loads of one table are not Load's to count, so a load of a test
%% running beside does not change the answer.
tables_held_twice_with(Load) ->
    names_held_twice_with(Load, persistent_term:get()).

names_held_twice_with(Load, Terms) ->
    Megabyte = 1024 * 1024,
    Large = [{Held, Name, Size} || {{Held, {table_term, Name}}, Term} <- Terms,
                                   Size <- [erts_debug:flat_size(Term) * erlang:system_info(wordsize)],
                                   Size >= Megabyte],
    lists:usort([Name || {Held, Name, Size} <- Large, Held =:= Load,
                         lists:any(fun({Other, OtherName, OtherSize}) ->
                                           Other =/= Load andalso OtherName =:= Name andalso OtherSize =:= Size
                                   end, Large)]).

%% The names of every table term the VM holds, of any size, in order: what the
%% pattern of names_held_twice finds among the keys the store really writes.
table_names() ->
    lists:usort([Name || {Name, _Term} <- table_terms(persistent_term:get())]).

%% Each table's name and term among the keys and terms: a table's term is
%% stored under {Load, {table_term, Name}} (genesis_prime/table/loader/store).
table_terms(Terms) ->
    [{Name, Term} || {{_Load, {table_term, Name}}, Term} <- Terms].

names_held_twice(Terms) ->
    Megabyte = 1024 * 1024,
    Large = [{Name, Size} || {Name, Term} <- table_terms(Terms),
                             Size <- [erts_debug:flat_size(Term) * erlang:system_info(wordsize)],
                             Size >= Megabyte],
    lists:usort([Name || {Name, _Size} <- Large -- lists:usort(Large)]).

%% What the allocator holds beyond the live persistent terms may be this many
%% bytes when a load starts: the VM's own literals take about 9 MB of it, and
%% the rest is room for a planted load's erased terms (6 to 23 MB each).
-define(PENDING_LIMIT, 33554432).

pending_limit_bytes() ->
    ?PENDING_LIMIT.

%% The bytes of the allocator's allocated blocks that are not in a live
%% persistent term: terms erased and not yet released by the literal area
%% collector, and the VM's own literals. The allocator's own account, read the
%% way carriers_peak/0 reads it.
pending_bytes() ->
    Allocated = lists:sum([Size
                           || {instance, _, Properties} <- erlang:system_info({allocator_sizes, literal_alloc}),
                              {Kind, Fields} <- Properties,
                              Kind =:= mbcs orelse Kind =:= sbcs,
                              {blocks, [{literal_alloc, Sizes}]} <- [lists:keyfind(blocks, 1, Fields)],
                              {size, Size, _, _} <- [lists:keyfind(size, 1, Sizes)]]),
    max(0, Allocated - persistent_term_memory()).

%% The longest any wait of the gate takes before it gives up and fails the test
%% that waits, so a wait that never ends is a failure that names what it waited
%% for.
-define(WAIT_BOUND_MS, 60000).

wait_bound_ms() ->
    ?WAIT_BOUND_MS.

%% Returns when Check() is true, checking again every millisecond; after the
%% bound it ends the calling process with the text Describe() gives. The one wait
%% of the gate: the literal area's release (wait_until_released/0) and a place
%% among the loads (owned_key_ffi) are both made with it.
wait_until(Check, Describe) ->
    wait_until(Check, Describe, erlang:monotonic_time(millisecond) + ?WAIT_BOUND_MS).

wait_until(Check, Describe, Until) ->
    case Check() of
        true ->
            ok;
        false ->
            case erlang:monotonic_time(millisecond) >= Until of
                true ->
                    erlang:error({gave_up_waiting, unicode:characters_to_binary(Describe())});
                false ->
                    timer:sleep(1),
                    wait_until(Check, Describe, Until)
            end
    end.

%% Returns when pending_bytes/0 is at most the limit. The collector releases the
%% erased terms whatever a test does, so the wait ends.
wait_until_released() ->
    wait_until(fun() -> pending_bytes() =< ?PENDING_LIMIT end, fun describe_pending/0),
    erlang:put(literal_area_admissions, admissions() + 1),
    nil.

describe_pending() ->
    io_lib:format("waited ~p ms for the literal area collector: ~p bytes pending, limit ~p",
                  [?WAIT_BOUND_MS, pending_bytes(), ?PENDING_LIMIT]).

%% How many times the calling process has come out of wait_until_released/0.
admissions() ->
    case erlang:get(literal_area_admissions) of
        undefined -> 0;
        Count -> Count
    end.

%% Runs Fun while the literal area collector is suspended, so a term erased in it
%% stays allocated until Fun returns.
with_the_collector_suspended(Fun) ->
    [Collector] = [Pid || Pid <- processes(),
                          process_info(Pid, initial_call)
                              =:= {initial_call, {erts_literal_area_collector, start, 0}}],
    erlang:suspend_process(Collector),
    try Fun() after erlang:resume_process(Collector) end.
