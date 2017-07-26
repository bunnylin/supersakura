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

function PollKey(keyval : byte) : longint;
// Returns non-zero if the given key is held down, or 0 if it is not.
// Checks cursor keys first, then gamepad direction buttons, then gamepad
// left stick. On the console port, only checks the cursor keys.
// The non-zero return value will be 32767 for digital buttons, and in the
// range 1..32768 for the analog left stick.
begin
 PollKey := 0;

 {$ifdef sakucon}
 if sysvar.keysdown and keyval <> 0 then PollKey := 32767;
 {$else}

 case keyval of
   KEYVAL_DOWN: begin
    if (byte((mv_PKeystate + SDL_SCANCODE_DOWN)^) <> 0)
    or (mv_GamepadH <> NIL)
    and (SDL_GameControllerGetButton(mv_GamepadH, SDL_CONTROLLER_BUTTON_DPAD_DOWN) <> 0)
    then PollKey := 32767
    else begin
     PollKey := SDL_GameControllerGetAxis(mv_GamepadH, SDL_CONTROLLER_AXIS_LEFTY);
     if PollKey < sysvar.ctrldeadzone then PollKey := 0;
    end;
   end;

   KEYVAL_UP: begin
    if (byte((mv_PKeystate + SDL_SCANCODE_UP)^) <> 0)
    or (mv_GamepadH <> NIL)
    and (SDL_GameControllerGetButton(mv_GamepadH, SDL_CONTROLLER_BUTTON_DPAD_UP) <> 0)
    then PollKey := 32767
    else begin
     PollKey := -SDL_GameControllerGetAxis(mv_GamepadH, SDL_CONTROLLER_AXIS_LEFTY);
     if PollKey < sysvar.ctrldeadzone then PollKey := 0;
    end;
   end;

   KEYVAL_LEFT: begin
    if (byte((mv_PKeystate + SDL_SCANCODE_LEFT)^) <> 0)
    or (mv_GamepadH <> NIL)
    and (SDL_GameControllerGetButton(mv_GamepadH, SDL_CONTROLLER_BUTTON_DPAD_LEFT) <> 0)
    then PollKey := 32767
    else begin
     PollKey := -SDL_GameControllerGetAxis(mv_GamepadH, SDL_CONTROLLER_AXIS_LEFTX);
     if PollKey < sysvar.ctrldeadzone then PollKey := 0;
    end;
   end;

   KEYVAL_RIGHT: begin
    if (byte((mv_PKeystate + SDL_SCANCODE_RIGHT)^) <> 0)
    or (mv_GamepadH <> NIL)
    and (SDL_GameControllerGetButton(mv_GamepadH, SDL_CONTROLLER_BUTTON_DPAD_RIGHT) <> 0)
    then PollKey := 32767
    else begin
     PollKey := SDL_GameControllerGetAxis(mv_GamepadH, SDL_CONTROLLER_AXIS_LEFTX);
     if PollKey < sysvar.ctrldeadzone then PollKey := 0;
    end;
   end;
 end;

 {$endif}
end;

// SuperSakura user input

procedure UserInput_CtrlB; inline;
begin
 HideBoxes(sysvar.hideboxes = 0);
end;

procedure UserInput_CtrlD;
// Toggles the dropdown console in debug mode.
begin
 // User must type Ctrl-XYZZY to allow debug mode.
 if sysvar.debugallowed < 5 then exit;

 // If boxes hidden, show them, and don't stop at this step.
 if sysvar.hideboxes <> 0 then HideBoxes(FALSE);

 // If box 0 already displayed and not in transcript mode, remove the box.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT)
 and (sysvar.transcriptmode = FALSE)
 then begin
  dec(gamevar.activetextinput);
  {$ifndef sakucon}
  if gamevar.activetextinput = 0 then SDL_StopTextInput;
  {$endif}
  Box0SlideUp;
  exit;
 end;

 // If transcript mode is on, delete the user input portion in the box.
 if sysvar.transcriptmode then TBox[0].userinputlen := 0;

 // Turn off transcript mode and slide in the box.
 sysvar.transcriptmode := FALSE;
 TBox[0].caretpos := TBox[0].userinputlen;
 Box0SlideDown;
 PrintDebugBuffer;
 {$ifndef sakucon}
 if gamevar.activetextinput = 0 then SDL_StartTextInput;
 {$endif}
 inc(gamevar.activetextinput);
