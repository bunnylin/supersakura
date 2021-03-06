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

procedure Decomp_ExcellentDAT(const loader : TFileLoader; const listfilename, outputdir : UTF8string);
// Unpacks files from an Excellents .DAT file, using the accompanying .LST
// file, and saves them in outputdir/temp/. The unpacked files are then
// further forwarded to conversion functions.
// Returns an empty string if successful, otherwise returns an error message.
var i : dword;
    listfile : TFileLoader;
    reslist : array of UTF8string;
    rescount : dword;
begin
 setlength(reslist, 256);
 // Is it a useless MEMORY.DAT or SAVEx.DAT?
 reslist[0] := lowercase(ExtractFileName(loader.filename));
 if (reslist[0] = 'memory.dat')
 //and (word(loader^) = 2)
 or (reslist[0] = 'save0.dat')
 or (reslist[0] = 'save1.dat')
 or (reslist[0] = 'save2.dat')
 then begin
  write(stdout, 'this has no resources! ');
  exit;
 end;

 // Make a temp directory.
 mkdir(outputdir + 'temp');
 while IOresult <> 0 do ; // flush

 // Load the list file.
 try
  listfile := TFileLoader.Open(listfilename);
 except
  on E : Exception do
   raise DecompException.Create(E.Message);
 end;

 try
  // Check list file signature.
  setlength(reslist[0], 11);
  move(listfile.readp^, reslist[0][1], 11);

  if reslist[0] <> 'D_Lib -02- ' then
   raise DecompException.Create('bad .lst signature');

  // Skip rest of list header.
  listfile.ofs := 16;

  // Start extracting resources from the dat.
  writeln('extracting resources...');
  writeln(stdout, 'extracting resources...');

  rescount := 0;
  while (listfile.readp + 16 <= listfile.endp) do begin
   // Expand reslist if needed.
   if rescount >= dword(length(reslist)) then setlength(reslist, length(reslist) shl 1);

   // Read the resource filename.
   setlength(reslist[rescount], 13);
   move(listfile.readp^, reslist[rescount][1], 12);
   reslist[rescount][13] := chr(0);
   setlength(reslist[rescount], pos(chr(0), reslist[rescount]) - 1);
   i := pos('\', reslist[rescount]); // replace backslashes with underscore
   if i <> 0 then reslist[rescount][i] := '_';
   if reslist[rescount] = '[[End]]     ' then break;
   writeln(stdout, reslist[rescount]);

   // Read the data offset.
   inc(listfile.readp, 12);
   loader.ofs := listfile.ReadDword;

   // Read the next data offset to use as this one's end offset.
   i := dword((listfile.readp + 12)^);

   // Validate the data offsets.
   if i > loader.size then begin
    PrintError('end offset beyond .dat end!');
    i := loader.size;
   end;
   if i < loader.ofs then begin
    PrintError('end offset before start offset!');
    i := loader.size;
   end;

   // Get the data byte size.
   dec(i, loader.ofs);

   // Suffixless files are probably graphics, so give them a .G extension.
   if (pos('.', reslist[rescount]) = 0) and (i > 8) then begin
    // check that the file starts with a graphic signature or correct-looking
    // image size.
    if (word(loader.readp^) = $6950) // Pi sig
    or (word(loader.readp^) <> 0)
    and (word((loader.readp + 2)^) <> 0)
    and (byte(loader.readp^) in [0..3]) // valid image widths: 001..3FF
    and (byte((loader.readp + 2)^) in [0..2]) // valid heights: 001..2FF
    then reslist[rescount] := reslist[rescount] + '.g';
   end;

   // Save the file in /temp/.
   SaveFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount], loader.readp, i);

   // next file!
   inc(rescount);
  end;

  // Dispatch the extracted files for conversion.
  writeln('dispatching dat contents...');
  writeln(stdout, 'dispatching dat contents...');
  while rescount <> 0 do begin
   dec(rescount);
   DispatchFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount]);
  end;

 finally
  if listfile <> NIL then listfile.free;
  listfile := NIL;
 end;
end;

