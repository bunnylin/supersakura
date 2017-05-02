program SuperSakura;

{                                                                           }
{ SuperSakura engine :: Copyright 2009-2017 :: Kirinn Bunnylin / Mooncore   }
{ https://mooncore.eu/ssakura                                               }
{ https://github.com/something                                              }
{                                                                           }
{ This program is free software: you can redistribute it and/or modify      }
{ it under the terms of the GNU General Public License as published by      }
{ the Free Software Foundation, either version 3 of the License, or         }
{ (at your option) any later version.                                       }
{                                                                           }
{ This program is distributed in the hope that it will be useful,           }
{ but WITHOUT ANY WARRANTY; without even the implied warranty of            }
{ MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             }
{ GNU General Public License for more details.                              }
{                                                                           }
{ You should have received a copy of the GNU General Public License         }
{ along with this program.  If not, see <https://www.gnu.org/licenses/>.    }
{ ------------------------------------------------------------------------- }
{                                                                           }
{ Targets FPC 3.0.2 for Linux/Win, 32/64-bit.                               }
{                                                                           }
{ Compilation dependencies:                                                 }
{ - Pascal translation of SDL2 headers (27-Mar-2017)                        }
{   https://github.com/ev1313/Pascal-SDL-2-Headers                          }
{ - Various moonlibs                                                        }
{   https://github.com/something                                            }
{                                                                           }
{ Runtime dependencies:                                                     }
{ - Simple DirectMedia Library SDL2 and SDL2_ttf (2.0.5)                    }
{   https://libsdl.org                                                      }
{                                                                           }

{$mode fpc}
{$ifdef WINDOWS}{$apptype console}{$endif}
{$codepage UTF8}
{$asmmode intel}
{$I-}
{$inline on}
{$unitpath inc}
{$WARN 4079 off} // Spurious hints: Converting the operands to "Int64" before
{$WARN 4080 off} // doing the operation could prevent overflow errors.
{$WARN 4081 off}
{$WARN 5090 off} // Variable of a managed type not initialised, supposedly.

// ---------------------- ===== TO DO ===== -------------------------
// SuperSakura
// FUTURE
// - Consider an Android port, if FPC support improves?
// - Consider trimming FPC's System and Sysutils units to save space?
// - Audio (full FM etc softsynth)
//    + Build a library of custom chip sound effects (rip some from Alleycat
//      at least), use those in the games as appropriate
// - Add some scriptable customisation to the settings dialog?
// - Switch custom mouse cursor to be engine-drawn, Win support for custom
//   cursors is too convoluted to rely on across different screen modes, not
//   to mention compatibility across operating systems; or perhaps cursor
//   changing should be dropped as too much trouble for minimal reward
// - Eye candy
//    + Add a pixelisation effect, dynamically slidable pixel size?
//    + Add nice wind for sakura petals and snowfall
//    + Add a sunlight effect; perhaps full starburst with loc/speed vars
//    + Add a rain effect
//    + Add a horizontal blur effect, doubled vision (use in sakura CS704)
// - Add graphic scaling at run-time in scriptcode? Scalesizex/y? A rescale
//   cache used solely by the Renderer routine, so when a gob of unusual size
//   is requested, it's rescaled and cached? Smooth size slides done this way
//   might be pretty heavy, particularly if using BunnyScaler...
// - Automated testing stuff:
//    + Commandline switch/debug option to disable frame limiter; it needs
//      to set the per-frame delay to 0 and override the millisecs elapsed
//      calculation with a constant 64 ms. Allow switch to set constant?
//    + Add a randomtest commandline switch/debug option; it clears text
//      boxes as they come up, and selects random multiple choice options
//      by simulating button presses; and if there are clickable items, it
//      needs to click on a random one, except in main script it should
//      always pick item 1 (Start Game). Also do a bunch of random mouseons
//      and offs for overable items, if any.
//    + Save every button press and non-move mouse event incl. mouseovers
//      in an internal buffer that needs to be dumped in a text file in case
//      of abnormal program exit; add a commandline switch/debug option to
//      play back virtual input from a file like this. The text file dump
//      should also have remarks to clarify current script location (offset?
//      label?) and the strings of choices selected.
// - Extra content as optional mods!
//    + Sad face for sakura/Hidemi-okaasan
//    + Import the shrine background from FromH, insert as brief extra scene
//      in runaway once or twice, to foreshadow and remind about the tree
//    + Import the church at night from Parfait, insert in Saku/Seia's story
//    + Runaway is the most linear of the classics; add choices for bypassing
//      some H-scenes, resulting in mildly different epilogue segments; add
//      an extra textual ending or two based on how Hiroaki comes to terms
//      with his power?
//    + 3sis has too much exposition at the beginning, streamline it
//    + Runaway needs a clickable map when moving around downtown
//    + 3sis needs a clickable map when moving around the school
//    + Expanded soundtrack mod, subtle variations on existing themes?
//    + Eye-blinkies for event graphics wherever appropriate
// REQUIRED FOR 1.0
// - Add runtime modification loading, eg. game language switching
//   (by loading game_*.mod, each needs title and description blocks;
//   use global save file per game to allow mod selection to persist)
// - Add auto-update capability from UPD files; if DAT to be patched is
//   write-protected, rename UPD to MOD, notify user, copy to appdata\, and
//   automatically add it to enabled mods
// - Create a Settings dialog, video and audio config
//    + Needs a simple widget system of our own; existing ones would probably
//      work well except I'd like gamepad support; most likely layout will be
//      something like PPSSPP menus, a vertical list that scrolls, with the
//      item names on the left and the values on the right
// - Create a game/dat selection dialog, something like ScummVM
// - Add a friendly button in game/dat selecion dialog to directly convert
//   games to ssakudats
//    + Integrate decomp/beautify/recomp in supersakura?
//    + Source dir selection may require a separate UI, current choicebox
//      design doesn't really work with directory tree traversal; perhaps
//      just put in a text field and tell the user to type the directory...
//      Vertical-only choicebox could forward left/right presses to area
//      events, allowing a file list and actions at the same time?
// - Implement a basic save/load state command; remember to save all array
//   sizes in save file; even if constant, it may be desirable to expand them
//   in the future, and it's better to save stuff dynamically anyway; make
//   save files DAT-style modular
//    + Various gamevars should be moved into varmon for easier saving
// - Create a save/load dialog, accessing separate .Sxx files
// - 8 autosave slots, use a timer and save once every five minutes during
//   waitkey or waitevent, but only if saves allowed (also check if
//   allownosaves persists properly when returning to a script)
// - Check how well multiple displays and hi-DPI are working
// - Textboxes:
//    + Add test for if normal text and choices can now coexist in boxes
//    + Add a box padding parameter; boxsize = content + margins + padding;
//      background gradient, texture, and bevel apply to non-padded area, but
//      frame decor is relative to the padded area
//    + Add a box drop shadow?
//    + Add more bevelling parameters, to allow shaped bevels etc
//    + In addition to a primary text color, allow for a color gradient?
//    + Implement text outlines, with RGBA color, thickness, offset, and the
//      option to fade alpha to transparent toward the outline edge; the
//      thickness and offset must be 32k values relative to fontheight
// - See if can read TTF etc headers to find font face names, that would
//   allow quick font enumeration at startup and then friendly selection
// - Implement drop-down console in box 0
// - The drop-down console should probably work in two modes: either show all
//   debug stdout text, or show a game text transcript as you play, which can
//   be brought up if you missed a textbox accidentally; should probably have
//   a way to dump all contents of either log into a text file
// - Try calling dumpexceptionbacktrace in the exit block??
// - Skip seen text is cumbersome if implemented per-string, but it could
//   work well on a per-label basis, with far less user state to track
// - Reimplement precipitation effects
// - Change animation sequence handling to run code snippets in minifibers
//   instead of the current special syntax monstrosity; anim snippets should
//   be a list of their own, and gobs and box decors point to list items
// - Develop a proper Bunnyscaler, or use an existing pixel scaler
// - Rework Moonsynth into Bunnysynth, plain midi; as for sound effects,
//   consider internal support for wav/flac/opus
// - Make the pre-cacher read ahead in bytecode from the current position to
//   chart out all potential needed graphics at least a couple
//   waitkeys/sleeps/if-jumps away; pre-cacher also needs to strongly
//   prioritise big pictures since small ones can be loaded at runtime almost
//   instantly anyway
// - Implement the software pixel shader style thing to replace the old
//   renderer; subpixel repositioning will have to go here too
// - Metamenu viewframe option: can be handled in script; game window size
//   changes or fullscreen toggles must be completely transparent to the
//   script, and UI may not be modified by the script depending on window
//   pixel size
// ONGOING
// - Re-implement gob/area events
// - Re-implement quick RGB tweak?
// - Gob move effect
// - Make fullscreen switch work again, and sakucon react to term resize
// - Revise main scripts for all supported games
// - Fix Eden suspect parade visuals
// - Add transitions wipe from left, ragged dissipate right; map transitions
//   during decomp to the available set
// - By default, binaries should be in a write-protected executable
//   directory; writable subdirectories for "data" and "save" will be
//   used for the other stuff, or if they don't exist and cannot be
//   created, they are put under the user's home directory as appropriate
//
// ------------------------------------------------------------------
// Recomp
// FUTURE
// - When adding support to more games:
//    + Write intro and ending scripts, new title screens
//    + Make program icons and textboxes (box idea: a raised decoration on
//      the left going higher than rest of box, leaving a snug corner/slot
//      for a title box to fit in, title box can have diagonal far edge)
//    + Touch up all graphics to eliminate artifacts
//    + Go over all scripts, add hacks in decomp to use cool new effects
//    + Consider adding sound effects and ambient sounds?
// REQUIRED FOR 1.0
// - Make a mod that inserts new special effects all over the scripts
// - data.txt: add entries for gamename, gameversion, modname, moddesc
// - Make program icons for all three games
// - Add intros for the prime three
// - Add music conversion options in data.txt; needs instrument mappings and
//   vol/key transposing at least; useful for .M or .O files
// ONGOING
// - Old main/endings/intro scripts need a syntax update
// BUGS
// - Nothing!
//
// ------------------------------------------------------------------
// Decomp
// FUTURE
// - Support for new games
// - Improved game support:
//    + Proper translation of the few remaining odd bytecodes
//    + Figure out the .O music format
//    + Fix incorrect .SC5 looping in FromH
//    + Add a tilemap mode? for top-down jrpg adventures like Vanishing Point
//    + Tasogare needs a wolf3d-style dungeon, and an automap
// - Check the broken Deep graphics in the original, just keep jumping ahead
//   in scripts until find one or two; if they still look corrupt, write
//   a brute force fixer to guess at what the corrupt bytes should be
// - Treat .hdi and .fdi files as subdirectories, if can figure out the
//   format, so it'll be easier to convert games
// REQUIRED FOR 1.0
// - Add color to dialogue titles?
// - Specific global vars with known uses in games should be named
// - Fix music conversion, polish code
// - Integrate Beautify
// ONGOING
// - Nothing!
// BUGS
// - Use v512 for endings in 3sis SK_737, SK_738 and SK_743
//
// ------------------------------------------------------------------
// Bunnylin's Brilliant Beautifier
// FUTURE
// - Nothing!
// REQUIRED FOR 1.0
// - Touch up all Sakura graphics (112 sprites, 52 anims, 94 event pictures,
//   90+ other pictures)
// - Touch up all 3sis graphics (40 sprites, 40 anims, 90 event pictures,
//   30+ other pictures)
// - Touch up all Runaway graphics (22 sprites, 22 anims, 72 event pictures,
//   50+ other pictures)
// - Touch up common pictures (about 16 from Xfer, 7 otherwise)
// - Touch up remaining other pictures (about 150...)
// - Modularise Beautify into a unit, usable by ssakura/Decomp/Detailer
// ONGOING
// - Nothing!
// BUGS
// - Finish refactoring and clean the code so it'll work again...
//
// ------------------------------------------------------------------
// Other
// FUTURE
// - Investigate FLIF compression, switch from PNG to save 25% space? Without
//   image editing tool support, would make resource modification harder, so
//   would have to keep images as PNGs while unbundled and FLIFs only in
//   bundles; would preferably need a pasflif unit to minimise dependencies,
//   but no one's made one yet; flif code seems a bit complex, might take
//   about two weeks to write a pascal version...
// REQUIRED FOR 1.0
// - Put up a bitcoin address for donations
// - Make vector graphic funny thanks-images to thank donaters?
//    + 3sis: Emi glowering at Risa over logo, Yuki in middle with drop
//    + Runaway: Hiroaki with two clingy chicks shouted at by wossname?
//    + Sakura: Last Supper scene in classroom, desks piled at door
// - MCGLoder.mcg_ScaleBitmap32: in horizontal shrink, use source^ directly?
// ONGOING
// - Nothing!
// -------------------- ===== TO DO END ===== -----------------------

uses sysutils, // needed for file traversal etc
     SDL2,
     SDL2_ttf,
     mcvarmon, // script variable handling system
     mcgloder, // graphics loading and resizing
     mcsassm, // general asset management, streaming stuff from DAT-files
     mccommon, // helper routines
     paszlib; // standard compression/decompression unit for savegames etc

// Basic structures, helper functions.
{$include inc/sakucommon.pas}

// Text box functions.
{$include inc/sakubox-sdl.pas}

// Gob functions.
{$include inc/sakugobs.pas}

// Special effects setup and execution.
{$include inc/sakueffects.pas}

// Rendering and visual effect functions.
{$include inc/sakurender-sdl.pas}

// Choicematic functions.
{$include inc/sakuchoicematic.pas}

// Sakurascript compiler and types.
{$include inc/ssscript.pas}

// Sakurascript execution, fiber handling system, and helpers.
{$include inc/sakufiber.pas}

// User input handling.
{$include inc/sakuinput.pas}

// SDL-specific init, main loop, input handling, output display.
{$include inc/sakubase-sdl.pas}

// ------------------------------------------------------------------

begin
 if DoParams = FALSE then exit;
 if InitEverything = FALSE then exit;
 MainLoop;
 WriteConfig;
end.
