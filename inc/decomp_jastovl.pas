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
// Decomp --- Script bytecode conversion code

function GetLoaderString(ofsu : dword) : string;
// Returns a null-terminated string from (loader^)[ofsu]
var ivar : dword;
begin
 ivar := 0;
 while (byte((loader + ofsu + ivar)^) <> 0) and (ofsu + ivar < loadersize) do inc(ivar);
 if ivar > 255 then ivar := 255;
 byte(GetLoaderString[0]) := ivar;
 move((loader + ofsu)^, GetLoaderString[1], ivar);
end;

function Decomp_JastOvl(const srcfile, outputfile : UTF8string) : UTF8string;
// Reads the indicated JAST/Tiare bytecode file, and saves it in outputfile
// as a plain text sakurascript file.
// Returns an empty string if successful, otherwise returns an error message.
var outbuf : record
      labellist : array of dword;
      linelist : array of UTF8string;
      bufindex, bufsize : dword;
      buffy : pointer;
    end;
    jumplist : array of dword;
    jumpcount : dword;

    localvarlist : array of word;

    scriptname : UTF8string;

    ivar, jvar, lvar : dword;
    ptrresults, ptrscript, ptroptions, ptrpix, ptrnil : word;
    gutan : word;
    combos, options, pictures, bitness : byte;
    implicitwaitkey, waitkeyswipe : byte;
    persistence, blackedout, haschoices, stashactive : boolean;
    txt : string;
    lastbkg : string;
    nextgra : record
      style, ofsx : word;
      transition, unswiped : byte;
    end;
    stringcache : array[0..15] of string[63]; // for 0B-4B
    choicecombo : array[0..63] of record
      verbtext, subjecttext : string[32];
      id : word;
      jumpresult : array[0..31] of word;
    end;
    optionlist : array[1..63] of record
      address : word;
      verbtext : string[32];
      subjecttext : array[1..24] of string[32];
    end;
    gfxlist : array[0..63] of record
      gfxname : string[8];
      data1, data2 : byte;
    end;
    animslot : array[0..8] of record
      ofsx : word;
      namu : string[15];
      displayed : boolean;
    end;

  procedure WriteBuf(const line : UTF8string); inline;
  begin
   with outbuf do
    linelist[bufindex] := linelist[bufindex] + line;
  end;

  procedure WriteBuf(const line : UTF8string; linelen : dword); inline;
  begin
   with outbuf do
    linelist[bufindex] := linelist[bufindex] + copy(line, 1, linelen);
  end;

  procedure WriteBufLn(const line : UTF8string);
  begin
   WriteBuf(line);
   inc(outbuf.bufindex);
   if outbuf.bufindex >= dword(length(outbuf.labellist)) then begin
    setlength(outbuf.labellist, length(outbuf.labellist) shl 1);
    setlength(outbuf.linelist, length(outbuf.labellist) shl 1);
   end;
   outbuf.labellist[outbuf.bufindex] := lofs;
   outbuf.linelist[outbuf.bufindex] := '';
  end;

  procedure AddLocalVar(varnum : word);
  // Maintains a list of all local variables (0..255) used in this script.
  // Any that have constant values assigned to them at any point have to be
  // initialised to zero at the top of the script.
  var vvar : dword;
  begin
   vvar := length(localvarlist);
   while vvar <> 0 do begin
    dec(vvar);
    if localvarlist[vvar] = varnum then exit;
   end;
   vvar := length(localvarlist);
   setlength(localvarlist, vvar + 1);
   localvarlist[vvar] := varnum;
  end;

  function capsize(intxt : UTF8string) : UTF8string;
  // Capitalizes the first character and lowercases the rest.
  // Also a ton of special cases. These are choice verbs or subjects, which
  // in the originals are in all capitals.
  var buh : byte;
  begin
   capsize := '';
   // Trim whitespace.
   while (length(intxt) <> 0) and (intxt[length(intxt)] = ' ') do setlength(intxt, length(intxt) - 1);
   while (length(intxt) <> 0) and (intxt[1] = ' ') do intxt := copy(intxt, 2, length(intxt));
   if intxt = '' then exit;

   // Capitalise appropriately if English text.
   if game in [gid_3SIS, gid_RUNAWAY, gid_SAKURA]
   then intxt := upcase(intxt[1]) + lowercase(copy(intxt, 2, length(intxt)));

   case game of
     gid_3SIS:
     begin
      if (scriptname = 'SK_215') or (scriptname = 'SK_315')
      or (scriptname = 'SK_614') or (scriptname = 'SK_517')
      then begin
       // Make the number selections more verbose in this script, for clarity
       case intxt[1] of
        '1': intxt := 'Focus harder';
        '2': intxt := 'Ignore being watched';
        '3': intxt := 'Enjoy being watched';
       end;
      end;
      if intxt = '''yes, i''m cold''' then capsize := '''Yes, I''m cold''';
      if intxt = 'Kaisan corp.' then capsize := 'Kaisan Corporation';
      if intxt = 'Tairiku indust.' then capsize := 'Tairiku Industries';
      if intxt = 'Kongoji zaibatsu' then capsize := 'Kongoji Zaibatsu';
      if intxt = 'R. gymnastics' then capsize := 'Rhythmic gymnastics';
      if intxt = 'Kumi akimoto' then capsize := 'Kumi Akimoto';
      if intxt = 'Chie makino' then capsize := 'Chie Makino';
      if intxt = 'Yuko uchimura' then capsize := 'Yuko Uchimura';
      if intxt = 'Chisato fujimura' then capsize := 'Chisato Fujimura';
      if intxt = 'No, i can''t' then capsize := 'No, I can''t';
      if intxt = 'Id card' then capsize := 'ID card';
      if capsize <> '' then exit;
      buh := pos('okamura', intxt);
      if buh <> 0 then intxt[buh] := 'O';
      buh := pos('emi', intxt);
      if buh <> 0 then intxt[buh] := 'E';
      buh := pos('risa', intxt);
      if buh <> 0 then intxt[buh] := 'R';
      buh := pos(' yuki', intxt);
      if buh <> 0 then intxt[buh + 1] := 'Y';
      buh := pos(' mana', intxt);
      if buh <> 0 then intxt[buh + 1] := 'M';
      buh := pos('eiichi', intxt);
      if buh <> 0 then intxt[buh] := 'E';
      buh := pos('taihei', intxt);
      if buh <> 0 then intxt[buh] := 'T';
     end;

     gid_RUNAWAY: begin
      if scriptname = 'MT_0208' then begin
       // Make the number selections more verbose in this script, for clarity
       case intxt[1] of
        '1': intxt := 'She was going inside?';
        '2': intxt := 'She slept there?';
        '3': intxt := 'She was forced there?';
        '4': intxt := 'Just a coincidence?';
        '5': intxt := 'She lives there?';
       end;
      end;
      if intxt = 'Virtual ninja' then capsize := 'Virtual Ninja' else
      if intxt = 'Where is yume?' then capsize := 'Where is Yume?' else
      if intxt = 'Vcr' then capsize := 'VCR' else
      if intxt = 'Tv' then capsize := 'TV';
      if copy(intxt, 1, 3) = 'S&m' then capsize := 'S&M' + lowercase(copy(intxt, 4, $FF));
      if intxt = 'Reach buddhahood' then capsize := 'Reach Buddhahood' else
      if intxt = 'Black snake' then capsize := 'Black Snake' else
      if intxt = 'Human completion' then capsize := 'Human Completion' else
      if intxt = 'Black science' then capsize := 'Black Science' else
      if intxt = 'Angel bait' then capsize := 'Angel Bait' else
      if intxt = 'How was i?' then capsize := 'How was I?';
      if capsize <> '' then exit;
      buh := pos('choko', intxt);
      if buh <> 0 then intxt[buh] := 'C';
      buh := pos('yumirin', intxt);
      if buh <> 0 then intxt[buh] := 'Y';
      buh := pos('fujiko', intxt);
      if buh <> 0 then intxt[buh] := 'F';
     end;

     gid_SAKURA: begin
      if intxt = 'Yamagami denki' then capsize := 'Yamagami Denki' else
      if intxt = 'V-ninja ii' then capsize := 'Virtual Ninja II' else
      if intxt = 'New years day' then capsize := 'New Year''s Day' else
      if intxt = 'Ask makoto' then capsize := 'Ask Makoto';
      if capsize <> '' then exit;
     end;
   end;

   // Common items in English.
   if game in [gid_3SIS,gid_RUNAWAY,gid_SAKURA] then begin
    // ugly hack, sometimes two separate "go" verbs in same script
    if intxt = 'G0' then intxt := 'Move';
    // trailing capital: Plan A, Plan B... 1-A, 2-B, 3-D...
    if (length(intxt) >= 3) and (intxt[length(intxt) - 1] in [' ','-'])
    then intxt[length(intxt)] := upcase(intxt[length(intxt)]);
    // single-quoted speech
    if intxt[1] = '''' then intxt[2] := upcase(intxt[2]);
    // forward slash, suggesting multiple speakers together
    buh := pos('/', intxt);
    if buh <> 0 then intxt[buh + 1] := upcase(intxt[buh + 1]);
    // period+space, probably "Mr. something" or "Dr. Negishi"
    buh := pos('. ', intxt);
    if buh <> 0 then intxt[buh + 2] := upcase(intxt[buh + 2]);
    // someone & someone else
    buh := pos(' & ', intxt);
    if buh <> 0 then intxt[buh + 3] := upcase(intxt[buh + 3]);

    capsize := intxt;
    exit;
   end;

   // Choice lines in Japanese games need to be converted to UTF-8.
   buh := 0;
   while buh < length(intxt) do begin
    inc(buh);
    if byte(intxt[buh]) in [$80..$A0,$E0..$EF] then begin
     capsize := capsize + GetUTF8(byte(intxt[buh]) shl 8 + byte(intxt[buh + 1]));
     inc(buh);
    end else begin
     capsize := capsize + GetUTF8(byte(intxt[buh]));
    end;
   end;

   case game of
     gid_SETSUJUU: begin
      // Cut out spaces from Japanese text, unnecessary. Snowcat in
      // particular uses hard spaces to fake text centering.
      buh := length(capsize);
      while buh <> 0 do begin
       // simple space
       if capsize[buh] = chr($20)
        then capsize := copy(capsize, 1, buh - 1) + copy(capsize, buh + 1, length(capsize)) else
       // ideographic space
       if (buh + 1 < length(capsize))
       and (byte(capsize[buh]) = $E3)
       and (byte(capsize[buh + 1]) = $80)
       and (byte(capsize[buh + 2]) = $80)
        then capsize := copy(capsize, 1, buh - 1) + copy(capsize, buh + 3, length(capsize));
       dec(buh);
      end;
     end;
   end;
  end;

  procedure WriteThwomp(numthwomp : byte; namu : string);
  // Writes out 1 + numthwomp vertical bashes.
  var ivar : byte;
  begin
   writebufln('gfx.bash 0 2000 10 14 ' + namu);
   ivar := numthwomp;
   while ivar <> 0 do begin
    dec(ivar);
    writebufln('sleep ' + strdec(240 + byte(numthwomp - ivar) shl 7));
    writebufln('gfx.bash 0 ' + strdec(2000 + byte(numthwomp - ivar) shl 8) + ' 10 14 ' + namu);
   end;
  end;

  procedure WriteBash(numbash : byte; namu : string);
  // Writes out 1 + numbash mostly horizontal bashes.
  begin
   writebufln('$v42 := rnd 4000 + 6000');
   writebufln('if rnd 2 = 0 then $v42 := -$v42 end');
   writebufln('$v43 := rnd 2048 - 512');
   writebufln('gfx.bash $v42 $v43 60 12 ' + namu);
   while numbash <> 0 do begin
    writebufln('sleep ' + strdec(480 + numbash shl 7));
    writebufln('$v42 := -$v42 + rnd 2000 - 1000');
    writebufln('$v43 := rnd 2048 - 512');
    writebufln('gfx.bash $v42 $v43 50 12 ' + namu);
    dec(numbash);
   end;
  end;

  procedure AutoloadAnims(const aninamu : string);
  // 3sis-era games automatically load animations when a sprite is loaded.
  // Some sprites have no animations, most have 1, a few have more than 1.
  var a : byte;
  begin
   a := 1;
   case game of

    gid_3SIS, gid_3SIS98: begin
     if aninamu = 'ST37' then a := 0
     else if aninamu = 'ST21' then a := 2; // Eiichi with Keiko, two eyepairs
    end;

    gid_RUNAWAY, gid_RUNAWAY98: begin
     if aninamu = 'MB07A' then a := 0; // arcade players overlay, no anims
    end;

    gid_SETSUJUU: begin
     a := 0; // Snowcat doesn't have sprite blinkies!
     if (copy(aninamu, 1, 3) = 'SH_') and (aninamu[length(aninamu)] <> 'S')
     then begin // but H-scenes do have anims...
      a := 1;
      if byte(valx(copy(aninamu, 4, 2))) in [3,6,7,10,13,15,17..20,24,28,32..34,37,49..51]
      then a := 0;
      if (aninamu = 'SH_31') or (aninamu = 'SH_38') or (aninamu = 'SH_52') then a := 2;
     end;
    end;

    gid_TRANSFER98: begin
     a := 0;
     // Sprite blinkies...
     if copy(aninamu, 1, 3) = 'TT_' then a := 1 else
     // Event blinkies...
     if aninamu = 'TI_006' then a := 1 else
     if aninamu = 'TI_029' then a := 2 else
     if aninamu = 'TH_067' then a := 2 else
     if (copy(aninamu, 1, 3) = 'TH_')
     and (byte(valx(copy(aninamu, 4, 3))) in [13,14,17,18,22,32..34,38..40,
       44..46,52..54,60..62,66,68,73,74,80,81,83,88..90,95..97,100..102,
       124..126,130..132]) then a := 1;
    end;

    gid_VANISH: begin
     if (aninamu = 'VT_012') or (aninamu = 'VT_018') or (aninamu = 'VT_019')
     then a := 2;
     if copy(aninamu, 1, 3) = 'VMT' then a := 0;
    end;

   end;
   while a <> 0 do begin
    dec(a);
    writebufln('gfx.show ' + aninamu + 'A' + strdec(a));
   end;
  end;

  procedure DoTextOutput;
  var printstr : UTF8string;
      printofs, jvar, lvar : dword;
      u8c : string[4];
      maybetitle : boolean;
  begin
   maybetitle := TRUE;
   implicitwaitkey := 2;
   printofs := 1;
   setlength(printstr, 256);
   dec(lofs); // step back to the character that triggered DoTextOutput

   {$ifdef enable_hacks}
   case game of
     gid_RUNAWAY: begin
      // Hack: don't interpret colon as a dialogue title
      if (scriptname = 'MT_0104') and (lofs = $166)
      or (scriptname = 'MT_0417') and (lofs = $2E4) then maybetitle := FALSE;
     end;

     gid_SAKURA: begin
      // Hack: don't interpret colon as a dialogue title
      if (scriptname = 'CSA08') and (lofs = $92F) then maybetitle := FALSE;
     end;
   end;

   // Special case: single dot followed by a brief sleep or something.
   // These should be marked as global since they're ubiquitous.
   if (word((loader + lofs)^) = $4581)
   and (byte((loader + lofs + 2)^) < $20)
   then writebuf('print ~"')
   else writebuf('print "');

   if game in
   [gid_3SIS98, gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2, gid_EDEN,
   gid_FROMH, gid_MAJOKKO, gid_PARFAIT, gid_RUNAWAY98, gid_SAKURA98,
   gid_SETSUJUU, gid_TRANSFER98, gid_TASOGARE, gid_VANISH]
   then begin
    // Catch Shift-JIS dialogue titles, written as "[name]:"
    if word((loader + lofs)^) = $7981 then begin
     jvar := 2;
     while (jvar <= 20) and (word((loader + lofs + jvar)^) <> $7A81) do begin
      lvar := byte((loader + lofs + jvar)^); inc(jvar);
      // double-byte?
      if lvar in [$81..$84,$88..$9F,$E0..$EA] then begin
       lvar := lvar shl 8 + byte((loader + lofs + jvar)^); inc(jvar);
      end;
      // add each character to printstr, except in-text spaces in snowcat
      if (game <> gid_SETSUJUU) or (lvar <> $8140) then begin
       u8c := GetUTF8(lvar);
       if printofs + 8 >= dword(length(printstr)) then setlength(printstr, length(printstr) + 128);
       move(u8c[1], printstr[printofs], length(u8c));
       inc(printofs, length(u8c));
      end;
     end;

     if word((loader + lofs + jvar)^) = $7A81 then begin
      inc(lofs, jvar + 2);

      if copy(printstr, 1, 2) = '%0' then
       writebuf('\$s' + strdec(valx(printstr)) + ';')
      else
       writebuf(printstr, printofs - 1);
      writebuf('\:');
      if word((loader + lofs)^) = $4681 then inc(lofs, 2) // ":"
      else if byte((loader + lofs)^) = $3A then inc(lofs); // ":"
      if byte((loader + lofs)^) = $A then inc(lofs); // linebreak
      maybetitle := FALSE;
     end;
    end;
   end;

   // Eliminate useless starting spaces
   if game = gid_FROMH then begin
    //if byte((loader + lofs)^) = $A then inc(lofs);
    if (word((loader + lofs)^) = $4081)
    and (word((loader + lofs + 2)^) <> $4081)
    then inc(lofs, 2);
   end;
   {$endif enable_hacks}

   printofs := 1;
   jvar := byte((loader + lofs)^);
   while jvar in [$0A, $20..$EF] do begin

    // expand the string variable if necessary.
    if printofs + 8 >= dword(length(printstr)) then setlength(printstr, length(printstr) + 128);

    {$ifdef enable_hacks}
    // Catch "--" and replace it with a long dash
    if (game in [gid_3SIS, gid_RUNAWAY, gid_SAKURA])
    and (word((loader + lofs)^) = $2D2D) then begin
     byte(printstr[printofs]) := $E2; inc(printofs);
     byte(printstr[printofs]) := $80; inc(printofs);
     byte(printstr[printofs]) := $93; inc(printofs);
     inc(lofs, 2);
     jvar := byte((loader + lofs)^);
     continue;
    end;
    {$endif enable_hacks}

    case jvar of
      $0A: // linefeed CR
      begin
       if game in [gid_3SIS, gid_RUNAWAY, gid_SAKURA] then begin
        // latin alphabet
        // write nothing if there's a hyphen or space already
        if (char((loader + lofs - 1)^) <> '-')
        and (char((loader + lofs - 1)^) <> ' ')
        and (char((loader + lofs + 1)^) <> ' ') then begin
         // replace it with a space in most cases,
         // unless it's the string's last character.
         if (byte((loader + lofs + 1)^) < 32) then begin
          if printofs > 1 then begin
           printstr[printofs] := '\'; inc(printofs);
           printstr[printofs] := 'n'; inc(printofs);
           inc(lofs);
           break;
          end;
         end else begin
          // replace with a space
          printstr[printofs] := ' '; inc(printofs);
         end;
        end;

       end
       // shift-jis
       else begin
        printstr[printofs] := '\'; inc(printofs);
        printstr[printofs] := 'n'; inc(printofs);
        inc(lofs);
        break;
       end;
      end;

      // double-quotes and backslashes must be escaped
      $22,$5C: begin
       printstr[printofs] := '\'; inc(printofs);
       printstr[printofs] := chr(jvar); inc(printofs);
      end;

      {$ifdef enable_hacks}
      // change string var %00x to use our escape code + end mark
      $25: begin
       lvar := dword((loader + lofs)^);
       if lvar and $FFFF = $3025 then begin
        lvar := ((lvar shr 24) and $F) + ((lvar shr 16) and $F * 10);
        inc(lofs, 3);
        printstr[printofs] := '\'; inc(printofs);
        printstr[printofs] := '$'; inc(printofs);
        printstr[printofs] := 's'; inc(printofs);
        u8c := strdec(lvar);
        move(u8c[1], printstr[printofs], length(u8c));
        inc(printofs, length(u8c));
        printstr[printofs] := ';'; inc(printofs);
       end else begin
        printstr[printofs] := chr(jvar); inc(printofs);
       end;
      end;

      // change ":  " and ": " to a title identifier mark,
      // but only if we are still close to the line beginning.
      $3A: begin
       if (byte((loader + lofs + 1)^) = 32) then begin
        lvar := 1;
        if (byte((loader + lofs + 2)^) = 32) then inc(lvar);
        if (printofs < 32) and (maybetitle) then begin
         inc(lofs, lvar);
         maybetitle := FALSE;
         if printstr[1] = ' ' then writebuf(copy(printstr, 2, printofs - 2))
         else writebuf(printstr, printofs - 1);
         writebuf('\:');
         printofs := 1;
        end
        else begin
         printstr[printofs] := chr(jvar); inc(printofs);
        end;
       end else begin
        printstr[printofs] := chr(jvar); inc(printofs);
       end;
      end;
      {$endif enable_hacks}

      // Double-byte JIS
      $81..$9F, $E0..$EF: begin
       inc(lofs);
       u8c := GetUTF8(jvar shl 8 + byte((loader + lofs)^));
       move(u8c[1], printstr[printofs], length(u8c));
       inc(printofs, length(u8c));
      end;

      // Single-byte katakana
      $A1..$DF: begin
       u8c := GetUTF8(jvar);
       move(u8c[1], printstr[printofs], length(u8c));
       inc(printofs, length(u8c));
      end;

      // Single-byte plain ASCII
      else begin
       printstr[printofs] := chr(jvar); inc(printofs);
      end;
    end;

    inc(lofs);
    jvar := byte((loader + lofs)^);
    {$ifdef enable_hacks}
    // Jump into the middle of a string... add a string break
    if (game = gid_ANGELSCOLLECTION1) and (scriptname = 'SCB12') and (lofs = $20C)
    or (game = gid_ANGELSCOLLECTION2) and (scriptname = 'S2_009') and (lofs = $18B)
    or (game = gid_VANISH) and (scriptname = 'EB049_01') and (lofs = $9A6)
    then break;
    {$endif enable_hacks}
   end;

   // Write out the print command
   writebuf(printstr, printofs - 1);
   writebufln('"');
  end;

begin
 // Load the input file into loader^. Unless the source file name is an .exe,
 // in which case assume it's already loaded.
 Decomp_JastOvl := '';
 if upcase(ExtractFileExt(srcfile)) <> '.EXE' then begin
  Decomp_JastOvl := LoadFile(srcfile);
  if Decomp_JastOvl <> '' then exit;
 end;

 scriptname := ExtractFileName(outputfile);
 scriptname := upcase(copy(scriptname, 1, length(scriptname) - length(ExtractFileExt(scriptname))));

 nextgra.style := 0; // just to remove a compiler warning
 animslot[0].ofsx := 0;
 choicecombo[0].id := 0;
 gfxlist[0].gfxname := '';
 lastbkg := '';

 // Initialisation
 setlength(outbuf.labellist, 640);
 setlength(outbuf.linelist, 640);
 outbuf.labellist[0] := 0;
 outbuf.linelist[0] := '';
 outbuf.bufindex := 0;
 setlength(jumplist, 64);
 jumpcount := 0;
 setlength(localvarlist, 0);

 fillbyte(animslot[0], length(animslot) * sizeof(animslot[0]), 0);

 for ivar := 1 to high(optionlist) do begin
  optionlist[ivar].verbtext := '';
  for jvar := 1 to dword(high(optionlist[1].subjecttext)) do optionlist[ivar].subjecttext[jvar] := '';
 end;
 haschoices := FALSE;
 persistence := FALSE;
 combos := 0; options := 0; pictures := 0;
 for ivar := dword(high(stringcache)) downto 0 do stringcache[ivar] := '';

 // Variable references can be 8-bit or 16-bit, though the vars themselves at
 // runtime are always 16-bit signed.
 bitness := 1;
 if game in [gid_PARFAIT] then bitness := 2;

 {$ifdef enable_hacks}
 // HACK collection, fixes for original bugs and decompilation issues
 case game of
  gid_3SIS: begin
   // Hack: split a thought due to a jump into the middle of a string
   if scriptname = 'SK_103' then byte((loader + $9EE)^) := 1;
   // Hack: replace waitkey.noclear with plain waitkey, also remove a space
   if scriptname = 'SK_105' then word((loader + $715)^) := $0120;
   // Hack: remove a hyphen
   if scriptname = 'SK_108' then begin
    txt := 'tution scandal.  ';
    move(txt[1], (loader + $470)^, length(txt));
   end;
   // Hack: add a waitkey
   if scriptname = 'SK_112' then word((loader + $BB9)^) := $0121;
   // Hack: add a waitkey that's supposed to be there
   if scriptname = 'SK_121' then begin
    txt := chr(1) + '%001:';
    move(txt[1], (loader + $2D0)^, length(txt));
   end;
   // Hack: change a choice variable to use a unique tracking variable
   if scriptname = 'SK_212' then byte((loader + $1BA)^) := $10;
   // Hack: fix bug in original, jumps to exit instead of start of string
   if scriptname = 'SK_213' then inc(byte((loader + $907)^));
   // Hack: add a missing graphic that seems to crash even the original
   if scriptname = 'SK_406' then begin
    gfxlist[2].gfxname := 'TB_000';
    gfxlist[2].data1 := 7;
    gfxlist[2].data2 := $4E;
   end;
   if scriptname = 'SK_737' then begin
    // Hack: cut common ending sequence, replace with call to ENDINGS (2)
    txt := chr(1) + chr($C) + chr(3) + chr($FF) + chr(2) + chr(4) + 'ENDINGS' + chr(0);
    fillbyte((loader + $88E)^, 1996, 0);
    move(txt[1], (loader + $88C)^, length(txt));
   end;
   if scriptname = 'SK_738' then begin
    // Hack: change a final IF into a catch-all ELSE
    dword((loader + $123)^) := $00162336;
    // Hack: eliminate unnecessary 5-second sleeps
    txt := chr(1) + chr($B) + chr($36) + chr($7C) + chr($19) + chr(0);
    move(txt[1], (loader + $4BE)^, length(txt));
    move(txt[1], (loader + $84D)^, length(txt));
    move(txt[1], (loader + $BDD)^, length(txt));
    move(txt[1], (loader + $F6C)^, length(txt));
    move(txt[1], (loader + $12BF)^, length(txt));
    move(txt[1], (loader + $161B)^, length(txt));
    move(txt[1], (loader + $1974)^, length(txt));
    // Hack: cut common ending sequence, replace with call to ENDINGS (1)
    txt := chr($C) + chr(3) + chr($FF) + chr(1) + chr(4) + 'ENDINGS' + chr(0);
    move(txt[1], (loader + $197C)^, length(txt));
    loadersize := $197C + length(txt);
   end;
   if scriptname = 'SK_743' then begin
    // Hack: add a missing waitkey
    txt := chr(1) + '%001:'; move(txt[1], (loader + $6B9)^, length(txt));
    // Hack: cut common ending sequence, replace with call to ENDINGS (0)
    txt := chr($C) + chr(3) + chr($FF) + chr(0) + chr(4) + 'ENDINGS' + chr(0);
    move(txt[1], (loader + $756)^, length(txt));
    loadersize := $756 + length(txt);
   end;
  end;

  gid_3SIS98: begin
   // Hack: replace a newline with a waitkey
   if scriptname = 'SK_106' then byte((loader + $1BF)^) := 1;
   // Hack: fix a jump into the middle of a string
   if scriptname = 'SK_406' then word((loader + $A1)^) := $5F4;
  end;

  gid_ANGELSCOLLECTION2: begin
   // Hack: change weird 8757 Shift-JIS to a visually similar double-slash
   if scriptname = 'S2_007' then word((loader + $349)^) := $2F2F;
   // Hack: clip unreachable code
   if scriptname = 'S4_016' then loadersize := $61D;
   if scriptname = 'S4_021' then loadersize := $C4;
   if scriptname = 'S4_022' then loadersize := $112;
   if scriptname = 'S4_027' then loadersize := $3F;
   if scriptname = 'S4_031' then loadersize := $25C;
   if scriptname = 'S4_035' then loadersize := $74;
   if scriptname = 'S4_036' then loadersize := $2BB;
   if scriptname = 'S4_043' then loadersize := $109;
   if scriptname = 'S4_044' then loadersize := $66F;
   if scriptname = 'S4_051' then loadersize := $1C5;
   if scriptname = 'S4_052' then loadersize := $182;
   if scriptname = 'S4_064' then loadersize := $62B;
   if scriptname = 'S4_071' then loadersize := $17E;
   if scriptname = 'S4_072' then loadersize := $1C9;
   if scriptname = 'S4_073' then loadersize := $6F9;
   // Hack: erase problems in reachable but redundant code
   if scriptname = 'S4_067' then dword((loader + $30C)^) := 0;
   if scriptname = 'S4_068' then dword((loader + $3E0)^) := 0;
   if scriptname = 'S4_070' then dword((loader + $1C9)^) := 0;
  end;

  gid_DEEP: begin
   // Hack: restore incorrectly missing actions... even if they were disabled
   // on purpose, it's throwing my header parser off
   if scriptname = 'H03_08' then word((loader + $22)^) := $008D;
   if scriptname = 'H04_03' then word((loader + $2A)^) := $00AE;
  end;

  gid_EDEN: begin
   // Hack: remove a dummy 09 opcode by adding a space and shifting text
   if scriptname = 'JO4101' then begin
    //txt := ' ' + chr(1) + 'ÅyÉWÉá';
    //move(txt[1], (loader + $D1)^, length(txt));
    dword((loader + $D1)^) := $79810120;
    dword((loader + $D5)^) := $87835783;
   end;
  end;

  gid_FROMH: begin
   // Hack: Correct 0B-4B item count, enables unaccessible code
   if scriptname = 'AT_002' then inc(byte((loader + $1041)^));
   // Hack: Correct 0B-4B item count
   if scriptname = 'MT_004' then inc(byte((loader + $3A1F)^));
   // Hack: Correct 0B-4B item count
   if scriptname = 'RT_001' then inc(byte((loader + $95A)^));
   // Hack: Correct 0B-4B item count
   if scriptname = 'RT_001B' then inc(byte((loader + $958)^));
  end;

  gid_MAJOKKO: begin
   // Hack: separate two exit commands so the latter can be jumped to
   if scriptname = 'MP7809' then byte((loader + $FAF)^) := 1;
   if scriptname = 'MP780E' then byte((loader + $1083)^) := 1;
   if scriptname = 'MP7A09' then byte((loader + $10DA)^) := 1;
   if scriptname = 'MP7A0E' then byte((loader + $102E)^) := 1;
   if scriptname = 'MP7C08' then byte((loader + $FD9)^) := 1;
   if scriptname = 'MP7C0D' then byte((loader + $FD5)^) := 1;
  end;

  gid_RUNAWAY: begin
   // Hack: change a dash into a long dash
   if scriptname = 'MT_0101' then byte((loader + $1F9C)^) := $2D;
   // Hack: fix typo
   if scriptname = 'MT_0116' then word((loader + $99)^) := $524F;
   // Hack: separate two dialogue lines
   if scriptname = 'MT_0208' then byte((loader + $942)^) := 1;
   // Hack: remove extraneous waitkey
   if scriptname = 'MT_0214' then char((loader + $B49)^) := ' ';
   // Hack: split dialogue lines
   if scriptname = 'MT_0218' then begin
    byte((loader + $7C)^) := 1;
    byte((loader + $AD)^) := 1;
   end;
   // Hack: remove a waitkey
   if scriptname = 'MT_0304' then char((loader + $E43)^) := ' ';
   // Hack: particularly ugly, two separate verbs GO, change one to G0
   if scriptname = 'MT_0305' then char((loader + $C0)^) := '0';
   // Hack: remove a waitkey
   if scriptname = 'MT_0808' then char((loader + $1091)^) := ' ';
   // Hack: remove a double-quote
   if scriptname = 'MT_1002' then char((loader + $1EB7)^) := ' ';
   // Hack: another one, PROCEED x2, change one to Pr0ceed
   if scriptname = 'MT_1003' then char((loader + $CA)^) := '0';
   // Hack: unreachable code causes parsing errors, just snip it out
   if scriptname = 'MT_1118' then loadersize := $38A;
   if scriptname = 'MT_1119' then loadersize := $8BD;
   // Hack: shift ENDINGS hook a bit earlier
   if scriptname = 'MT_9906' then word((loader + $2BA)^) := $0010;
  end;

  gid_SAKURA: begin
   // Hack: split two lines from one dialogue entry, twice
   if scriptname = 'CS103' then begin
    byte((loader + $9FC)^) := 1;
    byte((loader + $A36)^) := 1;
   end;
   // Hack: change %100 to %001
   if scriptname = 'CS104' then dword((loader + $11C6)^) := $20313030;
   // Hack: change odd transition to a crossfade
   if scriptname = 'CS208' then byte((loader + $51A)^) := $3B;
   // Hack: remove trailing space from TALK
   if scriptname = 'CS211' then byte((loader + $3D)^) := 0;
   // Hack: change THINK + GIRL to just THINK (inconsistent scripting)
   if scriptname = 'CS212' then word((loader + $67)^) := $FFFF;
   // Hack: change TALK + BAGS to just TALK
   if scriptname = 'CS403' then word((loader + $78)^) := $FFFF;
   if scriptname = 'CS501' then begin
    // Hack: split two lines from one dialogue entry
    byte((loader + $419)^) := 1;
    // Hack: add a waitkey to keep lines apart
    byte((loader + $5CB)^) := 1;
    // Hack: change "Shuji..." to "%001... "
    dword((loader + $CEB)^) := $31303025;
    dword((loader + $CEF)^) := $202E2E2E;
   end;
   // Hack: fix inconsistent clothing change
   if scriptname = 'CS510_11' then char((loader + $172)^) := 'F';
   // Hack: fix an animation slot
   if scriptname = 'CS514_E' then byte((loader + $DCA)^) := 3;
   // Hack: split two lines from one dialogue entry
   if scriptname = 'CS601' then byte((loader + $BFB)^) := 1;
   // Hack: eliminate a false positive dialogue title
   if scriptname = 'CS605' then char((loader + $36A)^) := '!';
   // Hack: split two lines from one dialogue entry
   if scriptname = 'CS702' then byte((loader + $4C4)^) := 1;
   // Hack: split two lines from one dialogue entry
   if scriptname = 'CS704' then byte((loader + $67C)^) := 1;
   // Hack: split two lines from one dialogue entry, and combine three titles
   if scriptname = 'CS705' then begin
    byte((loader + $374)^) := 1;
    txt := '/Kiyomi/Mio:  %001!!' + space(18);
    move(txt[1], (loader + $643)^, length(txt));
    // Hack: translation error, should be Hidemi instead of Meimi
    txt := 'Hidemi:';
    move(txt[1], (loader + $C52)^, length(txt));
   end;
   // Hack: combine 3 titles, split dialogue pair
   if scriptname = 'CS707' then begin
    txt := '/Kiyomi/Mio:  %001!!' + space(15);
    move(txt[1], (loader + $670)^, length(txt));
    byte((loader + $FFD)^) := 1;
   end;
   // Hack: split two lines from one dialogue entry, premature slot call fix
   if scriptname = 'CS801_3' then begin
    byte((loader + $96A)^) := 1;
    animslot[6].ofsx := 96; animslot[6].namu := 'CT03A0';
    animslot[5].namu := 'CT02IA0';
   end;
   if scriptname = 'CS801_4' then begin
    // Hack: combine three synchronized exclamations
    txt := '/Kiyomi/Mio:  %001!' + space(15);
    move(txt[1], (loader + $A38)^, length(txt));
    // Hack: remove unintended exit, enabling unreachable code
    byte((loader + $40A)^) := $20;
   end;
   // Hack: split Reiko/Mio lines properly
   if scriptname = 'CS804' then begin
    byte((loader + $12F)^) := 1;
    txt := '/Mio:  ';
    move(txt[1], (loader + $199)^, length(txt));
    move(txt[1], (loader + $3E6)^, length(txt));
    txt := '.......';
    move(txt[1], (loader + $1B4)^, length(txt));
    move(txt[1], (loader + $405)^, length(txt));
   end;
   // Hack: split Meimi/Seia line
   if scriptname = 'CS810' then byte((loader + $DB4)^) := 1;
   // Hack: fix original animation slot bugs
   if scriptname = 'CS810_1' then begin
    byte((loader + $E8)^) := 1;
    byte((loader + $1C3)^) := 7;
   end;
   // Hack: combine *pantpant* lines
   if scriptname = 'CS811' then begin
    txt := '/Aki:  *pant pant*' + space(14);
    move(txt[1], (loader + $4B0)^, length(txt));
    move(txt[1], (loader + $51B)^, length(txt));
    txt := '/Girl:  *pant pant*' + space(14);
    move(txt[1], (loader + $53F)^, length(txt));
    txt := '/%001:  *pant pant pant*' + space(19);
    move(txt[1], (loader + $6E3)^, length(txt));
    txt := '/Girl:  *pant pant pant*' + space(19);
    move(txt[1], (loader + $712)^, length(txt));
    move(txt[1], (loader + $7F3)^, length(txt));
    move(txt[1], (loader + $83D)^, length(txt));
    move(txt[1], (loader + $9A1)^, length(txt));
    move(txt[1], (loader + $AA6)^, length(txt));
   end;
   // Hack: fix a dialogue title
   if scriptname = 'CS819' then begin
    txt := ':  ';
    move(txt[1], (loader + $AA4)^, length(txt));
   end;
   // Hack: make a waitkey nonclearing
   if scriptname = 'CS824' then byte((loader + $77E)^) := 8;
   // Hack: split dialogue lines
   if scriptname = 'CS901' then begin
    byte((loader + $2A7)^) := 1;
    byte((loader + $31A)^) := 1;
    byte((loader + $383)^) := 1;
   end;
   // Hack: skip over useless code
   if scriptname = 'CS904_A' then begin
    dword((loader + $72)^) := $008D360B;
    fillbyte((loader + $76)^, 10, 0);
   end;
   // Hack: remove an extraneous waitkey
   if scriptname = 'CS904_H' then byte((loader + $743)^) := 32;
   // Hack: change a waitkey to noclear
   if scriptname = 'CSA01' then byte((loader + $534)^) := 8;
   // Hack: force a linefeed
   if scriptname = 'CSA10' then byte((loader + $847)^) := $A;
   // Hack: force linefeeds in read mini-letters, signature tries to be sort
   // of right-aligned by using lots of whitespace
   if scriptname = 'CSB05_' then begin
    byte((loader + $D4B)^) := 10;
    byte((loader + $EB2)^) := 10;
    byte((loader + $1037)^) := 10;
   end;
   // Hack: Replace some exits with returns for consistency
   if scriptname = 'CSC01_A' then begin
    byte((loader + $7E8)^) := 3;
    byte((loader + $908)^) := 3;
    byte((loader + $A3F)^) := 3;
    byte((loader + $B47)^) := 3;
   end;
   if scriptname = 'CSC01_C' then begin
    byte((loader + $789)^) := 3;
    byte((loader + $80E)^) := 3;
    byte((loader + $944)^) := 3;
    byte((loader + $A24)^) := 3;
   end;
   if scriptname = 'CSC01_F' then begin
    byte((loader + $69B)^) := 3;
    byte((loader + $6A1)^) := 3;
    byte((loader + $7A2)^) := 3;
    byte((loader + $7CC)^) := 3;
    byte((loader + $85C)^) := 3;
    byte((loader + $890)^) := 3;
    byte((loader + $970)^) := 3;
   end;
   if scriptname = 'CSE_ABAD' then begin
    // Hack: change "Shuji..." to "%001...."
    dword((loader + $88)^) := $31303025;
    byte((loader + $8C)^) := $2E;
   end;
   // Hack: fix a title
   if scriptname = 'CSE_BBAD' then char((loader + $2FA)^) := ':';
   // Hack: force a linefeed
   if scriptname = 'CSE_E_7' then byte((loader + $A72)^) := 10;
   // Hack: fix anim slot 20 to something smaller
   if scriptname = 'CSE_FBAD' then byte((loader + $4A2)^) := 8;
   // Hack: split dialogue lines
   if scriptname = 'CSE_H_1' then begin
    byte((loader + $2A5)^) := 1;
    byte((loader + $2CC)^) := 1;
   end;
  end;

  gid_SAKURA98: begin
   // Hack: premature slot call fix
   if scriptname = 'CS801_3' then begin
    animslot[6].ofsx := 96; animslot[6].namu := 'CT03A0';
    animslot[5].namu := 'CT02IA0';
   end;
   // Hack: fix original animation slot bugs
   if scriptname = 'CS810_1' then begin
    byte((loader + $E0)^) := 1;
    byte((loader + $1EF)^) := 7;
   end;
   // Hack: Replace some exits with returns for consistency
   if scriptname = 'CSC01_A' then begin
    byte((loader + $7F8)^) := 3;
    byte((loader + $906)^) := 3;
    byte((loader + $A62)^) := 3;
    byte((loader + $BA1)^) := 3;
   end;
   if scriptname = 'CSC01_C' then begin
    byte((loader + $887)^) := 3;
    byte((loader + $93E)^) := 3;
    byte((loader + $AC6)^) := 3;
    byte((loader + $BCB)^) := 3;
   end;
   if scriptname = 'CSC01_F' then begin
    byte((loader + $784)^) := 3;
    byte((loader + $78A)^) := 3;
    byte((loader + $88C)^) := 3;
    byte((loader + $8C6)^) := 3;
    byte((loader + $994)^) := 3;
    byte((loader + $9DC)^) := 3;
    byte((loader + $AB9)^) := 3;
   end;
  end;

  gid_SETSUJUU: begin
   // Hack: change erroneous choice.off to a repeat of previous
   if scriptname = 'SMG_S031' then byte((loader + $17B)^) := 2;
  end;

  gid_TRANSFER98: begin
   // Hack: separate dialogue lines
   if scriptname = 'TEN_S007' then byte((loader + $1E4)^) := 1;
   // Hack: fix graphic type
   if scriptname = 'TEN_S069' then byte((loader + $33)^) := $4E;
   // Hack: fix graphic type
   if scriptname = 'TEN_S105' then byte((loader + $51)^) := $4E;
   // Hack: fix graphic type
   if scriptname = 'TEN_S106' then byte((loader + $3E)^) := $4E;
   // Hack: fix a missing graphic definition
   if scriptname = 'TEN_S108' then begin
    gfxlist[2].gfxname := 'TT_02';
    gfxlist[2].data1 := 9;
    gfxlist[2].data2 := $38;
   end;
  end;

  gid_TASOGARE: begin
   // Hack: streamline 0F ending minicode segments
   if scriptname = 'TA_ED01' then begin
    byte((loader + $637)^) := 0;
    byte((loader + $C46)^) := 0;
    dec(loadersize);
   end;
   if scriptname = 'TA_ED02' then begin
    txt := chr($F) + chr(1) + 'YE_041' + chr(0) + chr(3);
    move(txt[1], (loader + $600)^, length(txt));
    dword((loader + $7C7)^) := $8103040F;
    byte((loader + $830)^) := 0;
    byte((loader + $EC5)^) := 0;
    txt[8] := '0';
    move(txt[1], (loader + $134A)^, length(txt));
    byte((loader + $185F)^) := 0;
   end;
   if scriptname = 'TA_00DG' then begin
    // Hack: fix incorrect variable reference, triggers some new strings
    inc(byte((loader + $2C)^));
    // Hack: add a missing exit
    dword((loader + $84E)^) := $00000300;
   end;
   if scriptname = 'TA_0801' then begin
    // Hack: correct 0B-4B item count, enables previously unreachable code,
    //   although all that does is an 11-04 and return to the same choices.
    byte((loader + $DA6)^) := 3;
    // Hack: avoid a double-waitkey by jumping a byte further
    inc(byte((loader + $471)^));
   end;
   // Hack: add a missing script name
   if scriptname = 'TA_1402' then begin
    inc(loadersize, 3); reallocmem(loader, loadersize);
    txt := 'TA_1100' + chr(0); move(txt[1], (loader + $134A)^, length(txt));
   end;
   // Hack: eliminate a troublesome lone linebreak
   if scriptname = 'TA_2403' then word((loader + $413)^) := $0413;
   // Hack: correct 0B-4B item count
   if scriptname = 'TA_3803' then dec(byte((loader + $2DBE)^));
   if scriptname = 'TA_4001' then begin
    // Hack: correct 0B-4B item count, enables previously unreachable code
    byte((loader + $1580)^) := 3;
    // Hack: correct bug in said unreachable code
    for ivar := $16A0 to $16B1 do byte((loader + ivar)^) := byte((loader + ivar + 1)^);
   end;
   // Hack: eliminate a troublesome lone linebreak
   if scriptname = 'TA_4908' then dword((loader + $901)^) := $01011620;
  end;

  gid_VANISH: begin
   // Hack: remove unaccessable code
   if scriptname = 'EB020' then loadersize := $6B;
   // Hack: remove unaccessable code
   if scriptname = 'EB040' then loadersize := $71;
   // Hack: remove unaccessable code
   if scriptname = 'EB045' then loadersize := $68;
   // Hack: remove unaccessable code
   if scriptname = 'EB046' then loadersize := $68;
   // Hack: remove unaccessable code
   if scriptname = 'EB049' then loadersize := $68;
  end;

 end;
 {$endif enable_hacks}

 ptrscript := 0;

 // Maririn DX has a wholly different header, handled here
 if game = gid_MARIRIN then begin
  ptrresults := word(loader^);
  ptrscript := word((loader + word((loader + 2)^) )^);
  writebufln('// ID list:');
  lofs := ptrresults;
  while (lofs < loadersize) and (lofs < word((loader + ptrresults)^)) do begin
   ivar := word((loader + lofs)^); // current word pointer
   inc(lofs, 2);
   if lofs < word((loader + ptrresults)^)
    then jvar := word((loader + lofs)^) else jvar := ptrscript;
   dec(jvar, ivar);
   writebuf('//');
   for gutan := 1 to jvar do begin
    txt := strhex(byte((loader + ivar)^));
    if length(txt) = 1 then txt := '0' + txt;
    writebuf(' ' + txt);
    inc(ivar);
   end;
   writebufln('');
  end;
  writebufln('');
  lofs := ptrscript;
 end else

 // Deep has a different header, handled here
 if game = gid_DEEP then begin
  // Read constant pointers
  ptrresults := word(loader^);
  ptrscript := word((loader + 2)^);
  ptrpix := word((loader + 4)^);
  ptrnil := word((loader + 6)^);
  if ptrresults in [0,6,8] = FALSE then begin
   PrintError('Script header starts with $' + strhex(ptrresults) + '??'); exit;
  end;
  if ptrresults = 6 then begin // alternative tiny header skips first array
   ptrnil := ptrpix; ptrpix := ptrscript; ptrscript := ptrresults;
  end else
  if ptrresults = 0 then begin // alternative bloated header with extra 0000
   ptrresults := ptrscript; ptrscript := ptrpix; ptrpix := ptrnil;
   ptrnil := word((loader + 8)^);
  end;
  // Read local var list? or action mapping? from fourth array
  lvar := word((loader + ptrresults)^);
  if lvar = 0 then lvar := word((loader + ptrscript)^);
  writebuf('// Fourth array:');
  while (ptrnil < lvar) do begin
   writebuf(' ' + strdec(byte((loader + ptrnil)^)));
   inc(ptrnil);
  end;
  writebufln('');
  lofs := word((loader + ptrscript)^); // script main entry point
  // Read click action list, from first array
  if word((loader + ptrresults)^) <> 0 then
  while (ptrresults < ptrscript) do begin
   writebuf('// ');
   ptrnil := word((loader + ptrresults)^);
   case byte((loader + ptrnil)^) of // action type
    1: writebuf('Look');
    2: writebuf('Go');
    3: writebuf('Talk');
    4: writebuf('Hit');
    5: writebuf('Push');
    6: writebuf('Open');
    7: writebuf('Touch');
    8: writebuf('Lick');
    9: writebuf('Kiss');
    10: writebuf('Drill');
    else writebuf('Unknown action ' + strdec(byte((loader + ptrnil)^)));
   end;
   inc(ptrnil); // local var number
   writebuf(': $v' + strdec(byte((loader + ptrnil)^)));
   inc(ptrnil);
   while (ptrnil < word((loader + ptrresults + 2)^)) do begin
    ivar := byte((loader + ptrnil)^); // jump addresses
    if ivar = 0 then begin PrintError('0!!!'); exit; end;
    dec(ivar); // make it 0-based
    txt := strhex(word((loader + ptrscript + ivar * 2)^));
    while length(txt) < 4 do txt := '0' + txt;
    writebuf('; ' + txt);
    inc(ptrnil);
   end;
   writebufln('');
   inc(ptrresults, 2);
  end;
  writebufln(''); // empty line before code starts
 end else

 // Tasogare no Kyoukai has a different header for dungeons, handled here
 if (game = gid_TASOGARE) and (scriptname = 'TA_00DG') then begin
  writebufln('// OVL is divided in four sections, so work around it with a case jump');
  writebufln('case $v512 SHR 8; ."noarray:array2:array4:array6"');
  writebufln('');
  ptrscript := word(loader^);
  ivar := 2;
  while ivar < ptrscript do begin
   writebufln('');
   writebufln('@array' + strdec(ivar) + ':');
   writebuf('case $v512 AND 0xFF; ."');
   jvar := word((loader + ivar)^);
   lofs := jvar;
   while lofs < word((loader + jvar)^) do begin
    if lofs <> jvar then writebuf(':');
    gutan := word((loader + lofs)^);
    txt := strhex(gutan);
    while length(txt) < 4 do txt := '0' + txt;
    writebuf(txt);
    inc(lofs, 2);
   end;
   writebufln('"');
   fillbyte((loader + jvar)^, lofs - jvar, 0);
   inc(ivar, 2);
  end;
  writebufln('');
  writebufln('@noarray:');
  lofs := 8;
 end else

 // If option lists exist, handle them; sometimes it's plain code, no lists
 if word(loader^) in [$0008, $000A, $000C] then begin
  // Read constant pointers
  ptrresults := word(loader^);
  ptrscript := word((loader + 2)^);
  ptroptions := word((loader + 4)^);
  ptrpix := word((loader + 6)^);
  ptrnil := word((loader + 8)^);

  // Get the address of the bytecode entrypoint
  ptrscript := word((loader + ptrscript)^);

  // First word array must have non-zero length, and the first offset must be
  // valid, otherwise there are no choices to be made.
  lofs := word((loader + ptrresults)^);
  if (ptrresults < word((loader + 2)^))
  and (lofs > ptrnil) and (lofs < ptrscript)
  then begin
   // Read the choice combination records
   repeat
    if combos > high(choicecombo) then begin PrintError('Choicecombo overflow @ $' + strhex(lofs)); exit; end;
    // verb pointer
    ivar := word((loader + lofs)^); inc(lofs, 2);
    if (ivar <= ptrnil) or (ivar >= ptrscript) then break; // validity check
    choicecombo[combos].verbtext := capsize(GetLoaderString(ivar + 1));
    // subject pointer
    ivar := word((loader + lofs)^); inc(lofs, 2);
    if (ivar <= ptrnil) or (ivar >= ptrscript) // validity check
    then choicecombo[combos].subjecttext := ''
    else choicecombo[combos].subjecttext := capsize(GetLoaderString(ivar + 1));
    // variable ID
    choicecombo[combos].ID := word((loader + lofs)^); inc(lofs, 2);
    // jump addresses, read up to first invalid address or start of bytecode
    lvar := 0;
    repeat
     ivar := word((loader + lofs)^);
     if (ivar < ptrscript) or (lofs >= ptrscript) then break;
     if lvar >= high(choicecombo[1].jumpresult) then begin PrintError('Choicecombo jumpresult overflow @ $' + strhex(lofs)); exit; end;
     choicecombo[combos].jumpresult[lvar] := ivar;
     inc(lvar); inc(lofs, 2);
    until (lofs >= ptrscript);
    choicecombo[combos].jumpresult[lvar] := $FFFF; // mark end of results
    // If the next word is a zero, skip it
    if word((loader + lofs)^) = 0 then inc(lofs, 2);

    inc(combos);
   until lofs >= ptrscript;
  end;


  if combos <> 0 then begin
   // Read option list addresses
   lofs := ptroptions;
   while (lofs < ptrpix) do begin
    ivar := word((loader + lofs)^); inc(lofs, 2);
    if (ivar <= ptrnil) or (ivar >= ptrscript) then continue; // in data section?
    inc(options);
    if options > high(optionlist) then begin PrintError('Optionlist overflow @ $' + strhex(lofs)); exit; end;
    optionlist[options].address := ivar;
   end;

   ivar := 1;
   while ivar <= options do begin
    lofs := optionlist[ivar].address;
    // read the verb string
    optionlist[ivar].verbtext := capsize(GetLoaderString(word((loader + lofs)^) + 1));
    inc(lofs, 2);
    // read subject strings, until FFFF
    lvar := word((loader + lofs)^); inc(lofs, 2);
    jvar := 0;
    while lvar <> $FFFF do begin
     inc(jvar);
     optionlist[ivar].subjecttext[jvar] := capsize(GetLoaderString(lvar + 1));
     lvar := word((loader + lofs)^); inc(lofs, 2);
    end;
    inc(ivar);
   end;
  end;

  // read picture list
  if (word((loader + word((loader + ptrpix)^))^) <> 0)
  then begin
   lofs := ptrpix;
   while lofs < ptrnil do begin
    if pictures > high(gfxlist) then begin PrintError('Picture list overflow @ $' + strhex(lofs)); exit; end;
    jvar := word((loader + lofs)^);
    writebuf('// Gfx ' + strdec(pictures) + ': style $' + strhex(byte((loader + jvar)^)));
    case byte((loader + jvar)^) of // translate swipe styles to uniform values
                                      // 2: sweep from top
                                      // 3: sweep from left
     4: gfxlist[pictures].data1 := 4; // 4: box fill inward from edges
     5: gfxlist[pictures].data1 := 5; // 5: spiral fill inward from edges
     6: gfxlist[pictures].data1 := 6; // 6: box fill outward from center
     7: gfxlist[pictures].data1 := 7; // 7: sweep from mid to left and right
     8: gfxlist[pictures].data1 := 8; // 8: sweep from mid to top and bottom
     9: gfxlist[pictures].data1 := 9; // 9: noisy fade in (crossfade)
     $A: gfxlist[pictures].data1 := $A; // interlaced sweep from top & bottom
     $B: gfxlist[pictures].data1 := $B; // ragged uneven sweep from left
     else gfxlist[pictures].data1 := 0; // 0: instant
    end;
    {$ifdef enable_hacks}
    // Hack: Turn all instant transitions into crossfades
    if (game in [gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2])
    and (gfxlist[pictures].data1 = 0) then gfxlist[pictures].data1 := 9;
    {$endif}
    inc(jvar);
    gfxlist[pictures].data2 := byte((loader + jvar)^);
    writebuf(' type $' + strhex(byte((loader + jvar)^)));
    inc(jvar);
    gfxlist[pictures].gfxname := upcase(GetLoaderString(jvar));
    writebufln(' ' + gfxlist[pictures].gfxname);
    if gfxlist[pictures].data2 in [$03,$38,$42,$4E,$50] = FALSE then
     PrintError('Unknown image type $' + strhex(gfxlist[pictures].data2) + ': ' + gfxlist[pictures].gfxname);
    inc(pictures); inc(lofs, 2);
   end;
   writebufln('');
  end;

  // In Sakura's code, the options list is occasionally in a different order
  // than the goto-results list. The options list has the correct order, so
  // the results must be shifted to conform.
  // But I can't be bothered.
  // (see the following scripts:
  // CS212 (hack fix), CS401, CS403 (hack fix), CS501, CS701, CS802, CS822)

  // output readable option lists
  if combos <> 0 then begin

   //for lvar := 0 to combos - 1 do writeln(lvar,': ',choicecombo[lvar].ID,' ',choicecombo[lvar].verbtext,' ',choicecombo[lvar].subjecttext);
   writebufln('choice.reset');

   for ivar := 0 to combos - 1 do begin
    // If an option has no jump results, don't print it.
    // (eliminates a few odd duplicate combos, see MT_1002, MT_1003, MT_0814)
    if choicecombo[ivar].jumpresult[0] <> $FFFF then
    with choicecombo[ivar] do begin
     writebuf('choice.set "' + verbtext);
     if subjecttext <> '' then writebuf(':' + subjecttext);
     writebuf('" ."');
     jvar := 0;
     while (jvar < dword(length(jumpresult))) and (jumpresult[jvar] <> $FFFF)
     do begin
      jumplist[jumpcount] := jumpresult[jvar]; inc(jumpcount);
      txt := strhex(jumpresult[jvar]);
      while length(txt) < 4 do txt := '0' + txt;
      if jvar <> 0 then writebuf(':');
      writebuf(txt);
      inc(jvar);
     end;
     writebuf('"');
     if jvar > 1 then begin
      writebuf(' v' + strdec(ID));
      {writebuf('$v' + strdec(ID) + ':=0');}
      AddLocalVar(ID);
     end;
     writebufln('');
     haschoices := TRUE;
    end;
   end;

   writebufln('');
  end;

  lofs := ptrscript;
 end;
 // end of option lists handling

 // ... now to decipher bytecode segments ...

 case game of // some games have one or two non-compliant OVL files
  gid_TASOGARE: if scriptname = 'OP_M2' then begin
   lvar := 0;
   writebufln('mus.play TK_19');
   writebufln('#event.create.interrupt');
   writebufln('sleep 1000');
   while lofs < loadersize do begin
    ivar := byte((loader + lofs)^);
    inc(lofs);
    case ivar of
     1: begin
         txt := upcase(GetLoaderString(lofs));
         inc(lofs, dword(length(txt) + 1));
         writebufln('gfx.show ' + txt);
         writebufln('gfx.transition 0');
         if byte((loader + lofs)^) = 2 then writebufln('sleep 100');
        end;
     2: if lvar = 0 then writebufln('gfx.clearall')
        else begin
         lvar := 0;
         writebufln('tbox.clear');
        end;
     3: begin
         jvar := byte((loader + lofs)^);
         inc(lofs);
         writebufln('sleep ' + strdec(jvar * 100));
        end;
     4: begin
         writebufln('gfx.clearall');
         writebufln('gfx.flash 2 1');
         writebufln('sleep');
        end;
     5: begin
         gutan := 0; // track longest row, 16 chars is about half scr width
         jvar := byte((loader + lofs)^);
         inc(lofs);
         while jvar <> 0 do begin
          dec(jvar);
          txt := GetLoaderString(lofs);
          inc(lofs, dword(length(txt) + 1));
          if gutan < length(txt) then gutan := length(txt);
          if jvar <> 0 then txt := txt + '\n';
          writebufln('print ' + txt);
         end;
         if gutan > 63 then gutan := 63;
         writebufln('tbox.move 1 ' + strdec(dword(16384 - gutan shl 8)) + ' 12000');
         lvar := 1;
        end;
     6: begin
         jvar := byte((loader + lofs)^);
         inc(lofs);
         while jvar <> 0 do begin
          dec(jvar);
          txt := GetLoaderString(lofs);
          inc(lofs, dword(length(txt) + 1));
          if (txt[1] = chr($81)) and (txt[2] = chr($40))
           then txt := copy(txt, 3, $FF); // cut initial whitespace
          if jvar <> 0 then txt := txt + '\n';
          writebufln('print 2 "' + txt + '"');
         end;
         writebufln('sleep 1500');
         writebufln('tbox.clear 2');
         writebufln('sleep 500');
        end;
     7: begin
         txt := upcase(GetLoaderString(lofs));
         inc(lofs, dword(length(txt) + 1));
         writebufln('gfx.show ' + txt);
         writebufln('#gfx.solidblit ' + txt + '; $FFFFFFFF');
         writebufln('gfx.transition 0');
         writebufln('sleep 50');
         writebufln('#gfx.solidblit ' + txt + '; 0');
         writebufln('gfx.transition 4');
         writebufln('sleep');
        end;
     10: begin
          writebufln('gfx.flash 4 1');
          writebufln('sleep');
          writebufln('@movingon: event.remove.interrupt');
          writebufln('//event.exit');
          writebufln('gfx.clearall');
          writebufln('return');
         end;
    end;
   end;
   lofs := loadersize;
  end;

  gid_TRANSFER98: if scriptname = 'TKEXE' then begin
   jvar := 0;
   while lofs < loadersize do begin
    ivar := byte((loader + lofs)^);
    inc(lofs);
    case ivar of
      0: begin
       writebufln('return');
       writebufln('');
       inc(jvar);
       writebufln('@' + strdec(jvar) + ': // $' + strhex(lofs));
      end;
      1: writebufln('waitkey');
      2..$1F: writebufln('//dummy $' + strhex(ivar));
      else DoTextOutput;
    end;
   end;
   lofs := loadersize;
  end;
 end;

 // 3sis-version engines automatically draw the first listed graphic
 if pictures <> 0 then begin
  writebufln('gfx.clearkids');
  if (gfxlist[0].data2 = $50) and (gfxlist[0].data1 <> 0)
  and (gfxlist[0].gfxname <> 'TB_000') then begin
   // graphic type $50, if not instantly drawn, is preceded by a black-out
   writebufln('gfx.show TB_000 bkg');
   writebufln('gfx.transition 3');
   writebufln('sleep');
  end;
  writebufln('gfx.show ' + gfxlist[0].gfxname + ' bkg');
  writebuf('gfx.transition ');
  case gfxlist[0].data1 of
    6,7: writebufln('1'); // wipe from left
    11: writebufln('2'); // ragged wipe
    4,5,8,10: writebufln('3'); // interlaced wipe from top and bottom
    9: writebufln('4'); // crossfade
    else writebufln('0'); // instant
  end;
  writebufln('sleep');
  if game in [gid_SETSUJUU] then AutoLoadAnims(gfxlist[0].gfxname);
  persistence := TRUE;
  lastbkg := gfxlist[0].gfxname;
 end;
 blackedout := FALSE; stashactive := FALSE;
 waitkeyswipe := $FF;
 implicitwaitkey := 0;
 fillbyte(nextgra, sizeof(nextgra), 0);
 nextgra.transition := $FF;
 nextgra.unswiped := 0;

 // LOFS was set to ptrscript at the end of header handling.
 // If header was not present, LOFS is still 0.
 while lofs < loadersize do begin

  // Transition in drawn graphics if the next command doesn't draw more
  if (waitkeyswipe <> $FF)
  and (byte((loader + lofs)^) <> $06) and (word((loader + lofs)^) <> $0211)
  then begin
   writebufln('gfx.transition ' + strdec(waitkeyswipe));
   writebufln('sleep');
   waitkeyswipe := $FF;
  end;

  // Print an informative line at choice jump targets
  if combos <> 0 then
  for ivar := combos - 1 downto 0 do with choicecombo[ivar] do begin
   for jvar := 0 to dword(high(jumpresult)) do begin
    if jumpresult[jvar] = $FFFF then break;
    if jumpresult[jvar] = lofs then begin
     writebuf('### ' + verbtext + ' : ');
     if subjecttext <> '' then writebuf(subjecttext + ' : ');
     writebufln('v' + strdec(ID) + '=' + strdec(jvar));
     break;
    end;
   end;
  end;

  // Make sure there's room in the jump list.
  if jumpcount + 16 >= dword(length(jumplist)) then setlength(jumplist, length(jumplist) shl 1);

  {$ifdef enable_hacks}
  case game of

   gid_RUNAWAY: begin
    // Hack: Skip a clearallabovebkg
    if (scriptname = 'MT_0215') and (lofs = $8F) then persistence := TRUE;
   end;

   gid_SAKURA: begin
    if scriptname = 'CS904_A' then begin
     // Hack: add a snow effect
     if lofs = $A8 then begin
      writebufln('//$v901 := 48');
      writebufln('//fx.precipitate.init SNOW1; SNOW2; snow; 20');
     end else
     if lofs = $262 then begin
      writebufln('//fx.precipitate.end');
      writebufln('//$v901 := 20');
     end else
     // Hack: redraw oddly missing sprite
     if lofs = $39C then begin
      writebufln('gfx.show ofs 8192 CT01C');
      writebufln('gfx.show ofs 8192 CT01R');
     end else
     if lofs = $1AD then writebuf('//');
    end;
    // Hack: Insert a missing swipe
    if (scriptname = 'CSA01') and (lofs = $EC) then begin
     writebufln('gfx.transition 3');
     writebufln('sleep');
    end;
   end;

  end;
  {$endif enable_hacks}

  // See SAKURA.TXT for documentation on most bytecodes.
  ivar := byte((loader + lofs)^);
  inc(lofs);

  if implicitwaitkey = 2 then
   if (ivar in [0,2..5])
   or (ivar = $0B) and (byte((loader + lofs)^) in [$A, $32..$37, $39])
   then begin
    if ivar = 3 then writebuf('waitkey') else writebuf('waitkey noclear=1');
    writebufln(' // implicit');
    implicitwaitkey := 0;
   end;

  case ivar of
   // 00 [00] - end of bytecode section; get user input
   0: begin
       {$note try to suppress some 00, see sakura.txt}
       while (lofs < loadersize) and (byte((loader + lofs)^) = 0) do inc(lofs);
       if haschoices then
        writebufln('choice.go')
       else // if no choices have been defined, pop the script
        writebufln('return');
       persistence := FALSE;
      end;
   // 01 - Wait for keypress, then clear message area
   1: begin
       if implicitwaitkey = 0 then writebuf('tbox.clear // ');
       writebufln('waitkey');
       implicitwaitkey := 0;
      end;
   // 02 - Jump to new OVL by number
   2: case game of
       gid_ANGELSCOLLECTION1, gid_SETSUJUU, gid_TRANSFER98: begin
        jvar := byte((loader + lofs)^);
        inc(lofs);
        txt := strdec(jvar);
        while length(txt) < 3 do txt := '0' + txt;
        case game of
         gid_ANGELSCOLLECTION1: writebufln('call ' + copy(scriptname, 1, 3) + txt[2] + txt[3] + '.');
         gid_SETSUJUU: writebufln('call SMG_S' + txt + '.');
         gid_TRANSFER98: writebufln('call TEN_S' + txt + '.');
        end;
        if byte((loader + lofs)^) <> 0 then writebufln('');
       end;
       gid_DEEP: begin
        jvar := byte((loader + lofs)^);
        inc(lofs);
        writebufln('//dummy $02 ' + strhex(jvar) + ' // unlock map square, go to script H01_xx?');
       end;
       gid_MARIRIN: begin
        jvar := byte((loader + lofs)^);
        inc(lofs);
        writebufln('//dummy $02 ' + strhex(jvar));
       end;
       gid_TASOGARE: begin // enter the dungeon!
        jvar := dword((loader + lofs)^); inc(lofs, 3);
        writebufln('// dungeon romp! map ' + strdec(jvar and $FF) + ' coords ' + strdec((jvar shr 8) and $FF) + ',' + strdec((jvar shr 16) and $FF));
        if byte((loader + lofs)^) <> 0 then writebufln('');
       end;
       else begin PrintError('Unknown code $02 @ $' + strhex(lofs)); exit; end;
      end;
   // 03 - Return to wherever last jumped from
   3: begin
       case game of
        gid_PARFAIT: begin
         writebufln('return // or exit? 03');
        end;
        gid_TASOGARE: begin
         if scriptname = 'TA_00DG'
         then writebufln('return // back to dungeon mode!') else
         if copy(scriptname, length(scriptname) - 1, 2) = 'MP'
         then writebufln('goto mapentry')
         else writebufln('return');
        end;
        else writebufln('return');
       end;
       if byte((loader + lofs)^) <> 0 then writebufln('');
      end;
   // 04 - Jump to new OVL by name
   4: case game of
       gid_DEEP: begin
        writebuf('//dummy runscript 04');
        for jvar := 2 downto 0 do begin
         writebuf(', ' + strdec(byte((loader + lofs)^)));
         inc(lofs);
        end;
        writebufln('');
        if byte((loader + lofs)^) in [0,3] = FALSE then writebufln('');
       end;
       else begin
        txt := GetLoaderString(lofs);
        inc(lofs, dword(length(txt) + 1));
        jvar := pos('.', txt);
        if jvar <> 0 then txt := copy(txt, 1, jvar - 1);
        {$ifdef enable_hacks}
        // Hack: replace calls to GOVER.OVL with a unified ENDINGS script
        if game = gid_3SIS then
         if txt = 'GOVER' then begin
          writebufln('$v512 := 255'); txt := 'ENDINGS';
         end;
        {$endif}
        writebufln('call ' + txt + '.');
        if byte((loader + lofs)^) <> 0 then writebufln('');
       end;
      end;
   // 05 - Jump to new OVL by name?
   5: case game of
       gid_HOHOEMI, gid_PARFAIT, gid_TASOGARE: begin
        txt := GetLoaderString(lofs);
        inc(lofs, dword(length(txt) + 1));
        jvar := pos('.', txt);
        if jvar <> 0 then txt := copy(txt, 1, jvar - 1);
        writebufln('call ' + txt + '. // 05');
       end;
       gid_DEEP: begin
        txt := strdec(byte((loader + lofs)^)); inc(lofs);
        if length(txt) < 2 then txt := '0' + txt;
        writebuf('call E' + txt + '.');
        if byte((loader + lofs)^) <> 0 then writebuf('x // depends which character is selected');
        inc(lofs);
        writebufln('');
        if byte((loader + lofs)^) in [0,3] = FALSE then writebufln('');
       end;
       gid_MARIRIN: begin
        jvar := byte((loader + lofs)^);
        inc(lofs);
        writebufln('//dummy $05 ' + strhex(jvar));
       end;
       else begin PrintError('Unknown code $05 @ $' + strhex(lofs)); exit; end;
      end;
   // 06 - [Sakura] play song xx / [3sis] show graphic xx (no persistence)
   6: case game of
       gid_3SIS, gid_3SIS98, gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2,
       gid_RUNAWAY, gid_RUNAWAY98, gid_SETSUJUU, gid_TRANSFER98, gid_VANISH:
       begin
        if implicitwaitkey = 0 then inc(implicitwaitkey);
        jvar := byte((loader + lofs)^);
        inc(lofs);
        if jvar >= length(gfxlist) then begin PrintError('Graphic draw request out of bounds @ $' + strhex(lofs)); exit; end;
        if persistence = FALSE then begin
         writebufln('gfx.clearkids');
         if (gfxlist[jvar].data2 = $50) and (gfxlist[jvar].data1 <> 0)
         and (gfxlist[jvar].gfxname <> 'TB_000') and (blackedout = FALSE)
         then begin
          writebufln('gfx.show TB_000 bkg');
          writebufln('gfx.transition 3');
          writebufln('sleep');
         end;
        end;
        persistence := FALSE;
        writebuf('gfx.show ' + gfxlist[jvar].gfxname);
        if gfxlist[jvar].data2 = $38 then begin
         //writebuf(' sprite');
         waitkeyswipe := 4;
        end else begin
         writebuf(' bkg');
         if waitkeyswipe <> 4 then case gfxlist[jvar].data1 of
           6,7: waitkeyswipe := 1;
           11: waitkeyswipe := 2;
           4,5,8,10: waitkeyswipe := 3;
           9: waitkeyswipe := 4;
           else waitkeyswipe := 0;
         end;
        end;
        writebufln(' // $' + strhex(gfxlist[jvar].data2));
        if gfxlist[jvar].gfxname = 'TB_000' then blackedout := TRUE else blackedout := FALSE;
        // load animations automatically
        if (gfxlist[jvar].data2 = $38)
        or (game in [gid_SETSUJUU, gid_TRANSFER98])
        then AutoloadAnims(gfxlist[jvar].gfxname);
       end;

       gid_HOHOEMI, gid_EDEN, gid_FROMH, gid_MAJOKKO,
       gid_SAKURA, gid_SAKURA98, gid_TASOGARE:
       begin
        // Play song
        jvar := byte((loader + lofs)^);
        inc(lofs);
        if jvar in [0,$FF] then writebufln('mus.stop')
        else if jvar > dword(length(songlist)) then begin
         PrintError('Song outside list @ $' + strhex(lofs));
         writebufln('');
        end else
         writebufln('mus.play ' + songlist[jvar - 1]);
       end;

       gid_PARFAIT: begin // unknown
        jvar := byte((loader + lofs)^); inc(lofs);
        lvar := byte((loader + lofs)^); inc(lofs);
        writebufln('//dummy 06 // $' + strhex(jvar) + ' $' + strhex(lvar));
       end;
       else begin PrintError('Unknown code $06 @ $' + strhex(lofs)); exit; end;
      end;
   // 07 - 3sis/Runaway play song xx
   7: case game of
       gid_3SIS, gid_3SIS98, gid_RUNAWAY, gid_RUNAWAY98, gid_VANISH,
       gid_TRANSFER98, gid_SETSUJUU, gid_ANGELSCOLLECTION1,
       gid_ANGELSCOLLECTION2, gid_DEEP:
       begin
        jvar := byte((loader + lofs)^);
        inc(lofs);
        if jvar in [0,$FF] then writebufln('mus.stop')
        else if jvar > dword(length(songlist)) then begin
         PrintError('Song outside list @ $' + strhex(lofs));
         writebufln('');
        end else
         writebufln('mus.play ' + songlist[jvar - 1]);
       end;

       gid_MARIRIN: begin
        jvar := byte((loader + lofs)^);
        inc(lofs);
        writebufln('//dummy $07 ' + strhex(jvar));
       end;

       gid_FROMH, gid_TASOGARE: begin
        jvar := byte((loader + lofs)^);
        inc(lofs);
        writebufln('print \$v' + strdec(jvar));
       end;

       else begin PrintError('Unknown code $07 @ $' + strhex(lofs)); exit; end;
      end;
   // 08 - Wait for keypress, don't clear message area afterward
   8: case game of
       gid_SETSUJUU, gid_TRANSFER98, gid_VANISH:
       begin // play sound effect, one data byte
        writebufln('// sound effect ' + strdec(byte((loader + lofs)^)));
        inc(lofs);
       end;

       gid_DEEP: begin
        writebufln('// begin fight #' + strdec(byte((loader + lofs)^)));
        inc(lofs);
       end;

       gid_HOHOEMI, gid_EDEN, gid_FROMH, gid_MAJOKKO, gid_SAKURA,
       gid_SAKURA98, gid_TASOGARE:
       begin
        if implicitwaitkey = 0 then writebuf('// ');
        writebufln('waitkey noclear=1');
        implicitwaitkey := 0;
       end;

       else begin PrintError('Unknown code $08 @ $' + strhex(lofs)); exit; end;
      end;
   // 09 - Wait for keypress, don't clear message area afterward (or sleep)
   9: case game of
       gid_3SIS, gid_3SIS98:
                 begin
                  if implicitwaitkey = 0 then writebuf('// ');
                  writebufln('waitkey noclear=1');
                  implicitwaitkey := 0;
                 end;
       gid_HOHOEMI, gid_DEEP, gid_MAJOKKO, gid_PARFAIT, gid_TASOGARE:
                 begin // interruptable pause
                  writebufln('sleep ' + strdec(byte((loader + lofs)^) * 100) + ' // 09');
                  inc(lofs);
                 end;
       gid_FROMH: begin // weird strings
                   writebuf('//dummy $09 "');
                   while byte((loader + lofs)^) in [32..122] do begin
                    writebuf(char((loader + lofs)^)); inc(lofs);
                   end;
                   writebufln('"');
                  end;
       gid_TRANSFER98: begin // redundant runscript command
                        inc(lofs);
                        txt := strdec(word((loader + lofs)^));
                        while length(txt) < 3 do txt := '0' + txt;
                        writebufln('call TEN_S' + txt + '.');
                        inc(lofs, 2);
                       end;
       else begin PrintError('Unknown code $09 @ $' + strhex(lofs)); exit; end;
      end;
   // 0A - Linebreak, handled with other text output
   // 0B - Local variable functions
   $B: begin
        inc(lofs);
        if bitness = 2 then begin
         // 16-bit references
         jvar := word((loader + lofs)^); // yy
         lvar := word((loader + lofs + 2)^); // zz
         gutan := word((loader + lofs + 4)^); // aa
        end else begin
         // 8-bit references
         jvar := byte((loader + lofs)^); // yy
         lvar := byte((loader + lofs + 1)^); // zz
         gutan := byte((loader + lofs + 2)^); // aa
        end;
        case byte((loader + lofs - 1)^) of // xx
         1: begin
             AddLocalVar(jvar);
             if bitness = 1 then longint(lvar) := shortint(lvar) else longint(lvar) := integer(lvar);
             if lvar = 1 then writebufln('inc v' + strdec(jvar)) else
             if longint(lvar) = -1 then writebufln('dec v' + strdec(jvar))
             else begin
              writebuf('$v' + strdec(jvar));
              if longint(lvar) >= 0 then writebufln(' += ' + strdec(lvar))
              else writebufln(' -= ' + strdec(-longint(lvar)));
             end;
             inc(lofs, bitness + bitness);
            end;
         2: begin
             writebufln('$v' + strdec(jvar) + ' += $v' + strdec(lvar));
             inc(lofs, bitness + bitness);
            end;
         3: begin
             writebufln('$v' + strdec(jvar) + ' -= $v' + strdec(lvar));
             inc(lofs, bitness + bitness);
            end;
         4: begin
             writebufln('$v' + strdec(jvar) + ' := $v' + strdec(lvar));
             inc(lofs, bitness + bitness);
            end;
         5: begin
             AddLocalVar(jvar);
             writebufln('$v' + strdec(jvar) + ' := ' + strdec(lvar));
             inc(lofs, bitness + bitness);
            end;
         6: begin
             writebufln('$v' + strdec(jvar) + ' := $v' + strdec(lvar) + ' - $v' + strdec(gutan));
             inc(lofs, dword(bitness * 3));
            end;
         7: begin
             writebufln('$v' + strdec(jvar) + ' := $v' + strdec(lvar) + ' - ' + strdec(gutan));
             inc(lofs, dword(bitness * 3));
            end;
         8: begin
             writebufln('$v' + strdec(jvar) + ' := $v' + strdec(lvar) + ' and $v' + strdec(gutan));
             inc(lofs, dword(bitness * 3));
            end;
         9: begin
             writebufln('$v' + strdec(jvar) + ' := $v' + strdec(lvar) + ' or $v' + strdec(gutan));
             inc(lofs, dword(bitness * 3));
            end;
         $A: begin
              writebuf('if $v' + strdec(jvar) + ' == 0 then ');
              if haschoices then
               writebufln('choice.go end')
              else
               writebufln('return end');
              inc(lofs, bitness);
             end;
         $B,$C: begin
                 writebuf('$v' + strdec(lvar) + ' := $v' + strdec(lvar));
                 lvar := byte((loader + lofs - 1)^);
                 inc(lofs, bitness + bitness); dec(jvar);
                 while jvar <> 0 do begin
                  if bitness = 1 then gutan := byte((loader + lofs)^) else gutan := word((loader + lofs)^);
                  if lvar = $B then writebuf(' AND $v' + strdec(gutan))
                  else writebuf(' OR $v' + strdec(gutan));
                  inc(lofs, bitness); dec(jvar);
                 end;
                 writebufln('');
                end;
         $14: begin
               writebufln('$v' + strdec(jvar) + ' := rnd ' + strdec(lvar));
               inc(lofs, bitness + bitness);
              end;
         $15: begin
               writebufln('//dummy $0B 15 play song var ' + strhex(jvar));
               inc(lofs, bitness);
              end;
         $1D: begin
               writebufln('//dummy $0B 1D // $' + strhex(jvar) + ' $' + strhex(lvar) + ' $' + strhex(gutan));
               inc(lofs, dword(bitness * 3));
              end;
         $32..$35: begin
               writebuf('if $v' + strdec(jvar) + ' ');
               case byte((loader + lofs - 1)^) of
                $32: writebuf('>');
                $33: writebuf('==');
                $34: writebuf('<');
                $35: writebuf('<>');
               end;
               inc(lofs, bitness);
               lvar := word((loader + lofs)^);
               inc(lofs, 2);
               txt := strhex(lvar);
               while length(txt) < 4 do txt := '0' + txt;
               writebufln(' 0 then goto ."' + txt + '" end');

               // Make sure there's room in the jump list, and add this.
               if jumpcount + 16 >= dword(length(jumplist)) then setlength(jumplist, length(jumplist) shl 1);
               jumplist[jumpcount] := lvar; inc(jumpcount);
              end;
         $36: begin
               txt := strhex(word((loader + lofs)^));
               while length(txt) < 4 do txt := '0' + txt;
               writebufln('goto ."' + txt + '"');

               // Make sure there's room in the jump list, and add this.
               if jumpcount + 16 >= dword(length(jumplist)) then setlength(jumplist, length(jumplist) shl 1);
               jumplist[jumpcount] := word((loader + lofs)^); inc(jumpcount);

               inc(lofs, 2);
               if byte((loader + lofs)^) <> 0 then writebufln('');
              end;
         $37: begin
               ivar := 0; gutan := $FFFF; inc(lofs, bitness);
               writebufln('// 0B-37 multijump');
               writebuf('casecall $v' + strdec(jvar) + ' ."');
               repeat
                // checks for undetected array ends
                if game = gid_TASOGARE then begin
                 lvar := valx(copy(scriptname, 4, 4));
                 if (lvar = 4831) and (lofs = $2C)
                 or (lvar = 4252) and (lofs = $2E)
                 or (lvar = 4250) and (lofs = $2E)
                 or (lvar = 2101) and (lofs = $1D34)
                 or (lvar = 1953) and (lofs = $2E)
                 then break;
                end;
                lvar := word((loader + lofs)^);
                // To find end of array, must test each new word address for
                // validity. Also, see if we've hit the closest of the jump
                // addresses given, since that means the array ended already.
                if (lvar < ptrscript) or (lvar >= loadersize) or (lofs = gutan) then break;
                if (lvar < gutan) and (lvar > lofs) then gutan := lvar;
                txt := strhex(lvar);
                while length(txt) < 4 do txt := '0' + txt;
                if ivar <> 0 then writebuf(':');
                writebuf(txt);
                inc(ivar); inc(lofs, 2);

                // Make sure there's room in the jump list, and add this.
                if jumpcount + 16 >= dword(length(jumplist)) then setlength(jumplist, length(jumplist) shl 1);
                jumplist[jumpcount] := lvar; inc(jumpcount);

               until (lofs >= loadersize);
               writebufln('"');
               writebufln('');
              end;
         $38: begin // same as 36?
               txt := strhex(word((loader + lofs)^));

               // Make sure there's room in the jump list, and add this.
               if jumpcount + 16 >= dword(length(jumplist)) then setlength(jumplist, length(jumplist) shl 1);
               jumplist[jumpcount] := word((loader + lofs)^); inc(jumpcount);

               while length(txt) < 4 do txt := '0' + txt;
               writebufln('goto ."' + txt + '" // 0B-38');
               inc(lofs, 2);
               if byte((loader + lofs)^) <> 0 then writebufln('');
              end;
         $39: begin
               inc(lofs, bitness);
               lvar := word((loader + lofs)^);
               inc(lofs, 2);
               gutan := 0;
               writebuf('casecall $v' + strdec(jvar) + ' ."');
               while lvar <> $FFFF do begin
                txt := strhex(lvar);
                while length(txt) < 4 do txt := '0' + txt;
                if gutan <> 0 then writebuf(':');
                writebuf(txt);

                // Make sure there's room in the jump list, and add this.
                if jumpcount + 16 >= dword(length(jumplist)) then setlength(jumplist, length(jumplist) shl 1);
                jumplist[jumpcount] := lvar; inc(jumpcount);

                lvar := word((loader + lofs)^);
                inc(lofs, 2);
                inc(gutan);
               end;
               writebufln('" // 0B-39');
              end;
         $46, $47: begin
               // Followed by l word addresses pointing to strings; get user
               // choice between them, put result in var j.
               writebufln('choice.reset // 0B-' + strhex(byte((loader + lofs - 1)^)) + ' immediate choice');
               inc(lofs, bitness + bitness);

               lvar := lvar shl 16; // stick for loop tracking variable in hiword
               while lvar and $FFFF < lvar shr 16 do begin
                ivar := word((loader + lofs + (lvar and $FFFF) * 2)^);

                txt := GetLoaderString(ivar + 1);
                if txt = '' then begin
                 // fetch string from cache
                 for gutan := high(stringcache) downto 0 do
                  if word((@stringcache[gutan][62])^) = word(ivar) then break;
                 txt := stringcache[gutan];
                end else begin
                 // cache string, overwrite with zeroes in code
                 for gutan := high(stringcache) downto 0 do if stringcache[gutan] = '' then break;
                 stringcache[gutan] := txt;
                 word((@stringcache[gutan][62])^) := word(ivar);
                 fillbyte((loader + ivar)^, length(txt) + 2, 0);
                end;

                txt := capsize(txt);
                writebufln('choice.set "' + txt + '"');
                inc(lvar);
               end;
               writebufln('$v' + strdec(jvar) + ' := (choice.get)');
               lvar := lvar shr 16;
               inc(lofs, lvar + lvar);
              end;
         $49: begin
               // Four variable numbers, followed by l word addresses
               // pointing to strings; get user choice, put result in var j.
               writebufln('choice.reset // 0B-49 bitmasked immediate choice');
               inc(lofs, dword(bitness * 3));
               // gutan is already the 3rd variable, but it's always set to 0
               // and is never checked afterward, so ignore it.
               // we grab the 4th var into ptrnil. It's the choice bitmask.
               if bitness = 1 then ptrnil := byte((loader + lofs)^)
               else ptrnil := word((loader + lofs)^);
               inc(lofs, bitness);

               lvar := lvar shl 16; // stick for loop tracking variable in hiword
               while lvar and $FFFF < lvar shr 16 do begin
                ivar := word((loader + lofs + (lvar and $FFFF) * 2)^);

                txt := GetLoaderString(ivar + 1);
                if txt = '' then begin
                 // fetch string from cache
                 for gutan := high(stringcache) downto 0 do
                  if word((@stringcache[gutan][62])^) = word(ivar) then break;
                 txt := stringcache[gutan];
                end else begin
                 // cache string, overwrite with zeroes in code
                 for gutan := high(stringcache) downto 0 do if stringcache[gutan] = '' then break;
                 stringcache[gutan] := txt;
                 word((@stringcache[gutan][62])^) := word(ivar);
                 fillbyte((loader + ivar)^, length(txt) + 2, 0);
                end;

                txt := capsize(txt);
                writebufln('if $v' + strdec(ptrnil) + ' AND ' + strdec(1 shl (lvar and $FFFF)) + ' <> 0 then');
                writebufln('  choice.set "' + txt + '"');
                writebufln('end');
                inc(lvar);
               end;
               writebufln('$v' + strdec(jvar) + ' := (choice.get)');
               lvar := lvar shr 16;
               inc(lofs, lvar + lvar);
              end;

         $4B: begin // followed by yy pairs of word addresses
               writebufln('choice.reset // 0B-4B immediate choice');
               inc(lofs, bitness);
               while jvar <> 0 do begin
                lvar := word((loader + lofs)^); inc(lofs, 2);
                txt := GetLoaderString(lvar + 1);
                if txt = '' then begin
                 // fetch string from cache
                 for gutan := high(stringcache) downto 0 do
                  if word((@stringcache[gutan][62])^) = word(lvar) then break;
                 txt := stringcache[gutan];
                end else begin
                 // cache string, overwrite with zeroes in code
                 for gutan := high(stringcache) downto 0 do if stringcache[gutan] = '' then break;
                 stringcache[gutan] := txt;
                 word((@stringcache[gutan][62])^) := word(lvar);
                 fillbyte((loader + lvar)^, length(txt) + 2, 0);
                end;
                txt := capsize(txt);
                lvar := word((loader + lofs)^); inc(lofs, 2);
                writebuf('choice.set "' + txt + '" ."');
                txt := strhex(lvar);
                while length(txt) < 4 do txt := '0' + txt;
                writebufln(txt + '"');

                // Make sure there's room in the jump list, and add this.
                if jumpcount + 16 >= dword(length(jumplist)) then setlength(jumplist, length(jumplist) shl 1);
                jumplist[jumpcount] := lvar; inc(jumpcount);

                dec(jvar);
               end;
               //if byte((loader + lofs)^) <> 0 then begin
                writebufln('choice.go');
               //end;
              end;
         else begin PrintError('Unknown $B subcode $' + strhex(byte((loader + lofs - 1)^)) + ' @ $' + strhex(lofs - 2)); exit; end;
        end;
       end;

   // 0C - Global variable functions
   $C: begin
        case byte((loader + lofs)^) of
         1: begin
             writebufln('$v' + strdec(byte((loader + lofs + 1)^)) + ' := $v' + strdec(byte((loader + lofs + 2)^) + 256));
             inc(lofs, 3);
            end;
         2: begin
             writebufln('$v' + strdec(byte((loader + lofs + 1)^) + 256) + ' := $v' + strdec(byte((loader + lofs + 2)^)));
             inc(lofs, 3);
            end;
         3: begin
             writebufln('$v' + strdec(byte((loader + lofs + 1)^) + 256) + ' := ' + strdec(byte((loader + lofs + 2)^)));
             inc(lofs, 3);
            end;
         else begin PrintError('Unknown $C subcode $' + strhex(byte((loader + lofs)^)) + ' @ $' + strhex(lofs)); exit; end;
        end;
       end;

   // $0D - various more modern graphic functions
   $0D: case game of
         gid_DEEP: begin
          writebuf('//dummy 0D');
          for jvar := 2 downto 0 do begin
           writebuf('-$' + strhex(byte((loader + lofs)^)));
           inc(lofs);
          end;
          writebufln('');
         end;

         gid_PARFAIT: begin
          inc(lofs);
          case byte((loader + lofs - 1)^) of // xx
           $02: begin
                 writebuf('//dummy 0D-02 // data words');
                 for jvar := 3 downto 0 do begin
                  txt := strhex(word((loader + lofs)^));
                  while length(txt) < 4 do txt := '0' + txt;
                  writebuf(' $' + txt);
                  inc(lofs, 2);
                 end;
                 writebufln('');
                end;
           $09: begin
                 writebufln('//dummy 0D-09 // gfx.transition? $' + strhex(byte((loader + lofs)^)));
                 inc(lofs);
                end;
           $0A: begin
                 txt := GetLoaderString(lofs);
                 inc(lofs, dword(length(txt) + 1));
                 gutan := word((loader + lofs)^); inc(lofs, 2); // unk
                 jvar := word((loader + lofs)^); inc(lofs, 2); // locx
                 lvar := word((loader + lofs)^); inc(lofs, 2); // locy
                 writebuf('gfx.show type anim');
                 if jvar <> 0 then writebuf(' ofsx ' + strdec(jvar));
                 if lvar <> 0 then writebuf(' ofsy ' + strdec(lvar));
                 writebufln(' ' + txt + ' // unk word $' + strhex(gutan));
                 inc(lofs, 4);
                 repeat
                  jvar := word((loader + lofs)^); inc(lofs, 2);
                 until jvar = $FFFF;
                end;
           $0B: writebufln('//dummy 0D-0B // gfx.clearkids?');
           else begin PrintError('Unknown $D subcode $' + strhex(byte((loader + lofs - 1)^)) + ' @ $' + strhex(lofs - 2)); exit; end;
          end;
         end;
         else begin PrintError('Unknown code $0D @ $' + strhex(lofs - 1)); exit; end;
        end;
   $0E: case game of // graphic panning

         gid_ANGELSCOLLECTION1, gid_ANGELSCOLLECTION2, gid_TRANSFER98:
         begin
          jvar := byte((loader + lofs)^);
          inc(lofs);
          writebufln('// fx.move $' + strhex(jvar));
         end;

         gid_MAJOKKO: begin
          jvar := byte((loader + lofs)^);
          inc(lofs);
          writebufln('// slidegob!');
         end;

         gid_DEEP: begin
          jvar := byte((loader + lofs)^);
          inc(lofs);
          writebufln('//dummy $0E ' + strhex(jvar) + ' // pan image?');
         end;

         gid_PARFAIT: begin
          jvar := word((loader + lofs)^);
          inc(lofs, 2);
          writebufln('//dummy $0E ' + strhex(jvar) + ' // transition? pan?');
         end;

         else begin PrintError('Unknown code $0E @ $' + strhex(lofs)); exit; end;
        end;
   // 0F xx - happy ending!
   $0F: case game of
         gid_SAKURA, gid_SAKURA98, gid_MAJOKKO,
         gid_ANGELSCOLLECTION2, gid_EDEN:
         begin
          jvar := byte((loader + lofs)^);
          if jvar <> 0 then inc(lofs);
          writebufln('$v512 := ' + strdec(jvar));
          writebufln('call ENDINGS.');
         end;

         gid_FROMH: begin
          txt := GetLoaderString(lofs);
          inc(lofs, dword(length(txt) + 1));
          writebufln('gfx.clearkids');
          writebufln('gfx.show ' + txt + ' bkg');
          writebufln('gfx.transition 4');
          writebufln('sleep');
          writebufln('call ENDINGS.');
         end;

         gid_3SIS, gid_3SIS98, gid_RUNAWAY, gid_RUNAWAY98,
         gid_ANGELSCOLLECTION1, gid_SETSUJUU, gid_TRANSFER98, gid_VANISH:
         begin // vanilla end
          writebufln('$v512 := 0');
          writebufln('call ENDINGS.');
         end;

         gid_TASOGARE: begin // ending credits sequence
          writebufln('$v900 := 2000');
          repeat
           jvar := byte((loader + lofs)^); inc(lofs);
           writebufln('gfx.clearkids');
           case jvar of
            1: writebuf('gfx.show type bkg ');
            2: writebuf('gfx.show type sprite ');
            4: continue;
            else break;
           end;
           txt := GetLoaderString(lofs);
           inc(lofs, dword(length(txt) + 1));
           writebufln(txt);
           writebufln('gfx.transition 4');
           writebufln('sleep 7000');
          until lofs >= loadersize;
         end;

         else begin PrintError('Unknown code $0F @ $' + strhex(lofs)); exit; end;
        end;

   // 10 - unhappy ending!
   $10: begin
         writebufln('$v512 := 255');
         writebufln('call ENDINGS.');
         if lofs + 1 < loadersize then writebufln('');
        end;

   // 11 xx - lots of commands
   $11: if game = gid_ANGELSCOLLECTION1 then begin
         writebufln('//dummy $11');
        end else
        begin
         jvar := byte((loader + lofs)^); inc(lofs);
         case jvar of
          $02: case game of
                gid_3SIS, gid_3SIS98, gid_RUNAWAY, gid_RUNAWAY98:
                begin
                 if implicitwaitkey = 0 then inc(implicitwaitkey);
                 if persistence = FALSE then writebufln('gfx.clearkids');
                 lvar := byte((loader + lofs)^); inc(lofs);
                 if (gfxlist[lvar].data2 = $50) and (gfxlist[lvar].data1 <> 0)
                 and (gfxlist[lvar].gfxname <> 'TB_000') and (blackedout = FALSE)
                 then begin
                  writebufln('gfx.show TB_000 bkg');
                  writebufln('gfx.transition 3');
                  writebufln('sleep');
                 end;
                 writebuf('gfx.show ');
                 // image type $38 sprite: always use a crossfade
                 if gfxlist[lvar].data2 = $38 then waitkeyswipe := 4
                 else begin
                  // all other image types $50, $03, $42, $4E can use
                  // a variety of transitions, unless overridden with xfade.
                  writebuf('type bkg ');
                  if waitkeyswipe <> 4 then
                  case gfxlist[lvar].data1 of
                    6,7: waitkeyswipe := 1;
                    11: waitkeyswipe := 2;
                    4,5,8,10: waitkeyswipe := 3;
                    9: waitkeyswipe := 4;
                    else waitkeyswipe := 0;
                  end;
                 end;
                 writebufln(gfxlist[lvar].gfxname);

                 if gfxlist[lvar].gfxname = 'TB_000' then blackedout := TRUE else blackedout := FALSE;
                 // load animations automatically
                 if gfxlist[lvar].data2 = $38 then AutoloadAnims(gfxlist[lvar].gfxname);
                 persistence := TRUE;
                end;
                gid_VANISH: begin
                 lvar := byte((loader + lofs)^); inc(lofs);
                 writebufln('// battle? #' + strdec(lvar));
                end;
                else begin PrintError('Unknown code $11-02 @ $' + strhex(lofs)); exit; end;
               end;
          $03: case game of
                gid_VANISH: begin
                 writebufln('//dummy $11-03 ' + strhex(byte((loader + lofs)^)));
                 inc(lofs);
                end;
                else begin PrintError('Unknown code $11-03 @ $' + strhex(lofs)); exit; end;
               end;
          $04: case game of
                gid_TASOGARE: begin
                 writebufln('// sys.savegame');
                end;
                gid_VANISH: begin
                 writebufln('//dummy $11-04: var ' + strdec(byte((loader + lofs)^)) + ' with value ' + strdec(byte((loader + lofs + 1)^)) + '?');
                 inc(lofs, 2);
                end;
                else begin PrintError('Unknown code $11-04 @ $' + strhex(lofs)); exit; end;
               end;
          // Name entry
          $05: case game of
                gid_FROMH, gid_TASOGARE: begin
                 writebufln('// <-- name entry!');
                end;
                gid_VANISH: begin
                 writebufln('sys.quit');
                end;
                else begin PrintError('Unknown code $11-05 @ $' + strhex(lofs)); exit; end;
               end;
          $06: case game of
                gid_EDEN: begin
                 writebufln('$v600 := ' + strdec(byte((loader + lofs)^)));
                 writebufln('call NEWMAP.');
                 inc(lofs);
                end;
                gid_FROMH, gid_TASOGARE: begin
                 writebufln('// mark graphic ' + strdec(byte((loader + lofs)^)) + ' as seen');
                 inc(lofs);
                end;
                else begin PrintError('Unknown code $11-06 @ $' + strhex(lofs)); exit; end;
               end;

          $07: case game of
                gid_FROMH, gid_TASOGARE: begin
                 writebufln('// $v' + strdec(byte((loader + lofs)^)) + ' := GraphicSeen(v' + strdec(byte((loader + lofs + 1)^)) + ')');
                 inc(lofs, 2);
                end;
                else begin PrintError('Unknown code $11-07 @ $' + strhex(lofs)); exit; end;
               end;

          $08: case game of
                gid_TASOGARE: begin
                 lvar := byte((loader + lofs)^); inc(lofs);
                 writebufln('// fade to black and back over ' + strdec(lvar) + ' desisecs');
                end;
                else begin PrintError('Unknown code $11-08 @ $' + strhex(lofs)); exit; end;
               end;

          $09: case game of // clickable map!
                gid_FROMH: begin
                 lvar := byte((loader + lofs)^); inc(lofs);
                 writebufln('// 11-09 data=' + strdec(lvar));
                 for gutan := 0 to 11 do begin
                  writebuf('$v' + strdec(601 + gutan) + ' := ');
                  lvar := word((loader + lofs + gutan * 2)^);
                  if lvar = 0 then writebufln('0')
                  else begin
                   writebufln('1');
                   writebufln('$s' + strdec(11 + gutan) + ' := ~"' + GetLoaderString(lvar) + '"');
                  end;
                 end;
                 writebufln('call NEWMAP.');
                 writebuf('case $v600; ."');
                 for gutan := 0 to 11 do begin
                  lvar := word((loader + lofs)^);
                  if lvar = 0 then lvar := ptrscript else begin
                   while (lvar < loadersize) and (byte((loader + lvar)^) <> 0) do begin
                    byte((loader + lvar)^) := 0; inc(lvar);
                   end;
                   inc(lvar);
                  end;

                  // Make sure there's room in the jump list, and add this.
                  if jumpcount + 16 >= dword(length(jumplist)) then setlength(jumplist, length(jumplist) shl 1);
                  jumplist[jumpcount] := lvar; inc(jumpcount);

                  txt := strhex(lvar); inc(lofs, 2);
                  while length(txt) < 4 do txt := '0' + txt;
                  if gutan <> 0 then writebuf(':');
                  writebuf(txt);
                 end;
                 writebufln('"');
                end;

                gid_TASOGARE: begin
                 writebufln('// 11-09 map');
                 for gutan := 0 to 12 do begin
                  writebuf('$v' + strdec(601 + gutan) + ' := ');
                  lvar := word((loader + lofs + gutan * 2)^);
                  if byte((loader + lvar)^) = $FF then writebufln('0')
                  else begin
                   writebufln('1');
                   writebufln('$s' + strdec(11 + gutan) + ' := ~"' + GetLoaderString(lvar + 1) + '"');
                  end;
                 end;
                 writebufln('@mapentry: call NEWMAP.');
                 writebuf('case $v600; ."');
                 for gutan := 0 to 12 do begin
                  lvar := word((loader + lofs)^); jvar := $FFFF;
                  if byte((loader + lvar)^) = $FF then jvar := ptrscript;
                  byte((loader + lvar)^) := 0; inc(lvar);
                  while (lvar < loadersize) and (byte((loader + lvar)^) <> 0) do begin
                   byte((loader + lvar)^) := 0; inc(lvar);
                  end;
                  inc(lvar);
                  if jvar <> $FFFF then lvar := jvar;

                  // Make sure there's room in the jump list, and add this.
                  if jumpcount + 16 >= dword(length(jumplist)) then setlength(jumplist, length(jumplist) shl 1);
                  jumplist[jumpcount] := lvar; inc(jumpcount);

                  txt := strhex(lvar); inc(lofs, 2);
                  while length(txt) < 4 do txt := '0' + txt;
                  if gutan <> 0 then writebuf(':');
                  writebuf(txt);
                 end;
                 writebufln('"');
                end;
                else begin PrintError('Unknown code $11-09 @ $' + strhex(lofs)); exit; end;
               end;

          $0B: case game of
                gid_TASOGARE: begin
                 writebufln('gfx.clearkids // 11-0B');
                end;
                else begin PrintError('Unknown code $11-0B @ $' + strhex(lofs)); exit; end;
               end;

          $0C: case game of
                gid_TASOGARE: begin
                 writebufln('//dummy $11-0C // push player one square backward');
                end;
                else begin PrintError('Unknown code $11-0C @ $' + strhex(lofs)); exit; end;
               end;

          $0E: case game of
                gid_HOHOEMI: begin
                 writebufln('// mark graphic ' + strdec(byte((loader + lofs)^)) + ' as seen');
                 inc(lofs);
                end;
                else begin PrintError('Unknown code $11-0E @ $' + strhex(lofs)); exit; end;
               end;

          $10: case game of
                gid_TASOGARE: begin
                 writebufln('//dummy $11-10 // change cell ' + strdec(byte((loader + lofs + 1)^)) + ',' + strdec(byte((loader + lofs)^)) + ' to $' + strhex(byte((loader + lofs + 2)^)));
                 inc(lofs, 3);
                end;
                else begin PrintError('Unknown code $11-10 @ $' + strhex(lofs)); exit; end;
               end;

          $11,$12: case game of
                gid_TASOGARE: begin
                 gutan := byte((loader + lofs)^); inc(lofs);
                 lvar := byte((loader + lofs)^); inc(lofs);
                 writebufln('// 11-' + strhex(jvar) + ', data bytes: $' + strhex(gutan) + ', ' + strhex(lvar));
                 txt := upcase(GetLoaderString(lofs));
                 inc(lofs, dword(length(txt) + 1));
                 if txt[length(txt)] = 'X' then begin
                  txt := copy(txt, 1, length(txt) - 2);
                  writebufln('gfx.show type sprite ' + txt);
                  txt := txt + 'A0';
                 end;
                 writebufln('gfx.show type sprite ' + txt);
                end;
                else begin PrintError('Unknown code $11-' + strhex(jvar) + ' @ $' + strhex(lofs)); exit; end;
               end;
          else begin PrintError('Unknown code $11-' + strhex(jvar) + ' @ $' + strhex(lofs)); exit; end;
         end;

        end;

   // 12 xx - Option functions - at script init all options default to ON
   $12: begin
         jvar := byte((loader + lofs + 1)^);
         lvar := byte((loader + lofs + 2)^);
         if jvar > dword(high(optionlist)) then begin
          PrintError('$12 requested text outside optionlist! @ $' + strhex(lofs)); exit;
         end;
         if optionlist[jvar].verbtext = '' then begin
          writebuf('// no such choice: $' + strhex(jvar) + ' // ');
          PrintError('Choice verb not defined @ $' + strhex(lofs));
         end;
         case byte((loader + lofs)^) of
          1: begin
              writebufln('choice.off "' + optionlist[jvar].verbtext + '"');
              inc(lofs, 2);
             end;
          2: begin
              writebufln('choice.on "' + optionlist[jvar].verbtext + '"');
              inc(lofs, 2);
             end;
          4: begin
              writebufln('choice.off "' + optionlist[jvar].verbtext + ':' + optionlist[jvar].subjecttext[lvar] + '"');
              inc(lofs, 3);
             end;
          5: begin
              writebufln('choice.on "' + optionlist[jvar].verbtext + ':' + optionlist[jvar].subjecttext[lvar] + '"');
              inc(lofs, 3);
             end;
          else begin PrintError('Unknown code $12 ' + strhex(byte((loader + lofs)^)) + ' @ $' + strhex(lofs)); exit; end;
         end;
        end;

   // 13 xx - Graphic functions (or smash in 3sis and Runaway)
   $13: case game of

         gid_HOHOEMI, gid_EDEN, gid_FROMH, gid_MAJOKKO,
         gid_SAKURA, gid_SAKURA98, gid_TASOGARE:
         begin
          if implicitwaitkey = 0 then inc(implicitwaitkey);
          if blackedout then begin // conclusion for $14-03
           writebufln('gfx.remove TB_000');
           blackedout := FALSE; inc(nextgra.unswiped);
          end;
          txt := '';
          nextgra.style := 0; nextgra.ofsx := 0;
          nextgra.transition := $FF;
          // Parse the 13 xxxxx string
          repeat
           jvar := byte((loader + lofs)^);
           inc(lofs);
           case jvar of
            $01..$04: nextgra.style := nextgra.style or (1 shl jvar);
            $11: nextgra.style := nextgra.style or $8000;
            $00, $05..$0A, $14: ;
            $0B,$0C: writebufln('// 13 has ' + strhex(jvar));
            $0D: begin
                  nextgra.ofsx := word((loader + lofs)^) * 8;
                  inc(lofs, 2);
                 end;
            $0E: begin
                  nextgra.transition := byte((loader + lofs)^);
                  inc(lofs);
                  if nextgra.transition >= $32 then dec(nextgra.transition, $32)
                  else if nextgra.transition = 0 then nextgra.transition := 10
                  else PrintError('Encountered transition $' + strhex(nextgra.transition) + ' @ $' + strhex(lofs));
                 end;
            $0F: begin
                  if stashactive then writebuf('gfx.clearkids TB_008')
                  else writebuf('gfx.clearkids');
                  writebufln(' // 13-0F restore gfx');
                  inc(nextgra.unswiped);
                  for lvar := high(animslot) downto 0 do animslot[lvar].displayed := FALSE;
                 end;
            $10: begin
                  writebufln('gfx.show TB_008 // 13-10 save gfx');
                  stashactive := TRUE;
                 end;
            $21..$7E: begin // graphic file name, stick into a string
                  inc(byte(txt[0]));
                  txt[byte(txt[0])] := chr(jvar);
                 end;
            else begin
                  PrintError('Unknown code $13 ' + strhex(jvar) + ' @ $' + strhex(lofs)); exit;
                 end;
           end;
          until jvar in [$00, $0F, $10];
          // Draw a background with no name = pop state
          if (nextgra.style and 16 <> 0) and (txt = '') then begin
           if stashactive then writebuf('gfx.clearkids TB_008')
           else writebuf('gfx.clearkids');
           writebufln(' // 13-04 restore gfx');
           inc(nextgra.unswiped);
           for lvar := high(animslot) downto 0 do animslot[lvar].displayed := FALSE;
          end else
          // Draw a graphic, if it isn't useless, or deferred (13 02)
          if txt = 'TB_008' then writebufln('');
          if (txt <> '') and (txt <> 'TB_008') and (nextgra.style and 4 = 0)
          then begin
           // See if drawing a sprite over an animation -> auto-disable anim
           if nextgra.style and 8 <> 0 then
            for lvar := high(animslot) downto 0 do
             if (animslot[lvar].displayed) and (animslot[lvar].ofsx = nextgra.ofsx)
              then begin
               animslot[lvar].displayed := FALSE;
               writebufln('gfx.remove ' + animslot[lvar].namu + ' // auto-remove');
              end;
           // Code $13 11: draw the first animation frame as a sprite
           if nextgra.style and $8000 <> 0 then txt := txt + 'A0';

           if nextgra.style and 16 <> 0 then begin
            writebufln('gfx.remove TB_008 // clearstate');
            stashactive := FALSE;
            lastbkg := txt;
           end;
           // HACK: chapter title card in Majokko is named "NOT"
           if txt = 'NOT' then writebuf('gfx.show ."NOT"')
           else writebuf('gfx.show ' + txt);
           if nextgra.style and 2 <> 0 then writebuf(' name ' + txt + '..') else
           if nextgra.style and 8 <> 0 then writebuf(' sprite') else
           if nextgra.style and 16 <> 0 then writebuf(' bkg') else
           begin PrintError('Draw graphic without style @ $' + strhex(lofs)); exit; end;
           if nextgra.ofsx <> 0 then begin
            jvar := BaseResX;
            gutan := seekpng(txt, FALSE);
            if gutan <> 0 then if PNGlist[gutan].origresx <> 0 then jvar := PNGlist[gutan].origresx;
            writebuf(' ofsx ' + strdec((nextgra.ofsx shl 15 + jvar shr 1) div jvar));
           end;
           writebufln('');
           inc(nextgra.unswiped);
          end;
          // Add a transition (replace interlaced swipe with a crossfade for
          // 13 03 sprites, and non-loader 13 02 ... 03 00)
          if nextgra.transition <> $FF then
           if nextgra.unswiped <> 0 then begin
            if (nextgra.style and 8 <> 0)
            and (nextgra.transition = 10)
            then nextgra.transition := 9;
            writebuf('gfx.transition ');
            case nextgra.transition of
              6,7: writebufln('1'); // wipe from left
              11: writebufln('2'); // ragged wipe from left
              4,5,8,10: writebufln('3'); // interlaced wipe from top/bottom
              9: writebufln('4'); // crossfade
              else writebufln('0'); // instant
            end;
            writebufln('sleep');
            nextgra.transition := $FF; nextgra.unswiped := 0;
           end
           else writebufln('');
         end;

         // weird graphics thing
         gid_PARFAIT: begin
          writebuf('//dummy $13');
          while lofs < loadersize do begin
           jvar := byte((loader + lofs)^);
           if jvar > $20 then begin
                       writebuf(' ');
                       repeat
                        jvar := byte((loader + lofs)^); inc(lofs);
                        if jvar = 0 then break;
                        writebuf(chr(jvar));
                       until lofs >= loadersize;
           end else begin
            writebuf(' $' + strhex(jvar)); inc(lofs);
            case jvar of
             0,1,$10: lvar := 1;
             2: lvar := 2;
             9: lvar := 0;
             $B: lvar := 4;
             $C: lvar := 5;
             $D: lvar := 4;
             $12: lvar := 2;
             else lvar := 0;
            end;
            while lvar <> 0 do begin
             txt := strhex(byte((loader + lofs)^));
             if length(txt) = 1 then txt := '0' + txt;
             writebuf(' ' + txt);
             inc(lofs); dec(lvar);
            end;
           end;
           if jvar in [0,1,$10,$33..$7F] then break;
          end;
          writebufln('');
         end;

         // Smash/Flash, always combined in these older games
         gid_3SIS, gid_3SIS98, gid_RUNAWAY, gid_RUNAWAY98:
         begin
          jvar := byte((loader + lofs)^);
          inc(lofs);
          writebufln('gfx.flash ' + strdec(jvar) + ' 1');
          lvar := 2; while lvar * lvar < jvar do inc(lvar);
          lvar := (lvar - 1) shr 1;
          // In some scripts, a sideways bash is more appropriate than
          // a vertical thwomp; in others, just a flash is quite enough.
          // Nominate the scripts manually here.
          jvar := valx(scriptname);
          case game of
           gid_3SIS, gid_3SIS98:
             case jvar of
              123,216,217,220,223,541,702,713,719,733,737,738: WriteBash(lvar, gfxlist[0].gfxname);
              104,110,117,206,306,402,508,605,725,731: WriteThwomp(lvar, gfxlist[0].gfxname);
             end;
          end;
         end;

         else begin PrintError('Unknown code $13 ' + strhex(byte((loader + lofs + 1)^)) + ' @ $' + strhex(lofs)); exit; end;
        end;
   // 14 - Variable reset; or, kill the overlay, restore the background
   $14: case game of
         gid_HOHOEMI, gid_EDEN, gid_FROMH, gid_MAJOKKO,
         gid_SAKURA, gid_SAKURA98, gid_TASOGARE:
         begin
          inc(lofs);
          case byte((loader + lofs - 1)^) of
           // Reset global variables
           1: begin
               jvar := byte((loader + lofs)^);
               inc(lofs);
               while jvar <> 0 do begin
                writebufln('$v' + strdec(byte((loader + lofs)^) + 256) + ' := 0');
                inc(lofs); dec(jvar);
               end;
              end;
           // Black out screen for a bit
           3: begin
               writebufln('gfx.show TB_000');
               jvar := byte((loader + lofs)^); inc(lofs);
               case jvar of // some black-out transitions are not standard
                $32,$3B: jvar := 0;
                $39: jvar := 1;
                $3D: jvar := 2;
                $36,$37,$38,$3A,$3C: jvar := 3;
                else PrintError('Encountered transition $' + strhex(jvar) + ' @ $' + strhex(lofs));
               end;
               writebufln('gfx.transition ' + strdec(jvar));
               writebufln('sleep');
               blackedout := TRUE; nextgra.unswiped := 0;
              end;
           else begin PrintError('Unknown code $14 ' + strhex(byte((loader + lofs)^)) + ' @ $' + strhex(lofs)); exit; end;
          end;
         end;

         gid_3SIS, gid_3SIS98, gid_RUNAWAY, gid_RUNAWAY98:
         begin
          writebufln('sleep ' + strdec(byte((loader + lofs)^) * 100));
          inc(lofs);
         end;

         else begin PrintError('Unknown code $14 @ $' + strhex(lofs)); exit; end;
        end;
   // 15 xx - Handle animations
   $15: case game of
         gid_EDEN, gid_FROMH, gid_HOHOEMI, gid_MAJOKKO,
         gid_PARFAIT, gid_SAKURA, gid_SAKURA98, gid_TASOGARE:
         begin
          jvar := byte((loader + lofs)^);
          inc(lofs);
          case jvar of
           // 01 - Read anim into slot yy, with an offset
           // 02 - Read anim into slot yy, without offset
           $01, $02: begin
               lvar := byte((loader + lofs)^) mod length(animslot);
               inc(lofs);
               if animslot[lvar].displayed then begin
                writebufln('gfx.remove ' + animslot[lvar].namu + ' // old slot ' + strdec(lvar));
                //if game <> gid_MAJOKKO then writebufln('gfx.transition 0');
               end;
               animslot[lvar].ofsx := 0;
               if byte((loader + lofs)^) = $0D then begin
                animslot[lvar].ofsx := word((loader + lofs + 1)^) * 8;
                inc(lofs, 3);
               end;
               animslot[lvar].namu := GetLoaderString(lofs);
               inc(lofs, dword(length(animslot[lvar].namu) + 1));
               // clean the animname string of illegal chars
               for jvar := length(animslot[lvar].namu) downto 1 do
                if animslot[lvar].namu[jvar] in ['!'..'z'] = FALSE then
                 animslot[lvar].namu := copy(animslot[lvar].namu, 1, jvar - 1) + copy(animslot[lvar].namu, jvar + 1, $FF);
               if length(animslot[lvar].namu) > 8 then byte(animslot[lvar].namu[0]) := 8;
               {$note Put this in temp string, write commented out if the NEXT code is 15-04}
               writebuf('gfx.show ' + animslot[lvar].namu + ' anim');
               if animslot[lvar].ofsx <> 0 then begin
                gutan := seekpng(animslot[lvar].namu, FALSE);
                if gutan <> 0 then gutan := PNGlist[gutan].origresx;
                if gutan = 0 then gutan := BaseResX;
                writebuf(' ofsx ' + strdec((animslot[lvar].ofsx shl 15 + gutan shr 1) div gutan));
               end;
               writebufln(' // load slot ' + strdec(lvar));

               if animslot[lvar].displayed then begin // draw over existing anim
                // Just switching an animation merits a crossfade
                if game = gid_MAJOKKO then begin
                 writebufln('gfx.transition 4');
                 writebufln('sleep');
                end;
               end;

               animslot[lvar].displayed := TRUE;
              end;
           // 03 - Display animation from slot yy
           3: begin
               lvar := byte((loader + lofs)^) mod length(animslot);
               inc(lofs);
               if animslot[lvar].namu = '' then begin
                PrintError('Animslot ' + strdec(lvar) + ' used while undefined @ $' + strhex(lofs - 3));
                writebuf('// ');
               end;
               writebuf('gfx.show ' + animslot[lvar].namu + ' anim');
               if animslot[lvar].ofsx <> 0 then begin
                gutan := seekpng(animslot[lvar].namu, FALSE);
                if gutan <> 0 then gutan := PNGlist[gutan].origresx;
                if gutan = 0 then gutan := BaseResX;
                writebuf(' ofsx ' + strdec((animslot[lvar].ofsx shl 15 + gutan shr 1) div gutan) + ' ');
               end;
               writebufln(' // show slot ' + strdec(lvar));
               animslot[lvar].displayed := TRUE;
              end;
           // 04 and 05 - Probably stop ongoing animations
           4,5: begin
                 writebufln('gfx.removeanims // code 15 0' + strdec(jvar));
                 for lvar := 0 to high(animslot) do animslot[lvar].displayed := FALSE;
                end;
           else begin PrintError('Unknown code $15 ' + strhex(byte((loader + lofs + 1)^)) + ' @ $' + strhex(lofs)); exit; end;
          end;
         end;

         else begin PrintError('Unknown code $15 @ $' + strhex(lofs)); exit; end;
        end;
   // 16 xx - Screen flashes xx times
   $16: case game of
         gid_HOHOEMI, gid_EDEN, gid_FROMH, gid_MAJOKKO,
         gid_SAKURA, gid_SAKURA98, gid_TASOGARE:
         begin
          jvar := byte((loader + lofs)^);
          inc(lofs);
          {$ifdef enable_hacks}
          case jvar of
           // reduce flashing, it's overdone at points
           2: jvar := 1;
           3,4: dec(jvar);
           5,6: jvar := 3;
          end;
          {$endif enable_hacks}
          writebufln('gfx.flash ' + strdec(jvar) + ' 1');
          // In case of CS304, an implicit delay is expected after each flash
          if (scriptname = 'CS304') and (lofs > $1D00)
          then writebufln('sleep 400');
         end;

         gid_PARFAIT: begin // some kinda graphics command?
          jvar := byte((loader + lofs)^); inc(lofs);
          if jvar <> $A then begin PrintError('Unknown $16 subcode @ $' + strhex(lofs)); exit; end;
          writebuf('//dummy $16 0A //');
          for lvar := 3 downto 0 do begin
           txt := strhex(word((loader + lofs)^));
           while length(txt) < 4 do txt := '0' + txt;
           inc(lofs, 2);
           writebuf(' $' + txt);
          end;
          for lvar := 4 downto 0 do begin
           txt := strhex(byte((loader + lofs)^));
           if length(txt) = 1 then txt := '0' + txt;
           inc(lofs);
           writebuf(' $' + txt);
          end;
          writebufln('');
         end;

         else begin PrintError('Unknown code $16 @ $' + strhex(lofs)); exit; end;
        end;
   // 17 xx - Pause for xx desisecs (or until an impatient key pressed)
   $17: case game of
         gid_HOHOEMI, gid_EDEN, gid_FROMH, gid_MAJOKKO,
         gid_SAKURA, gid_SAKURA98, gid_TASOGARE:
         begin
          writebufln('sleep ' + strdec(byte((loader + lofs)^) * 100));
          inc(lofs);
         end;
         else begin PrintError('Unknown code $17 @ $' + strhex(lofs)); exit; end;
        end;
   // 18 xx - Screen shakes vertically xx times
   $18: case game of
         gid_EDEN, gid_FROMH, gid_MAJOKKO, gid_SAKURA, gid_SAKURA98,
         gid_TASOGARE:
         begin
          jvar := byte((loader + lofs)^);
          inc(lofs);
          lvar := 1; while lvar * lvar < jvar do inc(lvar);
          lvar := (lvar - 1) shr 1;
          if (scriptname = 'CSA09')
          or (scriptname = 'CS507_D')
          then WriteBash(1, lastbkg) else WriteThwomp(lvar, lastbkg);
         end;
         else begin PrintError('Unknown code $18 @ $' + strhex(lofs)); exit; end;
        end;
   // 19 - Clear textbox immediately
   $19: case game of
         gid_3SIS, gid_EDEN, gid_FROMH, gid_MAJOKKO, gid_PARFAIT,
         gid_TASOGARE: begin
          writebufln('tbox.clear');
          writebufln('tbox.clear 1');
          implicitwaitkey := 0;
         end;

         gid_HOHOEMI: begin
          writebufln('//dummy $19');
         end;

         else begin PrintError('Unknown code $19 @ $' + strhex(lofs)); exit; end;
        end;
   // 1E xx - unknown
   $1E: case game of
         gid_DEEP: begin
          jvar := byte((loader + lofs)^);
          inc(lofs);
          writebufln('//dummy $1E v' + strdec(jvar));
         end;
         else begin PrintError('Unknown code $1E @ $' + strhex(lofs)); exit; end;
        end;
   // F3 xx - unknown
   $F3: case game of
         gid_DEEP: begin
          jvar := byte((loader + lofs)^);
          inc(lofs);
          writebufln('//dummy $F3-$' + strhex(jvar));
         end;
         else begin PrintError('Unknown code $F3 @ $' + strhex(lofs)); exit; end;
        end;
   // ASCII/Shift-JIS text output
   $0A, $20..$EF: DoTextOutput;
   // exceptions
   else begin
    PrintError('Unknown code $' + strhex(ivar) + ' @ $' + strhex(lofs - 1));
    exit;
   end;
  end;

 end;

 // Sort the jump list - teleporting gnome, with duplicate removal.
 ivar := 0; jvar := $FFFFFFFF;
 while ivar < jumpcount do begin
  if (ivar <> 0) and (jumplist[ivar] = jumplist[ivar - 1]) then begin
   jumplist[ivar] := jumplist[jumpcount - 1];
   dec(jumpcount);
  end else
  if (ivar = 0) or (jumplist[ivar] > jumplist[ivar - 1])
  then begin
   if jvar = $FFFFFFFF then inc(ivar) else begin ivar := jvar; jvar := $FFFFFFFF; end;
  end
  else begin
   lvar := jumplist[ivar];
   jumplist[ivar] := jumplist[ivar - 1];
   jumplist[ivar - 1] := lvar;
   jvar := ivar; dec(ivar);
  end;
 end;
 setlength(jumplist, jumpcount);

 // Set up a buffer that can hold all script lines.
 jvar := 0;
 for ivar := outbuf.bufindex - 1 downto 0 do
  inc(jvar, dword(length(outbuf.linelist[ivar])) + 8);
 getmem(outbuf.buffy, jvar + dword(length(localvarlist)) * 16);
 // Print reset instructions for local variables.
 outbuf.bufsize := 0;
 if length(localvarlist) <> 0 then
  for ivar := 0 to length(localvarlist) - 1 do begin
   txt := '$v' + strdec(localvarlist[ivar]) + ':=0' + chr($A);
   move(txt[1], (outbuf.buffy + outbuf.bufsize)^, length(txt));
   inc(outbuf.bufsize, length(txt));
  end;
 // Build the sakurascript lines into a single memory block.
 lvar := 0;
 for ivar := 0 to outbuf.bufindex - 1 do begin

  // If this line's label address is in jumplist, print the label.
  if (lvar < dword(length(jumplist)))
  and (outbuf.labellist[ivar] >= jumplist[lvar]) then begin
   case outbuf.labellist[ivar] of
    0..$F: txt := chr($A) + '@000' + hextable[outbuf.labellist[ivar]] + ':';
    $10..$FF: txt := chr($A) + '@00' + strhex(outbuf.labellist[ivar]) + ':';
    $100..$FFF: txt := chr($A) + '@0' + strhex(outbuf.labellist[ivar]) + ':';
    else txt := chr($A) + '@' + strhex(outbuf.labellist[ivar]) + ':';
   end;

   move(txt[1], (outbuf.buffy + outbuf.bufsize)^, length(txt));
   inc(outbuf.bufsize, length(txt));

   inc(lvar);
  end;

  if length(outbuf.linelist[ivar]) <> 0 then begin
   move(outbuf.linelist[ivar][1], (outbuf.buffy + outbuf.bufsize)^, length(outbuf.linelist[ivar]));
   inc(outbuf.bufsize, dword(length(outbuf.linelist[ivar])));
  end;

  outbuf.linelist[ivar] := '';
  // Line break after each line.
  byte((outbuf.buffy + outbuf.bufsize)^) := $A;
  inc(outbuf.bufsize);
 end;

 // Save the built script.
 Decomp_JastOvl := SaveFile(outputfile, outbuf.buffy, outbuf.bufsize);

 // clean up
 freemem(outbuf.buffy); outbuf.buffy := NIL;
end;
