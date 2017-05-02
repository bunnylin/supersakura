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

// ==================================================================
// The reverse-dithering algorithm
//
// - Detect lines
// - Adjust the image palette for gamma, temperature, saturation
// - Detect dithering patterns
// - Flatten dithering
// - Smooth alpha edges, if applicable
// - Do shadow edge blurring and edge-preserving blurring, if applicable

var rd_param : record
      lightness, chroma, temperature : byte; // range 0..32
      RDthres : byte; // reverse dithering filter sensitivity, range 0..32
      EPBthres : byte; // edge-preserving blur sensitivity, range 0..32
      SEBthres : byte; // shadow-edge blur sensitivity, range 0..32
      processHVlines, addspritealpha, checkerboardonly : boolean;
    end;

// This table has gamma-corrected values for 256 color channel intensities.
// The table is calculated by scaling [0..255] into a [0..1] range, then
// raising each value to the power of 2.2, and finally scaling the range up
// to [0..65535]. The low end has been further adjusted by hand.
// There is a reverse table in buncomp\gamma.inc, but since it takes 64k
// memory, it's better to generate a reverse table at runtime.
// Gamma-corrected values should be used in color comparisons wherever
// possible, as the result might be more visually pleasing. Mixing colors
// benefits as well, but then the result needs to be reverse-corrected.
var mcg_RevGammaTab : array of byte;
const mcg_GammaTab : array[0..255] of word = (
 0, 1, 2, 4, 7, 11, 17, 24, 32, 42, 53, 65, 79, 94, 111, 129,
 148, 169, 192, 216, 242, 270, 299, 330, 362, 396, 432, 469,
 508, 549, 591, 635, 681, 729, 779, 830, 883, 938, 995, 1053,
 1113, 1175, 1239, 1305, 1373, 1443, 1514, 1587, 1663, 1740, 1819, 1900,
 1983, 2068, 2155, 2243, 2334, 2427, 2521, 2618, 2717, 2817, 2920, 3024,
 3131, 3240, 3350, 3463, 3578, 3694, 3813, 3934, 4057, 4182, 4309, 4438,
 4570, 4703, 4838, 4976, 5115, 5257, 5401, 5547, 5695, 5845, 5998, 6152,
 6309, 6468, 6629, 6792, 6957, 7124, 7294, 7466, 7640, 7816, 7994, 8175,
 8358, 8543, 8730, 8919, 9111, 9305, 9501, 9699, 9900, 10102, 10307, 10515,
 10724, 10936, 11150, 11366, 11585, 11806, 12029, 12254,
 12482, 12712, 12944, 13179, 13416, 13655, 13896, 14140,
 14386, 14635, 14885, 15138, 15394, 15652, 15912, 16174,
 16439, 16706, 16975, 17247, 17521, 17798, 18077, 18358,
 18642, 18928, 19216, 19507, 19800, 20095, 20393, 20694,
 20996, 21301, 21609, 21919, 22231, 22546, 22863, 23182,
 23504, 23829, 24156, 24485, 24817, 25151, 25487, 25826,
 26168, 26512, 26858, 27207, 27558, 27912, 28268, 28627,
 28988, 29351, 29717, 30086, 30457, 30830, 31206, 31585,
 31966, 32349, 32735, 33124, 33514, 33908, 34304, 34702,
 35103, 35507, 35913, 36321, 36732, 37146, 37562, 37981,
 38402, 38825, 39252, 39680, 40112, 40546, 40982, 41421,
 41862, 42306, 42753, 43202, 43654, 44108, 44565, 45025,
 45487, 45951, 46418, 46888, 47360, 47835, 48313, 48793,
 49275, 49761, 50249, 50739, 51232, 51728, 52226, 52727,
 53230, 53736, 54245, 54756, 55270, 55787, 56306, 56828,
 57352, 57879, 58409, 58941, 59476, 60014, 60554, 61097,
 61642, 62190, 62741, 63295, 63851, 64410, 64971, 65535);

// ------------------------------------------------------------------

function mcg_GammaInput(color : rgbquad) : RGBA64;
// Applies a 2.2 gamma to convert display sRGB into a linear colorspace.
// Use this on all input colors, before doing any processing on them.
begin
 mcg_GammaInput.b := mcg_GammaTab[color.b];
 mcg_GammaInput.g := mcg_GammaTab[color.g];
 mcg_GammaInput.r := mcg_GammaTab[color.r];
 mcg_GammaInput.a := (color.a * 65535 + 128) div 255;
end;

function mcg_GammaOutput(color : RGBA64) : rgbquad;
// Applies a 1/2.2 gamma to convert linear colors into an sRGB colorspace.
// Use this on all adjusted colors just before actually drawing them.
begin
 mcg_GammaOutput.b := mcg_RevGammaTab[color.b];
 mcg_GammaOutput.g := mcg_RevGammaTab[color.g];
 mcg_GammaOutput.r := mcg_RevGammaTab[color.r];
 mcg_GammaOutput.a := (color.a * 255 + 32768) div 65535;
end;

// ::: DiffYCC :::
// The distance is calculated with perceptual weighting. The colors are
// broken from RGB color space into YCbCr, where Y is sort of greenish luma,
// and Cb and Cr are the delta from it to the red and blue components.
//
// The calculations are done with fixed point maths. This entails shifting
// numbers up somewhat, and doing digital rounding upon divisions. Digital
// rounding means adding half of the divisor to the dividee before dividing.
// For example: 15 div 4 = 3    but (15 + 2) div 4 = 4
//
// Finally, for the distance calculation, the components are weighed.
// 2 Y : 3/2 Cr : 1 Cb : 1 a (and afterwards, they are squared)
function diffYCC(c1, c2 : RGBA64) : dword;
var Y : longint;
    Cb, Cr : dword;
    aeon : word;
begin
 // RGB-to-YCbCr conversion: (ITU-R BT.709)
 //
 // Kb = 0.0722 = 2366 / 32768
 // Kr = 0.2126 = 6966 / 32768
 //
 // Y' = 0.2126r + 0.7152g + 0.0722b
 // Cr = (r - Y') / 1.5748
 // Cb = (b - Y') / 1.8556

 // This is the optimised version, the comparison can be unified without
 // breaking the expression! Here I use (c1 - c2).
 // Y ranges [-7FFF8000..7FFF8000], scaled to [-FFFF00..FFFF00]
 Y := (6966 * (c1.r - c2.r)
    + 23436 * (c1.g - c2.g)
     + 2366 * (c1.b - c2.b)) div 128;
 // Cr is in 24-bit scale, to start with; div 1.5748 becomes *256/403.1488
 // and when the *256 is dropped, Cr ends in a 16-bit scale [0..FFFF].
 Cr := (abs(c2.r shl 8 - c1.r shl 8 + Y) + 201) div 403;
 // Cb likewise, div 1.8556 becomes *256/475.0336, scaling to [0..FFFF].
 Cb := (abs(c2.b shl 8 - c1.b shl 8 + Y) + 237) div 475;

 // Shift Y from 24- to 17-bit scale (16-bit * 2, actually)
 Y := (abs(Y) + 64) shr 7;
 // Make Cr 16-bit * 1.5
 inc(Cr, Cr shr 1);
 // Keep Cb at 16-bit * 1
 // And let's not forget poor old alpha, also at 16-bit * 1 weight.
 aeon := abs(c2.a - c1.a);

 // Finally, calculate the difference-value itself
 // Numbers have to be squared, while trying hard not to overflow a dword,
 // without losing the lower end's granularity completely.
 diffYCC := Y + Cr + Cb + aeon; // nominal range of sum = [0..360443]
 Y := Y shr 2; // nominal range [0..32767], square 1 073 676 289
 Cr := Cr shr 2; // nominal range [0..24575], square 603 930 625
 Cb := Cb shr 2; // nominal range [0..16383], square 268 402 689
 aeon := aeon shr 2; // nominal range [0..16383], square 268 402 689
 inc(diffYCC, Y * Y + Cr * Cr + Cb * Cb + aeon * aeon);
 // Summed squares can nominally total up to 2 214 412 292.
 // With previous non-squared, the function's nominal output range becomes
 // [0..2 214 772 735] or [0..$8402BFFF].
 // In practice, the biggest output is $50017FFF, between black and white.
 // This means you might safely use the top bit for something else when
 // storing returned diff values.
