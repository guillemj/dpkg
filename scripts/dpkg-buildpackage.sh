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
         -sgpg         the sign-command is called like GPG
         -spgp         the sign-command is called like PGP 
         -us           unsigned source
         -uc           unsigned changes
         -a<arch>      architecture field of the changes _file_name_
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
         -h            print this message
END
}

rootcommand=''
signcommand=pgp # Default command for signing
warnpgp='no'	# Display a warning to encourage switching to gpg?
if [ ! -e $HOME/.gnupg/secring.gpg ] ; then
	warnpgp=yes
fi
if [ -e $HOME/.gnupg/secring.gpg -a ! -e $HOME/.pgp/secring.pgp ] ; then
	signcommand=gpg
fi
if [ -e $HOME/.pgp/secring.pgp -a ! -e $HOME/.gnupg/secring.gpg ] ; then
	signcommand=pgp
fi
signinterface=$signcommand
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

while [ $# != 0 ]
do
	value="`echo x\"$1\" | sed -e 's/^x-.//'`"
	case "$1" in
	-h)	usageversion; exit 0 ;;
	-r*)	rootcommand="$value" ;;
	-p*)	signcommand="$value"; warnpgp='' ;;
	-sgpg)  signinterface=gpg ;;
	-spgp)  signinterface=pgp ;;
	-us)	signsource=: ; warnpgp='' ;;
	-uc)	signchanges=: ; warnpgp='' ;;
	-a*)    opt_a=1; arch="$value" ;;
	-si)	sourcestyle=-si ;;
	-sa)	sourcestyle=-sa ;;
	-sd)	sourcestyle=-sd ;;
	-tc)	cleansource=true ;;
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

if test "X$warnpgp" = "Xyes" ; then
  echo >&2 <<EOWARN
The Debian project will switch to using GPG (the GNU Privacy Guard) instead
of PGP for signing packages. You might want to make preparations. Check out
the gnupg and debian-keyring packages.
EOWARN
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
test "${opt_a}" \
	|| mustsetvar arch "`dpkg --print-architecture`" "build architecture"

sversion=`echo "$version" | perl -pe 's/^\d+://'`
pv="${package}_${sversion}"
pva="${package}_${sversion}${arch:+_${arch}}"

signfile () {
	if test $signinterface = gpg ; then
		# --textmode doesn't seem to work; we use perl to filter ^M;
		# this doesn't affect the actual signature.
		(cat "../$1" ; echo "") | \
		$signcommand --local-user "$maintainer" --clearsign --armor \
			--textmode --output - - | \
			perl -n -p -e 's/\r$//' > "../$1.asc" 
	else
		$signcommand -u "$maintainer" +clearsig=on -fast <"../$1" \
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
	withecho $rootcommand debian/rules clean
fi
if [ x$binaryonly = x ]; then
	cd ..; withecho dpkg-source -b "$dirn"; cd "$dirn"
fi
withecho debian/rules build
withecho $rootcommand debian/rules $binarytarget
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
	withecho $rootcommand debian/rules clean
fi

echo "dpkg-buildpackage: $srcmsg"
