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

// Supersakura common rendering functions

procedure DrawRGB24(clipdata : pblitstruct);
// Copies data from a source bitmap into a destination buffer, while ignoring
// the alpha channel. The source data must be in BGRA byte order.
var destbufbytewidth : dword;
begin
 with clipdata^ do begin
  // Special case for outputbuffy-wide graphics, faster direct blit.
  if (srcskipwidth or destskipwidth) = 0 then
   move(srcp^, destp^, copyrows * copywidth * 4)
  else begin
   // Normal clipped blit.
   copywidth := copywidth * 4;
   inc(srcskipwidth, copywidth);
   destbufbytewidth := copywidth + destskipwidth;
   while copyrows <> 0 do begin
    move(srcp^, destp^, copywidth);
    inc(srcp, srcskipwidth);
    inc(destp, destbufbytewidth);
    dec(copyrows);
   end;
  end;
 end;
end;

procedure DrawRGBA32(clipdata : pblitstruct);
// Copies data from a source bitmap into a destination buffer, applying alpha
// blending normally. The source data must be in BGRA byte order.
var x : dword;
    alpha : byte;
begin
 with clipdata^ do begin
  while copyrows <> 0 do begin
   x := copywidth;
   while x <> 0 do begin
    alpha := byte((srcp + 3)^);
    case alpha of
      // Shortcut for the majority of pixels, totally transparent or opaque.
      0: begin
          inc(srcp, 4); inc(destp, 4);
         end;
      $FF: begin
            dword(destp^) := dword(srcp^);
            inc(srcp, 4); inc(destp, 4);
           end;
      else begin
       // Partial alpha mix, using the precalculated alphamixtable.
       // The source is premultiplied by its own alpha. To mix, we must now
       // multiply the source by the inverse of the alpha, and sum the two.
       alpha := alpha xor $FF;
       byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + byte(srcp^));
       inc(srcp); inc(destp);
       byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + byte(srcp^));
       inc(srcp); inc(destp);
       byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + byte(srcp^));
       inc(srcp); inc(destp);
       byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + byte(srcp^));
       inc(srcp); inc(destp);
      end;
    end;
    dec(x);
   end;
   inc(srcp, srcskipwidth);
   inc(destp, destskipwidth);

   dec(copyrows);
  end;
 end;
end;

procedure DrawRGBA32hardlight(clipdata : pblitstruct);
// Copies data from a source bitmap into a destination buffer, applying
// "hard light" blending. The source data must be in BGRA byte order.
var x : dword;
    alpha, alphainv, res : byte;
begin
 {$note optimise, stress test hardlight blend}
 with clipdata^ do begin
  while copyrows <> 0 do begin
   x := copywidth;
   while x <> 0 do begin
    alpha := byte((srcp + 3)^);
    alphainv := alpha xor $FF;

    if byte(srcp^) < 128
    then res := byte(srcp^) * byte(destp^) shr 7
    else res := 255 - ((255 - byte(srcp^)) * (255 - byte(destp^))) shr 7;
    byte(destp^) := (byte(destp^) * alphainv + res * alpha) div 255;
    inc(srcp); inc(destp);
    if byte(srcp^) < 128
    then res := byte(srcp^) * byte(destp^) shr 7
    else res := 255 - ((255 - byte(srcp^)) * (255 - byte(destp^))) shr 7;
    byte(destp^) := (byte(destp^) * alphainv + res * alpha) div 255;
    inc(srcp); inc(destp);
    if byte(srcp^) < 128
    then res := byte(srcp^) * byte(destp^) shr 7
    else res := 255 - ((255 - byte(srcp^)) * (255 - byte(destp^))) shr 7;
    byte(destp^) := (byte(destp^) * alphainv + res * alpha) div 255;
    inc(srcp); inc(destp);

    // Increase opaqueness if source is more opaque than destination.
    if byte(srcp^) > byte(destp^) then
    byte(destp^) := (byte(destp^) + byte(srcp^)) shr 1;
    inc(srcp); inc(destp);
    dec(x);
   end;
   inc(srcp, srcskipwidth);
   inc(destp, destskipwidth);

   dec(copyrows);
  end;
 end;
end;

procedure DrawRGBA32alpha(clipdata : pblitstruct; amul : byte);
// Copies 32-bit RGBA data from a source bitmap into a destination buffer,
// multiplying the source bitmap with an alpha value along the way.
// Call ClipRGB first to generate the blitstruct.
// 255 alpha is fully visible, 0 alpha is fully invisible.
var x : dword;
    alpha : byte;
begin
 with clipdata^ do begin
  while copyrows <> 0 do begin
   x := copywidth;
   while x <> 0 do begin
    alpha := alphamixtab[byte((srcp + 3)^), amul];
    // Shortcut for totally transparent pixels.
    if alpha = 0 then begin
     inc(srcp, 4); inc(destp, 4);
    end else begin
     // Partial alpha mix, using the precalculated alphamixtable.
     // Source is premultiplied by its own alpha, but must be further
     // multiplied by amul. Destination must be multiplied by the inverse
     // of (alpha * amul), then the two are summed.
     alpha := alpha xor $FF;
     byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + alphamixtab[byte(srcp^), amul]);
     inc(srcp); inc(destp);
     byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + alphamixtab[byte(srcp^), amul]);
     inc(srcp); inc(destp);
     byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + alphamixtab[byte(srcp^), amul]);
     inc(srcp); inc(destp);
     byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + alpha xor $FF);
     inc(srcp); inc(destp);
    end;

    dec(x);
   end;
   inc(srcp, srcskipwidth);
   inc(destp, destskipwidth);

   dec(copyrows);
  end;
 end;