end;

procedure UserInput_CtrlT;
// Toggles the dropdown console in transcript mode.
begin
 // If not in normal metastate, ignore it.
 if metastate <> METASTATE_NORMAL then exit;

 // If skip seen text mode is enabled, disable it.

 // If boxes hidden, show them, and don't stop at this step.
 if sysvar.hideboxes <> 0 then HideBoxes(FALSE);

 // If box 0 already displayed and in transcript mode, remove the box.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode)
 then begin
  Box0SlideUp;
  exit;
 end;

 // If transcript mode is off, we're leaving debug mode...
 if sysvar.transcriptmode = FALSE then begin
  TBox[0].caretpos := -1;
  TBox[0].userinputlen := 0;
  dec(gamevar.activetextinput);
  {$ifndef sakucon}
  if gamevar.activetextinput = 0 then SDL_StopTextInput;
  {$endif}
 end;

 // Enable transcript mode and slide in the box.
 sysvar.transcriptmode := TRUE;
 Box0SlideDown;
 PrintTranscriptBuffer;
end;

// ------------------------------------------------------------------

procedure UserInput_Mouse(musx, musy : longint; button : byte);
// The coordinates are a pixel value from the game window's top left.
// The button is 0 if this is just the mouse moving around; 1 if it's
// a left-click and 3 if it's a right-click.
var ivar, jvar : dword;
    x, y : longint;
    overnewarea, overnewgob : boolean;
