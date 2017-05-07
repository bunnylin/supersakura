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

// SuperSakura-con rendering functions

// The Ascii Blitzer needs to run fast, so it has platform-specific code.
// Bear in mind SuperSakura does frequent full-screen transitions. On Windows
// only the WriteConsoleOutput command is fast enough; trying to write things
// one character at a time literally takes a second to do the full console.
// Whereas *nix terminals by design only accept input one character at
// a time, but at least are optimised to do it fast. (Some terminal emulators
// are vastly slower than others, however.)
// So, the WinBlitz builds a char/color buffer in memory and blits it in one
// go, while the NixBlitz builds a string of characters and color escape
// codes and prints that one line at a time.
{$ifdef WINDOWS}
var AsciiBuf : array of dword;
{$endif}
procedure BlitzAscii(x1, y1, x2, y2 : longint);
var x, y : longint;
    r, g, b, l : dword;
    srcp : pointer;

  procedure GetColor; inline;
  begin
   b := byte(srcp^); inc(srcp);
   g := byte(srcp^); inc(srcp);
   r := byte(srcp^); inc(srcp, 2);
   l := xpal[r shr 4][g shr 4][b shr 4];
   if (x xor y) and 1 = 0 then l := l and $F else l := l shr 4;
  end;

  function GetCharr : byte; inline;
  begin
   // Calculate this source pixel's luma in sRGB space.
   l := (6966 * r + 23436 * g + 2366 * b + 16383) shr 15;

   // .,:;+rcomg#&
   case l of
    0: GetCharr := byte(' ');
    1..70: GetCharr := byte('.');
    71..86: GetCharr := byte(',');
    87..102: GetCharr := byte(':');
    103..118: GetCharr := byte(';');
    119..134: GetCharr := byte('+');
    135..150: GetCharr := byte('r');
    151..166: GetCharr := byte('c');
    167..184: GetCharr := byte('o');
    185..202: GetCharr := byte('m');
    203..220: GetCharr := byte('g');
    221..238: GetCharr := byte('#');
    else GetCharr := byte('&');
   end;
  end;

{$ifdef WINDOWS}
var destp : pointer;
    sx, sy, cellcount : dword;
begin
 if (x1 >= x2) or (y1 >= y2) then exit; // safety
 sx := x2 - x1; sy := y2 - y1;
 cellcount := sx * sy;
 l := 0;
 if dword(length(AsciiBuf)) < cellcount then begin setlength(AsciiBuf, 0); setlength(AsciiBuf, cellcount); end;
 destp := @AsciiBuf[0];
 for y := y1 to y2 - 1 do begin
  srcp := mv_OutputBuffy + (y * longint(sysvar.mv_WinSizeX) + x1) shl 2;
  for x := x1 to x2 - 1 do begin
   GetColor; cellcount := l shl 16;
   dword(destp^) := GetCharr + cellcount;
   inc(destp, 4);
  end;
 end;
 srcp := NIL; destp := NIL;
 CrtWriteConOut(@AsciiBuf[0], sx, sy, x1, y1, x2, y2);
end;
{$else}
var lastcolor, outbuflen : dword;
    outbuf : string;
begin
 if (x1 >= x2) or (y1 >= y2) then exit; // safety
 lastcolor := $FF; outbuflen := 0; l := 0;
 for y := y1 to y2 - 1 do begin
  GotoXY(x1, y);
  srcp := mv_OutputBuffy + (y * longint(sysvar.mv_WinSizeX) + x1) shl 2;
  for x := x1 to x2 - 1 do begin
   GetColor;
   if lastcolor <> l then begin
    inc(outbuflen); outbuf[outbuflen] := chr(27);
    inc(outbuflen); outbuf[outbuflen] := '[';
    inc(outbuflen); outbuf[outbuflen] := termtextcolor[l][1];
    inc(outbuflen); outbuf[outbuflen] := termtextcolor[l][2];
    inc(outbuflen); outbuf[outbuflen] := 'm';
    lastcolor := l;
   end;
   inc(outbuflen);
   byte(outbuf[outbuflen]) := GetCharr;
   if outbuflen >= 240 then begin
    byte(outbuf[0]) := outbuflen;
    write(outbuf);
    outbuflen := 0;
   end;
  end;
  byte(outbuf[0]) := outbuflen;
  write(outbuf);
  outbuflen := 0;
 end;

 SetColor(7);
 srcp := NIL;
