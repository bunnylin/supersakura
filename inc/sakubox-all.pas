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

procedure HideBoxes(dohide : boolean);
var ivar : dword;
    hideval : byte;
begin
 hideval := 0;
 if dohide then hideval := 1;

 for ivar := high(TBox) downto 0 do
  with TBox[ivar] do begin
   if (style.hidable and 1) = (hideval xor 1) then begin
    style.hidable := style.hidable and $FE + hideval;
    needsredraw := NOT dohide;
    if boxstate <> BOXSTATE_NULL then
     AddRefresh(boxlocxp_r, boxlocyp_r, boxlocxp_r + longint(boxsizexp_r), boxlocyp_r + longint(boxsizeyp_r));
   end;
  end;
 gamevar.hideboxes := hideval;
end;

procedure ClearTextbox(boxnum : longint);
// Clears a textbox's contents, updates all relevant variables.
begin
 if (boxnum >= length(TBox)) or (boxnum < 0) then exit;
 with TBox[boxnum] do begin
  contentfullrows := 0; contentfullheightp := 0; contentwinscrollofsp := 0;
  contentbuftextvalid := FALSE;
  txtlength := 0; txtescapecount := 0; txtlinebreakcount := 0;
  if length(txtcontent) > 4096 then setlength(txtcontent, length(txtcontent) shr 1);
  if boxstate in [BOXSTATE_NULL, BOXSTATE_EMPTY, BOXSTATE_VANISHING] = FALSE
  then boxstate := BOXSTATE_EMPTY;
 end;
end;

procedure SnapBox(boxnum : dword);
// Snaps the rendering location of the given box pixel-perfectly to the
// rendering location of the box's snapto-neighbor. You should only ever snap
// to lower-numbered boxes, or you risk lagging the snapto-neighbor's
// position by one frame.
var ownx1, ownx2, owny1, owny2 : longint;
    neighx1, neighx2, neighy1, neighy2 : longint;
    leftdist, rightdist, topdist, bottomdist : dword;
begin
 with TBox[TBox[boxnum].snaptobox] do begin
  neighx1 := boxlocxp_r;
  neighx2 := boxlocxp_r + longint(boxsizexp_r);
  neighy1 := boxlocyp_r;
  neighy2 := boxlocyp_r + longint(boxsizeyp_r);
 end;
 with TBox[boxnum] do begin
  ownx1 := boxlocxp_r;
  ownx2 := boxlocxp_r + longint(boxsizexp_r);
  owny1 := boxlocyp_r;
  owny2 := boxlocyp_r + longint(boxsizeyp_r);

  leftdist := $FFFFFFFF; rightdist := $FFFFFFFF; topdist := $FFFFFFFF; bottomdist := $FFFFFFFF;

  // test top and bottom snap distance if boxes' x areas overlap
  if (ownx1 <= neighx2) and (ownx2 >= neighx1) then begin
   topdist := abs(owny2 - neighy1);
   bottomdist := abs(neighy2 - owny1);
  end;
  // test left and right snap distance if boxes' y areas overlap
  if (owny1 <= neighy2) and (owny2 >= neighy1) then begin
   leftdist := abs(ownx2 - neighx1);
   rightdist := abs(neighx2 - ownx1);
  end;
  // pick closest snap distance and use it
  if (topdist <= leftdist) and (topdist <= rightdist) and (topdist <= bottomdist) then
   boxlocyp_r := neighy1 - boxsizeyp_r
  else if (rightdist <= leftdist) and (rightdist <= bottomdist) then
   boxlocxp_r := neighx2
  else if (bottomdist <= leftdist) then
   boxlocyp_r := neighy2
  else if (leftdist <> $FFFFFFFF) then
   boxlocxp_r := neighx1 - boxsizexp_r;
 end;
end;

procedure ScrollBoxTo(boxnum : dword; scrollto : dword); inline;
begin
 //if boxnum >= dword(length(TBox)) then exit;
 with TBox[boxnum] do begin
  contentwinscrollofsp := scrollto;
  finalbufvalid := FALSE;
  needsredraw := TRUE;
 end;
end;

procedure PrintBox(boxnum : dword; const newtxt : UTF8string);
// Adds the given string to the box's text content. Separates escape codes
// from displayable text first, and immediately dereferences variables.
var ivar, jvar : dword;
    inofs : dword;
    refstr : string[63];

  procedure addescape(code : char; more : boolean);
  var reflen : dword;
  begin
   with TBox[boxnum] do begin
    // Expand the escape list if needed.
    if txtescapecount >= dword(length(txtescapelist)) then setlength(txtescapelist, length(txtescapelist) + 8);
    // Grab the extra data, if available.
    if more then begin
     reflen := 0;
     inc(inofs);
     while (inofs <= dword(length(newtxt))) and (newtxt[inofs] <> ';') do begin
      inc(reflen);
      refstr[reflen] := newtxt[inofs];
      inc(inofs);
     end;
     byte(refstr[0]) := reflen;
     case code of
       '$': begin
        // Special handling: variable dereference is immediate.
        GetStrVar(refstr);
        if boxlanguage < dword(length(stringstash))
        then PrintBox(boxnum, stringstash[boxlanguage])
        else PrintBox(boxnum, stringstash[0]);
        // Expand txtcontent to ensure the rest of the current string fits.
        reflen := txtlength + dword(length(newtxt)) - inofs + 8;
        if reflen >= dword(length(txtcontent))
        then setlength(txtcontent, reflen + 64);
        exit;
       end;
       'c': begin
        txtescapelist[txtescapecount].escapedata := ExpandColorRef(longint(valhex(refstr)));
       end;
       ':': begin
        // Special handling: emotes must be followed by an implicit space.
       end;
     end;
    end;
    // Save the new escape.
    txtescapelist[txtescapecount].escapeofs := txtlength;
    txtescapelist[txtescapecount].escapecode := byte(code);
    inc(txtescapecount);
   end;
  end;

