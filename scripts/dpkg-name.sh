#!/bin/sh

set -e

# Time-stamp: <96/05/03 13:59:41 root>
prog="`basename \"${0}\"`"
version="1.2.3"; # This line modified by Makefile
purpose="rename Debian packages to full package names"

license () {
echo "# ${prog} ${version} -- ${purpose}
# Copyright (C) 1995,1996 Erick Branderhorst <branderh@debian.org>.

# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any
# later version.

# This is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
# /usr/share/common-licenses/GPL for more details."
}

stderr () {
	echo "${prog}: $@" 1>&2;
}

show_version () {
	echo "${prog} version ${version} -- ${purpose}";
}

usage () {
	echo "Usage: ${prog} file[s]
  ${purpose}
  file.deb changes to <package>_<version>_<architecture>.deb 
  according to the ``underscores convention''.
  -a|--no-architecture  No architecture part in filename
  -o|--overwrite        Overwrite if file exists
  -k|--symlink          Don't create a new file, but a symlink
  -s|--subdir [dir]     Move file into subdir (Use with care)
  -c|--create-dir       Create target dir if not there (Use with care)
  -h|--help|-v|--version|-l|--license  Show help/version/license"
}

fileexists () {
	if [ -f "$1" ];
	then
		return 0;
	else
		stderr "can't find \`"$1"'";
		return 1;
	fi
}

getname () {
	if p=`dpkg-deb -f -- "$1" package`;
	then
		v=`dpkg-deb -f -- "$1" version | sed s,.*:,,`;
		r=`dpkg-deb -f -- "$1" revision`;
		if [ -z "$r" ];
		then
			r=`dpkg-deb -f -- "$1" package_revision`;
		fi

		if [ -n "$r" ];
		then
			v=$v-$r;
		fi

		a=`dpkg-deb -f -- "$1" architecture`;
		a=`echo $a|sed -e 's/ *//g'`;
		if [ -z "$a" ] && [ -n "$noarchitecture" ]; # arch field empty, or ignored
		then
			a=`dpkg --print-architecture`;
			stderr "assuming architecture \`"$a"' for \`"$1"'";
		fi
		if [ -z "$noarchitecture" ];
		then
			tname=$p\_$v\_$a.deb;
		else
			tname=$p\_$v.deb
		fi
	
		name=`echo $tname|sed -e 's/ //g'`
		if [ "$tname" != "$name" ]; # control fields have spaces 
		then
			stderr "bad package control information for \`"$1"'"
		fi
		return 0;
	fi
}

getdir () {
	if [ -z "$destinationdir" ];
	then
		dir=`dirname "$1"`;
		if [ -n "$subdir" ];
		then
			s=`dpkg-deb -f -- "$1" section`;
			if [ -z "$s" ];
			then
				s="no-section";
				stderr "assuming section \`"no-section"' for \`"$1"'";
			fi
			if [ "$s" != "non-free" ] && [ "$s" != "contrib" ] && [ "$s" != "no-section" ];
			then
				dir=`echo unstable/binary-$a/$s`;
			else
				dir=`echo $s/binary-$a`;
			fi
		fi
	else
		dir=$destinationdir;
	fi
}

move () {
	if fileexists "$arg"; 
	then
		getname "$arg";
		getdir "$arg";
		if [ ! -d "$dir" ];
		then
			if [ -n "$createdir" ];
			then
  			if `mkdir -p $dir`;
	  		then
		  		stderr "created directory \`$dir'";
			  else
		  		stderr "failed creating directory \`$dir'";
					exit 1;
				fi
			else
				stderr "no such dir \`$dir'";
				stderr "try --create-dir (-c) option";
				exit 1;
			fi
		fi
		newname=`echo $dir/$name`;
		if [ x$symlink = x1 ];
		then
			command="ln -s --"
		else
			command="mv --"
		fi
		if [ $newname -ef "$1" ]; # same device and inode numbers
		then
			stderr "skipping \`"$1"'";
		elif [ -f $newname ] && [ -z "$overwrite" ];
		then
			stderr "can't move \`"$1"' to existing file";
		elif `$command "$1" $newname`;
		then
			echo "moved \``basename "$1"`' to \`$newname'";
		else
			stderr "mkdir can be used to create directory";
			exit 1;
		fi
  fi
}

if [ $# = 0 ]; then usage; exit 0; fi	
for arg
do
	if [ -n "$subdirset" ];
	then
		subdirset=0;
		subdir=1;
		if [ -d $arg ];
		then
			destinationdir=$arg;
			continue
		fi
	fi
	case "$arg" in
		--version|-v) show_version; exit 0;;
		--help|-[h?]) usage; exit 0;;
		--licen[cs]e|-l) license; exit 0;;
		--create-dir|-c) createdir=1;;
		--subdir|-s) subdirset=1;;
		--overwrite|-o) overwrite=1 ;;
		--symlink|-k) symlink=1 ;;
		--no-architecture|-a) noarchitecture=1 ;;
		--) shift; 
			for arg 
			do 
				move "$arg";
			done; exit 0;;
		*) move "$arg";;
	esac
done
exit 0;

# Local variables:
# tab-width: 2
# End:
