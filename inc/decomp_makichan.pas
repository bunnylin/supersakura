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

procedure UnpackMakiGraphic(const loader : TFileLoader; PNGindex : word; subtype : byte);
// Attempts to decompress a Maki v1 image from loader, and puts the result
// in PNGlist[PNGindex].
// Subtype must be 1 for MAKI01A, or 2 for MAKI01B.
var tempimage : bitmaptype;
    flagAmask : array[0..31999] of byte;
    outp, colorp : pointer;
    ofsa, ofsb, extflag : dword;
    x, y : dword;
begin
 inc(loader.readp, 4); // computer model, skip
 inc(loader.readp, 20); // user name etc, skip

 //flagbsize := (loader.ReadByte shl 8) or loader.ReadByte;
 //pxasize := (loader.ReadByte shl 8) or loader.ReadByte;
 //pxbsize := (loader.ReadByte shl 8) or loader.ReadByte;
 inc(loader.readp, 6);
 extflag := (loader.ReadByte shl 8) or loader.ReadByte;
 PNGlist[PNGindex].origofsxp := (loader.ReadByte shl 8) or loader.ReadByte;
 PNGlist[PNGindex].origofsyp := (loader.ReadByte shl 8) or loader.ReadByte;
 PNGlist[PNGindex].origsizexp := (loader.ReadByte shl 8) or loader.ReadByte;
 PNGlist[PNGindex].origsizeyp := (loader.ReadByte shl 8) or loader.ReadByte;

 // Validate...
 if extflag <> 0 then PrintError('EXTFLAG <> 0!?');
 if PNGlist[PNGindex].origofsxp <> 0 then PrintError('OfsX <> 0!?');
 if PNGlist[PNGindex].origofsyp <> 0 then PrintError('OfsY <> 0!?');
 if PNGlist[PNGindex].origsizexp <> 640 then PrintError('SizeX <> 640!?');
 if PNGlist[PNGindex].origsizeyp <> 400 then PrintError('SizeY <> 400!?');

 // Read GRB palette.
 setlength(PNGlist[PNGindex].pal, 16);
 for x := 0 to 15 do with PNGlist[PNGindex].pal[x] do begin
  g := loader.ReadByte and $F0;
  r := loader.ReadByte and $F0;
  b := loader.ReadByte and $F0;
  // only the top nibble is significant; the bottom nibble is 0 if the top
  // is 0, else it is $F
  if g <> 0 then g := g or $F;
  if r <> 0 then r := r or $F;
  if b <> 0 then b := b or $F;
 end;

 // First construct the flag A alpha mask (320x400).
 // We'll use the low nibbles of each byte to put 4 bits in each byte.
 // Each flag A bit sets 4x4 mask bits.
 ofsa := 0;
 ofsb := loader.ofs + 1000;
 loader.bitindex := 7;

 for y := 99 downto 0 do begin
  for x := 79 downto 0 do begin
   if loader.ReadBit then begin
    // flag A is true, set 4x4 block using the next flag B word
    flagAmask[ofsa + 000] := loader.ReadByteFrom(ofsb) shr 4;
    flagAmask[ofsa + 080] := loader.ReadByteFrom(ofsb) and $F;
    inc(ofsb);
    flagAmask[ofsa + 160] := loader.ReadByteFrom(ofsb) shr 4;
    flagAmask[ofsa + 240] := loader.ReadByteFrom(ofsb) and $F;
    inc(ofsb);
   end else begin
    // flag A is false, clear 4x4 block
    flagAmask[ofsa + 000] := 0;
    flagAmask[ofsa + 080] := 0;
    flagAmask[ofsa + 160] := 0;
    flagAmask[ofsa + 240] := 0;
   end;
   inc(ofsa);
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
  byte((tempimage.image + x)^) := (flagAmask[x * 2] shl 4) or flagAmask[x * 2 + 1];
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
 colorp := loader.PtrAt(ofsb);
 outp := tempimage.image;

 for ofsa := 0 to 31999 do begin

  // For each bit in the flag A buffer...
  // if the bit is 0, output a 0 byte;
  // if the bit is 1, output a byte from the pixel color stream.
  if flagAmask[ofsa] and 8 = 0 then
   byte(outp^) := 0
  else begin
   byte(outp^) := byte(colorp^); inc(colorp);
  end;
  inc(outp);

  if flagAmask[ofsa] and 4 = 0 then
   byte(outp^) := 0
  else begin
   byte(outp^) := byte(colorp^); inc(colorp);
  end;
  inc(outp);

  if flagAmask[ofsa] and 2 = 0 then
   byte(outp^) := 0
  else begin
   byte(outp^) := byte(colorp^); inc(colorp);
  end;
  inc(outp);

  if flagAmask[ofsa] and 1 = 0 then
   byte(outp^) := 0
  else begin
   byte(outp^) := byte(colorp^); inc(colorp);
  end;
  inc(outp);

 end;

 // Apply the vertical XOR filter.
 // (each row is 640 4-bit pixels, so 320 bytes)
 // MAKI01A xors from two rows above;
 // MAKI01B xors from four rows above.
 if subtype = 2 then ofsa := 320 * 4 else ofsa := 320 * 2;
 outp := tempimage.image + ofsa;

 for ofsb := (128000 - ofsa) div 4 - 1 downto 0 do begin
  dword(outp^) := dword(outp^) xor dword((outp - ofsa)^);
  inc(outp, 4);
 end;

 // Expand 4bpp indexed --> 8bpp indexed.
 mcg_ExpandBitdepth(@tempimage);
 PNGlist[PNGindex].bitmap := tempimage.image; tempimage.image := NIL;
