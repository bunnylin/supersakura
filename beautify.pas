program Beautify;
{                                                                           }
{ Bunnylin's Brilliant Beautifier, work in progress                         }
{ Copyright 2009-2017 :: Kirinn Bunnylin / Mooncore                         }
{ https://mooncore.eu/ssakura                                               }
{ https://github.com/something                                              }
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
{ ------------------------------------------------------------------------- }
{                                                                           }
{ Targets FPC 3.0.2 for Win32.                                              }
{                                                                           }
{ Compilation dependencies:                                                 }
{ - Various moonlibs                                                        }
{   https://github.com/something                                            }
{                                                                           }

// This program takes 8-bit PNGs, attempts to beautify them using a reverse-
// dithering algorithm, and saves the full-color result. The algorithm is too
// heavy for realtime use, and results in a smattering of artifacts that
// still need to be cleaned by hand.
{$apptype console}
{$asmmode intel}
{$I-}
{$resource beautify.res}

uses windows, commdlg, mcgloder, mccommon;

type RGBtriplet = packed record
      b, g, r : byte;
     end;
     RGBarray = array[0..$FFFFFF] of RGBtriplet;

const mv_ProgramName : string[11] = 'Beautifier' + chr(0);
      mainclass : string[9] = 'BTFMAINC' + chr(0);
      viewclass : string[9] = 'BTFVIEWC' + chr(0);
      PBS_SMOOTH : longint = 1; // win32 progress bar, smooth style

var i, j : dword;
    mainsizex, mainsizey, helpsizey : word;
    lastactiveview : byte;
    // View 0 - 8-bit source
    // View 1 - flags render
    // View 2 - result image after reverse-dither with user commands applied
    // View 3 - post-processed image, saved as diff from view 2
    viewdata : array[0..3] of packed record
     bmpdata : bitmaptype;
     winsizex, winsizey : word;
     viewofsx, viewofsy : integer;
     buffy : pointer;
     winhandu : hwnd;
     deeku : hdc;
     buffyh, oldbuffyh : hbitmap;
     zoom, alpha : byte;
    end;
    acolor : RGBquad; // the alpha-rendering color

    mv_AMessage : msg;
    mv_MainWinH : handle;
    mv_DC : hdc;
    mv_Contextmenu : hmenu;
    mv_FontH, mv_TabWinH : array[1..2] of handle;
    mv_ButtonH : array[0..7] of handle;
    mv_StaticH : array[0..24] of handle;
    mv_SliderH : array[1..6] of handle;
    mv_ListH : array[1..2] of handle;
    mv_ProgressH, mv_AcceleratorTable, mv_TabH : handle;
    bminfo : bitmapinfo;
    mousescrollx, mousescrolly : integer;
    mousescrolling : boolean;
    mv_EndProgram : boolean;
    mv_Dlg : packed record // hacky thing for spawning dialog boxes
              headr : DLGTEMPLATE;
              data : array[0..31] of byte;
             end;
    OldTabProc : WNDPROC;

    newimu : pointer;
    //postprocess : procedure(px, py : word);
    blurindex : dword;
    blurlist : pointer;

// Dipa is a numerical description of the most common 16-step dithering
// pattern used in the source material.
const dipa : array[0..15] of byte = (
0, 10, 2, 8, 5, 15, 7, 13, 4, 14, 6, 12, 1, 11, 3, 9);
// Disttable is a pre-calculated table of distances from origin for stuff
// like a Gaussian blur.
      disttable : array[0..6,0..6] of byte = ( // r 2 = 1/24  R 3 = 1/35
(34,29,25,24,25,29,34),
(29,23,18,16,18,23,29),
(25,18,11,08,11,18,25),
(24,16,08,00,08,16,24),
(25,18,11,08,11,18,25),
(29,23,18,16,18,23,29),
(34,29,25,24,25,29,34));

// ------------------------------------------------------------------

function hexifycolor(inco : RGBquad) : string;
// A macro for turning a color into a six-hex piece of text.
begin
 hexifycolor[0] := chr(6);
 hexifycolor[1] := hextable[inco.r shr 4];
 hexifycolor[2] := hextable[inco.r and $F];
 hexifycolor[3] := hextable[inco.g shr 4];
 hexifycolor[4] := hextable[inco.g and $F];
 hexifycolor[5] := hextable[inco.b shr 4];
 hexifycolor[6] := hextable[inco.b and $F];
end;

// ==================================================================

function errortxt(ernum : byte) : string;
begin
 case ernum of
  // FPC errors
  2: errortxt := 'File not found';
  3: errortxt := 'Path not found';
  5: errortxt := 'Access denied';
  6: errortxt := 'File handle variable trashed, memory corrupted!!';
  100: errortxt := 'Disk read error';
  101: errortxt := 'Disk write error, disk full?';
  103: errortxt := 'File not open';
  200: errortxt := 'Div by zero!!';
  201: errortxt := 'Range check error';
  203: errortxt := 'Heap overflow - not enough memory, possibly corrupted resource size?';
  204: errortxt := 'Invalid pointer operation';
  207: errortxt := 'Floating point fail';
  215: errortxt := 'Arithmetic overflow';
  216: errortxt := 'General protection fault';
  // BCC errors
  99: errortxt := 'CreateWindow failed!';
  98: errortxt := 'RegisterClass failed, while trying to create a window.';
  88: errortxt := 'Trying to render incorrect image type.';
  89: errortxt := 'Trying to pack incorrect image type.';
  else errortxt := 'Unlisted error';
 end;
 errortxt := strdec(ernum) + ': ' + errortxt;
end;

procedure BeautyExit;
// Procedure called automatically on program exit.
var ert : string;
    ivar : dword;
begin
 mv_EndProgram := TRUE;

 // Destroy the views
 for ivar := 0 to high(viewdata) do begin
  mcg_ForgetImage(@viewdata[ivar].bmpdata);
  if viewdata[ivar].winhandu <> 0 then DestroyWindow(viewdata[ivar].winhandu);
  viewdata[ivar].winhandu := 0;
  if viewdata[ivar].BuffyH <> 0 then begin
   SelectObject(viewdata[ivar].deeku, viewdata[ivar].OldBuffyH);
   DeleteDC(viewdata[ivar].deeku);
   DeleteObject(viewdata[ivar].BuffyH);
   viewdata[ivar].buffyh := 0;
  end;
 end;
 // Destroy the main window
 if mv_MainWinH <> 0 then DestroyWindow(mv_MainWinH);
 // this also destroys all its child windows and controls

 // Destroy everything else
 if mv_ContextMenu <> 0 then DestroyMenu(mv_ContextMenu);
 // mv_AcceleratorTable is automatically released on program termination

 // Release fonts
 if mv_FontH[1] <> 0 then deleteObject(mv_FontH[1]);
 if mv_FontH[2] <> 0 then deleteObject(mv_FontH[2]);

 // Print out the error message if exiting unnaturally
 if (erroraddr <> NIL) or (exitcode <> 0) then begin
  ert := errortxt(exitcode) + chr(0);
  MessageBoxA(0, @ert[1], NIL, MB_OK);
 end;
end;

procedure ProgressCallback(percent : byte);
begin
end;

{$include inc/b_revdit.pas}

// ==================================================================
// View processing functions

// ==================================================================
// View IO functions

procedure PackView(winpo : byte; bytealign : byte; whither : pbitmaptype);
// Takes a view and checks if the number of colors is 256 or less. In that
// case, creates an indexed-color image, otherwise returns the RGB or RGBA
// image straight from the view. The returned image has its scanlines padded
// to BYTE or DWORD -alignment, defined by the bytealign variable. The
// procedure returns the new image as a non-standard bitmap type, which the
// caller must free when finished. (Don't try to feed it to my other
// functions that accept bitmaptypes, they only accept byte-aligned images;
// this one also puts the byte width, not pixel width, in .sizex)
var xvar, yvar, dibwidth : word;
    zvar, svar : dword;
    pvar : longint;
    tempcolor : RGBquad;
begin
 if (winpo > high(viewdata)) or (viewdata[winpo].bmpdata.image = NIL) then exit;
 mcg_ForgetImage(whither);
 if bytealign = 0 then inc(bytealign);

 // 256 or less colors, index em
 if length(viewdata[winpo].bmpdata.palette) <= 256 then with viewdata[winpo] do begin
  // store the palette
  setlength(whither^.palette, length(bmpdata.palette));
  move(bmpdata.palette[0], whither^.palette[0], length(bmpdata.palette) * 4);
  // decide which bitdepth to pack into
  case length(bmpdata.palette) of
   0..2: whither^.bitdepth := 1;
   3..4: if bytealign = 1 then whither^.bitdepth := 2
         // v4 DIBs are DWORD -aligned, and don't support 2 bpp.
         else whither^.bitdepth := 4;
   5..16: whither^.bitdepth := 4;
   17..256: whither^.bitdepth := 8;
  end;
  // calculate various descriptive numbers
  dec(bytealign);
  whither^.sizex := (((bmpdata.sizex * whither^.bitdepth + 7) shr 3) + bytealign) and ($FFFFFFFF - bytealign);
  whither^.sizey := bmpdata.sizey;
  whither^.memformat := 4 + (alpha - 3);
  // match each pixel to the palette, store the indexes as the new image
  // svar is the source offset, zvar is the 29.3 fixed point target offset
  zvar := 0; svar := 0;
  case bmpdata.memformat of
   0: begin // 24-bit RGB source
       getmem(whither^.image, whither^.sizex * bmpdata.sizey);
       for yvar := bmpdata.sizey - 1 downto 0 do begin
        for xvar := bmpdata.sizex - 1 downto 0 do begin
         move(RGBarray(bmpdata.image^)[svar], tempcolor.b, 3);
         tempcolor.a := $FF;
         pvar := mcg_MatchColorInPal(tempcolor, whither);
         byte((whither^.image + zvar shr 3)^) := byte( byte((whither^.image + zvar shr 3)^) shl whither^.bitdepth ) or pvar;
         inc(svar); inc(zvar, whither^.bitdepth);
        end;
        zvar := (zvar + 7) and $FFFFFFF8;
        zvar := (((zvar shr 3) + bytealign) and ($FFFFFFFF - bytealign)) shl 3;
       end;
      end;
   1: begin // 32-bit RGBA source
       getmem(whither^.image, whither^.sizex * bmpdata.sizey);
       for yvar := bmpdata.sizey - 1 downto 0 do begin
        for xvar := bmpdata.sizex - 1 downto 0 do begin
         pvar := mcg_MatchColorInPal(RGBAarray(bmpdata.image^)[svar], whither);
         byte((whither^.image + zvar shr 3)^) := byte( (byte((whither^.image + zvar shr 3)^) shl whither^.bitdepth) or pvar );
         inc(svar); inc(zvar, whither^.bitdepth);
        end;
        zvar := (zvar + 7) and $FFFFFFF8;
        zvar := (((zvar shr 3) + bytealign) and ($FFFFFFFF - bytealign)) shl 3;
       end;
      end;
   4,5: // indexed source
      begin
       dibwidth := (((bmpdata.sizex shl 3 + 7) shr 3) + bytealign) and ($FFFFFFFF - bytealign);
       getmem(whither^.image, dibwidth * bmpdata.sizey);
       whither^.sizex := dibwidth;
       whither^.sizey := bmpdata.sizey;
       whither^.memformat := bmpdata.memformat;
       whither^.bitdepth := 8;
       for yvar := 0 to bmpdata.sizey - 1 do
        move((bmpdata.image + yvar * bmpdata.sizex)^, (whither^.image + yvar * dibwidth)^, bmpdata.sizex);
      end;
   else halt(89);
  end;

 end

 // More than 256 colors
 else with viewdata[winpo] do begin
  dec(bytealign);
  dibwidth := ((bmpdata.sizex * alpha) + bytealign) and ($FFFFFFFF - bytealign);
  getmem(whither^.image, dibwidth * bmpdata.sizey);
  whither^.sizex := dibwidth;
  whither^.sizey := bmpdata.sizey;
  whither^.memformat := (alpha - 3); // RGB = 0, RGBA = 1
  whither^.bitdepth := alpha * 8;
  for yvar := 0 to bmpdata.sizey - 1 do
   move((bmpdata.image + yvar * bmpdata.sizex * alpha)^, (whither^.image + yvar * dibwidth)^, bmpdata.sizex * alpha);
 end;

end;

procedure SaveViewAsPNG(winpo : byte);
// Pops up a Save As dialog, then saves the image from
// viewdata[winpo].bmpdata into a PNG file using the given name.
var newimu : bitmaptype;
    openfilurec : openfilename;
    kind, txt : string;
    filu : file;
    ivar, jvar : dword;
    pingustream : pointer;
begin
 if (winpo > high(viewdata)) or (viewdata[winpo].bmpdata.image = NIL) then exit;
 kind := 'PNG image file' + chr(0) + '*.png' + chr(0) + chr(0);
 txt := chr(0);
 fillbyte(openfilurec, sizeof(openfilurec), 0);
 with openfilurec do begin
  lStructSize := 76; // sizeof gives incorrect result?
  hwndOwner := viewdata[winpo].winhandu;
  lpstrFilter := @kind[1]; lpstrCustomFilter := NIL;
  nFilterIndex := 1;
  lpstrFile := @txt[1]; nMaxFile := 255;
  lpstrFileTitle := NIL; lpstrInitialDir := NIL; lpstrTitle := NIL;
  Flags := OFN_OVERWRITEPROMPT or OFN_PATHMUSTEXIST;
 end;
 if GetSaveFileNameA(@openfilurec) = FALSE then exit;

 // We have the filename, so prepare the file
 txt := openfilurec.lpstrfile;
 if upcase(copy(txt, length(txt) - 3, 4)) <> '.PNG' then txt := txt + '.png';
 assign(filu, txt);
 filemode := 1; rewrite(filu, 1); // write-only
 ivar := IOresult;
 if ivar <> 0 then begin
  txt := errortxt(ivar) + chr(0);
  MessageBoxA(viewdata[winpo].winhandu, @txt[1], NIL, MB_OK); exit;
 end;

 // Squash the image into the smallest uncompressed space possible
 fillbyte(newimu, sizeof(newimu), 0);
 PackView(winpo, 1, @newimu);
 newimu.sizex := viewdata[winpo].bmpdata.sizex; // use pixel, not byte width

 // Render the image into a compressed PNG
 pingustream := NIL;
 ivar := mcg_MemorytoPNG(@newimu, @pingustream, @jvar);
 if ivar <> 0 then begin
  mcg_ForgetImage(@newimu);
  txt := mcg_errortxt + chr(0);
  MessageBoxA(viewdata[winpo].winhandu, @txt[1], NIL, MB_OK); exit;
 end;

 // Write the PNG datastream into the file
 blockwrite(filu, pingustream^, jvar);
 ivar := IOresult;
 if ivar <> 0 then begin
  txt := errortxt(ivar) + chr(0);
  MessageBoxA(viewdata[winpo].winhandu, @txt[1], NIL, MB_OK);
 end;

 // Clean up
 mcg_ForgetImage(@newimu); close(filu);
 freemem(pingustream); pingustream := NIL;
end;

procedure CopyView(winpo : byte);
// Tries to place the image in viewdata[winpo] on the clipboard.
var workhand : hglobal;
    tonne : pointer;
    txt : string;
    hedari : bitmapv4header;
    newimu : bitmaptype;
    ofsu, ofx : dword;
begin
 if (winpo > high(viewdata)) or (viewdata[winpo].bmpdata.image = NIL) then exit;
 fillbyte(newimu, sizeof(newimu), 0);
 PackView(winpo, 4, @newimu);
 fillbyte(hedari, sizeof(hedari), 0);
 with hedari do begin // not all programs know what v4DIBs are
  bv4Size := sizeof(bitmapinfoheader); // so use lowest common denominator
  bv4Width := viewdata[winpo].bmpdata.sizex;
  bv4Height := viewdata[winpo].bmpdata.sizey;
  bv4BitCount := newimu.bitdepth;
  bv4v4Compression := BI_RGB; bv4SizeImage := newimu.sizex * newimu.sizey;
  bv4XPelsPerMeter := $AF0; bv4YPelsPerMeter := $AF0; bv4ClrImportant := 0;
  if newimu.memformat < 2 then bv4ClrUsed := 0 else bv4ClrUsed := length(newimu.palette);
  bv4RedMask := $FF0000; bv4GreenMask := $FF00;
  bv4BlueMask := $FF; bv4AlphaMask := $FF000000;
  bv4Planes := 1; bv4CSType := 0;
 end;

 if OpenClipboard(viewdata[winpo].winhandu) = FALSE then begin
  txt := 'Could not open clipboard.' + chr(0);
  MessageBoxA(viewdata[winpo].winhandu, @txt[1], NIL, MB_OK);
 end else begin
  EmptyClipboard;
  // Allocate a system-wide memory chunk
  workhand := GlobalAlloc(GMEM_MOVEABLE, hedari.bv4Size + hedari.bv4ClrUsed * 4 + newimu.sizex * newimu.sizey);
  if workhand = 0 then begin
   txt := 'Could not allocate global memory.' + chr(0);
   MessageBoxA(viewdata[winpo].winhandu, @txt[1], NIL, MB_OK);
  end else begin
   // Stuff the memory chunk with goodies!
   tonne := GlobalLock(workhand);
   // first up: the bitmapinfoheader
   move((@hedari)^, tonne^, hedari.bv4Size);
   inc(tonne, hedari.bv4Size);
   // next up: the palette, if applicable
   if hedari.bv4ClrUsed <> 0 then begin
    move(newimu.palette[0], tonne^, hedari.bv4ClrUsed * 4);
    inc(tonne, hedari.bv4ClrUsed * 4);
   end;

   // last up: the image itself! Must be bottom-up, top-down doesn't seem to
   // work on the 9x clipboard
   if newimu.memformat = 1 then begin
    // 32-bit ABGR, must be converted to Windows' preferred BGRA
    ofsu := (newimu.sizex shr 2) * (hedari.bv4Height - 1);
    while ofsu <> 0 do begin
     for ofx := 0 to (newimu.sizex shr 2) - 1 do begin
      dword(tonne^) := dword((newimu.image + ofsu * 4)^);
      //dword(tonne^) := (dword(tonne^) shr 8) or (dword(tonne^) shl 24);
      inc(tonne, 4); inc(ofsu);
     end;
     dec(ofsu, (newimu.sizex shr 2) * 2);
    end;
   end
   else begin
    // any other than 32-bit RGBA
    ofsu := hedari.bv4SizeImage;
    while ofsu > 0 do begin
     dec(ofsu, newimu.sizex);
     move((newimu.image + ofsu)^, tonne^, newimu.sizex);
     inc(tonne, newimu.sizex);
    end;
   end;

   tonne := NIL;
   GlobalUnlock(workhand);
   if SetClipBoardData(CF_DIB, workhand) = 0 then begin
    txt := 'Could not place data on the clipboard.' + chr(0);
    MessageBoxA(viewdata[winpo].winhandu, @txt[1], NIL, MB_OK);
    GlobalFree(workhand);
   end;
  end;
  // Clean up
  CloseClipboard;
 end;
 mcg_ForgetImage(@newimu);
end;

procedure MakeHistogram(pimu : pbitmaptype);
// Fills the pimu^.palette array with a series of RGBA dwords, one for each
// unique color present in the image. Uses dynamic array hashing.
var iofs, hvar, ivar, jvar, gramsize : dword;
    hash : array[0..4095] of array of dword;
    bucketitems : array[0..4095] of dword;
    bitmask : dword;
    bpp : byte;
    existence : boolean;
begin
 if (pimu = NIL) or (pimu^.image = NIL)
 // If a palette already exists, this proc will not recalculate it. If you
 // want to force a recalculation, SetLength(*.palette, 0) first.
 // Monochrome images should be RGB at this point, and indexed images have to
 // have a palette ready to start with, so we only accept RGB or RGBA images.
 or (length(pimu^.palette) <> 0) or (pimu^.memformat > 1) then exit;

 gramsize := 0;
 filldword(bucketitems, 4096, 0);

 // Each 32-bit color (24-bit images are read as 32-bit) is read into HVAR,
 // then reduced to a 12-bit ID tag, placed in JVAR. There are 4096 hashing
 // buckets, and each has a dynamic array list of the actual 32-bit colors
 // encountered whose ID tag pointed to that bucket. Doing this means that
 // checking for whether a particular color is already added to the list only
 // requires up to a few dozen comparisons in its bucket's list.

 bpp := 3 + pimu^.memformat; // RGB = 3, RGBA = 4
 bitmask := 0; if pimu^.memformat = 0 then bitmask := $FF000000;
 iofs := pimu^.sizex * pimu^.sizey * bpp;
 while iofs <> 0 do begin
  dec(iofs, bpp);
  hvar := dword((pimu^.image + iofs)^) or bitmask;
  jvar := (hvar and $FFF) xor (hvar shr 12);
  jvar := (jvar xor (jvar shr 12)) and $FFF;
  if bucketitems[jvar] = 0 then begin // empty bucket? allocate space
   setlength(hash[jvar], 64);
   bucketitems[jvar] := 1;
   hash[jvar][0] := hvar;
   inc(gramsize);
  end else begin // non-empty bucket; check for a match among listed colors
   existence := FALSE;
   ivar := bucketitems[jvar];
   while (ivar <> 0) and (existence = FALSE) do begin
    dec(ivar);
    if hash[jvar][ivar] = hvar then existence := TRUE;
   end;
   if existence = FALSE then begin // no match exists! add new to bucket
    if bucketitems[jvar] = length(hash[jvar]) then setlength(hash[jvar], length(hash[jvar]) + 64);
    hash[jvar][bucketitems[jvar]] := hvar;
    inc(bucketitems[jvar]);
    inc(gramsize);
   end;
  end;
 end;

 // Shift the color list into viewdata:
 // Go through all 4096 buckets, and sequentially dump the color list array
 // contents from each into the palettegram.
 setlength(pimu^.palette, gramsize);
 iofs := 4096; hvar := 0;
 while iofs <> 0 do begin
  dec(iofs);
  if bucketitems[iofs] <> 0 then begin
   for ivar := 0 to bucketitems[iofs] - 1 do begin
    dword(pimu^.palette[hvar]) := hash[iofs][ivar];
    inc(hvar);
   end;
  end;
 end;
end;

procedure RedrawView(sr : byte);
// Renders the raw bitmap into a buffer that the system can display.
var sofs, dofs : dword;
    aval, avalx : byte;
begin
 if (sr >= length(viewdata)) or (viewdata[sr].bmpdata.image = NIL) then exit;

 with viewdata[sr] do begin
  // The DIBitmap that is designated as our output buffer must have rows that
  // have a length in bytes divisible by 4. Happily, it is a 32-bit RGBx DIB
  // so this is not a problem.

  sofs := bmpdata.sizex * bmpdata.sizey;
  case bmpdata.memformat of
   0: begin // 24-bit RGB rendering
       dofs := sofs * 4;
       sofs := sofs * 3;
       while sofs <> 0 do begin
        dec(dofs, 4); dec(sofs, 3);
        dword((buffy + dofs)^) := dword((bmpdata.image + sofs)^);
        byte((buffy + dofs + 3)^) := 0; // alpha, zeroed
       end;
      end;
   1: begin // 32-bit RGBA rendering
       sofs := sofs * 4;
       while sofs <> 0 do begin
        dec(sofs, 4);
        dofs := dword((bmpdata.image + sofs)^);
        aval := byte(dofs shr 24);
        avalx := aval xor $FF;
        byte((buffy + sofs    )^) := (byte(dofs       ) * aval + acolor.b * avalx) div 255;
        byte((buffy + sofs + 1)^) := (byte(dofs shr  8) * aval + acolor.g * avalx) div 255;
        byte((buffy + sofs + 2)^) := (byte(dofs shr 16) * aval + acolor.r * avalx) div 255;
        byte((buffy + sofs + 3)^) := aval;
       end;
      end;
   4: begin
       // Indexed rendering, ignoring alpha
       dofs := sofs * 4;
       while sofs <> 0 do begin
        dec(sofs); dec(dofs, 4);
        dword((buffy + dofs)^) := dword(bmpdata.palette[byte((bmpdata.image + sofs)^)]);
        byte((buffy + dofs + 3)^) := 0; // alpha, zeroed
       end;
      end;
   5: begin
       // Indexed rendering, handling alpha
       dofs := sofs * 4;
       while sofs <> 0 do begin
        dec(sofs);
        aval := byte((bmpdata.image + sofs)^);
        avalx := bmpdata.palette[aval].a xor $FF;
        dec(dofs);
        byte((buffy + dofs)^) := avalx;
        dec(dofs);
        byte((buffy + dofs)^) := (bmpdata.palette[aval].r * bmpdata.palette[aval].a + acolor.r * avalx) div 255;
        dec(dofs);
        byte((buffy + dofs)^) := (bmpdata.palette[aval].g * bmpdata.palette[aval].a + acolor.g * avalx) div 255;
        dec(dofs);
        byte((buffy + dofs)^) := (bmpdata.palette[aval].b * bmpdata.palette[aval].a + acolor.b * avalx) div 255;
       end;
      end;
   else halt(88);
  end;
  invalidaterect(winhandu, NIL, TRUE);
 end;
end;

// If a view has been closed, a new window needs to be generated using this.
procedure SpawnViewWindow(sr : byte); forward;

function SpawnView(sr : byte; imu : pbitmaptype) : boolean;
// Places the given bitmap in viewdata[sr] so it is displayed to the user.
// viewdata[sr] can be uninitialised.
// viewdata[sr].sizexy will be the window client area's dimensions.
// viewdata[sr].bmpdata.sizexy will be the bitmap's real pixel dimensions.
// The bitmaptype record imu^ will be copied to viewdata[sr].bmpdata, and the
// original will be wiped out.
// Returns TRUE if successful.
var erm : string;
    rr : rect;
    col : RGBquad;
    ivar : dword;
begin
 SpawnView := FALSE;
 if (imu = NIL) or (imu^.image = NIL) then exit;
 if sr >= length(viewdata) then sr := 0;

 // Monochrome images need expanding
 if imu^.memformat in [2,3] then mcg_ExpandIndexed(imu);
 // Check how many colors the image really has
 MakeHistogram(imu);
 // Source image must be indexable in 8 bits, so at max 256 colors
 if (sr = 0) and (length(imu^.palette) > 256) then begin
  erm := 'Only up to 256 colors allowed! This image has ' + strdec(length(imu^.palette)) + ' colors.' + chr(0);
  MessageBoxA(mv_MainWinH, @erm[1], NIL, MB_OK);
  mcg_ForgetImage(imu);
  exit;
 end;
 // Shrink source to an 8-bit image
 if (sr = 0) and (imu^.memformat < 2) then begin
  if imu^.memformat = 0 then begin
   for ivar := 0 to imu^.sizex * imu^.sizey - 1 do begin
    dword(col) := dword((imu^.image + ivar * 3)^);
    col.a := $FF;
    byte((imu^.image + ivar)^) := mcg_MatchColorInPal(col, imu);
   end;
  end else begin
   for ivar := 0 to imu^.sizex * imu^.sizey - 1 do
    byte((imu^.image + ivar)^) := mcg_MatchColorInPal(RGBquad((imu^.image + ivar shl 2)^), imu);
  end;
  reallocmem(imu^.image, imu^.sizex * imu^.sizey);
  imu^.memformat := 4 + imu^.memformat and 1; // switch to indexed
 end;

 if viewdata[sr].winhandu = 0 then SpawnViewWindow(sr);

 // Clean up any existing bitmap in this view
 if viewdata[sr].BuffyH <> 0 then begin
  SelectObject(viewdata[sr].deeku, viewdata[sr].OldBuffyH);
  DeleteDC(viewdata[sr].deeku);
  DeleteObject(viewdata[sr].BuffyH);
  viewdata[sr].buffyh := 0;
 end;
 mcg_ForgetImage(@viewdata[sr].bmpdata);

 // Shift imu^ into viewdata[].bmpdata^
 viewdata[sr].alpha := 3 + (imu^.memformat and 1);
 with viewdata[sr] do begin
  zoom := 1; viewofsx := 0; viewofsy := 0;
  bmpdata := imu^;
  setlength(bmpdata.palette, length(imu^.palette));
  if length(imu^.palette) <> 0 then
   move(imu^.palette[0], bmpdata.palette[0], length(imu^.palette) * 4);
  imu^.image := NIL;
  mcg_ForgetImage(imu);
 end;

 with bminfo.bmiheader do begin
  bisize := sizeof(bminfo.bmiheader);
  biwidth := viewdata[sr].bmpdata.sizex;
  biheight := -viewdata[sr].bmpdata.sizey;
  bisizeimage := 0; biplanes := 1;
  bibitcount := 32; bicompression := bi_RGB;
  biclrused := 0; biclrimportant := 0;
  bixpelspermeter := 28000; biypelspermeter := 28000;
 end;
 dword(bminfo.bmicolors) := 0;
 mv_DC := getDC(viewdata[sr].winhandu);
 viewdata[sr].deeku := createCompatibleDC(mv_DC);
 ReleaseDC(viewdata[sr].winhandu, mv_DC);
 viewdata[sr].BuffyH := createDIBsection(viewdata[sr].deeku, bminfo, dib_rgb_colors, viewdata[sr].buffy, 0, 0);
 viewdata[sr].OldBuffyH := selectObject(viewdata[sr].deeku, viewdata[sr].BuffyH);

 RedrawView(sr);

 // Resize the window to accommodate the loaded image
 rr.left := 0; rr.top := 0;
 rr.right := GetSystemMetrics(SM_CXMAXIMIZED) - GetSystemMetrics(SM_CXFRAME) * 4;
 rr.bottom := GetSystemMetrics(SM_CYMAXIMIZED) - GetSystemMetrics(SM_CYFRAME) * 4 - GetSystemMetrics(SM_CYCAPTION);
 if viewdata[sr].bmpdata.sizex < rr.right then rr.right := viewdata[sr].bmpdata.sizex;
 if viewdata[sr].bmpdata.sizey < rr.bottom then rr.bottom := viewdata[sr].bmpdata.sizey;
 adjustWindowRectEx(@rr, WS_CAPTION or WS_THICKFRAME, FALSE, WS_EX_TOOLWINDOW);
 rr.right := rr.right - rr.left;
 rr.bottom := rr.bottom - rr.top;
 SetWindowPos(viewdata[sr].winhandu, 0,0,0, rr.right, rr.bottom, SWP_NOMOVE or SWP_NOZORDER);
 SpawnView := TRUE;
end;

procedure GrabUIParams;
// Reads the user's reverse dithering settings from the user interface.
// Do this before calling the Beautify procedure.
begin
 rd_param.lightness := GetScrollPos(mv_SliderH[1], SB_CTL);
 rd_param.chroma := GetScrollPos(mv_SliderH[2], SB_CTL);
 rd_param.temperature := GetScrollPos(mv_SliderH[3], SB_CTL) * 2 + 6;
 rd_param.RDthres := GetScrollPos(mv_SliderH[4], SB_CTL);
 rd_param.EPBthres := GetScrollPos(mv_SliderH[5], SB_CTL);
 rd_param.SEBthres := GetScrollPos(mv_SliderH[6], SB_CTL);
 rd_param.addspritealpha := SendMessage(mv_ButtonH[1], BM_GETCHECK, 0, 0) = BST_CHECKED;
 rd_param.processHVlines := SendMessage(mv_ButtonH[2], BM_GETCHECK, 0, 0) = BST_CHECKED;
 rd_param.checkerboardonly := SendMessage(mv_ButtonH[3], BM_GETCHECK, 0, 0) = BST_CHECKED;
end;

// ==================================================================
// Windows functions

function ViewProc (window : hwnd; amex : uint; wepu : wparam; lapu : lparam) : lresult; stdcall;
// Handles win32 messages for the source and result view windows.
var mv_PS : paintstruct;
    rrs, rrd : rect;
    pico : RGBquad;
    kind : string[40];
    winpo : byte;
begin
 // Specify the view window this message is intended for
 winpo := GetWindowLong(window, GWL_USERDATA);

 case amex of
  // Copy stuff to screen from our own buffer
  wm_Paint: begin
             mv_DC := beginPaint (window, @mv_PS);
             with viewdata[winpo] do begin
              if bmpdata.sizex * zoom <= winsizex then begin
               rrd.left := (winsizex - bmpdata.sizex * zoom) shr 1;
               rrd.right := bmpdata.sizex * zoom;
               rrs.left := 0;
               rrs.right := bmpdata.sizex;
              end else begin
               rrd.left := -viewofsx mod zoom;
               rrd.right := winsizex - (winsizex mod zoom) + zoom;
               rrs.left := viewofsx div zoom;
               rrs.right := (winsizex div zoom) + 1;
              end;
              if bmpdata.sizey * zoom <= winsizey then begin
               rrd.top := (winsizey - bmpdata.sizey * zoom) shr 1;
               rrd.bottom := bmpdata.sizey * zoom;
               rrs.top := 0;
               rrs.bottom := bmpdata.sizey;
              end else begin
               rrd.top := -viewofsy mod zoom;
               rrd.bottom := winsizey - (winsizey mod zoom) + zoom;
               rrs.top := viewofsy div zoom;
               rrs.bottom := (winsizey div zoom) + 1;
              end;
             end;
             StretchBlt (mv_DC,
                    rrd.left, rrd.top, rrd.right, rrd.bottom,
                    viewdata[winpo].deeku,
                    rrs.left, rrs.top, rrs.right, rrs.bottom,
                    SRCCOPY);
             endPaint (window, mv_PS);
             ViewProc := 0;
            end;
  // Resizing
  wm_Size: with viewdata[winpo] do begin
            // read the new window size
            winsizex := word(lapu);
            winsizey := lapu shr 16;
            // adjust the view offset
            if winsizex > bmpdata.sizex * zoom then
             viewofsx := -((winsizex - bmpdata.sizex * zoom) shr 1)
            else if viewofsx > bmpdata.sizex * zoom - winsizex then
             viewofsx := bmpdata.sizex * zoom - winsizex
            else if viewofsx < 0 then viewofsx := 0;
            if winsizey > bmpdata.sizey * zoom then
             viewofsy := -((winsizey - bmpdata.sizey * zoom) shr 1)
            else if viewofsy > bmpdata.sizey * zoom - winsizey then
             viewofsy := bmpdata.sizey * zoom - winsizey
            else if viewofsy < 0 then viewofsy := 0;
            invalidaterect(window, NIL, TRUE);
            viewproc := 0;
           end;
  // Losing or gaining window focus
  wm_Activate: begin
                if wepu and $FFFF = WA_INACTIVE then begin
                 if mousescrolling then begin
                  ReleaseCapture;
                  mousescrolling := FALSE;
                 end;
                end else
                 lastactiveview := winpo;
               end;
  // Mouse stuff
  wm_MouseMove: begin
                 // update coords text
                 kind := strdec((lapu and $FFFF + viewdata[winpo].viewofsx) div viewdata[winpo].zoom) + ', '
                       + strdec((lapu shr 16 + viewdata[winpo].viewofsy) div viewdata[winpo].zoom) + chr(0);
                 SendMessage(mv_StaticH[0], WM_SETTEXT, length(kind), ptrint(@kind[1]));

                 if mousescrolling = FALSE then begin
                  // If left button pressed, start mousescrolling
                  if wepu and MK_LBUTTON <> 0 then begin
                   SetCapture(window);
                   mousescrolling := TRUE;
                   mousescrollx := lapu and $FFFF;
                   mousescrolly := lapu shr 16;
                  end;
                 end

                 // Mouse scrolling
                 else with viewdata[winpo] do begin
                  // rrd.left/top = delta from previous cursor position
                  rrd.left := mousescrollx - integer(lapu and $FFFF);
                  rrd.top := mousescrolly - integer(lapu shr 16);
                  mousescrollx := integer(lapu and $FFFF);
                  mousescrolly := integer(lapu shr 16);

                  // images smaller than winsize can't be scrolled
                  if bmpdata.sizex * zoom <= winsizex then rrd.left := 0;
                  if bmpdata.sizey * zoom <= winsizey then rrd.top := 0;
                  if (rrd.left or rrd.top) <> 0 then begin
                   // can't scroll view beyond edges
                   if viewofsx + rrd.left <= 0 then rrd.left := -viewofsx else
                   if dword(viewofsx + rrd.left + winsizex) >= bmpdata.sizex * zoom then rrd.left := bmpdata.sizex * zoom - winsizex - viewofsx;
                   if viewofsy + rrd.top <= 0 then rrd.top := -viewofsy else
                   if dword(viewofsy + rrd.top + winsizey) >= bmpdata.sizey * zoom then rrd.top := bmpdata.sizey * zoom - winsizey - viewofsy;

                   if (rrd.left or rrd.top) <> 0 then begin
                    inc(viewofsx, rrd.left);
                    inc(viewofsy, rrd.top);
                    invalidaterect(window, NIL, FALSE);
                   end;
                  end;
                 end;
                 viewproc := 0;
                end;
  wm_LButtonUp: if mousescrolling then begin
                 ReleaseCapture;
                 mousescrolling := FALSE;
                 viewproc := 0;
                end;
  // Right-click menu popup
  wm_ContextMenu: begin
                   if mousescrolling then begin
                    ReleaseCapture; mousescrolling := FALSE;
                   end;
                   RemoveMenu(mv_ContextMenu, 2, MF_BYPOSITION);
                   case winpo of
                    0: begin
                        kind := '&Paste from clipboard' + chr(8) + '(CTRL+V)' + chr(0);
                        InsertMenu(mv_ContextMenu, 2, MF_BYPOSITION, 95, @kind[1]);
                       end;
                    3: begin
                        kind := '&Paste from clipboard' + chr(8) + '(CTRL+F)' + chr(0);
                        InsertMenu(mv_ContextMenu, 2, MF_BYPOSITION, 96, @kind[1]);
                       end;
                   end;
                   TrackPopupMenu(mv_ContextMenu, TPM_LEFTALIGN, lapu and $FFFF, lapu shr 16, 0, window, NIL);
                   viewproc := 0;
                  end;
  wm_Command: case wepu of
               93: SaveViewAsPNG(winpo);
               94: CopyView(winpo);
               95,96: SendMessage(mv_MainWinH, amex, wepu, lapu);
              end;
  // Keypresses
  wm_Char: begin
            case wepu of
             ord('+'): with viewdata[winpo] do if zoom < 8 then begin
                        // Make sure the image does not scroll while zooming
                        viewofsx := (word(winsizex shr 1) + viewofsx) * (zoom + 1) div zoom - (winsizex shr 1);
                        viewofsy := (word(winsizey shr 1) + viewofsy) * (zoom + 1) div zoom - (winsizey shr 1);
                        inc(zoom);
                        // Affirm bounds
                        if winsizex > bmpdata.sizex * zoom then viewofsx := -((winsizex - bmpdata.sizex * zoom) shr 1)
                        else if viewofsx < 0 then viewofsx := 0
                        else if viewofsx + winsizex >= bmpdata.sizex * zoom then viewofsx := bmpdata.sizex * zoom - winsizex;
                        if winsizey > bmpdata.sizey * zoom then viewofsy := -((winsizey - bmpdata.sizey * zoom) shr 1)
                        else if viewofsy < 0 then viewofsy := 0
                        else if viewofsy + winsizey >= bmpdata.sizey * zoom then viewofsy := bmpdata.sizey * zoom - winsizey;
                        // Redraw the image
                        invalidaterect(window, NIL, FALSE);
                       end;
             ord('-'): with viewdata[winpo] do if zoom > 1 then begin
                        // Make sure the image does not scroll while zooming
                        dec(zoom);
                        viewofsx := (word(winsizex shr 1) + viewofsx) * zoom div (zoom + 1) - (winsizex shr 1);
                        viewofsy := (word(winsizey shr 1) + viewofsy) * zoom div (zoom + 1) - (winsizey shr 1);
                        // Affirm bounds
                        if winsizex > bmpdata.sizex * zoom then viewofsx := -((winsizex - bmpdata.sizex * zoom) shr 1) else
                        if viewofsx < 0 then viewofsx := 0 else
                        if dword(viewofsx + winsizex) >= bmpdata.sizex * zoom then viewofsx := bmpdata.sizex * zoom - winsizex;
                        if winsizey > bmpdata.sizey * zoom then viewofsy := -((winsizey - bmpdata.sizey * zoom) shr 1) else
                        if viewofsy < 0 then viewofsy := 0 else
                        if dword(viewofsy + winsizey) >= bmpdata.sizey * zoom then viewofsy := bmpdata.sizey * zoom - winsizey;
                        // Redraw the image
                        invalidaterect(window, NIL, TRUE);
                       end;
            end;
            viewproc := 0;
           end;
  // Closing down
  wm_Close: begin
             ViewProc := 0; // ignore close commands
            end;
  wm_Destroy: begin // getting destroyed regardless of wm_close
               if lastactiveview = winpo then lastactiveview := $FF;
               // Clean the variables
               if viewdata[winpo].winhandu <> 0 then viewdata[winpo].winhandu := 0;
               if viewdata[winpo].BuffyH <> 0 then begin
                SelectObject(viewdata[winpo].deeku, viewdata[winpo].OldBuffyH);
                DeleteDC(viewdata[winpo].deeku);
                DeleteObject(viewdata[winpo].BuffyH);
                viewdata[winpo].buffyh := 0;
               end;
               mcg_ForgetImage(@viewdata[winpo].bmpdata);
               SetForegroundWindow(mv_MainWinH);
              end;
  else ViewProc := DefWindowProc (Window, AMex, wepu, lapu);
 end;
end;

function AlfaSelectorProc (window : hwnd; amex : uint; wepu : wparam; lapu : lparam) : lresult; stdcall;
// A mini-dialog box for entering the color that alpha is rendered with.
var flaguz : dword;
    kind : string[9];
    txt : string;
    handuli : hwnd;
    rr : rect;
begin
 AlfaSelectorProc := 0;
 case amex of
  wm_InitDialog: begin
                  flaguz := SWP_NOMOVE or SWP_NOREDRAW;
                  rr.left := 0; rr.right := 384;
                  rr.top := 0; rr.bottom := 144;
                  AdjustWindowRect(rr, WS_CAPTION or DS_CENTER or DS_MODALFRAME, FALSE);
                  SetWindowPos(window, HWND_TOP, 0, 0, rr.right - rr.left, rr.bottom - rr.top, flaguz);

                  kind := 'STATIC' + chr(0); txt := 'Please enter the hexadecimal color to render the alpha channel with' + chr(13) + '(example: 007FFF would be azure)' + chr(0);
                  flaguz := WS_CHILD or WS_VISIBLE or SS_CENTER;
                  rr.left := 0; rr.right := 384;
                  rr.top := 24; rr.bottom := 32;
                  handuli := CreateWindow(@kind[1], @txt[1], flaguz,
                               rr.left, rr.top, rr.right, rr.bottom,
                               window, 180, system.maininstance, NIL);
                  SendMessageA(handuli, WM_SETFONT, longint(mv_FontH[2]), -1);

                  kind := 'EDIT' + chr(0); txt := hexifycolor(acolor) + chr(0);
                  flaguz := WS_CHILD or WS_VISIBLE or ES_UPPERCASE or WS_TABSTOP;
                  rr.left := 96; rr.right := 192;
                  rr.top := 64; rr.bottom := 24;
                  handuli := CreateWindowEx(WS_EX_CLIENTEDGE, @kind[1], @txt[1], flaguz,
                               rr.left, rr.top, rr.right, rr.bottom,
                               window, 181, system.maininstance, NIL);
                  SendMessageA(handuli, WM_SETFONT, longint(mv_FontH[1]), -1);
                  SendMessageA(handuli, EM_SETLIMITTEXT, 6, 0);

                  kind := 'BUTTON' + chr(0); txt := 'OK' + chr(0);
                  flaguz := WS_CHILD or WS_VISIBLE or BS_CENTER or BS_DEFPUSHBUTTON or WS_TABSTOP;
                  rr.left := 160; rr.right := 56;
                  rr.top := 96; rr.bottom := 24;
                  handuli := CreateWindow(@kind[1], @txt[1], flaguz,
                               rr.left, rr.top, rr.right, rr.bottom,
                               window, 182, system.maininstance, NIL);
                  SendMessageA(handuli, WM_SETFONT, longint(mv_FontH[1]), -1);
                  SendMessageA(window, DM_SETDEFID, 182, 0);

                  AlfaSelectorProc := 1;
                 end;
  wm_Command: if word(wepu) = 182 then begin
               SendMessageA(window, wm_Close, 0, 0);
               AlfaSelectorProc := 1;
              end else if word(wepu) = 181 then begin
               if wepu shr 16 = EN_UPDATE then begin
                txt[0] := chr(0);
                byte(kind[0]) := SendMessageA(lapu, WM_GETTEXT, 9, ptrint(@kind[1]));
                flaguz := length(kind);
                while flaguz <> 0 do begin
                 if (kind[flaguz] in ['0'..'9','A'..'F'] = FALSE) then begin
                  kind := copy(kind, 1, flaguz - 1) + copy(kind, flaguz + 1, length(kind) - flaguz);
                  txt[0] := chr(flaguz);
                 end;
                 dec(flaguz);
                end;
                kind := kind + chr(0);
                flaguz := 0; flaguz := byte(txt[0]);
                if flaguz <> 0 then begin
                 dec(flaguz);
                 SendMessageA(lapu, WM_SETTEXT, length(kind), ptrint(@kind[1]));
                 SendMessageA(lapu, EM_SETSEL, flaguz, flaguz);
                end;
                flaguz := valhex(kind);
                acolor.b := byte(flaguz);
                acolor.g := byte(flaguz shr 8);
                acolor.r := byte(flaguz shr 16);
               end;
              end;
  wm_Close: begin
             for flaguz := 0 to high(viewdata) do RedrawView(flaguz);
             EndDialog(window, 0);
             AlfaSelectorProc := 1;
            end;
 end;
end;

function TabProc (window : hwnd; amex : uint; wepu : wparam; lapu : lparam) : lresult; stdcall;
// Subclass handler for tab pages. All controls on tabs are children of the
// tab page, so in order to handle control messages, we have to intercept
// them before the tab page's default handler discards them...
var z : dword;
    txt : string;
    slideinfo : scrollinfo;
begin
 TabProc := 0;
 case amex of
  // Slider handling
  wm_HScroll: if wepu and $FFFF <> SB_ENDSCROLL then begin
               slideinfo.fMask := SIF_ALL;
               slideinfo.cbSize := sizeof(slideinfo);
               GetScrollInfo(lapu, SB_CTL, @slideinfo);
               z := slideinfo.nPos;
               case wepu and $FFFF of
                SB_LINELEFT: if z > 0 then dec(z);
                SB_LINERIGHT: inc(z);
                SB_PAGELEFT: if z > slideinfo.nPage
                             then dec(z, slideinfo.nPage) else z := 0;
                SB_PAGERIGHT: inc(z, slideinfo.nPage);
                SB_THUMBPOSITION, SB_THUMBTRACK: z := wepu shr 16;
               end;
               slideinfo.fMask := SIF_POS;
               slideinfo.nPos := z;
               z := SetScrollInfo(lapu, SB_CTL, @slideinfo, TRUE);
               if dword(lapu) = mv_SliderH[1] then begin
                txt := ' ' + strdec(longint(z - 16)) + chr(0);
                if z = 16 then txt := 'Neutral' + txt else
                if z < 16 then txt := 'Dark' + txt else txt := 'Light' + txt;
                SendMessageA(mv_StaticH[3], wm_settext, 0, ptrint(@txt[1]));
               end else
               if dword(lapu) = mv_SliderH[2] then begin
                txt := ' ' + strdec(longint(z - 16)) + chr(0);
                if z = 16 then txt := 'Neutral' + txt else
                if z < 16 then txt := 'Grey' + txt else txt := 'Colorful' + txt;
                SendMessageA(mv_StaticH[5], wm_settext, 0, ptrint(@txt[1]));
               end else
               if dword(lapu) = mv_SliderH[3] then begin
                txt := ' ' + strdec(longint(z - 5)) + chr(0);
                if z = 5 then txt := 'Neutral' + txt else
                if z < 5 then txt := 'Cold' + txt else txt := 'Warm' + txt;
                SendMessageA(mv_StaticH[7], wm_settext, 0, ptrint(@txt[1]));
               end else
               if dword(lapu) = mv_SliderH[4] then begin
                txt := ' ' + strdec(z) + chr(0);
                if z = 16 then txt := 'Normal' + txt else
                if z < 16 then txt := 'Weak' + txt else txt := 'Strong' + txt;
                SendMessageA(mv_StaticH[9], wm_settext, 0, ptrint(@txt[1]));
               end else
               if dword(lapu) = mv_SliderH[5] then begin
                txt := ' ' + strdec(z) + chr(0);
                if z = 16 then txt := 'Normal' + txt else
                if z = 0 then txt := 'None' + txt else
                if z < 16 then txt := 'Timid' + txt else txt := 'Bold' + txt;
                SendMessageA(mv_StaticH[11], wm_settext, 0, ptrint(@txt[1]));
               end else
               if dword(lapu) = mv_SliderH[6] then begin
                txt := ' ' + strdec(z) + chr(0);
                if z = 16 then txt := 'Normal' + txt else
                if z = 0 then txt := 'None' + txt else
                if z < 16 then txt := 'Timid' + txt else txt := 'Bold' + txt;
                SendMessageA(mv_StaticH[13], wm_settext, 0, ptrint(@txt[1]));
               end;
              end;
  else TabProc := CallWindowProc(OldTabProc, window, amex, wepu, lapu);
 end;
end;

function mv_MainProc (window : hwnd; amex : uint; wepu : wparam; lapu : lparam) : lresult; stdcall;
// Message handler for the main work window that has everything on it
var kind, txt, strutsi : string;
    slideinfo : scrollinfo;
    openfilurec : openfilename;
    cliphand : handle;
    objp : pointer;
    rr, rtab : rect;
    z, zz : dword;
    f : file;
    tempbmp, bmp2 : bitmaptype;
begin
 mv_MainProc := 0;
 case amex of
  // Initialization
  wm_Create: begin
              // Tab control
              rtab.left := 4; rtab.right := mainsizex - 8;
              rtab.top := 4; rtab.bottom := mainsizey - helpsizey - 8;
              mv_TabH := CreateWindow(WC_TABCONTROL, NIL,
                         WS_CHILD or WS_VISIBLE or WS_CLIPSIBLINGS,
                         rtab.left, rtab.top, rtab.right, rtab.bottom,
                         window, 40, system.maininstance, NIL);
              // Init tabs
              SendMessageA(mv_TabH, wm_setfont, longint(mv_FontH[2]), 0);
              getmem(objp, sizeof(TC_ITEM));
              fillbyte(objp^, sizeof(TC_ITEM), 0);
              TC_ITEM(objp^).mask := TCIF_TEXT;
              TC_ITEM(objp^).pszText := @kind[1];
              kind := 'Params' + chr(0);
              SendMessage(mv_TabH, TCM_INSERTITEM, 0, ptrint(objp));
              kind := 'Hints' + chr(0);
              SendMessage(mv_TabH, TCM_INSERTITEM, 1, ptrint(objp));
              freemem(objp); objp := NIL;
              // get tab page size
              GetClientRect(mv_TabH, @rtab);
              SendMessage(mv_TabH, TCM_ADJUSTRECT, 0, ptrint(@rtab));
              dec(rtab.right, rtab.left);
              dec(rtab.bottom, rtab.top);
              // Statics!
              kind := 'STATIC' + chr(0);
              mv_TabWinH[1] := CreateWindow(@kind[1], NIL, WS_CHILD or WS_VISIBLE,
                               rtab.left, rtab.top, rtab.right, rtab.bottom,
                               mv_TabH, 39, system.maininstance, NIL);
              mv_TabWinH[2] := CreateWindow(@kind[1], NIL, WS_CHILD,
                               rtab.left, rtab.top, rtab.right, rtab.bottom,
                               mv_TabH, 38, system.maininstance, NIL);
              ptruint(OldTabProc) := ptruint(SetWindowLong(mv_TabWinH[1], GWL_WNDPROC, ptrint(@TabProc)));

              z := WS_CHILD or WS_VISIBLE or SS_LEFT;
              rr.left := 4; rr.right := mainsizex shr 1 - 4;
              rr.top := mainsizey - helpsizey; rr.bottom := helpsizey - 4;
              mv_StaticH[0]:= CreateWindow(@kind[1], NIL, z,
                               rr.left, rr.top, rr.right, rr.bottom,
                               window, 40, system.maininstance, NIL);

              z := WS_CHILD or WS_VISIBLE or SS_ETCHEDHORZ;
              rr.left := 0; rr.right := mainsizex + 8;
              rr.top := 0; rr.bottom := 1;
              mv_StaticH[1]:= CreateWindow(@kind[1], NIL, z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              window, 41, system.maininstance, NIL);

              txt := 'Lightness:' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_LEFT;
              rr.top := 0; rr.bottom := 16;
              rr.left := 0; rr.right := rtab.right shr 1;
              mv_StaticH[2]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 42, system.maininstance, NIL);
              txt := 'Neutral 0' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_CENTER;
              rr.left := rr.right;
              mv_StaticH[3]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 43, system.maininstance, NIL);

              txt := 'Chrominance:' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_LEFT;
              rr.top := 34;
              rr.left := 0; rr.right := rtab.right shr 1;
              mv_StaticH[4]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 44, system.maininstance, NIL);
              txt := 'Neutral 0' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_CENTER;
              rr.left := rr.right;
              mv_StaticH[5]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 45, system.maininstance, NIL);

              txt := 'Temperature:' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_LEFT;
              rr.top := 68;
              rr.left := 0; rr.right := rtab.right shr 1;
              mv_StaticH[6]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 46, system.maininstance, NIL);
              txt := 'Neutral 0' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_CENTER;
              rr.left := rr.right;
              mv_StaticH[7]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 47, system.maininstance, NIL);

              txt := 'Revdither:' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_LEFT;
              rr.top := 102;
              rr.left := 0; rr.right := rtab.right shr 1;
              mv_StaticH[8]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 48, system.maininstance, NIL);
              txt := 'Normal 16' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_CENTER;
              rr.left := rr.right;
              mv_StaticH[9]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 49, system.maininstance, NIL);

              txt := 'EPBthres:' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_LEFT;
              rr.top := 136;
              rr.left := 0; rr.right := rtab.right shr 1;
              mv_StaticH[10]:= CreateWindow(@kind[1], @txt[1], z,
                               rr.left, rr.top, rr.right, rr.bottom,
                               mv_TabWinH[1], 50, system.maininstance, NIL);
              txt := 'Normal 16' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_CENTER;
              rr.left := rr.right;
              mv_StaticH[11]:= CreateWindow(@kind[1], @txt[1], z,
                               rr.left, rr.top, rr.right, rr.bottom,
                               mv_TabWinH[1], 51, system.maininstance, NIL);

              txt := 'SEBthres:' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_LEFT;
              rr.top := 170;
              rr.left := 0; rr.right := rtab.right shr 1;
              mv_StaticH[12]:= CreateWindow(@kind[1], @txt[1], z,
                               rr.left, rr.top, rr.right, rr.bottom,
                               mv_TabWinH[1], 52, system.maininstance, NIL);
              txt := 'Normal 16' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SS_CENTER;
              rr.left := rr.right;
              mv_StaticH[13]:= CreateWindow(@kind[1], @txt[1], z,
                               rr.left, rr.top, rr.right, rr.bottom,
                               mv_TabWinH[1], 53, system.maininstance, NIL);

              // Sliders!
              kind := 'SCROLLBAR' + chr(0);
              z := WS_CHILD or WS_VISIBLE or SBS_HORZ;
              rr.left := 4; rr.right := rtab.right - 8;
              rr.top := 16; rr.bottom := 14;
              mv_SliderH[1]:= CreateWindow(@kind[1], NIL, z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 31, system.maininstance, NIL);
              rr.top := 50;
              mv_SliderH[2]:= CreateWindow(@kind[1], NIL, z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 32, system.maininstance, NIL);
              rr.top := 84;
              mv_SliderH[3]:= CreateWindow(@kind[1], NIL, z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 33, system.maininstance, NIL);
              rr.top := 118;
              mv_SliderH[4]:= CreateWindow(@kind[1], NIL, z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 34, system.maininstance, NIL);
              rr.top := 152;
              mv_SliderH[5]:= CreateWindow(@kind[1], NIL, z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 35, system.maininstance, NIL);
              rr.top := 186;
              mv_SliderH[6]:= CreateWindow(@kind[1], NIL, z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[1], 36, system.maininstance, NIL);

              // Buttons!
              kind := 'BUTTON' + chr(0);
              z := WS_CHILD or WS_VISIBLE or BS_TEXT or BS_PUSHLIKE;
              txt := 'Beautify!' + chr(0);
              rr.right := mainsizex shr 1 - 12;
              rr.left := mainsizex - rr.right - 4;
              rr.top := mainsizey - helpsizey; rr.bottom := helpsizey - 4;
              mv_ButtonH[0]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              window, 60, system.maininstance, NIL);

              z := WS_CHILD or WS_VISIBLE or BS_TEXT or BS_AUTOCHECKBOX;
              txt := 'Alpha edges' + chr(0);
              rr.left := 4;
              rr.right := rtab.right shr 1 - 8;
              rr.top := 2; rr.bottom := 20;
              mv_ButtonH[1]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[2], 61, system.maininstance, NIL);
              txt := 'H / V lines' + chr(0);
              rr.left := rtab.right shr 1 + 4;
              mv_ButtonH[2]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[2], 62, system.maininstance, NIL);
              txt := 'Checkerboard only' + chr(0);
              rr.left := 4; rr.right := rtab.right - 8; rr.top := 22;
              mv_ButtonH[3]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[2], 63, system.maininstance, NIL);

              z := WS_CHILD or WS_VISIBLE or BS_TEXT or BS_AUTORADIOBUTTON or BS_PUSHLIKE or WS_GROUP;
              rr.left := 4;
              rr.right := (rtab.right + 8) div 4 - 16;
              rr.top := rtab.bottom - 24; rr.bottom := 20;
              txt := '•' + chr(0);
              mv_ButtonH[4]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[2], 64, system.maininstance, NIL);
              z := WS_CHILD or WS_VISIBLE or BS_TEXT or BS_AUTORADIOBUTTON or BS_PUSHLIKE ;
              inc(rr.left, rr.right + 16);
              txt := 'O' + chr(0);
              mv_ButtonH[5]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[2], 65, system.maininstance, NIL);
              inc(rr.left, rr.right + 16);
              txt := '/' + chr(0);
              mv_ButtonH[6]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[2], 66, system.maininstance, NIL);
              inc(rr.left, rr.right + 16);
              txt := '[]' + chr(0);
              mv_ButtonH[7]:= CreateWindow(@kind[1], @txt[1], z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              mv_TabWinH[2], 67, system.maininstance, NIL);
              // Boxes!
              kind := 'LISTBOX' + chr(0);
              z := WS_CHILD or WS_VISIBLE or WS_GROUP or WS_VSCROLL
                or LBS_DISABLENOSCROLL or LBS_NOINTEGRALHEIGHT or LBS_NOTIFY;
              rr.left := 4; rr.right := rtab.right - 8;
              rr.top := 44; rr.bottom := rtab.bottom - rr.top - 54;
              mv_ListH[1] := CreateWindowEx(WS_EX_CLIENTEDGE, @kind[1], NIL, z,
                             rr.left, rr.top, rr.right, rr.bottom,
                             mv_TabWinH[2], 68, system.maininstance, NIL);
              kind := 'COMBOBOX' + chr(0);
              z := WS_CHILD or WS_VISIBLE or CBS_DROPDOWNLIST;
              rr.top := rtab.bottom - 50; rr.bottom := 400;
              mv_ListH[2] := CreateWindow(@kind[1], NIL, z,
                             rr.left, rr.top, rr.right, rr.bottom,
                             mv_TabWinH[2], 69, system.maininstance, NIL);

              // Progress bar!
              z := WS_CHILD or PBS_SMOOTH;
              rr.top := mainsizey - helpsizey; rr.bottom := helpsizey - 4;
              rr.left := 4; rr.right := mainsizex - 8;
              mv_ProgressH := CreateWindow(PROGRESS_CLASS, NIL, z,
                              rr.left, rr.top, rr.right, rr.bottom,
                              window, 30, system.maininstance, NIL);

              // Set fonts
              for z := 0 to 3 do SendMessageA(mv_ButtonH[z], wm_setfont, longint(mv_FontH[2]), 0);
              for z := 4 to 7 do SendMessageA(mv_ButtonH[z], wm_setfont, longint(mv_FontH[1]), 0);
              for z := 0 to 13 do SendMessageA(mv_StaticH[z], wm_setfont, longint(mv_FontH[2]), 0);
              for z := 1 to 2 do SendMessageA(mv_ListH[z], wm_setfont, longint(mv_FontH[2]), 0);
              // Init sliders
              slideinfo.cbSize := sizeof(slideinfo);
              slideinfo.fMask := SIF_ALL;
              slideinfo.nMin := 0;
              slideinfo.nMax := 35; // 32 + nPage-1
              slideinfo.nPage := 4;
              slideinfo.nPos := 16;
              SetScrollInfo(mv_SliderH[1], SB_CTL, @slideinfo, TRUE);
              SetScrollInfo(mv_SliderH[2], SB_CTL, @slideinfo, TRUE);
              SetScrollInfo(mv_SliderH[4], SB_CTL, @slideinfo, TRUE);
              SetScrollInfo(mv_SliderH[5], SB_CTL, @slideinfo, TRUE);
              SetScrollInfo(mv_SliderH[6], SB_CTL, @slideinfo, TRUE);
              slideinfo.nMin := 0;
              slideinfo.nMax := 10;
              slideinfo.nPage := 1;
              slideinfo.nPos := 5;
              SetScrollInfo(mv_SliderH[3], SB_CTL, @slideinfo, TRUE);
              // Init boxes
              kind := '-new-' + chr(0);
              SendMessage(mv_ListH[1], LB_ADDSTRING, 0, ptrint(@kind[1]));
              kind := 'Horizontal line' + chr(0);
              SendMessage(mv_ListH[2], CB_ADDSTRING, 0, ptrint(@kind[1]));
              kind := 'Vertical line' + chr(0);
              SendMessage(mv_ListH[2], CB_ADDSTRING, 0, ptrint(@kind[1]));
              kind := 'H+V line' + chr(0);
              SendMessage(mv_ListH[2], CB_ADDSTRING, 0, ptrint(@kind[1]));
              kind := 'Meandering line' + chr(0);
              SendMessage(mv_ListH[2], CB_ADDSTRING, 0, ptrint(@kind[1]));
              kind := 'Filter' + chr(0);
              SendMessage(mv_ListH[2], CB_ADDSTRING, 0, ptrint(@kind[1]));
              kind := 'Don''t touch' + chr(0);
              SendMessage(mv_ListH[2], CB_ADDSTRING, 0, ptrint(@kind[1]));
              SendMessage(mv_ListH[2], CB_SETCURSEL, 0, 0);
              // Init other stuff
              SendMessage(mv_ButtonH[4], BM_CLICK, 0, 0);
              SendMessage(mv_ProgressH, PBM_SETRANGE, 0, 10 shl 16);
              SendMessage(mv_ProgressH, PBM_SETSTEP, 1, 0);
             end;
  // Tab switch
  wm_Notify: begin
              if wepu and $FFFF = 40 then begin
               if longint(NMHDR(pointer(lapu)^).code) = TCN_SELCHANGE then begin
                z := SendMessage(mv_TabH, TCM_GETCURSEL, 0, 0);
                ShowWindow(mv_TabWinH[z xor 1 + 1], SW_HIDE);
                ShowWindow(mv_TabWinH[z + 1], SW_SHOW);
               end;
              end;
             end;
  // Control handling
  wm_Command: begin
               case word(wepu) of
                // Beautify
                60: if viewdata[0].bmpdata.memformat in [4,5] = FALSE then begin
                     kind := 'Source must have 256 colors or less' + chr(0);
                     MessageBoxA(window, @kind[1], NIL, MB_OK);
                    end else begin
                     GrabUIParams;
                     tempbmp.image := NIL; bmp2.image := NIL;
                     SendMessage(mv_ProgressH, PBM_SETPOS, 0, 0);
                     ShowWindow(mv_ProgressH, SW_SHOWNA);
                     Beautify(@viewdata[0].bmpdata, @tempbmp, @bmp2);
                     ShowWindow(mv_ProgressH, SW_HIDE);
                     SpawnView(1, @tempbmp);
                     SpawnView(2, @bmp2);
                    end;
                // Open a PNG or BMP file
                90,92: begin
                     kind := 'PNG or BMP' + chr(0) + '*.png;*.bmp' + chr(0) + chr(0);
                     txt := chr(0);
                     fillbyte(openfilurec, sizeof(openfilurec), 0);
                     with openfilurec do begin
                      lStructSize := 76; // sizeof gives incorrect result?
                      hwndOwner := window;
                      lpstrFilter := @kind[1]; lpstrCustomFilter := NIL;
                      nFilterIndex := 1;
                      lpstrFile := @txt[1]; nMaxFile := 255;
                      lpstrFileTitle := NIL; lpstrInitialDir := NIL; lpstrTitle := NIL;
                      Flags := OFN_FILEMUSTEXIST;
                     end;
                     if GetOpenFileNameA(@openfilurec) then begin
                      // We got a filename the user wants to open!
                      assign(f, openfilurec.lpstrfile);
                      filemode := 0; reset(f, 1); // read-only
                      z := IOresult; // problem opening the file?
                      if z <> 0 then begin
                       txt := errortxt(z) + chr(0);
                       MessageBoxA(window, @txt[1], NIL, MB_OK);
                      end else begin
                       zz := filesize(f);
                       getmem(objp, zz); // read file into memory
                       blockread(f, objp^, zz);
                       close(f);
                       tempbmp.image := NIL;
                       z := mcg_LoadGraphic(objp, zz, @tempbmp); // MCGLoder
                       freemem(objp); objp := NIL;
                       if z <> 0 then begin
                        txt := mcg_errortxt + chr(0);
                        MessageBoxA(window, @txt[1], NIL, MB_OK)
                       end else begin
                        if word(wepu) = 90 then begin
                         if SpawnView(0, @tempbmp) then begin
                          // set the window name
                          txt := openfilurec.lpstrfile;
                          txt := upcase(copy(txt, openfilurec.nFileOffset + 1, length(txt) - openfilurec.nFileOffset));
                          if (copy(txt, length(txt) - 3, 4) = '.PNG')
                          or (copy(txt, length(txt) - 3, 4) = '.BMP')
                          then txt := copy(txt, 1, length(txt) - 4);
                          if length(txt) > 15 then txt := copy(txt, 1, 15);
                          txt := txt + chr(0);
                          SendMessageA(mv_MainWinH, WM_SETTEXT, 0, ptrint(@txt[1]));
                         end;
                        end else begin
                         SpawnView(3, @tempbmp);
                        end;
                       end;
                       mcg_ForgetImage(@tempbmp);
                      end;
                     end;
                    end;
                // Save view as PNG
                91: if lastactiveview <> $FF then SaveViewAsPNG(lastactiveview);
                // Copy image to clipboard
                94: if lastactiveview <> $FF then CopyView(lastactiveview);
                // Copy from clipboard
                95,96: begin
                     OpenClipboard(window);

                     if IsClipboardFormatAvailable(CF_DIB) then begin
                      cliphand := GetClipboardData(CF_DIB);
                      objp := GlobalLock(cliphand);
                      tempbmp.image := NIL;
                      z := mcg_BMPtoMemory(objp, @tempbmp); // unit MCGLoder
                      GlobalUnlock(cliphand);
                      if z <> 0 then begin
                       strutsi := mcg_errortxt + chr(0);
                       MessageBoxA(mv_MainWinH, @strutsi[1], NIL, MB_OK);
                      end else begin
                       if word(wepu) = 95 then begin
                        if SpawnView(0, @tempbmp) then begin
                         // set the window name
                         txt := 'Clipboard' + chr(0);
                         SendMessageA(mv_MainWinH, WM_SETTEXT, 0, ptrint(@txt[1]));
                        end;
                       end else begin
                        SpawnView(3, @tempbmp);
                       end;
                      end;
                      mcg_ForgetImage(@tempbmp);
                     end else MessageBoxA(window, 'No graphic found on clipboard.' + chr(0), NIL, MB_OK);
                     CloseClipboard;
                    end;
                // Set alpha rendering color
                98: DialogBoxIndirect(system.maininstance, @mv_Dlg, mv_MainWinH, @AlfaSelectorProc);
                // File:Exit
                100: SendMessageA(mv_MainWinH, wm_close, 0, 0);
                // View focus change request
                101..104: SetForegroundWindow(viewdata[word(wepu) - 101].winhandu);
               end;
              end;
  // Somebody desires our destruction!
  wm_Close: begin
             DestroyWindow(window); mv_MainWinH := 0;
            end;
  wm_Destroy: begin
               mv_EndProgram := TRUE;
              end;
  else mv_MainProc := DefWindowProc(window, amex, wepu, lapu);
 end;

