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

For a list of supported games, run `decomp -list`, or see
`inc/gidtable.inc`, or visit the main site at
[mooncore.eu/ssakura](https://mooncore.eu/ssakura/).


Screenshots
-----------

See [here](https://mooncore.eu/ssakura/sscreens.php).


Downloads
---------

You can get a reasonably recent Win32 build of the engine and tools from
[mooncore.eu/ssakura](https://mooncore.eu/ssakura/). But for best results,
see below on how to compile your own copy.

You MUST have SDL2 installed to run the engine!


SDL2
----

This is a famous video/audio library used by many modern games, so you may
already have it on your system. If not, it is easy to get.

**32-bit Windows**: Get the 32-bit runtime binary for Windows from
[libsdl.org/download-2.0.php](https://libsdl.org/download-2.0.php), and the
font-rendering 32-bit runtime binary from
[libsdl.org/projects/SDL_ttf](https://www.libsdl.org/projects/SDL_ttf/).
Put both in your `\Windows\System32` directory (or in the same directory
where SuperSakura is, if you prefer).

**64-bit Windows**: You can run the 32-bit version of SuperSakura on 64-bit
Windowses, so do the same as above, except you may need to put the DLL files
in your `\Windows\SysWOW64` directory. If you have a 64-bit version of
SuperSakura, get the 64-bit SDL2 and SDL2_ttf runtime binaries and put those
in your `\Windows\System32` directory (or in the same directory where
SuperSakura is, if you prefer).

**Linux**: Your distro's main software repository should have SDL2 and
SDL2_ttf. On Debian/Ubuntu, the packages may be named libsdl2-2.0-0 and
libsdl2-ttf-2.0-0. Install both through your normal package manager. You
should end up with libSDL2*.so files somewhere under your `/usr/lib` or
`/usr/lib/x86_64-linux-gnu` directory. The two files that must be present
are libSDL2.so and libSDL2_ttf.so. If you do not have these, it is possible
your package manager only set up version-numbered files and neglected to
create generically named links for them. This can be fixed by manually
creating the symbolic links in the library directory:

	ln -s libSDL2-2.0.so.0 libSDL2.so
	ln -s libSDL2_ttf-2.0.so.0 libSDL2_ttf.so

Some useful information on setting up SDL2 for Linux is [here](http://www.freepascal-meets-sdl.net/chapter-2-installation-configuration-linux-version/).
Note, that under some conditions SDL may crash on startup due to an
unsupported rendering mode. This happens especially if trying to run in
a Linux inside VirtualBox, which has imperfect graphic acceleration support.
[Overriding the SDL video driver](https://wiki.libsdl.org/FAQUsingSDL) may
help in this case. If you get a division by zero on startup, it's possible
your SDL version is outdated; building the latest SDL2 source from the
master branch may get it working.


Compiling
---------

Requirements:
- [The Free Pascal compiler](https://www.freepascal.org/)
- [SDL2 and SDL2_ttf](https://libsdl.org/) libraries/dlls
- [The SDL2 Pascal headers](https://github.com/ev1313/Pascal-SDL-2-Headers)
- [Various moonlibs](https://github.com/bunnylin/moonlibs)

After downloading the SuperSakura sources, you need to install FPC.
Preferably get the latest 3.0.x compiler version. Try to make a hello-world
program to confirm it works.

Next, get the SDL2 and SDL2_ttf runtime binaries. (You won't need the
development libraries for this.) The binaries are dynamically linked
libraries that must be present on the system for the engine to run. See the
SDL2 section above for details.

The SDL2 Pascal headers and moonlibs are statically linked units or
libraries; they are needed to compile the engine and tools, but afterward
are not needed to run them. Download the sources for those and save them in
a directory near FPC's other units. On Windows, this is probably
`\FPC\units\<arch>\`. On Linuxes, it may be under
`/usr/lib/fpc/version/<arch>/`. If you have trouble finding where FPC keeps
its units, see the relevant
[wiki page](http://wiki.freepascal.org/Unit_not_found_-_How_to_find_units).

Alternatively, just dump everything in the SuperSakura source directory. You
can also edit the compiler's
[configuration file](https://www.freepascal.org/docs-html/user/usersu10.html)
to tell it where to look for units. The unit directories are specified in
the format `-FuDirectory/Subdirectory/Subdirectory`.

To compile a program or unit, you can use the included `comp.bat` or
`comp.sh` commands:

    comp <file>

Or invoke the compiler directly:

    fpc <file>

Although FPC will automatically build any units needed by programs, you may
want to start off by compiling the individual `SDL2_xxx.pas` and `mcxxx.pas`
files one by one, to see potential error messages more clearly. As long as
the compiler output doesn't say "Fatal:" or "Error:" at the end, it probably
worked. The created unit or executable will be in the same directory as the
source.

To build the whole engine and its tools:

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

The tools and engine print their log output into files: `saku.log`,
`recomp.log`, and `decomp.log`. By default, these are put in the program's
working directory. If the working directory is write-protected, then the
logs are saved under your profile directory.

You can add -h to any executable's commandline to see what other commandline
options are available.

The console port works best when playing games in English. If your console
is configured to correctly display Japanese characters, you can also play in
Japanese. But successfully configuring a console to show UTF-8-encoded
Japanese, especially in Windows, can be challenging. I was able to get it
working in various Linuxes and Windows XP, but not in Windows 7. You might
consider a third-party console replacement, such as
[ConEmu](https://conemu.github.io/).


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


Translating games
-----------------

Under EU law, translations count as derivative works, and it would be
a copyright infringement to make them available to the public without
permission from the rightsholder, whether in patch form or otherwise.
Therefore, translations for the supported games are not distributed with
this project. However, you can easily produce a basic translation through
machine translation, which is legal as long as it is only for your personal
use. Publishing such a translation on peer-to-peer filesharing systems or at
ROMhacking.net would again be infringing.

To dump the Japanese strings from a game, you need to use the Recomp tool.
While compiling a project, use the `-dumpstr=file.tsv` commandline argument.
For example, for the PC-98 version of the Three Sisters' Story:

	recomp 3sis98 -dumpstr=3sis98.tsv

Alternatively, read and dump strings straight from a dat file:

	recomp -load=data/3sis98.dat -dumpstr=3sis98.tsv

This produces a simple tab-separated spreadsheet in the given file, in UTF-8
encoding. You can open it in any text editor, or LibreOffice Calc, or Excel,
or Notepad++ etc. If you are given any import options, be sure to turn off
everything except tab delimitation/separation, explicitly ask for UTF-8
encoding, and import the columns as pure "Text" rather than "Standard" etc.

The first column contains unique string IDs. The second column starts with
the column's language identifier, and has the actual strings in the game's
original language. You can add a new column, put "English" in the top cell,
and type all translated strings below it.

To help automate translation, you could try Mort Yao's excellent
[Translate-Shell](https://www.soimort.org/translate-shell/)
utility. If you copy all strings into a simple text file, one line per
string, you could try this command:

	translate-shell -b ja:en file://whatever.txt >output.txt

Included with SuperSakura are helper scripts that make using translate-shell
more robust. You can feed in the string table tsv file as is, and the script
will produce a new tsv with a few different translation alternatives, easy
to polish manually. The scripts also do constant string substitutions from
`trans-subs.txt`, so you can add commonly mistranslated terms there to force
a correct translation.

If you're on Linux, with translate-shell installed and on the system path:

	translate.sh input.tsv >output.tsv

Or, if you have Python 3, again with translate-shell installed and available
on the system path:

	python translate.py input.tsv >output.tsv

Automatically translating all strings in a game will likely take hours.
Perhaps leave it running overnight. You can watch how the translation is
going by opening your output file in a text editor, but don't do anything to
save changes, as that could mess up the translation output.

There are a few other translation options.
[Translation Aggregator](http://www.hongfire.com/forum/showthread.php/94395-Translation-Aggregator-v0-4-9?p=3648894#post3648894)
leverages both online and offline resources, but I'm not sure how hard it
would be to straight up feed a text file through it.

Once you have a translated tsv file, some things still need to be checked
manually. At least you should clean up the verb:noun commands, in the first
few hundred lines of the file. The verbs must be consistently translated, or
some game scripts may fail to enable or disable the correct verbs. Also,
check that all escape codes were preserved; for example, `\n` or
`\$varname;` must look exactly the same in the original string and in the
translated string. Finally, there is one special string, probably ID
`MAIN..1` or thereabouts. It says `Japanese`. Change that to `English`. This
controls the textbox language and font.

Finally, delete all columns except `String IDs` and your new `English`
column. Save this single-tab two-column spreadsheet as a tsv file, or csv
file with tab-separated values. The filename can be anything, as long as it
ends with the .tsv suffix, for example `3sis98-en.tsv`.

The translated strings can be inserted into a game in two ways. The simpler
way is to copy the .tsv file anywhere under the game's project directory
with all the other converted game resources. Recompile the game normally,
and it should now run in English by default.

The second way is to compile a mod, so the translation can be loaded from
SuperSakura's frontend. These are the minimal steps:

1. Create a new project directory under SuperSakura's data directory, for
example `3sis98-en`.

2. Copy the translated .tsv file in the new directory.

3. Create a `data.txt` file there. It should contain a description line, for
example `desc Sanshimai (English mod) (PC98)`, and it should specify the
language: `language English`.

4. Compile the mod by specifying the parent project name, for example:
	`recomp 3sis98-en -parent=3sis98`

You should end up with a new dat file. When you load the new dat in
SuperSakura, the engine will automatically load the parent dat first. An
extra bonus with this modding approach is that you can also include modified
graphics in the mod, in case the original graphics have localisable content
or annoying mosaics or whatever. Just drop the new graphics anywhere under
the mod's project directory and recompile. When the dat is loaded, the
graphics also get loaded over the original game's graphics by the same
filenames. (You can replace game scripts as well, but that gets more
complicated.)
