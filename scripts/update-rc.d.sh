#!/bin/sh
#
# Usage:
#  update-rc.d <basename> remove
#  update-rc.d <basename> [options]
# Options are:
#  start <codenumber> <runlevel> <runlevel> <runlevel> .
#  stop  <codenumber> <runlevel> <runlevel> <runlevel> .
#  defaults [<codenumber> | <startcode> <stopcode>]
#   (means       start <startcode> 2 3 4 5
#    as well as  stop <stopcode> 0 1 2 3 4 5 6
#    <codenumber> defaults to 20)

set -e
cd /etc

initd='init.d'

usage () { echo >&2 "\
update-rc.d: error: $1.
usage: update-rc.d <basename> remove
       update-rc.d <basename> defaults [<cn> | <scn> <kcn>]
       update-rc.d <basename> start|stop <cn> <r> <r> .  ..."; exit 1 }

getinode () {
	inode="`ls -Li1 \"$1\" | sed -e 's/^ *//; s/ .*//'`"
}

if [ $# -lt 2 ]; then usage "too few arguments"; fi
bn="$1"; shift

if [ xremove = "x$1" ]; then
	if [ $# != 1 ]; then usage "remove must be only action"; fi
	if [ -f "$initd/$bn" ]; then
		echo >&2 "update-rc.d: error: /etc/$initd/$bn exists during rc.d purge."
		exit 1
	fi
	echo " Removing any system startup links to /etc/$initd/$bn ..."
	trap 'rm -f "$initd/$bn"' 0
	touch "$initd/$bn"
	getinode "$initd/$bn"
	own="$inode"
	for f in rc?.d/[SK]*; do
		getinode "$f"
		if [ "x$inode" = "x$own" ]; then
			rm "$f";
			echo "   $f"
		fi
	done
	exit 0
elif [ xdefaults = "x$1" ]; then
	if [ $# = 1 ]; then sn=20; kn=20;
	elif [ $# = 2 ]; then sn="$2"; kn="$2";
	elif [ $# = 3 ]; then sn="$2"; kn="$3";
	else usage "defaults takes only one or two codenumbers"; fi
	set start "$sn" 2 3 4 5 . stop "$kn" 0 1 6 .
elif ! [ xstart = "x$1" -o xstop = "x$1" ]; then
	usage "unknown mode or add action $1"
fi

if ! [ -f "$initd/$bn" ]; then
	echo >&2 "update-rc.d: warning /etc/$initd/$bn doesn't exist during rc.d setup."
	exit 0
fi

getinode "$initd/$bn"
own="$inode"
for f in rc?.d/[SK]*; do
	getinode "$f"
	if [ "x$inode" = "x$own" ]; then
		echo " System startup links pointing to /etc/$initd/$bn already exist."
		exit 0
	fi
done

echo " Adding system startup links pointing to /etc/$initd/$bn ..."
while [ $# -ge 3 ]; do
	if [ xstart = "x$1" ]; then ks=S
	elif [ xstop = "x$1" ]; then ks=K
	else usage "unknown action $1"; fi
	number="$2"
	shift; shift
	while [ $# -ge 1 ]; do
		case "$1" in
		.)
			break
			;;
		?)
			ln -s "../$initd/$bn" "rc$1.d/$ks$number$bn"
			echo "   rc$1.d/$ks$number$bn -> ../$initd/$bn"
			shift
			continue
			;;
		*)
			usage "runlevel is more than one character (forgotten \`.' ?)"
		esac
	done
	if [ $# -eq 0 ]; then
		usage "action with list of runlevels not terminated by \`.'"
	fi
	shift
done

if [ $# != 0 ]; then
	usage "surplus arguments, but not enough for an add action: $*"
fi

exit 0
