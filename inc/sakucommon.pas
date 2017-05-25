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

{$include version.inc}
const mainscriptname : string[5] = 'MAIN.'; // this is run at startup

// Pause states:
// Normal = all fibers run normally
// Single = each fiber takes a single step, then the game pauses itself
// Paused = fibers do not run
type tpausestate = (PAUSESTATE_NORMAL, PAUSESTATE_SINGLE, PAUSESTATE_PAUSED);

// Meta states:
// Normal = running normal game scripts
// Special = game scripts are suspended, running saveload/settings/etc
var metastate : (METASTATE_NORMAL, METASTATE_SPECIAL);

// Fiber states:
// Stopping = not running, can be removed
// Normal = executing script
// Waitkey = pause until keypress not eaten by boxes/events, or signalled
// Waitclear = pause until keypress not eaten, or signalled, then clear boxes
// Waitchoice = pause until new choice appears in choicematic, or cancelled
// Waitsignal = pause until signalled by another fiber
// Waitsleep = pause until thread's sleep effect or another fiber signals
// Waitfx = pause until thread's fx refcount is 0, or signalled
const
FIBERSTATE_STOPPING = 0;
FIBERSTATE_NORMAL = 1;
FIBERSTATE_WAITKEY = 2;
FIBERSTATE_WAITCLEAR = 3;
FIBERSTATE_WAITCHOICE = 4;
FIBERSTATE_WAITSIGNAL = 5;
FIBERSTATE_WAITSLEEP = 6;
FIBERSTATE_WAITFX = 7;

// Box states:
// Null = box is not shown, will be set to Appearing when text is inserted
// Empty = box is shown, will be set to Vanishing if autovanish = TRUE
// Appearing = pop-in animation, will be set to Showtext when complete
// Vanishing = pop-out animation, will be set to Null when complete
// Showtext = box+content are shown
// Showchoices = box+content+highlight are shown, choicematic is in control
BOXSTATE_NULL = 0;
BOXSTATE_EMPTY = 1;
BOXSTATE_APPEARING = 2;
BOXSTATE_VANISHING = 3;
BOXSTATE_SHOWTEXT = 4;

// Effect kinds:
FX_SLEEP = 1;
FX_TRANSITION = 2;
FX_BOXMOVE = 10;
FX_BOXSIZE = 11;
FX_BOXSCROLL = 12;
FX_GOBMOVE = 20;
FX_GOBALPHA = 22;

// Move types:
MOVETYPE_INSTANT = 0;
MOVETYPE_LINEAR = 1;
MOVETYPE_COSCOS = 2; // a visually pleasing soft glide
MOVETYPE_HALFCOS = 3; // second half of coscos, starts fast, slows toward end

// Transition types:
TRANSITION_INSTANT = 0;
TRANSITION_WIPEFROMLEFT = 1;
TRANSITION_RAGGEDWIPE = 2;
TRANSITION_INTERLACED = 3;
TRANSITION_CROSSFADE = 4;

// Blend modes:
BLENDMODE_NORMAL = 0;
BLENDMODE_HARDLIGHT = 1;

const
FIBER_STACK_SIZE = 2047; // this many + 1 dwords, must be ^2 minus 1
CALLSTACK_SIZE = 15;

type fibertype = record
       fibername : UTF8string;
       labelname : UTF8string;
       labelindex : dword; // this fiber is running script[labelindex]
       codeofs : dword; // current offset in script[].code^

       // Every timed effect spawned by this fiber increases the fxrefcount.
       // Any effect belonging to this fiber decreases it on expiry.
       // This allows efficiently waiting for all timed effects to complete.
       fxrefcount : dword;

       // Stack used to execute sakurascript. Script consists of tokenised
       // operands and operations; operands get pushed on the stack, and
       // operations pop them off to do things with them, possibly pushing
       // the result back. The stack loops around, since some commands leave
       // unpopped leftovers. Datacount tracks how many valid poppable dwords
       // are available, to catch stack underflows.
       datastack : array[0..FIBER_STACK_SIZE] of dword;
       dataindex, datacount : dword;

       // The furthest-back callstack level must always be zeroed out, so any
       // attempt to return further back will show an error.
       callstack : array[0..CALLSTACK_SIZE] of record
         labelname : UTF8string;
         ofs : dword;
       end;

       callstackindex : byte; // rolling counter, points at next free slot
       fiberstate : byte; // see fiber state enums in sakucommon.pas
     end;

type gobtype = record
       // Graphic object data is stored in this, except for the actual bitmap
       // images, which are pulled through the asset manager as needed.
       // Gobs are drawn from 0 upwards, and are expected to have an
       // ascending hierarchy where front gobs are children of back gobs.
       // For example, sprites are children of a background picture, and
       // blinking animations are children of the character sprites.
       // If a gob moves, its kids move along; if destroyed, kids are too.
       gobnamu : UTF8string;
       gfxnamu : UTF8string;
       // gfxlist[] slot of gob's bitmap, maybe invalid.
       cachedgfx : dword;

       // Any gob can be a child of another gob, -1 for none. Most gobs will
       // be adopted by the background gob. If the parent gob moves or is
       // removed or whatever, child gobs go right along.
       parent : dword;
       // Position, clip, and size the gob within this viewport.
       inviewport : dword;
       // 32k coordinates of graphic relative to its viewport
       locx, locy : longint;
       // px coordinates of graphic relative to the game window
       locxp, locyp : longint;
       // gob's frames are drawn scaled to this size
       sizexp, sizeyp : dword;
       // size=size*multiplier div 32768, 32k = 100%
       sizemultiplier : dword;
       // which frame of the graphic to display
       drawframe : dword;
       // current frame: gfxlist[].sequence[animseqp]
       animseqp : dword;
       // next frame after x msecs, -1 if not animating
       animtimer : dword;

       solidblit : RGBquad; // if non-zero, gob is colorised with this color
       solidblitnext : RGBquad; // this moves to solidblit on next transition
       zlevel : longint;

       // Bitflags, the current state of the gob
       drawstate : byte;
       // bit 0: draw/redraw at next Renderer pass
       // bit 1: is this gob supposed to be visible?
       // bit 5: make this the new background upon next gfx.transition
       // bits 6-7: other action upon next gfx.transition
       //   $00 - none
       //   $40 - make visible
       //   $80 - kill
       //   $C0 - make invisible

       alphaness : byte; // 0 = transparent, 255 = fully visible (default)
     end;

