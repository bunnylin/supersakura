{                                                                           }
{ Copyright 2009 :: Kirinn Bunnylin / Mooncore                              }
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

procedure UnpackMakiGraphic(PNGindex : word; subtype : byte);
// Attempts to decompress a Maki v1 image from (loader + lofs)^ and puts the
// result in PNGlist[PNGindex].
// Subtype must be 1 for MAKI01A, or 2 for MAKI01B.
var flagbsize, ofsa, ofsb, pxofs, extflag : dword;
    tempimage : bitmaptype;
    flagmap : array[0..31999] of byte;
    outofs : dword;
    ivar, x, y : dword;
begin
 inc(lofs, 4); // computer model, skip
 inc(lofs, 20); // user name etc, skip

 flagbsize := byte((loader + lofs + 0)^) shl 8 or byte((loader + lofs + 1)^);
 //pxasize := byte((loader + lofs + 2)^) shl 8 or byte((loader + lofs + 3)^);
 //pxbsize := byte((loader + lofs + 4)^) shl 8 or byte((loader + lofs + 5)^);
 extflag := byte((loader + lofs + 6)^) shl 8 or byte((loader + lofs + 7)^);
 PNGlist[PNGindex].origofsxp := byte((loader + lofs + 8)^) shl 8 or byte((loader + lofs + 9)^);
 PNGlist[PNGindex].origofsyp := byte((loader + lofs + 10)^) shl 8 or byte((loader + lofs + 11)^);
 PNGlist[PNGindex].origsizexp := byte((loader + lofs + 12)^) shl 8 or byte((loader + lofs + 13)^);
 PNGlist[PNGindex].origsizeyp := byte((loader + lofs + 14)^) shl 8 or byte((loader + lofs + 15)^);
 inc(lofs, 16);

 if extflag <> 0 then PrintError('EXTFLAG <> 0!?');

 // Read GRB palette
 setlength(PNGlist[PNGindex].pal, 16);
 for ivar := 0 to 15 do with PNGlist[PNGindex].pal[ivar] do begin
  g := byte((loader + lofs)^) and $F0; inc(lofs);
  r := byte((loader + lofs)^) and $F0; inc(lofs);
  b := byte((loader + lofs)^) and $F0; inc(lofs);
  // only the top nibble is significant; the bottom nibble is 0 if the top
  // is 0, else it is $F
  if g <> 0 then g := g or $F;
  if r <> 0 then r := r or $F;
  if b <> 0 then b := b or $F;
 end;

 // First construct the flag A alpha mask (320x400).
 // We'll use the low nibbles of each byte to put 4 bits in each byte.
 // Each flag A bit sets 4x4 mask bits.
 ofsa := 1;
 ofsb := lofs + 1000;
 pxofs := ofsb + flagbsize;
 l_bitptr := 7;
 ivar := 0;
 for y := 99 downto 0 do begin
  for x := 79 downto 0 do begin
   if l_getbit then begin
    // flag A is true, set 4x4 block using the next flag B word
    flagmap[ofsa + 000] := byte((loader + ofsb)^) shr 4;
    flagmap[ofsa + 080] := byte((loader + ofsb)^) and $F;
    inc(ofsb);
    flagmap[ofsa + 160] := byte((loader + ofsb)^) shr 4;
    flagmap[ofsa + 240] := byte((loader + ofsb)^) and $F;
    inc(ofsb);
   end else begin
    // flag A is false, clear 4x4 block
    flagmap[ofsa] := 0;
    flagmap[ofsa + 80] := 0;
    flagmap[ofsa + 160] := 0;
    flagmap[ofsa + 240] := 0;
   end;
   if ivar = 1 then inc(ofsa, 3) else dec(ofsa);
   ivar := ivar xor 1;
  end;
  inc(ofsa, 240); // jump to the next 4x4 row's start
 end;

 // Create the image buffer
 getmem(tempimage.image, (PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp) shr 1);
 tempimage.sizex := 640; tempimage.sizey := 400;
 tempimage.memformat := 4; tempimage.bitdepth := 4;

 {$ifdef bonk}
 // If you want to render the alpha mask, use this...
 tempimage.sizex := 320; tempimage.sizey := 400;
 tempimage.bitdepth := 1;
 for x := 0 to 15999 do
  byte((tempimage.image + x)^) := flagmap[x * 2] or (flagmap[x * 2 + 1] shl 4);
 with PNGlist[PNGindex] do begin
  pal[0].r := 0; pal[0].g := 0; pal[0].b := 0;
  pal[1].r := $DD; pal[1].g := $44; pal[1].b := $66;
  origsizexp := 320; origsizeyp := 400;
 end;
 // Expand 1bpp indexed --> 8bpp indexed.
 mcg_ExpandBitdepth(@tempimage);
 PNGlist[PNGindex].bitmap := tempimage.image; tempimage.image := NIL;
 exit;
 {$endif}

 // Fill in the pixel colors...
 pxofs := ofsb;
 outofs := 0; ivar := 0; ofsb := 1;
 x := 0;
 for ofsa := 127999 downto 0 do begin

  // For each bit in the flag A buffer...
  if flagmap[ofsb] and 8 = 0 then
   // if the bit is 0, set two pixels to 0
   byte((tempimage.image + outofs)^) := 0
  else begin
   // if the bit is 1, set two pixels from the color buffer
   byte((tempimage.image + outofs)^) := byte((loader + pxofs)^);
   inc(pxofs);
  end;
  inc(outofs);

  // Move to the next flag A buffer bit.
  flagmap[ofsb] := flagmap[ofsb] shl 1;
  inc(ivar);
  if ivar = 4 then begin
   ivar := 0;
   if x = 1 then inc(ofsb, 3) else dec(ofsb);
   x := x xor 1;
  end;
 end;

 // Apply the vertical XOR filter.
 // (each row is 640 4-bit pixels, so 320 bytes)
 // MAKI01A xors from two rows above;
 // MAKI01B xors from four rows above.
 if subtype = 2 then ofsa := 320 * 4 else ofsa := 320 * 2;
 outofs := ofsa;
 for ofsb := (128000 - ofsa) div 4 - 1 downto 0 do begin
  dword((tempimage.image + outofs)^) := dword((tempimage.image + outofs)^) xor dword((tempimage.image + outofs - ofsa)^);
  inc(outofs, 4);
 end;

 // Expand 4bpp indexed --> 8bpp indexed.
 mcg_ExpandBitdepth(@tempimage);
 PNGlist[PNGindex].bitmap := tempimage.image; tempimage.image := NIL;
