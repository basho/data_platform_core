%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(data_platform_peer_service).
-behavior(plumtree_peer_behavior).

-export([get_peer_state/0, 
         register_changes/1,
         get_members/0,
         get_members/1]).


get_peer_state() ->
    riak_ensemble_manager:get_cluster_state().

register_changes(Callback) ->
    riak_ensemble_manager:subscribe(Callback).

get_members() ->
    ClusterState = riak_ensemble_manager:get_cluster_state(),
    case ordsets:from_list(riak_ensemble_state:members(ClusterState)) of
        [] ->
            [node()];
        Members ->
            Members
    end.

get_members(ClusterState) ->
    case ordsets:from_list(riak_ensemble_state:members(ClusterState)) of
        [] ->
            [node()];
        Members ->
            Members
    end.

