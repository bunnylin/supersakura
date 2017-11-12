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

const
STACK_TOKEN_ENDPARAMS = 0;
STACK_TOKEN_MINILOCALSTRING = 1;
STACK_TOKEN_UNIQUETABLESTRING = 2;
STACK_TOKEN_GLOBALTABLESTRING = 3;
STACK_TOKEN_NUMBER = 10; // paired with longint value
STACK_TOKEN_SINGLESTRING = 11; // paired with 1 longstring
STACK_TOKEN_MULTISTRING = 12; // paired with lang x longstrings
STACK_TOKEN_PARAM = 256; // added to wopp enum, see ssscript.pas

// ------------------------------------------------------------------

procedure SaveStateFibers;
begin
end;

procedure LoadStateFibers;
begin
end;

// ------------------------------------------------------------------

procedure ScriptGoto(fibernum : dword; labelnamu : UTF8string);
// Jumps fiber execution to the start of the given label.
var ivar : dword;
begin
 with fiber[fibernum] do begin
  if labelnamu = '' then begin
   LogError('ScriptGoto fiber ' + fibername + ':' + labelname + ': empty label or out of code');
   fiberstate := FIBERSTATE_STOPPING; exit;
  end;
  // Labels must be uppercased.
  labelnamu := upcase(labelnamu);
  // If the target label contains no dots, add some.
  ivar := pos('.', labelnamu);
  if ivar = 0 then begin
   ivar := pos('.', labelname);
   labelnamu := copy(labelname, 1, ivar) + labelnamu;
  end;

  ivar := GetScr(labelnamu);
  if ivar = 0 then begin
   LogError('ScriptGoto fiber ' + fibername + ':' + labelname + ': no such label: ' + labelnamu);
   fiberstate := FIBERSTATE_STOPPING; exit;
  end;
  labelname := labelnamu;
  labelindex := ivar;
  codeofs := 0;
 end;
end;

procedure ScriptCall(fibernum : dword; const labelnamu : UTF8string);
// Pushes the current fiber execution point on a call stack, then jumps fiber
// execution to the start of the given label.
begin
 with fiber[fibernum] do begin
  callstack[callstackindex].labelname := labelname;
  callstack[callstackindex].ofs := codeofs;
  callstackindex := (callstackindex + 1) and CALLSTACK_SIZE;
  // Zero out the next free slot.
  callstack[callstackindex].labelname := '';
 end;
 ScriptGoto(fibernum, labelnamu);
end;

procedure ScriptReturn(fibernum : dword);
// Pops a fiber execution point from the call stack, if available, and
// continues fiber execution from there.
begin
 with fiber[fibernum] do begin
  if callstackindex = 0 then callstackindex := CALLSTACK_SIZE else dec(callstackindex);
  if callstack[callstackindex].labelname = '' then begin
   LogError('ScriptReturn fiber ' + fibername + ':' + labelname + ': out of callstack');
   fiberstate := FIBERSTATE_STOPPING; exit;
  end;

  labelindex := GetScr(callstack[callstackindex].labelname);
  if labelindex = 0 then begin
   LogError('ScriptReturn fiber ' + fibername + ':' + labelname + ': no such label: ' + callstack[callstackindex].labelname);
   fiberstate := FIBERSTATE_STOPPING; exit;
  end;

  labelname := callstack[callstackindex].labelname;
  codeofs := callstack[callstackindex].ofs;
 end;
end;

procedure ScriptCase(fibernum : dword; const labs : UTF8string; caseindex : dword; docall : boolean);
// Labs must be a string of valid labels separated with colons. This selects
// the label indicated by 0-based caseindex, and performs a ScriptCall or
// ScriptGoto depending on the docall parameter.
// If the index is beyond the number of available labels, does nothing.
var startofs, curofs : dword;
begin
 // The label name string must contain labels separated by colons.
 // Find the correct label index.
 startofs := 1; curofs := 1;
 while curofs <= dword(length(labs)) do begin
  if labs[curofs] = ':' then begin
   // Found it!
   if caseindex = 0 then break;
   // Not there yet, keep looking.
   dec(caseindex);
   startofs := curofs + 1;
  end;
  inc(curofs);
 end;

 if caseindex = 0 then if docall
 then ScriptCall(fibernum, copy(labs, startofs, curofs - startofs))
 else ScriptGoto(fibernum, copy(labs, startofs, curofs - startofs));
end;

function ClearWaitKey : boolean;
// Resumes fibers waiting for a keypress. Returns TRUE if any fiber was
// resumed, otherwise FALSE.
var ivar, jvar : dword;
begin
 ClearWaitKey := FALSE;
 if fibercount <> 0 then
  for ivar := fibercount - 1 downto 0 do
   if fiber[ivar].fiberstate in [FIBERSTATE_WAITKEY, FIBERSTATE_WAITCLEAR]
   then begin
    if fiber[ivar].fiberstate = FIBERSTATE_WAITCLEAR then
     for jvar := high(TBox) downto 1 do ClearTextbox(jvar);
    fiber[ivar].fiberstate := FIBERSTATE_NORMAL;
    ClearWaitKey := TRUE;
   end;
end;

procedure SignalFiber(fibernamu : UTF8string);
// Finds all fibers with the given name (case-insensitive), or all fibers if
// empty name, and puts them in a normal state if they were waiting for
// a signal.
var ivar : dword;
begin
 if fibercount = 0 then exit; // no fibers exist
 fibernamu := upcase(fibernamu);
 for ivar := length(fiber) - 1 downto 0 do
  if fiber[ivar].fiberstate in
    [FIBERSTATE_WAITKEY, FIBERSTATE_WAITSIGNAL,
     FIBERSTATE_WAITSLEEP, FIBERSTATE_WAITFX]
  then if (fibernamu = '') or (fiber[ivar].fibername = fibernamu)
  then fiber[ivar].fiberstate := FIBERSTATE_NORMAL;