type boxtype = record
       // Position, clip, and size the box within this viewport.
       inviewport : dword;

       // Fontheight is 32k relative to the parent viewport's height.
       // Origfontheight is set by the script. This is multiplied by the
       // user's interface magnification to become the true fontheight.
       origfontheight, fontheight : dword;

       // After the font is created, these are the actual metrics received,
       // and are used for rendering only. Additionally, if outlines are
       // defined in the box style, lineheightp is increased by
       // outlinemargintopp/bottomp to allow the biggest outline
       // thickness/offset to fit.
       reqfontheightp, fontheightp, fontwidthp, lineheightp : dword;

       {$ifndef sakucon}
       // Font handle used by SDL. Nominally PTTF_Font, but the structure
       // contents are for SDL's internal use only, so we only get a pointer.
       fonth : pointer;
       {$endif}

       // Content window size bounds, depending on the selected font. The
       // rows are converted to a pixel height using lineheightp, and cols
       // to a pixel width using fontheightp as an em-width, plus outline
       // margins on the left and right.
       contentwinminrows, contentwinmaxrows : dword;
       contentwinmincols, contentwinmaxcols : dword;

       // More content window size bounds, 32k relative to parent viewport.
       contentwinminsizex, contentwinminsizey : dword;
       contentwinmaxsizex, contentwinmaxsizey : dword;

       // The above two bounds combined into pixel value bounds. These are
       // used to linewrap text in the box and figure out how many rows are
       // needed for all the text.
       contentwinminsizexp, contentwinminsizeyp : dword;
       contentwinmaxsizexp, contentwinmaxsizeyp : dword;

       // After the text content is broken into rows, the row count is kept
       // here. The full content pixel height is row count * lineheightp.
       // This gives a vertically scrollable content buffer.
       contentfullrows, contentfullheightp : dword;

       // Vertical offset of the content window from the top of the buffer,
       // in pixels. This allows scrolling down by one line by adding
       // lineheightp. The window can scroll past the bottom of the content.
       contentwinscrollofsp : dword;

       // Content window size after linewrapping and bounding, in pixels.
       contentwinsizexp, contentwinsizeyp : dword;

       // Margin sizes, 32k relative to viewport.
       marginleft, marginright, margintop, marginbottom : dword;
       // Same in pixels.
       marginleftp, marginrightp, margintopp, marginbottomp : dword;

       // Box size = content window size + margins. Derived from above.
       boxsizexp, boxsizeyp : dword;

       // 32k coordinates of anchor point within the box.
       anchorx, anchory : longint;

       // 32k coordinates relative to box's parent viewport.
       boxlocx, boxlocy : longint;
       // For rendering, pixel values relative to the box's parent viewport.
       boxlocxp, boxlocyp : longint;

       // If non-zero, this box's final rendering location, below, is snapped
       // to be pixel-perfectly attached to the closest edge of the given
       // other box. A box can't snap to itself, and no box can snap to 0.
       snaptobox : dword;

       // The _r variables are the final rendering location and size, pixel
       // values relative to the game window. These include any temporary
       // adjustment caused by pop-in or pop-out.
       boxlocxp_r, boxlocyp_r : longint;
       boxsizexp_r, boxsizeyp_r : dword;

       // Basebufsize = boxsizexp * boxsizeyp * bytes per pixel
       basebufsize, basebufmaxsize : dword;
       // Contentfullbufsize = contentwinsizexp * contentfullheightp * bpp
       contentfullbufsize, contentfullbufmaxsize : dword;
       // Rowbufsize = contentwinsizexp * fontheightp * bytes per pixel
       rowbufsize, rowbufmaxsize : dword;

       // Base image, consisting of tiled/stretched graphic and frame decor.
       basebuf : pointer;
       // Full content buffer, possibly taller than the box size.
       contentfullbuf : pointer;
       // Row buffer, for rendering individual rows with outlines. Row parts
       // are rendered, then appended here. Once the row is full, the rowbuf
       // is used to render outlines in the full content buffer, and finally
       // to copy the text itself there over the outlines.
       rowbuf : pointer;
       // Final image = base image + window of full content buffer. The final
       // buffer is the same size as the base buffer.
       finalbuf : pointer;

       // Set invalid when any parameter has changed, so everything about the
       // box needs recalculating. Always invalidates contentbuftext+basebuf.
       contentbufparamvalid : boolean;
       // Set invalid when the text has changed, so a new content size must
       // be calcualted and the new text rendered. If content size after
       // bounding is different than before, invalidates basebuf. Always
       // invalidates finalbuf.
       contentbuftextvalid : boolean;
       // When invalid, a new base size is calculated, and a new base image
       // is rendered. Invalidates finalbuf.
       basebufvalid : boolean;
       // When invalid, resizes to same as base size if needed, then renders
       // the final image from the latest base buf and scrolled content.
       finalbufvalid : boolean;

       // This is true if the box for whatever reason needs to be redrawn.
       // In console mode, boxes require special handling, so they are always
       // redrawn completely or not at all.
       needsredraw : boolean;

       // Simple UTF-8 text directly from print-commands, with escape codes
       // separated. (Variable references get dereferenced immediately.)
       txtcontent : array of byte;
       txtlength : dword; // in bytes

       // List of escape codes and their offsets in txtcontent[]. Codes:
       // \0 = empty character
       // \n = explicit linebreak
       // \? = begin choice string
       // \. = end choice string
       // \B \b = enable\disable bold font
       // \$xxx; = variable reference, not saved, immediately dereferenced
       // \:xxx; = show emoji number xxx
       // \cRGBA; = set primary text color temporarily to RGBA, one hex each
       // \d = restore the default text color
       // \L \C \R = set text alignment temporarily to left/center/right
       txtescapelist : array of record
         escapeofs : dword;
         escapecode : byte;
         escapedata : dword;
       end;
       txtescapecount : dword;

       // When getting ready to render, txtcontent must first be scanned to
       // identify explicit and implicit linebreaks. A binary search is done
       // to find exactly up to which character can fit in the maximum
       // contentwinsizexp less outlinemarginleftp/rightp.
       // Then, scan backwards to find the first suitable line break
       // character; if none found, display the whole line.
       // This list has the final txtcontent[] line break offsets.
       // (Also keep track of how many rows the text was broken into. This
       // goes into contentfullrows, above.)
       txtlinebreaklist : array of dword;
       txtlinebreakcount : dword;

       // All string manipulation is done in all available languages at the
       // same time. When a string is printed in this box, this language
       // index is the one displayed.
       boxlanguage : dword;

       // Anything printed in this box is also printed in the export target
       // box, in that box's preferred language. 0 for disabled. Exporting
       // can be chained.
       exportcontentto : dword;

       // See box state enums above.
       boxstate : byte;

       // If the box state is appearing/vanishing, popruntime counts msecs
       // toward style.poptime. When it is reached, the box state changes.
       popruntime : longint;

       // Variables controlling box appearance and functionality.
       style : record
         // Default primary text color. Each tbox.clear reverts to this.
         textcolor : RGBquad;
         // The base image starts out filled with this color, depending on
         // base type. The base color should always be defined, as it's
         // a fallback if something goes wrong with a textured base.
         basecolor : array[0..3] of RGBquad;
         // 0 = no fill, 1 = flat basecolor[0], 2 = four-corner gradient
         basefill : byte;

         boxblendmode : byte;

         // 0 = no texture, 1 = stretched texture, 2 = tiled texture
         texturetype : byte;
         textureblendmode : byte;
         texturename : string[31];
         // If you want, you can use a multi-frame graphic as a texture.
         textureframeindex : dword;
         // Pixel values marking the boundaries of the texture graphic. These
         // delineate a hash-shape, where the corners get copied directly,
         // the top and bottom are stretched horizontally, the left and right
         // are stretched vertically, and the middle is stretched both ways.
         // These pixel values are margin widths, relative to the original
         // graphic size, and are defined by the script.
         textureleftorigp, texturerightorigp, texturetoporigp, texturebottomorigp : dword;
         // These are the same, but derived from the above, and are relative
         // to the graphic resized to the box's parent viewport.
         textureleftp, texturerightp, texturetopp, texturebottomp : dword;
         // The texture's pixel size within the box's viewport.
         texturesizexp, texturesizeyp : dword;

         // 0 = no bevel, 1 = apply bevel of half of smallest margin
         dobevel : byte;

         // After the base and texture and bevel, decoration graphics can
         // also be pasted on the base image.
         decorlist : array of record
           decorname : string[31];
           decorframeindex : dword;
           decoranchorx, decoranchory : longint;
           decorlocx, decorlocy : longint;
           // By default, the graphic is sized from its original resolution
           // to the box's viewport size. If either decorsize is defined,
           // then that axis is resized to said 32k fraction of boxsizexyp.
           // If the requested graphic is larger than the base buffer in
           // either dimension, the dimension is shrunk to fit.
           decorsizex, decorsizey : dword; // 32k
           decorsizexp, decorsizeyp : dword;
         end;

         // When the box is appearing/vanishing, these are the pop types:
         // 0 = instant, 1 = grow/shrink, 2 = fade, 3 = swipe left-to-right
         // The visual effect is done during blitting of the final buffer
         // into the game window.
         poptype : byte;
         // Pop time in msecs, how long the appearing/vanishing takes.
         poptime : dword;

         // Default text alignment. The alignment can be temporarily changed
         // by escape codes during any row.
         // 0 = left, 1 = center, 2 = right
         textalign : byte;

         // After each text row has been rendered, while the row is being
         // copied into the full content buffer, text outlines are drawn in
         // first in reverse order, before the text proper is placed in. This
         // can be used for drop shadows too.
         outline : array of record
           outlinecolor : RGBquad;
           // The thickness and offset are 32k values relative to the box's
           // parent viewport.
           thickness : dword;
           ofsx, ofsy : longint;
           // These are absolute pixel values derived from the above.
           thicknessp : dword;
           ofsxp, ofsyp : longint;
           // If TRUE, the outline color fades toward transparent alpha as
           // a function of distance over thickness.
           alphafade : boolean;
         end;
         // When the outline array is modified, new outline margin pixel
         // sizes must be calculated, which causes lineheightp to adapt, and
         // forces a re-linebreaking. These come from the furthest pixel
         // distance any outline reaches, counting its offset in that
         // direction plus that outline's pixel thickness.
         outlinemarginleftp, outlinemarginrightp, outlinemargintopp, outlinemarginbottomp : dword;

         // If the text content takes more space than the box can fit, and
         // this is TRUE, the user can scroll the text freely by pressing
         // up/down or pgup/pgdn/home/end, or using the mouse wheel. If the
         // box contains choices, it always counts as scrollable.
         freescrollable : boolean;
         // If a box with overflown content is not freely scrollable, and
         // autowaitkey is TRUE, the box will page down upon a keypress. When
         // the box is displaying the bottom of the content, it no longer
         // eats keypresses, which pass to waitkey normally.
         autowaitkey : boolean;
         // With autovanish, when a box is cleared, it goes in Vanishing
         // state. Otherwise the empty box will stick around.
         autovanish : boolean;
         // The user can hide visible textboxes to see the full game window.
         // Scripts can also force-hide boxes. This controls hidability:
         // bit 0 = if set, hidden; bit 1 = if set, user change not allowed
         hidable : byte;
         // If negatebkg is on, during blitting of the final buffer, whatever
         // is under this box gets negated first.
         negatebkg : boolean;
       end;
     end;

type FXtype = record
       // not all of the fields are used for every effect; each effect kind
       // can use whatever it likes however it likes
       // (except .kind .fxfiber .fxbox .fxgob .inviewport)
       poku : pointer;
       kind : dword;
       time, time2 : dword;
       x1, y1, x2, y2 : longint;
       fxbox : dword; // if a box is referenced, the ID must be here
       fxgob : dword; // if a gob is referenced, the ID must be here
       fxfiber : longint; // fiber that spawned this effect, or -1
       data, data2 : dword;
       inviewport : dword;
     end;

type viewporttype = record
       // Graphics are rendered into logical viewports, to make it easier to
       // have separate interface elements of possibly varying pixel ratios.
       // Viewports are defined in relation to parent viewports.
       // Due to the cascading nature of size changes, you should always call
       // UpdateViewport after changing anything.
       // Viewport 0 is special, hardcoded to be equal to the output window.
       viewportparent : dword;
       // If these are non-zero, you can force a viewport to be a specific
       // aspect ratio. It gets letterboxed within its parent viewport.
       // If you leave these as zero, the full parent window is used, but its
       // aspect ratio could be anything.
       // Generally you want to force an aspect ratio for game graphics, but
       // use the full window for textboxes.
       viewportratiox, viewportratioy : dword;
       // These are the logical 32k coordinates of the inclusive top left
       // and exclusive bottom right corner of a viewport, relative to the
       // viewport's parent viewport letterboxed to this port's ratio.
       // This is useful for having the game view inside a fixed viewframe.
       viewportx1, viewporty1, viewportx2, viewporty2 : longint;
       // These are the absolute pixel coordinates of the inclusive top left
       // and exclusive bottom right corner of a viewport, within the full
       // output window. Only used internally by the engine.
       viewportx1p, viewporty1p, viewportx2p, viewporty2p : longint;
       viewportsizexp, viewportsizeyp : dword; // shortcut: x2p-x1p, y2p-y1p
       // Each viewport can have one background gob; every other gob placed
       // in the same viewport will be at or above background index.
       backgroundgob : dword;
     end;

type blitstruct = record
       srcp, destp : pointer;
       srcofs, destofs : dword;
       destofsxp, destofsyp : longint;
       copywidth, copyrows : dword;
       srcskipwidth, destskipwidth : dword;
       clipx1p, clipy1p : longint;
       clipx2p, clipy2p : longint;
       clipviewport : dword;
     end;
     pblitstruct = ^blitstruct;


var // Script execution fibers.
    fiber : array of fibertype;

    // Graphic objects.
    gob : array of gobtype;

    // Textboxes.
    TBox : array of boxtype;

    // Special effect tracking.
    fx : array of FXtype;

    // Dedicated counters for the above, to reduce need for array resizing.
    fibercount, fxcount : dword;

    // Viewports
    viewport : array of viewporttype;

    // Events
    event : record
      area : array of record
        namu : UTF8string;
        inviewport : dword;
        x1, y1, x2, y2 : longint; // 32k relative to viewport
        x1p, y1p, x2p, y2p : longint; // pixel values relative to game window
        triggerlabel, mouseonlabel, mouseofflabel : UTF8string;
        state : byte; // 1 if currently overed, 0 if not
        mouseonly : boolean;
      end;
      gob : array of record
        namu : UTF8string;
        gobnamu : UTF8string;
        gobnum : dword;
        triggerlabel, mouseonlabel, mouseofflabel : UTF8string;
        state : byte; // 1 if currently overed, 0 if not
        mouseonly : boolean;
      end;
      timer : array of record
        namu : UTF8string;
        triggerfreq : dword; // timers trigger every x msecs
        timercounter : dword; // accumulates every frame
        triggerlabel : UTF8string; // on trigger, this is run in a new fiber
      end;
      normalint : record
        triggerlabel : UTF8string;
      end;
      escint : record
        triggerlabel : UTF8string;
      end;
      triggeredint : boolean; // TRUE if an int was triggered this frame
    end;

