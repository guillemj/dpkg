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
catalogs=`ls *.po`
for cat in $catalogs; do
  if [ "$cat" = "dpkg.po" ] ; then continue ; fi
  lang=`echo $cat | sed 's/\.po$//'`
  msgfmt -o $lang.gmo $cat
done
cd ..

# Kill some obsolete directories found in CVS
rm -rf attic/ doc/obsolete

# Now remove the CVS scripts
rm -f autogen.sh release.sh po/update.sh
