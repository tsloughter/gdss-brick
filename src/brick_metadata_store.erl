%%%-------------------------------------------------------------------
%%% Copyright (c) 2014-2015 Hibari developers. All rights reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% File    : brick_metadata_store.erl
%%% Purpose :
%%%-------------------------------------------------------------------

-module(brick_metadata_store).

-behaviour(gen_server).

-include("brick_specs.hrl").
-include("brick_hlog.hrl").

%% Common API
-export([get_metadata_store/1]).

%% API for brick_data_sup Module
-export([start_link/2,
         stop/0
        ]).

%% API for Brick Server
-export([read_metadata/2,
         write_metadata/2,
         write_metadata_group_commit/2,
         request_group_commit/1
        ]).

%% API for Write-back Module
-export([writeback_to_stable_storage/3
        ]).

%% Temporary API
-export([get_leveldb/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
        ]).

%% DEBUG
-export([test1/0,
         test2/0
        ]).


%% ====================================================================
%% types and records
%% ====================================================================

%% @TODO: Use registered name rather than pid. pid will change when a process crashes.
-record(?MODULE, {
           impl_mod   :: module(),
           brick_name :: brickname(),
           pid        :: pid()}).

-type impl() :: #?MODULE{}.
-type brickname() :: atom().
-type wal_entry() :: term().

-type orddict(_A) :: term().  %% orddict in stdlib

-record(state, {
          impl_mod                :: module(),
          registory=orddict:new() :: orddict(impl())  %% Registory of metadata_store impl
         }).

-define(TIMEOUT, 60 * 1000).


%% ====================================================================
%% API
%% ====================================================================

%% @TODO Define brick_metadata_store behaviour.


-spec start_link(module(), [term()])
                -> {ok, impl()} | ignore | {error, term()}.
start_link(ImplMod, Options) ->
    gen_server:start_link({local, ?METADATA_STORE_REG_NAME},
                          ?MODULE, [ImplMod, Options], []).

%% @TODO: It will be better to stop each brick_metadata_store_leveldb when
%%        brick server is stopped.
-spec stop() -> ok.
stop() ->
    gen_server:cast(?METADATA_STORE_REG_NAME, stop).

-spec get_metadata_store(brickname()) -> {ok, impl()} | {error, term()}.
get_metadata_store(BrickName) ->
    gen_server:call(?METADATA_STORE_REG_NAME,
                    {get_or_start_metadata_store_impl, BrickName}, ?TIMEOUT).

-spec read_metadata(key(), impl()) -> brick_ets:store_tuple().
read_metadata(Key, #?MODULE{impl_mod=ImplMod}) ->
    ImplMod:read_metadata(Key).

-spec write_metadata([brick_ets:store_tuple()], impl())
                    -> ok | {hunk_too_big, len()} | {error, term()}.
write_metadata(MetadataList, #?MODULE{impl_mod=ImplMod, brick_name=BrickName, pid=Pid}) ->
    ImplMod:write_metadata(Pid, BrickName, MetadataList).

-spec write_metadata_group_commit([brick_ets:store_tuple()], impl())
                                 -> {ok, callback_ticket()}
                                        | {hunk_too_big, len()}
                                        | {error, term()}.
write_metadata_group_commit(MetadataList, #?MODULE{impl_mod=ImplMod, brick_name=BrickName, pid=Pid}) ->
    ImplMod:write_metadata_group_commit(Pid, BrickName, MetadataList).

-spec request_group_commit(impl()) -> callback_ticket().
request_group_commit(#?MODULE{impl_mod=ImplMod, pid=Pid}) ->
    ImplMod:request_group_commit(Pid).

%% Called by the WAL write-back process.
-spec writeback_to_stable_storage([wal_entry()], boolean(), impl()) -> ok | {error, term()}.
writeback_to_stable_storage(WalEntries, IsLastBatch,
                            #?MODULE{impl_mod=ImplMod, pid=Pid}) ->
    ImplMod:writeback_to_stable_storage(Pid, WalEntries, IsLastBatch).

%% Temporary API. Need higher abstruction.
-spec get_leveldb(impl()) -> {ok, h2leveldb:db()}.
get_leveldb(#?MODULE{impl_mod=ImplMod, pid=Pid}) ->
    ImplMod:get_leveldb(Pid).


%% ====================================================================
%% gen_server callbacks
%% ====================================================================

init([ImplMod, _Options]) ->
    process_flag(trap_exit, true),
    %% process_flag(priority, high),
    {ok, #state{impl_mod=ImplMod}}.

handle_call({get_or_start_metadata_store_impl, BrickName}, _From,
            #state{impl_mod=ImplMod, registory=Registory}=State) ->
    case orddict:find(BrickName, Registory) of
        {ok, _Impl}=Res ->
            {reply, Res, State};
        error ->
            Options = [],
            case ImplMod:start_link(BrickName, Options) of
                {ok, Pid} ->
                    Impl = #?MODULE{
                               impl_mod=ImplMod,
                               brick_name=BrickName,
                               pid=Pid
                              },
                    Registory1 = orddict:store(BrickName, Impl, Registory),
                    {reply, {ok, Impl}, State#state{registory=Registory1}};
                ignore ->
                    error({inconsistent_metadata_registory, ImplMod, BrickName});
                Err ->
                    {reply, Err, State}
            end
    end.

handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_, State) ->
    {noreply, State}.

%% @TODO: Handle exit from the gen_servers of metadata_store impl
handle_info(_, State) ->
    {noreply, State}.

terminate(_Reason, #state{impl_mod=ImplMod, registory=Registory}) ->
    orddict:fold(fun(_BrickName, #?MODULE{pid=Pid}, _Acc) ->
                         catch ImplMod:stop(Pid),
                         ok
                 end, undefined, Registory),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% ====================================================================
%% Internal functions
%% ====================================================================




%% DEBUG (@TODO: eunit / quickcheck cases)

test1() ->
    StoreTuple1 = {<<"key1">>, brick_server:make_timestamp(), <<"val1">>},
    StoreTuple2 = {<<"key12">>, brick_server:make_timestamp(), <<"val12">>},
    MetadataList = [StoreTuple1, StoreTuple2],
    {ok, MetadataStore} = get_metadata_store(table1_ch1_b1),
    MetadataStore:write_metadata(MetadataList).

test2() ->
    StoreTuple1 = {<<"key1">>, brick_server:make_timestamp(), <<"val1">>},
    StoreTuple2 = {<<"key12">>, brick_server:make_timestamp(), <<"val12">>},
    MetadataList = [StoreTuple1, StoreTuple2],
    {ok, MetadataStore} = get_metadata_store(table1_ch1_b1),
    MetadataStore:write_metadata_group_commit(MetadataList).