end;

procedure UnpackMAG2Graphic(PNGindex : word);
// Attempts to decompress a MAG v2 image from (loader + lofs)^ and puts the
// result in PNGlist[PNGindex].
// Also works on MAX images, which are MSX-flavored MAG v2.
var flagaofs, flagbofs, pxofs, leftofs, rightofs : dword;
    ofsa, ofsb, ofsc, hstart, outofs, bytewidth : dword;
    ivar, jvar : dword;
    tempimage : bitmaptype;
    actionbuffy : array of byte;
    modelcode, modelflags, screenmode : byte;

const delx : array[0..15] of byte = (0,1,2,4,0,1,0,1,2,0,1,2,0,1,2,0);
      dely : array[0..15] of byte = (0,0,0,0,1,1,2,2,2,4,4,4,8,8,8,16);

  procedure ConvertYJK(hasrgb : boolean);
  var readofs, writeofs, loopvar, chibiloopvar, readval : dword;
      jval, kval, yval, outval : longint;
  begin
   readofs := 0; writeofs := 0;
   for loopvar := (PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp) div 8 - 1 downto 0 do begin
    // turn our expanded 8bpp pixels back into a 4bpp dword...
    readval := 0;
    for chibiloopvar := 3 downto 0 do begin
     readval := readval shr 8;
     readval := readval or (dword(byte((PNGlist[PNGindex].bitmap + readofs)^) and $F) shl 28);
     inc(readofs);
     readval := readval or (dword(byte((PNGlist[PNGindex].bitmap + readofs)^) and $F) shl 24);
     inc(readofs);
    end;

    // grab K value from low 3 bits of pixels 0 and 1
    kval := (readval and 7) or (((readval shr 8) and 7) shl 3);
    if kval > 31 then dec(kval, 64); // 6-bit signed int
    // grab J value from low 3 bits of pixels 2 and 3
    jval := ((readval shr 16) and 7) or (((readval shr 24) and 7) shl 3);
    if jval > 31 then dec(jval, 64); // 6-bit signed int

    // process the pixels
    for chibiloopvar := 3 downto 0 do begin
     // get the Y value for this pixel
     yval := (readval shr 3) and $1F;
     readval := readval shr 8;

     if (hasrgb) and (yval and 1 <> 0) then begin
      // actually this pixel's a straight RGB...
      yval := yval shr 1;
      byte((tempimage.image + writeofs)^) := PNGlist[PNGindex].pal[yval].b;
      inc(writeofs);
      byte((tempimage.image + writeofs)^) := PNGlist[PNGindex].pal[yval].g;
      inc(writeofs);
      byte((tempimage.image + writeofs)^) := PNGlist[PNGindex].pal[yval].r;
      inc(writeofs);
     end
     else begin
      // BLUE = 1.25 * Y - J / 2 - K / 4
      //outval := round(1.25 * yval - jval / 2 - kval / 4);
      outval := 5 * yval div 4 - jval div 2 - kval div 4;
      if outval < 0 then outval := 0 else if outval > 31 then outval := 31;
      byte((tempimage.image + writeofs)^) := (outval * 255 + 15) div 31;
      inc(writeofs);
      // GREEN = Y + K
      outval := yval + kval;
      if outval < 0 then outval := 0 else if outval > 31 then outval := 31;
      byte((tempimage.image + writeofs)^) := (outval * 255 + 15) div 31;
      inc(writeofs);
      // RED = Y + J
      outval := yval + jval;
      if outval < 0 then outval := 0 else if outval > 31 then outval := 31;
      byte((tempimage.image + writeofs)^) := (outval * 255 + 15) div 31;
      inc(writeofs);
     end;
    end;
   end;
  end;

  procedure GrabWord(action : byte);
  // Outputs a word into the output buffer, either from the color stream or
  // copying from earlier in the output buffer.
  var wvar : word;
  begin
   if action = 0 then begin // new color word
    if ofsc + 1 >= loadersize then begin
     PrintError('Tried to read color array out of bounds: outofs=' + strdec(outofs) + '/' + strdec(bytewidth * PNGlist[PNGindex].origsizeyp));
     ofsc := pxofs;
    end;
    wvar := word((loader + ofsc)^); inc(ofsc, 2);
   end else begin // copy word from before
    wvar := word((tempimage.image + outofs - (dely[action] * bytewidth) - delx[action] shl 1)^);
   end;
   // output the word
   word((tempimage.image + outofs)^) := wvar; inc(outofs, 2);
  end;