begin
 sysvar.mousex := musx;
 sysvar.mousey := musy;

 // Check if mouseovering choices in an active choicebox.
 if choicematic.active then with TBox[choicematic.choicebox] do begin
  if (musx >= boxlocxp_r) and (musx < boxlocxp_r + longint(boxsizexp_r))
  and (musy >= boxlocyp_r) and (musy < boxlocyp_r + longint(boxsizeyp_r))
  then begin
   // Calculate the cursor's location relative to the full content buffer.
   x := musx - boxlocxp_r;
   y := musy - boxlocyp_r + longint(contentwinscrollofsp);
   // Check if the cursor is over any choice rect.
   ivar := choicematic.showcount;
   while ivar <> 0 do begin
    dec(ivar);
    if (ivar <> choicematic.highlightindex)
    and (x >= longint(choicematic.showlist[ivar].slx1p))
    and (x < longint(choicematic.showlist[ivar].slx2p))
    and (y >= longint(choicematic.showlist[ivar].sly1p))
    and (y < longint(choicematic.showlist[ivar].sly2p))
    then begin
     choicematic.highlightindex := ivar;
     HighlightChoice(MOVETYPE_HALFCOS);
     break;
    end;
   end;
  end;
 end;

 // Check mouseoverable areas.
 overnewarea := FALSE;
 if length(event.area) <> 0 then
  for ivar := length(event.area) - 1 downto 0 do
   with event.area[ivar] do begin
    if (musx >= x1p) and (musx < x2p)
    and (musy >= y1p) and (musy < y2p)
    then begin
     // Area is being overed!
     if state = 0 then begin
      // It wasn't overed before, so prepare to trigger mouseon.
      state := 1;
      if mouseonlabel <> '' then begin
       overnewarea := TRUE;
       state := 2;
      end;
     end;
    end else begin
     // Area is not being overed!
     if state <> 0 then begin
      // It was overed before, so trigger mouseoff.
      state := 0;
      if mouseofflabel <> '' then StartFiber(mouseofflabel, '');
     end;
    end;
   end;

 // Check mouseoverable gobs.
 overnewgob := FALSE;
 ivar := length(event.gob);
 while ivar <> 0 do begin
  dec(ivar);

  with gob[event.gob[ivar].gobnum] do begin
   // Check if the cursor is over the gob.
   if (musx >= locxp) and (musx < locxp + longint(sizexp))
   and (musy >= locyp) and (musy < locyp + longint(sizeyp))
   then begin
    // Gob is being overed!
    if event.gob[ivar].state = 0 then begin
     // It wasn't overed before, so prepare to trigger mouseon.
     event.gob[ivar].state := 1;
     if event.gob[ivar].mouseonlabel <> '' then begin
      overnewgob := TRUE;
      event.gob[ivar].state := 2;
     end;
    end;
   end else begin
    // Gob is not being overed!
    if event.gob[ivar].state <> 0 then begin
     // It was overed before, so trigger mouseoff.
     event.gob[ivar].state := 0;
     if event.gob[ivar].mouseofflabel <> '' then StartFiber(event.gob[ivar].mouseofflabel, '');
    end;
   end;
  end;
 end;

 // Trigger mouseon labels.
 if overnewarea then for ivar := 0 to high(event.area) do
  if event.area[ivar].state = 2 then begin
   event.area[ivar].state := 1;
   StartFiber(event.area[ivar].mouseonlabel, '');
  end;
 if overnewgob then for ivar := 0 to high(event.gob) do
  if event.gob[ivar].state = 2 then begin
   event.gob[ivar].state := 1;
   StartFiber(event.gob[ivar].mouseonlabel, '');
  end;

 // Handle mouse clicks...

 // Left-click!
 if button = 1 then begin

  // If textboxes are hidden, make them visible.
  if sysvar.hideboxes and 1 <> 0 then begin
   HideBoxes(FALSE);
   exit;
  end;

  // If clicking over a choice rectangle in the choice box, select the
  // currently highlighted choice.
  if choicematic.active then with TBox[choicematic.choicebox] do
   if (musx >= boxlocxp_r) and (musx < boxlocxp_r + longint(boxsizexp_r))
   and (musy >= boxlocyp_r) and (musy < boxlocyp_r + longint(boxsizeyp_r))
   then begin
    // Calculate the cursor's location relative to the full content buffer.
    x := musx - boxlocxp_r;
    y := musy - boxlocyp_r + longint(contentwinscrollofsp);
    // Check if the cursor is over the highlighted choice.
    if (x >= longint(choicematic.showlist[choicematic.highlightindex].slx1p))
    and (x < longint(choicematic.showlist[choicematic.highlightindex].slx2p))
    and (y >= longint(choicematic.showlist[choicematic.highlightindex].sly1p))
    and (y < longint(choicematic.showlist[choicematic.highlightindex].sly2p))
    then begin
     SelectChoice(choicematic.highlightindex);
     exit;
    end;
   end;

  // If clicking over any box, page boxes ahead and resume waitkeys.
  for ivar := high(TBox) downto 0 do
   if TBox[ivar].boxstate <> BOXSTATE_NULL then
    with TBox[ivar] do
     if (musx >= boxlocxp_r) and (musx < boxlocxp_r + longint(boxsizexp_r))
     and (musy >= boxlocyp_r) and (musy < boxlocyp_r + longint(boxsizeyp_r))
     then begin
      if CheckPageableBoxes then exit;
      ClearWaitKey;
      exit;
     end;

  // If over any mouseoverable gob or area, trigger them.
  jvar := 0;
  ivar := length(event.gob);
  while ivar <> 0 do begin
   dec(ivar);
   if (event.gob[ivar].state <> 0) and (event.gob[ivar].triggerlabel <> '')
   then begin
    StartFiber(event.gob[ivar].triggerlabel, '');
    inc(jvar);
   end;
  end;
  ivar := length(event.area);
  while ivar <> 0 do begin
   dec(ivar);
   if (event.area[ivar].state <> 0) and (event.area[ivar].triggerlabel <> '')
   then begin
    StartFiber(event.area[ivar].triggerlabel, '');
    inc(jvar);
   end;
  end;
  if jvar <> 0 then exit;

  // Page boxes ahead and resume waitkeys, even if not clicking a box.
  if CheckPageableBoxes then exit;
  if ClearWaitKey then exit;

  // Trigger the normal interrupt, if defined.
  if (event.normalint.triggerlabel <> '') and (event.triggeredint = FALSE) then begin
   event.triggeredint := TRUE;
   StartFiber(event.normalint.triggerlabel, '');
  end;

 end else

 // Right-click!
 if button = 3 then begin

  // If choicematic is active and not on the topmost choice level, cancel
  // toward the top level.
  if (choicematic.active) and (choicematic.choiceparent <> '') then begin
   RevertChoice;
   exit;
  end;

  // If boxes are visible and the mouse is over any displayed box, hide
  // all boxes.
  if sysvar.hideboxes = 0 then
   for ivar := high(TBox) downto 0 do
    if TBox[ivar].boxstate <> BOXSTATE_NULL then
     with TBox[ivar] do
      if (musx >= boxlocxp_r) and (musx < boxlocxp_r + longint(boxsizexp_r))
      and (musy >= boxlocyp_r) and (musy < boxlocyp_r + longint(boxsizeyp_r))
      then begin
       HideBoxes(TRUE);
       exit;
      end;

  // Trigger the esc-interrupt, if defined.
  if (event.escint.triggerlabel <> '') and (event.triggeredint = FALSE) then begin
   event.triggeredint := TRUE;
   StartFiber(event.escint.triggerlabel, '');
  end;

  // If metastate is normal, enter the metamenu metastate.
 end;
