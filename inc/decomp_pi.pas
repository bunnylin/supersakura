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

procedure ConvertJastAnimData(animp : pointer; PNGindex : dword);
// Takes a pointer to a single unit of JAST/Tiare animation data, processes
// it into useful data in PNGlist[]. This does not release animp.
var i, j : dword;
begin
 {$ifdef enable_hacks}
 case game of
  gid_SAKURA, gid_SAKURA98: begin
   // Hack: fix a misspelled animation name
   //if uzi = 'CT14A1' then uzi := 'CT14DA1';
   // Hack: add a missing sequence length
   if PNGlist[PNGindex].namu = 'CT14IA1' then word(animp^) := 7;
   // Hack: Make Seia blink a tiny bit more slowly
   // (adds extra delay to between sequence[0] and [1])
   if copy(PNGlist[PNGindex].namu, 1, 4) = 'CT07' then inc(word((animp + 116)^), 32);
  end;
 end;
 {$endif enable_hacks}

 // Get the sequence length.
 PNGlist[PNGindex].seqlen := word(animp^); inc(animp, 2);
 inc(animp, 36); // skip the name...
 inc(animp, 4); // skip image width and height, redundant

 // Sort the other data into PNGlist[PNGindex].
 PNGlist[PNGindex].origofsxp := word(animp^) * 8; inc(animp, 2);
 PNGlist[PNGindex].origofsyp := word(animp^);     inc(animp, 2);
 PNGlist[PNGindex].framewidth := word(animp^) * 8; inc(animp, 2);
 PNGlist[PNGindex].frameheight := word(animp^);    inc(animp, 2);
 setlength(PNGlist[PNGindex].sequence, 32);
 // Sequence storage format:
 // [n] [xx][frame number 13 bits] [xx][delay 14 bits]
 for i := 0 to 31 do begin
  PNGlist[PNGindex].sequence[i] := byte(animp^) shl 16;
  inc(animp, 2);
 end;
 // Convert to ~millisecs, shift delays to intuitively correct frames.
 for i := 1 to 32 do begin
  j := word((animp + i * 2)^) * 11;
  if j = 0 then j := 16;
  PNGlist[PNGindex].sequence[i - 1] := PNGlist[PNGindex].sequence[i - 1] + j;
 end;
 i := PNGlist[PNGindex].seqlen - 1;
 j := dword(word(animp^) * 11);
 PNGlist[PNGindex].sequence[i] := (PNGlist[PNGindex].sequence[i] and $FFFF0000) + j;
 // If sequence length = 1, enforce a stopped animation.
 if PNGlist[PNGindex].seqlen = 1 then PNGlist[PNGindex].sequence[0] := PNGlist[PNGindex].sequence[0] or $FFFF;

 // Adjust the animation offset depending on the game. 3sis and Runaway,
 // for example, have offsets that assume the interface's frame is present.
 case game of
  gid_3SIS, gid_3SIS98, gid_RUNAWAY, gid_RUNAWAY98, gid_TRANSFER98:
  if PNGlist[PNGindex].namu <> 'OP_013A0' then begin // no viewframe in title
   dec(PNGlist[PNGindex].origofsxp, 80);
   dec(PNGlist[PNGindex].origofsyp, 15);
  end;

  gid_SETSUJUU: begin
   dec(PNGlist[PNGindex].origofsxp, 24);
   dec(PNGlist[PNGindex].origofsyp, 28);
  end;

 end;
end;

