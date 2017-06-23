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

// SuperSakura Decomp game ID list

const gid_UNKNOWN = 0;
      // JAST
      //gid_ANGELS1 = 10; // Tenshitachi no Gogo
      //gid_ANGELS1B = 11; // Tenshitachi no Gogo - Bangai Hen
      //gid_ANGELS2 = 12; // Tenshitachi no Gogo 2 - Minako
      //gid_ANGELS2B = 13; // Tenshitachi no Gogo 2 - Bangai Hen
      //gid_ANGELS3 = 14; // Tenshitachi no Gogo 3 - Ribbon
      //gid_ANGELS3B = 15; // Tenshitachi no Gogo 3 - Bangai Hen
      //gid_ANGELS4 = 16; // Tenshitachi no Gogo 4 - Yuuko
      //gid_ANGELS5 = 17; // Tenshitachi no Gogo 5 - Neraureta Tenshi
      //gid_ANGELS6 = 18; // Tenshitachi no Gogo 6 - My Fair Teacher
      gid_ANGELSCOLLECTION1 = 21; // Tenshitachi no Gogo Collection 1
      gid_ANGELSCOLLECTION2 = 22; // Tenshitachi no Gogo Collection 2
      gid_MARIRIN = 28; // Super Urutora Mucchin Puri^2 Saibo-gu Maririn DX
      // (Obviously mangled title, and the cyborg in question is Marilyn, but
      // in line with the silly nature of the game, Maririn sounds funnier.)
      gid_DEEP = 29; // Deep
      gid_SETSUJUU = 30; // Setsujuu - Yuganda Kioku (Distorted Memories)
      // (although the title kanji translate as Snow Cat, the first kanji
      // could be a person's name, Setsu etc. But there is snow and a white
      // cat in the game, so the title must have a double meaning.)
      gid_TRANSFER98 = 31; // Tenshitachi no Gogo - Tenkousei (PC-98)
      gid_3SIS = 32; // The Three Sisters' Story (DOS)
      gid_3SIS98 = 33; // Sanshimai (PC-98)
      gid_EDEN = 34; // Eden no Kaori
      gid_FROMH = 35; // Shyukan From H
      gid_HOHOEMI = 36; // Tenshitachi no Hohoemi, Angelsmile
      //gid_TRANSFER = 37; // Transfer Student (Win)

      // Tiare
      gid_VANISH = 40; // Vanishing Point - Tenshi no Kieta Machi
      gid_RUNAWAY = 41; // Runaway City (DOS)
      gid_RUNAWAY98 = 42; // Meisou Toshi (PC-98)
      gid_SAKURA = 43; // Season of the Sakura (DOS)
      gid_SAKURA98 = 44; // Sakura no Kisetsu (PC-98)
      gid_MAJOKKO = 45; // Majokko Paradise, Magical Girl Paradise
      gid_TASOGARE = 46; // Tasogare no Kyoukai - Edge of Twilight?
      gid_PARFAIT = 48; // Muchimuchi Sekushii Parfait for oneesan
      // Pom-pom Pretty Parfait for children? Censored version of the game?

      // Apricot
      gid_NOCTURNE = 50; // Nocturnal Illusion (Win)
      gid_NOCTURNE98 = 51; // Mugen Yasoukyoku (PC-98)

      // Desire
      gid_MAYCLUB = 60; // May Club (Win)
      gid_MAYCLUB98 = 61; // VR Date - May Club Gogatsu Kuchibi (PC-98)
      gid_YUUGIRI = 62; // Yuugiri - Ningiyushi no Isan

      // Parsley
      gid_VENUS = 70; // Venus
      gid_TRUELOVE = 71; // True Love (Win)
      gid_TRUELOVE98 = 72; // True Love (PC-98)
      gid_RENO = 73; // Re-No - Stayin' Alive

// Use ChibiCRC to calculate a CRC for an EXE to try to identify it.
// The ID numbers and their order are subject to change at any time.
// Only use sets of const gid names from above when checking for game ID.
type gameidtype = record
      CRC : dword;
      gidnum : byte;
      namu : string[15];
      desc : string;
      baseresx, baseresy : word;
      level : byte; // 3: completable, 2: playable, 1: resources only
     end;