end;

procedure UnpackMAG2Graphic(const loader : TFileLoader; PNGindex : word);
// Attempts to decompress a MAG v2 image from loader, and puts the result in
// PNGlist[PNGindex].
// Also works on MAX images, which are MSX-flavored MAG v2.
var tempimage : bitmaptype;
    actionbuffy : array of byte;
    header : record
      modelcode, modelflags, screenmode : byte;
      left, top, right, bottom : dword;
      flagaofs, flagbofs, colorofs : dword;
    end;
    paddedleft, paddedright : dword;
    cropleft, cropright : dword;
    i, bytewidth : dword;

const delx : array[0..15] of byte = (0,1,2,4,0,1,0,1,2,0,1,2,0,1,2,0);
      dely : array[0..15] of byte = (0,0,0,0,1,1,2,2,2,4,4,4,8,8,8,16);

  // ----------------------------------------------------------------
  procedure DoDecompress();
  // The is the straightforward main MAG v2 decompressing loop.
  var outp, endp : pointer;
      actionindex, flagbindex, colorindex : dword;

    procedure GrabWord(action : byte);
    // Decompression helper, saves a word of output.
    var wvar : word;
    begin
     if action = 0 then begin
      // Fetch a new word from the color index stream.
      if colorindex + 1 >= loader.size then begin
       PrintError('Tried to read color array out of bounds: outofs=' + strdec(outp - tempimage.image) + '/' + strdec(bytewidth * tempimage.sizey) + ' colorindex=' + strdec(colorindex));
       wvar := 0;
      end
      else begin
       wvar := loader.ReadWordFrom(colorindex);
       inc(colorindex, 2);
      end;
     end
     else begin
      // Copy a previously output word.
      wvar := word((outp - (dely[action] * bytewidth) - delx[action] * 2)^);
     end;
     // Output the word.
     word(outp^) := wvar;
     inc(outp, 2);
    end;

  begin
   loader.ofs := header.flagaofs;
   loader.bitindex := 7;
   actionindex := 0;
   flagbindex := header.flagbofs;
   colorindex := header.colorofs;
   outp := tempimage.image;
   endp := outp + bytewidth * tempimage.sizey - 1;

   // Decompress until the output buffer is full...
   repeat

    // Read the next flag A bit.
    if loader.ofs >= header.flagbofs then begin
     PrintError('Tried to read flag A out of bounds'); exit;
    end;
    if loader.ReadBit then begin
     // If the flag A bit is set, read the next flag B byte, and xor the
     // current action byte with it.
     if flagbindex >= header.colorofs then begin
      PrintError('Tried to read flag B out of bounds'); exit;
     end;
     actionbuffy[actionindex] :=
       actionbuffy[actionindex] xor loader.ReadByteFrom(flagbindex);
     inc(flagbindex);
    end;

    // Act on the top action nibble.
    GrabWord(actionbuffy[actionindex] shr 4);
    if outp >= endp then break;

    // Act on the bottom action nibble.
    GrabWord(actionbuffy[actionindex] and $F);
    if outp >= endp then break;

    // Advance the action buffer pointer, looping around the action buffer.
    actionindex := (actionindex + 1) mod dword(length(actionbuffy));

   until FALSE;
  end;

  // ----------------------------------------------------------------
  procedure CropTempImage();
  // Crops the left and right edges back to the exact values given in the
  // image header. The cropping is done in-place.
  // At this point, tempimage must be either 8bpp indexed, or 24-bit RGB.
  var srcp, destp : pointer;
      sourcewidth, targetwidth, y : dword;
  begin
   // Calculate the widths.
   sourcewidth := tempimage.sizex;
   targetwidth := tempimage.sizex - cropleft - cropright;
   // Does the image need cropping?
   if (tempimage.sizey <> 0) and (sourcewidth <> targetwidth)
   then begin
    // Yes, the image was padded and needs cropping.
    dec(tempimage.sizex, cropleft + cropright);
    // If the image is 24-bit RGB, adjust the widths.
    if tempimage.memformat = 0 then begin
     sourcewidth := sourcewidth * 3;
     targetwidth := targetwidth * 3;
     cropleft := cropleft * 3;
    end;

    srcp := tempimage.image + cropleft;
    destp := tempimage.image;
    for y := tempimage.sizey - 1 downto 0 do begin
     memcopy(srcp, destp, targetwidth);
     inc(srcp, sourcewidth);
     inc(destp, targetwidth);
    end;
   end;
  end;

  // ----------------------------------------------------------------
  procedure ConvertYJK(hasrgb : boolean);
  // Converts tempimage^ from YJK-encoding to 24-bit RGB.
  var workimage : pointer;
      readp, writep : pointer;
      loopvar, chibiloopvar, readval : dword;
      Y, J, K, outval : longint;
  begin
   getmem(workimage, tempimage.sizex * tempimage.sizey * 3);

   readp := tempimage.image;
   writep := workimage;

   // For all bytes in the image...
   for loopvar := (tempimage.sizex * tempimage.sizey) div 4 - 1 downto 0 do begin
    readval := dword(readp^); inc(readp, 4);

    // Grab J from low 3 bits of pixels 2 and 3.
    J := ((readval shr 16) and 7) or (((readval shr 24) and 7) shl 3);
    // Grab K from low 3 bits of pixels 0 and 1.
    K := (readval and 7) or (((readval shr 8) and 7) shl 3);

    // These are 6-bit signed ints, so apply the sign.
    if J > 31 then dec(J, 64);
    if K > 31 then dec(K, 64);

    // For all 4 pixels in this quartet...
    for chibiloopvar := 3 downto 0 do begin
     // Grab Y for this pixel.
     Y := (readval shr 3) and $1F;
     readval := readval shr 8;

     if (hasrgb) and (Y and 1 <> 0) then begin
      // Straight RGB!
      Y := Y shr 1;
      byte(writep^) := tempimage.palette[Y].b; inc(writep);
      byte(writep^) := tempimage.palette[Y].g; inc(writep);
      byte(writep^) := tempimage.palette[Y].r; inc(writep);
     end
     else begin
      // BLUE = 1.25 * Y - J / 2 - K / 4
      //outval := round(1.25 * yval - jval / 2 - kval / 4);
      outval := 5 * Y div 4 - J div 2 - K div 4;
      if outval < 0 then outval := 0 else if outval > 31 then outval := 31;
      byte(writep^) := (outval * 255 + 15) div 31;
      inc(writep);
      // GREEN = Y + K
      outval := Y + K;
      if outval < 0 then outval := 0 else if outval > 31 then outval := 31;
      byte(writep^) := (outval * 255 + 15) div 31;
      inc(writep);
      // RED = Y + J
      outval := Y + J;
      if outval < 0 then outval := 0 else if outval > 31 then outval := 31;
      byte(writep^) := (outval * 255 + 15) div 31;
      inc(writep);
     end;
    end;
   end;

   freemem(tempimage.image); tempimage.image := workimage; workimage := NIL;

   // It's no longer an indexed-color image, release the palette.
   setlength(tempimage.palette, 0);
   tempimage.memformat := 0;
   tempimage.bitdepth := 8;

   // If the image used to be 4bpp, the conversion halved its pixel width.
   if (header.screenmode and $80 = 0) then
    tempimage.sizex := tempimage.sizex shr 1;
  end;

  // ----------------------------------------------------------------
  procedure ApplyDoubleHeight();
  // Replaces tempimage with a double-height version of itself.
  var workimage, srcp, destp : pointer;
      imagebytewidth, y : dword;
  begin
   imagebytewidth := tempimage.sizex;
   if tempimage.memformat = 0 then imagebytewidth := tempimage.sizex * 3;
   getmem(workimage, imagebytewidth * tempimage.sizey * 2);

   srcp := tempimage.image;
   destp := workimage;

   for y := tempimage.sizey - 1 downto 0 do begin
    move(srcp^, destp^, imagebytewidth);
    inc(destp, imagebytewidth);
    move(srcp^, destp^, imagebytewidth);
    inc(srcp, imagebytewidth);
    inc(destp, imagebytewidth);
   end;

   freemem(tempimage.image);
   tempimage.image := workimage;
   workimage := NIL;

   tempimage.sizey := tempimage.sizey * 2;
  end;
  // ----------------------------------------------------------------

