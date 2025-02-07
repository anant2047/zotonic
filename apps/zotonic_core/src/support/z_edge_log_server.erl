%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2014 Marc Worrell
%% @doc Check for changed edges, trigger notifications.

%% Copyright 2014 Marc Worrell
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

-module(z_edge_log_server).
-author("Marc Worrell <marc@worrell.nl>").
-behaviour(gen_server).

%% gen_server exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([start_link/0, start_link/1]).

%% interface functions
-export([
    check/1,
    delete_if_unconnected/2
]).

-export([
    observe_check_edge_log/2
]).

-include_lib("zotonic.hrl").

% Check every 10 minutes if we have anything to handle.
% Check every 100msec when working through a backlog.
-define(CLEANUP_TIMEOUT_LONG, 600000).
-define(CLEANUP_TIMEOUT_SHORT, 100).
-define(CLEANUP_BATCH_SIZE, 100).

-record(state, {site :: atom()}).


%% @doc Force a check, useful after known edge operations.
check(Context) ->
    z_notifier:notify(check_edge_log, Context).

%% @doc Do an edge log check.
observe_check_edge_log(check_edge_log, Context) ->
    Name = z_utils:name_for_site(?MODULE, Context),
    gen_server:cast(Name, check).

%%====================================================================
%% API
%%====================================================================
%% @spec start_link() -> {ok,Pid} | ignore | {error,Error}
%% @doc Starts the server
start_link() ->
    start_link([]).
start_link(Args) when is_list(Args) ->
    {site, Site} = proplists:lookup(site, Args),
    Name = z_utils:name_for_site(?MODULE, Site),
    gen_server:start_link({local, Name}, ?MODULE, Args, []).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore               |
