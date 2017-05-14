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

 // Check boxes for pageble content. Any box that has more to display and is
 // not freely scrollable but does have autowaitkey enabled, will scroll
 // ahead by a page, swallowing the keystroke.
 if CheckPageableBoxes then exit;

 // Check if any fiber is waiting for a keypress, and resume them if so,
 // swallowing the keystroke.
 if ClearWaitKey then exit;

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

procedure UserInput_Up;
var ivar : dword;
begin
 if choicematic.active then begin MoveChoiceHighlightUp; exit; end;
 // Scroll freescrollable boxes.
 for ivar := high(TBox) downto 0 do with TBox[ivar] do
  if (style.freescrollable) and (contentwinscrollofsp > 0) then begin
   if contentwinscrollofsp > fontheightp
   then ScrollBoxTo(ivar, contentwinscrollofsp - fontheightp)
   else ScrollBoxTo(ivar, 0);
   exit;
  end;
end;

procedure UserInput_Down;
var ivar : dword;
begin
 if choicematic.active then begin MoveChoiceHighlightDown; exit; end;
 // Scroll freescrollable boxes.
 for ivar := high(TBox) downto 0 do with TBox[ivar] do
  if (style.freescrollable)
  and (contentwinscrollofsp + contentwinsizeyp < contentfullheightp) then begin
   ScrollBoxTo(ivar, contentwinscrollofsp + fontheightp);
   exit;
  end;
end;

procedure UserInput_Left; inline;
begin
 if (choicematic.active) and (choicematic.numcolumns > 1) then MoveChoiceHighlightLeft;
end;

procedure UserInput_Right; inline;
begin
 if (choicematic.active) and (choicematic.numcolumns > 1) then MoveChoiceHighlightRight;
end;

procedure UserInput_HideBoxes; inline;
begin
 HideBoxes(gamevar.hideboxes = 0);
end;
