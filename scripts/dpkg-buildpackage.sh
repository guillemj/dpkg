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
Options: -r<gain-root-command>
         -p<sign-command>
	 -k<keyid>     the key to use for signing
         -sgpg         the sign-command is called like GPG
         -spgp         the sign-command is called like PGP 
         -us           unsigned source
         -uc           unsigned changes
         -a<arch>      Debian architecture we build for
         -b            binary-only, do not build source } also passed to
         -B            binary-only, no arch-indep files } dpkg-genchanges
         -v<version>   changes since version <version>      }
         -m<maint>     maintainer for release is <maint>    } only passed
         -C<descfile>  changes are described in <descfile>  }  to dpkg-
         -si (default) src includes orig for rev. 0 or 1    } genchanges
         -sa           uploaded src always includes orig    }
         -sd           uploaded src is diff and .dsc only   }
         -nc           do not clean source tree (implies -b)
         -tc           clean source tree when finished
         -ap           add pause before starting signature process
         -h            print this message
         -i[<regex>]   ignore diffs of files matching regex } only passed
                                                             to dpkg-source
END
}

rootcommand=''
if [ -e $HOME/.gnupg/secring.gpg ] ; then
	signcommand=gpg
else
	signcommand=pgp
fi
signsource='withecho signfile'
signchanges='withecho signfile'
cleansource=false
binarytarget=binary
sourcestyle=''
version=''
since=''
maint=''
desc=''
noclean=false
usepause=false

while [ $# != 0 ]
do
	value="`echo x\"$1\" | sed -e 's/^x-.//'`"
	case "$1" in
	-h)	usageversion; exit 0 ;;
	-r*)	rootcommand="$value" ;;
	-p*)	signcommand="$value" ;;
	-k*)	signkey="$value" ;;
	-sgpg)  forcesigninterface=gpg ;;
	-spgp)  forcesigninterface=pgp ;;
	-us)	signsource=: ;;
	-uc)	signchanges=: ;;
	-ap)	usepause="true";;
	-a*)    opt_a=1; arch="$value" ;;
	-si)	sourcestyle=-si ;;
	-sa)	sourcestyle=-sa ;;
	-sd)	sourcestyle=-sd ;;
        -i*)    diffignore=$1;;
	-tc)	cleansource=true ;;
	-t*)    targetgnusystem="$value" ;;          # Order DOES matter!
	-nc)	noclean=true; binaryonly=-b ;;
	-b)	binaryonly=-b ;;
	-B)	binaryonly=-B; binarytarget=binary-arch ;;
	-v*)	since="$value" ;;
	-m*)	maint="$value" ;;
	-C*)	descfile="$value" ;;
	*)	echo >&2 "$progname: unknown option or argument $1"
		usageversion; exit 2 ;;
	esac
	shift
done

if test -n "$forcesigninterface" ; then
  signinterface=$forcesigninterface
else
  signinterface=$signcommand
fi

mustsetvar () {
	if [ "x$2" = x ]; then
		echo >&2 "$progname: unable to determine $3" ; \
		exit 1
	else
		echo "$progname: $3 is $2" ; \
		eval "$1=\"\$2\""
	fi
}

curd="`pwd`"
dirn="`basename \"$curd\"`"
mustsetvar package "`dpkg-parsechangelog | sed -n 's/^Source: //p'`" "source package"
mustsetvar version "`dpkg-parsechangelog | sed -n 's/^Version: //p'`" "source version"
if [ -n "$maint" ]; then maintainer="$maint"; 
else mustsetvar maintainer "`dpkg-parsechangelog | sed -n 's/^Maintainer: //p'`" "source maintainer"; fi
command -v dpkg-architecture > /dev/null 2>&1 && eval `dpkg-architecture -a${arch} -t${targetgnusystem} -s`
archlist=`dpkg-architecture -a${arch} -t${targetgnusystem} -f 2> /dev/null`
test "${opt_a}" \
	|| arch=`dpkg-architecture -a${arch} -t${targetgnusystem} -qDEB_HOST_ARCH 2> /dev/null` && test "${arch}" \
	|| mustsetvar arch "`dpkg --print-architecture`" "build architecture"

sversion=`echo "$version" | perl -pe 's/^\d+://'`
pv="${package}_${sversion}"
pva="${package}_${sversion}${arch:+_${arch}}"

signfile () {
	if test "$signinterface" = "gpg" ; then
		(cat "../$1" ; echo "") | \
		$signcommand --local-user "${signkey:-$maintainer}" --clearsign --armor \
			--textmode  > "../$1.asc" 
	else
		$signcommand -u "${signkey:-$maintainer}" +clearsig=on -fast <"../$1" \
			>"../$1.asc"
	fi
	echo
	mv -- "../$1.asc" "../$1"
}

withecho () {
        echo " $@" >&2
	"$@"
}

set -- $binaryonly $sourcestyle
if [ -n "$maint"	]; then set -- "$@" "-m$maint"		; fi
if [ -n "$since"	]; then set -- "$@" "-v$since"		; fi
if [ -n "$desc"		]; then set -- "$@" "-C$desc"		; fi

if [ x$noclean != xtrue ]; then
	withecho $rootcommand debian/rules clean $archlist
fi
if [ x$binaryonly = x ]; then
	cd ..; withecho dpkg-source $diffignore -b "$dirn"; cd "$dirn"
fi
withecho debian/rules build $archlist
withecho $rootcommand debian/rules $binarytarget $archlist

if [ "$usepause" = "true" ] && [ x$binaryonly = x -o x$signchanges != x ] ; then
    echo Press the return key to start signing process
    read dummy_stuff
fi

if [ x$binaryonly = x ]; then
        $signsource "$pv.dsc"
fi
chg=../"$pva.changes"
withecho dpkg-genchanges "$@" >"$chg"

fileomitted () {
	set +e
	test -z "`sed -n '/^Files:/,/^[^ ]/ s/'$1'$//p' <$chg`"
	fir=$?
	set -e
	return $fir
}	

if fileomitted '\.dsc'; then
	srcmsg='no source included in upload'
elif fileomitted '\.diff\.gz'; then
	srcmsg='Debian-specific package; upload is full source'
elif fileomitted '\.orig\.tar\.gz'; then
	srcmsg='diff-only upload (original source NOT included)'
else
	srcmsg='full upload (original source is included)'
fi

$signchanges "$pva.changes"

if $cleansource; then
	withecho $rootcommand debian/rules clean $archlist
fi

echo "dpkg-buildpackage: $srcmsg"