%%                     {stop, Reason}
%% @doc Initiates the server.
init(Args) ->
    {site, Site} = proplists:lookup(site, Args),
    lager:md([
        {site, Site},
        {module, ?MODULE}
      ]),

    z_notifier:observe(check_edge_log, {?MODULE, observe_check_edge_log}, Site),

    {ok, #state{site=Site}, ?CLEANUP_TIMEOUT_LONG}.

%% @spec handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% @doc Trap unknown calls
handle_call(Message, _From, State) ->
    {stop, {unknown_call, Message}, State}.

%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
handle_cast(check, State) ->
    case do_check(State#state.site) of
        {ok, 0} ->
            {noreply, State, ?CLEANUP_TIMEOUT_LONG};
        {ok, _} ->
            {noreply, State, ?CLEANUP_TIMEOUT_SHORT};
        {error, _} ->
            {noreply, State, ?CLEANUP_TIMEOUT_LONG}
    end;

%% @doc Trap unknown casts
handle_cast(Message, State) ->
    {stop, {unknown_cast, Message}, State}.



%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% @doc Handling all non call/cast messages
handle_info(timeout, State) ->
    handle_cast(check, State);
handle_info(_Info, State) ->
    {noreply, State}.

%% @spec terminate(Reason, State) -> void()
%% @doc This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
terminate(_Reason, _State) ->
    ok.

%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @doc Convert process state when code is changed
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%====================================================================
%% support functions
%%====================================================================

-spec do_check( atom() ) -> {ok, non_neg_integer()} | {error, econnrefused}.
do_check(Site) ->
    try
        Context = z_acl:sudo(z_context:new(Site)),
        do_check_1(z_db:q("
                        select id,op,subject_id,predicate,object_id,edge_id
                        from edge_log
                        order by id
                        limit $1",
                        [?CLEANUP_BATCH_SIZE],
                        Context),
                   Context)
    catch
        exit:{timeout, _} -> {ok, 0};
        throw:{error, econnrefused} = Error -> Error
    end.


do_check_1([], _Context) ->
    {ok, 0};
do_check_1(Rs, Context) ->
    RscIds = lists:usort(fetch_ids(Rs, [])),
    lists:foreach(fun(RscId) ->
                    z_depcache:flush(RscId, Context)
                  end,
                  RscIds),
    lists:foreach(fun({_Id,Op,SubjectId,Predicate,ObjectId,EdgeId}) ->
                    PredName = z_convert:to_atom(Predicate),
                    do_edge_notify(Op, SubjectId, PredName, ObjectId, EdgeId, Context)
                  end, Rs),
    Ranges = z_utils:ranges([ element(1,R) || R <- Rs ]),
    z_db:transaction(
            fun(Ctx) ->
                lists:foreach(fun
                                ({A,A}) ->
                                    z_db:q("delete from edge_log where id = $1", [A], Ctx);
                                ({A,B}) ->
                                    z_db:q("delete from edge_log where id >= $1 and id <= $2", [A,B], Ctx)
                              end,
                              Ranges)
             end,
             Context),
    {ok, length(Rs)}.

fetch_ids([], Acc) ->
    Acc;
fetch_ids([{_Id,_Op,SubjectId,_Pred,ObjectId,_EdgeId}|Rs], Acc) ->
    fetch_ids(Rs, [SubjectId,ObjectId|Acc]).

do_edge_notify(<<"DELETE">>, SubjectId, PredName, ObjectId, EdgeId, Context) ->
    Edge = #edge_delete{subject_id=SubjectId, predicate=PredName, object_id=ObjectId, edge_id=EdgeId},
    z_notifier:notify_sync(Edge, Context),
    z_mqtt:publish(
            [ <<"model">>, <<"edge">>, <<"event">>, SubjectId, <<"o">>, z_convert:to_binary(PredName) ],
            Edge,
            Context),
    z_mqtt:publish(
            [ <<"model">>, <<"edge">>, <<"event">>, ObjectId, <<"s">>, z_convert:to_binary(PredName) ],
            Edge,
            Context),
    maybe_delete_dependent(ObjectId, Context);
do_edge_notify(<<"UPDATE">>, SubjectId, PredName, ObjectId, EdgeId, Context) ->
    Edge = #edge_update{subject_id=SubjectId, predicate=PredName, object_id=ObjectId, edge_id=EdgeId},
    z_notifier:notify_sync(Edge, Context),
    z_mqtt:publish(
            [ <<"model">>, <<"edge">>, <<"event">>, SubjectId, <<"o">>, z_convert:to_binary(PredName) ],
            Edge,
            Context),
    z_mqtt:publish(
            [ <<"model">>, <<"edge">>, <<"event">>, ObjectId, <<"s">>, z_convert:to_binary(PredName) ],
            Edge,
            Context);
do_edge_notify(<<"INSERT">>, SubjectId, PredName, ObjectId, EdgeId, Context) ->
    Edge = #edge_insert{subject_id=SubjectId, predicate=PredName, object_id=ObjectId, edge_id=EdgeId},
    z_notifier:notify_sync(Edge, Context),
    z_mqtt:publish(
            [ <<"model">>, <<"edge">>, <<"event">>, SubjectId, <<"o">>, z_convert:to_binary(PredName) ],
            Edge,
            Context),
    z_mqtt:publish(
            [ <<"model">>, <<"edge">>, <<"event">>, ObjectId, <<"s">>, z_convert:to_binary(PredName) ],
            Edge,
            Context).

maybe_delete_dependent(Id, Context) ->
    case m_rsc:p_no_acl(Id, is_dependent, Context) of
        true ->
            Key = z_convert:to_binary(Id),
            z_pivot_rsc:insert_task_after(3600, ?MODULE, delete_if_unconnected, Key, [Id], Context);
        _False ->
            ok
    end.

delete_if_unconnected(Id, Context) ->
    case z_db:q_row("select r.is_dependent, r.is_protected, e.object_id
                     from rsc r
                          left join edge e on e.object_id = r.id
                     where r.is_dependent
                       and r.id = $1
                     limit 1",
                    [Id], Context)
    of
        {true, false, undefined} -> m_rsc:delete(Id, z_acl:sudo(Context));
        _ -> ok
    end.
