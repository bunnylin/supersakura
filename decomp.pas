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

type DecompException = class(Exception);

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

var PNGcount, newgfxcount : dword;
    // PNGlist[] has image metadata from data.txt and newdata.txt.
    PNGlist : array of PNGtype; // index [0] is a null entry
    // newgfxlist[] has the filename of each image converted this session.
    newgfxlist : array of UTF8string;
    baseresx, baseresy : word;
    songlist : array of string[12];

    decomp_param : record
      sourcedir : UTF8string; // the input resources are read from here
      outputdir : UTF8string;
      filetypeoverride : dword;
      outputoverride : boolean;
      gidoverride : boolean;
      dobeautify : boolean;
      docomposite : boolean;
      listgames : boolean;
      listtypes : boolean;
    end;

    decomp_stats : record
      numfiles : dword;
      numconverted : dword;
      numskipped : dword;
      numerrors : dword;
    end;

{$include inc/gidtable.inc} // game ID table with CRC numbers
var game, crctableid : dword;

    filu : file; // used by decomp_music, todo: replace with SaveFile()

procedure PrintError(const wak : UTF8string);
// Unified method of informing the user of errors during Recompile.
// Calling this increases the error counter, so for non-error messages,
// write to console and stdout on your own.
begin
 writeln(wak);
 writeln(stdout, wak);
 inc(decomp_stats.numerrors);
end;

// ------------------------------------------------------------------

procedure ResetMemResources;
var i : dword;
begin
 PNGcount := 0;
 if length(PNGlist) <> 0 then
  for i := length(PNGlist) - 1 downto 0 do with PNGlist[i] do
   if bitmap <> NIL then begin
    freemem(bitmap); bitmap := NIL;
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
var i, ofs, crcfilesize : dword;
    crcfile : file;
begin
 write(stdout, '[ChibiCRC] ' + filename + ': ');
 ChibiCRC := 0; i := 0;
 assign(crcfile, filename);
 filemode := 0; reset(crcfile, 1); // read-only
 i := IOresult;
 if i <> 0 then begin
  PrintError(errortxt(i) + ' trying to read ' + filename);
  exit;
 end;
 crcfilesize := filesize(crcfile);

 ChibiCRC := $ABBACACA + crcfilesize;
 ofs := $100;
 while ofs + 4 < crcfilesize do begin
  seek(crcfile, ofs);
  blockread(crcfile, i, 4);
  ChibiCRC := rordword(ChibiCRC xor i, 3);
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

// ------------------------------------------------------------------

procedure WriteMetaData;
// Writes data.txt.
var metafile : text;
    i, j : dword;
    metafilename, txt : UTF8string;
begin
 metafilename := decomp_param.outputdir + 'data.txt';
 assign(metafile, metafilename);
 filemode := 1; rewrite(metafile); // write-only
 i := IOresult;
 if i <> 0 then
  PrintError(errortxt(i) + ' trying to write ' + metafilename)
 else begin
  writeln(stdout, 'Writing ', metafilename);

  writeln(metafile, '// Graphic details and animation data');
  writeln(metafile, 'baseres ', strdec(baseresx), 'x', strdec(baseresy));

  if game <> gid_UNKNOWN then
   writeln(metafile, 'desc ', CRCid[crctableid].desc);

  if PNGcount <> 0 then begin
   for i := 1 to PNGcount do with PNGlist[i] do
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
     for j := 0 to seqlen - 1 do begin
      if length(txt) >= 70 then begin
       writeln(metafile, txt);
       txt := 'sequence';
      end;
      // index
      txt := txt + ' ' + strdec(j) + ':';
      if sequence[j] and $80000000 <> 0 then txt := txt + 'jump ';
      // frame
      if sequence[j] and $40000000 <> 0 then txt := txt + 'r';
      if sequence[j] and $20000000 <> 0 then txt := txt + 'v';
      txt := txt + strdec((sequence[j] shr 16) and $1FFF);
      // delay
      if sequence[j] and $80000000 = 0 then begin
       txt := txt + ',';
       case (sequence[j] and $FFFF) of
        $8000..$BFFF: txt := txt + 'r'+ strdec(sequence[j] and $3FFF);
        $C000..$FFFE: txt := txt + 'v'+ strdec(sequence[j] and $3FFF);
        $FFFF: txt := txt + 'stop';
        else txt := txt + strdec(sequence[j] and $7FFF);
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