end;

procedure StopFiber(fibernamu : UTF8string);
// Stops all fibers with the given name. (Case-insensitive comparison.)
var ivar : dword;
begin
 if fibercount = 0 then exit; // no fibers exist
 fibernamu := upcase(fibernamu);
 for ivar := length(fiber) - 1 downto 0 do
  if fiber[ivar].fibername = fibernamu
  then fiber[ivar].fiberstate := FIBERSTATE_STOPPING;
end;

procedure StartFiber(labelnamu, fibernamu : UTF8string);
// Starts a fiber running the given label. Uses the label name as the fiber
// name if fibernamu is empty.
// The new fiber is placed at the end of the fiber list, so if it was created
// from script code, the new fiber is guaranteed to run during the same
// ScriptAhead call before effects/rendering are done.
var ivar : dword;
begin
 // Find the label in script[].
 labelnamu := upcase(labelnamu);
 ivar := GetScr(labelnamu);
 if ivar = 0 then begin
  LogError('StartFiber: label not found: ' + labelnamu);
  exit;
 end;
 // Resize the fiber list if needed.
 if (fibercount + 8 < dword(length(fiber)) shr 1)
 or (fibercount >= dword(length(fiber)))
 then setlength(fiber, fibercount + fibercount shr 1 + 4);
 // Initialise fiber data.
 with fiber[fibercount] do begin
  if fibernamu <> '' then fibername := upcase(fibernamu)
  else fibername := labelnamu;
  log('StartFiber: label ' + labelnamu + ' as ' + strdec(fibercount) + ':' + fibername);
  labelname := labelnamu;
  labelindex := ivar;
  codeofs := 0;
  fxrefcount := 0;
  for ivar := 0 to high(callstack) do begin
   callstack[ivar].labelname := ''; callstack[ivar].ofs := 0;
  end;
  filldword(datastack[0], FIBER_STACK_SIZE + 1, 0);
  dataindex := 0;
  datacount := 0;
  callstackindex := 0;
  fiberstate := FIBERSTATE_NORMAL;
 end;

 inc(fibercount);
end;

procedure RunDebugCommand;
// Extracts the last line from TBox[0], compiles and runs it in a new fiber.
var srcp, resultp : pointer;
    logline : UTF8string;
    ivar : dword;
begin
 // Stop any previous debug command fiber.
 StopFiber(chr(0));

 with TBox[0] do begin
  // Get the command line.
  srcp := @txtcontent[txtlength - userinputlen];
  setlength(logline, userinputlen + 1);
  move(srcp^, logline[1], userinputlen);
  logline[userinputlen + 1] := chr($A); // implicit newline at end
  srcp := @logline[1];
  // Compile the line.
  resultp := CompileScript('', srcp, srcp + userinputlen + 1);
  // Log the line and remove it from TBox[0].
  srcp := NIL;
  setlength(logline, userinputlen);
  log(logline);
  logline := '';
  dec(txtlength, userinputlen);
  caretpos := 0;
  userinputlen := 0;
  if (txtescapecount <> 0)
  and (txtescapelist[txtescapecount - 1].escapecode = 1)
  then txtescapelist[txtescapecount - 1].escapeofs := txtlength;
 end;

 // Reassign label indexes to all active fibers first.
 ivar := fibercount;
 while ivar <> 0 do begin
  dec(ivar);
  fiber[ivar].labelindex := GetScr(fiber[ivar].labelname);
 end;

 if resultp <> NIL then begin
  // Script compile failed. Print error messages in log.
  srcp := resultp;
  while byte(srcp^) <> 0 do begin
   log(string(srcp^));
   inc(srcp, byte(srcp^) + 1);
  end;
  freemem(resultp); resultp := NIL; srcp := NIL;
 end
 else begin
  // Script compile succeeded. Start new fiber in this script.
  // Resize the fiber list if needed.
  if (fibercount + 8 < dword(length(fiber)) shr 1)
  or (fibercount >= dword(length(fiber)))
  then setlength(fiber, fibercount + fibercount shr 1 + 4);
  // Initialise fiber data.
  with fiber[fibercount] do begin
   fibername := chr(0);
   labelname := '';
   labelindex := 0;
   codeofs := 0;
   fxrefcount := 0;
   for ivar := 0 to high(callstack) do begin
    callstack[ivar].labelname := ''; callstack[ivar].ofs := 0;
   end;
   filldword(datastack[0], FIBER_STACK_SIZE + 1, 0);
   dataindex := 0;
   datacount := 0;
   callstackindex := 0;
   fiberstate := FIBERSTATE_NORMAL;
  end;
  inc(fibercount);
 end;
end;

// ------------------------------------------------------------------

