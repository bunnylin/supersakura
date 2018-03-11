// File I/O, mainly a loader object.

var loader : pointer; // the file being converted usually goes in this
    loadersize, lofs : dword;
    l_bitptr : byte;

{$ifdef caseshenanigans}
function FindFile_caseless(const namu : UTF8string) : UTF8string;
// Tries to find the given filename using a case-insensitive search.
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

 findresult := FindFirst(basedir + '*', faReadOnly, filusr);
 while findresult = 0 do begin
  if lowercase(filusr.Name) = basename then begin
   FindFile_caseless := basedir + filusr.Name;
   break;
  end;
  findresult := FindNext(filusr);
 end;
 FindClose(filusr);
end;
{$endif caseshenanigans}

function LoadFile(const namu : UTF8string) : UTF8string;
// Loads the given file's binary contents into loader^, places the size in
// loadersize. Does not care what the actual file content is.
// Returns an empty string if successful, otherwise returns an error message.
var f : file;
    ivar : dword;
begin
 LoadFile := '';
 while IOresult <> 0 do; // flush
 assign(f, namu);
 filemode := 0; reset(f, 1); // read-only
 ivar := IOresult;
 {$ifdef caseshenanigans}
 // If the file wasn't found, we may have the wrong case in the file name...
 if ivar = 2 then begin
  LoadFile := FindFile_caseless(namu);
  if LoadFile <> '' then begin
   assign(f, LoadFile);
   filemode := 0; reset(f, 1); // read-only
   ivar := IOresult;
   LoadFile := '';
  end;
 end;
 {$endif caseshenanigans}
 if ivar <> 0 then begin
  LoadFile := errortxt(ivar) + ' opening ' + namu;
  exit;
 end;
 // Load the entire file into loader^
 if loader <> NIL then begin freemem(loader); loader := NIL; end;
 loadersize := filesize(f);
 getmem(loader, loadersize);
 blockread(f, loader^, loadersize);
 ivar := IOresult;
 if ivar <> 0 then LoadFile := errortxt(ivar) + ' reading ' + namu;
 close(f);
 while IOresult <> 0 do; // flush
 lofs := 0;
end;

function SaveFile(const namu : UTF8string; buf : pointer; bufsize : dword) : UTF8string;
// Saves bufsize bytes from buf^ into the given file. If the file exists, it
// is overwritten without warning.
// Returns an empty string if successful, otherwise returns an error message.
var f : file;
    targetdir : UTF8string;
    i, j : dword;
begin
 if namu = '' then begin
  SaveFile := 'no file name specified';
  exit;
 end;

 SaveFile := '';
 while IOresult <> 0 do; // flush
 {$ifdef caseshenanigans}
 // On case-sensitive filesystems, to avoid ending up with multiple
 // identically-named differently-cased files, we must explicitly delete any
 // previous file that has a matching name.
 SaveFile := FindFile_caseless(namu);
 if SaveFile <> '' then begin
  assign(f, SaveFile);
  erase(f);
  SaveFile := '';
 end;
 {$endif}

 // Make sure the target directory exists.
 for i := 2 to length(namu) do
  if namu[i] = DirectorySeparator then begin
   targetdir := copy(namu, 1, i);
   if DirectoryExists(targetdir) = FALSE then begin
    mkdir(targetdir);
    j := IOresult;
    if j <> 0 then begin
     SaveFile := errortxt(j) + ' creating directory ' + targetdir;
     exit;
    end;
   end;
  end;

 // Try to write the file.
 assign(f, namu);
 filemode := 1; rewrite(f, 1); // write-only
 i := IOresult;
 if i <> 0 then begin
  SaveFile := errortxt(i) + ' creating ' + namu;
  exit;
 end;
 blockwrite(f, buf^, bufsize);
 i := IOresult;
 if i <> 0 then SaveFile := errortxt(i) + ' writing ' + namu;
 close(f);
 while IOresult <> 0 do; // flush
end;

function l_getbit : boolean;
// Grabs the next bit from (loader + lofs)^, nudges the offset counter.
begin
 l_getbit := boolean((byte((loader + lofs)^) shr l_bitptr) and 1);
 if l_bitptr = 0 then begin
  inc(lofs);
  l_bitptr := 8;
 end;
 dec(l_bitptr);
end;
