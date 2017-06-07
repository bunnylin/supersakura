if [ $# -eq 0 ]
then
  echo "Usage: translate.sh (input file) >output.tsv"
  echo "The input file can have multiple strings, each on its own line."
  echo "You'll need to pipe the translated output into a suitable file."
  exit 1
fi

printf "Phonetic\tGoogle\tBing\tYandex\n"

while IFS= read -ru 10 line
do
  # Replace backslashes with a double backslash, to avoid shell weirdness.
  line=$(sed "s/\\\/\\\\\\\/g" <<< $line)

  transgoo=$(timeout 8 translate-shell ja:en -e google -no-ansi -no-autocorrect -show-alternatives n -show-languages n -show-prompt-message n -- "$line")
  # $transgoo is now expected to have the original on line 1, the phonetic
  # on line 2 in brackets, and the translation on line 4, may be last line.
  trans0=$(printf -- "$transgoo" | sed -n 2p | sed "s/[()]//g")
  trans1=$(printf -- "$transgoo" | sed -n 4p)

  # Get the other translations.
  trans2=$(timeout 8 translate-shell -b ja:en -e bing -no-ansi -- "$line")
  trans3=$(timeout 8 translate-shell -b ja:en -e yandex -no-ansi -- "$line")

  # Output a row.
  printf -- "$trans0\t$trans1\t$trans2\t$trans3\n"

  # A brief wait between requests is polite to the translation servers.
  sleep 1
done 10< <(grep . "$1")

exit 0