begin
 with TBox[boxnum] do begin
  // Expand the txtcontent to fit estimated input string size.
  if txtlength + dword(length(newtxt)) + 8 >= dword(length(txtcontent))
  then setlength(txtcontent, txtlength + dword(length(newtxt)) + 64);

  // Parse newtxt.
  inofs := 0;
  while inofs < dword(length(newtxt)) do begin
   inc(inofs);
   // Handle normal character.
   if newtxt[inofs] <> '\' then begin
    // Get character's UTF-8 byte count.
    // 1: 0xxxxxxx
    // 2: 110xxxxx 10xxxxxx
    // 3: 1110xxxx 10xxxxxx 10xxxxxx
    // 4: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    case byte(newtxt[inofs]) of
      $20..$7F: ivar := 0;
      $C0..$DF: ivar := 1;
      $E0..$EF: ivar := 2;
      $F0..$F7: ivar := 3;
      else begin
       LogError('Print box ' + strdec(boxnum) + ' bad UTF8 in: ' + newtxt); break;
      end;
    end;
    // Save the character.
    txtcontent[txtlength] := byte(newtxt[inofs]);
    inc(txtlength);
    jvar := ivar;
    while jvar <> 0 do begin
     inc(inofs);
     if (inofs > dword(length(newtxt)))
     or (byte(newtxt[inofs]) and $C0 <> $80)
     then begin
      LogError('Print box ' + strdec(boxnum) + ' bad UTF8 in: ' + newtxt); break;
     end;
     txtcontent[txtlength] := byte(newtxt[inofs]);
     inc(txtlength);
     dec(jvar);
    end;
    continue;
   end;

   // Handle escape code.
   if inofs < dword(length(newtxt)) then inc(inofs);
   case byte(newtxt[inofs]) of
     byte('0'): inc(inofs); // empty char
     byte('n'),byte('?'),byte('.'),byte('b'),byte('B'),byte('d'),byte('L'),byte('C'),byte('R'):
       addescape(newtxt[inofs], FALSE);
     byte('$'),byte(':'),byte('c'):
       addescape(newtxt[inofs], TRUE);
     $80..$FF: begin
      LogError('Print box ' + strdec(boxnum) + ' bad escape code in: ' + newtxt); break;
     end;
     else begin
      txtcontent[txtlength] := byte(newtxt[inofs]);
      inc(txtlength);
     end;
   end;
  end;

  contentbuftextvalid := FALSE;
  case boxstate of
    BOXSTATE_NULL, BOXSTATE_VANISHING: boxstate := BOXSTATE_APPEARING;
    BOXSTATE_EMPTY: boxstate := BOXSTATE_SHOWTEXT;
  end;
 end;
end;

// ------------------------------------------------------------------

procedure SetBoxParam(boxnum : longint; bpname : UTF8string; bpval : longint; usebpval : boolean);
  procedure bperr(const errtxt : UTF8string);
  begin
   LogError('SetBoxParam box ' + strdec(boxnum) + ' ' + bpname + '=' + strdec(bpval) + ': ' + errtxt);
  end;