end;

procedure UserInput_Wheel(y : longint);
// Input positive numbers to scroll up/away, negative to scroll down/toward.
var ivar, jvar : dword;
    newpos : longint;
begin
 // If textboxes are hidden, ignore.
 if sysvar.hideboxes <> 0 then exit;

 // If choicematic is active, move the highlight forward/backward directly.
 if choicematic.active then with choicematic do begin
  newpos := highlightindex - y;
  if newpos >= longint(showcount) then newpos := showcount - 1
  else if newpos < 0 then newpos := 0;
  if dword(newpos) <> highlightindex then begin
   highlightindex := newpos;
   HighlightChoice(MOVETYPE_HALFCOS);
   exit;
  end;
 end;

 // Scroll freescrollable boxes.
 for ivar := high(TBox) downto 0 do with TBox[ivar] do
  if (style.freescrollable) then begin
   newpos := contentwinscrollofsp;
   // Check for an existing scroll effect.
   jvar := fxcount;
   while jvar <> 0 do begin
    dec(jvar);
    if (fx[jvar].kind = FX_BOXSCROLL) and (fx[jvar].fxbox = ivar) then begin
     // Found one. Import it's target scroll offset. This allows multiple
     // sequential wheel ticks to add up naturally.
     newpos := fx[jvar].y2;
     break;
    end;
   end;

   dec(newpos, y * longint(fontheightp));
   if newpos + longint(contentwinsizeyp) > longint(contentfullheightp) then newpos := contentfullheightp - contentwinsizeyp;
   if newpos < 0 then newpos := 0;
   ScrollBoxTo(ivar, newpos, MOVETYPE_HALFCOS);
  end;
end;

// ------------------------------------------------------------------

procedure MoveToMouseoverable(direction : byte);
// Attempts to find the closest mouseoverable area or gob center point in the
// indicated direction (8=up, 2=down, 4=left, 6=right), relative to the
// current mouse cursor position. If one was found, teleports the cursor onto
// that center point.
var ivar, dist, bestdist : dword;
    x, y, bestx, besty : longint;

  procedure trynewbest; inline;
  begin
   if (direction = 2) and (y > 0) and (y >= abs(x))
   or (direction = 8) and (y < 0) and (-y >= abs(x))
   or (direction = 4) and (x < 0) and (-x >= abs(y))
   or (direction = 6) and (x > 0) and (x >= abs(y))
   then begin
    dist := x * x + y * y;
    if dist < bestdist then begin
     bestx := x; besty := y;
     bestdist := dist;
    end;
   end;
  end;

