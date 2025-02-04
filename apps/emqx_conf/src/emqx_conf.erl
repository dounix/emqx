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
-module(emqx_conf).

-compile({no_auto_import, [get/1, get/2]}).
-include_lib("emqx/include/logger.hrl").
-include_lib("hocon/include/hoconsc.hrl").
-include_lib("emqx/include/emqx_schema.hrl").
-include("emqx_conf.hrl").

-export([add_handler/2, remove_handler/1]).
-export([get/1, get/2, get_raw/1, get_raw/2, get_all/1]).
-export([get_by_node/2, get_by_node/3]).
-export([update/3, update/4]).
-export([remove/2, remove/3]).
-export([tombstone/2]).
-export([reset/2, reset/3]).
-export([dump_schema/2, reformat_schema_dump/1]).
-export([schema_module/0]).

%% TODO: move to emqx_dashboard when we stop building api schema at build time
-export([
    hotconf_schema_json/0,
    bridge_schema_json/0,
    hocon_schema_to_spec/2
]).

%% for rpc
-export([get_node_and_config/1]).

%% API
%% @doc Adds a new config handler to emqx_config_handler.
-spec add_handler(emqx_config:config_key_path(), module()) -> ok.
add_handler(ConfKeyPath, HandlerName) ->
    emqx_config_handler:add_handler(ConfKeyPath, HandlerName).

%% @doc remove config handler from emqx_config_handler.
-spec remove_handler(emqx_config:config_key_path()) -> ok.
remove_handler(ConfKeyPath) ->
    emqx_config_handler:remove_handler(ConfKeyPath).

-spec get(emqx_utils_maps:config_key_path()) -> term().
get(KeyPath) ->
    emqx:get_config(KeyPath).

-spec get(emqx_utils_maps:config_key_path(), term()) -> term().
get(KeyPath, Default) ->
    emqx:get_config(KeyPath, Default).

-spec get_raw(emqx_utils_maps:config_key_path(), term()) -> term().
get_raw(KeyPath, Default) ->
    emqx_config:get_raw(KeyPath, Default).

-spec get_raw(emqx_utils_maps:config_key_path()) -> term().
get_raw(KeyPath) ->
    emqx_config:get_raw(KeyPath).

%% @doc Returns all values in the cluster.
-spec get_all(emqx_utils_maps:config_key_path()) -> #{node() => term()}.
get_all(KeyPath) ->
    {ResL, []} = emqx_conf_proto_v3:get_all(KeyPath),
    maps:from_list(ResL).

%% @doc Returns the specified node's KeyPath, or exception if not found
-spec get_by_node(node(), emqx_utils_maps:config_key_path()) -> term().
get_by_node(Node, KeyPath) when Node =:= node() ->
    emqx:get_config(KeyPath);
get_by_node(Node, KeyPath) ->
    emqx_conf_proto_v3:get_config(Node, KeyPath).

%% @doc Returns the specified node's KeyPath, or the default value if not found
-spec get_by_node(node(), emqx_utils_maps:config_key_path(), term()) -> term().
get_by_node(Node, KeyPath, Default) when Node =:= node() ->
    emqx:get_config(KeyPath, Default);
get_by_node(Node, KeyPath, Default) ->
    emqx_conf_proto_v3:get_config(Node, KeyPath, Default).

%% @doc Returns the specified node's KeyPath, or config_not_found if key path not found
-spec get_node_and_config(emqx_utils_maps:config_key_path()) -> term().
get_node_and_config(KeyPath) ->
    {node(), emqx:get_config(KeyPath, config_not_found)}.

%% @doc Update all value of key path in cluster-override.conf or local-override.conf.
-spec update(
    emqx_utils_maps:config_key_path(),
    emqx_config:update_request(),
    emqx_config:update_opts()
) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
update(KeyPath, UpdateReq, Opts) ->
    emqx_conf_proto_v3:update(KeyPath, UpdateReq, Opts).