// ------------------------------------------------------------------

procedure ProcessMetaData(const srcfilu : UTF8string);
// Reads data.txt. This is mostly identical to the same procedure in Recomp.
var ffilu : text;
    line : UTF8string;
    i, j : dword;
    l : longint;
    PNGindex : dword;
    linenumber, lineofs : dword;

  procedure Error(const quack : UTF8string);
  begin
   PrintError(srcfilu + ' (' + strdec(linenumber) + '): ' + quack);
  end;

begin
 // Init default values...
 PNGindex := 0;
 assign(ffilu, srcfilu);
 filemode := 0; reset(ffilu); // read-only access
 i := IOresult;
 if i = 2 then begin
  writeln(stdout, srcfilu + ' doesn''t exist yet.');
  exit;
 end;
 if i <> 0 then begin
  PrintError(errortxt(i) + ' reading ' + srcfilu);
  exit;
 end;
 writeln(stdout, 'Reading ', srcfilu);
 linenumber := 0;

 // Parse the file...
 while eof(ffilu) = FALSE do begin

  // Get the new line.
  readln(ffilu, line);
  inc(linenumber);

  // Drop line comments using //
  i := pos('//', line);
  if i <> 0 then setlength(line, i - 1);
  // Drop line comments using #
  i := pos('#', line);
  if i <> 0 then setlength(line, i - 1);
  // Trim whitespace.
  line := trim(line);
  if line = '' then continue;
  // Transform to all lowercase.
  line := lowercase(line);
  lineofs := 1;

  // Line specifies a filename that following lines apply to?
  if MatchString(line, 'file ', lineofs) then begin
   // safeties
   i := pos('.', line);
   if i <> 0 then begin
    Error('Dots not allowed in filenames');
    setlength(line, i - 1);
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

  // Offset for an image's top left corner.
  if MatchString(line, 'ofs ', lineofs) then begin
   PNGlist[PNGindex].origofsxp := CutNumberFromString(line, lineofs);
   PNGlist[PNGindex].origofsyp := CutNumberFromString(line, lineofs);
   continue;
  end;

  // Intended image resolution.
  if MatchString(line, 'res ', lineofs) then begin
   PNGlist[PNGindex].origresx := CutNumberFromString(line, lineofs);
   PNGlist[PNGindex].origresy := CutNumberFromString(line, lineofs);
   continue;
  end;

  // Number of frames in the image.
  if MatchString(line, 'framecount ', lineofs) then begin
   PNGlist[PNGindex].framecount := CutNumberFromString(line, lineofs);
   if PNGlist[PNGindex].framecount = 0 then inc(PNGlist[PNGindex].framecount);
   continue;
  end;

  // Animation frame sequence, pairs of FRAME:DELAY.
  if MatchString(line, 'sequence ', lineofs) then begin
   // Parse the sequence string...
   while lineofs <= dword(length(line)) do begin
    // sequence index
    i := abs(CutNumberFromString(line, lineofs));
    if i > 8191 then i := 8191;
    if i >= dword(length(PNGlist[PNGindex].sequence)) then setlength(PNGlist[PNGindex].sequence, (i + 16) and $FFF0);
    if i >= PNGlist[PNGindex].seqlen then PNGlist[PNGindex].seqlen := i + 1;
    // frame number to display or jump command
    j := 0;
    while (lineofs <= dword(length(line))) and (line[lineofs] in ['0'..'9','j','r','v'] = FALSE) do inc(lineofs);
    if line[lineofs] = 'j' then begin
     j := $80000000; // jump
     inc(lineofs);
    end;
    while (lineofs <= dword(length(line))) and (line[lineofs] in ['0'..'9','j','r','v'] = FALSE) do inc(lineofs);
    case line[lineofs] of
     'r': j := j or $40000000; // random
     'v': j := j or $20000000; // variable
    end;
    while (lineofs <= dword(length(line))) and (line[lineofs] in ['0'..'9','+','-'] = FALSE) do inc(lineofs);
    if (j = $80000000) and (line[lineofs] in ['+','-'])
    then l := i + dword(CutNumberFromString(line, lineofs)) // relative jump
    else l := abs(CutNumberFromString(line, lineofs)); // non-relative
    j := j or dword((l and $1FFF) shl 16);
    if j and $80000000 = 0 then begin
     // delay value
     while (lineofs <= dword(length(line))) and (line[lineofs] in ['0'..'9','s','r','v'] = FALSE) do inc(lineofs);
     case line[lineofs] of
      // stop at this frame
      's': j := j or $FFFF;
      // random delay, top bits 10
      'r': j := j or $8000 or dword(CutNumberFromString(line, lineofs) and $3FFF);
      // delay from variable, top bits 11
      'v': j := j or $C000 or dword(CutNumberFromString(line, lineofs) and $3FFF);
      // absolute delay value, top bit 0
      else j := j or dword(CutNumberFromString(line, lineofs) and $7FFF);
     end;
    end;
    // Save the packed action:frame:delay into sequence[].
    PNGlist[PNGindex].sequence[i] := j;
    // Skip ahead until the next entry on the line.
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