begin
 bestx := 0; besty := 0; bestdist := $FFFFFFFF;
 ivar := length(event.area);
 while ivar <> 0 do begin
  dec(ivar);
  with event.area[ivar] do if mouseonly = FALSE then begin
   x := (x1p + x2p) div 2 - sysvar.mousex;
   y := (y1p + y2p) div 2 - sysvar.mousey;
   trynewbest;
  end;
 end;
 ivar := length(event.gob);
 while ivar <> 0 do begin
  dec(ivar);
  with event.gob[ivar] do if mouseonly = FALSE then begin
   x := gob[gobnum].locxp + longint(gob[gobnum].sizexp shr 1) - sysvar.mousex;
   y := gob[gobnum].locyp + longint(gob[gobnum].sizeyp shr 1) - sysvar.mousey;
   trynewbest;
  end;
 end;
 if bestdist <> $FFFFFFFF then
  UserInput_Mouse(sysvar.mousex + bestx, sysvar.mousey + besty, 0);
end;

procedure UserInput_Enter;
var ivar, jvar : dword;
begin
 // If skip seen text mode is enabled, disable it.

 // If textboxes are hidden, make them visible.
 if sysvar.hideboxes <> 0 then begin
  HideBoxes(FALSE);
  exit;
 end;

 // If box 0 as debug console is in showtext state, execute the last line.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode = FALSE)
 and (TBox[0].userinputlen <> 0) then begin
  RunDebugCommand;
  exit;
 end;

 // Check boxes for pageble content. Any box that has more to display and is
 // not freely scrollable but does have autowaitkey enabled, will scroll
 // ahead by a page, swallowing the keystroke.
 if CheckPageableBoxes then exit;

 // Select mouseoverables that are highlighted and have trigger labels.
 jvar := 0;
 ivar := length(event.area);
 while ivar <> 0 do begin
  dec(ivar);
  if (event.area[ivar].state <> 0) and (event.area[ivar].mouseonly = FALSE)
  and (event.area[ivar].triggerlabel <> '') then begin
   StartFiber(event.area[ivar].triggerlabel, '');
   inc(jvar);
  end;
 end;
 ivar := length(event.gob);
 while ivar <> 0 do begin
  dec(ivar);
  if (event.gob[ivar].state <> 0) and (event.gob[ivar].mouseonly = FALSE)
  and (event.gob[ivar].triggerlabel <> '') then begin
   StartFiber(event.gob[ivar].triggerlabel, '');
   inc(jvar);
  end;
 end;
 if jvar <> 0 then exit;

 // If choicematic is active, select the highlighted choice.
 if choicematic.active then begin
  SelectChoice(choicematic.highlightindex);
  exit;
 end;

 // If choicematic typeinbox is valid, resume any waittyping fibers.

 // Resume any fibers in waitkey state.
 if ClearWaitKey then exit;

 // If a normal interrupt is defined, trigger it.
 if (event.normalint.triggerlabel <> '') and (event.triggeredint = FALSE) then begin
  event.triggeredint := TRUE;
  StartFiber(event.normalint.triggerlabel, '');
 end;
end;

procedure UserInput_Esc;
begin
 // If skip seen text mode is enabled, disable it.

 // If textboxes are hidden, ignore.
 if sysvar.hideboxes <> 0 then exit;

 // If box 0 as transcript log is in showtext state, slide out the box.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode)
 then begin
  UserInput_CtrlT;
  exit;
 end;

 // If choicematic has something cancellable, cancel it.
 if (choicematic.active) and (choicematic.choiceparent <> '') then begin
  RevertChoice;
  exit;
 end;

 // If esc-interrupt is defined, trigger it.
 if (event.escint.triggerlabel <> '') and (event.triggeredint = FALSE) then begin
  event.triggeredint := TRUE;
  StartFiber(event.escint.triggerlabel, '');
  exit;
 end;

 // If metastate is normal, enter the metamenu metastate.
end;

