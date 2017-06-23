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

var mv_MainWinH : PSDL_Window;
    mv_RendererH : PSDL_Renderer;
    mv_MainTexH : PSDL_Texture;
    mv_GamepadH : PSDL_GameController;
    mv_PKeystate : pointer;

procedure ScreenModeSwitch(usefull : boolean); forward;

procedure LogError(const ert : UTF8string);
begin
 writeln(logfile, '[!] ', ert);
 if length(ert) > length(debugbuffer[debugbufindex])
  then setlength(debugbuffer[debugbufindex], 0);
 setlength(debugbuffer[debugbufindex], length(ert));
 move(ert[1], debugbuffer[debugbufindex][1], length(ert));
 debugbufindex := (debugbufindex + 1) and high(debugbuffer);
 // If the debug log is currently visible, redraw it.
 if (TBox[0].boxstate <> BOXSTATE_NULL)
 and (sysvar.transcriptmode = FALSE) then PrintDebugBuffer;
 SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, 'Error', @ert[1], mv_MainWinH);
end;

const SDL_INIT_EVENTS = $00004000;

procedure SetProgramName(const newnamu : UTF8string); inline;
begin
 if newnamu <> '' then SDL_SetWindowTitle(mv_MainWinH, @newnamu[1])
 else SDL_SetWindowTitle(mv_MainWinH, NIL);
end;

function CompStrFast(const str1, str2 : UTF8string) : boolean;
begin
 CompStrFast := FALSE;
 if length(str1) <> length(str2) then exit;
 if (length(str1) = 0)
 or (str1[1] = str2[1])
 or (byte(str1[1]) in [65..90, 97..122])
 and (byte(str2[1]) in [65..90, 97..122])
 and (byte(str1[1]) or $20 = byte(str2[1]) or $20)
 then if lowercase(str1) = lowercase(str2) then CompStrFast := TRUE;
end;

function FindFont(fontmatch : UTF8string) : UTF8string;
// Attempts to locate a .ttf or .otf file for the given font match. Returns
// the exact font path if found, otherwise an empty string.
var sysfontdir : array of UTF8string;
    filudir, filuext, foundindir : UTF8string;
    filusr : TSearchRec;
    ivar : dword;
    searchresult : longint;

  procedure lookatdir(dirnamu : UTF8string; const filunamu : UTF8string);
  var looksr : TSearchRec;
      lookres : longint;
  begin
   log('Looking for ' + dirnamu + filunamu);
   lookres := FindFirst(dirnamu + filunamu, faReadOnly, looksr);
   while lookres = 0 do begin
    filuext := lowercase(ExtractFileExt(looksr.Name));
    if (filuext = '.ttf') or (filuext = '.otf') or (filuext = '.ttc')
    or (filuext = '.fon') then begin
     log('found ' + dirnamu + looksr.Name);
     if (FindFont = '') or (looksr.Name < FindFont)
     then begin
      foundindir := dirnamu;
      FindFont := looksr.Name;
     end;
    end;
    lookres := FindNext(looksr);
   end;
   FindClose(looksr);
   // Also check sub-directories.
   lookres := FindFirst(dirnamu + '*', faDirectory or faReadOnly, looksr);
   while lookres = 0 do begin
    if (looksr.Attr and faDirectory <> 0) and (looksr.Name[1] <> '.')
    then lookatdir(dirnamu + looksr.Name + DirectorySeparator, filunamu);
    lookres := FindNext(looksr);
   end;
   FindClose(looksr);
  end;

begin
 FindFont := ''; foundindir := '';
 log('Trying to match font: ' + fontmatch);
 if pos(DirectorySeparator, fontmatch) <> 0 then begin
  // Fontmatch contains an explicit directory. Just look there.
  filudir := ExtractFilePath(fontmatch);
  searchresult := FindFirst(fontmatch, faReadOnly, filusr);
  log('Looking in ' + filudir);
  while searchresult = 0 do begin
   filuext := lowercase(ExtractFileExt(filusr.Name));
   if (filuext = '.ttf') or (filuext = '.otf') or (filuext = '.fon') then begin
    log('found ' + filudir + filusr.Name);
    if (FindFont = '') or (filusr.Name < FindFont)
    then begin
     FindFont := filusr.Name;
     foundindir := filudir;
    end;
   end;
   searchresult := FindNext(filusr);
  end;
  FindClose(filusr);
 end
 else begin
  // Fontmatch doesn't contain a directory. Look in known font directories.
  {$ifdef WINDOWS}
  setlength(sysfontdir, 1);
  sysfontdir[0] := GetEnvironmentVariable('windir');
  if sysfontdir[0] = '' then sysfontdir[0] := 'C:\WINDOWS';
  sysfontdir[0] := sysfontdir[0] + '\Fonts\';
  {$else}
  setlength(sysfontdir, 3);
  sysfontdir[0] := '~/.fonts/';
  sysfontdir[1] := '/usr/local/share/fonts/';
  sysfontdir[2] := '/usr/share/fonts/';
  {$endif}
  for ivar := 0 to high(sysfontdir) do lookatdir(sysfontdir[ivar], fontmatch);
 end;

 if FindFont = '' then log('No match :(') else begin
  FindFont := foundindir + FindFont;
  log('Using ' + FindFont);
 end;
end;

function IsFontLangInList(const lang : UTF8string) : dword;
// Returns the given language's fontlist[] index if it exists, or a value out
// of range otherwise.
begin
 IsFontLangInList := 0;
 while IsFontLangInList < dword(length(fontlist)) do begin
  if CompStrFast(lang, fontlist[IsFontLangInList].fontlang) then exit;
  inc(IsFontLangInList);
 end;
end;

function AddFontLang(const lang : UTF8string; matchstr : UTF8string) : boolean;
// Tries to find a matching font and adds it to fontlist[]. Returns true if
// successful.
var findres : UTF8string;
begin
 AddFontLang := FALSE;
 // Remove double-quotes, if they are present for some reason.
 if (matchstr[1] = '"') and (matchstr[length(matchstr)] = '"')
 then matchstr := copy(matchstr, 2, length(matchstr) - 2);
 // Try to find the font file!
 findres := FindFont(matchstr);
 if (findres = '') and (matchstr[length(matchstr)] <> '*') then begin
  matchstr := matchstr + '*';
  findres := FindFont(matchstr);
 end;
 {$ifndef WINDOWS}
 if (findres = '') and (byte(matchstr[1]) in [97..122]) then begin
  // Try again but with a capital first letter!
  byte(matchstr[1]) := byte(matchstr[1]) - $20;
  findres := FindFont(matchstr);
 end;
 {$endif}
 if findres <> '' then begin
  AddFontLang := TRUE;
  setlength(fontlist, length(fontlist) + 1);
  with fontlist[length(fontlist) - 1] do begin
   fontlang := lang;
   fontmatch := matchstr;
   fontfile := findres;
  end;
 end;
end;
