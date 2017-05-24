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

procedure ScreenModeSwitch;
// Call this to adjust the game to whatever the console's current size is.
var ivar, jvar : dword;
begin
 GetConsoleSize(ivar, jvar);
 if ivar <> 0 then sysvar.mv_WinSizeX := ivar;
 if jvar <> 0 then sysvar.mv_WinSizeY := jvar;

 log('Console size change: ' + strdec(ivar) + 'x' + strdec(jvar));
 if ivar <> 0 then sysvar.mv_WinSizeX := ivar;
 if jvar <> 0 then sysvar.mv_WinSizeY := jvar;
 // Forget any ongoing transition. These rely on a stashed copy of the screen
 // being transitioned away from, and a new screen size means the old copy
 // would be mis-sized.
 if transitionactive < fxcount then DeleteFx(transitionactive);

 // Set up buffers for output.
 ivar := sysvar.mv_WinSizeX * sysvar.mv_WinSizeY * 4;
 if mv_OutputBuffy <> NIL then begin freemem(mv_OutputBuffy); mv_OutputBuffy := NIL; end;
 getmem(mv_OutputBuffy, ivar);
 if stashbuffy <> NIL then begin freemem(stashbuffy); stashbuffy := NIL; end;
 getmem(stashbuffy, ivar);

 // The viewports may need adjusting. This call imports the new window pixel
 // size into viewport 0, and then cascades the change down to child ports.
 // All content in the viewports also gets marked for refreshing. All
 // previous screen refresh rects are dropped, as they are now mis-sized.
 numfresh := 0;
 UpdateViewport(0);
end;

procedure Debug_PrintGobs;
var ivar : dword;
    txt : UTF8string;
begin
 log('=== GOBS ===');
 if length(gob) = 0 then exit;
 for ivar := 0 to high(gob) do begin
  if ivar < 10 then txt := '0' + strdec(ivar) else txt := strdec(ivar);
  txt := txt + '  ' + gob[ivar].gobnamu;
  if length(gob[ivar].gobnamu) < 16 then txt := txt + space(16 - length(gob[ivar].gobnamu));
  txt := txt + '  parent=';
  if gob[ivar].parent < 10 then txt := txt + '0' + strdec(gob[ivar].parent)
  else if gob[ivar].parent >= dword(length(gob)) then txt := txt + '--'
  else txt := txt + strdec(gob[ivar].parent);
  txt := txt + '  vp=' + strdec(gob[ivar].inviewport) + '  drawst=' + strhex(gob[ivar].drawstate) + '  loc=';
  txt := txt + strdec(gob[ivar].locx) + ',' + strdec(gob[ivar].locy);
  txt := txt + '  locp=' + strdec(gob[ivar].locxp) + ',' + strdec(gob[ivar].locyp);
  txt := txt + '  sizep=' + strdec(gob[ivar].sizexp) + 'x' + strdec(gob[ivar].sizeyp);
  log(txt);
 end;
end;

procedure HandleConEvent(com : UTF8string);
var ivar : dword;
begin
 if com = '' then exit;
 if com[1] = chr(0) then begin
  // Ctrl-B
  if com = chr(0) + chr(4) + chr(2) then UserInput_HideBoxes;

  // Ctrl-P
  if com = chr(0) + chr(4) + chr($10) then
   if pausestate = PAUSESTATE_NORMAL then SetPauseState(PAUSESTATE_PAUSED)
   else SetPauseState(PAUSESTATE_NORMAL);
  // Ctrl-Alt-P or Ctrl-Shift-P
  if (com = chr(0) + chr(2) + chr($10))
  or (com = chr(0) + chr(5) + chr($10)) then SetPauseState(PAUSESTATE_SINGLE);

  // Ctrl-Q
  if com = chr(0) + chr(4) + chr($11) then sysvar.quit := TRUE;

  // Ctrl-R
  if com = chr(0) + chr(4) + chr($12) then ScreenModeSwitch;

  // Ctrl-T
  if com = chr(0) + chr(4) + chr($14) then begin
   saku_param.lxymix := NOT saku_param.lxymix;
   initxpal;
   AddRefresh(0, 0, sysvar.mv_WinSizeX, sysvar.mv_WinSizeY);
   for ivar := high(TBox) downto 0 do
    if TBox[ivar].style.hidable and 1 = 0 then TBox[ivar].needsredraw := TRUE;
  end;
 end

 else if com[1] = chr($EE) then begin
  if com = chr($EE) + chr($90) + chr($A5) then UserInput_Left else
  if com = chr($EE) + chr($90) + chr($A6) then UserInput_Up else
  if com = chr($EE) + chr($90) + chr($A7) then UserInput_Right else
  if com = chr($EE) + chr($90) + chr($A8) then UserInput_Down;
 end

 else begin
  // Enter
  if com = chr($D) then UserInput_Enter else

  // Esc
  if com = chr(27) then UserInput_Esc else

  if com = '*' then UserInput_HideBoxes else
  if com = '@' then Debug_PrintGobs;
 end;
