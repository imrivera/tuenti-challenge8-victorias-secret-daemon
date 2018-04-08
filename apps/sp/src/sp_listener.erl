%%%-------------------------------------------------------------------
%%% @author imrivera
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 24. Mar 2018 16:15
%%%-------------------------------------------------------------------
-module(sp_listener).
-author("imrivera").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-define(KEYS_APPS, [calculator, email, browser, file, eject]).
-define(KEYS, [calculator, email, browser, file, eject,
               alt_f4, ctrl_c, alt_tab, ctrl_d, f1,
               backspace, arrow_up, arrow_down, arrow_left, arrow_right, print_screen, page_up, page_down,
               "\n0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ -"]).

-record(state, {listener_socket :: gen_tcp:socket(), counter = 0, id = 0}).
-record(tracking, {ip_address :: string(), port :: inet:port_number(), id, start_time, pid}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  Port = application:get_env(sp, listen_port, 3240),
  SendTimeout = application:get_env(sp, send_timeout, 5000),
  lager:info("Creating listening socket on port ~p", [Port]),
  {ok, ListenSocket} = gen_tcp:listen(0, [binary, {send_timeout, SendTimeout}, {send_timeout_close, true}, {active, once}, {backlog, 100}, {port, Port}, {ip, any}, {reuseaddr, true}, {nodelay, true}]),
  lager:info("Socket successfully created"),
  ets:new(keys_apps, [set, public, {read_concurrency, true}, named_table]),
  ets:new(keys, [set, public, {read_concurrency, true}, named_table]),
  fill_keys(keys_apps, ?KEYS_APPS),
  fill_keys(keys, ?KEYS),
  ets:new(client_monitors, [set, public, named_table]),
  self() ! listen,
  {ok, #state{listener_socket = ListenSocket}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info(listen, #state{listener_socket = ListenSocket, counter = Counter, id = Id} = State) ->
  case gen_tcp:accept(ListenSocket, 3000) of
    {ok, Socket} ->
      StartTime = erlang:monotonic_time(seconds),
      {ok, {IPAddress, Port}} = inet:peername(Socket),
      IPAddressString = inet:ntoa(IPAddress),

      {ok, WorkerPid} = sp_keyboard:start(Socket, Id, IPAddressString, Port),
      gen_tcp:controlling_process(Socket, WorkerPid),


      NewCounter = Counter + 1,
      lager:info("Client connected from ~s:~B  PID: ~p  ID: ~B  Concurrent clients: ~B", [IPAddressString, Port, WorkerPid, Id, NewCounter]),

      MRef = erlang:monitor(process, WorkerPid),
      ets:insert(client_monitors, {MRef, #tracking{ip_address = IPAddressString, port = Port, id = Id, pid = WorkerPid, start_time = StartTime}}),
      self() ! listen,
      {noreply, State#state{counter = NewCounter, id = Id + 1}};
    {error, timeout} ->
      self() ! listen,
      {noreply, State}
  end;
handle_info({'DOWN', MRef, process, _, Info}, #state{counter = Counter} = State) ->
  case catch ets:lookup(client_monitors, MRef) of
    [{_, #tracking{} = Tracking}] ->
      NewCounter = Counter - 1,
      ElapsedSeconds = erlang:monotonic_time(seconds) - Tracking#tracking.start_time,
      lager:info("Client disconnected from ~s:~B  Reason: \"~p\"  PID: ~p  ID: ~B  Connected time: ~B seconds  Concurrent clients: ~B", [
        Tracking#tracking.ip_address,
        Tracking#tracking.port,
        Info,
        Tracking#tracking.pid,
        Tracking#tracking.id,
        ElapsedSeconds,
        NewCounter
      ]),
      ets:delete(client_monitors, MRef),
      {noreply, State#state{counter = NewCounter}};
    _ ->
      {noreply, State}
  end;
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

fill_keys(Ets, Keys) ->
  Flatten = lists:flatten(Keys),
  lists:foldl(fun(Key, Index) -> true = ets:insert(Ets, {Index, Key}), Index + 1 end, 1, Flatten).