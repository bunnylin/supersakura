program Recompiler;
{                                                                           }
{ Mooncore Super Resource Recompiler tool                                   }
{ Copyright 2009-2017 :: Kirinn Bunnylin / Mooncore                         }
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

// Output DAT-file specs (words stored x86-style LSB first):
//
// Header:
// DWORD : signature $CACABAAB
// BYTE : file format version, must be 3
// DWORD : banner image offset, or zero for none
// BYTE : byte length of parent name string
// CHARS : parent name string, UTF-8
// BYTE : byte length of dat description string
// CHARS : description string, UTF-8
// BYTE : byte length of version string
// CHARS : version string, UTF-8
//
// Followed by a series of data blocks...
// each has DWORD-SIG, DWORD-DATALEN, then DATA of said length.
//
// SCRIPT BYTECODE : signature $501E0BB0
//   block size : DWORD;
//   uncompressed stream size : DWORD;
//
//   followed by a single ZLib-compressed script stream, containing...
//   array of record
//     label name : ministring up to 63 bytes;
//     next label : ministring up to 63 bytes;
//     codesize : dword; (uncompressed byte size)
//     code : array[codesize] of bytecode;
//   end;
//
// STRING SET : signature $511E0BB0
//   block size : DWORD;
//   uncompressed stream size : DWORD;
//
//   followed by a single ZLib-compressed string stream, containing...
//   language description : UTF-8 ministring;
//   array of record
//     labelnamu : UTF-8 ministring;
//     stringcount : DWORD;
//     stringblock : array of record
//       stringlength : DWORD;
//       string : array[1..stringlength] of BYTE;
//     end;
//     terminator $FFFFFFFF : DWORD;
//   end;
//   terminator 0 : BYTE;
//
// MIDI MUSIC : signature $521E0BB0
//   block size : DWORD;
//   WORD : number of entries
//   followed by ... all midi files, compressed?
//
// PNG IMAGE : signature $531E0BB0
//   block size : DWORD;
//   Followed by metadata...
//     namu : ministring up to 31 bytes;
//     origresx, origresy : word;
//     origsizexp, origsizeyp : word;
//     origofsxp, origofsyp : longint;
//     framecount : dword;
//     seqlen : dword;
//     sequence : array[0..seqlen-1] of dword
//     bitflag : byte;
//   Followed by the PNG file without the first 2 DWORDS (redundant sig)
//
// OGG SOUND : signature $541E0BB0
//   block size : DWORD;
//   name : ministring up to 31 bytes;
//   followed by ... the OGG file?
//
// FLAC SOUND : signature $551E0BB0
//   block size : DWORD;
//   name : ministring up to 31 bytes;
//   followed by ... the FLAC file?
//
// Base resolution values : signature $5F1E0BB0
//   block size : DWORD;
//   BaseResX, BaseResY : word - the preferred resolution for this game

{$mode fpc}
{$ifdef WINDOWS}{$apptype console}{$endif}
{$codepage UTF8}
{$asmmode intel}
{$I-}
{$inline on}
{$WARN 4079 off} // Spurious hints: Converting the operands to "Int64" before
{$WARN 4080 off} // doing the operation could prevent overflow errors.
{$WARN 4081 off}

uses sysutils, mcgloder, mcsassm, mccommon;

// Override "recomp" with "ssakura" since this tool is a part of ssakura.
// This is used by GetAppConfigDir to decide on a good config directory.
function truename : ansistring;
begin truename := 'ssakura'; end;

{$include inc/version.inc}
const fileversion : byte = 3; // this is stored in the output DAT file header

var errorcount : dword;
    filu : file;
    filubuffy : pointer; // output is first built in memory into this buffer
    filubuffyofs, filubuffysize : dword;

    // The script counter is informative only, and counts how many script
    // text files have been read. The scrlist array can have a totally
    // different size, since it stores labels, not script files.
    SCRcount : dword;
    // The PNG counter tracks the number of valid PNG files in PNGlist,
    // excluding the null 0 index. This counter allows growing PNGlist in
    // large efficient chunks, as images are added.
    PNGcount : dword;
    // Human-readable description string for the dat being built.
    projectdesc : UTF8string;
    // The metadata file may specify one of the graphics in the dat-file as
    // a banner. While saving the graphics, the absolute offset to the named
    // file will be remembered and is saved in the dat-file's header.
    bannerimagename : UTF8string;
    bannerimageofs : dword;

    recomp_param : record
      projectname : UTF8string; // the project name, also default src/out
      parentname : UTF8string; // mods must have a parent project
      sourcedir : UTF8string; // the resources being built are read from here
      outputfile : UTF8string; // the packed resources go in this one file
      dumpstrings : UTF8string; // the string table is dumped in this file
      loadfile : UTF8string; // packed resource file to read before building
    end;

