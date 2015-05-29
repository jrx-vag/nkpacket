%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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

-module(http_test).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-compile([export_all]).
-include_lib("eunit/include/eunit.hrl").
-include_lib("nklib/include/nklib.hrl").
-include_lib("kernel/include/file.hrl").
-include("nkpacket.hrl").

% http_test_() ->
%   	{setup, spawn, 
%     	fun() -> 
%     		ok = nkpacket_app:start(),
%     		?debugMsg("Starting HTTP test")
% 		end,
% 		fun(_) -> 
% 			ok
% 		end,
% 	    fun(_) ->
% 		    [
% 				fun() -> basic() end,
% 				fun() -> https() end
% 			]
% 		end
%   	}.


basic() ->
	Port = test_util:get_port(tcp),
	{Ref1, M1, Ref2, M2, Ref3, M3} = test_util:reset_3(),
 	Url1 = "<http://all:"++integer_to_list(Port)++"/test1>",
	WebProto1 = {dispatch, #{routes => [{'_', [{"/test1", test_cowboy_handler, [M1]}]}]}},
	{ok, Http1} = nkpacket:start_listener(dom1, Url1, M1#{web_proto=>WebProto1}),
 	Url2 = "<http://all:"++integer_to_list(Port)++"/test2>",
	WebProto2 = {dispatch, #{routes => [{'_', [{"/test2", test_cowboy_handler, [M2]}]}]}},
	{ok, Http2} = nkpacket:start_listener(dom2, Url2, M2#{web_proto=>WebProto2}),
	WebProto3 = {dispatch, #{routes => [{'_', [{"/test3", test_cowboy_handler, [M3]}]}]}},
 	Url3 = "<http://all:"++integer_to_list(Port)++">",
	{ok, Http3} = nkpacket:start_listener(dom3, Url3, M3#{
		host => "localhost",
		path => "/test3, /test3b/test3bb",
		web_proto => WebProto3
	}),
	timer:sleep(100),

	[
		#nkport{
			domain = dom1,transp = http,
			local_ip = {0,0,0,0}, local_port = Port,
			listen_ip = {0,0,0,0}, listen_port = Port,
			protocol = nkpacket_protocol_http, pid=Http1, socket = CowPid,
			meta = #{path_list := [<<"/test1">>]}
		}
	] = nkpacket:get_all(dom1),
	[
	 	#nkport{
 			domain = dom2,transp = http,
			local_ip = {0,0,0,0}, local_port = Port,
			listen_ip = {0,0,0,0}, listen_port = Port,
			pid = Http2, socket = CowPid,
			meta = #{path_list := [<<"/test2">>]}
		}
	] = nkpacket:get_all(dom2),
	[
		#nkport{
			domain = dom3,transp = http,
			local_ip = {0,0,0,0}, local_port = Port,
			listen_ip = {0,0,0,0}, listen_port = Port,
			pid = Http3, socket = CowPid,
			meta = #{
				host_list := [<<"localhost">>],
				path_list := [<<"/test3">>, <<"/test3b/test3bb">>]
			}
		}
	] = nkpacket:get_all(dom3),

	{ok, Gun} = gun:open("127.0.0.1", Port, #{transport=>tcp, retry=>0}),
	{ok, 404, H1} = get(Gun, "/", []),
	<<"NkPACKET">> = nklib_util:get_value(<<"server">>, H1),

	%% All connections share the same server process
	{ok, 200, _, <<"Hello World!">>} = get(Gun, "/test1", []),
	P = receive {Ref1, http_init, P1} -> P1 after 1000 -> error(?LINE) end,
	P = receive {Ref1, http_terminate, P2} -> P2 after 1000 -> error(?LINE) end,

	{ok, 200, _, <<"Hello World!">>} = get(Gun, "/test2", []),
	P = receive {Ref2, http_init, P3} -> P3 after 1000 -> error(?LINE) end,
	P = receive {Ref2, http_terminate, P4} -> P4 after 1000 -> error(?LINE) end,

	{ok, 404, H2} = get(Gun, "/test3", []),
	<<"NkPACKET">> = nklib_util:get_value(<<"server">>, H2),
	{ok, 200, _, _} = get(Gun, "/test3", [{<<"host">>, <<"localhost">>}]),
	P = receive {Ref3, http_init, P5} -> P5 after 1000 -> error(?LINE) end,
	P = receive {Ref3, http_terminate, P6} -> P6 after 1000 -> error(?LINE) end,

	%% This path is ok for NkPacket, but not for our current dispath
	{ok, 404, H3} = get(Gun, "/test3b/test3bb", [{<<"host">>, <<"localhost">>}]),
	<<"Cowboy">> = nklib_util:get_value(<<"server">>, H3),

	% If we close the transport, NkPacket blocks access, but only for the next
	% connection
	ok = nkpacket:stop_listener(Http3),
	timer:sleep(100),
	{ok, Gun2} = gun:open("127.0.0.1", Port, #{transport=>tcp, retry=>0}),
	{ok, 404, H4} = get(Gun2, "/test3b/test3bb", [{<<"host">>, <<"localhost">>}]),
	<<"NkPACKET">> = nklib_util:get_value(<<"server">>, H4),

	ok = nkpacket:stop_listener(Http1),
	ok = nkpacket:stop_listener(Http2),
	ok.


https() ->
	Port = test_util:get_port(tcp),
	{Ref1, M1} = test_util:reset_1(),
 	Url1 = "<https://all:"++integer_to_list(Port)++">",
	WebProto1 = {dispatch, #{routes => [{'_', [{"/test1", test_cowboy_handler, [M1]}]}]}},
	{ok, Http1} = nkpacket:start_listener(dom1, Url1, M1#{web_proto=>WebProto1}),
	{ok, Gun} = gun:open("127.0.0.1", Port, #{transport=>ssl, retry=>0}),
	{ok, 200, _, <<"Hello World!">>} = get(Gun, "/test1", []),
	P = receive {Ref1, http_init, P1} -> P1 after 1000 -> error(?LINE) end,
	P = receive {Ref1, http_terminate, P2} -> P2 after 1000 -> error(?LINE) end,
	{ok, 404, H1} = get(Gun, "/kk", []),
	<<"Cowboy">> = nklib_util:get_value(<<"server">>, H1),
	ok = nkpacket:stop_listener(Http1).


static() ->
	Port = 8021, %test_util:get_port(tcp),
	Path = filename:join(code:priv_dir(nkpacket), "www"),

 	Url1 = "http://all:"++integer_to_list(Port),
	WebProto1 = {static, #{path=>Path, index_file=>"index.html"}},
	{ok, S1} = nkpacket:start_listener(dom1, Url1, #{web_proto=>WebProto1}),

 	Url2 = "http://all:"++integer_to_list(Port)++"/1/2/",
	WebProto2 = {static, #{path=>Path}},
	{ok, S2} = nkpacket:start_listener(dom1, Url2, #{web_proto=>WebProto2}),

	{ok, Gun} = gun:open("127.0.0.1", Port, #{transport=>tcp, retry=>0}),
	{ok, 200, H1, <<"index_root">>} = get(Gun, "/", []),
	[
		{<<"connection">>, <<"keep-alive">>},
		{<<"content-length">>, <<"10">>},
		{<<"content-type">>, <<"text/html">>},
		{<<"date">>, _},
		{<<"etag">>, Etag},
		{<<"last-modified">>, Date},
		{<<"server">>, <<"NkPACKET">>}
	] = lists:sort(H1),
	File1 = filename:join(Path, "index.html"),
	{ok, #file_info{mtime=Mtime}} = file:read_file_info(File1, [{time, universal}]),
	Etag = <<$", (integer_to_binary(erlang:phash2({10, Mtime}, 16#ffffffff)))/binary, $">>,
	Date = cowboy_clock:rfc1123(Mtime),

	{ok, 400, _} = get(Gun, "../..", []),
	{ok, 403, _} = get(Gun, "/1/2/", []),
	{ok, 200, _, <<"index_root">>} = get(Gun, "/1/2/index.html", []),
	{ok, 404, _} = get(Gun, "/1/2/index.htm", []),
	{ok, 200, _, <<"index_dir1">>} = get(Gun, "/dir1", []),
	{ok, 403, _} = get(Gun, "/1/2/dir1", []),
	{ok, 200, H2, <<"file1.txt">>} = get(Gun, "/dir1/file1.txt", []),
	[
		{<<"connection">>, <<"keep-alive">>},
		{<<"content-length">>, <<"9">>},
		{<<"content-type">>, <<"text/plain">>},
		{<<"date">>, _},
		{<<"etag">>, _},
		{<<"last-modified">>, _},
		{<<"server">>,<<"NkPACKET">>}
	] = lists:sort(H2),
	{ok, 200, H2, <<"file1.txt">>} = get(Gun, "/1/2/dir1/file1.txt", []),

	ok = nkpacket:stop_listener(S1),
	timer:sleep(1000),
	get(Gun, "/dir1", []).













%%%%%%%% Util

get(Pid, Path, Hds) ->
	Ref = gun:get(Pid, Path, Hds),
	receive
		{gun_response, _, Ref, fin, Code, RHds} -> 
			{ok, Code, RHds};
		{gun_response, _, Ref, nofin, Code, RHds} -> 
			receive 
				{gun_data, _, Ref, fin, Data} -> 
					{ok, Code, RHds, Data}
			after 1000 ->
				timeout
			end;
		{gun_error, _, Ref, Error} ->
			{error, Error}
	after 1000 ->
		{error, timeout}
	end.