procedure Decomp_ExcellentLib(const loader : TFileLoader; const catfilename, outputdir : UTF8string);
// Unpacks files from an Excellents .LIB file, using the accompanying .CAT
// file, and saves them in outputdir/temp/. The unpacked files are then
// further forwarded to conversion functions.
// Returns an empty string if successful, otherwise returns an error message.
var catp, resp : pointer;
    catofs, catpsize : dword;
    catfile : TFileLoader;
    reslist : array of UTF8string;
    rescount, comptype, ressize, startofs : dword;
    dump : file;
begin
 // Check lib file signature.
 if loader.ReadDword <> $3062694C then
  raise DecompException.Create('bad .lib signature');

 resp := NIL; catp := NIL;
 try

 // Load the cat file.
 catfile := TFileLoader.Open(catfilename);

 try
  // Check cat file signature.
  if catfile.ReadDword <> $31746143 then
   raise DecompException.Create('bad .cat signature');

  if loader.ReadWord <> catfile.ReadWord then
   raise DecompException.Create('.cat and .lib have mismatching postsig word');

  // Uncompress the Softdisk-style LZ77 stream.
  Decompress_LZ77(catfile.readp, catfile.size - 6, catp, catpsize);

 finally
  if catfile <> NIL then catfile.free;
  catfile := NIL;
 end;

 assign(dump, 'dump.dat');
 rewrite(dump,1);
 blockwrite(dump, catp^, catpsize);
 close(dump);

 // Make a temp directory.
 mkdir(outputdir + 'temp');
 while IOresult <> 0 do ; // flush

 // Start extracting resources from the lib.
 setlength(reslist, 256);
 rescount := 0;
 catofs := 0;
 writeln('extracting resources...');
 writeln(stdout, 'extracting resources...');

 while catofs + 22 <= catpsize do begin
  // Expand reslist if needed.
  if rescount >= dword(length(reslist)) then setlength(reslist, length(reslist) shl 1);

  // Read the resource filename.
  setlength(reslist[rescount], 12);
  move((catp + catofs)^, reslist[rescount][1], 12);
  inc(catofs, 12);

  // Remove trailing spaces.
  reslist[rescount] := trim(reslist[rescount]);
  writeln(stdout, reslist[rescount]);

  // Read the compression type.
  comptype := word((catp + catofs)^);
  inc(catofs, 2);
  if comptype > 1 then
   raise DecompException.Create('unknown compression type ' + strdec(comptype));

  // Read the resource size and location.
  ressize := dword((catp + catofs)^);
  inc(catofs, 4);
  startofs := dword((catp + catofs)^) + 6;
  inc(catofs, 4);

  // Validate the data offsets.
  if startofs > loader.size then begin
   PrintError('start offset beyond .lib end!');
   startofs := loader.size;
  end;
  if startofs + ressize > loader.size then begin
   PrintError('file end beyond .lib end!');
   ressize := loader.size - startofs;
  end;

  // Suffixless files are probably graphics, so give them a .G extension.
  // (Mayclub98 has Z65 in DISK_A which is a graphic, but is LZ77-compressed
  // in addition to Pi, probably programmer error. Still works though.)
  if (pos('.', reslist[rescount]) = 0) then reslist[rescount] := reslist[rescount] + '.g';

  if ressize = 0 then writeln(stdout, 'resource size 0!')
  else begin

   // Pi graphic files...
   if comptype = 0 then begin
    // Save the file directly from the lib.
    SaveFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount], loader.PtrAt(startofs), ressize);
   end

   // LZ77 compressed files...
   else begin
    inc(startofs, 4); dec(ressize, 4); // skip unpacked size dword
    Decompress_LZ77(loader.PtrAt(startofs), ressize, resp, ressize);
    SaveFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount], resp, ressize);
    freemem(resp); resp := NIL;
   end;
  end;

  // next file!
  inc(rescount);
 end;

 // Dispatch the extracted files for conversion.
 writeln('dispatching lib contents...');
 writeln(stdout, 'dispatching lib contents...');
 while rescount <> 0 do begin
  dec(rescount);
  DispatchFile(outputdir + 'temp' + DirectorySeparator + reslist[rescount]);
 end;

 finally
  if catp <> NIL then begin freemem(catp); catp := NIL; end;
  if resp <> NIL then begin freemem(resp); resp := NIL; end;
 end;
end;