procedure PrintError(const wak : UTF8string);
// Unified method of informing the user of errors during Recompile.
// Calling this increases the error counter, so for non-error messages,
// write to console and stdout on your own.
begin
 writeln(wak);
 writeln(stdout, wak);
 inc(errorcount);
end;

// Uncomment this when compiling with HeapTrace. Call this whenever to test
// if at that moment the heap has yet been messed up.
{procedure CheckHeap;
var poku : pointer;
begin
 QuickTrace := FALSE;
 getmem(poku, 4); freemem(poku); poku := NIL;
 QuickTrace := TRUE;
end;}

procedure flushbuffy;
// Dumps the current contents of the intermediate output buffer onto disk.
var ivar : dword;
begin
 blockwrite(filu, filubuffy^, filubuffyofs);
 ivar := IOresult;
 if ivar <> 0 then PrintError(errortxt(ivar) + ' trying to write into output file.');
 filubuffyofs := 0;
end;

procedure writebuffy(srcp : pointer; datalen : dword);
// Use this to write your data into the intermediate file output buffer.
// If the buffer's max size draws near, the buffer is dumped into the file.
// The data length can be bigger than the buffy size, no worries.
var ivar : dword;
begin
 if filubuffyofs + datalen >= filubuffysize then flushbuffy;
 if datalen > filubuffysize then begin
  blockwrite(filu, srcp^, datalen);
  ivar := IOresult;
  if ivar <> 0 then PrintError(errortxt(ivar) + ' trying to write into output file.');
 end
 else begin
  move(srcp^, (filubuffy + filubuffyofs)^, datalen);
  inc(filubuffyofs, datalen);
 end;
end;

function seekpng(const nam : UTF8string) : dword;
// Returns the PNGlist index where this name is found.
// Returns 0 if not found.
// PNGlist is not sorted at this point, so can't use GetPNG.
begin
 seekpng := PNGcount;
 while seekpng <> 0 do begin
  if PNGlist[seekpng].namu = nam then exit;
  dec(seekpng);
 end;
end;

function FindFile_caseless(const namu : UTF8string; isdir : boolean) : UTF8string;
// Tries to find the given filename using a case-insensitive search.
// If isdir is TRUE, looks for a directory instead of a file.
// Wildcards not supported. The path still has to be case-correct. :(
// This can be used to find a single specific file on *nixes without knowing
// the exact case used in the filename.
// Returns the full case-correct path+name, or an empty string if not found.
// If multiple identically-named, differently-cased files exist, returns
// whichever FindFirst picks up first.
var filusr : TSearchRec;
    basedir, basename : UTF8string;
    findresult : longint;
begin
 FindFile_caseless := '';
 basename := lowercase(ExtractFileName(namu));
 basedir := copy(namu, 1, length(namu) - length(basename));
 findresult := faReadOnly;
 if isdir then findresult := findresult or faDirectory;

 findresult := FindFirst(basedir + '*', findresult, filusr);
 while findresult = 0 do begin
  if lowercase(filusr.Name) = basename then
  if (isdir = FALSE) or (filusr.Attr and faDirectory <> 0)
  then begin
   FindFile_caseless := basedir + filusr.Name;
   break;
  end;
  findresult := FindNext(filusr);
 end;
 FindClose(filusr);
end;

{$include inc/ssscript.pas}

procedure ProcessScript(const srcfilu : UTF8string);
var gnamu : UTF8string;
    infilu : file;
    readbuf : pointer;
    readbufsize : dword;
    ivar : dword;
    errorlist : pointer;
begin
 writeln(stdout, srcfilu);
 while IOresult <> 0 do ; // flush

 // First get the file name, without ".txt"
 // The uppercased base file name is used to refer to the script
 gnamu := ExtractFileName(srcfilu);
 gnamu := upcase(copy(gnamu, 1, length(gnamu) - 4));
 if length(gnamu) > 31 then begin
  PrintError(srcfilu + ': file name too long (max 31 bytes)');
  gnamu := copy(gnamu, 1, 31);
 end;

 // Read the file
 assign(infilu, srcfilu);
 filemode := 0; reset(infilu, 1); // read-only
 ivar := IOresult;
 if ivar <> 0 then begin
  PrintError(srcfilu + ': ' + errortxt(ivar) + ' trying to open');
  exit;
 end;
 readbufsize := filesize(infilu) + 1; // leave space for an extra linebreak
 getmem(readbuf, readbufsize);
 blockread(infilu, readbuf^, readbufsize - 1);
 ivar := IOresult;
 close(infilu);
 if ivar <> 0 then begin
  PrintError(srcfilu + ': ' + errortxt(ivar) + ' trying to read');
  freemem(readbuf); readbuf := NIL;
  exit;
 end;
 // Add a linebreak at the end in case there wasn't one before
 byte((readbuf + readbufsize - 1)^) := $D;

 // Pack the script into our script and string arrays.
 // (Scripts are saved label by label, and each script file may contain
 // multiple labels, so CompileScript needs to decide which array indexes
 // everything goes to.)
 errorlist := CompileScript(gnamu, readbuf, readbuf + readbufsize);
 freemem(readbuf); readbuf := NIL;
 inc(SCRcount);

 // If we got a null pointer, all went well.
 if errorlist = NIL then exit;

 // Otherwise we got a buffy of error ministrings.
 ivar := 0;
 while byte((errorlist + ivar)^) <> 0 do begin
  PrintError(string((errorlist + ivar)^));
  inc(ivar, byte((errorlist + ivar)^) + byte(1));
 end;
 freemem(errorlist); errorlist := NIL;
