#!/bin/sh

# Wichert: thought this might be useful :) -- Ben

# run the autogen, but make sure we copy everything instead of symlinking
./autogen.sh --copy

# remove CVS files
rm -rf `find . -name CVS -type d`
rm -f `find . -name .cvsignore -type f`

# Remove any cruft files...
rm -f `find . -name '*.orig' -o -name '*.rej' -o -name '*~'`

# Now remove the CVS scripts
rm -f autogen.sh release.sh
