%%%----------------------------------------------------------------------
%%% Copyright (c) 2015 Hibari developers. All rights reserved.
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
%%% File    : brick_blob_store_hlog.hrl
%%% Purpose : specs for blob store using log hunk.
%%%----------------------------------------------------------------------

-ifndef(brick_blob_store_hlog_hrl).
-define(brick_blob_store_hlog_hrl, true).

-include("brick_specs.hrl").
-include("brick_hlog.hrl").
-include("gmt_hlog.hrl").      % for offset()

-record(l, {
          hunk_pos   :: offset(),
          val_offset :: offset(),
          val_len    :: len(),
          key        :: key(),
          timestamp  :: ts()
         }).
-type location_info() :: #l{}.

-type location_info_file() :: disk_log:log().
-type continuation() :: disk_log:continuation().

-endif. % -ifndef(brick_blob_store_hlog_hrl).