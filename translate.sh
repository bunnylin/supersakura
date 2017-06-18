# CC0, 2017 :: Kirinn Bunnylin / Mooncore
# https://creativecommons.org/publicdomain/zero/1.0/

if [ $# -eq 0 ]
then
  echo "Usage: translate.sh inputfile.tsv >outputfile.tsv"
  echo "The input file should be a tsv. The leftmost column is preserved in"
  echo "the output as unique string IDs, and the rightmost column is taken"
  echo "as the text to be translated."
  echo "The translated output is printed in stdout in tsv format. You should"
  echo 'pipe it into a suitable file, for example "outputfile.tsv".'
  exit 1
fi

printf "String IDs\tOriginal\tPhonetic\tGoogle\tBing\tYandex\n"

while IFS= read -ru 10 line
do
  # Count how many tab characters this line has.
  numtabs=$(echo -n "$line" | grep -P -o "\t" | wc -l)

  # If there are no tabs, the line as a whole is used as translatable input.
  # Otherwise everything before the first tab is saved as the string ID, and
  # everything after the last tab is used as the translatable input.
  stringid=""
  if [ $numtabs -gt 0 ]
  then
    stringid=$(echo -n "$line" | cut -f1)
    line=$(echo -n "$line" | sed "s/.*\t//" )
  fi

  # Output the string ID and translatable input.
  echo -n "$stringid"
  printf "\t"
  echo -n "$line"
  printf "\t"

  # Apply pre-translation substitutions. The file trans-subs.txt should
  # contain one substitution per line, in the form "source/new text".
  # Lines starting with a # are treated as comments.
  while read -ru 11 sub
  do
    if ! echo -n "$sub" | grep -q "^ *#"
    then
      line=$(sed "s/$sub/g" <<< $line)
    fi
  done 11< <(grep . trans-subs.txt)

  # Replace backslashes with a double backslash. At least Bing sometimes
  # drops backslashes if not doubled.
  line=$(sed "s/\\\/\\\\\\\/g" <<< $line)

  # Google translate may need a few tries occasionally.
  tries=3
  while [ $tries -gt 0 ]
  do
    tries=$(( tries-1 ))
    transgoo=$(timeout 16 translate-shell ja:en \
      -e google -no-ansi -no-autocorrect -show-alternatives n \
      -show-languages n -show-prompt-message n -- "$line")
    if [ "$transgoo" != "" ]; then tries=0; fi
  done

  # $transgoo is now expected to have the original on line 1, the phonetic
  # on line 2 in brackets, and the translation on line 4, may be last line.
  trans0=$(echo -n "$transgoo" | sed -n 2p | sed "s/[()]//g")
  trans1=$(echo -n "$transgoo" | sed -n 4p)

  # Get the other translations.
  trans2=$(timeout 16 translate-shell -b ja:en -e bing -no-ansi -- "$line")
  trans3=$(timeout 16 translate-shell -b ja:en -e yandex -no-ansi -- "$line")

  # A brief wait between requests is polite to the translation servers.
  sleep 1

  # Pack the translated strings in a single variable for post-processing.
  # Delimit with tab characters.
  transall="$trans0"$'\t'"$trans1"$'\t'"$trans2"$'\t'"$trans3"

  # If the output contains ": ", but the input doesn't, then the space was
  # added unnecessarily and should be removed.
  if echo -n "$transall" | grep -q ": " \
  && ! echo -n "$line" | grep -q ": "
  then
    transall=$(echo -n "$transall" | sed "s/: /:/g")
  fi

  # The translators tend to add spaces after some backslashes, remove them.
  transall=$(sed "s/\\\ /\\\/g" <<< $transall)
  # Change double-backslashes back to normal.
  transall=$(sed "s/\\\\\\\/\\\/g" <<< $transall)
  # Some translators also add spaces after dollars, remove them.
  transall=$(sed "s/\\\$ /\\\$/g" <<< $transall)

  # Output the translated, processed strings.
  echo "$transall"
done 10< <(grep . "$1")

exit 0