%% @doc Update the specified node's key path in local-override.conf.
-spec update(
    node(),
    emqx_utils_maps:config_key_path(),
    emqx_config:update_request(),
    emqx_config:update_opts()
) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()} | emqx_rpc:badrpc().
update(Node, KeyPath, UpdateReq, Opts0) when Node =:= node() ->
    emqx:update_config(KeyPath, UpdateReq, Opts0#{override_to => local});
update(Node, KeyPath, UpdateReq, Opts) ->
    emqx_conf_proto_v3:update(Node, KeyPath, UpdateReq, Opts).

%% @doc Mark the specified key path as tombstone
tombstone(KeyPath, Opts) ->
    update(KeyPath, ?TOMBSTONE_CONFIG_CHANGE_REQ, Opts).

%% @doc remove all value of key path in cluster-override.conf or local-override.conf.
-spec remove(emqx_utils_maps:config_key_path(), emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
remove(KeyPath, Opts) ->
    emqx_conf_proto_v3:remove_config(KeyPath, Opts).

%% @doc remove the specified node's key path in local-override.conf.
-spec remove(node(), emqx_utils_maps:config_key_path(), emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
remove(Node, KeyPath, Opts) when Node =:= node() ->
    emqx:remove_config(KeyPath, Opts#{override_to => local});
remove(Node, KeyPath, Opts) ->
    emqx_conf_proto_v3:remove_config(Node, KeyPath, Opts).

%% @doc reset all value of key path in cluster-override.conf or local-override.conf.
-spec reset(emqx_utils_maps:config_key_path(), emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
reset(KeyPath, Opts) ->
    emqx_conf_proto_v3:reset(KeyPath, Opts).

%% @doc reset the specified node's key path in local-override.conf.
-spec reset(node(), emqx_utils_maps:config_key_path(), emqx_config:update_opts()) ->
    {ok, emqx_config:update_result()} | {error, emqx_config:update_error()}.
reset(Node, KeyPath, Opts) when Node =:= node() ->
    emqx:reset_config(KeyPath, Opts#{override_to => local});
reset(Node, KeyPath, Opts) ->
    emqx_conf_proto_v3:reset(Node, KeyPath, Opts).

%% @doc Called from build script.
%% TODO: move to a external escript after all refactoring is done
dump_schema(Dir, SchemaModule) ->
    %% TODO: Load all apps instead of only emqx_dashboard
    %% as this will help schemas that searches for apps with
    %% relevant schema definitions
    _ = application:load(emqx_dashboard),
    ok = emqx_dashboard_desc_cache:init(),
    lists:foreach(
        fun(Lang) ->
            ok = gen_config_md(Dir, SchemaModule, Lang),
            ok = gen_schema_json(Dir, SchemaModule, Lang)
        end,
        ["en", "zh"]
    ).

%% for scripts/spellcheck.
gen_schema_json(Dir, SchemaModule, Lang) ->
    SchemaJsonFile = filename:join([Dir, "schema-" ++ Lang ++ ".json"]),
    io:format(user, "===< Generating: ~s~n", [SchemaJsonFile]),
    %% EMQX_SCHEMA_FULL_DUMP is quite a hidden API
    %% it is used to dump the full schema for EMQX developers and supporters
    IncludeImportance =
        case os:getenv("EMQX_SCHEMA_FULL_DUMP") =:= "1" of
            true -> ?IMPORTANCE_HIDDEN;
            false -> ?IMPORTANCE_LOW
        end,
    io:format(user, "===< Including fields from importance level: ~p~n", [IncludeImportance]),
    Opts = #{
        include_importance_up_from => IncludeImportance,
        desc_resolver => make_desc_resolver(Lang)
    },
    StructsJsonArray = hocon_schema_json:gen(SchemaModule, Opts),
    IoData = emqx_utils_json:encode(StructsJsonArray, [pretty, force_utf8]),
    ok = file:write_file(SchemaJsonFile, IoData),
    ok = gen_preformat_md_json_files(Dir, StructsJsonArray, Lang).

gen_preformat_md_json_files(Dir, StructsJsonArray, Lang) ->
    NestedStruct = reformat_schema_dump(StructsJsonArray),
    %% write to files
    NestedJsonFile = filename:join([Dir, "schmea-v2-" ++ Lang ++ ".json"]),
    io:format(user, "===< Generating: ~s~n", [NestedJsonFile]),
    ok = file:write_file(
        NestedJsonFile, emqx_utils_json:encode(NestedStruct, [pretty, force_utf8])
    ),
    ok.

%% @doc This function is exported for scripts/schema-dump-reformat.escript
reformat_schema_dump(StructsJsonArray0) ->
    %% prepare
    StructsJsonArray = deduplicate_by_full_name(StructsJsonArray0),
    #{fields := RootFields} = hd(StructsJsonArray),
    RootNames0 = lists:map(fun(#{name := RootName}) -> RootName end, RootFields),
    RootNames = lists:map(fun to_bin/1, RootNames0),
    %% reformat
    [Root | FlatStructs0] = lists:map(
        fun(Struct) -> gen_flat_doc(RootNames, Struct) end, StructsJsonArray
    ),
    FlatStructs = [Root#{text => <<"root">>, hash => <<"root">>} | FlatStructs0],
    gen_nested_doc(FlatStructs).

deduplicate_by_full_name(Structs) ->
    deduplicate_by_full_name(Structs, #{}, []).

deduplicate_by_full_name([], _Seen, Acc) ->
    lists:reverse(Acc);
deduplicate_by_full_name([#{full_name := FullName} = H | T], Seen, Acc) ->
    case maps:get(FullName, Seen, false) of
        false ->
            deduplicate_by_full_name(T, Seen#{FullName => H}, [H | Acc]);
        H ->
            %% Name clash, but identical, ignore
            deduplicate_by_full_name(T, Seen, Acc);
        _Different ->
            %% ADD NAMESPACE!
            throw({duplicate_full_name, FullName})
    end.

%% Ggenerate nested docs from root struct.
%% Due to the fact that the same struct can be referenced by multiple fields,
%% we need to generate a unique nested doc for each reference.
%% The unique path to each type and is of the below format:
%% - A a path starts either with 'T-' or 'V-'. T stands for type, V stands for value.
%% - A path is a list of strings delimited by '-'.
%%   - The letter S is used to separate struct name from field name.
%%   - Field names are however NOT denoted by a leading 'F-'.
%% For example:
%% - T-root: the root struct;
%% - T-foo-S-footype: the struct named "footype" in the foo field of root struct;
%% - V-foo-S-footype-bar: the field named "bar" in the struct named "footype" in the foo field of root struct
gen_nested_doc(Structs) ->
    KeyByFullName = lists:foldl(
        fun(#{hash := FullName} = Struct, Acc) ->
            maps:put(FullName, Struct, Acc)
        end,
        #{},
        Structs
    ),
    FindFn = fun(Hash) -> maps:get(Hash, KeyByFullName) end,
    gen_nested_doc(hd(Structs), FindFn, []).

gen_nested_doc(#{fields := Fields} = Struct, FindFn, Path) ->
    TypeAnchor = make_type_anchor(Path),
    ValueAnchor = fun(FieldName) -> make_value_anchor(Path, FieldName) end,
    NewFields = lists:map(
        fun(#{text := Name} = Field) ->
            NewField = expand_field(Field, FindFn, Path),
            NewField#{hash => ValueAnchor(Name)}
        end,
        Fields
    ),
    Struct#{
        fields => NewFields,
        hash => TypeAnchor
    }.

%% Make anchor for type.
%% Start with "T-" to distinguish from value anchor.
make_type_anchor([]) ->
    <<"T-root">>;
make_type_anchor(Path) ->
    to_bin(["T-", lists:join("-", lists:reverse(Path))]).

%% Value anchor is used to link to the field's struct.
%% Start with "V-" to distinguish from type anchor.
make_value_anchor(Path, FieldName) ->
    to_bin(["V-", join_path_hash(Path, FieldName)]).

%% Make a globally unique "hash" (the http anchor) for each struct field.
join_path_hash([], Name) ->
    Name;
join_path_hash(Path, Name) ->
    to_bin(lists:join("-", lists:reverse([Name | Path]))).

%% Expand field's struct reference to nested doc.
expand_field(#{text := Name, refs := References} = Field, FindFn, Path) ->
    %% Add struct type name in path to make it unique.
    NewReferences = lists:map(
        fun(#{text := StructName} = Ref) ->
            expand_ref(Ref, FindFn, [StructName, "S", Name | Path])
        end,
        References
    ),
    Field#{refs => NewReferences};
expand_field(Field, _FindFn, _Path) ->
    %% No reference, no need to expand.
    Field.

expand_ref(#{hash := FullName}, FindFn, Path) ->
    Struct = FindFn(FullName),
    gen_nested_doc(Struct, FindFn, Path).

%% generate flat docs for each struct.
%% using references to link to other structs.
gen_flat_doc(RootNames, #{full_name := FullName, fields := Fields} = S) ->
    ShortName = short_name(FullName),
    case is_missing_namespace(ShortName, to_bin(FullName), RootNames) of
        true ->
            error({no_namespace, FullName, S});
        false ->
            ok
    end,
    #{
        text => short_name(FullName),
        hash => format_hash(FullName),
        doc => maps:get(desc, S, <<"">>),
        fields => format_fields(Fields)
    }.

format_fields([]) ->
    [];
format_fields([Field | Fields]) ->
    [format_field(Field) | format_fields(Fields)].

format_field(#{name := Name, aliases := Aliases, type := Type} = F) ->
    L = [
        {text, Name},
        {type, format_type(Type)},
        {refs, format_refs(Type)},
        {aliases,
            case Aliases of
                [] -> undefined;
                _ -> Aliases
            end},
        {default, maps:get(hocon, maps:get(default, F, #{}), undefined)},
        {doc, maps:get(desc, F, undefined)}
    ],
    maps:from_list([{K, V} || {K, V} <- L, V =/= undefined]).

format_refs(Type) ->
    References = find_refs(Type),
    case lists:map(fun format_ref/1, References) of
        [] -> undefined;
        L -> L
    end.

format_ref(FullName) ->
    #{text => short_name(FullName), hash => format_hash(FullName)}.

find_refs(Type) ->
    lists:reverse(find_refs(Type, [])).

%% go deep into union, array, and map to find references
find_refs(#{kind := union, members := Members}, Acc) ->
    lists:foldl(fun find_refs/2, Acc, Members);
find_refs(#{kind := array, elements := Elements}, Acc) ->
    find_refs(Elements, Acc);
find_refs(#{kind := map, values := Values}, Acc) ->
    find_refs(Values, Acc);
find_refs(#{kind := struct, name := FullName}, Acc) ->
    [FullName | Acc];
find_refs(_, Acc) ->
    Acc.

format_type(#{kind := primitive, name := Name}) ->
    format_primitive_type(Name);
format_type(#{kind := singleton, name := Name}) ->
    to_bin(["String(\"", to_bin(Name), "\")"]);
format_type(#{kind := enum, symbols := Symbols}) ->
    CommaSep = lists:join(",", lists:map(fun(S) -> to_bin(S) end, Symbols)),
    to_bin(["Enum(", CommaSep, ")"]);
format_type(#{kind := array, elements := ElementsType}) ->
    to_bin(["Array(", format_type(ElementsType), ")"]);
format_type(#{kind := union, members := MemberTypes} = U) ->
    DN = maps:get(display_name, U, undefined),
    case DN of
        undefined ->
            to_bin(["OneOf(", format_union_members(MemberTypes), ")"]);
        Name ->
            format_primitive_type(Name)
    end;
format_type(#{kind := struct, name := FullName}) ->
    to_bin(["Struct(", short_name(FullName), ")"]);
format_type(#{kind := map, name := Name, values := ValuesType}) ->
    to_bin(["Map($", Name, "->", format_type(ValuesType), ")"]).

format_union_members(Members) ->
    format_union_members(Members, []).

format_union_members([], Acc) ->
    lists:join(",", lists:reverse(Acc));
format_union_members([Member | Members], Acc) ->
    NewAcc = [format_type(Member) | Acc],
    format_union_members(Members, NewAcc).

format_primitive_type(TypeStr) ->
    Spec = emqx_conf_schema_types:readable_docgen(?MODULE, TypeStr),
    to_bin(maps:get(type, Spec)).

%% All types should have a namespace to avlid name clashing.
is_missing_namespace(ShortName, FullName, RootNames) ->
    case lists:member(ShortName, RootNames) of
        true ->
            false;
        false ->
            ShortName =:= FullName
    end.

%% Returns short name from full name, fullname delemited by colon(:).
short_name(FullName) ->
    case string:split(FullName, ":") of
        [_, Name] -> to_bin(Name);
        _ -> to_bin(FullName)
    end.

%% Returns the hash-anchor from full name, fullname delemited by colon(:).
format_hash(FullName) ->
    case string:split(FullName, ":") of
        [Namespace, Name] ->
            ok = warn_bad_namespace(Namespace),
            iolist_to_binary([Namespace, "__", Name]);
        _ ->
            iolist_to_binary(FullName)
    end.

%% namespace should only have letters, numbers, and underscores.
warn_bad_namespace(Namespace) ->
    case re:run(Namespace, "^[a-zA-Z0-9_]+$", [{capture, none}]) of
        nomatch ->
            case erlang:get({bad_namespace, Namespace}) of
                true ->
                    ok;
                _ ->
                    erlang:put({bad_namespace, Namespace}, true),
                    io:format(standard_error, "WARN: bad_namespace: ~s~n", [Namespace])
            end;
        _ ->
            ok
    end.

%% TODO: move this function to emqx_dashboard when we stop generating this JSON at build time.
hotconf_schema_json() ->
    SchemaInfo = #{title => <<"EMQX Hot Conf API Schema">>, version => <<"0.1.0">>},
    gen_api_schema_json_iodata(emqx_mgmt_api_configs, SchemaInfo).

%% TODO: move this function to emqx_dashboard when we stop generating this JSON at build time.
bridge_schema_json() ->
    Version = <<"0.1.0">>,
    SchemaInfo = #{title => <<"EMQX Data Bridge API Schema">>, version => Version},
    gen_api_schema_json_iodata(emqx_bridge_api, SchemaInfo).

%% TODO: remove it and also remove hocon_md.erl and friends.
%% markdown generation from schema is a failure and we are moving to an interactive
%% viewer like swagger UI.
gen_config_md(Dir, SchemaModule, Lang) ->
    SchemaMdFile = filename:join([Dir, "config-" ++ Lang ++ ".md"]),
    io:format(user, "===< Generating: ~s~n", [SchemaMdFile]),
    ok = gen_doc(SchemaMdFile, SchemaModule, Lang).

%% @doc return the root schema module.
-spec schema_module() -> module().
schema_module() ->
    case os:getenv("SCHEMA_MOD") of
        false ->
            resolve_schema_module();
        Value ->
            list_to_existing_atom(Value)
    end.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

-ifdef(TEST).
resolve_schema_module() ->
    case os:getenv("PROFILE") of
        "emqx" ->
            emqx_conf_schema;
        "emqx-enterprise" ->
            emqx_enterprise_schema;
        false ->
            error("PROFILE environment variable is not set")
    end.
-else.
-spec resolve_schema_module() -> no_return().
resolve_schema_module() ->
    error("SCHEMA_MOD environment variable is not set").
-endif.

%% @doc Make a resolver function that can be used to lookup the description by hocon_schema_json dump.
make_desc_resolver(Lang) ->
    fun
        ({desc, Namespace, Id}) ->
            emqx_dashboard_desc_cache:lookup(Lang, Namespace, Id, desc);
        (Desc) ->
            unicode:characters_to_binary(Desc)
    end.

-spec gen_doc(file:name_all(), module(), string()) -> ok.
gen_doc(File, SchemaModule, Lang) ->
    Version = emqx_release:version(),
    Title =
        "# " ++ emqx_release:description() ++ " Configuration\n\n" ++
            "<!--" ++ Version ++ "-->",
    BodyFile = filename:join([rel, "emqx_conf.template." ++ Lang ++ ".md"]),
    {ok, Body} = file:read_file(BodyFile),
    Resolver = make_desc_resolver(Lang),
    Opts = #{title => Title, body => Body, desc_resolver => Resolver},
    Doc = hocon_schema_md:gen(SchemaModule, Opts),
    file:write_file(File, Doc).

gen_api_schema_json_iodata(SchemaMod, SchemaInfo) ->
    emqx_dashboard_swagger:gen_api_schema_json_iodata(
        SchemaMod,
        SchemaInfo,
        fun ?MODULE:hocon_schema_to_spec/2
    ).

-define(TO_REF(_N_, _F_), iolist_to_binary([to_bin(_N_), ".", to_bin(_F_)])).
-define(TO_COMPONENTS_SCHEMA(_M_, _F_),
    iolist_to_binary([
        <<"#/components/schemas/">>,
        ?TO_REF(emqx_dashboard_swagger:namespace(_M_), _F_)
    ])
).

hocon_schema_to_spec(?R_REF(Module, StructName), _LocalModule) ->
    {#{<<"$ref">> => ?TO_COMPONENTS_SCHEMA(Module, StructName)}, [{Module, StructName}]};
hocon_schema_to_spec(?REF(StructName), LocalModule) ->
    {#{<<"$ref">> => ?TO_COMPONENTS_SCHEMA(LocalModule, StructName)}, [{LocalModule, StructName}]};
hocon_schema_to_spec(Type, LocalModule) when ?IS_TYPEREFL(Type) ->
    {typename_to_spec(typerefl:name(Type), LocalModule), []};
hocon_schema_to_spec(?ARRAY(Item), LocalModule) ->
    {Schema, Refs} = hocon_schema_to_spec(Item, LocalModule),
    {#{type => array, items => Schema}, Refs};
hocon_schema_to_spec(?ENUM(Items), _LocalModule) ->
    {#{type => enum, symbols => Items}, []};
hocon_schema_to_spec(?MAP(Name, Type), LocalModule) ->
    {Schema, SubRefs} = hocon_schema_to_spec(Type, LocalModule),
    {
        #{
            <<"type">> => object,
            <<"properties">> => #{<<"$", (to_bin(Name))/binary>> => Schema}
        },
        SubRefs
    };
hocon_schema_to_spec(?UNION(Types, _DisplayName), LocalModule) ->
    {OneOf, Refs} = lists:foldl(
        fun(Type, {Acc, RefsAcc}) ->
            {Schema, SubRefs} = hocon_schema_to_spec(Type, LocalModule),
            {[Schema | Acc], SubRefs ++ RefsAcc}
        end,
        {[], []},
        hoconsc:union_members(Types)
    ),
    {#{<<"oneOf">> => OneOf}, Refs};
hocon_schema_to_spec(Atom, _LocalModule) when is_atom(Atom) ->
    {#{type => enum, symbols => [Atom]}, []}.

typename_to_spec(TypeStr, Module) ->
    emqx_conf_schema_types:readable_dashboard(Module, TypeStr).

to_bin(List) when is_list(List) -> iolist_to_binary(List);
to_bin(Boolean) when is_boolean(Boolean) -> Boolean;
to_bin(Atom) when is_atom(Atom) -> atom_to_binary(Atom, utf8);
to_bin(X) -> X.
