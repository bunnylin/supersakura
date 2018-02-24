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

// Decomp --- Music and sound conversion code

var cur_ticks : longint;
    trackdata : array[0..18] of array of byte;
    tofs, tracktime, trackloop : array[0..18] of dword;
    instused : array of byte;
    // Special handling instructions, fetched from aud.cfg
    songinfo : record
      forcelength : dword; // request up to this many ticks of song
      forceloopstart, forceloopend : dword;
      forceinst : array[0..18] of byte;
      instmap : array[0..$FF] of byte;
      instvol : array[0..$FF] of byte; // real volume = vol * instvol / 64
      instkey : array[0..$FF] of shortint; // key modifier, in semitones
    end;

{$ifdef bonk}
procedure ReadSongInfo(songnamu : string);
// This accesses projectdir\new\aud.cfg and tries to find data for the file
// called songnamu. If the file does not exist, a blank one is created.
// Also resets SongInfo values to defaults, except for instmap / instkey.
// Instrument translation defaults must be set by the converter proc instead.
var ivar : dword;
    jvar : integer;
    infofile : text;
    doread : boolean;
begin
 // Default values - no messing with looping, no vol/key adjustments
 songinfo.forcelength := $FFFFFFFF;
 songinfo.forceloopstart := $FFFFFFFF;
 songinfo.forceloopend := $FFFFFFFF;
 fillbyte(songinfo.instvol, length(songinfo.instvol), 64);
 fillbyte(songinfo.forceinst, length(songinfo.forceinst), $FF);
 // Try to open aud.cfg in read-only mode
 while IOresult <> 0 do ;
 assign(infofile, projectdir + 'new' + DirectorySeparator + 'aud.cfg');
 filemode := 0; reset(infofile);
 ivar := IOresult;
 // File not found! Create a new one.
 if ivar = 2 then begin
  filemode := 1; rewrite(infofile);
  ivar := IOresult;
  if ivar <> 0 then begin
   PrintError('IO error ' + strdec(ivar) + ' trying to create ' + projectdir + 'new\aud.cfg');
   exit;
  end;
  writeln(infofile, '// Music conversion data for game ' + strdec(game));
  writeln(infofile, '');
  writeln(infofile, '// Entry format:');
  writeln(infofile, '// file VP069.SC5');
  writeln(infofile, '// length 800');
  writeln(infofile, '// loopstart 0');
  writeln(infofile, '// loopend 800');
  writeln(infofile, '// inst 20: -49, 64, -12');
  writeln(infofile, '// trackinst 1: 20');
  writeln(infofile, '//');
  writeln(infofile, '// Length and loop values are in ticks. Inst x: a,b,c changes the mapping');
  writeln(infofile, '// of song instrument x to use midi instrument a, its volume adjusted by');
  writeln(infofile, '// volume * b / 64, and its key adjusted by +/- c semitones.');
  writeln(infofile, '// Trackinst a: b overrides instrument selection, forcing track a to only use');
  writeln(infofile, '// song instrument b.');
  writeln(infofile, '// Instrument numbers are 0-based, track numbers are 1-based. Midi instruments');
  writeln(infofile, '// may use negative numbers for percussion, eg. Acoustic Bass Drum at -34.');
  close(infofile);
  exit;
 end;
 // Read through the file until the desired filename is encountered
 doread := FALSE; songnamu := lowercase(songnamu);
 while eof(infofile) = FALSE do begin
  readln(infofile, txt);
  if txt[1] = '/' then continue;
  // Strip leading spaces
  ivar := 1;
  while (ivar <= length(txt)) and (txt[ivar] = ' ') do inc(ivar);
  txt := copy(txt, ivar, $FF);
  if txt = '' then continue;
  txt := lowercase(txt);
  if txt = 'common' then begin doread := TRUE; continue; end;
  // Filename indicator
  if copy(txt, 1, 5) = 'file ' then begin
   if copy(txt, 6, $FF) = songnamu then doread := TRUE else doread := FALSE;
   continue;
  end;
  if doread = FALSE then continue;
  // Instrument mapping
  if copy(txt, 1, 5) = 'inst ' then begin
   txt := copy(txt, 6, $FF);
   ivar := CutNumberFromTxt and $FF;
   jvar := integer(cutnumberfromtxt);
   if jvar < 0 then jvar := -jvar + 128;
   songinfo.instmap[ivar] := byte(jvar);
   songinfo.instvol[ivar] := byte(cutnumberfromtxt);
   songinfo.instkey[ivar] := shortint(cutnumberfromtxt) + 12;
   continue;
  end;
  // Overrides
  if copy(txt, 1, 10) = 'trackinst ' then begin
   txt := copy(txt, 11, $FF);
   ivar := abs(cutnumberfromtxt - 1) mod length(songinfo.forceinst);
   songinfo.forceinst[ivar] := byte(cutnumberfromtxt);
   continue;
  end;
  if copy(txt, 1, 7) = 'length ' then songinfo.forcelength := cutnumberfromtxt;
  if copy(txt, 1, 10) = 'loopstart ' then songinfo.forceloopstart := cutnumberfromtxt;
  if copy(txt, 1, 8) = 'loopend ' then songinfo.forceloopend := cutnumberfromtxt;
 end;

 close(infofile);
end;
{$endif}

procedure addinstrument(newnum : byte);
// Checks if given instrument is yet in InstUsed-list. If not, adds it.
var ivar : byte;
begin
 ivar := length(instused);
 while ivar <> 0 do begin
  dec(ivar);
  if instused[ivar] = newnum then exit;
 end;
 setlength(instused, length(instused) + 1);
 instused[high(instused)] := newnum;
end;