var // Commandline parameters.
    saku_param : record
      appname, workdir, profiledir : UTF8string;
      datnames : array of UTF8string;
      overridex, overridey : dword;
      {$ifdef sakucon}
      lxymix : boolean; // use LXY mixing instead of RGB
      {$endif}
      help : boolean;
    end;

    // List of detected dat-files.
    availabledatlist : array of DATtype;

    // System vars, not imported/exported in save states.
    sysvar : record
      activeprojectname : UTF8string;
      resttime : dword; // maximum rest time between frames, milliseconds
      mv_WinSizeX, mv_WinSizeY : dword;
      windowSizeX, windowSizeY : dword;
      uimagnification : dword; // text size adjustment, 32k = 100%
      mouseX, mouseY : longint; // straight px coord within program window
      keysdown : byte; // bitmask: 1 = down, 2 = left, 4 = right, 8 = up
      numlang : byte; // number of languages
      hideboxes : byte; // 1 = hidden, 0 = visible
      fullscreen : boolean;
      WinSizeAuto : boolean; // use default winsize values?
      usevsync : boolean;
      skipseentext : boolean;
      restart : boolean; // set to TRUE to restart main script
      quit : boolean; // set to TRUE when quitting or restarting
    end;

    // Game session variables, imported/exported in save states.
    gamevar : record
      defaulttextbox : dword; // print commands default to this TBox[]
      defaultviewport : dword; // new gobs are relative to this by default
    end;

    // Font preferences.
    fontlist : array of record
      fontlang : UTF8string;
      fontmatch : UTF8string;
      fontfile : UTF8string;
    end;

    // Main engine pause state. In SDL mode, press the pause key to pause and
    // unpause. In console mode, it's Ctrl-P. Shift-pause or Ctrl-Shift-P
    // will execute a single step in every fiber, then pauses.
    // While the engine is paused, fibers do not execute and most user input
    // is ignored.
    pausestate : tpausestate;

    // The choicematic controls choices in textboxes.
    choicematic : record
      choicebox, choicepartbox, highlightbox : dword;
      // Choices are printed in this many columns. By default 4; set to 1 to
      // have a simple vertical list. If a choice text is wider than a single
      // column, it will simply occupy more than one column, and the
      // following choices are shifted ahead. If the total choices take more
      // rows than the box's content window, the box becomes scrollable.
      numcolumns, colwidthp : dword;
      // This starts empty, then gets the user's choice appended to it. This
      // string can be displayed as the choice parent, if you replace the
      // intermediate colons with spaces.
      choiceparent : UTF8string;
      // When the choice is confirmed, the full choice string goes in this.
      // If the user is prompted for a choice again, this can be used to set
      // the initial highlight. Choice.reset also resets this.
      previouschoice : UTF8string;
      // If not empty, each time the user changes the highlight, this label
      // gets spawned in a new fiber.
      onhighlight : UTF8string;

      // Choicelist comes straight from sakurascript's choice.set command.
      choicelist : array of record
        choicetxt : UTF8string;
        jumplist : UTF8string;
        trackvar : UTF8string;
        selectable : boolean; // if FALSE, choice is not selectable nor shown
      end;
      showlist : array of record
        showtxt : UTF8string;
        // Top left and bottom right pixel coords of this string in the box's
        // intbuf^. Does not take into account the intbuf's scrolling offset.
        // These are filled in by the box content renderer as it encounters
        // choice tags.
        slx1p, sly1p, slx2p, sly2p : dword;
      end;
      choicelistcount, showcount : dword;
      // Current selection in showlist[]. When the choicebox content is
      // rendered, this gets automatically highlighted.
      highlightindex : dword;
      // When a choice is finalised, the choicelist[] index is placed here.
      // This is used by the choice-triggering fiber to either jump/call to
      // a label, or to save the number in a variable.
      previouschoiceindex : dword;

      // Print higher-level choice(s) in choicepartbox?
      printchoiceparent : boolean;
      // Is the choicematic active?
      active : boolean;
    end;

var logfile : text;
    mv_ProgramName : UTF8string;
    // Table of cos(cos) values, interpolated from mcg_costable, for effects
    coscos : array of word;

    seengfxsize : dword; // bytesize reserved for below pointer
    seengfxp : pointer; // stream of string[15] graphic names
    seengfxitems : dword; // number of strings[15] stored in above

var // BGRA buffer for the full game window: mv_WinSizeX * mv_WinSizeY * 4
    mv_OutputBuffy : pointer;
    // Another BGRA buffer of the same size. Some effects and transitions
    // need a textboxless view of the game window, which is kept here.
    stashbuffy : pointer;

// A structure to track screen rectangles needing refreshing.
type tfresh = record
       // xy1p is the inclusive top left, xy2p the exclusive bottom right
       x1p, y1p, x2p, y2p : longint;
     end;

var refresh : array of tfresh;
    numfresh : dword;
    // If transitionactive <> $FFFFFFFF, then it points to the fx[] index of
    // a transition effect.
    transitionactive : dword;
    alphamixtab : array[0..255, 0..255] of byte;
    RGBtweaktable : array[0..767] of byte; // fullscreen 3-chn adjustment
    RGBtweakactive : byte;

// Override "supersakura-whatever" with "ssakura" for conciseness.
// This is used by GetAppConfigDir to decide on a good config directory.
function truename : ansistring;
begin truename := 'ssakura'; end;

// ------------------------------------------------------------------

// Some con/sdl -specific helper functions.
{$ifdef sakucon}
  {$include sakuhead-con.pas}
{$else}
  {$include sakuhead-sdl.pas}
{$endif}

// General-purpose blitters.
procedure DrawRGB24(clipdata : pblitstruct); forward;
procedure DrawRGBA32(clipdata : pblitstruct); forward;
procedure DrawRGBA32hardlight(clipdata : pblitstruct); forward;
// Visual transition helper.
procedure StashRender; forward;
// The choicematic etc may need to spawn fibers.
procedure StartFiber(labelnamu, fibernamu : UTF8string); forward;
// The box renderer etc may need to set the highlighted choice.
procedure HighlightChoice(style : byte); forward;

// Uncomment this when compiling with HeapTrace. Call this whenever to test
// if at that moment the heap has yet been messed up.
{procedure CheckHeap;
var poku : pointer;
begin
 QuickTrace := FALSE;
 getmem(poku, 4); freemem(poku); poku := NIL;
 QuickTrace := TRUE;
end;}

// ------------------------------------------------------------------

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

// ------------------------------------------------------------------

function GetDat(const nam : UTF8string) : dword;
// Returns the lowest existing dat in availabledatlist[] with a matching
// project name, or length(availabledatlist) if no match found. The input
// project name should be in lowercase.
begin
 GetDat := 0;
 while GetDat < dword(length(availabledatlist)) do begin
  if availabledatlist[GetDat].projectname = nam then exit;
  inc(GetDat);
 end;
end;

function IsGobValid(const gobnum : dword) : boolean; inline;
begin
 IsGobValid := (gobnum < dword(length(gob))) and (gob[gobnum].gobnamu <> '');
end;

function GetGob(const nam : UTF8string) : dword;
// Returns the lowest existing gob with a matching name, or length(gob) if
// no match found.
begin
 GetGob := 0;
 while GetGob < dword(length(gob)) do begin
  if (IsGobValid(GetGob)) and (gob[GetGob].gobnamu = nam) then exit;
  inc(GetGob);
 end;
end;

function ExpandColorRef(colin : longint) : dword; inline;
// Takes a four-hex RGBA color (lsb first, so first byte is AB; when printed,
// you see RGBA order), and returns a full eight-hex ARGB color, compatible
// with the RGBquad type.
begin
 ExpandColorRef := (colin and $F) shl 24 + (colin and $F0) shr 4 + (colin and $F00) + (colin and $F000) shl 4;
 ExpandColorRef := ExpandColorRef or (ExpandColorRef shl 4);
end;

procedure ReadSeenGFX;
// Initialises the seengfx list, opens the .SAV file, reads previously seen
// graphics into the list.
var filu : file;
    ivar, jvar : dword;
    tux : string;
begin
 exit;
 jvar := 0; seengfxitems := 0; seengfxsize := 4096;
 if seengfxp <> NIL then begin freemem(seengfxp); seengfxp := NIL; end;
 getmem(seengfxp, seengfxsize);

 tux := saku_param.workdir + sysvar.activeprojectname;
 while (tux <> '') and (tux[length(tux)] <> '.') do dec(byte(tux[0]));
 if tux = '' then halt(81);
 tux := tux + 'sav';
 assign(filu, tux);
 filemode := 0; reset(filu, 1); // read-only access
 ivar := IOresult;
 if ivar = 0 then begin
  // Read the signature
  blockread(filu, jvar, 4);
  if jvar <> $CBCABAAB then LogError('Wrong sig in SAV file')
  else begin
   // Read the list size
   blockread(filu, seengfxitems, 2);
   ivar := (seengfxitems * 16 + 1024) and $FFFFFF00;
   if ivar > seengfxsize then begin
    freemem(seengfxp); seengfxp := NIL;
    seengfxsize := ivar;
    getmem(seengfxp, seengfxsize);
   end;
   blockread(filu, seengfxp^, seengfxitems * 16);
   Log('Seen gfx in SAV: ' + strdec(seengfxitems));
  end;
  close(filu);
 end else LogError('No SAV file found');

 while IOresult <> 0 do ;
end;

procedure SaveGlobals;
// Attempts to write the seen graphics and strings lists into a SAV file.
var filu : file;
    ivar, jvar : dword;
    tux : string;
