/*
 * dselect - Debian GNU/Linux package maintenance user interface
 * pkgcmds.cc - package list keyboard commands
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

static int matches(struct pkginfo *pkg, struct pkginfo *comparewith) {
  if (comparewith->priority != pkginfo::pri_unset &&
      (comparewith->priority != pkg->priority ||
       comparewith->priority == pkginfo::pri_other &&
       strcasecmp(comparewith->otherpriority,pkg->otherpriority)))
    return 0;
  if (comparewith->section &&
      strcasecmp(comparewith->section,
                 pkg->section ?
                 pkg->section : ""))
    return 0;
  return 1;
}

void packagelist::affectedrange(int *startp, int *endp) {
  if (table[cursorline]->pkg->name) {
    *startp= cursorline;
    *endp= cursorline+1;
    return;
  }
  int index;
  for (index= cursorline; index < nitems && !table[index]->pkg->name; index++);
  if (index >= nitems) {
    *startp= *endp= cursorline;
    return;
  }
  *startp= index;
  while (index < nitems && matches(table[index]->pkg,table[cursorline]->pkg)) index++;
  *endp= index;
}

void packagelist::movecursorafter(int ncursor) {
  if (ncursor >= nitems) ncursor= nitems-1;
  topofscreen += ncursor-cursorline;
  if (topofscreen > nitems - list_height) topofscreen= nitems - list_height;
  if (topofscreen < 0) topofscreen= 0;
  setcursor(ncursor);
  refreshlist(); redrawthisstate();
}

void packagelist::setwant(pkginfo::pkgwant nw) {
  int index, top, bot;

  if (!readwrite) { beep(); return; }

  if (recursive) {
    redrawitemsrange(cursorline,cursorline+1);
    table[cursorline]->selected= nw;
    redraw1item(cursorline);
    top= cursorline;
    bot= cursorline+1;
  } else {
    packagelist *sub= new packagelist(bindings,0);

    affectedrange(&top,&bot);
    for (index= top; index < bot; index++) {
      if (!table[index]->pkg->name ||
          table[index]->selected == nw ||
          table[index]->selected == pkginfo::want_purge && nw == pkginfo::want_deinstall)
        continue;
      sub->add(table[index]->pkg,nw);
    }

    repeatedlydisplay(sub,dp_may,this);
    for (index=top; index < bot; index++)
      redraw1item(index);
  }
  movecursorafter(bot);
}

void packagelist::kd_select()   { setwant(pkginfo::want_install);   }
void packagelist::kd_deselect() { setwant(pkginfo::want_deinstall); }
void packagelist::kd_purge()    { setwant(pkginfo::want_purge);     }

void packagelist::sethold(int hold) {
  int top, bot, index;

  if (!readwrite) { beep(); return; }

  affectedrange(&top,&bot);
  for (index= top; index < bot; index++) {
    // Sorry about the contortions, but GCC produces a silly warning otherwise
    unsigned int neweflag= table[index]->pkg->eflag;
    if (hold) neweflag |= pkginfo::eflagf_hold;
    else neweflag &= ~pkginfo::eflagf_hold;
    table[index]->pkg->eflag= (enum pkginfo::pkgeflag)neweflag;
    redraw1item(index);
  }
  movecursorafter(bot);
}

void packagelist::kd_hold()     { sethold(1);                       }
void packagelist::kd_unhold()   { sethold(0);                       }

const char *packagelist::itemname(int index) {
  return table[index]->pkg->name;
}

void packagelist::kd_swaporder() {
  switch (sortorder) {
  case so_priority:  sortorder= so_section;   break;
  case so_section:   sortorder= so_alpha;     break;
  case so_alpha:     sortorder= so_priority;  break;
  case so_unsorted:                           return;
  default: internerr("unknown sort in kd_swaporder");
  }
  const char *oldname= table[cursorline]->pkg->name;
  sortmakeheads();
  int newcursor;
  newcursor= 0;
  if (oldname) {
    int index;
    for (index=0; index<nitems; index++) {
      if (table[index]->pkg->name && !strcasecmp(oldname,table[index]->pkg->name)) {
        newcursor= index;
        break;
      }
    }
  }
  topofscreen= newcursor-1;
  if (topofscreen > nitems - list_height) topofscreen= nitems-list_height;
  if (topofscreen < 0) topofscreen= 0;
  setwidths();
  redrawtitle();
  redrawcolheads();
  ldrawnstart= ldrawnend= -1;
  cursorline= -1;
  setcursor(newcursor);
  refreshlist();
}

void packagelist::kd_verbose() {
  verbose= !verbose;
  setwidths();
  leftofscreen= 0;
  ldrawnstart= ldrawnend= -1;
  redrawtitle();
  redrawcolheads();
  redrawitemsrange(topofscreen,lesserint(topofscreen+list_height,nitems));
  refreshlist();
}

void packagelist::kd_quit_noop() { }

void packagelist::kd_revert_abort() {
  int index;
  for (index=0; index<nitems; index++) {
    if (table[index]->pkg->name)
      table[index]->selected= table[index]->original;
    ldrawnstart= ldrawnend= -1;
  }
  refreshlist(); redrawthisstate();
}

void packagelist::kd_revertdirect() {
  int index;
  for (index=0; index<nitems; index++) {
    if (table[index]->pkg->name)
      table[index]->selected= table[index]->direct;
    ldrawnstart= ldrawnend= -1;
  }
  refreshlist(); redrawthisstate();
}

void packagelist::kd_revertsuggest() {
  int index;
  for (index=0; index<nitems; index++) {
    if (table[index]->pkg->name)
      table[index]->selected= table[index]->suggested;
    ldrawnstart= ldrawnend= -1;
  }
  refreshlist(); redrawthisstate();
}

/* fixme: configurable purge/deselect */
/* fixme: un-hold things */

void packagelist::kd_info() {
  currentinfo++;
  infotopofscreen=0;
  redrawinfo();
}