end;

procedure DrawRGBA32wipe(clipdata : pblitstruct; completion : dword; wipein : boolean);
// Copies data from a source bitmap into a destination buffer, applying
// a sideways wipe effect up to 32k completion fraction. If wipein is TRUE,
// the image will appear wiped in from the left; else the image appears being
// wiped away toward the right.
var atable : array of byte;
    x : dword;
    edgewidthp, leadedgep, trailedgep : dword;
    alpha, alpha2 : byte;
begin
 with clipdata^ do begin
  // Pre-calculate an alpha table... This shows what alpha each pixel column
  // needs to be multiplied with.
  setlength(atable, copywidth + 1);
  // If wiping out, invert completion.
  if wipein = FALSE then completion := 32768 - completion;
  // Soft edge width = WinSizeX / 16
  edgewidthp := (copywidth + (destskipwidth shr 2)) shr 4;
  // Lead edge position.
  leadedgep := ((copywidth + edgewidthp) * completion) shr 15;
  // Trailing edge position.
  trailedgep := 0;
  if leadedgep > edgewidthp then trailedgep := leadedgep - edgewidthp;

  if wipein then begin
   // Fill max alpha before trailing edge.
   if trailedgep <> 0 then fillbyte(atable[copywidth - trailedgep], trailedgep, 255);
   // Fill min alpha after leading edge.
   if leadedgep < copywidth then fillbyte(atable[0], copywidth - leadedgep, 0);
   // Prepare the trailing edge alpha value.
   alpha := 255;
   if leadedgep < edgewidthp then alpha := (255 * leadedgep) div edgewidthp;
   // Prepare the leading edge alpha value.
   alpha2 := 0;
   if leadedgep > copywidth then alpha2 := 255 * (leadedgep - copywidth) div edgewidthp;
  end
  else begin
   // Fill min alpha before trailing edge.
   if trailedgep <> 0 then fillbyte(atable[copywidth - trailedgep], trailedgep, 0);
   // Fill max alpha after leading edge.
   if leadedgep < copywidth then fillbyte(atable[0], copywidth - leadedgep, 255);
   // Prepare the trailing edge alpha value.
   alpha := 0;
   if leadedgep < edgewidthp then alpha := ((255 * leadedgep) div edgewidthp) xor $FF;
   // Prepare the leading edge alpha value.
   alpha2 := 255;
   if leadedgep > copywidth then alpha2 := (255 * (leadedgep - copywidth) div edgewidthp) xor $FF;
  end;
  // Clip lead edge.
  if leadedgep > copywidth then leadedgep := copywidth;
  // Calculate the soft edge linear alpha gradient.
  for x := leadedgep - trailedgep downto 0 do
   atable[copywidth - x - trailedgep] := (alpha2 * x + alpha * (leadedgep - trailedgep - x)) div (leadedgep - trailedgep);

  while copyrows <> 0 do begin
   x := copywidth;
   while x <> 0 do begin
    alpha := alphamixtab[byte((srcp + 3)^), atable[x]];
    // Shortcut for totally transparent pixels.
    if alpha = 0 then begin
     inc(srcp, 4); inc(destp, 4);
    end else begin
     // Partial alpha mix, using the precalculated alphamixtable.
     // Source is premultiplied by its own alpha, but must be further
     // multiplied by atable. Destination must be multiplied by the inverse
     // of (alpha * atable), then the two are summed.
     alpha := alpha xor $FF;
     byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + alphamixtab[byte(srcp^), atable[x]]);
     inc(srcp); inc(destp);
     byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + alphamixtab[byte(srcp^), atable[x]]);
     inc(srcp); inc(destp);
     byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + alphamixtab[byte(srcp^), atable[x]]);
     inc(srcp); inc(destp);
     byte(destp^) := byte(alphamixtab[alpha, byte(destp^)] + alpha xor $FF);
     inc(srcp); inc(destp);
    end;

    dec(x);
   end;
   inc(srcp, srcskipwidth);
   inc(destp, destskipwidth);

   dec(copyrows);
  end;
 end;
end;

procedure DrawSolid(clipdata : pblitstruct; fillcolor : dword; hasalpha : byte);
// Fills a destination buffer with the alpha profile of a source bitmap,
// using fillcolor. The fill color will be solid, its a component is ignored.
// Useful for full-screen blackouts, or making a character sprite flash.
// Call ClipRGB first to generate the blitstruct.
begin
end;

procedure NegateRGB(clipdata : pblitstruct);
// Negates the destination rectangle given in the input structure.
// Call ClipRGB first to generate the blitstruct.
// (This is only used as a textbox effect)
begin
end;

