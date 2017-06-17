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
  # Apply pre-translation substitutions.
  while read -ru 11 sub
  do
    if ! echo $sub | grep -q "^ *#"
    then
      line=$(sed "s/$sub/g" <<< $line)
    fi
  done 11< <(grep . trans-subs.txt)

  # Replace backslashes with a double backslash, to avoid shell weirdness.
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
  trans0=$(printf -- "$transgoo" | sed -n 2p | sed "s/[()]//g")
  trans1=$(printf -- "$transgoo" | sed -n 4p)

  # Get the other translations.
  trans2=$(timeout 16 translate-shell -b ja:en -e bing -no-ansi -- "$line")
  trans3=$(timeout 16 translate-shell -b ja:en -e yandex -no-ansi -- "$line")

  # A brief wait between requests is polite to the translation servers.
  sleep 1

  # Output a row.
  transall="$trans0\t$trans1\t$trans2\t$trans3"
  printf -- "$transall\n"
done 10< <(grep . "$1")

exit 0
