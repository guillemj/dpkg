#!/bin/sh

set -e

prog="`basename \"${0}\"`"
version="0.11"; # This line modified by Makefile
purpose="rename Debian packages to full package names"

license () {
echo "# ${prog} ${version} -- ${purpose}
# Copyright (C) 1995,1996 Erick Branderhorst <branderhorst@heel.fgg.eur.nl>.

# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any
# later version.

# This is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
# /usr/doc/copyright/GPL for more details."
}

stderr () {
	echo "${prog}: $@" >/dev/stderr;
}

show_version () {
	echo "${prog} version ${version} -- ${purpose}";
}

usage () {
	echo "Usage: ${prog} file[s]
  ${purpose}
  file.deb changes to <package>-<version>[-<revision>].deb
  -h|--help|-v|--version|-l|--license  Show help/version/license"
}

rename () {
	if [ -f "$1" ];
	then
		if p=`dpkg-deb -f -- "$1" package`;
		then
			p="$p-"`dpkg-deb -f -- "$1" version`;
			r=`dpkg-deb -f -- "$1" revision`;
			if [ -z "$r" ];
			then
				r=`dpkg-deb -f -- "$1" package_revision`;
			fi
			if [ -n "$r" ];
			then
				p=$p-$r;
			fi
			p=`echo $p|sed 's/ //g'`
			p=`dirname "$1"`"/"$p.deb	
			if [ $p -ef "$1" ];									# same device and inode numbers
			then
				stderr "skipping \`"$1"'";
			elif [ -f $p ];
			then
				stderr "can't move \`"$1"' to existing file";
			elif `mv -- "$1" $p`;
			then
				echo "moved \``basename "$1"`' to \`${p}'";
			else
				stderr "hmm how did this happen?";
			fi
		fi
	else
		stderr "can't deal with \`"$1"'";
  fi
}

if [ $# = 0 ]; then usage; exit 0; fi	
for arg
do
	case "$arg" in
		--version|-v) show_version; exit 0;;
		--help|-[h?]) usage; exit 0;;
		--licen[cs]e|-l) license; exit 0;;
		--) shift; 
			for arg 
			do 
				rename "$arg"; 
			done; exit 0;;
		*) rename "$arg";;
	esac
done
exit 0;

# Local variables:
# tab-width: 2
# End:

