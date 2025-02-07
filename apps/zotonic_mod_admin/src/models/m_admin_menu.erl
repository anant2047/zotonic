%% @author Arjan Scherpenisse <arjan@scherpenisse.net>
%% @copyright 2012 Arjan Scherpenisse <arjan@scherpenisse.net>
%% Date: 2012-03-16

%% @doc Zotonic: admin menu

%% Copyright 2012 Arjan Scherpenisse
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(m_admin_menu).
-author("Arjan Scherpenisse <arjan@scherpenisse.net>").

-behaviour(zotonic_model).

-include_lib("zotonic_core/include/zotonic.hrl").
-include_lib("../../include/admin_menu.hrl").

%% interface functions
-export([
    m_get/3,
    menu/1
]).

-export([test/0]).


%% @doc Fetch the value for the key from a model source
-spec m_get( list(), zotonic_model:opt_msg(), z:context() ) -> zotonic_model:return().
m_get([], _Msg, Context) ->
    {ok, {menu(Context), []}};
m_get([ <<"menu">> | Rest ], _Msg, Context) ->
    {ok, {menu(Context), Rest}};
m_get(Vs, _Msg, _Context) ->
    lager:info("Unknown ~p lookup: ~p", [?MODULE, Vs]),
    {error, unknown_path}.

menu(Context) ->
    case z_acl:is_allowed(use, mod_admin, Context) of
        false ->
            [];
        true ->
            Menu = z_notifier:foldl(#admin_menu{}, [], Context),
            hierarchize(Menu, Context)
    end.


hierarchize(Items, Context) ->
    hierarchize(undefined, Items, Context).

hierarchize(Id, All, Context) ->
    {Matches, Rest} = partition(Id, All),
    Matches1 = sort_items(Matches),
    Matches2 = [ mixin(C, Rest, Context) || C <- Matches1 ],
    lists:filter(fun(I) -> item_visible(I, Context) end, Matches2).

sort_items(Ts) ->
    {_, Ts1} = lists:foldl(
        fun
            (#menu_item{ sort = S } = M, {N, Acc}) ->
                {N+1, [{S, N, M} | Acc]};
            (#menu_separator{ sort = S } = M, {N, Acc}) ->
                {N+1, [{S, N, M} | Acc]}
        end,
        {1, []},
        Ts),
    Ts2 = lists:sort( lists:reverse(Ts1) ),
    lists:map(fun({_, _, M}) -> M end, Ts2).

partition(Key, Items) ->
    lists:partition(
        fun
            (#menu_item{parent=K}) when K =:= Key ->
                true;
            (#menu_separator{parent=K}) when K =:= Key ->
                true;
            (_) ->
                false
        end,
        Items).

mixin(#menu_item{ id = Id, url = UrlDef } = Item, All, Context) ->
    Url = item_url(UrlDef, Context),
    Props = [
        {url, Url},
        {items, hierarchize(Id, All, Context)}
        | proplists:delete(url, lists:zip(record_info(fields, menu_item), tl(tuple_to_list(Item))))
    ],
    {Id, Props};
mixin(#menu_separator{ visiblecheck = C }, _All, _Context) ->
    {undefined, [ {separator, true}, {visiblecheck, C} ]}.

item_url(undefined, _Context) ->
    undefined;
item_url(Rule, Context) when is_atom(Rule) ->
    z_dispatcher:url_for(Rule, Context);
item_url({Rule}, Context) ->
    z_dispatcher:url_for(Rule, Context);
item_url({Rule, Args}, Context) ->
    z_dispatcher:url_for(Rule, Args, Context);
item_url(URL, _Context) when is_list(URL); is_binary(URL) ->
    URL.

item_visible({_Key, ItemProps}, Context) ->
    case proplists:get_value(visiblecheck, ItemProps) of
        undefined ->
            %% Always show separators
            proplists:get_value(separator, ItemProps) =:= true orelse

            %% Always show menu items with an external URL
            proplists:get_value(url, ItemProps) =/= undefined orelse

            %% Show a menu item only if it contains non-separator sub items
            lists:filter(
                fun({_SubItemKey, SubItemProps}) ->
                    proplists:get_value(separator, SubItemProps) =/= true
                end,
                proplists:get_value(items, ItemProps, [])
            ) =/= [];
        F when is_function(F, 0) ->
            F();
        F when is_function(F, 1) ->
            F(Context);
        {acl, Action, Object} ->
            z_acl:is_allowed(Action, Object, Context)
    end.



test() ->
    C = z:c(zotonic_site_status),

    %% simple test
    Items1 = [
              #menu_item{id=top1, label="Label", url="/"}
             ],

    [{top1, [{url, "/"},
             {items, []},
             {id, top1},
             {parent, undefined},
             {label, "Label"},
             {icon, undefined},
             {visiblecheck, undefined}]}] = hierarchize(Items1, C),

    %% simple test with empty children
    Items1a = [
              {top1, {undefined, "Label", "/"}},
              {top2, {undefined, "Label2", undefined}}
             ],
    [{top1, [{url, "/"},
             {label, "Label"},
             {items, []}]}] = hierarchize(Items1a, C),

    %% test w/ 1 child
    Items2 = [
              {top1, {undefined, "Label", "/"}},
              {sub1, {top1, "Label1", "/xx"}}
             ],
    [{top1, [{url, "/"},
             {label, "Label"},
             {items, [
                      {sub1, [{url, "/xx"}, {label, "Label1"}, {items, []}]}
                     ]}]}] = hierarchize(Items2, C),


    %% test w/ 1 child
    Items2a = [
              {top1, {undefined, "Label", "/"}},
              {sub1, {top1, "Label1", "/xx"}},
              {sub2, {top1, "Label2", "/yy"}}
             ],
    [{top1, [{url, "/"},
             {label, "Label"},
             {items, [
                      {sub1, [{url, "/xx"}, {label, "Label1"}, {items, []}]},
                      {sub2, [{url, "/yy"}, {label, "Label2"}, {items, []}]}
                     ]}]}] = hierarchize(Items2a, C),

    %% test w/ callback
    Items3 = [
              {top1, {undefined, "Label", "/"}},
              {sub1, {top1, "Label1", "/xx", fun() -> false end}}
             ],
    [{top1, [{url, "/"},
             {label, "Label"},
             {items, []}]}] = hierarchize(Items3, C),
    ok.

