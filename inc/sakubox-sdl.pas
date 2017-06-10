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

// SuperSakura text box functions

// ------------------------------------------------------------------

procedure GetNewFont(boxnum, heightp : dword);
var fontnum, minx, maxx : dword;
    facenamu : PChar;
begin
 fontnum := IsFontLangInList(languagelist[TBox[boxnum].boxlanguage]);
 if fontnum >= dword(length(fontlist)) then begin
  LogError('No font for ' + languagelist[TBox[boxnum].boxlanguage]);
  fontnum := 0;
 end;
 with TBox[boxnum] do begin
  if fonth <> NIL then TTF_CloseFont(fonth);
  fonth := TTF_OpenFont(@fontlist[fontnum].fontfile[1], heightp);
  if fonth = NIL then LogError('Failed to open font ' + fontlist[fontnum].fontfile + ': ' + TTF_GetError)
  else begin
   fontheightp := TTF_FontHeight(fonth);
   // Lineskip is sometimes greater than font height, sometimes less. If it
   // is less, rows overlap each other, which is a rendering nuisance.
   //fontheightp := TTF_FontLineSkip(fonth);
   fontwidthp := fontheightp;
   if TTF_GlyphMetrics(fonth, ord('M'), @minx, @maxx, NIL, NIL, NIL) = 0
   then begin
    log('font em ' + strdec(minx) + '..' + strdec(maxx));
    fontwidthp := maxx - minx;
   end;
   facenamu := TTF_FontFaceFamilyName(fonth);
   log('Box ' + strdec(boxnum) + ' (' + languagelist[TBox[boxnum].boxlanguage] + '): ' + facenamu + ' ' + strdec(fontheightp) + 'px/' + strdec(fontwidthp));
   facenamu := '';
  end;
  reqfontheightp := heightp;
 end;
end;

function GetUTF8Size(poku : pointer; slen, boxnum : dword) : dword;
// Returns the width in pixels of the given UTF-8 string, by forwarding the
// call to SDL's TTF_SizeUTF8. Poku must point to a valid UTF-8 byte
// sequence, and slen is the byte length of the sequence. Poku^ must also be
// slen + 1 bytes, or more, to allow for a temporary terminating zero.
var ivar, jvar : dword;
begin
 // Save the original string's terminating byte, and insert a zero.
 ivar := byte((poku + slen)^);
 byte((poku + slen)^) := 0;
 // Get the pixel size.
 jvar := 1;
 if TTF_SizeUTF8(TBox[boxnum].fonth, poku, @jvar, NIL) <> 0 then LogError('GetUTF8Size: ' + TTF_GetError);
 GetUTF8Size := jvar;
 // Restore the original string.
 byte((poku + slen)^) := ivar;
end;

// ------------------------------------------------------------------

function RenderGlyph(boxnum : dword; gnamu : pstring; framenum : byte) : word;
// Calls up the given frame of the given 32-bit graphic resource, resizes it
// to match the given style's font height, and copies the alpha channel of
// the resized graphic frame into mv_TextBuffy^. Returns the pixel width of
// the resized frame as rendered.
// Framenum should be 0-based.
// Use this to add hearts and sweatdrops inside textboxes.
//var sofs, dofs : pointer;
//    ivar, jvar : dword;
begin
 RenderGlyph := framenum;
 if boxnum >= dword(length(TBox)) then exit;

{$ifdef bonk}
 // Fetch the glyph's PNG index
 ivar := GetPNG(gnamu);
 // The PNG must exist and the requested frame must not be out of bounds!
 if (ivar = 0) or (framenum >= PNGlist[ivar].framecount) then exit;

 // Calculate the multiplier to use on the original-size glyph to achieve
 // a version that's the same size as our font
 jvar := (TBox[boxnum].fontheightp shl 15 + PNGlist[ivar].origframeheightp shr 1) div PNGlist[ivar].origframeheightp;

 // Request an appropriately resized version of the graphic
 gfxindex := GetGFX(gnamu, jvar, PNGlist[ivar].origresx, PNGlist[ivar].origresy);
 // The glyph graphic must be successfully loaded and 32-bit!
 if (gfxindex = 0) or (gfxlist[gfxindex].bitflag and $80 = 0) then exit;

 // The function will return the glyph's final pixel width, do that here...
 RenderGlyph := jvar;

 // Copy the frame into textbuffy^
 sofs := gfxlist[gfxindex].bitmap;
 dofs := mv_TextBuffy;
 inc(sofs, 3); // alpha byte

 // select the right frame
 inc(sofs, framenum * gfxlist[gfxindex].sizexp * gfxlist[gfxindex].frameheightp shl 2);
 for jvar := gfxlist[gfxindex].frameheightp - 1 downto 0 do begin
  for ivar := gfxlist[gfxindex].sizexp - 1 downto 0 do begin
   byte(dofs^) := (byte(sofs^) + 1) and $FF xor 1;
   inc(dofs); inc(sofs, 4);
  end;
  inc(dofs, textbuffysizexp - gfxlist[gfxindex].sizexp);
 end;

 sofs := NIL; dofs := NIL; // clean up
{$endif}
end;