begin
 // Computer model, username etc, $1A, skip.
 while (lofs + 32 < loadersize) and (byte((loader + lofs)^) <> $1A) do inc(lofs);
 // Find the first 0 byte after $1A, where the header starts.
 while (lofs + 32 < loadersize) and (byte((loader + lofs)^) <> 0) do inc(lofs);
 if byte((loader + lofs)^) <> 0 then begin
  PrintError('Failed to find start of header 1A-00!');
  exit;
 end;

 // Mark the beginning of the header for laters.
 hstart := lofs; inc(lofs);

 // Read the header.
 modelcode := byte((loader + lofs)^); inc(lofs);
 modelflags := byte((loader + lofs)^); inc(lofs);
 screenmode := byte((loader + lofs)^); inc(lofs);
 leftofs := word((loader + lofs)^); inc(lofs, 2);
 PNGlist[PNGindex].origofsxp := leftofs;
 PNGlist[PNGindex].origofsyp := word((loader + lofs)^); inc(lofs, 2);
 rightofs := word((loader + lofs)^); inc(lofs, 2);
 PNGlist[PNGindex].origsizeyp := word((loader + lofs)^); inc(lofs, 2);

 ofsa := dword((loader + lofs)^) + hstart; inc(lofs, 4); // flag A stream
 ofsb := dword((loader + lofs)^) + hstart; inc(lofs, 8); // flag B stream
 ofsc := dword((loader + lofs)^) + hstart; inc(lofs, 8); // color stream
 flagaofs := ofsa;
 flagbofs := ofsb;
 pxofs := ofsc;
 if (ofsa >= loadersize) or (ofsb >= loadersize) or (ofsc >= loadersize)
 then begin
  PrintError('Section offset out of bounds!'); exit;
 end;

 // Read GRB palette, usually 16, sometimes 256 entries.
 if screenmode and $80 = 0 then setlength(PNGlist[PNGindex].pal, 16) else setlength(PNGlist[PNGindex].pal, 256);
 ivar := 0;
 while lofs < flagaofs do begin
  with PNGlist[PNGindex].pal[ivar] do begin
   g := byte((loader + lofs)^) and $F0; inc(lofs);
   r := byte((loader + lofs)^) and $F0; inc(lofs);
   b := byte((loader + lofs)^) and $F0; inc(lofs);
   // only the top nibble is significant; the bottom nibble is 0 if the top
   // is 0, else it is $F
   if g <> 0 then g := g or $F;
   if r <> 0 then r := r or $F;
   if b <> 0 then b := b or $F;
  end;
  inc(ivar);
 end;

 // While decompressing, image width must be a multiple of 8 pixels.
 // (we can crop it later)
 if (screenmode and $80 = 0) then begin
  // 16-color mode...
  // calculate the image size from edge to edge
  // and both horizontal edges must be pushed out to a multiple of 8
  PNGlist[PNGindex].origsizexp := (rightofs + 8) and $FFF8 - (leftofs and $FFF8);
  tempimage.bitdepth := 4;
  setlength(actionbuffy, PNGlist[PNGindex].origsizexp div 8);
 end else begin
  // 256-color mode has some differences...
  // calculate the image size from edge to edge
  // and both horizontal edges must be pushed out to a multiple of 4
  PNGlist[PNGindex].origsizexp := (rightofs + 4) and $FFFC - (leftofs and $FFFC);
  tempimage.bitdepth := 8;
  setlength(actionbuffy, PNGlist[PNGindex].origsizexp div 4);
 end;
 PNGlist[PNGindex].origsizeyp := PNGlist[PNGindex].origsizeyp - PNGlist[PNGindex].origofsyp + 1;
 bytewidth := (PNGlist[PNGindex].origsizexp * tempimage.bitdepth) shr 3;

 // Unpack image into this, as a 4bpp indexed thing.
 getmem(tempimage.image, (bytewidth * dword(PNGlist[PNGindex].origsizeyp + 1)));
 tempimage.sizex := PNGlist[PNGindex].origsizexp; tempimage.sizey := PNGlist[PNGindex].origsizeyp;
 tempimage.memformat := 4;

 fillbyte(actionbuffy[0], length(actionbuffy), 0);
 outofs := 0; l_bitptr := 7; lofs := flagaofs;
 ofsa := 0; jvar := 0;

 // For each pixel in the image...
 ivar := (PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp * tempimage.bitdepth) shr 3;
 while outofs < ivar do begin

  if jvar = 0 then begin
   // a new top action nibble is needed, fetch new flag A bit.
   if lofs >= flagbofs then begin
    PrintError('Tried to read flag A out of bounds'); exit;
   end;
   // if the new flag A bit is TRUE, xor previous row's action byte with
   // a new flag B value.
   if l_getbit then begin
    if ofsb >= pxofs then begin
     PrintError('Tried to read flag B out of bounds'); exit;
    end;
    actionbuffy[ofsa] := actionbuffy[ofsa] xor byte((loader + ofsb)^);
    inc(ofsb);
   end;
   // act on the top action nibble.
   GrabWord(actionbuffy[ofsa] shr 4);
  end
  else begin
   // act on the bottom action nibble.
   GrabWord(actionbuffy[ofsa] and $F);
   // advance the action buffer pointer.
   inc(ofsa);
   // loop back to start of action buffer if needed.
   if ofsa >= dword(length(actionbuffy)) then ofsa := 0;
  end;

  jvar := jvar xor 1;
 end;

 // Expand 4bpp indexed --> 8bpp indexed.
 if tempimage.bitdepth < 8 then mcg_ExpandBitdepth(@tempimage);

 // Crop the sides if they were padded earlier.
 if (PNGlist[PNGindex].origsizeyp > 1) then begin
  ofsa := leftofs and 7; // this amount must be cropped from left
  ofsb := 0;
  ofsb := 7 - rightofs and 7; // this must be cropped from right
  // this is the result width.
  ofsc := PNGlist[PNGindex].origsizexp - ofsa - ofsb;
  // Make a buffer for the cropped image.
  getmem(PNGlist[PNGindex].bitmap, ofsc * PNGlist[PNGindex].origsizeyp);
  // Copy the image to the new buffer, less cropped sides.
  outofs := 0; jvar := ofsa;
  for ivar := PNGlist[PNGindex].origsizeyp - 1 downto 0 do begin
   move((tempimage.image + jvar)^, (PNGlist[PNGindex].bitmap + outofs)^, ofsc);
   inc(outofs, ofsc);
   inc(jvar, PNGlist[PNGindex].origsizexp);
  end;
  freemem(tempimage.image);
  // Note the image's cropped width.
  PNGlist[PNGindex].origsizexp := ofsc;
 end
 else begin
  PNGlist[PNGindex].bitmap := tempimage.image;
 end;
 tempimage.image := NIL;

 // If this is an MSX+ screen, we may need to decode the YJK colors.
 // Pixels are stored four in a row, all sharing a J and K value, and having
 // individual Y values.
 if (modelcode = 3) and (modelflags in [$24,$34,$44]) then begin
  getmem(tempimage.image, (PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp) * 3);
  ConvertYJK(modelflags <> $44);

  freemem(PNGlist[PNGindex].bitmap);
  PNGlist[PNGindex].bitmap := tempimage.image;
  tempimage.image := NIL;

  // it's no longer an indexed-color image, release the palette...
  setlength(PNGlist[PNGindex].pal, 0);
  PNGlist[PNGindex].origsizexp := 256;
 end else

 // Apply double-height pixel ratio, if necessary.
 if (screenmode and 1 <> 0) then begin
  getmem(tempimage.image, PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp * 2);
  outofs := 0; jvar := 0;
  for ivar := PNGlist[PNGindex].origsizeyp - 1 downto 0 do begin
   move((PNGlist[PNGindex].bitmap + jvar)^, (tempimage.image + outofs)^, PNGlist[PNGindex].origsizexp);
   inc(outofs, PNGlist[PNGindex].origsizexp);
   move((PNGlist[PNGindex].bitmap + jvar)^, (tempimage.image + outofs)^, PNGlist[PNGindex].origsizexp);
   inc(outofs, PNGlist[PNGindex].origsizexp);
   inc(jvar, PNGlist[PNGindex].origsizexp);
  end;

  freemem(PNGlist[PNGindex].bitmap);
  PNGlist[PNGindex].bitmap := tempimage.image;
  tempimage.image := NIL;

  PNGlist[PNGindex].origsizeyp := PNGlist[PNGindex].origsizeyp * 2;
 end;
