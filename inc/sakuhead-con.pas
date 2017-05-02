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

procedure Log(const ert : UTF8string); inline;
begin writeln(logfile, ert); end;
procedure LogError(const ert : UTF8string); inline;
begin writeln(logfile, '[!] ', ert); end;

type LXYtriplet = record luma : byte; x, y : longint; end;

function RGBtoLXY(r, g, b : byte) : LXYtriplet;
// This converts an sRGB value to a kind of YCH space, great for perceptual
// comparisons. The first component is L', but the C and H are further
// transformed to x and y coordinates on a hue/saturation hexagon.
var multi, mulcomp : single;
    c : byte;
    msc : (red, green, blue);
    mscval, lscval : byte;
// On a hexagon with red on the right, green top left, and blue lower left:
// red   =  1.0, 0.0    =  255, 0
// green = -0.5, 0.866  = -128, 221
// blue  = -0.5, -0.866 = -128, -221

begin
 // This converts sRGB to BT.709 L'. Both in and out are in range 0..255.
 RGBtoLXY.luma := (6966 * r + 23436 * g + 2366 * b + 16383) shr 15;
 // Greyscale?
 if (r = g) and (r = b) then begin
  RGBtoLXY.x := 0; RGBtoLXY.y := 0; exit;
 end;

 // Get chroma/saturation, where in-range 0..255, out-range 1..255.
 msc := red; mscval := r;
 if g > r then begin msc := green; mscval := g; end;
 if b > mscval then begin msc := blue; mscval := b; end;
 lscval := r;
 if g < r then lscval := g;
 if b < lscval then lscval := b;
 c := mscval - lscval;

 // Translate hue into x and y coordinates, range -255..255.
 case msc of
   red:
   if g > b then begin // red-yellow
    multi := (g - b) / c;
    mulcomp := 1 - multi;
    RGBtoLXY.x := round(255 * mulcomp + 128 * multi);
    RGBtoLXY.y := round(0 * mulcomp + 221 * multi);
   end else begin // red-magenta
    multi := (b - g) / c;
    mulcomp := 1 - multi;
    RGBtoLXY.x := round(255 * mulcomp + 128 * multi);
    RGBtoLXY.y := round(0 * mulcomp + -221 * multi);
   end;

   green:
   if r > b then begin // green-yellow
    multi := (r - b) / c;
    mulcomp := 1 - multi;
    RGBtoLXY.x := round(-128 * mulcomp + 128 * multi);
    RGBtoLXY.y := 221;
   end else begin // green-cyan
    multi := (b - r) / c;
    mulcomp := 1 - multi;
    RGBtoLXY.x := round(-128 * mulcomp + -255 * multi);
    RGBtoLXY.y := round(221 * mulcomp + 0 * multi);
   end;

   blue:
   if g > r then begin // blue-cyan
    multi := (g - r) / c;
    mulcomp := 1 - multi;
    RGBtoLXY.x := round(-128 * mulcomp + -255 * multi);
    RGBtoLXY.y := round(-221 * mulcomp + 0 * multi);
   end else begin // blue-magenta
    multi := (r - g) / c;
    mulcomp := 1 - multi;
    RGBtoLXY.x := round(-128 * mulcomp + 128 * multi);
    RGBtoLXY.y := -221;
   end;
 end;

 // Apply the saturation as a multiplier toward 0,0.
 with RGBtoLXY do begin
  if x >= 0 then x := (x * c + 128) div 255
  else x := (x * c - 128) div 255;
  if y >= 0 then y := (y * c + 128) div 255
  else y := (y * c - 128) div 255;
 end;
end;

function diffRGB(c1, c2 : RGBquad) : dword;
// Returns the squared difference between two RGBquad colors.
var r, g, b : dword;
begin
 r := abs(c1.r - c2.r) * 3;
 g := abs(c1.g - c2.g) * 4;
 b := abs(c1.b - c2.b) * 2;
 diffRGB := r * r + g * g + b * b;
end;

function diffLXY(c1, c2 : LXYtriplet) : dword;
var ld, x, y : dword;
begin
 ld := abs(c1.luma - c2.luma) * 2;
 x := abs(c1.x - c2.x) * 3;
 y := abs(c1.y - c2.y) * 3;
 diffLXY := ld * ld + (x * x + y * y);
end;

var xpal : array[0..15] of array[0..15] of array[0..15] of byte;