end;

procedure ProcessPng(const srcfilu : UTF8string);
var gnamu : UTF8string;
    infilu : file;
    workimu : bitmaptype;
    ivar, filusize : dword;
    minibuf : array[0..31] of byte;
    PNGindex : longint;

  procedure Error(const quack : string);
  begin
   PrintError(srcfilu + ': ' + quack);
  end;

begin
 writeln(stdout, srcfilu);
 while IOresult <> 0 do ; // flush
 minibuf[0] := 0; // just to eliminate a compiler warning

 // First get the file name, without ".png"
 // The uppercased base file name is used to refer to the graphic by scripts.
 gnamu := ExtractFileName(srcfilu);
 gnamu := upcase(copy(gnamu, 1, length(gnamu) - 4));
 if length(gnamu) > 31 then begin
  Error('Graphic file name too long (max 31 bytes)');
  gnamu := copy(gnamu, 1, 31);
 end;

 // Check the file size.
 assign(infilu, srcfilu);
 filemode := 0; reset(infilu, 1); // read-only
 ivar := IOresult;
 if ivar <> 0 then begin
  Error(errortxt(ivar) + ' trying to open');
  exit;
 end;
 filusize := filesize(infilu);
 if filusize < 21 then begin
  // absolute minimum recognisable file header is a single IHDR chunk without
  // an appended CRC: 4 + 4 + IHDR content (13) = 21 bytes
  close(infilu);
  Error('file is way too tiny');
  exit;
 end;

 // Get the PNGlist index, if there is one. (Since the PNG array is being
 // edited, it's not expected to be sorted, so this isn't the standard GetPNG
 // binary search. Seekpng is a linear search, defined somewhere above.)
 PNGindex := seekpng(gnamu);

 // If this graphic hasn't been mentioned in PNGlist, create a new slot.
 if PNGindex = 0 then begin
  inc(PNGcount);
  // Expand array if needed.
  if PNGcount >= dword(length(PNGlist)) then begin
   setlength(PNGlist, length(PNGlist) + 80);
   fillbyte(PNGlist[PNGcount], sizeof(PNGtype) * 80, 0);
  end;
  PNGindex := PNGcount;
  // Init the new slot.
  PNGlist[PNGindex].namu := gnamu;
  PNGlist[PNGindex].origresx := asman_baseresx;
  PNGlist[PNGindex].origresy := asman_baseresy;
 end;

 // We need to extract the PNG header, but don't need the rest of the file
 // right now...
 ivar := filusize; if ivar > 32 then ivar := 32;
 blockread(infilu, minibuf[0], ivar);

 // Parse the PNG header (mcg_ReadHeaderOnly was set to 1 earlier)
 workimu.image := NIL; // just to remove a compiler warning
 fillbyte(workimu, sizeof(workimu), 0);
 if mcg_PNGtoMemory(@minibuf[0], ivar, @workimu) <> 0 then Error(mcg_errortxt);

 // Check if the header started with the skippable PNG sig.
 ivar := 0;
 if dword((@minibuf[0])^) = $89504E47 then ivar := 8;

 // Capture the image size from the parsed header.
 PNGlist[PNGindex].origsizexp := workimu.sizex;
 PNGlist[PNGindex].origsizeyp := workimu.sizey;

 // Remember which file contains this PNG data.
 with PNGlist[PNGindex] do begin
  srcfilename := srcfilu;
  srcfileofs := ivar;
  srcfilesizu := filusize - ivar;
 end;
end;

procedure ProcessTsv(const srcfilu : UTF8string);
begin
 writeln(stdout, srcfilu);
 while IOresult <> 0 do ; // flush
 if ImportStringTable(srcfilu) = FALSE then PrintError(asman_errormsg);
end;

procedure ProcessMid(const srcfilu : UTF8string);
begin
 writeln(stdout, srcfilu, ': skip');
end;
procedure ProcessOgg(const srcfilu : UTF8string);
begin
 writeln(stdout, srcfilu, ': skip');
end;
procedure ProcessFlac(const srcfilu : UTF8string);
begin
 writeln(stdout, srcfilu, ': skip');
end;