procedure UserInput_TextInput(const instr : UTF8string);
// Localised keyboard input comes in as UTF8 snippets.
var ivar : dword;
begin
 if instr = '' then exit;
 // If textboxes are hidden, ignore.
 if sysvar.hideboxes <> 0 then exit;

 // If the dropdown console is active in debug mode, the input goes there.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode = FALSE)
 then with TBox[0] do begin
  inc(userinputlen, dword(length(instr)));
  inc(txtlength, dword(length(instr)));
  if txtlength >= dword(length(txtcontent)) then setlength(txtcontent, txtlength + 64);

  if dword(caretpos) < userinputlen then begin
   for ivar := txtlength - 1 downto txtlength - userinputlen + caretpos do
    txtcontent[ivar] := txtcontent[ivar - length(instr)];
  end;

  move(instr[1], txtcontent[txtlength - userinputlen + caretpos], length(instr));
  inc(caretpos, length(instr));

  if (txtescapecount <> 0)
  and (txtescapelist[txtescapecount - 1].escapecode = 1)
  then inc(txtescapelist[txtescapecount - 1].escapeofs, dword(length(instr)));
  contentbuftextvalid := FALSE;
  exit;
 end;
end;

procedure UserInput_Backspace;
// Part of localised keyboard input.
var ivar, jvar : dword;
begin
 // If textboxes are hidden, ignore.
 if sysvar.hideboxes <> 0 then exit;

 // If the dropdown console is active in debug mode, backspace goes there.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode = FALSE)
 then with TBox[0] do begin
  if caretpos > 0 then begin
   ivar := caretpos;
   repeat
    dec(caretpos);
   until (caretpos = 0)
   or (txtcontent[txtlength - userinputlen + caretpos] and $C0 <> $80);

   jvar := txtlength - userinputlen + caretpos;
   dec(ivar, caretpos);
   dec(txtlength, ivar);
   dec(userinputlen, ivar);
   while jvar < txtlength do begin
    txtcontent[jvar] := txtcontent[jvar + ivar];
    inc(jvar);
   end;
   if (txtescapecount <> 0)
   and (txtescapelist[txtescapecount - 1].escapecode = 1)
   then dec(txtescapelist[txtescapecount - 1].escapeofs, ivar);
   contentbuftextvalid := FALSE;
  end;
  exit;
 end;
end;

procedure UserInput_Delete;
// Part of localised keyboard input.
var ivar, jvar : dword;
begin
 // If textboxes are hidden, ignore.
 if sysvar.hideboxes <> 0 then exit;

 // If the dropdown console is active in debug mode, delete goes there.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode = FALSE)
 then with TBox[0] do begin
  if dword(caretpos) < userinputlen then begin
   ivar := caretpos;
   repeat
    inc(ivar);
   until (ivar >= userinputlen)
   or (txtcontent[txtlength - userinputlen + ivar] and $C0 <> $80);

   jvar := txtlength - userinputlen + caretpos;
   dec(ivar, caretpos);
   dec(txtlength, ivar);
   dec(userinputlen, ivar);
   while jvar < txtlength do begin
    txtcontent[jvar] := txtcontent[jvar + ivar];
    inc(jvar);
   end;
   contentbuftextvalid := FALSE;
  end;
  exit;
 end;
end;

procedure UserInput_Home;
begin
 // If textboxes are hidden, ignore.
 if sysvar.hideboxes <> 0 then exit;

 // If the dropdown console is active in debug mode, move caret to far left.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode = FALSE)
 then with TBox[0] do begin
  if caretpos > 0 then begin
   caretpos := 0;
   if (txtescapecount <> 0)
   and (txtescapelist[txtescapecount - 1].escapecode = 1)
   then txtescapelist[txtescapecount - 1].escapeofs := txtlength - userinputlen;
   contentbuftextvalid := FALSE;
  end;
  exit;
 end;
end;

procedure UserInput_End;
begin
 // If textboxes are hidden, ignore.
 if sysvar.hideboxes <> 0 then exit;

 // If the dropdown console is active in debug mode, move caret to far right.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode = FALSE)
 then with TBox[0] do begin
  if dword(caretpos) < userinputlen then begin
   caretpos := userinputlen;
   if (txtescapecount <> 0)
   and (txtescapelist[txtescapecount - 1].escapecode = 1)
   then txtescapelist[txtescapecount - 1].escapeofs := txtlength;
   contentbuftextvalid := FALSE;
  end;
  exit;
 end;
end;

