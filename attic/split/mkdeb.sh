#!/bin/bash
# This script is only supposed to be called by dpkg-deb.
# Its arguments are: <sourcefile> <partsize> <prefix> <totalsize>
# Stdin is also redirected from the source archive by dpkg-split.

# Copyright (C) 1995 Ian Jackson <ian.greenend.org.uk>
#
#   This is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as
#   published by the Free Software Foundation; either version 2,
#   or (at your option) any later version.
#
#   This is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with dpkg; if not, write to the Free Software
#   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

set -e

if [ "$#" != 4 ]; then echo >&2 'Bad invocation of mksplit.sh.'; exit 1; fi

sourcefile="$1"
partsize="$2"
prefix="$3"
orgsize="$4"

myversion=2.0
binary=i386-linux
#csum=`md5sum <"$sourcefile"`
#package="`dpkg-deb --field \"$sourcefile\" Package`"
#version="`dpkg-deb --field \"$sourcefile\" Version`"
#revision="`dpkg-deb --field \"$sourcefile\" Package_Revision`"
startat=0
partnum=0

mkdir /tmp/ds$$
ec=1
trap "rm -r /tmp/ds$$; exit $ec" 0
dsp=/tmp/ds$$/debian-binary

echo -n "Splitting package $package into $nparts parts: "

while [ $startat -lt $orgsize ]
do
	showpartnum=$[$partnum+1]
	echo $myversion >$dsp
	echo $binary >>$dsp
	tar -C DEBIAN -cf /tmp/ds$$/control .
	tar --
	dd bs=$partsize skip=$partnum count=1 \
	   of=/tmp/ds$$/data.$showpartnum \
	 2>&1 | (egrep -v '.* records (in|out)' || true)
	rm -f /tmp/ds$$/part
	echo -n "$showpartnum "
	(cd /tmp/ds$$ &&
	 ar qc part debian-split data.$showpartnum)
	mv /tmp/ds$$/part $prefix.${showpartnum}of$nparts.deb
	startat=$[$startat+$partsize]
	partnum=$showpartnum
done
echo "done"

ec=0