procedure ProcessMetaData(const srcfilu : UTF8string);
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
 if ivar <> 0 then begin
  Error(errortxt(ivar) + ' reading ' + srcfilu);
  exit;
 end;

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

  // Base language description.
  if (lowercase(copy(line, lineofs, 1)) = 'l')
  and (lowercase(copy(line, lineofs + 1, 8)) = 'anguage ') then begin
   inc(lineofs, 9);
   languagelist[0] := copy(line, lineofs, length(line));
   if length(languagelist[0]) > 255 then languagelist[0] := copy(languagelist[0], 1, 255);
   continue;
  end;

  // Human-readable description string for the dat being built.
  if (lowercase(copy(line, lineofs, 1)) = 'd')
  and (lowercase(copy(line, lineofs + 1, 4)) = 'esc ') then begin
   inc(lineofs, 5);
   projectdesc := copy(line, lineofs, length(line));
   if length(projectdesc) > 255 then projectdesc := copy(projectdesc, 1, 255);
   continue;
  end;

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
   line := upcase(copy(line, lineofs, 31));
   // Get the PNGlist index for saving this metadata, if one exists.
   // (Seekpng is a linear search, defined somewhere above.)
   PNGindex := seekpng(line);
   if PNGindex = 0 then begin
    // an unprecedented file! Create a new slot, expand array if needed.
    inc(PNGcount);
    if PNGcount >= dword(length(PNGlist)) then begin
     setlength(PNGlist, length(PNGlist) + 80);
     fillbyte(PNGlist[PNGcount], sizeof(PNGtype) * 80, 0);
    end;
    PNGindex := PNGcount;
    // initialise the PNGlist[] slot
    PNGlist[PNGindex].namu := line;
   end;
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
   if PNGlist[PNGindex].framecount <= 0 then inc(PNGlist[PNGindex].framecount);
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

  // Set the base resolution
  if MatchString(line, 'baseres ', lineofs) then begin
   asman_baseresx := CutNumberFromString(line, lineofs);
   asman_baseresy := CutNumberFromString(line, lineofs);
   if (asman_baseresx < 2) or (asman_baseresy < 2) then begin
    Error('Base resolution ' + strdec(asman_baseresx) + 'x' + strdec(asman_baseresy) + ' is invalid!');
    asman_baseresx := 640;
    asman_baseresy := 480;
   end;
   continue;
  end;

  // Banner image name.
  if MatchString(line, 'banner ', lineofs) then begin
   bannerimagename := upcase(copy(line, lineofs, length(line)));
   writeln(stdout, 'Requested banner image: ', bannerimagename);
   continue;
  end;

  // Unknown command!
  Error('Unknown command: ' + line);
 end;

 close(ffilu);
end;

procedure ProcessFiles(srcdir : UTF8string);

  procedure ProcessDir(const currdir : UTF8string; rootdir : boolean);
  var filusr : TSearchRec;
      fnam : UTF8string;
      searchresult : longint;
  begin
   writeln(stdout, '----------------------------------------------------------------------');
   writeln(stdout, 'scanning ', currdir);

   // Metadata from the root directory must be processed first of all.
   if rootdir then begin
    PNGcount := 0;
    // First read data.txt; this should contain all metadata generated during
    // a game's decompilation.
    fnam := FindFile_Caseless(currdir + 'data.txt', FALSE);
    if fnam <> '' then ProcessMetaData(fnam);
    // Next read newdata.txt; this should contain overrides for the above
    // metadata, for example to fix decompilation bugs or original game bugs.
    fnam := FindFile_Caseless(currdir + 'newdata.txt', FALSE);
    if fnam <> '' then ProcessMetaData(fnam);
   end;

   // Find and try to process all files that could be recognisable data.
   searchresult := FindFirst(currdir + '*', faReadOnly, filusr);
   while searchresult = 0 do begin
    if length(filusr.Name) >= 5 then begin
     // (all must have a non-empty name, a dot, and a suffix)
     if copy(filusr.Name, length(filusr.Name) - 3, 1) = '.'
     then fnam := lowercase(copy(filusr.Name, length(filusr.Name) - 3, 4))
     else fnam := lowercase(copy(filusr.Name, length(filusr.Name) - 4, 5));

     // Identify file types by suffix, and forward for processing.
     // (.txt files are not picked up from the root directory, to avoid
     // getting confused by metadata files or other game docs.)
     if (fnam = '.txt') and (rootdir = FALSE)
     then ProcessScript(currdir + filusr.Name)
     else if fnam = '.png' then ProcessPng(currdir + filusr.Name)
     else if fnam = '.tsv' then ProcessTsv(currdir + filusr.Name)
     else if fnam = '.mid' then ProcessMid(currdir + filusr.Name)
     else if fnam = '.ogg' then ProcessOgg(currdir + filusr.Name)
     else if fnam = '.flac' then ProcessFlac(currdir + filusr.Name);
    end;
    searchresult := FindNext(filusr);
   end;
   FindClose(filusr);

   // Find sub-directories, to search recursively
   searchresult := FindFirst(currdir + '*', faReadOnly or faDirectory, filusr);
   while searchresult = 0 do begin
    if (filusr.Attr and faDirectory <> 0)
    and (filusr.Name <> '.') and (filusr.Name <> '..') then begin
     ProcessDir(currdir + filusr.Name + DirectorySeparator, FALSE);
    end;
    searchresult := FindNext(filusr);
   end;
   FindClose(filusr);
  end;