// Decompilers may need to redispatch bundle contents etc.
procedure DispatchFile(const srcfile : UTF8string); forward;

// Image compositing/beautifying functions. Call PostProcess to do all.
{$include inc/decomp_postproc.pas}

// Decompiling functions for specific input file types.
{$include inc/decomp_jastovl.pas}
{$include inc/decomp_excellents.pas}
{$include inc/decomp_makichan.pas}
{$include inc/decomp_pi.pas}
{$include inc/decomp_music.pas}
{$include inc/decomp_exe.pas}
{$include inc/decomp_bundles.pas}

// ------------------------------------------------------------------

procedure DispatchFile(const srcfile : UTF8string);
// Forwards the given file to an appropriate conversion routine. File type
// identification depends on the currently identified game ID and file
// suffix.
var loader : TFileLoader;
    basename, suffix : UTF8string;
    isagraphic : boolean;
begin
 inc(decomp_stats.numfiles);
 write(stdout, srcfile, ': ');

 suffix := lowercase(ExtractFileExt(srcfile));
 basename := ExtractFileName(srcfile);
 basename := upcase(copy(basename, 1, length(basename) - length(suffix)));
 isagraphic := FALSE;

 try try
 loader := TFileLoader.Open(srcfile);

 case suffix of
   // === Executables ===
   '.exe':
   Decomp_Exe(loader);

   // === Scripts ===
   '.ovl':
   case game of
     gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2, gid_MARIRIN, gid_DEEP,
     gid_SETSUJUU, gid_TRANSFER98, gid_3SIS, gid_3SIS98, gid_EDEN, gid_FROMH,
     gid_HOHOEMI, gid_VANISH, gid_RUNAWAY, gid_RUNAWAY98, gid_SAKURA,
     gid_SAKURA98, gid_MAJOKKO, gid_TASOGARE, gid_PARFAIT:
     Decomp_JastOvl(loader, decomp_param.outputdir + 'scr' + DirectorySeparator + basename + '.txt');
   end;

   '.s':
   case game of
     gid_MAYCLUB, gid_MAYCLUB98, gid_NOCTURNE, gid_NOCTURNE98:
     Decomp_ExcellentS(loader, decomp_param.outputdir + 'scr' + DirectorySeparator + basename + '.txt');
   end;

   // === Graphics ===
   '.gra':
   case game of
     gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2, gid_MARIRIN, gid_DEEP,
     gid_SETSUJUU, gid_TRANSFER98, gid_3SIS, gid_3SIS98, gid_EDEN, gid_FROMH,
     gid_HOHOEMI, gid_VANISH, gid_RUNAWAY, gid_RUNAWAY98, gid_SAKURA,
     gid_SAKURA98, gid_MAJOKKO, gid_TASOGARE:
     begin
      Decomp_Pi(loader, decomp_param.outputdir + 'gfx' + DirectorySeparator + basename + '.png');
      isagraphic := TRUE;
     end;
   end;

   '.mki', '.mag', '.max':
   begin
    Decomp_Makichan(loader, decomp_param.outputdir + 'gfx' + DirectorySeparator + basename + '.png');
    isagraphic := TRUE;
   end;

   '.pi':
   begin
    Decomp_Pi(loader, decomp_param.outputdir + 'gfx' + DirectorySeparator + basename + '.png');
    isagraphic := TRUE;
   end;

   '.g':
   case game of
     gid_NOCTURNE, gid_NOCTURNE98, gid_MAYCLUB, gid_MAYCLUB98:
     begin
      Decomp_Pi(loader, decomp_param.outputdir + 'gfx' + DirectorySeparator + basename + '.png');
      isagraphic := TRUE;
     end;
   end;

   // === Music ===
   '.m':
   Decomp_dotM(loader, decomp_param.outputdir + 'aud' + DirectorySeparator + basename + '.mid');

   '.sc5':
   Decomp_SC5(loader, decomp_param.outputdir + 'aud' + DirectorySeparator + basename + '.mid');

   // === Bundles ===
   '.dat':
   case game of
     gid_NOCTURNE, gid_MAYCLUB:
     // must be accompanied by a .lst file
     Decomp_ExcellentDAT(loader, copy(srcfile, 1, length(srcfile) - 3) + 'lst', decomp_param.outputdir);
   end;

   '.lib':
   case game of
     gid_NOCTURNE98, gid_MAYCLUB98:
     // must be accompanied by a .cat file
     Decomp_ExcellentLib(loader, copy(srcfile, 1, length(srcfile) - 3) + 'cat', decomp_param.outputdir);
   end;
 end;

 // Present the file dispatch result.
 writeln(stdout, 'ok');
 if isagraphic then begin
  if newgfxcount >= dword(length(newgfxlist)) then setlength(newgfxlist, length(newgfxlist) shl 1 + 64);
  newgfxlist[newgfxcount] := basename;
  inc(newgfxcount);
 end;

 inc(decomp_stats.numconverted);

 except
  on E : DecompException do begin
   inc(decomp_stats.numerrors);
   writeln(stdout, E.Message);
  end;
  on E : Exception do begin
   inc(decomp_stats.numerrors);
   writeln(stdout, 'Error!');
   raise;
  end;
 end;

 finally
  if loader <> NIL then loader.free;
  loader := NIL;
 end;
