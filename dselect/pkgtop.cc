/*
 * dselect - Debian package maintenance user interface
 * pkgtop.cc - handles (re)draw of package list windows colheads, list, thisstate
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <assert.h>
#include <ctype.h>
#include <string.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

#include "dselect.h"
#include "pkglist.h"

static const char *
pkgprioritystring(const struct pkginfo *pkg)
{
  if (pkg->priority == pkginfo::pri_unset) {
    return 0;
  } else if (pkg->priority == pkginfo::pri_other) {
    return pkg->otherpriority;
  } else {
    assert(pkg->priority <= pkginfo::pri_unknown);
    return gettext(prioritystrings[pkg->priority]);
  }
}

int packagelist::describemany(char buf[], const char *prioritystring,
                              const char *section,
                              const struct perpackagestate *pps) {
  const char *ssostring, *ssoabbrev;
  int statindent;

  statindent= 0;
  ssostring= 0;
  ssoabbrev= _("All");
  switch (statsortorder) {
  case sso_avail:
    if (pps->ssavail == -1) break;
    ssostring= ssastrings[pps->ssavail];
    ssoabbrev= ssaabbrevs[pps->ssavail];
    statindent++;
    break;
  case sso_state:
    if (pps->ssstate == -1) break;
    ssostring= sssstrings[pps->ssstate];
    ssoabbrev= sssabbrevs[pps->ssstate];
    statindent++;
    break;
  case sso_unsorted:
    break;
  default:
    internerr("unknown statsortrder in describemany all");
  }

  if (!prioritystring) {
    if (!section) {
      strcpy(buf, ssostring ? gettext(ssostring) : _("All packages"));
      return statindent;
    } else {
      if (!*section) {
        sprintf(buf,_("%s packages without a section"),gettext(ssoabbrev));
      } else {
        sprintf(buf,_("%s packages in section %s"),gettext(ssoabbrev),section);
      }
      return statindent+1;
    }
  } else {
    if (!section) {
      sprintf(buf,_("%s %s packages"),gettext(ssoabbrev),prioritystring);
      return statindent+1;
    } else {
      if (!*section) {
        sprintf(buf,_("%s %s packages without a section"),gettext(ssoabbrev),prioritystring);
      } else {
        sprintf(buf,_("%s %s packages in section %s"),gettext(ssoabbrev),prioritystring,section);
      }
      return statindent+2;
    }
  }
}

void packagelist::redrawthisstate() {
  if (!thisstate_height) return;
  mywerase(thisstatepad);

  const char *section= table[cursorline]->pkg->section;
  const char *priority= pkgprioritystring(table[cursorline]->pkg);
  char *buf= new char[500+
                      max((table[cursorline]->pkg->name ?
                           strlen(table[cursorline]->pkg->name) : 0),
                          (section ? strlen(section) : 0) +
                          (priority ? strlen(priority) : 0))];

  if (table[cursorline]->pkg->name) {
    sprintf(buf,
            _("%-*s %s%s%s;  %s (was: %s).  %s"),
            package_width,
            table[cursorline]->pkg->name,
            gettext(statusstrings[table[cursorline]->pkg->status]),
            ((eflagstrings[table[cursorline]->pkg->eflag][0]==' ') &&
              (eflagstrings[table[cursorline]->pkg->eflag][1]=='\0'))  ? "" : " - ",
            gettext(eflagstrings[table[cursorline]->pkg->eflag]),
            gettext(wantstrings[table[cursorline]->selected]),
            gettext(wantstrings[table[cursorline]->original]),
            priority);
  } else {
    describemany(buf,priority,section,table[cursorline]->pkg->clientdata);
  }
  mvwaddnstr(thisstatepad,0,0, buf, total_width);
  pnoutrefresh(thisstatepad, 0,leftofscreen, thisstate_row,0,
               thisstate_row, min(total_width - 1, xmax - 1));

  delete[] buf;
}

void packagelist::redraw1itemsel(int index, int selected) {
  int i, indent, j;
  const char *p;
  const struct pkginfo *pkg= table[index]->pkg;
  const struct pkgbin *info = &pkg->available;
  int screenline = index - topofscreen;

  wattrset(listpad, selected ? listsel_attr : list_attr);

  if (pkg->name) {
    if (verbose) {
      mvwprintw(listpad, screenline, 0, "%-*.*s ",
                status_hold_width, status_hold_width,
                gettext(eflagstrings[pkg->eflag]));
      wprintw(listpad, "%-*.*s ",
              status_status_width, status_status_width,
              gettext(statusstrings[pkg->status]));
      wprintw(listpad, "%-*.*s ",
              status_want_width, status_want_width,
              /* FIXME: keep this? */
              /*table[index]->original == table[index]->selected ? "(same)"
              : */gettext(wantstrings[table[index]->original]));
      wattrset(listpad, selected ? selstatesel_attr : selstate_attr);
      wprintw(listpad, "%-*.*s",
              status_want_width, status_want_width,
              gettext(wantstrings[table[index]->selected]));
      wattrset(listpad, selected ? listsel_attr : list_attr);
      waddch(listpad, ' ');

      mvwprintw(listpad, screenline, priority_column - 1, " %-*.*s",
                priority_width, priority_width,
                pkg->priority == pkginfo::pri_other ? pkg->otherpriority :
                gettext(prioritystrings[pkg->priority]));
    } else {
      mvwaddch(listpad, screenline, 0, eflagchars[pkg->eflag]);
      waddch(listpad, statuschars[pkg->status]);
      waddch(listpad,
             /* FIXME: keep this feature? */
             /*table[index]->original == table[index]->selected ? ' '
             : */wantchars[table[index]->original]);

      wattrset(listpad, selected ? selstatesel_attr : selstate_attr);
      waddch(listpad, wantchars[table[index]->selected]);
      wattrset(listpad, selected ? listsel_attr : list_attr);

      wmove(listpad, screenline, priority_column - 1);
      waddch(listpad, ' ');
      if (pkg->priority == pkginfo::pri_other) {
        for (i=priority_width, p=pkg->otherpriority;
             i > 0 && *p;
             i--, p++)
          waddch(listpad, tolower(*p));
        while (i-- > 0) waddch(listpad,' ');
      } else {
        wprintw(listpad, "%-*.*s", priority_width, priority_width,
                gettext(priorityabbrevs[pkg->priority]));
      }
    }

    mvwprintw(listpad, screenline, section_column - 1, " %-*.*s",
              section_width, section_width,
              pkg->section ? pkg->section : "?");

    mvwprintw(listpad, screenline, package_column - 1, " %-*.*s ",
              package_width, package_width, pkg->name);

    if (versioninstalled_width)
      mvwprintw(listpad, screenline, versioninstalled_column, "%-*.*s ",
                versioninstalled_width, versioninstalled_width,
                versiondescribe(&pkg->installed.version, vdew_nonambig));
    if (versionavailable_width) {
      if (informativeversion(&pkg->available.version) &&
          versioncompare(&pkg->available.version,&pkg->installed.version) > 0)
        wattrset(listpad, selected ? selstatesel_attr : selstate_attr);
      mvwprintw(listpad, screenline, versionavailable_column, "%-*.*s",
                versionavailable_width, versionavailable_width,
                versiondescribe(&pkg->available.version, vdew_nonambig));
      wattrset(listpad, selected ? listsel_attr : list_attr);
      waddch(listpad,' ');
    }

    i= description_width;
    p= info->description ? info->description :
       pkg->installed.description ? pkg->installed.description : "";
    while (i>0 && *p && *p != '\n') { waddnstr(listpad,p,1); i--; p++; }
  } else {
    const char *section= pkg->section;
    const char *priority= pkgprioritystring(pkg);

    char *buf= new char[500+
                        (section ? strlen(section) : 0) +
                        (priority ? strlen(priority) : 0)];

    indent= describemany(buf,priority,section,pkg->clientdata);

    mvwaddstr(listpad, screenline, 0, "    ");
    i= total_width-7;
    j= (indent<<1) + 1;
    while (j-- >0) { waddch(listpad,ACS_HLINE); i--; }
    waddch(listpad,' ');

    wattrset(listpad, selected ? selstatesel_attr : selstate_attr);
    p= buf;
    while (i>0 && *p) { waddnstr(listpad, p,1); p++; i--; }
    wattrset(listpad, selected ? listsel_attr : list_attr);

    waddch(listpad,' ');
    j= (indent<<1) + 1;
    while (j-- >0) { waddch(listpad,ACS_HLINE); i--; }

    delete[] buf;
  }

  while (i>0) { waddch(listpad,' '); i--; }
}

