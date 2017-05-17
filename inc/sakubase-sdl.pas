{                                                                           }
{ Copyright 2009-2017 :: Kirinn Bunnylin / Mooncore                         }
{                                                                           }
{ This file is part of SuperSakura.                                         }
{                                                                           }
{ SuperSakura is free software: you can redistribute it and/or modify       }
{ it under the terms of the GNU General Public License as published by      }
{ the Free Software Foundation, either version 3 of the License, or         }
{ (at your option) any later version.                                       }
{                                                                           }
{ SuperSakura is distributed in the hope that it will be useful,            }
{ but WITHOUT ANY WARRANTY; without even the implied warranty of            }
{ MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             }
{ GNU General Public License for more details.                              }
{                                                                           }
{ You should have received a copy of the GNU General Public License         }
{ along with SuperSakura.  If not, see <https://www.gnu.org/licenses/>.     }
{                                                                           }

procedure InitGamepad;
var ivar : dword;
begin
 // Release the previous gamepad, if any.
 if mv_GamepadH <> NIL then begin
  SDL_GameControllerClose(mv_GamepadH);
  mv_GamepadH := NIL;
 end;

 ivar := SDL_NumJoysticks;
 while ivar <> 0 do begin
  dec(ivar);
  if SDL_IsGameController(ivar) = SDL_TRUE then begin
   mv_GamepadH := SDL_GameControllerOpen(ivar);
   if mv_GamepadH <> NIL then break;
   writeln('Failed to open gamepad: ',SDL_GetError);
  end;
 end;

 if mv_GamepadH <> NIL then writeln('Opened gamepad: ',SDL_GameControllerName(mv_GamepadH));
end;

procedure CreateRendererAndTexture;
var rendinfo : TSDL_RendererInfo;
    ivar, jvar : dword;
begin
 // Release the old-sized texture and renderer, if any.
 if mv_MainTexH <> NIL then begin SDL_DestroyTexture(mv_MainTexH); mv_MainTexH := NIL; end;
 if mv_RendererH <> NIL then begin SDL_DestroyRenderer(mv_RendererH); mv_RendererH := NIL; end;

 // Create the renderer!
 ivar := 0;
 if sysvar.usevsync then ivar := SDL_RENDERER_PRESENTVSYNC;
 mv_RendererH := SDL_CreateRenderer(mv_MainWinH, -1, ivar);
 if mv_RendererH = NIL then begin
  LogError('Failed to create SDL renderer: ' + SDL_GetError);
  exit;
 end;

 SDL_GetRendererOutputSize(mv_RendererH, @ivar, @jvar);
 log('New renderer output size: ' + strdec(ivar) + 'x' + strdec(jvar));

 // Clear the window a few times (double/triple buffering).
 SDL_SetRenderDrawColor(mv_RendererH, 0, 0, 0, 255);
 SDL_RenderClear(mv_RendererH);
 SDL_RenderPresent(mv_RendererH);
 SDL_SetRenderDrawColor(mv_RendererH, 0, 0, 0, 255);
 SDL_RenderClear(mv_RendererH);
 SDL_RenderPresent(mv_RendererH);
 SDL_SetRenderDrawColor(mv_RendererH, 0, 0, 0, 255);
 SDL_RenderClear(mv_RendererH);
 SDL_RenderPresent(mv_RendererH);

 ivar := SDL_GetRendererInfo(mv_RendererH, @rendinfo);
 if ivar <> 0 then LogError('Error fetching renderer info: ' + SDL_GetError)
 else begin
  log('Using renderer: ' + rendinfo.name);
  log('Desired texture size: ' + strdec(sysvar.mv_WinSizeX) + 'x' + strdec(sysvar.mv_WinSizeY));
  log('Max texture size (effectively, largest possible window): ' + strdec(rendinfo.max_texture_width) + 'x' + strdec(rendinfo.max_texture_height));
  if rendinfo.flags and SDL_RENDERER_SOFTWARE <> 0
  then log('We''re a software renderer')
  else log('We''re a hardware renderer');
  if rendinfo.flags and SDL_RENDERER_ACCELERATED <> 0
  then log('We''re accelerated')
  else log('We''re not accelerated');
  if rendinfo.flags and SDL_RENDERER_PRESENTVSYNC <> 0
  then log('We''re vsynched')
  else log('We''re not vsynched');
 end;

 // Create the texture that is directly used as output
 mv_MainTexH := SDL_CreateTexture(
   mv_RendererH, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING,
   sysvar.mv_WinSizeX, sysvar.mv_WinSizeY);
 if mv_MainTexH = NIL then begin
  LogError('Failed to create SDL maintex: ' + SDL_GetError);
  exit;
 end;

 // Set up buffers for output.
 ivar := sysvar.mv_WinSizeX * sysvar.mv_WinSizeY * 4;
 if mv_OutputBuffy <> NIL then begin freemem(mv_OutputBuffy); mv_OutputBuffy := NIL; end;
 getmem(mv_OutputBuffy, ivar);
 if stashbuffy <> NIL then begin freemem(stashbuffy); stashbuffy := NIL; end;
 getmem(stashbuffy, ivar);
end;

procedure SpawnWindow;
// Does everything necessary to set up a window to draw in.
begin
 log('Spawning a window...');

 // Close and release the existing game window, if any.
 if mv_MainWinH <> NIL then begin SDL_DestroyWindow(mv_MainWinH); mv_MainWinH := NIL; end;

 // Arbitrary window size minimum bounds.
 if sysvar.WindowSizeX < 16 then sysvar.WindowSizeX := 16;
 if sysvar.WindowSizeY < 16 then sysvar.WindowSizeY := 16;

 sysvar.mv_WinSizeX := sysvar.WindowSizeX;
 sysvar.mv_WinSizeY := sysvar.WindowSizeY;

 // Create the window!
 mv_MainWinH := SDL_CreateWindow(
   NIL, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
   sysvar.mv_WinSizeX, sysvar.mv_WinSizeY, SDL_WINDOW_SHOWN);
 if mv_MainWinH = NIL then begin
  LogError('Failed to create SDL window: ' + SDL_GetError);
  exit;
 end;

 // Create the renderer and texture. All output goes first into our own
 // outputbuffy, then that gets pushed into the texture, and the renderer is
 // called to copy the full texture to the game window every frame.
 CreateRendererAndTexture;

 // Make sure we start with a clean, black window.
 filldword(mv_OutputBuffy^, sysvar.mv_WinSizeX * sysvar.mv_WinSizeY, 0);
 SDL_UpdateTexture(mv_MainTexH, NIL, mv_OutputBuffy, sysvar.mv_WinSizeX * 4);
end;

procedure ScreenModeSwitch(usefull : boolean);
// Removes the existing game window, and creates a new one.
// If FULL is TRUE, creates a desktop-sized window.
// If FULL is FALSE, creates a window of size WindowSizeX,WindowSizeY.
// SDL2 has a fullscreen toggle, but it seems bugged under some conditions,
// so manually recreating the whole display stack seems to be the best way.
var dispmode : TSDL_DisplayMode;
    ivar, jvar : dword;
begin
 log(':: Screen mode switch!');
 // Forget any ongoing transition. These rely on a stashed copy of the screen
 // being transitioned away from, and a new screen size means the old copy
 // would be mis-sized.
 if transitionactive < fxcount then DeleteFx(transitionactive);

 // Close and release the existing game window, if any.
 if mv_MainWinH <> NIL then begin SDL_DestroyWindow(mv_MainWinH); mv_MainWinH := NIL; end;

 {$ifdef bonk}
 // Resize the window. You'd think this would just work, but returning from
 // fullscreen may cause the renderer to adopt a wrong size??
 ivar := 0;
 if usefull then ivar := SDL_WINDOW_FULLSCREEN_DESKTOP;
 if SDL_SetWindowFullscreen(mv_MainWinH, ivar) <> 0 then begin
  LogError('SetWindowFullscreen: ' + SDL_GetError);
  exit;
 end;
 {$endif}

 ivar := SDL_WINDOW_SHOWN;
 if usefull then ivar := ivar or SDL_WINDOW_FULLSCREEN_DESKTOP;
 // Re-create the window!
 mv_MainWinH := SDL_CreateWindow(
   NIL, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
   sysvar.WindowSizeX, sysvar.WindowSizeY, ivar);
 if mv_MainWinH = NIL then begin
  LogError('Failed to create SDL window: ' + SDL_GetError);
  exit;
 end;

 // Rename the window!
 if (pausestate = PAUSESTATE_PAUSED)
 then SetProgramName(mv_ProgramName + ' [paused]')
 else SetProgramName(mv_ProgramName);

 // Confirm what we got. When switching away from fullscreen, the display
 // mode may show an incorrect size, so the new window size must be taken
 // from GetWindowSize.
 SDL_GetWindowDisplayMode(mv_MainWinH, @dispmode);
 log('GetWinDisplayMode: ' + strdec(dispmode.w) + 'x' + strdec(dispmode.h));
 SDL_GL_GetDrawableSize(mv_MainWinH, @ivar, @jvar);
 log('GL_GetDrawable: ' + strdec(ivar) + 'x' + strdec(jvar));
 SDL_GetWindowSize(mv_MainWinH, @ivar, @jvar);
 log('GetWindowSize: ' + strdec(ivar) + 'x' + strdec(jvar));
 sysvar.mv_WinSizeX := ivar;
 sysvar.mv_WinSizeY := jvar;
 sysvar.fullscreen := usefull;

 // Re-create the renderer.
 CreateRendererAndTexture;

 // The viewports may need adjusting. This call imports the new window pixel
 // size into viewport 0, and then cascades the change down to child ports.
 // All content in the viewports also gets marked for refreshing. All
 // previous screen refresh rects are dropped, as they are now mis-sized.
 numfresh := 0;
 UpdateViewport(0);
end;

procedure GetDefaultWindowSizes(var sizex, sizey : dword);
// This calculates the nicest window size that fits on the user's desktop.
// The main game data file should be loaded before this, as it gives us the
// native resolution of the game being loaded. We can use that size to figure
// out a good multiplier that doesn't use weird fractions.
var mymode : TSDL_DisplayMode;
    myrekt : TSDL_Rect;
    ivar : dword;
begin
 if SDL_GetDesktopDisplayMode(0, @mymode) <> 0 then LogError(SDL_GetError)
 else if SDL_GetDisplayUsableBounds(0, @myrekt) <> 0 then LogError(SDL_GetError)
 else begin
  log('SDL reports desktop size: ' + strdec(mymode.w) + 'x' + strdec(mymode.h));
  log('Usable desktop area: ' + strdec(myrekt.w) + 'x' + strdec(myrekt.h));
  sysvar.FullSizeX := mymode.w;
  sysvar.FullSizeY := mymode.h;
  sizex := asman_baseresx;
  sizey := asman_baseresy;
  // Start from 0.5x, add 0.5 more until a good size is reached.
  ivar := 1;
  while ((sizex * ivar) shr 1 <= dword(myrekt.w))
  and ((sizey * ivar) shr 1 <= dword(myrekt.h))
  do inc(ivar);
  dec(ivar);
  sizex := (sizex * ivar) shr 1;
  sizey := (sizey * ivar) shr 1;
 end;
end;

{$ifdef bonk}
   // Ctrl-V: game version
   $4016: begin
           txt := 'SuperSakura ' + ssver + chr(13)
                //+ gstr[0] + ' v' + strdec(gameversion) + chr(13)
                + chr(13) + 'Osewa ni natte imasu! ^_^ ' + chr(0);
           MessageBoxA(mv_WindowH, @txt[1], @txt[length(txt)], MB_OK);
          end;

   ord('$'): begin // Do a bunch of renders to count FPS
              ivar := sysvar.resttime;
              sysvar.resttime := 0; xvar := 512;
              lvar := GetTickCount;
              for jvar := xvar - 1 downto 0 do begin
               for yvar := high(gob) downto 0 do // redraw everything!
                if IsGobValid(yvar) then
                if gob[yvar].drawstate and 2 <> 0 then
                gob[yvar].drawstate := gob[yvar].drawstate or 1;
               Renderer(sysvar.resttime);
              end;
              lvar := GetTickCount - lvar;
              sysvar.resttime := ivar;
              jvar := (lvar + xvar shr 1) div xvar; // msec per frame
              ivar := (xvar * 1000 + lvar shr 1) div lvar; // fps
              ClearTextBox(1);
              PrintTxt(0, 'Rendered current screen ' + strdec(xvar) + ' times' + chr($A) + 'Elapsed time: ' + strdec(lvar) + 'ms' + chr($A) + 'Time/frame: ' + strdec(jvar) + 'ms' + chr($A) + 'FPS: ' + strdec(ivar));
             end;
{$endif}

procedure HandleSDLevent(evd : PSDL_event);
// Call this with each new SDL event that comes in.

  function ConfirmQuit : boolean;
  var bbdata : array[0..1] of TSDL_MessageBoxButtonData;
      boxdata : TSDL_MessageBoxData;
      response : longint;
  begin
   // TODO: use in-engine blocking dialog box to have gamepad support
   ConfirmQuit := FALSE;
   bbdata[1].flags := SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT;
   bbdata[1].buttonid := 0;
   bbdata[1].text := 'Yes';
   bbdata[0].flags := SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT;
   bbdata[0].buttonid := 1;
   bbdata[0].text := 'No';
   with boxdata do begin
    flags := 0;
    window := mv_MainWinH;
    title := 'Quit?';
    _message := 'Are you sure you want to quit?';
    numbuttons := 2;
    buttons := @bbdata[0];
    colorScheme := NIL;
   end;

   if SDL_ShowMessageBox(@boxdata, @response) <> 0 then begin
    LogError('Confirm Quit box failed: ' + SDL_GetError);
    ConfirmQuit := TRUE;
   end
   else if response = 0 then ConfirmQuit := TRUE;
  end;

  procedure HandleKeyPress(sym : longint; modifier : word);
  // The symbol is an SDL virtual keycode, and the modifier is an SDL_Keymod.
  // Use this for any direct keyboard input, but NOT for typing in any
  // strings. Typed strings require bonus localisation handling.
  begin
   // === Keyboard shortcuts ===
   if modifier and KMOD_CTRL <> 0 then case sym of
    SDLK_B: UserInput_HideBoxes;

   end;

   // === Cursor keys, Enter and ESC ===
   case sym of
    SDLK_RETURN, SDLK_RETURN2, SDLK_KP_ENTER: UserInput_Enter;
    SDLK_ESCAPE: UserInput_Esc;
    SDLK_RIGHT, SDLK_KP_6: UserInput_Right;
    SDLK_LEFT, SDLK_KP_4: UserInput_Left;
    SDLK_DOWN, SDLK_KP_2: UserInput_Down;
    SDLK_UP, SDLK_KP_8: UserInput_Up;
    else
     writeln('KeyDown: ',sym,' mod $',strhex(modifier));
   end;
  end;

begin
 // A few keyboard commands must be handled early regardless of gamemode...
 if evd^.type_ = SDL_KEYDOWN then begin

  // ctrl-q = 113 / $40 and 113 / $80
  if (evd^.key.keysym.sym = SDLK_Q) and (evd^.key.keysym._mod and $C0 <> 0)
  then evd^.type_ := SDL_QUITEV else

  // the pause button
  if (evd^.key.keysym.sym = SDLK_PAUSE)
  or (evd^.key.keysym._mod and KMOD_CTRL <> 0)
  and (evd^.key.keysym.sym = SDLK_P)
  then begin
   if evd^.key.keysym._mod and KMOD_SHIFT <> 0 then begin
    // Shift-pause was pressed (modifiers $1 and $2)
    SetPauseState(PAUSESTATE_SINGLE);
   end else begin
    // Normal pause
    if pausestate = PAUSESTATE_PAUSED then SetPauseState(PAUSESTATE_NORMAL)
    else SetPauseState(PAUSESTATE_PAUSED);
   end;
   exit;
  end else
  // alt-enter = 13 / $100 or $240
  if (evd^.key.keysym.sym = SDLK_RETURN)
  or (evd^.key.keysym.sym = SDLK_RETURN2)
  or (evd^.key.keysym.sym = SDLK_KP_ENTER) then
  if (evd^.key.keysym._mod = KMOD_LALT)
  or (evd^.key.keysym._mod = KMOD_RALT)
  or (evd^.key.keysym._mod = $240) // alt-gr
  then begin
   ScreenModeSwitch(not sysvar.fullscreen);
   exit;
  end;
 end;

 // These events must be handled no matter what
 case evd^.type_ of
  SDL_QUITEV: begin
    {$note must be in-engine too due to gamepads+non-modal sdlbox}
    {$note if metamenu is open here, autoclose it}
    // the confirmquit message box is done through SQL, but it can only be
    // interacted with via keyboard and mouse, and it's non-modal? So we
    // gotta implement an in-engine message box a bit later.
    if ConfirmQuit then sysvar.quit := TRUE;
    exit;
  end;
  SDL_CONTROLLERDEVICEADDED: begin log('Controller added!'); InitGamepad; end;
  SDL_CONTROLLERDEVICEREMOVED: begin log('Controller removed!'); InitGamepad; end;

  // If this happens, the renderer has been wrecked? Can happen when the user
  // task switches while in fullscreen mode. Redrawing the whole screen
  // should set things right.
  SDL_RENDER_TARGETS_RESET: begin
   log('RENDER TARGETS RESET');
   numfresh := 0;
   AddRefresh(0, 0, sysvar.mv_WinSizeX, sysvar.mv_WinSizeY);
  end;
  SDL_RENDER_DEVICE_RESET: log('RENDER DEVICE RESET - DO SOMETHING!?');

  SDL_WINDOWEVENT: begin
    if evd^.window.event = SDL_WINDOWEVENT_FOCUS_GAINED then sysvar.havefocus := 1 else
    if evd^.window.event = SDL_WINDOWEVENT_FOCUS_LOST then sysvar.havefocus := 0;
  end;
 end;

 // Any other events can be unceremoniously dropped if the game is paused
 // or if our window doesn't have input focus. (If we only gained focus this
 // frame, drop input until the next frame anyway.)
 if (pausestate = PAUSESTATE_PAUSED)
 or (sysvar.havefocus < 2)
 then exit;

 case evd^.type_ of
  SDL_KEYDOWN: HandleKeyPress(evd^.key.keysym.sym, evd^.key.keysym._mod);
  SDL_MOUSEMOTION: UserInput_Mouse(evd^.motion.x, evd^.motion.y, 0);
  SDL_MOUSEBUTTONDOWN: UserInput_Mouse(evd^.button.x, evd^.button.y, evd^.button.button);
  //SDL_MOUSEBUTTONUP: writeln('Musbutt up: ',evd^.button.button);
  SDL_MOUSEWHEEL: UserInput_Wheel(evd^.wheel.y);
  SDL_CONTROLLERBUTTONDOWN: writeln('Padbutt dn: ',evd^.cbutton.button);
  SDL_CONTROLLERBUTTONUP: writeln('Padbutt up: ',evd^.cbutton.button);
  SDL_CONTROLLERAXISMOTION: writeln('Pad axis: ',evd^.caxis.axis,' is ',evd^.caxis.value);
 end;
end;

// ------------------------------------------------------------------

procedure MainLoop;
var evd : TSDL_event;
    tickcount, tickmark : ptruint;
    ivar : dword;
begin
 tickmark := SDL_GetTicks;
 while NOT sysvar.quit do begin
  // How long has it been since the last frame?
  tickcount := tickmark;
  tickmark := SDL_GetTicks;
  tickcount := (tickmark - tickcount) and $FFFF;
  // If we are paused, then override elapsed time with 0.
  if pausestate = PAUSESTATE_PAUSED then tickcount := 0;

  // Process timer events, if any.
  if (length(event.timer) <> 0) and (tickcount <> 0) then
   for ivar := high(event.timer) downto 0 do with event.timer[ivar] do begin
    inc(timercounter, tickcount);
    while timercounter >= triggerfreq do begin
     dec(timercounter, triggerfreq);
     StartFiber(triggerlabel, '');
    end;
   end;

  // User input etc.
  event.triggeredint := FALSE;
  while SDL_PollEvent(@evd) <> 0 do HandleSDLevent(@evd);

  // if we gained focus just now, stop dropping events as of the next frame
  if sysvar.havefocus = 1 then inc(sysvar.havefocus);

  // if we just entered single-stepping mode...
  if pausestate = PAUSESTATE_SINGLE then begin
   // override elapsed time
   tickcount := sysvar.resttime;
   // should also forward a single piece of user input from all devices...?
  end;

  // Script logic.
  if pausestate <> PAUSESTATE_PAUSED then RunFibers;

  // If, as far as we can tell, absolutely no time has passed since the last
  // time we rendered stuff, then nothing can have changed on-screen, and we
  // may as well not bother drawing the exact same stuff again.
  if tickcount <> 0 then begin

   // Update display structures.
   UpdateVisuals(tickcount);
   // Update various effects.
   if fxcount <> 0 then Effector(tickcount);
  end;

  // Update textbox data and prepare to draw them a little later.
  TextBoxer(tickcount);

  // Update the screen.
  Renderer;

  // Frame limiter... wait for it.
  tickcount := dword(SDL_GetTicks - tickmark);
  if tickcount < sysvar.resttime then SDL_Delay(sysvar.resttime - tickcount);

  // Ask the renderer to finally display the new frame.
  // (or, admit it in the display queue anyway, if double/triple buffering)
  SDL_RenderPresent(mv_RendererH);

  // If single-stepping, our step is done, so re-pause the game.
  if pausestate = PAUSESTATE_SINGLE then SetPauseState(PAUSESTATE_PAUSED);
 end;
end;

// ------------------------------------------------------------------

procedure SakuExit;
// Procedure called automatically on program exit.
var ivar : dword;
    logfileavail : boolean;
begin
 logfileavail := TextRec(logfile).mode <> fmClosed;
 if logfileavail then log('Quitting...');
 sysvar.quit := TRUE;

 // Free textboxes.
 DestroyTextbox(0);

 // Release SDL resources.
 if mv_GamepadH <> NIL then SDL_GameControllerClose(mv_GamepadH);
 if mv_RendererH <> NIL then SDL_DestroyRenderer(mv_RendererH);
 if mv_MainTexH <> NIL then SDL_DestroyTexture(mv_MainTexH);
 if mv_MainWinH <> NIL then SDL_DestroyWindow(mv_MainWinH);
 if logfileavail then log('SDL resources released');

 if TTF_WasInit then TTF_Quit;

 SDL_Quit;

 // Release the display buffer.
 if mv_OutputBuffy <> NIL then begin freemem(mv_OutputBuffy); mv_OutputBuffy := NIL; end;
 if stashbuffy <> NIL then begin freemem(stashbuffy); stashbuffy := NIL; end;

 // Free whatever other memory was reserved.
 if seengfxp <> NIL then begin freemem(seengfxp); seengfxp := NIL; end;
 if length(fx) <> 0 then
 for ivar := high(fx) downto 0 do if fx[ivar].poku <> NIL then begin freemem(fx[ivar].poku); fx[ivar].poku := NIL; end;

 // Print out the error message if exiting unnaturally.
 if (erroraddr <> NIL) or (exitcode <> 0) then begin
  //LogError(errortxt(exitcode));

  // Also print the script code history.
  if logfileavail then begin
   LogError(errortxt(exitcode));
   {$ifdef bonk}
   if scr <> NIL then begin
    log('Script history:');
    for ivar := 15 downto 0 do begin
     if scr^.historyindex <> 0 then dec(scr^.historyindex)
     else scr^.historyindex := 15;
     log(strdec(ivar) + ': ' + strdec(scr^.history[scr^.historyindex]));
    end;
   end;
   {$endif}
  end;
 end;

 if logfileavail then close(logfile);
end;

// ------------------------------------------------------------------

function InitEverything : boolean;
var ivar, jvar : dword;
    txt : UTF8string;

  procedure doinit(initsys : dword; const sysnamu : string);
  begin
   ivar := SDL_InitSubSystem(initsys);
   if ivar <> 0 then begin
    LogError('Failed to init ' + sysnamu + ': ' + strdec(ivar) + ' ' + SDL_GetError);
    inc(jvar);
    exit;
   end;
   log(sysnamu + ' inited');
  end;

begin
 InitEverything := FALSE;
 // Install the exit handler proc
 assign(logfile, '');
 AddExitProc(@sakuexit);
 OnGetApplicationName := @truename;

 // Get the current directory and executable name!
 // The executable name is used for the config file, and the current
 // directory is used for default file IO.
 saku_param.workdir := paramstr(0);
 ivar := length(saku_param.workdir);
 while ivar <> 0 do begin
  if saku_param.workdir[ivar] = DirectorySeparator then break;
  dec(ivar);
 end;
 saku_param.appname := copy(saku_param.workdir, ivar + 1, length(saku_param.workdir));
 setlength(saku_param.workdir, ivar);
 ivar := pos('.', saku_param.appname);
 if ivar <> 0 then setlength(saku_param.appname, ivar - 1);

 // In some cases, the current directory may be write-protected, in which
 // case it's best to fall back to the user's profile directory.
 // The "false" below means user-specific, not global.
 saku_param.profiledir := GetAppConfigDir(FALSE);

 // Set up a log file. Try the current directory first...
 txt := saku_param.workdir + 'saku.log';
 assign(logfile, txt);
 filemode := 1; rewrite(logfile); // write-only
 ivar := IOresult;
 if ivar = 5 then begin
  // Access denied! Try the user's profile directory...
  txt := saku_param.profiledir + 'saku.log';
  assign(logfile, txt);
  filemode := 1; rewrite(logfile); // write-only
  ivar := IOresult;
 end;
 if ivar <> 0 then begin
  txt := errortxt(ivar) + ' trying to create ' + txt;
  SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, 'Error', @txt[1], NIL);
  exit;
 end;

 mv_MainWinH := NIL; mv_RendererH := NIL; mv_MainTexH := NIL;
 mv_GamepadH := NIL;

 log('---===--- SuperSakura ' + SSver + ' ---===---');
 log('SDL headers: ' + strdec(SDL_MAJOR_VERSION) + '.' + strdec(SDL_MINOR_VERSION) + '.' + strdec(SDL_PATCHLEVEL));

 // Evidently this is needed to avoid an exception if GDB is being used...
 //SDL_SetHint(SDL_HINT_WINDOWS_DISABLE_THREAD_NAMING, '1');

 jvar := 0;
 SDL_Init(0);
 doinit(SDL_INIT_EVENTS, 'SDL_events');
 doinit(SDL_INIT_TIMER, 'SDL_timer');
 doinit(SDL_INIT_VIDEO, 'SDL_video');
 doinit(SDL_INIT_AUDIO, 'SDL_audio');
 doinit(SDL_INIT_GAMECONTROLLER, 'SDL_gamecontroller');
 if jvar <> 0 then exit;
 if TTF_Init <> 0 then begin LogError('TTF_Init: ' + TTF_GetError); exit; end;

 ivar := SDL_GetNumVideoDrivers;
 log(strdec(ivar) + ' video drivers');
 while ivar <> 0 do begin
  dec(ivar);
  log(strdec(ivar) + ': ' + SDL_GetVideoDriver(ivar));
 end;
 log('Using driver: ' + SDL_GetCurrentVideoDriver);

 mv_PKeystate := SDL_GetKeyboardState(NIL);
 if mv_PKeystate = NIL then begin LogError('SDL_GetKbState: ' + SDL_GetError); exit; end;

 // Basic variable init. Sysvars carry over even when returning to a game's
 // main script. Some of these get saved in a configuration file.
 with sysvar do begin
  resttime := 1000 div 30;
  mv_WinSizeX := 640; mv_WinSizeY := 480;
  FullSizeX := 640; FullSizeY := 480;
  WindowSizeX := 640; WindowSizeY := 480;
  uimagnification := 32768;
  fullscreen := FALSE; // meaningless on consoles
  havefocus := 2; // consoles always have focus
  WinSizeAuto := TRUE;
  usevsync := TRUE;
  quit := FALSE; // set to TRUE to quit
 end;

 // alphamixtab is a lookup table for anything where you need a*b/255
 for ivar := 255 downto 0 do for jvar := 255 downto 0 do
  alphamixtab[jvar, ivar] := ivar * jvar div 255;

 // Load the initial DAT file.
 // Use a default if no file was specified on the commandline.
 if saku_param.datname = '' then saku_param.datname := 'supersakura.dat';

 if pos(DirectorySeparator, saku_param.datname) = 0 then begin
  // The filename does not contain a path.
  // If it also doesn't have an extension, add ".dat" as a default.
  if pos('.', saku_param.datname) = 0 then saku_param.datname := saku_param.datname + '.dat';
  // Look in the current directory first...
  txt := FindFile_caseless(saku_param.workdir + saku_param.datname);
  // Try in current/data...
  if txt = '' then txt := FindFile_caseless(saku_param.workdir + 'data' + DirectorySeparator + saku_param.datname);
  // Try in profile/data...
  if txt = '' then txt := FindFile_caseless(saku_param.profiledir + 'data' + DirectorySeparator + saku_param.datname);
 end
 else begin
  // The filename contains a path. Let's just check the exact dat string.
  txt := FindFile_caseless(saku_param.workdir + saku_param.datname);
 end;

 if txt = '' then begin
  txt := 'DAT file not found: ' + saku_param.datname;
  LogError(txt);
  exit;
 end;
 log('Selected DAT: ' + txt);

 if LoadDAT(txt) <> 0 then begin
  LogError(asman_errormsg);
  exit;
 end;

 if GetScr(mainscriptname) = 0 then begin
  LogError('Main script not found.');
  exit;
 end;

 //ReadSeenGFX;
 // Read the config file here.
 ReadConfig;
 if length(fontlist) = 0 then begin
  LogError('Failed to find font files.');
  exit;
 end;

 GetDefaultWindowSizes(ivar, jvar);
 if (ivar <> 0) and (saku_param.overridex = 0) then sysvar.mv_WinSizeX := ivar;
 if (jvar <> 0) and (saku_param.overridey = 0) then sysvar.mv_WinSizeY := jvar;
 sysvar.WindowSizeX := sysvar.mv_WinSizeX;
 sysvar.WindowSizeY := sysvar.mv_WinSizeY;

 log('Game window size: ' + strdec(sysvar.mv_WinSizeX) + 'x' + strdec(sysvar.mv_WinSizeY));
 UpdateCoscosTable;

 // Pop up the game window.
 SpawnWindow;

 setlength(refresh, 16); numfresh := 0;
 transitionactive := $FFFFFFFF;

 // For graphics caching, eight times the fullscreen size should be plenty.
 asman_gfxmemlimit := sysvar.FullSizeX * sysvar.FullSizeY * 32;

 // The wop param list may need initing.
 if ss_rwopparams[WOP_TBOX_PRINT][WOPP_BOX] = 0 then ss_rwopparams_init;

 // This must be called every time before booting the main script.
 ResetDefaults;

 randomize;
 StartFiber(mainscriptname, 'MAIN');
 InitEverything := TRUE;