begin
 tux := saku_param.workdir + sysvar.activeprojectname;
 while (tux <> '') and (tux[length(tux)] <> '.') do dec(byte(tux[0]));
 if tux = '' then halt(81);
 tux := lowercase(tux) + 'sav';
 assign(filu, tux);
 filemode := 1; rewrite(filu, 1); // write-only access
 ivar := IOresult;
 if ivar = 0 then begin
  // Write the signature
  jvar := $CBCABAAB;
  blockwrite(filu, jvar, 4);
  // Write the seen graphics list
  blockwrite(filu, seengfxitems, 2);
  blockwrite(filu, seengfxp^, seengfxitems * 16);
  // Write the seen strings lists
  close(filu);
 end else logerror(errortxt(ivar) + ' trying to write SAV');

 while IOresult <> 0 do ;
end;

// ------------------------------------------------------------------

procedure AddRefresh(x1p, y1p, x2p, y2p : longint);
// Adds the given rectangle to Refresh[], a list of areas that are going
// get redrawn.
// Clips the rectangle against the window size, and makes sure there is no
// overlap with previously added rectangles.
// The input values are px coordinates relative to the full window.
// X1p:Y1p is inclusive top left, X2p:Y2p is exclusive bottom right.
// Any clipping against a viewport must be done before calling this.
var ivar : dword;
begin
 // clip against full window
 if x1p < 0 then x1p := 0;
 if x2p > longint(sysvar.mv_WinSizeX) then x2p := sysvar.mv_WinSizeX;
 if y1p < 0 then y1p := 0;
 if y2p > longint(sysvar.mv_WinSizeY) then y2p := sysvar.mv_WinSizeY;
 // after clipping, any visible pixels left?
 if (x2p <= x1p) or (y2p <= y1p) then exit;

 //logmsg('+++ AddRefresh ' + strdec(x1p) + ',' + strdec(y1p) + ' to ' + strdec(x2p) + ',' + strdec(y2p));

 // Look for overlaps
 // (remember, x1p:y1p is inclusive, x2p:y2p is exclusive)
 ivar := numfresh;
 while ivar <> 0 do begin
  dec(ivar);

  // no overlap?
  if (x1p >= refresh[ivar].x2p) or (y1p >= refresh[ivar].y2p)
  or (x2p <= refresh[ivar].x1p) or (y2p <= refresh[ivar].y1p)
  then continue;

  // For the below comparisons, A is our new area, B is the existing area.
  //
  // To minimise refresh regions, operations should be done in this order:
  // 1. Preferably drop a full area
  // 2. Clip an area
  // 3. Split an area, but only if no other choice
  //
  // Fun optimisation idea: there are 4 possible comparisons per coordinate,
  // and 4 coordinates, for a total of 4^4 combinations. Why not do the
  // comparisons and save the boolean result into a bit array, then do
  // a simple case switch for the combinations you're interested in?
  // It would still have to absolutely respect the operation order though.
  //
  // A careful analysis of the if-then-else flow might allow combining more
  // comparisons, but be super careful. You have to have ">=" and "<=" on
  // both outcomes of an if-statement, or some cases get handled incorrectly.

  // A fully inside B: drop A
  if (x1p >= refresh[ivar].x1p) and (y1p >= refresh[ivar].y1p)
  and (x2p <= refresh[ivar].x2p) and (y2p <= refresh[ivar].y2p)
  then exit;

  // B fully inside A: drop B
  if (x1p <= refresh[ivar].x1p) and (y1p <= refresh[ivar].y1p)
  and (x2p >= refresh[ivar].x2p) and (y2p >= refresh[ivar].y2p)
  then begin
   dec(numfresh);
   refresh[ivar] := refresh[numfresh];
   continue;
  end;

  if (x1p >= refresh[ivar].x1p) then begin
    if (y1p >= refresh[ivar].y1p) then begin
      if (x2p <= refresh[ivar].x2p) then begin
        if (y2p > refresh[ivar].y2p) then begin
          // A poking into B from below: clip A's top
          y1p := refresh[ivar].y2p; continue;
        end;
      end else begin
        if (y2p <= refresh[ivar].y2p) then begin
          // A poking into B from right: clip A's left
          x1p := refresh[ivar].x2p; continue;
        end;
      end;
    end else begin
      if (x2p <= refresh[ivar].x2p) and (y2p <= refresh[ivar].y2p) then begin
        // A poking into B from above: clip A's bottom
        y2p := refresh[ivar].y1p; continue;
      end;
    end;
  end else begin
    if (y1p >= refresh[ivar].y1p) and (x2p <= refresh[ivar].x2p)
    and (y2p <= refresh[ivar].y2p) then begin
      // A poking into B from left: clip A's right
      x2p := refresh[ivar].x1p; continue;
    end;
  end;

  if (x1p <= refresh[ivar].x1p) then begin
    if (y1p <= refresh[ivar].y1p) then begin
      if (x2p >= refresh[ivar].x2p) then begin
        if (y2p < refresh[ivar].y2p) then begin
          // B poking into A from below: clip B's top
          refresh[ivar].y1p := y2p; continue;
        end;
      end else begin
        if (y2p >= refresh[ivar].y2p) then begin
          // B poking into A from right: clip B's left
          refresh[ivar].x1p := x2p; continue;
        end;
      end;
    end else begin
      if (x2p >= refresh[ivar].x2p) and (y2p >= refresh[ivar].y2p) then begin
        // B poking into A from above: clip B's bottom
        refresh[ivar].y2p := y1p; continue;
      end;
    end;
  end else begin
    // B poking into A from left: clip B's right
    if (y1p <= refresh[ivar].y1p) and (x2p >= refresh[ivar].x2p)
    and (y2p >= refresh[ivar].y2p) then begin
      refresh[ivar].x2p := x1p; continue;
    end;
  end;

  if (x1p >= refresh[ivar].x1p) then begin
    if (y1p < refresh[ivar].y1p) then begin
      if (x2p <= refresh[ivar].x2p) then begin
        if (y2p > refresh[ivar].y2p) then begin
          // A crosses B vertically: split A
          AddRefresh(x1p, y1p, x2p, refresh[ivar].y1p); // A's top third
          y1p := refresh[ivar].y2p; // A's bottom third
          continue;
        end;
      end else begin
        if (y2p <= refresh[ivar].y2p) then begin
          // A bottom left corner in B: split A
          // clip A's bottom left corner, add bottom right corner as new
          AddRefresh(refresh[ivar].x2p, refresh[ivar].y1p, x2p, y2p);
          y2p := refresh[ivar].y1p; // A's top half
          continue;
        end;
      end;
    end else begin
      if (x2p > refresh[ivar].x2p) and (y2p > refresh[ivar].y2p) then begin
        // A top left corner in B: split A
        // clip A's top left corner, add top right corner as new
        AddRefresh(refresh[ivar].x2p, y1p, x2p, refresh[ivar].y2p);
        y1p := refresh[ivar].y2p; // A's bottom half
        continue;
      end;
    end;
  end else begin
    if (y1p >= refresh[ivar].y1p) then begin
      if (x2p > refresh[ivar].x2p) then begin
        if (y2p <= refresh[ivar].y2p) then begin
          // A crosses B horizontally: split A
          AddRefresh(x1p, y1p, refresh[ivar].x1p, y2p); // A's left third
          x1p := refresh[ivar].x2p; // A's right third
          continue;
        end;
      end else begin
        if (y2p > refresh[ivar].y2p) then begin
          // A top right corner in B: split A
          // clip A's top right corner, add top left corner as new
          AddRefresh(x1p, y1p, refresh[ivar].x1p, refresh[ivar].y2p);
          y1p := refresh[ivar].y2p; // A's bottom half
          continue;
        end;
      end;
    end else begin
      if (x2p <= refresh[ivar].x2p) and (y2p <= refresh[ivar].y2p) then begin
        // A bottom right corner in B: split A
        // clip A's bottom right corner, add bottom left corner as new
        AddRefresh(x1p, refresh[ivar].y1p, refresh[ivar].x1p, y2p);
        y2p := refresh[ivar].y1p; // A's top half
        continue;
      end;
    end;
  end;

 end;

 if numfresh >= dword(length(refresh)) then setlength(refresh, length(refresh) + 8);
 refresh[numfresh].x1p := x1p;
 refresh[numfresh].y1p := y1p;
 refresh[numfresh].x2p := x2p;
 refresh[numfresh].y2p := y2p;
 inc(numfresh);

 {for ivar := 0 to numfresh - 1 do
  logmsg('Refresh ' + strdec(ivar) + ': '
   + strdec(refresh[ivar].x1p) + ',' + strdec(refresh[ivar].y1p) + ' to '
   + strdec(refresh[ivar].x2p) + ',' + strdec(refresh[ivar].y2p));}
end;

{$ifdef sakucon}
procedure RemoveRefresh(x1p, y1p, x2p, y2p : longint);
// The console version needs to crop out any refresh regions that would get
// drawn over by textboxes. The SDL version handles textboxes differently and
// has no need for this.
var ivar : dword;
    jvar : longint;