procedure ExecuteFiber(fiberid : dword; yieldnow : boolean);
// Executes code in the given fiber until the fiber yields control.
// If yieldnow is TRUE, only executes a single step and returns immediately.
var strvalue, strvalue2 : array of UTF8string;
    numvalue, numvalue2 : longint;

    dynaparamnum : array[0..15] of longint;
    dynaparamstr : array[0..15] of array of UTF8string;
    namedparam : array[0..15] of record
      paramid : byte;
      numvalue : longint;
      strvalue : array of UTF8string;
    end;
    dynaparamnumcount, dynaparamstrcount, namedparamcount : byte;

  procedure fibererror(const msg : string);
  begin
   LogError('Fiber ' + strdec(fiberid) + ':' + fiber[fiberid].labelname + ':' + strdec(fiber[fiberid].codeofs) + '/' + strdec(script[fiber[fiberid].labelindex].codesize) + ': ' + msg);
   fiber[fiberid].fiberstate := FIBERSTATE_STOPPING; yieldnow := TRUE;
  end;

  // ----------------------------------------------------------------
  procedure PushInt(num : longint);
  begin
   with fiber[fiberid] do begin
    longint(datastack[dataindex]) := num;
    dataindex := (dataindex + 1) and FIBER_STACK_SIZE;
    inc(datacount);
    if datacount > FIBER_STACK_SIZE then datacount := FIBER_STACK_SIZE;
   end;
  end;

  function PopInt : longint;
  begin
   with fiber[fiberid] do begin
    if datacount = 0 then begin
     fibererror('Stack underflow');
     PopInt := 0; exit;
    end;
    dec(datacount);
    if dataindex = 0 then dataindex := FIBER_STACK_SIZE else dec(dataindex);
    PopInt := longint(datastack[dataindex]);
   end;
  end;

  procedure PushString(srcp : pointer; numbytes : dword);
  var numdwords, stackfreespace, xfersize : dword;
  begin
   with fiber[fiberid] do begin
    numdwords := numbytes shr 2;
    // Push data up to end of stack.
    stackfreespace := FIBER_STACK_SIZE - dataindex + 1;
    while numdwords >= stackfreespace do begin
     dec(numdwords, stackfreespace);
     xfersize := stackfreespace shl 2;
     move(srcp^, datastack[dataindex], xfersize); inc(srcp, xfersize);
     dataindex := 0;
     stackfreespace := FIBER_STACK_SIZE + 1;
    end;
    // Push rest of full dwords.
    xfersize := numdwords shl 2;
    move(srcp^, datastack[dataindex], xfersize); inc(srcp, xfersize);
    inc(dataindex, numdwords);
    // Push leftover bytes.
    datastack[dataindex] := 0;
    xfersize := numbytes and 3;
    if xfersize <> 0 then begin
     move(srcp^, datastack[dataindex], xfersize);
     dataindex := (dataindex + 1) and FIBER_STACK_SIZE;
    end;
    // Push the string's byte length.
    datastack[dataindex] := numbytes;
    dataindex := (dataindex + 1) and FIBER_STACK_SIZE;
    // Update the valid data counter.
    inc(datacount, (numbytes + 3) shr 2 + 1);
    if datacount > FIBER_STACK_SIZE then datacount := FIBER_STACK_SIZE;
   end;
  end;

  function PopString : UTF8string;
  var slen, numdwords, xfersize : dword;
  begin
   with fiber[fiberid] do begin
    // Get the string's byte length.
    slen := PopInt;
    if slen = 0 then begin PopString := ''; exit; end;
    numdwords := (slen + 3) shr 2;
    if numdwords > datacount then begin
     fibererror('Stack underflow');
     PopString := ''; exit;
    end;
    dec(datacount, numdwords);
    setlength(PopString, numdwords shl 2);
    // Get the second half of the string.
    if numdwords > dataindex then begin
     dec(numdwords, dataindex);
     xfersize := dataindex shl 2;
     move(datastack[0], PopString[length(PopString) - xfersize + 1], xfersize);
     dataindex := FIBER_STACK_SIZE + 1;
    end;
    // Get the first half of the string.
    move(datastack[dataindex - numdwords], PopString[1], numdwords shl 2);
    dec(dataindex, numdwords);

    // Crop the string to its exact size.
    setlength(PopString, slen);
   end;
  end;

  procedure PopThing;
  var ivar : dword;
      typetoken : longint;
  begin
   setlength(strvalue, 0);
   typetoken := PopInt;
   case typetoken of
     STACK_TOKEN_NUMBER: numvalue := PopInt;

     STACK_TOKEN_MINILOCALSTRING: begin
      ivar := PopInt;
      setlength(strvalue, 1);
      strvalue[0] := string((script[fiber[fiberid].labelindex].code + ivar)^);
     end;

     STACK_TOKEN_SINGLESTRING: begin
      setlength(strvalue, 1);
      strvalue[0] := PopString;
     end;

     STACK_TOKEN_MULTISTRING: begin
      setlength(strvalue, length(languagelist));
      for ivar := length(languagelist) - 1 downto 0 do
       strvalue[ivar] := PopString;
     end;

     STACK_TOKEN_UNIQUETABLESTRING: begin
      numvalue := PopInt;
      ivar := length(languagelist);
      setlength(strvalue, ivar);
      while ivar <> 0 do begin
       dec(ivar);
       if numvalue >= length(script[fiber[fiberid].labelindex].stringlist[ivar].txt)
       then strvalue[ivar] := ''
       else strvalue[ivar] := script[fiber[fiberid].labelindex].stringlist[ivar].txt[numvalue];
      end;
     end;

     STACK_TOKEN_GLOBALTABLESTRING: begin
      numvalue := PopInt;
      ivar := length(languagelist);
      setlength(strvalue, ivar);
      while ivar <> 0 do begin
       dec(ivar);
       if numvalue >= length(script[0].stringlist[ivar].txt)
       then strvalue[ivar] := ''
       else strvalue[ivar] := script[0].stringlist[ivar].txt[numvalue];
      end;
     end;

     else fibererror('Bad stack token type: ' + strdec(typetoken));
   end;
  end;

  // ----------------------------------------------------------------
  function GetBestString(preferred : dword) : dword;
  // Used to figure out which language string to display. Returns an index to
  // strvalue[]. If the preferred index is available and contains a non-empty
  // string, returns the preferred index. Otherwise returns the highest index
  // that is available and non-empty, or 0 if no such strings found.
  // If the strvalue array is empty, returns preferred unchanged.
  begin
   GetBestString := preferred;
   if length(strvalue) = 0 then exit;
   if (preferred < dword(length(strvalue)))
    and (strvalue[preferred] <> '') then exit;
   GetBestString := length(strvalue);
   while (GetBestString <> 0) do begin
    dec(GetBestString);
    if strvalue[GetBestString] <> '' then exit;
   end;
  end;

  function FetchParam(paramtoken : byte) : boolean;
  // Looks for the given parameter id in the named parameter list and then
  // fuzzily in the dynamic parameter list. If found, removes it from the
  // list and returns TRUE, placing the value in numvalue or strvalue.
  var ivar, jvar : dword;

    procedure validatestr0;
    begin
     if strvalue[0] <> '' then exit;
     jvar := length(strvalue);
     while jvar > 1 do begin
      dec(jvar);
      if strvalue[jvar] <> '' then begin
       strvalue[0] := strvalue[jvar];
       exit;
      end;
     end;
    end;

  begin
   FetchParam := TRUE;
   // Check named parameter list.
   ivar := namedparamcount;
   while ivar <> 0 do begin
    dec(ivar);
    if namedparam[ivar].paramid = paramtoken then begin
     // Found matching named parameter, save the value.
     if ss_rwoppargtype[paramtoken] = ARG_NUM
     then numvalue := namedparam[ivar].numvalue
     else begin
      strvalue := namedparam[ivar].strvalue;
      validatestr0;
     end;
     // Remove it from named params list.
     namedparam[ivar] := namedparam[namedparamcount - 1];
     dec(namedparamcount);
     exit;
    end;
   end;
   // Check dynamic parameter list.
   if ss_rwoppargtype[paramtoken] = ARG_NUM then begin
    if dynaparamnumcount <> 0 then begin
     dec(dynaparamnumcount);
     numvalue := dynaparamnum[dynaparamnumcount];
     exit;
    end;
   end
   else if dynaparamstrcount <> 0 then begin
    dec(dynaparamstrcount);
    strvalue := dynaparamstr[dynaparamstrcount];
    validatestr0;
    exit;
   end;
   // Param not found, return false.
   FetchParam := FALSE;
  end;

  // ----------------------------------------------------------------
  procedure Stashstrval;
  // Copies strvalue into strvalue2 safely.
  var svar : dword;
      lendiff : longint;
  begin
   // If strvalue is empty, quick exit.
   if length(strvalue) = 0 then begin
    setlength(strvalue2, 0);
    exit;
   end;

   // Resize strvalue2 to same length as strvalue, efficiently.
   lendiff := length(strvalue) - length(strvalue2);
   if lendiff <> 0 then begin
    if lendiff > 0 then setlength(strvalue2, 0);
    setlength(strvalue2, length(strvalue));
   end;

   // Copy the strvalue contents to strvalue2.
   for svar := length(strvalue) - 1 downto 0 do
    strvalue2[svar] := strvalue[svar];
  end;

  procedure ConsumeParams;
  // When a word of power token is encountered, this is called to pop the
  // wop's parameters off the stack and into variables. Parameter identifiers
  // and their values are popped until STACK_TOKEN_ENDPARAMS is found.
  var paramtoken : longint;
      strnum : dword;
  begin
   dynaparamnumcount := 0;
   dynaparamstrcount := 0;
   namedparamcount := 0;
   repeat
    // Get the next parameter identifier. Quit if it is ENDPARAMS.
    paramtoken := PopInt - STACK_TOKEN_PARAM;
    if paramtoken < 0 then exit;
    if (paramtoken >= length(ss_rwoppargtype))
    or (paramtoken <> WOPP_DYNAMIC) and (ss_rwoppargtype[paramtoken] = 0)
    then begin
     fibererror('Param id out of bounds'); exit;
    end;
    // Get the value associated with this parameter. The value may be of any
    // type at this point, so it'll be typefitted later.
    PopThing;

    // Validate value for non-dynamic parameters.
    if paramtoken <> WOPP_DYNAMIC then begin
     if namedparamcount >= dword(length(namedparam)) then begin
      fibererror('Too many named params'); exit;
     end;
     namedparam[namedparamcount].paramid := paramtoken;

     case ss_rwoppargtype[paramtoken] of
       ARG_NUM:
       if length(strvalue) <> 0 then begin
        strnum := GetBestString($FFFF);
        if (length(strvalue[strnum]) > 2) and (strvalue[strnum][1] = '0')
        and (byte(strvalue[strnum][2]) or $20 = byte('x'))
        then namedparam[namedparamcount].numvalue := valhex(copy(strvalue[strnum], 3, length(strvalue[strnum])))
        else namedparam[namedparamcount].numvalue := valx(strvalue[strnum]);
       end
       else namedparam[namedparamcount].numvalue := numvalue;
       ARG_STR:
       if length(strvalue) = 0 then begin
        setlength(namedparam[namedparamcount].strvalue, 1);
        namedparam[namedparamcount].strvalue[0] := strdec(numvalue);
       end
       else namedparam[namedparamcount].strvalue := strvalue;
     end;

     inc(namedparamcount);
    end
    else begin
     // Add dynamic parameters in the dynamic parameter list.
     if length(strvalue) = 0 then begin
      if dynaparamnumcount >= dword(length(dynaparamnum)) then begin
       fibererror('Too many numeric dynamic params'); exit;
      end;
      dynaparamnum[dynaparamnumcount] := numvalue;
      inc(dynaparamnumcount);
     end else begin
      if dynaparamstrcount >= dword(length(dynaparamstr)) then begin
       fibererror('Too many string dynamic params'); exit;
      end;
      dynaparamstr[dynaparamstrcount] := strvalue;
      inc(dynaparamstrcount);
     end;
    end;
   until FALSE;
  end;
  // ----------------------------------------------------------------
  {$include sakufiberwops.pas}