procedure remember(const txt : string; idx : dword);
// Stores string(txt) in trackdata[i] [tofs[i]]
begin
 if tofs[idx] + 300 > dword(length(trackdata[idx])) then setlength(trackdata[idx], length(trackdata[idx]) + 65536);
 move(txt[1], trackdata[idx][tofs[idx]], length(txt));
 inc(tofs[idx], length(txt));
end;

function makemidivarlength(number : dword) : string;
// Turns number into a string of bytes as a MIDI variable-length value.
begin
 makemidivarlength := '';
 repeat
  makemidivarlength := chr((number and $7F) or $80) + makemidivarlength;
  number := number shr 7;
 until number = 0;
 byte(makemidivarlength[length(makemidivarlength)])
 := byte(makemidivarlength[length(makemidivarlength)]) and $7F;
end;

procedure writedeltatime(idx, deltatime : dword);
// Writes the deltatime since the last message into trackdata[idx]^, and adds
// the elapsed time to tracktime[idx] to know how long the track is so far.
begin
 inc(tracktime[idx], deltatime);
 dec(cur_ticks, deltatime);
 remember(makemidivarlength(deltatime), idx);
end;

function Decomp_dotM(const srcfile, outputfile : UTF8string) : UTF8string;
// Reads the indicated .M music file, and saves it in outputfile as a normal
// midi file.
// Returns an empty string if successful, otherwise returns an error message.
var ivar, jvar, lvar : dword;
    txt : string;
    musname : UTF8string;
    numtracks : byte;
    trackptr : array[0..12] of dword;
    mversion, cofs : byte;
    m, n : integer;
    pb, pbp : word;
    poku : pointer;
    repecount : array[1..8] of word;
    cur_channel, cur_inst, repenest, staccato, noteplaying : byte;
    pitchbendrange : byte; // range set to +/- so many semitones, default 2
    bent : shortint;
    volume : integer;
    vibra : record
             active : byte;
             delay, rate, stepsize, depth : byte;
            end;