end;

// ------------------------------------------------------------------

procedure SelectGame(newnum : dword);
var i : dword;
begin
 // Dump metadata and tweak graphics, if starting to work on a new recognised
 // game after a previous recognised game.
 if game <> gid_UNKNOWN then PostProcess;

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
   i := IOresult;
   if i = 5 then begin
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

// ------------------------------------------------------------------

procedure ScanFiles(srcdir : UTF8string);

  procedure ScanExe(const exenamu : UTF8string);
  // Compares the given exe file's Chibi-CRC to the known list in CRCID[].
  // If the exe is recognised, sends it to the dispatcher.
  var execrc, i : dword;
  begin
   execrc := ChibiCRC(exenamu);
   for i := length(CRCID) - 1 downto 0 do
    if CRCID[i].CRC = execrc then begin
     // Match found!
     if (decomp_param.gidoverride = FALSE) and (game <> CRCID[i].gidnum)
     then SelectGame(i);
     // Dispatch the executable for extraction.
     DispatchFile(exenamu);
     exit;
    end;
  end;

  procedure ScanDir(const currentsearch : UTF8string; onlyexes : boolean);
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
    ScanDir(curdir + '*', TRUE);
   end;

   // If there are potentially convertable files, but we haven't identified
   // the game yet, and the current directory is a known game data
   // subdirectory, then check the parent directory for executables.
   if (filucount <> 0) and (game = gid_UNKNOWN) then begin
    if (lowercase(copy(curdir, length(curdir) - 4, 5)) = DirectorySeparator + 'gra' + DirectorySeparator)
    or (lowercase(copy(curdir, length(curdir) - 4, 5)) = DirectorySeparator + 'ovl' + DirectorySeparator)
    then begin
     writeln(stdout, 'Checking parent directory for game exe');
     ScanDir(copy(curdir, 1, length(curdir) - 4) + '*', TRUE);
    end;
   end;

   // Examine the individual files for convertables.
   while filucount <> 0 do begin
    dec(filucount);
    DispatchFile(curdir + filulist[filucount]);
   end;

   // Scan subdirectories, if any.
   while dircount <> 0 do begin
    dec(dircount);
    ScanDir(curdir + dirlist[dircount] + DirectorySeparator + '*', FALSE);
   end;

   writeln(stdout, '----------------------------------------------------------------------');
  end;