procedure RenderTextboxContent(boxnum : dword);
// Draws the current box content in the content buffer. The content must be
// appropriately linebroken first, by calling FlowTextboxContent.
var txtsurface : PSDL_Surface;
    color1, color2 : TSDL_Color;
    runcolor, textcoloramul : RGBquad;
    txtofs, txtmark, breakindex, escindex, choiceindex : dword;
    ivar, rowsizexp, totalsizeyp : dword;
    destp : pointer;
    runalign, luggage : byte;
    runchoice : boolean;

  procedure finaliserow;
  var lclear, rclear, y : dword;
      readp : pointer;
  begin
   with TBox[boxnum] do begin
    // Calculate how much empty space should be cleared in the content buffer
    // on both sides of this complete row. Depends on text alignment.
    lclear := 0; rclear := 0;
    case runalign of
     0: rclear := contentwinsizexp - rowsizexp;
     1: begin
      lclear := (contentwinsizexp - rowsizexp) shr 1;
      rclear := contentwinsizexp - rowsizexp - lclear;
     end;
     2: lclear := contentwinsizexp - rowsizexp;
    end;

    readp := rowbuf;
    rowsizexp := rowsizexp * 4;
    for y := lineheightp - 1 downto 0 do begin
     // Clear the left side.
     if lclear <> 0 then begin
      filldword(destp^, lclear, 0);
      inc(destp, lclear * 4);
     end;
     // Copy the row.
     move(readp^, destp^, rowsizexp);
     inc(readp, contentwinsizexp * 4);
     inc(destp, rowsizexp);
     // Clear the right side.
     if rclear <> 0 then begin
      filldword(destp^, rclear, 0);
      inc(destp, rclear * 4);
     end;
    end;

    // Check all choices on this row, if any, adjust choice rects by lclear.
    if lclear <> 0 then begin
     y := choiceindex;
     while y <> 0 do begin
      dec(y);
      with choicematic.showlist[y] do
      if sly1p = totalsizeyp then begin
       inc(slx1p, lclear);
       inc(slx2p, lclear);
      end;
     end;
    end;

    rowsizexp := 0;
    inc(totalsizeyp, lineheightp);
   end;
  end;

  procedure stashspace(widthp : dword); inline;
  // Adds the given width of pixels of empty space to the row.
  var writep : pointer;
      skipw, y : dword;
  begin
   with TBox[boxnum] do begin
    writep := rowbuf + rowsizexp * 4;
    skipw := contentwinsizexp * 4;
    for y := fontheightp - 1 downto 0 do begin
     filldword(writep^, widthp, 0);
     inc(writep, skipw);
    end;
    inc(rowsizexp, widthp);
   end;
  end;

  procedure stashtext; inline;
  // Appends the SDL-provided text surface to the current row.
  var srcp, basep, writep : pointer;
      x, y, rowendskip : dword;
      a : byte;
  begin
   with TBox[boxnum] do begin
    srcp := txtsurface^.pixels;
    basep := rowbuf + rowsizexp * 4;
    rowendskip := (4 - (txtsurface^.w and 3)) and 3;
    for y := 0 to txtsurface^.h - 1 do begin
     writep := basep;
     for x := txtsurface^.w - 1 downto 0 do begin
      case byte(srcp^) of
        0: begin dword(writep^) := 0; inc(writep, 4); end;
        $FF: begin
         dword(writep^) := dword(textcoloramul);
         inc(writep, 4);
        end;
        else begin
         a := (byte(srcp^) * runcolor.a) div 255;
         byte(writep^) := runcolor.b * a div 255; inc(writep);
         byte(writep^) := runcolor.g * a div 255; inc(writep);
         byte(writep^) := runcolor.r * a div 255; inc(writep);
         byte(writep^) := a; inc(writep);
        end;
      end;
      inc(srcp);
     end;
     inc(basep, contentwinsizexp * 4);
     inc(srcp, rowendskip);
    end;
    inc(rowsizexp, dword(txtsurface^.w));
   end;
  end;

  procedure endchoicerun;
  begin
   with TBox[boxnum] do begin
    if (rowsizexp <> 0)
    and (choiceindex <> 0)
    and (choiceindex <= dword(length(choicematic.showlist))) then
    with choicematic.showlist[choiceindex - 1] do begin
     if rowsizexp > slx2p then slx2p := rowsizexp;
     sly2p := totalsizeyp + lineheightp;
     //log('showlist '+strdec(dword(choiceindex-1))+' end: '+strdec(rowsizexp) + ','+strdec(dword(totalsizeyp + lineheightp)));
    end;
   end;
  end;

  procedure newcolor(colval : dword); inline;
  // Selects a new text color.
  begin
   dword(runcolor) := colval;
   dword(textcoloramul) := colval;
   textcoloramul.b := textcoloramul.b * textcoloramul.a div 255;
   textcoloramul.g := textcoloramul.g * textcoloramul.a div 255;
   textcoloramul.r := textcoloramul.r * textcoloramul.a div 255;
  end;

