#! /bin/sh

copy=$1

# Start by setting up everything for main tree
aclocal -I ./automake
gettextize $copy -f
libtoolize --force $copy
autoheader
autoconf
