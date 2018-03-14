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

// Image post-processing functions.

function Composite(namu1, namu2 : UTF8string; action : byte) : dword;
// Checks if namu1 and namu2 both exist in newgfxlist[], a list of graphics
// converted just earlier. If yes, opens both PNGs, combines them according
// to the action value, and writes the result over namu1, deleting namu2.
// Possible actions:
// 0 - namu2 added under namu1, images must be of same width
// 1 - namu1 with alpha imprinted over namu2
// 2 - namu2 added on right side of namu1, must be same height
// 3 - namu2 added above namu1, images must be of same width
// $40 bit clear - use namu1's palette
// $40 bit set - use namu2's palette
// Also, if $80 bit is set, namu2 will not be deleted.
// Returns PNGlist[] index of namu1 for convenience.
var loader : TFileLoader;
    ivar, jvar, kvar, lvar, png1, png2 : dword;
    poku : pointer;
    image1, image2 : bitmaptype;
    txt : UTF8string;
    bvar : byte;
begin
 mcg_AutoConvert := 1; // don't autoconvert to truecolor
 Composite := $FFFF;
 png1 := seeknewgfx(namu1); if png1 >= newgfxcount then exit;
 png2 := seeknewgfx(namu2); if png2 >= newgfxcount then exit;
 write(stdout, 'Compositing: ');
 case action and $F of
  0: writeln(stdout, namu1, ' above ', namu2);
  1: writeln(stdout, namu1, ' layered on ', namu2);
  2: writeln(stdout, namu1, ' on left side of ', namu2);
  3: writeln(stdout, namu1, ' below ', namu2);
 end;
 image1.image := NIL;
 image2.image := NIL;
 png1 := seekpng(namu1, FALSE);
 png2 := seekpng(namu2, FALSE);

 loader := TFileLoader.Open(decomp_param.outputdir + 'gfx' + DirectorySeparator + namu1 + '.png');
 try
  ivar := mcg_PNGtoMemory(loader.readp, loader.size, @image1);
  if ivar <> 0 then begin
   PrintError(mcg_errortxt); mcg_ForgetImage(@image1); exit;
  end;
 finally
  if loader <> NIL then loader.free;
  loader := NIL;
 end;

 loader := TFileLoader.Open(decomp_param.outputdir + 'gfx' + DirectorySeparator + namu2 + '.png');
 try
  ivar := mcg_PNGtoMemory(loader.readp, loader.size, @image2);
  if ivar <> 0 then begin
   PrintError(mcg_errortxt);
   mcg_ForgetImage(@image1); mcg_ForgetImage(@image2); exit;
  end;
 finally
  if loader <> NIL then loader.free;
  loader := NIL;
 end;

 bvar := 0;
 for ivar := high(image1.palette) downto 0 do // grab the transparent index
  if image1.palette[ivar].a = 0 then bvar := ivar;

 txt := '';
 case action and $3F of
  0: begin
      // namu1 on top of namu2
      if image1.sizex <> image2.sizex then txt := 'Images not same width'
      else begin
       ivar := image1.sizex * image1.sizey;
       inc(image1.sizey, image2.sizey);
       reallocmem(image1.image, image1.sizex * image1.sizey);
       move(image2.image^, (image1.image + ivar)^, image2.sizex * image2.sizey);
      end;
     end;
  1: begin
      // namu1 alpha-blitted over namu2
      longint(ivar) :=
        (PNGlist[png1].origofsyp - PNGlist[png2].origofsyp) * image2.sizex
      + (PNGlist[png1].origofsxp - PNGlist[png2].origofsxp);
      if ivar >= image2.sizex * image2.sizey then ivar := 0; // overflow cap
      lvar := 0;
      // ivar = destination offset [image2], lvar = source offset [image1]

      for kvar := image1.sizey - 1 downto 0 do begin
       for jvar := image1.sizex - 1 downto 0 do begin
        if byte((image1.image + lvar)^) <> bvar then
         byte((image2.image + ivar)^) := byte((image1.image + lvar)^);
        inc(ivar); inc(lvar);
       end;
       inc(longint(ivar), image2.sizex - image1.sizex);
      end;
      freemem(image1.image); image1.image := image2.image; image2.image := NIL;
      image1.sizex := image2.sizex; image1.sizey := image2.sizey;
      if action and $40 = 0 then image1.palette := image2.palette;
      PNGlist[png1].origofsxp := PNGlist[png2].origofsxp;
      PNGlist[png1].origofsyp := PNGlist[png2].origofsyp;
     end;
  2: begin
      // namu1 on left side of namu2
      if image1.sizey <> image2.sizey then txt := 'Images not same height'
      else begin
       ivar := image1.sizex;
       inc(image1.sizex, image2.sizex);
       lvar := image1.sizex * image1.sizey; // dest ofs
       reallocmem(image1.image, lvar);
       for jvar := image1.sizey - 1 downto 0 do begin
        dec(lvar, image2.sizex);
        move((image2.image + image2.sizex * jvar)^, (image1.image + lvar)^, image2.sizex);
        dec(lvar, ivar);
        move((image1.image + ivar * jvar)^, (image1.image + lvar)^, ivar);
       end;
      end;
     end;
  3: begin
      // namu2 on top of namu1
      if image1.sizex <> image2.sizex then txt := 'Images not same width'
      else begin
       // set the offset so the bottom half is by default shown first
       PNGlist[png1].origofsyp := -image1.sizey;
       // combine the images
       ivar := image2.sizex * image2.sizey;
       inc(image2.sizey, image1.sizey);
       reallocmem(image2.image, image2.sizex * image2.sizey);
       move(image1.image^, (image2.image + ivar)^, image1.sizex * image1.sizey);
       mcg_ForgetImage(@image1); image1 := image2; image2.image := NIL;
      end;
     end;
  else txt := 'Unknown compositing action';
 end;
 mcg_ForgetImage(@image2);

 if txt <> '' then begin
  mcg_ForgetImage(@image1);
  PrintError(txt);
  exit;
 end;

 // Save the result over the first original
 Composite := png1;
 poku := NIL;
 jvar := mcg_MemorytoPNG(@image1, @poku, @ivar); // build a PNG in poku^
 mcg_ForgetImage(@image1);
 if jvar <> 0 then begin
  PrintError(mcg_errortxt); exit;
 end;
 SaveFile(decomp_param.outputdir + 'gfx' + DirectorySeparator + namu1 + '.png', poku, ivar);
 freemem(poku); poku := NIL;
 if txt <> '' then begin
  mcg_ForgetImage(@image1);
  PrintError(txt);
  exit;
 end;

 {$ifdef bonk}
 // Remove the other original from PNGlist[] and newgfxlist[], erase the file
 if action and $80 = 0 then begin
  while png2 < PNGcount do begin
   PNGlist[png2] := PNGlist[png2 + 1];
   inc(png2);
  end;
  dec(PNGcount);

  png2 := FindPNG(namu2);
  while png2 + 1 < gfxprocessed do begin
   filuseeker[png2] := filuseeker[png2 + 1];
   inc(png2);
  end;
  dec(gfxprocessed);

  assign(outfilu, decomp_param.outputdir + 'gfx' + DirectorySeparator + namu2 + '.png');
  erase(outfilu);
 end;
 {$endif}
