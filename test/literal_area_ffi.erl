-module(literal_area_ffi).
-export([record_peak/1, carriers_peak/0, persistent_term_memory/0, persistent_term_count/0,
         allocated_bytes/0, tables_not_shared/2, flat_size/1, through_ets/1]).

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

%% How many persistent terms the VM holds.
persistent_term_count() ->
    maps:get(count, persistent_term:info()).

%% The bytes of the literal allocator's allocated blocks: the persistent terms,
%% the VM's own literals, and the terms erased and not yet released by the
%% literal area collector. The allocator's own account, read the way
%% carriers_peak/0 reads it.
allocated_bytes() ->
    lists:sum([Size
               || {instance, _, Properties} <- erlang:system_info({allocator_sizes, literal_alloc}),
                  {Kind, Fields} <- Properties,
                  Kind =:= mbcs orelse Kind =:= sbcs,
                  {blocks, [{literal_alloc, Sizes}]} <- [lists:keyfind(blocks, 1, Fields)],
                  {size, Size, _, _} <- [lists:keyfind(size, 1, Sizes)]]).

%% How many of the values First reads its tables from Second does not read its
%% tables from as the very same term (the same words, not an equal copy): the
%% persistent terms First reads that Second does not, and the tables First holds
%% in its edits that are not the same words in Second's: 0 when Second shares
%% every table of First. A `Tables` is {tables, Stored, StoredDerived, {EditedTables,
%% EditedDerived}, Digest}.
tables_not_shared({tables, FirstStored, _, {FirstEdits, _}, _},
                  {tables, SecondStored, _, {SecondEdits, _}, _}) ->
    length([Key || Key <- FirstStored, not lists:member(Key, SecondStored)]) +
        length([Name || {Name, Table} <- maps:to_list(FirstEdits),
                        not erts_debug:same(Table, maps:get(Name, SecondEdits, none))]).

%% The words Value takes when it is copied whole to another heap or into ETS,
%% where a persistent term in it is copied too.
flat_size(Value) -> erts_debug:flat_size(Value).

%% Value inserted into a new ETS table and read back: the copy an insert makes.
through_ets(Value) ->
    Table = ets:new(through_ets, [set, private]),
    ets:insert(Table, {held, Value}),
    [{held, Back}] = ets:lookup(Table, held),
    ets:delete(Table),
    Back.
