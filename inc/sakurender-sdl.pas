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

// SuperSakura-SDL rendering functions

{$include sakurender-all.pas}

procedure Renderer;
// Handles all visual output into outputbuffy^.
var rekt : TSDL_Rect;
    refrect : dword;
begin
 refrect := numfresh;
 while refrect <> 0 do begin
  dec(refrect);

  // Draw stuff.
  RenderGobs(refresh[refrect], mv_OutputBuffy);

  // Push into the output texture.
  with refresh[refrect] do begin
   rekt.x := x1p;
   rekt.y := y1p;
   rekt.w := x2p - x1p;
   rekt.h := y2p - y1p;

   SDL_UpdateTexture(mv_MainTexH,
     @rekt,
     mv_OutputBuffy + (y1p * longint(sysvar.mv_WinSizeX) + x1p) * 4,
     sysvar.mv_WinSizeX * 4);
  end;
 end;

 // Push the texture into the renderer. Apparently we can't rely on the
 // previous frame still being there, so gotta do fullscreen updates.
 SDL_RenderCopy(mv_RendererH, mv_MainTexH, NIL, NIL);

 // Reset the refresh regions.
 if (numfresh = 0) and (length(refresh) > 24) then begin
  setlength(refresh, 0); setlength(refresh, 16);
 end;
 numfresh := 0;
end;
