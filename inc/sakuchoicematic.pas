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

// Choicematic functions.

procedure DeactivateChoicematic(cancelled : boolean);
// If the choicematic is active, disables it, clears all boxes, hides the
// highlight box, and resumes all threads that were waiting for a choice.
// If the choice was cancelled, sets the finalised choice to empty.
var ivar : dword;
begin
 with choicematic do begin
  active := FALSE;
  if cancelled then begin
   previouschoice := '';
   previouschoiceindex := 0;
  end;
 end;

 for ivar := high(TBox) downto 0 do ClearTextbox(ivar);

 if fibercount <> 0 then
  for ivar := fibercount - 1 downto 0 do
   if fiber[ivar].fiberstate = FIBERSTATE_WAITCHOICE
    then fiber[ivar].fiberstate := FIBERSTATE_NORMAL;
end;

procedure HighlightChoice(style : byte);
// Sets the higlight box over the highlighted choice index. If style is 0,
// the change is immediate, else the box slides over with the given style.
// Generally, you'll want MOVETYPE_HALFCOS.
// Scrolls the choicebox if the highlighted choice is currently out of view.
var x1, y1, x2, y2 : longint;
    ivar : dword;
begin
 with choicematic do begin
  // The showlist coords are pixel values relative to the box's sizexyp.
  // The top and left margins of the choicebox are included in these.
  x1 := showlist[highlightindex].slx1p;
  y1 := showlist[highlightindex].sly1p;
  x2 := showlist[highlightindex].slx2p;
  y2 := showlist[highlightindex].sly2p;

  with TBox[choicebox] do begin
   // Scroll the box if needed.
   ivar := contentwinscrollofsp;
   if y1 - margintopp < contentwinscrollofsp then begin
    ivar := y1 - margintopp;
    ScrollBoxTo(choicebox, ivar, MOVETYPE_HALFCOS);
   end else
   if y2 - margintopp > contentwinscrollofsp + contentwinsizeyp then begin
    ivar := y2 - margintopp - contentwinsizeyp;
    ScrollBoxTo(choicebox, ivar, MOVETYPE_HALFCOS);
   end;
   // Deduct the box's scrolling offset.
   dec(y1, ivar);
   dec(y2, ivar);
   // Add the box's true coordinates.
   inc(x1, boxlocxp_r);
   inc(x2, boxlocxp_r);
   inc(y1, boxlocyp_r);
   inc(y2, boxlocyp_r);
  end;

  {$ifdef sakucon}
  TBox[choicebox].needsredraw := TRUE;
  {$else}

  with TBox[highlightbox] do begin
   // safety
   if x1 < 0 then x1 := 0;
   if y1 < 0 then y1 := 0;
   if x2 < 0 then x2 := 0;
   if y2 < 0 then y2 := 0;
   // Convert to 32k within the highlight box's viewport.
   ivar := viewport[inviewport].viewportsizexp shr 1;
   x1 := (x1 shl 15 + longint(ivar)) div longint(viewport[inviewport].viewportsizexp);
   x2 := (x2 shl 15 + longint(ivar)) div longint(viewport[inviewport].viewportsizexp);
   ivar := viewport[inviewport].viewportsizeyp shr 1;
   y1 := (y1 shl 15 + longint(ivar)) div longint(viewport[inviewport].viewportsizeyp);
   y2 := (y2 shl 15 + longint(ivar)) div longint(viewport[inviewport].viewportsizeyp);
   // Add the highlight box's own margin.
   dec(x1, marginleft);
   dec(x2, marginleft);
   dec(y1, margintop);
   dec(y2, margintop);
   // Make sure the highlight box pops in.
   boxstate := BOXSTATE_APPEARING;
  end;

  AddBoxMoveEffect(highlightbox, -1, x1, y1, 0, 0, 160, style);
  AddBoxSizeEffect(highlightbox, -1, x2 - x1, y2 - y1, 160, style);
  {$endif}

  // Trigger the on-highlight callback if defined.
  if onhighlight <> '' then begin
   StartFiber(onhighlight, '');
   onhighlight := '';
  end;
 end;
end;

