-module(planted_table_ffi).
-export([utf16/1, with_folder/1, persistent_terms_under/1]).

%% The UTF-16 little-endian bytes of a string, with no ending zero character.
utf16(Text) ->
    unicode:characters_to_binary(Text, utf8, {utf16, little}).

%% Makes a folder no other call has used, runs Body with its path, and
%% removes the folder afterwards, also when Body crashes.
with_folder(Body) ->
    Base = case os:getenv("TMPDIR") of
               false -> "/tmp";
               Folder -> Folder
           end,
    Name = io_lib:format("planted_table_~s_~p", [os:getpid(), erlang:unique_integer([positive])]),
    Path = unicode:characters_to_binary(filename:join(Base, lists:flatten(Name))),
    ok = filelib:ensure_path(Path),
    try
        Body(Path)
    after
        file:del_dir_r(Path)
    end.

%% How many persistent terms are stored under a key of the form {Key, Index}.
persistent_terms_under(Key) ->
    length([Stored || {{Under, _Index} = Stored, _Term} <- persistent_term:get(),
                      Under =:= Key]).
