#!/bin/sh
#
# Copyright © 2010 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2008 Joey Hess <joeyh@debian.org>
# Copyright © 2007 Guillem Jover (modifications on wiki.debian.org)
# Copyright © 2005 Scott James Remnant (original implementation on www.dpkg.org)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# The conffile related functions are inspired by
# http://wiki.debian.org/DpkgConffileHandling

# This script is documented in dpkg-maintscript-helper(1)

##
## Functions to remove an obsolete conffile during upgrade
##
rm_conffile() {
	local CONFFILE="$1"
	local LASTVERSION="$2"
	local PACKAGE="$3"
	if [ "$PACKAGE" = "--" -o -z "$PACKAGE" ]; then
		PACKAGE="$DPKG_MAINTSCRIPT_PACKAGE"
	fi
	# Skip remaining parameters up to --
	while [ "$1" != "--" -a $# -gt 0 ]; do shift; done
	[ $# -gt 0 ] || badusage
	shift

	[ -n "$PACKAGE" ] || error "couldn't identify the package"
	[ -n "$1" ] || error "maintainer script parameters are missing"
	[ -n "$DPKG_MAINTSCRIPT_NAME" ] || \
		error "environment variable DPKG_MAINTSCRIPT_NAME is required"

	debug "Executing $0 rm_conffile in $DPKG_MAINTSCRIPT_NAME "\
	      "of $DPKG_MAINTSCRIPT_PACKAGE"
	debug "CONFFILE=$CONFFILE PACKAGE=$PACKAGE "\
	      "LASTVERSION=$LASTVERSION ACTION=$1 PARAM=$2"
	case "$DPKG_MAINTSCRIPT_NAME" in
	preinst)
		if [ "$1" = "install" -o "$1" = "upgrade" ] &&
		   dpkg --compare-versions "$2" le-nl "$LASTVERSION"; then
			prepare_rm_conffile "$CONFFILE" "$PACKAGE"
		fi
		;;
	postinst)
		if [ "$1" = "configure" ] &&
		   dpkg --compare-versions "$2" le-nl "$LASTVERSION"; then
			finish_rm_conffile $CONFFILE
		fi
		;;
	postrm)
		if [ "$1" = "purge" ]; then
			rm -f "$CONFFILE.dpkg-bak" "$CONFFILE.dpkg-remove"
		fi
		if [ "$1" = "abort-install" -o "$1" = "abort-upgrade" ] &&
		   dpkg --compare-versions "$2" le-nl "$LASTVERSION"; then
			abort_rm_conffile "$CONFFILE"
		fi
		;;
	*)
		debug "$0 rm_conffile not required in $DPKG_MAINTSCRIPT_NAME"
		;;
	esac
}

prepare_rm_conffile() {
	local CONFFILE="$1"
	local PACKAGE="$2"

	[ -e "$CONFFILE" ] || return 0

	local md5sum="$(md5sum $CONFFILE | sed -e 's/ .*//')"
	local old_md5sum="$(dpkg-query -W -f='${Conffiles}' $PACKAGE | \
		sed -n -e "\' $CONFFILE ' { s/ obsolete$//; s/.* //; p }")"
	if [ "$md5sum" != "$old_md5sum" ]; then
		echo "Obsolete conffile $CONFFILE has been modified by you."
		echo "Saving as $CONFFILE.dpkg-bak ..."
		mv -f "$CONFFILE" "$CONFFILE.dpkg-bak"
	else
		echo "Moving obsolete conffile $CONFFILE out of the way..."
		mv -f "$CONFFILE" "$CONFFILE.dpkg-remove"
	fi
}

finish_rm_conffile() {
	local CONFFILE="$1"

	if [ -e "$CONFFILE.dpkg-remove" ]; then
		echo "Removing obsolete conffile $CONFFILE ..."
		rm -f "$CONFFILE.dpkg-remove"
	fi
}

abort_rm_conffile() {
	local CONFFILE="$1"

	if [ -e "$CONFFILE.dpkg-remove" ]; then
		echo "Reinstalling $CONFFILE that was moved away"
		mv "$CONFFILE.dpkg-remove" "$CONFFILE"
	fi
	if [ -e "$CONFFILE.dpkg-bak" ]; then
		echo "Reinstalling $CONFFILE that was backupped"
		mv "$CONFFILE.dpkg-bak" "$CONFFILE"
	fi
}

##
## Functions to rename a conffile during upgrade
##
mv_conffile() {
	local OLDCONFFILE="$1"
	local NEWCONFFILE="$2"
	local LASTVERSION="$3"
	local PACKAGE="$4"
	if [ "$PACKAGE" = "--" -o -z "$PACKAGE" ]; then
		PACKAGE="$DPKG_MAINTSCRIPT_PACKAGE"
	fi
	# Skip remaining parameters up to --
	while [ "$1" != "--" -a $# -gt 0 ]; do shift; done
	[ $# -gt 0 ] || badusage
	shift

	[ -n "$PACKAGE" ] || error "couldn't identify the package"
	[ -n "$1" ] || error "maintainer script parameters are missing"
	[ -n "$DPKG_MAINTSCRIPT_NAME" ] || \
		error "environment variable DPKG_MAINTSCRIPT_NAME is required"

	debug "Executing $0 mv_conffile in $DPKG_MAINTSCRIPT_NAME "\
	      "of $DPKG_MAINTSCRIPT_PACKAGE"
	debug "CONFFILE=$OLDCONFFILE -> $NEWCONFFILE PACKAGE=$PACKAGE "\
	      "LASTVERSION=$LASTVERSION ACTION=$1 PARAM=$2"
	case "$DPKG_MAINTSCRIPT_NAME" in
	preinst)
		if [ "$1" = "install" -o "$1" = "upgrade" ] &&
		   dpkg --compare-versions "$2" le-nl "$LASTVERSION"; then
			prepare_mv_conffile "$OLDCONFFILE" "$PACKAGE"
		fi
		;;
	postinst)
		if [ "$1" = "configure" ] &&
		   dpkg --compare-versions "$2" le-nl "$LASTVERSION"; then
			finish_mv_conffile "$OLDCONFFILE" "$NEWCONFFILE"
		fi
		;;
	postrm)
		if [ "$1" = "abort-install" -o "$1" = "abort-upgrade" ] &&
		   dpkg --compare-versions "$2" le-nl "$LASTVERSION"; then
			abort_rm_conffile "$OLDCONFFILE"
		fi
		;;
	*)
		debug "$0 mv_conffile not required in $DPKG_MAINTSCRIPT_NAME"
		;;
	esac
}

