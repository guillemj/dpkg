#! /bin/sh

copy=$1

# Start by setting up everything for main tree
aclocal -I ./automake
gettextize $copy -f
libtoolize --force $copy
autoheader
automake --add-missing --foreign $copy
autoconf

# Utils has it's own configure, so we need to repeat this there
cd utils
aclocal -I ../automake
autoheader
automake --foreign
autoconf -l ../

# Return to the previous directory
cd ..

