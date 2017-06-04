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

function NewFx(fibernum : longint) : dword;
// Returns a free FX[] slot for the given fiber, expands the array as needed.
// Use fiber -1 for non-fiber-specific effects.
begin
 NewFx := fxcount;
 inc(fxcount);
 // expand array
 if fxcount >= dword(length(fx)) then begin
  setlength(fx, length(fx) + 6);
  fillbyte(fx[fxcount], sizeof(fxtype) * 6, 0);
 end;
 // init new fx slot
 fillbyte(fx[NewFx], sizeof(fxtype), 0);
 with fx[NewFx] do begin
  fxfiber := fibernum;
  fxgob := $FFFFFFFF;
  fxbox := $FFFFFFFF;
 end;

 if (fibernum >= 0) and (dword(fibernum) < fibercount) then
  inc(fiber[fibernum].fxrefcount);
end;

procedure DeleteFx(fxnum : dword);
// Stops and removes the given effect. Moves the topmost active fx[] item to
// the freed slot.
begin
 if (fxnum >= fxcount) or (fxnum >= dword(length(fx))) then begin
  LogError('DeleteFx: index ' + strdec(fxnum) + ' out of range'); exit;
 end;
 if (fx[fxnum].fxfiber >= longint(fibercount)) or (fx[fxnum].fxfiber >= length(fiber)) then
  LogError('DeleteFx: no such fiber: ' + strdec(fx[fxnum].fxfiber));

 // Clean up the effect's effect.
 with fx[fxnum] do begin
  case kind of
    FX_SLEEP: begin
     if (fxfiber >= 0)
     and (fiber[fxfiber].fiberstate = FIBERSTATE_WAITSLEEP)
     then fiber[fxfiber].fiberstate := FIBERSTATE_NORMAL;
    end;

    FX_TRANSITION: begin
     transitionactive := $FFFFFFFF;
     with viewport[inviewport] do
      AddRefresh(viewportx1p, viewporty1p, viewportx2p, viewporty2p);
    end;

    FX_BOXMOVE: begin
     with TBox[fxbox] do begin
      boxlocx := x2;
      boxlocy := y2;
      anchorx := longint((poku + 8)^);
      anchory := longint((poku + 12)^);
      contentbufparamvalid := FALSE;
     end;
    end;

    FX_BOXSIZE: begin
     with TBox[fxbox] do begin
      contentwinminsizex := x2;
      contentwinmaxsizex := x2;
      contentwinminsizey := y2;
      contentwinmaxsizey := y2;
      contentbufparamvalid := FALSE;
     end;
    end;

    FX_BOXSCROLL: begin
     with TBox[fxbox] do begin
      contentwinscrollofsp := y2;
      finalbufvalid := FALSE;
      needsredraw := TRUE;
     end;
    end;

    FX_GOBMOVE: MoveGob(fxgob, x2 - gob[fxgob].locx, y2 - gob[fxgob].locy);

    FX_GOBALPHA: begin
     gob[fxgob].alphaness := x2;
     if gob[fxgob].drawstate and 2 <> 0 then gob[fxgob].drawstate := gob[fxgob].drawstate or 1;
    end;
  end;

  // Zero out the effect data.
  kind := 0;
  if poku <> NIL then begin freemem(poku); poku := NIL; end;

  if fxfiber >= 0 then begin
   dec(fiber[fxfiber].fxrefcount);
   if (fiber[fxfiber].fxrefcount = 0) and (fiber[fxfiber].fiberstate = FIBERSTATE_WAITFX)
   then fiber[fxfiber].fiberstate := FIBERSTATE_NORMAL;
  end;
 end;

 // Copy the top effect into the current slot.
 dec(fxcount);
 if (fxcount <> 0) and (fxnum < fxcount) then begin
  fx[fxnum] := fx[fxcount];
  fx[fxcount].kind := 0;
  fx[fxcount].poku := NIL;
  if transitionactive = fxcount then transitionactive := fxnum;
 end;
end;

// ------------------------------------------------------------------