var ivar, jvar : dword;
    token : char;
begin // ExecuteFiber

 // Silence compiler warnings.
 numvalue := 0; numvalue2 := 0;
 setlength(strvalue, 0); setlength(strvalue2, 0);

 repeat with fiber[fiberid] do begin
  // Run the next label, if reached the end of the current one.
  // If there is no next label, terminate the fiber.
  if codeofs >= script[labelindex].codesize then
   if script[labelindex].nextlabel = ''
    then fiberstate := FIBERSTATE_STOPPING
    else ScriptGoto(fiberid, script[labelindex].nextlabel);

  if fiberstate = FIBERSTATE_STOPPING then exit;

  // Process a script token from the current execution address.
  token := char((script[labelindex].code + codeofs)^);
  inc(codeofs);

  case token of
    // Direct number values.
    chr(0)..chr(31): begin
     PushInt(byte(token));
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_BYTE: begin
     PushInt(byte((script[labelindex].code + codeofs)^));
     inc(codeofs);
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_LONGINT: begin
     PushInt(longint((script[labelindex].code + codeofs)^));
     inc(codeofs, 4);
     PushInt(STACK_TOKEN_NUMBER);
    end;

    // String values.
    TOKEN_EMPTYSTRING: begin
     PushInt(0);
     PushInt(STACK_TOKEN_SINGLESTRING);
    end;

    TOKEN_MINILOCALSTRING: begin
     PushInt(codeofs);
     ivar := byte((script[labelindex].code + codeofs)^);
     inc(codeofs, ivar + 1);
     PushInt(STACK_TOKEN_MINILOCALSTRING);
    end;

    TOKEN_LONGLOCALSTRING: begin
     ivar := dword((script[labelindex].code + codeofs)^);
     inc(codeofs, 4);
     PushString(script[labelindex].code + codeofs, ivar);
     inc(codeofs, ivar);
     PushInt(STACK_TOKEN_SINGLESTRING);
    end;

    TOKEN_MINIUNIQUESTRING: begin
     PushInt(byte((script[labelindex].code + codeofs)^));
     inc(codeofs);
     PushInt(STACK_TOKEN_UNIQUETABLESTRING);
    end;

    TOKEN_LONGUNIQUESTRING: begin
     PushInt(longint((script[labelindex].code + codeofs)^));
     inc(codeofs, 4);
     PushInt(STACK_TOKEN_UNIQUETABLESTRING);
    end;

    TOKEN_MINIGLOBALSTRING: begin
     PushInt(byte((script[labelindex].code + codeofs)^));
     inc(codeofs);
     PushInt(STACK_TOKEN_GLOBALTABLESTRING);
    end;

    TOKEN_LONGGLOBALSTRING: begin
     PushInt(longint((script[labelindex].code + codeofs)^));
     inc(codeofs, 4);
     PushInt(STACK_TOKEN_GLOBALTABLESTRING);
    end;

    // Unary operations.
    TOKEN_NOT: begin
     PopThing;
     if length(strvalue) <> 0 then begin
      // Notting returns an empty string if input is non-empty, else "1".
      if strvalue[GetBestString($FFFF)] = '' then begin
       strvalue[0] := '1';
       PushString(@strvalue[0][1], 1);
      end else PushInt(0);
      PushInt(STACK_TOKEN_SINGLESTRING);
     end else begin
      if numvalue = 0 then PushInt(1) else PushInt(0);
      PushInt(STACK_TOKEN_NUMBER);
     end;
    end;

    TOKEN_NEG: begin
     PopThing;
     if length(strvalue) <> 0 then begin
      ivar := GetBestString($FFFF);
      if strvalue[ivar] = '' then numvalue := 0
      else fibererror('Can''t negate a string: ' + strvalue[ivar]);
     end;
     PushInt(-numvalue);
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_VAR: begin
     // Pop the variable name string.
     PopThing;
     if length(strvalue) = 0 then begin setlength(strvalue, 1); strvalue[0] := strdec(numvalue); end;
     // Check the variable type.
     numvalue2 := GetBestString($FFFF);
     ivar := GetVarType(strvalue[numvalue2]);
     case ivar of
       // Numeric variable. Fetch and push the value.
       1: begin
        PushInt(GetNumVar(strvalue[numvalue2]));
        PushInt(STACK_TOKEN_NUMBER);
       end;
       // String variable. Fetch and push the value.
       2: begin
        GetStrVar(strvalue[numvalue2]);
        for jvar := 0 to length(languagelist) - 1 do
         if length(stringstash[jvar]) <> 0
         then PushString(@stringstash[jvar][1], length(stringstash[jvar]))
         else PushInt(0);
        if length(languagelist) = 1
        then PushInt(STACK_TOKEN_SINGLESTRING)
        else PushInt(STACK_TOKEN_MULTISTRING);
       end;
       // Variable doesn't exist, push empty string.
       else begin
        PushInt(0);
        PushInt(STACK_TOKEN_SINGLESTRING);
       end;
     end;
    end;

    TOKEN_RND: begin
     PopThing;
     if length(strvalue) <> 0 then fibererror('Can''t RND a string: ' + strvalue[GetBestString($FFFF)])
     else begin
      // Getting random negative numbers is dodgy, so special handling.
      if numvalue >= 0 then PushInt(random(numvalue))
      else PushInt(-random(-numvalue));
      PushInt(STACK_TOKEN_NUMBER);
     end;
    end;

    TOKEN_ABS: begin
     PopThing;
     if length(strvalue) <> 0 then fibererror('Can''t ABS a string: ' + strvalue[GetBestString($FFFF)])
     else begin
      PushInt(abs(numvalue));
      PushInt(STACK_TOKEN_NUMBER);
     end;
    end;

    TOKEN_TONUM: begin
     PopThing;
     if length(strvalue) <> 0 then begin
      ivar := GetBestString($FFFF);
      if (strvalue[ivar][1] = '0')
      and (byte(strvalue[ivar][2]) or $20 = byte('x'))
      then numvalue := valhex(copy(strvalue[ivar], 3, length(strvalue[ivar])))
      else numvalue := valx(strvalue[ivar]);
     end;
     PushInt(numvalue);
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_TOSTR: begin
     PopThing;
     if length(strvalue) = 0 then begin setlength(strvalue, 1); strvalue[0] := strdec(numvalue); end;
     ivar := GetBestString($FFFF);
     PushString(@strvalue[ivar][1], length(strvalue[ivar]));
     PushInt(STACK_TOKEN_SINGLESTRING);
    end;

    // Binary operations. Right-hand operand is popped first.
    TOKEN_PLUS: begin
     PopThing;
     numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     // Adding an empty string and a number returns the number.
     if (length(strvalue) = 0) and (length(strvalue2) <> 0)
     and (strvalue2[jvar] = '') then begin
      PushInt(numvalue);
      PushInt(STACK_TOKEN_NUMBER);
     end else
     if (length(strvalue2) = 0) and (length(strvalue) <> 0)
     and (strvalue[GetBestString($FFFF)] = '') then begin
      PushInt(numvalue2);
      PushInt(STACK_TOKEN_NUMBER);
     end else
     if (length(strvalue) = 0) and (length(strvalue2) = 0) then begin
      // Two numbers, add them.
      PushInt(longint(numvalue + numvalue2));
      PushInt(STACK_TOKEN_NUMBER);
     end else begin
      // At least one side is a string, converts numbers to strings.
      if length(strvalue) = 0 then begin setlength(strvalue, 1); strvalue[0] := strdec(numvalue); end else
      if length(strvalue2) = 0 then begin setlength(strvalue2, 1); strvalue2[0] := strdec(numvalue2); end;
      // Make sure both sides have equal number of languages.
      if length(strvalue) <> length(strvalue2) then begin
       ivar := length(languagelist) - length(strvalue);
       if ivar <> 0 then begin
        setlength(strvalue, length(languagelist));
        for jvar := length(strvalue) - ivar to length(strvalue) - 1 do
         strvalue[jvar] := strvalue[0];
       end;
       ivar := length(languagelist) - length(strvalue2);
       if ivar <> 0 then begin
        setlength(strvalue2, length(languagelist));
        for jvar := length(strvalue2) - ivar to length(strvalue2) - 1 do
         strvalue2[jvar] := strvalue2[0];
       end;
      end;
      // Add and push the strings.
      for ivar := 0 to length(strvalue) - 1 do begin
       strvalue[ivar] := strvalue[ivar] + strvalue2[ivar];
       PushString(@strvalue[ivar][1], length(strvalue[ivar]));
      end;
      if length(strvalue) = 1 then PushInt(STACK_TOKEN_SINGLESTRING)
      else PushInt(STACK_TOKEN_MULTISTRING);
     end;
    end;

    TOKEN_MINUS: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     if length(strvalue) <> 0 then begin
      ivar := GetBestString($FFFF);
      if strvalue[ivar] = '' then numvalue := 0
      else fibererror('Can''t subtract from string: ' + strvalue[ivar]);
     end;
     if length(strvalue2) <> 0 then begin
      if strvalue2[jvar] = '' then numvalue2 := 0
      else fibererror('Can''t subtract by a string: ' + strvalue2[jvar]);
     end;
     PushInt(longint(numvalue - numvalue2));
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_MUL: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     if length(strvalue) <> 0 then begin
      ivar := GetBestString($FFFF);
      if strvalue[ivar] = '' then numvalue := 0
      else fibererror('Can''t multiply with string: ' + strvalue[ivar]);
     end;
     if length(strvalue2) <> 0 then begin
      if strvalue2[jvar] = '' then numvalue2 := 0
      else fibererror('Can''t multiply with string: ' + strvalue2[jvar]);
     end;
     PushInt(longint(numvalue * numvalue2));
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_DIV: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     if length(strvalue) <> 0 then begin
      ivar := GetBestString($FFFF);
      if strvalue[ivar] = '' then numvalue := 0
      else fibererror('Can''t divide a string: ' + strvalue[ivar]);
     end;
     if length(strvalue2) <> 0 then begin
      if strvalue2[jvar] = '' then numvalue2 := 0
      else fibererror('Can''t divide by a string: ' + strvalue2[jvar]);
     end;
     PushInt(longint(numvalue div numvalue2));
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_MOD: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     if length(strvalue) <> 0 then begin
      ivar := GetBestString($FFFF);
      if strvalue[ivar] = '' then numvalue := 0
      else fibererror('Can''t modulo a string: ' + strvalue[ivar]);
     end;
     if length(strvalue2) <> 0 then begin
      if strvalue2[jvar] = '' then numvalue2 := 0
      else fibererror('Can''t modulo with a string: ' + strvalue2[jvar]);
     end;
     PushInt(longint(numvalue mod numvalue2));
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_AND: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     if length(strvalue) <> 0 then begin
      ivar := GetBestString($FFFF);
      if strvalue[ivar] = '' then numvalue := 0
      else fibererror('Can''t AND string: ' + strvalue[ivar]);
     end;
     if length(strvalue2) <> 0 then begin
      if strvalue2[jvar] = '' then numvalue2 := 0
      else fibererror('Can''t AND string: ' + strvalue2[jvar]);
     end;
     PushInt(longint(numvalue and numvalue2));
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_OR: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     if length(strvalue) <> 0 then begin
      ivar := GetBestString($FFFF);
      if strvalue[ivar] = '' then numvalue := 0
      else fibererror('Can''t OR string: ' + strvalue[ivar]);
     end;
     if length(strvalue2) <> 0 then begin
      if strvalue2[jvar] = '' then numvalue2 := 0
      else fibererror('Can''t OR string: ' + strvalue2[jvar]);
     end;
     PushInt(longint(numvalue or numvalue2));
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_XOR: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     if length(strvalue) <> 0 then begin
      ivar := GetBestString($FFFF);
      if strvalue[ivar] = '' then numvalue := 0
      else fibererror('Can''t XOR string: ' + strvalue[ivar]);
     end;
     if length(strvalue2) <> 0 then begin
      if strvalue2[jvar] = '' then numvalue2 := 0
      else fibererror('Can''t XOR string: ' + strvalue2[jvar]);
     end;
     PushInt(longint(numvalue xor numvalue2));
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_EQ, TOKEN_LT, TOKEN_GT, TOKEN_LE, TOKEN_GE, TOKEN_NE: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     // Comparing an empty string and a number turns the string into 0.
     if (length(strvalue) = 0) and (length(strvalue2) <> 0)
     and (strvalue2[jvar] = '') then begin
      numvalue2 := 0; setlength(strvalue2, 0);
     end;
     if (length(strvalue2) = 0) and (length(strvalue) <> 0)
     and (strvalue[GetBestString($FFFF)] = '') then begin
      numvalue := 0; setlength(strvalue, 0);
     end;

     ivar := 0;
     if length(strvalue) = 0 then begin
      if length(strvalue2) = 0 then begin
       // Two numbers, compare them.
       case token of
         TOKEN_EQ: if numvalue = numvalue2 then ivar := 1;
         TOKEN_LT: if numvalue < numvalue2 then ivar := 1;
         TOKEN_GT: if numvalue > numvalue2 then ivar := 1;
         TOKEN_LE: if numvalue <= numvalue2 then ivar := 1;
         TOKEN_GE: if numvalue >= numvalue2 then ivar := 1;
         TOKEN_NE: if numvalue <> numvalue2 then ivar := 1;
       end;
      end else begin
       fibererror('Can''t compare number ' + strdec(numvalue) + ' and string ' + strvalue2[jvar]);
      end;
     end else
     if length(strvalue2) <> 0 then begin
      // Two strings, compare them case-insensitively.
      numvalue := GetBestString($FFFF);
      strvalue[numvalue] := upcase(strvalue[numvalue]);
      strvalue2[jvar] := upcase(strvalue2[jvar]);
      case token of
        TOKEN_EQ: if strvalue[numvalue] = strvalue2[jvar] then ivar := 1;
        TOKEN_LT: if strvalue[numvalue] < strvalue2[jvar] then ivar := 1;
        TOKEN_GT: if strvalue[numvalue] > strvalue2[jvar] then ivar := 1;
        TOKEN_LE: if strvalue[numvalue] <= strvalue2[jvar] then ivar := 1;
        TOKEN_GE: if strvalue[numvalue] >= strvalue2[jvar] then ivar := 1;
        TOKEN_NE: if strvalue[numvalue] <> strvalue2[jvar] then ivar := 1;
      end;
     end else
      fibererror('Can''t compare string ' + strvalue[GetBestString($FFFF)] + ' and number ' + strdec(numvalue2));
     PushInt(ivar);
     PushInt(STACK_TOKEN_NUMBER);
    end;

    TOKEN_SET: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     PopThing;
     // Left side must be a variable reference.
     if length(strvalue) = 0 then begin setlength(strvalue, 1); strvalue[0] := strdec(numvalue); end;
     // Set numeric variable.
     if length(strvalue2) = 0 then begin
      SetNumVar(strvalue[GetBestString($FFFF)], numvalue2, FALSE);
     end
     else begin
      // Set a string variable.
      for ivar := 0 to length(strvalue2) - 1 do stringstash[ivar] := strvalue2[ivar];
      while ivar < dword(length(languagelist) - 1) do begin
       inc(ivar);
       stringstash[ivar] := '';
      end;
      SetStrVar(strvalue[GetBestString($FFFF)], FALSE);
     end;
    end;

    TOKEN_INC: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     PopThing;
     // Left side must be a variable reference.
     if length(strvalue) = 0 then begin setlength(strvalue, 1); strvalue[0] := strdec(numvalue); end;
     // Check the variable type.
     jvar := GetBestString($FFFF);
     ivar := GetVarType(strvalue[jvar]);
     case ivar of
       // Numeric variable.
       1: if length(strvalue2) = 0 then begin
        // Increasing a numeric variable by a number.
        SetNumVar(strvalue[jvar], GetNumVar(strvalue[jvar]) + numvalue2, FALSE);
       end else begin
        // Increasing a numeric variable by a string. Nope!
        fibererror('Can''t inc numeric variable $' + strvalue[jvar] + ' by a string');
       end;
       // String variable.
       2: begin
        GetStrVar(strvalue[jvar]);
        if length(strvalue2) = 0 then begin setlength(strvalue2, 1); strvalue2[0] := strdec(numvalue2); end;
        numvalue := 0;
        for ivar := 0 to length(strvalue2) - 1 do begin
         stringstash[ivar] := stringstash[ivar] + strvalue2[ivar];
         if strvalue2[ivar] <> '' then numvalue := ivar;
        end;
        while ivar < dword(length(languagelist) - 1) do begin
         inc(ivar);
         stringstash[ivar] := strvalue2[numvalue];
        end;
        SetStrVar(strvalue[jvar], FALSE);
       end;
       // Non-existing variable, just set without adding.
       else
        if length(strvalue2) = 0 then
         SetNumVar(strvalue[jvar], numvalue2, FALSE)
        else begin
         numvalue := 0;
         for ivar := 0 to length(strvalue2) - 1 do begin
          stringstash[ivar] := strvalue2[ivar];
          if strvalue2[ivar] <> '' then numvalue := ivar;
         end;
         while ivar < dword(length(languagelist) - 1) do begin
          inc(ivar);
          stringstash[ivar] := strvalue2[numvalue];
         end;
         SetStrVar(strvalue[jvar], FALSE);
        end;
     end;
    end;

    TOKEN_DEC: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     // Left side must be a variable reference.
     if length(strvalue) = 0 then begin setlength(strvalue, 1); strvalue[0] := strdec(numvalue); end;
     // Right side must be a number.
     if length(strvalue2) <> 0 then fibererror('Can''t decrease by string: ' + strvalue2[jvar])
     else begin
      // Check the variable type.
      jvar := GetBestString($FFFF);
      ivar := GetVarType(strvalue[jvar]);
      if ivar = 2 then fibererror('Can''t decrease a string variable: ' + strvalue[jvar])
      // Numeric or non-existing variable which counts as zero.
      else SetNumVar(strvalue[jvar], GetNumVar(strvalue[jvar]) - numvalue2, FALSE);
     end;
    end;

    TOKEN_SHL: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     if length(strvalue) <> 0 then fibererror('Can''t SHL string: ' + strvalue[GetBestString($FFFF)])
     else if length(strvalue2) <> 0 then fibererror('Can''t SHL string: ' + strvalue2[jvar])
     else begin
      PushInt(longint(numvalue shl numvalue2));
      PushInt(STACK_TOKEN_NUMBER);
     end;
    end;

    TOKEN_SHR: begin
     PopThing; numvalue2 := numvalue; StashStrval;
     jvar := GetBestString($FFFF);
     PopThing;
     if length(strvalue) <> 0 then fibererror('Can''t SHR string: ' + strvalue[GetBestString($FFFF)])
     else if length(strvalue2) <> 0 then fibererror('Can''t SHR string: ' + strvalue2[jvar])
     else begin
      PushInt(longint(numvalue shr numvalue2));
      PushInt(STACK_TOKEN_NUMBER);
     end;
    end;

    // Unconditional jump.
    TOKEN_JUMP: begin
     longint(ivar) := longint(codeofs) + longint((script[labelindex].code + codeofs)^);
     if longint(ivar) < 0 then fibererror('Sub-zero jump')
     else if ivar > script[labelindex].codesize then fibererror('Jump out of bounds')
     else codeofs := ivar;
    end;

    // Conditional jump.
    TOKEN_IF: begin
     PopThing;
     if (length(strvalue) <> 0) and (strvalue[GetBestString($FFFF)] = '')
     or (length(strvalue) = 0) and (numvalue = 0) then begin
      // Condition false, get relative offset and jump past the then-segment.
      longint(ivar) := longint(codeofs) + longint((script[labelindex].code + codeofs)^);
      if longint(ivar) < 0 then fibererror('Sub-zero if-jump')
      else if ivar > script[labelindex].codesize then fibererror('If-jump out of bounds')
      else codeofs := ivar;
     end else
      // Condition true, ignore offset, fall into then-segment.
      inc(codeofs, 4);
    end;

    // React to the previous choice wop.
    TOKEN_CHOICEREACT: begin
     token := char((script[labelindex].code + codeofs - 2)^);
     if byte(token) = WOP_CHOICE_GET then begin
      PushInt(choicematic.previouschoiceindex);
      PushInt(STACK_TOKEN_NUMBER);
     end else with choicematic do begin
      if previouschoiceindex >= dword(length(choicelist)) then fibererror('react: choice out of bounds')
      else begin
       ivar := 0;
       if choicelist[previouschoiceindex].trackvar <> '' then
        ivar := GetNumVar(choicelist[previouschoiceindex].trackvar);
       ScriptCase(fiberid, choicelist[previouschoiceindex].jumplist, ivar, byte(token) = WOP_CHOICE_CALL);
      end;
     end;
    end;

    // Word of power parameters.
    TOKEN_WOPEND: PushInt(STACK_TOKEN_ENDPARAMS);

    TOKEN_DYNPARAM: PushInt(STACK_TOKEN_PARAM);

    TOKEN_PARAM: begin
     PushInt(STACK_TOKEN_PARAM + byte((script[labelindex].code + codeofs)^));
     inc(codeofs);
    end;

    // Words of power.
    TOKEN_WOP: begin
     ivar := byte((script[labelindex].code + codeofs)^); inc(codeofs);
     ConsumeParams;
     InvokeWordOfPower(ivar);
    end;

    // Unrecognised token.
    else begin
     fibererror('Invalid script token: ' + strdec(byte(token))); exit;
    end;
  end;
 end; until yieldnow;