procedure MoveChoiceHighlightUp;
var ivar, closestindex, closestdist : dword;
begin
 closestindex := $FFFFFFFF; closestdist := $FFFFFFFF;
 with choicematic do begin
  ivar := showcount;
  while ivar <> 0 do begin
   dec(ivar);
   if ivar = highlightindex then continue;
   // Is this choice above the highlighted choice?
   if (showlist[ivar].sly2p <= showlist[highlightindex].sly1p)
   // Does this choice overlap the highlighted choice's X coords?
   and (showlist[ivar].slx1p < showlist[highlightindex].slx2p)
   and (showlist[ivar].slx2p > showlist[highlightindex].slx1p)
   // Is the choice closer than previous closest?
   and (showlist[highlightindex].sly1p - showlist[ivar].sly1p < closestdist)
   then begin
    closestindex := ivar;
    closestdist := showlist[highlightindex].sly1p - showlist[ivar].sly1p;
   end;
  end;
  if closestindex < showcount then begin
   highlightindex := closestindex;
   HighlightChoice(MOVETYPE_HALFCOS);
  end;
 end;
end;

procedure MoveChoiceHighlightDown;
var ivar, closestindex, closestdist : dword;
begin
 closestindex := $FFFFFFFF; closestdist := $FFFFFFFF;
 with choicematic do begin
  ivar := showcount;
  while ivar <> 0 do begin
   dec(ivar);
   if ivar = highlightindex then continue;
   // Is this choice below the highlighted choice?
   if (showlist[ivar].sly1p >= showlist[highlightindex].sly2p)
   // Does this choice overlap the highlighted choice's X coords?
   and (showlist[ivar].slx1p < showlist[highlightindex].slx2p)
   and (showlist[ivar].slx2p > showlist[highlightindex].slx1p)
   // Is the choice closer than previous closest?
   and (showlist[ivar].sly1p - showlist[highlightindex].sly1p < closestdist)
   then begin
    closestindex := ivar;
    closestdist := showlist[ivar].sly1p - showlist[highlightindex].sly1p;
   end;
  end;
  if closestindex < showcount then begin
   highlightindex := closestindex;
   HighlightChoice(MOVETYPE_HALFCOS);
  end;
 end;
end;

procedure MoveChoiceHighlightLeft;
var ivar, closestindex, closestdist : dword;
begin
 closestindex := $FFFFFFFF; closestdist := $FFFFFFFF;
 with choicematic do begin
  ivar := showcount;
  while ivar <> 0 do begin
   dec(ivar);
   if ivar = highlightindex then continue;
   // Is this choice to the left of the highlighted choice?
   if (showlist[ivar].slx2p <= showlist[highlightindex].slx1p)
   // Does this choice overlap the highlighted choice's Y coords?
   and (showlist[ivar].sly1p < showlist[highlightindex].sly2p)
   and (showlist[ivar].sly2p > showlist[highlightindex].sly1p)
   // Is the choice closer than previous closest?
   and (showlist[highlightindex].slx1p - showlist[ivar].slx1p < closestdist)
   then begin
    closestindex := ivar;
    closestdist := showlist[highlightindex].slx1p - showlist[ivar].slx1p;
   end;
  end;
  if closestindex < showcount then begin
   highlightindex := closestindex;
   HighlightChoice(MOVETYPE_HALFCOS);
  end;
 end;
end;

procedure MoveChoiceHighlightRight;
var ivar, closestindex, closestdist : dword;
begin
 closestindex := $FFFFFFFF; closestdist := $FFFFFFFF;
 with choicematic do begin
  ivar := showcount;
  while ivar <> 0 do begin
   dec(ivar);
   if ivar = highlightindex then continue;
   // Is this choice to the right of the highlighted choice?
   if (showlist[ivar].slx1p >= showlist[highlightindex].slx2p)
   // Does this choice overlap the highlighted choice's Y coords?
   and (showlist[ivar].sly1p < showlist[highlightindex].sly2p)
   and (showlist[ivar].sly2p > showlist[highlightindex].sly1p)
   // Is the choice closer than previous closest?
   and (showlist[ivar].slx1p - showlist[highlightindex].slx1p < closestdist)
   then begin
    closestindex := ivar;
    closestdist := showlist[ivar].slx1p - showlist[highlightindex].slx1p;
   end;
  end;
  if closestindex < showcount then begin
   highlightindex := closestindex;
   HighlightChoice(MOVETYPE_HALFCOS);
  end;
 end;