begin
 // Remove trailing slashes
 while (length(srcdir) <> 0) and (copy(srcdir, length(srcdir), 1) = DirectorySeparator)
  do srcdir := copy(srcdir, 1, length(srcdir) - 1);

 // Recursively list all files of interest
 if srcdir <> '' then
 ProcessDir(ExpandFileName(srcdir) + DirectorySeparator, TRUE);
end;

procedure GenerateDataFile;
var poku : pointer;
    txt : string[99];
    ivar, jvar : dword;

  procedure savepng(PNGindex : dword);
  var lvar, datalenofs : dword;
      infilu : file;
  begin
   // Start writing the header into our dat stream
   //   signature $531E0BB0 : dword;
   //   data length : dword;
   //   namu : ministring up to 31 bytes;
   //   origresx, origresy : word;
   //   origsizexp, origsizeyp : word;
   //   origofsxp, origofsyp : longint;
   //   framecount : dword;
   //   seqlen : dword;
   //   sequence : array[0..seqlen-1] of dword;
   //   bitflag : byte;
   // Followed by the PNG file without the first 2 DWORDS (redundant sig)

   // safety
   if PNGlist[PNGindex].srcfilename = '' then begin
    PrintError(PNGlist[PNGindex].namu + ': no PNG source file exists');
    exit;
   end;
   if PNGlist[PNGindex].srcfilesizu > filubuffysize then begin
    PrintError(PNGlist[PNGindex].namu + ': file too big, would cause buffy overflow');
    exit;
   end;
   assign(infilu, PNGlist[PNGindex].srcfilename);
   filemode := 0; reset(infilu, 1); // read-only
   lvar := IOresult;
   if lvar <> 0 then begin
    PrintError(errortxt(lvar) + ' trying to open ' + PNGlist[PNGindex].srcfilename);
    exit;
   end;
   // If the output buffer is getting full, flush it before we start.
   if filubuffyofs + 128 >= filubuffysize then flushbuffy;

   // If this is the banner image, remember the offset.
   if bannerimagename = PNGlist[PNGindex].namu then begin
    bannerimageofs := filepos(filu) + filubuffyofs;
    writeln(stdout, 'Banner image saved at $', strhex(bannerimageofs));
   end;

   // Write the supersakura PNG resource signature.
   lvar := $531E0BB0; writebuffy(@lvar, 4);
   // Remember this offset, must write the data length here later...
   datalenofs := filubuffyofs;
   inc(filubuffyofs, 4);

   // Write the image resource name.
   lvar := length(PNGlist[PNGindex].namu);
   writebuffy(@lvar, 1);
   writebuffy(@PNGlist[PNGindex].namu[1], lvar);
   // Write the image resolution.
   if PNGlist[PNGindex].origresx = 0 then PNGlist[PNGindex].origresx := asman_baseresx;
   if PNGlist[PNGindex].origresy = 0 then PNGlist[PNGindex].origresy := asman_baseresy;
   writebuffy(@PNGlist[PNGindex].origresx, sizeof(PNGtype.origresx));
   writebuffy(@PNGlist[PNGindex].origresy, sizeof(PNGtype.origresy));
   // Write the original image size.
   writebuffy(@PNGlist[PNGindex].origsizexp, sizeof(PNGtype.origsizexp));
   writebuffy(@PNGlist[PNGindex].origsizeyp, sizeof(PNGtype.origsizeyp));
   // Write the offset.
   writebuffy(@PNGlist[PNGindex].origofsxp, sizeof(PNGtype.origofsxp));
   writebuffy(@PNGlist[PNGindex].origofsyp, sizeof(PNGtype.origofsyp));
   // Write the frame count. For single-frame images, can be 0 or 1.
   writebuffy(@PNGlist[PNGindex].framecount, sizeof(PNGtype.framecount));
   // Write the animation sequence length.
   writebuffy(@PNGlist[PNGindex].seqlen, sizeof(PNGtype.seqlen));
   // Write the animation sequence, if any.
   if PNGlist[PNGindex].seqlen <> 0 then
    writebuffy(@PNGlist[PNGindex].sequence[0], PNGlist[PNGindex].seqlen * 4);
   // Write the image bitflag.
   writebuffy(@PNGlist[PNGindex].bitflag, sizeof(PNGtype.bitflag));
   // Go back to write the total data block byte size.
   dword((filubuffy + datalenofs)^) := filubuffyofs - datalenofs - 4 + PNGlist[PNGindex].srcfilesizu;

   // Flush the output buffer, if it can't accommodate the PNG data.
   if filubuffyofs + PNGlist[PNGindex].srcfilesizu >= filubuffysize then flushbuffy;

   // Read the PNG directly into the output buffer.
   seek(infilu, PNGlist[PNGindex].srcfileofs);
   blockread(infilu, (filubuffy + filubuffyofs)^, PNGlist[PNGindex].srcfilesizu);
   lvar := IOresult;
   inc(filubuffyofs, PNGlist[PNGindex].srcfilesizu);

   // React to file IO errors.
   close(infilu);
   if lvar <> 0 then PrintError(errortxt(lvar) + ' trying to read ' + PNGlist[PNGindex].namu + ' from ' + PNGlist[PNGindex].srcfilename);
  end;