begin
 // clip against full window
 if x1p < 0 then x1p := 0;
 if x2p > longint(sysvar.mv_WinSizeX) then x2p := sysvar.mv_WinSizeX;
 if y1p < 0 then y1p := 0;
 if y2p > longint(sysvar.mv_WinSizeY) then y2p := sysvar.mv_WinSizeY;
 // after clipping, any visible pixels left?
 if (x2p <= x1p) or (y2p <= y1p) then exit;

 // Remove this region from existing refresh regions.
 ivar := numfresh;
 while ivar <> 0 do begin
  dec(ivar);
  // no overlap?
  if (x1p >= refresh[ivar].x2p) or (y1p >= refresh[ivar].y2p)
  or (x2p <= refresh[ivar].x1p) or (y2p <= refresh[ivar].y1p)
  then continue;

  // For the below comparisons, A is our exclusion, B is the existing area.

  // A fully inside B: split B into four
  if (x1p > refresh[ivar].x1p) and (y1p > refresh[ivar].y1p)
  and (x2p < refresh[ivar].x2p) and (y2p < refresh[ivar].y2p)
  then begin
   jvar := refresh[ivar].y2p;
   refresh[ivar].y2p := y1p; // reduce B into top part
   AddRefresh(refresh[ivar].x1p, y2p, refresh[ivar].x2p, jvar); // new bottom
   AddRefresh(refresh[ivar].x1p, refresh[ivar].y1p, x1p, y2p); // new left
   AddRefresh(x2p, refresh[ivar].y1p, refresh[ivar].x2p, y2p); // new right
   continue;
  end;

  // B fully inside A: drop B
  if (x1p <= refresh[ivar].x1p) and (y1p <= refresh[ivar].y1p)
  and (x2p >= refresh[ivar].x2p) and (y2p >= refresh[ivar].y2p)
  then begin
   dec(numfresh);
   refresh[ivar] := refresh[numfresh];
   continue;
  end;

  if (x1p > refresh[ivar].x1p) then begin
    if (y1p > refresh[ivar].y1p) then begin
      if (x2p < refresh[ivar].x2p) then begin
        if (y2p >= refresh[ivar].y2p) then begin
          // A poking into B from below: split B
          jvar := refresh[ivar].y2p;
          refresh[ivar].y2p := y1p; // reduce B into top part
          AddRefresh(refresh[ivar].x1p, y1p, x1p, jvar); // new left
          AddRefresh(x2p, y1p, refresh[ivar].x2p, jvar); // new right
          continue;
        end;
      end;
    end;
  end;

  if (x1p > refresh[ivar].x1p) then begin
    if (y1p > refresh[ivar].y1p) then begin
      if (x2p >= refresh[ivar].x2p) then begin
        if (y2p < refresh[ivar].y2p) then begin
          // A poking into B from right: split B
          jvar := refresh[ivar].y2p;
          refresh[ivar].y2p := y1p; // reduce B into top part
          AddRefresh(refresh[ivar].x1p, y1p, x1p, y2p); // new left
          AddRefresh(refresh[ivar].x1p, y2p, refresh[ivar].x2p, jvar); // new bottom
          continue;
        end;
      end;
    end
  end;

  if (x1p > refresh[ivar].x1p) then begin
    if (y1p <= refresh[ivar].y1p) then begin
      if (x2p < refresh[ivar].x2p) then begin
        if (y2p < refresh[ivar].y2p) then begin
          // A poking into B from above: split B
          jvar := refresh[ivar].y1p;
          refresh[ivar].y1p := y2p; // reduce B into bottom part
          AddRefresh(refresh[ivar].x1p, jvar, x1p, y2p); // new left
          AddRefresh(x2p, jvar, refresh[ivar].x2p, y2p); // new right
          continue;
        end;
      end;
    end;
  end;

  if (x1p <= refresh[ivar].x1p) then begin
    if (y1p > refresh[ivar].y1p) then begin
      if (x2p < refresh[ivar].x2p) then begin
        if (y2p < refresh[ivar].y2p) then begin
          // A poking into B from left: split B
          jvar := refresh[ivar].y2p;
          refresh[ivar].y2p := y1p; // reduce B into top part
          AddRefresh(x2p, y1p, refresh[ivar].x2p, y2p); // new right
          AddRefresh(refresh[ivar].x1p, y2p, refresh[ivar].x2p, jvar); // new bottom
          continue;
        end;
      end;
    end;
  end;

  if (x1p <= refresh[ivar].x1p) then begin
    if (y1p <= refresh[ivar].y1p) then begin
      if (x2p >= refresh[ivar].x2p) then begin
        if (y2p < refresh[ivar].y2p) then begin
          // B poking into A from below: clip B's top
          refresh[ivar].y1p := y2p; continue;
        end;
      end;
    end;
  end;

  if (x1p <= refresh[ivar].x1p) then begin
    if (y1p <= refresh[ivar].y1p) then begin
      if (x2p < refresh[ivar].x2p) then begin
        if (y2p >= refresh[ivar].y2p) then begin
          // B poking into A from right: clip B's left
          refresh[ivar].x1p := x2p; continue;
        end;
      end;
    end
  end;

  if (x1p <= refresh[ivar].x1p) then begin
    if (y1p > refresh[ivar].y1p) then begin
      if (x2p >= refresh[ivar].x2p) then begin
        if (y2p >= refresh[ivar].y2p) then begin
          // B poking into A from above: clip B's bottom
          refresh[ivar].y2p := y1p; continue;
        end;
      end;
    end;
  end;

  if (x1p > refresh[ivar].x1p) then begin
    if (y1p <= refresh[ivar].y1p) then begin
      if (x2p >= refresh[ivar].x2p) then begin
        if (y2p >= refresh[ivar].y2p) then begin
          // B poking into A from left: clip B's right
          refresh[ivar].x2p := x1p; continue;
        end;
      end;
    end;
  end;

  if (x1p > refresh[ivar].x1p) then begin
    if (y1p <= refresh[ivar].y1p) then begin
      if (x2p < refresh[ivar].x2p) then begin
        if (y2p >= refresh[ivar].y2p) then begin
          // A crosses B vertically: split B
          jvar := refresh[ivar].x2p;
          refresh[ivar].x2p := x1p; // reduce B to left
          AddRefresh(x2p, refresh[ivar].y1p, jvar, refresh[ivar].y2p); // new right
          continue;
        end;
      end;
    end;
  end;

  if (x1p <= refresh[ivar].x1p) then begin
    if (y1p > refresh[ivar].y1p) then begin
      if (x2p >= refresh[ivar].x2p) then begin
        if (y2p < refresh[ivar].y2p) then begin
          // A crosses B horizontally: split B
          jvar := refresh[ivar].y2p;
          refresh[ivar].y2p := y1p; // reduce B to top
          AddRefresh(refresh[ivar].x1p, y2p, refresh[ivar].x2p, jvar); // new bottom
          continue;
        end;
      end;
    end;
  end;

  if (x1p > refresh[ivar].x1p) then begin
    if (y1p <= refresh[ivar].y1p) then begin
      if (x2p >= refresh[ivar].x2p) then begin
        if (y2p < refresh[ivar].y2p) then begin
          // A bottom left corner in B: split B
          jvar := refresh[ivar].y1p;
          refresh[ivar].y1p := y2p; // reduce B to bottom
          AddRefresh(refresh[ivar].x1p, jvar, x1p, y2p); // new left
          continue;
        end;
      end;
    end;
  end;

  if (x1p > refresh[ivar].x1p) then begin
    if (y1p > refresh[ivar].y1p) then begin
      if (x2p >= refresh[ivar].x2p) then begin
        if (y2p >= refresh[ivar].y2p) then begin
          // A top left corner in B: split B
          jvar := refresh[ivar].y2p;
          refresh[ivar].y2p := y1p; // reduce B to top
          AddRefresh(refresh[ivar].x1p, y1p, x1p, jvar); // new left
          continue;
        end;
      end;
    end;
  end;

  if (x1p <= refresh[ivar].x1p) then begin
    if (y1p > refresh[ivar].y1p) then begin
      if (x2p < refresh[ivar].x2p) then begin
        if (y2p >= refresh[ivar].y2p) then begin
          // A top right corner in B: split B
          jvar := refresh[ivar].y2p;
          refresh[ivar].y2p := y1p; // reduce B to top
          AddRefresh(x2p, y1p, refresh[ivar].x2p, jvar); // new right
          continue;
        end;
      end;
    end;
  end;

  if (x1p <= refresh[ivar].x1p) then begin
    if (y1p <= refresh[ivar].y1p) then begin
      if (x2p < refresh[ivar].x2p) then begin
        if (y2p < refresh[ivar].y2p) then begin
          // A bottom right corner in B: split B
          jvar := refresh[ivar].y1p;
          refresh[ivar].y1p := y2p; // reduce B to bottom
          AddRefresh(x2p, jvar, refresh[ivar].x2p, y2p); // new right
          continue;
        end;
      end;
    end;
  end;

 end;
end;
{$endif sakucon}

// ------------------------------------------------------------------

procedure UpdateCoscosTable;
// Interpolate a coscos table suitable for the current resolution.
var ivar, jvar, kvar, lvar, tabsize, flaguz : dword;
begin
 flaguz := 0;
 tabsize := 256;
 while tabsize < sysvar.mv_WinSizeX + sysvar.mv_WinSizeY do begin
  inc(flaguz);
  tabsize := 256 shl flaguz;
 end;

 if dword(length(coscos)) <= tabsize then begin
  setlength(coscos, tabsize + 1);
  log('New coscos: 0..' + strdec(tabsize));
  for ivar := 255 downto 0 do begin
   kvar := (mcg_costable[(mcg_costable[ivar] shr 8) xor $FF] + mcg_costable[ivar]) shr 1;
   lvar := (mcg_costable[(mcg_costable[ivar + 1] shr 8) xor $FF] + mcg_costable[ivar + 1]) shr 1;
   for jvar := (1 shl flaguz) - 1 downto 0 do begin
    coscos[ivar shl flaguz + jvar] :=
    ( kvar * byte(1 shl flaguz - jvar)
    + lvar * byte(jvar)
    + dword((1 shl flaguz) shr 1)
    ) div byte(1 shl flaguz);
   end;
  end;
 end;
end;

procedure DeleteGob(gobnum : dword);
// Immediately marks a gob as no longer existing. Deletes child gobs too.
var ivar : dword;
begin
 // safety
 if IsGobValid(gobnum) = FALSE then exit;

 // Mark the gob's former pixel position for redrawing, if gob was visible.
 with gob[gobnum] do
  if drawstate and 3 <> 0 then
   AddRefresh(locxp, locyp, locxp + longint(sizexp), locyp + longint(sizeyp));

 gob[gobnum].gobnamu := '';

 // Kill kids.
 for ivar := high(gob) downto gobnum + 1 do
  if (gob[ivar].parent = gobnum) then DeleteGob(ivar);
 // Kill related effects.
 for ivar := high(fx) downto 0 do
  if (fx[ivar].kind <> 0) and (fx[ivar].fxgob = gobnum)
  then begin
   if fx[ivar].poku <> NIL then begin freemem(fx[ivar].poku); fx[ivar].poku := NIL; end;
   fx[ivar].kind := 0;
  end;
 // Kill events.
 ivar := length(event.gob);
 while ivar <> 0 do begin
  dec(ivar);
  if event.gob[ivar].gobnum = gobnum then begin
   if ivar < dword(high(event.gob)) then event.gob[ivar] := event.gob[high(event.gob)];
   setlength(event.gob, length(event.gob) - 1);
  end;
 end;
end;

