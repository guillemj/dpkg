#! /bin/sh

# Start by setting up everything for main tree
aclocal -I ./automake
autoheader
gettextize
libtoolize --force
automake --add-missing --foreign
autoconf

# Utils has it's own configure, so we need to repeat this there
cd utils
aclocal -I ../automake
autoheader
automake --foreign
autoconf

# Return to the previous directory
cd ..

