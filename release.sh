#!/bin/sh -e

# Wichert: thought this might be useful :) -- Ben

# run the autogen, but make sure we copy everything instead of symlinking
./autogen.sh --copy

# remove CVS files
rm -rf `find . -name CVS -type d`
rm -f `find . -name .cvsignore -type f`

# Remove any cruft files...
rm -f `find . -name '*.orig' -o -name '*.rej' -o -name '*~'`

# Generate all the gettext stuff
cd po
./update.sh
catalogs='en.gmo fr.gmo es.gmo ja_JP.ujis.gmo'
for cat in $catalogs; do
  lang=`echo $cat | sed 's/\.gmo$//'`
  msgfmt -o $cat $lang.po
done
cd ..

# Now remove the CVS scripts
rm -f autogen.sh release.sh po/update.sh