begin
 // Computer model, username etc, $1A, skip.
 while (loader.readp + 32 < loader.endp) and (byte(loader.readp^) <> $1A) do inc(loader.readp);
 // Find the first 0 byte after $1A, where the header starts.
 while (loader.readp + 32 < loader.endp) and (byte(loader.readp^) <> 0) do inc(loader.readp);
 if byte(loader.readp^) <> 0 then
  raise Exception.Create('Failed to find start of header 1A-00!');

 // Remember the beginning of the header for use below.
 i := loader.ofs; inc(loader.readp);

 // Read the header.
 header.modelcode := loader.ReadByte;
 header.modelflags := loader.ReadByte;
 header.screenmode := loader.ReadByte;

 header.left := loader.ReadWord;
 header.top := loader.ReadWord;
 header.right := loader.ReadWord;
 header.bottom := loader.ReadWord;

 header.flagaofs := i + loader.ReadDword;
 header.flagbofs := i + loader.ReadDword;
 inc(loader.readp, 4); // skip flag B stream size, unnecessary
 header.colorofs := i + loader.ReadDword;
 inc(loader.readp, 4); // skip color index stream size, unnecessary

 if (header.flagaofs >= loader.size)
 or (header.flagbofs >= loader.size)
 or (header.colorofs >= loader.size) then
  raise Exception.Create('Section offset out of bounds!');

 // Read GRB palette, usually 16, sometimes up to 256 entries.
 // Let's read from current position up to the start of the flag A stream.
 setlength(tempimage.palette, (header.flagaofs - loader.ofs) div 3);
 if length(tempimage.palette) <> 0 then
  for i := 0 to length(tempimage.palette) - 1 do
   with tempimage.palette[i] do begin
    g := loader.ReadByte and $F0;
    r := loader.ReadByte and $F0;
    b := loader.ReadByte and $F0;
    // only the top nibble is significant; the bottom nibble is 0 if the top
    // is 0, else it is $F
    if g <> 0 then g := g or $F;
    if r <> 0 then r := r or $F;
    if b <> 0 then b := b or $F;
   end;

 if (header.screenmode and $80 = 0)
 then tempimage.bitdepth := 4
 else tempimage.bitdepth := 8;

 // Calculate the byte location of the left and right edges.
 // (at 8bpp, 1 byte = 1 pixel; at 4bpp, 1 byte = 2 pixels)
 paddedleft := (header.left div byte(8 div tempimage.bitdepth));
 paddedright := (header.right div byte(8 div tempimage.bitdepth));

 // Pad the edges to a multiple of 4 bytes.
 paddedleft := paddedleft and $FFFC;
 paddedright := (paddedright + 3 + 1) and $FFFC;
 bytewidth := paddedright - paddedleft;

 // Set up tempimage as an indexed-color image, although we'll treat it as
 // a byte array at first, to simplify decompression.
 tempimage.memformat := 4;
 tempimage.sizex := bytewidth * byte(8 div tempimage.bitdepth);
 tempimage.sizey := header.bottom - header.top + 1;
 getmem(tempimage.image, bytewidth * tempimage.sizey);

 // Calculate how many pixels of padding are being added.
 // This will be used later to delete the padding.
 cropleft := header.left - paddedleft * 8 div tempimage.bitdepth;
 cropright := tempimage.sizex - (header.right - header.left + 1) - cropleft;

 // Set up actionbuffy for one row of flag B bytes.
 setlength(actionbuffy, bytewidth div 4);
 fillbyte(actionbuffy[0], length(actionbuffy), 0);

 // Unpack the image into the output buffy.
 DoDecompress;

 // If this is an MSX2+ screen, we may need to decode the YJK colors.
 // This sets tempimage to be 24-bit RGB, no longer indexed.
 if (header.modelcode = 3) and (header.modelflags in [$24, $34, $44]) then
  ConvertYJK(header.modelflags <> $44);

 // If still using a 4bpp indexed palette, expand to 8bpp.
 if tempimage.bitdepth < 8 then mcg_ExpandBitdepth(@tempimage);

 // Remove the left/right padding, if any.
 CropTempImage;

 // Apply double-height pixel ratio, if necessary.
 if (header.modelcode <> 3) and (header.screenmode and $81 = 1)
 or (header.modelcode = 3) and (header.modelflags = $04)
 then ApplyDoubleHeight;

 // Store the result.
 PNGlist[PNGindex].bitmap := tempimage.image; tempimage.image := NIL;
 PNGlist[PNGindex].origsizexp := tempimage.sizex;
 PNGlist[PNGindex].origsizeyp := tempimage.sizey;
 i := length(tempimage.palette);
 setlength(PNGlist[PNGindex].pal, i);
 if i <> 0 then
  move(tempimage.palette[0], PNGlist[PNGindex].pal[0], i * sizeof(tempimage.palette[0]));
