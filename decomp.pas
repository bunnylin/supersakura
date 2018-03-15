program SuperSakura_Decompiler;
{                                                                           }
{ SuperSakura Decompiler tool                                               }
{ Copyright 2009-2018 :: Kirinn Bunnylin / Mooncore                         }
{ https://mooncore.eu/ssakura                                               }
{ https://github.com/bunnylin/supersakura                                   }
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
{ ------------------------------------------------------------------------- }
{                                                                           }
{ Targets FPC 3.0.4 for Linux/Win 32/64-bit.                                }
{                                                                           }
{ Compilation dependencies:                                                 }
{ - Various moonlibs                                                        }
{   https://github.com/bunnylin/moonlibs                                    }
{                                                                           }

// This program takes a variety of resources from classic VN games, and
// converts them into standard formats usable by the SuperSakura engine.

// File types converted:
// .OVL JAST/Tiare bytecode
// --> .TXT plain-text SuperSakura script
//
// .GRA JAST/Tiare Pi graphics files
// .MAG/.MAX/.MKI various Maki-chan graphics files
// .G Excellents variant of Pi
// --> .PNG images
//
// .M PMD music files
// .SC5 Recomposer midi files
// --> .MID standard midi files
//
// .DAT/.LST from Nocturnal Illusion and Mayclub
// .LIB/.CAT from PC98 Nocturnal Illusion and Mayclub
// --> various standard resources

{$mode objfpc}
{$ifdef WINDOWS}{$apptype console}{$endif}
{$codepage UTF8}
{$asmmode intel}
{$I-}
{$inline on}
{$WARN 4079 off} // Spurious hints: Converting the operands to "Int64" before
{$WARN 4080 off} // doing the operation could prevent overflow errors.
{$WARN 4081 off}
{$WARN 5090 off} // Variable of a managed type not initialised, supposedly.

// Hacks fix a wide variety of things in the original resources. Some bugs
// are merely cosmetic errors, but a few will break SuperSakura. Turn this
// off only if you want virgin resource conversion for your own purposes.
{$define enable_hacks}

// On case-sensitive filesystems, user experience can be improved by doing
// some extra case-insensitive checks.
{$ifndef WINDOWS}{$define caseshenanigans}{$endif}

uses sysutils, mcgloder, sjisutf8, mcfileio, mccommon;

// Override "decomp" with "ssakura" since this tool is a part of ssakura.
// This is used by GetAppConfigDir to decide on a good config directory.
function truename : ansistring;
begin truename := 'ssakura'; end;

{$include inc/version.inc}

type PNGtype = record
       // image data, only for processing purposes
       bitmap : pointer;
       pal : array of rgbquad;
       // metadata from image header
       namu : string[31];
       origsizexp, origsizeyp : word;
       origresx, origresy : word;
       origofsxp, origofsyp : longint; // pixel values relative to original
       framecount : dword;
       framewidth, frameheight : word;
       seqlen : dword; // animation sequence length
       sequence : array of dword; // 16.16: action/frame . param/delay
       bitflag : byte;
       // 1 - integerscaling only
       // 128 - if set, 32-bit RGBA, else 32-bit RGBx
     end;

var errorcount : dword;

    decomp_param : record
      sourcedir : UTF8string; // the input resources are read from here
      outputdir : UTF8string;
      outputoverride : boolean;
      gidoverride : boolean;
      dobeautify : boolean;
      docomposite : boolean;
      listgames : boolean;
    end;

    PNGcount, newgfxcount : dword;
    // PNGlist[] has image metadata from data.txt and newdata.txt.
    PNGlist : array of PNGtype; // index [0] is a null entry
    // newgfxlist[] has the filename of each image converted this session.
    newgfxlist : array of UTF8string;
    baseresx, baseresy : word;
    songlist : array of string[12];

{$include inc/gidtable.inc} // game ID table with CRC numbers
var game, crctableid : dword;

    filu : file;

procedure PrintError(const wak : UTF8string);
// Unified method of informing the user of errors during Recompile.
// Calling this increases the error counter, so for non-error messages,
// write to console and stdout on your own.
begin
 writeln(wak);
 writeln(stdout, wak);
 inc(errorcount);
end;

// ------------------------------------------------------------------

procedure ResetMemResources;
var ivar : dword;
begin
 PNGcount := 0;
 if length(PNGlist) <> 0 then
  for ivar := length(PNGlist) - 1 downto 0 do
   if PNGlist[ivar].bitmap <> NIL then begin
    freemem(PNGlist[ivar].bitmap); PNGlist[ivar].bitmap := NIL;
   end;
 setlength(PNGlist, 0);
 setlength(PNGlist, 1);
 fillbyte(PNGlist[0], sizeof(PNGtype), 0);

 newgfxcount := 0;
 setlength(newgfxlist, 0);

 setlength(songlist, 0);
end;

function ChibiCRC(const filename : UTF8string) : dword;
// Calculates a Chibi-CRC for the given file.
var ivar, ofs, crcfilesize : dword;
    crcfile : file;
begin
 write(stdout, '[ChibiCRC] ' + filename + ': ');
 ChibiCRC := 0; ivar := 0;
 assign(crcfile, filename);
 filemode := 0; reset(crcfile, 1); // read-only
 ivar := IOresult;
 if ivar <> 0 then begin
  PrintError(errortxt(ivar) + ' trying to read ' + filename);
  exit;
 end;
 crcfilesize := filesize(crcfile);

 ChibiCRC := $ABBACACA + crcfilesize;
 ofs := $100;
 while ofs + 4 < crcfilesize do begin
  seek(crcfile, ofs);
  blockread(crcfile, ivar, 4);
  ChibiCRC := rordword(ChibiCRC xor ivar, 3);
  inc(ofs, ofs shr 2);
 end;

 writeln(stdout, strhex(ChibiCRC));
 close(crcfile);
 while IOresult <> 0 do; // flush
end;

function seekpng(const nam : UTF8string; docreate : boolean) : dword;
// Returns the PNGlist[] index where this name is found. If the name isn't
// listed yet, and docreate is true, the name is added at the end of PNGlist
// and its index is returned.
// The input string must be in uppercase.
// Returns 0 if not found or created.
// (PNGlist is not sorted at this point, so can't use GetPNG.)
begin
 seekpng := PNGcount;
 while seekpng <> 0 do begin
  if PNGlist[seekpng].namu = nam then exit;
  dec(seekpng);
 end;
 // not found!
 if docreate = FALSE then exit;
 // add it as a new slot!
 inc(PNGcount);
 if PNGcount >= dword(length(PNGlist)) then setlength(PNGlist, length(PNGlist) + length(PNGlist) shr 1 + 40);
 fillbyte(PNGlist[PNGcount], sizeof(PNGtype), 0);
 PNGlist[PNGcount].namu := nam;
 seekpng := PNGcount;
end;

function seeknewgfx(const nam : UTF8string) : dword;
// Scans through newgfxlist[] to find a matching name, returns the index.
// The input string must be in uppercase.
// If not found, returns FFFFFFFF.
begin
 seeknewgfx := newgfxcount;
 while seeknewgfx <> 0 do begin
  dec(seeknewgfx);
  if upcase(newgfxlist[seeknewgfx]) = nam then exit;
 end;
 seeknewgfx := $FFFFFFFF;
end;

procedure memcopy(source, destination : pointer; count : dword);
// Rolls "count" bytes from source to destination, with possible overlap.
// (The native FPC move is faster, but can't overlap src+dest regions.)
var movedist : ptruint;
begin
 movedist := abs(destination - source);
 if movedist > count then begin
  // No region overlap, can use optimised move.
  move(source^, destination^, count);
  exit;
 end;

 case movedist of
   0: exit;
   1: ;
   // Copy words.
   2, 3: while count >= 2 do begin
          word(destination^) := word(source^);
          inc(destination, 2); inc(source, 2);
          dec(count, 2);
         end;
   // Copy dwords.
   else while count >= 4 do begin
         dword(destination^) := dword(source^);
         inc(destination, 4); inc(source, 4);
         dec(count, 4);
        end;
 end;
 // Copy leftover bytes.
 while count <> 0 do begin
  byte(destination^) := byte(source^);
  inc(destination); inc(source);
  dec(count);
 end;
end;

procedure Decompress_LZ77(srcp : pointer; srcsize : dword; var outp : pointer; var outsize : dword);
// Attempts to uncompress a SoftDisk-style LZ77 stream from scrp^. Puts the
// result in outp^ and outsize. Caller is responsible for freeing both
// buffers.
var srcend : pointer;
    mycode : dword;
    flagbyte, bitindex, copybytes : byte;
begin
 getmem(outp, 65536);
 outsize := 0;
 srcend := srcp + srcsize;
 flagbyte := 0; bitindex := 1;
 while srcp < srcend do begin
  dec(bitindex);
  if bitindex = 0 then begin
   flagbyte := byte(srcp^); inc(srcp);
   bitindex := 8;
  end;

  if flagbyte and 1 <> 0 then begin
   // literal
   byte((outp + outsize)^) := byte(srcp^);
   inc(srcp); inc(outsize);
  end else begin
   // codeword
   mycode := word(srcp^); inc(srcp, 2);
   if mycode = 0 then break;
   copybytes := (mycode and $F) + 3;
   mycode := mycode shr 4 + outsize and $FFFFF000;
   if mycode >= outsize then dec(mycode, $1000);
   memcopy(outp + mycode - 1, outp + outsize, copybytes);
   inc(outsize, copybytes);
  end;

  flagbyte := flagbyte shr 1;
 end;
end;

procedure CropVoidBorders(PNGindex : dword; xparency : byte);
// If an image has plenty of totally transparent space on any side, it can be
// cropped out, but for a single-pixel wide transparent border.
var clipleft, clipright, cliptop, clipbottom : dword;
    ivar : dword;
    srcp, endp : pointer;
begin
 clipleft := 0; clipright := 0; cliptop := 0; clipbottom := 0;
 with PNGlist[PNGindex] do begin

  endp := bitmap + origsizexp * origsizeyp - 1;
  // Bottom: check for transparent rows, by scanning pixels from the end of
  // the image until a non-transparent is found.
  srcp := endp;
  while (srcp > bitmap) and (byte(srcp^) = xparency) do dec(srcp);
  // Calculate the total transparent pixels.
  ivar := endp - srcp;
  // Calculate the total full rows of transparent pixels.
  clipbottom := ivar div origsizexp;

  // Top: check for transparent rows, by scanning pixels from the start of
  // the image until a non-transparent is found.
  srcp := bitmap;
  while (srcp < endp) and (byte(srcp^) = xparency) do inc(srcp);
  // Calculate the total transparent pixels.
  ivar := srcp - bitmap;
  // Calculate the total full rows of transparent pixels.
  cliptop := ivar div origsizexp;

  // Check if there's anything left of the image.
  if cliptop + clipbottom >= origsizeyp then begin
   origsizexp := 1; origsizeyp := 1;
   framewidth := 1; frameheight := 1;
   exit;
  end;

  // Left: check for transparent columns...
  ivar := 0;
  repeat
   if ivar = 0 then begin // new column
    srcp := bitmap + cliptop * origsizexp + clipleft;
    ivar := origsizeyp - cliptop - clipbottom;
    inc(clipleft);
   end;
   dec(ivar);
   if srcp >= endp then break;
   if byte(srcp^) <> xparency then break;
   inc(srcp, origsizexp);
  until FALSE;
  dec(clipleft);

  // Right: check for transparent columns...
  ivar := 0;
  repeat
   if ivar = 0 then begin // new column
    srcp := endp - clipbottom * origsizexp - clipright;
    ivar := origsizeyp - cliptop - clipbottom;
    inc(clipright);
   end;
   dec(ivar);
   if srcp <= bitmap then break;
   if byte(srcp^) <> xparency then break;
   dec(srcp, origsizexp);
  until FALSE;
  dec(clipright);

  // Leave single-pixel transparent borders even if cropping the rest.
  if clipleft > 0 then dec(clipleft);
  if clipright > 0 then dec(clipright);
  if cliptop > 0 then dec(cliptop);
  if clipbottom > 0 then dec(clipbottom);
  writeln(stdout, 'Clipped from ',origsizexp,'x',origsizeyp,'@',origofsxp,',',origofsyp,' by L:',clipleft,' R:',clipright,' T:',cliptop,' B:',clipbottom);

  // Put the new size in the frame dimensions.
  framewidth := origsizexp - clipleft - clipright;
  frameheight := origsizeyp - cliptop - clipbottom;

  // Copy the image data without resizing the buffer or anything.
  endp := bitmap;
  srcp := bitmap + cliptop * origsizexp + clipleft;
  for ivar := frameheight - 1 downto 0 do begin
   // (must use memcopy instead of FPC's move since if clipping is minimal
   // then srcp and endp may cause an overlapping transfer.)
   memcopy(srcp, endp, framewidth);
   inc(endp, framewidth);
   inc(srcp, origsizexp);
  end;

  // Save the new dimensions and top left offset.
  inc(origofsxp, longint(clipleft));
  inc(origofsyp, longint(cliptop));
  origsizexp := framewidth;
  origsizeyp := frameheight;
 end;
end;

procedure RearrangeFrames(PNGindex : dword);
// Rearranges an animation frame grid so that frames are stacked vertically.
// All frames must be the exact same dimensions. The image must be 8bpp.
var poku, srcp, destp : pointer;
    scanline, x, y, hframes, vframes : dword;
begin
 with PNGlist[PNGindex] do begin
  if (framewidth = 0) or (frameheight = 0)
  or (framewidth > origsizexp) or (frameheight > origsizeyp) then begin
   PrintError('bad frame size');
   exit;
  end;

  framecount := 0;
  hframes := origsizexp div framewidth;
  vframes := origsizeyp div frameheight;
  getmem(poku, origsizexp * origsizeyp);
  destp := poku;
  for x := 0 to hframes - 1 do begin
   for y := 0 to vframes - 1 do begin
    srcp := bitmap + y * frameheight * origsizexp + x * framewidth;
    for scanline := frameheight - 1 downto 0 do begin
     move(srcp^, destp^, framewidth);
     inc(srcp, origsizexp);
     inc(destp, framewidth);
    end;
    inc(framecount);
   end;
  end;
  freemem(bitmap); bitmap := poku; poku := NIL;
  origsizexp := framewidth;
  origsizeyp := frameheight * hframes * vframes;
 end;
end;

// ------------------------------------------------------------------

// Decompiling functions for specific input file types.
{$include inc/decomp_jastovl.pas}
{$include inc/decomp_excellents.pas}
{$include inc/decomp_makichan.pas}
{$include inc/decomp_pi.pas}
{$include inc/decomp_excellentg.pas}
{$include inc/decomp_music.pas}

// Forward declaration of DispatchFile, so bundle decompile functions can
// redispatch bundle contents.
function DispatchFile(srcfile : UTF8string) : dword; forward;

{$include inc/decomp_bundles.pas}

// ------------------------------------------------------------------

procedure WriteMetaData;
// Writes data.txt.
var metafile : text;
    ivar, jvar : dword;
    txt : string;
begin
 assign(metafile, decomp_param.outputdir + 'data.txt');
 filemode := 1; rewrite(metafile); // write-only
 ivar := IOresult;
 if ivar <> 0 then PrintError(errortxt(ivar) + ' trying to write ' + decomp_param.outputdir + 'data.txt')
 else begin
  writeln(stdout, 'Writing ', decomp_param.outputdir, 'data.txt');
  writeln(metafile, '// Graphic details and animation data');
  writeln(metafile, 'baseres ', strdec(baseresx), 'x', strdec(baseresy));
  if game <> gid_UNKNOWN then
   writeln(metafile, 'desc ', CRCid[crctableid].desc);
  if PNGcount <> 0 then begin
   for ivar := 1 to PNGcount do with PNGlist[ivar] do
   if ((origofsxp or origofsyp or longint(seqlen)) <> 0)
   or (framecount > 1)
   or (origresx or origresy <> 0)
   then begin
    writeln(metafile);
    writeln(metafile, 'file ', namu);
    if (origofsxp or origofsyp) <> 0 then
    writeln(metafile, 'ofs ', strdec(origofsxp), ',', strdec(origofsyp));
    if (origresx or origresy) <> 0 then
    writeln(metafile, 'res ', strdec(origresx), 'x', strdec(origresy));
    if bitflag and 1 <> 0 then writeln(metafile, 'integerscaling');
    if bitflag and 4 <> 0 then writeln(metafile, 'dontresize');
    if framecount > 1 then writeln(metafile, 'framecount ', strdec(framecount));
    if seqlen <> 0 then begin

     // Print the unpacked animation sequence
     txt := 'sequence';
     for jvar := 0 to seqlen - 1 do begin
      if length(txt) >= 70 then begin
       writeln(metafile, txt); txt := 'sequence';
      end;
      // index
      txt := txt + ' ' + strdec(jvar) + ':';
      if sequence[jvar] and $80000000 <> 0 then txt := txt + 'jump ';
      // frame
      if sequence[jvar] and $40000000 <> 0 then txt := txt + 'r';
      if sequence[jvar] and $20000000 <> 0 then txt := txt + 'v';
      txt := txt + strdec((sequence[jvar] shr 16) and $1FFF);
      // delay
      if sequence[jvar] and $80000000 = 0 then begin
       txt := txt + ',';
       case (sequence[jvar] and $FFFF) of
        $8000..$BFFF: txt := txt + 'r'+ strdec(sequence[jvar] and $3FFF);
        $C000..$FFFE: txt := txt + 'v'+ strdec(sequence[jvar] and $3FFF);
        $FFFF: txt := txt + 'stop';
        else txt := txt + strdec(sequence[jvar] and $7FFF);
       end;
      end;
      txt := txt + ';';
     end;
     writeln(metafile, txt);

    end;
   end;
  end;

  close(metafile);
 end;
end;

procedure ProcessMetaData(const srcfilu : UTF8string);
// Reads data.txt. This is mostly identical to the same procedure in Recomp.
var ivar, jvar : dword;
    ffilu : text;
    line : UTF8string;
    lvar : longint;
    PNGindex : dword;
    linenumber, lineofs : dword;

  procedure Error(const quack : string);
  begin
   PrintError(srcfilu + ' (' + strdec(linenumber) + '): ' + quack);
  end;

begin
 // for error reporting
 linenumber := 0;
 // init default values
 PNGindex := 0;
 assign(ffilu, srcfilu);
 filemode := 0; reset(ffilu); // read-only access
 ivar := IOresult;
 if ivar = 2 then begin
  writeln(stdout, srcfilu + ' doesn''t exist yet.');
  exit;
 end;
 if ivar <> 0 then begin
  PrintError(errortxt(ivar) + ' reading ' + srcfilu);
  exit;
 end;
 writeln(stdout, 'Reading ', srcfilu);

 // Parse the file
 while eof(ffilu) = FALSE do begin

  // Get the new line
  readln(ffilu, line);
  inc(linenumber);

  // Line comments using //
  ivar := pos('//', line);
  if ivar <> 0 then setlength(line, ivar - 1);
  // Line comments using #
  ivar := pos('#', line);
  if ivar <> 0 then setlength(line, ivar - 1);

  // Remove trailing spaces
  while (length(line) <> 0) and (ord(line[length(line)]) <= 32) do setlength(line, length(line) - 1);
  // Skip preceding spaces
  lineofs := 1;
  while (lineofs <= dword(length(line))) and (ord(line[lineofs]) <= 32) do inc(lineofs);
  // If the leftover is an empty string, skip to next line
  if lineofs > dword(length(line)) then continue;

  // Transform to all lowercase
  line := lowercase(line);

  // Line specifies a filename that following lines apply to?
  if MatchString(line, 'file ', lineofs) then begin
   // safeties
   ivar := pos('.', line);
   if ivar <> 0 then begin
    Error('Dots not allowed in filenames');
    setlength(line, ivar - 1);
   end;
   if length(line) - lineofs + 1 > 31 then begin
    Error('Filename too long (max 31 bytes)');
   end;
   // Get the PNGlist index for saving this metadata, or create one.
   // (Seekpng is a linear search, defined somewhere above.)
   line := upcase(copy(line, lineofs, 31));
   PNGindex := seekpng(line, TRUE);
   continue;
  end;

  // Offset for an image's top left corner
  if MatchString(line, 'ofs ', lineofs) then begin
   PNGlist[PNGindex].origofsxp := CutNumberFromString(line, lineofs);
   PNGlist[PNGindex].origofsyp := CutNumberFromString(line, lineofs);
   continue;
  end;

  // Intended image resolution
  if MatchString(line, 'res ', lineofs) then begin
   PNGlist[PNGindex].origresx := CutNumberFromString(line, lineofs);
   PNGlist[PNGindex].origresy := CutNumberFromString(line, lineofs);
   continue;
  end;

  // Number of frames in the image
  if MatchString(line, 'framecount ', lineofs) then begin
   PNGlist[PNGindex].framecount := CutNumberFromString(line, lineofs);
   if PNGlist[PNGindex].framecount = 0 then inc(PNGlist[PNGindex].framecount);
   continue;
  end;

  // Animation frame sequence, pairs of FRAME:DELAY
  if MatchString(line, 'sequence ', lineofs) then begin
   // Parse the sequence string
   while lineofs <= dword(length(line)) do begin
    // sequence index
    ivar := abs(CutNumberFromString(line, lineofs));
    if ivar > 8191 then ivar := 8191;
    if ivar >= dword(length(PNGlist[PNGindex].sequence)) then setlength(PNGlist[PNGindex].sequence, (ivar + 16) and $FFF0);
    if ivar >= PNGlist[PNGindex].seqlen then PNGlist[PNGindex].seqlen := ivar + 1;
    // frame number to display or jump command
    jvar := 0;
    while (lineofs <= dword(length(line))) and (line[lineofs] in ['0'..'9','j','r','v'] = FALSE) do inc(lineofs);
    if line[lineofs] = 'j' then begin
     jvar := $80000000; // jump
     inc(lineofs);
    end;
    while (lineofs <= dword(length(line))) and (line[lineofs] in ['0'..'9','j','r','v'] = FALSE) do inc(lineofs);
    case line[lineofs] of
     'r': jvar := jvar or $40000000; // random
     'v': jvar := jvar or $20000000; // variable
    end;
    while (lineofs <= dword(length(line))) and (line[lineofs] in ['0'..'9','+','-'] = FALSE) do inc(lineofs);
    if (jvar = $80000000) and (line[lineofs] in ['+','-'])
    then lvar := ivar + dword(CutNumberFromString(line, lineofs)) // relative jump
    else lvar := abs(CutNumberFromString(line, lineofs)); // non-relative
    jvar := jvar or dword((lvar and $1FFF) shl 16);
    if jvar and $80000000 = 0 then begin
     // delay value
     while (lineofs <= dword(length(line))) and (line[lineofs] in ['0'..'9','s','r','v'] = FALSE) do inc(lineofs);
     case line[lineofs] of
      // stop at this frame
      's': jvar := jvar or $FFFF;
      // random delay, top bits 10
      'r': jvar := jvar or $8000 or dword(CutNumberFromString(line, lineofs) and $3FFF);
      // delay from variable, top bits 11
      'v': jvar := jvar or $C000 or dword(CutNumberFromString(line, lineofs) and $3FFF);
      // absolute delay value, top bit 0
      else jvar := jvar or dword(CutNumberFromString(line, lineofs) and $7FFF);
     end;
    end;
    // Save the packed action:frame:delay into sequence[]
    PNGlist[PNGindex].sequence[ivar] := jvar;
    // Skip ahead until the next entry on the line
    while (lineofs <= dword(length(line))) and (line[lineofs] in ['0'..'9'] = FALSE) do inc(lineofs);
   end;
   continue;
  end;
  // Integer-scaling flag
  if MatchString(line, 'integerscaling', lineofs) then begin
   PNGlist[PNGindex].bitflag := PNGlist[PNGindex].bitflag or 1;
   continue;
  end;
  // Forbid resizing flag
  if MatchString(line, 'dontresize', lineofs) then begin
   PNGlist[PNGindex].bitflag := PNGlist[PNGindex].bitflag or 4;
   continue;
  end;

  if MatchString(line, 'baseres ', lineofs) then continue;
  if MatchString(line, 'desc ', lineofs) then continue;

  // Unknown command!
  Error('Unknown command: ' + line);
 end;

 close(ffilu);
end;

// ------------------------------------------------------------------

// Image compositing/beautifying functions. Call PostProcess to do all.
{$include inc/decomp_postproc.pas}

procedure SelectGame(newnum : dword);
var ivar : dword;
begin
 // New recognised game, do a general state reset.
 ResetMemResources;
 game := CRCID[newnum].gidnum;
 crctableid := newnum;
 writeln('Game: ' + CRCID[newnum].desc);
 writeln(stdout, 'Game: ' + CRCID[newnum].desc);
 baseresx := CRCID[newnum].baseresx;
 baseresy := CRCID[newnum].baseresy;
 while IOresult <> 0 do ; // flush

 // Decide on a suitable project output directory.
 if decomp_param.outputoverride = FALSE then begin
  decomp_param.outputdir := 'data' + DirectorySeparator + CRCID[newnum].namu;
  if DirectoryExists(decomp_param.outputdir) = FALSE then begin
   writeln(stdout, 'mkdir ' + decomp_param.outputdir);
   mkdir(decomp_param.outputdir);
   ivar := IOresult;
   if ivar = 5 then begin
    // access denied? Try putting the output under the user's profile...
    decomp_param.outputdir := GetAppConfigDir(FALSE) + decomp_param.outputdir;
    writeln(stdout, 'access denied, so mkdir ' + decomp_param.outputdir);
    mkdir(decomp_param.outputdir);
   end;
  end;
 end;
 while IOresult <> 0 do ; // flush

 if copy(decomp_param.outputdir, length(decomp_param.outputdir), 1) <> DirectorySeparator
 then decomp_param.outputdir := decomp_param.outputdir + DirectorySeparator;

 writeln('Output directory: ', decomp_param.outputdir);
 writeln(stdout, 'Output directory: ', decomp_param.outputdir);

 // Read the metadata file, if it exists.
 ProcessMetaData(decomp_param.outputdir + 'data.txt');
end;

procedure GetStuffFromExe(const exefilename : UTF8string);
// Reads an executable file and extracts useful data, like animation frames
// or music file lists.
// The executable's game ID must be known before calling.
var loader : TFileLoader;
    poku : pointer;
    txt : UTF8string;
    songnamu : string[15];
    ivar, jvar : dword;
    songlistofs, animdataofs : dword;
begin
 loader := TFileLoader.Open(exefilename);

 try
 // Extract constant data from the EXE
 songlistofs := 0; animdataofs := 0;
 songnamu := '';
 setlength(songlist, 0);
 case game of
  gid_3SIS: begin setlength(songlist, 24); animdataofs := $15AD0; end;
  gid_3SIS98: begin setlength(songlist, 24); animdataofs := $146B0; end;
  gid_ANGELSCOLLECTION1: begin setlength(songlist, 30); end;
  gid_ANGELSCOLLECTION2: begin songlistofs := $137E8; setlength(songlist, 30); end;
  gid_DEEP: begin songlistofs := $1EB43; setlength(songlist, 47); end;
  gid_EDEN: begin setlength(songlist, 20); end;
  gid_FROMH: begin setlength(songlist, 28); end;
  gid_HOHOEMI: begin songlistofs := $1A2BC; setlength(songlist, 30); end;
  gid_MAJOKKO: begin songlistofs := $182E8; setlength(songlist, 30); end;
  gid_MARIRIN: begin setlength(songlist, 26); end;
  gid_RUNAWAY: begin setlength(songlist, 22); animdataofs := $162B0; end;
  gid_RUNAWAY98: begin setlength(songlist, 22); animdataofs := $15030; end;
  gid_SAKURA: begin setlength(songlist, 33); end;
  gid_SAKURA98: begin setlength(songlist, 33); end;
  gid_SETSUJUU: begin songlistofs := $1466F; setlength(songlist, 22); animdataofs := $15816; end;
  gid_TASOGARE: begin songlistofs := $1B3AA; setlength(songlist, 27); end;
  gid_TRANSFER98: begin setlength(songlist, 40); animdataofs := $159CC; end;
  gid_VANISH: begin {songlistofs := $19CDC;} setlength(songlist, 15); end;
 end;

 // Enumerate songs
 case game of
  gid_3SIS, gid_3SIS98: songnamu := 'SS_';
  gid_ANGELSCOLLECTION1: songnamu := 'T';
  gid_EDEN: songnamu := 'EK_';
  gid_FROMH: songnamu := '';
  gid_MARIRIN: songnamu := 'MR_';
  gid_RUNAWAY, gid_RUNAWAY98: songnamu := 'MT_';
  gid_SAKURA, gid_SAKURA98: songnamu := 'SK_';
  gid_TRANSFER98: songnamu := 'TEN0';
  gid_VANISH: songnamu := 'VP0';
 end;
 if (length(songlist) <> 0) and (songlistofs = 0) then
  for ivar := high(songlist) downto 0 do
  if ivar < 9 then songlist[ivar] := songnamu + '0' + strdec(ivar + 1)
  else songlist[ivar] := songnamu + strdec(ivar + 1);
 //if game = gid_TRANSFER98 then songlist[39] := 'TRAIN';

 // Extract songs, if applicable
 if songlistofs <> 0 then begin
  for ivar := high(songlist) downto 0 do byte(songlist[ivar][0]) := 0;
  ivar := 0;
  while ivar < dword(length(songlist)) do begin
   if loader.ReadByteFrom(songlistofs) = 0 then begin
    // crop out the extension
    while (length(songlist[ivar]) <> 0)
    and (songlist[ivar][length(songlist[ivar])] <> '.')
    do dec(byte(songlist[ivar][0]));
    dec(byte(songlist[ivar][0]));
    inc(ivar);
   end else
    songlist[ivar] := songlist[ivar] + char(loader.ReadByteFrom(songlistofs));
   inc(songlistofs);
  end;
  writeln(stdout, 'Extracted songlist, ' + strdec(length(songlist)) + ' entries.');
  for ivar := 0 to high(songlist) do writeln(stdout, ivar,':',songlist[ivar]);
 end;

 // Extract animation data.
 if animdataofs <> 0 then begin
  loader.ofs := animdataofs;
  getmem(poku, 178);

  // Snowcat and Tenkousei use a modified format.
  if game in [gid_SETSUJUU, gid_TRANSFER98] then begin
   jvar := 0;
   case game of // baseline address for name strings
    gid_SETSUJUU: jvar := $14340;
    gid_TRANSFER98: jvar := $13E50;
   end;
   repeat
    // read the animation sequence length (word) + 32 more words.
    move(loader.readp^, poku^, 66);
    inc(loader.readp, 66);
    // invalid sequence length means we're done.
    if (word(poku^) > $FF) or (dword(poku^) = 0) then break;
    // read the rest of the animation record.
    move(loader.readp^, (poku + 38)^, 140);
    inc(loader.readp, 140);
    // read the animation file name.
    move(loader.PtrAt(jvar + word((poku + 2)^))^, songnamu[1], 9);
    // find the null to determine string length.
    for ivar := 1 to 9 do
     if songnamu[ivar] = chr(0) then begin
      byte(songnamu[0]) := ivar - 1;
      break;
     end;
    // an empty animation name means we're done.
    if songnamu = '' then break;
    // find the PNGlist[] entry for this, or create one.
    songnamu := upcase(songnamu);
    ivar := seekpng(songnamu, TRUE);
    // convert and save the animation data into PNGlist[].
    if byte((poku + 2)^) <> 0 then ChewAnimations(poku, ivar);
   until FALSE;
  end

  // Other games use a more common format
  else begin
   repeat
    move(loader.readp^, poku^, 178);
    inc(loader.readp, 178);
    // 0 seqlen or 0 name? We're done
    if (word(poku^) = 0) or (word((poku + 2)^) = 0) then break;
    // grab the animation name.
    move((poku + 2)^, songnamu[1], 9);
    // find the null to determine string length.
    for ivar := 1 to 9 do
     if songnamu[ivar] = chr(0) then begin
      byte(songnamu[0]) := ivar - 1;
      break;
     end;
    // find the PNGlist[] entry for this, or create one.
    songnamu := upcase(songnamu);
    ivar := seekpng(songnamu, TRUE);
    // convert and save the animation data into PNGlist[].
    ChewAnimations(poku, ivar);
   until FALSE;
  end;

  freemem(poku); poku := NIL;
 end;

 // Tenkousei has some scripts embedded in the executable...
 if game = gid_TRANSFER98 then begin
  txt := 'Extracting bytecode from TK.EXE...';
  writeln(txt); writeln(stdout, txt);
  loader.ofs := $14FC6;
  loader.size := $14FC6 + $9A5; // up to excluding $1596B
  Decomp_JastOvl(loader, decomp_param.outputdir + 'scr' + DirectorySeparator + 'tkexe.txt');
 end;

 finally
  if loader <> NIL then loader.free;
  loader := NIL;
 end;
end;

function ScanEXE(const exenamu : UTF8string) : dword;
// Compares the Chibi-CRC of the file by the given path+name to the known
// list in CRCID[]. Returns a CRCID[] index if match found, otherwise FFFF.
// While at it, if the EXE is recognised, this also scans it for song name
// enumerations and animation data.
var ivar, jvar : dword;
begin
 ivar := ChibiCRC(exenamu);
 ScanEXE := $FFFF;
 for jvar := length(CRCID) - 1 downto 0 do
  if CRCID[jvar].CRC = ivar then begin
   ScanEXE := jvar; break;
  end;
 if ScanEXE = $FFFF then exit;

 if (decomp_param.gidoverride = FALSE)
 and (game <> CRCID[ScanEXE].gidnum) then begin
  // Dump metadata and tweak graphics, if we've found a new recognised game
  // after a previous one.
  if game <> gid_UNKNOWN then PostProcess;
  SelectGame(ScanEXE);
 end;

 GetStuffFromExe(exenamu);
end;

// ------------------------------------------------------------------

function DispatchFile(srcfile : UTF8string) : dword;
// Forwards the given file to an appropriate conversion routine. File type
// identification depends on the currently identified game ID and file
// suffix.
// Returns 1 if attempted to convert the file, 0 if skipped file.
var basename, suffix : UTF8string;
    isagraphic : boolean;
begin
 DispatchFile := 0;
 write(stdout, srcfile, ': ');

 suffix := lowercase(ExtractFileExt(srcfile));
 basename := ExtractFileName(srcfile);
 basename := upcase(copy(basename, 1, length(basename) - length(suffix)));
 isagraphic := FALSE;

 case suffix of
   // === Scripts ===
   '.ovl':
   case game of
     gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2, gid_MARIRIN, gid_DEEP,
     gid_SETSUJUU, gid_TRANSFER98, gid_3SIS, gid_3SIS98, gid_EDEN, gid_FROMH,
     gid_HOHOEMI, gid_VANISH, gid_RUNAWAY, gid_RUNAWAY98, gid_SAKURA,
     gid_SAKURA98, gid_MAJOKKO, gid_TASOGARE, gid_PARFAIT:
     Decomp_JastOvl(TFileLoader.Open(srcfile), decomp_param.outputdir + 'scr' + DirectorySeparator + basename + '.txt');
   end;

   '.s':
   case game of
     gid_MAYCLUB, gid_MAYCLUB98, gid_NOCTURNE, gid_NOCTURNE98:
     Decomp_ExcellentS(TFileLoader.Open(srcfile), decomp_param.outputdir + 'scr' + DirectorySeparator + basename + '.txt');
   end;

   // === Graphics ===
   '.gra':
   case game of
     gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2, gid_MARIRIN, gid_DEEP,
     gid_SETSUJUU, gid_TRANSFER98, gid_3SIS, gid_3SIS98, gid_EDEN, gid_FROMH,
     gid_HOHOEMI, gid_VANISH, gid_RUNAWAY, gid_RUNAWAY98, gid_SAKURA,
     gid_SAKURA98, gid_MAJOKKO, gid_TASOGARE:
     begin
      Decomp_Pi(TFileLoader.Open(srcfile), decomp_param.outputdir + 'gfx' + DirectorySeparator + basename + '.png');
      isagraphic := TRUE;
     end;
   end;

   '.mki', '.mag', '.max':
   begin
    Decomp_Makichan(TFileLoader.Open(srcfile), decomp_param.outputdir + 'gfx' + DirectorySeparator + basename + '.png');
    isagraphic := TRUE;
   end;

   '.g':
   case game of
     gid_NOCTURNE, gid_NOCTURNE98, gid_MAYCLUB, gid_MAYCLUB98:
     begin
      Decomp_ExcellentG(TFileLoader.Open(srcfile), decomp_param.outputdir + 'gfx' + DirectorySeparator + basename + '.png');
      isagraphic := TRUE;
     end;
   end;

   // === Music ===
   '.m':
   Decomp_dotM(TFileLoader.Open(srcfile), decomp_param.outputdir + 'aud' + DirectorySeparator + basename + '.mid');

   '.sc5':
   Decomp_SC5(TFileLoader.Open(srcfile), decomp_param.outputdir + 'aud' + DirectorySeparator + basename + '.mid');

   // === Bundles ===
   '.dat':
   case game of
     gid_NOCTURNE, gid_MAYCLUB:
     // must be accompanied by a .lst file
     Decomp_ExcellentDAT(TFileLoader.Open(srcfile), copy(srcfile, 1, length(srcfile) - 3) + 'lst', decomp_param.outputdir);
   end;

   '.lib':
   case game of
     gid_NOCTURNE98, gid_MAYCLUB98:
     // must be accompanied by a .cat file
     Decomp_ExcellentLib(TFileLoader.Open(srcfile), copy(srcfile, 1, length(srcfile) - 3) + 'cat', decomp_param.outputdir);
   end;
 end;

 // Present the file dispatch result.
  writeln(stdout, 'ok');
  if isagraphic then begin
   if newgfxcount >= dword(length(newgfxlist)) then setlength(newgfxlist, length(newgfxlist) shl 1 + 64);
   newgfxlist[newgfxcount] := basename;
   inc(newgfxcount);
  end;
end;

procedure ProcessFiles(srcdir : UTF8string);
var filuhits : dword;

  procedure ProcessDir(const currentsearch : UTF8string; onlyexes : boolean);
  var filusr : TSearchRec;
      exelist, dirlist, filulist : array of UTF8string;
      execount, dircount, filucount : dword;
      curdir : UTF8string;
      searchresult : longint;
  begin
   writeln(stdout, '----------------------------------------------------------------------');
   writeln(stdout, 'scanning ' + currentsearch);
   setlength(exelist, 0);
   setlength(dirlist, 0);
   setlength(filulist, 0);
   execount := 0; dircount := 0; filucount := 0;
   // Figure out what directory the current search is in.
   curdir := ExtractFilePath(currentsearch);

   // Build a list of files and directories matched by the current search.
   searchresult := FindFirst(currentsearch, faReadOnly or faDirectory, filusr);
   while searchresult = 0 do begin
    // directories...
    if (filusr.Attr and faDirectory <> 0) then begin
     if (onlyexes = FALSE)
     and (filusr.Name <> '.') and (filusr.Name <> '..') then begin
      if dircount >= dword(length(dirlist)) then setlength(dirlist, length(dirlist) shl 1 + 4);
      dirlist[dircount] := filusr.Name;
      inc(dircount);
     end;
    end
    // executables...
    else if lowercase(ExtractFileExt(filusr.Name)) = '.exe' then begin
     if execount >= dword(length(exelist)) then setlength(exelist, length(exelist) shl 1 + 4);
     exelist[execount] := filusr.Name;
     inc(execount);
    end
    // other files...
    else if onlyexes = FALSE then begin
     if filucount >= dword(length(filulist)) then setlength(filulist, length(filulist) shl 1 + 16);
     filulist[filucount] := filusr.Name;
     inc(filucount);
    end;

    searchresult := FindNext(filusr);
   end;
   FindClose(filusr);

   if (execount or dircount or filucount) = 0 then writeln(stdout, 'No hits.');

   // Examine the executables for game identification.
   while execount <> 0 do begin
    dec(execount);
    ScanEXE(curdir + exelist[execount]);
   end;

   // If there are potentially convertable files, but we haven't identified
   // the game yet, and no executables were included in the search, then
   // check the current directory specifically for executables.
   if (filucount <> 0) and (game = gid_UNKNOWN) and (execount = 0) then begin
    writeln(stdout, 'Checking current directory for game exe');
    ProcessDir(curdir + '*', TRUE);
   end;

   // If there are potentially convertable files, but we haven't identified
   // the game yet, and the current directory is a known game data
   // subdirectory, then check the parent directory for executables.
   if (filucount <> 0) and (game = gid_UNKNOWN) then begin
    if (lowercase(copy(curdir, length(curdir) - 4, 5)) = DirectorySeparator + 'gra' + DirectorySeparator)
    or (lowercase(copy(curdir, length(curdir) - 4, 5)) = DirectorySeparator + 'ovl' + DirectorySeparator)
    then begin
     writeln(stdout, 'Checking parent directory for game exe');
     ProcessDir(copy(curdir, 1, length(curdir) - 4) + '*', TRUE);
    end;
   end;

   // Examine the individual files for convertables.
   while filucount <> 0 do begin
    dec(filucount);
    inc(filuhits, DispatchFile(curdir + filulist[filucount]));
   end;

   // Scan subdirectories, if any.
   while dircount <> 0 do begin
    dec(dircount);
    ProcessDir(curdir + dirlist[dircount] + DirectorySeparator + '*', FALSE);
   end;

   writeln(stdout, '----------------------------------------------------------------------');
  end;

begin
 if srcdir = '' then begin
  writeln('Nothing to do.');
  writeln(stdout, 'Nothing to do.');
  exit;
 end;

 // Find and process input resources.
 filuhits := 0;
 ProcessDir(ExpandFileName(srcdir), FALSE);
 if filuhits = 0 then PrintError('No input files found.')
 else begin
  writeln('Total input files: ', filuhits);
  writeln(stdout, 'Total input files: ', filuhits);
 end;

 // Dump metadata, composite and beautify graphics, etc.
 if (game <> gid_UNKNOWN) then PostProcess;
end;

// ------------------------------------------------------------------

function DoInits : boolean;
// Sets up a logging file, an output data file, etc preparations.
// Returns true if all good, or false if anything went wrong.
var ivar : dword;
    txt : UTF8string;
begin
 DoInits := FALSE;
 OnGetApplicationName := @truename;
 ResetMemResources;
 game := gid_UNKNOWN;
 crctableid := 0;

 // Create a basic logging file...
 // Try the current working directory first.
 assign(stdout, 'decomp.log');
 filemode := 1; rewrite(stdout); // write-only
 ivar := IOresult;
 if not ivar in [0,5] then begin
  writeln(errortxt(ivar) + ' trying to write decomp.log in current directory');
  exit;
 end;
 if ivar = 5 then begin
  // Access denied: fall back to the user's profile directory.
  txt := GetAppConfigDir(FALSE); // false means user-specific, not global
  mkdir(txt);
  while IOresult <> 0 do ; // flush
  assign(stdout, txt + 'decomp.log');
  filemode := 1; rewrite(stdout); // write-only
  ivar := IOresult;
  if ivar <> 0 then begin
   writeln(errortxt(ivar) + ' trying to write decomp.log under profile at ' + txt);
   exit;
  end;
 end;
 while IOresult <> 0 do ; // flush

 // Create a data directory.
 if DirectoryExists('data') = FALSE then begin
  mkdir('data');
  if IOresult = 5 then begin
   // Access denied: fall back to the user's profile directory.
   mkdir(GetAppConfigDir(FALSE));
   mkdir(GetAppConfigDir(FALSE) + 'data');
  end;
 end;
 while IOresult <> 0 do ; // flush

 if decomp_param.sourcedir <> '' then begin
  writeln('Input files: ', decomp_param.sourcedir);
  writeln(stdout, 'Input files: ', decomp_param.sourcedir);
 end;

 if decomp_param.gidoverride then SelectGame(game);

 DoInits := TRUE;
end;

procedure DoCleanup;
var ivar : dword;
    txt : string;
begin
 // Give the user a summary of what happened
 if errorcount = 0 then txt := 'Finished, no errors.'
 else txt := 'Finished, ' + strdec(errorcount) + ' errors! See decomp.log.';
 writeln(txt); writeln(stdout, txt);

 // Make sure memory is freed.
 if length(PNGlist) <> 0 then
  for ivar := length(PNGlist) - 1 downto 0 do
   if PNGlist[ivar].bitmap <> NIL then begin
    freemem(PNGlist[ivar].bitmap); PNGlist[ivar].bitmap := NIL;
   end;

 // Close the log file and get ready to quit.
 close(stdout);
end;

function DoParams : boolean;
// Processes the recomp commandline. Returns FALSE in case of errors etc.
var txt : UTF8string;
    ivar, jvar : longint;
begin
 DoParams := TRUE;
 with decomp_param do begin
  sourcedir := '';
  outputdir := 'data' + DirectorySeparator + 'unknown' + DirectorySeparator;
  outputoverride := FALSE;
  gidoverride := FALSE;
  dobeautify := FALSE;
  docomposite := TRUE;
  listgames := FALSE;
 end;

 ivar := 0;
 while ivar < paramcount do begin
  inc(ivar);
  txt := paramstr(ivar);
  if (txt = '?') or (txt = '/?') then DoParams := FALSE else

  if txt[1] = '-' then begin
   jvar := 2;
   // handle double-dash prefix
   if txt[2] = '-' then inc(jvar);
   // help: -? -h -H -help
   if ((length(txt) = jvar) and (txt[jvar] in ['?','h','H']))
   or ((length(txt) = jvar + 3) and (lowercase(copy(txt, jvar, 4)) = 'help'))
   then DoParams := FALSE

   else if (lowercase(copy(txt, jvar, length(txt))) = 'b')
   or (lowercase(copy(txt, jvar, length(txt))) = 'beautify')
     then decomp_param.dobeautify := TRUE

   else if (lowercase(copy(txt, jvar, length(txt))) = 'l')
   or (lowercase(copy(txt, jvar, length(txt))) = 'list')
     then decomp_param.listgames := TRUE

   else if (lowercase(copy(txt, jvar, length(txt))) = 'nocomp')
     then decomp_param.docomposite := FALSE

   else if (lowercase(copy(txt, jvar, 3)) = 'id=') then begin
     txt := lowercase(copy(txt, jvar + 3, length(txt)));
     game := gid_UNKNOWN;
     for jvar := high(CRCID) downto 1 do
      if (txt = lowercase(CRCID[jvar].namu)) or (txt = strdec(CRCID[jvar].gidnum))
      then begin game := jvar; break; end;
     if game <> gid_UNKNOWN then decomp_param.gidoverride := TRUE
     else writeln('Unrecognised ID. Use either project name or gid number from -list.');
   end

   else if (lowercase(copy(txt, jvar, 4)) = 'out=') then begin
     decomp_param.outputdir := ExpandFileName(copy(txt, jvar + 4, length(txt)));
     decomp_param.outputoverride := TRUE;
   end

   else begin
    writeln('Unrecognised option: ', paramstr(ivar));
    DoParams := FALSE; exit;
   end;
  end

  else begin
   if decomp_param.sourcedir = '' then decomp_param.sourcedir := paramstr(ivar)
   else begin
    writeln('Unrecognised parameter: ', paramstr(ivar));
    DoParams := FALSE; exit;
   end;
  end;
 end;

 // Print the supported game list if requested.
 if decomp_param.listgames then begin
  writeln;
  writeln('Supported games:');
  for ivar := 1 to high(CRCID) do begin
   case CRCID[ivar].level of
    0: write('      ');
    1: write('[*]   ');
    2: write('[**]  ');
    3: write('[***] ');
    4: write('[###] ');
    else write('[?]   ');
   end;
   writeln(CRCID[ivar].gidnum:2, ' ', CRCID[ivar].desc);
  end;
  writeln('[ ] none  [*] resources only  [**] playable  [***] completable  [###] polished');
  writeln;
  if DoParams then exit;
 end;

 // If no parameters are present or no source files were specified, then
 // there's nothing to do; show the help text.
 if (paramcount = 0) or (decomp_param.sourcedir = '') then DoParams := FALSE;

 if DoParams then exit;

 writeln;
 writeln('  SuperSakura Game Decompiler');
 writeln('------------------------------- ' + SSver + ' --');
 writeln('Usage: decomp <input directory or files> [-options]');
 writeln;
 writeln('This tool converts resources from various old games into newer standard files.');
 writeln('After converting the resources, you can edit them and repack them using the');
 writeln('Recomp tool into a single data file that the SuperSakura engine can use.');
 writeln;
 writeln('You can convert individual files or everything under a directory, for example:');
 writeln('decomp ~/Games/3sis/OVL/SK_9*.OVL');
 writeln('decomp "E:\games\Sakura no Kisetsu\"');
 writeln;
 writeln('The converted files are written in game-specific sub-directories under');
 writeln('a "data" directory. The data directory is by default created in your current');
 writeln('working directory, or if that is write-protected, then in your home/profile');
 writeln('directory under "ssakura".');
 writeln;
 writeln('Options:');
 writeln('-out=directory     Override the output directory');
 writeln('-id=game           Override game identification');
 writeln('-b                 Beautify input graphics while converting');
 writeln('-nocomp            Don''t composite multipart graphics, save them unmodified');
 writeln('-list              Print game compatibility list');
end;

begin
 if DoParams = FALSE then exit;
 if DoInits = FALSE then exit;

 // Find and process source files
 ProcessFiles(decomp_param.sourcedir);

 DoCleanup;
end.
