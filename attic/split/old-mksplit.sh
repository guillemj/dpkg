#!/bin/bash
# This script is only supposed to be called by dpkg-split.
# Its arguments are:
#  <sourcefile> <partsize> <prefix> <totalsize> <partsizeallow> <msdostruncyesno>
# Stdin is also redirected from the source archive by dpkg-split.

# Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

set -ex

if [ "$#" != 6 ]; then echo >&2 'Bad invocation of mksplit.sh.'; exit 1; fi

sourcefile="$1"
partsize="$2"
prefix="$3"
orgsize="$4"
partsizeallow="$5"
msdos="$6"

myversion=2.1
csum=`md5sum <"$sourcefile"`
package="`dpkg-deb --field \"$sourcefile\" Package`"
version="`dpkg-deb --field \"$sourcefile\" Version`"
revision="`dpkg-deb --field \"$sourcefile\" Package_Revision`"
if [ "x$revision" != x ]; then version="$version-$revision"; fi
nparts=$[($orgsize+$partsize-1)/$partsize]
startat=0
partnum=0

td=/tmp/ds$$
mkdir $td
ec=1
trap "rm -r $td; exit $ec" 0
dsp=$td/debian-split

echo -n "Splitting package $package into $nparts parts: "

if [ yes = "$msdos" ]
then
	prefixdir="`dirname \"$prefix\"`"
	cleanprefix="`basename \"$prefix\" | tr A-Z+ a-zx | tr -dc 0-9a-z-`"
fi

ar-include () {
	perl -e '
		$f= $ARGV[0];
		(@s= stat(STDIN)) || die "$f: $!";
                undef $/; read(STDIN,$d,$s[7]) == $s[7] || die "$f: $!";
		printf("%-16s%-12d0     0     100644  %-10d%c\n%s%s",
			$f, time, $s[7], 0140, $d,
                        ($s[7] & 1) ? "\n" : "") || die "$f: $!";
                close(STDOUT) || die "$f: $!";
	' "$1" <"$td/$1"
}                 

while [ $startat -lt $orgsize ]
do
	showpartnum=$[$partnum+1]
	echo $myversion >$dsp
	echo $package >>$dsp
	echo $version >>$dsp
	echo $csum >>$dsp
	echo $orgsize >>$dsp
	echo $partsize >>$dsp
	echo $showpartnum/$nparts >>$dsp
	dd bs=$partsize skip=$partnum count=1 \
	   of=$td/data.$showpartnum \
	 2>&1 | (egrep -v '.* records (in|out)' || true)
	rm -f $td/part
	echo -n "$showpartnum "
	echo '!<arch>' >$td/part
	ar-include debian-split >>$td/part
	ar-include data.$showpartnum >>$td/part
	thispartreallen="`ls -l $td/part | awk '{print $5}'`"
	if ! [ "$thispartreallen" -le "$partsizeallow" ]
	then
		cat >&2 <<END

Header is too long, making part too long.  Your package name or version
numbers must be extraordinarily long, or something.  Giving up.
END
		exit 1
	fi
	if [ yes = "$msdos" ]
	then
		basename="`echo ${showpartnum}of$nparts.\"$cleanprefix\" | \
			   dd bs=9 count=1 2>/dev/null | \
			   sed -e 's/^\([^.]*\)\.\(.*\)$/\2\1/'`"
		basename="$prefixdir/$basename"
	else
		basename="$prefix.${showpartnum}of$nparts"
	fi
	mv $td/part $basename.deb
	startat=$[$startat+$partsize]
	partnum=$showpartnum
done
echo "done"

ec=0
