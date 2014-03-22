-module(pt_utils).

-export([renumber/1, revert/1]).

-type form()    :: any().
-type forms()   :: [form()].



renumber(Result) ->
  Rev = revert(Result),
  renumber_(Rev).

-spec revert(forms()) ->
  forms().
revert(Tree) when is_list(Tree) ->
  WorkAround = needs_revert_workaround(),
  [revert_form(T, WorkAround) || T <- lists:flatten(Tree)].

%revert_form(F) ->
%  revert_form(F, needs_revert_workaround()).

revert_form(F, W) ->
  case erl_syntax:revert(F) of
    {attribute,L,A,Tree} when element(1,Tree) == tree ->
      {attribute,L,A,erl_syntax:revert(Tree)};
    Result ->
      if W -> fix_impl_fun(Result);
        true -> Result
      end
  end.

fix_impl_fun({'fun',L,{function,{atom,_,Fn},{integer,_,Ay}}}) ->
  {'fun',L,{function,Fn,Ay}};
fix_impl_fun({'fun',L,{function,{atom,_,M},{atom,_,Fn},{integer,_,Ay}}}) ->
  {'fun',L,{function,M,Fn,Ay}};
fix_impl_fun(T) when is_tuple(T) ->
  list_to_tuple([fix_impl_fun(F) || F <- tuple_to_list(T)]);
fix_impl_fun([H|T]) ->
  [fix_impl_fun(H) | fix_impl_fun(T)];
fix_impl_fun(X) ->
  X.

needs_revert_workaround() ->
  case application:get_env(dallas_trans,revert_workaround) of
    {ok, Bool} when is_boolean(Bool) -> Bool;
    _ ->
      Res = try lint_reverted()
      catch
        error:_ ->
          true
      end,
      application:set_env(dallas_trans,revert_workaround,Res),
      Res
  end.

lint_reverted() ->
  Ts = [{attribute,1,module,m},
    {attribute,2,export,[{f,0}]},
    erl_syntax:function(erl_syntax:atom(f),
      [erl_syntax:clause(
          [],
          [erl_syntax:implicit_fun(
              erl_syntax:atom(f),
              erl_syntax:integer(0))])])],
  Rev = erl_syntax:revert_forms(Ts),
  erl_lint:module(Rev),
  false.

renumber_(L) when is_list(L) ->
  {Result, _} = renumber_(L, 1),
  Result.

renumber_(L, Acc) when is_list(L) ->
  lists:mapfoldl(fun renumber_/2, Acc, L);
renumber_(T, Prev) when is_tuple(T) ->
  case is_form(T) of
    true ->
      New = Prev+1,
      T1 = setelement(2, T, New),
      {Res, NewAcc} = renumber_(tuple_to_list(T1), New),
      {list_to_tuple(Res), NewAcc};
    false ->
      L = tuple_to_list(T),
      {Res, NewAcc} = renumber_(L, Prev),
      {list_to_tuple(Res), NewAcc}
  end;
renumber_(X, Prev) ->
  {X, Prev}.

is_form(T) when element(1,T)==type -> true;
is_form(T) ->
  try erl_syntax:type(T),
    true
  catch
    error:_ ->
      false
  end.
