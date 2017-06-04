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

function ShuntGobList(wedge : dword) : boolean;
// Makes space in gob[] at wedge, by pushing everything at that index and
// above upward by a step. Zeroes out the freed index. Can't move background
// gobs, or push anything above background gobs from below them.
// If the wedge index failed to be freed, returns FALSE, otherwise TRUE.
var ivar, jvar, nearestbkg : dword;
begin
 ShuntGobList := FALSE;
 if (wedge = 0) or (wedge >= dword(length(gob))) then exit;
 if IsGobValid(wedge) = FALSE then begin ShuntGobList := TRUE; exit; end;
 // Make sure there's space at the top of the array.
 if IsGobValid(length(gob) - 1) then InitGob(length(gob));
 // Identify the nearest background slot above the wedge index.
 nearestbkg := $FFFFFFFF;
 for ivar := length(viewport) - 1 downto 0 do
  if (viewport[ivar].backgroundgob >= wedge)
  and (viewport[ivar].backgroundgob < nearestbkg)
  then nearestbkg := viewport[ivar].backgroundgob;
 if nearestbkg = wedge then begin LogError('Can''t shunt a background'); exit; end;
 // Find the first free slot above the wedge index.
 ivar := wedge;
 repeat
  inc(ivar);
  if ivar = nearestbkg then begin LogError('No free space between wedge and next background'); exit; end;
 until IsGobValid(ivar) = FALSE;

 // Move gobs up a step.
 while ivar > wedge do begin
  gob[ivar] := gob[ivar - 1];
  dec(ivar);
  // Update this gob's kids.
  for jvar := ivar to length(gob) - 1 do
   if gob[jvar].parent = ivar then inc(gob[jvar].parent);
  // Update related effects.
  for jvar := high(fx) downto 0 do
   if fx[jvar].fxgob = ivar then inc(fx[jvar].fxgob);
  // Update events.
  if length(event.gob) <> 0 then for jvar := high(event.gob) downto 0 do
   if event.gob[jvar].gobnum = ivar then inc(event.gob[jvar].gobnum);
 end;

 // Zero out the freed index.
 gob[wedge].drawstate := 0;
 InitGob(wedge);
 ShuntGobList := TRUE;
end;

procedure CompressGobList;
// Rearranges the contents of gob[] to remove empty space, while retaining
// the relative order of existing gobs. Doesn't move background gobs. Leaves
// up to 12 free slots at the top.
var srci, desti, ivar, jvar : dword;
begin
 srci := 1; desti := 1;
 while srci < dword(length(gob)) do begin
  jvar := 0;
  for ivar := length(viewport) - 1 downto 0 do
   if srci = viewport[ivar].backgroundgob then begin
    inc(srci);
    desti := srci;
    inc(jvar);
    break;
   end;
  if jvar <> 0 then continue;

  if IsGobValid(srci) then begin
   if srci <> desti then begin
    gob[desti] := gob[srci];
    InitGob(srci);
    // Update this gob's kids.
    for jvar := srci + 1 to length(gob) - 1 do
     if gob[jvar].parent = srci then gob[jvar].parent := desti;
    // Update related effects.
    for jvar := high(fx) downto 0 do
     if fx[jvar].fxgob = srci then fx[jvar].fxgob := desti;
    // Update events.
    if length(event.gob) <> 0 then for jvar := high(event.gob) downto 0 do
     if event.gob[jvar].gobnum = srci then event.gob[jvar].gobnum := desti;
   end;
   inc(desti);
  end;
  inc(srci);
 end;

 ivar := length(gob) - desti;
 if ivar > 12 then setlength(gob, desti + 8);
end;

function AdoptGob(kid : dword) : dword;
// Compare the screen location of kid gob to all other visible gobs below its
// index in the same viewport. The first that completely contains the kid
// gets to be the parent, or by default, the viewport's background is.
// Note: size multipliers aren't handled yet and will mess up everything.
var ivar, jvar, kidPNG, parPNG : dword;
    kidx1, kidy1, kidx2, kidy2 : longint;
    parx1, pary1, parx2, pary2 : longint;