end;

procedure RunFibers;
// Forwards all active fibers to execute code, cleans up stopped fibers.
var fiberid, ivar : dword;
begin
 fiberid := 0;
 while fiberid < fibercount do begin

  // Active fibers
  if fiber[fiberid].fiberstate = FIBERSTATE_NORMAL
  then ExecuteFiber(fiberid, pausestate = PAUSESTATE_SINGLE);

  // Stopping fibers
  if fiber[fiberid].fiberstate = FIBERSTATE_STOPPING
  then begin
   if fiber[fiberid].fibername <> chr(0)
    then log('Stopping fiber ' + fiber[fiberid].fibername);
   // Stop this fiber's effects, shift above fibers' effects down a notch.
   if fxcount <> 0 then for ivar := fxcount - 1 downto 0 do begin
    if fx[ivar].fxfiber = longint(fiberid) then DeleteFx(ivar)
    else if fx[ivar].fxfiber > longint(fiberid) then dec(fx[ivar].fxfiber);
   end;
   // Move above fibers down a notch.
   ivar := fiberid + 1;
   while ivar < fibercount do begin
    fiber[ivar - 1] := fiber[ivar];
    inc(ivar);
   end;
   dec(fibercount);
   continue;
  end;

  inc(fiberid);
 end;
end;