end;

function Decomp_Makichan(const srcfile, outputfile : UTF8string) : UTF8string;
// Reads the indicated Maki-chan graphics file, and saves it in outputfile as
// a normal PNG.
// Returns an empty string if successful, otherwise returns an error message.
var imunamu : UTF8string;
    ivar, jvar : dword;
    PNGindex : dword;
    tempbmp : bitmaptype;
begin
 // Load the input file into loader^.
 Decomp_Makichan := LoadFile(srcfile);
 if Decomp_Makichan <> '' then exit;

 tempbmp.image := NIL;

 // Find this graphic name in PNGlist[], or create if doesn't exist yet.
 imunamu := ExtractFileName(srcfile);
 imunamu := upcase(copy(imunamu, 1, length(imunamu) - length(ExtractFileExt(imunamu))));
 PNGindex := seekpng(imunamu, TRUE);

 // Check the file for a "MAKI" signature.
 if dword(loader^) <> $494B414D then begin
  Decomp_Makichan := 'no MAKI signature';
  exit;
 end;

 // Call the right decompressor.
 ivar := dword((loader + 4)^); // 01A, 01B, or 02
 lofs := 8;
 case ivar of
  $20413130: UnpackMakiGraphic(PNGindex, 1); // 01A
  $20423130: UnpackMakiGraphic(PNGindex, 2); // 01B
  $20203230: UnpackMAG2Graphic(PNGindex); // 02
  else begin
   Decomp_Makichan := 'unknown MAKI subtype $' + strhex(ivar);
   exit;
  end;
 end;
 if PNGlist[PNGindex].bitmap = NIL then begin
  Decomp_Makichan := 'failed to load image';
  exit;
 end;

 // Put the uncompressed image into a bitmaptype for PNG conversion...
 tempbmp.image := PNGlist[PNGindex].bitmap;
 PNGlist[PNGindex].bitmap := NIL;
 tempbmp.sizex := PNGlist[PNGindex].origsizexp;
 tempbmp.sizey := PNGlist[PNGindex].origsizeyp;
 tempbmp.bitdepth := 8;
 tempbmp.memformat := 4; // indexed
 setlength(tempbmp.palette, length(PNGlist[PNGindex].pal));

 if length(PNGlist[PNGindex].pal) <> 0 then begin
  for ivar := high(PNGlist[PNGindex].pal) downto 0 do begin
   tempbmp.palette[ivar].a := $FF;
   tempbmp.palette[ivar].b := PNGlist[PNGindex].pal[ivar].b;
   tempbmp.palette[ivar].g := PNGlist[PNGindex].pal[ivar].g;
   tempbmp.palette[ivar].r := PNGlist[PNGindex].pal[ivar].r;
  end;
 end
 else begin
  // If there was no palette, assume our pic's already 24-bit RGB.
  tempbmp.memformat := 0;
 end;

 // Convert bitmaptype(pic^) into a compressed PNG, saved in bitmap^.
 // The PNG byte size goes into jvar.
 ivar := mcg_MemoryToPng(@tempbmp, @PNGlist[PNGindex].bitmap, @jvar);
 mcg_ForgetImage(@tempbmp);

 if ivar <> 0 then begin
  Decomp_Makichan := mcg_errortxt;
  if PNGlist[PNGindex].bitmap <> NIL then begin
   freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
  end;
  exit;
 end;

 Decomp_Makichan := SaveFile(outputfile, PNGlist[PNGindex].bitmap, jvar);
 freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
end;
