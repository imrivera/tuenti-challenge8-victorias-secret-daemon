%%%-------------------------------------------------------------------
%%% @author imrivera
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 24. Mar 2018 16:47
%%%-------------------------------------------------------------------
-module(sp_keyboard).
-author("imrivera").

-behaviour(gen_server).

%% API
-export([start/1]).
-export([debug/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).


-define(KEYS, [
  16#08,
  16#06,
  16#0B,
  16#12,
  16#2C,
  16#0F,
  16#08,
  16#17,
  16#16,
  16#2C,
  16#13,
  16#0F,
  16#04,
  16#1C,
  16#2C,
  16#04,
  16#2C,
  16#0A,
  16#04,
  16#10,
  16#08,
  16#28,
  16#00
]).


-define(SERVER, ?MODULE).

-define(USBIP_VERSION, 16#0111).
-define(USBIP_OP_CMD_SUBMIT, 16#0001).
-define(USBIP_OP_RET_SUBMIT, 16#0003).
-define(USBIP_OP_CMD_UNLINK, 16#0002).
-define(USBIP_OP_RET_UNLINK, 16#0004).
-define(USBIP_OP_REQ_IMPORT, 16#8003).
-define(USBIP_OP_REP_IMPORT, 16#0003).
-define(USBIP_OP_REQ_DEVLIST, 16#8005).
-define(USBIP_OP_REP_DEVLIST, 16#0005).

%-define(DEVICE_SYSTEM_PATH, <<"/el/quinto/pinto">>).
%-define(DEVICE_BUSID, <<"8-20">>).
-define(DEVICE_SYSTEM_PATH, <<"/sys/devices/pci0000:00/0000:00:14.0/usb1/1-14">>).
-define(DEVICE_BUSID, <<"1-14">>).
-define(DEVICE_BUS_NUMBER, 1).
-define(DEVICE_NUMBER, 9).
-define(DEVICE_CONNECTED_SPEED, 1). % 1 = Low speed
-define(DEVICE_ID_VENDOR, 16#413C).
-define(DEVICE_ID_PRODUCT, 16#2003).
-define(DEVICE_BCD_DEVICE, 16#0306).
-define(DEVICE_BDEVICE_CLASS, 16#00).
-define(DEVICE_BDEVICE_SUB_CLASS, 16#00).
-define(DEVICE_BDEVICE_PROTOCOL, 16#00).
-define(DEVICE_BCONFIGURATION_VALUE, 16#00).
-define(DEVICE_BNUM_CONFIGURATIONS, 16#01).
-define(DEVICE_BNUM_INTERFACES, 16#00).



-define(HID_REPORT, <<16#05, 16#01, 16#09, 16#06, 16#a1, 16#01, 16#05, 16#07, 16#19, 16#e0, 16#29, 16#e7, 16#15, 16#00, 16#25, 16#01,
  16#75, 16#01, 16#95, 16#08, 16#81, 16#02, 16#95, 16#01, 16#75, 16#08, 16#81, 16#01, 16#95, 16#03, 16#75, 16#01,
  16#05, 16#08, 16#19, 16#01, 16#29, 16#03, 16#91, 16#02, 16#95, 16#01, 16#75, 16#05, 16#91, 16#01, 16#95, 16#06,
  16#75, 16#08, 16#15, 16#00, 16#26, 16#ff, 16#00, 16#05, 16#07, 16#19, 16#00, 16#2a, 16#ff, 16#00, 16#81, 16#00,
  16#c0>>).

-define(URB_VENDOR, <<"Dell"/utf16-little>>).
-define(URB_DESC, <<"Dell USB Keyboard"/utf16-little>>).

-record(state, {socket :: gen_tcp:socket(),
                pending_data = <<>> :: binary(),
                step :: undefined | imported,
                sequence = undefined :: non_neg_integer() | undefined,
                keys = ?KEYS :: list(),
                first_submit = true,
                timer_for_set = undefined :: reference() | undefined}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(gen_tcp:socket()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start(Socket) ->
  gen_server:start(?MODULE, [Socket], []).

debug() ->
  dbg:tracer(),
  dbg:tpl(?MODULE, x),
  dbg:tpl(gen_tcp, send, x),
  dbg:p(all, [c]).

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
init([Socket]) ->
  {ok, #state{socket = Socket, pending_data = <<>>, step = undefined}}.

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
handle_info({tcp, Socket, Data}, #state{pending_data = PendingData} = State) ->
  FullBuffer = <<PendingData/binary, Data/binary>>,
  StateWithFullBuffer = State#state{pending_data = FullBuffer},
  case handle_command(FullBuffer, Socket, StateWithFullBuffer) of
    {need_more_data, NewState} ->
      inet:setopts(Socket, [{active, once}]),
      {noreply, NewState};
    close ->
      gen_tcp:close(Socket),
      {stop, normal, StateWithFullBuffer};
    {error, Reason} ->
      {stop, Reason, StateWithFullBuffer}
  end;
handle_info(next_key_timeout, State) ->
  self() ! next_key,
  {noreply, State#state{timer_for_set = undefined}};
handle_info(next_key, #state{sequence = SequenceNumber, socket = Socket, keys = Keys} = State) ->

  KeysToUse = case Keys of
                [] ->
                  [];
                  % ?KEYS;
                _ ->
                  Keys
              end,

  case KeysToUse of
    [] ->
      {noreply, State#state{keys = KeysToUse, sequence = undefined}};
    _ ->
      FirstKey = hd(KeysToUse),
      Data = <<0, 0, FirstKey, 0, 0, 0, 0, 0>>,
      RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
        <<SequenceNumber:32/big>>,
        <<0:16/big, 0:16/big>>,   % Devid
        <<0:32/big>>,    % Direction
        <<0:32/big>>,    % Endpoint
        <<0:32/big>>,    % Status success
        <<8:32/big>>,
        <<16#FFFFFFFF:32/unsigned-big>>,    % ISO start frame
        <<0:32/big>>,    % Number of ISO descriptors
        <<0:32/big>>,    % ISO error count
        <<0:64/big>>     % Setup data
      ],
      gen_tcp:send(Socket, [RespPrefix, Data]),
      {noreply, State#state{keys = tl(KeysToUse), sequence = undefined}}
  end;

handle_info({tcp_closed, _}, State) ->
  % Connection closed
  {stop, normal, State};
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

handle_command(<<?USBIP_VERSION:16/big, ?USBIP_OP_REQ_DEVLIST:16/big, _Status:32/big, _RestBinary/binary>>, Socket, #state{step = undefined}) ->
  io:format("USBIP_OP_REQ_DEVLIST~n"),
  Resp = [
    <<?USBIP_VERSION:16/big,
      ?USBIP_OP_REP_DEVLIST:16/big,
      0:32/big,          % Success
      1:32/big>>,        % Number of exported devices
    bin_zero_pad(?DEVICE_SYSTEM_PATH, 256),  % System path
    bin_zero_pad(?DEVICE_BUSID, 32),         % Bus Id
    <<?DEVICE_BUS_NUMBER:32/big>>,
    <<?DEVICE_NUMBER:32/big>>,
    <<?DEVICE_CONNECTED_SPEED:32/big>>,
    <<?DEVICE_ID_VENDOR:16/big>>,
    <<?DEVICE_ID_PRODUCT:16/big>>,
    <<?DEVICE_BCD_DEVICE:16/big>>,
    ?DEVICE_BDEVICE_CLASS,
    ?DEVICE_BDEVICE_SUB_CLASS,
    ?DEVICE_BDEVICE_PROTOCOL,
    ?DEVICE_BCONFIGURATION_VALUE,
    ?DEVICE_BNUM_CONFIGURATIONS,
    ?DEVICE_BNUM_INTERFACES],
  gen_tcp:send(Socket, Resp),
  close;
handle_command(<<?USBIP_VERSION:16/big, ?USBIP_OP_REQ_IMPORT:16/big, _Status:32/big, BusId:32/binary, RestBinary/binary>>, Socket, #state{step = undefined} = State) ->
  PaddedBusId = iolist_to_binary(bin_zero_pad(?DEVICE_BUSID, 32)),
  io:format("MyBus = #~s#~n", [PaddedBusId]),
  io:format("OtBus = #~s#~n", [BusId]),
  case PaddedBusId == BusId of
    false ->
      RespError = [
        <<?USBIP_VERSION:16/big>>,
        <<?USBIP_OP_REP_IMPORT:16/big>>,
        <<1:32/big>>],  % 1 = Error Status
      gen_tcp:send(Socket, RespError),
      close;
    true ->
      RespOk = [
        <<?USBIP_VERSION:16/big>>,
        <<?USBIP_OP_REP_IMPORT:16/big>>,
        <<0:32/big>>,   % 0 = Status ok,
        bin_zero_pad(?DEVICE_SYSTEM_PATH, 256),
        PaddedBusId,
        <<?DEVICE_BUS_NUMBER:32/big>>,
        <<?DEVICE_NUMBER:32/big>>,
        <<?DEVICE_CONNECTED_SPEED:32/big>>,
        <<?DEVICE_ID_VENDOR:16/big>>,
        <<?DEVICE_ID_PRODUCT:16/big>>,
        <<?DEVICE_BCD_DEVICE:16/big>>,
        ?DEVICE_BDEVICE_CLASS,
        ?DEVICE_BDEVICE_SUB_CLASS,
        ?DEVICE_BDEVICE_PROTOCOL,
        ?DEVICE_BCONFIGURATION_VALUE,
        ?DEVICE_BNUM_CONFIGURATIONS,
        ?DEVICE_BNUM_INTERFACES],
      gen_tcp:send(Socket, RespOk),
      handle_command(RestBinary, Socket, State#state{step = imported, pending_data = RestBinary})
  end;
handle_command(<<?USBIP_OP_CMD_SUBMIT:32/big, RestBinary/binary>>, Socket, #state{step = imported} = State) ->
  handle_cmd_submit(RestBinary, Socket, State);
handle_command(<<?USBIP_OP_CMD_UNLINK:32/big, SequenceNumber:32/big, ?DEVICE_BUS_NUMBER:16/big, ?DEVICE_NUMBER:16/big,
    _Direction:32/big,
    _Endpoint:32/big,
    UnlinkSequenceNumber:32/big,
    _:24/binary, % ???
    RestBinary/binary>>, Socket, #state{step = imported} = State) ->

  io:format ("## UNLINK ~p~n", [UnlinkSequenceNumber]),
  Resp = [<<?USBIP_OP_RET_UNLINK:32/big>>,
    <<SequenceNumber:32/big>>,
    <<0:16/big, 0:16/big>>,   % Devid
    <<0:32/big>>,    % Direction
    <<0:32/big>>,    % Endpoint
    <<0:32/big>>,    % Status success
    <<0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0>>],

  gen_tcp:send(Socket, Resp),
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary});

handle_command(Binary, _Socket, State) when size(Binary) =< 5120 ->
  %io:format("## UNRECOGNIZED COMMAND ~p~n",[Binary]),
  {need_more_data, State};
handle_command(_, _, _) ->
  {error, invalid_data}.

handle_cmd_submit(<<SequenceNumber:32/big, ?DEVICE_BUS_NUMBER:16/big, ?DEVICE_NUMBER:16/big,
  Direction:32/big,  % Direction
  0:32/big,  % Endpoint
  _:32/big, % Transfer flags
  _TransferBufferLength:32/big,
  0:32/big, % ISO start frame
  0:32/big, % Number of ISO descriptors
  0:32/big, % Interval
  RestBinary/binary>>, Socket, State) ->

  Op = case Direction band 1 of
          1 -> get;
          0 -> set
  end,

  handle_urb(Op, RestBinary, SequenceNumber, Socket, State);

handle_cmd_submit(<<SequenceNumber:32/big, ?DEVICE_BUS_NUMBER:16/big, ?DEVICE_NUMBER:16/big,
  1:32/big,  % Direction
  1:32/big,  % Endpoint
  _:32/big, % Transfer flags
  _TransferBufferLength:32/big,
  _:32/big, % ISO start frame
  _:32/big, % Number of ISO descriptors
  _:32/big, % Interval
  _:64/big,
  RestBinary/binary>>, Socket, #state{first_submit = IsFirstSubmit} = State) ->

  TimeRef = case IsFirstSubmit of
              true ->
                erlang:send_after(1000, self(), next_key_timeout);
              false ->
                self() ! next_key,
                undefined
            end,
  io:format("## URB SUBMIT ~p~n", [SequenceNumber]),

  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary, sequence = SequenceNumber, timer_for_set = TimeRef, first_submit = false});
handle_cmd_submit(_Binary, _, State) ->
  {ok, State}.


handle_urb(get, <<16#8006:16/big,   % GET DESCRIPTOR
             0,    % Descriptor Index
             1,    % Descriptor Type  (DEVICE)
             _Language:16/little,
             RequestedLength:16/little,
             RestBinary/binary>>,
             SequenceNumber,
             Socket,
             State) ->
  DeviceDescriptorIoList = [
    1,  % DescriptorType = DEVICE
    <<16#0110:16/little>>, % bcdUSB
    ?DEVICE_BDEVICE_CLASS,
    ?DEVICE_BDEVICE_SUB_CLASS,
    ?DEVICE_BDEVICE_PROTOCOL,
    8,   % MaxPacketSize
    <<?DEVICE_ID_VENDOR:16/little>>,
    <<?DEVICE_ID_PRODUCT:16/little>>,
    <<?DEVICE_BCD_DEVICE:16/little>>,  % bcdDevice
    1,  % iManufacturer
    2,  % iProduct
    0,  % iSerialNumber
    1   % bNumConfigurations
  ],

  DeviceDescriptorSize = iolist_size(DeviceDescriptorIoList) + 1,

  RespLength = lists:min([DeviceDescriptorSize, RequestedLength]),


  RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
          <<SequenceNumber:32/big>>,
          <<0:16/big, 0:16/big>>,   % Devid
          <<0:32/big>>,    % Direction
          <<0:32/big>>,    % Endpoint
          <<0:32/big>>,    % Status success
          <<RespLength:32/big>>,
          <<0:32/big>>,    % ISO start frame
          <<0:32/big>>,    % Number of ISO descriptors
          <<0:32/big>>,    % ISO error count
          <<0:64/big>>     % Setup data
  ],

  FullRespBinary = iolist_to_binary([
          DeviceDescriptorSize,
          DeviceDescriptorIoList]),

  <<RespBinary:RespLength/binary, _/binary>> = FullRespBinary,

  gen_tcp:send(Socket, [RespPrefix, RespBinary]),
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary});

handle_urb(get, <<16#8006:16/big,   % GET DESCRIPTOR
  0,    % Descriptor Index
  2,    % Descriptor Type  (CONFIGURATION)
  _Language:16/little,
  RequestedLength:16/little,
  RestBinary/binary>>,
    SequenceNumber,
    Socket,
    State) ->

  InterfaceDescriptorIoList = [
    4,  % bDescriptorType (INTERFACE)
    0,  % bInterfaceNumber
    0,  % bAlternateSetting
    1,  % bNumEndpoints,
    3,  % bInterfaceClass (HID)
    1,  % bInterfaceSubclass (Boot Interface)
    1,  % bInterfaceProtocol: Keyboard,
    0   % iInterface
  ],

  InterfaceDescriptorSize = iolist_size(InterfaceDescriptorIoList) + 1,

  HidReportSize = size(?HID_REPORT),

  HidDescriptorIoList = [
    16#21,  % bDescriptorType (HID)
    <<16#110:16/little>>,  %bcdHID
    0,  %bCountryCode
    1,  % bNumDescriptors
    16#22, % bDescriptorType
    <<HidReportSize:16/little>> % wDescriptorLength
  ],

  HidDescriptorSize = iolist_size(HidDescriptorIoList) + 1,

  EndpointDescriptorIoList = [
    16#05,  % bDescriptorType (ENDPOINT)
    16#81,  % IN Endpoint:1
    16#03,  % bmAttributes
    <<8:16/little>>,      % wMaxPacketSize
    24  % bInterval
  ],

  EndpointDescriptorSize = iolist_size(EndpointDescriptorIoList) + 1,

  AllSize = 9 + InterfaceDescriptorSize + HidDescriptorSize + EndpointDescriptorSize,

  DeviceDescriptorIoList = [
    2,  % DescriptorType = CONFIGURATION
    <<AllSize:16/little>>,  % wTotalLength
    1, % bNumInterfaces
    1, % bConfigurationValue
    0, % iConfiguration
    16#A0, % bmAttributes
    35],  % bMaxPower

  RespLength = lists:min([RequestedLength, AllSize]),

  RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
    <<SequenceNumber:32/big>>,
    <<0:16/big, 0:16/big>>,   % Devid
    <<0:32/big>>,    % Direction
    <<0:32/big>>,    % Endpoint
    <<0:32/big>>,    % Status success
    <<RespLength:32/big>>,
    <<0:32/big>>,    % ISO start frame
    <<0:32/big>>,    % Number of ISO descriptors
    <<0:32/big>>,    % ISO error count
    <<0:64/big>>    % Setup data
  ],

  RespDescriptors = [
    9,
    DeviceDescriptorIoList,
    InterfaceDescriptorSize,
    InterfaceDescriptorIoList,
    HidDescriptorSize,
    HidDescriptorIoList,
    EndpointDescriptorSize,
    EndpointDescriptorIoList
  ],

  <<RespDescriptorsBinary:RespLength/binary, _/binary>> = iolist_to_binary(RespDescriptors),

  gen_tcp:send(Socket, [RespPrefix, RespDescriptorsBinary]),
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary});

handle_urb(get, <<16#8006:16/big,   % GET DESCRIPTOR
  DescriptorIndex,    % Descriptor Index
  3,    % Descriptor Type  (STRING)
  _Language:16/little,
  RequestedLength:16/little,
  RestBinary/binary>>,
    SequenceNumber,
    Socket,
    State) ->

  String = case DescriptorIndex of
              0 ->
                [3, <<16#0409:16/little>>];  % English
              1 ->
                [3, ?URB_VENDOR];
              2 ->
                [3, ?URB_DESC];
              _ ->
                undefined
          end,

  case String of
    undefined ->
      EmptyResp = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
        <<SequenceNumber:32/big>>,
        <<0:16/big, 0:16/big>>,   % Devid
        <<0:32/big>>,    % Direction
        <<0:32/big>>,    % Endpoint
        <<0:32/big>>,    % Status success
        <<0:32/big>>,
        <<0:32/big>>,    % ISO start frame
        <<0:32/big>>,    % Number of ISO descriptors
        <<0:32/big>>,    % ISO error count
        <<0:64/big>>    % Setup data
      ],

      gen_tcp:send(Socket, EmptyResp),
      {ok, State#state{pending_data = RestBinary}};
    _ ->
      DescriptorSize = iolist_size(String) + 1,
      RespLength = lists:min([DescriptorSize, RequestedLength]),

      <<Resp:RespLength/binary, _/binary>> = iolist_to_binary([DescriptorSize, String]),

      RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
        <<SequenceNumber:32/big>>,
        <<0:16/big, 0:16/big>>,   % Devid
        <<0:32/big>>,    % Direction
        <<0:32/big>>,    % Endpoint
        <<0:32/big>>,    % Status success
        <<RespLength:32/big>>,
        <<0:32/big>>,    % ISO start frame
        <<0:32/big>>,    % Number of ISO descriptors
        <<0:32/big>>,    % ISO error count
        <<0:64/big>>    % Setup data
      ],

      gen_tcp:send(Socket, [RespPrefix, Resp]),
      handle_command(RestBinary, Socket, State#state{pending_data = RestBinary})
  end;

handle_urb(get, <<16#8106:16/big,   % GET DESCRIPTOR
  0,    % Descriptor Index
  16#22,    % Descriptor Type  (HID Report)
  0:16/little,  % wInterfaceNumber
  MaxLength:16/little,
  RestBinary/binary>>,
    SequenceNumber,
    Socket,
    State) ->


  HidReportSize = size(?HID_REPORT),
  RespLength = lists:min([HidReportSize, MaxLength]),

  RespPrefix = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
    <<SequenceNumber:32/big>>,
    <<0:16/big, 0:16/big>>,   % Devid
    <<0:32/big>>,    % Direction
    <<0:32/big>>,    % Endpoint
    <<0:32/big>>,    % Status success
    <<RespLength:32/big>>,
    <<0:32/big>>,    % ISO start frame
    <<0:32/big>>,    % Number of ISO descriptors
    <<0:32/big>>,    % ISO error count
    <<0:64/big>>    % Setup data
  ],

  <<Resp:RespLength/binary, _/binary>> = iolist_to_binary([?HID_REPORT]),

  gen_tcp:send(Socket, [RespPrefix, Resp]),
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary});


handle_urb(set, <<_,    % Host to device
             _,    % bRequest
             _WValue:16/little,
             _WIndex:16/little,
             WLength:16/little, _Payload:WLength/binary, RestBinary/binary>>,
            SequenceNumber, Socket, #state{timer_for_set = TimerRef} = State) ->

  io:format("##SET CONFIGURATION~n"),
  EmptyResp = [<<?USBIP_OP_RET_SUBMIT:32/big>>,
    <<SequenceNumber:32/big>>,
    <<0:16/big, 0:16/big>>,   % Devid
    <<0:32/big>>,    % Direction
    <<0:32/big>>,    % Endpoint
    <<0:32/big>>,    % Status success
    <<WLength:32/big>>,
    <<0:32/big>>,    % ISO start frame
    <<0:32/big>>,    % Number of ISO descriptors
    <<0:32/big>>,    % ISO error count
    <<0:64/big>>    % Setup data
  ],

  gen_tcp:send(Socket, EmptyResp),
  case TimerRef of
    undefined ->
      ok;
    _ ->
      erlang:cancel_timer(TimerRef),
      self() ! next_key
  end,
  handle_command(RestBinary, Socket, State#state{pending_data = RestBinary, timer_for_set = undefined});

handle_urb(_, _, _, _, State) ->
  io:format("## UNRECOGNIZED URB~n"),
  {ok, State}.

-spec bin_zero_pad(binary(), non_neg_integer()) -> iolist().
bin_zero_pad(Binary, N) when size(Binary) =< N ->
  [Binary, binary:copy(<<0>>, N - size(Binary))].