procedure UserInput_Up;
var ivar : dword;
begin
 {$ifdef sakucon}
 sysvar.keysdown := sysvar.keysdown or KEYVAL_UP;
 {$endif}
 if choicematic.active then begin MoveChoiceHighlightUp; exit; end;
 // Scroll freescrollable boxes.
 for ivar := high(TBox) downto 0 do with TBox[ivar] do
  if (style.freescrollable) and (contentwinscrollofsp > 0) then begin
   if contentwinscrollofsp > fontheightp
   then ScrollBoxTo(ivar, contentwinscrollofsp - fontheightp, MOVETYPE_HALFCOS)
   else ScrollBoxTo(ivar, 0, MOVETYPE_HALFCOS);
   exit;
  end;
 // Move to closest mouseoverable.
 MoveToMouseoverable(8);
end;

procedure UserInput_Down;
var ivar : dword;
begin
 {$ifdef sakucon}
 sysvar.keysdown := sysvar.keysdown or KEYVAL_DOWN;
 {$endif}
 if choicematic.active then begin MoveChoiceHighlightDown; exit; end;
 // Scroll freescrollable boxes.
 for ivar := high(TBox) downto 0 do with TBox[ivar] do
  if (style.freescrollable)
  and (contentwinscrollofsp + contentwinsizeyp < contentfullheightp) then begin
   ScrollBoxTo(ivar, contentwinscrollofsp + fontheightp, MOVETYPE_HALFCOS);
   exit;
  end;
 // Move to closest mouseoverable.
 MoveToMouseoverable(2);
end;

procedure UserInput_Left;
begin
 // If the dropdown console is active in debug mode, move the caret.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode = FALSE)
 then with TBox[0] do begin
  if caretpos > 0 then begin
   repeat
    dec(caretpos);
   until (caretpos = 0)
   or (txtcontent[txtlength - userinputlen + caretpos] and $C0 <> $80);

   if (txtescapecount <> 0)
   and (txtescapelist[txtescapecount - 1].escapecode = 1)
   then txtescapelist[txtescapecount - 1].escapeofs := txtlength - userinputlen + caretpos;
   contentbuftextvalid := FALSE;
  end;
  exit;
 end;

 {$ifdef sakucon}
 sysvar.keysdown := sysvar.keysdown or KEYVAL_LEFT;
 {$endif}
 if (choicematic.active) and (choicematic.numcolumns > 1) then begin
  MoveChoiceHighlightLeft;
  exit;
 end;
 // Move to closest mouseoverable.
 MoveToMouseoverable(4);
end;

procedure UserInput_Right;
begin
 // If the dropdown console is active in debug mode, move the caret.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode = FALSE)
 then with TBox[0] do begin
  if dword(caretpos) < userinputlen then begin
   repeat
    inc(caretpos);
   until (dword(caretpos) >= userinputlen)
   or (txtcontent[txtlength - userinputlen + caretpos] and $C0 <> $80);

   if (txtescapecount <> 0)
   and (txtescapelist[txtescapecount - 1].escapecode = 1)
   then txtescapelist[txtescapecount - 1].escapeofs := txtlength - userinputlen + caretpos;
   contentbuftextvalid := FALSE;
  end;
  exit;
 end;

 {$ifdef sakucon}
 sysvar.keysdown := sysvar.keysdown or KEYVAL_RIGHT;
 {$endif}
 if (choicematic.active) and (choicematic.numcolumns > 1) then begin
  MoveChoiceHighlightRight;
  exit;
 end;
 // Move to closest mouseoverable.
 MoveToMouseoverable(6);
end;

// ------------------------------------------------------------------

{$ifndef sakucon}
procedure UserInput_GamepadCancel;
begin
 // If skip seen text mode is enabled, disable it.

 // If textboxes are hidden, make them visible.
 if sysvar.hideboxes <> 0 then begin
  HideBoxes(FALSE);
  exit;
 end;

 // If box 0 as transcript log is in showtext state, slide out the box.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode)
 then begin
  UserInput_CtrlT;
  exit;
 end;

 // If choicematic has something cancellable, cancel it.
 if (choicematic.active) and (choicematic.choiceparent <> '') then begin
  RevertChoice;
  exit;
 end;

 // Check boxes for pageble content. Any box that has more to display and is
 // not freely scrollable but does have autowaitkey enabled, will scroll
 // ahead by a page, swallowing the keystroke.
 if CheckPageableBoxes then exit;

 // Resume any fibers in waitkey state.
 if ClearWaitKey then exit;

 // If a normal interrupt is defined, trigger it.
 if (event.normalint.triggerlabel <> '') and (event.triggeredint = FALSE) then begin
  event.triggeredint := TRUE;
  StartFiber(event.normalint.triggerlabel, '');
  exit;
 end;

 // If esc-interrupt is defined, trigger it.
 if (event.escint.triggerlabel <> '') and (event.triggeredint = FALSE) then begin
  event.triggeredint := TRUE;
  StartFiber(event.escint.triggerlabel, '');
 end;
