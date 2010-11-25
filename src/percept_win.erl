%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2009. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%

-module(percept_win).

-export([
	new/2,
	stop/2,

	add/2

        ]).

-include_lib("wx/include/wx.hrl").

-record(rs, {
	l = [],
	n = 1
	}).

-record(state, {
          parent_pid,
          frame,
          window,
          width,
          height,
          pen,
          brush,
          font,
	  rs = #rs{},
          ticker
         }).

-define(BRD,10).
-define(ARC_R, 10).

-define(color_bg, {45,50,95}).
-define(color_fg, {235,245,230}).
-define(color_default, {10,220,20}).
-define(color_default_bg, {20,230,30}).
-define(color_alternate, {220,10,20}).
-define(color_alternate_bg, {230,20,30}).


add(Pid, {Ts, State}) -> Pid ! {add, {Ts, State}}.

stop(Pid, Reason) -> 
    Ref = erlang:monitor(process, Pid),
    Pid ! {stop, Reason},
    receive
        {'DOWN', Ref, _, _, _} ->
            ok
    end.

new(Parent, Options) ->
    Env = wx:get_env(),
    Me  = self(),
    Pid = spawn_link(fun() -> init([Parent, Me, Env, Options]) end),
    receive {Pid, {?MODULE, Panel}} -> {Pid,Panel} end.
    
init([ParentWin, Pid, Env, Options]) ->
    wx:set_env(Env),

    Win = wxWindow:new(ParentWin, ?wxID_ANY, Options),
    
    wxWindow:connect(Win, enter_window),        
    wxWindow:connect(Win, move),
    wxWindow:connect(Win, motion),
    wxWindow:connect(Win, mousewheel),
    wxWindow:connect(Win, key_up),
    wxWindow:connect(Win, left_down),
    wxWindow:connect(Win, left_up),
    wxWindow:connect(Win, right_down),
    %%wxWindow:connect(Win, paint,  [{skip, true}]),
    %% wxWindow:connect(Win, paint,  [{callback, fun(_,_) -> ok end}]),
    
    Pen   = wxPen:new({0,0,0}, [{width, 3}]),
    Font  = wxFont:new(12, ?wxSWISS, ?wxNORMAL, ?wxNORMAL,[]),
    Brush = wxBrush:new({0,0,0}),
    
    WindowSizer = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(WindowSizer, Win, [{flag, ?wxEXPAND}, {proportion, 1}]),

    Pid ! {self(), {?MODULE, WindowSizer}},

    wxWindow:setFocus(Win), %% Get keyboard focus
  
    Me = self(),

    Ticker = spawn_link(fun() -> ticker_init(Me) end),
    
    loop( #state{ parent_pid = Pid,
		  frame = ParentWin,
		  window = Win,
		  ticker = Ticker,
		  pen = Pen,
		  font = Font,
		  brush = Brush}).



ticker_init(Pid) ->
    ticker_loop(Pid, 50).
ticker_loop(Pid, Time) ->
    receive after Time ->
        Pid ! {self(), redraw},
        T0 = now(),
        receive {Pid, ok} -> ok end,
        T1 = now(),
        D = timer:now_diff(T1, T0)/1000,
        case round(40 - D) of
            Ms when Ms < 0 -> ticker_loop(Pid, 0);
            Ms -> ticker_loop(Pid, Ms)
        end
    end.


loop(S) ->
    receive

        {Req, redraw} ->
            Req ! {self(), ok},
	    {Out, Rs} = rs_do(S#state.rs),
            redraw(S, Out),
            loop(S#state{ rs = Rs});

        {stop, Reason} ->
	    unlink(S#state.parent_pid),
	    exit(Reason);

	{add, What} ->
	    loop(S#state{ rs = rs_add(What, S#state.rs)});


        Other ->
            %error_logger:format("~p~p got unexpected message:\n\t~p\n", [?MODULE, self(), Other]),          
            loop(S)
    end.

%% runnability handling

rs_add({Ts, active}, #rs{l = L, n = N} = Rs) ->
    Rs#rs{ l = [{Ts, N + 1}|L], n = N + 1};
rs_add({Ts, inactive}, #rs{l = L, n = N} = Rs) ->
    Rs#rs{ l = [{Ts, N - 1}|L], n = N - 1}.

rs_do(#rs{ l = L} = Rs) -> rs_do(L, [], [], now(), Rs).
rs_do([], Lsr, Out, T1, Rs) -> {lists:reverse(Out), Rs};
rs_do([{T0,N}|Ls], Lsr, Out, T1, Rs) ->
    case timer:now_diff(T1, T0)/1000000 of
    	T when T > 20 -> {lists:reverse([{20, N}|Out]), Rs#rs{ l = lists:reverse([{T0,N}|Lsr])}};
	T -> rs_do(Ls, [{T0,N}|Lsr], [{T,N}|Out], T1, Rs)
    end.




redraw(#state{window=Win} = S, Lrs) ->
    DC0  = wxClientDC:new(Win),
 %%   DC   = wxBufferedDC:new(DC0),
    Size = wxWindow:getSize(Win),
    redraw(DC0, Size, S, Lrs),
 %%   wxBufferedDC:destroy(DC),
    wxClientDC:destroy(DC0),
    ok.

redraw(DC, Size, S, Lrs) ->    
    wx:batch(fun() -> 
        Pen   = S#state.pen,
        Font  = S#state.font,
        Brush = S#state.brush,
        wxDC:setTextForeground(DC,?color_fg),
        wxBrush:setColour(Brush, ?color_bg),
        wxDC:setBrush(DC, Brush),
        wxDC:setBackground(DC, Brush),
        wxDC:clear(DC),

	wxPen:setColour(Pen, {220,200, 200}),
        wxPen:setWidth(Pen, 1),
        wxDC:setPen(DC,Pen),

	draw_rs(DC, Size, Lrs),
	
	wxPen:setColour(Pen, {20,200, 200}),
        wxDC:setPen(DC,Pen),

	draw_x(DC, Size),

        ok
    end).


draw_rs(DC, {Sx, Sy}, Rs) -> draw_rs(DC, {Sx - 10, Sy - 10}, {0,0}, Rs).
draw_rs(DC, _, _, []) -> ok;
draw_rs(DC, Size, P0, [P1|Rs]) ->
    draw_line(DC, xyc(P0, {10,10}, Size), xyc(P1, {10,10}, Size)),
    draw_rs(DC, Size, P1, Rs).

xyc({T, N}, {Sx, Sy}, {Ex, Ey}) ->
    Lx = Ex - Sx,
    
    X = round(T/20*Lx + Sx),
    Y = round(Ey - 5*N),
    {X, Y}.

draw_x(DC, {Sx, Sy}) ->
    X1 = 10,
    X2 = Sx - 10,
    Y1 = 10,
    Y2 = Sy - 10,

    draw_line(DC, {X1, Y1}, {X2, Y1}),
    draw_line(DC, {X2, Y1}, {X2, Y2}),
%    draw_line(DC, {X2, Y2}, {X1, Y2}),
    draw_line(DC, {X1, Y2}, {X1, Y1}),
    ok.

draw_line(DC, P0, P1) -> draw_line(DC, P0, P1, {0,0}).
draw_line(DC, {X0,Y0}, {X1, Y1}, {X, Y}) ->
    wxDC:drawLine(DC, {round(X0 + X), round(Y0 + Y)}, {round(X1 + X), round(Y1 + Y)}).
