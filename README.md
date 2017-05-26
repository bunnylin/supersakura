SuperSakura engine
==================

SuperSakura is a modern visual novel engine that can run certain Japanese
games from the mid-90's. Many of these old titles were surprisingly good,
but were never localised. SuperSakura has tools to help localise games, and
supports enhanced graphics and a modernised user interface.

The engine is written in Free Pascal, uses SDL2, and targets Linux/Windows,
32/64-bit.

Note that this is just a game engine, and a set of asset conversion tools.
The actual games themselves are under copyright and are not distributed with
this project. To run games on Supersakura, you need to convert the game data
from original files.

For a list of supported games, run "decomp -list", or see inc/gidtable.inc,
or visit the main site at
[mooncore.eu/ssakura](https://mooncore.eu/ssakura/).


Downloads
---------

You can get a reasonably recent Win32 build of the engine and tools from
[mooncore.eu/ssakura](https://mooncore.eu/ssakura/). But for best results,
see below on how to compile your own copy.


Compiling
---------

Requirements:
- [The Free Pascal compiler](https://www.freepascal.org/)
- [SDL2 and SDL2_ttf](https://libsdl.org/) libraries/dlls
- [The SDL2 Pascal headers](https://github.com/ev1313/Pascal-SDL-2-Headers)
- [Various moonlibs](https://github.com/bunnylin/moonlibs)

After downloading the SuperSakura sources, you need to install FPC. Try to
make a hello-world program to confirm it works.

Next, get SDL2 and SDL2_ttf. These are dynamically linked libraries that
must be present on the system for the engine to run. If on Windows, you can
download the dll's from libsdl.org, and can put them either in your
\Windows\System32 directory, or in SuperSakura's source directory. On
Linuxes, your distro's main software repository will have SDL2 and SDL2_ttf.

The SDL2 Pascal headers and moonlibs are statically linked units or
libraries; they are needed to compile the engine and tools, but afterward
are not needed to run them. Download the sources for those and save them in
a directory near FPC's other units. On Windows, this is probably
\FPC\units\arch\. On Linuxes, it may be under /usr/lib/fpc/version/arch/.
If you have trouble finding where FPC keeps its units, see the relevant
[wiki page](http://wiki.freepascal.org/Unit_not_found_-_How_to_find_units).

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

For example, to compile the included Winterquest ministory/testsuite:

    recomp winterq

To run any compiled game through a friendly frontend:

    supersakura

Or, to run the console port:

    supersakura-con

The tools and engine print their log output into files: saku.log, recomp.log,
and decomp.log. By default, these are put in the program's working directory.
If the working directory is write-protected, then the logs are saved under
your profile directory.

You can add -h to any executable's commandline to see what other commandline
options are available.


Converting game data
--------------------

The resource decompiler tool takes individual files from original games, and
saves them under SuperSakura's data directory in converted standard file
formats. Note, that although some PC-98 games are supported, Decomp cannot
yet extract the individual data files from .HDI or .FDI images, so if you
keep your PC-98 games in those, you will have to first extract the files
from the disk image manually. EditDisk or another tool like it may do the
trick.

To convert resources:

    decomp <filename or directory>

For example, to convert and run the DOS version of The Three Sisters' Story
(the Windows port is not yet supported):

    decomp /mygames/threesistersstory/
    recomp 3sis
    supersakura 3sis
