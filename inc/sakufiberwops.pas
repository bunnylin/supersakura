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

procedure Invoke_CALL; inline;
begin
 if FetchParam(WOPP_LABEL) then ScriptCall(fiberid, strvalue[0])
 else fibererror('Call without label name');
end;

procedure Invoke_CASECALL; inline;
begin
 if FetchParam(WOPP_LABEL) = FALSE then fibererror('Casecall without label names')
 else begin
  numvalue := 0;
  FetchParam(WOPP_INDEX);
  ScriptCase(fiberid, strvalue[0], numvalue, TRUE);
 end;
end;

procedure Invoke_CASEGOTO; inline;
begin
 if FetchParam(WOPP_LABEL) = FALSE then fibererror('Casegoto without label names')
 else begin
  numvalue := 0;
  FetchParam(WOPP_INDEX);
  ScriptCase(fiberid, strvalue[0], numvalue, FALSE);
 end;
end;

procedure Invoke_CHOICE_CALL; inline;
begin
 numvalue := 0;
 FetchParam(WOPP_NOCLEAR);
 if numvalue = 0 then with choicematic do begin
  ClearTextbox(choicebox);
  if choicepartbox <> choicebox then ClearTextbox(choicepartbox);
 end;
 ActivateChoicematic(fiberid);
 yieldnow := TRUE;
end;

procedure Invoke_CHOICE_CANCEL; // not inlined, called from other invokes
begin
 DeactivateChoicematic(TRUE);
end;

procedure Invoke_CHOICE_COLUMNS; inline;
begin
 numvalue := 0;
 FetchParam(WOPP_VALUE);
 if numvalue <= 0 then numvalue := 4;
 choicematic.numcolumns := numvalue;
 choicematic.colwidthp := 0;
end;

procedure Invoke_CHOICE_GET; inline;
begin
 numvalue := 0;
 FetchParam(WOPP_NOCLEAR);
 if numvalue = 0 then with choicematic do begin
  ClearTextbox(choicebox);
  if choicepartbox <> choicebox then ClearTextbox(choicepartbox);
 end;
 ActivateChoicematic(fiberid);
 yieldnow := TRUE;
end;

procedure Invoke_CHOICE_GOTO; inline;
begin
 numvalue := 0;
 FetchParam(WOPP_NOCLEAR);
 if numvalue = 0 then with choicematic do begin
  ClearTextbox(choicebox);
  if choicepartbox <> choicebox then ClearTextbox(choicepartbox);
 end;
 ActivateChoicematic(fiberid);
 yieldnow := TRUE;
end;

procedure Invoke_CHOICE_OFF; inline;
begin
 if choicematic.active then Invoke_CHOICE_CANCEL;
 if FetchParam(WOPP_TEXT) = FALSE
 then ToggleChoices('', FALSE) // disable all choices
 else begin
  if (choicematic.choicebox < dword(length(TBox)))
  and (TBox[choicematic.choicebox].boxlanguage < dword(length(strvalue)))
  then strvalue[0] := strvalue[TBox[choicematic.choicebox].boxlanguage];
  if strvalue[0] = '' then ToggleChoices('', FALSE) // disable all choices
  else ToggleChoices(strvalue[0], FALSE) // disable a specific choice
 end;
end;

procedure Invoke_CHOICE_ON; inline;
begin
 if choicematic.active then Invoke_CHOICE_CANCEL;
 if FetchParam(WOPP_TEXT) = FALSE
 then ToggleChoices('', TRUE) // enable all choices
 else begin
  if (choicematic.choicebox < dword(length(TBox)))
  and (TBox[choicematic.choicebox].boxlanguage < dword(length(strvalue)))
  then strvalue[0] := strvalue[TBox[choicematic.choicebox].boxlanguage];
  if strvalue[0] = '' then ToggleChoices('', TRUE) // enable all choices
  else ToggleChoices(strvalue[0], TRUE) // enable a specific choice
 end;
end;

procedure Invoke_CHOICE_PRINTPARENT; inline;
begin
 numvalue := 0;
 FetchParam(WOPP_VALUE);
 choicematic.printchoiceparent := numvalue <> 0;
end;

procedure Invoke_CHOICE_REMOVE; inline;
var ivar : dword;
begin
 with choicematic do begin
  if active then Invoke_CHOICE_CANCEL;
  ivar := choicelistcount;
  if (FetchParam(WOPP_TEXT) = FALSE) or (strvalue[0] = '') then begin
   // Remove all choices.
   choicelistcount := 0;
  end else begin
   // Remove a specific choice.
   if (choicebox >= dword(length(TBox)))
   or (TBox[choicebox].boxlanguage >= dword(length(strvalue)))
   then strvalue[0] := upcase(strvalue[0])
   else strvalue[0] := upcase(strvalue[TBox[choicebox].boxlanguage]);
   while ivar <> 0 do begin
    dec(ivar);
    if upcase(choicelist[ivar].choicetxt) = strvalue[0] then begin
     choicelist[ivar].choicetxt := '';
     choicelist[ivar].selectable := FALSE;
    end;
   end;
   while (choicelistcount <> 0) and (choicelist[choicelistcount - 1].choicetxt = '') do
    dec(choicelistcount);
  end;
 end;
end;

procedure Invoke_CHOICE_RESET; inline;
begin
 if choicematic.active then Invoke_CHOICE_CANCEL;
 choicematic.choicelistcount := 0;
 choicematic.showcount := 0;
 //choicematic.previouschoice := '';
end;

procedure Invoke_CHOICE_SET; inline;
begin
 with choicematic do begin
  if active then Invoke_CHOICE_CANCEL;
  // By default, use the first free index.
  numvalue := choicelistcount;
  FetchParam(WOPP_INDEX);
  if numvalue < 0 then fibererror('choice.set negative index') else
  if FetchParam(WOPP_TEXT) = FALSE then fibererror('choice.set without text')
  else begin
   // Make room in choicematic.
   if numvalue >= length(choicelist)
   then setlength(choicelist, length(choicelist) shr 1 + numvalue + 8);
   while choicelistcount <= dword(numvalue) do begin
    choicelist[choicelistcount].choicetxt := '';
    choicelist[choicelistcount].jumplist := '';
    choicelist[choicelistcount].trackvar := '';
    choicelist[choicelistcount].selectable := FALSE;
    inc(choicelistcount);
   end;
   // Set the choice details. Use the choice box's preferred language.
   if (choicebox >= dword(length(TBox)))
   or (TBox[choicebox].boxlanguage >= dword(length(strvalue)))
   then choicelist[numvalue].choicetxt := strvalue[0]
   else choicelist[numvalue].choicetxt := strvalue[TBox[choicebox].boxlanguage];
   choicelist[numvalue].jumplist := '';
   choicelist[numvalue].trackvar := '';
   choicelist[numvalue].selectable := TRUE;
   if FetchParam(WOPP_LABEL) then choicelist[numvalue].jumplist := strvalue[0];
   if FetchParam(WOPP_VAR) then choicelist[numvalue].trackvar := strvalue[0];
  end;
 end;