end;

procedure UserInput_GamepadMenu;
begin
 // If skip seen text mode is enabled, disable it.

 // If textboxes are hidden, make them visible.
 if sysvar.hideboxes <> 0 then begin
  HideBoxes(FALSE);
  exit;
 end;

 // If box 0 as transcript log is in showtext state, slide out the box.
 if (TBox[0].boxstate = BOXSTATE_SHOWTEXT) and (sysvar.transcriptmode)
 then begin
  UserInput_CtrlT;
  exit;
 end;

 // If esc-interrupt is defined, trigger it.
 if (event.escint.triggerlabel <> '') and (event.triggeredint = FALSE) then begin
  event.triggeredint := TRUE;
  StartFiber(event.escint.triggerlabel, '');
  exit;
 end;

 // If metastate is normal, enter the metamenu metastate.
end;

procedure UserInput_GamepadButtonDown(bnum : TSDL_GameControllerButton);
begin
 case bnum of
   SDL_CONTROLLER_BUTTON_DPAD_UP: begin
    sysvar.keyrepeataftermsecs := 480;
    sysvar.keysdown := sysvar.keysdown or KEYVAL_UP;
    UserInput_Up;
   end;

   SDL_CONTROLLER_BUTTON_DPAD_DOWN: begin
    sysvar.keyrepeataftermsecs := 480;
    sysvar.keysdown := sysvar.keysdown or KEYVAL_DOWN;
    UserInput_Down;
   end;

   SDL_CONTROLLER_BUTTON_DPAD_LEFT: begin
    sysvar.keyrepeataftermsecs := 480;
    sysvar.keysdown := sysvar.keysdown or KEYVAL_LEFT;
    UserInput_Left;
   end;

   SDL_CONTROLLER_BUTTON_DPAD_RIGHT: begin
    sysvar.keyrepeataftermsecs := 480;
    sysvar.keysdown := sysvar.keysdown or KEYVAL_RIGHT;
    UserInput_Right;
   end;

   SDL_CONTROLLER_BUTTON_BACK: UserInput_CtrlB;

   // button A: low position
   SDL_CONTROLLER_BUTTON_A: UserInput_Enter;
   // button B: right position
   SDL_CONTROLLER_BUTTON_B: UserInput_GamepadCancel;
   // button Y: top position
   SDL_CONTROLLER_BUTTON_Y: UserInput_GamepadMenu;
   // button X: left position
   SDL_CONTROLLER_BUTTON_X: UserInput_CtrlT;
 end;
end;

procedure UserInput_GamepadButtonUp(bnum : TSDL_GameControllerButton);
begin
 case bnum of
   SDL_CONTROLLER_BUTTON_DPAD_UP: sysvar.keysdown := sysvar.keysdown and (KEYVAL_UP xor $FF);
   SDL_CONTROLLER_BUTTON_DPAD_DOWN: sysvar.keysdown := sysvar.keysdown and (KEYVAL_DOWN xor $FF);
   SDL_CONTROLLER_BUTTON_DPAD_LEFT: sysvar.keysdown := sysvar.keysdown and (KEYVAL_LEFT xor $FF);
   SDL_CONTROLLER_BUTTON_DPAD_RIGHT: sysvar.keysdown := sysvar.keysdown and (KEYVAL_RIGHT xor $FF);
 end;
end;

{procedure UserInput_GamepadAxis(anum : TSDL_GameControllerAxis; value : longint);
begin
end;}
{$endif !sakucon}
