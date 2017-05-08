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

// SakuraScript
// Defines and a function for converting a UTF-8 buffer into bytecode.

// Define this to get various debug output as standard output
{$define !ssscriptdebugoutput}

// Word of power parameter enums
const
WOPP_DYNAMIC = 0; // autofit to next appropriate parameter type
WOPP_ALLFX = 3;
WOPP_ALPHA = 5;
WOPP_ANCHORX = 7;
WOPP_ANCHORY = 8;
WOPP_BOX = 10;
WOPP_BY = 12;
WOPP_COLOR = 16;
WOPP_FIBER = 18;
WOPP_FRAME = 20;
WOPP_FREQ = 22;
WOPP_GAMMA = 24;
WOPP_GOB = 26;
WOPP_INDEX = 28;
WOPP_LABEL = 30;
WOPP_LOCX = 32;
WOPP_LOCY = 33;
WOPP_MOUSEOFF = 35;
WOPP_MOUSEON = 36;
WOPP_NAME = 38;
WOPP_NOCLEAR = 40;
WOPP_PARENT = 42;
WOPP_RATIOX = 44;
WOPP_RATIOY = 45;
WOPP_SIZEX = 47;
WOPP_SIZEY = 48;
WOPP_STYLE = 50;
WOPP_TEXT = 52;
WOPP_THICKNESS = 54;
WOPP_TIME = 55;
WOPP_TYPE = 57;
WOPP_VALUE = 58;
WOPP_VAR = 59;
WOPP_VIEWPORT = 61;
WOPP_ZLEVEL = 63;

// Word of power parameter definitions
// Must be arranged in ascending ascii order!
const ss_rwopplist : array[0..38] of record
  id : string[13];
  code : byte;
end = (
// WOPP_DYNAMIC has special handling, so it's not listed among these
(id : 'allfx';         code : WOPP_ALLFX),
(id : 'alpha';         code : WOPP_ALPHA),
(id : 'anchorx';       code : WOPP_ANCHORX),
(id : 'anchory';       code : WOPP_ANCHORY),
(id : 'box';           code : WOPP_BOX),
(id : 'by';            code : WOPP_BY),
(id : 'color';         code : WOPP_COLOR),
(id : 'fiber';         code : WOPP_FIBER),
(id : 'frame';         code : WOPP_FRAME),
(id : 'freq';          code : WOPP_FREQ),
(id : 'gamma';         code : WOPP_GAMMA),
(id : 'gob';           code : WOPP_GOB),
(id : 'index';         code : WOPP_INDEX),
(id : 'label';         code : WOPP_LABEL),
(id : 'locx';          code : WOPP_LOCX),
(id : 'locy';          code : WOPP_LOCY),
(id : 'mouseoff';      code : WOPP_MOUSEOFF),
(id : 'mouseon';       code : WOPP_MOUSEON),
(id : 'name';          code : WOPP_NAME),
(id : 'noclear';       code : WOPP_NOCLEAR),
(id : 'ofsx';          code : WOPP_LOCX),
(id : 'ofsy';          code : WOPP_LOCY),
(id : 'parent';        code : WOPP_PARENT),
(id : 'ratiox';        code : WOPP_RATIOX),
(id : 'ratioy';        code : WOPP_RATIOY),
(id : 'sizex';         code : WOPP_SIZEX),
(id : 'sizey';         code : WOPP_SIZEY),
(id : 'style';         code : WOPP_STYLE),
(id : 'text';          code : WOPP_TEXT),
(id : 'thickness';     code : WOPP_THICKNESS),
(id : 'time';          code : WOPP_TIME),
(id : 'type';          code : WOPP_TYPE),
(id : 'value';         code : WOPP_VALUE),
(id : 'var';           code : WOPP_VAR),
(id : 'viewport';      code : WOPP_VIEWPORT),
(id : 'x';             code : WOPP_LOCX),
(id : 'y';             code : WOPP_LOCY),
(id : 'z';             code : WOPP_ZLEVEL),
(id : 'zlevel';        code : WOPP_ZLEVEL)
);

// Word of power enums
const
WOP_NOP = 0;
WOP_DEC = 2;
WOP_INC = 3;

WOP_MUS_PLAY = 0;
WOP_MUS_STOP = 0;

WOP_CALL = 35;
WOP_CASECALL = 36;
WOP_CASEGOTO = 37;
WOP_GOTO = 38;
WOP_RETURN = 39;

WOP_CHOICE_CALL = 40;
WOP_CHOICE_CANCEL = 41;
WOP_CHOICE_COLUMNS = 42;
WOP_CHOICE_GET = 43;
WOP_CHOICE_GOTO = 44;
WOP_CHOICE_OFF = 45;
WOP_CHOICE_ON = 46;
WOP_CHOICE_PRINTPARENT = 47;
WOP_CHOICE_REMOVE = 48;
WOP_CHOICE_RESET = 49;
WOP_CHOICE_SET = 50;
WOP_CHOICE_SETCHOICEBOX = 51;
WOP_CHOICE_SETHIGHLIGHTBOX = 52;
WOP_CHOICE_SETPARTBOX = 53;

WOP_GFX_ADOPT = 80;
WOP_GFX_BASH = 81;
WOP_GFX_CLEARALL = 82;
WOP_GFX_CLEARANIMS = 83;
WOP_GFX_CLEARBKG = 84;
WOP_GFX_CLEARKIDS = 85;
WOP_GFX_FLASH = 86;
WOP_GFX_GETFRAME = 87;
WOP_GFX_GETSEQUENCE = 88;
WOP_GFX_MOVE = 89;
WOP_GFX_PRECACHE = 90;
WOP_GFX_REMOVE = 91;
WOP_GFX_SETALPHA = 92;
WOP_GFX_SETFRAME = 93;
WOP_GFX_SETSEQUENCE = 94;
WOP_GFX_SETSOLIDBLIT = 95;
WOP_GFX_SHOW = 96;
WOP_GFX_TRANSITION = 97;

WOP_TBOX_CLEAR = 120;
WOP_TBOX_DECORATE = 121;
WOP_TBOX_OUTLINE = 122;
WOP_TBOX_POPIN = 123;
WOP_TBOX_POPOUT = 124;
WOP_TBOX_PRINT = 125;
WOP_TBOX_REMOVEDECOR = 126;
WOP_TBOX_REMOVEOUTLINES = 127;
WOP_TBOX_SETDEFAULT = 128;
WOP_TBOX_SETLOC = 129;
WOP_TBOX_SETNUMBOXES = 130;
WOP_TBOX_SETPARAM = 131;
WOP_TBOX_SETSIZE = 132;
WOP_TBOX_SETTEXTURE = 133;

WOP_FIBER_GETID = 160;
WOP_FIBER_SIGNAL = 161;
WOP_FIBER_START = 162;
WOP_FIBER_STOP = 163;
WOP_FIBER_WAIT = 164;
WOP_FIBER_WAITKEY = 165;
WOP_FIBER_WAITSIG = 166;
WOP_FIBER_YIELD = 167;

WOP_EVENT_CREATE_AREA = 189;
WOP_EVENT_CREATE_ESC = 190;
WOP_EVENT_CREATE_GOB = 191;
WOP_EVENT_CREATE_INT = 192;
WOP_EVENT_CREATE_TIMER = 193;
WOP_EVENT_MOUSEOFF = 194;
WOP_EVENT_MOUSEON = 195;
WOP_EVENT_REMOVE = 196;
WOP_EVENT_REMOVE_ESC = 197;
WOP_EVENT_REMOVE_INT = 198;
WOP_EVENT_SETLABEL = 199;

WOP_VIEWPORT_SETBKGINDEX = 200;
WOP_VIEWPORT_SETDEFAULT = 201;
WOP_VIEWPORT_SETGAMMA = 202;
WOP_VIEWPORT_SETPARAMS = 203;

WOP_SYS_QUIT = 255;
WOP_SYS_PAUSE = 254;
WOP_SYS_SETCURSOR = 253;
WOP_SYS_SETTITLE = 252;

// Reserved words of power
// Table mapping word of power strings to bytecode values
// Must be arranged in ascending ascii order!
var ss_rwoplist : array[0..123] of record
  namu : string[22];
  code : byte;