end;
{$endif}

procedure BlitzBox(boxnum : dword);
// Entirely reprints a box in a console.
var ivar, jvar, y, cellcount : dword;
    textpal, backpal : dword;
    txtofs : dword;
    txt : UTF8string;
begin
 with TBox[boxnum] do begin
  // safety, clipping not performed
  if (boxlocxp_r < 0) or (boxlocyp_r < 0)
  or (boxlocxp_r + longint(boxsizexp_r) > longint(sysvar.mv_WinSizeX))
  or (boxlocyp_r + longint(boxsizeyp_r) > longint(sysvar.mv_WinSizeY))
  then exit;

  textpal := xpal[style.textcolor.r shr 4][style.textcolor.g shr 4][style.textcolor.b shr 4] and $F;
  backpal := xpal[style.basecolor[0].r shr 4][style.basecolor[0].g shr 4][style.basecolor[0].b shr 4] and $F;
  SetColor(textpal + backpal shl 4);

  // Fill the box rectangle.
  {$ifdef WINDOWS}
  cellcount := boxsizexp_r * boxsizeyp_r;
  if dword(length(AsciiBuf)) < cellcount then begin setlength(AsciiBuf, 0); setlength(AsciiBuf, cellcount); end;
  filldword(AsciiBuf[0], cellcount, backpal shl 20 + $20);
  CrtWriteConOut(@AsciiBuf[0], boxsizexp_r, boxsizeyp_r, boxlocxp_r, boxlocyp_r, dword(boxlocxp_r) + boxsizexp_r, dword(boxlocyp_r) + boxsizeyp_r);
  {$else}
  for y := boxlocyp_r to boxlocyp_r + boxsizeyp_r - 1 do begin
   GotoXY(boxlocxp_r, y);
   write(space(boxsizexp_r));
  end;
  {$endif}

  // If the box is showing text, write the text one line at a time, starting
  // from the scroll-offset line.
  if boxstate = BOXSTATE_SHOWTEXT then begin
   txtofs := 0; ivar := 0;
   y := contentwinscrollofsp;
   if y > txtlinebreakcount then txtofs := txtlength
   else if y <> 0 then txtofs := txtlinebreaklist[y - 1];

   while txtofs < txtlength do begin
    GotoXY(dword(boxlocxp_r) + marginleftp, dword(boxlocyp_r) + margintopp + ivar);
    txt := '';
    jvar := txtlength;
    if y < txtlinebreakcount then jvar := txtlinebreaklist[y];
    inc(y);
    dec(jvar, txtofs);
    if jvar <> 0 then begin
     setlength(txt, jvar);
     move(txtcontent[txtofs], txt[1], jvar);
     UTF8Write(txt);
     inc(txtofs, jvar);
    end;
    // Stop writing when content window bottom reached.
    inc(ivar);
    if ivar >= contentwinsizeyp then break;
   end;
  end;

 end;
 SetColor(7);
 GotoXY(0, sysvar.mv_WinSizeY - 1);
end;

// ------------------------------------------------------------------

{$include sakurender-all.pas}

procedure Renderer;
// Handles all visual output into outputbuffy^.
var refrect : dword;
begin
 refrect := numfresh;
 while refrect <> 0 do begin
  dec(refrect);

  // Draw stuff.
  RenderGobs(refresh[refrect], mv_OutputBuffy);

  // Present drawing to user.
  with refresh[refrect] do
   BlitzAscii(x1p, y1p, x2p, y2p);
 end;

 // Reset the refresh regions.
 if length(refresh) > 24 then begin
  setlength(refresh, 0); setlength(refresh, 16);
 end;
 numfresh := 0;

 // Textboxes in need of redrawing are completely reprinted in con mode.
 if gamevar.hideboxes = 0 then
 for refrect := 0 to high(TBox) do
  if (TBox[refrect].boxstate <> BOXSTATE_NULL)
  and (TBox[refrect].needsredraw)
  then begin
   BlitzBox(refrect);
   TBox[refrect].needsredraw := FALSE;
  end;
end;
