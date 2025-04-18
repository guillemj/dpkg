#!/bin/sh
#
# Copyright © 2014, 2017-2018, 2020-2021 Guillem Jover <guillem@debian.org>
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

ADMINDIR=/var/lib/dpkg
BACKUPSDIR=/var/backups
ROTATE=7

PKGDATADIR_DEFAULT=src
PKGDATADIR="${DPKG_DATADIR:-$PKGDATADIR_DEFAULT}"
TAR="${TAR:-tar}"

# shellcheck source=src/sh/dpkg-error.sh
. "$PKGDATADIR/sh/dpkg-error.sh"

while [ $# -ne 0 ]; do
  case "$1" in
  --rotate=*)
    ROTATE="${1#--rotate=}"
    ;;
  esac
  shift
done

# Check for required commands availability.
for cmd in "$TAR" savelog; do
  if ! command -v "$cmd" >/dev/null; then
    error "cannot find required program '$cmd'"
  fi
done

dbdir="$ADMINDIR"

# Backup the N last versions of dpkg databases containing user data.
if cd $BACKUPSDIR ; then
  # We backup all relevant database files if any has changed, so that
  # the rotation number always contains an internally consistent set.
  dbchanged=no
  dbfiles="arch status diversions statoverride"
  for db in $dbfiles ; do
    if ! [ -s "dpkg.${db}.0" ] && ! [ -s "$dbdir/$db" ]; then
      # Special case the files not existing or being empty as being equal.
      continue
    elif ! cmp -s "dpkg.${db}.0" "$dbdir/$db"; then
      dbchanged=yes
      break
    fi
  done
  if [ "$dbchanged" = "yes" ] ; then
    for db in $dbfiles ; do
      if [ -e "$dbdir/$db" ]; then
        cp -p "$dbdir/$db" "dpkg.$db"
      else
        touch "dpkg.$db"
      fi
      savelog -c "$ROTATE" "dpkg.$db" >/dev/null
    done
  fi

  # The alternatives database is independent from the dpkg database.
  dbalt=alternatives

  # XXX: Ideally we'd use --warning=none instead of discarding stderr, but
  # as of GNU tar 1.27.1, it does not seem to work reliably (see #749307).
  if ! test -e ${dbalt}.tar.0 ||
     ! $TAR -df ${dbalt}.tar.0 -C $dbdir $dbalt >/dev/null 2>&1 ;
  then
    $TAR -cf ${dbalt}.tar -C $dbdir $dbalt >/dev/null 2>&1
    savelog -c "$ROTATE" ${dbalt}.tar >/dev/null
  fi
fi
