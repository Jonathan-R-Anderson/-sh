#!/usr/bin/env sh

# Example script demonstrating a case statement
# describing the number of legs certain animals have.

printf "Enter the name of an animal: "
read ANIMAL
printf "The %s has " "$ANIMAL"
case $ANIMAL in
  horse|dog|cat)
    legs="four"
    ;;
  man|kangaroo)
    legs="two"
    ;;
  *)
    printf "an unknown number of "
    legs=""
    ;;
esac
if [ -n "$legs" ]; then
  echo "$legs legs."
else
  echo "legs."
fi