void packagelist::redrawcolheads() {
  if (colheads_height) {
    wattrset(colheadspad,colheads_attr);
    mywerase(colheadspad);
    if (verbose) {
      wmove(colheadspad,0,0);
      for (int i=0; i<status_width-status_want_width; i++) waddch(colheadspad,'.');
      mvwaddnstr(colheadspad,0,
                 0,
                 _("Error"),
                 status_hold_width);
      mvwaddnstr(colheadspad,0,
                 status_hold_width+1,
                 _("Installed?"),
                 status_status_width);
      mvwaddnstr(colheadspad,0,
                 status_hold_width+status_status_width+2,
                 _("Old mark"),
                 status_want_width);
      mvwaddnstr(colheadspad,0,
                 status_hold_width+status_status_width+status_want_width+3,
                 _("Marked for"),
                 status_want_width);
    } else {
      mvwaddstr(colheadspad,0,0, _("EIOM"));
    }
    mvwaddnstr(colheadspad,0,section_column, _("Section"), section_width);
    mvwaddnstr(colheadspad,0,priority_column, _("Priority"), priority_width);
    mvwaddnstr(colheadspad,0,package_column, _("Package"), package_width);

    if (versioninstalled_width)
      mvwaddnstr(colheadspad,0,versioninstalled_column,
                 _("Inst.ver"),versioninstalled_width);
    if (versionavailable_width)
      mvwaddnstr(colheadspad,0,versionavailable_column,
                 _("Avail.ver"),versionavailable_width);

    mvwaddnstr(colheadspad,0,description_column, _("Description"), description_width);
  }
  refreshcolheads();
}