end = (
(namu : ''; code : WOP_NOP),
(namu : 'call'; code : WOP_CALL),
(namu : 'case'; code : WOP_CASEGOTO),
(namu : 'casecall'; code : WOP_CASECALL),
(namu : 'casegoto'; code : WOP_CASEGOTO),
(namu : 'choice.call'; code : WOP_CHOICE_CALL),
(namu : 'choice.cancel'; code : WOP_CHOICE_CANCEL),
(namu : 'choice.clear'; code : WOP_CHOICE_RESET),
(namu : 'choice.columns'; code : WOP_CHOICE_COLUMNS),
(namu : 'choice.disable'; code : WOP_CHOICE_OFF),
(namu : 'choice.enable'; code : WOP_CHOICE_ON),
(namu : 'choice.get'; code : WOP_CHOICE_GET),
(namu : 'choice.go'; code : WOP_CHOICE_GOTO),
(namu : 'choice.goto'; code : WOP_CHOICE_GOTO),
(namu : 'choice.jump'; code : WOP_CHOICE_GOTO),
(namu : 'choice.off'; code : WOP_CHOICE_OFF),
(namu : 'choice.on'; code : WOP_CHOICE_ON),
(namu : 'choice.printparent'; code : WOP_CHOICE_PRINTPARENT),
(namu : 'choice.remove'; code : WOP_CHOICE_REMOVE),
(namu : 'choice.reset'; code : WOP_CHOICE_RESET),
(namu : 'choice.set'; code : WOP_CHOICE_SET),
(namu : 'choice.setchoicebox'; code : WOP_CHOICE_SETCHOICEBOX),
(namu : 'choice.sethighlightbox'; code : WOP_CHOICE_SETHIGHLIGHTBOX),
(namu : 'choice.setpartbox'; code : WOP_CHOICE_SETPARTBOX),
(namu : 'dec'; code : WOP_DEC),
(namu : 'event.clear'; code : WOP_EVENT_REMOVE),
(namu : 'event.create.area'; code : WOP_EVENT_CREATE_AREA),
(namu : 'event.create.esc'; code : WOP_EVENT_CREATE_ESC),
(namu : 'event.create.escape'; code : WOP_EVENT_CREATE_ESC),
(namu : 'event.create.gob'; code : WOP_EVENT_CREATE_GOB),
(namu : 'event.create.int'; code : WOP_EVENT_CREATE_INT),
(namu : 'event.create.interrupt'; code : WOP_EVENT_CREATE_INT),
(namu : 'event.create.timer'; code : WOP_EVENT_CREATE_TIMER),
(namu : 'event.mouseoff'; code : WOP_EVENT_MOUSEOFF),
(namu : 'event.mouseon'; code : WOP_EVENT_MOUSEON),
(namu : 'event.remove'; code : WOP_EVENT_REMOVE),
(namu : 'event.remove.all'; code : WOP_EVENT_REMOVE),
(namu : 'event.remove.esc'; code : WOP_EVENT_REMOVE_ESC),
(namu : 'event.remove.escape'; code : WOP_EVENT_REMOVE_ESC),
(namu : 'event.remove.int'; code : WOP_EVENT_REMOVE_INT),
(namu : 'event.remove.interrupt'; code : WOP_EVENT_REMOVE_INT),
(namu : 'event.setlabel'; code : WOP_EVENT_SETLABEL),
(namu : 'fiber.getid'; code : WOP_FIBER_GETID),
(namu : 'fiber.signal'; code : WOP_FIBER_SIGNAL),
(namu : 'fiber.start'; code : WOP_FIBER_START),
(namu : 'fiber.stop'; code : WOP_FIBER_STOP),
(namu : 'fiber.wait'; code : WOP_FIBER_WAIT),
(namu : 'fiber.waitkey'; code : WOP_FIBER_WAITKEY),
(namu : 'fiber.waitsig'; code : WOP_FIBER_WAITSIG),
(namu : 'fiber.waitsignal'; code : WOP_FIBER_WAITSIG),
(namu : 'fiber.yield'; code : WOP_FIBER_YIELD),
(namu : 'gfx.adopt'; code : WOP_GFX_ADOPT),
(namu : 'gfx.bash'; code : WOP_GFX_BASH),
(namu : 'gfx.clearall'; code : WOP_GFX_CLEARALL),
(namu : 'gfx.clearanims'; code : WOP_GFX_CLEARANIMS),
(namu : 'gfx.clearbkg'; code : WOP_GFX_CLEARBKG),
(namu : 'gfx.clearkids'; code : WOP_GFX_CLEARKIDS),
(namu : 'gfx.create'; code : WOP_GFX_SHOW),
(namu : 'gfx.flash'; code : WOP_GFX_FLASH),
(namu : 'gfx.getframe'; code : WOP_GFX_GETFRAME),
(namu : 'gfx.getsequence'; code : WOP_GFX_GETSEQUENCE),
(namu : 'gfx.move'; code : WOP_GFX_MOVE),
(namu : 'gfx.precache'; code : WOP_GFX_PRECACHE),
(namu : 'gfx.remove'; code : WOP_GFX_REMOVE),
(namu : 'gfx.removeall'; code : WOP_GFX_CLEARALL),
(namu : 'gfx.removeanims'; code : WOP_GFX_CLEARANIMS),
(namu : 'gfx.removebkg'; code : WOP_GFX_CLEARBKG),
(namu : 'gfx.removekids'; code : WOP_GFX_CLEARKIDS),
(namu : 'gfx.setalpha'; code : WOP_GFX_SETALPHA),
(namu : 'gfx.setbackgroundindex'; code : WOP_VIEWPORT_SETBKGINDEX),
(namu : 'gfx.setbackgroundslot'; code : WOP_VIEWPORT_SETBKGINDEX),
(namu : 'gfx.setbkgindex'; code : WOP_VIEWPORT_SETBKGINDEX),
(namu : 'gfx.setbkgslot'; code : WOP_VIEWPORT_SETBKGINDEX),
(namu : 'gfx.setframe'; code : WOP_GFX_SETFRAME),
(namu : 'gfx.setparent'; code : WOP_GFX_ADOPT),
(namu : 'gfx.setsequence'; code : WOP_GFX_SETSEQUENCE),
(namu : 'gfx.setsolidblit'; code : WOP_GFX_SETSOLIDBLIT),
(namu : 'gfx.show'; code : WOP_GFX_SHOW),
(namu : 'gfx.transition'; code : WOP_GFX_TRANSITION),
(namu : 'goto'; code : WOP_GOTO),
(namu : 'inc'; code : WOP_INC),
(namu : 'jump'; code : WOP_GOTO),
(namu : 'mus.play'; code : WOP_MUS_PLAY),
(namu : 'mus.stop'; code : WOP_MUS_STOP),
(namu : 'nop'; code : WOP_NOP),
(namu : 'pause'; code : WOP_SYS_PAUSE),
(namu : 'print'; code : WOP_TBOX_PRINT),
(namu : 'quit'; code : WOP_SYS_QUIT),
(namu : 'return'; code : WOP_RETURN),
(namu : 'signal'; code : WOP_FIBER_SIGNAL),
(namu : 'sleep'; code : WOP_FIBER_WAIT),
(namu : 'stop'; code : WOP_FIBER_STOP),
(namu : 'sys.pause'; code : WOP_SYS_PAUSE),
(namu : 'sys.quit'; code : WOP_SYS_QUIT),
(namu : 'sys.setcursor'; code : WOP_SYS_SETCURSOR),
(namu : 'sys.settitle'; code : WOP_SYS_SETTITLE),
(namu : 'tbox.addoutline'; code : WOP_TBOX_OUTLINE),
(namu : 'tbox.clear'; code : WOP_TBOX_CLEAR),
(namu : 'tbox.decorate'; code : WOP_TBOX_DECORATE),
(namu : 'tbox.move'; code : WOP_TBOX_SETLOC),
(namu : 'tbox.outline'; code : WOP_TBOX_OUTLINE),
(namu : 'tbox.popin'; code : WOP_TBOX_POPIN),
(namu : 'tbox.popout'; code : WOP_TBOX_POPOUT),
(namu : 'tbox.print'; code : WOP_TBOX_PRINT),
(namu : 'tbox.removedecor'; code : WOP_TBOX_REMOVEDECOR),
(namu : 'tbox.removeoutlines'; code : WOP_TBOX_REMOVEOUTLINES),
(namu : 'tbox.setdefault'; code : WOP_TBOX_SETDEFAULT),
(namu : 'tbox.setloc'; code : WOP_TBOX_SETLOC),
(namu : 'tbox.setnumboxes'; code : WOP_TBOX_SETNUMBOXES),
(namu : 'tbox.setparam'; code : WOP_TBOX_SETPARAM),
(namu : 'tbox.setsize'; code : WOP_TBOX_SETSIZE),
(namu : 'tbox.settexture'; code : WOP_TBOX_SETTEXTURE),
(namu : 'transition'; code : WOP_GFX_TRANSITION),
(namu : 'viewport.setbkgindex'; code : WOP_VIEWPORT_SETBKGINDEX),
(namu : 'viewport.setbkgslot'; code : WOP_VIEWPORT_SETBKGINDEX),
(namu : 'viewport.setdefault'; code : WOP_VIEWPORT_SETDEFAULT),
(namu : 'viewport.setgamma'; code : WOP_VIEWPORT_SETGAMMA),
(namu : 'viewport.setparams'; code : WOP_VIEWPORT_SETPARAMS),
(namu : 'viewport.transition'; code : WOP_GFX_TRANSITION),
(namu : 'wait'; code : WOP_FIBER_WAIT),
(namu : 'waitkey'; code : WOP_FIBER_WAITKEY),
(namu : 'waitsig'; code : WOP_FIBER_WAITSIG),
(namu : 'waitsignal'; code : WOP_FIBER_WAITSIG),
(namu : 'yield'; code : WOP_FIBER_YIELD)
);

// Word of power parameter type enums (0 is invalid)
const
ARG_NUM = 1;
ARG_STR = 2;

// Mapping of parameter bytecodes to all wop bytecodes
// Before use, you MUST call ss_rwopparams_init!
// To use, query ss_rwopparams[WOPCODE][PARAMCODE].
// Invalid parameters are 0; valid parameters have the parameter type enum.
// Also, the top nibble contains the dynamic priority. Parameters with higher
// priority numbers get filled with dynamic values first.
var ss_rwopparams : array[0..255] of array[0..63] of byte;
    ss_rwoppargtype : array[0..63] of byte;