begin
 if (boxnum < 0) or (boxnum >= length(TBox)) then begin bperr('no such box'); exit; end;
 if bpname = '' then begin bperr('no param name'); exit; end;

 with TBox[boxnum] do begin
  contentbufparamvalid := FALSE;

  case lowercase(bpname) of
    'viewport':
    if usebpval = FALSE then inviewport := 0 else
    if (bpval >= 0) and (bpval < length(viewport)) then inviewport := bpval
    else bperr('viewport out of range');

    'fontheight':
    if usebpval = FALSE then origfontheight := 1311 else // 16px/400px
    if (bpval > 0) then origfontheight := bpval
    else bperr('height <= 0');

    'mincols':
    if usebpval = FALSE then contentwinmincols := 0 else
    if (bpval >= 0) then contentwinmincols := bpval
    else bperr('mincols <= 0');

    'minrows':
    if usebpval = FALSE then contentwinminrows := 0 else
    if (bpval >= 0) then contentwinminrows := bpval
    else bperr('minrows <= 0');

    'maxcols':
    if usebpval = FALSE then contentwinmaxcols := $FFFFFFFF else
    if (bpval >= 0) then contentwinmaxcols := bpval
    else bperr('maxcols <= 0');

    'maxrows':
    if usebpval = FALSE then contentwinmaxrows := $FFFFFFFF else
    if (bpval >= 0) then contentwinmaxrows := bpval
    else bperr('maxrows <= 0');

    'minsizex':
    if usebpval = FALSE then contentwinminsizex := 0 else
    if (bpval >= 0) then contentwinminsizex := bpval
    else bperr('minsizex <= 0');

    'minsizey':
    if usebpval = FALSE then contentwinminsizey := 0 else
    if (bpval >= 0) then contentwinminsizey := bpval
    else bperr('minsizey <= 0');

    'maxsizex':
    if usebpval = FALSE then contentwinmaxsizex := $FFFFFFFF else
    if (bpval >= 0) then contentwinmaxsizex := bpval
    else bperr('maxsizex <= 0');

    'maxsizey':
    if usebpval = FALSE then contentwinmaxsizey := $FFFFFFFF else
    if (bpval >= 0) then contentwinmaxsizey := bpval
    else bperr('maxsizey <= 0');

    'marginleft':
    if usebpval = FALSE then marginleft := 768 else
    if (bpval >= 0) then marginleft := bpval
    else bperr('margin <= 0');

    'marginright':
    if usebpval = FALSE then marginright := 768 else
    if (bpval >= 0) then marginright := bpval
    else bperr('margin <= 0');

    'margintop':
    if usebpval = FALSE then margintop := 400 else
    if (bpval >= 0) then margintop := bpval
    else bperr('margin <= 0');

    'marginbottom':
    if usebpval = FALSE then marginleft := 400 else
    if (bpval >= 0) then marginbottom := bpval
    else bperr('margin <= 0');

    'ax','anchorx':
    if usebpval = FALSE then anchorx := 0 else anchorx := bpval;
    'ay','anchory':
    if usebpval = FALSE then anchory := 0 else anchory := bpval;
    'x','lx','locx':
    if usebpval = FALSE then boxlocx := 0 else boxlocx := bpval;
    'y','ly','locy':
    if usebpval = FALSE then boxlocy := 0 else boxlocy := bpval;

    'snaptobox':
    if usebpval = FALSE then snaptobox := 0
    else if (bpval < 0) then bperr('snap < 0')
    else if (bpval >= boxnum) then bperr('can''t snap to box above self')
    else snaptobox := bpval;

    'boxlanguage':
    if usebpval = FALSE then boxlanguage := 0
    else if bpval < 0 then bperr('language < 0')
    else boxlanguage := bpval;

    'exportcontentto':
    if usebpval = FALSE then exportcontentto := 0
    else if bpval < 0 then bperr('export to < 0')
    else exportcontentto := bpval;

    'textcolor':
    if usebpval = FALSE then dword(style.textcolor) := 0
    else if bpval < 0 then bperr('color < 0')
    else if bpval > $FFFF then bperr('color > $FFFF')
    else dword(style.textcolor) := ExpandColorRef(bpval);

    'basecolor': begin
     if usebpval = FALSE then bpval := $AAAF;
     if bpval < 0 then bperr('color < 0')
     else if bpval > $FFFF then bperr('color > $FFFF')
     else begin
      style.basefill := 1; // flat
      dword(style.basecolor[0]) := ExpandColorRef(bpval);
      dword(style.basecolor[1]) := dword(style.basecolor[0]);
      dword(style.basecolor[2]) := dword(style.basecolor[0]);
      dword(style.basecolor[3]) := dword(style.basecolor[0]);
     end;
    end;
    'basecolor0':
    if usebpval = FALSE then dword(style.basecolor[0]) := ExpandColorRef($AAAF)
    else if bpval < 0 then bperr('color < 0')
    else if bpval > $FFFF then bperr('color > $FFFF')
    else dword(style.basecolor[0]) := ExpandColorRef(bpval);
    'basecolor1':
    if usebpval = FALSE then dword(style.basecolor[1]) := ExpandColorRef($AAAF)
    else if bpval < 0 then bperr('color < 0')
    else if bpval > $FFFF then bperr('color > $FFFF')
    else dword(style.basecolor[1]) := ExpandColorRef(bpval);
    'basecolor2':
    if usebpval = FALSE then dword(style.basecolor[2]) := ExpandColorRef($AAAF)
    else if bpval < 0 then bperr('color < 0')
    else if bpval > $FFFF then bperr('color > $FFFF')
    else dword(style.basecolor[2]) := ExpandColorRef(bpval);
    'basecolor3':
    if usebpval = FALSE then dword(style.basecolor[3]) := ExpandColorRef($AAAF)
    else if bpval < 0 then bperr('color < 0')
    else if bpval > $FFFF then bperr('color > $FFFF')
    else dword(style.basecolor[3]) := ExpandColorRef(bpval);
    'basefill':
    if usebpval = FALSE then style.basefill := 2
    else if bpval in [0..2] = FALSE then bperr('bad fill type')
    else style.basefill := bpval;

    'texleftedge':
    if usebpval = FALSE then style.textureleftorigp := 0
    else if bpval < 0 then bperr('edge < 0')
    else style.textureleftorigp := bpval;
    'texrightedge':
    if usebpval = FALSE then style.texturerightorigp := 0
    else if bpval < 0 then bperr('edge < 0')
    else style.texturerightorigp := bpval;
    'textopedge':
    if usebpval = FALSE then style.texturetoporigp := 0
    else if bpval < 0 then bperr('edge < 0')
    else style.texturetoporigp := bpval;
    'texbottomedge':
    if usebpval = FALSE then style.texturebottomorigp := 0
    else if bpval < 0 then bperr('edge < 0')
    else style.texturebottomorigp := bpval;

    'blendmode':
    if usebpval = FALSE then style.boxblendmode := 0
    else if bpval in [0..1] = FALSE then bperr('bad blend mode')
    else style.boxblendmode := bpval;
    'bevel':
    if usebpval = FALSE then style.dobevel := 0
    else if bpval in [0..1] = FALSE then bperr('bad bevel type')
    else style.dobevel := bpval;
    'textalign':
    if usebpval = FALSE then style.textalign := 0
    else if bpval in [0..2] = FALSE then bperr('bad align type')
    else style.textalign := bpval;

    'poptype':
    if usebpval = FALSE then style.poptype := 1
    else if bpval in [0..3] = FALSE then bperr('bad pop type')
    else style.poptype := bpval;
    'poptime':
    if usebpval = FALSE then begin
     popruntime := dword(popruntime) * 384 div style.poptime;
     style.poptime := 384;
    end else
    if bpval < 0 then bperr('time < 0')
    else begin
     popruntime := dword(popruntime) * dword(bpval) div style.poptime;
     style.poptime := bpval;
    end;

    'freescrollable':
    if usebpval = FALSE then style.freescrollable := FALSE
    else style.freescrollable := bpval <> 0;
    'autowaitkey':
    if usebpval = FALSE then style.autowaitkey := FALSE
    else style.autowaitkey := bpval <> 0;
    'autovanish':
    if usebpval = FALSE then style.autovanish := TRUE
    else style.autovanish := bpval <> 0;
    'hidable':
    if (usebpval = FALSE) or (bpval <> 0)
    then style.hidable := style.hidable or 1 // hidable
    else style.hidable := style.hidable and $FE; // not hidable
    'negatebkg':
    if usebpval = FALSE then style.negatebkg := FALSE
    else style.negatebkg := bpval <> 0;

    else bperr('unknown param');
  end;
 end;