prepare_mv_conffile() {
	local CONFFILE="$1"
	local PACKAGE="$2"

	[ -e "$CONFFILE" ] || return 0

	local md5sum="$(md5sum $CONFFILE | sed -e 's/ .*//')"
	local old_md5sum="$(dpkg-query -W -f='${Conffiles}' $PACKAGE | \
		sed -n -e "\' $CONFFILE ' { s/ obsolete$//; s/.* //; p }")"
	if [ "$md5sum" = "$old_md5sum" ]; then
		mv -f "$CONFFILE" "$CONFFILE.dpkg-remove"
	fi
}

finish_mv_conffile() {
	local OLDCONFFILE="$1"
	local NEWCONFFILE="$2"

	rm -f $OLDCONFFILE.dpkg-remove

	[ -e "$OLDCONFFILE" ] || return 0

	echo "Preserving user changes to $NEWCONFFILE (renamed from $OLDCONFFILE)..."
	mv -f "$NEWCONFFILE" "$NEWCONFFILE.dpkg-new"
	mv -f "$OLDCONFFILE" "$NEWCONFFILE"
}

abort_mv_conffile() {
	local CONFFILE="$1"

	if [ -e "$CONFFILE.dpkg-remove" ]; then
		echo "Reinstalling $CONFFILE that was moved away"
		mv "$CONFFILE.dpkg-remove" "$CONFFILE"
	fi
}

# Common functions
debug() {
	if [ -n "$DPKG_DEBUG" ]; then
		echo "DEBUG: $PROGNAME: $1" >&2
	fi
}

error() {
	echo "$PROGNAME: error: $1" >&2
	exit 1
}

warning() {
	echo "$PROGNAME: warning: $1" >&2
}

usage() {
	cat <<END
Syntax: $0 <command> [<parameters>] -- <maintainer script parameters>

Commands and parameters:

  supports <command>
	Returns 0 (success) if the given command is supported, 1
	otherwise.

  rm_conffile <conffile> <last-version> [<package>]
	Remove obsolete conffile.
	Must be called in preinst, postinst and postrm.

  mv_conffile <old-conf> <new-conf> <last-version> [<package>]
	Rename a conffile.
	Must be called in preinst, postinst and postrm.

  help
	Display this usage information.
END
}

badusage() {
	usage
	exit 1
}

# Main code
set -e

PROGNAME=$(basename $0)
version="unknown"
command="$1"
[ $# -gt 0 ] || badusage
shift

case "$command" in
supports)
	case "$1" in
	rm_conffile|mv_conffile)
		code=0
		;;
	*)
		code=1
		;;
	esac
	if [ -z "$DPKG_MAINTSCRIPT_NAME" ]; then
		warning "environment variable DPKG_MAINTSCRIPT_NAME missing"
		code=1
	fi
	if [ -z "$DPKG_MAINTSCRIPT_PACKAGE" ]; then
		warning "environment variable DPKG_MAINTSCRIPT_PACKAGE missing"
		code=1
	fi
	exit $code
	;;
rm_conffile)
	rm_conffile "$@"
	;;
mv_conffile)
	mv_conffile "$@"
	;;
--help|help|-?|-h)
	usage
	;;
--version)
	cat <<-END
	Debian $PROGNAME version $version.

	Copyright (C) 2010 Raphaël Hertzog <hertzog@debian.org>
	Copyright (C) 2008 Joey Hess <joeyh@debian.org>
	Copyright (C) 2007 Guillem Jover <guillem@debian.org>
	Copyright (C) 2005 Scott James Remnant

	This is free software; see the GNU General Public License version 2 or
	later for copying conditions. There is NO warranty.
	END
	;;
*)
	cat >&2 <<-END
	$PROGNAME: error: command $command is unknown
	Hint: upgrading dpkg to a newer version might help.

	END
	usage
	exit 1
esac

exit 0
