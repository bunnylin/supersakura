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

// SuperSakura text box functions

procedure GetNewFont(boxnum, heightp : dword);
begin
 TBox[boxnum].fontheightp := 1;
 TBox[boxnum].fontwidthp := 1;
end;

function GetUTF8Size(poku : pointer; slen, boxnum : dword) : dword;
// Returns the size in character cells of the given UTF-8 string. Tries to
// account for double-width CJK. Poku must point to a valid UTF-8 byte
// sequence, and slen is the byte length of the sequence.
var endp : pointer;
    utfcode : dword;
begin
 GetUTF8Size := 0;
 endp := poku + slen;
 while poku < endp do begin
  // 1: 0xxxxxxx
  // 2: 110xxxxx 10xxxxxx
  // 3: 1110xxxx 10xxxxxx 10xxxxxx
  // 4: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
  case byte(poku^) of
    $00..$7F: begin inc(poku); inc(GetUTF8Size); continue; end;
    $C0..$DF: begin
     utfcode := byte(poku^) shl 8 + byte((poku + 1)^);
     inc(poku, 2);
    end;
    $E0..$EF: begin
     utfcode := byte(poku^) shl 16 + byte((poku + 1)^) shl 8 + byte((poku + 2)^);
     inc(poku, 3);
    end;
    $F0..$F7: begin
     utfcode := byte(poku^) shl 24 + byte((poku + 1)^) shl 16 + byte((poku + 2)^) shl 8 + byte((poku + 3)^);
     inc(poku, 4);
    end;
    else begin LogError('Con_UTF8Size: invalid UTF8 first byte: $' + strhex(byte(poku^))); exit; end;
  end;
  inc(GetUTF8Size);
  // Double-width characters:
  // 2E80..D7AF   = E2BA80..ED9EAF (mishmash of all basic CJK)
  // FF01..FF60   = EFBC81..EFBDA0 (doublewidth ascii characters)
  // FFE0..FFE6   = EFBFA0..EFBFA6 (extra CJK punctuation)
  // 20000..2CEAF = F0A08080..F0ACBAAF (tons of extended ideographs)
  if utfcode >= $E2BA80 then begin
   if (utfcode <= $ED9EAF)
   or (utfcode >= $EFBC81) and (utfcode <= $EFBDA0)
   or (utfcode >= $EFBFA0) and (utfcode <= $EFBFA6)
   or (utfcode >= $F0A08080) and (utfcode <= $F0ACBAAF)
   then inc(GetUTF8Size);
  end;
 end;
end;

// ------------------------------------------------------------------

{$include sakubox-all.pas}