procedure ss_rwopparams_init;
var ivar : dword;
begin
 // Explicitly zero out everything
 for ivar := high(ss_rwopparams) downto 0 do
  filldword(ss_rwopparams[ivar][0], length(ss_rwopparams[0]) shr 2, 0);
 filldword(ss_rwoppargtype, length(ss_rwoppargtype) shr 2, 0);

 // Set up the argument types for all parameters
 ss_rwoppargtype[WOPP_ALLFX] := ARG_NUM;
 ss_rwoppargtype[WOPP_ALPHA] := ARG_NUM;
 ss_rwoppargtype[WOPP_ANCHORX] := ARG_NUM;
 ss_rwoppargtype[WOPP_ANCHORY] := ARG_NUM;
 ss_rwoppargtype[WOPP_BOX] := ARG_NUM;
 ss_rwoppargtype[WOPP_BY] := ARG_NUM;
 ss_rwoppargtype[WOPP_COLOR] := ARG_NUM;
 ss_rwoppargtype[WOPP_FIBER] := ARG_STR;
 ss_rwoppargtype[WOPP_FRAME] := ARG_NUM;
 ss_rwoppargtype[WOPP_FREQ] := ARG_NUM;
 ss_rwoppargtype[WOPP_GAMMA] := ARG_NUM;
 ss_rwoppargtype[WOPP_GOB] := ARG_STR;
 ss_rwoppargtype[WOPP_INDEX] := ARG_NUM;
 ss_rwoppargtype[WOPP_LABEL] := ARG_STR;
 ss_rwoppargtype[WOPP_LOCX] := ARG_NUM;
 ss_rwoppargtype[WOPP_LOCY] := ARG_NUM;
 ss_rwoppargtype[WOPP_MOUSEOFF] := ARG_STR;
 ss_rwoppargtype[WOPP_MOUSEON] := ARG_STR;
 ss_rwoppargtype[WOPP_NAME] := ARG_STR;
 ss_rwoppargtype[WOPP_NOCLEAR] := ARG_NUM;
 ss_rwoppargtype[WOPP_PARENT] := ARG_STR;
 ss_rwoppargtype[WOPP_RATIOX] := ARG_NUM;
 ss_rwoppargtype[WOPP_RATIOY] := ARG_NUM;
 ss_rwoppargtype[WOPP_SIZEX] := ARG_NUM;
 ss_rwoppargtype[WOPP_SIZEY] := ARG_NUM;
 ss_rwoppargtype[WOPP_STYLE] := ARG_STR;
 ss_rwoppargtype[WOPP_TEXT] := ARG_STR;
 ss_rwoppargtype[WOPP_THICKNESS] := ARG_NUM;
 ss_rwoppargtype[WOPP_TIME] := ARG_NUM;
 ss_rwoppargtype[WOPP_TYPE] := ARG_STR;
 ss_rwoppargtype[WOPP_VALUE] := ARG_NUM;
 ss_rwoppargtype[WOPP_VAR] := ARG_STR;
 ss_rwoppargtype[WOPP_VIEWPORT] := ARG_NUM;
 ss_rwoppargtype[WOPP_ZLEVEL] := ARG_NUM;

 // === System commands ===
 // default: empty gob name = no cursor override
 ss_rwopparams[WOP_SYS_SETCURSOR][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 // default: empty title string
 ss_rwopparams[WOP_SYS_SETTITLE][WOPP_TEXT] := ss_rwoppargtype[WOPP_TEXT];

 // === Textbox commands === (wopp_box defaults to gamevar.defaulttextbox)
 ss_rwopparams[WOP_TBOX_PRINT][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 // default: empty string
 ss_rwopparams[WOP_TBOX_PRINT][WOPP_TEXT] := ss_rwoppargtype[WOPP_TEXT];
 // default: clear all boxes
 ss_rwopparams[WOP_TBOX_CLEAR][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 // default: box 1
 ss_rwopparams[WOP_TBOX_SETDEFAULT][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 // default: 3 boxes, which is also the minimum
 ss_rwopparams[WOP_TBOX_SETNUMBOXES][WOPP_INDEX] := ss_rwoppargtype[WOPP_INDEX];
 ss_rwopparams[WOP_TBOX_SETLOC][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX] or $F0;
 // default: current location or 0,0
 ss_rwopparams[WOP_TBOX_SETLOC][WOPP_LOCX] := ss_rwoppargtype[WOPP_LOCX] or $E0;
 ss_rwopparams[WOP_TBOX_SETLOC][WOPP_LOCY] := ss_rwoppargtype[WOPP_LOCY] or $D0;
 // default: 0 msec
 ss_rwopparams[WOP_TBOX_SETLOC][WOPP_TIME] := ss_rwoppargtype[WOPP_TIME] or $A0;
 // default: current anchor or 0,0
 ss_rwopparams[WOP_TBOX_SETLOC][WOPP_ANCHORX] := ss_rwoppargtype[WOPP_ANCHORX] or $60;
 ss_rwopparams[WOP_TBOX_SETLOC][WOPP_ANCHORY] := ss_rwoppargtype[WOPP_ANCHORY] or $50;
 // default: "linear"
 ss_rwopparams[WOP_TBOX_SETLOC][WOPP_STYLE] := ss_rwoppargtype[WOPP_STYLE];
 ss_rwopparams[WOP_TBOX_SETSIZE][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX] or $F0;
 // default: current size or 0,0
 ss_rwopparams[WOP_TBOX_SETSIZE][WOPP_SIZEX] := ss_rwoppargtype[WOPP_SIZEX] or $E0;
 ss_rwopparams[WOP_TBOX_SETSIZE][WOPP_SIZEY] := ss_rwoppargtype[WOPP_SIZEY] or $D0;
 // default: 0 msec
 ss_rwopparams[WOP_TBOX_SETSIZE][WOPP_TIME] := ss_rwoppargtype[WOPP_TIME] or $A0;
 // default: "linear"
 ss_rwopparams[WOP_TBOX_SETSIZE][WOPP_STYLE] := ss_rwoppargtype[WOPP_STYLE];
 ss_rwopparams[WOP_TBOX_SETTEXTURE][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 // default: empty texture graphic name
 ss_rwopparams[WOP_TBOX_SETTEXTURE][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 // default: "normal"
 ss_rwopparams[WOP_TBOX_SETTEXTURE][WOPP_STYLE] := ss_rwoppargtype[WOPP_STYLE];
 // default: "stretched"
 ss_rwopparams[WOP_TBOX_SETTEXTURE][WOPP_TYPE] := ss_rwoppargtype[WOPP_TYPE];
 // default: frame 0
 ss_rwopparams[WOP_TBOX_SETTEXTURE][WOPP_FRAME] := ss_rwoppargtype[WOPP_FRAME];
 ss_rwopparams[WOP_TBOX_DECORATE][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX] or $F0;
 // default: empty gob name, decorate fails
 ss_rwopparams[WOP_TBOX_DECORATE][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB] or $D0;
 // default: 0,0
 ss_rwopparams[WOP_TBOX_DECORATE][WOPP_LOCX] := ss_rwoppargtype[WOPP_LOCX] or $B0;
 ss_rwopparams[WOP_TBOX_DECORATE][WOPP_LOCY] := ss_rwoppargtype[WOPP_LOCY] or $A0;
 // default: 0,0
 ss_rwopparams[WOP_TBOX_DECORATE][WOPP_SIZEX] := ss_rwoppargtype[WOPP_SIZEX] or $B0;
 ss_rwopparams[WOP_TBOX_DECORATE][WOPP_SIZEY] := ss_rwoppargtype[WOPP_SIZEY] or $A0;
 // default: 0,0
 ss_rwopparams[WOP_TBOX_DECORATE][WOPP_ANCHORX] := ss_rwoppargtype[WOPP_ANCHORX] or $60;
 ss_rwopparams[WOP_TBOX_DECORATE][WOPP_ANCHORY] := ss_rwoppargtype[WOPP_ANCHORY] or $50;

 ss_rwopparams[WOP_TBOX_OUTLINE][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX] or $F0;
 // default: black
 ss_rwopparams[WOP_TBOX_OUTLINE][WOPP_COLOR] := ss_rwoppargtype[WOPP_COLOR] or $D0;
 // default: 256
 ss_rwopparams[WOP_TBOX_OUTLINE][WOPP_THICKNESS] := ss_rwoppargtype[WOPP_THICKNESS] or $A0;
 // default: 0,0
 ss_rwopparams[WOP_TBOX_OUTLINE][WOPP_LOCX] := ss_rwoppargtype[WOPP_LOCX] or $60;
 ss_rwopparams[WOP_TBOX_OUTLINE][WOPP_LOCY] := ss_rwoppargtype[WOPP_LOCY] or $50;
 // default: 0
 ss_rwopparams[WOP_TBOX_OUTLINE][WOPP_ALPHA] := ss_rwoppargtype[WOPP_ALPHA] or $20;

 ss_rwopparams[WOP_TBOX_POPIN][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 ss_rwopparams[WOP_TBOX_POPOUT][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];

 ss_rwopparams[WOP_TBOX_REMOVEOUTLINES][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 ss_rwopparams[WOP_TBOX_REMOVEDECOR][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX] or $F0;
 // default: empty gob name, removes all decorations
 ss_rwopparams[WOP_TBOX_REMOVEDECOR][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB] or $B0;
 // default: box 1
 ss_rwopparams[WOP_TBOX_SETPARAM][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 ss_rwopparams[WOP_TBOX_SETPARAM][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME];
 ss_rwopparams[WOP_TBOX_SETPARAM][WOPP_VALUE] := ss_rwoppargtype[WOPP_VALUE];

 // === Choice commands ===
 // default: noclear=0, choicebox is cleared before printing choices
 ss_rwopparams[WOP_CHOICE_CALL][WOPP_NOCLEAR] := ss_rwoppargtype[WOPP_NOCLEAR];
 ss_rwopparams[WOP_CHOICE_GET][WOPP_NOCLEAR] := ss_rwoppargtype[WOPP_NOCLEAR];
 ss_rwopparams[WOP_CHOICE_GOTO][WOPP_NOCLEAR] := ss_rwoppargtype[WOPP_NOCLEAR];
 // default: empty string, all choices
 ss_rwopparams[WOP_CHOICE_OFF][WOPP_TEXT] := ss_rwoppargtype[WOPP_TEXT];
 ss_rwopparams[WOP_CHOICE_ON][WOPP_TEXT] := ss_rwoppargtype[WOPP_TEXT];
 ss_rwopparams[WOP_CHOICE_REMOVE][WOPP_TEXT] := ss_rwoppargtype[WOPP_TEXT];
 // default: 4 columns
 ss_rwopparams[WOP_CHOICE_COLUMNS][WOPP_VALUE] := ss_rwoppargtype[WOPP_VALUE];
 // default: first free index
 ss_rwopparams[WOP_CHOICE_SET][WOPP_INDEX] := ss_rwoppargtype[WOPP_INDEX];
 // default: empty string, choice set fails
 ss_rwopparams[WOP_CHOICE_SET][WOPP_TEXT] := ss_rwoppargtype[WOPP_TEXT] or $F0;
 // default: undefined labels
 ss_rwopparams[WOP_CHOICE_SET][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL] or $E0;
 // default: undefined tracking var
 ss_rwopparams[WOP_CHOICE_SET][WOPP_VAR] := ss_rwoppargtype[WOPP_VAR] or $B0;
 // default: box 1
 ss_rwopparams[WOP_CHOICE_SETCHOICEBOX][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 // default: box 1
 ss_rwopparams[WOP_CHOICE_SETPARTBOX][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 // default: box 2
 ss_rwopparams[WOP_CHOICE_SETHIGHLIGHTBOX][WOPP_BOX] := ss_rwoppargtype[WOPP_BOX];
 // default: 0, disabled
 ss_rwopparams[WOP_CHOICE_PRINTPARENT][WOPP_VALUE] := ss_rwoppargtype[WOPP_VALUE];

 // === Various jump commands === (wopp_label defaults to empty/fail)
 ss_rwopparams[WOP_CALL][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL];
 // default: 0, first index
 ss_rwopparams[WOP_CASECALL][WOPP_INDEX] := ss_rwoppargtype[WOPP_INDEX];
 ss_rwopparams[WOP_CASEGOTO][WOPP_INDEX] := ss_rwoppargtype[WOPP_INDEX];
 ss_rwopparams[WOP_CASECALL][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL];
 ss_rwopparams[WOP_CASEGOTO][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL];
 ss_rwopparams[WOP_GOTO][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL];

 // === Event commands === (wopp_label defaults to empty, no trigger)
 // default: empty string, create event fails
 ss_rwopparams[WOP_EVENT_CREATE_AREA][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME] or $F0;
 ss_rwopparams[WOP_EVENT_CREATE_AREA][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL] or $C0;
 // default: no mouseoverables
 ss_rwopparams[WOP_EVENT_CREATE_AREA][WOPP_MOUSEON] := ss_rwoppargtype[WOPP_MOUSEON] or $80;
 ss_rwopparams[WOP_EVENT_CREATE_AREA][WOPP_MOUSEOFF] := ss_rwoppargtype[WOPP_MOUSEOFF] or $70;
 // default: location 0,0
 ss_rwopparams[WOP_EVENT_CREATE_AREA][WOPP_LOCX] := ss_rwoppargtype[WOPP_LOCX] or $D0;
 ss_rwopparams[WOP_EVENT_CREATE_AREA][WOPP_LOCY] := ss_rwoppargtype[WOPP_LOCY] or $C0;
 // default: size 32768,32768
 ss_rwopparams[WOP_EVENT_CREATE_AREA][WOPP_SIZEX] := ss_rwoppargtype[WOPP_SIZEX] or $90;
 ss_rwopparams[WOP_EVENT_CREATE_AREA][WOPP_SIZEY] := ss_rwoppargtype[WOPP_SIZEY] or $80;
 // default: gamevar.defaultviewport
 ss_rwopparams[WOP_EVENT_CREATE_AREA][WOPP_VIEWPORT] := ss_rwoppargtype[WOPP_VIEWPORT] or $40;
 ss_rwopparams[WOP_EVENT_CREATE_ESC][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL];
 // default: empty string, create event fails
 ss_rwopparams[WOP_EVENT_CREATE_GOB][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME] or $F0;
 // default: empty string, create event fails
 ss_rwopparams[WOP_EVENT_CREATE_GOB][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB] or $E0;
 ss_rwopparams[WOP_EVENT_CREATE_GOB][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL] or $C0;
 // default: no mouseoverables
 ss_rwopparams[WOP_EVENT_CREATE_GOB][WOPP_MOUSEON] := ss_rwoppargtype[WOPP_MOUSEON] or $80;
 ss_rwopparams[WOP_EVENT_CREATE_GOB][WOPP_MOUSEOFF] := ss_rwoppargtype[WOPP_MOUSEOFF] or $70;
 ss_rwopparams[WOP_EVENT_CREATE_INT][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL];
 // default: empty string, create event fails
 ss_rwopparams[WOP_EVENT_CREATE_TIMER][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME] or $F0;
 ss_rwopparams[WOP_EVENT_CREATE_TIMER][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL] or $C0;
 // default: 1000 msec
 ss_rwopparams[WOP_EVENT_CREATE_TIMER][WOPP_FREQ] := ss_rwoppargtype[WOPP_FREQ];
 // default: empty string, mouse off fails
 ss_rwopparams[WOP_EVENT_MOUSEOFF][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME] or $F0;
 ss_rwopparams[WOP_EVENT_MOUSEOFF][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL] or $C0;
 // default: empty string, mouse on fails
 ss_rwopparams[WOP_EVENT_MOUSEON][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME] or $F0;
 ss_rwopparams[WOP_EVENT_MOUSEON][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL] or $C0;
 // default: empty string, remove all events
 ss_rwopparams[WOP_EVENT_REMOVE][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME];
 // default: empty string, set label fails
 ss_rwopparams[WOP_EVENT_SETLABEL][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME] or $F0;
 ss_rwopparams[WOP_EVENT_SETLABEL][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL] or $C0;

 // === Fiber commands ===
 // default: empty string, all fibers get a signal
 ss_rwopparams[WOP_FIBER_SIGNAL][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME];
 // default: empty string, fiber start fails
 ss_rwopparams[WOP_FIBER_START][WOPP_LABEL] := ss_rwoppargtype[WOPP_LABEL] or $F0;
 // default: same name as label string
 ss_rwopparams[WOP_FIBER_START][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME] or $C0;
 // default: stop self
 ss_rwopparams[WOP_FIBER_STOP][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME];
 // default: 0 msec, fiber waits for all effects to end, or signal
 ss_rwopparams[WOP_FIBER_WAIT][WOPP_TIME] := ss_rwoppargtype[WOPP_TIME];
 // default: noclear = 0, box is cleared
 ss_rwopparams[WOP_FIBER_WAITKEY][WOPP_NOCLEAR] := ss_rwoppargtype[WOPP_NOCLEAR];

 // === Graphics commands === (wopp_gob defaults to empty, fail)
 // default: empty string, gfx.adopt fails
 ss_rwopparams[WOP_GFX_ADOPT][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB] or $F0;
 // default: empty string, gob is orphaned
 ss_rwopparams[WOP_GFX_ADOPT][WOPP_PARENT] := ss_rwoppargtype[WOPP_PARENT] or $C0;
 ss_rwopparams[WOP_GFX_BASH][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 ss_rwopparams[WOP_GFX_CLEARKIDS][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 ss_rwopparams[WOP_GFX_FLASH][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 ss_rwopparams[WOP_GFX_GETFRAME][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 ss_rwopparams[WOP_GFX_GETSEQUENCE][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 ss_rwopparams[WOP_GFX_MOVE][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB] or $F0;
 // default: "linear"
 ss_rwopparams[WOP_GFX_MOVE][WOPP_STYLE] := ss_rwoppargtype[WOPP_STYLE] or $80;
 // default: current location
 ss_rwopparams[WOP_GFX_MOVE][WOPP_LOCX] := ss_rwoppargtype[WOPP_LOCX] or $C0;
 ss_rwopparams[WOP_GFX_MOVE][WOPP_LOCY] := ss_rwoppargtype[WOPP_LOCY] or $B0;
 // default: 0 msec
 ss_rwopparams[WOP_GFX_MOVE][WOPP_TIME] := ss_rwoppargtype[WOPP_TIME] or $80;
 // default: empty string, gfx precache fails
 ss_rwopparams[WOP_GFX_PRECACHE][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 // default: default viewport
 ss_rwopparams[WOP_GFX_PRECACHE][WOPP_VIEWPORT] := ss_rwoppargtype[WOPP_VIEWPORT];
 ss_rwopparams[WOP_GFX_REMOVE][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 ss_rwopparams[WOP_GFX_SETALPHA][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 // default: alpha 255, fully opaque
 ss_rwopparams[WOP_GFX_SETALPHA][WOPP_ALPHA] := ss_rwoppargtype[WOPP_ALPHA];
 // default: 0 msec
 ss_rwopparams[WOP_GFX_SETALPHA][WOPP_TIME] := ss_rwoppargtype[WOPP_TIME];
 ss_rwopparams[WOP_GFX_SETFRAME][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 // default: frame 0
 ss_rwopparams[WOP_GFX_SETFRAME][WOPP_FRAME] := ss_rwoppargtype[WOPP_FRAME];
 ss_rwopparams[WOP_GFX_SETSEQUENCE][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 // default: index 0
 ss_rwopparams[WOP_GFX_SETSEQUENCE][WOPP_INDEX] := ss_rwoppargtype[WOPP_INDEX];
 ss_rwopparams[WOP_GFX_SETSOLIDBLIT][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB];
 // default: 0, disables solid blit effect
 ss_rwopparams[WOP_GFX_SETSOLIDBLIT][WOPP_COLOR] := ss_rwoppargtype[WOPP_COLOR];
 // default: empty string, gfx show fails
 ss_rwopparams[WOP_GFX_SHOW][WOPP_GOB] := ss_rwoppargtype[WOPP_GOB] or $F0;
 // default: sprite, or anim if an animation is defined for this graphic
 ss_rwopparams[WOP_GFX_SHOW][WOPP_TYPE] := ss_rwoppargtype[WOPP_TYPE] or $C0;
 // default: same name as gob resource
 ss_rwopparams[WOP_GFX_SHOW][WOPP_NAME] := ss_rwoppargtype[WOPP_NAME] or $80;
 // default: 0,0
 ss_rwopparams[WOP_GFX_SHOW][WOPP_LOCX] := ss_rwoppargtype[WOPP_LOCX] or $D0;
 ss_rwopparams[WOP_GFX_SHOW][WOPP_LOCY] := ss_rwoppargtype[WOPP_LOCY] or $C0;
 // default: gamevar.defaultviewport
 ss_rwopparams[WOP_GFX_SHOW][WOPP_VIEWPORT] := ss_rwoppargtype[WOPP_VIEWPORT] or $80;
 // default: 0
 ss_rwopparams[WOP_GFX_SHOW][WOPP_ZLEVEL] := ss_rwoppargtype[WOPP_ZLEVEL] or $10;
 // default: 0 for instant
 ss_rwopparams[WOP_GFX_TRANSITION][WOPP_INDEX] := ss_rwoppargtype[WOPP_INDEX];
 // default: 768 msec
 ss_rwopparams[WOP_GFX_TRANSITION][WOPP_TIME] := ss_rwoppargtype[WOPP_TIME] or $C0;
 // default: gamevar.defaultviewport
 ss_rwopparams[WOP_GFX_TRANSITION][WOPP_VIEWPORT] := ss_rwoppargtype[WOPP_VIEWPORT] or $80;

 // === Viewport commands ===
 // default: slot 0
 ss_rwopparams[WOP_VIEWPORT_SETBKGINDEX][WOPP_INDEX] := ss_rwoppargtype[WOPP_INDEX];
 // default: viewport 0
 ss_rwopparams[WOP_VIEWPORT_SETBKGINDEX][WOPP_VIEWPORT] := ss_rwoppargtype[WOPP_VIEWPORT];
 // default: viewport 0, which is equal to the whole game window
 ss_rwopparams[WOP_VIEWPORT_SETDEFAULT][WOPP_VIEWPORT] := ss_rwoppargtype[WOPP_VIEWPORT];
 // default: gamma 1.0
 ss_rwopparams[WOP_VIEWPORT_SETGAMMA][WOPP_GAMMA] := ss_rwoppargtype[WOPP_GAMMA] or $C0;
 // default: viewport 0
 ss_rwopparams[WOP_VIEWPORT_SETGAMMA][WOPP_VIEWPORT] := ss_rwoppargtype[WOPP_VIEWPORT] or $A0;
 // default: 0 msec
 ss_rwopparams[WOP_VIEWPORT_SETGAMMA][WOPP_TIME] := ss_rwoppargtype[WOPP_TIME] or $80;
 // default: viewport 1, can't modify viewport 0
 ss_rwopparams[WOP_VIEWPORT_SETPARAMS][WOPP_VIEWPORT] := ss_rwoppargtype[WOPP_VIEWPORT] or $C0;
 // default: current parent
 ss_rwopparams[WOP_VIEWPORT_SETPARAMS][WOPP_PARENT] := ss_rwoppargtype[WOPP_PARENT] or $10;
 // default: current location
 ss_rwopparams[WOP_VIEWPORT_SETPARAMS][WOPP_LOCX] := ss_rwoppargtype[WOPP_LOCX] or $90;
 ss_rwopparams[WOP_VIEWPORT_SETPARAMS][WOPP_LOCY] := ss_rwoppargtype[WOPP_LOCY] or $80;
 // default: current size
 ss_rwopparams[WOP_VIEWPORT_SETPARAMS][WOPP_SIZEX] := ss_rwoppargtype[WOPP_SIZEX] or $50;
 ss_rwopparams[WOP_VIEWPORT_SETPARAMS][WOPP_SIZEY] := ss_rwoppargtype[WOPP_SIZEY] or $40;
 // default: current ratio
 ss_rwopparams[WOP_VIEWPORT_SETPARAMS][WOPP_RATIOX] := ss_rwoppargtype[WOPP_RATIOX] or $30;
 ss_rwopparams[WOP_VIEWPORT_SETPARAMS][WOPP_RATIOY] := ss_rwoppargtype[WOPP_RATIOY] or $20;

 // === Sound commands ===

 // === Variable commands === (wopp_by defaults to 1)
 // default: empty variable name, dec and inc fail
 ss_rwopparams[WOP_DEC][WOPP_VAR] := ss_rwoppargtype[WOPP_VAR];
 ss_rwopparams[WOP_DEC][WOPP_BY] := ss_rwoppargtype[WOPP_BY];
 ss_rwopparams[WOP_INC][WOPP_VAR] := ss_rwoppargtype[WOPP_VAR];
 ss_rwopparams[WOP_INC][WOPP_BY] := ss_rwoppargtype[WOPP_BY];
end;

// Output token enums
const
// unary operators
TOKEN_NOT = '!'; // NOT !
TOKEN_NEG = '_'; // unary prefix negation
TOKEN_VAR = '$';
TOKEN_RND = 'r'; // RND
TOKEN_TONUM = 't'; // TONUMBER
TOKEN_TOSTR = 'T'; // TOSTRING
// binary operators (right-side operand is popped first, left-side second)
TOKEN_PLUS = '+';
TOKEN_MINUS = '-';
TOKEN_MUL = '*';
TOKEN_DIV = '/'; // / DIV
TOKEN_MOD = '%'; // % MOD
TOKEN_AND = '&'; // & AND &&
TOKEN_OR = '|'; // | OR ||
TOKEN_XOR = '^'; // ^ XOR
TOKEN_EQ = '='; // = ==
TOKEN_LT = '<';
TOKEN_GT = '>';
TOKEN_LE = 'l'; // <= =<
TOKEN_GE = 'g'; // >= =>
TOKEN_NE = 'n'; // != <>
TOKEN_SET = ':'; // :=
TOKEN_INC = 'i'; // +=
TOKEN_DEC = 'd'; // -=
TOKEN_SHL = 'L'; // << SHL
TOKEN_SHR = 'R'; // >> SHR
// function-like operators
TOKEN_WOP = 'w'; // followed by a 1-byte word of power enum
TOKEN_PARAM = 'p'; // followed by a 1-byte word of power parameter enum
TOKEN_DYNPARAM = 'P';
TOKEN_WOPEND = ';'; // marks the end of wop parameters (but is actually output first)
TOKEN_JUMP = 'j'; // unconditional relative jump by following longint from the first byte of said longint
TOKEN_IF = '?'; // pop topmost stack; if 0, relative jump by following longint
TOKEN_CHOICEREACT = 'c'; // react to result of choice.get/goto/call
// flow operators (only during processing, these are output as ifs and jumps)
TOKEN_THEN = '{';
TOKEN_ELSE = '\';
TOKEN_END = '}';
TOKEN_WHILE = 'W';
TOKEN_DO = 'D';
// brackets (only during processing, these are not output)
TOKEN_PARENOPEN = '(';
TOKEN_PARENCLOSE = ')';
// operands
TOKEN_LONGUNIQUESTRING = 'U'; // followed by dword local string table index
TOKEN_LONGGLOBALSTRING = 'S'; // followed by dword global string table index
TOKEN_LONGLOCALSTRING = 'Z'; // followed by length dword + immediate string
TOKEN_MINIUNIQUESTRING = 'u'; // followed by byte local string table index
TOKEN_MINIGLOBALSTRING = 's'; // followed by byte global string table index
TOKEN_MINILOCALSTRING = 'z'; // followed by length byte + immediate string
TOKEN_EMPTYSTRING = '"';
TOKEN_BYTE = 'b'; // followed by byte
TOKEN_LONGINT = '#'; // followed by longint
// additionally, numbers 0..31 can be saved as direct values

function GetWordOfPower(const nam : string) : dword;
// Scans through ss_rwoplist for an exact match to the input string.
// Returns the index if found, otherwise returns 0.
// The input string should be in lowercase, like all words of power.
var ivar, min, max : longint;
begin
 // binary search
 min := 0; max := high(ss_rwoplist);
 repeat
  GetWordOfPower := (min + max) shr 1;
  ivar := CompStr(@nam[1], @ss_rwoplist[GetWordOfPower].namu[1], length(nam), length(ss_rwoplist[GetWordOfPower].namu));
  if ivar = 0 then exit;
  if ivar > 0 then min := GetWordOfPower + 1 else max := GetWordOfPower - 1;
 until min > max;
 GetWordOfPower := 0;
end;

function GetWordOfPowerParameter(const nam : string) : dword;
// Scans through ss_rwopplist for an exact match to the input string.
// Returns the index if found, otherwise returns 0.
// The input string should be in lowercase, like all wop parameters.
var ivar, min, max : longint;
begin
 // binary search
 min := 0; max := high(ss_rwopplist);
 repeat
  GetWordOfPowerParameter := (min + max) shr 1;
  ivar := CompStr(@nam[1], @ss_rwopplist[GetWordOfPowerParameter].id[1], length(nam), length(ss_rwopplist[GetWordOfPowerParameter].id));
  if ivar = 0 then exit;
  if ivar > 0 then min := GetWordOfPowerParameter + 1 else max := GetWordOfPowerParameter - 1;
 until min > max;
 GetWordOfPowerParameter := 0;
end;

// ------------------------------------------------------------------

function CompileScript(scriptname : UTF8string; inbuf, inbufend : pointer) : pointer;
// This takes a pointer to UTF-8 text data of size (inbufend - inbuf),
// compiles it to label-blocks of bytecode, and saves them in script[].
// Also, this places the strings in the script in stringtable[0][], with
// automatic deduplication where appropriate.
//
// If you're compiling a script at runtime, use an empty scriptname. This
// will hardcode all string instead of creating permanent string table
// references which would waste memory. The compiled bytecode is placed in
// script[0] which otherwise is an empty script.
//
// The input text data buffy must terminate with some kind of linebreak!
// Returns null if all went well; otherwise returns a pointer to a buffer
// containing a series of ministrings with error messages, terminating with
// a 0-length string. The caller must free this.
//
// If you call this while script fibers have already been set up, you MUST
// update the fibers' script indexes, since this re-sorts the script list!
// Existing label code is overwritten if the same label is present in the
// input data. If a fiber was running in that label, terminate the fiber with
// an error message, since whatever it was running no longer exists.

var parserstate :
      (blankstate, readinglabel, readingcomment,
      readingdecnum, readinghexnum,
      readingquostr, readingministr, readingminitrue, readingoperator);

    lasttoken :
      (none, parenopen, flowcontrol, woptoken, paramtoken, operand,
      unaryprefixoperator, binaryoperator);
      // parenclosed is remembered as operand
      // if-then-else-while-do are remembered as flowcontrol
      // end is remembered as none

    stringtypeoverride :
      (auto, hardcode, unique, dupable);

var linestart : pointer;
    linenumber : dword;
    newlabel : scripttype;
    errorlist : array of string;
    errorcount : longint;
    ivar, jvar : dword;

    opstack : array of record
      optoken : char;
      opprecedence : byte;
    end;
    ifstack : array of dword;
    currentwop : array of record
      wopnum : byte;
      paramarray : array[0..127] of byte;
    end;
    opstackcount, ifstackcount, currentwopcount : longint;

    labelcount : longint;
    uniquestringcount, globalstringcount : longint;
    // Compiled bytecode is temporarily stored here, and when a label ends,
    // the bytecode is moved to script[].code^.
    codebuffy : array of byte;
    codeofs : longint;
    // These are for capturing literals as we parse the input buffer.
    strip : string;
    stripUTF8 : array[0..4095] of byte;
    stripUTF8len : longint;
    stripnum : dword;
    // Various state trackers.
    quotype : byte;
    ifwhileexpr : byte;
    revivethread : boolean;
    // wop params on the same line as their wop can be nameless
    acceptnamelessparams : boolean;

  procedure error(const msg : string);
  begin
   if length(errorlist) >= errorcount then setlength(errorlist, length(errorlist) + 16);
   if scriptname = '' then errorlist[errorcount] := 'line ' + strdec(linenumber) + ',' + strdec(dword(inbuf - linestart)) + ': ' + msg
   else errorlist[errorcount] := scriptname + ' (' + strdec(linenumber) + ',' + strdec(dword(inbuf - linestart)) +  '): ' + msg;
   inc(errorcount);
  end;

  procedure opstackpop(pres : byte);
  // Pops the operator stack as long as stack item precedence >= pres.
  // Popped operators are output as bytecode.
  // Wop and wopp tokens come with a companion byte that must be popped at
  // the same time.
  begin
   while (opstackcount <> 0) and (opstack[opstackcount - 1].opprecedence >= pres)
   do begin
    dec(opstackcount);
    codebuffy[codeofs] := byte(opstack[opstackcount].optoken);
    inc(codeofs);
    // When popping a wop, also remove it from the currentwop stack
    if opstack[opstackcount].optoken = TOKEN_WOP then begin
     if currentwopcount = 0 then error('internal: pop empty wopstack??');
     dec(currentwopcount);
     if currentwopcount = 0 then acceptnamelessparams := FALSE;
    end;
    // companion byte! pop it also
    if opstack[opstackcount].optoken in [TOKEN_WOP, TOKEN_PARAM] then begin
     dec(opstackcount);
     codebuffy[codeofs] := byte(opstack[opstackcount].optoken);
     inc(codeofs);
     // choice.get/call/goto? Print an implicit choice-react token.
     if (opstack[opstackcount + 1].optoken = TOKEN_WOP)
     and (byte(opstack[opstackcount].optoken) in [WOP_CHOICE_GET, WOP_CHOICE_CALL, WOP_CHOICE_GOTO])
     then begin
      codebuffy[codeofs] := byte(TOKEN_CHOICEREACT);
      inc(codeofs);
     end;
    end;
   end;
  end;

  procedure opstackpushwop(wopid : byte);
  {$ifdef ssscriptdebugoutput}
  var ivar : dword;
  begin
   for ivar := high(ss_rwoplist) downto 0 do if ss_rwoplist[ivar].code = wopid then break;
   writeln('word of power: ' + ss_rwoplist[ivar].namu + ' $' + strhex(wopid));
  {$else}
  begin
  {$endif}

   // If this is an expression right after if or while, only one such is
   // allows before a corresponding then or do must be present.
   if ifwhileexpr <> 0 then begin
    if (ifwhileexpr and $1 <> 0) then begin
     if ifwhileexpr and $80 <> 0 then error('expected do, instead of a wop')
     else error('expected then, instead of a wop');
    end
    else inc(ifwhileexpr);
   end;

   // Check for expected element order
   if lasttoken in [unaryprefixoperator, binaryoperator, paramtoken]
   then error('wop statement must be in brackets to use its return value');

   // Pop any previous wop or other expression, up to the first open bracket
   opstackpop(11);
   lasttoken := woptoken;

   // Push the new wop on the wop stack, so we can keep track of which
   // parameters will be allowed or mandatory.
   if currentwopcount >= length(currentwop) then setlength(currentwop, length(currentwop) + 16);
   currentwop[currentwopcount].wopnum := wopid;
   filldword(currentwop[currentwopcount].paramarray, 32, 0); // 128 bytes
   inc(currentwopcount);

   // Output a marker for end of wop params
   codebuffy[codeofs] := byte(TOKEN_WOPEND);
   inc(codeofs);

   if opstackcount + 1 >= length(opstack) then setlength(opstack, length(opstack) + 16);
   byte(opstack[opstackcount].optoken) := wopid;
   opstack[opstackcount].opprecedence := 14;
   inc(opstackcount);
   opstack[opstackcount].optoken := TOKEN_WOP;
   opstack[opstackcount].opprecedence := 14;
   inc(opstackcount);
   // Any params following this wop on the same line don't have to have an
   // explicit name. This allows constructs like Print 3 "Bunny" as shorthand
   // for most common wop commands, in this case Print box=3 text="Bunny".
   acceptnamelessparams := TRUE;
  end;

  procedure opstackpushwopp(woppid : byte);
  {$ifdef ssscriptdebugoutput}
  var ivar : dword;
  {$endif}
  begin
   // Check if there's an active wop
   if currentwopcount = 0 then begin
    error('there is no active word of power for this parameter');
    exit;
   end;
   // Check for expected element order
   if lasttoken in [unaryprefixoperator, binaryoperator, paramtoken]
   then error('expected expression, instead of parameter name');

   // Pop any previous woppparam or expression
   opstackpop(16);
   lasttoken := paramtoken;

   // Expand the opstack as needed
   if opstackcount + 1 >= length(opstack) then setlength(opstack, length(opstack) + 16);
   if woppid = WOPP_DYNAMIC then begin
    {$ifdef ssscriptdebugoutput}
    writeln('wop dynamic param');
    {$endif}
    opstack[opstackcount].optoken := TOKEN_DYNPARAM;
    opstack[opstackcount].opprecedence := 16;
    inc(opstackcount);
   end
   else begin
    {$ifdef ssscriptdebugoutput}
    for ivar := high(ss_rwopplist) downto 0 do if ss_rwopplist[ivar].code = woppid then break;
    writeln('wop param: ' + ss_rwopplist[ivar].id + ' $' + strhex(woppid));
    {$endif}

    // Check if named parameter is repeated
    if currentwop[currentwopcount - 1].paramarray[woppid] <> 0 then
     error('this wop parameter was already defined');
    // Check if named parameter applies to the active wop
    if ss_rwopparams[currentwop[currentwopcount - 1].wopnum][woppid] = 0
    then error('this parameter does not apply to the active wop');

    byte(opstack[opstackcount].optoken) := woppid;
    opstack[opstackcount].opprecedence := 16;
    inc(opstackcount);
    opstack[opstackcount].optoken := TOKEN_PARAM;
    opstack[opstackcount].opprecedence := 16;
    inc(opstackcount);
    currentwop[currentwopcount - 1].paramarray[woppid] := 1;
   end;
  end;

  procedure startnewexpr(maybeprint : boolean);
  begin
   // If this is an expression right after if or while, only one such is
   // allows before a corresponding then or do must be present.
   if ifwhileexpr <> 0 then begin
    if (ifwhileexpr and $1 <> 0) then begin
     if ifwhileexpr and $80 <> 0 then error('expected do, instead of an expression')
     else error('expected then, instead of an expression');
    end
    else inc(ifwhileexpr);
   end;

   // If this is on the same line as a wop, then generate an implicit dynamic
   // parameter tag; otherwise terminate the current wop if any.
   // If maybeprint is true, then a print command is issued.
   if acceptnamelessparams then opstackpushwopp(WOPP_DYNAMIC)
   else begin
    opstackpop(11);
    if opstackcount <> 0 then
     if opstack[opstackcount - 1].optoken = TOKEN_PARENOPEN
     then error('expected ) instead of new expression');
    if maybeprint then begin
     opstackpushwop(WOP_TBOX_PRINT);
     opstackpushwopp(WOPP_DYNAMIC);
    end;
   end;
  end;

  procedure opstackpush(token : char);
  var precedence : byte;
  begin
   case token of
     TOKEN_PARENOPEN:
     // Open bracket: pop nothing, just push the token
     begin
      if lasttoken in [none, flowcontrol, woptoken, operand] then startnewexpr(FALSE);
      if length(opstack) <= opstackcount then setlength(opstack, length(opstack) + 16);
      opstack[opstackcount].optoken := TOKEN_PARENOPEN;
      opstack[opstackcount].opprecedence := 10;
      inc(opstackcount);
      lasttoken := parenopen;
     end;

     TOKEN_PARENCLOSE:
     // Closed bracket: pop the operator stack until open bracket found
     begin
      if lasttoken = paramtoken then error('expected expression after parameter name, instead of )')
      else if lasttoken in [unaryprefixoperator, binaryoperator] then error('expected expression after operator, instead of )');
      opstackpop(11);
      if (opstackcount = 0)
      or (opstack[opstackcount - 1].optoken <> TOKEN_PARENOPEN)
      then error('mismatched )')
      else dec(opstackcount); // pop the open bracket
      lasttoken := operand;
     end;

     else begin
      // Special case: equals-sign after parameter name is fine, skip it
      if (token = TOKEN_EQ) and (lasttoken = paramtoken) then exit;
      // Check for expected element order
      if token in [TOKEN_NOT, TOKEN_NEG, TOKEN_VAR, TOKEN_RND, TOKEN_TONUM, TOKEN_TOSTR]
      then begin
       // unary prefix operator
       if lasttoken in [none, flowcontrol, woptoken, operand] then startnewexpr(FALSE);
       lasttoken := unaryprefixoperator;
      end
      else begin
       // binary operator
       if lasttoken in [none, parenopen, flowcontrol, woptoken, binaryoperator, unaryprefixoperator]
       then error('expected operand, instead of a binary operator')
       else if lasttoken = paramtoken
       then error('expected operand after parameter name, instead of a binary operator');
       lasttoken := binaryoperator;
      end;

      // Establish this token's precedence priority
      precedence := 0;
      case token of
        TOKEN_SET, TOKEN_INC, TOKEN_DEC: precedence := 20;
        TOKEN_EQ, TOKEN_LT, TOKEN_GT, TOKEN_LE, TOKEN_GE, TOKEN_NE: precedence := 30;
        TOKEN_OR, TOKEN_XOR, TOKEN_PLUS, TOKEN_MINUS: precedence := 40;
        TOKEN_MUL, TOKEN_DIV, TOKEN_MOD, TOKEN_AND, TOKEN_SHL, TOKEN_SHR: precedence := 50;
        TOKEN_NOT, TOKEN_NEG, TOKEN_VAR, TOKEN_RND, TOKEN_TONUM, TOKEN_TOSTR: precedence := 60;
      end;

      // Establish this token's associativity, lefty by default.
      // While precedence of topmost in opstack >= this lefty token, or
      // precedence of topmost in opstack > this righty token, keep popping.
      if token in
        [TOKEN_NOT, TOKEN_NEG, TOKEN_VAR, TOKEN_RND, TOKEN_TONUM, TOKEN_TOSTR,
        TOKEN_SET, TOKEN_INC, TOKEN_DEC]
        then opstackpop(precedence + 1) // righty
        else opstackpop(precedence); // lefty

      // Check for variable assignment validity; the last thing output must
      // have been a variable token.
      if token in [TOKEN_SET, TOKEN_INC, TOKEN_DEC] then begin
       if opstack[opstackcount].optoken <> TOKEN_VAR then error('left side of assignment must be a variable')
       else dec(codeofs);
      end;

      // Push this token on operator stack
      if opstackcount >= length(opstack) then setlength(opstack, length(opstack) + 16);
      opstack[opstackcount].optoken := token;
      opstack[opstackcount].opprecedence := precedence;
      inc(opstackcount);
     end;
   end;
  end;

  procedure opstackpushflowcontrol(token : char);
  var ivar : dword;
  begin
   // Check for expected element order
   if lasttoken in [unaryprefixoperator, binaryoperator]
   then error('expected an expression after operator')
   else if lasttoken = paramtoken
   then error('expected an expression after a parameter name');
   lasttoken := flowcontrol;

   // Pop everything up to previous open bracket, if any
   opstackpop(11);
   if opstackcount <> 0 then
    if opstack[opstackcount - 1].optoken = TOKEN_PARENOPEN
    then error('expected ), no brackets allowed in flow control');
   // Pop everything up to previous flow control
   opstackpop(8);
   // Expand the stacks if needed
   if opstackcount >= length(opstack) then setlength(opstack, length(opstack) + 16);
   if ifstackcount >= length(ifstack) then setlength(ifstack, length(ifstack) + 16);

   case token of
     TOKEN_IF:
     begin
      // Check for expected flow control order
      if opstackcount <> 0 then
       if opstack[opstackcount - 1].optoken = TOKEN_IF then
       begin
        error('expected if-expression-then, not if-if'); exit;
       end
       else if opstack[opstackcount - 1].optoken = TOKEN_WHILE
       then error('expected while-expression-do, not while-if');
      // Push the if token
      opstack[opstackcount].optoken := TOKEN_IF;
      opstack[opstackcount].opprecedence := 7;
      inc(opstackcount);
      ifwhileexpr := $40;
     end;

     TOKEN_THEN:
     begin
      // Check for expected flow control order
      if (opstackcount = 0)
       or (opstack[opstackcount - 1].optoken <> TOKEN_IF)
       then begin error('then is only allowed after if'); exit; end;
      if (ifwhileexpr and 1 = 0) then error('expected expression before then');
      ifwhileexpr := 0;
      // Replace if with then on opstack
      opstack[opstackcount - 1].optoken := TOKEN_THEN;
      // Output if token
      codebuffy[codeofs] := byte(TOKEN_IF);
      inc(codeofs);
      // Save the current code offset on ifstack
      ifstack[ifstackcount] := codeofs;
      inc(ifstackcount);
      // Skip a longint in output, we'll fill it in later
      inc(codeofs, 4);
     end;

     TOKEN_ELSE:
     begin
      // Check for expected flow control order
      if (opstackcount = 0)
       or (opstack[opstackcount - 1].optoken <> TOKEN_THEN)
       then begin error('else is only allowed after a then-block'); exit; end;
      // Replace then with else on opstack
      opstack[opstackcount - 1].optoken := TOKEN_ELSE;
      // Pop from ifstack
      if ifstackcount = 0 then begin error('internal: pop empty ifstack??'); exit; end;
      dec(ifstackcount);
      ivar := ifstack[ifstackcount];
      // Output unconditional relative jump token
      codebuffy[codeofs] := byte(TOKEN_JUMP);
      inc(codeofs);
      // Save the current code offset on ifstack
      ifstack[ifstackcount] := codeofs;
      inc(ifstackcount);
      // Skip a longint in output, we'll fill it in later
      inc(codeofs, 4);
      // Fill in the jump address for the previous then
      longint((@codebuffy[ivar])^) := codeofs - ivar;
     end;

     TOKEN_WHILE:
     begin
      // Check for expected flow control order
      if opstackcount <> 0 then
       if opstack[opstackcount - 1].optoken = TOKEN_IF
       then error('expected if-expression-then, not if-while')
       else if opstack[opstackcount - 1].optoken = TOKEN_WHILE then
       begin
        error('expected while-expression-do, not while-while'); exit;
       end;
      // Push the while token
      opstack[opstackcount].optoken := TOKEN_WHILE;
      opstack[opstackcount].opprecedence := 7;
      inc(opstackcount);
      ifwhileexpr := $80;
      // Save the current code offset on ifstack
      ifstack[ifstackcount] := codeofs;
      inc(ifstackcount);
     end;

     TOKEN_DO:
     begin
      // Check for expected flow control order
      if (opstackcount = 0)
       or (opstack[opstackcount - 1].optoken <> TOKEN_WHILE)
       then begin error('do is only allowed after while'); exit; end;
      if (ifwhileexpr and 1 = 0) then error('expected expression before do');
      ifwhileexpr := 0;
      // Replace while with do on opstack
      opstack[opstackcount - 1].optoken := TOKEN_DO;
      // Output if token (in this case it means a conditional relative jump)
      codebuffy[codeofs] := byte(TOKEN_IF);
      inc(codeofs);
      // Save the current code offset on ifstack
      ifstack[ifstackcount] := codeofs;
      inc(ifstackcount);
      // Skip a longint in output, we'll fill it in later
      inc(codeofs, 4);
     end;

     TOKEN_END:
     begin
      lasttoken := none;
      // Check for expected flow control order
      if (opstackcount = 0)
       or (opstack[opstackcount - 1].optoken in [TOKEN_DO, TOKEN_THEN, TOKEN_ELSE] = FALSE)
       then begin error('end is only allowed after a then/else/do-block'); exit; end;
      // Pop the do/then/else from opstack
      dec(opstackcount);
      // Pop from ifstack
      if ifstackcount = 0 then begin error('internal: pop empty ifstack??'); exit; end;
      dec(ifstackcount);
      ivar := ifstack[ifstackcount];
      // Depending on whether this is if or while, the rest is different...
      if opstack[opstackcount].optoken = TOKEN_DO then begin
       // This is while-do-end...
       // Fill in the jump address for conditional jump
       longint((@codebuffy[ivar])^) := codeofs - ivar + 5;
       // Pop from ifstack
       if ifstackcount = 0 then begin error('internal: pop empty ifstack??'); exit; end;
       dec(ifstackcount);
       ivar := ifstack[ifstackcount];
       // Output unconditional relative jump token
       codebuffy[codeofs] := byte(TOKEN_JUMP);
       inc(codeofs);
       // Jump distance back to the start of the while statement
       longint((@codebuffy[codeofs])^) := ivar - codeofs;
       inc(codeofs, 4);
      end
      else begin
       // This is if-then-else-end...
       // Fill in the jump address for the end of the "then" block
       longint((@codebuffy[ivar])^) := codeofs - ivar;
      end;
     end;
   end;
  end;

  procedure outputnumop(num : dword);
  begin
   // Number operands are expected after operators and parameter names.
   // Otherwise, this must be the first element of the next expression.
   if lasttoken in [none, flowcontrol, woptoken, operand]
   then startnewexpr(FALSE);
   lasttoken := operand;

   // Number operands 0..31 are saved directly
   if num <= 31 then begin
    codebuffy[codeofs] := byte(num);
    inc(codeofs);
   end else
   // Number operands 32..255 are saved as a byte
   if num <= 255 then begin
    codebuffy[codeofs] := byte(TOKEN_BYTE); inc(codeofs);
    codebuffy[codeofs] := byte(num); inc(codeofs);
   end else
   // Number operands 256..maxint32 are saved as a dword
   begin
    codebuffy[codeofs] := byte(TOKEN_LONGINT); inc(codeofs);
    dword((@codebuffy[codeofs])^) := num;
    inc(codeofs, 4);
   end;
  end;

  procedure outputstrop;
  // Outputs a string operand, either hardcoded or through the string table.
  var ivar : dword;
      matchfound : boolean;

    function addglobalstring : dword;
    begin
     with script[0].stringlist[0] do begin
      // Grow the string list if needed
      if globalstringcount >= length(txt) then
       setlength(txt, length(txt) + 32);
      // Select the next list slot
      addglobalstring := globalstringcount;
      inc(globalstringcount);
      // Store the string
      setlength(txt[addglobalstring], stripUTF8len);
      move(stripUTF8[0], txt[addglobalstring][1], stripUTF8len);
     end
    end;
    function adduniquestring : dword;
    begin
     with newlabel.stringlist[0] do begin
      // Grow the string list if needed
      if uniquestringcount >= length(txt) then
       setlength(txt, length(txt) + length(txt) shr 1 + 32);
      // Select the next list slot
      adduniquestring := uniquestringcount;
      inc(uniquestringcount);
      // Store the string
      setlength(txt[adduniquestring], stripUTF8len);
      move(stripUTF8[0], txt[adduniquestring][1], stripUTF8len);
     end;
    end;

  begin
   // Check for expected control flow when outputting string operands.
   // If a non-quoted string appears as the first non-param expression
   // element that's not in a conditional, it's an error.
   if quotype = 0 then
    if (lasttoken = none)
    or (lasttoken = flowcontrol) and (ifwhileexpr and $F0 = 0)
    or (lasttoken in [woptoken, operand]) and (acceptnamelessparams = FALSE)
    then error('not a word of power; add quotes if string literal');

   case lasttoken of
     flowcontrol: startnewexpr((quotype <> 0) and (ifwhileexpr and $F0 = 0));
     // if this string follows a wop on the same line, it'll be a dynamic
     // parameter, or on the next line it's an implicit tbox.print thing.
     none, woptoken, operand: startnewexpr(quotype <> 0);
     // parenopen, unaryprefixoperator, binaryoperator: no action needed, the
     // string is part of the current expression
     // paramtoken: no action needed, the string affiliates with the param
   end;
   lasttoken := operand;

   if stripUTF8len = 0 then begin
    {$ifdef ssscriptdebugoutput}
    writeln('<empty string>');
    {$endif}
    stringtypeoverride := auto;
    codebuffy[codeofs] := byte(TOKEN_EMPTYSTRING); inc(codeofs);
    exit;
   end;

   // Determine string type, unless already overridden.
   // If compiling a nameless script, you're probably doing it at runtime, so
   // all string references can be hardcoded.
   if scriptname = '' then stringtypeoverride := hardcode
   else if stringtypeoverride = auto then begin
    // the currently active wop often suggests a best choice
    if currentwopcount <> 0 then begin
     case currentwop[currentwopcount - 1].wopnum of
       WOP_CALL, WOP_CASECALL, WOP_CASEGOTO, WOP_DEC, WOP_GOTO, WOP_INC,
       WOP_SYS_SETCURSOR,
       //WOP_MUS_PLAY, WOP_MUS_STOP,
       WOP_EVENT_CREATE_AREA,
       WOP_EVENT_CREATE_ESC, WOP_EVENT_CREATE_GOB, WOP_EVENT_CREATE_INT,
       WOP_EVENT_CREATE_TIMER, WOP_EVENT_MOUSEOFF, WOP_EVENT_MOUSEON,
       WOP_EVENT_REMOVE, WOP_EVENT_SETLABEL,
       WOP_FIBER_START, WOP_FIBER_STOP,
       WOP_GFX_ADOPT, WOP_GFX_BASH, WOP_GFX_FLASH, WOP_GFX_GETFRAME,
       WOP_GFX_GETSEQUENCE, WOP_GFX_MOVE, WOP_GFX_PRECACHE,
       WOP_GFX_REMOVE, WOP_GFX_SETALPHA, WOP_GFX_SETFRAME,
       WOP_GFX_SETSEQUENCE, WOP_GFX_SETSOLIDBLIT, WOP_GFX_SHOW:
         stringtypeoverride := hardcode;
       WOP_SYS_SETTITLE, WOP_TBOX_PRINT:
         stringtypeoverride := unique;
       WOP_CHOICE_ON, WOP_CHOICE_OFF, WOP_CHOICE_REMOVE:
         stringtypeoverride := dupable;
       WOP_CHOICE_SET:
         if quotype = 0 then stringtypeoverride := hardcode
         else stringtypeoverride := dupable;
     end;
    end;
    // if no useful wop was active...
    if stringtypeoverride = auto then
    // strings without quotes, that are not overridden, default to hardcoded
    if quotype = 0 then stringtypeoverride := hardcode
    // quote-encased strings default to unique
    else stringtypeoverride := unique;
   end;

   case stringtypeoverride of
     hardcode:
     begin
      if stripUTF8len <= 255 then begin
       // Save the string as a hardcoded ministring
       codebuffy[codeofs] := byte(TOKEN_MINILOCALSTRING); inc(codeofs);
       codebuffy[codeofs] := byte(stripUTF8len); inc(codeofs);
       {$ifdef ssscriptdebugoutput}
       write('minilocal-z:');
       {$endif}
      end
      else begin
       // Save the string as a hardcoded longstring
       codebuffy[codeofs] := byte(TOKEN_LONGLOCALSTRING); inc(codeofs);
       dword((@codebuffy[codeofs])^) := stripUTF8len; inc(codeofs, 4);
       {$ifdef ssscriptdebugoutput}
       write('longlocal-Z:');
       {$endif}
      end;
      // expand code output buffer if we must
      if codeofs + stripUTF8len >= length(codebuffy) then setlength(codebuffy, (codeofs + stripUTF8len + 65535) and $FFFF0000);
      // output the string proper
      move(stripUTF8[0], codebuffy[codeofs], stripUTF8len);
      inc(codeofs, stripUTF8len);
     end;

     dupable:
     begin
      // Check if this exact string exists under the global label
      ivar := 0; matchfound := FALSE;
      with script[0] do begin
       if globalstringcount <> 0 then
        for ivar := 0 to globalstringcount - 1 do begin
         if (length(script[0].stringlist[0].txt[ivar]) = stripUTF8len)
         and (CompareByte(script[0].stringlist[0].txt[ivar][1], stripUTF8[0], stripUTF8len) = 0)
         then begin
          matchfound := TRUE;
          break;
         end;
        end;
      end;

      // If this string doesn't exist under the global label, add it there
      if matchfound = FALSE then ivar := addglobalstring;

      // Save the string reference
      if ivar <= 255 then begin
       codebuffy[codeofs] := byte(TOKEN_MINIGLOBALSTRING); inc(codeofs);
       codebuffy[codeofs] := byte(ivar); inc(codeofs);
       {$ifdef ssscriptdebugoutput}
       write('miniglobal-s[' + strdec(ivar) + ']:');
       {$endif}
      end
      else begin
       codebuffy[codeofs] := byte(TOKEN_LONGGLOBALSTRING); inc(codeofs);
       dword((@codebuffy[codeofs])^) := ivar; inc(codeofs, 4);
       {$ifdef ssscriptdebugoutput}
       write('longglobal-S[' + strdec(ivar) + ']:');
       {$endif}
      end;
     end;

     unique:
     begin
      // Add the string under the current script label
      ivar := adduniquestring;
      // Save the string reference
      if ivar <= 255 then begin
       codebuffy[codeofs] := byte(TOKEN_MINIUNIQUESTRING); inc(codeofs);
       codebuffy[codeofs] := byte(ivar); inc(codeofs);
       {$ifdef ssscriptdebugoutput}
       write('miniunique-u[' + strdec(ivar) + ']:');
       {$endif}
      end
      else begin
       codebuffy[codeofs] := byte(TOKEN_LONGUNIQUESTRING); inc(codeofs);
       dword((@codebuffy[codeofs])^) := ivar; inc(codeofs, 4);
       {$ifdef ssscriptdebugoutput}
       write('longunique-U[' + strdec(ivar) + ']:');
       {$endif}
      end;
     end;
   end;

   {$ifdef ssscriptdebugoutput}
   for ivar := 0 to stripUTF8len - 1 do write(chr(stripUTF8[ivar]));
   writeln;
   {$endif}

   stringtypeoverride := auto;
  end;

  function checkministring : boolean;
  // Compares strip to the word of power list, the wop parameters list, the
  // operator keywords, and if-then-else-end. Pushes or outputs the
  // appropriate thing in response.
  // Returns TRUE if the strip string matched something, else FALSE.
  var ivar : dword;
  begin
   checkministring := TRUE;
   // If the last token was a $, this must be a ministring
   if (opstackcount <> 0) and (opstack[opstackcount - 1].optoken = TOKEN_VAR)
   and (lasttoken = unaryprefixoperator) then begin
    checkministring := FALSE; exit;
   end;
   // Is it a recognised keyword?
   case length(strip) of
    2:
    if strip = 'if' then begin opstackpushflowcontrol(TOKEN_IF); exit; end else
    if strip = 'do' then begin opstackpushflowcontrol(TOKEN_DO); exit; end else
    if strip = 'or' then begin opstackpush(TOKEN_OR); exit; end;
    3:
    if strip = 'end' then begin opstackpushflowcontrol(TOKEN_END); exit; end else
    if strip = 'and' then begin opstackpush(TOKEN_AND); exit; end else
    if strip = 'xor' then begin opstackpush(TOKEN_XOR); exit; end else
    if strip = 'not' then begin opstackpush(TOKEN_NOT); exit; end else
    if strip = 'div' then begin opstackpush(TOKEN_DIV); exit; end else
    if strip = 'mod' then begin opstackpush(TOKEN_MOD); exit; end else
    if strip = 'rnd' then begin opstackpush(TOKEN_RND); exit; end else
    if strip = 'shl' then begin opstackpush(TOKEN_SHL); exit; end else
    if strip = 'shr' then begin opstackpush(TOKEN_SHR); exit; end;
    4:
    if strip = 'then' then begin opstackpushflowcontrol(TOKEN_THEN); exit; end else
    if strip = 'else' then begin opstackpushflowcontrol(TOKEN_ELSE); exit; end;
    5:
    if strip = 'while' then begin opstackpushflowcontrol(TOKEN_WHILE); exit; end else
    if strip = 'tonum' then begin opstackpushflowcontrol(TOKEN_TONUM); exit; end else
    if strip = 'tostr' then begin opstackpushflowcontrol(TOKEN_TOSTR); exit; end;
    6:
    if strip = 'random' then begin opstackpush(TOKEN_RND); exit; end;
    8:
    if strip = 'tonumber' then begin opstackpush(TOKEN_TONUM); exit; end else
    if strip = 'tostring' then begin opstackpush(TOKEN_TOSTR); exit; end;
   end;
   // Is it a word of power?
   ivar := GetWordOfPower(strip);
   if ivar <> 0 then begin opstackpushwop(ss_rwoplist[ivar].code); exit; end;
   // Is it a word of power parameter?
   ivar := GetWordOfPowerParameter(strip);
   if ivar <> 0 then begin opstackpushwopp(ss_rwopplist[ivar].code); exit; end;

   // Don't know what it is, must be a ministring, caller can handle it
   checkministring := FALSE;
  end;

  procedure endlabel;
  var ivar : dword;
  begin
   // Clean up the current label's leftovers
   opstackpop(11);
   if opstackcount <> 0 then
    case opstack[opstackcount - 1].optoken of
      TOKEN_IF: error('expected then after if, instead of label');
      TOKEN_THEN: error('expected else/end after if-then, instead of label');
      TOKEN_ELSE: error('expected end after if-else, instead of label');
      TOKEN_WHILE: error('expected do after while, instead of label');
      TOKEN_DO: error('expected end after while-do, instead of label');
      TOKEN_PARENOPEN: error('expected ), instead of label');
    end;
   // react to the last token...
   case lasttoken of
     unaryprefixoperator, binaryoperator: error('expected an operand, instead of label');
     paramtoken: error('expected an expression after parameter name, instead of label');
   end;

   // save the built bytecode
   newlabel.codesize := codeofs;
   if codeofs <> 0 then begin
    {$ifdef ssscriptdebugoutput}
    writeln(newlabel.labelnamu + ' BYTECODE DUMP:');
    DumpBuffer(@codebuffy[0], codeofs); // see mccommon unit
    writeln;
    {$endif}
    getmem(newlabel.code, codeofs);
    move(codebuffy[0], newlabel.code^, codeofs);
    codeofs := 0;
   end;

   // shrink the string array to a precise size
   setlength(newlabel.stringlist[0].txt, uniquestringcount);

   // add the new label to the script[] array
   ivar := GetScr(newlabel.labelnamu);
   if ivar = 0 then begin
    // add as a new script[] item
    ivar := length(script);
    setlength(script, ivar + 1);
    script[ivar] := newlabel;
    SortScripts(TRUE);
   end
   else begin
    // this label already exists, overwrite previous
    if script[ivar].code <> NIL then begin freemem(script[ivar].code); script[ivar].code := NIL; end;
    script[ivar].labelnamu := newlabel.labelnamu;
    script[ivar].nextlabel := newlabel.nextlabel;
    script[ivar].code := newlabel.code;
    script[ivar].codesize := newlabel.codesize;
    setlength(script[ivar].stringlist[0].txt, 0);
    script[ivar].stringlist[0] := newlabel.stringlist[0];
   end;
   newlabel.code := NIL;
  end;

  procedure initlabel(const nam : string);
  begin
   if length(newlabel.stringlist) <> 0 then begin
    // connect the previous label to this new one
    newlabel.nextlabel := nam;
    // save the previous label
    endlabel;
   end;
   // new label starts with a blank slate
   lasttoken := none;
   stringtypeoverride := auto;
   acceptnamelessparams := FALSE;
   codeofs := 0;
   opstackcount := 0;
   ifstackcount := 0;
   currentwopcount := 0;
   uniquestringcount := 0;
   ifwhileexpr := 0;
   quotype := 0;
   // new label inits
   newlabel.labelnamu := nam;
   newlabel.nextlabel := '';
   newlabel.codesize := 0;
   setlength(newlabel.stringlist, 0);
   setlength(newlabel.stringlist, length(languagelist));
   inc(labelcount);
  end;

  procedure unexpected_char_error;
  begin
   error('unexpected character ' + char(inbuf^) + ' ($' + strhex(byte(inbuf^)) + ')')
  end;

begin
 setlength(errorlist, 0);
 errorcount := 0;
 linenumber := 1;
 linestart := inbuf;

 // Silence compiler warnings.
 strip := ''; stripnum := 0; stripUTF8len := 0; quotype := 0;
 codeofs := 0; opstackcount := 0; lasttoken := none;

 labelcount := 0;
 setlength(newlabel.stringlist, 0);

 setlength(opstack, 64);
 setlength(ifstack, 16);
 setlength(currentwop, 16);

 globalstringcount := length(script[0].stringlist[0].txt);

 // The wop param list may need initing.
 if ss_rwopparams[WOP_TBOX_PRINT][WOPP_BOX] = 0 then ss_rwopparams_init;

 // Output goes here.
 setlength(codebuffy, 65536);

 parserstate := blankstate;
 // We'll be messing with the script array, so shut down the asset manager.
 revivethread := asman_isthreadalive;
 asman_endthread;
 // Initialise the implicit script start label.
 scriptname := upcase(scriptname);
 initlabel(scriptname + '.');

 // Process the input text buffy.
 while inbuf < inbufend do begin

  case parserstate of

    blankstate:
    begin
     // expand code output buffer as needed
     if codeofs + 32 >= length(codebuffy) then setlength(codebuffy, length(codebuffy) + length(codebuffy) shr 1 + 65536);

     case char(inbuf^) of

      // Linebreak, LF/VT/FF/CR
      chr($A)..chr($D):
      begin
       if (byte(inbuf^) = $D)
       and (inbuf + 1 < inbufend) and (byte((inbuf + 1)^) = $A)
       then inc(inbuf); // CR + LF
       inc(linenumber);
       linestart := inbuf;
       acceptnamelessparams := FALSE;
      end;

      // Whitespace, comma
      chr(9), chr($20), ',': ;

      // Control chars
      chr(0)..chr(8), chr($E)..chr($1F): unexpected_char_error;

      // Labels
      '@':
      begin
       strip := '';
       parserstate := readinglabel;
      end;

      // Numerals
      '0':
      begin
       // If the number starts with 0x or 0X, it's actually a hexadecimal!
       if (inbuf + 1 < inbufend) and (byte((inbuf + 1)^) or $20 = ord('x'))
       then begin
        inc(inbuf);
        stripnum := 0;
        parserstate := readinghexnum;
       end
       else begin
        stripnum := 0;
        parserstate := readingdecnum;
       end;
      end;
      '1'..'9':
      begin
       stripnum := byte(inbuf^) - 48;
       parserstate := readingdecnum;
      end;

      // String uniqueness/dupability overrides
      '~': stringtypeoverride := dupable;
      '?': stringtypeoverride := unique;
      '.': stringtypeoverride := hardcode;

      // Quoted string literal
      '"', '''':
      begin
       // Save the quote character, the string must end with the same char
       quotype := byte(inbuf^);
       stripUTF8len := 0;
       parserstate := readingquostr;
      end;

      // Comments
      '#': parserstate := readingcomment;
      '/':
      if (inbuf + 1 < inbufend)
      and (char((inbuf + 1)^) = '/')
      then begin
       inc(inbuf);
       parserstate := readingcomment;
      end
      else begin
       // If the / isn't followed by another /, it must be an attempt to
       // divide something instead.
       opstackpush(TOKEN_DIV);
      end;

      // Single-character operators and brackets
      // / % * $ ^ ( )
      '%': opstackpush(TOKEN_MOD);
      '*': opstackpush(TOKEN_MUL);
      '$': opstackpush(TOKEN_VAR);
      '^': opstackpush(TOKEN_XOR);
      '(': opstackpush(TOKEN_PARENOPEN);
      ')': opstackpush(TOKEN_PARENCLOSE);

      // Possibly double-character operators
      // != -= += && || == =< => <= >= <> << >>
      '!', '-', '+', '&', '|', '=', '<', '>':
      begin
       strip := char(inbuf^);
       parserstate := readingoperator;
      end;

      // Always double-character operators
      ':':
      if (inbuf + 1 < inbufend)
      and (char((inbuf + 1)^) = '=')
      then begin
       inc(inbuf);
       opstackpush(TOKEN_SET);
      end
      else Error('unexpected : here');

      // Backslash, must be an escape char for a ministring
      '\':
      begin
       strip := ''; stripUTF8len := 0;
       parserstate := readingministr; continue;
      end;

      // Ministring
      else begin
       quotype := 0; // non-quote-encased ministrings default to hardcoded
       strip := char(inbuf^);
       if strip[1] in ['A'..'Z'] then byte(strip[1]) := ord(strip[1]) or $20;
       stripUTF8[0] := byte(inbuf^);
       stripUTF8len := 1;
       parserstate := readingministr;
      end;
     end;
    end;

    readinglabel:
    case byte(inbuf^) of
      // Linebreak, LF/VT/FF/CR
      $A..$D:
      begin
       error('label @' + strip + ' must end with : on the same line');
       parserstate := readingcomment;
       continue;
      end;
      // Control chars
      0..9, $E..$1F: unexpected_char_error;
      // End of label
      ord(':'):
      begin
       if length(strip) = 0 then error('explicit label cannot be empty')
       else initlabel(scriptname + '.' + strip);
       parserstate := blankstate;
      end;
      // Lowercase ascii letters
      ord('a')..ord('z'):
      if length(strip) >= 31 then begin
       error('too long label, max 31 bytes: @' + copy(strip, 1, 31));
       parserstate := readingcomment;
      end
      else begin
       inc(byte(strip[0]));
       // save them as uppercase
       strip[byte(strip[0])] := chr(byte(inbuf^) and $DF);
      end;
      // Anything else is a fair label character
      else
      if length(strip) >= 31 then begin
       error('too long label, max 31 bytes: @' + copy(strip, 1, 31));
       parserstate := readingcomment;
      end
      else begin
       inc(byte(strip[0]));
       strip[byte(strip[0])] := char(inbuf^);
      end;
    end;

    readingcomment:
    case byte(inbuf^) of
      // Linebreak, LF/VT/FF/CR
      $A..$D:
      begin
       parserstate := blankstate;
       continue;
      end;
    end;

    readingdecnum:
    case char(inbuf^) of
      '0'..'9': stripnum := (stripnum * 10 + byte(byte(inbuf^) - 48)) and $7FFFFFFF;
      else begin
       dec(inbuf);
       outputnumop(stripnum);
       parserstate := blankstate;
      end;
    end;

    readinghexnum:
    case char(inbuf^) of
      '0'..'9': stripnum := ((stripnum shl 4) and $7FFFFFFF) + byte(byte(inbuf^) - 48);
      'A'..'F': stripnum := ((stripnum shl 4) and $7FFFFFFF) + byte(byte(inbuf^) - 55);
      'a'..'f': stripnum := ((stripnum shl 4) and $7FFFFFFF) + byte(byte(inbuf^) - 87);
      else begin
       dec(inbuf);
       outputnumop(stripnum);
       parserstate := blankstate;
      end;
    end;

    readingquostr:
    begin
     if byte(inbuf^) = quotype then begin
      outputstrop;
      parserstate := blankstate;
     end else
     case byte(inbuf^) of
      // Linebreak, LF/VT/FF/CR
      $A..$D:
      begin
       error('expected ' + char(quotype) + ' before end of line');
       parserstate := blankstate;
       continue;
      end;
      // Control chars
      0..9, $E..$1F: unexpected_char_error;
      // Escape char
      ord('\'):
      begin
       // length check
       if stripUTF8len >= length(stripUTF8) then begin
        error('string exceeded max len ' + strdec(length(stripUTF8)) + ' bytes');
        parserstate := readingcomment;
        continue;
       end;
       // save the backslash
       stripUTF8[stripUTF8len] := ord('\');
       inc(stripUTF8len);
       inc(inbuf);
       // escape + control char not allowed
       if byte(inbuf^) in [0..31] then begin
        unexpected_char_error;
        byte(inbuf^) := 32;
       end;
       // another length check
       if stripUTF8len >= length(stripUTF8) then begin
        error('string exceeded max len ' + strdec(length(stripUTF8)) + ' bytes');
        parserstate := readingcomment;
        continue;
       end;
       // save the escaped char
       // (if it's our quote mark, then overwrite the backslash)
       if byte(inbuf^) = quotype then dec(stripUTF8len);
       stripUTF8[stripUTF8len] := byte(inbuf^);
       inc(stripUTF8len);
      end;
      // Anything else is a fair string character
      else begin
       // length check
       if stripUTF8len >= length(stripUTF8) then begin
        error('string exceeded max len ' + strdec(length(stripUTF8)) + ' bytes');
        parserstate := readingcomment;
        continue;
       end;
       // save the escaped char
       stripUTF8[stripUTF8len] := byte(inbuf^);
       inc(stripUTF8len);
      end;
     end;
    end;

    readingministr:
    begin
     case char(inbuf^) of
       // Basic letters and dots
       'A'..'Z':
       begin
        inc(byte(strip[0]));
        byte(strip[byte(strip[0])]) := byte(inbuf^) or $20; // lowercase
        stripUTF8[stripUTF8len] := byte(inbuf^);
        inc(stripUTF8len);
        // if string is very long, must be a trueministring
        if stripUTF8len >= 24 then parserstate := readingminitrue;
       end;
       'a'..'z', '.':
       begin
        inc(byte(strip[0]));
        byte(strip[byte(strip[0])]) := byte(inbuf^);
        stripUTF8[stripUTF8len] := byte(inbuf^);
        inc(stripUTF8len);
        // if string is very long, must be a trueministring
        if stripUTF8len >= 24 then parserstate := readingminitrue;
       end;
       // Colon or equals-sign
       ':', '=':
       begin
        dec(inbuf);
        // Is it a word of power parameter?
        // If the last token was a $, this can't be a parameter name...
        ivar := 0;
        if (opstackcount = 0) or (opstack[opstackcount - 1].optoken <> TOKEN_VAR) then
         ivar := GetWordOfPowerParameter(strip);
        if ivar <> 0 then begin
         // yes, it was; push it, return to blank state
         opstackpushwopp(ss_rwopplist[ivar].code);
         parserstate := blankstate;
         inc(inbuf);
        end
        else begin
         // no; it must be a plain ministring
         parserstate := readingminitrue;
        end;
       end;
       // Whitespace, line break, brackets, comments, comma
       chr(9), ' ', chr($A)..chr($D), '(', ')', '#', '/', ',':
       begin
        dec(inbuf);
        // was this string snippet a wop/wopp/operator/if-then-else-end?
        if checkministring then
         // yes, it was; it has been processed, return to blank state
         parserstate := blankstate
        else
         // no; it must be a plain ministring
         parserstate := readingminitrue;
       end;
       // Anything else - can't be wop/wopp/operator/if-then-else-end
       else begin
        parserstate := readingminitrue;
        continue;
       end;
     end;
    end;

    readingminitrue:
    case char(inbuf^) of
      // Control char, whitespace, brackets, hash comment, comma
      chr(0)..chr(32), '(', ')', '#', ',',
      // ... and various operators that are more important than the string
      '+','=','!','<','>',':','&','|':
      begin
       dec(inbuf);
       outputstrop;
       parserstate := blankstate;
      end;
      // Variable reference is an implicit plus
      '$':
      begin
       dec(inbuf);
       char(inbuf^) := '+';
       dec(inbuf);
       outputstrop;
       parserstate := blankstate;
      end;
      // Double-slash comment
      '/':
      begin
       if (inbuf + 1 < inbufend)
       and (char((inbuf + 1)^) = '/')
       then begin
        dec(inbuf);
        outputstrop;
        parserstate := blankstate;
       end
       else begin
        // single slash is a fair string char
        stripUTF8[stripUTF8len] := byte(inbuf^);
        inc(stripUTF8len);
       end;
      end;
      // Escape char
      '\':
      begin
       // save the backslash
       stripUTF8[stripUTF8len] := ord('\');
       inc(stripUTF8len);
       inc(inbuf);
       // escape + control char not allowed
       if byte(inbuf^) in [0..31] then begin
        unexpected_char_error;
        byte(inbuf^) := 32;
       end;
       // save the escaped char
       stripUTF8[stripUTF8len] := byte(inbuf^);
       inc(stripUTF8len);
      end;
      // Anything else is a fair string char
      else begin
       stripUTF8[stripUTF8len] := byte(inbuf^);
       inc(stripUTF8len);
      end;
    end;

    readingoperator:
    begin
     // This state is only for checking the second character of potentially
     // double-character operators, so we always exit the state right after.
     parserstate := blankstate;
     // We're watching out for these:
     // != += -= && || == =< => <= >= <> << >>
     // Check the first character
     case strip[1] of
       '!':
       if char(inbuf^) = '=' then opstackpush(TOKEN_NE)
       else begin dec(inbuf); opstackpush(TOKEN_NEG); end;
       '+':
       if char(inbuf^) = '=' then opstackpush(TOKEN_INC)
       else begin dec(inbuf); opstackpush(TOKEN_PLUS); end;
       '-':
       if char(inbuf^) = '=' then opstackpush(TOKEN_DEC)
       else begin
        // decide whether it's a binary minus op or unary negator
        dec(inbuf);
        if lasttoken = operand then opstackpush(TOKEN_MINUS)
        else opstackpush(TOKEN_NEG);
       end;
       '&':
       begin
        if char(inbuf^) <> '&' then dec(inbuf);
        opstackpush(TOKEN_AND);
       end;
       '|':
       begin
        if char(inbuf^) <> '|' then dec(inbuf);
        opstackpush(TOKEN_OR);
       end;
       '=':
       case char(inbuf^) of
         '=': opstackpush(TOKEN_EQ);
         '<': opstackpush(TOKEN_LE);
         '>': opstackpush(TOKEN_GE);
         else begin
          dec(inbuf);
          opstackpush(TOKEN_EQ);
         end;
       end;
       '<':
       case char(inbuf^) of
         '=': opstackpush(TOKEN_LE);
         '<': opstackpush(TOKEN_SHL);
         '>': opstackpush(TOKEN_NE);
         else begin
          dec(inbuf);
          opstackpush(TOKEN_LT);
         end;
       end;
       '>':
       case char(inbuf^) of
         '=': opstackpush(TOKEN_GE);
         '<': opstackpush(TOKEN_NE); // should >< have a different meaning?
         '>': opstackpush(TOKEN_SHR);
         else begin
          dec(inbuf);
          opstackpush(TOKEN_GT);
         end;
       end;
     end;
    end;
  end;

  inc(inbuf);
 end;
 // End of script processing code! Just terminate the final label.
 endlabel;

 // Resize the global strings array to a precise size
 setlength(script[0].stringlist[0].txt, globalstringcount);

 // Resume the asset manager's thread if it used to be alive
 if revivethread then asman_beginthread;
 // Return results; nil for all good, otherwise a list of error strings
 CompileScript := NIL;
 if errorcount = 0 then exit;

 getmem(CompileScript, errorcount * 256 + 1);
 jvar := 0;
 for ivar := 0 to errorcount - 1 do begin
  move(errorlist[ivar][0], (CompileScript + jvar)^, byte(errorlist[ivar][0]) + 1);
  inc(jvar, byte(errorlist[ivar][0]) + byte(1));
 end;
 byte((CompileScript + jvar)^) := 0;
end;