begin
 // Write the header!
 // dword sig for supersakura dats
 ivar := $CACABAAB;
 WriteBuffy(@ivar, 4);
 // supersakura dat format version, constant value at top of source
 WriteBuffy(@fileversion, 1);
 // banner image offset
 ivar := 0;
 WriteBuffy(@ivar, 4);
 // parent project name string
 if length(recomp_param.parentname) > 255 then
  recomp_param.parentname := copy(recomp_param.parentname, 1, 255);
 ivar := length(recomp_param.parentname);
 WriteBuffy(@ivar, 1);
 if ivar <> 0 then WriteBuffy(@recomp_param.parentname[1], ivar);
 // project description string
 if length(projectdesc) > 255 then projectdesc := copy(projectdesc, 1, 255);
 ivar := length(projectdesc);
 WriteBuffy(@ivar, 1);
 if ivar <> 0 then WriteBuffy(@projectdesc[1], ivar);
 // recomp version string
 ivar := length(SSver);
 WriteBuffy(@ivar, 1);
 WriteBuffy(@SSver[1], ivar);

 // Compress and save the scripts
 writeln('Saving scripts...');
 writeln(stdout, 'Saving scripts...');
 poku := NIL;
 ivar := CompressScripts(@poku);
 if ivar = 0 then PrintError(asman_errormsg)
 else WriteBuffy(poku, ivar);
 if poku <> NIL then begin freemem(poku); poku := NIL; end;

 // Compress and save the string table
 writeln('Saving string table...');
 writeln(stdout, 'Saving string table...');
 for jvar := 0 to length(languagelist) - 1 do begin
  ivar := CompressStringTable(@poku, jvar);
  if ivar = 0 then PrintError(asman_errormsg)
  else WriteBuffy(poku, ivar);
  if poku <> NIL then begin freemem(poku); poku := NIL; end;
 end;

 // Save the graphics
 writeln('Saving graphics...');
 writeln(stdout, 'Saving graphics...');
 ivar := 1;
 while ivar <= PNGcount do begin
  savepng(ivar);
  inc(ivar);
 end;

 // If this is not a mod, save the BaseRes.
 if recomp_param.parentname = '' then begin
  // All images are saved with their proper resolution as part of their
  // metadata, but saving the official baseres separately allows the game
  // engine to set the game window to a nice integer multiple size.
  txt := 'Saving base res... (' + strdec(asman_baseresx) + 'x' + strdec(asman_baseresy) + ')';
  writeln(txt);
  writeln(stdout, txt);
  ivar := $5F1E0BB0;
  WriteBuffy(@ivar, 4);
  ivar := 8;
  WriteBuffy(@ivar, 4);
  WriteBuffy(@asman_baseresx, 4);
  WriteBuffy(@asman_baseresy, 4);
 end;
end;