end;

procedure RemoveBoxDecoration(boxnum : longint; decornamu : UTF8string);
var ivar, jvar : dword;
begin
 if (boxnum < 0) or (boxnum >= length(TBox)) then LogError('RemoveBoxDecor box out of range: ' + strdec(boxnum))
 else begin
  if decornamu = '' then setlength(TBox[boxnum].style.decorlist, 0)
  else begin
   decornamu := upcase(decornamu);
   ivar := length(TBox[boxnum].style.decorlist);
   while ivar <> 0 do begin
    dec(ivar);
    if TBox[boxnum].style.decorlist[ivar].decorname = decornamu then begin
     jvar := ivar + 1;
     while jvar < dword(length(TBox[boxnum].style.decorlist)) do begin
      TBox[boxnum].style.decorlist[jvar - 1] := TBox[boxnum].style.decorlist[jvar];
      inc(jvar);
     end;
     setlength(TBox[boxnum].style.decorlist, length(TBox[boxnum].style.decorlist) - 1);
    end;
   end;
  end;
  TBox[boxnum].basebufvalid := FALSE;
 end;
end;

procedure FlowTextboxContent(boxnum : dword);
// Builds a list of all implicit and explicit linebreaks in the box's text,
// while calculating the best box content dimensions. The box's text is
// assumed to be valid UTF-8.
var ivar, jvar, curwidthp, maxwidthp : dword;
    segstart, seglen, segend, segwidthp : dword;
    nextesc : dword;
    worktxt : array[0..255] of byte;
