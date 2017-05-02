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

function Decomp_ExcellentDAT(const datfile, lstfile, outputdir : UTF8string) : UTF8string;
// Unpacks files from an Excellents .DAT file, using the accompanying .LST
// file, and saves them in outputdir/temp/. The unpacked files are then
// further forwarded to conversion functions.
// Returns an empty string if successful, otherwise returns an error message.
var ivar, listofs, listsize : dword;
    listp : pointer;
    reslist : array of UTF8string;
    rescount : dword;
begin
 // Is it a useless MEMORY.DAT?
 if (lowercase(ExtractFileName(datfile)) = 'memory.dat')
 and (word(loader^) = 2) then begin
  write(stdout, 'this has no resources, ');
  Decomp_ExcellentDAT := 'skip';
  exit;
 end;

 // Make a temp directory.
 mkdir(outputdir + 'temp');
 while IOresult <> 0 do ; // flush

 // Load the list file.
 Decomp_ExcellentDAT := LoadFile(lstfile);
 if Decomp_ExcellentDAT <> '' then exit;
 // Reshuffle the file contents into listp^.
 listp := loader; loader := NIL;
 listofs := 0; listsize := loadersize;
 setlength(reslist, 256);

 // Check list file signature.
 setlength(reslist[0], 11);
 move(listp^, reslist[0][1], 11);
 if reslist[0] <> 'D_Lib -02- ' then begin
  Decomp_ExcellentDAT := 'bad .lst signature';
  freemem(listp); listp := NIL;
  exit;
 end;
 // Skip rest of list header.
 listofs := 16;

 // Load the dat file.
 Decomp_ExcellentDAT := LoadFile(datfile);
 if Decomp_ExcellentDAT <> '' then begin
  freemem(listp); listp := NIL;
  exit;
 end;

 // Start extracting resources from the dat.
 writeln('extracting resources...');
 writeln(stdout, 'extracting resources...');

 rescount := 0;
 while (listofs + 16 <= listsize) do begin
  // Expand reslist if needed.
  if rescount >= dword(length(reslist)) then setlength(reslist, length(reslist) shl 1);
  // Read the resource filename.
  setlength(reslist[rescount], 13);
  move((listp + listofs)^, reslist[rescount][1], 12);
  reslist[rescount][13] := chr(0);
  setlength(reslist[rescount], pos(chr(0), reslist[rescount]) - 1);
  ivar := pos('\', reslist[rescount]); // replace backslashes with underscore
  if ivar <> 0 then reslist[rescount][ivar] := '_';
  if reslist[rescount] = '[[End]]     ' then break;
  writeln(stdout, reslist[rescount]);
  // Read the data offset.
  inc(listofs, 12);
  lofs := dword((listp + listofs)^);
  inc(listofs, 4);
  // Read the next data offset to figure out data size.
  ivar := dword((listp + listofs + 12)^);
  // Validate the data offsets.
  if ivar > loadersize then begin
   PrintError('end offset beyond .dat end!');
   ivar := loadersize;
  end;
  if lofs > ivar then begin
   PrintError('start offset beyond end offset!');
   ivar := loadersize;
  end;
  // Get the data byte size.
  dec(ivar, lofs);
  // Suffixless files are probably graphics, so give them a .G extension.
  if (pos('.', reslist[rescount]) = 0) and (ivar > 8) then begin
   // check that the file starts with a graphic signature or correct-looking
   // image size.
   if (dword((loader + lofs)^) = $73556950) // PiUser sig
   or (word((loader + lofs)^) <> 0)
   and (word((loader + lofs + 2)^) <> 0)
   and (byte((loader + lofs)^) in [0..3]) // valid image widths: 001..3FF
   and (byte((loader + lofs + 2)^) in [0..2]) // valid heights: 001..2FF
   then reslist[rescount] := reslist[rescount] + '.g';
  end;
  // Save the file in /temp/.
  Decomp_ExcellentDAT := SaveFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount], loader + lofs, ivar);
  if Decomp_ExcellentDAT <> '' then begin
   freemem(listp); listp := NIL;
   exit;
  end;
  // next file!
  inc(rescount);
 end;

 freemem(listp); listp := NIL;

 // Dispatch the extracted files for conversion.
 while rescount <> 0 do begin
  dec(rescount);
  DispatchFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount]);
 end;
end;