function addBashEffect(direction, freq, amp, duration : longint; const targetgob : string) : dword;
// This causes the target gob and its children to start oscillating.
//
// Direction: an angle expressed in 32k, with 0 pointing up, +8k pointing
//   right, +/- 16k pointing down, and so on. It wraps around smoothly.
// Frequency: 16k = 0.5 Hz, 32k = 1 Hz, 64k = 2Hz
// Amplitude: 32k = +/- 100% of gob's width, 64k = +/- 200% of gob's width
// Duration: milliseconds, amplitude shrinks toward 0 over the duration.
//   If duration <= 0, amplitude remains constant and the effect lasts until
//   the gob is removed.
//
// Multiple bash effects can apply simultaneously to the same gob, although
// you can't consistently achieve a perfectly circular motion since this
// doesn't support offsetting the frequency progression.
//
// An earlier version of this tracked the bash through msec-precise force and
// inertia calculations, as if the screen was attached to the window's center
// with a rubber band, but that's only useful if there's a constant
// disrupting force acting on the object (such as another object physically
// smacking on it and sticking together for a bit). Since a bash only gave
// the screen a single directed impulse, it looked identical to a simple
// oscillator. Using coscos looks the same but is faster to calculate.
var fxvar, ivar : dword;
begin
 {$note Re-implement bash effect}
 addBashEffect := 0;
 // Find the victim
 for ivar := high(gob) downto 0 do
  if (IsGobValid(ivar)) and (gob[ivar].gobnamu = targetgob) then break;
 if ivar = 0 then begin
  LogError('fx.bash target gob ' + targetgob + ' not found');
  exit;
 end;

 // Sanity checks
 if duration < 0 then duration := 0
 else if duration > 65000 then duration := 65000;
 //if direction < 0 then inc(direction, $80000000);
 direction := direction mod 32768; // result: angle 0..32767
 if freq < 0 then begin
  direction := direction xor $4000;
  freq := abs(freq);
 end;
 if amp < 0 then begin
  direction := direction xor $4000;
  amp := abs(amp);
 end;
 if (freq = 0) or (amp = 0) then exit;

 // Create the effect
 fxvar := NewFx(0);
 fx[fxvar].kind := 5;
 fx[fxvar].fxgob := ivar;
 fx[fxvar].data := freq;
 fx[fxvar].data2 := amp;
 fx[fxvar].time2 := duration; // this stays unchanged
 fx[fxvar].time := 0; // this accumulates tickcount, grows up to starttime
 Log('Bash direction=' + strdec(direction) + ' freq=' + strdec(freq) + ' amp=' + strdec(amp) + ' dura=' + strdec(duration));

 // Convert the direction to a 32k unit vector
 // Y component:
 if direction >= 16384
 then ivar := direction - 16384 // down-left-up (16k:+max to 32k:-max) arc
 else ivar := 16384 - direction; // up-right-down (0:-max to 16k:+max) arc
 ivar := (ivar * dword(high(coscos)) + 8192) shr 14; // scale to 0..high(coscos)
 fx[fxvar].y1 := coscos[ivar] - 32768; // 32767..-32768

 // X component (90 degrees offset):
 direction := (direction + 8192) and $7FFF;
 if direction >= 16384
 then ivar := direction - 16384 // right-down-left (16k:+max to 32k:-max) arc
 else ivar := 16384 - direction; // left-up-right (0:-max to 16k:+max) arc
 ivar := (ivar * dword(high(coscos)) + 8192) shr 14; // scale to 0..high(coscos)
 fx[fxvar].x1 := coscos[ivar] - 32768; // 32767..-32768

 Log('Bash vector: ' + strdec(fx[fxvar].x1) + ',' + strdec(fx[fxvar].y1));

 addBashEffect := fxvar;
end;

function addFlashEffect(amount, vp : byte) : byte;
var fxvar : byte;
begin
 {$note Re-implement flash effect}
 if vp >= length(viewport) then begin
  LogError('flash effect viewport ' + strdec(vp) + ' doesn''t exist');
  vp := 0;
 end;
 // If flash effect is already on, add to it
 for fxvar := high(fx) downto 0 do
 if (fx[fxvar].kind = 4) and (fx[fxvar].inviewport = vp) then begin
  inc(fx[fxvar].data, amount);
  addFlashEffect := fxvar;
  exit;
 end;
 // Otherwise create a fresh flash
 if amount <> 0 then dec(amount);
 fxvar := NewFx(0);
 fx[fxvar].kind := 4;
 fx[fxvar].data2 := 0;
 fx[fxvar].inviewport := vp;
 fx[fxvar].data := amount;
 addFlashEffect := fxvar;
end;

procedure addGobMoveEffect(gobnum : dword; fibernum, tox, toy, msecs: longint; style : byte);
var fxvar : dword;
begin
 if IsGobValid(gobnum) = FALSE then exit;

 if style = MOVETYPE_INSTANT then msecs := 0;
 // If a move effect on this box is already live, co-opt it.
 fxvar := 0;
 while fxvar < fxcount do begin
  if (fx[fxvar].kind = FX_GOBMOVE) and (fx[fxvar].fxgob = gobnum) then break;
  inc(fxvar);
 end;
 if fxvar >= fxcount then fxvar := NewFx(fibernum);

 // Set up the effect.
 with fx[fxvar] do begin
  kind := FX_GOBMOVE;
  fxgob := gobnum;
  // source location
  x1 := gob[gobnum].locx;
  y1 := gob[gobnum].locy;
  // target location
  x2 := tox;
  y2 := toy;

  time := msecs; // remaining msecs
  time2 := msecs; // full msecs
  data2 := style;

  // End the effect immediately if time is 0.
  if msecs = 0 then DeleteFx(fxvar);
 end;