procedure initxpal;
var rr, gg, bb : byte;
    mylxy : LXYtriplet;
    conpalhsl : array[0..$F] of LXYtriplet;
    rrr, ggg, bbb : dword;
    mycol, palcol : RGBquad;
    ivar, jvar : dword;
    nearest : byte;
    bestscore : dword;
begin
 // Acquire the exact RGB palette used by our console, if possible.
 GetConsolePalette;
 if saku_param.lxymix then log('Using LXY mixing with palette:')
 else log('Using RGB mixing with palette:');
 for ivar := 0 to 15 do log(strdec(ivar) + ': ' + strhex(crtpalette[ivar].r) + strhex(crtpalette[ivar].g) + strhex(crtpalette[ivar].b));

 if saku_param.lxymix then begin
  // Convert the console palette to HSL.
  for ivar := 0 to 15 do conpalhsl[ivar] := RGBtoLXY(crtpalette[ivar].r, crtpalette[ivar].g, crtpalette[ivar].b);

  // Due to our 16-color limit, no point doing a full 8-bit per channel
  // palette mapping. 4 bits per channel is plenty.
  // Loop through every possible color in a 4-bit RGB space.
  for rr := 0 to 15 do for gg := 0 to 15 do for bb := 0 to 15 do begin
   // Convert the 4-bit sRGB color to 8-bit sRGB.
   mylxy := RGBtoLXY(rr * 255 div 15, gg * 255 div 15, bb * 255 div 15);
   // Find the closest console palette color to this color.
   nearest := 0; bestscore := $FFFFFFFF;
   for ivar := 0 to 15 do begin
    jvar := diffLXY(mylxy, conpalhsl[ivar]);
    if jvar < bestscore then begin
     nearest := ivar; bestscore := jvar;
    end;
   end;
   // Check which other color the closest color mixes with 50-50 to get the
   // closest match. This could be itself. The true dithering midpoint is
   // found by doing the mix in linear RGB space, then returning to sRGB.
   for ivar := 0 to 15 do begin
    rrr := mcg_RevGammaTab[(mcg_GammaTab[crtpalette[nearest].r] + mcg_GammaTab[crtpalette[ivar].r]) shr 1];
    ggg := mcg_RevGammaTab[(mcg_GammaTab[crtpalette[nearest].g] + mcg_GammaTab[crtpalette[ivar].g]) shr 1];
    bbb := mcg_RevGammaTab[(mcg_GammaTab[crtpalette[nearest].b] + mcg_GammaTab[crtpalette[ivar].b]) shr 1];
    jvar := diffLXY(mylxy, RGBtoLXY(rrr, ggg, bbb));
    if jvar <= bestscore then begin
     xpal[rr][gg][bb] := nearest + ivar shl 4;
     bestscore := jvar;
    end;
   end;
  end;

 end else begin

  for rr := 0 to 15 do for gg := 0 to 15 do for bb := 0 to 15 do begin
   // Convert the 4-bit sRGB color to 8-bit sRGB.
   mycol.r := rr * 255 div 15;
   mycol.g := gg * 255 div 15;
   mycol.b := bb * 255 div 15;
   // Find the closest console palette color to this color.
   nearest := 0; bestscore := $FFFFFFFF;
   for ivar := 0 to 15 do begin
    palcol.r := crtpalette[ivar].r;
    palcol.g := crtpalette[ivar].g;
    palcol.b := crtpalette[ivar].b;
    jvar := diffRGB(mycol, palcol);
    if jvar < bestscore then begin
     nearest := ivar; bestscore := jvar;
    end;
   end;
   // Check which other color the closest color mixes with 50-50 to get the
   // closest match.
   for ivar := 0 to 15 do begin
    palcol.r := mcg_RevGammaTab[(mcg_GammaTab[crtpalette[nearest].r] + mcg_GammaTab[crtpalette[ivar].r]) shr 1];
    palcol.g := mcg_RevGammaTab[(mcg_GammaTab[crtpalette[nearest].g] + mcg_GammaTab[crtpalette[ivar].g]) shr 1];
    palcol.b := mcg_RevGammaTab[(mcg_GammaTab[crtpalette[nearest].b] + mcg_GammaTab[crtpalette[ivar].b]) shr 1];
    jvar := diffRGB(mycol, palcol);
    if jvar <= bestscore then begin
     xpal[rr][gg][bb] := nearest + ivar shl 4;
     bestscore := jvar;
    end;
   end;
  end;
 end;
end;

procedure SetProgramName(const newnamu : UTF8string); inline;
begin
 CrtSetTitle(newnamu);
end;