begin
 if srcdir = '' then exit;

 // Find and process input resources.
 ScanDir(ExpandFileName(srcdir), FALSE);

 // Composite and beautify graphics, etc.
 PostProcess;

 WriteMetadata;
end;

// ------------------------------------------------------------------

function DoInits : boolean;
// Sets up a logging file, an output data file, etc preparations.
// Returns true if all good, or false if anything went wrong.
var i : dword;
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
 i := IOresult;
 if not i in [0,5] then begin
  writeln(errortxt(i) + ' trying to write decomp.log in current directory');
  exit;
 end;
 if i = 5 then begin
  // Access denied: fall back to the user's profile directory.
  txt := GetAppConfigDir(FALSE); // false means user-specific, not global
  mkdir(txt);
  while IOresult <> 0 do ; // flush
  assign(stdout, txt + 'decomp.log');
  filemode := 1; rewrite(stdout); // write-only
  i := IOresult;
  if i <> 0 then begin
   writeln(errortxt(i) + ' trying to write decomp.log under profile at ' + txt);
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

 fillbyte(decomp_stats, sizeof(decomp_stats), 0);

 if decomp_param.sourcedir <> '' then begin
  writeln('Input files: ', decomp_param.sourcedir);
  writeln(stdout, 'Input files: ', decomp_param.sourcedir);
 end;

 if decomp_param.gidoverride then SelectGame(game);

 DoInits := TRUE;
end;

procedure DoCleanup;
var i : dword;
    txt : UTF8string;
begin
 // Give the user a summary of what happened
 if decomp_stats.numconverted + decomp_stats.numerrors = 0 then
  PrintError('No convertable files found.')
 else begin
  txt := 'Files found: ' + strdec(decomp_stats.numfiles);
  writeln(txt); writeln(stdout, txt);
  txt := 'Files converted: ' + strdec(decomp_stats.numconverted);
  writeln(txt); writeln(stdout, txt);
  txt := 'Files skipped: ' + strdec(decomp_stats.numskipped);
  writeln(txt); writeln(stdout, txt);
  if decomp_stats.numerrors = 0 then txt := 'No errors.'
  else txt := strdec(decomp_stats.numerrors) + ' errors! See decomp.log.';
  writeln(txt); writeln(stdout, txt);
 end;

 // Make sure memory is freed.
 if length(PNGlist) <> 0 then
  for i := length(PNGlist) - 1 downto 0 do with PNGlist[i] do
   if bitmap <> NIL then begin
    freemem(bitmap); bitmap := NIL;
   end;

 // Close the log file and get ready to quit.
 close(stdout);
end;

function DoParams : boolean;
// Processes the recomp commandline. Returns FALSE in case of errors etc.
var txt, switch : UTF8string;
    i, j : longint;
