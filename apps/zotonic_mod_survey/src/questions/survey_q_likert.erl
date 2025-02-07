%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2011 Marc Worrell

%% Copyright 2011 Marc Worrell
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

-module(survey_q_likert).

-export([
    answer/3,
    prep_chart/3,
    prep_answer_header/2,
    prep_answer/3,
    prep_block/2,
    to_block/1
]).

-include_lib("zotonic_core/include/zotonic.hrl").
-include_lib("zotonic_mod_survey/include/survey.hrl").

to_block(Q) ->
    #{
        <<"type">> => <<"survey_likert">>,
        <<"is_required">> => Q#survey_question.is_required,
        <<"name">> => z_convert:to_binary(Q#survey_question.name),
        <<"prompt">> => z_convert:to_binary(Q#survey_question.question)
    }.

answer(Block, Answers, _Context) ->
    Name = maps:get(<<"name">>, Block, undefined),
    case proplists:get_value(Name, Answers) of
        <<C>> when C >= $1, C =< $5 -> {ok, [{Name, C - $0}]};
        undefined -> {error, missing}
    end.

prep_chart(_Block, [], _Context) ->
    undefined;
prep_chart(Block, [{_, Vals}], Context) ->
    Labels = [
        5, 4, 3, 2, 1
    ],
    Agree = case z_trans:lookup_fallback(maps:get(<<"agree">>, Block, undefined), Context) of
        undefined -> ?__("Strongly Agree", Context);
        <<>> -> ?__("Strongly Agree", Context);
        Ag -> Ag
    end,
    DisAgree = case z_trans:lookup_fallback(maps:get(<<"disagree">>, Block, undefined), Context) of
        undefined -> ?__("Strongly Disagree", Context);
        <<>> -> ?__("Strongly Disagree", Context);
        DisAg -> DisAg
    end,
    LabelsDisplay = [
        iolist_to_binary([<<"5 ">>, z_trans:lookup_fallback(Agree, Context)]),
        <<"4">>,
        <<"3">>,
        <<"2">>,
        iolist_to_binary([<<"1 ">>, z_trans:lookup_fallback(DisAgree, Context)])
    ],
    LabelsPie = [
        <<"5">>,
        <<"4">>,
        <<"3">>,
        <<"2">>,
        <<"1">>
    ],
    Values = [ get_value(C, Vals, 0) || C <- Labels ],
    Sum = case lists:sum(Values) of 0 -> 1; N -> N end,
    Perc = [ round(V*100/Sum) || V <- Values ],
    #{
        <<"question">> => maps:get(<<"prompt">>, Block, undefined),
        <<"values">> => lists:zip(LabelsDisplay, Values),
        <<"type">> => <<"pie">>,
        <<"data">> => [{L,P} || {L,P} <- lists:zip(LabelsPie, Perc), P /= 0]
    }.

get_value(C, [ {B, _} | _ ] = L, Default) when is_binary(B) ->
    proplists:get_value(z_convert:to_binary(C), L, Default);
get_value(C, L, Default) ->
    proplists:get_value(C, L, Default).

prep_answer_header(Block, _Context) ->
    maps:get(<<"name">>, Block, undefined).

prep_answer(_Q, [], _Context) ->
    <<>>;
prep_answer(_Q, [{_Name, Value}|_], _Context) ->
    Value.

prep_block(B, _Context) ->
    B.