end;

procedure Invoke_CHOICE_SETCHOICEBOX; inline;
begin
 numvalue := 1;
 FetchParam(WOPP_BOX);
 choicematic.choicebox := numvalue;
end;

procedure Invoke_CHOICE_SETHIGHLIGHTBOX; inline;
begin
 numvalue := 1;
 FetchParam(WOPP_BOX);
 choicematic.highlightbox := numvalue;
end;

procedure Invoke_CHOICE_SETPARTBOX; inline;
begin
 numvalue := 1;
 FetchParam(WOPP_BOX);
 choicematic.choicepartbox := numvalue;
end;

procedure Invoke_DEC; inline;
begin
 if FetchParam(WOPP_VAR) = FALSE then fibererror('Dec without variable name')
 else begin
  if GetVarType(strvalue[0]) = 2 then fibererror('Can''t decrease a string variable')
  else begin
   numvalue := 1;
   FetchParam(WOPP_BY);
   SetNumVar(strvalue[0], GetNumVar(strvalue[0]) - numvalue, FALSE);
  end;
 end;
end;

procedure Invoke_EVENT_CREATE_AREA; inline; begin end;

procedure Invoke_EVENT_CREATE_ESC; inline;
begin
 if FetchParam(WOPP_LABEL) then begin
  if pos('.', strvalue[0]) = 0 then
   strvalue[0] := copy(fiber[fiberid].labelname, 1, pos('.', fiber[fiberid].labelname)) + strvalue[0];
  event.escint.triggerlabel := strvalue[0];
 end;
end;

procedure Invoke_EVENT_CREATE_GOB; inline; begin end;

procedure Invoke_EVENT_CREATE_INT; inline;
begin
 if FetchParam(WOPP_LABEL) then begin
  if pos('.', strvalue[0]) = 0 then
   strvalue[0] := copy(fiber[fiberid].labelname, 1, pos('.', fiber[fiberid].labelname)) + strvalue[0];
  event.normalint.triggerlabel := strvalue[0];
 end;
end;

procedure Invoke_EVENT_CREATE_TIMER; inline;
begin
 if FetchParam(WOPP_NAME) = FALSE then fibererror('Create timer without name')
 else begin
  StashStrval;
  strvalue[0] := '';
  FetchParam(WOPP_LABEL);
  if pos('.', strvalue[0]) = 0 then
   strvalue[0] := copy(fiber[fiberid].labelname, 1, pos('.', fiber[fiberid].labelname)) + strvalue[0];
  numvalue := 1000;
  FetchParam(WOPP_FREQ);
  if numvalue < 0 then fibererror('Create timer freq < 0')
  else begin
   // Save the new timer.
   numvalue2 := length(event.timer);
   setlength(event.timer, numvalue2 + 1);
   with event.timer[numvalue2] do begin
    namu := strvalue2[0];
    triggerfreq := numvalue;
    timercounter := 0;
    triggerlabel := strvalue[0];
   end;
  end;
 end;
end;

procedure Invoke_EVENT_MOUSEOFF; inline; begin end;
procedure Invoke_EVENT_MOUSEON; inline; begin end;

procedure Invoke_EVENT_REMOVE; inline;
var ivar : dword;
begin
 if (FetchParam(WOPP_NAME) = FALSE) or (strvalue[0] = '') then begin
  // Remove all events.
  setlength(event.area, 0);
  setlength(event.gob, 0);
  setlength(event.timer, 0);
  event.normalint.triggerlabel := '';
  event.escint.triggerlabel := '';
 end
 else begin
  // Remove all events by this name.
 end;
end;

procedure Invoke_EVENT_REMOVE_ESC; inline;
begin
 event.escint.triggerlabel := '';
end;

procedure Invoke_EVENT_REMOVE_INT; inline;
begin
 event.normalint.triggerlabel := '';
end;

procedure Invoke_EVENT_SETLABEL; inline;
begin
end;

procedure Invoke_FIBER_GETID; inline;
begin
 PushInt(fiberid);
 PushInt(STACK_TOKEN_NUMBER);
end;

procedure Invoke_FIBER_SIGNAL; inline;
begin
 if FetchParam(WOPP_NAME) then SignalFiber(strvalue[0]) else SignalFiber('');
end;

procedure Invoke_FIBER_START; inline;
begin
 if FetchParam(WOPP_LABEL) = FALSE then fibererror('fiber.start without label name')
 else begin
  if pos('.', strvalue[0]) = 0 then
   strvalue[0] := copy(fiber[fiberid].labelname, 1, pos('.', fiber[fiberid].labelname)) + strvalue[0];
  StashStrval;
  FetchParam(WOPP_NAME);
  StartFiber(strvalue2[0], strvalue[0]);
 end;
end;

procedure Invoke_FIBER_STOP; inline;
begin
 if FetchParam(WOPP_NAME) = FALSE // stop self by default
 then fiber[fiberid].fiberstate := FIBERSTATE_STOPPING
 else StopFiber(strvalue[0]); // or stop all fibers with a matching name
end;

procedure Invoke_FIBER_WAIT; inline;
begin
 numvalue := 0;
 FetchParam(WOPP_TIME);
 // If a time was specified, put the fiber to sleep for so long.
 if numvalue <> 0 then AddSleepEffect(fiberid, numvalue)
 // Otherwise, if this fiber spawned any effects, wait for them to expire.
 // (If no effects are active, then just yield once.)
 else if fiber[fiberid].fxrefcount <> 0
 then fiber[fiberid].fiberstate := FIBERSTATE_WAITFX;
 yieldnow := TRUE;
end;

procedure Invoke_FIBER_WAITKEY; inline;
begin
 numvalue := 0;
 FetchParam(WOPP_NOCLEAR);
 if numvalue = 0
 then fiber[fiberid].fiberstate := FIBERSTATE_WAITCLEAR
 else fiber[fiberid].fiberstate := FIBERSTATE_WAITKEY;
 yieldnow := TRUE;
end;

