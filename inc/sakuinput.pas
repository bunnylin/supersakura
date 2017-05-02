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

procedure UserInput_Enter; inline;
var ivar, jvar : dword;
    swallow : boolean;
begin
 // If textboxes are hidden, make them visible.
 if gamevar.hideboxes <> 0 then begin
  HideBoxes(FALSE);
  exit;
 end;

 // If the game is paused, only allow enter for the debug window.
 if pausestate <> PAUSESTATE_NORMAL then begin
  exit;
 end;

 // If choicematic is active, selects the highlighted choice.
 // (Console mode uses a different choice paradigm, so skip this.)
 {$ifndef sakucon}
 if choicematic.active then begin
  SelectChoice(choicematic.highlightindex);
  exit;
 end;
 {$endif}

 // Check boxes for pageble content.
 swallow := FALSE;
 for ivar := high(TBox) downto 0 do
  with TBox[ivar] do begin
   if (boxstate = BOXSTATE_SHOWTEXT)
   and (style.freescrollable = FALSE) and (style.autowaitkey)
   and (contentwinscrollofsp + contentwinsizeyp < contentfullheightp)
   then begin
    ScrollBoxTo(ivar, contentwinscrollofsp + contentwinsizeyp);
    swallow := TRUE;
   end;
  end;
 if swallow then exit;

 // Clear fibers waiting for a keypress.
 if fibercount <> 0 then
  for ivar := fibercount - 1 downto 0 do
   if fiber[ivar].fiberstate in [FIBERSTATE_WAITKEY, FIBERSTATE_WAITCLEAR]
   then begin
    if fiber[ivar].fiberstate = FIBERSTATE_WAITCLEAR then
     for jvar := high(TBox) downto 0 do ClearTextbox(jvar);
    fiber[ivar].fiberstate := FIBERSTATE_NORMAL;
    swallow := TRUE;
   end;
 if swallow then exit;

 // Select a mouseoverable, if highlighted.

 // If an interrupt is defined, invokes it.
 if event.normalint.triggerlabel <> '' then StartFiber(event.normalint.triggerlabel, '');
end;

procedure UserInput_Esc; inline;
begin
 // If the game is paused, only allow esc for the debug window.
 if pausestate <> PAUSESTATE_NORMAL then begin
  exit;
 end;

 // If choicematic has something cancellable, cancel it.
 if (choicematic.active) and (choicematic.choiceparent <> '') then begin
  RevertChoice;
  exit;
 end;

 // If esc-interrupt is defined, invokes it.
 if event.escint.triggerlabel <> '' then begin
  StartFiber(event.escint.triggerlabel, '');
  exit;
 end;

 // Summon the metamenu.
end;

procedure UserInput_Up; inline;
begin
 if choicematic.active then with choicematic do begin
  if highlightindex >= numcolumns then begin
   dec(highlightindex, numcolumns);
   HighlightChoice(MOVETYPE_HALFCOS);
  end;
  exit;
 end;
end;

procedure UserInput_Down; inline;
begin
 if choicematic.active then with choicematic do begin
  if highlightindex + numcolumns < showcount then begin
   inc(highlightindex, numcolumns);
   HighlightChoice(MOVETYPE_HALFCOS);
  end;
  exit;
 end;
end;

procedure UserInput_Left; inline;
begin
 if (choicematic.active) and (choicematic.numcolumns > 1) then with choicematic do begin
  if highlightindex mod numcolumns <> 0 then begin
   dec(highlightindex);
   HighlightChoice(MOVETYPE_HALFCOS);
  end;
  exit;
 end;
end;

procedure UserInput_Right; inline;
begin
 if (choicematic.active) and (choicematic.numcolumns > 1) then with choicematic do begin
  if ((highlightindex + 1) mod numcolumns <> 0)
  and (highlightindex + 1 < showcount) then begin
   inc(highlightindex);
   HighlightChoice(MOVETYPE_HALFCOS);
  end;
  exit;
 end;
end;