end;

// ------------------------------------------------------------------

function DoParams : boolean;
// Processes the ssakura commandline. Returns FALSE in case of errors etc.
var txt : UTF8string;
    ivar : longint;
begin
 DoParams := TRUE;
 with saku_param do begin
  appname := '';
  workdir := '';
  profiledir := '';
  datname := '';
  overridex := 0; overridey := 0;
  help := FALSE;
 end;

 ivar := 0;
 while ivar < paramcount do begin
  inc(ivar);
  txt := paramstr(ivar);
  if (txt = '?') or (txt = '/?') then saku_param.help := TRUE
  else
  case copy(txt, 1, 1) of
    '-':
    begin
     if copy(txt, 2, 1) = '-' then txt := copy(txt, 3, length(txt) - 2)
     else txt := copy(txt, 2, length(txt) - 1);
     if ((length(txt) = 1) and (txt[1] in ['?','h','H']))
     or (lowercase(txt) = 'help')
       then saku_param.help := TRUE
     else if (lowercase(copy(txt, 1, 2)) = 'x=')
       then saku_param.overridex := valx(copy(txt, 3, length(txt) - 2))
     else if (lowercase(copy(txt, 1, 2)) = 'y=')
       then saku_param.overridey := valx(copy(txt, 3, length(txt) - 2))
     else begin
      writeln('Unrecognised option: ' + paramstr(ivar));
      DoParams := FALSE;
     end;
    end;

    else begin
     if saku_param.datname = '' then saku_param.datname := paramstr(ivar)
     else begin
      writeln('Unrecognised parameter: ' + paramstr(ivar));
      DoParams := FALSE;
     end;
    end;
  end;
 end;

 if (saku_param.help = FALSE) or (DoParams = FALSE) then exit;

 DoParams := FALSE;
 writeln;

 writeln('  SuperSakura  ' + SSver);
 writeln('----------------------------------------');
 writeln('(built on ' + {$include %DATE%} + ' ' + {$include %TIME%} + ')');
 writeln('Usage: supersakura [data file] [-options]');
 writeln;
 writeln('Options:');
 writeln('-x=n               Override window width, set to n pixels');
 writeln('-y=n               Override window height, set to n pixels');
 writeln('-help              Shows this thing?');
end;