end;

// ------------------------------------------------------------------

procedure Beautify(imu, flagimu, finalimu : pbitmaptype);
// Takes an 8-bit image from imu^ and applies reverse dithering on it.
// Places a debug flag image in flagimu^.
// Places the end result in finalimu^.
// You should set the algorithm parameters in rd_param before calling this.
//
// Flag meanings in low byte of p^:
//   1 - Definite horizontal line, dithered or not
//   2 - Definite vertical line
//   4 - Other non-dithered line, probably meandering
//   8 - Filter (RGBA components are tallied in finalimu^.image^)
//  10 - Edge on left side
//  20 - Edge on right side
//  40 - Edge on top side
//  80 - Edge on bottom side
//  FF - Don't touch this pixel, only set as user hint; overrides all above
var p : array of word; // flags, high byte is markcount
    palquad : array of RGBA64; // source pal with 2.2 gamma etc alterations
    poku1, poku2 : pointer;
    kol : RGBquad;
    ivar, jvar, kvar, lvar : dword;

  procedure DetectHVlines;
  // Attempts to identify horizontal and vertical edges in the source image,
  // flags them and single-pixel-width lines.
  var linea, lineb : array[0..3] of byte;
      ofsu : dword;
      wvar, xvar, yvar, zvar : word;

    function TestEdge : boolean;
    // Returns TRUE if there's a distinct edge between linea and lineb.
    var stack : array[0..7] of dword;
        cola, colb : RGBA64;
        wvar : byte;
    begin
     TestEdge := FALSE;
     filldword(stack[0], 8, 0);
     // if any pixels between lines are the same color, it's no edge
     for wvar := 3 downto 0 do begin
      if (linea[0] = lineb[wvar]) or (linea[1] = lineb[wvar]) then exit;
      inc(stack[0], palquad[linea[wvar]].b); inc(stack[1], palquad[linea[wvar]].g);
      inc(stack[2], palquad[linea[wvar]].r); inc(stack[3], palquad[linea[wvar]].a);
      inc(stack[4], palquad[lineb[wvar]].b); inc(stack[5], palquad[lineb[wvar]].g);
      inc(stack[6], palquad[lineb[wvar]].r); inc(stack[7], palquad[lineb[wvar]].a);
     end;
     // get both lines' average colors
     cola.b := (stack[0] + 2) shr 2; cola.g := (stack[1] + 2) shr 2;
     cola.r := (stack[2] + 2) shr 2; cola.a := (stack[3] + 2) shr 2;
     colb.b := (stack[4] + 2) shr 2; colb.g := (stack[5] + 2) shr 2;
     colb.r := (stack[6] + 2) shr 2; colb.a := (stack[7] + 2) shr 2;
     // moment of truth
     if DiffYCC(cola, colb) < $328000 then exit;
     TestEdge := TRUE;
    end;

    function LineBinLineA : boolean;
    // Returns true if all bytes in LineB[] can be found in LineA[].
    var rvar : byte;
    begin
     LineBinLineA := FALSE;
     for rvar := 3 downto 0 do
      if (LineB[rvar] <> LineA[0]) and (LineB[rvar] <> LineA[1])
      and (LineB[rvar] <> LineA[2]) and (LineB[rvar] <> LineA[3])
      then exit;
     LineBinLineA := TRUE;
    end;

  begin
   if (imu^.sizex < 4) or (imu^.sizey < 4) then exit;
   for yvar := imu^.sizey - 1 downto 0 do begin
    for xvar := imu^.sizex - 1 downto 0 do begin
     ofsu := yvar * imu^.sizex + xvar;
     // horizontal
     if xvar + 3 < imu^.sizex then begin
      // grab alpha row
      dword((@linea[0])^) := dword((imu^.image + ofsu)^);
      // if alpha row's 1st/3rd or 2nd/4th pixels don't match, skip
      if (linea[0] = linea[2]) and (linea[1] = linea[3]) then begin
       if yvar = 0 then begin
        // top row, automatic edge along top
        for zvar := 3 downto 0 do p[ofsu + zvar] := p[ofsu + zvar] or $40;
       end else begin
        dword((@lineb[0])^) := dword((imu^.image + ofsu - imu^.sizex)^);
        if TestEdge then for zvar := 3 downto 0 do begin
         // mark bottom edge, and horizontal line if has top+bottom
         p[ofsu + zvar] := p[ofsu + zvar] or $40;
         if (p[ofsu + zvar] and $C0 = $C0)
         and (p[ofsu + zvar] and 8 = 0)
          then p[ofsu + zvar] := p[ofsu + zvar] or 1;
         // mark above line's top edge, and horizontal line if has top+bottom
         p[ofsu + zvar - imu^.sizex] := p[ofsu + zvar - imu^.sizex] or $80;
         if (p[ofsu + zvar - imu^.sizex] and $C0 = $C0)
         and (p[ofsu + zvar - imu^.sizex] and 8 = 0)
          then p[ofsu + zvar - imu^.sizex] := p[ofsu + zvar - imu^.sizex] or 1;
        end;
       end;
       if yvar + 1 = imu^.sizey then begin
        // bottom row, automatic edge along bottom
        for zvar := 3 downto 0 do p[ofsu + zvar] := p[ofsu + zvar] or $80;
       end else begin
        dword((@lineb[0])^) := dword((imu^.image + ofsu + imu^.sizex)^);
        if TestEdge then for zvar := 3 downto 0 do begin
         // mark bottom edge, and horizontal line if has top+bottom
         p[ofsu + zvar] := p[ofsu + zvar] or $80;
         if (p[ofsu + zvar] and $C0 = $C0)
         and (p[ofsu + zvar] and 8 = 0)
          then p[ofsu + zvar] := p[ofsu + zvar] or 1;
         // mark below line's top edge, and horizontal line if has top+bottom
         p[ofsu + zvar + imu^.sizex] := p[ofsu + zvar + imu^.sizex] or $40;
         if (p[ofsu + zvar + imu^.sizex] and $C0 = $C0)
         and (p[ofsu + zvar + imu^.sizex] and 8 = 0)
          then p[ofsu + zvar + imu^.sizex] := p[ofsu + zvar + imu^.sizex] or 1;
        end;
       end;
      end;
     end;
     // vertical
     if yvar + 3 < imu^.sizey then begin
      // grab alpha row
      for zvar := 3 downto 0 do linea[zvar] := byte((imu^.image + ofsu + zvar * imu^.sizex)^);
      // if alpha row's 1st/3rd or 2nd/4th pixels don't match, skip
      if (linea[0] <> linea[2]) or (linea[1] <> linea[3]) then continue;
      if xvar = 0 then begin
       // leftmost row, automatic edge along left
       for zvar := 3 downto 0 do p[ofsu + zvar * imu^.sizex] := p[ofsu + zvar * imu^.sizex] or $10;
      end else begin
       for zvar := 3 downto 0 do lineb[zvar] := byte((imu^.image + ofsu + zvar * imu^.sizex - 1)^);
       if TestEdge then for zvar := 3 downto 0 do begin
        // mark left edge, and vertical line if has left+right
        p[ofsu + zvar * imu^.sizex] := p[ofsu + zvar * imu^.sizex] or $10;
        if (p[ofsu + zvar * imu^.sizex] and $30 = $30)
         and (p[ofsu + zvar * imu^.sizex] and 8 = 0)
         then p[ofsu + zvar * imu^.sizex] := p[ofsu + zvar * imu^.sizex] or 2;
        // mark previous line's right edge, and vert line if has left+right
        p[ofsu + zvar * imu^.sizex - 1] := p[ofsu + zvar * imu^.sizex - 1] or $20;
        if (p[ofsu + zvar * imu^.sizex - 1] and $30 = $30)
         and (p[ofsu + zvar * imu^.sizex - 1] and 8 = 0)
         then p[ofsu + zvar * imu^.sizex - 1] := p[ofsu + zvar * imu^.sizex - 1] or 2;
       end;
      end;
      if xvar + 1 = imu^.sizex then begin
       // rightmost row, automatic edge along right
       for zvar := 3 downto 0 do p[ofsu + zvar * imu^.sizex] := p[ofsu + zvar * imu^.sizex] or $20;
      end else begin
       for zvar := 3 downto 0 do lineb[zvar] := byte((imu^.image + ofsu + zvar * imu^.sizex + 1)^);
       if TestEdge then for zvar := 3 downto 0 do begin
        // mark right edge, and vertical line if has left+right
        p[ofsu + zvar * imu^.sizex] := p[ofsu + zvar * imu^.sizex] or $20;
        if (p[ofsu + zvar * imu^.sizex] and $30 = $30)
         and (p[ofsu + zvar * imu^.sizex] and 8 = 0)
         then p[ofsu + zvar * imu^.sizex] := p[ofsu + zvar * imu^.sizex] or 2;
        // mark next line's left edge, and vertical line if has left+right
        p[ofsu + zvar * imu^.sizex + 1] := p[ofsu + zvar * imu^.sizex + 1] or $10;
        if (p[ofsu + zvar * imu^.sizex + 1] and $30 = $30)
         and (p[ofsu + zvar * imu^.sizex + 1] and 8 = 0)
         then p[ofsu + zvar * imu^.sizex + 1] := p[ofsu + zvar * imu^.sizex + 1] or 2;
       end;
      end;
     end;
    end;
   end;
   // Line gap detection
   for yvar := imu^.sizey - 1 downto 0 do begin
    for xvar := imu^.sizex - 1 downto 0 do begin
     ofsu := yvar * imu^.sizex + xvar;
     // horizontal
     if (xvar >= 3) and (xvar + 2 < imu^.sizex) then
     if (p[ofsu] and 1 <> 0) and (p[ofsu + 1] and 1 <> 0)
     and (p[ofsu - 1] and 1 = 0) then begin
      // get colors of originating line
      word((@linea[0])^) := word((imu^.image + ofsu)^);
      lineb[0] := linea[0]; lineb[1] := linea[1];
      lineb[2] := linea[0]; lineb[3] := linea[0];
      // scan on until end of image or next marked line
      for wvar := 1 to xvar - 1 do begin
       if p[ofsu - wvar] and 1 = 0 then begin
        // not line
        zvar := byte((imu^.image + ofsu - wvar)^);
        if (zvar = lineb[0]) or (zvar = lineb[1]) then continue;
        if lineb[2] = lineb[0] then begin lineb[2] := zvar; continue; end;
        if zvar = lineb[2] then continue;
        if lineb[3] = lineb[0] then begin lineb[3] := zvar; continue; end;
        if zvar = lineb[3] then continue;
        break; // definitely too many colors
       end else begin
        if p[ofsu - wvar - 1] and 1 = 0 then break;
        // yes line
        word((@linea[2])^) := word((imu^.image + ofsu - wvar - 1)^);
        // test if all in-between colors are found in marked line segments
        if LineBinLineA then
         // mark the in-between as a line!
         for zvar := 1 to wvar - 1 do p[ofsu - zvar] := p[ofsu - zvar] or 1;
        break;
       end;
      end;
     end;
     // vertical
     if (yvar >= 3) and (yvar + 2 < imu^.sizey) then
     if (p[ofsu] and 2 <> 0) and (p[ofsu + imu^.sizex] and 2 <> 0)
     and (p[ofsu - imu^.sizex] and 2 = 0) then begin
      // get colors of originating line
      linea[0] := byte((imu^.image + ofsu)^);
      linea[1] := byte((imu^.image + ofsu + imu^.sizex)^);
      lineb[0] := linea[0]; lineb[1] := linea[1];
      lineb[2] := linea[0]; lineb[3] := linea[0];
      // scan on until end of image or next marked line
      for wvar := 1 to yvar - 1 do begin
       if p[ofsu - wvar * imu^.sizex] and 2 = 0 then begin
        // not line
        zvar := byte((imu^.image + ofsu - wvar * imu^.sizex)^);
        if (zvar = lineb[0]) or (zvar = lineb[1]) then continue;
        if lineb[2] = lineb[0] then begin lineb[2] := zvar; continue; end;
        if zvar = lineb[2] then continue;
        if lineb[3] = lineb[0] then begin lineb[3] := zvar; continue; end;
        if zvar = lineb[3] then continue;
        break; // definitely too many colors
       end else begin
        if p[ofsu - (wvar + 1) * imu^.sizex] and 2 = 0 then break;
        // yes line
        linea[2] := byte((imu^.image + ofsu - wvar * imu^.sizex)^);
        linea[3] := byte((imu^.image + ofsu - (wvar + 1) * imu^.sizex)^);
        // test if all in-between colors are found in marked line segments
        if LineBinLineA then
         // mark the in-between as a line!
         for zvar := 1 to wvar - 1 do p[ofsu - zvar * imu^.sizex] := p[ofsu - zvar * imu^.sizex] or 2;
        break;
       end;
      end;
     end;
    end;
   end;
  end;

  procedure DetectMeanderingLines;
  // Attempts to identify and mark single-pixel-wide single-color lines that
  // are not completely orthogonal.
  var ofsu : dword;
      xvar, yvar : word;

    function GetNeighbors : dword;
    // Checks which pixels adjacent to current location are the same color as
    // the current location's pixel. Returns 8 nibbles packed as a dword:
    // - lowest nibble is the count of matching pixels
    // - next nibbles up to highest are the directions of matching neighbors
    //   in no particular order, where
    //   0 = no neighbor direction saved in this nibble
    //   1 = neighbor up left
    //   proceeding clockwise around the current location to
    //   8 = neighbor directly left
    var poku : pointer;
        mycol : byte;

      procedure SaveIt(dir : byte); inline;
      begin
       GetNeighbors := ((GetNeighbors and $FFFFFFF0) shl 4) or dir + GetNeighbors and $F + 1;
      end;

    begin
     GetNeighbors := 0;
     poku := imu^.image + ofsu;
     mycol := byte(poku^);
     if xvar <> 0 then if byte((poku - 1)^) = mycol then GetNeighbors := $81;
     if xvar + 1 < imu^.sizex then if byte((poku + 1)^) = mycol then SaveIt($40);
     if yvar <> 0 then begin
      dec(poku, imu^.sizex);
      if xvar <> 0 then if byte((poku - 1)^) = mycol then SaveIt($10);
      if byte(poku^) = mycol then SaveIt($20);
      if xvar + 1 < imu^.sizex then if byte((poku + 1)^) = mycol then SaveIt($30);
      inc(poku, imu^.sizex);
     end;
     if yvar + 1 < imu^.sizey then begin
      inc(poku, imu^.sizex);
      if xvar <> 0 then if byte((poku - 1)^) = mycol then SaveIt($70);
      if byte(poku^) = mycol then SaveIt($60);
      if xvar + 1 < imu^.sizex then if byte((poku + 1)^) = mycol then SaveIt($50);
     end;
     poku := NIL;
    end;

    procedure TraceMeander;
    // Follows a suspected meandering line, and if it's not disqualified,
    // marks the whole shebang as an XLINE. Otherwise marks it as DONTSCAN.
    var wvar : dword;
        dx, dy : integer;
        direction, zvar, markbyte : byte;
    begin
     markbyte := 4; dx := 0; dy := 0;
     // find the end of the line, or detect if it loops
     wvar := GetNeighbors;
     direction := (wvar shr 4) and $F; // we came from this direction
     repeat

     until (dx or dy = 0);
    end;

  begin
   ofsu := imu^.sizex * imu^.sizey;
   for yvar := imu^.sizey - 1 downto 0 do begin
    for xvar := imu^.sizex - 1 downto 0 do begin
     dec(ofsu);
     if (p[ofsu] and $F = 0) // only test UNMARKED pixels
     and (GetNeighbors and $F = 2) // precisely 2 same-color neighbors
     then TraceMeander;
    end;
   end;
   // clear DONTSCAN flags
   for ofsu := imu^.sizey * imu^.sizex - 1 downto 0 do
    if p[ofsu] and $F = 7 then p[ofsu] := p[ofsu] and $F0;
  end;

  procedure TweakPalette;
  // Adjusts the temperature, lightness and chrominance of the RGB palette
  // entries in palquad[]. Converting to YCbCr or HSL results in trouble
  // since tweaking those components can too easily lead to the color falling
  // out of the RGB colorspace, and failure to convert back to RGB.
  var rvar : dword;
      qvar : longint;
      pvar : byte;

    function funk(x : word; n : byte) : word;
    // Funk = f(x) + ((x - f(x)) * 2n) / nmax
    // Uses a ^2 on x within the range [0..65535] to get f(x), a curve below
    // the 0,0-65535,65535 line.
    // g(x) is the same curve mirrored above the line.
    // Funk then returns a value linearry interpolated between f(x) and g(x),
    // with value n, whose range is [0..32], so nmax = 32.
    var fx : word;
    begin
     fx := (x * x + 32768) div 65535;
     funk := fx + ((x - fx) * (n shl 1) + 16) div 32;
    end;

  begin
   for pvar := high(palquad) downto 0 do begin
    with palquad[pvar] do begin
     // Adjust lightness
     if rd_param.lightness <> 16 then begin
      r := Funk(r, rd_param.lightness);
      g := Funk(g, rd_param.lightness);
      b := Funk(b, rd_param.lightness);
     end;
     // Chroma = difference between biggest and smallest component in RGB
     // The chrominance adjustment is basically movement toward or away from
     // greyscale, and the best greyscale is Y' luma.
     // Y' = 0.2126r + 0.7152g + 0.0722b
     if rd_param.chroma <> 16 then begin
      rvar := (13933 * r + 46871 * g + 4732 * b + 32768) shr 16;
      if rd_param.chroma < 16 then begin // toward luma
       r := (r * rd_param.chroma + rvar * (16 - rd_param.chroma) + 8) shr 4;
       g := (g * rd_param.chroma + rvar * (16 - rd_param.chroma) + 8) shr 4;
       b := (b * rd_param.chroma + rvar * (16 - rd_param.chroma) + 8) shr 4;
      end else begin // away from luma
       qvar := r shl 1 - rvar;
       if qvar > 65535 then qvar := 65535 else if qvar < 0 then qvar := 0;
       r := (r * (32 - rd_param.chroma) + qvar * (rd_param.chroma - 16) + 8) shr 4;
       qvar := g shl 1 - rvar;
       if qvar > 65535 then qvar := 65535 else if qvar < 0 then qvar := 0;
       g := (g * (32 - rd_param.chroma) + qvar * (rd_param.chroma - 16) + 8) shr 4;
       qvar := b shl 1 - rvar;
       if qvar > 65535 then qvar := 65535 else if qvar < 0 then qvar := 0;
       b := (b * (32 - rd_param.chroma) + qvar * (rd_param.chroma - 16) + 8) shr 4;
      end;
     end;
     // Adjust temperature
     if rd_param.temperature <> 16 then begin
      r := Funk(r, rd_param.temperature);
      b := Funk(b, 32 - rd_param.temperature);
     end;
    end;
   end;
  end;

  procedure Detect4x4Dither;
  // Finds 4x4 pixel patterns, marks them for flattening.
  type bloktype = record
         px : array[0..15] of byte; // palette indexes 4x4
         oddcol, evencol : array[0..15] of byte;
         numoddcols, numevencols : byte;
         bicolor : boolean;
       end;
       bloktypep = ^bloktype;
  var blok, nblok : bloktype;
      xvar, yvar : word;
      score : integer;

    procedure MarkBlok;
    // Calculates the 4x4 block's average color, adds up the RGBA components
    // in finalimu^.image^ for each pixel, marks block as FILTER.
    var poing : pointer;
        btal, gtal, rtal, atal, ofsu : dword;
        loopvar : byte;
    begin
     btal := 0; gtal := 0; rtal := 0; atal := 0;
     for loopvar := 15 downto 0 do begin
      // tally color components
      inc(btal, palquad[blok.px[loopvar]].b);
      inc(gtal, palquad[blok.px[loopvar]].g);
      inc(rtal, palquad[blok.px[loopvar]].r);
      inc(atal, palquad[blok.px[loopvar]].a);
     end;
     // calculate average color across block
     btal := (btal + 8) shr 4; gtal := (gtal + 8) shr 4;
     rtal := (rtal + 8) shr 4; atal := (atal + 8) shr 4;
     for loopvar := 15 downto 0 do begin
      ofsu := (yvar + loopvar shr 2) * imu^.sizex + xvar + loopvar and 3;
      p[ofsu] := p[ofsu] or 8; // mark as FILTER
      inc(p[ofsu], $100); // increase markcount
      poing := finalimu^.image + ofsu * 12; // 3 bytes per pixel
      inc(dword(poing^), btal); // AAAA AARR RRRR GGGG GGBB BBBB
      inc(dword((poing + 3)^), gtal);
      inc(dword((poing + 6)^), rtal);
      inc(dword((poing + 9)^), atal);
     end;
     poing := NIL;
    end;

    function GetBlok(xx, yy : word; here : bloktypep) : boolean;
    // Copies a 4x4 pixel block from the source image at xx, yy into here^.
    // Returns FALSE if requested area has any internal edges, or in fact
    // anything except UNMARKED and FILTER flags.
    var ooh : dword;
        vvar, uvar : byte;
    begin
     GetBlok := FALSE;
     ooh := yy * imu^.sizex + xx;
     // row 1
     if (p[ooh] and $A7) or (p[ooh + 1] and $B7)
     or (p[ooh + 2] and $B7) or (p[ooh + 3] and $97) <> 0 then exit;
     dword((@here^.px[0])^) := dword((imu^.image + ooh)^);
     inc(ooh, imu^.sizex);
     // row 2
     if (p[ooh] and $E7) or (p[ooh + 1] and $F7)
     or (p[ooh + 2] and $F7) or (p[ooh + 3] and $D7) <> 0 then exit;
     dword((@here^.px[4])^) := dword((imu^.image + ooh)^);
     inc(ooh, imu^.sizex);
     // row 3
     if (p[ooh] and $E7) or (p[ooh + 1] and $F7)
     or (p[ooh + 2] and $F7) or (p[ooh + 3] and $D7) <> 0 then exit;
     dword((@here^.px[8])^) := dword((imu^.image + ooh)^);
     inc(ooh, imu^.sizex);
     // row 4
     if (p[ooh] and $67) or (p[ooh + 1] and $77)
     or (p[ooh + 2] and $77) or (p[ooh + 3] and $57) <> 0 then exit;
     dword((@here^.px[12])^) := dword((imu^.image + ooh)^);
     // Also, tabulate the frequency of colors in this block
     with here^ do begin
      numoddcols := 1;
      filldword(evencol[0], 4, 0);
      oddcol[0] := px[15]; evencol[0] := 1;
      for vvar := 14 downto 0 do begin
       ooh := numoddcols;
       while ooh <> 0 do begin
        dec(ooh);
        if oddcol[ooh] = px[vvar] then begin inc(evencol[ooh]); break; end;
        if ooh = 0 then begin
         oddcol[numoddcols] := px[vvar]; evencol[numoddcols] := 1;
         inc(numoddcols);
         if numoddcols > 4 then exit; // too many colors in block? no good
        end;
       end;
      end;
      // two-color blocks get more leniency later, mark them
      bicolor := FALSE;
      if numoddcols = 2 then bicolor := TRUE;
      // sort the two most frequent colors at bottom of list
      if numoddcols > 1 then
       for ooh := 1 downto 0 do
        for vvar := numoddcols - 2 downto 0 do
         if evencol[vvar + 1] > evencol[vvar] then begin
          uvar := evencol[vvar + 1]; evencol[vvar + 1] := evencol[vvar]; evencol[vvar] := uvar;
          uvar := oddcol[vvar + 1]; oddcol[vvar + 1] := oddcol[vvar]; oddcol[vvar] := uvar;
         end;
      // if any adjacent two pixels in block are same color, it must be the
      // dominant color, or this block is out
      for ooh := 3 downto 0 do for vvar := 3 downto 0 do begin
       uvar := ooh shl 2 + vvar;
       if (px[uvar] = px[ooh shl 2 + (vvar + 1) and 3])
       or (px[uvar] = px[((ooh + 1) and 3) shl 2 + vvar]) then
        if (px[uvar] <> oddcol[0]) or (evencol[0] = evencol[1]) then exit;
      end;
     end;
     GetBlok := TRUE;
    end;

    procedure SortBlokColors(here : bloktypep);
    // Tabulates each distinct color present on both sides of a checkerboard
    // pattern in the here^ block. Result goes in here^ as well.
    var wvar, zvar : byte;
    begin
     with here^ do begin
      dword((@oddcol[0])^) := $FFFFFFFF;
      dword((@evencol[0])^) := $FFFFFFFF;
      oddcol[0] := px[15]; numoddcols := 1;
      evencol[0] := px[14]; numevencols := 1;
      for zvar := 13 downto 0 do begin
       if ((zvar and 3) xor (zvar shr 2)) and 1 = 0 then begin
        oddcol[numoddcols] := px[zvar]; // odds
        for wvar := numoddcols - 1 downto 0 do
         if oddcol[wvar] = px[zvar] then dec(numoddcols);
        inc(numoddcols);
       end else begin
        evencol[numevencols] := px[zvar]; // evens
        for wvar := numevencols - 1 downto 0 do
         if evencol[wvar] = px[zvar] then dec(numevencols);
        inc(numevencols);
       end;
      end;
      if numoddcols < 8 then oddcol[numoddcols] := $FF;
      if numevencols < 8 then evencol[numevencols] := $FF;
      // sort first three colors in list, for easier comparison later
      if oddcol[0] > oddcol[1] then begin wvar := oddcol[0]; oddcol[0] := oddcol[1]; oddcol[1] := wvar; end;
      if oddcol[1] > oddcol[2] then begin wvar := oddcol[2]; oddcol[2] := oddcol[1]; oddcol[1] := wvar; end;
      if oddcol[0] > oddcol[1] then begin wvar := oddcol[0]; oddcol[0] := oddcol[1]; oddcol[1] := wvar; end;
      if evencol[0] > evencol[1] then begin wvar := evencol[0]; evencol[0] := evencol[1]; evencol[1] := wvar; end;
      if evencol[1] > evencol[2] then begin wvar := evencol[2]; evencol[2] := evencol[1]; evencol[1] := wvar; end;
      if evencol[0] > evencol[1] then begin wvar := evencol[0]; evencol[0] := evencol[1]; evencol[1] := wvar; end;
     end;
    end;

    function RateMyBlok : byte;
    // Returns a similarity score 0..60, between blok^ and nblok^.
    var gvar : byte;
    begin
     RateMyBlok := 0;
     // does neighbor have exact same colors?
     if (blok.numoddcols <> nblok.numoddcols)
     or (blok.numevencols <> nblok.numevencols)
     or (dword((@blok.oddcol[0])^) <> dword((@nblok.oddcol[0])^))
     or (dword((@blok.evencol[0])^) <> dword((@nblok.evencol[0])^))
     then exit;
     // count matching pixels
     for gvar := 15 downto 0 do if blok.px[gvar] = nblok.px[gvar] then inc(RateMyBlok);
     // award points, starting from 60
     RateMyBlok := 120 div (18 - RateMyBlok);
     // except if our block has more than 2 colors, demand perfect match
     if (blok.bicolor = FALSE) and (RateMyBlok <> 60)
     then RateMyBlok := 0;
    end;

  begin
   if (imu^.sizex < 4) or (imu^.sizey < 4) then exit;
   for yvar := imu^.sizey - 4 downto 0 do begin
    for xvar := imu^.sizex - 4 downto 0 do begin
     // init evaluation
     score := 0;
     if GetBlok(xvar, yvar, @blok) = FALSE then continue;
     // evaluate ditheriness
     SortBlokColors(@blok);
     with blok do begin
      // is it a pure 50-50 checkerboard pattern? or a flat color block?
      if (numoddcols = 1) and (numevencols = 1)
      then begin MarkBlok; continue; end;
      // if it's not checkerboard, and checkerboardonly = true, skip ahead
      if rd_param.checkerboardonly then continue;
      // if one half is single color, the other half may have up to 2 other
      // colors, or 3 is the first half's color is included; otherwise skip
      if numoddcols = 1 then begin
       oddcol[7] := 2;
       if (evencol[0] = oddcol[0]) or (evencol[1] = oddcol[0]) or (evencol[2] = oddcol[0]) then inc(oddcol[7]);
       if numevencols > oddcol[7] then continue;
      end;
      if numevencols = 1 then begin
       evencol[7] := 2;
       if (oddcol[0] = evencol[0]) or (oddcol[1] = evencol[0]) or (oddcol[2] = evencol[0]) then inc(evencol[7]);
       if numoddcols > evencol[7] then continue;
      end;
      // if either half has more than 1 color and the other has more than
      // 2 colors, skip
      if (numoddcols > 1) and (numevencols > 2)
      or (numevencols > 1) and (numoddcols > 2) then continue;
     end;
     // compare with neighboring blocks
     if yvar >= 4 then begin
      if GetBlok(xvar, yvar - 4, @nblok) then begin
       SortBlokColors(@nblok);
       inc(score, RateMyBlok);
      end;
      if xvar >= 4 then
      if GetBlok(xvar - 4, yvar - 4, @nblok) then begin
       SortBlokColors(@nblok);
       inc(score, RateMyBlok div 3);
      end;
      if xvar <= imu^.sizex - 8 then
      if GetBlok(xvar + 4, yvar - 4, @nblok) then begin
       SortBlokColors(@nblok);
       inc(score, RateMyBlok div 3);
      end;
     end;
     if yvar <= imu^.sizey - 8 then begin
      if GetBlok(xvar, yvar + 4, @nblok) then begin
       SortBlokColors(@nblok);
       inc(score, RateMyBlok);
      end;
      if xvar >= 4 then
      if GetBlok(xvar - 4, yvar + 4, @nblok) then begin
       SortBlokColors(@nblok);
       inc(score, RateMyBlok div 3);
      end;
      if xvar <= imu^.sizex - 8 then
      if GetBlok(xvar + 4, yvar + 4, @nblok) then begin
       SortBlokColors(@nblok);
       inc(score, RateMyBlok div 3);
      end;
     end;
     if xvar >= 4 then
     if GetBlok(xvar - 4, yvar, @nblok) then begin
      SortBlokColors(@nblok);
      inc(score, RateMyBlok);
     end;
     if xvar <= imu^.sizex - 8 then
     if GetBlok(xvar + 4, yvar, @nblok) then begin
      SortBlokColors(@nblok);
      inc(score, RateMyBlok);
     end;

     // does score exceed threshold?
     if score >= 120 then MarkBlok;
    end;
   end;
  end;

  procedure Detect2x2Dither;
  // Finds 2x2 pixel patterns, marks them for flattening.
  type bloktype = record
         px : array[0..3] of byte;
         flag : array[0..3] of word;
       end;
       bloktypep = ^bloktype;
  var blok, nblok : bloktype;
      resultcount : dword;
      btally, gtally, rtally, atally : dword;
      xvar, yvar, score : word;
      tallyweight : byte;

    procedure MarkBlok;
    // Figures out the 2x2 block's and its matching neighbors' average color,
    // saves the RGBA components in finalimu^.image^ for each pixel, marks
    // the block as FILTER.
    var poing : pointer;
        ofsu : dword;
        loopvar : byte;
    begin
     for loopvar := 3 downto 0 do begin
      // tally color components
      inc(btally, palquad[blok.px[loopvar]].b);
      inc(gtally, palquad[blok.px[loopvar]].g);
      inc(rtally, palquad[blok.px[loopvar]].r);
      inc(atally, palquad[blok.px[loopvar]].a);
      inc(tallyweight);
     end;
     // calculate average color across block
     ofsu := tallyweight shr 1;
     btally := (btally + ofsu) div tallyweight;
     gtally := (gtally + ofsu) div tallyweight;
     rtally := (rtally + ofsu) div tallyweight;
     atally := (atally + ofsu) div tallyweight;
     // save the result
     for loopvar := 3 downto 0 do begin
      ofsu := (yvar + loopvar shr 1) * imu^.sizex + xvar + loopvar and 1;
      p[ofsu] := p[ofsu] or 8; // mark as FILTER
      inc(p[ofsu], $100); // increase markcount
      poing := finalimu^.image + ofsu * 12; // 3 bytes per pixel
      inc(dword(poing^), btally); // AAAA AARR RRRR GGGG GGBB BBBB
      inc(dword((poing + 3)^), gtally);
      inc(dword((poing + 6)^), rtally);
      inc(dword((poing + 9)^), atally);
     end;
     poing := NIL;
     inc(resultcount);
    end;

    function GetBlok(xx, yy : word; here : bloktypep) : boolean;
    // Copies a 2x2 pixel block from the source image at xx, yy into here^.
    // Returns FALSE if requested area doesn't look at all dithered.
    var ofsu : dword;
    begin
     GetBlok := FALSE;
     ofsu := yy * imu^.sizex + xx;
     with here^ do begin
      dword((@flag[0])^) := dword((@p[ofsu])^);
      dword((@flag[2])^) := dword((@p[ofsu + imu^.sizex])^);
      // block may be UNMARKED or FILTER, and no internal edges
      if (flag[0] and $A7 <> 0) or (flag[1] and $97 <> 0)
      or (flag[2] and $67 <> 0) or (flag[3] and $57 <> 0) then exit;
      word((@here^.px[0])^) := word((imu^.image + ofsu)^);
      word((@here^.px[2])^) := word((imu^.image + ofsu + imu^.sizex)^);
      // if block is completely a single color, skip
      if (px[0] = px[1]) and (word((@px[0])^) = word((@px[2])^)) then exit;
      // if checkerboardonly, block must be a dither of two colors
      if rd_param.checkerboardonly then
       if (px[0] <> px[3]) or (px[1] <> px[2]) then exit;
     end;
     GetBlok := TRUE;
    end;

    function RateMyBlok(xx, yy : word; multi : byte) : boolean;
    // Adds a similarity value, between blok^ and nblok^, to score. Also adds
    // color components to a weighed average, in case blok^ eventually gets
    // marked as FILTER.
    var subscore, svar, tvar, uvar : byte;
    begin
     RateMyBlok := FALSE;
     if GetBlok(xx, yy, @nblok) = FALSE then exit;
     subscore := 0;
     // perfect pixel match?
     if dword((@blok.px[0])^) = dword((@nblok.px[0])^) then subscore := 8
     else begin
      if rd_param.checkerboardonly then exit;
      // off by more than one pixel?
      svar := $FF; tvar := 0;
      for uvar := 3 downto 0 do
       if blok.px[uvar] <> nblok.px[uvar] then begin inc(tvar); svar := uvar; end;
      if tvar > 1 then exit;
      // the off-pixel's color must be somewhere in blok^ or marked FILTER
      if nblok.flag[svar] and 8 = 0 then begin
       tvar := 0;
       for uvar := 3 downto 0 do
        if nblok.px[svar] = blok.px[uvar] then inc(tvar);
       if tvar = 0 then exit;
      end;
      subscore := 4;
     end;
     // tally the colors
     for uvar := 3 downto 0 do with nblok do begin
      inc(btally, palquad[px[uvar]].b);
      inc(gtally, palquad[px[uvar]].g);
      inc(rtally, palquad[px[uvar]].r);
      inc(atally, palquad[px[uvar]].a);
      inc(tallyweight);
     end;
     // triple bonus if neighbor is entirely marked FILTER!
     if (nblok.flag[0] and 8 <> 0) and (nblok.flag[1] and 8 <> 0)
     and (nblok.flag[2] and 8 <> 0) and (nblok.flag[3] and 8 <> 0)
     then subscore := subscore * 3;
     // tally the score
     inc(score, subscore * multi);
     RateMyBlok := TRUE;
    end;

    procedure CompBloks;
    // Compares blok^ with a variety of neighbors and keeps score.
    begin
     score := 0; tallyweight := 0;
     rtally := 0; gtally := 0; btally := 0; atally := 0;
     // block must have at least one UNMARKED pixel
     // or a FILTER pixel that doesn't have any tallied color
     if (blok.flag[0] and $F = 0) or (blok.flag[1] and $F = 0)
     or (blok.flag[2] and $F = 0) or (blok.flag[3] and $F = 0)
     or (blok.flag[0] = $4) or (blok.flag[1] = $4)
     or (blok.flag[2] = $4) or (blok.flag[3] = $4)
     then begin

      if yvar >= 2 then begin
       // upward
       if RateMyBlok(xvar, yvar - 2, 3) then if yvar >= 4 then
       if RateMyBlok(xvar, yvar - 4, 3) then if yvar >= 8
       then RateMyBlok(xvar, yvar - 8, 2);
       // up left
       if xvar >= 2 then
       if RateMyBlok(xvar - 2, yvar - 2, 2) then if (xvar >= 4) and (yvar >= 4)
       then RateMyBlok(xvar - 4, yvar - 4, 2);
       // up right
       if xvar + 3 < imu^.sizex then
       if RateMyBlok(xvar + 2, yvar - 2, 2) then if (xvar + 5 < imu^.sizex) and (yvar >= 4)
       then RateMyBlok(xvar + 4, yvar - 4, 2);
      end;
      if yvar + 3 < imu^.sizey then begin
       // downward
       if RateMyBlok(xvar, yvar + 2, 3) then if yvar + 5 < imu^.sizey then
       if RateMyBlok(xvar, yvar + 4, 3) then if yvar + 9 < imu^.sizey
       then RateMyBlok(xvar, yvar + 8, 2);
       // down left
       if xvar >= 2 then
       if RateMyBlok(xvar - 2, yvar + 2, 2) then if (xvar >= 4) and (yvar + 5 < imu^.sizey)
       then RateMyBlok(xvar - 4, yvar + 4, 2);
       // down right
       if xvar + 3 < imu^.sizex then
       if RateMyBlok(xvar + 2, yvar + 2, 2) then if (xvar + 5 < imu^.sizex) and (yvar + 5 < imu^.sizey)
       then RateMyBlok(xvar + 4, yvar + 4, 2);
      end;
      // leftward
      if xvar >= 2 then
      if RateMyBlok(xvar - 2, yvar, 3) then if xvar >= 4 then
      if RateMyBlok(xvar - 4, yvar, 3) then if xvar >= 8
      then RateMyBlok(xvar - 8, yvar, 2);
      // rightward
      if xvar + 3 < imu^.sizex then
      if RateMyBlok(xvar + 2, yvar, 3) then if xvar + 5 < imu^.sizex then
      if RateMyBlok(xvar + 4, yvar, 3) then if xvar + 9 < imu^.sizex
      then RateMyBlok(xvar + 8, yvar, 2);

      // all that aside, are we there yet?
      if score >= 120 then MarkBlok;
     end;
    end;

  begin
   if (imu^.sizex < 2) or (imu^.sizey < 2) then exit;
   repeat
    // test forwards
    resultcount := 0;
    for yvar := 0 to imu^.sizey - 2 do
     for xvar := 0 to imu^.sizex - 2 do
      if GetBlok(xvar, yvar, @blok) then CompBloks;
    if resultcount = 0 then exit;
    // test backwards
    resultcount := 0;
    for yvar := imu^.sizey - 2 downto 0 do
     for xvar := imu^.sizex - 2 downto 0 do
      if GetBlok(xvar, yvar, @blok) then CompBloks;
    if resultcount = 0 then exit;
   until FALSE;
  end;

  function TallyPixel(ofsu : dword; multi, mask : byte) : boolean;
  // Used in H/V line rendering to tally pixel color values.
  begin
   TallyPixel := FALSE;
   if p[ofsu] and mask = 0 then exit;
   TallyPixel := TRUE;
   inc(jvar, multi);
   inc(dword((poku2 + 0)^), palquad[byte((imu^.image + ofsu)^)].b * multi);
   inc(dword((poku2 + 3)^), palquad[byte((imu^.image + ofsu)^)].g * multi);
   inc(dword((poku2 + 6)^), palquad[byte((imu^.image + ofsu)^)].r * multi);
   inc(dword((poku2 + 9)^), palquad[byte((imu^.image + ofsu)^)].a * multi);
  end;

