/*
 * dselect - Debian GNU/Linux package maintenance user interface
 * pkgtop.cc - handles (re)draw of package list windows colheads, list, thisstate
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
#include <ctype.h>

extern "C" {
#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
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
    return prioritystrings[pkg->priority];
  }
}

static int describemany(char buf[], const char *prioritystring, const char *section) {
  if (!prioritystring) {
    if (!section) {
      strcpy(buf, "All packages");
      return 0;
    } else {
      if (!*section) {
        strcpy(buf, "All packages without a section");
      } else {
        sprintf(buf, "All packages in section %s", section);
      }
      return 1;
    }
  } else {
    if (!section) {
      sprintf(buf, "All %s packages", prioritystring);
      return 1;
    } else {
      if (!*section) {
        sprintf(buf, "All %s packages without a section", prioritystring);
      } else {
        sprintf(buf, "All %s packages in section %s", prioritystring, section);
      }
      return 2;
    }
  }
}

void packagelist::redrawthisstate() {
  if (!thisstate_height) return;
  mywerase(thisstatepad);

  const char *section= table[cursorline]->pkg->section;
  const char *priority= pkgprioritystring(table[cursorline]->pkg);
  char *buf= new char[220+
                      greaterint((table[cursorline]->pkg->name
                                  ? strlen(table[cursorline]->pkg->name) : 0),
                                 (section ? strlen(section) : 0) +
                                 (priority ? strlen(priority) : 0))];
    
  if (table[cursorline]->pkg->name) {
    sprintf(buf,
            "%-*s %s%s%s;  %s (was: %s).  %s",
            package_width,
            table[cursorline]->pkg->name,
            statusstrings[table[cursorline]->pkg->status],
            holdstrings[table[cursorline]->pkg->eflag][0] ? " - " : "",
            holdstrings[table[cursorline]->pkg->eflag],
            wantstrings[table[cursorline]->selected],
            wantstrings[table[cursorline]->original],
            priority);
  } else {
    describemany(buf,priority,section);
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
                holdstrings[pkg->eflag]);
      wprintw(listpad, "%-*.*s ",
              status_status_width, status_status_width,
              statusstrings[pkg->status]);
      wprintw(listpad, "%-*.*s ",
              status_want_width, status_want_width,
              /* fixme: keep this ? */
              /*table[index]->original == table[index]->selected ? "(same)"
              : */wantstrings[table[index]->original]);
      wattrset(listpad, selected ? selstatesel_attr : selstate_attr);
      wprintw(listpad, "%-*.*s",
              status_want_width, status_want_width,
              wantstrings[table[index]->selected]);
      wattrset(listpad, selected ? listsel_attr : list_attr);
      waddch(listpad, ' ');
  
      mvwprintw(listpad,index,priority_column-1, " %-*.*s",
                priority_width, priority_width,
                pkg->priority == pkginfo::pri_other ? pkg->otherpriority :
                prioritystrings[pkg->priority]);

    } else {

      mvwaddch(listpad,index,0, holdchars[pkg->eflag]);
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
        char *p;
        for (i=priority_width, p=pkg->otherpriority;
             i > 0 && *p;
             i--, p++)
          waddch(listpad, tolower(*p));
        while (i-- > 0) waddch(listpad,' ');
      } else {
        wprintw(listpad, "%-*.*s", priority_width, priority_width,
                priorityabbrevs[pkg->priority]);
      }

    }

    mvwprintw(listpad,index,section_column-1, " %-*.*s",
              section_width, section_width,
              pkg->section ? pkg->section : "?");
  
    mvwprintw(listpad,index,package_column-1, " %-*.*s ",
              package_width, package_width, pkg->name);
      
    i= description_width;
    p= info->description ? info->description : "";
    while (i>0 && *p && *p != '\n') { waddch(listpad,*p); i--; p++; }
      
  } else {

    const char *section= pkg->section;
    const char *priority= pkgprioritystring(pkg);

    char *buf= new char[220+
                        (section ? strlen(section) : 0) +
                        (priority ? strlen(priority) : 0)];
    
    indent= describemany(buf,priority,section);

    mvwaddstr(listpad,index,0, "    ");
    i= total_width-6;
    j= (indent<<1) + 1;
    while (j-- >0) { waddch(listpad,'-'); i--; }
    waddch(listpad,' ');

    wattrset(listpad, selected ? selstatesel_attr : selstate_attr);
    p= buf;
    while (i>0 && *p) { waddch(listpad, *p); p++; i--; }
    wattrset(listpad, selected ? listsel_attr : list_attr);

    waddch(listpad,' ');
    j= (indent<<1) + 1;
    while (j-- >0) { waddch(listpad,'-'); i--; }

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
                 "Hold/Err.",
                 status_hold_width);
      mvwaddnstr(colheadspad,0,
                 status_hold_width+1,
                 "Installed?",
                 status_status_width);
      mvwaddnstr(colheadspad,0,
                 status_hold_width+status_status_width+2,
                 "Old sel.",
                 status_want_width);
      mvwaddnstr(colheadspad,0,
                 status_hold_width+status_status_width+status_want_width+3,
                 "Selection",
                 status_want_width);
    } else {
      mvwaddstr(colheadspad,0,0, "HIOS");
    }
    mvwaddnstr(colheadspad,0,section_column, "Section", section_width);
    mvwaddnstr(colheadspad,0,priority_column, "Priority", priority_width);
    mvwaddnstr(colheadspad,0,package_column, "Package", package_width);
    mvwaddnstr(colheadspad,0,description_column, "Description", description_width);
  }
  refreshcolheads();
}
