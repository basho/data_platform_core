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

-module(data_platform_service_sup).
-behaviour(supervisor).

% superviosr and supervisor_bridge callbacks.
-export([start_link/0, 
         init/1]).
% external api.
-export([start_service/3,
         stop_service/1, 
         restart_service/1, 
         services/0,
         app_definition/0]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    lager:info("Basho Data Platform Service Supervisor Starting"),
    {ok, {{one_for_one, 5, 10}, []}}.

start_service(Name, Exec, Options) ->
    MFA = {data_platform_service, start_link, [Exec, Options]},
    ChildSpec = {Name, MFA, permanent, 5000, worker, [exec]},
    supervisor:start_child(?MODULE, ChildSpec).

stop_service(Service) ->
    _ = supervisor:terminate_child(?MODULE, Service),
    _ = supervisor:delete_child(?MODULE, Service),
    ok.

restart_service(Service) ->
    _ = supervisor:terminate_child(?MODULE, Service),
    _ = supervisor:restart_child(?MODULE, Service),
    ok.

services() ->
    Children = supervisor:which_children(?MODULE),
    [{Id,Pid} || {Id, Pid, worker, _} <- Children,
                 is_pid(Pid)].

app_definition() ->
    % This is taken from the now defunct data_plaform_service module.
    % It was/is used in the data_platform_manager, after a call to a sanity
    % check function. It is hard-coded there, and here, and thus, magic.
    % It is unclear the intent. Thus:
    % TODO: document the point of this.
    [{ports, [internal_listen, external_listen]}].


