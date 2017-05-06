program SuperSakura;

{                                                                           }
{ SuperSakura engine :: Copyright 2009-2017 :: Kirinn Bunnylin / Mooncore   }
{ https://mooncore.eu/ssakura                                               }
{ https://github.com/bunnylin/supersakura                                   }
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
{   https://github.com/bunnylin/moonlibs                                    }
{                                                                           }
{ Runtime dependencies:                                                     }
{ - Simple DirectMedia Library SDL2 and SDL2_ttf (2.0.5)                    }
{   https://libsdl.org                                                      }
{                                                                           }

{$mode fpc}
{$ifdef WINDOWS}{$apptype console}{$endif}
{$codepage UTF8}
{$I-}
{$inline on}
{$unitpath inc}

{$WARN 4079 off} // Spurious hints: Converting the operands to "Int64" before
{$WARN 4080 off} // doing the operation could prevent overflow errors.
{$WARN 4081 off}
{$WARN 5090 off} // Variable of a managed type not initialised, supposedly.

uses sysutils, // needed for file system traversal etc
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