procedure Invoke_FIBER_WAITSIG; inline;
begin
 fiber[fiberid].fiberstate := FIBERSTATE_WAITSIGNAL;
 yieldnow := TRUE;
end;

procedure Invoke_FIBER_YIELD; inline;
begin
 yieldnow := TRUE;
end;

procedure Invoke_GFX_ADOPT; inline;
begin
 if FetchParam(WOPP_GOB) = FALSE then fibererror('gfx.adopt without gob')
 else begin
  numvalue := GetGob(strvalue[0]);
  if numvalue >= length(gob) then fibererror('gfx.adopt no such gob: ' + strvalue[0])
  else begin
   if FetchParam(WOPP_PARENT) = FALSE then gob[numvalue].parent := $FFFFFFFF
   else begin
    numvalue2 := GetGob(strvalue[0]);
    if numvalue = numvalue2 then fibererror('gfx.adopt gob can''t adopt self')
    else if numvalue2 >= length(gob) then fibererror('gfx.adopt no such parent gob: ' + strvalue[0])
    else if numvalue2 > numvalue then fibererror('gfx.adopt parent must be below kid')
    else if gob[numvalue].inviewport <> gob[numvalue2].inviewport then fibererror('gfx.adopt gobs not in same viewport')
    else gob[numvalue].parent := numvalue2;
   end;
  end;
 end;
end;

procedure Invoke_GFX_BASH; inline; begin end;

procedure Invoke_GFX_CLEARALL; inline;
var ivar : dword;
begin
 // Remove all existing gobs in every viewport on the next transition.
 for ivar := length(gob) - 1 downto 0 do
  gob[ivar].drawstate := (gob[ivar].drawstate and $1F) or $80;
end;

procedure Invoke_GFX_CLEARANIMS; inline;
var ivar : dword;
begin
 // Instantly remove all actively animating gobs in the default viewport.
 for ivar := length(gob) - 1 downto 0 do
  if (IsGobValid(ivar)) and (gob[ivar].animtimer <> $FFFFFFFF)
  and (gob[ivar].inviewport = gamevar.defaultviewport)
  then DeleteGob(ivar);
end;

procedure Invoke_GFX_CLEARBKG; inline;
begin
 // Remove the background in the default viewport on the next transition.
 numvalue := viewport[gamevar.defaultviewport].backgroundgob;
 if IsGobValid(numvalue)
 then gob[numvalue].drawstate := (gob[numvalue].drawstate and $1F) or $80;
end;

procedure Invoke_GFX_CLEARKIDS; inline;
var ivar : dword;
begin
 // Remove all children of the given gob on the next transition.
 numvalue := viewport[gamevar.defaultviewport].backgroundgob;
 if FetchParam(WOPP_GOB) <> FALSE then begin
  numvalue := GetGob(strvalue[0]);
  if numvalue = 0 then fibererror('gfx.clearkids no such gob: ' + strvalue[0]);
 end;
 if IsGobValid(numvalue) = FALSE then exit;

 for ivar := numvalue + 1 to length(gob) - 1 do
  if (IsGobValid(ivar)) and (gob[ivar].parent = dword(numvalue))
  then gob[ivar].drawstate := (gob[ivar].drawstate and $1F) or $80;
end;

procedure Invoke_GFX_FLASH; inline; begin end;

procedure Invoke_GFX_GETFRAME; inline;
begin
 numvalue := viewport[gamevar.defaultviewport].backgroundgob;
 if FetchParam(WOPP_GOB) then numvalue := GetGob(upcase(strvalue[0]));
 if numvalue >= length(gob) then fibererror('gfx.getframe: no such gob: ' + strvalue[0])
 else begin
  PushInt(gob[numvalue].drawframe);
  PushInt(STACK_TOKEN_NUMBER);
 end;
end;

procedure Invoke_GFX_GETSEQUENCE; inline;
begin
 numvalue := viewport[gamevar.defaultviewport].backgroundgob;
 if FetchParam(WOPP_GOB) then numvalue := GetGob(upcase(strvalue[0]));
 if numvalue >= length(gob) then fibererror('gfx.getsequence: no such gob: ' + strvalue[0])
 else begin
  PushInt(gob[numvalue].animseqp);
  PushInt(STACK_TOKEN_NUMBER);
 end;
end;

procedure Invoke_GFX_MOVE; inline; begin end;

procedure Invoke_GFX_PRECACHE; inline;
var x, y : dword;
begin
 if FetchParam(WOPP_GOB) = FALSE then fibererror('gfx.precache without gob')
 else begin
  numvalue := gamevar.defaultviewport;
  FetchParam(WOPP_VIEWPORT);
  if numvalue >= length(viewport) then fibererror('gfx.precache no such viewport: ' + strdec(numvalue))
  else begin
   strvalue[0] := upcase(strvalue[0]);
   numvalue2 := GetPNG(strvalue[0]);
   if numvalue2 = 0 then fibererror('gfx.precache no such graphic: ' + strvalue[0])
   else begin
    x := (PNGlist[numvalue2].origsizexp * viewport[numvalue].viewportsizexp + PNGlist[numvalue2].origresx shr 1) div PNGlist[numvalue2].origresx;
    y := (PNGlist[numvalue2].origframeheightp * viewport[numvalue].viewportsizeyp + PNGlist[numvalue2].origresy shr 1) div PNGlist[numvalue2].origresy;
    if CacheGfx(strvalue[0], x, y, TRUE) = 0 then fibererror('gfx.precache CacheGfx failed');
   end;
  end;
 end;
end;

procedure Invoke_GFX_REMOVE; inline;
var ivar : dword;
begin
 // Delete the named gob on the next transition.
 if FetchParam(WOPP_GOB) = FALSE then fibererror('gfx.remove without gob')
 else begin
  strvalue[0] := upcase(strvalue[0]);
  for ivar := length(gob) - 1 downto 0 do
   if gob[ivar].gobnamu = strvalue[0]
   then gob[ivar].drawstate := (gob[ivar].drawstate and $1F) or $80;
 end;
end;

procedure Invoke_GFX_SETALPHA; inline; begin end;

procedure Invoke_GFX_SETFRAME; inline; begin end;
procedure Invoke_GFX_SETSEQUENCE; inline; begin end;
procedure Invoke_GFX_SETSOLIDBLIT; inline; begin end;

procedure Invoke_GFX_SHOW; inline;
var nam : UTF8string;
    x, y, z : longint;
    gobtype : byte;
