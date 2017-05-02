SuperSakura engine
==================

SuperSakura is a modern visual novel engine that can run certain Japanese
games from the mid-90's. Many of these old titles were surprisingly good,
but were never localised. SuperSakura has tools to help localise games, and
supports enhanced graphics and a modernised user interface.

The engine is written in Free Pascal, and targets Linux/Windows, 32/64-bit.

Note that this is just a game engine, and a set of asset conversion tools.
The actual games themselves are under copyright and are not distributed with
this project. To run games on Supersakura, you need to convert the game data
from original files.

For a list of supported games, see inc/gidtable.inc, or the main site at
[mooncore.eu/ssakura](https://mooncore.eu/ssakura/).


Compiling
---------

Requirements:
- [The Free Pascal compiler](https://www.freepascal.org/)
- [SDL2 and SDL2_ttf](https://libsdl.org/) libraries/dlls
- [The SDL2 Pascal headers](https://github.com/ev1313/Pascal-SDL-2-Headers)
- [Various moonlibs](https://github.com/bunnylin/moonlibs)

After downloading the SuperSakura sources, you need to install FPC. Try to
make a hello-world program to confirm it works.

Next, get SDL2 and SDL2_ttf. If on Windows, you can download the dll's from
libsdl.org, and can put them either in your \Windows\System32 directory, or
in SuperSakura's source directory. On Linuxes, your distro's main software
repository will have SDL2.

Get the sources for the SDL2 Pascal headers and moonlibs, and save them in
a directory near FPC's other bundled units. On Windows, this is probably
\FPC\units\arch\. On Linuxes, it may be under /lib/fpc/version/arch/.
Alternatively, just dump everything in the SuperSakura source directory.

To compile, you can use the included comp.bat or comp.sh commands:

    comp <file>

Or invoke the compiler directly:

    fpc <file>

Although FPC will automatically build any units programs need, you may want
to start off by compiling the individual SDL2_xxx.pas and mcxxx.pas files
one by one, to see potential error messages more clearly.

Finally, build the engine and its tools:

    comp supersakura
    comp supersakura-con
    comp recomp
    comp decomp


Using the engine
----------------

To compile resources into a usable SuperSakura data file:

    recomp <projectname>

To run the game:

    supersakura <projectname>

Or, the non-graphical version:

    supersakura-con <projectname>

Aside from standard console output, these also create a recomp.log and
saku.log files in the working directory, or in your profile directory if the
working directory is not writable.


Converting game data
--------------------

The resource decompiler tool takes individual files from original games, and
saves them under SuperSakura's data directory in converted standard file
formats. Note, that although some PC-98 games are supported, Decomp cannot
yet extract the individual data files from .HDI or .FDI images, so if you
keep your PC-98 games in those, you will have to first extract the files
manually. EditDisk or another tool like it may do the trick.

To convert resources:

    decomp <filename or directory>

For example, to run the DOS version of The Three Sisters' Story (the Windows
port is not yet supported):

    decomp /mygames/threesistersstory/
    recomp 3sis
    supersakura 3sis