begin
 // Start out parentless.
 AdoptGob := $FFFFFFFF;
 // safety
 if (kid >= dword(length(gob))) or (kid = 0)
 or (gob[kid].inviewport >= dword(length(viewport)))
 or (kid <= viewport[gob[kid].inviewport].backgroundgob) then exit;
 //log('Adopting gob ' + strdec(kid) + ':' + gob[kid].gobnamu);

 // We'll need some metadata from the kid gob's graphic.
 kidPNG := GetPNG(gob[kid].gfxnamu);
 if kidPNG = 0 then begin
  LogError('Failed to find PNG: ' + gob[kid].gfxnamu);
  exit;
 end;

 // Calculate the kid gob's 32k coords in the viewport.
 // (xy1 are inclusive, xy2 are exclusive coordinates.)
 kidx1 := gob[kid].locx + PNGlist[kidPNG].origofsx;
 kidx2 := kidx1 + longint(PNGlist[kidPNG].origsizex);
 kidy1 := gob[kid].locy + PNGlist[kidPNG].origofsy;
 kidy2 := kidy1 + longint(PNGlist[kidPNG].origsizey);
 //log('kid loc: '+strdec(kidx1)+','+strdec(kidy1)+' to '+strdec(kidx2)+','+strdec(kidy2));

 // Scan gobs from kid down to this viewport's background.
 ivar := kid - 1;
 while ivar > viewport[gob[kid].inviewport].backgroundgob do begin
  // a parent must actually exist
  if (IsGobValid(ivar))
  // ...in the same viewport
  and (gob[ivar].inviewport = gob[kid].inviewport)
  // a parent must not vanish upon the next transition
  //and (gob[ivar].drawstate and $80 = 0)
  // and is already visible or will be upon the next transition
  //and ((gob[ivar].drawstate and 3 <> 0) or (gob[ivar].drawstate and $40 <> 0))
  // this single check wraps all of the above together
  and (gob[ivar].drawstate in [1..3,$40..$43])
  then begin
   // The parent candidate's own parents must meet the same criteria.
   jvar := gob[ivar].parent; parPNG := 0;
   while IsGobValid(jvar) do begin
    if gob[jvar].drawstate in [1..3,$40..$43] = FALSE then begin
     inc(parPNG); break; // nope, next candidate
    end;
    jvar := gob[jvar].parent;
   end;
   // Finally, does the parent candidates coords contain the kid?
   if parPNG = 0 then begin
    // get the PNG for metadata...
    parPNG := GetPNG(gob[ivar].gfxnamu);
    if parPNG <> 0 then begin
     // get the 32k coords...
     parx1 := gob[ivar].locx + PNGlist[parPNG].origofsx;
     parx2 := parx1 + longint(PNGlist[parPNG].origsizex);
     pary1 := gob[ivar].locy + PNGlist[parPNG].origofsy;
     pary2 := pary1 + longint(PNGlist[parPNG].origsizey);
     //log(gob[ivar].gfxnamu+' loc: '+strdec(parx1)+','+strdec(pary1)+' to '+strdec(parx2)+','+strdec(pary2));
     // check for containment...
     // (award +2 to fuzziness to allow for rounding error)
     if (parx1 - 2 <= kidx1) and (parx2 + 2 >= kidx2)
     and (pary1 - 2 <= kidy1) and (pary2 + 2 >= kidy2)
     // or, if this gob is a full-viewport bkg/overlay, that's also fine.
     or (parx1 <= 0) and (parx2 >= 32768)
     and (pary1 <= 0) and (pary2 >= 32768)
     then break;
    end;
   end;
  end;

  dec(ivar);
 end;

 {$note gob.adopt should inherit parent fx?}
 // It is decided! gob[ivar] shall be the parent!
 if IsGobValid(ivar) then AdoptGob := ivar
 // Or not, in which case become a child of the background.
 else AdoptGob := viewport[gob[kid].inviewport].backgroundgob;
end;

procedure MoveGob(gobnum : dword; deltax, deltay : longint);
// Call this to change an existing gob's screen position. This also makes
// sure all the gob's children are moved along. The delta values should be in
// 32k form, and may go off-screen. Refreshes the screen appropriately.
var ivar : dword;
begin
 if IsGobValid(gobnum) = FALSE then exit;
 if (deltax or deltay) = 0 then exit;

 with gob[gobnum] do begin
  // Place gob at new 32k coordinates.
  inc(locx, deltax);
  inc(locy, deltay);
  // Update the pixel position.
  UpdateGobLocp(gobnum);
 end;

 // Move all children by the same amount.
 ivar := gobnum + 1;
 while ivar < dword(length(gob)) do begin
  if (IsGobValid(ivar)) and (gob[ivar].parent = gobnum) then MoveGob(ivar, deltax, deltay);
  inc(ivar);
 end;
