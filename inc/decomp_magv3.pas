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

// SuperSakura_GRAMOVL_Decompiler
// Decomp --- Graphics conversion code

procedure ChewAnimations(animp : pointer; PNGindex : dword);
// Takes a pointer to a single unit of JAST/Tiare animation data, processes
// it into useful data in PNGlist[]. This does not release animp.
var ivar, jvar : dword;
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
 for ivar := 0 to 31 do begin
  PNGlist[PNGindex].sequence[ivar] := byte(animp^) shl 16;
  inc(animp, 2);
 end;
 // Convert to ~millisecs, shift delays to intuitively correct frames.
 for ivar := 1 to 32 do begin
  jvar := word((animp + ivar * 2)^) * 11;
  if jvar = 0 then jvar := 16;
  PNGlist[PNGindex].sequence[ivar - 1] := PNGlist[PNGindex].sequence[ivar - 1] + jvar;
 end;
 ivar := PNGlist[PNGindex].seqlen - 1;
 jvar := dword(word(animp^) * 11);
 PNGlist[PNGindex].sequence[ivar] := (PNGlist[PNGindex].sequence[ivar] and $FFFF0000) + jvar;
 // If sequence length = 1, enforce a stopped animation
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

function l_getcolorcode : byte;
// Translates a variable-bit-length color code into a normal number.
begin
 if l_getbit then begin // 1x
  if l_getbit then l_getcolorcode := 15 else l_getcolorcode := 16;

 end else begin // 0.....
  if l_getbit then begin // 01....
   if l_getbit then begin // 011xxx
    if l_getbit then begin // 0111xx
     if l_getbit then begin // 01111x
      if l_getbit then l_getcolorcode := 1 else l_getcolorcode := 2;
     end else begin // 01110x
      if l_getbit then l_getcolorcode := 3 else l_getcolorcode := 4;
     end;
    end else begin // 0110xx
     if l_getbit then begin // 01101x
      if l_getbit then l_getcolorcode := 5 else l_getcolorcode := 6;
     end else begin // 01100x
      if l_getbit then l_getcolorcode := 7 else l_getcolorcode := 8;
     end;
    end;
   end else begin // 010xx
    if l_getbit then begin // 0101x
     if l_getbit then l_getcolorcode := 9 else l_getcolorcode := 10;
    end else begin // 0100x
     if l_getbit then l_getcolorcode := 11 else l_getcolorcode := 12;
    end;
   end;
  end else begin // 00x
   if l_getbit then l_getcolorcode := 13 else l_getcolorcode := 14;
  end;
 end;
end;

function l_getlencode : dword;
// Returns a variable-bit-length number used for repetition lengths.
var luxus : word;
begin
 luxus := 0;
 while l_getbit do inc(luxus);
 l_getlencode := 1 shl luxus;
 while luxus <> 0 do begin
  dec(luxus);
  if l_getbit then inc(l_getlencode, dword(1 shl luxus));
 end;
end;

procedure UnpackMAG3Graphic(PNGindex : dword);
var iofs : dword;
    lcolors : array[0..15] of array[1..16] of byte;
    lpp, lnp : dword;
    ltv, llv : word;
    pair1, pair2, pairx : word;
    l_firstrep, l_mode : byte;