begin
 worktxt[0] := 0; // silence a compiler warning
 with TBox[boxnum] do begin
  txtlinebreakcount := 0;
  segstart := 0;
  curwidthp := 0;
  nextesc := 0;
  maxwidthp := contentwinmaxsizexp - style.outlinemarginleftp - style.outlinemarginrightp;
  if maxwidthp > $FFFF then maxwidthp := $FFFF;
  contentwinsizexp := 0;
  {$ifndef sakucon}
  TTF_SetFontStyle(fonth, 0);
  // Calculate choice column width if needed.
  if (choicematic.colwidthp = 0) and (boxnum = choicematic.choicebox) then
   choicematic.colwidthp := maxwidthp div choicematic.numcolumns;
  {$endif}

  if txtlength <> 0 then
  repeat
   // Is there an escape code at the current character?
   if (nextesc < txtescapecount)
   and (txtescapelist[nextesc].escapeofs = segstart)
   then begin
    case txtescapelist[nextesc].escapecode of
      {$ifndef sakucon}
      byte('B'): TTF_SetFontStyle(fonth, TTF_STYLE_BOLD);
      byte('b'): TTF_SetFontStyle(fonth, 0);
      // Choice item!
      byte('?'): begin
       ivar := curwidthp + choicematic.colwidthp - 1;
       dec(ivar, ivar mod choicematic.colwidthp);
       if ivar >= maxwidthp then begin
        if txtlinebreakcount >= dword(length(txtlinebreaklist)) then setlength(txtlinebreaklist, length(txtlinebreaklist) + 8);
        txtlinebreaklist[txtlinebreakcount] := segstart;
        inc(txtlinebreakcount);
        if contentwinsizexp < curwidthp then contentwinsizexp := curwidthp;
        curwidthp := 0;
       end
       else curwidthp := ivar;
      end;
      {$endif}
      // Line break!
      byte('n'): begin
       if txtlinebreakcount >= dword(length(txtlinebreaklist)) then setlength(txtlinebreaklist, length(txtlinebreaklist) + 8);
       txtlinebreaklist[txtlinebreakcount] := segstart;
       inc(txtlinebreakcount);
       if contentwinsizexp < curwidthp then contentwinsizexp := curwidthp;
       curwidthp := 0;
      end;
    end;
    inc(nextesc);
    continue;
   end;

   // Best guess how many characters may fit on this row...
   segend := segstart + $FF;
   // Check the distance to the next escape code.
   if (nextesc < txtescapecount)
   and (txtescapelist[nextesc].escapeofs < segend)
   then segend := txtescapelist[nextesc].escapeofs
   // Check distance to the end of the string.
   else if segend > txtlength + 1 then segend := txtlength + 1
   // Limit to 256 bytes at most. Find the nearest UTF-8 char initial byte.
   else while (txtcontent[segend] and $C0 = $80) do dec(segend);

   // Copy the byte sequence into worktxt for width analysis.
   seglen := segend - segstart;
   move(txtcontent[segstart], worktxt[0], seglen);

   segwidthp := GetUTF8Size(@worktxt[0], seglen, boxnum);
   // Does the current segment fit on the current row?
   if curwidthp + segwidthp > maxwidthp then begin
    // It doesn't fit. Cut the segment to an approximately fitting length.
    seglen := seglen * (maxwidthp - curwidthp) div segwidthp;
    // Find the nearest prior UTF-8 char initial byte.
    segend := segstart + seglen;
    while (segend > segstart) and (txtcontent[segend] and $C0 = $80) do dec(segend);
    seglen := segend - segstart;
    // Check the size again.
    segwidthp := GetUTF8Size(@worktxt[0], seglen, boxnum);

    if curwidthp + segwidthp > maxwidthp then begin
     // Approximately sized segment doesn't fit. Scan backwards to first fit.
     repeat
      repeat
       dec(segend);
      until (segend = segstart) or (txtcontent[segend] and $C0 <> $80);
      seglen := segend - segstart;
      segwidthp := GetUTF8Size(@worktxt[0], seglen, boxnum);
     until curwidthp + segwidthp <= maxwidthp;
    end
    else begin
     // Approximately sized segment fits. Scan forward to first non-fitting.
     repeat
      repeat
       inc(segend);
      until (txtcontent[segend] and $C0 <> $80);
      segwidthp := GetUTF8Size(@worktxt[0], segend - segstart, boxnum);
     until curwidthp + segwidthp > maxwidthp;
     // Back one character to last fitting.
     repeat
      dec(segend);
     until (txtcontent[segend] and $C0 <> $80);
     seglen := segend - segstart;
    end;

    // Scan backward until the first soft linebreaking character. Breaks are
    // allowed after a normal space, and after any CJK symbol. This could be
    // refined, since not all CJK symbols are actually linebreak-friendly.
    while segend > segstart do begin
     ivar := 0;
     repeat
      dec(segend); inc(ivar);
     until (txtcontent[segend] and $C0 <> $80);
     jvar := 0;
     case ivar of
      1: jvar := txtcontent[segend];
      2: jvar := txtcontent[segend] shl 8 + txtcontent[segend + 1];
      3: jvar := txtcontent[segend] shl 16 + txtcontent[segend + 1] shl 8 + txtcontent[segend + 2];
      4: jvar := txtcontent[segend] shl 24 + txtcontent[segend + 1] shl 16 + txtcontent[segend + 2] shl 8 + txtcontent[segend + 3];
     end;
     // 2E80..D7AF   = E2BA80..ED9EAF (mishmash of all basic CJK)
     // FF01..FF60   = EFBC81..EFBDA0 (doublewidth ascii characters)
     // FFE0..FFE6   = EFBFA0..EFBFA6 (extra CJK punctuation)
     // 20000..2CEAF = F0A08080..F0ACBAAF (tons of extended ideographs)
     if (jvar = $20)
     or (jvar >= $E2BA80) and (jvar <= $ED9EAF)
     or (jvar >= $F0A08080) and (jvar <= $F0ACBAAF)
     then begin inc(segend, ivar); break; end;
    end;
    // No soft linebreaking characters? Add a linebreak at the maximum line
    // length if this is the only thing on the current row, else linebreak
    // before the current segment.
    if segend = segstart then begin
     if curwidthp = 0 then segend := segstart + seglen
     else begin
      if txtlinebreakcount >= dword(length(txtlinebreaklist)) then setlength(txtlinebreaklist, length(txtlinebreaklist) + 8);
      txtlinebreaklist[txtlinebreakcount] := segstart;
      inc(txtlinebreakcount);
      if contentwinsizexp < curwidthp then contentwinsizexp := curwidthp;
      curwidthp := 0;
      continue;
     end;
    end
    else seglen := segend - segstart;
   end;

   // We now have a segment that fits on the current row.
   inc(curwidthp, GetUTF8Size(@worktxt[0], seglen, boxnum));
   inc(segstart, seglen);

  until segstart > txtlength;

  // Recalculate the content dimensions. ContentWinSizeXp will be the largest
  // calculated row width.
  if contentwinsizexp < curwidthp then contentwinsizexp := curwidthp;
  // Enforce a minimum content width. (The maximum width was already enforced
  // above, causing all the implicit linebreaks.)
  if contentwinsizexp < contentwinminsizexp then contentwinsizexp := contentwinminsizexp + style.outlinemarginleftp + style.outlinemarginrightp;

  contentfullrows := txtlinebreakcount + 1;
  contentfullheightp := contentfullrows * lineheightp;
  contentwinsizeyp := contentfullheightp;
  // Enforce content window min and max height.
  if contentwinsizeyp > contentwinmaxsizeyp then contentwinsizeyp := contentwinmaxsizeyp;
  if contentwinsizeyp < contentwinminsizeyp then contentwinsizeyp := contentwinminsizeyp;

  // The full box size is always simply the content window plus margins.
  boxsizexp := contentwinsizexp + marginleftp + marginrightp;
  boxsizeyp := contentwinsizeyp + margintopp + marginbottomp;
 end;
