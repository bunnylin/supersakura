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

procedure decomp_ExcellentG(const loader : TFileLoader; const outputfile : UTF8string);
// Reads the indicated Excellents graphic file, and saves it in outputfile
// as a standard PNG.
// Throws an exception in case of errors.
var imunamu : UTF8string;
    ivar, jvar : dword;
    PNGindex, xparency : dword;
    tempbmp : bitmaptype;
begin
 tempbmp.image := NIL;

 // Find this graphic name in PNGlist[], or create if doesn't exist yet.
 imunamu := ExtractFileName(loader.filename);
 imunamu := upcase(copy(imunamu, 1, length(imunamu) - length(ExtractFileExt(imunamu))));
 PNGindex := seekpng(imunamu, TRUE);

 // Test for "PiUser" signature... signifies a full MAGv3 image.
 if dword(loader.readp^) = $73556950 then begin
  while byte(loader.readp^) <> $1A do inc(loader.readp);
  // Read ahead until 00 encountered
  while byte(loader.readp^) <> $00 do begin
   inc(loader.readp);
   if (loader.readp + 4 >= loader.endp) then
    raise Exception.Create('No 00 in initial block??');
  end;
  // Skip things.
  inc(loader.readp, 10);
  // Now follows what feels like a pascal-string of unknown data.
  ivar := loader.ReadByte;
  inc(loader.readp, ivar);
 end;

 // Next two words are image width and height.
 PNGlist[PNGindex].origsizexp := (loader.ReadByte shl 8) or loader.ReadByte;
 PNGlist[PNGindex].origsizeyp := (loader.ReadByte shl 8) or loader.ReadByte;

 if (PNGlist[PNGindex].origsizexp > 640)
 or (PNGlist[PNGindex].origsizeyp > 800)
 or (PNGlist[PNGindex].origsizexp < 2)
 or (PNGlist[PNGindex].origsizeyp < 2) then
  raise Exception.Create('Suspicious size ' + strdec(PNGlist[PNGindex].origsizexp) + 'x' + strdec(PNGlist[PNGindex].origsizeyp) + ' is causing dragons of loading to refuse.');

 // Read the palette.
 setlength(PNGlist[PNGindex].pal, 16);
 for ivar := 0 to 15 do with PNGlist[PNGindex].pal[ivar] do begin
  r := loader.ReadByte and $F0;
  g := loader.ReadByte and $F0;
  b := loader.ReadByte and $F0;
 end;

 UnpackPiGraphic(loader, PNGindex);

 // Did we get the image?
 if PNGlist[PNGindex].bitmap = NIL then
  raise Exception.Create('failed to load image');

 {$note mayclubs d27*.g have garbage pixels}

 // If the image has a transparent palette index, it must be marked.
 // I think this is always index 0?
 xparency := 0;

 // Mark the intended image resolution.
 ivar := 0;
 if PNGlist[PNGindex].seqlen = 0 then
  if (PNGlist[PNGindex].origsizexp > baseresx)
  or (PNGlist[PNGindex].origsizeyp > baseresy) then inc(ivar);
 case game of
  gid_MAYCLUB: if imunamu = 'PRS' then inc(ivar); // not needed?
 end;

 if ivar <> 0 then begin
  PNGlist[PNGindex].origresx := 640;
  PNGlist[PNGindex].origresy := 400;
 end;

 PNGlist[PNGindex].framecount := 0;
 if PNGlist[PNGindex].framewidth = 0 then PNGlist[PNGindex].framewidth := PNGlist[PNGindex].origsizexp;
 if PNGlist[PNGindex].frameheight = 0 then PNGlist[PNGindex].frameheight := PNGlist[PNGindex].origsizeyp;

 // Crop out unused transparent space.
 ivar := PNGlist[PNGindex].origsizexp;
 jvar := PNGlist[PNGindex].origsizeyp;
 PNGlist[PNGindex].origofsxp := 0;
 PNGlist[PNGindex].origofsyp := 0;
 CropVoidBorders(PNGindex, xparency);

 // If the image wasn't cropped, this probably has no transparency.
 if (ivar = PNGlist[PNGindex].origsizexp)
 and (jvar = PNGlist[PNGindex].origsizeyp)
 then xparency := $FFFF;

 // Put the uncompressed image into a bitmaptype for PNG conversion...
 tempbmp.image := PNGlist[PNGindex].bitmap;
 PNGlist[PNGindex].bitmap := NIL;
 tempbmp.sizex := PNGlist[PNGindex].origsizexp;
 tempbmp.sizey := PNGlist[PNGindex].origsizeyp;
 tempbmp.bitdepth := 8;
 tempbmp.memformat := 4; // indexed
 setlength(tempbmp.palette, length(PNGlist[PNGindex].pal));

 if length(PNGlist[PNGindex].pal) <> 0 then begin
  for ivar := high(PNGlist[PNGindex].pal) downto 0 do begin
   tempbmp.palette[ivar].a := $FF;
   tempbmp.palette[ivar].b := PNGlist[PNGindex].pal[ivar].b;
   tempbmp.palette[ivar].g := PNGlist[PNGindex].pal[ivar].g;
   tempbmp.palette[ivar].r := PNGlist[PNGindex].pal[ivar].r;
  end;
 end
 else begin
  // If there was no palette, assume our pic's already 24-bit RGB.
  tempbmp.memformat := 0;
 end;

 // Set the transparent palette index, if any.
 if xparency < dword(length(tempbmp.palette)) then begin
  tempbmp.palette[xparency].a := 0;
  inc(tempbmp.memformat);
 end;

 // Convert bitmaptype(pic^) into a compressed PNG, saved in bitmap^.
 // The PNG byte size goes into jvar.
 ivar := mcg_MemoryToPng(@tempbmp, @PNGlist[PNGindex].bitmap, @jvar);
 mcg_ForgetImage(@tempbmp);

 if ivar <> 0 then begin
  if PNGlist[PNGindex].bitmap <> NIL then begin
   freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
  end;
  raise Exception.Create(mcg_errortxt);
 end;

 SaveFile(outputfile, PNGlist[PNGindex].bitmap, jvar);
 freemem(PNGlist[PNGindex].bitmap); PNGlist[PNGindex].bitmap := NIL;
end;
