#
# Copyright © 2010 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2011-2015 Guillem Jover <guillem@debian.org>
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
#
# shellcheck shell=sh

# Set a default program name.
: "${PROGNAME:=$(basename "$0")}"

# Standard ANSI colors and attributes.
COLOR_NORMAL=''
COLOR_RESET='[0m'
COLOR_BOLD='[1m'
COLOR_BLACK='[30m'
COLOR_RED='[31m'
COLOR_GREEN='[32m'
COLOR_YELLOW='[33m'
COLOR_BLUE='[34m'
COLOR_MAGENTA='[35m'
COLOR_CYAN='[36m'
COLOR_WHITE='[37m'
COLOR_BOLD_BLACK='[1;30m'
COLOR_BOLD_RED='[1;31m'
COLOR_BOLD_GREEN='[1;32m'
COLOR_BOLD_YELLOW='[1;33m'
COLOR_BOLD_BLUE='[1;34m'
COLOR_BOLD_MAGENTA='[1;35m'
COLOR_BOLD_CYAN='[1;36m'
COLOR_BOLD_WHITE='[1;37m'

: "${DPKG_COLORS=auto}"

case "$DPKG_COLORS" in
auto)
  if [ -t 1 ]; then
    _dpkg_use_colors=yes
  else
    _dpkg_use_colors=no
  fi
  ;;
always)
  _dpkg_use_colors=yes
  ;;
*)
  _dpkg_use_colors=no
  ;;
esac

if [ $_dpkg_use_colors = yes ]; then
  _dpkg_color_clear="$COLOR_RESET"
  _dpkg_color_prog="$COLOR_BOLD"
  _dpkg_color_info="$COLOR_GREEN"
  _dpkg_color_notice="$COLOR_YELLOW"
  _dpkg_color_warn="$COLOR_BOLD_YELLOW"
  _dpkg_color_error="$COLOR_BOLD_RED"
else
  _dpkg_color_clear=""
fi
_dpkg_fmt_prog="$_dpkg_color_prog$PROGNAME$_dpkg_color_clear"

# This function is deprecated and kept only for backwards compatibility.
# Deprecated since dpkg 1.22.12.
setup_colors()
{
  :
}

debug() {
  if [ -n "$DPKG_DEBUG" ]; then
    echo "DEBUG: $_dpkg_fmt_prog: $*" >&2
  fi
}

error() {
  echo "$_dpkg_fmt_prog: ${_dpkg_color_error}error${_dpkg_color_clear}: $*" >&2
  exit 1
}

warning() {
  echo "$_dpkg_fmt_prog: ${_dpkg_color_warn}warning${_dpkg_color_clear}: $*" >&2
}

badusage() {
  echo "$_dpkg_fmt_prog: ${_dpkg_color_error}error${_dpkg_color_clear}: $1" >&2
  echo >&2
  echo "Use '$PROGNAME --help' for program usage information." >&2
  exit 1
}