end;

procedure CompositeGraphics;
// Some games have a single big image broken into two halves, or a mostly
// transparent layer meant to be drawn over another image at run-time.
// If handled as designed, beautification would result in extra artifacts.
// Therefore, images must be put together before beautification.
begin
 // The filenames must be in uppercase.
 //
 // 0: image1 above, image2 below
 // 1: image1 superimposed on image2
 // 2: image1 left, image2 right
 // 3: image1 below, image2 above, set PNGlist[].ofsy to init show lower half
 // $80: don't delete image2 afterward
 case game of
  gid_ANGELSCOLLECTION1: begin
    Composite('GPP_0C','GPP_0A',3);
    Composite('T2_08','T2_09',0);
    Composite('T3_14','T3_15',0);
    Composite('T3_44','T3_45',0);
    Composite('T3_62','T3_63',0);
  end;
  gid_ANGELSCOLLECTION2: begin
    Composite('O2_006','O2_007',0);
    Composite('O3_006','O3_007',0);
    Composite('T3_025','T3_026',2);
    Composite('T3_039','T3_040',$80);
    Composite('T3_041','T3_040',$80);
    Composite('T3_043','T3_044',2);
    Composite('T4_076','T4_075',0);
  end;
  gid_DEEP: begin
    Composite('DH_S01_A','DH_S01_B',0);
    Composite('DH_S02_A','DH_S02_B',0);
    Composite('DH_S03_A','DH_S03_B',0);
    Composite('DH_S04_A','DH_S04_B',0);
    Composite('DH_S5J_A','DH_S5J_B',0);
    Composite('DH_S5K_A','DH_S5K_B',0);
    Composite('DH_S5M_A','DH_S5M_B',0);
    Composite('DH_S5S_A','DH_S5S_B',0);
    Composite('DH_S06_A','DH_S06_B',0);
    Composite('DH_S07_A','DH_S07_B',0);
    Composite('DH_S08_A','DH_S08_B',0);
    Composite('DH_S09_A','DH_S09_B',0);
  end;
  gid_FROMH: begin
    // Composite('FE_007G','FE_007',$81); // looks better separately
    Composite('FE_011G','FE_011',$81);
    Composite('FH_010G','FH_010',$81);
    Composite('FH_022G','FH_022',$81);
    // Composite('FH_029G','FH_029',$81); // complex, check scripting first
    Composite('FT_27','FB_007',$81);
    Composite('FT_28','FB_007',$81);
  end;
  gid_MAJOKKO: begin
    Composite('OPA','OPB',0);
    Composite('KE_035_1','KE_035_2',0);
    Composite('KE_036_1','KE_036_2',0);
    Composite('KE_039_1','KE_039_2',0);
    Composite('KE_044_1','KE_044_2',0);
    Composite('KE_051_1','KE_051_2',0);
    Composite('KE_052_1','KE_052_2',0);
    Composite('KE_065_1','KE_065_2',0);
    Composite('KE_069_1','KE_069_2',0);
    Composite('KE_076_1','KE_076_2',0);
  end;
  gid_MAYCLUB, gid_MAYCLUB98: begin
    Composite('A05B','A05A',1);
    Composite('B11B','B11A',1);
    Composite('B11F','B11A',1);
    Composite('BG02','BG01',1);
    Composite('C20B','C20A',1);
    Composite('C20F','C20A',1);
    Composite('C22B','C22A',1);
    Composite('D27C','D27A',1);
    Composite('D27F','D27A',1);
    Composite('D27H','D27A',1);
    Composite('D32B','D32A',1);
    Composite('D33B','D33A',1);
    Composite('E35B','E35A',1);
    Composite('E35E','E35A',1);
    Composite('E35G','E35A',1);
    Composite('G41B','G41A',1);
    Composite('G41C','G41A',1);
    Composite('G41E','G41A',1);
    Composite('G41G','G41A',1);
    Composite('G41H','G41A',1);
    Composite('G43A','G43Z',1);
    Composite('G43B','G43Z',1);
    Composite('G43C','G43Z',1);
    Composite('H47B','H47A',1);
    Composite('H47C','H47A',1);
    Composite('H47G','H47A',1);
    Composite('H49B','H49A',1);
    Composite('H50B','H50A',1);
    Composite('H50C','H50B',1);
    Composite('I54B','I54A',1);
    Composite('I54C','I54A',1);
    Composite('I54D','I54A',1);
    Composite('I54E','I54A',1);
    Composite('I54F','I54A',1);
    Composite('I54H','I54A',1);
    Composite('I55B','I55A',1);
    Composite('Z64N','Z64',$41);
    Composite('Z65N','Z65',$41);
    Composite('Z65Y','Z65N',$41);
    Composite('Z68N','Z68',$41);
    Composite('Z69N','Z69',$41);
    Composite('Z70N','Z70',$41);
  end;
  gid_NOCTURNE, gid_NOCTURNE98: begin
    Composite('01N','001',$41);
    Composite('02N','002',$41);
    Composite('03N','003',$41);
    Composite('04N','004',$41);
    Composite('05N','005',$41);
    Composite('06N','006',$41);
    Composite('07B','07A',1);
    Composite('07N','07A',$41);
    Composite('08N','008',$41);
    Composite('09N','009',$41);
    Composite('10B','10A',1);
    Composite('10N','10A',$41);
    Composite('11N','011',$41);
    Composite('12B','012',1);
    Composite('12N','012',$41);
    Composite('13N','013',$41);
    Composite('14N','014',$41);
    Composite('15N','015',$41);
    Composite('16B','16A',1);
    Composite('17B','17C',1);
    Composite('17A','17B',1);
    Composite('25B','25A',1);
    Composite('25C','25A',1);
    Composite('25E','25A',1);
    Composite('25G','25A',1);
    Composite('2C1','2A1',1);
    Composite('2C2','2A2',1);
    Composite('2D1','2A1',1);
    Composite('2D2','2A2',1);
    Composite('37B','37A',1);
    Composite('37C','37A',1);
    Composite('43B','43A',1);
    Composite('43C','43A',1);
    Composite('43E','43D',1);
    Composite('49N','049',$41);
    Composite('52B','52A',1);
    Composite('52C','52A',1);
    Composite('52D','52A',1);
    Composite('52E','52A',1);
    Composite('54B','54A',1);
    Composite('58B','58A',1);
    Composite('60A','60B',1);
    Composite('60C','60A',1);
    Composite('67B','67A',1);
    Composite('67C','67B',1);
    Composite('79B','79A',1);
    Composite('79C','79A',1);
    Composite('79D','79A',1);
    Composite('7B2','7A2',1);
    Composite('7C2','7A2',1);
    Composite('84B','84A',1);
    Composite('84D','84A',1);
    Composite('86B','86A',1);
    Composite('86C','86B',1);
    Composite('86D','86C',1);
    Composite('96B','96A',1);
    if game = gid_NOCTURNE98 then begin
     Composite('30C','30B',1);
     Composite('30D','30C',1);
    end;
  end;
  gid_SETSUJUU: begin
    Composite('SH_05S','SH_05',$81);
    Composite('SH_30S','SH_30',$81);
    Composite('SH_48S','SH_48',$81);
    Composite('SH_53S','SH_53',$81);
    Composite('SH_58S','SH_58',$81);
    Composite('SH_68S','SH_68',$81);
  end;
  gid_TRANSFER98: begin
    Composite('0001_A','0001_B',0);
    Composite('TH_019','TH_020',0);
    Composite('TH_035','TH_036',0);
    Composite('TH_041','TH_042',2);
    Composite('TH_047','TH_048',0);
    Composite('TH_055','TH_056',0);
    Composite('TH_063','TH_064',0);
    Composite('TH_069','TH_070',0);
    Composite('TH_075','TH_076',0);
    Composite('TH_085','TH_086',0);
    Composite('TH_091','TH_092',0);
    Composite('TH_098','TH_099',0);
    Composite('TH_103','TH_104',0);
    Composite('TH_109','TH_110',2);
    Composite('TH_127','TH_128',0);
    Composite('TH_133','TH_134',0);
  end;
  gid_TASOGARE: begin
    Composite('YB_012G','YB_012',$81);
  end;
  gid_VANISH: begin
    Composite('VOP_002','VOP_001',3);
  end;
 end;