procedure UpdateGobLocp(gobnum : dword);
// Recalculates the pixel location of the gob based on its 32k coordinates.
// Doesn't update children. Call this while moving a gob. However, if
// a viewport changes, you should call UpdateGobSizep instead, since the
// meta offset depends on the size, and must be added to the final pixel
// offset.
// This also adds a screen refresh region.
begin
 if IsGobValid(gobnum) = FALSE then exit;

 with gob[gobnum] do begin
  // Mark the previous gob pixel position for redrawing, if gob visible.
  if drawstate and 3 <> 0 then
   AddRefresh(locxp, locyp, locxp + longint(sizexp), locyp + longint(sizeyp));

  if locx >= 0
  then locxp := (locx * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15
  else locxp := -((-locx * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15);
  if locy >= 0
  then locyp := (locy * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15
  else locyp := -((-locy * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15);

  inc(locxp, gfxlist[cachedgfx].ofsxp + viewport[inviewport].viewportx1p);
  inc(locyp, gfxlist[cachedgfx].ofsyp + viewport[inviewport].viewporty1p);

  // Mark the updated gob pixel position for redrawing, if gob visible.
  if drawstate and 3 <> 0 then
   AddRefresh(locxp, locyp, locxp + longint(sizexp), locyp + longint(sizeyp));
 end;
end;

procedure UpdateGobSizep(gobnum : dword);
// Recalculates the pixel size of the gob based on its graphic's original
// resolution versus its parent viewport, and the gob's multiplication
// factor. Doesn't update children. Call this if viewports are changing. This
// also adds a screen refresh region.
var ivar : dword;
begin
 if IsGobValid(gobnum) = FALSE then exit;

 with gob[gobnum] do begin
  // Mark the previous gob pixel position for redrawing, if gob visible.
  if drawstate and 3 <> 0 then
   AddRefresh(locxp, locyp, locxp + longint(sizexp), locyp + longint(sizeyp));

  ivar := GetPNG(gfxnamu);
  if ivar = 0 then begin
   LogError('PNG for ' + gfxnamu + ' not found');
   DeleteGob(gobnum);
   exit;
  end;

  // Calculate the new pixel size.
  sizexp := (PNGlist[ivar].origsizexp * viewport[inviewport].viewportsizexp + PNGlist[ivar].origresx shr 1) div PNGlist[ivar].origresx;
  sizeyp := (PNGlist[ivar].origframeheightp * viewport[inviewport].viewportsizeyp + PNGlist[ivar].origresy shr 1) div PNGlist[ivar].origresy;
  // Apply the size multiplier. (32k = 100%)
  if sizemultiplier <> 0 then begin
   sizexp := (sizexp * sizemultiplier + 16384) shr 15;
   sizeyp := (sizeyp * sizemultiplier + 16384) shr 15;
  end;

  cachedgfx := CacheGfx(gfxnamu, sizexp, sizeyp, TRUE);
 end;

 // Update the location too, it may depend on the new size.
 UpdateGobLocp(gobnum);
end;

procedure InitGob(gobnum : dword);
// Inits a gob to basically zero values at almost everything. Expands the
// gob array if needed.
var ivar : dword;
begin
 // Expand gob array if necessary, zero out newly created indexes.
 if gobnum >= dword(length(gob)) then begin
  ivar := length(gob);
  setlength(gob, gobnum + 6); // allocate with some headroom
  fillbyte(gob[ivar], sizeof(gobtype) * (gobnum + 6 - ivar), 0);
 end else begin
  // Existing index.
  ivar := 0;
  if IsGobValid(gobnum) then ivar := gob[gobnum].drawstate;
  gob[gobnum].gobnamu := '';
  gob[gobnum].gfxnamu := '';
  fillbyte(gob[gobnum], sizeof(gobtype), 0);
  gob[gobnum].alphaness := $FF;
 end;
end;

procedure UpdateViewport(viewnum : dword);
// If you've changed any viewport parameters, call this afterward to
// recalculate the viewport's pixel values and propagate the changes to any
// child viewports. This also adds a screen refresh region.
// This also needs to be called for viewport 0 on window size change, and the
// new window size must first go in viewport[0].viewportsizexyp.
var ivar : dword;
    newsxp, newsyp, lbxp, lbyp : dword;
    newx1p, newy1p, newx2p, newy2p : longint;
begin
 if viewnum >= dword(length(viewport)) then begin
  LogError('UpdateViewport: viewport ' + strdec(viewnum) + ' doesn''t exist');
  exit;
 end;
 log('Updating viewport ' + strdec(viewnum));
 // Mark the previous viewport pixel position for redrawing.
 with viewport[viewnum] do
  AddRefresh(viewportx1p, viewporty1p, viewportx2p, viewporty2p);

 if viewnum = 0 then with viewport[0] do begin
  // The full game window just needs to reflect sizexyp.
  viewportsizexp := sysvar.mv_WinSizeX;
  viewportsizeyp := sysvar.mv_WinSizeY;
  viewportx1p := 0; viewportx2p := viewportsizexp;
  viewporty1p := 0; viewporty2p := viewportsizeyp;
  viewportratiox := viewportsizexp;
  viewportratioy := viewportsizeyp;
  UpdateCoscosTable;
 end else begin
  // Child viewports inherit their size from their parent.
  if viewport[viewnum].viewportparent >= viewnum then begin
   LogError('UpdateViewport: viewport ' + strdec(viewnum) + ' parent ' + strdec(viewport[viewnum].viewportparent) + ' can''t be below child');
   exit;
  end;
  // Start from the parent's pixel coords.
  with viewport[viewport[viewnum].viewportparent] do begin
   newx1p := viewportx1p; newy1p := viewporty1p;
   newx2p := viewportx2p; newy2p := viewporty2p;
   newsxp := viewportsizexp; newsyp := viewportsizeyp;
  end;
  log('Parent viewport ' + strdec(viewport[viewnum].viewportparent) + ': ' + strdec(newx1p) + ',' + strdec(newy1p) + ' to ' + strdec(newx2p) + ',' + strdec(newy2p));
  with viewport[viewnum] do begin
   {$ifndef sakucon}
   // Apply letterboxing. (In console mode, skip this as unworkable.)
   if (viewportratiox <> 0) and (viewportratioy <> 0) then begin
    // To transform the current viewport to the required aspect ratio:
    // new width = cury * reqx / reqy
    // new height = curx * reqy / reqx
    lbxp := (newsyp * viewportratiox + viewportratioy shr 1) div viewportratioy;
    lbyp := (newsxp * viewportratioy + viewportratiox shr 1) div viewportratiox;
    // One will require enlarging the current viewport, the other shrinking
    // it. We have to stay within the parent, so we can only shrink.
    if lbxp < newsxp then begin
     inc(newx1p, (newsxp - lbxp) shr 1); // center horizontally
     newx2p := newx1p + longint(lbxp);
     newsxp := lbxp;
    end;
    if lbyp < newsyp then begin
     inc(newy1p, (newsyp - lbyp) shr 1); // center vertically
     newy2p := newy1p + longint(lbyp);
     newsyp := lbyp;
    end;
    log('Letterbox ratio ' + strdec(viewportratiox) + ':' + strdec(viewportratioy) + ' -> ' + strdec(newx1p) + ',' + strdec(newy1p) + ' to ' + strdec(newx2p) + ',' + strdec(newy2p));
   end;
   {$endif}
   // Apply 32k coords within the newxp:newyp box to get final values.
   if viewportx2 < viewportx1 then viewportx2 := viewportx1;
   if viewporty2 < viewporty1 then viewporty2 := viewporty1;
   log('32k position: ' + strdec(viewportx1) + ',' + strdec(viewporty1) + ' to ' + strdec(viewportx2) + ',' + strdec(viewporty2));
   if viewportx1 >= 0 then viewportx1p := newx1p + (viewportx1 * longint(newsxp) + 16384) shr 15
   else viewportx1p := newx1p - (-viewportx1 * longint(newsxp) + 16384) shr 15;
   if viewportx2 <= 32768 then viewportx2p := newx2p - ((32768 - viewportx2) * longint(newsxp) + 16384) shr 15
   else viewportx2p := newx2p + ((viewportx2 - 32768) * longint(newsxp) + 16384) shr 15;
   if viewporty1 >= 0 then viewporty1p := newy1p + (viewporty1 * longint(newsyp) + 16384) shr 15
   else viewporty1p := newy1p - (-viewporty1 * longint(newsyp) + 16384) shr 15;
   if viewporty2 <= 32768 then viewporty2p := newy2p - ((32768 - viewporty2) * longint(newsyp) + 16384) shr 15
   else viewporty2p := newy2p + ((viewporty2 - 32768) * longint(newsyp) + 16384) shr 15;
   viewportsizexp := viewportx2p - viewportx1p;
   viewportsizeyp := viewporty2p - viewporty1p;
   log('Viewport now ' + strdec(viewportx1p) + ',' + strdec(viewporty1p) + ' to ' + strdec(viewportx2p) + ',' + strdec(viewporty2p) + ' (' + strdec(viewportsizexp) + 'x' + strdec(viewportsizeyp) + ')');
  end;
 end;

 // Mark the updated viewport pixel position for redrawing.
 with viewport[viewnum] do
  AddRefresh(viewportx1p, viewporty1p, viewportx2p, viewporty2p);

 // Refresh all children of this viewport.
 ivar := viewnum + 1;
 while ivar < dword(length(viewport)) do begin
  if viewport[ivar].viewportparent = viewnum then UpdateViewport(ivar);
  inc(ivar);
 end;

 // Refresh all gobs in this viewport.
 ivar := length(gob);
 while ivar <> 0 do begin
  dec(ivar);
  if gob[ivar].inviewport = viewnum then UpdateGobSizep(ivar);
 end;

 // Refresh all boxes in this viewport.
 ivar := length(TBox);
 while ivar <> 0 do begin
  dec(ivar);
  if (TBox[ivar].inviewport = viewnum) then TBox[ivar].contentbufparamvalid := FALSE;
 end;

 // Refresh all area events in this viewport.
 ivar := length(event.area);
 while ivar <> 0 do with event.area[ivar] do begin
  dec(ivar);
  if x1 >= 0
  then x1p := (x1 * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15 + viewport[inviewport].viewportx1p
  else x1p := -((-x1 * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15) + viewport[inviewport].viewportx1p;
  if x2 >= 0
  then x2p := (x2 * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15 + viewport[inviewport].viewportx1p
  else x2p := -((-x2 * longint(viewport[inviewport].viewportsizexp) + 16384) shr 15) + viewport[inviewport].viewportx1p;
  if y1 >= 0
  then y1p := (y1 * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15 + viewport[inviewport].viewporty1p
  else y1p := -((-y1 * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15) + viewport[inviewport].viewporty1p;
  if y2 >= 0
  then y2p := (y2 * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15 + viewport[inviewport].viewporty1p
  else y2p := -((-y2 * longint(viewport[inviewport].viewportsizeyp) + 16384) shr 15) + viewport[inviewport].viewporty1p;
 end;
end;

procedure InitViewport(viewnum : dword);
// Inits a viewport to basically zero values at almost everything. This
// should probably refresh gobs/fx/boxes in the viewport too, but if this is
// only called during bootup, then it's not important.
var ivar : dword;
begin
 // Expand viewport array if necessary, reset all newly created indexes.
 if viewnum >= dword(length(viewport)) then begin
  ivar := length(viewport);
  setlength(viewport, viewnum + 1);
  while ivar < dword(high(viewport)) do begin
   InitViewport(ivar); inc(ivar);
  end;
 end;

 fillbyte(viewport[viewnum], sizeof(viewporttype), 0);
 with viewport[viewnum] do begin
  viewportx2 := 32768;
  viewporty2 := 32768;
  viewportx2p := sysvar.mv_WinSizeX; viewportsizexp := sysvar.mv_WinSizeX;
  viewporty2p := sysvar.mv_WinSizeY; viewportsizeyp := sysvar.mv_WinSizeY;
 end;
end;

procedure InitTextbox(boxnum : dword);
// Inits a box to basically zero values at almost everything.
var ivar : dword;

  procedure setbasics(b : dword);
  begin
   fillbyte(TBox[b], sizeof(boxtype), 0);
   with TBox[b] do begin
    origfontheight := 1200; // ~15px/400px
    contentwinmaxcols := $FFFFFFFF;
    contentwinmaxrows := $FFFFFFFF;
    contentwinmaxsizex := $FFFFFFFF;
    contentwinmaxsizey := $FFFFFFFF;
    marginleft := 768;
    marginright := 768;
    margintop := 400;
    marginbottom := 400;
    dword(style.textcolor) := ExpandColorRef($FFFF);
    dword(style.basecolor[0]) := ExpandColorRef($83AD);
    dword(style.basecolor[1]) := dword(style.basecolor[0]);
    dword(style.basecolor[2]) := ExpandColorRef($729D);
    dword(style.basecolor[3]) := dword(style.basecolor[2]);
    style.basefill := 2; // gradient
    style.poptime := 384;
    style.autovanish := TRUE;
    style.dobevel := 1;
   end;
  end;

begin
 // Expand TBox array if necessary, reset all newly created indexes.
 if boxnum >= dword(length(TBox)) then begin
  ivar := length(TBox);
  setlength(TBox, boxnum + 1);
  while ivar < dword(length(TBox)) do begin
   setbasics(ivar); inc(ivar);
  end;
 end else begin
  // Existing index.
  with TBox[boxnum] do begin
   setlength(txtcontent, 0);
   setlength(txtescapelist, 0);
   setlength(txtlinebreaklist, 0);
   setlength(style.decorlist, 0);
   setlength(style.outline, 0);
   if basebuf <> NIL then freemem(basebuf);
   if contentfullbuf <> NIL then freemem(contentfullbuf);
   if rowbuf <> NIL then freemem(rowbuf);
   if finalbuf <> NIL then freemem(finalbuf);
  end;
  setbasics(boxnum);
 end;
end;

procedure DestroyTextbox(boxnum : dword);
// Releases all memory for this box, and all boxes with a higher number.
var ivar : dword;
begin
 ivar := boxnum;
 while ivar < dword(length(TBox)) do
 with TBox[ivar] do begin
  if basebuf <> NIL then begin freemem(basebuf); basebuf := NIL; end;
  if contentfullbuf <> NIL then begin freemem(contentfullbuf); contentfullbuf := NIL; end;
  if rowbuf <> NIL then begin freemem(rowbuf); rowbuf := NIL; end;
  if finalbuf <> NIL then begin freemem(finalbuf); finalbuf := NIL; end;

  setlength(txtcontent, 0);
  setlength(txtescapelist, 0);
  setlength(txtlinebreaklist, 0);
  setlength(style.decorlist, 0);
  setlength(style.outline, 0);
  fillbyte(TBox[ivar], sizeof(boxtype), 0);

  // safeties
  if choicematic.choicebox = ivar then choicematic.choicebox := 1;
  if choicematic.highlightbox = ivar then choicematic.highlightbox := 2;

  inc(ivar);
 end;

 // Shrink the textbox array.
 setlength(TBox, boxnum + 1);
end;

procedure ResetAllBoxes;
// Sets all textboxes to defaults.
begin
 // Reset textboxes: release existing memory.
 DestroyTextbox(0);
 // Set the new amount of textboxes.
 InitTextbox(2);

 // Set styles to defaults
 with TBox[0] do begin // console/system box
  dword(style.basecolor[0]) := $B0B0B0FF;
  dword(style.basecolor[1]) := $B0B0B0FF;
  dword(style.basecolor[2]) := $909090FF;
  dword(style.basecolor[3]) := $808080FF;
  contentwinminsizex := 32000;
  contentwinmaxsizex := 32000;
  contentwinminsizey := 14000;
  contentwinmaxsizey := 14000;
  boxlocx := 16384; boxlocy := 0;
  anchorx := 16384; anchory := 0;
 end;
 with TBox[1] do begin // game text box
  boxlocx := 16384;
  boxlocy := 32000;
  anchorx := 16384;
  anchory := 32768;
  contentwinminrows := 4;
  contentwinmaxrows := 4;
  contentwinminsizex := 26214;
  contentwinmaxsizex := 26214;
  style.autowaitkey := TRUE;
 end;
end;

// ------------------------------------------------------------------

procedure ResetDefaults;
// Resets the engine state nearly completely to default values. Runscript
// calls this whenever someone wants to start executing the main script, to
// ensure returning to main menu will not have carryover oddities.
var ivar : dword;
begin
 mv_ProgramName := sysvar.activeprojectname;
 SetProgramName(mv_ProgramName);
 // Init/restart the variable monster. Languagelist was set equal to the
 // number of languages when the DAT was loaded. We'll start with 16 variable
 // buckets, plenty for most purposes.
 VarmonInit(length(languagelist), 16);

 // Viewports
 setlength(viewport, 0);
 InitViewport(0);

 with gamevar do begin
  defaulttextbox := 1;
  defaultviewport := 0;
 end;
 with choicematic do begin
  choicebox := 1;
  choicepartbox := 1;
  highlightbox := 2;
  numcolumns := 4;
  colwidthp := 0;
  choiceparent := '';
  previouschoice := '';
  onhighlight := '';
  setlength(choicelist, 0);
  setlength(showlist, 0);
  choicelistcount := 0;
  showcount := 0;
  highlightindex := 0;
  previouschoiceindex := 0;
  printchoiceparent := TRUE;
  active := FALSE;
 end;

 pausestate := PAUSESTATE_NORMAL;
 metastate := METASTATE_NORMAL;

 // Reset events
 setlength(event.area, 0);
 setlength(event.gob, 0);
 setlength(event.timer, 0);
 event.normalint.triggerlabel := '';
 event.escint.triggerlabel := '';

 // Reset gobs
 setlength(gob, 12);
 for ivar := high(gob) downto 0 do gob[ivar].gobnamu := '';

 // Reset effects
 if length(fx) <> 0 then
 for ivar := high(fx) downto 0 do begin
  fx[ivar].kind := 0;
  if fx[ivar].poku <> NIL then begin freemem(fx[ivar].poku); fx[ivar].poku := NIL; end;
 end;
 setlength(fx, 6);
 fxcount := 0;
 transitionactive := $FFFFFFFF;

 // Reset all textboxes.
 ResetAllBoxes;

 // Reset various stuff
 RGBtweakactive := $FF;
 for ivar := 255 downto 0 do begin
  RGBtweakTable[ivar] := ivar;
  RGBtweakTable[ivar or 256] := ivar;
  RGBtweakTable[ivar or 512] := ivar;
 end;

 // Clear the screen too.
 setlength(refresh, 16); numfresh := 0;
 AddRefresh(0, 0, sysvar.mv_WinSizeX, sysvar.mv_WinSizeY);

 randomize;
end;

// ------------------------------------------------------------------

procedure SummonSaveLoad;
// If the game state allows it, shifts execution to the SAVELOAD script.
begin
 //if (scr^.gamestate in [1..4] = FALSE)
 //or (script[scr^.curnum].namu = 'SAVELOAD')
 //then exit;
 //RunScript('SAVELOAD');
end;

procedure SummonMetaMenu;
// If the game state allows it, creates a pop-up metamenu.
var ivar : dword;
begin
 // Special case: if esc-interrupt is defined, take it
 for ivar := high(fx) downto 0 do
  if (fx[ivar].kind = 14)
  then begin
   //ScriptGoto(fx[ivar].data, TRUE); exit;
  end;

 writeln('metamenu');
 exit;

 // Spawn the metamenu at the mouse cursor
 //flushinput := TRUE; // clicks outside popup menu are sent to main window!
end;

procedure SpawnSettingswindow;
begin
 writeln('settings');
end;

// ------------------------------------------------------------------

procedure LoadDatCommon(const loadname : UTF8string);
// Loads the given dat project name. Makes sure the dat's ancestors are
// loaded first, if they exist. Loadname must be in lowercase. You must call
// EnumerateDats before calling this.
var datnum, ivar : dword;
begin
 datnum := GetDat(loadname);
 if datnum >= dword(length(availabledatlist))
 then LogError('Dat not found: ' + loadname)
 else begin

  if availabledatlist[datnum].parentname <> '' then begin
   ivar := 0;
   while ivar < dword(length(datlist)) do begin
    if datlist[ivar].projectname = availabledatlist[datnum].parentname then break;
    inc(ivar);
   end;
   if ivar >= dword(length(datlist)) then begin
    log('Loading dat dependency ' + availabledatlist[datnum].parentname);
    LoadDatCommon(availabledatlist[datnum].parentname);
   end;
  end
  else if sysvar.activeprojectname <> availabledatlist[datnum].projectname
  then begin
   sysvar.activeprojectname := availabledatlist[datnum].projectname;
   log('Active project now: ' + sysvar.activeprojectname);
  end;

  if LoadDAT(availabledatlist[datnum].filenamu) <> 0
  then LogError(asman_errormsg);
 end;
end;

procedure EnumerateDats;
// Finds all DAT files under the working directory and under the user's
// profile directory, puts them in availabledatlist[]. If a DAT exists in
// both locations, the one in the user's profile is ignored. Dats whose
// filename is the same as their project name are pure dats, and any other
// are mods. Mods are removed from the list if their parent project dat isn't
// listed. The special supersakura.dat frontend is always removed. Finally,
// the list is sorted.
var filuhandle : file;
    currdir : UTF8string;
    filusr : TSearchRec;
    ivar, jvar, datnum : dword;
    fsresult : longint;

  procedure addthisfile;
  begin
   datnum := length(availabledatlist);
   if GetDat(lowercase(filusr.Name)) < datnum then begin
    log('Already added ' + currdir + filusr.Name);
    exit;
   end;

   setlength(availabledatlist, datnum + 1);
   availabledatlist[datnum].filenamu := currdir + filusr.Name;
   if ReadDATHeader(availabledatlist[datnum], filuhandle) = 0
   then begin
    close(filuhandle);
    log('Added ' + currdir + filusr.Name);
   end
   else begin
    log('Failed to add ' + currdir + filusr.Name + ': ' + asman_errormsg);
    setlength(availabledatlist, datnum);
   end;
  end;

begin
 log('Enumerating dats');
 setlength(availabledatlist, 0);
 // Find all dats under the working directory's data directory.
 currdir := saku_param.workdir + 'data' + DirectorySeparator;
 fsresult := FindFirst(currdir + '*', faReadOnly, filusr);
 while fsresult = 0 do begin
  if lowercase(ExtractFileExt(filusr.Name)) = '.dat' then addthisfile;
  fsresult := FindNext(filusr);
 end;
 FindClose(filusr);
 // Find all dats under the profile directory's data directory.
 currdir := saku_param.profiledir + 'data' + DirectorySeparator;
 fsresult := FindFirst(currdir + '*', faReadOnly, filusr);
 while fsresult = 0 do begin
  if lowercase(ExtractFileExt(filusr.Name)) = '.dat' then addthisfile;
  fsresult := FindNext(filusr);
 end;
 FindClose(filusr);

 // Check that parent/grandparent dats for all mods are present.
 datnum := length(availabledatlist);
 while datnum <> 0 do begin
  dec(datnum);
  ivar := datnum;
  jvar := $FF; // infinite loop detector
  repeat
   // If there's no parent name, it's a present pure dat.
   if availabledatlist[ivar].parentname = '' then break;
   // Otherwise this is a mod, so check if its parent dat is present.
   ivar := GetDat(availabledatlist[ivar].parentname);
   dec(jvar);
   if (ivar >= dword(length(availabledatlist))) or (jvar = 0) then begin
    // Parent is not present, drop the mod being checked.
    log('No parent for ' + availabledatlist[datnum].filenamu);
    if datnum + 1 < dword(length(availabledatlist)) then
     availabledatlist[datnum] := availabledatlist[length(availabledatlist) - 1];
    setlength(availabledatlist, length(availabledatlist) - 1);
    break;
   end;
  until FALSE;
 end;

 // Remove supersakura.dat if present.
 datnum := GetDat('supersakura');
 if datnum < dword(length(availabledatlist)) then begin
  log('Dropping ' + availabledatlist[datnum].filenamu);
  if datnum + 1 < dword(length(availabledatlist)) then
   availabledatlist[datnum] := availabledatlist[length(availabledatlist) - 1];
  setlength(availabledatlist, length(availabledatlist) - 1);
 end;

 // Sort the list.
end;

procedure ReadConfig;
var cfile : text;
    ivar, jvar, kvar : dword;
    cline, txt : UTF8string;
begin
 setlength(fontlist, 0);
 log('Reading config from ' + saku_param.workdir + saku_param.appname + '.ini');
 while IOresult <> 0 do; // flush
 assign(cfile, saku_param.workdir + saku_param.appname + '.ini');
 filemode := 0; reset(cfile); // read-only
 ivar := IOresult;
 if ivar <> 0 then LogError('ReadConfig ' + saku_param.workdir + saku_param.appname + '.ini: ' + errortxt(ivar))
 else begin
  while eof(cfile) = FALSE do begin
   // Read the config file a line at a time.
   readln(cfile, cline);
   // Empty line or a comment? Skip it.
   if (cline = '') or (cline[1] in ['/','#']) then continue;
   // Remove whitespace.
   ivar := 1;
   while (ivar <= dword(length(cline))) and (cline[ivar] = ' ') do inc(ivar);
   jvar := length(cline);
   while (jvar <> 0) and (cline[jvar] = ' ') do dec(jvar);
   if (ivar <> 1) or (jvar <> dword(length(cline)))
   then cline := copy(cline, ivar, jvar - ivar + 1);

   {$ifndef sakucon}
   // Font preference.
   if lowercase(copy(cline, 1, 5)) = 'font ' then begin
    // Grab the language name for this font.
    ivar := 6;
    while (ivar <= dword(length(cline))) and (cline[ivar] = ' ') do inc(ivar);
    jvar := ivar + 1;
    while (jvar <= dword(length(cline))) and (cline[jvar] <> ' ') do inc(jvar);
    txt := copy(cline, ivar, jvar - ivar);
    while (jvar <= dword(length(cline))) and (cline[jvar] = ' ') do inc(jvar);
    // Grab the match string and try to add it.
    if IsFontLangInList(txt) < dword(length(fontlist))
    then LogError('ReadConfig: fontlang already listed: ' + txt)
    else if AddFontLang(txt, copy(cline, jvar, length(cline))) = FALSE
    then LogError('No matching font found for ' + txt);
    continue;
   end;
   {$endif}

   // Vsync setting.
   if lowercase(copy(cline, 1, 6)) = 'vsync ' then begin
    txt := lowercase(copy(cline, 7, length(cline)));
    if (txt = 'on') or (txt = '1') or (txt = 'true') or (txt = 'enabled')
    or (txt = 'yes') or (txt = 'auto') then sysvar.usevsync := TRUE
    else sysvar.usevsync := FALSE;
   end;

   // Game window size.
   cline := lowercase(cline);
   if copy(cline, 1, 8) = 'winsize ' then begin
    ivar := 9;
    while (ivar < dword(length(cline))) and (cline[ivar] in ['0'..'9'] = FALSE) do inc(ivar);
    jvar := valx(copy(cline, ivar, $FF));
    inc(ivar, length(strdec(jvar)));
    kvar := valx(copy(cline, ivar, $FF));
    if (jvar = 0) or (kvar = 0) then sysvar.WinSizeAuto := TRUE else begin
     sysvar.WinSizeAuto := FALSE;
     sysvar.WindowSizeX := jvar;
     sysvar.WindowSizeY := kvar;
    end;
    continue;
   end;

  end;
  close(cfile);
 end;

 {$ifndef sakucon}
 // Try to make sure English and Japanese fonts are available. If a font
 // doesn't exist for the given language, this will work down the list and
 // stops at the first font found for each language. Fonts at the top are
 // subjectively nicer-looking.
 if IsFontLangInList('English') >= dword(length(fontlist)) then
 // serifed
 if AddFontLang('English', 'fp9r*') = FALSE then // FPL Neu
 if AddFontLang('English', 'bkant*') = FALSE then // Book Antiqua
 if AddFontLang('English', 'pala*') = FALSE then // Palatino
 if AddFontLang('English', 'deja?u?erif*') = FALSE then // DejaVu Serif
 // sans
 if AddFontLang('English', 'tahoma*') = FALSE then // Tahoma
 if AddFontLang('English', 'liberation*egular*') = FALSE then // Liberation
 if AddFontLang('English', 'droid*') = FALSE then // Droid
 if AddFontLang('English', 'roboto-?egular*') = FALSE then // Roboto
 if AddFontLang('English', 'noto*egular*') = FALSE then // Noto
 AddFontLang('English', 'cour*'); // Courier

 if IsFontLangInList('Japanese') >= dword(length(fontlist)) then
 if AddFontLang('Japanese', 'yumin*') = FALSE then // Yu Mincho
 if AddFontLang('Japanese', 'hana?in*') = FALSE then // Hanazono Mincho
 if AddFontLang('Japanese', 'noto?ansCJKjp-?egular*') = FALSE then // Noto
 if AddFontLang('Japanese', 'noto?ans?????-?egular*') = FALSE then // Noto
 if AddFontLang('Japanese', 'meiryo*') = FALSE then // MS Meiryo
 AddFontLang('Japanese', 'msgothic*'); // MS Gothic
 {$endif}
end;

procedure WriteConfig;
var cfile : text;
    ivar : dword;
begin
 log('Writing config to ' + saku_param.workdir + saku_param.appname + '.ini');
 while IOresult <> 0 do; // flush
 assign(cfile, saku_param.workdir + saku_param.appname + '.ini');
 filemode := 1; rewrite(cfile); // write-only
 ivar := IOresult;
 if ivar <> 0 then LogError('WriteConfig ' + saku_param.workdir + saku_param.appname + '.ini: ' + errortxt(ivar))
 else begin
  writeln(cfile, '# SuperSakura configuration');
  writeln(cfile, '');
  // video settings
  writeln(cfile, '# Game window size in windowed mode. Set to "auto" to use the game''s default');
  writeln(cfile, '# resolution, scaled as large as comfortably fits on your screen.');
  writeln(cfile, '# Override the default by giving a pixel size, for example: WinSize 512x384');
  write(cfile, 'winsize ');
  if sysvar.WinSizeAuto then writeln(cfile, 'auto') else writeln(cfile, strdec(sysvar.WindowSizeX) + 'x' + strdec(sysvar.WindowSizeY));
  {$ifndef sakucon}
  writeln(cfile, '');
  writeln(cfile, '# Preferred font for each language. You must specify a font file name, with');
  writeln(cfile, '# optional * and ? wildcards. The first matching .ttf/.otf file in the given');
  writeln(cfile, '# directory or in standard system font directories will be used. Examples:');
  writeln(cfile, '# font English Times*');
  writeln(cfile, '# font Japanese ~/myfonts/kittens-serif-bold.ttf');
  if length(fontlist) <> 0 then
   for ivar := 0 to high(fontlist) do
    writeln(cfile, 'font ', fontlist[ivar].fontlang, ' ', fontlist[ivar].fontmatch);

  writeln(cfile, '');
  writeln(cfile, '# Vertical sync. Enabling this may reduce the frame rate, but looks nicer.');
  if sysvar.usevsync then writeln(cfile, 'vsync on')
  else writeln(cfile, 'vsync off');
  {$endif}
  // audio settings
  // other settings

  close(cfile);
 end;
end;

procedure SetPauseState(newstate : tpausestate);
// Call to switch cleanly between pause states.
begin
 if (newstate = PAUSESTATE_PAUSED) and (pausestate <> PAUSESTATE_PAUSED)
 then begin
  SetProgramName(mv_ProgramName + ' [paused]');
 end else
 if (newstate <> PAUSESTATE_PAUSED) and (pausestate = PAUSESTATE_PAUSED)
 then begin
  SetProgramName(mv_ProgramName);
 end;

 pausestate := newstate;
end;
