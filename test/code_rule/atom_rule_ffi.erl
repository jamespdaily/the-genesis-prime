%% Finds where Erlang source calls or refers to one of the named BIFs, read
%% with Erlang's own scanner, so comments, strings and whitespace are what the
%% compiler sees. A name counts when it is unqualified or qualified by
%% `erlang:`, and it is called (followed by `(`) or referred to as a fun
%% (followed by `/`). Another module's function of the same name does not
%% count. Gives the line of each, or {error, Line} when the text does not scan.
-module(atom_rule_ffi).
-export([unsafe_lines/2]).

unsafe_lines(Text, Names) ->
    Atoms = [binary_to_atom(Name) || Name <- Names],
    case erl_scan:string(unicode:characters_to_list(Text)) of
        {ok, Tokens, _End} -> {ok, walk(Tokens, none, none, Atoms, [])};
        {error, {Line, _Module, _Reason}, _} -> {error, line_of(Line)}
    end.

%% Before is the token just before the current one, BeforeThat the one before.
walk([], _, _, _, Found) ->
    lists:reverse(Found);
walk([{atom, Anno, Name} = Token | Rest], Before, BeforeThat, Atoms, Found) ->
    Counts = lists:member(Name, Atoms)
        andalso qualified_by_erlang_or_none(Before, BeforeThat)
        andalso called_or_referred(Rest),
    Next = case Counts of
               true -> [line_of(Anno) | Found];
               false -> Found
           end,
    walk(Rest, Token, Before, Atoms, Next);
walk([Token | Rest], Before, _BeforeThat, Atoms, Found) ->
    walk(Rest, Token, Before, Atoms, Found).

qualified_by_erlang_or_none({':', _}, {atom, _, erlang}) -> true;
qualified_by_erlang_or_none({':', _}, _) -> false;
qualified_by_erlang_or_none(_, _) -> true.

called_or_referred([{'(', _} | _]) -> true;
called_or_referred([{'/', _} | _]) -> true;
called_or_referred(_) -> false.

line_of(Anno) -> erl_anno:line(Anno).