procedure DumpTables;
var txt : UTF8string;
begin
 txt := 'Dumping string tables in ' + recomp_param.dumpstrings;
 writeln(txt); writeln(stdout, txt);
 if DumpStringTable(recomp_param.dumpstrings) then begin
  txt := 'String tables dumped.';
  writeln(txt); writeln(stdout, txt);
 end
 else
  PrintError(asman_errormsg);
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
 mcg_ReadHeaderOnly := 1; // we need some metadata but not the whole images
 PNGcount := 0;
 SCRcount := 0;
 bannerimagename := '';
 bannerimageofs := 0;

 // Create a basic logging file...
 // Try the current working directory first.
 assign(stdout, 'recomp.log');
 filemode := 1; rewrite(stdout); // write-only
 ivar := IOresult;
 if not ivar in [0,5] then begin
  writeln(errortxt(ivar) + ' trying to write recomp.log in current directory');
  exit;
 end;
 if ivar = 5 then begin
  // Access denied! Fall back to the user's profile directory.
  txt := GetAppConfigDir(FALSE); // false means user-specific, not global
  mkdir(txt);
  while IOresult <> 0 do ;
  assign(stdout, txt + 'recomp.log');
  filemode := 1; rewrite(stdout); // write-only
  ivar := IOresult;
  if ivar <> 0 then begin
   writeln(errortxt(ivar) + ' trying to write recomp.log under profile at ' + txt);
   exit;
  end;
 end;

 // Sanitise the commandline parameters...

 // Default sourcedir: the project name.
 if (recomp_param.sourcedir = '')
 and (recomp_param.projectname <> '')
 then recomp_param.sourcedir := recomp_param.projectname;

 // Check if this sourcedir exists under "data".
 // (Sourcedir can still be empty if neither sourcedir or project were
 // specified on the commandline. In this case there should at least be
 // a -loadfile parameter, otherwise there's nothing to work with.)
 if recomp_param.sourcedir <> '' then begin

  // Remove the trailing separator, if any.
  if recomp_param.sourcedir[length(recomp_param.sourcedir)] = DirectorySeparator
  then setlength(recomp_param.sourcedir, length(recomp_param.sourcedir) - 1);

  txt := FindFile_Caseless('data' + DirectorySeparator + recomp_param.sourcedir, TRUE);
  if txt = '' then begin
   PrintError('Sourcedir not found: data' + DirectorySeparator + recomp_param.sourcedir);
   exit;
  end;
  // If the sourcedir is the same as the project name, use the sourcedir's
  // exact casing for the project name too.
  if lowercase(recomp_param.sourcedir) = lowercase(recomp_param.projectname)
  then recomp_param.projectname := ExtractFileName(txt);
  // Use the exact casing of the source directory.
  recomp_param.sourcedir := txt;

  // Add a trailing separator to the source directory now.
  recomp_param.sourcedir := recomp_param.sourcedir + DirectorySeparator;
 end;

 // If outputfile was not overridden, use the project name, under data dir.
 if (recomp_param.outputfile = '') and (recomp_param.projectname <> '')
 then recomp_param.outputfile := 'data' + DirectorySeparator + recomp_param.projectname + '.dat';

 // Load an existing dat, if specified on commandline
 if recomp_param.loadfile <> '' then begin
  // (quit if output file is same as loadfile)
  if lowercase(recomp_param.outputfile) = lowercase(recomp_param.loadfile) then begin
   PrintError('-load and -out cannot point to the same file.');
   exit;
  end;
  txt := FindFile_Caseless(recomp_param.loadfile, FALSE);
  if txt = '' then begin
   PrintError('No such file: ' + recomp_param.loadfile);
   exit;
  end;
  writeln('Loading dat: ' + txt);
  writeln(stdout, 'Loading dat: ' + txt);
  if (LoadDAT(txt, '') <> 0) then begin
   PrintError('LoadDAT failed: ' + asman_errormsg);
   exit;
  end;

  PNGcount := length(PNGlist) - 1;
 end;

 if recomp_param.projectname <> '' then begin
  txt := 'Project: ' + recomp_param.projectname;
  writeln(txt); writeln(stdout, txt);
 end;
 if recomp_param.parentname <> '' then begin
  txt := 'This is a mod for: ' + recomp_param.parentname;
  writeln(txt); writeln(stdout, txt);
 end;
 if recomp_param.sourcedir <> '' then begin
  txt := 'Source directory: ' + recomp_param.sourcedir;
  writeln(txt); writeln(stdout, txt);
 end;
 if recomp_param.outputfile <> '' then begin
  txt := 'Output file: ' + recomp_param.outputfile;
  writeln(txt); writeln(stdout, txt);

  // Prepare the output file.
  txt := FindFile_Caseless(recomp_param.outputfile, FALSE);
  if txt <> '' then begin
   assign(filu, txt);
   erase(filu);
  end;
  while IOresult <> 0 do ; // flush
  assign(filu, recomp_param.outputfile);
  filemode := 1; rewrite(filu, 1); // write-only
  ivar := IOresult;
  if ivar <> 0 then begin
   PrintError(errortxt(ivar) + ' trying to write ' + recomp_param.outputfile);
   exit;
  end;

  // Prepare the output memory buffer.
  {$note test if dat works with tiny buffysize}
  filubuffysize := 1 shl 24; filubuffyofs := 0;
  getmem(filubuffy, filubuffysize);
 end;

 DoInits := TRUE;
end;

procedure DoCleanup;
var txt : string;
    ivar, lvar : longint;
    uniquestringcount : longint;