end;

procedure PrintActiveChoices(noprint : longint);
// Builds a list of currently displayed choices from the total set of enabled
// choices, and if noprint=0, prints them in the choicebox.
var ivar, jvar, lvar : dword;
    tempstr : UTF8string;
begin
 with choicematic do begin
  // Build a showlist.
  showcount := 0;
  highlightindex := 0;
  if choicelistcount = 0 then exit;
  jvar := length(choiceparent);
  for ivar := 0 to choicelistcount - 1 do begin
   // Choice must be selectable, and a child of the current parent choice.
   if (choicelist[ivar].selectable)
   then if (jvar = 0)
   or (dword(length(choicelist[ivar].choicetxt)) > jvar)
   and (CompStr(@choiceparent[1], @choicelist[ivar].choicetxt[1], jvar, jvar) = 0)
   then begin
    // Isolate the next level in the choice text.
    // (If current level is "LOOK", and choice is "LOOK:BOB:IN THE EYE", then
    // the next level would be "BOB".)
    lvar := jvar + 1;
    while (lvar <= dword(length(choicelist[ivar].choicetxt)))
    and (choicelist[ivar].choicetxt[lvar] <> ':')
    do inc(lvar);
    tempstr := copy(choicelist[ivar].choicetxt, jvar + 1, lvar - jvar - 1);
    // Check if this choice bit is in the showlist yet.
    lvar := 0;
    while lvar < showcount do begin
     if showlist[lvar].showtxt = tempstr then break;
     inc(lvar);
    end;
    // Add it to the showlist if it wasn't there.
    if lvar >= showcount then begin
     if showcount >= dword(length(showlist)) then setlength(showlist, length(showlist) + 8);
     showlist[showcount].showtxt := tempstr;

     // If this was part of the last complete choice, start by highlighting
     // this option as default.
     if previouschoice <> '' then begin
      tempstr := choiceparent + tempstr;
      if copy(previouschoice, 1, length(tempstr)) = tempstr then
      if (length(previouschoice) = length(tempstr))
      or (length(previouschoice) > length(tempstr))
      and (previouschoice[length(tempstr) + 1] = ':')
      then highlightindex := showcount;
     end;

     inc(showcount);
    end;
   end;
  end;

  if (showcount = 0) or (noprint <> 0) then exit;

  // Print the parent choice level, if appropriate.
  if (printchoiceparent) and (choiceparent <> '') then
   PrintBox(choicepartbox, '\B' + copy(choiceparent, 1, length(choiceparent) - 1) + '\b\n');

  // Print the showlist in the choicebox.
  for ivar := 0 to showcount - 1 do begin
   {$ifdef sakucon}
   if ivar <> 0 then
    if ivar mod numcolumns = 0
     then PrintBox(choicebox, '\n')
     else PrintBox(choicebox, ' ');
   {$endif}
   PrintBox(choicebox, '\?' + showlist[ivar].showtxt + '\.');
  end;
 end;
end;

procedure SelectChoice(selnum : dword);
// Selects showlist[selnum]. If further choice levels exist beyond this,
// prints sub-choices, otherwise saves the finalised choice and resumes any
// fibers that were waiting for it.
begin
 // If boxes are hidden, can't select anything in them.
 if sysvar.hideboxes <> 0 then exit;

 with choicematic do begin
  if selnum >= showcount then exit;

  // Build the current choice string.
  choiceparent := choiceparent + showlist[selnum].showtxt + ':';
  // Print the next level of sub-choices, if any.
  ClearTextbox(choicebox);
  if choicepartbox <> choicebox then ClearTextbox(choicepartbox);
  PrintActiveChoices(0);
  if showcount <> 0 then exit;

  // No available sub-choices, finalise this choice.
  previouschoice := copy(choiceparent, 1, length(choiceparent) - 1);
  log('Choice=' + previouschoice);

  previouschoiceindex := choicelistcount;
  while previouschoiceindex <> 0 do begin
   dec(previouschoiceindex);
   if choicelist[previouschoiceindex].choicetxt = previouschoice then break;
  end;

  DeactivateChoicematic(FALSE);
 end;