end;

procedure SpawnViewWindow(sr : byte);
var kind : string;
    rr : rect;
    z : dword;
begin
 if sr >= length(viewdata) then exit;
 if viewdata[sr].winhandu <> 0 then DestroyWindow(viewdata[sr].winhandu);
 // Set up the new view window
 with viewdata[sr] do begin
  winsizex := 256;
  winsizey := 256;
  // Set up a fake image to be displayed
  getmem(bmpdata.image, winsizex * winsizey);
  bmpdata.sizex := winsizex;
  bmpdata.sizey := winsizey;
  bmpdata.memformat := 4;
  bmpdata.bitdepth := 8;
  setlength(bmpdata.palette, 1);
  dword(bmpdata.palette[0]) := $FFFFFFFF;
  fillbyte(bmpdata.image^, winsizex * winsizey, 0);
  alpha := 3;
  zoom := 1; viewofsx := 0; viewofsy := 0;
 end;
 //GetClientRect(GetDesktopWindow, rr); // this gives desktop resolution
 // but we want a maximized window that does not overlap the taskbar!
 rr.right := GetSystemMetrics(SM_CXMAXIMIZED) - GetSystemMetrics(SM_CXFRAME) * 4;
 rr.bottom := GetSystemMetrics(SM_CYMAXIMIZED) - GetSystemMetrics(SM_CYFRAME) * 4 - GetSystemMetrics(SM_CYCAPTION);
 if viewdata[sr].winsizex > rr.right then viewdata[sr].winsizex := rr.right;
 if viewdata[sr].winsizey > rr.bottom then viewdata[sr].winsizey := rr.bottom;
 rr.left := 0; rr.right := viewdata[sr].winsizex;
 rr.top := 0; rr.bottom := viewdata[sr].winsizey;
 kind := viewclass;
 z := WS_CAPTION or WS_THICKFRAME;
 adjustWindowRectEx(@rr, z, FALSE, WS_EX_TOOLWINDOW);
 rr.right := rr.right - rr.left; rr.bottom := rr.bottom - rr.top;
 viewdata[sr].winhandu := CreateWindowEx(WS_EX_TOOLWINDOW, @kind[1], NIL, z,
                          sr * 40 + 32, (length(viewdata) - sr) * 18, rr.right, rr.bottom,
                          0, 0, system.maininstance, NIL);
 if viewdata[sr].winhandu = 0 then halt(99);
 SetWindowLong(viewdata[sr].winhandu, GWL_USERDATA, sr);
 ShowWindow(viewdata[sr].winhandu, SW_SHOWNORMAL);
 case sr of
  0: kind := 'Source' + chr(0);
  1: kind := 'Filter map' + chr(0);
  2: kind := 'Beautified' + chr(0);
  3: kind := 'Final' + chr(0);
 end;
 SendMessageA(viewdata[sr].winhandu, WM_SETTEXT, 0, ptrint(@kind[1]));

 with bminfo.bmiheader do begin
  bisize := sizeof(bminfo.bmiheader);
  biwidth := viewdata[sr].bmpdata.sizex;
  biheight := -viewdata[sr].bmpdata.sizey;
  bisizeimage := 0; biplanes := 1;
  bibitcount := 32; bicompression := bi_RGB;
  biclrused := 0; biclrimportant := 0;
  bixpelspermeter := 28000; biypelspermeter := 28000;
 end;
 dword(bminfo.bmicolors) := 0;
 mv_DC := getDC(viewdata[sr].winhandu);
 viewdata[sr].deeku := createCompatibleDC(mv_DC);
 ReleaseDC(viewdata[sr].winhandu, mv_DC);
 viewdata[sr].BuffyH := createDIBsection(viewdata[sr].deeku, bminfo, dib_rgb_colors, viewdata[sr].buffy, 0, 0);
 viewdata[sr].OldBuffyH := selectObject(viewdata[sr].deeku, viewdata[sr].BuffyH);

 RedrawView(sr); // make the fake initial image visible
