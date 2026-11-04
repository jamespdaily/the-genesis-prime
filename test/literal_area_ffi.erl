-module(literal_area_ffi).
-export([record_peak/1, carriers_peak/0, persistent_term_memory/0, tables_held_twice/0,
         names_held_twice/1]).

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

names_held_twice(Terms) ->
    Megabyte = 1024 * 1024,
    Large = [{Name, Size} || {{_Load, {table_term, Name}}, Term} <- Terms,
                             Size <- [erts_debug:flat_size(Term) * erlang:system_info(wordsize)],
                             Size >= Megabyte],
    lists:usort([Name || {Name, _Size} <- Large -- lists:usort(Large)]).