end;

procedure RevertChoice;
// Backs toward the top choice level, if possible.
var ivar : dword;
begin
 with choicematic do begin
  if choiceparent = '' then exit;
  // Remember the current choice branch as the most recently selected, so the
  // correct option is highlighted as we go up a level.
  previouschoice := choiceparent;
  // Rewind choiceparent to the previous colon or start of string.
  ivar := length(choiceparent) - 1;
  while (ivar <> 0) and (choiceparent[ivar] <> ':') do dec(ivar);
  setlength(choiceparent, ivar);
  // Reprint choices.
  ClearTextbox(choicebox);
  if choicepartbox <> choicebox then ClearTextbox(choicepartbox);
  PrintActiveChoices(0);
  if showcount = 0 then begin
   LogError('RevertChoice: no choices showable');
   DeactivateChoicematic(TRUE);
  end;
 end;
end;

procedure ActivateChoicematic(fibernum, noclear, noprint : longint);
// Prints out choices in a textbox and sets the triggering fiber to rest.
// Stops the fiber if any errors occur.
begin
 if (fibernum < 0) or (dword(fibernum) >= fibercount) then begin
  LogError('ActivateChoicematic: bad fiber: ' + strdec(fibernum));
  exit;
 end;

 with choicematic do begin
  if choicelistcount = 0 then begin
   LogError('Fiber ' + strdec(fibernum) + ':' + fiber[fibernum].fibername + ': empty choicematic');
   fiber[fibernum].fiberstate := FIBERSTATE_STOPPING;
   exit;
  end;

  if noclear = 0 then begin
   ClearTextbox(choicebox);
   if choicepartbox <> choicebox then ClearTextbox(choicepartbox);
  end;

  choiceparent := '';

  PrintActiveChoices(noprint);

  if showcount = 0 then begin
   LogError('Fiber ' + strdec(fibernum) + ':' + fiber[fibernum].fibername + ': choicematic all disabled');
   fiber[fibernum].fiberstate := FIBERSTATE_STOPPING;
   exit;
  end;

  active := TRUE;
  fiber[fibernum].fiberstate := FIBERSTATE_WAITCHOICE;

  {$ifdef sakucon}
  // The SDL version builds the choice text before displaying it, and so
  // knows each choice's coordinates and can call HighlightChoice whenever.
  // However, the console version only prints the text on demand during
  // rendering, and so won't know choice coordinates until after the first
  // render, and can't call HighlightChoice before that.
  // So, while normally the on-highlight callback is triggered for the first
  // time in response to an implicit initial HighlightChoice, the console
  // version needs to trigger this separately the first time.
  if onhighlight <> '' then StartFiber(onhighlight, '');
  {$endif}
 end;
end;

procedure ToggleChoices(txt : UTF8string; avail : boolean);
// Enables or disables the given choices in choicelist. The comparison is
// case-insensitive. Although it's preferable to toggle individual choices,
// partial matches also work. ("GO" will match "GO:THERE" but not "GOT".)
// An empty input string enables or disables all defined choices.
// Enables the choice if avail is TRUE, else disables it.
var ivar : dword;
begin
 with choicematic do begin
  if choicelistcount = 0 then exit; // nothing to do!

  if txt = '' then begin
   // Toggle all choices.
   for ivar := choicelistcount - 1 downto 0 do choicelist[ivar].selectable := avail;
  end
  else begin
   // Toggle matching choices.
   txt := upcase(txt);
   for ivar := choicelistcount - 1 downto 0 do begin
    if length(choicelist[ivar].choicetxt) = length(txt) then begin
     if upcase(choicelist[ivar].choicetxt) = txt then choicelist[ivar].selectable := avail;
    end else
    if (length(choicelist[ivar].choicetxt) > length(txt))
    and (choicelist[ivar].choicetxt[length(txt) + 1] = ':')
    and (upcase(copy(choicelist[ivar].choicetxt, 1, length(txt))) = txt)
    then choicelist[ivar].selectable := avail;
   end;
  end;
 end;
end;