begin
 with TBox[boxnum] do begin
  // Make sure the content buffer is suitably-sized.
  contentfullbufsize := contentwinsizexp * contentfullheightp * 4;
  if (contentfullbufsize > contentfullbufmaxsize)
  or (contentfullbufsize * 8 < contentfullbufmaxsize) then begin
   // Adjust size in 8k chunks, with 1-2 chunks for headroom.
   contentfullbufmaxsize := (contentfullbufsize + 16384) and $FFFFE000;
   freemem(contentfullbuf); contentfullbuf := NIL;
   getmem(contentfullbuf, contentfullbufmaxsize);
  end;

  // Make sure the intermediary row buffer is suitably-sized.
  rowbufsize := contentwinsizexp * fontheightp * 4;
  if (rowbufsize > rowbufmaxsize) or (rowbufsize * 16 < rowbufmaxsize) then begin
   // Adjust size in 8k chunks, with 1-2 chunks for headroom.
   rowbufmaxsize := (rowbufsize + 16384) and $FFFFE000;
   freemem(rowbuf); rowbuf := NIL;
   getmem(rowbuf, rowbufmaxsize);
  end;

  rowsizexp := 0; totalsizeyp := 0; choiceindex := 0;
  runalign := style.textalign;
  destp := contentfullbuf;

  if txtlength <> 0 then begin
   // Make sure there's at least one byte of space beyond the end of the
   // content string, for a terminating null byte.
   if txtlength >= dword(length(txtcontent)) then setlength(txtcontent, txtlength + 8);

   breakindex := 0; escindex := 0; txtofs := 0;
   runchoice := FALSE;
   color1.r := $FF; color1.g := $FF; color1.b := $FF; color1.a := $FF;
   color2.r := 0; color2.g := 0; color2.b := 0; color2.a := 0;
   newcolor(dword(style.textcolor));
   TTF_SetFontStyle(fonth, 0);

   repeat
    // Check for linebreaks at current txt offset.
    while (breakindex < txtlinebreakcount)
    and (txtlinebreaklist[breakindex] = txtofs)
    do begin
     if runchoice then endchoicerun;
     inc(breakindex);
     finaliserow;
    end;

    // Check for escape codes at current txt offset.
    while (escindex < txtescapecount)
    and (txtescapelist[escindex].escapeofs = txtofs)
    do begin
     case txtescapelist[escindex].escapecode of
       byte('B'): TTF_SetFontStyle(fonth, TTF_STYLE_BOLD);
       byte('b'): TTF_SetFontStyle(fonth, 0);
       byte('c'): newcolor(txtescapelist[escindex].escapedata);
       byte('d'): newcolor(dword(style.textcolor));
       byte('L'): runalign := 0;
       byte('C'): runalign := 1;
       byte('R'): runalign := 2;
       byte(':'): ;
       byte('?'): begin
        // Choice item! Calculate how many pixels to tab ahead.
        ivar := rowsizexp + choicematic.colwidthp - 1;
        dec(ivar, ivar mod choicematic.colwidthp + rowsizexp);
        if (ivar <> 0) and (rowsizexp + ivar < contentwinsizexp)
        then stashspace(ivar);
        // Remember the start coordinate of this choice rect.
        if choiceindex < dword(length(choicematic.showlist)) then
        with choicematic.showlist[choiceindex] do begin
         slx1p := rowsizexp;
         slx2p := rowsizexp;
         sly1p := totalsizeyp;
         sly2p := totalsizeyp;
         //log('showlist '+strdec(choiceindex)+' begin: '+strdec(rowsizexp)+','+strdec(totalsizeyp));
         inc(choiceindex);
         runchoice := TRUE;
        end;
       end;
       byte('.'): begin
        endchoicerun;
        runchoice := FALSE;
       end;
     end;
     inc(escindex);
    end;

    // Is this the end of the text?
    if txtofs = txtlength then break;

    // Calculate the distance to the next escape, linebreak, or end of text.
    txtmark := txtlength;
    if (breakindex < txtlinebreakcount)
    and (txtlinebreaklist[breakindex] < txtmark)
    then txtmark := txtlinebreaklist[breakindex];
    if (escindex < txtescapecount)
    and (txtescapelist[escindex].escapeofs < txtmark)
    then txtmark := txtescapelist[escindex].escapeofs;

    // Render text up to the next txtmark.
    luggage := txtcontent[txtmark];
    txtcontent[txtmark] := 0;
    txtsurface := TTF_RenderUTF8_Shaded(fonth, @txtcontent[txtofs], color1, color2);
    txtcontent[txtmark] := luggage;
    if txtsurface = NIL then begin
     LogError('TTF_RenderUTF8 fail: ' + TTF_GetError);
     break;
    end;
    stashtext;
    SDL_FreeSurface(txtsurface);

    txtofs := txtmark;
   until FALSE;
  end;
  finaliserow;

  if (choicematic.active) and (boxnum = choicematic.choicebox) then begin
   // Add margins to the choice coords.
   ivar := choicematic.showcount;
   while ivar <> 0 do begin
    dec(ivar);
    with choicematic.showlist[ivar] do begin
     inc(slx1p, marginleftp - style.outlinemarginleftp);
     inc(slx2p, marginleftp + style.outlinemarginrightp);
     inc(sly1p, margintopp - style.outlinemargintopp);
     inc(sly2p, margintopp + style.outlinemarginbottomp);
    end;
   end;
  end;
 end;