begin
 if FetchParam(WOPP_GOB) = FALSE then fibererror('gfx.show without gob') else begin
  nam := strvalue[0];
  gobtype := 3;
  if FetchParam(WOPP_TYPE) <> FALSE then begin
   strvalue[0] := upcase(strvalue[0]);
   if strvalue[0] = 'SLOT' then gobtype := 0 else
   if strvalue[0] = 'BKG' then gobtype := 1 else
   if strvalue[0] = 'SPRITE' then gobtype := 2 else
   if strvalue[0] <> 'ANIM' then fibererror('gfx.show bad gob type: ' + strvalue[0]);
  end;
  strvalue[0] := '';
  FetchParam(WOPP_NAME);

  numvalue := 0; FetchParam(WOPP_LOCX); x := numvalue;
  numvalue := 0; FetchParam(WOPP_LOCY); y := numvalue;
  numvalue := gamevar.defaultviewport; FetchParam(WOPP_VIEWPORT); numvalue2 := numvalue;
  numvalue := 0; FetchParam(WOPP_ZLEVEL); z := numvalue;

  CreateGob(nam, strvalue[0], gobtype, numvalue2, x, y, z);
 end;
end;

procedure Invoke_GFX_TRANSITION; inline;
var ivar, jvar, viewnum, xstyle : dword;
begin
 numvalue := 0; // default: 0 for instant
 FetchParam(WOPP_INDEX);
 xstyle := numvalue;

 numvalue := 768; // defaut: 768 msecs
 FetchParam(WOPP_TIME);
 numvalue2 := numvalue;

 numvalue := gamevar.defaultviewport;
 FetchParam(WOPP_VIEWPORT);
 viewnum := numvalue;

 AddTransitionEffect(fiberid, viewnum, xstyle, numvalue2);

 // Optimise the gob[] array.
 CompressGobList;
 // Tell the graphics cacher that previously visible graphics are probably
 // not needed anymore and may be freed if cache space is low. The renderer
 // call right after this will re-mark still visible graphics as sacred.
 ReleaseGfx;

 for ivar := length(gob) - 1 downto 0 do begin
  case (gob[ivar].drawstate and $E0) of
    // set as new background
    $20: begin
     gob[ivar].zlevel := -$80000000;
     gob[ivar].drawstate := 1;
     jvar := viewport[gob[ivar].inviewport].backgroundgob;
     if ivar <> jvar then begin
      gob[jvar] := gob[ivar];
      gob[ivar].gobnamu := ''; gob[ivar].gfxnamu := '';
      gob[ivar].drawstate := $80;
     end;
    end;
    // make visible after swipe -> draw gob
    $40: gob[ivar].drawstate := gob[ivar].drawstate and $18 or 1;
    // kill after swipe -> delete gob
    $80: DeleteGob(ivar);
    // make invisible after swipe -> hide
    $C0: gob[ivar].drawstate := gob[ivar].drawstate and $1C;
  end;
 end;

 {for ivar := 0 to length(gob) - 1 do begin
  write(' ',ivar:2,':',gob[ivar].gobnamu:11,' parent=');
  if gob[ivar].parent = $FFFFFFFF then write('--') else write(gob[ivar].parent:2);
  writeln(' vp=',gob[ivar].inviewport,' drawstate=$',strhex(gob[ivar].drawstate),' locx=',gob[ivar].locx,' locy=',gob[ivar].locy);
 end;}
end;

procedure Invoke_GOTO; inline;
begin
 if FetchParam(WOPP_LABEL) then ScriptGoto(fiberid, strvalue[0])
 else fibererror('Goto without label name');
end;

procedure Invoke_INC; inline;
begin
 if FetchParam(WOPP_VAR) = FALSE then fibererror('Inc without variable name')
 else begin
  if GetVarType(strvalue[0]) = 2 then fibererror('Can''t increase a string variable')
  else begin
   numvalue := 1;
   FetchParam(WOPP_BY);
   SetNumVar(strvalue[0], GetNumVar(strvalue[0]) + numvalue, FALSE);
  end;
 end;
end;

procedure Invoke_MUS_PLAY; inline; begin end;
procedure Invoke_MUS_STOP; inline; begin end;

procedure Invoke_RETURN; inline;
begin
 ScriptReturn(fiberid);
end;

procedure Invoke_SYS_PAUSE; inline;
begin
 SetPauseState(PAUSESTATE_PAUSED);
 yieldnow := TRUE;
end;

procedure Invoke_SYS_QUIT; inline;
begin
 sysvar.quit := TRUE;
 yieldnow := TRUE;
 fibercount := 0;
end;

procedure Invoke_SYS_SETCURSOR; inline;
begin
 if FetchParam(WOPP_GOB) then log('set cursor to ' + strvalue[0])
 else log('remove cursor override');
end;

procedure Invoke_SYS_SETTITLE; inline;
begin
 if FetchParam(WOPP_TEXT) then SetProgramName(strvalue[0])
 else SetProgramName('');
end;

procedure Invoke_TBOX_CLEAR; inline;
begin
 numvalue := gamevar.defaulttextbox;
 FetchParam(WOPP_BOX);
 if (numvalue < 0) or (numvalue >= length(TBox))
 then fibererror('tboxclear box out of range: ' + strdec(numvalue))
 else ClearTextbox(numvalue);
end;

procedure Invoke_TBOX_DECORATE; inline;
var boxnum, lx, ly, sx, sy, ax, ay : longint;
begin
 numvalue := gamevar.defaulttextbox;
 FetchParam(WOPP_BOX);
 if (numvalue < 0) or (numvalue >= length(TBox))
 then fibererror('decorate box out of range: ' + strdec(numvalue))
 else begin
  boxnum := numvalue;
  if FetchParam(WOPP_GOB) = FALSE then fibererror('decorate box without gob')
  else begin
   numvalue := 0; FetchParam(WOPP_LOCX); lx := numvalue;
   numvalue := 0; FetchParam(WOPP_LOCY); ly := numvalue;
   numvalue := 0; FetchParam(WOPP_SIZEX); sx := numvalue;
   numvalue := 0; FetchParam(WOPP_SIZEY); sy := numvalue;
   numvalue := 0; FetchParam(WOPP_ANCHORX); ax := numvalue;
   numvalue := 0; FetchParam(WOPP_ANCHORY); ay := numvalue;

   numvalue2 := length(TBox[boxnum].style.decorlist);
   setlength(TBox[boxnum].style.decorlist, numvalue2 + 1);
   with TBox[boxnum].style.decorlist[numvalue2] do begin
    decorname := upcase(strvalue[0]);
    decorframeindex := 0; {$note add tbox.setdecorframeindex}
    decoranchorx := ax;
    decoranchory := ay;
    decorlocx := lx;
    decorlocy := ly;
    decorsizex := sx;
    decorsizey := sy;
   end;
   TBox[boxnum].basebufvalid := FALSE; // flag the box for redraw with this
  end;
 end;