end;

// ------------------------------------------------------------------

procedure ApplyFilter(namu : string);
// Checks if the given graphic file has an associated DTL-file; if not,
// creates a default one for it.
// Then, if images are to be beautified, calls Beautify to auto-process the
// given graphic file.
var image : bitmaptype;
    ivar, jvar, kvar, lvar : dword;
    gfxi : word;
begin
 {$ifdef bonk}
 mcg_AutoConvert := 1; // don't autoconvert to truecolor
 gfxi := seekpng(@namu);
 if gfxi = 0 then exit;
 if LoadFile(projectdir + 'gfx' + DirectorySeparator + namu + '.png') = FALSE then exit;
 fillbyte(image, sizeof(bitmaptype), 0);
 ivar := mcg_PNGtoMemory(loader, @image);
 if ivar <> 0 then begin
  PrintError(mcg_errortxt); mcg_ForgetImage(@image); exit;
 end;

 InitBeautify(namu);

 // Adjust default parameters for close-up images, nominated manually
 ivar := 0;
 case game of
  gid_3SIS, gid_3SIS98: if copy(namu, 1, 3) = 'SE_' then inc(ivar);
  gid_DEEP: if (copy(namu, 1, 4) = 'DH_S') or (copy(namu, 1, 3) = 'DI_') then inc(ivar);
  gid_EDEN: if copy(namu, 1, 3) = 'EE_' then inc(ivar);
  gid_FROMH: if (copy(namu, 1, 3) = 'FE_') or (copy(namu, 1, 3) = 'FH_') or (copy(namu, 1, 3) = 'GRO') then inc(ivar);
  gid_MAJOKKO: if (copy(namu, 1, 3) = 'KE_') or (copy(namu, 1, 2) = 'OP') then inc(ivar);
  gid_MARIRIN: if copy(namu, 1, 3) = 'BC' then inc(ivar);
  gid_RUNAWAY, gid_RUNAWAY98: if copy(namu, 1, 3) = 'MH_' then inc(ivar);
  gid_SAKURA, gid_SAKURA98: if copy(namu, 1, 3) = 'AE_' then inc(ivar);
  gid_SETSUJUU: if (copy(namu, 1, 3) = 'SH_') or (copy(namu, 1, 3) = 'SI_') then inc(ivar);
  gid_TRANSFER98: if (copy(namu, 1, 3) = 'TH_') or (copy(namu, 1, 3) = 'TI_') then inc(ivar);
  gid_TASOGARE: if (copy(namu, 1, 3) = 'YE_') or (copy(namu, 1, 3) = 'YH_') then inc(ivar);
  gid_VANISH: if (copy(namu, 1, 3) = 'VE_') or (copy(namu, 1, 3) = 'VH_') then inc(ivar);
 end;
 if ivar <> 0 then begin
  gammacorrect := 113; // closeups generally look better darker
  processHVlines := FALSE; // ... and generally don't have orthogonal lines
 end;

 // Figure out the transparent color index
 xparency := $FF;
 if image.memformat = 5 then begin
  for ivar := high(image.palette) downto 0 do
   if image.palette[ivar].a = 0 then xparency := ivar;
 end;
 // transparent things usually don't have horizontal/vertical lines
 if xparency <> $FF then processHVlines := FALSE;

 // Image frames need to be pushed apart to avoid color leaking. Do this by
 // injecting four transparent pixel rows between all frames.
 if PNGlist[gfxi].framecount > 1 then begin
  if xparency >= dword(length(PNGlist[gfxi].pal)) then begin
   PrintError('Transparent color must be hardcoded in decomp_g!');
  end else begin
   ivar := image.sizey + (PNGlist[gfxi].framecount - 1) * 4;
   getmem(loader, image.sizex * ivar);
   lvar := image.sizex * PNGlist[gfxi].frameheight;
   jvar := PNGlist[gfxi].framecount;
   while jvar <> 0 do begin
    dec(jvar);
    move((image.image + jvar * lvar)^,
         (loader + jvar * image.sizex * (PNGlist[gfxi].frameheight + 4))^,
         lvar);
    if jvar + 1 <> PNGlist[gfxi].framecount then
     fillbyte((loader + jvar * image.sizex * (PNGlist[gfxi].frameheight + 4) + lvar)^, image.sizex * 4, xparency);
   end;
   freemem(image.image); image.image := loader; loader := NIL;
   image.sizey := ivar;
  end;
 end;

 setlength(detaillist, 0);
 Beautify(@image);

 // Image frames should be put together again
 if PNGlist[gfxi].framecount > 1 then begin
  lvar := image.sizex * (3 + image.memformat and 1); // image row byte width
  ivar := lvar * PNGlist[gfxi].frameheight; // frame byte size
  jvar := lvar * (PNGlist[gfxi].frameheight + 4); // frame byte size + 4 rows
  for kvar := 1 to PNGlist[gfxi].framecount - 1 do
   move((image.image + jvar * kvar)^, (image.image + ivar * kvar)^, ivar);
  image.sizey := PNGlist[gfxi].frameheight * PNGlist[gfxi].framecount;

  // Make animation frame edges completely transparent to reduce artifacts
  if image.memformat = 1 then
  for kvar := PNGlist[gfxi].framecount - 1 downto 0 do begin
   jvar := ivar * kvar; // jvar = offset to frame's top left corner
   fillbyte((image.image + jvar)^, lvar, 0); // top edge
   fillbyte((image.image + jvar + ivar - lvar)^, lvar, 0); // bottom edge
  end;
  jvar := 0; ivar := (3 + image.memformat and 1);
  for kvar := image.sizey - 1 downto 0 do begin
   fillbyte((image.image + jvar)^, ivar, 0); // left edge
   inc(jvar, lvar);
   fillbyte((image.image + jvar - ivar)^, ivar, 0);
  end;
 end;

 // Save the result over the original
 jvar := mcg_MemorytoPNG(@image, @loader, @ivar); // build a PNG in loader^
 mcg_ForgetImage(@image);
 if jvar <> 0 then begin
  PrintError(mcg_errortxt); exit;
 end;
 assign(filu, projectdir + 'gfx' + DirectorySeparator + namu + '.png');
 filemode := 1; rewrite(filu, 1); // write-only
 jvar := IOresult;
 if jvar <> 0 then begin
  PrintError('IO error ' + strdec(jvar) + ' trying to write ' + namu);
  exit;
 end;
 blockwrite(filu, loader^, ivar);
 close(filu);
 {$endif}
end;

procedure BeautifyGraphics;
// Converted graphics have been stored under gfx\ as 16-color indexed PNGs.
// This batch-beautifies them using a reverse-dithering filter.
var ivar : dword;
begin
 if newgfxcount = 0 then exit;

 writeln('Applying reverse-dithering filter on ', newgfxcount, ' images...');
 for ivar := newgfxcount - 1 downto 0 do begin
  ApplyFilter(newgfxlist[ivar]);
  write('.');
 end;
 writeln;
end;

// ------------------------------------------------------------------

procedure PostProcess;
// After all input files for a game have been converted, call this to handle
// all necessary post-conversion tasks.
begin
 if newgfxcount <> 0 then begin
  if decomp_param.docomposite then CompositeGraphics;
  if decomp_param.dobeautify then BeautifyGraphics;
 end;
 WriteMetadata;
end;
