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

// SuperSakura user input

procedure UserInput_HideBoxes; inline;
begin
 HideBoxes(gamevar.hideboxes = 0);
end;

procedure UserInput_Mouse(musx, musy : longint; button : byte);
// The coordinates are a pixel value from the game window's top left.
// The button is 0 if this is just the mouse moving around; 1 if it's
// a left-click and 3 if it's a right-click.
var ivar, jvar : dword;
    x, y : longint;
    overnewarea, overnewgob : boolean;
begin
 // If we're paused, mouse clicks are ignored and mouseovers don't trigger.
 if pausestate = PAUSESTATE_PAUSED then exit;

 gamevar.mousex := musx;
 gamevar.mousey := musy;

 // Check if mouseovering choices in an active choicebox.
 // (Ignore, if the highlight box is currently moving.)
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
  if gamevar.hideboxes and 1 <> 0 then begin
   UserInput_HideBoxes;
   exit;
  end;

  // If clicking over a choicebox, select the currently highlighted choice.
  if choicematic.active then with TBox[choicematic.choicebox] do
   if (musx >= boxlocxp_r) and (musx < boxlocxp_r + longint(boxsizexp_r))
   and (musy >= boxlocyp_r) and (musy < boxlocyp_r + longint(boxsizeyp_r))
   then begin
    SelectChoice(choicematic.highlightindex);
    exit;
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
  if gamevar.hideboxes = 0 then
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

  // Summon the metamenu.
 end;
end;

procedure UserInput_Wheel(y : longint);
// Input positive numbers to scroll up/away, negative to scroll down/toward.
var ivar : dword;
    newpos : longint;
begin
 // If choicematic is active, move the highlight forward/backward directly.
 if choicematic.active then with choicematic do begin
  newpos := highlightindex - y;
  if newpos >= showcount then highlightindex := showcount - 1
  else if newpos < 0 then highlightindex := 0
  else highlightindex := newpos;
  HighlightChoice(MOVETYPE_HALFCOS);
  exit;
 end;

 // Scroll freescrollable boxes.
 for ivar := high(TBox) downto 0 do with TBox[ivar] do
  if (style.freescrollable) then begin
   newpos := contentwinscrollofsp - y * fontheightp;
   if newpos + contentwinsizeyp > contentfullheightp then newpos := contentfullheightp - contentwinsizeyp;
   if newpos < 0 then newpos := 0;
   ScrollBoxTo(ivar, newpos, MOVETYPE_HALFCOS);
  end;
end;

procedure UserInput_Enter;
var ivar, jvar : dword;
begin
 // If skip seen text mode is enabled, disable it.

 // If textboxes are hidden, make them visible.
 if gamevar.hideboxes <> 0 then begin
  HideBoxes(FALSE);
  exit;
 end;

 // If box 0 as debug console is in showtext state, execute the last line.

 // If the game is paused, any further actions are forbidden.
 if pausestate <> PAUSESTATE_NORMAL then exit;

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

 // If textboxes are hidden, ignore it.
 if gamevar.hideboxes <> 0 then exit;

 // If box 0 as transcript log is in showtext state, pop out the box.

 // If the game is paused, any further actions are forbidden.
 if pausestate <> PAUSESTATE_NORMAL then exit;

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

 // If metastate is normal, summon the metamenu.
end;

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
   x := (x1p + x2p) div 2 - gamevar.mousex;
   y := (y1p + y2p) div 2 - gamevar.mousey;
   trynewbest;
  end;
 end;
 ivar := length(event.gob);
 while ivar <> 0 do begin
  dec(ivar);
  with event.gob[ivar] do if mouseonly = FALSE then begin
   x := gob[gobnum].locxp + gob[gobnum].sizexp shr 1 - gamevar.mousex;
   y := gob[gobnum].locyp + gob[gobnum].sizeyp shr 1 - gamevar.mousey;
   trynewbest;
  end;
 end;
 if bestdist <> $FFFFFFFF then
  UserInput_Mouse(gamevar.mousex + bestx, gamevar.mousey + besty, 0);
end;

procedure UserInput_Up;
var ivar : dword;
begin
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

procedure UserInput_Left; inline;
begin
 if (choicematic.active) and (choicematic.numcolumns > 1) then begin
  MoveChoiceHighlightLeft;
  exit;
 end;
 // Move to closest mouseoverable.
 MoveToMouseoverable(4);
end;

procedure UserInput_Right; inline;
begin
 if (choicematic.active) and (choicematic.numcolumns > 1) then begin
  MoveChoiceHighlightRight;
  exit;
 end;
 // Move to closest mouseoverable.
 MoveToMouseoverable(6);
end;
