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
While compiling a project, use the -dumpstr=file.tsv commandline argument.
For example, the PC-98 version of the Three Sisters' Story:

	recomp 3sis98 -dumpstr=3sis98.tsv

This produces a simple tab-separated spreadsheet in the given file, in UTF-8
encoding. You can open it in any text editor, or LibreOffice Calc, or Excel,
or Notepad++ etc. If you are given any import options, be sure to turn off
everything except tab separation, and use UTF-8 encoding, and explicitly
import the columns as pure text.

The first column contains unique string IDs. The second column starts with
the column's language identifier, and has the actual strings in the game's
original language. The simplest way to translate is to just replace all the
Japanese text directly with English text. Alternatively, you can add a new
column, put the language identifier (English, probably) in the top cell, and
put the translated strings below it. Although in this case you may also need
to edit the game's main script and change the textboxes to expect English
text.

To help automate translation, you could try Mort Yao's excellent
[Translate-Shell] (https://www.soimort.org/translate-shell/)
utility. If you copy all strings into a simple text file, one line per
string, you could just use:

	translate-shell -b ja:en file://whatever.txt >output.txt

Although you may want to first replace all backslashes in the file with
double-backslashes. The goal is to make sure all instances of "\n" and "\$x"
are present unchanged in the translated strings. The included shell script
translate.sh may be able to do the whole thing for you, if you're on Linux
and have translate-shell installed:

	translate.sh input.txt >output.tsv

Translating all strings in a game will likely take hours. Perhaps leave it
running overnight. You can watch how the translation is going by opening
your output file, but don't do anything to save changes, as that could mess
up the translation output. And, since automatic translation sucks, you'll
still want to clean up at least the common verb:noun commands that are near
the start of the file. The verbs need to be consistently translated, or the
game may rarely fail to enable or disable the correct verbs.

There are a few other translation options. [Translation Aggregator]
(http://www.hongfire.com/forum/showthread.php/94395-Translation-Aggregator-v0-4-9?p=3648894#post3648894)
leverages both online and offline resources, but I'm not sure how hard it
would be to straight up feed a text file through it.

Once you have a translated file, copy its contents into the original .tsv
file, making sure the translated strings line up correctly with the unique
string IDs in the leftmost column. Save the file anywhere under the game's
project directory, under any filename as long as it ends with ".tsv". If you
need to edit the main script to change text box languages, do so now. Just
find all lines saying "tbox.setlanguage x Japanese" and change those to say
English. Recompile the game normally, and the translation should be in.

It is also possible to compile the translation into a mod, so the player can
just load the translation from SuperSakura's frontend. These are the minimal
steps, assuming the game's textboxes have been set to English:

1. Create a new project directory under SuperSakura's data directory, for
example "3sis98-en".

2. Copy the translated .tsv file there.

3. Create a data.txt file there. It should contain a description line, for
example "desc Sanshimai (English mod) (PC98)", and it should specify the
language: "language English".

4. Compile the mod by specifying the parent project name, for example:

	recomp 3sis98-en -parent=3sis98

You should end up with a new dat file. When loaded by SuperSakura, it will
automatically load its parent dat first. The nice thing about this modding
approach is that you can also include modified graphics in the mod, in case
the original graphics have localisable content. Just drop the new graphics
somewhere under the mod's project directory.

Modding sounds more complicated than it is. I hope to make the process more
friendly over time, and improve the documentation.