const crcid : array[0..28] of gameidtype  = (
(CRC : 0; gidnum : gid_UNKNOWN; namu : 'unknown';
desc : 'unknown';
baseresx : 640; baseresy : 400;
level : 0),

(CRC : $AD6265D6; gidnum : gid_3SIS; namu : '3sis';
desc : 'The Three Sisters'' Story (DOS)';
baseresx : 480; baseresy : 296;
level : 3),

(CRC : $90371AFB; gidnum : gid_3SIS98; namu : '3sis98';
desc : 'Sanshimai (PC98)';
baseresx : 480; baseresy : 296;
level : 2),

(CRC : $65F71A2C; gidnum : gid_ANGELSCOLLECTION1; namu : 'AngelsC1';
desc : 'Tenshitachi no Gogo Collection (PC98)';
baseresx : 480; baseresy : 280;
level : 2),

(CRC : $9AC5B678; gidnum : gid_ANGELSCOLLECTION2; namu : 'AngelsC2';
desc : 'Tenshitachi no Gogo Collection 2 (PC98)';
baseresx : 480; baseresy : 280;
level : 2),

(CRC : $FD5B952C; gidnum : gid_DEEP; namu : 'Deep';
desc : 'Deep (PC98)';
baseresx : 560; baseresy : 262;
level : 1),

(CRC : $38C8034D; gidnum : gid_EDEN; namu : 'Eden';
desc : 'Eden no Kaori (PC98)';
baseresx : 480; baseresy : 296;
level : 2),

(CRC : $CE363C50; gidnum : gid_FROMH; namu : 'FromH';
desc : 'Shyuukan From H (PC98)';
baseresx : 480; baseresy : 296;
level : 2),

(CRC : $EBD54729; gidnum : gid_HOHOEMI; namu : 'Hohoemi';
desc : 'Tenshitachi no Hohoemi (PC98)';
baseresx : 496; baseresy : 328;
level : 1),

(CRC : $81A1F0C2; gidnum : gid_MAJOKKO; namu : 'Majokko';
desc : 'Majokko Paradise (PC98)';
baseresx : 480; baseresy : 296;
level : 2),

(CRC : $8476FBE0; gidnum : gid_MARIRIN; namu : 'Maririn';
desc : 'Super Ultra Mucchin Puripuri Cyborg Maririn DX (PC98)';
baseresx : 512; baseresy : 280;
level : 1),

(CRC : $CFB08395; gidnum : gid_MAYCLUB; namu : 'Mayclub';
desc : 'Mayclub (Win)';
baseresx : 480; baseresy : 288;
level : 1),

(CRC : $CD50066E; gidnum : gid_MAYCLUB98; namu : 'Mayclub98';
desc : 'Mayclub (PC98)';
baseresx : 480; baseresy : 288;
level : 1),

(CRC : $EE24DA1B; gidnum : gid_NOCTURNE; namu : 'Nocturne';
desc : 'Nocturnal Illusion (Win)';
baseresx : 480; baseresy : 304;
level : 1),

(CRC : $F911F9CD; gidnum : gid_NOCTURNE98; namu : 'Nocturne98';
desc : 'Mugen Yasoukyoku (PC98)';
baseresx : 480; baseresy : 304;
level : 1),

(CRC : $5B879F23; gidnum : gid_PARFAIT; namu : 'Parfait';
desc : 'Muchimuchi Sexy Parfait for Oneesan (Win)';
baseresx : 480; baseresy : 296;
level : 1),

(CRC : $05B8AA01; gidnum : gid_RENO; namu : 'ReNo';
desc : 'Re-No (PC98)';
baseresx : 480; baseresy : 296;
level : 0),

(CRC : $617C7CE9; gidnum : gid_RUNAWAY; namu : 'Runaway';
desc : 'Runaway City (DOS)';
baseresx : 480; baseresy : 296;
level : 3),

(CRC : $CFBFCBC2; gidnum : gid_RUNAWAY98; namu : 'Runaway98';
desc : 'Meisou Toshi (PC98)';
baseresx : 480; baseresy : 296;
level : 2),

(CRC : $0E5B98C7; gidnum : gid_SAKURA; namu : 'Sakura';
desc : 'Season of the Sakura (DOS)';
baseresx : 480; baseresy : 296;
level : 3),

(CRC : $C19433D2; gidnum : gid_SAKURA98; namu : 'Sakura98';
desc : 'Sakura no Kisetsu (PC98)';
baseresx : 480; baseresy : 296;
level : 2),

(CRC : $799265F3; gidnum : gid_SETSUJUU; namu : 'Setsujuu';
desc : 'Setsujuu - Yuganda Kioku (PC98)';
baseresx : 496; baseresy : 255;
level : 3),

(CRC : $A876CC7E; gidnum : gid_TASOGARE; namu : 'Tasogare';
desc : 'Tasogare no Kyoukai (PC98)';
baseresx : 480; baseresy : 296;
level : 1),

(CRC : $A0E6E952; gidnum : gid_TRANSFER98; namu : 'Transfer98';
desc : 'Tenshitachi no Gogo - Tenkousei (PC98)';
baseresx : 480; baseresy : 296;
level : 2),

(CRC : $AED4390C; gidnum : gid_TRUELOVE; namu : 'Truelove';
desc : 'True Love (Win)';
baseresx : 480; baseresy : 296;
level : 0),

(CRC : $0E3CC250; gidnum : gid_TRUELOVE98; namu : 'Truelove98';
desc : 'True Love (PC98)';
baseresx : 480; baseresy : 296;
level : 0),

(CRC : $CB59CF9A; gidnum : gid_VANISH; namu : 'Vanish';
desc : 'Vanishing Point (PC98)';
baseresx : 480; baseresy : 296;
level : 1),

(CRC : $C778B59A; gidnum : gid_VENUS; namu : 'Venus';
desc : 'Venus (PC98)';
baseresx : 480; baseresy : 296;
level : 0),

(CRC : $02CC490F; gidnum : gid_YUUGIRI; namu : 'Yuugiri';
desc : 'Yuugiri - Ningiyushi no Isan (PC98)';
baseresx : 480; baseresy : 296;
level : 0)
);