end;

// ------------------------------------------------------------------

procedure MainLoop;
var tickcount, tickmark : ptruint;
    ivar, jvar : dword;
begin
 tickmark := GetMsecTime;
 while TRUE do begin
  while NOT sysvar.quit do begin
   // How long has it been since the last frame?
   tickcount := tickmark;
   tickmark := GetMsecTime;
   tickcount := (tickmark - tickcount) and $FFFF;
   // If we are paused, then override elapsed time with 0.
   if pausestate = PAUSESTATE_PAUSED then tickcount := 0;

   // Process timer events, if any.
   if (length(event.timer) <> 0) and (tickcount <> 0) then
    for ivar := 0 to high(event.timer) do with event.timer[ivar] do begin
     inc(timercounter, tickcount);
     while timercounter >= triggerfreq do begin
      dec(timercounter, triggerfreq);
      StartFiber(triggerlabel, '');
     end;
    end;

   // User input etc.
   event.triggeredint := FALSE;
   sysvar.keysdown := 0;
   while KeyPressed do HandleConEvent(ReadKey);

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
   tickcount := dword(GetMsecTime - tickmark);
   if tickcount < sysvar.resttime then delay(sysvar.resttime - tickcount);

   // If single-stepping, our step is done, so re-pause the game.
   if pausestate = PAUSESTATE_SINGLE then SetPauseState(PAUSESTATE_PAUSED);
  end;
  // Quitting the main loop; if restart is not true, shut down.
  if sysvar.restart = FALSE then exit;
  // If restart is true, re-init and return to the main loop.
  sysvar.restart := FALSE;
  sysvar.quit := FALSE;
  ResetDefaults;
  StartFiber(mainscriptname, 'MAIN');
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

 // Release the display buffer.
 if mv_OutputBuffy <> NIL then begin freemem(mv_OutputBuffy); mv_OutputBuffy := NIL; end;
 if stashbuffy <> NIL then begin freemem(stashbuffy); stashbuffy := NIL; end;

 // Free textboxes.
 DestroyTextbox(0);

 // Free whatever other memory was reserved.
 if seengfxp <> NIL then begin freemem(seengfxp); seengfxp := NIL; end;
 if length(fx) <> 0 then
 for ivar := high(fx) downto 0 do if fx[ivar].poku <> NIL then begin freemem(fx[ivar].poku); fx[ivar].poku := NIL; end;

 // Print out the error message if exiting unnaturally.
 if (erroraddr <> NIL) or (exitcode <> 0) then begin
  writeln(errortxt(exitcode));

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
  mkdir(saku_param.profiledir);
  while IOresult <> 0 do ;
  txt := saku_param.profiledir + 'saku.log';
  assign(logfile, txt);
  filemode := 1; rewrite(logfile); // write-only
  ivar := IOresult;
 end;
 if ivar <> 0 then begin
  writeln(errortxt(ivar) + ' trying to create ' + txt);
  exit;
 end;

 log('---===--- SuperSakura ' + SSver + ' ---===---');

 // Basic variable init. Sysvars carry over even when returning to a game's
 // main script. Some of these get saved in a configuration file.
 with sysvar do begin
  resttime := 1000 div 16; // consoles don't need too many FPS
  mv_WinSizeX := 80; mv_WinSizeY := 25;
  uimagnification := 32768;
  mouseX := 0; mouseY := 0;
  hideboxes := 0;
  numlang := 1;
  skipseentext := FALSE;
  fullscreen := FALSE; // meaningless on consoles
  WinSizeAuto := TRUE;
  restart := FALSE;
  quit := FALSE; // set to TRUE to quit
 end;

 // alphamixtab is a lookup table for anything where you need a*b/255
 for ivar := 255 downto 0 do for jvar := 255 downto 0 do
  alphamixtab[jvar, ivar] := ivar * jvar div 255;
 initxpal;

 // Load the initial DAT file.
 // Use a default if no file was specified on the commandline.
 if saku_param.datname = '' then
 if lowercase(saku_param.appname) = 'supersakura-con'
 then saku_param.datname := 'supersakura.dat'
 else saku_param.datname := saku_param.appname + '.dat';

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
  writeln(txt);
  LogError(txt);
  exit;
 end;
 log('Selected DAT: ' + txt);

 if LoadDAT(txt) <> 0 then begin
  writeln(asman_errormsg);
  LogError(asman_errormsg);
  exit;
 end;

 if GetScr(mainscriptname) = 0 then begin
  txt := 'Main script not found.';
  writeln(txt);
  LogError(txt);
  exit;
 end;

 //ReadSeenGFX;
 // Read the config file here.
 ReadConfig;

 GetConsoleSize(ivar, jvar);
 if ivar <> 0 then sysvar.mv_WinSizeX := ivar;
 if jvar <> 0 then sysvar.mv_WinSizeY := jvar;
 if saku_param.overridex <> 0 then sysvar.mv_WinSizeX := saku_param.overridex;
 if saku_param.overridey <> 0 then sysvar.mv_WinSizeY := saku_param.overridey;

 // Hide the console cursor. Set the console colors to an expected default.
 CrtShowCursor(FALSE);
 SetColor($0007);

 log('Game window size: ' + strdec(sysvar.mv_WinSizeX) + 'x' + strdec(sysvar.mv_WinSizeY));
 UpdateCoscosTable;

 // Set up buffers for output.
 ivar := sysvar.mv_WinSizeX * sysvar.mv_WinSizeY * 4;
 if mv_OutputBuffy <> NIL then begin freemem(mv_OutputBuffy); mv_OutputBuffy := NIL; end;
 getmem(mv_OutputBuffy, ivar);
 if stashbuffy <> NIL then begin freemem(stashbuffy); stashbuffy := NIL; end;
 getmem(stashbuffy, ivar);

 // One meg should be plenty for console graphics caching.
 asman_gfxmemlimit := 1048576;

 // The wop param list may need initing.
 if ss_rwopparams[WOP_TBOX_PRINT][WOPP_BOX] = 0 then ss_rwopparams_init;

 // This must be called every time before booting the main script.
 ResetDefaults;

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
  lxymix := FALSE;
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
     else if (lowercase(txt) = 'lxy')
       then saku_param.lxymix := TRUE
     else if (lowercase(txt) = 'rgb')
       then saku_param.lxymix := FALSE
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

 writeln('  SuperSakura-con  ' + SSver);
 writeln('----------------------------------------');
 writeln('(built on ' + {$include %DATE%} + ' ' + {$include %TIME%} + ')');
 writeln('Usage: supersakura-con [data file] [-options]');
 writeln;
 writeln('Options:');
 writeln('-x=n               Override window width, set to n columns');
 writeln('-y=n               Override window height, set to n rows');
 writeln('-rgb               Use RGB palette mixing');
 writeln('-lxy               Use LXY palette mixing');
 writeln('-help              Shows this thing?');
end;