end;

procedure addBoxMoveEffect(boxnum : dword; fibernum, tox, toy, ankhx, ankhy, msecs : longint; style : byte);
// Moves a box from its current pixel position to a new pixel position, over
// a period of msecs. Tox and toy are pixel values.
var fxvar : dword;
begin
 if boxnum >= dword(length(TBox)) then exit;

 if style = MOVETYPE_INSTANT then msecs := 0;
 // If a move effect on this box is already live, co-opt it.
 fxvar := 0;
 while fxvar < fxcount do begin
  if (fx[fxvar].kind = FX_BOXMOVE) and (fx[fxvar].fxbox = boxnum) then break;
  inc(fxvar);
 end;
 if fxvar >= fxcount then begin
  fxvar := NewFx(fibernum);
  getmem(fx[fxvar].poku, 16);
 end;

 // Set up the effect.
 with fx[fxvar] do begin
  kind := FX_BOXMOVE;
  fxbox := boxnum;
  // source location
  x1 := TBox[boxnum].boxlocx;
  y1 := TBox[boxnum].boxlocy;
  // target location
  x2 := tox;
  y2 := toy;
  // source anchor
  longint(poku^) := TBox[boxnum].anchorx;
  longint((poku + 4)^) := TBox[boxnum].anchory;
  // target anchor
  longint((poku + 8)^) := ankhx;
  longint((poku + 12)^) := ankhy;

  time := msecs; // remaining msecs
  time2 := msecs; // full msecs
  data2 := style;

  // End the effect immediately if time is 0.
  if msecs = 0 then DeleteFx(fxvar);
 end;
end;

procedure addBoxSizeEffect(boxnum : dword; fibernum, tox, toy, msecs : longint; style : byte);
// Resized a box from its current 32k size to a new 32k size, over a period
// of msecs.
var fxvar : dword;
begin
 if boxnum >= dword(length(TBox)) then exit;
 if style = MOVETYPE_INSTANT then msecs := 0;
 // If a resize effect on this box is already live, co-opt it.
 fxvar := 0;
 while fxvar < fxcount do begin
  if (fx[fxvar].kind = FX_BOXSIZE) and (fx[fxvar].fxbox = boxnum) then break;
  inc(fxvar);
 end;
 if fxvar >= fxcount then fxvar := NewFx(fibernum);

 // Set up the effect.
 with fx[fxvar] do begin
  kind := FX_BOXSIZE;
  fxbox := boxnum;
  // source 32k size
  with TBox[boxnum] do begin
   x1 := (contentwinsizexp shl 15 + viewport[inviewport].viewportsizexp shr 1) div viewport[inviewport].viewportsizexp;
   y1 := (contentwinsizeyp shl 15 + viewport[inviewport].viewportsizeyp shr 1) div viewport[inviewport].viewportsizeyp;
  end;
  // target 32k size
  x2 := tox;
  y2 := toy;

  time := msecs; // remaining msecs
  time2 := msecs; // full msecs
  data2 := style;
  // End the effect immediately if time is 0.
  if msecs = 0 then DeleteFx(fxvar);
 end;
end;

procedure addBoxScrollEffect(boxnum : dword; fibernum, toy, msecs : longint; style : byte);
// Scrolls a box from its current pixel ofs to a new pixel ofs, over a period
// of msecs.
var fxvar : dword;
begin
 if boxnum >= dword(length(TBox)) then exit;
 if style = MOVETYPE_INSTANT then msecs := 0;
 // If a scroll effect on this box is already live, co-opt it.
 fxvar := 0;
 while fxvar < fxcount do begin
  if (fx[fxvar].kind = FX_BOXSCROLL) and (fx[fxvar].fxbox = boxnum) then break;
  inc(fxvar);
 end;
 if fxvar >= fxcount then fxvar := NewFx(fibernum);

 // Set up the effect.
 with fx[fxvar] do begin
  kind := FX_BOXSCROLL;
  fxbox := boxnum;
  y1 := TBox[boxnum].contentwinscrollofsp; // source scrollpos
  y2 := toy; // target scrollpos

  time := msecs; // remaining msecs
  time2 := msecs; // full msecs
  data2 := style;
  // End the effect immediately if time is 0.
  if msecs = 0 then DeleteFx(fxvar);
 end;
end;