end;

procedure CreateGob(gfxname, gobname : UTF8string; gobtype, viewnum : dword;
  atx, aty, atz : longint);
// Creates a gob, initially hidden but set to become visible on the next
// transition. The gfxname must be an available graphic resource. The gobname
// is used to refer to the gob in script code; it may be empty, in which case
// the gfxname is used as the gobname. The gob will be in viewport viewnum.
// Gobtypes: 0 = slot, 1 = background, 2 = sprite, 3 = animation
// Initial 32k x and y coordinates can be added. A z-level can be defined,
// ensuring the gob remains below or above other gobs. The background is
// always z-level negative maxint.
var ivar : dword;
    gobindex : dword;
begin
 // Sanitise the given names.
 gfxname := upcase(copy(gfxname, 1, 31));
 if gobname = '' then gobname := gfxname
 else gobname := upcase(copy(gobname, 1, 31));

 if GetPNG(gfxname) = 0 then begin
  log('[!] Source image not found: ' + gfxname);
  exit;
 end;
 // Check parameter validity.
 if gobtype in [0..3] = FALSE then begin
  LogError('CreateGob: unknown gobtype ' + strdec(gobtype) + ' for ' + gobname); exit;
 end;
 if viewnum >= dword(length(viewport)) then begin
  LogError('CreateGob: viewport ' + strdec(viewnum) + ' out of range for ' + gobname); exit;
 end;

 // Does a gob by this same name already exist?
 ivar := length(gob);
 while ivar <> 0 do begin
  dec(ivar);
  if gob[ivar].gobnamu = gobname then begin
   // YES: mark the previous copy for removal at the next transition, but
   // inherit the anim vars.
   gob[ivar].drawstate := (gob[ivar].drawstate and $1F) or $80;
   {$note: todo inherit anim vars; delete gob imm?}
   break;
  end;
 end;

 // Backgrounds start out as foremost but non-interactable garage dragons.
 if gobtype = 1 then atz := $7FFFFFFF;

 // Acquire a suitable gob[] slot.
 if gobtype = 0 then begin
  // Slot gob goes in a specific slot.
  if atz < 0 then begin
   LogError('CreateGob: slot type must have z > 0'); exit;
  end;
  gobindex := atz;
 end else
 begin
  // Sprites and anims go in the first slot above the top gob on the same
  // z-level. Gobs are moved to make space if needed.
  // Find the top existing gob at or below the new gob's z-level...
  gobindex := length(gob) - 1;
  while gobindex > viewport[viewnum].backgroundgob do begin
   if (IsGobValid(gobindex)) and (gob[gobindex].zlevel <= atz) then break;
   dec(gobindex);
  end;
  // Use the first slot above that.
  inc(gobindex);
  // Make space as needed.
  if gobindex < dword(length(gob)) then
  if ShuntGobList(gobindex) = FALSE then exit;
 end;

 InitGob(gobindex); // if over existing gob, inherits drawstate? why?
 with gob[gobindex] do begin
  drawstate := $40;
  gobnamu := gobname;
  gfxnamu := gfxname;
  inviewport := viewnum;
  locx := atx;
  locy := aty;
  zlevel := atz;
  sizemultiplier := 32768;
  drawframe := 0;
  animseqp := 0;
  animtimer := $FFFFFFFF;

  if gobtype = 1 then begin
   parent := $FFFFFFFF;
   // Mark this gob as non-interactable until the next gfx.transition, at
   // which time this overwrites the background slot.
   drawstate := $20;
  end else
  if gobtype = 3 then begin
   ivar := GetPNG(gfxname);
   if (ivar <> 0) and (PNGlist[ivar].seqlen <> 0) then begin
    animtimer := 0; // needs fixin', switch to anim snippets
    drawstate := drawstate or 1; // animations are immediately visible
   end;
  end;

  dword(solidblit) := 0;
  alphaness := 255;
  UpdateGobSizep(gobindex);
  if gobtype <> 1 then parent := AdoptGob(gobindex);
 end;

 log('show ' + gfxname);
 //writeln('show ',gfxname,' as ',gobindex,':',gobname,' vp=',viewnum,' parent=',gob[gobindex].parent);
end;