end;

procedure Decomp_Makichan(const loader : TFileLoader; const outputfile : UTF8string);
// Reads the indicated Maki-chan graphics file, and saves it in outputfile as
// a normal PNG.
// Throws an exception in case of errors.
var imunamu : UTF8string;
    i, j : dword;
    PNGindex : dword;
    tempbmp : bitmaptype;
begin
 tempbmp.image := NIL;

 // Find this graphic name in PNGlist[], or create if doesn't exist yet.
 imunamu := ExtractFileName(loader.filename);
 imunamu := upcase(copy(imunamu, 1, length(imunamu) - length(ExtractFileExt(imunamu))));
 PNGindex := seekpng(imunamu, TRUE);

 // Check the file for a "MAKI" signature.
 if loader.ReadDword <> $494B414D then raise Exception.Create('no MAKI signature');

 // Call the right decompressor.
 i := loader.ReadDword; // 01A, 01B, or 02
 case i of
  $20413130: UnpackMakiGraphic(loader, PNGindex, 1); // 01A
  $20423130: UnpackMakiGraphic(loader, PNGindex, 2); // 01B
  $20203230: UnpackMAG2Graphic(loader, PNGindex); // 02
  else raise Exception.Create('unknown MAKI subtype $' + strhex(i));
 end;
 if PNGlist[PNGindex].bitmap = NIL then
  raise Exception.Create('failed to load image');

 // Put the uncompressed image into a bitmaptype for PNG conversion...
 tempbmp.image := PNGlist[PNGindex].bitmap;
 PNGlist[PNGindex].bitmap := NIL;
 tempbmp.sizex := PNGlist[PNGindex].origsizexp;
 tempbmp.sizey := PNGlist[PNGindex].origsizeyp;
 tempbmp.bitdepth := 8;
 tempbmp.memformat := 4; // indexed
 setlength(tempbmp.palette, length(PNGlist[PNGindex].pal));

 if length(PNGlist[PNGindex].pal) <> 0 then begin
  for i := high(PNGlist[PNGindex].pal) downto 0 do begin
   tempbmp.palette[i].a := $FF;
   tempbmp.palette[i].b := PNGlist[PNGindex].pal[i].b;
   tempbmp.palette[i].g := PNGlist[PNGindex].pal[i].g;
   tempbmp.palette[i].r := PNGlist[PNGindex].pal[i].r;
  end;
 end
 else begin
  // If there was no palette, assume our pic's already 24-bit RGB.
  tempbmp.memformat := 0;
 end;

 // Convert bitmaptype(pic^) into a compressed PNG, saved in bitmap^.
 // The PNG byte size goes into j.
 i := mcg_MemoryToPng(@tempbmp, @PNGlist[PNGindex].bitmap, @j);
 mcg_ForgetImage(@tempbmp);

 if i <> 0 then begin
  if PNGlist[PNGindex].bitmap <> NIL then begin
   freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
  end;
  raise Exception.Create(mcg_errortxt);
 end;

 SaveFile(outputfile, PNGlist[PNGindex].bitmap, j);
 freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
end;