procedure ClipRGB(clipdata : pblitstruct);
// This function takes graphic dimensions and coordinates, and returns
// a blitstruct with offsets used by DrawRGB24, DrawRGBA32 and StoreRGB.
// The destination is always mv_OutputBuffy, or any other 32-bit buffer of
// equal size. The source bitmap must be a contiguous bytestream; pre-clipped
// source bitmaps won't work.
// Clipdata must point to a pre-filled blitstruct that ClipRGB can edit.
//
// The following parts of blitstruct must be initialised before calling:
//   srcp and destp must point to the first pixel of both bitmaps.
//   srcofs is the pixel offset to the first pixel of the source bitmap.
//     Usually 0, but can be adjusted to choose a source frame.
//   destofsxy are pixel values relative to mv_OutputBuffy.
//   srccopywidth and srcrows must be the source bitmap's pixel size.
//   clipxyp must be the pixel boundaries to clip against.
//   clipviewport must be set.
var ivar : longint;
begin
 with clipdata^ do begin
  // First clip the clipping area against the program window.
  if clipx1p < 0 then clipx1p := 0;
  if clipy1p < 0 then clipy1p := 0;
  if clipx2p > longint(sysvar.mv_WinSizeX) then clipx2p := sysvar.mv_WinSizeX;
  if clipy2p > longint(sysvar.mv_WinSizeY) then clipy2p := sysvar.mv_WinSizeY;
  // And against the gob's viewport.
  if clipx1p < viewport[clipviewport].viewportx1p then clipx1p := viewport[clipviewport].viewportx1p;
  if clipy1p < viewport[clipviewport].viewporty1p then clipy1p := viewport[clipviewport].viewporty1p;
  if clipx2p > viewport[clipviewport].viewportx2p then clipx2p := viewport[clipviewport].viewportx2p;
  if clipy2p > viewport[clipviewport].viewporty2p then clipy2p := viewport[clipviewport].viewporty2p;

  srcskipwidth := copywidth;
  // clip top
  ivar := clipy1p - destofsyp;
  if ivar > 0 then begin // ivar = rows to clip
   if dword(ivar) > copyrows then ivar := copyrows;
   dec(copyrows, ivar);
   inc(srcofs, copywidth * dword(ivar));
   destofsyp := clipy1p;
  end;
  // clip bottom
  ivar := destofsyp + longint(copyrows) - clipy2p;
  if ivar > 0 then begin // ivar = rows to clip
   if dword(ivar) > copyrows then ivar := copyrows;
   dec(copyrows, ivar);
  end;
  // clip left
  ivar := clipx1p - destofsxp;
  if ivar > 0 then begin // ivar = cols to clip
   if dword(ivar) > copywidth then ivar := copywidth;
   dec(copywidth, ivar);
   inc(srcofs, dword(ivar));
   destofsxp := clipx1p;
  end;
  // clip right
  ivar := destofsxp + longint(copywidth) - clipx2p;
  if ivar > 0 then begin // ivar = cols to clip
   if dword(ivar) > copywidth then ivar := copywidth;
   dec(copywidth, ivar);
  end;
  // For each row, skip all columns that are not copied.
  // Also convert the values to bytes instead of pixels.
  // (destofsxyp, srccopywidth, and srcrows remain pixel values)
  srcofs := srcofs * 4;
  srcskipwidth := (srcskipwidth - copywidth) * 4;
  destofs := (destofsyp * longint(sysvar.mv_WinSizeX) + destofsxp) * 4;
  destskipwidth := (sysvar.mv_WinSizeX - copywidth) * 4;
  inc(srcp, srcofs);
  inc(destp, destofs);
 end;
end;

procedure BuildRGBtweakTable(r1, g1, b1 : longint);
// Fills RGBtweaktable[] with conversion values.
// The table can be used to apply changes to a pixel's colors efficiently.
// First call this procedure to create the lookup table, where each color
// channel gets an individual adjustment curve from your input arguments.
// The input values may be -256..+256. At 0, the conversion curve will be
// a straight line. Negative numbers bend the curve toward zero, and at -256
// it's all flat zero. Positive numbers bend the curve upwards.
//
// The curve is calculated using three points; pStart, pMid, and pEnd.
// At zero state, pStart is 0, pMid is 128 and pEnd is 255.
//
// The curve is a standard ax^2 + bx + c = 0, where
// f(0) = pStart, f(128) = pMid and f(255) = pEnd.
// This solves to:
// a = (   127 * pStart -   255 * pMid +   128 * pEnd) / 4145280
// b = (-48641 * pStart + 65025 * pMid - 16384 * pEnd) / 4145280
// c = pStart
var pStart, pMid, pEnd, ivar : byte;
    a, b : longint;
begin
 // Cap the values
 if r1 < -256 then r1 := -256 else if r1 > 256 then r1 := 256;
 if g1 < -256 then g1 := -256 else if g1 > 256 then g1 := 256;
 if b1 < -256 then b1 := -256 else if b1 > 256 then b1 := 256;
 // Build the RED curve
 if r1 <= 128 then pStart := 0 else pStart := (byte(r1 - 128) * 255 + 64) shr 7;
 pMid := (word(r1 + 256) * 255 + 256) shr 9;
 if r1 >= -128 then pEnd := 255 else pEnd := (word(256 + r1) * 255 + 64) shr 7;
 a := word(pStart * 127) - word(pMid * 255) + word(pEnd * 128);
 b := dword(pMid * 65025) - dword(pEnd * 16384) - dword(pStart * 48641);
 for ivar := 255 downto 0 do
  RGBtweakTable[ivar] := (a * ivar + b) * ivar div 4145280 + pStart;
 // Build the GREEN curve
 if g1 <= 128 then pStart := 0 else pStart := (byte(g1 - 128) * 255 + 64) shr 7;
 pMid := (word(g1 + 256) * 255 + 256) shr 9;
 if g1 >= -128 then pEnd := 255 else pEnd := (word(256 + g1) * 255 + 64) shr 7;
 a := word(pStart * 127) - word(pMid * 255) + word(pEnd * 128);
 b := dword(pMid * 65025) - dword(pEnd * 16384) - dword(pStart * 48641);
 for ivar := 255 downto 0 do
  RGBtweakTable[ivar or 256] := (a * word(ivar * ivar) + b * ivar) div 4145280 + pStart;
 // Build the BLUE curve
 if b1 <= 128 then pStart := 0 else pStart := (byte(b1 - 128) * 255 + 64) shr 7;
 pMid := (word(b1 + 256) * 255 + 256) shr 9;
 if b1 >= -128 then pEnd := 255 else pEnd := (word(256 + b1) * 255 + 64) shr 7;
 a := word(pStart * 127) - word(pMid * 255) + word(pEnd * 128);
 b := dword(pMid * 65025) - dword(pEnd * 16384) - dword(pStart * 48641);
 for ivar := 255 downto 0 do
  RGBtweakTable[ivar or 512] := (a * word(ivar * ivar) + b * ivar) div 4145280 + pStart;