begin
 DoParams := TRUE;
 with decomp_param do begin
  sourcedir := '';
  outputdir := 'data' + DirectorySeparator + 'unknown' + DirectorySeparator;
  filetypeoverride := 0;
  outputoverride := FALSE;
  gidoverride := FALSE;
  dobeautify := FALSE;
  docomposite := TRUE;
  listgames := FALSE;
  listtypes := FALSE;
 end;

 i := 0;
 while i < paramcount do begin
  inc(i);
  txt := paramstr(i);
  if (i = 1) and ((txt = '?') or (txt = '/?')) then DoParams := FALSE else

  if txt[1] = '-' then begin
   j := 2;
   // handle double-dash prefix
   if txt[2] = '-' then inc(j);

   switch := lowercase(copy(txt, j, length(txt)));

   // help: -? -h -H -help
   if ((length(txt) = j) and (txt[j] in ['?','h','H'])) or (switch = 'help')
   then DoParams := FALSE

   else if (switch = 'b') or (switch = 'beautify')
    then decomp_param.dobeautify := TRUE

   else if (switch = 'l') or (switch = 'list') or (switch = 'listgames')
    then decomp_param.listgames := TRUE

   else if (switch = 'listtypes')
    then decomp_param.listtypes := TRUE

   else if (switch = 'nocomp')
    then decomp_param.docomposite := FALSE

   else if (copy(switch, 1, 3) = 'id=') then begin
    txt := copy(switch, 4, length(switch));
    game := gid_UNKNOWN;
    for j := high(CRCID) downto 1 do
     if (txt = lowercase(CRCID[j].namu)) or (txt = strdec(CRCID[j].gidnum))
     then begin game := j; break; end;
    if game <> gid_UNKNOWN then decomp_param.gidoverride := TRUE
    else begin
     writeln('Unrecognised ID. Use either project name or gid number from -list.');
     DoParams := FALSE; exit;
    end;
   end

   else if (copy(switch, 1, 5) = 'type=') then begin
    decomp_param.filetypeoverride := valx(copy(switch, 6, length(switch)));
   end

   else if (copy(switch, 1, 4) = 'out=') then begin
    decomp_param.outputdir := ExpandFileName(copy(txt, j + 4, length(txt)));
    decomp_param.outputoverride := TRUE;
   end

   else begin
    writeln('Unrecognised option: ', paramstr(i));
    DoParams := FALSE; exit;
   end;
  end

  else begin
   if decomp_param.sourcedir = '' then decomp_param.sourcedir := paramstr(i)
   else begin
    writeln('Unrecognised parameter: ', paramstr(i));
    DoParams := FALSE; exit;
   end;
  end;
 end;

 // Print the supported file type list if requested.
 if decomp_param.listtypes then begin
  DoParams := FALSE; exit;
 end;

 // Print the supported game list if requested.
 if decomp_param.listgames then begin
  writeln;
  writeln('Supported games:');
  for i := 1 to high(CRCID) do begin
   case CRCID[i].level of
     0: write('      ');
     1: write('[*]   ');
     2: write('[**]  ');
     3: write('[***] ');
     4: write('[###] ');
     else write('[?]   ');
   end;
   writeln(CRCID[i].gidnum:2, ' ', CRCID[i].desc);
  end;
  writeln('[ ] none  [*] resources only  [**] playable  [***] completable  [###] polished');
  writeln;
  DoParams := FALSE; exit;
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
 writeln('-out=<directory>   Override the output directory');
 writeln('-id=<game>         Override game identification');
 writeln('-type=<type>       Override the input file type auto-detection');
 writeln('-listtypes         Print convertable file type list');
 writeln('-b                 Beautify input graphics while converting');
 writeln('-nocomp            Don''t composite multipart graphics, save them unmodified');
 writeln('-list              Print game compatibility list');
end;

begin
 if DoParams = FALSE then exit;
 if DoInits = FALSE then exit;

 AddExitProc(@DoCleanup);
 // Find and process source files.
 ScanFiles(decomp_param.sourcedir);
end.