procedure UnpackPiGraphic(loader : TFileLoader; PNGindex : dword);
var destp, endp, startp : pointer;
    lcolors : array of array of byte;
    i, j : dword;
    lastbyteout, lastreptype : byte;
    doingrepetition : boolean;

  function readbits(numbits : byte) : byte; inline;
  begin
   readbits := 0;
   while numbits <> 0 do begin
    dec(numbits);
    readbits := readbits shl 1;
    if loader.Readbit then inc(readbits);
   end;
  end;

  function translatedeltacode : byte; inline;
  // Translates a variable-bit-length delta code into a normal number.
  // (Only works for 16-color variant, haven't seen 256-color Pi files...)
  begin
   translatedeltacode := 0;
   // safety
   if loader.readp + 2 >= loader.endp then begin
    loader.readp := loader.endp;
    exit;
   end;

   if loader.ReadBit then begin // 1x
    if loader.ReadBit then translatedeltacode := 1;

   end else begin // 0...
    if loader.ReadBit then begin // 01...
     if loader.ReadBit then begin // 011...

      if length(lcolors) = 256 then begin
       if loader.ReadBit then begin // 0111...
        if loader.ReadBit then begin // 01111...
         if loader.ReadBit then begin // 011111...
          if loader.ReadBit then begin // 0111111xxxxxxx
           translatedeltacode := 128 + readbits(7);
          end else // 0111110xxxxxx
           translatedeltacode := 64 + readbits(6);
         end else // 011110xxxxx
          translatedeltacode := 32 + readbits(5);
        end else // 01110xxxx
         translatedeltacode := 16 + readbits(4);
       end else // 0110xxx
        translatedeltacode := 8 + readbits(3);
      end

      else // 011xxx
       translatedeltacode := 8 + readbits(3);

     end else // 010xx
      translatedeltacode := 4 + readbits(2);
    end else begin // 00x
     if loader.ReadBit then translatedeltacode := 3 else translatedeltacode := 2;
    end;
   end;
  end;

  function getlengthcode : dword; inline;
  // Returns a variable-bit-length number used for repetition lengths.
  var bitprefixcount : word;
  begin
   bitprefixcount := 0;
   while (loader.readp < loader.endp) and (loader.ReadBit) do
    inc(bitprefixcount);
   getlengthcode := 1 shl bitprefixcount;
   while bitprefixcount <> 0 do begin
    dec(bitprefixcount);
    if (loader.readp < loader.endp) and (loader.ReadBit) then
     getlengthcode := dword(getlengthcode + dword(1 shl bitprefixcount));
   end;
   // safety, for unreasonably long repeats
   if getlengthcode >= $10000000 then getlengthcode := $FFFFFFF;
  end;

  function getrepetitiontype : byte; inline;
  // Returns one of five bitpacked repetition type codes.
  begin
   getrepetitiontype := 0;
   // safety
   if loader.readp + 2 >= loader.endp then begin
    loader.readp := loader.endp;
    exit;
   end;

   if loader.ReadBit then begin
    if loader.ReadBit then begin
     if loader.ReadBit then getrepetitiontype := 111
     else getrepetitiontype := 110;
    end
    else getrepetitiontype := 10;
   end else begin
    if loader.ReadBit then getrepetitiontype := 1;
   end;
  end;

  procedure copybytes(replen, repofs : dword; oobfiller : word); inline;
  // Copies replen bytes from (destp - repofs)^ to destp^. Where the source
  // offset is before the start of the image, fill with oobfiller instead.
  var oobcount : longint;
  begin
   oobcount := repofs - (destp - startp);
   if oobcount > 0 then begin
    if replen < dword(oobcount) then oobcount := replen;
    fillword(destp^, oobcount shr 1, oobfiller);
    inc(destp, oobcount);
    dec(replen, oobcount);
    // Handle odd fill lengths.
    if oobcount and 1 <> 0 then
     byte((destp - 1)^) := byte(oobfiller);
   end;

   memcopy(destp - repofs, destp, replen);
   inc(destp, replen);
  end;

  procedure processcolorcode;
  // Reads a color code from the input bit stream, adjusts the delta table,
  // and outputs a single byte.
  var deltaindex, newdelta : byte;
  begin
   deltaindex := translatedeltacode();
   // Move the new delta code to the front of its array.
   newdelta := lcolors[lastbyteout][deltaindex];
   while deltaindex <> 0 do begin
    lcolors[lastbyteout][deltaindex] := lcolors[lastbyteout][deltaindex - 1];
    dec(deltaindex);
   end;
   lcolors[lastbyteout][0] := newdelta;
   // The next byte out is the last byte plus a delta.
   lastbyteout := newdelta;
   byte(destp^) := lastbyteout;
   inc(destp);
  end;

  procedure processrepetitioncode(minusreps : byte);
  var replength : dword;
      bytequad : dword;
      bytepair : word;
      reptype : byte;
  begin
   // If the new repetition type is the same as the last one, stop doing
   // repeats and expect color codes again.
   reptype := getrepetitiontype();
   if lastreptype = reptype then begin
    doingrepetition := FALSE;
    lastbyteout := byte((destp - 1)^);
    exit;
   end;
   lastreptype := reptype;

   // Read the number of repetitions required. Subtract minusreps, which is
   // always 0 except on the first forced repeat where it is 1.
   // The repetitions are specified as byte pairs in the stream, so multiply
   // by two to get the byte length.
   replength := dword(getlengthcode - minusreps) * 2;

   // safety
   if destp + replength >= endp then replength := endp - destp;

   if replength <> 0 then
   case reptype of
     0: begin
      // Special repeat type, "Location 0" in the spec. Normally this repeats
      // the last 4 bytes, unless the last two bytes are equal or we're only
      // two bytes into the image, in which case it repeats the last 2 bytes.
      bytepair := word((destp - 2)^);
      if (destp < startp + 4) or (bytepair and $FF = bytepair shr 8)
      then begin
       // Repeat last two bytes.
       fillword(destp^, replength shr 1, bytepair);
       inc(destp, replength);
      end
      else begin
       // Repeat last four bytes.
       bytequad := dword((destp - 4)^);
       filldword(destp^, replength shr 2, bytequad);
       inc(destp, replength);
       // Handle odd number of repeats.
       if replength and 2 <> 0 then
        word((destp - 2)^) := word(bytequad);
      end;
     end;

     // Repeat type "Location 1" in the spec. Copy bytes from exactly one
     // row above. While out of bounds, copy only the top left word.
     1: copybytes(replength, PNGlist[PNGindex].origsizexp, word(startp^));

     // Repeat type "Location 2" in the spec. Copy bytes from exactly two
     // rows above. While out of bounds, copy only the top left word.
     10: copybytes(replength, PNGlist[PNGindex].origsizexp * 2, word(startp^));

     // Repeat type "Location 3" in the spec. Copy bytes from one row above,
     // 1 byte ahead. While out of bounds, copy the top left word, reversed.
     110: copybytes(replength, PNGlist[PNGindex].origsizexp - 1, swap(word(startp^)));

     // Repeat type "Location 4" in the spec. Copy bytes from one row above,
     // 1 byte back. While out of bounds, copy the top left word, reversed.
     111: copybytes(replength, PNGlist[PNGindex].origsizexp + 1, swap(word(startp^)));
   end;
  end;