begin
 // Load the input file into loader^.
 Decomp_dotM := LoadFile(srcfile);
 if Decomp_dotM <> '' then exit;
 Decomp_dotM := '.M file support is offline';
 exit;

 musname := ExtractFileName(srcfile);
 musname := upcase(copy(musname, 1, length(musname) - length(ExtractFileExt(musname))));

 repecount[1] := 0; // just to remove a compiler warning

 mversion := byte(loader^);
 if (word((loader + 1)^) <> $1A)
 and (word(loader^) <> $1A)
 then begin
  Decomp_dotM := 'Unfamiliar .M format...';
  exit;
 end;

 // If there's a version byte at the start, add a constant offset
 if word(loader^) = $1A then cofs := 0 else cofs := 1;

 // Set default conversion values
 fillbyte(songinfo.instmap, length(songinfo.instmap), 4);
 fillbyte(songinfo.instkey, length(songinfo.instkey), 12);

 // Read the track pointers
 lofs := 1;
 numtracks := 0;
 for ivar := 0 to 12 do begin
  trackptr[numtracks] := word((loader + lofs)^) + cofs;
  inc(lofs, 2);
  if ivar <= 10 then inc(numtracks);
 end;

 if numtracks = 0 then begin
  PrintError('No tracks identified!'); exit;
 end;
 // --Insert instrument auto-detection heuristics here--

 // Read hand-picked conversion rules
 //ReadSongInfo(musname + '.m');
 writeln(stdout, 'Instruments used in ' + musname + '.m');

 {$ifdef enable_hacks}
 // Hack: Ridiculous loop count cut to a sensible number
 if musname = 'SK_09' then byte(pointer(loader + $691)^) := $F;
 {$endif enable_hacks}

 // Process all tracks
 for ivar := 0 to numtracks - 1 do begin

  setlength(trackdata[ivar], 32768);
  tofs[ivar] := 0;
  tracktime[ivar] := 0;
  trackloop[ivar] := $FFFFFFFF;

  lofs := trackptr[ivar];
  vibra.active := 0;
  staccato := 0; volume := $69;
  noteplaying := $FF; bent := 0; pitchbendrange := 2;
  repenest := 0; fillbyte(repecount[1], 4, 0);
  cur_ticks := 0;
  cur_channel := ivar and $F;
  if cur_channel in [9..14] then inc(cur_channel);
  cur_inst := songinfo.forceinst[ivar];
  if cur_inst = $FF then cur_inst := ivar;
  setlength(instused, 0);

  // Start with an all controllers off
  txt := chr(0) + chr($B0 or cur_channel) + chr(121) + chr(0);
  remember(txt, ivar);
  // Pitch wheel middle
  txt := chr(0) + chr($E0 or cur_channel) + chr(0) + chr($40);
  remember(txt, ivar);
  // Reset pitch bend range to +/- 2 semitones
  txt := chr(0) + chr($B0 or cur_channel) + chr(101) + chr(0)
       + chr(0) + chr($B0 or cur_channel) + chr(6) + chr(2);
  remember(txt, ivar);
  // Select the default instrument
  if songinfo.instmap[cur_inst] >= 128 then cur_channel := 9
  else if songinfo.forceinst[ivar] <> $FF then begin
   addinstrument(cur_inst);
   txt := chr(0) + chr($C0 or cur_channel) + chr(songinfo.instmap[cur_inst]);
   remember(txt, ivar);
  end;

  // construct the event sequence for this track
  repeat

   lvar := byte((loader + lofs)^);
   m := byte((loader + lofs + 1)^);
   n := byte((loader + lofs + 2)^);
   //write(strhex(lofs):3,':',strhex(l):2,'; ');

   case lvar of
    $00..$0B, $10..$1B, $20..$2B, $30..$3B, $40..$4B, $50..$5B, $60..$6B,
    $70..$7B: begin
               // Play note l, where the top nibble is the octave, and the
               // lower nibble is the note. m is note duration.
               // convert it to a midi note
               jvar := byte(lvar shr 4) * $C + byte(lvar and $F);
               case songinfo.instmap[cur_inst] of
                0..127: begin
                         if longint(jvar) + songinfo.instkey[cur_inst] < 0 then jvar := 0
                         else begin
                          jvar := longint(jvar) + songinfo.instkey[cur_inst];
                          if jvar > 127 then jvar := 127;
                         end;
                        end;
                128..250: jvar := songinfo.instmap[cur_inst] and $7F; // perc
                255: // dynamic snare/crash
                     if m >= 24 then jvar := 48 else jvar := 37;
               end;
               m := m * 2; // note length, at double resolution

               // If the desired note is already playing, no action is needed
               if noteplaying + bent <> longint(jvar) then begin
                // If it is not playing, off whatever is playing
                if noteplaying <> $FF then begin
                 writedeltatime(ivar, cur_ticks);
                 txt := chr($80 or cur_channel) + chr(noteplaying) + chr(volume);
                 remember(txt, ivar); // noteoff
                end;
                if bent <> 0 then begin
                 writedeltatime(ivar, cur_ticks);
                 txt := chr($E0 or cur_channel) + chr(0) + chr($40);
                 remember(txt, ivar); // pitch bend = 0
                 bent := 0;
                end;
                // and send a note on message
                writedeltatime(ivar, cur_ticks);
                txt := chr($90 or cur_channel) + chr(jvar) + chr(volume);
                remember(txt, ivar);
                noteplaying := jvar;
               end;

               inc(cur_ticks, m);

               // Apply modulation if active and enough time elapsed
               if vibra.active and 11 in [1..3] then
                if cur_ticks > vibra.delay then begin
                 vibra.active := vibra.active or 8;
                 m := cur_ticks - vibra.delay;
                 cur_ticks := vibra.delay;
                 writedeltatime(ivar, cur_ticks);
                 txt := chr($B0 or cur_channel) + chr(1) + chr(vibra.depth and $7F);
                 remember(txt, ivar);
                 cur_ticks := m;
                end;

               // Code FB extends the note all the way to the next
               if n <> $FB then begin
                // without FB protection, however, the note is going down
                if staccato < cur_ticks then begin
                 dec(cur_ticks, staccato);
                 m := staccato;
                end else m := 0;
                writedeltatime(ivar, cur_ticks);
                cur_ticks := m;
                txt := chr($80 or cur_channel) + chr(noteplaying) + chr(volume);
                remember(txt, ivar);

                if vibra.active and 8 <> 0 then begin // remove modulation
                 vibra.active := vibra.active and 7;
                 writedeltatime(ivar, cur_ticks);
                 txt := chr($B0 or cur_channel) + chr(1) + chr(0);
                 remember(txt, ivar);
                end;
                noteplaying := $FF;
               end;
               inc(lofs, 2);
              end;
    // Pause
    $0F: begin
          if (tracktime[ivar] = 0) and (trackloop[ivar] = $FFFFFFFF)
          and (m < 5) then m := m shr 1; // reduce constant channel delays
          inc(cur_ticks, m * 2); // pause length, at double resolution
          inc(lofs, 2);
         end;
    // End of track
    $80: begin
          if bent <> 0 then begin // remove pitch bend
           writedeltatime(ivar, cur_ticks);
           txt := chr($E0 or cur_channel) + chr($2000 and $7F) + chr($2000 shr 7);
           remember(txt, ivar);
           bent := 0;
          end;
          break; // stop processing this track
         end;
    // unknown
    $BB, $C5: inc(lofs, 2);
    $C0: inc(lofs);
    // unknown, points to last track, then 00 00 00 00
    $C6: inc(lofs, 7);
    // unknown
    $C8: inc(lofs, 4);
    // unknown
    $C9, $CA, $CB, $CC, $CF: inc(lofs, 2);
    $CD: inc(lofs, 6);
    // unknown
    $D5,$D6: inc(lofs, 3);
    // Pitch slide from m to n during j
    $DA: begin
          m := byte(m shr 4) * $C + (m and $F) + songinfo.instkey[cur_inst];
          n := byte(n shr 4) * $C + (n and $F) + songinfo.instkey[cur_inst];
          if m < 0 then m := 0 else if m > 127 then m := 127;
          if n < 0 then n := 0 else if n > 127 then n := 127;

          // The currently playing note is noteplaying, with a possible
          // pitch wheel adjustment.
          // If no note is playing, start one at m
          if noteplaying = $FF then begin
           writedeltatime(ivar, cur_ticks);
           txt := chr($90 or cur_channel) + chr(m) + chr(volume);
           remember(txt, ivar);
           noteplaying := m;
          end else
          // If the starting note, m, is not within pitch bend range from
          // noteplaying, off the note and start a new one at m.
          if (abs(noteplaying - m) > pitchbendrange) then begin
           writedeltatime(ivar, cur_ticks);
           txt := chr($80 or cur_channel) + chr(noteplaying) + chr(volume);
           remember(txt, ivar);
           if vibra.active and 8 <> 0 then begin // remove modulation
            vibra.active := vibra.active and 7;
            txt := chr(0) + chr($B0 or cur_channel) + chr(1) + chr(0);
            remember(txt, ivar);
           end;
           if bent <> 0 then begin
            // unbend
            txt := chr(0) + chr($E0 or cur_channel) + chr(0) + chr($40);
            remember(txt, ivar);
            bent := 0;
           end;
           // new note on
           txt := chr(0) + chr($90 or cur_channel) + chr(m) + chr(volume);
           remember(txt, ivar);
           noteplaying := m;
          end;

          // Expand the pitch bend range if necessary
          if abs(noteplaying - n) > pitchbendrange then begin
           writedeltatime(ivar, cur_ticks);
           lvar := abs(noteplaying - n);
           txt := chr($B0 or cur_channel) + chr(101) + chr(0)
                + chr(0) + chr($B0 or cur_channel) + chr(6) + chr(lvar);
           remember(txt, ivar);
           pitchbendrange := lvar;
          end;

          // Calculate from- and to- pitch wheel positions
          pb := (m - noteplaying) * $1FFF div pitchbendrange + $2000;
          pbp := (n - noteplaying) * $1FFF div pitchbendrange + $2000;
          // Send the first pitch wheel message to start running status
          writedeltatime(ivar, cur_ticks);
          txt := chr($E0 or cur_channel) + chr(pb and $7F) + chr(pb shr 7);
          remember(txt, ivar);

          // Generate a series of pitch wheel events, over duration j
          jvar := byte((loader + lofs + 3)^) * 2; // (double resolution)
          lvar := jvar;
          while lvar <> 0 do begin
           dec(lvar);
           m := (longint(pb * lvar) + pbp * (jvar - lvar) + (jvar shr 1)) div jvar;
           cur_ticks := 1;
           writedeltatime(ivar, cur_ticks);
           txt := chr(m and $7F) + chr(m shr 7);
           remember(txt, ivar);
          end;

          // Remember our new pitch bend position
          bent := n - noteplaying;

          // The note's duration is over.
          inc(lofs, 4);
          // If the next code is FB, off the note and reset pitch bend.
          if byte((loader + lofs)^) <> $FB then begin
           writedeltatime(ivar, cur_ticks);
           txt := chr($80 or cur_channel) + chr(noteplaying) + chr(volume);
           remember(txt, ivar);
           txt := chr(0) + chr($E0 or cur_channel) + chr(0) + chr($40);
           remember(txt, ivar);
           if vibra.active and 8 <> 0 then begin // and remove modulation
            vibra.active := vibra.active and 7;
            txt := chr(0) + chr($B0 or cur_channel) + chr(1) + chr(0);
            remember(txt, ivar);
           end;
           noteplaying := $FF; bent := 0;
          end;
         end;
    // unknown
    $DC, $DD: inc(lofs, 2);
    // Reset? DF C0
    $DF: if m = $C0 then inc(lofs, 2)
         else begin
          Decomp_dotM := '$DF subcommand $' + strhex(m) + ' not known! @ $' + strhex(lofs);
          exit;
         end;
    // Unknown...
    $E2,$E3,$E8,$ED,$EE: inc(lofs, 2);
    $E6, $EF: inc(lofs, 1);
    $F0: inc(lofs, 5);
    // Vibrato
    $F1: begin
          vibra.active := m and 3;
          inc(lofs, 2);
         end;
    $F2: begin
          vibra.delay := m;
          vibra.rate := n;
          vibra.stepsize := byte((loader + lofs + 1)^);
          vibra.depth := byte((loader + lofs + 2)^);
          inc(lofs, 5);
          if vibra.delay = 1 then vibra.delay := 8
          else if vibra.delay = 2 then vibra.delay := 16;
          if vibra.depth > 6 then vibra.depth := 127
          else vibra.depth := 31 + vibra.depth * 16;
         end;
    // Volumesliding
    $F3: begin
          volume := (volume * 15) div 16;
          inc(lofs);
         end;
    $F4: begin
          volume := (volume * 16) div 15 + 1;
          if volume > 127 then volume := 127;
          inc(lofs);
         end;
    // Transposition
    $E7,$F5: begin
          inc(lofs, 2);
         end;
    // Loop marker
    $F6: begin
          writedeltatime(ivar, cur_ticks);
          txt := chr($FF) + chr($06) + chr(9) + 'LoopStart';
          remember(txt, ivar);
          trackloop[ivar] := tofs[ivar];
          tracktime[ivar] := 0;
          inc(lofs);
         end;
    // unknown, points to an F8
    $F7: inc(lofs, 3);
    // Repetition
    $F8: begin
          //m := m or (n shl 8);
          if m = 0 then break; // infinite loop!
          if repecount[repenest] = $FFFF then repecount[repenest] := m;
          dec(repecount[repenest]);
          if repecount[repenest] <> 0 then
           lofs := (byte((loader + lofs + 3)^) or (byte((loader + lofs + 4)^) shl 8)) + 2 + cofs
          else begin inc(lofs, 5); dec(repenest); end;
         end;
    $F9: begin
          inc(repenest); repecount[repenest] := $FFFF;
          inc(lofs, 3);
         end;
    // Detuning
    $FA: begin
          {$ifdef bonk}
          writedeltatime(cur_ticks);
          jvar := integer(m or (n shl 8)) + $2000;
          txt := chr($E0 or chnmap[ivar]) + chr(j and $7F) + chr((j shr 7) and $7F);
          remember(txt, ivar); // pitch bend
          {$endif}
          inc(lofs, 3);
         end;
    // Continue the previous note without cutting it
    $FB: inc(lofs);
    // Tempo
    $FC: begin
          writedeltatime(ivar, cur_ticks);
          jvar := -14500 * m + 3700000; // approximate conversion
          txt := chr($FF) + chr($51) + chr($03) + chr((jvar shr 16) and $FF)
                 + chr((jvar shr 8) and $FF) + chr(jvar and $FF);
          remember(txt, ivar); // add tempo change to data stream
          if (mversion = 0) and (m = $FE) then inc(lofs);
          inc(lofs, 2);
         end;
    // Volume
    $FD: begin
          volume := (m * 3 div 4) * songinfo.instvol[cur_inst] div 64;
          //if volume < 1 then volume := 1;
          if volume > 127 then volume := 127;
          inc(lofs, 2);
         end;
    // Staccato, values range 0..$F
    $FE: begin
          staccato := m and $F;
          inc(lofs, 2);
         end;
    // Instrument selection
    $FF: begin
          if (songinfo.forceinst[ivar] = $FF) and (cur_inst <> m) then begin
           addinstrument(m);
           cur_inst := m;
           // percussive instrument? then switch to percussion channel
           if songinfo.instmap[cur_inst] >= 128 then cur_channel := 9
           else begin
            // melodic instrument? use normal channel, send instrument message
            cur_channel := ivar;
            if cur_channel in [9..14] then inc(cur_channel);
            writedeltatime(ivar, cur_ticks);
            txt := chr($C0 or cur_channel) + chr(songinfo.instmap[cur_inst]);
            remember(txt, ivar);
           end;
          end;
          inc(lofs, 2);
         end;

    else begin
          Decomp_dotM := 'Unrecognized command $' + strhex(lvar) + ' @ $' + strhex(lofs);
          exit;
         end;
   end;

  until lofs + cofs >= trackptr[ivar + 1];

  if tracktime[ivar] <> 0 then begin
   write(stdout, 'Track ' + strdec(ivar + 1) + ':');
   lvar := 0;
   while lvar < dword(length(instused)) do begin
    write(stdout, ' ' + strdec(instused[lvar]));
    inc(lvar);
   end;
   writeln(stdout, '');
  end;

  writedeltatime(ivar, cur_ticks);
 end;

 // Now the tracks have been translated. However, they may still end at
 // different times.
 // Find the longest track
 jvar := 0;
 for ivar := 0 to numtracks - 1 do
  if tracktime[ivar] > jvar then jvar := tracktime[ivar];

 // If a track is shorter than the longest track, and has a loop defined,
 // repeat the loop until the track becomes long enough.
 for ivar := 0 to numtracks - 1 do
 if (tracktime[ivar] < jvar) and (trackloop[ivar] <> $FFFFFFFF) then begin

  while trackdata[ivar][trackloop[ivar]] and $80 <> 0 do inc(trackloop[ivar]);
  inc(trackloop[ivar]);

  trackptr[ivar] := tofs[ivar] - trackloop[ivar];
  getmem(poku, trackptr[ivar]);
  move(trackdata[ivar][trackloop[ivar]], poku^, trackptr[ivar]);
  lvar := jvar div tracktime[ivar];
  while lvar > 1 do begin
   if tofs[ivar] + trackptr[ivar] >= dword(length(trackdata[ivar])) then setlength(trackdata[ivar], length(trackdata[ivar]) + 65536);
   move(poku^, trackdata[ivar][tofs[ivar]], trackptr[ivar]);
   inc(tofs[ivar], trackptr[ivar]);
   dec(lvar);
  end;
  freemem(poku); poku := NIL;
 end;

 // The tracks are now built as midi data in track[]^
 // Count the number of tracks with actual data
 jvar := 0;
 for ivar := numtracks - 1 downto 0 do if tracktime[ivar] <> 0 then inc(jvar);

 // Output the midi file header
 txt := 'MThd' // signature
        + chr(0) + chr(0) + chr(0) + chr(6) // header data length
        + chr(0) + chr(1) // MIDI file type 1 - multiple simultaneous tracks
        + chr(0) + chr(jvar) // midi tracks present
        + chr(0) + chr($60); // ticks per quarternote - best guess constant
 blockwrite(filu, txt[1], 14);

 // Output the tracks
 for ivar := 0 to numtracks - 1 do
 if tracktime[ivar] <> 0 then begin
  txt := 'MTrk'; // track start signature
  blockwrite(filu, txt[1], 4);
  // append an end of track mark in track[ivar]^
  txt := chr($FF) + chr($2F) + chr(0);
  remember(txt, ivar);
  // flip track length tofs[ivar] into MSB form, and write it all out
  jvar := swapendian(tofs[ivar]);
  blockwrite(filu, jvar, 4);
  blockwrite(filu, trackdata[ivar][0], tofs[ivar]);
  setlength(trackdata[ivar], 0);
 end;