end;

function SpawnMainWindow : boolean;
// Creates the main tool window. It cannot be a dialog because dialogs have
// trouble processing accelerator keypresses; whereas a normal window cannot
// process ws_tabstop. The latter is a smaller loss...
var windowclass : wndclass;
    strutsi : string;
    rr : rect;
    z : dword;
begin
 SpawnMainWindow := FALSE;
 // Register the view class for future use
 windowclass.style := CS_OWNDC;
 windowclass.lpfnwndproc := wndproc(@ViewProc);
 windowclass.cbclsextra := 0;
 windowclass.cbwndextra := 0;
 windowclass.hinstance := system.maininstance;
 strutsi := 'BeautyIcon' + chr(0);
 windowclass.hicon := LoadIcon(system.maininstance, @strutsi[1]);
 windowclass.hcursor := LoadCursor(0, idc_arrow);
 windowclass.hbrbackground := GetSysColorBrush(color_3Dface);
 windowclass.lpszmenuname := NIL;
 windowclass.lpszclassname := @viewclass[1];
 if registerClass (windowclass) = 0 then halt(98);

 // Register the main class for immediate use
 windowclass.style := 0;
 windowclass.lpfnwndproc := wndproc(@mv_MainProc);
 windowclass.cbclsextra := 0;
 windowclass.cbwndextra := 0;
 windowclass.hinstance := system.maininstance;
 strutsi := 'BeautyIcon' + chr(0);
 windowclass.hicon := LoadIcon(system.maininstance, @strutsi[1]);
 windowclass.hcursor := LoadCursor(0, idc_arrow);
 windowclass.hbrbackground := GetSysColorBrush(color_btnface);
 strutsi := 'BeautyMenu' + chr(0);
 windowclass.lpszmenuname := @strutsi[1];
 windowclass.lpszclassname := @mainclass[1];
 if registerClass (windowclass) = 0 then halt(98);

 strutsi := 'Arial' + chr(0);
 mv_FontH[1] := CreateFont(16, 0, 0, 0, 600, 0, 0, 0, ANSI_CHARSET,
                OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE, @strutsi[1]);
 strutsi := 'Arial' + chr(0);
 mv_FontH[2] := CreateFont(14, 0, 0, 0, 0, 0, 0, 0, ANSI_CHARSET,
                OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, DEFAULT_PITCH or FF_DONTCARE, @strutsi[1]);

 z := dword(WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX or WS_VISIBLE);
 rr.left := 0; rr.right := mainsizex; rr.top := 0; rr.bottom := mainsizey;
 AdjustWindowRectEx(@rr, z, TRUE, WS_EX_CONTROLPARENT);
 mv_MainWinH := CreateWindowEx(WS_EX_CONTROLPARENT,
                @mainclass[1], @mv_ProgramName[1], z,
                8, GetSystemMetrics(SM_CYSCREEN) - (rr.bottom - rr.top) - 40,
                rr.right - rr.left, rr.bottom - rr.top,
                0, 0, system.maininstance, NIL);
 if mv_MainWinH = 0 then halt(99);

 // Load the keyboard shortcut table from bunny.res
 strutsi := 'BeautyHop' + chr(0);
 mv_AcceleratorTable := LoadAccelerators(system.maininstance, @strutsi[1]);

 // Create a right-click pop-up menu for the views
 mv_ContextMenu := CreatePopupMenu;
 strutsi := '&Copy to clipboard ' + chr(8) + '(CTRL+C)' + chr(0);
 InsertMenu(mv_ContextMenu, 0, MF_BYPOSITION, 94, @strutsi[1]);
 strutsi := '&Dump as PNG ' + chr(8) + '(CTRL+D)' + chr(0);
 InsertMenu(mv_ContextMenu, 1, MF_BYPOSITION, 91, @strutsi[1]);

 // Create four view windows
 for z := high(viewdata) downto 0 do SpawnViewWindow(z);

 // Just in case, make sure we are in the user's face
 SetForegroundWindow(mv_MainWinH);
 SetFocus(mv_MainWinH);

 // Get rid of init messages and give the window its first layer of paint
 while peekmessage(@mv_amessage, mv_MainWinH, 0, 0, PM_REMOVE) do begin
  translatemessage(mv_amessage);
  dispatchmessage(mv_amessage);
 end;