begin
 // The image will be directly decompressed into an 8bpp buffer, even if the
 // palette is only 16 colors. The algorithm doesn't care about the actual
 // palette values or presence/absence of alpha; we're only dealing with
 // an input bit stream and an output byte stream.
 i := PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp;
 getmem(PNGlist[PNGindex].bitmap, i);

 // Set up an access pointer and some important position markers.
 startp := PNGlist[PNGindex].bitmap;
 destp := startp;
 endp := startp + i;

 loader.bitindex := 7;
 lastbyteout := 0;
 lastreptype := 255;
 doingrepetition := TRUE;

 // Set up a color delta table.
 setlength(lcolors, length(PNGlist[PNGindex].pal));
 for i := 0 to high(lcolors) do begin
  setlength(lcolors[i], length(lcolors));
  for j := 0 to high(lcolors[i]) do
   lcolors[i][j] := (dword(length(lcolors)) + i - j) and byte(high(lcolors));
 end;

 // Start with two color codes.
 processcolorcode();
 processcolorcode();
 // Forced repetition, with length reduced by one.
 processrepetitioncode(1);

 while destp < endp do begin
  if doingrepetition then
   processrepetitioncode(0)
  else begin
   processcolorcode();
   processcolorcode();
   // If the next bit is not set, we'll do a repetition;
   // else two more color codes will follow.
   if loader.ReadBit = FALSE then begin
    doingrepetition := TRUE;
    lastreptype := 255;
   end;
  end;

  if loader.readp + 2 > loader.endp then
   raise DecompException.Create('Image incomplete, input bit stream too short, output still needs ' + strdec(endp - destp) + ' bytes');
 end;
 if loader.readp + 8 < loader.endp then
  raise DecompException.Create('Image complete, but input bit stream still has ' + strdec(loader.endp - loader.readp) + ' bytes');
end;

procedure Decomp_Pi(const loader : TFileLoader; const outputfile : UTF8string);
// Reads the indicated Pi graphics file, and saves it in outputfile as
// a normal PNG.
// Throws an exception in case of errors.
var tempbmp : bitmaptype;
    imunamu : UTF8string;
    i, j : dword;
    PNGindex, xparency, clippedx : dword;
    bitdepth : byte;