end;

procedure TextBoxer(tickcount : dword);
// Called by main loop. Recalculates textbox parameters and makes sure all
// buffers are up to date, so Renderer can just blit the final buffer of
// every visible textbox.
var boxnum : dword;
    oldx1p, oldy1p, oldsxp, oldsyp : longint;

  procedure updateconbufparams; inline;
  var ivar, jvar : dword;
  begin
   with TBox[boxnum] do begin
    // Calculate the font height.
    fontheight := (origfontheight * sysvar.uimagnification + 16384) shr 15;
    ivar := (fontheight * viewport[inviewport].viewportsizeyp + 16384) shr 15;
    if ivar <> reqfontheightp then GetNewFont(boxnum, ivar);
    // Calculate the pixel location.
    if boxlocx >= 0
    then boxlocxp := (boxlocx * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15
    else boxlocxp := -((-boxlocx * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15);
    inc(boxlocxp, viewport[inviewport].viewportx1p);
    if boxlocy >= 0
    then boxlocyp := (boxlocy * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15
    else boxlocyp := -((-boxlocy * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15);
    inc(boxlocyp, viewport[inviewport].viewporty1p);
    // Calculate the margins.
    marginleftp := (marginleft * viewport[inviewport].viewportsizexp + 16384) shr 15;
    marginrightp := (marginright * viewport[inviewport].viewportsizexp + 16384) shr 15;
    margintopp := (margintop * viewport[inviewport].viewportsizeyp + 16384) shr 15;
    marginbottomp := (marginbottom * viewport[inviewport].viewportsizeyp + 16384) shr 15;
    // Check the texture image, if any.
    if (style.texturetype <> 0) and (style.texturename <> '') then begin
     ivar := GetPNG(style.texturename);
     if ivar = 0 then begin
      style.texturename := '';
      style.texturetype := 0;
     end
     else begin
      if style.textureframeindex >= PNGlist[ivar].framecount
      then style.textureframeindex := 0;
      // Calculate the PNG margins fitted to the box's viewport, and the
      // texture's size in the viewport.
      jvar := PNGlist[ivar].origresx shr 1;
      style.textureleftp := (style.textureleftorigp * viewport[inviewport].viewportsizexp + jvar) div PNGlist[ivar].origresx;
      style.texturerightp := (style.texturerightorigp * viewport[inviewport].viewportsizexp + jvar) div PNGlist[ivar].origresx;
      style.texturesizexp := (PNGlist[ivar].origsizexp * viewport[inviewport].viewportsizexp + jvar) div PNGlist[ivar].origresx;
      jvar := PNGlist[ivar].origresy shr 1;
      style.texturetopp := (style.texturetoporigp * viewport[inviewport].viewportsizeyp + jvar) div PNGlist[ivar].origresy;
      style.texturebottomp := (style.texturebottomorigp * viewport[inviewport].viewportsizeyp + jvar) div PNGlist[ivar].origresy;
      style.texturesizeyp := (PNGlist[ivar].origsizeyp * viewport[inviewport].viewportsizeyp + jvar) div PNGlist[ivar].origresy;
     end;
    end;
    // Update font outline pixel sizes, if any.
    style.outlinemargintopp := 0; style.outlinemarginbottomp := 0;
    style.outlinemarginleftp := 0; style.outlinemarginrightp := 0;
    {$ifndef sakucon}
    ivar := length(style.outline);
    while ivar <> 0 do begin
     dec(ivar);
     style.outline[ivar].thicknessp := (style.outline[ivar].thickness * viewport[inviewport].viewportsizeyp + 16384) shr 15;
     if style.outline[ivar].ofsx >= 0
     then style.outline[ivar].ofsxp := (style.outline[ivar].ofsx * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15
     else style.outline[ivar].ofsxp := -((-style.outline[ivar].ofsx * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15);
     if style.outline[ivar].ofsy >= 0
     then style.outline[ivar].ofsyp := (style.outline[ivar].ofsy * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15
     else style.outline[ivar].ofsyp := -((-style.outline[ivar].ofsy * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15);

     longint(jvar) := longint(style.outline[ivar].thicknessp) - style.outline[ivar].ofsxp;
     if longint(jvar) > longint(style.outlinemarginleftp) then style.outlinemarginleftp := jvar;
     longint(jvar) := longint(style.outline[ivar].thicknessp) + style.outline[ivar].ofsxp;
     if longint(jvar) > longint(style.outlinemarginrightp) then style.outlinemarginrightp := jvar;
     longint(jvar) := longint(style.outline[ivar].thicknessp) - style.outline[ivar].ofsyp;
     if longint(jvar) > longint(style.outlinemargintopp) then style.outlinemargintopp := jvar;
     longint(jvar) := longint(style.outline[ivar].thicknessp) + style.outline[ivar].ofsyp;
     if longint(jvar) > longint(style.outlinemarginbottomp) then style.outlinemarginbottomp := jvar;
    end;
    {$endif sakucon}
    // Calculate the line height.
    lineheightp := fontheightp + style.outlinemargintopp + style.outlinemarginbottomp;
    // Calculate the content window bounds.
    contentwinmaxsizexp := $FFFFFFFF;
    contentwinmaxsizeyp := $FFFFFFFF;
    if contentwinminsizex < $FFFF then
     contentwinminsizexp := (contentwinminsizex * viewport[inviewport].viewportsizexp + 16384) shr 15;
    if contentwinmaxsizex < $FFFF then
     contentwinmaxsizexp := (contentwinmaxsizex * viewport[inviewport].viewportsizexp + 16384) shr 15;
    if contentwinminsizey < $FFFF then
     contentwinminsizeyp := (contentwinminsizey * viewport[inviewport].viewportsizeyp + 16384) shr 15;
    if contentwinmaxsizey < $FFFF then
     contentwinmaxsizeyp := (contentwinmaxsizey * viewport[inviewport].viewportsizeyp + 16384) shr 15;
    if contentwinminrows < $FFFF then begin
     ivar := contentwinminrows * lineheightp;
     if ivar > contentwinminsizeyp then contentwinminsizeyp := ivar;
    end;
    if contentwinmaxrows < $FFFF then begin
     ivar := contentwinmaxrows * lineheightp;
     if ivar < contentwinmaxsizeyp then contentwinmaxsizeyp := ivar;
    end;
    if contentwinmincols < $FFFF then begin
     ivar := contentwinmincols * fontheightp + style.outlinemarginleftp + style.outlinemarginrightp;
     if ivar > contentwinminsizexp then contentwinminsizexp := ivar;
    end;
    if contentwinmaxcols < $FFFF then begin
     ivar := contentwinmaxcols * fontheightp + style.outlinemarginleftp + style.outlinemarginrightp;
     if ivar < contentwinmaxsizexp then contentwinmaxsizexp := ivar;
    end;

    contentbuftextvalid := FALSE;
    basebufvalid := FALSE;
    contentbufparamvalid := TRUE;
   end;
  end;

  procedure updateconbuftext; inline;
  var oldcxp, oldcyp : dword;
  begin
   with TBox[boxnum] do begin
    // Remember the previous content window pixel size.
    oldcxp := contentwinsizexp;
    oldcyp := contentwinsizeyp;
    // Figure out where implicit linebreaks go and how many rows there are.
    FlowTextboxContent(boxnum);
    {$ifndef sakucon}
    // Draw the full content buffer.
    RenderTextboxContent(boxnum);
    {$endif}

    // If the content window pixel size has changed, invalidate base buffer.
    // Also refresh the box's previous area, so if the new size is smaller,
    // extra box bits get drawn over.
    if (oldcxp <> contentwinsizexp) or (oldcyp <> contentwinsizeyp)
    then basebufvalid := FALSE;
    contentbuftextvalid := TRUE;
    finalbufvalid := FALSE;
    needsredraw := TRUE;
   end;
  end;

  procedure updatebasebuf; inline;
  begin
   with TBox[boxnum] do begin
    {$ifndef sakucon}
    BuildBoxBase(boxnum, FALSE);
    {$endif}
    basebufvalid := TRUE;
    finalbufvalid := FALSE;
    needsredraw := TRUE;
   end;
  end;

  procedure updatefinalbuf; inline;
  begin
   with TBox[boxnum] do begin
    {$ifndef sakucon}
    BuildFinalBox(boxnum);
    {$endif}
    finalbufvalid := TRUE;
   end;
  end;

begin
 for boxnum := 0 to high(TBox) do
  with TBox[boxnum] do if boxstate <> BOXSTATE_NULL then begin
   // Save the box's previous rendering location.
   oldx1p := boxlocxp_r; oldsxp := boxsizexp_r;
   oldy1p := boxlocyp_r; oldsyp := boxsizeyp_r;

   // Apply autovanish to visible empty boxes.
   if (boxstate = BOXSTATE_EMPTY) and (style.autovanish)
   then boxstate := BOXSTATE_VANISHING;

   // Handle timing for appearing/vanishing boxes.
   case boxstate of
     BOXSTATE_APPEARING: begin
      inc(popruntime, longint(tickcount));
      if (dword(popruntime) >= style.poptime) or (style.poptype = 0) then begin
       popruntime := style.poptime;
       finalbufvalid := FALSE;
       boxstate := BOXSTATE_SHOWTEXT;
       {if (choicematic.active) and (boxnum = choicematic.choicebox)
       then boxstate := BOXSTATE_SHOWTEXT;}
       needsredraw := TRUE;
      end;
     end;
     BOXSTATE_VANISHING: begin
      dec(popruntime, tickcount);
      if (popruntime <= 0) or (style.poptype = 0) then begin
       popruntime := 0;
       boxstate := BOXSTATE_NULL;
       // The box has vanished completely; draw over it.
       AddRefresh(boxlocxp_r, boxlocyp_r, boxlocxp_r + longint(boxsizexp_r), boxlocyp_r + longint(boxsizeyp_r));
       continue;
      end;
      needsredraw := TRUE;
     end;
   end;

   // Update content buffer parameters.
   if contentbufparamvalid = FALSE then updateconbufparams;
   // Update content buffer after text change.
   if contentbuftextvalid = FALSE then updateconbuftext;
   // Update base buffer parameters.
   if basebufvalid = FALSE then updatebasebuf;

   if needsredraw then begin
    // Calculate the precise rendering position.
    boxsizexp_r := boxsizexp;
    boxsizeyp_r := boxsizeyp;
    boxlocxp_r := boxlocxp - (longint(boxsizexp) * anchorx) shr 15;
    boxlocyp_r := boxlocyp - (longint(boxsizeyp) * anchory) shr 15;
    // Snap the rendering position to another box, if defined.
    if snaptobox <> 0 then SnapBox(boxnum);
    // Calculate pop-in/pop-out size if necessary.
    if boxstate in [BOXSTATE_APPEARING, BOXSTATE_VANISHING] then begin
     if style.poptype = 1 then begin
      boxsizexp_r := (boxsizexp * dword(popruntime) + style.poptime shr 1) div style.poptime;
      boxsizeyp_r := (boxsizeyp * dword(popruntime) + style.poptime shr 1) div style.poptime;
      boxlocxp_r := boxlocxp - (longint(boxsizexp) * anchorx) shr 15 + (boxsizexp - boxsizexp_r) shr 1;
      boxlocyp_r := boxlocyp - (longint(boxsizeyp) * anchory) shr 15 + (boxsizeyp - boxsizeyp_r) shr 1;
      {$ifndef sakucon}
      BuildBoxBase(boxnum, TRUE);
      TBox[boxnum].finalbufvalid := TRUE;
      {$endif}
     end;
    end;
    // Update the final buffer.
    if finalbufvalid = FALSE then updatefinalbuf;

    // If the rendering position has changed at all from the previous frame,
    // draw over the previous position.
    if (oldx1p <> boxlocxp_r) or (oldsxp <> longint(boxsizexp_r))
    or (oldy1p <> boxlocyp_r) or (oldsyp <> longint(boxsizeyp_r))
    then AddRefresh(oldx1p, oldy1p, oldx1p + longint(oldsxp), oldy1p + longint(oldsyp));

    {$ifndef sakucon}
    // If this is the choicebox, set the highlight.
    if (choicematic.active) and (boxnum = choicematic.choicebox)
    and (boxstate = BOXSTATE_SHOWTEXT)
    then HighlightChoice(MOVETYPE_INSTANT);

    if gamevar.hideboxes = 0 then
     // Graphical textboxes get drawn like any gob, so just add the box's
     // position as a refresh region.
     AddRefresh(boxlocxp_r, boxlocyp_r, boxlocxp_r + longint(boxsizexp_r), boxlocyp_r + longint(boxsizeyp_r));

    needsredraw := FALSE;
    {$else}
    if gamevar.hideboxes = 0 then
     // Console textboxes get special treatment. Because of the difficulty in
     // printing textbox content in console mode, boxes are always drawn
     // fully. To avoid partial draws or flickering as a box gets overdrawn
     // and then refreshed, exclude those refresh rects.
     RemoveRefresh(boxlocxp_r, boxlocyp_r, boxlocxp_r + longint(boxsizexp_r), boxlocyp_r + longint(boxsizeyp_r));
    {$endif}
   end;
  end;
end;