end;

procedure ApplyRGBtweak(clipdata : pblitstruct);
// Takes the area in rendertarget^ at the given clip destination coordinates,
// and runs every pixel through a gamma correction conversion, as
// precalculated by BuildRGBtweakTable into the RGBtweakTable[] array.
{$note fix applyrgbtweak}
// Must take premul alpha into account; the RGB tweak function which
// currently could take any input 0..255 and return any output 0..255 must
// be scaled to return output in the range 0.. this pixel's alpha.
//var xvar, yvar : dword;
begin
{ yvar := bdata^.sourcerows;
 while yvar <> 0 do begin
  dec(yvar);
  xvar := bdata^.sourcecopywidth;
  while xvar <> 0 do begin
   dec(xvar);
   byte((mv_OutputBuffy + bdata^.destofs)^) := RGBtweaktable[byte((mv_OutputBuffy + bdata^.destofs)^) + 512];
   inc(bdata^.destofs);
   byte((mv_OutputBuffy + bdata^.destofs)^) := RGBtweaktable[byte((mv_OutputBuffy + bdata^.destofs)^) + 256];
   inc(bdata^.destofs);
   byte((mv_OutputBuffy + bdata^.destofs)^) := RGBtweaktable[byte((mv_OutputBuffy + bdata^.destofs)^) + 0];
   inc(bdata^.destofs, 2);
  end;
  inc(bdata^.destofs, bdata^.destskipwidth);
 end;}
end;

procedure RenderTransition;
// Mixes an old stashed view with the currently active one. Transitionactive
// must be the index of a valid transition effect, which is used to track the
// transition's progress. When starting a transition, StashRender should be
// called to retain a view to transition from.
var myfx : ^fxtype;
    srcp, destp : pointer;
    ivar, jvar, kvar, lvar : dword;
    targetx, targety, targetsizex, targetsizey : word;
    x, y, tox, toy : dword;
    rowstartskipbytes, rowendskipbytes : dword;
