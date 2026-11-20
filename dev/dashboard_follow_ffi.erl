%% Reads a piece of a file for `genesis_prime/dashboard/follow`: opens the file,
%% looks at the open file's inode and size, asks the caller what to read, reads
%% that piece with one positional read, and closes it. Nothing is kept open
%% between calls and no operating-system process is started.
%%
%% The caller's `Decide` is given the inode and the size of the file that was
%% opened and returns `{Offset, Length, Decision}`; `Decision` is handed back
%% untouched. The file is looked at by its path first only to refuse what is not
%% a regular file before opening it (opening a named pipe waits for a writer);
%% the inode and the size are those of the open file, so a file replaced after
%% that look is read as the file it is.
-module(dashboard_follow_ffi).
-export([read_piece/2]).

-include_lib("kernel/include/file.hrl").

-spec read_piece(binary(), fun((integer(), integer()) -> {integer(), integer(), term()})) ->
    {ok, {term(), binary()}} | {error, not_there} | {error, {unreadable, binary()}}.
read_piece(Path, Decide) ->
    Name = unicode:characters_to_list(Path),
    case file:read_file_info(Name) of
        {ok, #file_info{type = regular}} -> open_and_read(Name, Decide);
        {ok, #file_info{type = directory}} -> unreadable(eisdir);
        {ok, #file_info{}} -> unreadable(not_a_regular_file);
        {error, enoent} -> {error, not_there};
        {error, Reason} -> unreadable(Reason)
    end.

open_and_read(Name, Decide) ->
    case file:open(Name, [read, raw, binary]) of
        {ok, File} ->
            try opened(File, Decide) after file:close(File) end;
        {error, enoent} -> {error, not_there};
        {error, Reason} -> unreadable(Reason)
    end.

opened(File, Decide) ->
    case file:read_file_info(File) of
        {ok, #file_info{type = regular, inode = Inode, size = Size}} ->
            {Offset, Length, Decision} = Decide(Inode, Size),
            piece(File, Offset, Length, Decision);
        {ok, #file_info{}} -> unreadable(not_a_regular_file);
        {error, Reason} -> unreadable(Reason)
    end.

piece(_File, _Offset, 0, Decision) ->
    {ok, {Decision, <<>>}};
piece(File, Offset, Length, Decision) ->
    case file:pread(File, Offset, Length) of
        {ok, Bytes} -> {ok, {Decision, Bytes}};
        eof -> {ok, {Decision, <<>>}};
        {error, Reason} -> unreadable(Reason)
    end.

unreadable(Reason) when is_atom(Reason) ->
    {error, {unreadable, atom_to_binary(Reason)}};
unreadable(Reason) ->
    {error, {unreadable, iolist_to_binary(io_lib:format("~p", [Reason]))}}.
