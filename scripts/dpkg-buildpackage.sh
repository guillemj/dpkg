#!/bin/sh

set -e

version="1.3.0"; # This line modified by Makefile

progname="`basename \"$0\"`"
usageversion () {
	cat >&2 <<END
Debian GNU/Linux dpkg-buildpackage $version.  Copyright (C) 1996
Ian Jackson.  This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

Usage: dpkg-buildpackage [options]
Options:  -r<gain-root-command>
          -p<pgp-command>
          -b         (binary-only)
          -B         (binary-only, no arch-indep files)
          -us        (unsigned source)
          -uc        (unsigned changes)
          -h         print this message
END
}

rootcommand=''
pgpcommand=pgp
signsource=signfile
signchanges=signfile

while [ $# != 0 ]
do
	value="`echo x\"$1\" | sed -e 's/^x-.//'`"
	case "$1" in
	-h)	usageversion; exit 0 ;;
	-r*)	rootcommand="$value" ;;
	-p*)	pgpcommand="$value" ;;
	-us)	signsource=: ;;
	-uc)	signchanges=: ;;
	-b|-B)	binaryonly=$1 ;;
	*)	echo >&2 "$progname: unknown option or argument $1"
		usageversion; exit 2 ;;
	esac
	shift
done

mustsetvar () {
	if [ "x$2" = x ]; then
		echo >&2 "$progname: unable to determine $3"
		exit 1
	else
		echo "$progname: $3 is $2"
		eval "$1=\"\$2\""
	fi
}

curd="`pwd`"
dirn="`basename \"$curd\"`"
mustsetvar package "`dpkg-parsechangelog | sed -n 's/^Source: //p'`" "source package"
mustsetvar version "`dpkg-parsechangelog | sed -n 's/^Version: //p'`" "source version"
mustsetvar arch "`dpkg --print-architecture`" "build architecture"
pv="${package}_${version}"
pva="${package}_${version}_${arch}"

signfile () {
	$pgpcommand -fast <"../$1" >"../$1.asc"
	mv -- "../$1.asc" "../$1"
}

set -x -e

$rootcommand debian/rules clean
if [ x$binaryonly = x ]; then
	cd ..; dpkg-source -b "$dirn"; cd "$dirn"
fi
debian/rules build
$rootcommand debian/rules binary
$signsource "$pv.dsc"
dpkg-genchanges $binaryonly >../"$pva.changes"
$signchanges "$pva.changes"
