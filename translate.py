#!/usr/bin/python
# CC0, 2017 :: Kirinn Bunnylin / Mooncore
# https://creativecommons.org/publicdomain/zero/1.0/

import sys, re, time, subprocess
#from subprocess import check_output

if len(sys.argv) < 2:
  print("Usage: python translate.py inputfile.tsv >outputfile.tsv")
  print("The input file should be a tsv. The leftmost column is preserved in")
  print("the output as unique string IDs, and the rightmost column is taken")
  print("as the text to be translated.")
  print("The translated output is printed in stdout in tsv format. You should")
  print('pipe it into a suitable file, for example "outputfile.tsv".')
  sys.exit(1)


def GetTranslation(com):
# Handy retry loop with a timeout for easily invoking translate-shell.
  tries = 4
  while tries != 0:
    tries -= 1
    try:
      transres = subprocess.check_output(com, timeout = 16)
      transres = transres.decode(sys.stdout.encoding).split("\n")
    except subprocess.CalledProcessError:
      transres = [""]
    if len(transres) != 0: tries = 0
    else: time.sleep(4)
  return transres


# Read the constant substitutions list into memory. The file trans-subs.txt
# should contain one substitution per line, in the form "source/new text".
# Lines starting with a # are treated as comments.
sublist = []
with open("trans-subs.txt") as subfile:
  for line in subfile:
    if line[0] != "#":
      line = line.rstrip()
      if line != "":
        splitline = line.split("/")
        sublist.append({"from": splitline[0], "to": splitline[-1]})

# Print the output header.
print("String IDs\tOriginal\tPhonetic\tGoogle\tBing\tYandex")
sys.stdout.flush()

with open(sys.argv[1]) as infile:
  for line in infile:

    delaytime = time.time() + 1.024

    # If this line has no tabs, the line as a whole is used as translatable
    # input. Otherwise everything before the first tab is saved as the
    # string ID, and everything after the last tab is used as the
    # translatable input.
    stringid = ""
    splitline = line.rstrip().split("\t")
    if len(splitline) > 1:
      stringid = splitline[0]
    line = splitline[-1]

    # Output the string ID and translatable input.
    linepart = stringid + "\t" + line + "\t"
    sys.stdout.buffer.write(linepart.encode("utf-8"))

    # Apply pre-translation substitutions.
    for subitem in sublist:
      line = line.replace(subitem["from"], subitem["to"])

    # Replace backslashes with a double backslash. At least Bing sometimes
    # drops backslashes if not doubled.
    line = line.replace("\\", "\\\\")

    # Google translate, wrapped in a retry loop.
    transgoo = GetTranslation(["translate-shell","ja:en","-e","google",
      "-no-ansi","-no-autocorrect","-show-alternatives","n",
      "-show-languages","n","-show-prompt-message","n","--",line])

    # transgoo is now expected to have the original on line 1, the phonetic
    # on line 2 in brackets, and the translation on line 4.
    trans0 = transgoo[1][1:-1]
    trans1 = transgoo[3]

    # Get the other translations.
    trans2 = GetTranslation(["translate-shell","-b","ja:en","-e","bing",
      "-no-ansi","--",line])[0]
    trans3 = GetTranslation(["translate-shell","-b","ja:en","-e","yandex",
      "-no-ansi","--",line])[0]

    # A brief wait between requests is polite to the translation servers.
    delaylen = delaytime - time.time()
    if delaylen > 0: time.sleep(delaylen)

    # Pack the translated strings in a single variable for post-processing.
    # Delimit with tab characters.
    transall = trans0 + "\t" + trans1 + "\t" + trans2 + "\t" + trans3 + "\n"

    # If the output contains ": ", but the input doesn't, then the space was
    # added unnecessarily and should be removed.
    if transall.find(": ") != -1 and line.find(": ") == -1:
      transall = transall.replace(": ", ":")

    # The translators tend to add spaces after some backslashes, remove.
    transall = transall.replace("\\ ", "\\")
    # Change double-backslashes back to normal.
    transall = transall.replace("\\\\", "\\")
    # Some translators also add spaces after dollars, remove them.
    transall = transall.replace("\\$ ", "\\$")

    # Output the translated, processed strings.
    sys.stdout.buffer.write(transall.encode("utf-8"))
    sys.stdout.flush()

# end.