end;

// ==================================================================
// Interface

procedure BatchProcess;
// Grab the commandline params and build a list of filenames, then attempt to
// autobeautify all of them, printing results in the console.
begin
end;

// ==================================================================

begin
 AddExitProc(@beautyexit);

 {writeln('=== Testing ===');
 with viewdata[0].bmpdata do begin
  setlength(palette, 7);
  dword(palette[0]) := $00000000;
  dword(palette[1]) := $FFFFFFFF;
  dword(palette[2]) := $FF0000FF;
  dword(palette[3]) := $0000FFFF;
  dword(palette[4]) := $808080FF;
  dword(palette[5]) := $00FF00FF;
  dword(palette[6]) := $FF00FF00;

  writeln(diffYCC(mcg_GammaInput(palette[0]), mcg_GammaInput(palette[0])));
  writeln(diffYCC(mcg_GammaInput(palette[0]), mcg_GammaInput(palette[1])));
  writeln(diffYCC(mcg_GammaInput(palette[2]), mcg_GammaInput(palette[3])));
  writeln(diffYCC(mcg_GammaInput(palette[4]), mcg_GammaInput(palette[5])));
  writeln(diffYCC(mcg_GammaInput(palette[5]), mcg_GammaInput(palette[6])));

  setlength(palette, 0);
 end;
 exit;}

 mv_Dlg.headr.style := dword(WS_CAPTION or WS_VISIBLE or DS_CENTER or DS_MODALFRAME or DS_NOIDLEMSG or WS_CLIPCHILDREN);
 mv_Dlg.headr.cdit := 0;
 mv_Dlg.headr.x := 0; mv_Dlg.headr.y := 0;
 mv_Dlg.headr.cx := ((384 + 16) * 4) div (dword(GetDialogBaseUnits) and $FFFF);
 mv_Dlg.headr.cy := ((256 + 84) * 8) div (dword(GetDialogBaseUnits) shr 16);
 fillbyte(mv_Dlg.data[0], length(mv_Dlg.data), 0);

 // Possibly any implicit access to shell32.dll by FPC may automatically set
 // up all the controls and stuff. Certainly Open/Save dialogs work fine, as
 // do progress bars, without InitCommonControls, on all systems so far.
 //InitCommonControls;

 mv_MainWinH := 0;
 mv_ContextMenu := 0; lastactiveview := $FF;
 for i := 0 to high(viewdata) do with viewdata[i] do begin
  buffyh := 0; winhandu := 0;
 end;
 mcg_AutoConvert := 1; // autoexpand bitdepth to 8, but retain indexed
 dword(acolor) := $FFDD33FF; // alpha rendering color = violet
 mainsizex := 208; mainsizey := 264; helpsizey := 20;
 mousescrolling := FALSE; mv_EndProgram := FALSE;

 // Command-line parameters:
 // nothing - launch GUI
 // filename - launch GUI, load given graphic and detail
 // filenames, /auto - batch process all files, no GUI

 SpawnMainWindow;

 // Main message loop
 while (mv_EndProgram = FALSE) and (getmessage(@mv_amessage, 0, 0, 0))
 do begin
  if translateaccelerator(mv_MainWinH, mv_AcceleratorTable, mv_amessage) = 0
  then begin
   translatemessage(mv_amessage);
   dispatchmessage(mv_amessage);
  end;
 end;

 PostQuitMessage(0);
end.