begin
 if transitionactive >= fxcount then begin
  LogError('RenderTransition: bad fx index: ' + strdec(transitionactive)); exit;
 end;
 myfx := @fx[transitionactive];
 if myfx^.kind <> FX_TRANSITION then begin
  LogError('RenderTransition: not a transition effect');
  transitionactive := $FFFFFFFF;
  exit;
 end;

 // myfx^ contains the following:
 // .time2 = full transition duration, msecs
 // .time = time left at this render
 // .data = transition type
 // .inviewport

 targetx := viewport[myfx^.inviewport].viewportx1p;
 targety := viewport[myfx^.inviewport].viewporty1p;
 targetsizex := viewport[myfx^.inviewport].viewportsizexp;
 targetsizey := viewport[myfx^.inviewport].viewportsizeyp;
 //tox := targetx + targetsizex - 1;
 //toy := targety + targetsizey - 1;
 rowendskipbytes := (sysvar.mv_WinSizeX - targetsizex) * 4;

 // Set up stream pointers.
 ivar := (targety * sysvar.mv_WinSizeX + targetx) * 4;
 srcp := stashbuffy + ivar;
 destp := mv_OutputBuffy + ivar;

 case myfx^.data of

   TRANSITION_INSTANT: ;

   TRANSITION_WIPEFROMLEFT: begin
    // Calculate soft edge width.
    tox := targetsizex shr 4 + 1;
    // Calculate completion amount: runs from 0 to targetsizex + edge size.
    // This is the leading edge of the soft edge.
    ivar := dword(high(coscos)) * myfx^.time div myfx^.time2;
    jvar := (coscos[ivar] * (targetsizex + tox)) shr 16;
    // Get the width of the completed area behind the soft edge.
    rowstartskipbytes := 0;
    if jvar > tox then rowstartskipbytes := (jvar - tox) * 4;
    // Get the width of the pending area ahead of the soft edge.
    kvar := 0;
    if jvar < targetsizex then kvar := (targetsizex - jvar) * 4;
    // Clip the soft edge.
    if jvar < tox then tox := jvar
    else if jvar > targetsizex then dec(tox, jvar - targetsizex);

    for y := targetsizey - 1 downto 0 do begin
     // Skip the completed wipe area behind the soft edge.
     inc(srcp, rowstartskipbytes);
     inc(destp, rowstartskipbytes);
     // Do the soft edge.
     if tox <> 0 then for x := tox - 1 downto 0 do begin
      lvar := tox - x;
      byte(destp^) := (byte(destp^) * x + byte(srcp^) * lvar) div tox;
      inc(srcp); inc(destp);
      byte(destp^) := (byte(destp^) * x + byte(srcp^) * lvar) div tox;
      inc(srcp); inc(destp);
      byte(destp^) := (byte(destp^) * x + byte(srcp^) * lvar) div tox;
      inc(srcp, 2); inc(destp, 2);
     end;
     // Fill the pending area ahead of the soft edge.
     if kvar <> 0 then begin
      move(srcp^, destp^, kvar);
      inc(srcp, kvar);
      inc(destp, kvar);
     end;
     // Skip to next row.
     inc(srcp, rowendskipbytes);
     inc(destp, rowendskipbytes);
    end;
   end;

   TRANSITION_RAGGEDWIPE: begin
    // Calculate the maximum soft edge width.
    toy := targetsizex shr 2 + 1;

    // Build a raggedness list, if one doesn't exist yet. This assigns
    // a different soft edge size to each pixel row.
    if myfx^.poku = NIL then begin
     getmem(myfx^.poku, targetsizey * 4);
     // Find the largest integer square root of the maximum soft edge width.
     jvar := 1; while jvar * jvar <= toy do inc(jvar); dec(jvar);
     // Build the list.
     ivar := 0;
     for y := targetsizey - 1 downto 0 do begin
      kvar := random(jvar) + 1;
      dword((myfx^.poku + ivar)^) := kvar * kvar;
      inc(ivar, 4);
     end;
    end;

    // Calculate completion amount: runs from 0 to targetsizex + maxedgesize.
    // This is the leading edge of the soft edge.
    ivar := dword(high(coscos)) * myfx^.time div myfx^.time2;
    jvar := (coscos[ivar] * (targetsizex + toy)) shr 16;
    // Get the width of the pending area ahead of the soft edge.
    kvar := 0;
    if jvar < targetsizex then kvar := (targetsizex - jvar) * 4;

    for y := targetsizey - 1 downto 0 do begin
     // Get the soft edge width for this row.
     tox := dword((myfx^.poku + y * 4)^);
     // Get the width of the completed area behind the soft edge.
     rowstartskipbytes := 0;
     if jvar > tox then begin
      rowstartskipbytes := (jvar - tox);
      if rowstartskipbytes > targetsizex then rowstartskipbytes := targetsizex;
      rowstartskipbytes := rowstartskipbytes * 4;
     end;
     // Clip the soft edge.
     if jvar < tox then tox := jvar
     else if jvar > targetsizex then
     if jvar >= tox + targetsizex then tox := 0
     else dec(tox, jvar - targetsizex);
     // Skip the completed wipe area behind the soft edge.
     inc(srcp, rowstartskipbytes);
     inc(destp, rowstartskipbytes);
     // Do the soft edge.
     if tox <> 0 then for x := tox - 1 downto 0 do begin
      lvar := tox - x;
      byte(destp^) := (byte(destp^) * x + byte(srcp^) * lvar) div tox;
      inc(srcp); inc(destp);
      byte(destp^) := (byte(destp^) * x + byte(srcp^) * lvar) div tox;
      inc(srcp); inc(destp);
      byte(destp^) := (byte(destp^) * x + byte(srcp^) * lvar) div tox;
      inc(srcp, 2); inc(destp, 2);
     end;
     // Fill the pending area ahead of the soft edge.
     if kvar <> 0 then begin
      move(srcp^, destp^, kvar);
      inc(srcp, kvar);
      inc(destp, kvar);
     end;
     // Skip to next row.
     inc(srcp, rowendskipbytes);
     inc(destp, rowendskipbytes);
    end;
   end;

   TRANSITION_INTERLACED: begin
    // Calculate completion amount: runs from 0 to targetsizey-1.
    ivar := dword(high(coscos)) * myfx^.time div myfx^.time2;
    jvar := (coscos[ivar] * targetsizey) shr 16;
    kvar := targetsizey - 1 - jvar; // inverse
    lvar := targetsizex * 4;
    rowendskipbytes := sysvar.mv_WinSizeX * 4;

    for y := targetsizey - 1 downto 0 do begin
     if (y and 1 = 0) and (y > jvar)
     or (y and 1 <> 0) and (y < kvar) then begin
      move(srcp^, destp^, lvar);
     end;
     inc(srcp, rowendskipbytes);
     inc(destp, rowendskipbytes);
    end;
   end;

   TRANSITION_CROSSFADE: begin
    jvar := myfx^.time shl 15 div myfx^.time2; // 32k time left
    kvar := 32768 - jvar; // 32k time elapsed

    for y := targetsizey - 1 downto 0 do begin
     for x := targetsizex - 1 downto 0 do begin
      byte(destp^) := (byte(destp^) * kvar + byte(srcp^) * jvar) shr 15;
      inc(srcp); inc(destp);
      byte(destp^) := (byte(destp^) * kvar + byte(srcp^) * jvar) shr 15;
      inc(srcp); inc(destp);
      byte(destp^) := (byte(destp^) * kvar + byte(srcp^) * jvar) shr 15;
      inc(srcp, 2); inc(destp, 2);
     end;
     inc(srcp, rowendskipbytes);
     inc(destp, rowendskipbytes);
    end;
   end;

   else begin
    LogError('RenderTransition: bad transition type: ' + strdec(myfx^.data));
    myfx^.time := 0;
   end;
 end;

 srcp := NIL; destp := NIL;
end;

procedure RenderGobs(const refrect : tfresh; const destbuf : pointer); inline;
// Completely redraws everything in the given rectangle. The destination
// buffer must be mv_OutputBuffy or stashbuffy. If rendering into stashbuffy,
// draws everything except textboxes.
{$define !newrenderer} // <-- doesn't work yet
{$ifdef newrenderer}
// type renderinstruction = record
//       destp : pointer; // ^ to top right px of slice in output buffer
//       destrowbytes : dword; // number of bytes to add to destp per row
//       sliceheight : dword; // number of px scanlines
//       slicewidth : longint; // number of px per row, * -4
//       actionssize : dword; // sizeof action in bytes
//       action : array[0..numactions-1] of record
//        srcp : pointer; // ^ to top right pixel of clipped source bitmap
//        srcrowbytes : dword; // number of bytes to add to srcp per row
//        action : dword; // low byte is the action, rest can be data
//        actiondata : dword;
//        occlusionskip : dword; // bytes to add to action index if pxa=max
//       end;
//      end;
// Actions: (topmost means last gfx to be drawn at pixel?)
// 0 - getnextrow            1 - getnextpixel
// 2 - drawrgb24             3 - drawrgb24topmost
// 4 - drawrgba32            5 - drawrgba32topmost
// 6 - drawrgba32alpha       7 - drawrgba32alphatopmost
// 8 - drawrgba32flat        9 - drawrgba32flattopmost
// A - drawrgba32flatalpha   B - drawrgba32flatalphatopmost
// 80 - RGBtweak effect
var ivar, jvar, kvar, lvar : dword;
    clipsi : blitstruct;
    regiongoblist, cakegoblist : array of dword;
    regiongobcount, cakegobcount : dword; // refresh region > cake > slice
    roweventlist, coleventlist : array of dword; // slice edge coordinates
    roweventcount, coleventcount : dword;
