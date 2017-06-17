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

To compile, you can use the included `comp.bat` or `comp.sh` commands:

    comp <file>

Or invoke the compiler directly:

    fpc <file>

Although FPC will automatically build any units programs need, you may want
to start off by compiling the individual `SDL2_xxx.pas` and `mcxxx.pas`
files one by one, to see potential error messages more clearly.

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

The tools and engine print their log output into files: `saku.log`,
`recomp.log`, and `decomp.log`. By default, these are put in the program's
working directory. If the working directory is write-protected, then the
logs are saved under your profile directory.

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

The shell script translate.sh included with SuperSakura's tools may be able
to do even more, if you're on Linux and have translate-shell installed. You
can feed it the string table tsv file as is, and it will produce a new tsv
with a few different translation alternatives, easy to polish manually. The
script also does constant string substitutions from `trans-subs.txt`, so you
can add commonly mistranslated terms there to force a correct translation.

	translate.sh input.tsv >output.tsv

Automatically translating all strings in a game will likely take hours.
Perhaps leave it running overnight. You can watch how the translation is
going by opening your output file, but don't do anything to save changes, as
that could mess up the translation output.

There are a few other translation options.
[Translation Aggregator](http://www.hongfire.com/forum/showthread.php/94395-Translation-Aggregator-v0-4-9?p=3648894#post3648894)
leverages both online and offline resources, but I'm not sure how hard it
would be to straight up feed a text file through it.

Once you have a translated file, some things still need to be checked
manually. At least you should clean up the verb:noun commands, in the first
few hundred lines of the file. The verbs must be consistently translated, or
some game scripts may fail to enable or disable the correct verbs. Also,
check that all escape codes were preserved unchanged; for example, `\n` or
`\$varname;`. Finally, there is one special string, probably ID `MAIN..1` or
thereabouts. It says `Japanese`. Change that to `English`. This controls the
textbox language.

To make the final string table, delete all columns except `String IDs` and
your new `English` column. Save this as a tsv file, or csv file with
tab-separated values. The filename can be anything, as long as it ends with
the .tsv suffix.

The translated strings can be put into a game in two ways. The simpler one
is to copy the .tsv file anywhere under the game's project directory with
all the other converted game resources. Recompile the game normally, and it
should now run in English by default.

The second way is to compile a mod, so the translation can be loaded from
SuperSakura's frontend. These are the minimal steps:

1. Create a new project directory under SuperSakura's data directory, for
example `3sis98-en`.

2. Copy the translated .tsv file in the new directory.

3. Create a `data.txt` file there. It should contain a description line, for
example `desc Sanshimai (English mod) (PC98)`, and it should specify the
language: `language English`.

4. Compile the mod by specifying the parent project name, for example:


	recomp 3sis98-en -parent=3sis98

You should end up with a new dat file. When you load the new dat in
SuperSakura, the engine will automatically load the parent dat first. An
extra bonus with this modding approach is that you can also include modified
graphics in the mod, in case the original graphics have localisable content
or annoying mosaics or whatever. Just drop the new graphics anywhere under
the mod's project directory, and they'll get loaded over the original game's
graphics by the same filenames. (You can replace game scripts as well, but
that gets more complicated.)