begin
 if (imu = NIL) or (imu^.image = NIL) or (imu^.memformat in [4,5] = FALSE)
 or (length(imu^.palette) = 0) or (length(imu^.palette) > 256)
 then exit;
 // Initialisation
 mcg_ForgetImage(flagimu);
 mcg_ForgetImage(finalimu);
 flagimu^.sizex := imu^.sizex; finalimu^.sizex := imu^.sizex;
 flagimu^.sizey := imu^.sizey; finalimu^.sizey := imu^.sizey;
 flagimu^.bitdepth := 8; finalimu^.bitdepth := 8;
 flagimu^.memformat := 4; // indexed without alpha
 finalimu^.memformat := imu^.memformat and 1; // RGB or RGBA
 ivar := imu^.sizex * imu^.sizey;
 getmem(flagimu^.image, ivar);
 getmem(finalimu^.image, ivar * 12);
 filldword(finalimu^.image^, ivar * 3, 0);
 setlength(p, ivar); // pixel action map
 fillword(p[0], ivar, 0); // all pixels UNMARKED
 with flagimu^ do begin
  setlength(palette, 256);
  dword(palette[0]) := $FF000000; // unmarked black
  dword(palette[1]) := $FF2020FF; // horizontal line blue
  dword(palette[2]) := $FFF00000; // vertical line red
  dword(palette[3]) := $FFFF00FF; // h/v line purple
  dword(palette[4]) := $FFA0A0A0; // meandering etc line grey
  dword(palette[8]) := $FF00C000; // filter green
  dword(palette[$F]) := $FFFFFFFF; // donttouch white
  dword(palette[$10]) := $FFA00000; // left edge dark red
  dword(palette[$20]) := $FFDD8080; // right edge light red
  dword(palette[$30]) := $FFFF0000; // vertical line red
  dword(palette[$40]) := $FF1020A0; // top edge dark blue
  dword(palette[$50]) := $FFA000A0; // top+left dark violet
  dword(palette[$60]) := $FFFF80C0; // top+right purple
  dword(palette[$70]) := $FFDDDDDD; // vertical line+top white
  dword(palette[$80]) := $FF8080FF; // bottom edge light blue
  dword(palette[$90]) := $FFB040FF; // left+bottom indigo
  dword(palette[$A0]) := $FFFF80FF; // right+bottom bright violet
  dword(palette[$B0]) := $FFDDDDDD; // vertical line+bottom white
  dword(palette[$C0]) := $FF0010FF; // horizontal line blue
  dword(palette[$D0]) := $FFDDDDDD; // horizontal line+left white
  dword(palette[$E0]) := $FFDDDDDD; // horizontal line+right white
  dword(palette[$F0]) := $FFFFFFFF; // all edges white
  dword(palette[$FF]) := $FFFFFFFF; // donttouch white
 end;

 // Generate a reverse gamma correction table, if necessary
 if length(mcg_RevGammaTab) = 0 then begin
  setlength(mcg_RevGammaTab, 65536);
  jvar := 254;
  for ivar := 65535 downto 0 do begin
   if ivar < mcg_GammaTab[jvar] then dec(jvar);
   if mcg_GammaTab[jvar + 1] - ivar < ivar - mcg_GammaTab[jvar]
   then mcg_RevGammaTab[ivar] := jvar + 1
   else mcg_RevGammaTab[ivar] := jvar;
  end;
 end;

 // Generate 2.2-gamma-adjusted palette
 setlength(palquad, length(imu^.palette));
 for ivar := high(palquad) downto 0 do
  palquad[ivar] := mcg_GammaInput(imu^.palette[ivar]);

 if rd_param.processHVlines then DetectHVlines;
 DetectMeanderingLines;
 TweakPalette;
 Detect4x4Dither;
 //Detect2x2Dither;
 // Render flag and final images
 ivar := 0;
 for kvar := 0 to imu^.sizey - 1 do begin
  for lvar := 0 to imu^.sizex - 1 do begin
   poku1 := finalimu^.image + ivar * 8; // final render destination
   poku2 := poku1 + ivar shl 2; // RGBA tallies are here

   if p[ivar] <> $FF then begin
    jvar := 0;
    if p[ivar] and 1 <> 0 then begin // preprocess H Line
     TallyPixel(ivar, 8, 1);
     if lvar >= 1 then if TallyPixel(ivar - 1, 6, 1) then
     if lvar >= 2 then if TallyPixel(ivar - 2, 4, 1) then
     if lvar >= 3 then TallyPixel(ivar - 3, 3, 1);
     if lvar + 2 <= imu^.sizex then if TallyPixel(ivar + 1, 8, 1) then
     if lvar + 3 <= imu^.sizex then if TallyPixel(ivar + 2, 6, 1) then
     if lvar + 4 <= imu^.sizex then if TallyPixel(ivar + 3, 4, 1) then
     if lvar + 5 <= imu^.sizex then TallyPixel(ivar + 4, 3, 1);
    end;
    if p[ivar] and 2 <> 0 then begin // preprocess V Line
     TallyPixel(ivar, 8, 2);
     if kvar >= 1 then if TallyPixel(ivar - imu^.sizex, 6, 2) then
     if kvar >= 2 then if TallyPixel(ivar - imu^.sizex * 2, 4, 2) then
     if kvar >= 3 then TallyPixel(ivar - imu^.sizex * 3, 3, 2);
     if kvar + 2 <= imu^.sizey then if TallyPixel(ivar + imu^.sizex, 8, 2) then
     if kvar + 3 <= imu^.sizey then if TallyPixel(ivar + imu^.sizex * 2, 6, 2) then
     if kvar + 4 <= imu^.sizey then if TallyPixel(ivar + imu^.sizex * 3, 4, 2) then
     if kvar + 5 <= imu^.sizey then TallyPixel(ivar + imu^.sizex * 4, 3, 2);
    end;
    if p[ivar] and 8 <> 0 then begin // preprocess Filter
     jvar := p[ivar] shr 8;
    end;
   end;

   case p[ivar] and $F of
    0, $F: // UNMARKED or DONTTOUCH, direct copy from source
        RGBA64(poku1^) := palquad[byte((imu^.image + ivar)^)];
    1..3, 8: begin // FILTER
        RGBA64(poku1^).b := (dword(poku2^) and $FFFFFF + jvar shr 1) div jvar;
        RGBA64(poku1^).g := (dword((poku2 + 3)^) and $FFFFFF + jvar shr 1) div jvar;
        RGBA64(poku1^).r := (dword((poku2 + 6)^) and $FFFFFF + jvar shr 1) div jvar;
        RGBA64(poku1^).a := (dword((poku2 + 9)^) and $FFFFFF + jvar shr 1) div jvar;
       end;
   end;
   // sanitise flags for visibility
   if p[ivar] and $F <> 0 then p[ivar] := p[ivar] and $F;
   byte((flagimu^.image + ivar)^) := p[ivar] and $FF;
   inc(ivar);
  end;
 end;
 // Post-processing

 // Finally, apply reverse gamma correction
 poku1 := finalimu^.image; // source pointer
 poku2 := finalimu^.image; // dest pointer
 if finalimu^.memformat = 1 then begin // alpha exists, output 32-bit RGBA
  for ivar := 0 to imu^.sizex * imu^.sizey - 1 do begin
   RGBquad(poku2^) := mcg_GammaOutput(RGBA64(poku1^));
   inc(poku1, 8);
   inc(poku2, 4);
  end;
 end else begin // no alpha, output 24-bit RGB
  for ivar := 0 to imu^.sizex * imu^.sizey - 1 do begin
   kol := mcg_GammaOutput(RGBA64(poku1^));
   inc(poku1, 8);
   byte(poku2^) := kol.b; inc(poku2);
   byte(poku2^) := kol.g; inc(poku2);
   byte(poku2^) := kol.r; inc(poku2);
  end;
 end;

 reallocmem(finalimu^.image, finalimu^.sizex * finalimu^.sizey * (3 + finalimu^.memformat));
 poku1 := NIL; poku2 := NIL;
end;