function Decomp_ExcellentLib(const libfile, catfile, outputdir : UTF8string) : UTF8string;
// Unpacks files from an Excellents .LIB file, using the accompanying .CAT
// file, and saves them in outputdir/temp/. The unpacked files are then
// further forwarded to conversion functions.
// Returns an empty string if successful, otherwise returns an error message.
var catofs, catsize : dword;
    catp, resp : pointer;
    reslist : array of UTF8string;
    rescount, comptype, ressize, startofs : dword;
    dump : file;
begin
 // Make a temp directory.
 mkdir(outputdir + 'temp');
 while IOresult <> 0 do ; // flush

 // Load the cat file.
 Decomp_ExcellentLib := LoadFile(catfile);
 if Decomp_ExcellentLib <> '' then exit;

 // Check cat file signature.
 if dword(loader^) <> $31746143 then begin
  Decomp_ExcellentLib := 'bad .cat signature';
  exit;
 end;

 // Uncompress the Softdisk-style LZ77 stream.
 resp := NIL; catp := NIL; catsize := 0; catofs := 0;
 Decompress_LZ77(loader + 6, loadersize - 6, catp, catsize);
 freemem(loader); loader := NIL;

 assign(dump, 'dump.dat');
 rewrite(dump,1);
 blockwrite(dump, catp^, catsize);
 close(dump);

 // Load the lib file.
 Decomp_ExcellentLib := LoadFile(libfile);
 if Decomp_ExcellentLib <> '' then begin
  freemem(catp); catp := NIL;
  exit;
 end;

 // Check lib file signature.
 if dword(loader^) <> $3062694C then begin
  Decomp_ExcellentLib := 'bad .lib signature';
  freemem(catp); catp := NIL;
  exit;
 end;

 // Start extracting resources from the lib.
 setlength(reslist, 256);
 rescount := 0;
 writeln('extracting resources...');
 writeln(stdout, 'extracting resources...');

 while catofs + 22 <= catsize do begin
  // Expand reslist if needed.
  if rescount >= dword(length(reslist)) then setlength(reslist, length(reslist) shl 1);
  // Read the resource filename.
  setlength(reslist[rescount], 12);
  move((catp + catofs)^, reslist[rescount][1], 12);
  inc(catofs, 12);
  // Remove trailing spaces.
  while (length(reslist[rescount]) <> 0)
  and (reslist[rescount][length(reslist[rescount])] = ' ')
  do setlength(reslist[rescount], length(reslist[rescount]) - 1);
  writeln(stdout, reslist[rescount]);
  // Read the compression type.
  comptype := word((catp + catofs)^); inc(catofs, 2);
  if comptype > 1 then begin
   Decomp_ExcellentLib := 'unknown compression type ' + strdec(comptype);
   freemem(catp); catp := NIL;
   exit;
  end;
  // Read the resource size and location.
  ressize := dword((catp + catofs)^); inc(catofs, 4);
  startofs := dword((catp + catofs)^) + 6; inc(catofs, 4);
  // Validate the data offsets.
  if startofs > loadersize then begin
   PrintError('start offset beyond .lib end!');
   startofs := loadersize;
  end;
  if startofs + ressize > loadersize then begin
   PrintError('file end beyond .lib end!');
   ressize := loadersize - startofs;
  end;
  // Suffixless files are probably graphics, so give them a .G extension.
  // (Mayclub98 has Z65 in DISK_A which is a graphic, but is LZ77-compressed
  // in addition to MAGv3, probably programmer error. Still works though.)
  if (pos('.', reslist[rescount]) = 0) then reslist[rescount] := reslist[rescount] + '.g';

  // MAGv3 graphic files...
  if comptype = 0 then begin
   // Save the file directly from the lib.
   Decomp_ExcellentLib := SaveFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount], loader + startofs, ressize);
  end

  // LZ77 compressed files...
  else begin
   inc(startofs, 4); dec(ressize, 4); // skip unpacked size dword
   Decompress_LZ77(loader + startofs, ressize, resp, ressize);
   Decomp_ExcellentLib := SaveFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount], resp, ressize);
   freemem(resp); resp := NIL;
  end;

  if Decomp_ExcellentLib <> '' then begin
   freemem(catp); catp := NIL;
   exit;
  end;
  // next file!
  inc(rescount);
 end;

 freemem(catp); catp := NIL;

 // Dispatch the extracted files for conversion.
 writeln('dispatching lib contents...');
 writeln(stdout, 'dispatching lib contents...');
 while rescount <> 0 do begin
  dec(rescount);
  DispatchFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount]);
 end;
end;