begin
 // Write to disk whatever we've still got in the memory buffer.
 if recomp_param.outputfile <> '' then begin
  flushbuffy;
  // Insert the banner image offset in the header, if present.
  if bannerimageofs <> 0 then begin
   seek(filu, 5);
   blockwrite(filu, bannerimageofs, 4);
  end;

  close(filu);
  freemem(filubuffy); filubuffy := NIL;
 end;

 // Give the user a summary of what happened
 txt := 'Finished! ';
 if errorcount <> 0 then txt := txt + 'Encountered ' + strdec(errorcount) + ' errors! See recomp.log.'
 else txt := txt + 'No errors!';
 writeln(txt); writeln(stdout, txt);

 // Tell the user how many of each kind of asset was saved in the dat.
 txt := strdec(PNGcount) + ' images, ' + strdec(SCRcount) + ' script files, '
   + strdec(length(script) - 1) + ' script labels.';
 writeln(txt); writeln(stdout, txt);

 for lvar := length(languagelist) - 1 downto 0 do begin

  uniquestringcount := 0;

  if length(script) > 1 then
  for ivar := 1 to length(script) - 1 do
   if lvar < length(script[ivar].stringlist) then
    inc(uniquestringcount, length(script[ivar].stringlist[lvar].txt));

  txt := languagelist[lvar] + ': '
    + strdec(length(script[0].stringlist[lvar].txt)) + ' global strings, '
    + strdec(uniquestringcount) + ' unique strings.';
  writeln(txt); writeln(stdout, txt);
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
 with recomp_param do begin
  projectname := '';
  parentname := '';
  sourcedir := '';
  outputfile := '';
  dumpstrings := '';
  loadfile := '';
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

   else if (lowercase(copy(txt, jvar, 3)) = 'in=')
     then recomp_param.sourcedir := copy(txt, jvar + 3, length(txt))
   else if (lowercase(copy(txt, jvar, 4)) = 'out=')
     then recomp_param.outputfile := copy(txt, jvar + 4, length(txt))
   else if (lowercase(copy(txt, jvar, 8)) = 'outfile=')
     then recomp_param.outputfile := copy(txt, jvar + 8, length(txt))
   else if (lowercase(copy(txt, jvar, 8)) = 'dumpstr=')
     then recomp_param.dumpstrings := copy(txt, jvar + 8, length(txt))
   else if (lowercase(copy(txt, jvar, 5)) = 'load=')
     then recomp_param.loadfile := copy(txt, jvar + 5, length(txt))
   else if (lowercase(copy(txt, jvar, 9)) = 'loadfile=')
     then recomp_param.loadfile := copy(txt, jvar + 9, length(txt))
   else if (lowercase(copy(txt, jvar, 7)) = 'parent=')
     then recomp_param.parentname := copy(txt, jvar + 7, length(txt))
   else begin
    PrintError('Unrecognised option: ' + paramstr(ivar));
    DoParams := FALSE; exit;
   end;
  end

  else begin
   if recomp_param.projectname = '' then recomp_param.projectname := paramstr(ivar)
   else begin
    PrintError('Unrecognised parameter: ' + paramstr(ivar));
    DoParams := FALSE; exit;
   end;
  end;
 end;

 // If no parameters are present or project and loadfile are empty, then
 // there's nothing to do; show the help text.
 if (paramcount = 0)
 or (recomp_param.projectname = '') and (recomp_param.loadfile = '')
 then DoParams := FALSE;

 if DoParams then exit;

 writeln;
 writeln('  MoonCore Super Resource Recompiler');
 writeln('-------------------------------------- ' + SSver + ' --');
 writeln('Usage: recomp <project> [-options]');
 writeln;
 writeln('This tool packs resources into a single data file.');
 writeln('It reads scripts, graphics, and various music/sound files from subdirectories');
 writeln('under data/project directory; and data.txt and newdata.txt from the project');
 writeln('directory. All filenames must have 1-31 characters, plus 3 for the suffix.');
 writeln;
 writeln('You must define the project name using a commandline parameter.');
 writeln('For example, to build data/saku.dat from ./data/saku/*:');
 writeln('recomp saku');
 writeln;
 writeln('Options:');
 writeln('-in=dir/dir        Overrides the project source directory');
 writeln('-out=file.dat      Overrides the output file name');
 writeln('-load=file.dat     Loads the given dat before starting to process other files.');
 writeln('-dumpstr=file.tsv  Prints the string tables into a tab-separated text file.');
 writeln('-parent=project    Creates a mod for the specified parent project');
end;

begin
 recomp_param.sourcedir := ''; // silence a compiler warning
 errorcount := 0;

 if DoParams = FALSE then begin ExitCode := errorcount; exit; end;
 if DoInits = FALSE then begin ExitCode := errorcount; exit; end;

 // Find and process all files under the source directory
 if recomp_param.sourcedir <> ''
 then ProcessFiles(recomp_param.sourcedir);
 // Dump the string tables if requested
 if recomp_param.dumpstrings <> ''
 then DumpTables;
 // Produce a data file
 if recomp_param.outputfile <> ''
 then GenerateDataFile;

 DoCleanup;
 ExitCode := errorcount;
end.