begin
 getmem(PNGlist[PNGindex].bitmap, PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp + 32768); // best have some room for overflow

 l_firstrep := 1; l_mode := 1; l_bitptr := 7; lpp := 0; iofs := 0;
 for llv := 0 to 15 do for ltv := 1 to 16 do lcolors[llv][ltv] := ltv;

 repeat
  case l_mode of
   // Two pixels using color delta
   1: begin
       ltv := l_getcolorcode;
       lnp := lcolors[lpp][ltv];
       llv := ltv;
       while ltv < 16 do begin
        lcolors[lpp][ltv] := lcolors[lpp][ltv + 1];
        inc(ltv);
       end;
       lcolors[lpp][16] := lnp;
       lnp := (lpp + lnp) and 15;
       lpp := lnp;
       byte((PNGlist[PNGindex].bitmap + iofs shl 1)^) := lnp;

       ltv := l_getcolorcode;
       lnp := lcolors[lpp][ltv];
       llv := ltv;
       while ltv < 16 do begin
        lcolors[lpp][ltv] := lcolors[lpp][ltv + 1];
        inc(ltv);
       end;
       lcolors[lpp][16] := lnp;
       lnp := (lpp + lnp) and 15;
       lpp := lnp;
       byte((PNGlist[PNGindex].bitmap + (iofs shl 1) + 1)^) := lnp;
       inc(iofs);

       if (l_firstrep <> 0) then l_mode := 2
       else if l_getbit = false then l_mode := 2;
      end;
   // Repetition
   2: begin
       if l_getbit then begin
        if l_getbit then begin
         if l_getbit then ltv := 111 else ltv := 110;
        end
        else ltv := 10;
       end else begin
        if l_getbit then ltv := 1 else ltv := 0;
       end;

       repeat
        lpp := l_getlencode;
        if l_firstrep <> 0 then dec(lpp);

        case ltv of
         0: begin
             pair1 := word((PNGlist[PNGindex].bitmap + iofs * 2 - 2)^);
             if (pair1 shr 8 = pair1 and $FF) or (iofs < 2)
             then begin
              // repeat previous pair
              fillword((PNGlist[PNGindex].bitmap + iofs * 2)^, lpp, pair1);
              inc(iofs, lpp);
             end else begin
              // repeat two previous pairs
              pair2 := word((PNGlist[PNGindex].bitmap + iofs * 2 - 4)^);
              while lpp > 0 do begin
               word((PNGlist[PNGindex].bitmap + iofs * 2)^) := pair2;
               pairx := pair2; pair2 := pair1; pair1 := pairx;
               inc(iofs);
               dec(lpp);
              end;
             end;
            end;
         1: begin
             // while in topmost row, only copy the top left corner pair
             if iofs shl 1 < PNGlist[PNGindex].origsizexp then begin
              if (iofs + lpp) shl 1 <= PNGlist[PNGindex].origsizexp then begin
               fillword((PNGlist[PNGindex].bitmap + iofs * 2)^, lpp, word(PNGlist[PNGindex].bitmap^));
               inc(iofs, lpp); lpp := 0;
              end else begin
               fillword(((PNGlist[PNGindex].bitmap + iofs * 2)^), word(PNGlist[PNGindex].origsizexp shr 1) - iofs, word(PNGlist[PNGindex].bitmap^));
               dec(lpp, word(PNGlist[PNGindex].origsizexp shr 1) - iofs); iofs := PNGlist[PNGindex].origsizexp shr 1;
              end;
             end;

             // copy pixel sequence directly above
             memcopy(PNGlist[PNGindex].bitmap + (iofs shl 1) - PNGlist[PNGindex].origsizexp, PNGlist[PNGindex].bitmap + (iofs shl 1), lpp shl 1);
             inc(iofs, lpp);
            end;
         10: begin
              // if in topmost or second highest row,
              // repeat the top left corner pair
              if iofs < PNGlist[PNGindex].origsizexp then begin
               if iofs + lpp <= PNGlist[PNGindex].origsizexp then begin
                fillword(((PNGlist[PNGindex].bitmap + iofs * 2)^), lpp, word(PNGlist[PNGindex].bitmap^));
                inc(iofs, lpp); lpp := 0;
               end else begin
                fillword(((PNGlist[PNGindex].bitmap + iofs * 2)^), PNGlist[PNGindex].origsizexp - iofs, word(PNGlist[PNGindex].bitmap^));
                dec(lpp, PNGlist[PNGindex].origsizexp - iofs); iofs := PNGlist[PNGindex].origsizexp;
               end;
              end;

              // otherwise copy pixels running two rows above
              memcopy(PNGlist[PNGindex].bitmap + (iofs - PNGlist[PNGindex].origsizexp) shl 1, PNGlist[PNGindex].bitmap + (iofs shl 1), lpp shl 1);
              inc(iofs, lpp);
             end;
         110: begin
               // while in topmost row, only copy the top left corner pair
               if iofs shl 1 < PNGlist[PNGindex].origsizexp then begin
                pair1 := (byte(PNGlist[PNGindex].bitmap^) shl 8) or byte((PNGlist[PNGindex].bitmap + 1)^);
                if (iofs + lpp) shl 1 <= PNGlist[PNGindex].origsizexp then begin
                 fillword(((PNGlist[PNGindex].bitmap + iofs * 2)^), lpp, pair1);
                 inc(iofs, lpp); lpp := 0;
                end else begin
                 fillword(((PNGlist[PNGindex].bitmap + iofs * 2)^), word(PNGlist[PNGindex].origsizexp shr 1) - iofs, pair1);
                 dec(lpp, word(PNGlist[PNGindex].origsizexp shr 1) - iofs); iofs := PNGlist[PNGindex].origsizexp shr 1;
                end;
               end;
               // copy pixel sequence directly above and right
               memcopy(PNGlist[PNGindex].bitmap + (iofs shl 1) - PNGlist[PNGindex].origsizexp + 1, PNGlist[PNGindex].bitmap + (iofs shl 1), lpp shl 1);
               inc(iofs, lpp);
              end;
         111: begin
               // while in topmost row, only copy the top left corner pair
               if iofs shl 1 < PNGlist[PNGindex].origsizexp then begin
                pair1 := (byte(PNGlist[PNGindex].bitmap^) shl 8) + byte((PNGlist[PNGindex].bitmap + 1)^);
                if (iofs + lpp) shl 1 <= PNGlist[PNGindex].origsizexp then begin
                 fillword(((PNGlist[PNGindex].bitmap + iofs * 2)^), lpp, pair1);
                 inc(iofs, lpp); lpp := 0;
                end else begin
                 fillword(((PNGlist[PNGindex].bitmap + iofs * 2)^), word(PNGlist[PNGindex].origsizexp shr 1) - iofs, pair1);
                 dec(lpp, word(PNGlist[PNGindex].origsizexp shr 1) - iofs); iofs := PNGlist[PNGindex].origsizexp shr 1;
                end;
               end;

               // exception: first pixel pair of second row
               if iofs shl 1 = PNGlist[PNGindex].origsizexp then begin
                byte((PNGlist[PNGindex].bitmap + iofs shl 1)^) := byte((PNGlist[PNGindex].bitmap + 1)^);
                byte((PNGlist[PNGindex].bitmap + (iofs shl 1) + 1)^) := byte(PNGlist[PNGindex].bitmap^);
                inc(iofs); dec(lpp);
               end;

               // copy pixel sequence directly above and left
               memcopy(PNGlist[PNGindex].bitmap + (iofs shl 1) - PNGlist[PNGindex].origsizexp - 1, PNGlist[PNGindex].bitmap + (iofs shl 1), lpp shl 1);
               inc(iofs, lpp);
              end;
        end;

        lnp := ltv;
        if l_getbit then begin
         if l_getbit then begin
          if l_getbit then ltv := 111 else ltv := 110;
         end
         else ltv := 10;
        end else begin
         if l_getbit then ltv := 1 else ltv := 0;
        end;

        l_firstrep := 0;
       until lnp = ltv;
       lpp := byte((PNGlist[PNGindex].bitmap + (iofs shl 1) - 1)^);
       l_mode := 1;
      end;
  end;
 until (iofs shl 1 >= PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp) or (lofs + 2 > loadersize);

 if lofs + 2 > loadersize then begin
  PrintError('Ran out of datastream before image finished!'); exit;
 end;
