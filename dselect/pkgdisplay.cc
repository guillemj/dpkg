/*
 * dselect - Debian GNU/Linux package maintenance user interface
 * pkgdisplay.cc - package list display
 *
 * Copyright (C) 1994,1995 Ian Jackson <iwj10@cus.cam.ac.uk>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2,
 * or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <stdio.h>
#include <string.h>
#include <ncurses.h>
#include <assert.h>
#include <signal.h>

extern "C" {
#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
}
#include "dselect.h"
#include "pkglist.h"

/* These MUST be in the same order as the corresponding enums in dpkg-db.h */
const char
  *const wantstrings[]=   { "new package", "install", "hold", "remove", "purge", 0 },
  *const eflagstrings[]=   { "", "REINSTALL", 0 },
  *const statusstrings[]= { "not installed", "unpacked (not set up)",
                            "failed config", "installed", "half installed",
                            "removed (configs remain)", 0                            },
  *const prioritystrings[]=  { "Required", "Important", "Standard", "Recommended",
                               "Optional", "Extra", "Contrib",
                               "!Bug!", "Unclassified", 0                          },
  *const relatestrings[]= { "suggests", "recommends", "depends on", "pre-depends on",
                            "conflicts with", "provides", 0              },
  *const priorityabbrevs[]=  { "Req", "Imp", "Std", "Rec",
                               "Opt", "Xtr", "Ctb",
                               "bUG", "?"                  };
const char statuschars[]=   " UF*H-";
const char eflagchars[]=     " R?#";
const char wantchars[]=     "n*=-_";

/* These MUST be in the same order as the corresponding enums in pkglist.h */
const char
  *const ssaabbrevs[]= { "Broken",
                         "New",
                         "Updated",
                         "Obsolete/local",
                         "Up-to-date",
                         "Available" },
  *const ssastrings[]= { "Brokenly installed packages",
                         "Newly available packages",
                         "Updated packages (newer version is available)",
                         "Obsolete and local packages present on system",
                         "Up to date installed packages",
                         "Available packages (not currently installed)" };

const char
  *const sssstrings[]= { "Brokenly installed packages",
                         "Installed packages",
                         "Removed packages (configuration still present)",
                         "Purged packages and those never installed" },
  *const sssabbrevs[]= { "Broken",
                         "Installed",
                         "Removed",
                         "Purged" };

static int maximumstring(const char *const *array) {
  int maxlen= 0;
  while (*array) {
    int l= strlen(*array);
    const char *p= strchr(*array, '(');
    if (p && p > *array && *--p == ' ') l= p - *array;
    if (l > maxlen) maxlen= l;
    array++;
  }
  return maxlen;
}

void packagelist::setwidths() {
  if (debug) fprintf(debug,"packagelist[%p]::setwidths()\n",this);

  if (verbose) {
    status_hold_width= 9;
    status_status_width= maximumstring(statusstrings);
    status_want_width= maximumstring(wantstrings);
    status_width= status_hold_width+status_status_width+status_want_width*2+3;
    priority_width= 8;
    package_width= 16;
  } else {
    status_width= 4;
    priority_width= 3;
    package_width= 12;
  }
  section_width= 8;

  gap_width= 1;

  if (sortorder == so_section) {
    section_column= status_width + gap_width;
    priority_column= section_column + section_width + gap_width;
    package_column= priority_column + priority_width + gap_width;
  } else {
    priority_column= status_width + gap_width;
    section_column= priority_column + priority_width + gap_width;
    package_column= section_column + section_width + gap_width;
  }

  int versiondescriptioncolumn= package_column + package_width + gap_width;
  
  switch (versiondisplayopt) {
  case vdo_none:
    versioninstalled_column= versioninstalled_width= 0;
    versionavailable_column= versionavailable_width= 0;
    description_column= versiondescriptioncolumn;
    break;
  case vdo_available:
    versioninstalled_column= versioninstalled_width= 0;
    versionavailable_column= versiondescriptioncolumn;
    versionavailable_width= 11;
    description_column= versionavailable_column + versionavailable_width + gap_width;
    break;
  case vdo_both:
    versioninstalled_column= versiondescriptioncolumn;
    versioninstalled_width= 11;
    versionavailable_column= versioninstalled_column + versioninstalled_width +gap_width;
    versionavailable_width= versioninstalled_width;
    description_column= versionavailable_column + versionavailable_width + gap_width;
    break;
  default:
    internerr("unknown versiondisplayopt in setwidths");
  }
    
  total_width= TOTAL_LIST_WIDTH;
  description_width= total_width - description_column;
}

void packagelist::redrawtitle() {
  int x,y;
  
  if (title_height) {
    mywerase(titlewin);
    mvwaddnstr(titlewin,0,0,
               recursive ?  "dselect - recursive package listing" :
               !readwrite ? "dselect - inspection of package states" :
                            "dselect - main package listing",
               xmax);
    getyx(titlewin,y,x);
    if (x < xmax) {
      switch (sortorder) {
      case so_section:
        switch (statsortorder) {
        case sso_unsorted:
          waddnstr(titlewin, " (by section)", xmax-x);
          break;
        case sso_avail:
          waddnstr(titlewin, " (avail., section)", xmax-x);
          break;
        case sso_state:
          waddnstr(titlewin, " (status, section)", xmax-x);
          break;
        default:
          internerr("bad statsort in redrawtitle/so_section");
        }
        break;
      case so_priority:
        switch (statsortorder) {
        case sso_unsorted:
          waddnstr(titlewin, " (by priority)", xmax-x);
          break;
        case sso_avail:
          waddnstr(titlewin, " (avail., priority)", xmax-x);
          break;
        case sso_state:
          waddnstr(titlewin, " (status, priority)", xmax-x);
          break;
        default:
          internerr("bad statsort in redrawtitle/so_priority");
        }
        break;
      case so_alpha:
        switch (statsortorder) {
        case sso_unsorted:
          waddnstr(titlewin, " (alphabetically)", xmax-x);
          break;
        case sso_avail:
          waddnstr(titlewin, " (by availability)", xmax-x);
          break;
        case sso_state:
          waddnstr(titlewin, " (by status)", xmax-x);
          break;
        default:
          internerr("bad statsort in redrawtitle/so_priority");
        }
        break;
        waddnstr(titlewin, " (alphabetically)", xmax-x);
        break;
      case so_unsorted:
        break;
      default:
        internerr("bad sort in redrawtitle");
      }
    }
    const char *helpstring= readwrite ? (verbose ? " mark:+/=/- terse:v help:?"
                                                 : " mark:+/=/- verbose:v help:?")
                                      : (verbose ? " terse:v help:?"
                                                 : " verbose:v help:?");
    int l= strlen(helpstring);
    getyx(titlewin,y,x);
    if (xmax-l > 0) {
      mvwaddstr(titlewin,0,xmax-l, helpstring);
    }
    wnoutrefresh(titlewin);
  }
}