end;

procedure Invoke_TBOX_OUTLINE; inline;
var boxnum, color, thickness, lx, ly, alpha : longint;
begin
 numvalue := gamevar.defaulttextbox;
 FetchParam(WOPP_BOX);
 if (numvalue < 0) or (numvalue >= length(TBox))
 then fibererror('outline box out of range: ' + strdec(numvalue))
 else begin
  boxnum := numvalue;
  numvalue := $000F; FetchParam(WOPP_COLOR); color := numvalue;
  if color < 0 then fibererror('outline color < 0')
  else if color > $FFFF then fibererror('outline color > $FFFF')
  else begin
   dword(color) := ExpandColorRef(color);
   numvalue := 256; FetchParam(WOPP_THICKNESS); thickness := numvalue;
   numvalue := 0; FetchParam(WOPP_LOCX); lx := numvalue;
   numvalue := 0; FetchParam(WOPP_LOCY); ly := numvalue;
   numvalue := 0; FetchParam(WOPP_ALPHA); alpha := numvalue;
   numvalue2 := length(TBox[boxnum].style.outline);
   setlength(TBox[boxnum].style.outline, numvalue2 + 1);
   with TBox[boxnum].style.outline[numvalue2] do begin
    dword(outlinecolor) := dword(color);
    thickness := abs(thickness);
    ofsx := lx;
    ofsy := ly;
    alphafade := alpha <> 0;
   end;
   TBox[boxnum].contentbufparamvalid := FALSE; // flag the box for redraw
  end;
 end;
end;

procedure nestedprint(inbox : dword);
var ivar : dword;
begin
 // Print in designated box, in the box's preferred language.
 ivar := TBox[inbox].boxlanguage;
 if (ivar < dword(length(strvalue))) and (strvalue[ivar] <> '')
 then PrintBox(inbox, strvalue[ivar])
 else PrintBox(inbox, strvalue[0]);
 // Print in export target boxes, in their preferred languages.
 ivar := TBox[inbox].exportcontentto;
 if (ivar > 0) and (ivar < dword(length(TBox))) then nestedprint(ivar);
end;

procedure Invoke_TBOX_PRINT; inline;
begin
 numvalue := gamevar.defaulttextbox;
 FetchParam(WOPP_BOX);
 if numvalue >= length(TBox) then InitTextbox(numvalue);
 if FetchParam(WOPP_TEXT) then nestedprint(numvalue);
end;

procedure Invoke_TBOX_REMOVEDECOR; inline;
begin
 numvalue := gamevar.defaulttextbox;
 FetchParam(WOPP_BOX);
 if (numvalue < 0) or (numvalue >= length(TBox))
 then fibererror('removedecor box out of range: ' + strdec(numvalue))
 else begin
  strvalue[0] := '';
  FetchParam(WOPP_GOB);
  RemoveBoxDecoration(numvalue, strvalue[0]);
 end;
end;

procedure Invoke_TBOX_REMOVEOUTLINES; inline;
begin
 numvalue := gamevar.defaulttextbox;
 FetchParam(WOPP_BOX);
 if (numvalue < 0) or (numvalue >= length(TBox))
 then fibererror('removeoutlines box out of range: ' + strdec(numvalue))
 else begin
  setlength(TBox[numvalue].style.outline, 0);
  TBox[numvalue].contentbufparamvalid := FALSE; // mark the box for redraw
 end;
end;

procedure Invoke_TBOX_SETDEFAULT; inline;
begin
 numvalue := 1;
 FetchParam(WOPP_BOX);
 if numvalue <= 0 then fibererror('Bad default tbox: ' + strdec(numvalue))
 else begin
  gamevar.defaulttextbox := numvalue;
  if numvalue > length(TBox) then InitTextbox(numvalue);
 end;
end;

procedure Invoke_TBOX_SETLOC; inline;
var boxnum, newx, newy, ankhx, ankhy, time : longint;
begin
 numvalue := gamevar.defaulttextbox;
 FetchParam(WOPP_BOX);
 boxnum := numvalue;
 if (boxnum < 0) or (boxnum >= length(TBox))
 then fibererror('setloc box out of range: ' + strdec(boxnum))
 else begin
  newx := TBox[boxnum].boxlocx;
  newy := TBox[boxnum].boxlocy;
  ankhx := TBox[boxnum].anchorx;
  ankhy := TBox[boxnum].anchory;
  if FetchParam(WOPP_LOCX) then newx := numvalue;
  if FetchParam(WOPP_LOCY) then newy := numvalue;
  if FetchParam(WOPP_ANCHORX) then ankhx := numvalue;
  if FetchParam(WOPP_ANCHORY) then ankhy := numvalue;
  numvalue := 0;
  FetchParam(WOPP_TIME);
  time := numvalue;
  if time < 0 then time := 0;
  strvalue[0] := '';
  FetchParam(WOPP_STYLE);
  numvalue2 := MOVETYPE_INSTANT;
  case lowercase(strvalue[0]) of
    'linear': numvalue2 := MOVETYPE_LINEAR;
    'cosine','coscos','cos': numvalue2 := MOVETYPE_COSCOS;
    'halfcos': numvalue2 := MOVETYPE_HALFCOS;
    else numvalue2 := MOVETYPE_INSTANT;
  end;
  AddBoxMoveEffect(boxnum, fiberid, newx, newy, ankhx, ankhy, time, numvalue2);
 end;
end;

procedure Invoke_TBOX_SETNUMBOXES; inline;
begin
 numvalue := 3;
 FetchParam(WOPP_INDEX);
 if numvalue < 3 then numvalue := 3; // minimum is 3
 log('setnumboxes=' + strdec(numvalue));
 if numvalue < length(TBox) then DestroyTextbox(numvalue)
 else if numvalue > length(TBox) then InitTextbox(numvalue);
end;

procedure Invoke_TBOX_SETPARAM; inline;
begin
 numvalue := 1;
 FetchParam(WOPP_BOX);
 if numvalue > length(TBox) then InitTextbox(numvalue);
 if numvalue < 0 then fibererror('Can''t setparam box: ' + strdec(numvalue))
 else begin
  numvalue2 := numvalue;
  if FetchParam(WOPP_NAME) = FALSE then fibererror('tbox.setparam without param name')
  else if FetchParam(WOPP_VALUE) then SetBoxParam(numvalue2, strvalue[0], numvalue, TRUE)
  else SetBoxParam(numvalue2, strvalue[0], 0, FALSE);
 end;