end;

function Decomp_Magv3(const srcfile, outputfile : UTF8string) : UTF8string;
// Reads the indicated MAG v3 graphics file, and saves it in outputfile as
// a normal PNG.
// Returns an empty string if successful, otherwise returns an error message.
var imunamu : UTF8string;
    ivar, jvar : dword;
    PNGindex, xparency, clippedx : dword;
    tempbmp : bitmaptype;
begin
 // Load the input file into loader^.
 Decomp_Magv3 := LoadFile(srcfile);
 if Decomp_Magv3 <> '' then exit;

 tempbmp.image := NIL;

 // Find this graphic name in PNGlist[], or create if doesn't exist yet.
 imunamu := ExtractFileName(srcfile);
 imunamu := upcase(copy(imunamu, 1, length(imunamu) - length(ExtractFileExt(imunamu))));
 PNGindex := seekpng(imunamu, TRUE);

 if (game = gid_DEEP) and (imunamu = 'DB_05_08') then begin
  Decomp_Magv3 := 'This is probably badly corrupted and would crash Decomp.';
  exit;
 end;

 // Check the file for a SADBMP signature.
 if dword(loader^) = $002A4949 then begin
  write(stdout, '[sadbmp] ');
  PNGlist[PNGindex].origsizexp := dword((loader + 30)^);
  PNGlist[PNGindex].origsizeyp := dword((loader + 42)^);
  // Read the deranged palette.
  setlength(PNGlist[PNGindex].pal, 16);
  lofs := $100;
  for ivar := 0 to 15 do with PNGlist[PNGindex].pal[ivar] do begin
   r := word((loader + lofs)^) and $F0;
   g := word((loader + lofs + 32)^) and $F0;
   b := word((loader + lofs + 64)^) and $F0;
   inc(lofs, 2);
  end;
  // Copy the picture over, while expanding 4bpp indexed --> 8bpp indexed.
  ivar := PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp;
  getmem(PNGlist[PNGindex].bitmap, ivar);
  ivar := ivar shr 1;
  lofs := $200; jvar := 0;
  while (ivar <> 0) and (lofs < loadersize) do begin
   dec(ivar);
   byte((PNGlist[PNGindex].bitmap + jvar)^) := byte((loader + lofs)^) and $F;
   inc(jvar);
   byte((PNGlist[PNGindex].bitmap + jvar)^) := byte((loader + lofs)^) shr 4;
   inc(jvar); inc(lofs);
  end;
 end else

 // Check the file for a "MAKI" signature.
 if dword(loader^) = $494B414D then begin
  write(stdout, '[makichan] ');
  // Forward to the appropriate decompressor.
  ivar := dword((loader + 4)^); // 01A, 01B, or 02
  lofs := 8;
  case ivar of
   $20413130: UnpackMakiGraphic(PNGindex, 1); // 01A
   $20423130: UnpackMakiGraphic(PNGindex, 2); // 01B
   $20203230: UnpackMAG2Graphic(PNGindex); // 02
   else begin
    Decomp_Magv3 := 'unknown MAKI subtype $' + strhex(ivar);
    exit;
   end;
  end;
 end

 else begin
  // Modified Maki-chan format, let's call it MAG v3.
  // The file starts with a metadata string. Find the terminating 1A marker!
  while byte((loader + lofs)^) <> $1A do begin
   inc(lofs);
   if (lofs + 16 >= loadersize) then begin
    Decomp_Magv3 := 'Initial block not found! Maybe not a GRA file.';
    exit;
   end;
  end;

  // If the metadata string is $166 bytes long, it contains animation data.
  if lofs = $166 then begin
   // Pack nibbles into bytes
   for ivar := 1 to 178 do
    byte((loader + ivar)^) := byte((loader + ivar * 2)^) or (byte((loader + ivar * 2 + 1)^) shr 4);
   // Process the data
   ChewAnimations(loader + 1, PNGindex);
  end;
  // Non-animated images never have offsets in the file, so reset those to
  // zero. Thus, at this point, every image has a proper baseline ofs.
  if PNGlist[PNGindex].seqlen = 0 then begin
   PNGlist[PNGindex].origofsxp := 0;
   PNGlist[PNGindex].origofsyp := 0;
  end;

  // Read ahead until 00 encountered
  while byte((loader + lofs)^) <> $00 do begin
   inc(lofs);
   if (lofs + 4 >= loadersize) then begin
    Decomp_MAGv3 := 'No 00 in initial block??';
    exit;
   end;
  end;

  // Skip this and next four bytes, hope to land on a signature.
  inc(lofs, 5);
  // Skip over sig.
  inc(lofs, 4);
  // Skip over a 00 byte.
  inc(lofs);
  // Now follows what feels like a pascal-string of unknown data.
  ivar := byte((loader + lofs)^);
  inc(lofs, ivar + 1);

  // Next two words are image width and height.
  PNGlist[PNGindex].origsizexp := byte((loader + lofs)^) shl 8 + byte((loader + lofs + 1)^);
  PNGlist[PNGindex].origsizeyp := byte((loader + lofs + 2)^) shl 8 + byte((loader + lofs + 3)^);
  inc(lofs, 4);

  if (PNGlist[PNGindex].origsizexp > 640) or (PNGlist[PNGindex].origsizeyp > 800)
  or (PNGlist[PNGindex].origsizexp < 2) or (PNGlist[PNGindex].origsizeyp < 2) then begin
   Decomp_MAGv3 := 'Suspicious size ' + strdec(PNGlist[PNGindex].origsizexp) + 'x' + strdec(PNGlist[PNGindex].origsizeyp) + ' is causing dragons of loading to refuse.';
   exit;
  end;

  // Read the palette.
  setlength(PNGlist[PNGindex].pal, 16);
  for ivar := 0 to 15 do with PNGlist[PNGindex].pal[ivar] do begin
   r := byte((loader + lofs)^) and $F0; inc(lofs);
   g := byte((loader + lofs)^) and $F0; inc(lofs);
   b := byte((loader + lofs)^) and $F0; inc(lofs);
  end;

  UnpackMAG3Graphic(PNGindex);
 end;

 // Did we get the image?
 if PNGlist[PNGindex].bitmap = NIL then begin
  Decomp_Magv3 := 'failed to load image';
  exit;
 end;

 // If the image has a transparent palette index, it must be marked.
 // The transparent index is almost always 8, and usually applies only to
 // sprites and animations, but there are exceptions. I think the original
 // engines apply transparency only at runtime, so there's nothing in the
 // graphic files themselves to indicate the presence of transparency. So we
 // have no choice but to hardcode this stuff.
 xparency := $FFFF;

 // Common names...
 if (imunamu = 'MS_CUR')
 or (imunamu = 'TIARE_P')
 or (imunamu = 'MARU1') or (imunamu = 'MARU2') or (imunamu = 'MARU3')
 or (imunamu = 'TB_008') // completely transparent graphic!
 or (PNGlist[PNGindex].seqlen <> 0)
 then xparency := 8 else

 if imunamu = 'PUSH2' then xparency := $F else

 case game of
   gid_3SIS, gid_3SIS98:
   if copy(imunamu, 1, 2) = 'ST' then xparency := 8;

   gid_ANGELSCOLLECTION2:
   if (imunamu = 'O4_005') or (imunamu = 'T2_LOGO') or (imunamu = 'T3_LOGO')
   then xparency := 8;

   gid_HOHOEMI:
   if (copy(imunamu, 3, 2) = '_S') or (copy(imunamu, 3, 2) = '_U')
   or (imunamu = 'OP_000_')
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
   else if imunamu = 'OP_001A0' then xparency := $F;

   gid_MAJOKKO:
   if (copy(imunamu, 1, 2) = 'MT') or (copy(imunamu, 1, 2) = 'NO')
   or (imunamu = 'TAITOL') or (imunamu = 'SAKURA')
   then xparency := 8;

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

   gid_TRANSFER98:
   if (copy(imunamu, 1, 3) = 'TT_') or (imunamu = 'TI_135A')
   then xparency := 8
   else if imunamu = 'TB_149A' then xparency := 7;

   gid_TASOGARE:
   if (copy(imunamu, 1, 3) = 'MAP')
   or (copy(imunamu, 1, 3) = 'YO_')
   or (copy(imunamu, 1, 3) = 'YT_') and (imunamu[length(imunamu)] <> 'E')
   or (copy(imunamu, 1, 6) = 'YE_004') and (length(imunamu) = 7)
   or (imunamu = 'YE_006G') or (imunamu = 'YE_028')
   or (imunamu = 'YE_029') or (imunamu = 'YB_012G')
   then xparency := 8;

   gid_VANISH:
   if (copy(imunamu, 1, 3) = 'MC_') or (copy(imunamu, 1, 3) = 'MJ_')
   or (copy(imunamu, 1, 3) = 'MT_') or (copy(imunamu, 1, 2) = 'VM')
   or (copy(imunamu, 1, 3) = 'VT_')
   or (imunamu = 'V_LOGO2')
   then xparency := 8;
 end;

 // Mark the intended image resolution.
 // The originals are all 640x400, but a good chunk of that is wasted in
 // a viewframe. Graphics that are displayed inside the viewframe should use
 // the viewport's size as a resolution; that way SuperSakura can scale
 // them to full window size. As a rule, anything bigger than the viewport
 // (baseres) cannot fit inside the frame, and so should use a 640x400
 // resolution. There are also some smaller graphics, such as falling sakura
 // petals, meant to be used in a 640x400 context.

 ivar := 0;
 if PNGlist[PNGindex].seqlen = 0 then
  if (PNGlist[PNGindex].origsizexp > baseresx)
  or (PNGlist[PNGindex].origsizeyp > baseresy) then inc(ivar);

 if (imunamu = 'TIARE_P')
 or (imunamu = 'MARU1') or (imunamu = 'MARU2') or (imunamu = 'MARU3')
 then inc(ivar);

 case game of
  gid_ANGELSCOLLECTION1: if imunamu = 'TENGO_NO' then inc(ivar);
  gid_FROMH: if (imunamu[1] = 'O') or (imunamu = 'PUSH') then inc(ivar);
  gid_MAJOKKO: if imunamu = 'JURA' then inc(ivar);
  gid_MAYCLUB: if imunamu = 'PRS' then inc(ivar);
  gid_SAKURA, gid_SAKURA98:
    if (imunamu = 'HANKO') or (imunamu = 'SAKURA')
    or (copy(imunamu, 1, 5) = 'AE_19')
    then inc(ivar);
  gid_SETSUJUU: if copy(imunamu, 1, 3) = 'SET' then inc(ivar);
  gid_RUNAWAY, gid_RUNAWAY98: if imunamu = 'OP_013A0' then inc(ivar);
 end;

 if ivar <> 0 then begin
  PNGlist[PNGindex].origresx := 640;
  PNGlist[PNGindex].origresy := 400;
 end;

 {$ifdef enable_hacks}
 // Fix image garbage problems, clip transparent edges...

 if imunamu = 'MS_CUR' then begin
  // Hack: all cursors are 32x32 pixels, use proper frame division
  PNGlist[PNGindex].framewidth := 32;
  PNGlist[PNGindex].frameheight := 32;
 end;
 if imunamu = 'PUSH' then begin
  // Hack: all push anims are 16x16 pixels
  PNGlist[PNGindex].framewidth := 16;
  PNGlist[PNGindex].frameheight := 16;
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
    for ivar := 0 to 15 do sequence[ivar] := (ivar shl 16) or $50;
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
    for ivar := 2 to 11 do sequence[ivar] := sequence[ivar and 1];
    // frames 2+3 for 400 ms, rep x3
    for ivar := 6 to 11 do sequence[ivar] := sequence[ivar] or $20000;
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
    for ivar := 0 to 8 do sequence[ivar] := (ivar shl 16) or $100; // 256 ms
    sequence[9] := $00097FFF; // frame 9 for 32767 ms
    sequence[10] := $0009BFFF; // frame 9 for random(16383) ms
   end;
  end;
  gid_MAJOKKO: begin
   // Hack: cut out garbage pixels
   if imunamu = 'MT01FU' then clippedx := 200;
   // Hack: extrapolate a missing pixel row by copying from one up left
   if imunamu = 'KE_069_1' then begin
    ivar := PNGlist[PNGindex].origsizexp * PNGlist[PNGindex].origsizeyp;
    for jvar := (PNGlist[PNGindex].origsizexp shr 2) - 1 downto 0 do begin
     dec(ivar, 4);
     dword((PNGlist[PNGindex].bitmap + ivar)^) := dword((PNGlist[PNGindex].bitmap + ivar - PNGlist[PNGindex].origsizexp - 1)^);
    end;
    // fix minor remaining discontinuity
    ivar := PNGlist[PNGindex].origsizexp * (PNGlist[PNGindex].origsizeyp - 1);
    dword((PNGlist[PNGindex].bitmap + ivar + 203)^) := $0E0D0C00; // lt leg
    dword((PNGlist[PNGindex].bitmap + ivar + 296)^) := $0F000C0F; // rt leg
    dword((PNGlist[PNGindex].bitmap + ivar + 362)^) := $0F050404; // rt hand
    inc(ivar, 247); // inside legs
    move((PNGlist[PNGindex].bitmap + ivar - PNGlist[PNGindex].origsizexp)^, (PNGlist[PNGindex].bitmap + ivar)^, 9);
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
    jvar := 0;
    for ivar := PNGlist[PNGindex].origsizeyp - 1 downto 0 do begin
     byte((PNGlist[PNGindex].bitmap + jvar)^) := xparency;
     inc(jvar, PNGlist[PNGindex].origsizexp);
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
    for ivar := 0 to 13 do sequence[ivar] := (ivar shl 16) or $64;
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
  for ivar := 1 to PNGlist[PNGindex].origsizeyp - 1 do
   move((PNGlist[PNGindex].bitmap + ivar * PNGlist[PNGindex].origsizexp)^,
        (PNGlist[PNGindex].bitmap + ivar * clippedx)^,
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

 // Set the transparent palette index, if any.
 if xparency < dword(length(tempbmp.palette)) then begin
  tempbmp.palette[xparency].a := 0;
  inc(tempbmp.memformat);
 end;

 // Convert bitmaptype(pic^) into a compressed PNG, saved in bitmap^.
 // The PNG byte size goes into jvar.
 ivar := mcg_MemoryToPng(@tempbmp, @PNGlist[PNGindex].bitmap, @jvar);
 mcg_ForgetImage(@tempbmp);

 if ivar <> 0 then begin
  Decomp_Magv3 := mcg_errortxt;
  if PNGlist[PNGindex].bitmap <> NIL then begin
   freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
  end;
  exit;
 end;

 Decomp_Magv3 := SaveFile(outputfile, PNGlist[PNGindex].bitmap, jvar);
 freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
end;