begin
 tempbmp.image := NIL;
 bitdepth := 4;

 // Find this graphic name in PNGlist[], or create if doesn't exist yet.
 imunamu := ExtractFileName(loader.filename);
 imunamu := upcase(copy(imunamu, 1, length(imunamu) - length(ExtractFileExt(imunamu))));
 PNGindex := seekpng(imunamu, TRUE);

 {$ifdef bonk}
 // Check the file for a SADBMP signature.
 if dword(loader.readp^) = $002A4949 then begin
  write(stdout, '[sadbmp] ');
  PNGlist[PNGindex].origsizexp := loader.ReadDwordFrom(30);
  PNGlist[PNGindex].origsizeyp := loader.ReadDwordFrom(42);
  // Read the deranged palette.
  setlength(PNGlist[PNGindex].pal, 16);
  loader.ofs := $100;
  for i := 0 to 15 do with PNGlist[PNGindex].pal[i] do begin
   r := loader.ReadWordFrom(loader.ofs + 0) and $F0;
   g := loader.ReadWordFrom(loader.ofs + 32) and $F0;
   b := loader.ReadWordFrom(loader.ofs + 64) and $F0;
   inc(loader.readp, 2);
  end;
  // Copy the picture over, while expanding 4bpp indexed --> 8bpp indexed.
  i := PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp;
  getmem(PNGlist[PNGindex].bitmap, i);
  i := i shr 1;
  loader.ofs := $200;
  j := 0;
  while (i <> 0) and (loader.readp < loader.endp) do begin
   dec(i);
   byte((PNGlist[PNGindex].bitmap + j)^) := byte(loader.readp^) and $F;
   inc(j);
   byte((PNGlist[PNGindex].bitmap + j)^) := byte(loader.readp^) shr 4;
   inc(j); inc(loader.readp);
  end;
 end else
 {$endif}

 // Specification-compliant Pi files should always end the encoded image
 // stream with "32 bits of 0", ie. one dword of 0. Not all files respect
 // this: some Deep images end with only 3 zero-bytes, some Tasogare images
 // end with only 2.
 // "Sansi" in 3sis ends with 0000 001A, so accept the eof mark.
 if (word((loader.endp - 2)^) <> 0)
 and (dword((loader.endp - 4)^) <> $1A000000)
 then
  raise DecompException.Create('File doesn''t end with 00 00');

 // The file may begin with the full Pi header, with optional signature, or
 // it may skip straight to the image size declaration.

 // Check if the first two words are a valid image size.
 // (converting big endian to native)
 i := BEtoN(dword(loader.readp^));
 j := i and $FFFF;
 i := i shr 16;
 if (i < 2) or (j < 2)
 or (i > 640) or (j > 800)
 then begin
  // The file doesn't appear to start with a valid size, so it must start
  // with the full header. The header starts with a comment block that
  // terminates with $1A.
  repeat
   if (loader.readp + 16 >= loader.endp) or (loader.ofs > $170) then begin
    loader.ofs := 0;
    raise DecompException.Create('Comment block $1A not found');
   end;
  until loader.ReadByte = $1A;

  // The header starts after the first 0 after the 1A.
  repeat
   if (loader.readp + 16 >= loader.endp) or (loader.ofs > $170) then begin
    loader.ofs := 0;
    raise DecompException.Create('Header start 0 not found');
   end;
  until loader.ReadByte = 0;

  // If the comment block went up to offset $168, it probably contains
  // JAST-specific animation data. This is saved using only the top nibbles
  // of each byte.
  if loader.ofs = $168 then begin
   // Repack $164 nibbles into 178 bytes.
   loader.ofs := 2;
   for i := 1 to 178 do begin
    j := loader.ReadWord;
    byte(loader.PtrAt(i)^) := (j and $F0) or (j shr 12);
   end;
   // Process it.
   ConvertJastAnimData(loader.PtrAt(1), PNGindex);
   loader.ofs := $168;
  end;

  // Non-animated images never have offsets in the file, so reset those to
  // zero. Thus, at this point, every image has a proper baseline ofs.
  if PNGlist[PNGindex].seqlen = 0 then begin
   PNGlist[PNGindex].origofsxp := 0;
   PNGlist[PNGindex].origofsyp := 0;
  end;

  // Mode byte. Should be 00, could be FF.
  i := loader.ReadByte;
  if i in [0,$FF] = FALSE then
   raise DecompException.Create('Unknown mode ' + strdec(i));

  // Screen ratio. Is this ever not 0?
  i := loader.ReadByte;
  j := loader.ReadByte;
  if (i + j <> 0) and (i or j <> 1) then
   raise DecompException.Create('Non-zero ratio ' + strdec(i) + ':' + strdec(j));

  // Bitdepth. 4 or FF for 16 colors, 8 for 256 colors.
  bitdepth := loader.ReadByte;
  if bitdepth in [4,8,$FF] = FALSE then
   raise DecompException.Create('Unknown bitdepth ' + strdec(bitdepth));

  // Compressor model string. Usually only ascii chars.
  i := loader.ReadDword;
  // "Ese" in hiragana Shift-JIS is possible...
  if (i <> $B982A682) then
  // Any char >= $80 can't be ascii...
  if (i and $80808080 <> 0)
  // Any char < $20 can't be ascii...
  or (i and $60000000 = 0)
  or (i and $00600000 = 0)
  or (i and $00006000 = 0)
  or (i and $00000060 = 0) then
   raise DecompException.Create('Invalid compressor model $' + strhex(i));

  // Compressor-specific data, prefixed by length word, MSB first. Ignore.
  i := BEtoN(loader.ReadWord);
  if i > 5 then
   raise DecompException.Create('Suspicious compressor-specific data length ' + strdec(i));
  inc(loader.readp, i);
 end;

 // Next two words are image width and height, MSB first.
 i := BEtoN(loader.ReadWord);
 j := BEtoN(loader.ReadWord);

 if (i > 640) or (j > 800)
 or (i < 2) or (j < 2) then
  raise DecompException.Create('Suspicious size ' + strdec(i) + 'x' + strdec(j) + ' is causing dragons of loading to refuse.');

 PNGlist[PNGindex].origsizexp := i;
 PNGlist[PNGindex].origsizeyp := j;

 // Read the palette. Since PC98 systems of this era only used 4 bits per
 // channel, each palette byte must copy its top nibble to its bottom nibble.
 setlength(PNGlist[PNGindex].pal, 0);
 case bitdepth of
   4, $FF: setlength(PNGlist[PNGindex].pal, 16);
   8: setlength(PNGlist[PNGindex].pal, 256);
   else raise DecompException.Create('Unknown bitdepth ' + strdec(bitdepth));
 end;

 for i := 0 to high(PNGlist[PNGindex].pal) do
  with PNGlist[PNGindex].pal[i] do begin
   r := loader.ReadByte and $F0;
   g := loader.ReadByte and $F0;
   b := loader.ReadByte and $F0;
   r := r or (r shr 4);
   g := g or (g shr 4);
   b := b or (b shr 4);
   a := $FF;
  end;

 // The compressed image stream should immediately follow the palette.
 UnpackPiGraphic(loader, PNGindex);

 // Did we get the image?
 if PNGlist[PNGindex].bitmap = NIL then
  raise DecompException.Create('Failed to load image');

 // Mark the transparent palette index, if any.
 // The transparent index is almost always 8, and usually applies only to
 // sprites and animations, but there are exceptions. I think the original
 // engines apply transparency only at runtime, so there's nothing in the
 // graphic files themselves to indicate the presence of transparency. So we
 // have no choice but to hardcode this stuff.
 PNGlist[PNGindex].bitflag := 0;
 xparency := $FFFFFFFF;

 // Commonly named files...
 if game in [
   gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2, gid_MARIRIN, gid_DEEP,
   gid_SETSUJUU, gid_TRANSFER98, gid_3SIS, gid_3SIS98, gid_EDEN, gid_FROMH,
   gid_HOHOEMI, gid_VANISH, gid_RUNAWAY, gid_RUNAWAY98, gid_SAKURA,
   gid_SAKURA98, gid_MAJOKKO, gid_TASOGARE]
 then begin
  // Anything animated...
  if (PNGlist[PNGindex].seqlen <> 0)
  // Common names...
  or (imunamu = 'MS_CUR')
  or (imunamu = 'TIARE_P')
  or (imunamu = 'MARU1') or (imunamu = 'MARU2') or (imunamu = 'MARU3')
  or (imunamu = 'TB_008') // completely transparent graphic!
  then xparency := 8 else

  if imunamu = 'PUSH2' then xparency := $F;
 end
 else if game in [gid_MAYCLUB, gid_MAYCLUB98, gid_NOCTURNE, gid_NOCTURNE98]
 then begin
  // This is nearly always index 0.
  xparency := 0;
 end;

 // Game-specific files...
 case game of
   gid_3SIS, gid_3SIS98:
   if copy(imunamu, 1, 2) = 'ST' then xparency := 8;

   gid_ANGELSCOLLECTION2:
   if (imunamu = 'O4_005') or (imunamu = 'T2_LOGO') or (imunamu = 'T3_LOGO')
   then xparency := 8;

   gid_DEEP:
   if (copy(imunamu, 1, 3) = 'DC_') and (imunamu[5] = 'T')
   or (copy(imunamu, 1, 3) = 'DT_')
   then xparency := 8;

   gid_EDEN:
   if (imunamu = 'EE_070') or (imunamu = 'EE_084') or (imunamu = 'EE_087')
   or (imunamu = 'OP_TT') or (copy(imunamu, 1, 2) = 'ET')
   then xparency := 8;

   gid_FROMH:
   if (copy(imunamu, 1, 3) = 'FT_')
   or (imunamu = 'FE_007G') or (imunamu = 'FE_011G') or (imunamu = 'FH_010G')
   or (imunamu = 'FH_022G') or (imunamu = 'FH_029G')
   or (imunamu = 'FH_029G2') or (imunamu = 'FH_029G3') or (imunamu = 'FIN')
   then xparency := 8
   else if copy(imunamu, 1, 5) = 'OP_00' then xparency := $FFFFFFFF;

   gid_HOHOEMI:
   if (copy(imunamu, 3, 2) = '_S') or (copy(imunamu, 3, 2) = '_U')
   or (imunamu = 'OP_000_')
   then xparency := 8;

   gid_MAJOKKO:
   if (copy(imunamu, 1, 2) = 'MT') or (copy(imunamu, 1, 2) = 'NO')
   or (imunamu = 'TAITOL') or (imunamu = 'SAKURA')
   then xparency := 8;

   gid_MAYCLUB, gid_MAYCLUB98:
   if (copy(imunamu, 1, 3) = 'Z01') or (imunamu[1] in ['0'..'9'])
   then xparency := $FFFFFFFF;

   gid_RUNAWAY, gid_RUNAWAY98:
   if (copy(imunamu, 1, 3) = 'M8_')
   or (imunamu = 'OP_013A0') or (imunamu = 'MB07A') or (imunamu = 'MB09_1A')
   then xparency := 8;

   gid_SAKURA, gid_SAKURA98:
   if (copy(imunamu, 1, 2) = 'CT')
   or (imunamu = 'AE_007G') or (imunamu = 'HANKO')
   then xparency := 8
   else if imunamu = 'SAKURA' then xparency := $F; // petals! :D

   gid_SETSUJUU:
   if (copy(imunamu, 1, 3) = 'ST_') or (imunamu = 'YUKI') // snowflakes! :D
   or (imunamu[length(imunamu)] = 'S')
   and (byte(valx(copy(imunamu, 4, 2))) in [5,9,30,43,48,53,58,63,68])
   then xparency := 8;

   gid_TASOGARE:
   if (copy(imunamu, 1, 3) = 'MAP')
   or (copy(imunamu, 1, 3) = 'YO_')
   or (copy(imunamu, 1, 3) = 'YT_') and (imunamu[length(imunamu)] <> 'E')
   or (copy(imunamu, 1, 6) = 'YE_004') and (length(imunamu) = 7)
   or (imunamu = 'YE_006G') or (imunamu = 'YE_028')
   or (imunamu = 'YE_029') or (imunamu = 'YB_012G')
   then xparency := 8;

   gid_TRANSFER98:
   if (copy(imunamu, 1, 3) = 'TT_') or (imunamu = 'TI_135A')
   or (imunamu = 'ROGOL2')
   then xparency := 8
   else if imunamu = 'TB_149A' then xparency := 7;

   gid_VANISH:
   if (copy(imunamu, 1, 3) = 'MC_') or (copy(imunamu, 1, 3) = 'MJ_')
   or (copy(imunamu, 1, 3) = 'MT_') or (copy(imunamu, 1, 2) = 'VM')
   or (copy(imunamu, 1, 3) = 'VT_')
   or (imunamu = 'V_LOGO2')
   then xparency := 8;
 end;

 // Mark alpha as present.
 if xparency < dword(length(PNGlist[PNGindex].pal)) then begin
  PNGlist[PNGindex].bitflag := $80;
  PNGlist[PNGindex].pal[xparency].a := 0;
 end;

 // Mark the intended image resolution.
 // The originals are all 640x400, but a good chunk of that is wasted in
 // a viewframe. Graphics that are displayed inside the viewframe should use
 // the viewport's size as a resolution; that way SuperSakura can scale
 // them to full window size. As a rule, anything bigger than the viewport
 // (baseres) cannot fit inside the frame, and so should use a 640x400
 // resolution. There are also some smaller graphics, such as falling sakura
 // petals, meant to be used in a 640x400 context.

 i := 0;
 if PNGlist[PNGindex].seqlen = 0 then
  if (PNGlist[PNGindex].origsizexp > baseresx)
  or (PNGlist[PNGindex].origsizeyp > baseresy) then inc(i);

 if game in [
   gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2, gid_MARIRIN, gid_DEEP,
   gid_SETSUJUU, gid_TRANSFER98, gid_3SIS, gid_3SIS98, gid_EDEN, gid_FROMH,
   gid_HOHOEMI, gid_VANISH, gid_RUNAWAY, gid_RUNAWAY98, gid_SAKURA,
   gid_SAKURA98, gid_MAJOKKO, gid_TASOGARE]
 then begin
  if (imunamu = 'TIARE_P')
  or (imunamu = 'MARU1') or (imunamu = 'MARU2') or (imunamu = 'MARU3')
  then inc(i);
 end;

 case game of
   gid_ANGELSCOLLECTION1: if imunamu = 'TENGO_NO' then inc(i);
   gid_FROMH: if (imunamu[1] = 'O') or (imunamu = 'PUSH') then inc(i);
   gid_MAJOKKO: if imunamu = 'JURA' then inc(i);
   gid_MAYCLUB: if imunamu = 'PRS' then inc(i);
   gid_SAKURA, gid_SAKURA98:
    if (imunamu = 'HANKO') or (imunamu = 'SAKURA')
    or (copy(imunamu, 1, 5) = 'AE_19')
    then inc(i);
   gid_SETSUJUU: if copy(imunamu, 1, 3) = 'SET' then inc(i);
   gid_RUNAWAY, gid_RUNAWAY98: if imunamu = 'OP_013A0' then inc(i);
   gid_TRANSFER98: if imunamu = 'ROGOL2' then inc(i);
 end;

 if i <> 0 then begin
  PNGlist[PNGindex].origresx := 640;
  PNGlist[PNGindex].origresy := 400;
 end;

 {$ifdef enable_hacks}
 // Fix image garbage problems, clip transparent edges...

 if game in [
   gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2, gid_MARIRIN, gid_DEEP,
   gid_SETSUJUU, gid_TRANSFER98, gid_3SIS, gid_3SIS98, gid_EDEN, gid_FROMH,
   gid_HOHOEMI, gid_VANISH, gid_RUNAWAY, gid_RUNAWAY98, gid_SAKURA,
   gid_SAKURA98, gid_MAJOKKO, gid_TASOGARE]
 then begin
  if imunamu = 'MS_CUR' then begin
   // Hack: all cursors are 32x32 pixels, use proper frame division
   PNGlist[PNGindex].framewidth := 32;
   PNGlist[PNGindex].frameheight := 32;
  end else
  if imunamu = 'PUSH' then begin
   // Hack: all push anims are 16x16 pixels
   PNGlist[PNGindex].framewidth := 16;
   PNGlist[PNGindex].frameheight := 16;
  end;
 end;

 clippedx := PNGlist[PNGindex].origsizexp;
 case game of
  gid_ANGELSCOLLECTION1: begin
   // Hack: add frame size for viewframe roman numerals image
   if imunamu = 'TENGO_NO' then begin
    PNGlist[PNGindex].framewidth := 32;
    PNGlist[PNGindex].frameheight := 25;
    PNGlist[PNGindex].origofsxp := 552;
    PNGlist[PNGindex].origofsyp := 276;
   end;
  end;
  gid_EDEN: begin
   // Hack: many animations have an incorrect palette, blanket fix
   if copy(imunamu, length(imunamu) - 1, 2) = 'A0'
   then with PNGlist[PNGindex] do begin
    pal[1].r := $50; pal[2].r := $80; pal[3].r := $B0; pal[6].b := $D0;
    pal[8].r := $90; pal[8].b := $50;
    pal[12].r := $A0; pal[12].g := $70; pal[12].b := $60;
    pal[13].r := $D0;
   end;
  end;
  gid_FROMH: begin
   // Hack: cut out garbage pixels
   if imunamu = 'FT_09' then clippedx := 180;
   if imunamu = 'FT_10' then clippedx := 180;
   if imunamu = 'FT_11' then clippedx := 180;
   if imunamu = 'FT_14' then clippedx := 200;
   if imunamu = 'FT_15' then clippedx := 200;
   if imunamu = 'FT_16' then clippedx := 200;
   // Hack: add missing animation data
   if imunamu = 'FIN' then with PNGlist[PNGindex] do begin
    framewidth := 152; frameheight := 96;
    seqlen := 16; setlength(sequence, seqlen);
    for i := 0 to 15 do sequence[i] := (i shl 16) or $50;
    sequence[14] := sequence[14] or $200;
    sequence[15] := sequence[15] or $FFFF;
   end;
   if imunamu = 'OP_001A0' then with PNGlist[PNGindex] do begin
    framewidth := 160; frameheight := 200;
    origofsxp := (origresx - framewidth) shr 1; // make it centered
    origofsyp := (origresy - frameheight) shr 1 - 12; // a bit above center
    seqlen := 16; setlength(sequence, seqlen);
    sequence[0] := $00000190; // frame 0 for 400 ms
    sequence[1] := $00010190; // frame 1 for 400 ms, rep x2
    for i := 2 to 11 do sequence[i] := sequence[i and 1];
    // frames 2+3 for 400 ms, rep x3
    for i := 6 to 11 do sequence[i] := sequence[i] or $20000;
    sequence[12] := $00040100; // frame 4 for 256 ms
    sequence[13] := $00050100; // frame 5 for 256 ms
    sequence[14] := $00060100; // frame 6 for 256 ms
    sequence[15] := $0007FFFF; // frame 7, stop
   end;
   if imunamu = 'PUSH' then with PNGlist[PNGindex] do begin
    framewidth := 64; frameheight := 120;
    origofsxp := 544;
    origofsyp := 280;
    seqlen := 11; setlength(sequence, seqlen);
    for i := 0 to 8 do sequence[i] := (i shl 16) or $100; // 256 ms
    sequence[9] := $00097FFF; // frame 9 for 32767 ms
    sequence[10] := $0009BFFF; // frame 9 for random(16383) ms
   end;
  end;
  gid_HOHOEMI: begin
   // Hack: add missing animation data
   if imunamu = 'FIN' then with PNGlist[PNGindex] do begin
    framewidth := 152; frameheight := 96;
    seqlen := 16; setlength(sequence, seqlen);
    for i := 0 to 15 do sequence[i] := (i shl 16) or $50;
    sequence[14] := sequence[14] or $200;
    sequence[15] := sequence[15] or $FFFF;
   end;
   // Hack: Replace transparent palette with solid white
   if imunamu = 'OP_000_' then with PNGlist[PNGindex] do begin
    xparency := $FFFFFFFF;
    pal[8] := pal[$F];
    bitflag := bitflag and $7F;
   end;
  end;
  gid_MAJOKKO: begin
   // Hack: cut out garbage pixels
   if imunamu = 'MT01FU' then clippedx := 200;
   // Hack: extrapolate a missing pixel row by copying from one up left
   if imunamu = 'KE_069_1' then begin
    i := PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp;
    for j := (PNGlist[PNGindex].origsizexp shr 2) - 1 downto 0 do begin
     dec(i, 4);
     dword((PNGlist[PNGindex].bitmap + i)^) := dword((PNGlist[PNGindex].bitmap + i - PNGlist[PNGindex].origsizexp - 1)^);
    end;
    // fix minor remaining discontinuity
    i := PNGlist[PNGindex].origsizexp * (PNGlist[PNGindex].origsizeyp - 1);
    dword((PNGlist[PNGindex].bitmap + i + 203)^) := $0E0D0C00; // lt leg
    dword((PNGlist[PNGindex].bitmap + i + 296)^) := $0F000C0F; // rt leg
    dword((PNGlist[PNGindex].bitmap + i + 362)^) := $0F050404; // rt hand
    inc(i, 247); // inside legs
    move((PNGlist[PNGindex].bitmap + i - PNGlist[PNGindex].origsizexp)^, (PNGlist[PNGindex].bitmap + i)^, 9);
   end;
   // Hack: add missing animation data
   if imunamu = 'JURA' then with PNGlist[PNGindex] do begin
    framewidth := 48; frameheight := 70;
    origofsxp := 552;
    origofsyp := 322;
    seqlen := 11; setlength(sequence, seqlen);
    sequence[0] := $0000BFFF; // frame 0 for random(16383) ms
    sequence[1] := $00002008; // frame 0 for 8200 ms
    sequence[2] := $00010100; // frame 1 for 256 ms
    sequence[3] := $00020100; // frame 2 for 256 ms
    sequence[4] := $00030100; // frame 3 for 256 ms
    sequence[5] := $00020100; // frame 2 for 256 ms
    sequence[6] := $00010100; // frame 1 for 256 ms
    sequence[7] := $00020100; // frame 2 for 256 ms
    sequence[8] := $00030100; // frame 3 for 256 ms
    sequence[9] := $00020100; // frame 2 for 256 ms
    sequence[10] := $C0030000; // jump to sequence index random(3)
   end;
  end;
  gid_MAYCLUB, gid_MAYCLUB98: begin
   // Hack: cut out garbage pixels
   if imunamu = 'D27A' then clippedx := 182;
  end;
  gid_RUNAWAY, gid_RUNAWAY98: begin
   // Hack: set garbage pixel in bottom left corner to transparent
   if imunamu = 'M8_012' then with PNGlist[PNGindex] do
    byte((bitmap + origsizexp * (origsizeyp - 1))^) := xparency;
  end;
  gid_SAKURA, gid_SAKURA98: begin
   // Hack: fix a graphic garbage bug in the original
   if imunamu = 'CT03D' then dec(PNGlist[PNGindex].origsizeyp);
   // Hack: cut out unnecessary space caused by garbage pixels
   if imunamu = 'CT02S' then clippedx := 169;
   if imunamu = 'CT05S' then clippedx := 169;
   if imunamu = 'CT11D' then dec(PNGlist[PNGindex].origsizeyp, 160);
   if imunamu = 'CT14M' then clippedx := 299;
   // Hack: add offset to title bar
   if imunamu = 'SAKU_T' then begin
    inc(PNGlist[PNGindex].origofsxp, 64);
    inc(PNGlist[PNGindex].origofsyp, 112);
   end;
   // Hack: add frame sizes for sakura petal animation
   if imunamu = 'SAKURA' then begin
    PNGlist[PNGindex].framewidth := 16;
    PNGlist[PNGindex].frameheight := 16;
   end;
  end;
  gid_SETSUJUU: begin
   // Hack: leftmost pixel column is garbage, set it to transparent
   if imunamu = 'SH_58S' then begin
    j := 0;
    for i := PNGlist[PNGindex].origsizeyp - 1 downto 0 do begin
     byte((PNGlist[PNGindex].bitmap + j)^) := xparency;
     inc(j, PNGlist[PNGindex].origsizexp);
    end;
   end;
   // Hack: cut out garbage pixels
   if imunamu = 'SH_30S' then dec(PNGlist[PNGindex].origsizeyp);
   if imunamu = 'SH_63S' then begin PNGlist[PNGindex].origsizeyp := 130; clippedx := 180; end;
   if imunamu = 'SH_68S' then clippedx := 460;
   if imunamu = 'ST_05' then clippedx := 462;
  end;
  gid_TRANSFER98: begin
   // Hack: fix the palette
   if imunamu = 'TI_135A' then
   with PNGlist[PNGindex] do begin
    pal[0].r := 0; pal[0].g := 0; pal[0].b := 0;
    pal[1].r := $40; pal[1].g := $30; pal[1].b := $A0;
    pal[2].r := $40; pal[2].g := $60; pal[2].b := $C0;
    pal[3].r := $B0; pal[3].g := $C0; pal[3].b := $E0;
    pal[4].r := $80; pal[4].g := $90; pal[4].b := $D0;
    pal[5].r := $C0; pal[5].g := $80; pal[5].b := $70;
    pal[6].r := $F0; pal[6].g := $C0; pal[6].b := $B0;
    pal[7].r := $00; pal[7].g := $40; pal[7].b := $10;
    pal[8].r := $80; pal[8].g := $50; pal[8].b := $50;
    pal[9].r := $50; pal[9].g := $30; pal[9].b := $30;
    pal[10].r := $80; pal[10].g := $00; pal[10].b := $00;
    pal[11].r := $80; pal[11].g := $40; pal[11].b := $B0;
    pal[12].r := $50; pal[12].g := $10; pal[12].b := $70;
    pal[13].r := $C0; pal[13].g := $30; pal[13].b := $40;
    pal[14].r := $B0; pal[14].g := $70; pal[14].b := $F0;
    pal[15].r := $F0; pal[15].g := $F0; pal[15].b := $F0;
   end;
   // Hack: cut out garbage pixel
   if imunamu = 'TT_20' then clippedx := 360;
   // Hack: cut out unused black area
   if (imunamu = 'TH_042')
   or (imunamu = 'TH_110')
   then clippedx := 296;
  end;
  gid_TASOGARE: begin
   // Hack: cut out garbage pixels
   if imunamu = 'YT_10' then clippedx := 270;
   // Hack: add frame size for title graphics
   if imunamu = 'OP_MOJI' then begin
    PNGlist[PNGindex].framewidth := 80;
    PNGlist[PNGindex].frameheight := 400;
   end;
   if imunamu = 'OP_XXA' then with PNGlist[PNGindex] do begin
    framewidth := 64; frameheight := 168;
    origofsxp := 144;
    origofsyp := 168;
    seqlen := 15; setlength(sequence, seqlen);
    // show each frame for 100 msec
    for i := 0 to 13 do sequence[i] := (i shl 16) or $64;
    sequence[14] := $000EFFFF; // frame 14, stop
   end;
  end;
  gid_VANISH: begin
   // Hack: cut out garbage pixels
   if imunamu = 'VT_006' then clippedx := 350;
  end;
 end;

 // Clip the right side of the image, if required.
 if clippedx <> PNGlist[PNGindex].origsizexp then begin
  // (row 0 is already in place, can be skipped)
  for i := 1 to PNGlist[PNGindex].origsizeyp - 1 do
   move((PNGlist[PNGindex].bitmap + i * PNGlist[PNGindex].origsizexp)^,
        (PNGlist[PNGindex].bitmap + i * clippedx)^,
        clippedx);
  PNGlist[PNGindex].origsizexp := clippedx;
 end;

 PNGlist[PNGindex].framecount := 0;
 if PNGlist[PNGindex].framewidth = 0 then PNGlist[PNGindex].framewidth := PNGlist[PNGindex].origsizexp;
 if PNGlist[PNGindex].frameheight = 0 then PNGlist[PNGindex].frameheight := PNGlist[PNGindex].origsizeyp;

 // Compare the frame size to the image size to see if there are animation
 // frames. If there are, stack them vertically for easier access.
 if (PNGlist[PNGindex].framewidth < PNGlist[PNGindex].origsizexp)
 or (PNGlist[PNGindex].frameheight < PNGlist[PNGindex].origsizeyp)
 then RearrangeFrames(PNGindex)

 // If the graphic is not an animation, but has transparency, empty space at
 // the edges can be cropped out, but for a one-pixel transparent border.
 // (But leave TB_008 alone, we need a full-viewport transparent layer to act
 // as an overlay for the graphic stash.)
 else if (xparency < dword(length(PNGlist[PNGindex].pal)))
 and (imunamu <> 'TB_008')
 then CropVoidBorders(PNGindex, xparency);

 {$endif enable_hacks}

 // Put the uncompressed image into a bitmaptype for PNG conversion...
 tempbmp.image := PNGlist[PNGindex].bitmap;
 PNGlist[PNGindex].bitmap := NIL;
 tempbmp.sizex := PNGlist[PNGindex].origsizexp;
 tempbmp.sizey := PNGlist[PNGindex].origsizeyp;
 tempbmp.bitdepth := 8;
 tempbmp.memformat := 0; // 24-bit RGB
 setlength(tempbmp.palette, length(PNGlist[PNGindex].pal));

 if length(PNGlist[PNGindex].pal) <> 0 then begin
  tempbmp.memformat := 4; // indexed
  for i := high(PNGlist[PNGindex].pal) downto 0 do begin
   tempbmp.palette[i].a := PNGlist[PNGindex].pal[i].a;
   tempbmp.palette[i].b := PNGlist[PNGindex].pal[i].b;
   tempbmp.palette[i].g := PNGlist[PNGindex].pal[i].g;
   tempbmp.palette[i].r := PNGlist[PNGindex].pal[i].r;
  end;
 end;

 inc(tempbmp.memformat, PNGlist[PNGindex].bitflag shr 7);

 // Convert bitmaptype(pic^) into a compressed PNG, saved in bitmap^.
 // The PNG byte size goes into j.
 i := mcg_MemoryToPng(@tempbmp, @PNGlist[PNGindex].bitmap, @j);
 mcg_ForgetImage(@tempbmp);

 if i <> 0 then begin
  if PNGlist[PNGindex].bitmap <> NIL then begin
   freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
  end;
  raise DecompException.Create(mcg_errortxt);
 end;

 SaveFile(outputfile, PNGlist[PNGindex].bitmap, j);
 freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
end;