begin
 // At this point we have a bunch of screen rectangles that need to be fully
 // redrawn. Each rectangle may contain 0 or more gobs; none of the
 // rectangles overlap, and all are completely within the output buffer.
 //
 // Now we process the refresh regions one at a time:
 // 1a. Reduce a list of all visible gobs to just those inside the region
 // 1b. Drop any gobs below a RGB24 gob that covers the entire region
 // 1c. List the top and bottom edges of the above gobs, to help subdivide
 //     the region into horizontal "cake" bars
 // 2a. For each cake, reduce the above list to only those gobs present in
 //     the current cake bar
 // 2b. List the left and right edges of those gobs, to help subdivide the
 //     cake into slices
 // 3a. No gobs in cake? Blockfill with black.
 // 3b. If all gobs in the cake align with the region's width perfectly, and
 //     the region's width is equal to the output buffer's width, a single
 //     rendering instruction will take care of the rest
 // 3c. Otherwise, write instructions for drawing the cake slice, then the
 //     next slice until the cake is all gone
 // 4. Feed the instruction buffer into the renderer!

 // Prepare memory for the gob lists we'll need; reserve enough for the worst
 // case so there won't be any need for array resizing later.
 setlength(regiongoblist, length(gob));
 setlength(cakegoblist, length(gob));
 setlength(roweventlist, length(gob) * 2);
 setlength(coleventlist, length(gob) * 2);

 refrect := numfresh;
 while refrect <> 0 do begin
  dec(refrect);

  // Construct a list of all edges of gobs in this refresh rectangle,
  // down to the first RGB24 gob that covers the entire refresh area
  jvar := length(gob); regiongobcount := 0;
  while jvar <> 0 do begin
   dec(jvar);
   if (IsGobValid(jvar)) // only existing visible gobs need apply
   and (gob[jvar].drawstate and 3 <> 0) then begin
    if (gob[jvar].locxp_r < refresh[refrect].x2p)
    and (gob[jvar].locyp_r < refresh[refrect].y2p)
    and (gob[jvar].locxp_r + gcache[gob[jvar].cachenum].sizex > refresh[refrect].x1p)
    and (gob[jvar].locyp_r + gcache[gob[jvar].cachenum].frameheight > refresh[refrect].y1p)
    then begin
     // gob is within refresh rectangle, goes onto list
     regiongoblist[regiongobcount] := jvar;
     inc(regiongobcount);
     // And if it's an opaque 24-bit image that covers the entire rectangle,
     // nothing below it can be visible, so we can skip the rest.
     if (gcache[gob[jvar].cachenum].format = 0)
     and (gob[jvar].alphaness = $FF) then
     if (gob[jvar].locxp_r <= refresh[refrect].x1p)
     and (gob[jvar].locyp_r <= refresh[refrect].y1p)
     and (gob[jvar].locxp_r + gcache[gob[jvar].cachenum].sizex >= refresh[refrect].x2p)
     and (gob[jvar].locyp_r + gcache[gob[jvar].cachenum].frameheight >= refresh[refrect].y2p)
     then break;
    end;
   end;
  end;

   destp := rendertarget;
   // Select the right frame to draw by adjusting the image source offset
   clipsi.sourcecopywidth := gcache[gob[ivar].cachenum].sizex;
   clipsi.sourcerows := gcache[gob[ivar].cachenum].frameheight;
   clipsi.sourceofs := clipsi.sourcerows * clipsi.sourcecopywidth * gob[ivar].drawframe;
   // Guard against frames beyond actual image data
   if clipsi.sourceofs + clipsi.sourcecopywidth * clipsi.sourcerows > gcache[gob[ivar].cachenum].sizex * gcache[gob[ivar].cachenum].sizey
   then clipsi.sourceofs := 0;

   // Also clip the clipping area against the program window
   if cliplocxp < jvar then cliplocxp := jvar;
   if cliplocyp < kvar then cliplocyp := kvar;
   if clipsizexp > mv_WinSizeX - jvar then clipsizexp := mv_WinSizeX - jvar;
   if clipsizeyp > mv_WinSizeY - kvar then clipsizeyp := mv_WinSizeY - kvar;
   // And against the viewport, if gob is not a viewframe gob
   if gcache[gob[ivar].cachenum].bitflag and $80 <> 0 then begin
    if cliplocxp < sysvar.viewportlocxp + jvar then cliplocxp := sysvar.viewportlocxp + jvar;
    if cliplocyp < sysvar.viewportlocyp + kvar then cliplocyp := sysvar.viewportlocyp + kvar;
    if clipsizexp > sysvar.viewportlocxp + sysvar.viewportsizexp - jvar then clipsizexp := sysvar.viewportlocxp + sysvar.viewportsizexp - jvar;
    if clipsizeyp > sysvar.viewportlocyp + sysvar.viewportsizeyp - kvar then clipsizeyp := sysvar.viewportlocyp + sysvar.viewportsizeyp - kvar;
   end;
   // convert clipsize to actual clipsize instead of edge coordinates
   if clipsizexp <= cliplocxp then clipsizexp := 0 else dec(clipsizexp, cliplocxp);
   if clipsizeyp <= cliplocyp then clipsizeyp := 0 else dec(clipsizeyp, cliplocyp);

   if (clipsi.sourcecopywidth <> 0) and (clipsi.sourcerows <> 0) then begin
   {logmsg('[gob ' + strdec(ivar) + ': ' + gob[ivar].gobnamu + '; loc '
    + strdec(clipsi.destofsx) + ',' + strdec(clipsi.destofsy) + '; size '
    + strdec(clipsi.sourcecopywidth) + 'x' + strdec(clipsi.sourcerows)
    + '] locp_r=' + strdec(gob[ivar].locxp_r) + ',' + strdec(gob[ivar].locyp_r));}

   // At last, draw the graphic
   if gob[ivar].solidblit <> 0 then DrawSolid(@clipsi, (gvar[gob[ivar].solidblit] shr 8) or ((gvar[gob[ivar].solidblit] and $FF) shl 24), GCache[gob[ivar].cachenum].format and 1 = 1)
   else if gob[ivar].alphaness <> $FF then DrawRGBA32alpha(@clipsi, gob[ivar].alphaness)
   else if gcache[gob[ivar].cachenum].format and 1 = 0
   then DrawRGB24(@clipsi)
   else DrawRGBA32(@clipsi);

  // After all graphics have been drawn in a refresh rectangle, apply the
  // gamma correction effect over that rectangle, if necessary.
  if RGBtweakactive <> $FF then with clipsi do begin
   cliplocxp := sysvar.viewportlocxp; clipsizexp := sysvar.viewportsizexp;
   cliplocyp := sysvar.viewportlocyp; clipsizeyp := sysvar.viewportsizeyp;
   ClipRGB(@clipsi); ApplyRGBtweak(@clipsi);
  end;
 end;

 // Clean up our list memory explicitly
 setlength(regiongoblist, 0);
 setlength(cakegoblist, 0);
 setlength(roweventlist, 0);
 setlength(coleventlist, 0);
