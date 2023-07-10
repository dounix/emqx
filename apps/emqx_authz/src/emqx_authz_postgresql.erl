%%--------------------------------------------------------------------
%% Copyright (c) 2020-2023 EMQ Technologies Co., Ltd. All Rights Reserved.
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
%%--------------------------------------------------------------------

-module(emqx_authz_postgresql).

-include("emqx_authz.hrl").
-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/logger.hrl").
-include_lib("emqx/include/emqx_placeholder.hrl").

-include_lib("epgsql/include/epgsql.hrl").

-behaviour(emqx_authz).

%% AuthZ Callbacks
-export([
    description/0,
    create/1,
    update/1,
    destroy/1,
    authorize/4
]).

-ifdef(TEST).
-compile(export_all).
-compile(nowarn_export_all).
-endif.

-define(PLACEHOLDERS, [
    ?PH_USERNAME,
    ?PH_CLIENTID,
    ?PH_PEERHOST,
    ?PH_CERT_CN_NAME,
    ?PH_CERT_SUBJECT
]).

description() ->
    "AuthZ with PostgreSQL".

create(#{query := SQL0} = Source) ->
    {SQL, PlaceHolders} = emqx_authz_utils:parse_sql(SQL0, '$n', ?PLACEHOLDERS),
    ResourceID = emqx_authz_utils:make_resource_id(emqx_connector_pgsql),
    {ok, _Data} = emqx_authz_utils:create_resource(
        ResourceID,
        emqx_connector_pgsql,
        Source#{prepare_statement => #{ResourceID => SQL}}
    ),
    Source#{annotations => #{id => ResourceID, placeholders => PlaceHolders}}.

update(#{query := SQL0, annotations := #{id := ResourceID}} = Source) ->
    {SQL, PlaceHolders} = emqx_authz_utils:parse_sql(SQL0, '$n', ?PLACEHOLDERS),
    case
        emqx_authz_utils:update_resource(
            emqx_connector_pgsql,
            Source#{prepare_statement => #{ResourceID => SQL}}
        )
    of
        {error, Reason} ->
            error({load_config_error, Reason});
        {ok, Id} ->
            Source#{annotations => #{id => Id, placeholders => PlaceHolders}}
    end.

destroy(#{annotations := #{id := Id}}) ->
    ok = emqx_resource:remove_local(Id).

authorize(
    Client,
    Action,
    Topic,
    #{
        annotations := #{
            id := ResourceID,
            placeholders := Placeholders
        }
    }
) ->
    Vars = emqx_authz_utils:vars_for_rule_query(Client, Action),
    RenderedParams = emqx_authz_utils:render_sql_params(Placeholders, Vars),
    case
        emqx_resource:simple_sync_query(ResourceID, {prepared_query, ResourceID, RenderedParams})
    of
        {ok, Columns, Rows} ->
            do_authorize(Client, Action, Topic, column_names(Columns), Rows);
        {error, Reason} ->
            ?SLOG(error, #{
                msg => "query_postgresql_error",
                reason => Reason,
                params => RenderedParams,
                resource_id => ResourceID
            }),
            nomatch
    end.

do_authorize(_Client, _Action, _Topic, _ColumnNames, []) ->
    nomatch;
do_authorize(Client, Action, Topic, ColumnNames, [Row | Tail]) ->
    try
        emqx_authz_rule:match(
            Client, Action, Topic, emqx_authz_utils:parse_rule_from_row(ColumnNames, Row)
        )
    of
        {matched, Permission} -> {matched, Permission};
        nomatch -> do_authorize(Client, Action, Topic, ColumnNames, Tail)
    catch
        error:Reason:Stack ->
            ?SLOG(error, #{
                msg => "match_rule_error",
                reason => Reason,
                rule => Row,
                stack => Stack
            }),
            do_authorize(Client, Action, Topic, ColumnNames, Tail)
    end.

column_names(Columns) ->
    lists:map(
        fun(#column{name = Name}) -> Name end,
        Columns
    ).
