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

procedure Decomp_Exe(loader : TFileLoader);
// Reads an executable file and extracts useful data, like animation frames
// or music file lists.
// The executable's game ID must be known before calling.
var poku : pointer;
    txt : UTF8string;
    songnamu : string[15];
    i, j : dword;
    songlistofs, animdataofs : dword;
begin
 // Extract constant data from the EXE.
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

 // Enumerate songs.
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
  for i := high(songlist) downto 0 do
  if i < 9 then songlist[i] := songnamu + '0' + strdec(i + 1)
  else songlist[i] := songnamu + strdec(i + 1);
 //if game = gid_TRANSFER98 then songlist[39] := 'TRAIN';

 // Extract songs, if applicable.
 if songlistofs <> 0 then begin
  for i := high(songlist) downto 0 do byte(songlist[i][0]) := 0;
  i := 0;
  while i < dword(length(songlist)) do begin
   if loader.ReadByteFrom(songlistofs) = 0 then begin
    // crop out the extension
    while (length(songlist[i]) <> 0)
    and (songlist[i][length(songlist[i])] <> '.')
    do dec(byte(songlist[i][0]));
    dec(byte(songlist[i][0]));
    inc(i);
   end else
    songlist[i] := songlist[i] + char(loader.ReadByteFrom(songlistofs));
   inc(songlistofs);
  end;

  writeln(stdout, 'Extracted songlist, ' + strdec(length(songlist)) + ' entries.');
  for i := 0 to high(songlist) do writeln(stdout, i, ':', songlist[i]);
 end;

 // Extract animation data.
 if animdataofs <> 0 then begin
  loader.ofs := animdataofs;
  getmem(poku, 178);

  // Snowcat and Tenkousei use a modified format.
  if game in [gid_SETSUJUU, gid_TRANSFER98] then begin
   j := 0;
   case game of
    // baseline address for name strings.
    gid_SETSUJUU: j := $14340;
    gid_TRANSFER98: j := $13E50;
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
    move(loader.PtrAt(j + word((poku + 2)^))^, songnamu[1], 9);
    // find the null to determine string length.
    for i := 1 to 9 do
     if songnamu[i] = chr(0) then begin
      byte(songnamu[0]) := i - 1;
      break;
     end;
    // an empty animation name means we're done.
    if songnamu = '' then break;
    // find the PNGlist[] entry for this, or create one.
    songnamu := upcase(songnamu);
    i := seekpng(songnamu, TRUE);
    // convert and save the animation data into PNGlist[].
    if byte((poku + 2)^) <> 0 then ChewAnimations(poku, i);
   until FALSE;
  end

  // Other games use a more common format.
  else begin
   repeat
    move(loader.readp^, poku^, 178);
    inc(loader.readp, 178);
    // 0 seqlen or 0 name? We're done.
    if (word(poku^) = 0) or (word((poku + 2)^) = 0) then break;
    // grab the animation name.
    move((poku + 2)^, songnamu[1], 9);
    // find the null to determine string length.
    for i := 1 to 9 do
     if songnamu[i] = chr(0) then begin
      byte(songnamu[0]) := i - 1;
      break;
     end;
    // find the PNGlist[] entry for this, or create one.
    songnamu := upcase(songnamu);
    i := seekpng(songnamu, TRUE);
    // convert and save the animation data into PNGlist[].
    ChewAnimations(poku, i);
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
end;
