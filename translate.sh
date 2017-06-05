if [ $# -eq 0 ]
then
  echo "Usage: translate.sh (input file) >output.tsv"
  echo "The input file can have multiple strings, each on its own line."
  echo "You'll need to pipe the translated output into a suitable file."
  exit 1
fi

printf "Google\tBing\tYandex\n"

while IFS= read -ru 10 line
do
  line=$(sed "s/\\\/\\\\\\\/g" <<< $line)
  trans1=$(timeout 8 translate-shell -b -e google -no-autocorrect ja:en "$line")
  trans2=$(timeout 8 translate-shell -b -e bing ja:en "$line")
  trans3=$(timeout 8 translate-shell -b -e yandex ja:en "$line")
  printf "$trans1\t$trans2\t$trans3\n"
  sleep 1
done 10< <(grep . "$1")

exit 0
