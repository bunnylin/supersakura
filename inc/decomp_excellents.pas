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

function Decomp_ExcellentS(const srcfile, outputfile : UTF8string) : UTF8string;
// Reads the indicated Excellents bytecode file, and saves it in outputfile
// as a plain text sakurascript file.
// Returns an empty string if successful, otherwise returns an error message.
var startofs : dword;
const purifier : array[0..1] of byte = ($FF, 1);
begin
 // Load the input file into loader^.
 Decomp_ExcellentS := LoadFile(srcfile);
 if Decomp_ExcellentS <> '' then exit;

 // PC-98 version scripts tend to start with $100 zeroes. The DOS version
 // doesn't have these. But in both, MUG_SUB.S starts with some junk, which
 // may as well be cut out.
 startofs := 0;
 if (dword((loader + 4)^) = 0) and (dword((loader + 8)^) = 0)
 or (dword(loader^) = $646E6957) and (dword((loader + 4)^) = $62755379)
 then startofs := $100;

 // Remove script obfuscation.
 lofs := startofs;
 if game in [gid_MAYCLUB, gid_NOCTURNE] then begin
  while lofs < loadersize do begin
   byte((loader + lofs)^) := (byte((loader + lofs)^) + purifier[(lofs) and 1]) and $FF;
   inc(lofs);
  end;
 end
 else begin
  // The Japanese games just do xor 1 on every byte.
  while lofs + 4 < loadersize do begin
   dword((loader + lofs)^) := dword((loader + lofs)^) xor $01010101;
   inc(lofs, 4);
  end;
  while lofs < loadersize do begin
   byte((loader + lofs)^) := byte((loader + lofs)^) xor 1;
   inc(lofs);
  end;
 end;

 Decomp_ExcellentS := SaveFile(outputfile, loader + startofs, loadersize - startofs);
end;
