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

procedure Decomp_ExcellentS(const loader : TFileLoader; const outputfile : UTF8string);
// Reads the indicated Excellents bytecode file, and saves it in outputfile
// as a plain text sakurascript file.
// Throws an exception in case of errors.
var startofs : dword;
const purifier : array[0..1] of byte = ($FF, 1);
begin
 // PC-98 version scripts tend to start with $100 zeroes. The DOS version
 // doesn't have these. But in both, MUG_SUB.S starts with some junk, which
 // may as well be cut out.
 startofs := 0;
 if (loader.ReadDwordFrom(4) = 0) and (loader.ReadDwordFrom(8) = 0)
 or (loader.ReadDwordFrom(0) = $646E6957) and (loader.ReadDwordFrom(4) = $62755379)
 then startofs := $100;

 // Remove script obfuscation.
 loader.ofs := startofs;
 if game in [gid_MAYCLUB, gid_NOCTURNE] then begin
  while loader.readp < loader.endp do begin
   byte(loader.readp^) := (byte(loader.readp^) + purifier[(loader.ofs) and 1]) and $FF;
   inc(loader.readp);
  end;
 end
 else begin
  // The Japanese games just do xor 1 on every byte.
  while loader.readp + 4 < loader.endp do begin
   dword(loader.readp^) := dword(loader.readp^) xor $01010101;
   inc(loader.readp, 4);
  end;
  while loader.readp < loader.endp do begin
   byte(loader.readp^) := byte(loader.readp^) xor 1;
   inc(loader.readp);
  end;
 end;

 SaveFile(outputfile, loader.PtrAt(startofs), loader.size - startofs);
end;