end;

procedure BuildBoxBase(boxnum : dword; minibase : boolean);
// Draws the base image for the given box, at the box's current size.
// This includes a gradient background, a stretched texture, bevelled edges,
// and frame decorations.
// If minibase is true, the base image is drawn at a reduced rendering size,
// and saved as the final image.
var bufp, runp : pointer;
    ivar, jvar, kvar, lvar, mvar, nvar : dword;
    basesizexp, basesizeyp : dword;
    PNGindex, gfxindex : dword;
    leftcolor, rightcolor : RGBquad;
    tempbmp : bitmaptype;
    clipsi : blitstruct;

  procedure scalebox(srcx1, srcy1, srcx2, srcy2, towidth, toheight, destx1, desty1, destx2, desty2 : longint);
  // Lifts the source rectangle from gfxlist[gfxindex].bitmap^, resizes it
  // to a new width/height, then stretches or tiles it onto basebuf^ over the
  // given destination rectangle.
  var srcp, destp : pointer;
      srcw, destw, y : dword;
  begin
   // safety
   if (destx2 <= destx1) or (desty2 <= desty1) then exit;
   // Get the source rectangle into tempbmp.
   tempbmp.sizex := srcx2 - srcx1;
   tempbmp.sizey := srcy2 - srcy1;
   srcw := gfxlist[gfxindex].sizexp * 4;
   destw := tempbmp.sizex * 4;
   getmem(tempbmp.image, destw * tempbmp.sizey);
   srcp := gfxlist[gfxindex].bitmap + srcy1 * longint(srcw) + srcx1 * 4;
   destp := tempbmp.image;
   y := tempbmp.sizey;
   while y <> 0 do begin
    dec(y);
    move(srcp^, destp^, destw);
    inc(srcp, srcw);
    inc(destp, destw);
   end;
   // Stretching or tiling?
   if TBox[boxnum].style.texturetype = 1 then begin
    // Stretching mode! Resize directly to target rectangle size.
    mcg_ScaleBitmap(@tempbmp, destx2 - destx1, desty2 - desty1);
    y := tempbmp.memformat;
    if TBox[boxnum].style.basefill = 0 then y := 0;
    with clipsi do begin
     srcp := tempbmp.image;
     destp := bufp + (desty1 * longint(basesizexp) + destx1) * 4;
     copywidth := tempbmp.sizex;
     copyrows := tempbmp.sizey;
     srcskipwidth := 0;
     destskipwidth := (basesizexp - copywidth) * 4;
    end;
    if y = 0 then DrawRGB24(@clipsi) else
    if TBox[boxnum].style.textureblendmode = BLENDMODE_HARDLIGHT
    then DrawRGBA32hardlight(@clipsi)
    else DrawRGBA32(@clipsi);
   end
   else begin
    // Tiling mode! Resize to intermediate size.
    mcg_ScaleBitmap(@tempbmp, towidth, toheight);
    {$note Implement box texture tiling}
   end;
   // Clean up.
   freemem(tempbmp.image); tempbmp.image := NIL;
  end;

