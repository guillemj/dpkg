/*
 * dselect - Debian package maintenance user interface
 * pkgtop.cc - handles (re)draw of package list windows colheads, list, thisstate
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
extern "C" {
#include <config.h>
}

#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <ctype.h>

extern "C" {
#include <dpkg.h>
#include <dpkg-db.h>
}
#include "dselect.h"
#include "pkglist.h"

const char *pkgprioritystring(const struct pkginfo *pkg) {
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
                      greaterint((table[cursorline]->pkg->name
                                  ? strlen(table[cursorline]->pkg->name) : 0),
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
               thisstate_row, lesserint(total_width - 1, xmax - 1));

  delete[] buf;
}

void packagelist::redraw1itemsel(int index, int selected) {
  int i, indent, j;
  const char *p;
  const struct pkginfo *pkg= table[index]->pkg;
  const struct pkginfoperfile *info= &pkg->available;

  wattrset(listpad, selected ? listsel_attr : list_attr);

  if (pkg->name) {

    if (verbose) {

      mvwprintw(listpad,index,0, "%-*.*s ",
                status_hold_width, status_hold_width,
                gettext(eflagstrings[pkg->eflag]));
      wprintw(listpad, "%-*.*s ",
              status_status_width, status_status_width,
              gettext(statusstrings[pkg->status]));
      wprintw(listpad, "%-*.*s ",
              status_want_width, status_want_width,
              /* fixme: keep this ? */
              /*table[index]->original == table[index]->selected ? "(same)"
              : */gettext(wantstrings[table[index]->original]));
      wattrset(listpad, selected ? selstatesel_attr : selstate_attr);
      wprintw(listpad, "%-*.*s",
              status_want_width, status_want_width,
              gettext(wantstrings[table[index]->selected]));
      wattrset(listpad, selected ? listsel_attr : list_attr);
      waddch(listpad, ' ');
  
      mvwprintw(listpad,index,priority_column-1, " %-*.*s",
                priority_width, priority_width,
                pkg->priority == pkginfo::pri_other ? pkg->otherpriority :
                gettext(prioritystrings[pkg->priority]));

    } else {

      mvwaddch(listpad,index,0, eflagchars[pkg->eflag]);
      waddch(listpad, statuschars[pkg->status]);
      waddch(listpad,
             /* fixme: keep this feature? */
             /*table[index]->original == table[index]->selected ? ' '
             : */wantchars[table[index]->original]);
    
      wattrset(listpad, selected ? selstatesel_attr : selstate_attr);
      waddch(listpad, wantchars[table[index]->selected]);
      wattrset(listpad, selected ? listsel_attr : list_attr);
      
      wmove(listpad,index,priority_column-1); waddch(listpad,' ');
      if (pkg->priority == pkginfo::pri_other) {
        int i;
        const char *p;
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

    mvwprintw(listpad,index,section_column-1, " %-*.*s",
              section_width, section_width,
              pkg->section ? pkg->section : "?");
  
    mvwprintw(listpad,index,package_column-1, " %-*.*s ",
              package_width, package_width, pkg->name);

    if (versioninstalled_width)
      mvwprintw(listpad,index,versioninstalled_column, "%-*.*s ",
                versioninstalled_width, versioninstalled_width,
                versiondescribe(&pkg->installed.version,vdew_never));
    if (versionavailable_width) {
      if (informativeversion(&pkg->available.version) &&
          versioncompare(&pkg->available.version,&pkg->installed.version) > 0)
        wattrset(listpad, selected ? selstatesel_attr : selstate_attr);
      mvwprintw(listpad,index,versionavailable_column, "%-*.*s",
                versionavailable_width, versionavailable_width,
                versiondescribe(&pkg->available.version,vdew_never));
      wattrset(listpad, selected ? listsel_attr : list_attr);
      waddch(listpad,' ');
    }

    i= description_width;
    p= info->description ? info->description : "";
    while (i>0 && *p && *p != '\n') { waddnstr(listpad,p,1); i--; p++; }
      
  } else {

    const char *section= pkg->section;
    const char *priority= pkgprioritystring(pkg);

    char *buf= new char[500+
                        (section ? strlen(section) : 0) +
                        (priority ? strlen(priority) : 0)];
    
    indent= describemany(buf,priority,section,pkg->clientdata);

    mvwaddstr(listpad,index,0, "    ");
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
