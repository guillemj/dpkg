#!/bin/sh

set -e

# Time-stamp: <96/05/03 13:59:41 root>
prog="`basename \"${0}\"`"
version="1.1.6"; # This line modified by Makefile
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
  file.deb changes to <package>-<version>.<architecture>.deb
  <package> is y/-/_/ aware
  -a|--no-architecture  No architecture part in filename
  -o|--overwrite        Overwrite if file exists
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
		p=`echo $p|sed -e 'y/-/_/'`;
		v=`dpkg-deb -f -- "$1" version`;
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
		if [ -z "$a" ]; # architecture field empty
		then
			a=`dpkg --print-architecture`;
			stderr "assuming architecture \`"$a"' for \`"$1"'";
		fi
		if [ -z "$noarchitecture" ];
		then
			tname=$p-$v.$a.deb;
		else
			tname=$p-$v.deb
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
			if [ "$s" != "non-free" -a "$s" != "contrib" -a "$s" != "no-section" ];
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
		if [ $newname -ef "$1" ]; # same device and inode numbers
		then
			stderr "skipping \`"$1"'";
		elif [ -f $newname -a -z "$overwrite" ];
		then
			stderr "can't move \`"$1"' to existing file";
		elif `mv -- "$1" $newname`;
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

dpkg-name.1:
.\" This is an -*- nroff -*- source file.
.\" dpkg-name and this manpage are Copyright 1995,1996 by Erick Branderhorst.
.\"
.\" This is free software; see the GNU General Public Licence version 2
.\" or later for copying conditions.  There is NO warranty.
.\" Time-stamp: <96/05/03 14:00:06 root>
.TH dpkg-name 1 "April 1996" "Debian Project" "Debian Linux"
.SH NAME
dpkg\-name \- rename Debian packages to full package names
.SH SYNOPSIS
.B dpkg\-name 
[\-a|\-\-no\-architecture] [\-o|\-\-overwrite] [\-s|\-\-subdir [dir]]
[\-c|\-\-create\-dir] [\-h|\-\-help] [\-v|\-\-version]
[\-l|\-\-license] [\-[--] [files]
.SH DESCRIPTION
.PP
This manual page documents the
.B dpkg\-name 
sh script which provides an easy way to rename
.B Debian
packages into their full package names. A full package name consists
of <package>-<version>.<architecture>.deb as specified in the control
file of the package. The <package> part of the filename will have
hyphens "-" replaced by underscores "_". The <version> part of the
filename consists of the mainstream version information optionally
followed by a hyphen and the revision information.
.SH EXAMPLES
.TP
.B dpkg-name bar-foo.deb
The file `bar-foo.deb' will be renamed to bar_foo-1.0-2.i386.deb or
something similar (depending on whatever information is in the control
part of `bar-foo.deb').
.TP
.B find /root/debian/ \-name '*.deb' | xargs \-n 1 dpkg\-name -a
All files with the extension `deb' in the directory /root/debian and its
subdirectory's will be renamed by dpkg\-name if required into names with no
architecture information.
.TP
.B find -name '*.deb' | xargs \-n 1 dpkg-name -a -o -s -c
.B Don't do this.
Your archive will be messed up completely because a lot of packages
don't come with section information.
.B Don't do this.
.TP
.B dpkg --build debian-tmp && dpkg-name -s .. debian-tmp.deb
This can be used when building new packages.
.SS OPTIONS
.TP
.B "\-a, \-\-no\-architecture"
The destination filename will not have the architecture information. 
.TP 
.B "\-o, \-\-overwrite"
Existing files will be overwritten if they have the same name as the
destination filename.
.TP 
.B "\-s, \-\-subdir [dir]"
Files will be moved into subdir. If directory given as argument exists
the files will be moved into that direcotory otherswise the name of
the target directory is extracted from the section field in the
control part of the package. The target directory will be
`unstable/binary-<architecture>/<section>'. If the section is
`non-free', `contrib' or no section information is found in the
control file the target directory is
`<section>/binary-<architecture>'. The section field isn't required so
a lot of packages will find their way to the `no-section' area. Use
this option with care, it's messy.
.TP
.B "\-c, \-\-create\-dir"
This option can used together with the \-s option. If a target
directory isn't found it will be created automatically. 
.B Use this option with care.
.TP
.B "\-h, \-\-help"
Print a usage message and exit successfully.
.TP
.B "\-v, \-\-version"
Print version information and exit successfully.
.TP
.B "\-l, \-\-license"
Print copyright information and (a reference to GNU) license
information and exit successfully.
.SH BUGS?
Successfully tested on
.B Debian Linux 
systems only. Some packages don't follow the name structure
<package>-<version>.<architecture>.deb. Packages renamed by dpkg-name
will follow this structure. Generally this will have no impact on how
packages are installed by dselect/dpkg.
.SH SEE ALSO
.BR deb (5),
.BR deb-control (5),
.BR dpkg (5),
.BR dpkg (8),
.BR dpkg-deb (8).
.SH COPYRIGHT
Copyright 1995,1996 Erick Branderhorst.
.B dpkg-name
is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is
.B no
warranty.