end;

procedure Invoke_TBOX_SETSIZE; inline;
var boxnum, newx, newy, time : longint;
begin
 numvalue := gamevar.defaulttextbox;
 FetchParam(WOPP_BOX);
 boxnum := numvalue;
 if (boxnum < 0) or (boxnum >= length(TBox))
 then fibererror('setsize box out of range: ' + strdec(boxnum))
 else begin
  if FetchParam(WOPP_SIZEX) then newx := numvalue
  else newx := (TBox[boxnum].contentwinsizexp shl 15 + viewport[TBox[boxnum].inviewport].viewportsizexp shr 1) div viewport[TBox[boxnum].inviewport].viewportsizexp;
  if FetchParam(WOPP_SIZEY) then newy := numvalue
  else newy := (TBox[boxnum].contentwinsizeyp shl 15 + viewport[TBox[boxnum].inviewport].viewportsizeyp shr 1) div viewport[TBox[boxnum].inviewport].viewportsizeyp;
  numvalue := 0;
  FetchParam(WOPP_TIME);
  time := numvalue;
  if time < 0 then time := 0;
  strvalue[0] := '';
  FetchParam(WOPP_STYLE);
  numvalue2 := MOVETYPE_INSTANT;
  case lowercase(strvalue[0]) of
    'linear': numvalue2 := MOVETYPE_LINEAR;
    'cosine','coscos','cos': numvalue2 := MOVETYPE_COSCOS;
    'halfcos': numvalue2 := MOVETYPE_HALFCOS;
  end;
  AddBoxSizeEffect(boxnum, fiberid, newx, newy, time, numvalue2);
 end;
end;

procedure Invoke_TBOX_SETTEXTURE; inline;
begin
 numvalue := gamevar.defaulttextbox;
 FetchParam(WOPP_BOX);
 numvalue2 := numvalue;
 if (numvalue2 < 0) or (numvalue2 >= length(TBox))
 then fibererror('settexture box out of range: ' + strdec(numvalue2))
 else begin
  TBox[numvalue2].style.texturename := '';
  TBox[numvalue2].style.texturetype := 1; // stretched
  TBox[numvalue2].style.textureblendmode := BLENDMODE_NORMAL;

  if FetchParam(WOPP_GOB) then TBox[numvalue2].style.texturename := strvalue[0];
  if TBox[numvalue2].style.texturename = ''
  then TBox[numvalue2].style.texturetype := 0;
  if (FetchParam(WOPP_TYPE)) and (lowercase(strvalue[0]) = 'tiled')
  then TBox[numvalue2].style.texturetype := 2;
  if (FetchParam(WOPP_STYLE)) and (lowercase(strvalue[0]) = 'hardlight')
  then TBox[numvalue2].style.textureblendmode := BLENDMODE_HARDLIGHT;

  numvalue := 0;
  FetchParam(WOPP_FRAME);
  if numvalue < 0 then numvalue := 0;
  TBox[numvalue2].style.textureframeindex := numvalue;
  TBox[numvalue2].basebufvalid := FALSE;
 end;
end;

procedure Invoke_VIEWPORT_SETBKGINDEX; inline;
begin
 numvalue := 0;
 FetchParam(WOPP_INDEX);
 numvalue2 := numvalue;
 numvalue := 0;
 FetchParam(WOPP_VIEWPORT);
 if numvalue >= length(viewport) then fibererror('gfx.setbkgindex viewport ' + strdec(numvalue) + ' out of range')
 else viewport[numvalue].backgroundgob := numvalue2;
end;

procedure Invoke_VIEWPORT_SETDEFAULT; inline;
begin
 numvalue := 0;
 FetchParam(WOPP_VIEWPORT);
 gamevar.defaultviewport := numvalue;
end;

procedure Invoke_VIEWPORT_SETGAMMA; inline; begin end;

procedure Invoke_VIEWPORT_SETPARAMS; inline;
var viewnum : longint;
begin
 numvalue := 1;
 FetchParam(WOPP_VIEWPORT);
 viewnum := numvalue;
 if viewnum = 0 then fibererror('can''t set params on viewport 0')
 else begin
  if viewnum >= length(viewport) then InitViewport(viewnum);
  if FetchParam(WOPP_PARENT) then begin
   if (length(strvalue[0]) > 2) and (strvalue[0][1] = '0') and (byte(strvalue[0][2]) or $20 = byte('x'))
   then numvalue := valhex(copy(strvalue[0], 3, length(strvalue[0])))
   else numvalue := valx(strvalue[0]);
   if numvalue >= viewnum then fibererror('can''t set viewport ' + strdec(viewnum) + ' parent >= itself')
   else viewport[viewnum].viewportparent := numvalue;
  end;
  if FetchParam(WOPP_LOCX) then begin
   inc(viewport[viewnum].viewportx2, numvalue - viewport[viewnum].viewportx1);
   viewport[viewnum].viewportx1 := numvalue;
  end;
  if FetchParam(WOPP_LOCY) then begin
   inc(viewport[viewnum].viewporty2, numvalue - viewport[viewnum].viewporty1);
   viewport[viewnum].viewporty1 := numvalue;
  end;
  if FetchParam(WOPP_SIZEX) then viewport[viewnum].viewportx2 := viewport[viewnum].viewportx1 + numvalue;
  if FetchParam(WOPP_SIZEY) then viewport[viewnum].viewporty2 := viewport[viewnum].viewporty1 + numvalue;
  if FetchParam(WOPP_RATIOX) then viewport[viewnum].viewportratiox := numvalue;
  if FetchParam(WOPP_RATIOY) then viewport[viewnum].viewportratioy := numvalue;
  UpdateViewport(viewnum);
 end;
end;

// ------------------------------------------------------------------

procedure InvokeWordOfPower(woptoken : byte);
begin
 case woptoken of
   WOP_NOP:;

   WOP_CALL: Invoke_CALL;
   WOP_CASECALL: Invoke_CASECALL;
   WOP_CASEGOTO: Invoke_CASEGOTO;

   WOP_CHOICE_CALL: Invoke_CHOICE_CALL;
   WOP_CHOICE_CANCEL: Invoke_CHOICE_CANCEL;
   WOP_CHOICE_COLUMNS: Invoke_CHOICE_COLUMNS;
   WOP_CHOICE_GET: Invoke_CHOICE_GET;
   WOP_CHOICE_GOTO: Invoke_CHOICE_GOTO;
   WOP_CHOICE_OFF: Invoke_CHOICE_OFF;
   WOP_CHOICE_ON: Invoke_CHOICE_ON;
   WOP_CHOICE_PRINTPARENT: Invoke_CHOICE_PRINTPARENT;
   WOP_CHOICE_REMOVE: Invoke_CHOICE_REMOVE;
   WOP_CHOICE_RESET: Invoke_CHOICE_RESET;
   WOP_CHOICE_SET: Invoke_CHOICE_SET;
   WOP_CHOICE_SETCHOICEBOX: Invoke_CHOICE_SETCHOICEBOX;
   WOP_CHOICE_SETHIGHLIGHTBOX: Invoke_CHOICE_SETHIGHLIGHTBOX;
   WOP_CHOICE_SETPARTBOX: Invoke_CHOICE_SETPARTBOX;

   WOP_DEC: Invoke_DEC;

   WOP_EVENT_CREATE_AREA: Invoke_EVENT_CREATE_AREA;
   WOP_EVENT_CREATE_ESC: Invoke_EVENT_CREATE_ESC;
   WOP_EVENT_CREATE_GOB: Invoke_EVENT_CREATE_GOB;
   WOP_EVENT_CREATE_INT: Invoke_EVENT_CREATE_INT;
   WOP_EVENT_CREATE_TIMER: Invoke_EVENT_CREATE_TIMER;
   WOP_EVENT_MOUSEOFF: Invoke_EVENT_MOUSEOFF;
   WOP_EVENT_MOUSEON: Invoke_EVENT_MOUSEON;
   WOP_EVENT_REMOVE: Invoke_EVENT_REMOVE;
   WOP_EVENT_REMOVE_ESC: Invoke_EVENT_REMOVE_ESC;
   WOP_EVENT_REMOVE_INT: Invoke_EVENT_REMOVE_INT;
   WOP_EVENT_SETLABEL: Invoke_EVENT_SETLABEL;

   WOP_FIBER_GETID: Invoke_FIBER_GETID;
   WOP_FIBER_SIGNAL: Invoke_FIBER_SIGNAL;
   WOP_FIBER_START: Invoke_FIBER_START;
   WOP_FIBER_STOP: Invoke_FIBER_STOP;
   WOP_FIBER_WAIT: Invoke_FIBER_WAIT;
   WOP_FIBER_WAITKEY: Invoke_FIBER_WAITKEY;
   WOP_FIBER_WAITSIG: Invoke_FIBER_WAITSIG;
   WOP_FIBER_YIELD: Invoke_FIBER_YIELD;

   WOP_GFX_ADOPT: Invoke_GFX_ADOPT;
   WOP_GFX_BASH: Invoke_GFX_BASH;
   WOP_GFX_CLEARALL: Invoke_GFX_CLEARALL;
   WOP_GFX_CLEARANIMS: Invoke_GFX_CLEARANIMS;
   WOP_GFX_CLEARBKG: Invoke_GFX_CLEARBKG;
   WOP_GFX_CLEARKIDS: Invoke_GFX_CLEARKIDS;
   WOP_GFX_FLASH: Invoke_GFX_FLASH;
   WOP_GFX_GETFRAME: Invoke_GFX_GETFRAME;
   WOP_GFX_GETSEQUENCE: Invoke_GFX_GETSEQUENCE;
   WOP_GFX_MOVE: Invoke_GFX_MOVE;
   WOP_GFX_PRECACHE: Invoke_GFX_PRECACHE;
   WOP_GFX_REMOVE: Invoke_GFX_REMOVE;
   WOP_GFX_SETALPHA: Invoke_GFX_SETALPHA;
   WOP_GFX_SETFRAME: Invoke_GFX_SETFRAME;
   WOP_GFX_SETSEQUENCE: Invoke_GFX_SETSEQUENCE;
   WOP_GFX_SETSOLIDBLIT: Invoke_GFX_SETSOLIDBLIT;
   WOP_GFX_SHOW: Invoke_GFX_SHOW;
   WOP_GFX_TRANSITION: Invoke_GFX_TRANSITION;

   WOP_GOTO: Invoke_GOTO;
   WOP_INC: Invoke_INC;
   WOP_RETURN: Invoke_RETURN;

   WOP_SYS_PAUSE: Invoke_SYS_PAUSE;
   WOP_SYS_QUIT: Invoke_SYS_QUIT;
   WOP_SYS_SETCURSOR: Invoke_SYS_SETCURSOR;
   WOP_SYS_SETTITLE: Invoke_SYS_SETTITLE;

   WOP_TBOX_CLEAR: Invoke_TBOX_CLEAR;
   WOP_TBOX_DECORATE: Invoke_TBOX_DECORATE;
   WOP_TBOX_OUTLINE: Invoke_TBOX_OUTLINE;
   WOP_TBOX_PRINT: Invoke_TBOX_PRINT;
   WOP_TBOX_REMOVEDECOR: Invoke_TBOX_REMOVEDECOR;
   WOP_TBOX_REMOVEOUTLINES: Invoke_TBOX_REMOVEOUTLINES;
   WOP_TBOX_SETDEFAULT: Invoke_TBOX_SETDEFAULT;
   WOP_TBOX_SETLOC: Invoke_TBOX_SETLOC;
   WOP_TBOX_SETNUMBOXES: Invoke_TBOX_SETNUMBOXES;
   WOP_TBOX_SETPARAM: Invoke_TBOX_SETPARAM;
   WOP_TBOX_SETSIZE: Invoke_TBOX_SETSIZE;
   WOP_TBOX_SETTEXTURE: Invoke_TBOX_SETTEXTURE;

   WOP_VIEWPORT_SETBKGINDEX: Invoke_VIEWPORT_SETBKGINDEX;
   WOP_VIEWPORT_SETDEFAULT: Invoke_VIEWPORT_SETDEFAULT;
   WOP_VIEWPORT_SETGAMMA: Invoke_VIEWPORT_SETGAMMA;
   WOP_VIEWPORT_SETPARAMS: Invoke_VIEWPORT_SETPARAMS;

   else begin
    fibererror('Bad wop token: ' + strdec(woptoken)); exit;
   end;
 end;
end;

 {$ifdef bonk}
  case comm of
   // 17 = fx.movegob [name] [tox, toy] [duration] [style]
   17: begin
        namutxt := upcase(StripEscapes(ReadString));
        data2 := Evaluate; // tox
        data3 := Evaluate; // toy
        data4 := Evaluate; // duration
        if data4 < 0 then data4 := 0;
        data := byte((script[scr^.curnum].code + scr^.ofs)^); // style
        inc(scr^.ofs);
        // find all gobs of given name, move them
        ivar := length(gob);
        while ivar <> 0 do begin
         dec(ivar);
         if (IsGobValid(ivar)) and (gob[ivar].gobnamu = namutxt)
         then addMoveEffect(ivar, data2, data3, data4, data);
        end;
       end;
   // 42 = gfx.solidblit [gob name] [color variable]
   42: begin
        txt := upcase(StripEscapes(ReadString));
        data := dword(Evaluate);
        for ivar := high(gob) downto 0 do
         if (IsGobValid(ivar)) and (gob[ivar].gobnamu = txt) then
          AddSolidBlitEffect(ivar, data);
       end;
   // 45 = gfx.setsequence [gob name] [value]
   // 46 = gfx.setframe [gob name] [value]
   45,46: begin
        txt := upcase(StripEscapes(ReadString));
        accu := Evaluate;
        for ivar := high(gob) downto 0 do
         if (IsGobValid(ivar)) and (gob[ivar].gobnamu = txt)
         then begin
          if comm = 45 then begin
           jvar := GetPNG(@gob[ivar].gfxnamu);
           if jvar = 0 then begin
            log('[!] gfx.setsequence/setframe: ' + gob[ivar].gfxnamu + ' not found');
            continue;
           end;
           if PNGlist[jvar].seqlen = 0 then begin
            log('[!] gfx.setsequence/setframe: ' + gob[ivar].gfxnamu + ' has no frames');
            continue;
           end;
           while accu < 0 do inc(accu, PNGlist[jvar].seqlen);
           // set the frame to one before the requested
           if accu = 0 then gob[ivar].animseqp := PNGlist[jvar].seqlen - 1
           else gob[ivar].animseqp := accu - 1;
           // set time until the next frame to 0 to switch frames correctly
           gob[ivar].animtimer := 0;
          end else begin
           gob[ivar].drawframe := accu;
           // if gob is visible, set it to get redrawn
           if gob[ivar].drawstate and 2 <> 0 then gob[ivar].drawstate := gob[ivar].drawstate or 1;
          end;
         end;
       end;

   // ======= EVENT COMMANDS =======
   // 170 = event.create.area [event name] [coords] [viewport] [jump address]
   170: begin
         ivar := length(event.area);
         setlength(event.area, ivar + 1);
         with event.area[ivar] do begin
          namu := upcase(StripEscapes(ReadString));
          x1 := Evaluate;
          y1 := Evaluate;
          x2 := Evaluate;
          y2 := Evaluate;
          state := 0; // 0 = not overed, 1 = overed
          inviewport := byte(Evaluate);
          triggergoto := dword((script[scr^.curnum].code + scr^.ofs)^);
          inc(scr^.ofs, 4);
          mouseongoto := 0; mouseoffgoto := 0;
         end;

         if event.area[ivar].inviewport >= length(viewport) then begin
          log('[!] event.create.area: invalid viewport ' + strdec(event.area[ivar].inviewport));
          setlength(event.area, ivar);
         end else
         with event.area[ivar] do begin
          // locxp = locx * viewportsizexp / 32768 + viewportx1p
          if x1 < 0
          then x1p := (x1 * viewport[inviewport].viewportsizexp - 16384) div 32768 + viewport[inviewport].viewportx1p
          else x1p := (x1 * viewport[inviewport].viewportsizexp + 16384) shr 15 + viewport[inviewport].viewportx1p;
          if x2 < 0
          then x2p := (x2 * viewport[inviewport].viewportsizexp - 16384) div 32768 + viewport[inviewport].viewportx1p
          else x2p := (x2 * viewport[inviewport].viewportsizexp + 16384) shr 15 + viewport[inviewport].viewportx1p;
          if y1 < 0
          then y1p := (y1 * viewport[inviewport].viewportsizeyp - 16384) div 32768 + viewport[inviewport].viewporty1p
          else y1p := (y1 * viewport[inviewport].viewportsizeyp + 16384) shr 15 + viewport[inviewport].viewporty1p;
          if y2 < 0
          then y2p := (y2 * viewport[inviewport].viewportsizeyp - 16384) div 32768 + viewport[inviewport].viewporty1p
          else y2p := (y2 * viewport[inviewport].viewportsizeyp + 16384) shr 15 + viewport[inviewport].viewporty1p;
         end;
         // check if current mouse location applies
         gamevar.mousecheck := 1;
        end;
   // 171 = event.create.gob [event name] [gob name] [jump address]
   171: begin
         ivar := length(event.gob);
         setlength(event.gob, ivar + 1);
         event.gob[ivar].namu := upcase(StripEscapes(ReadString));
         event.gob[ivar].state := 0; // 0 = not overed, 1 = overed
         txt := upcase(StripEscapes(ReadString));
         for data := high(gob) downto 0 do
          if (IsGobValid(data)) and (gob[data].gobnamu = txt)
          then event.gob[ivar].gobnum := data;
         event.gob[ivar].triggergoto := dword((script[scr^.curnum].code + scr^.ofs)^);
         inc(scr^.ofs, 4);
         event.gob[ivar].mouseongoto := 0;
         event.gob[ivar].mouseoffgoto := 0;
         // check if current mouse location applies
         gamevar.mousecheck := 1;
        end;
   // 175 = event.mouseon [event name] [jump address]
   // 176 = event.mouseoff [event name] [jump address]
   175,176: begin
        txt := upcase(StripEscapes(ReadString));
        data := dword((script[scr^.curnum].code + scr^.ofs)^);
        inc(scr^.ofs, 4);

        ivar := length(event.area);
        while ivar <> 0 do begin
         dec(ivar);
         if event.area[ivar].namu = txt then begin
          if comm = 175 then event.area[ivar].mouseongoto := data
          else event.area[ivar].mouseoffgoto := data;
         end;
        end;

        ivar := length(event.gob);
        while ivar <> 0 do begin
         dec(ivar);
         if event.gob[ivar].namu = txt then begin
          if comm = 175 then event.gob[ivar].mouseongoto := data
          else event.gob[ivar].mouseoffgoto := data;
         end;
        end;

        // check if current mouse location applies
        gamevar.mousecheck := 1;
       end;
{$endif}