begin
 with TBox[boxnum] do begin

  // Make sure the base and final image buffers are suitably-sized for the
  // biggest potential render size.
  basesizexp := boxsizexp;
  basesizeyp := boxsizeyp;
  if boxsizexp_r > basesizexp then basesizexp := boxsizexp_r;
  if boxsizeyp_r > basesizeyp then basesizeyp := boxsizeyp_r;
  if style.texturetype <> 0 then begin
   ivar := style.textureleftp + style.texturerightp;
   if ivar > basesizexp then basesizexp := ivar;
   ivar := style.texturetopp + style.texturebottomp;
   if ivar > basesizeyp then basesizeyp := ivar;
  end;

  basebufsize := basesizexp * basesizeyp * 4;
  if (basebufsize > basebufmaxsize) or (basebufsize * 8 < basebufmaxsize) then begin
   // Adjust size in 8k chunks, with 1-2 chunks for headroom.
   basebufmaxsize := (basebufsize + 16384) and $FFFFE000;
   freemem(basebuf); basebuf := NIL;
   freemem(finalbuf); finalbuf := NIL;
   getmem(basebuf, basebufmaxsize);
   getmem(finalbuf, basebufmaxsize);
  end;

  // If the box base size is changing rapidly, e.g. appearing/vanishing, then
  // we can just render a resized version directly into the final buffer,
  // since there won't be text on it anyway.
  if minibase then begin
   bufp := finalbuf;
   basesizexp := boxsizexp_r;
   basesizeyp := boxsizeyp_r;
  end else begin
   bufp := basebuf;
   basesizexp := boxsizexp;
   basesizeyp := boxsizeyp;
  end;

  // safety
  if (basesizexp = 0) or (basesizeyp = 0) then exit;

  // The box texture imposes a minimum size for the box for rendering
  // purposes. If a texture is being used, we may have to render the box base
  // at a higher resolution, and only resize it to the exact pixel size at
  // the end.
  if style.texturetype <> 0 then begin
   ivar := style.textureleftp + style.texturerightp;
   if ivar > basesizexp then basesizexp := ivar;
   ivar := style.texturetopp + style.texturebottomp;
   if ivar > basesizeyp then basesizeyp := ivar;
  end;

  // === Background Gradient ===

  if style.basefill <> 0 then begin
   // Flat fill if requested, or if the base size is only 1px in either
   // dimension which makes gradients impossible.
   if (style.basefill = 1)
   or (basesizexp = 1) or (basesizeyp = 1) then
    filldword(bufp^, (basesizexp * basesizeyp), dword(style.basecolor[0]))
   else begin
    // Gradient fill between 4 colors in the corners.
    runp := bufp;
    kvar := basesizeyp - 1;
    for jvar := kvar downto 0 do begin
     nvar := kvar - jvar;
     {$note This should be done in linear RGB}
     leftcolor.b := (style.basecolor[0].b * jvar + style.basecolor[2].b * nvar) div kvar;
     leftcolor.g := (style.basecolor[0].g * jvar + style.basecolor[2].g * nvar) div kvar;
     leftcolor.r := (style.basecolor[0].r * jvar + style.basecolor[2].r * nvar) div kvar;
     leftcolor.a := (style.basecolor[0].a * jvar + style.basecolor[2].a * nvar) div kvar;
     rightcolor.b := (style.basecolor[1].b * jvar + style.basecolor[3].b * nvar) div kvar;
     rightcolor.g := (style.basecolor[1].g * jvar + style.basecolor[3].g * nvar) div kvar;
     rightcolor.r := (style.basecolor[1].r * jvar + style.basecolor[3].r * nvar) div kvar;
     rightcolor.a := (style.basecolor[1].a * jvar + style.basecolor[3].a * nvar) div kvar;
     nvar := basesizexp - 1;
     for ivar := nvar downto 0 do begin
      lvar := nvar - ivar;
      byte(runp^) := (leftcolor.b * ivar + rightcolor.b * lvar) div nvar;
      inc(runp);
      byte(runp^) := (leftcolor.g * ivar + rightcolor.g * lvar) div nvar;
      inc(runp);
      byte(runp^) := (leftcolor.r * ivar + rightcolor.r * lvar) div nvar;
      inc(runp);
      byte(runp^) := (leftcolor.a * ivar + rightcolor.a * lvar) div nvar;
      inc(runp);
     end;
    end;
   end;
   // The generated baseimage must use pre-mul alpha, so pre-multiply it!
   {$note Do premul directly at generation, above this}
   mcg_PremulRGBA32(bufp, basesizexp * basesizeyp);
  end;

  // === Box Texture ===

  if style.texturetype <> 0 then begin
   // Check if the texture exists.
   PNGindex := GetPNG(style.texturename);
   if PNGindex = 0 then begin
    LogError('BuildBoxBase: texture graphic doesn''t exist: ' + style.texturename);
    style.texturetype := 0;
    exit;
   end;
   // Get the texture in its original resolution. This is needed to ensure
   // the edges are pixel-perfect.
   gfxindex := GetGfx(style.texturename, PNGlist[PNGindex].origsizexp, PNGlist[PNGindex].origframeheightp);
   tempbmp.memformat := gfxlist[gfxindex].bitflag shr 7; // RGB/RGBA
   tempbmp.bitdepth := 8;

   // If all texture edges are 0, the entire texture can be stretched.
   if (style.textureleftp or style.texturetopp or style.texturerightp or style.texturebottomp) = 0 then
   scalebox(0, 0, PNGlist[PNGindex].origsizexp, PNGlist[PNGindex].origframeheightp,
     style.texturesizexp, style.texturesizeyp,
     0, 0, basesizexp, basesizeyp)
   else begin
    // The texture edges need to be stretched separately.
    {                                       }
    {           0  leftp  ivar\jvar  sizexp }
    {         0 +--------------------+      }
    {           |    |        |      |      }
    {      topp |----+--------+------|      }
    {           |    |        |      |      }
    { kvar\lvar |----+--------+------| nvar }
    {           |    |        |      |      }
    {    sizeyp +--------------------+ base }
    {                        mvar   sizexyp }
    {                                       }

    ivar := PNGlist[PNGindex].origsizexp - style.texturerightorigp;
    jvar := style.texturesizexp - style.texturerightp;
    kvar := PNGlist[PNGindex].origframeheightp - style.texturebottomorigp;
    lvar := style.texturesizeyp - style.texturebottomp;
    mvar := basesizexp - style.texturerightp;
    nvar := basesizeyp - style.texturebottomp;
    // scalebox(source rect, size adjusted to viewport, target rect)
    // For each box area, we lift the area from the original size, resize it
    // from its original resolution to the box's viewport, and then stretch
    // or tile the resized area to cover the target rectangle.

    // top left
    scalebox(0, 0, style.textureleftorigp, style.texturetoporigp,
      style.textureleftp, style.texturetopp,
      0, 0, style.textureleftp, style.texturetopp);
    // top middle
    scalebox(style.textureleftorigp, 0, ivar, style.texturetoporigp,
      jvar - style.textureleftp, style.texturetopp,
      style.textureleftp, 0, mvar, style.texturetopp);
    // top right
    scalebox(ivar, 0, PNGlist[PNGindex].origsizexp, style.texturetoporigp,
      style.texturerightp, style.texturetopp,
      mvar, 0, basesizexp, style.texturetopp);
    // left middle
    scalebox(0, style.texturetoporigp, style.textureleftorigp, kvar,
      style.textureleftp, lvar - style.texturetopp,
      0, style.texturetopp, style.textureleftp, nvar);
    // center
    scalebox(style.textureleftorigp, style.texturetoporigp, ivar, kvar,
      jvar - style.textureleftp, lvar - style.texturetopp,
      style.textureleftp, style.texturetopp, mvar, nvar);
    // right middle
    scalebox(ivar, style.texturetoporigp, PNGlist[PNGindex].origsizexp, kvar,
      style.texturerightp, lvar - style.texturetopp,
      mvar, style.texturetopp, basesizexp, nvar);
    // bottom left
    scalebox(0, kvar, style.textureleftorigp, PNGlist[PNGindex].origframeheightp,
      style.textureleftp, style.texturebottomp,
      0, nvar, style.textureleftp, basesizeyp);
    // bottom middle
    scalebox(style.textureleftorigp, kvar, ivar, PNGlist[PNGindex].origframeheightp,
      jvar - style.textureleftp, style.texturebottomp,
      style.textureleftp, nvar, mvar, basesizeyp);
    // bottom right
    scalebox(ivar, kvar, PNGlist[PNGindex].origsizexp, PNGlist[PNGindex].origframeheightp,
      style.texturerightp, style.texturebottomp,
      mvar, nvar, basesizexp, basesizeyp);
   end;
  end;

  // === Edge Bevel ===

  if style.dobevel <> 0 then begin
   // Use a bevel size of half of the smallest margin.
   nvar := marginleftp;
   if marginrightp < nvar then nvar := marginrightp;
   if margintopp < nvar then nvar := margintopp;
   if marginbottomp < nvar then nvar := marginbottomp;
   nvar := nvar shr 1;
   // safety
   if nvar > basesizexp shr 1 then nvar := basesizexp shr 1;
   if nvar > basesizeyp shr 1 then nvar := basesizeyp shr 1;
   {$note Clean up beveller}
       // Draw the bevel
       while nvar <> 0 do begin
        dec(nvar);
        // horizontal lines
        kvar := (nvar * basesizexp + nvar) shl 2;
        jvar := kvar + ((basesizeyp - nvar shl 1 - 1) * basesizexp) shl 2;
        ivar := basesizexp - nvar shl 1;
        while ivar <> 0 do begin
         dec(ivar);
         // Alpha 25% closer to $FF
         byte((bufp + kvar + 3)^) := (byte((bufp + kvar + 3)^) * 3 + $FF) shr 2;
         byte((bufp + jvar + 3)^) := (byte((bufp + jvar + 3)^) * 3 + $FF) shr 2;
         // Top edge 25% closer to $FF, bottom edge down 25%.
         byte((bufp + kvar)^) := (byte((bufp + kvar)^) * 3 + $FF) shr 2;
         dec(byte((bufp + jvar)^), byte((bufp + jvar)^) shr 2);
         inc(kvar); inc(jvar);
         byte((bufp + kvar)^) := (byte((bufp + kvar)^) * 3 + $FF) shr 2;
         dec(byte((bufp + jvar)^), byte((bufp + jvar)^) shr 2);
         inc(kvar); inc(jvar);
         byte((bufp + kvar)^) := (byte((bufp + kvar)^) * 3 + $FF) shr 2;
         dec(byte((bufp + jvar)^), byte((bufp + jvar)^) shr 2);
         inc(kvar, 2); inc(jvar, 2);
        end;
        // vertical lines
        dec(kvar, 4);
        jvar := kvar - (basesizexp - nvar shl 1 - 1) shl 2;
        ivar := basesizeyp - nvar shl 1;
        while ivar <> 0 do begin
         dec(ivar);
         // Alpha 12.5% closer to $FF
         byte((bufp + jvar + 3)^) := (byte((bufp + jvar + 3)^) * 7 + $FF) shr 3;
         byte((bufp + kvar + 3)^) := (byte((bufp + kvar + 3)^) * 7 + $FF) shr 3;
         // Left edge 12.5% closer to $FF, right edge down 12.5%.
         byte((bufp + jvar + 0)^) := (byte((bufp + jvar + 0)^) * 7 + $FF) shr 3;
         dec(byte((bufp + kvar + 0)^), byte((bufp + kvar + 0)^) shr 3);
         byte((bufp + jvar + 1)^) := (byte((bufp + jvar + 1)^) * 7 + $FF) shr 3;
         dec(byte((bufp + kvar + 1)^), byte((bufp + kvar + 1)^) shr 3);
         byte((bufp + jvar + 2)^) := (byte((bufp + jvar + 2)^) * 7 + $FF) shr 3;
         dec(byte((bufp + kvar + 2)^), byte((bufp + kvar + 2)^) shr 3);
         inc(kvar, basesizexp shl 2); inc(jvar, basesizexp shl 2);
        end;
       end;
  end;

  // === Frame Decorations ===
  if length(style.decorlist) <> 0 then
   for ivar := 0 to high(style.decorlist) do with style.decorlist[ivar] do begin
    PNGindex := GetPNG(decorname);
    if PNGindex = 0 then begin
     LogError('BuildBoxBase: decor graphic doesn''t exist: ' + decorname);
     setlength(style.decorlist, 0);
     continue;
    end;
    // Calculate the decoration size.
    if decorsizex = 0
    then decorsizexp := PNGlist[PNGindex].origsizexp * viewport[inviewport].viewportsizexp div PNGlist[PNGindex].origresx
    else decorsizexp := (decorsizex * viewport[inviewport].viewportsizexp + 16384) shr 15;
    if decorsizey = 0
    then decorsizeyp := PNGlist[PNGindex].origframeheightp * viewport[inviewport].viewportsizeyp div PNGlist[PNGindex].origresy
    else decorsizeyp := (decorsizey * viewport[inviewport].viewportsizeyp + 16384) shr 15;
    // Restrict decorations to the base buffer size at most.
    if decorsizexp > basesizexp then decorsizexp := basesizexp;
    if decorsizeyp > basesizeyp then decorsizeyp := basesizeyp;
    // Get the appropriately-sized decoration.
    gfxindex := GetGfx(decorname, decorsizexp, decorsizeyp);
    // Calculate the decoration location.
    longint(jvar) := (dword(decorlocx) * basesizexp + 16384) shr 15 - (longint(decorsizexp) * decoranchorx) shr 15;
    longint(kvar) := (dword(decorlocy) * basesizeyp + 16384) shr 15 - (longint(decorsizeyp) * decoranchory) shr 15;
    // Restrict the decoration to the base buffer.
    if longint(jvar) < 0 then jvar := 0
    else if jvar + decorsizexp > basesizexp then jvar := basesizexp - decorsizexp;
    if longint(kvar) < 0 then kvar := 0
    else if kvar + decorsizeyp > basesizeyp then kvar := basesizeyp - decorsizeyp;
    // Blit the decoration.
    with clipsi do begin
     srcp := gfxlist[gfxindex].bitmap;
     destp := bufp + (kvar * basesizexp + jvar) * 4;
     copywidth := decorsizexp;
     copyrows := decorsizeyp;
     srcskipwidth := 0;
     destskipwidth := (basesizexp - copywidth) * 4;
    end;
    DrawRGBA32(@clipsi);
   end;

  // Final size check. If we rendered the base at a higher size than
  // requested due to the texture edges, then resize to the exact requested
  // size now.
  if minibase then begin
   ivar := boxsizexp_r;
   jvar := boxsizeyp_r;
  end else begin
   ivar := boxsizexp;
   jvar := boxsizeyp;
  end;
  if (ivar <> basesizexp) or (jvar <> basesizeyp) then begin
   tempbmp.memformat := 1; // RGBA
   tempbmp.bitdepth := 8;
   tempbmp.sizex := basesizexp;
   tempbmp.sizey := basesizeyp;
   lvar := basesizexp * basesizeyp * 4;
   getmem(tempbmp.image, lvar);
   move(bufp^, tempbmp.image^, lvar);
   mcg_ScaleBitmap(@tempbmp, ivar, jvar);
   move(tempbmp.image^, bufp^, ivar * jvar * 4);
   freemem(tempbmp.image); tempbmp.image := NIL;
  end;

 end;
end;

procedure BuildFinalBox(boxnum : dword);
// Copies the base image and scrolled content window on top of each other as
// the final box image.
var clipsi : blitstruct;
begin
 with TBox[boxnum] do begin
  // If the rendering size is not the final size, the base image was already
  // drawn directly on the final buffer, so there's nothing to do.
  if (boxsizexp_r <> boxsizexp) or (boxsizeyp_r <> boxsizeyp) then exit;

  move(basebuf^, finalbuf^, basebufsize);
  // Check if the box is scrolled beyond the end of the buffer.
  if contentwinscrollofsp >= contentfullheightp then exit;
  // Blit the content over the base image.
  with clipsi do begin
   srcp := contentfullbuf + contentwinscrollofsp * contentwinsizexp * 4;
   destp := finalbuf + (margintopp * boxsizexp + marginleftp) * 4;
   copywidth := contentwinsizexp;
   copyrows := contentfullheightp - contentwinscrollofsp;
   if copyrows > contentwinsizeyp then copyrows := contentwinsizeyp;
   srcskipwidth := 0;
   destskipwidth := (boxsizexp - copywidth) * 4;
  end;
  DrawRGBA32(@clipsi);
 end;
end;

// ------------------------------------------------------------------

{$include sakubox-all.pas}