procedure AddGobAlphaEffect(gobnum : dword; fibernum : longint; toalpha : byte; msecs : dword);
// Creates an effect that slides the given gob's alphaness from its current
// value to a new value, over a duration of msecs.
// 255 = fully opaque, 0 = fully transparent.
// NOTE: if you alpha slide a gob that has a child gob, trouble ensues. Even
// if the child is alphaslid the same amount simultaneously, this type of
// alpha blending makes the child gob stand out sharply in any areas where it
// overlaps the parent gob. So before sliding a gob's alpha, hide its kids.
// To fix this, the alpha'ed gob and its kids would have to be composited in
// a separate buffer that later gets blitted to output. Or use the new
// renderer and its pixel shader approach.
var fxvar : dword;
begin
 if gobnum >= dword(length(gob)) then exit;
 // If an alpha slide on this gob is already live, co-opt it.
 fxvar := 0;
 while fxvar < fxcount do begin
  if (fx[fxvar].kind = FX_GOBALPHA) and (fx[fxvar].fxgob = gobnum) then break;
  inc(fxvar);
 end;
 if fxvar >= fxcount then fxvar := NewFx(fibernum);

 // If duration = 0, just set alphaness immediately.
 if msecs = 0 then begin
  gob[gobnum].alphaness := toalpha;
  if gob[gobnum].drawstate and 2 <> 0 then gob[gobnum].drawstate := gob[gobnum].drawstate or 1;
  exit;
 end;

 // Set up the effect.
 with fx[fxvar] do begin
  kind := FX_GOBALPHA;
  fxgob := gobnum;
  time := msecs; // remaining msecs
  time2 := msecs; // full msecs
  x1 := gob[gobnum].alphaness;
  x2 := toalpha;
 end;
end;

procedure AddGobSolidBlitEffect(gobnum : dword; blitcolor : dword);
var ivar : dword;
begin
 with gob[gobnum] do begin
  dword(solidblitnext) := blitcolor;
  // Redraw gob if it's supposed to be visible.
  if drawstate and 2 <> 0 then drawstate := drawstate or 1;
  // Also do the kids.
  for ivar := high(gob) downto gobnum + 1 do
   if (IsGobValid(ivar)) and (gob[ivar].parent = gobnum) then
    AddGobSolidBlitEffect(ivar, blitcolor);
 end;
end;


function AddGammaSlideEffect(rval, gval, bval, duration : longint; vp : byte) : byte;
var fxvar : byte;
begin
 // Check for a pre-existing gamma slide effect, set to expire immediately
 for fxvar := high(fx) downto 0 do if fx[fxvar].kind = 7 then fx[fxvar].data := 3;
 // Create a new effect
 fxvar := NewFx(0);
 fx[fxvar].kind := 7;
 fx[fxvar].data := 0;
 fx[fxvar].inviewport := vp;
 fx[fxvar].x1 := rval;
 fx[fxvar].y1 := gval;
 fx[fxvar].x2 := bval;
 fx[fxvar].time2 := duration;
 AddGammaSlideEffect := fxvar;
end;

// ------------------------------------------------------------------

procedure addSleepEffect(fibernum, msecs : dword);
var fxi : dword;
begin
 if fibernum >= dword(length(fiber)) then LogError('addSleep: bad fiber: ' + strdec(fibernum))
 else begin
  fxi := NewFx(fibernum);
  fx[fxi].kind := FX_SLEEP;
  fx[fxi].time := msecs; // target time
  fx[fxi].fxgob := $FFFFFFFF;
  fiber[fibernum].fiberstate := FIBERSTATE_WAITSLEEP;
 end;
end;

procedure addTransitionEffect(fibernum : longint; viewnum, xstyle, msecs : dword);
var fxi : dword;
begin
 // Any previous transition must be eliminated first.
 if transitionactive < fxcount then DeleteFx(transitionactive);
 if xstyle = TRANSITION_INSTANT then msecs := 0;

 if fibernum >= length(fiber) then begin
  LogError('addTransition: bad fiber: ' + strdec(fibernum));
  fibernum := -1;
 end;
 // Set up the effect.
 fxi := NewFx(fibernum);
 with fx[fxi] do begin
  kind := FX_TRANSITION;
  time := msecs; // remaining time
  time2 := msecs; // full time
  inviewport := viewnum;
  data := xstyle;
 end;
 transitionactive := fxi;
 // End the effect immediately if time is 0.
 if msecs = 0 then DeleteFx(fxi)
 else StashRender;
end;

// ------------------------------------------------------------------

procedure Effector(tickcount : dword);
// Handles timed special effect tracking.
var ivar, jvar : longint;
    fxi : dword;