end;

{$else oldrenderer}
var ivar, jvar, kvar, lvar : dword;
    clipsi : blitstruct;
    poku : pointer;
begin
  jvar := length(gob); ivar := $FFFFFFFF;
  // Find the lowest alpha-less gob that covers the entire refresh area.
  while jvar <> 0 do begin
   dec(jvar);
   if (IsGobValid(jvar))
   and (gob[jvar].drawstate and 3 <> 0)
   and (gob[jvar].alphaness = $FF)
   and (gfxlist[gob[jvar].cachedgfx].bitflag and 128 = 0) then begin
    if (gob[jvar].locxp <= refrect.x1p)
    and (gob[jvar].locyp <= refrect.y1p)
    and (gob[jvar].locxp + longint(gob[jvar].sizexp) >= refrect.x2p)
    and (gob[jvar].locyp + longint(gob[jvar].sizeyp) >= refrect.y2p)
    then begin ivar := jvar; break; end;
   end;
  end;

  // If no alpha-less gob covers the entire area, gotta draw all gobs that
  // touch the area at all, and paint the background black to avoid potential
  // ghost images.
  if ivar = $FFFFFFFF then begin
   ivar := (refrect.y1p * longint(sysvar.mv_WinSizeX) + refrect.x1p) shl 2;
   poku := destbuf + ivar;
   jvar := refrect.y2p - refrect.y1p; // rows
   kvar := refrect.x2p - refrect.x1p; // cols
   lvar := sysvar.mv_WinSizeX shl 2;
   while jvar <> 0 do begin
    dec(jvar);
    filldword(poku^, kvar, 0);
    inc(poku, lvar);
   end;
   ivar := 0;
  end;

  // Draw that lowest alpha-less gob and everything over it.
  while ivar < dword(length(gob)) do begin
   if (IsGobValid(ivar))
   and (gob[ivar].drawstate and 3 <> 0)
   then begin
    // Get the up to date gfx index for the graphic we want.
    gob[ivar].cachedgfx := GetGFX(gob[ivar].gfxnamu, gob[ivar].sizexp, gob[ivar].sizeyp);

    with clipsi do begin
     srcp := gfxlist[gob[ivar].cachedgfx].bitmap;
     destp := destbuf;
     destofsxp := gob[ivar].locxp;
     destofsyp := gob[ivar].locyp;

     // Select the right frame to draw by adjusting the image source offset.
     copywidth := gob[ivar].sizexp;
     copyrows := gob[ivar].sizeyp;
     jvar := gob[ivar].sizexp * gob[ivar].sizeyp; // pixels per frame
     srcofs := jvar * gob[ivar].drawframe;

     // Guard against frames beyond actual image data.
     if srcofs + jvar > gfxlist[gob[ivar].cachedgfx].sizexp * gfxlist[gob[ivar].cachedgfx].sizeyp
     then begin
      LogError('Frame ' + strdec(gob[ivar].drawframe) + ' in ' + gob[ivar].gfxnamu + ' is out of image bounds');
      srcofs := 0;
     end;

     // Clip against the refresh rectangle.
     clipx1p := refrect.x1p;
     clipy1p := refrect.y1p;
     clipx2p := refrect.x2p;
     clipy2p := refrect.y2p;
     // Also clip against the containing viewport.
     clipviewport := gob[ivar].inviewport;
    end;

    // Calculate the how much of the gob should be drawn after clipping.
    ClipRGB(@clipsi);

    if (clipsi.copywidth <> 0) and (clipsi.copyrows <> 0) then begin

     with clipsi do
      log('[gob ' + strdec(ivar) + ': ' + gob[ivar].gobnamu
       + '; gfxlist ' + strdec(gob[ivar].cachedgfx) + ':' + gfxlist[gob[ivar].cachedgfx].namu
       + ' loc=' + strdec(destofsxp) + ',' + strdec(destofsyp)
       + ' size=' + strdec(copywidth) + 'x' + strdec(copyrows)
       + ']');

     // At last, draw the graphic
     if gob[ivar].solidblit <> 0 then
      DrawSolid(@clipsi, gob[ivar].solidblit, gfxlist[gob[ivar].cachedgfx].bitflag shr 7)
     else
     if gob[ivar].alphaness <> $FF then
      DrawRGBA32alpha(@clipsi, gob[ivar].alphaness)
     else
     if gfxlist[gob[ivar].cachedgfx].bitflag and $80 = 0 then
      DrawRGB24(@clipsi)
     else
      DrawRGBA32(@clipsi);
    end;
   end;

   inc(ivar);
  end;

  // After all graphics have been drawn in a refresh rectangle, apply the
  // gamma correction effect over that rectangle, if necessary.
  {$ifdef bonk}
  if RGBtweakactive <> $FF then with clipsi do begin
   {$note this RGBtweak doesn't handle viewports correctly}
   destp := destbuf;
   destofsx := refrect.x1p;
   destofsy := refrect.y1p;
   sourcecopywidth := refrect.x2p - refrect.x1p;
   sourcerows := refrect.y2p - refrect.y1p;
   sourceofs := 0;
   cliplocxp := viewport[1].viewportx1p; clipsizexp := viewport[1].viewportsizexp;
   cliplocyp := viewport[1].viewporty1p; clipsizeyp := viewport[1].viewportsizeyp;
   ClipRGB(@clipsi);
   ApplyRGBtweak(@clipsi);
  end;
  {$endif}

  // If a transition is ongoing, draw it now.
  if transitionactive < fxcount then RenderTransition;

  {$ifndef sakucon}
  // Draw textboxes unless using stashbuffy.
  if (gamevar.hideboxes = 0)
  and (destbuf <> stashbuffy) then begin
   ivar := 0;
   while ivar < dword(length(TBox)) do begin
    if TBox[ivar].boxstate <> BOXSTATE_NULL then begin
     with clipsi do begin
      srcp := TBox[ivar].finalbuf;
      destp := destbuf;
      destofsxp := TBox[ivar].boxlocxp_r;
      destofsyp := TBox[ivar].boxlocyp_r;
      copywidth := TBox[ivar].boxsizexp_r;
      copyrows := TBox[ivar].boxsizeyp_r;
      srcofs := 0;

      // Clip against the refresh rectangle.
      clipx1p := refrect.x1p;
      clipy1p := refrect.y1p;
      clipx2p := refrect.x2p;
      clipy2p := refrect.y2p;
      // Also clip against the containing viewport.
      clipviewport := TBox[ivar].inviewport;
     end;

     // Calculate the how much of the gob should be drawn after clipping.
     ClipRGB(@clipsi);

     if (clipsi.copywidth <> 0) and (clipsi.copyrows <> 0) then begin

      {with clipsi do
       log('[box ' + strdec(ivar) + ':'
        + ' loc=' + strdec(destofsxp) + ',' + strdec(destofsyp)
        + ' size=' + strdec(copywidth) + 'x' + strdec(copyrows)
        + ']');}

      // Draw the box.
      if TBox[ivar].boxstate in [BOXSTATE_APPEARING, BOXSTATE_VANISHING] then begin
       case TBox[ivar].style.poptype of
         2: DrawRGBA32alpha(@clipsi, dword(TBox[ivar].popruntime) * 255 div TBox[ivar].style.poptime);
         3: DrawRGBA32wipe(@clipsi, (dword(TBox[ivar].popruntime) shl 15) div TBox[ivar].style.poptime, TBox[ivar].boxstate = BOXSTATE_APPEARING);
         else DrawRGBA32(@clipsi);
       end;
      end
      else DrawRGBA32(@clipsi);
     end;

    end;
    inc(ivar);
   end;
  end;
  {$endif}
end;
{$endif oldrenderer}

procedure StashRender;
// Copies mv_OutputBuffy^ into stashbuffy^, then removes all visible
// textboxes. The resulting image can be used as a snapshot of an earlier
// game state, for example as the departing transition image, or as a save
// game thumbnail.
var backupfresh : array of tfresh;
    backupnumfresh : dword;
    ivar : dword;
begin
 // Initial bulk copy.
 move(mv_OutputBuffy^, stashbuffy^, sysvar.mv_WinSizeX * sysvar.mv_WinSizeY * 4);
 // Back up the current refresh regions.
 backupfresh := refresh;
 backupnumfresh := numfresh;
 refresh := NIL;
 numfresh := 0;
 // Build a new refresh list from currently shown textboxes.
 ivar := length(TBox);
 while ivar <> 0 do begin
  dec(ivar);
  with TBox[ivar] do
   if boxstate <> BOXSTATE_NULL then
   AddRefresh(boxlocxp_r, boxlocyp_r, boxlocxp_r + longint(boxsizexp_r), boxlocyp_r + longint(boxsizeyp_r));
 end;
 // Draw over all the textboxes.
 while numfresh <> 0 do begin
  dec(numfresh);
  RenderGobs(refresh[numfresh], stashbuffy);
 end;
 // Restore the refresh regions.
 refresh := backupfresh;
 numfresh := backupnumfresh;
 backupfresh := NIL;
 numfresh := 0;
end;
