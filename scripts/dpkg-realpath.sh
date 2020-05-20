#!/bin/sh
#
# Copyright © 2020 Guillem Jover <guillem@debian.org>
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
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -e

PROGNAME=$(basename "$0")
version="unknown"

PKGDATADIR=scripts/sh

. "$PKGDATADIR/dpkg-error.sh"

show_version()
{
  cat <<END
Debian $PROGNAME version $version.

This is free software; see the GNU General Public License version 2 or
later for copying conditions. There is NO warranty.
END
}

show_usage()
{
  cat <<END
Usage: $PROGNAME [<option>...] <pathname>

Options:
       --version      Show the version.
  -?,  --help         Show this help message.
END
}

setup_colors

[ $# -eq 1 ] || badusage "missing pathname"

while [ $# -ne 0 ]; do
  case "$1" in
  --version)
    show_version
    exit 0
    ;;
  --help|-\?)
    show_usage
    exit 0
    ;;
  --)
    shift
    pathname="$1"
    ;;
  --*)
    badusage "unknown option: $1"
    ;;
  *)
    pathname="$1"
    ;;
  esac
  shift
done

realpath "$pathname"

exit 0