begin
 fxi := fxcount;
 while fxi <> 0 do begin
  dec(fxi);
  case fx[fxi].kind of

    FX_SLEEP: begin
     if tickcount >= fx[fxi].time then DeleteFx(fxi)
     else dec(fx[fxi].time, tickcount);
    end;

    FX_TRANSITION: begin
     if tickcount >= fx[fxi].time then DeleteFx(fxi)
     else begin
      dec(fx[fxi].time, tickcount);
      // Because many transition effects are drawn differently based on time
      // and location, the transition render cannot be easily split into
      // separate refresh rectangles. Due to the way refresh areas are merged
      // and split, the only way to be sure the transition effect is atomic
      // is to refresh the whole screen every frame.
      with viewport[fx[fxi].inviewport] do
       AddRefresh(viewportx1p, viewporty1p, viewportx2p, viewporty2p);
     end;
    end;

    FX_BOXMOVE: begin
     if tickcount >= fx[fxi].time then DeleteFx(fxi)
     else with fx[fxi] do begin
      dec(time, tickcount);
      case data2 of
        MOVETYPE_LINEAR: begin
         ivar := time2 - time;
         with TBox[fxbox] do begin
          boxlocx := (x2 * ivar + x1 * longint(time)) div longint(time2);
          boxlocy := (y2 * ivar + y1 * longint(time)) div longint(time2);
          anchorx := (longint((poku + 8)^) * ivar + longint((poku + 0)^) * longint(time)) div longint(time2);
          anchory := (longint((poku + 12)^) * ivar + longint((poku + 4)^) * longint(time)) div longint(time2);
         end;
        end;

        MOVETYPE_COSCOS: begin
         ivar := dword(high(coscos)) * time div time2;
         jvar := coscos[high(coscos) - ivar];
         ivar := jvar xor $FFFF;
         with TBox[fxbox] do begin
          boxlocx := (x2 * ivar + x1 * jvar) div $FFFF;
          boxlocy := (y2 * ivar + y1 * jvar) div $FFFF;
          anchorx := (longint((poku + 8)^) * ivar + longint((poku + 0)^) * jvar) div $FFFF;
          anchory := (longint((poku + 12)^) * ivar + longint((poku + 4)^) * jvar) div $FFFF;
         end;
        end;

        MOVETYPE_HALFCOS: begin
         ivar := dword(high(coscos) shr 1) * time div time2;
         jvar := $FFFF - coscos[ivar];
         ivar := jvar xor $7FFF;
         with TBox[fxbox] do begin
          boxlocx := (x2 * ivar + x1 * jvar) div $7FFF;
          boxlocy := (y2 * ivar + y1 * jvar) div $7FFF;
          anchorx := (longint((poku + 8)^) * ivar + longint((poku + 0)^) * jvar) div $7FFF;
          anchory := (longint((poku + 12)^) * ivar + longint((poku + 4)^) * jvar) div $7FFF;
         end;
        end;
      end;

      with TBox[fxbox] do begin
       // Re-calculate the pixel location.
       if boxlocx >= 0
       then boxlocxp := (boxlocx * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15
       else boxlocxp := -((-boxlocx * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15);
       inc(boxlocxp, viewport[inviewport].viewportx1p);
       if boxlocy >= 0
       then boxlocyp := (boxlocy * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15
       else boxlocyp := -((-boxlocy * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15);
       inc(boxlocyp, viewport[inviewport].viewporty1p);
       needsredraw := TRUE;
      end;
     end;
    end;

    FX_BOXSIZE: begin
     if tickcount >= fx[fxi].time then DeleteFx(fxi)
     else with fx[fxi] do begin
      dec(fx[fxi].time, tickcount);
      case data2 of
        MOVETYPE_LINEAR: begin
         ivar := time2 - time;
         with TBox[fxbox] do begin
          contentwinminsizex := (x2 * ivar + x1 * longint(time)) div longint(time2);
          contentwinminsizey := (y2 * ivar + y1 * longint(time)) div longint(time2);
         end;
        end;

        MOVETYPE_COSCOS: begin
         ivar := dword(high(coscos)) * time div time2;
         jvar := coscos[high(coscos) - ivar];
         ivar := jvar xor $FFFF;
         with TBox[fxbox] do begin
          contentwinminsizex := (x2 * ivar + x1 * jvar) div $FFFF;
          contentwinminsizey := (y2 * ivar + y1 * jvar) div $FFFF;
         end;
        end;

        MOVETYPE_HALFCOS: begin
         ivar := dword(high(coscos) shr 1) * time div time2;
         jvar := $FFFF - coscos[ivar];
         ivar := jvar xor $7FFF;
         with TBox[fxbox] do begin
          contentwinminsizex := (x2 * ivar + x1 * jvar) div $7FFF;
          contentwinminsizey := (y2 * ivar + y1 * jvar) div $7FFF;
         end;
        end;
      end;
      with TBox[fxbox] do begin
       // Re-calculate the pixel location.
       contentwinmaxsizex := contentwinminsizex;
       contentwinmaxsizey := contentwinminsizey;
       contentwinminsizexp := (contentwinminsizex * viewport[inviewport].viewportsizexp + 16384) shr 15;
       contentwinmaxsizexp := contentwinminsizexp;
       contentwinminsizeyp := (contentwinminsizey * viewport[inviewport].viewportsizeyp + 16384) shr 15;
       contentwinmaxsizeyp := contentwinminsizeyp;
       contentbuftextvalid := FALSE;
      end;
     end;
    end;

    FX_BOXSCROLL: begin
     if tickcount >= fx[fxi].time then DeleteFx(fxi)
     else with fx[fxi] do begin
      dec(fx[fxi].time, tickcount);
      case data2 of
        MOVETYPE_LINEAR: begin
         ivar := time2 - time;
         with TBox[fxbox] do begin
          contentwinscrollofsp := (y2 * ivar + y1 * longint(time)) div longint(time2);
         end;
        end;

        MOVETYPE_COSCOS: begin
         ivar := dword(high(coscos)) * time div time2;
         jvar := coscos[high(coscos) - ivar];
         ivar := jvar xor $FFFF;
         with TBox[fxbox] do begin
          contentwinscrollofsp := (y2 * ivar + y1 * jvar) div $FFFF;
         end;
        end;

        MOVETYPE_HALFCOS: begin
         ivar := dword(high(coscos) shr 1) * time div time2;
         jvar := $FFFF - coscos[ivar];
         ivar := jvar xor $7FFF;
         with TBox[fxbox] do begin
          contentwinscrollofsp := (y2 * ivar + y1 * jvar) div $7FFF;
         end;
        end;
      end;

      TBox[fxbox].finalbufvalid := FALSE;
      TBox[fxbox].needsredraw := TRUE;
     end;
    end;

    FX_GOBMOVE: begin
     if tickcount >= fx[fxi].time then DeleteFx(fxi)
     else with fx[fxi] do begin
      dec(time, tickcount);
      case data2 of
        MOVETYPE_LINEAR: begin
         ivar := time2 - time;
         MoveGob(fxgob,
           (x2 * ivar + x1 * longint(time)) div longint(time2) - gob[fxgob].locx,
           (y2 * ivar + y1 * longint(time)) div longint(time2) - gob[fxgob].locy);
        end;

        MOVETYPE_COSCOS: begin
         ivar := dword(high(coscos)) * time div time2;
         jvar := coscos[high(coscos) - ivar];
         ivar := jvar xor $FFFF;
         MoveGob(fxgob,
          (x2 * ivar + x1 * jvar) div $FFFF - gob[fxgob].locx,
          (y2 * ivar + y1 * jvar) div $FFFF - gob[fxgob].locy);
        end;

        MOVETYPE_HALFCOS: begin
         ivar := dword(high(coscos) shr 1) * time div time2;
         jvar := $FFFF - coscos[ivar];
         ivar := jvar xor $7FFF;
         MoveGob(fxgob,
           (x2 * ivar + x1 * jvar) div $7FFF - gob[fxgob].locx,
           (y2 * ivar + y1 * jvar) div $7FFF - gob[fxgob].locy);
        end;
      end;
     end;
    end;

    FX_GOBALPHA: begin
     if tickcount >= fx[fxi].time then DeleteFx(fxi)
     else with fx[fxi] do begin
      dec(time, tickcount);
      with gob[fx[fxi].fxgob] do begin
       alphaness := (dword(x1) * time + dword(x2) * (time2 - time)) div time2;
       if drawstate and 2 <> 0 then drawstate := drawstate or 1;
      end;
     end;
    end;

    else begin
     LogError('Effector: bad fx kind: ' + strdec(fx[fxi].kind));
     DeleteFx(fxi);
    end;
  end;
 end;
end;

{$ifdef bonk}
  case fx[ivar].kind of
   // Screen bash, elastic bounce
   5: begin
       inc(fx[ivar].time, tickcount);
       if (fx[ivar].time2 <> 0) and (fx[ivar].time >= fx[ivar].time2)
       then begin
        // Duration has elapsed, delete the effect
        MoveGob(fx[ivar].gob, 0, 0);
        fx[ivar].kind := 0; fx[ivar].gob := 0;
        Log('Bash finished');
       end else begin
        // The bash is still live!
        // Calculate the current decayed amplitude, unless infinite bash
        jvar := fx[ivar].data2;
        if fx[ivar].time2 <> 0 then begin
         jvar := ((high(coscos) shr 1) * (fx[ivar].time2 - fx[ivar].time) + fx[ivar].time2 shr 1) div fx[ivar].time2;
         jvar := (fx[ivar].data2 * coscos[high(coscos) - jvar] + 16384) shr 15;
        end;
        // Calculate the current phase and multiply amplitude with it
        // freq x: 1 rotation per (32k * 1000 / x) msecs
        // slowest freq = 1: 1 rotation per 32 million msecs (9.1 hours)
        // fastest freq = 2G: 1 per 0.015 msecs (way beyond our accuracy)
        xvar0 := (32768000 + fx[ivar].data shr 1) div fx[ivar].data;
        xvar1 := fx[ivar].time mod dword(xvar0); // phase as frac'n of .time2
        // convert to range [0..high(coscos) * 2]
        xvar1 := (xvar1 * (high(coscos) shl 1) + xvar0 shr 1) div xvar0;
        // get the appropriate coscos value for this phase
        if xvar1 < high(coscos) shr 1 then
         // 1Q: rising wave from 0 to maximum
         xvar1 := (high(coscos) shr 1) - xvar1
        else if xvar1 < (high(coscos) shr 1) * 3 then
         // 2Q: falling wave from maximum to 0
         // also 3Q: falling wave from 0 to minimum
         xvar1 := xvar1 - high(coscos) shr 1
        else
         // 4Q: rising wave from minimum to 0
         xvar1 := 5 * (high(coscos) shr 1) - xvar1;
        xvar2 := coscos[xvar1] - 32768; // range -32768..32767

        // Multiply the 32k unit direction vector by the amp/phase
        fx[ivar].x2 := fx[ivar].x1 * xvar2;
        if fx[ivar].x2 < 0
        then fx[ivar].x2 := (fx[ivar].x2 - 16384) div 32768
        else fx[ivar].x2 := (fx[ivar].x2 + 16384) shr 15;
        fx[ivar].x2 := fx[ivar].x2 * longint(jvar);
        if fx[ivar].x2 < 0
        then fx[ivar].x2 := (fx[ivar].x2 - 16384) div 32768
        else fx[ivar].x2 := (fx[ivar].x2 + 16384) shr 15;

        fx[ivar].y2 := fx[ivar].y1 * xvar2;
        if fx[ivar].y2 < 0
        then fx[ivar].y2 := (fx[ivar].y2 - 16384) div 32768
        else fx[ivar].y2 := (fx[ivar].y2 + 16384) shr 15;
        fx[ivar].y2 := fx[ivar].y2 * longint(jvar);
        if fx[ivar].y2 < 0
        then fx[ivar].y2 := (fx[ivar].y2 - 16384) div 32768
        else fx[ivar].y2 := (fx[ivar].y2 + 16384) shr 15;

        // Multiply the unit vector by the correct length, gob's pixel width
        if fx[ivar].x2 < 0
        then fx[ivar].x2 := (fx[ivar].x2 * longint(gob[fx[ivar].gob].sizexp) - 16384) div 32768
        else fx[ivar].x2 := (fx[ivar].x2 * longint(gob[fx[ivar].gob].sizexp) + 16384) shr 15;
        if fx[ivar].y2 < 0
        then fx[ivar].y2 := (fx[ivar].y2 * longint(gob[fx[ivar].gob].sizexp) - 16384) div 32768
        else fx[ivar].y2 := (fx[ivar].y2 * longint(gob[fx[ivar].gob].sizexp) + 16384) shr 15;

        // Place shaken gob at its new displaced location
        MoveGob(fx[ivar].gob, gob[fx[ivar].gob].locxp + fx[ivar].x2, gob[fx[ivar].gob].locyp + fx[ivar].y2);
       end;
      end;
   // Gamma slide effect
   7: begin
       // Initialisation
       if fx[ivar].data = 0 then begin
        if fx[ivar].x1 > 256 then fx[ivar].x1 := 256 else if fx[ivar].x1 < -256 then fx[ivar].x1 := -256;
        if fx[ivar].y1 > 256 then fx[ivar].y1 := 256 else if fx[ivar].y1 < -256 then fx[ivar].y1 := -256;
        if fx[ivar].x2 > 256 then fx[ivar].x2 := 256 else if fx[ivar].x2 < -256 then fx[ivar].x2 := -256;
        // Transition duration bounds, in milliseconds
        if fx[ivar].time2 > 32767 then fx[ivar].time2 := 32767 else
        if fx[ivar].time2 < 10 then fx[ivar].time2 := 10;
        fx[ivar].time := 0; fx[ivar].data := 1;
        // Store starting values
        longint((@fx[ivar].fxtxt[0])^) := 55;
        longint((@fx[ivar].fxtxt[4])^) := 66;
        longint((@fx[ivar].fxtxt[8])^) := 77;
        RGBtweakactive := ivar;
       end;
       // Closing down
       if (fx[ivar].data = 3)
       or (fx[ivar].x1 = 55) and (fx[ivar].y1 = 66) and (fx[ivar].x2 = 77)
       then begin
        fx[ivar].kind := 0;
        if (fx[ivar].x1 or fx[ivar].y1 or fx[ivar].x2 = 0)
        and (RGBtweakactive = ivar) then RGBtweakactive := $FF;
       end else
       // Make the new gamma table
       if fx[ivar].data = 1 then begin
        inc(fx[ivar].time, tickcount);
        if fx[ivar].time >= fx[ivar].time2 then begin
         fx[ivar].time := fx[ivar].time2;
         fx[ivar].data := 3;
        end;
        // interpolate linearry between initial and target values
        jvar := (fx[ivar].time shl 15 + fx[ivar].time2 shr 1) div fx[ivar].time2;
        xvar0 := 32768 - jvar;
        {$ifdef bonk}
        gvar[902] := (fx[ivar].x1 * jvar + longint((@fx[ivar].fxtxt[0])^) * xvar0) div 32768;
        gvar[903] := (fx[ivar].y1 * jvar + longint((@fx[ivar].fxtxt[4])^) * xvar0) div 32768;
        gvar[904] := (fx[ivar].x2 * jvar + longint((@fx[ivar].fxtxt[8])^) * xvar0) div 32768;
        BuildRGBtweakTable(gvar[902], gvar[903], gvar[904]);
        {$endif}
        // Make entire viewport redraw with new gamma
        with viewport[fx[ivar].inviewport] do
         AddRefresh(viewportx1p, viewporty1p, viewportx2p, viewporty2p);
       end;
       //write(tickcount,';');
      end;
   else begin
         LogError('Unknown effect ' + strdec(fx[ivar].kind));
         fx[ivar].kind := 0;
        end;
  end;
  inc(ivar);
 end;
end;
{$endif}

procedure UpdateVisuals(tickcount : dword);
// Updates animation data, marks gobs visible if pending.
var ivar, jvar, kvar, lvar : dword;
    PNGindex, roweventcount, coleventcount : dword;
begin
 if transitionactive < fxcount then begin
  // No animation updates during transitions, just draw stuff.
  for ivar := high(gob) downto 0 do
   if (IsGobValid(ivar)) and (gob[ivar].drawstate and 1 <> 0)
   then begin
    AddRefresh(gob[ivar].locxp, gob[ivar].locyp,
      gob[ivar].locxp + longint(gob[ivar].sizexp),
      gob[ivar].locyp + longint(gob[ivar].sizeyp));

    // Mark the gob as no longer needing a redraw
    if gob[ivar].drawstate and 1 <> 0 then
     gob[ivar].drawstate := (gob[ivar].drawstate and $FE) or 2;
   end;
 end
 else begin
  for ivar := high(gob) downto 0 do
   if IsGobValid(ivar) then begin

    // Update animation timers, set gob to redraw if timer elapsed
    if (gob[ivar].drawstate and 3 <> 0) // gob must be visible
    and (gob[ivar].animtimer <> $FFFFFFFF) // gob must not be frozen
    then begin
     PNGindex := GetPNG(gob[ivar].gfxnamu);
     jvar := tickcount; roweventcount := 64;
     while gob[ivar].animtimer <= jvar do begin
      dec(jvar, gob[ivar].animtimer);
      gob[ivar].animseqp := (gob[ivar].animseqp + 1) mod PNGlist[PNGindex].seqlen;
      repeat
       dec(roweventcount); if roweventcount = 0 then begin LogError('Infinite loop in anim seq? ' + gob[ivar].gobnamu); gob[ivar].animtimer := $FFFFFFFF; break; end;
       kvar := PNGlist[PNGindex].sequence[gob[ivar].animseqp];
       // get the new frame number
       lvar := (kvar shr 16) and $1FFF;
       case (kvar shr 16) and $6000 of
        // $2000: if lvar <= high(gvar) then gob[ivar].drawframe := word(gvar[lvar]);
        $4000: gob[ivar].drawframe := random(lvar);
        else gob[ivar].drawframe := lvar;
       end;
       // process the command
       if kvar and $80000000 <> 0 then begin
        // jump command
        coleventcount := 1;
        gob[ivar].animseqp := gob[ivar].drawframe mod PNGlist[PNGindex].seqlen;
       end else begin
        // show frame and delay
        coleventcount := 0;
        gob[ivar].drawframe := gob[ivar].drawframe mod PNGlist[PNGindex].framecount;
        gob[ivar].drawstate := gob[ivar].drawstate or 1;
        lvar := kvar and $FFFF; kvar := kvar and $3FFF;
        case lvar of
         $8000..$BFFF: gob[ivar].animtimer := random(kvar);
         // $C000..$FFFE: if kvar <= high(gvar) then gob[ivar].animtimer := gvar[kvar];
         $FFFF: gob[ivar].animtimer := $FFFFFFFF; // stop here
         else gob[ivar].animtimer := kvar;
        end;
       end;
      until coleventcount = 0;
     end;
     if gob[ivar].animtimer <> $FFFFFFFF then dec(gob[ivar].animtimer, jvar);
    end;

    // If redraw = true, the gob's screen area needs a refresh
    if gob[ivar].drawstate and 1 <> 0 then begin
     gob[ivar].cachedgfx := GetGFX(gob[ivar].gfxnamu, gob[ivar].sizexp, gob[ivar].sizeyp);

     AddRefresh(gob[ivar].locxp, gob[ivar].locyp,
       gob[ivar].locxp + longint(gob[ivar].sizexp),
       gob[ivar].locyp + longint(gob[ivar].sizeyp));

     // Mark the gob as no longer needing a redraw
     if gob[ivar].drawstate and 1 <> 0 then
      gob[ivar].drawstate := (gob[ivar].drawstate and $FE) or 2;
    end;
   end;
 end;
end;