end;

function Decomp_SC5(const srcfile, outputfile : UTF8string) : UTF8string;
// Reads the indicated .SC5 Recomposer midi file, and saves it in outputfile
// as a normal midi file.
// Returns an empty string if successful, otherwise returns an error message.
var ivar : longint;
    jvar, lvar, tempo : dword;
    txt : string;
    track : record // use this for working variables of each track
      startofs : dword; // beginning offset of the track's header
      size : dword; // size of track data in bytes, including header
      jumpedfrom : dword; // used by FC "goto" and FD "return" commands
      channel : byte; // midi channel assigned to this track
      repenestlevel, repenestbackup : byte;
      repecount : array[0..15] of byte;
      repefromlofs, repefromtofs, repefromtime : array[0..15] of dword;
      keyadjust : shortint;
    end;
    loopstarttime : array[0..18] of dword;
    control : array of record // put all control events here, sort later
      time : dword;
      event : string[16];
    end;
    livenotes : array[0..31] of record
      note, duration : byte;
    end;

    ticksperquarternote, timesignature : word;
    numtracks : byte;
    global_keyadjust : shortint;
begin
 // Load the input file into loader^.
 Decomp_SC5 := LoadFile(srcfile);
 if Decomp_SC5 <> '' then exit;
 Decomp_SC5 := '.SC5 file support is offline';
 exit;

 livenotes[0].note := $FF; // just to remove a compiler warning
 loopstarttime[0] := 0;
 filldword(loopstarttime[0], length(loopstarttime), 0);

 if (dword(loader^) <> $2D4D4352) or (dword((loader + 4)^) <> $38394350)
 or (dword((loader + 8)^) <> $302E3256)
 then begin
  Decomp_SC5 := 'Unknown file signature';
  exit;
 end;

 //ReadSongInfo(musname + '.sc5');

 // Read the header
 lofs := $1C0;
 ticksperquarternote := byte((loader + lofs)^) + byte((loader + lofs + 27)^) shl 8;
 tempo := byte((loader + lofs + 1)^);
 timesignature := word((loader + lofs + 2)^);
 global_keyadjust := byte((loader + lofs + 5)^);
 numtracks := byte((loader + lofs + 26)^);
 if numtracks in [1..18] = FALSE then numtracks := 18;
 // Init the control track
 setlength(control, 2);
 // initial tempo
 lvar := 60000000 div tempo;
 control[0].time := 0;
 control[0].event := chr($FF) + chr($51) + chr($03)
  + chr((lvar shr 16) and $FF) + chr((lvar shr 8) and $FF) + chr(lvar and $FF);
 // time signature (often 4/4)
 lvar := 1; while dword(1 shl lvar) < (timesignature shr 8) do inc(lvar); // denominator
 control[1].time := 0;
 control[1].event := chr($FF) + chr($58) + chr(4)
  + chr(timesignature and $FF) + chr(lvar) + chr($18) + chr(8);

 ivar := 0; lofs := $586; // jump to start of first track
 while ivar < numtracks do begin
  inc(ivar);
  setlength(trackdata[ivar], 65536);
  tofs[ivar] := 0; tracktime[ivar] := 0; cur_ticks := 0;
  trackloop[ivar] := $FFFFFFFF;
  if lofs + $30 > loadersize then begin
   Decomp_SC5 := 'Unexpected end of file!';
   exit;
  end;
  // Read the track header
  track.startofs := lofs;
  track.size := word((loader + lofs)^);
  track.channel := byte((loader + lofs + 4)^);
  // If the track is disabled, or only contains the header, screw it
  if (track.channel = $FF) or (track.size <= $30) then begin
   lofs := track.startofs + track.size; // jump to next track's header
   dec(ivar); dec(numtracks); continue;
  end;
  track.channel := track.channel and $F;
  track.keyadjust := shortint((loader + lofs + 5)^);
  if track.keyadjust and $80 <> 0 then track.keyadjust := -global_keyadjust;
  track.repenestlevel := 0;
  track.jumpedfrom := 0;
  fillbyte(livenotes, dword(length(livenotes)) * sizeof(livenotes[0]), $FF);

  // Start with an all controllers off
  txt := chr(0) + chr($B0 or track.channel) + chr(121) + chr(0);
  remember(txt, ivar);
  // Pitch wheel middle
  txt := chr(0) + chr($E0 or track.channel) + chr(0) + chr($40);
  remember(txt, ivar);
  // And reset the freaking pitch bend range to +/- 2 semitones
  txt := chr(0) + chr($B0 or track.channel) + chr(101) + chr(0)
       + chr(0) + chr($B0 or track.channel) + chr(100) + chr(0)
       + chr(0) + chr($B0 or track.channel) + chr(6) + chr(2)
       + chr(0) + chr($B0 or track.channel) + chr(38) + chr(0);
  remember(txt, ivar);
  // And set the instrument bank to 0
  txt := chr(0) + chr($B0 or track.channel) + chr(0) + chr(0);
  remember(txt, ivar);
  // (really, the midi player should do all this itself, but some don't)

  // Get the track's name, add it to midi track data
  byte(txt[0]) := 36;
  move((loader + lofs + 8)^, txt[1], 36);
  while (byte(txt[0]) <> 0) and (txt[byte(txt[0])] in [chr(0), chr(32)]) do dec(byte(txt[0]));
  txt := chr(0) + chr($FF) + chr($03) + chr(length(txt)) + txt;
  remember(txt, ivar);

  inc(lofs, 44); // on to the event data
  while lofs < track.startofs + track.size do begin

   // Overflow/infinite loop protection
   if tofs[ivar] > 256000 then begin
    Decomp_SC5 := 'Midi output overflow on track ' + strdec(ivar) + ' @ $' + strhex(lofs) + ' (jumped from $' + strhex(track.jumpedfrom) + ')';
    exit;
   end;

   jvar := dword((loader + lofs)^); // get the entire dword event into j
   inc(lofs, 4); // point to the next event

   // Act on known event codes
   case jvar and $FF of
    // Note on
    $00..$7F: if (jvar and $FF0000 <> 0) and ((jvar shr 24) and $7F <> 0)
         // duration and velocity data must be non-zero
         then begin
          // ivar = note, jvar = duration
          ivar := shortint(jvar and $7F) + global_keyadjust + track.keyadjust;
          if ivar < 0 then ivar := 0 else if ivar > $7F then ivar := $7F;
          jvar := (jvar shr 16) and $FF;
          if jvar = $FF then dec(jvar); // FF is for free livenote slots
          // Is this note playing?
          for lvar := high(livenotes) downto 0 do
           if livenotes[lvar].note = ivar then break;
          if livenotes[lvar].note = ivar then begin
           // The note is playing, so reset its duration; re-sort livenotes
           // jvar = duration, ivar = note
           // Remove it from livenotes, push others down to free top slot
           while lvar < dword(high(livenotes)) do begin
            livenotes[lvar] := livenotes[lvar + 1];
            inc(lvar);
           end;
           // Push livenotes up toward top slot until right duration is found
           while (lvar <> 0) and (livenotes[lvar - 1].duration <= jvar) do begin
            livenotes[lvar] := livenotes[lvar - 1];
            dec(lvar);
           end;
           // Insert refreshed note back into livenotes
           livenotes[lvar].duration := jvar; livenotes[lvar].note := ivar;
          end else begin
           // The note is not playing, so make it start playing
           writedeltatime(ivar, cur_ticks);
           txt := chr($90 or track.channel) + chr(ivar) + chr((jvar shr 24) and $7F);
           remember(txt, ivar);
           // Also, find a good slot in livenotes, keeping list sorted
           lvar := high(livenotes);
           while (lvar <> 0) and (livenotes[lvar].duration <= jvar) do dec(lvar);
           if livenotes[lvar].duration <= jvar then
            PrintError('Too much polyphony @ $' + strhex(lofs) + '! max ' + strdec(length(livenotes)));
           // Move everything below that slot down by one, to make room
           ivar := 0;
           while dword(ivar) < lvar do begin livenotes[ivar] := livenotes[ivar + 1]; inc(ivar); end;
           // Stick new note in livenotes
           livenotes[lvar].note := byte(txt[2]);
           livenotes[lvar].duration := jvar;
          end;
         end;
    // Channel change
    $E6: begin
          ivar := ((jvar shr 16) and $F);
          if ivar = 0 then break // if yy=0, disable the channel for good
          else track.channel := ivar - 1;
         end;
    // Tempo change (accumulate events into control array)
    $E7: begin
          lvar := 60000000 div (((jvar shr 16) and $FF) * tempo div 64);
          setlength(control, length(control) + 1);
          control[high(control)].time := longint(tracktime[ivar]) + cur_ticks;
          control[high(control)].event := chr($FF) + chr($51) + chr($03)
            + chr((lvar shr 16) and $FF) + chr((lvar shr 8) and $FF) + chr(lvar and $FF);
         end;
    // Aftertouch
    $EA: begin
          //txt := chr($A0 or track.channel) + chr((j shr 16) and $7F);
          PrintError('$EA aftertouch not implemented');
         end;
    // Control change
    $EB: begin
          jvar := (jvar shr 16) and $7F;
          // controllers 98/99 are synth-specific and can have unpleasant
          // consequences on midi devices other than the original...
          if jvar in [98, 99] = FALSE then begin
           writedeltatime(ivar, cur_ticks);
           txt := chr($B0 or track.channel) + chr(jvar) + chr((jvar shr 24) and $7F);
           remember(txt, ivar);
          end;
         end;
    // Instrument change (ignore for percussion channel 10)
    $EC: if track.channel <> 9 then begin
          writedeltatime(ivar, cur_ticks);
          txt := chr($C0 or track.channel) + chr((jvar shr 16) and $7F);
          remember(txt, ivar);
         end;
    // Pitch bend
    $EE: begin
          writedeltatime(ivar, cur_ticks);
          txt := chr($E0 or track.channel) + chr((jvar shr 16) and $7F) + chr((jvar shr 24) and $7F);
          remember(txt, ivar);
         end;
    // Loop end
    $F8: // Is there a loop start somewhere waiting for us?
         if track.repenestlevel <> 0 then begin
          lvar := (jvar shr 8) and $FF;
          // Is it an infinite loop? In that case this is the end of track.
          if lvar in [0, $FE, $FF] then begin
           // drop a marker
           writedeltatime(ivar, cur_ticks);
           txt := chr($FF) + chr(6) + chr(1) + '<';
           remember(txt, ivar);
           // remember loop's time and place
           dec(track.repenestlevel);
           loopstarttime[ivar] := track.repefromtime[track.repenestlevel];
           trackloop[ivar] := track.repefromtofs[track.repenestlevel];
           break;
          end;
          // Is repetition count for this level met?
          if track.repecount[track.repenestlevel - 1] < lvar
          then begin
           // More repetition is needed
           inc(track.repecount[track.repenestlevel - 1]);
           lofs := track.repefromlofs[track.repenestlevel - 1];
          end else begin
           // Enough is enough. Drop down a nesting level.
           dec(track.repenestlevel);
          end;
         end;
    // Loop start
    $F9: if track.repenestlevel > high(track.repefromlofs)
         then begin
          Decomp_SC5 := 'F9 loop nested too much @ $' + strhex(lofs);
          exit;
         end else
         begin
          // drop a marker
          writedeltatime(ivar, cur_ticks);
          txt := chr($FF) + chr(6) + chr(1) + '>';
          remember(txt, ivar);
          // push current state onto repetition stack
          track.repefromlofs[track.repenestlevel] := lofs;
          track.repefromtofs[track.repenestlevel] := tofs[ivar];
          track.repefromtime[track.repenestlevel] := tracktime[ivar];
          track.repecount[track.repenestlevel] := 1;
          inc(track.repenestlevel);
         end;
    // Goto command!
    $FC: // Are we already in a goto?
         if track.jumpedfrom <> 0 then begin
          // yes! In that case, return.
          lofs := track.jumpedfrom;
          track.jumpedfrom := 0;
          track.repenestlevel := track.repenestbackup;
         end else begin
          // no! Jump to the new address, remember the old one!
          lvar := (jvar shr 16);
          if lvar > track.size then PrintError('FC jump out of bounds @ ' + strhex(lofs))
          else begin
           track.jumpedfrom := lofs;
           lofs := track.startofs + lvar;
           track.repenestbackup := track.repenestlevel;
          end;
         end;
    // Return from goto!
    $FD: if track.jumpedfrom <> 0 then begin
          lofs := track.jumpedfrom;
          track.jumpedfrom := 0;
          track.repenestlevel := track.repenestbackup;
         end;
    // End of track
    $FE: break;
   end;

   // If the command was $F0..FE, then ignore xx, don't add it to ticks.
   if jvar and $F0 = $F0 then continue;
   // Add up current track time, see if any notes need offing.
   // jvar = ticks until next event
   jvar := (jvar shr 8) and $FF;

   // All ongoing notes must now have their duration reduced by j ticks.
   // First see how many notes have less than j ticks left.
   jvar := length(livenotes);
   while (jvar <> 0) and (livenotes[jvar - 1].duration <= jvar) do dec(jvar);
   // Off any and all such notes
   if jvar <> length(livenotes) then begin
    lvar := high(livenotes);
    while lvar >= jvar do begin
     writedeltatime(ivar, cur_ticks + livenotes[lvar].duration);
     cur_ticks := -livenotes[lvar].duration;
     txt := chr($90 or track.channel) + chr(livenotes[lvar].note) + chr(0);
     remember(txt, ivar);
     dec(lvar);
    end;
    cur_ticks := jvar - livenotes[lvar + 1].duration;
    // Shift remaining notes up to vacated slots
    ivar := length(livenotes) - jvar;
    lvar := jvar;
    while lvar <> 0 do begin
     dec(lvar); livenotes[lvar + dword(ivar)] := livenotes[lvar];
    end;
    // Clear the lowest slots that just had their contents shifted out
    fillbyte(livenotes, ivar * sizeof(livenotes[0]), $FF);
   end
   // If no notes were offed, add j ticks to counter from last midi message
   else inc(cur_ticks, longint(jvar));

   // Shave the full j ticks off all remaining notes
   for lvar := high(livenotes) downto 0 do
    if livenotes[lvar].duration <> $FF
    then dec(livenotes[lvar].duration, jvar);
  end;

  // The track data ended. Any notes still on must be offed!
  lvar := length(livenotes);
  while (lvar <> 0) and (livenotes[lvar - 1].duration <> $FF) do begin
   dec(lvar);
   if trackloop[ivar] = $FFFFFFFF then begin // no loop? Notes get full duration
    writedeltatime(ivar, cur_ticks + livenotes[lvar].duration);
    cur_ticks := -livenotes[lvar].duration;
   end else
    writedeltatime(ivar, 0); // yes loop? Notes get cut dead right away.
   txt := chr($90 or track.channel) + chr(livenotes[lvar].note) + chr(0);
   remember(txt, ivar);
  end;
  // jump to the next track's header
  lofs := track.startofs + track.size;
 end;

 // Handle asynchronous track looping
 // Find the longest track's length, count the number of looping tracks
 jvar := 0; jvar := 0;
 for ivar := 1 to numtracks do begin
  if tracktime[ivar] > jvar then jvar := tracktime[ivar];
  if trackloop[ivar] <> $FFFFFFFF then inc(jvar);
 end;
 // Drop a loopend mark at the end of the song
 if jvar <> 0 then begin
  setlength(control, length(control) + 1);
  control[high(control)].time := jvar;
  control[high(control)].event := chr($FF) + chr($06) + chr($07) + 'LoopEnd';
 end;
 // All looping tracks must be that long
 for ivar := 1 to numtracks do
  if (trackloop[ivar] <> $FFFFFFFF)
  and (tracktime[ivar] {+ 30} < jvar) // allow some fuzziness
  then begin
   // Calculate how many times track needs to repeat to reach needed length
   lvar := dword(jvar - tracktime[ivar]) div dword(tracktime[ivar] - loopstarttime[ivar]);
   //ivar := tofs[ivar] - trackloop[ivar]; //???
   // Copy midi data that many times
   setlength(trackdata[ivar], tofs[ivar] * (lvar + 1));
   while lvar <> 0 do begin
    move(trackdata[ivar][trackloop[ivar]], trackdata[ivar][tofs[ivar]], ivar);
    inc(tofs[ivar], dword(ivar));
    dec(lvar);
   end;
  end;
 // Find the latest loop start point, drop a marker there
 if jvar <> 0 then begin
  jvar := 0;
  for ivar := 1 to numtracks do
   if (trackloop[ivar] <> $FFFFFFFF) and (loopstarttime[ivar] > jvar) then jvar := loopstarttime[ivar];
  setlength(control, length(control) + 1);
  control[high(control)].time := jvar;
  control[high(control)].event := chr($FF) + chr($06) + chr($09) + 'LoopStart';
 end;

 // Sort out the control track (it's small, just use brute force)
 setlength(trackdata[0], length(control) * 32);
 tracktime[0] := 0; tofs[0] := 0; ivar := 0; jvar := length(control);
 while jvar <> 0 do begin
  // Find the lowest event time
  lvar := $FFFFFFFF; ivar := 0;
  for jvar := 0 to high(control) do // don't use downto 0, it breaks tempo
   if control[jvar].time < lvar then begin
    lvar := control[jvar].time;
    ivar := jvar;
   end;
  // Stuff the event into track 0
  writedeltatime(ivar, lvar - tracktime[0]);
  txt := control[ivar].event;
  remember(txt, ivar);
  // Give it a ridiculous time so it doesn't get picked as lowest again
  control[ivar].time := $FFFFFFFF;
  dec(jvar);
 end;

 // Output the midi file header
 txt := 'MThd' // signature
      + chr(0) + chr(0) + chr(0) + chr(6) // header data length
      + chr(0) + chr(1) // MIDI file type 1 - multiple simultaneous tracks
      + chr(0) + chr(numtracks + 1) // midi tracks present (+1 control track)
      + chr(ticksperquarternote shr 8) + chr(ticksperquarternote and $FF);
 blockwrite(filu, txt[1], 14);

 // Output the track data into the file
 for ivar := 0 to numtracks do begin
  txt := 'MTrk'; // track start signature
  blockwrite(filu, txt[1], 4);
  // append an end of track mark in track[ivar]^
  txt := chr(0) + chr($FF) + chr($2F) + chr(0);
  remember(txt, ivar);
  // flip track length tofs[ivar] into MSB form, and write it all out
  jvar := swapendian(tofs[ivar]);
  blockwrite(filu, jvar, 4);
  blockwrite(filu, trackdata[ivar][0], tofs[ivar]);
  setlength(trackdata[ivar], 0);
 end;
end;
