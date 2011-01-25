/*
 * dselect - Debian package maintenance user interface
 * pkgcmds.cc - package list keyboard commands
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

#include <string.h>
#include <stdio.h>

#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

#include "dselect.h"
#include "pkglist.h"

bool
packagelist::affectedmatches(struct pkginfo *pkg, struct pkginfo *comparewith) {
  switch (statsortorder) {
  case sso_avail:
    if (comparewith->clientdata->ssavail != pkg->clientdata->ssavail)
      return false;
    break;
  case sso_state:
    if (comparewith->clientdata->ssstate != pkg->clientdata->ssstate)
      return false;
    break;
  case sso_unsorted:
    break;
  default:
    internerr("unknown statsortorder in affectedmatches");
  }
  if (comparewith->priority != pkginfo::pri_unset &&
      (comparewith->priority != pkg->priority ||
       (comparewith->priority == pkginfo::pri_other &&
        strcasecmp(comparewith->otherpriority, pkg->otherpriority))))
    return false;
  if (comparewith->section &&
      strcasecmp(comparewith->section,
                 pkg->section ?
                 pkg->section : ""))
    return false;
  return true;
}

void packagelist::affectedrange(int *startp, int *endp) {
  if (table[cursorline]->pkg->set->name) {
    *startp= cursorline;
    *endp= cursorline+1;
    return;
  }
  int index = cursorline;
  while (index < nitems && !table[index]->pkg->set->name)
    index++;
  if (index >= nitems) {
    *startp= *endp= cursorline;
    return;
  }
  *startp= index;
  while (index < nitems && affectedmatches(table[index]->pkg,table[cursorline]->pkg))
    index++;
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

pkginfo::pkgwant packagelist::reallywant(pkginfo::pkgwant nwarg,
                                         struct perpackagestate *pkgstate) {
  if (nwarg != pkginfo::want_sentinel) return nwarg;
  pkginfo::pkgstatus status= pkgstate->pkg->status;
  if (status == pkginfo::stat_notinstalled) return pkginfo::want_purge;
  if (status == pkginfo::stat_configfiles) return pkginfo::want_deinstall;
  return pkginfo::want_install;
}

void packagelist::setwant(pkginfo::pkgwant nwarg) {
  int index, top, bot;
  pkginfo::pkgwant nw;

  if (!readwrite) { beep(); return; }

  if (recursive) {
    redrawitemsrange(cursorline,cursorline+1);
    table[cursorline]->selected= reallywant(nwarg,table[cursorline]);
    redraw1item(cursorline);
    top= cursorline;
    bot= cursorline+1;
  } else {
    packagelist *sub= new packagelist(bindings,0);

    affectedrange(&top,&bot);
    for (index= top; index < bot; index++) {
      if (!table[index]->pkg->set->name)
        continue;
      nw= reallywant(nwarg,table[index]);
      if (table[index]->selected == nw ||
          (table[index]->selected == pkginfo::want_purge &&
           nw == pkginfo::want_deinstall))
        continue;
      sub->add(table[index]->pkg,nw);
    }

    repeatedlydisplay(sub,dp_may,this);
    for (index=top; index < bot; index++)
      redraw1item(index);
  }
  movecursorafter(bot);
}

int manual_install = 0;

void packagelist::kd_select()   {
	manual_install = 1;
	setwant(pkginfo::want_install);
	manual_install = 0;
}
void packagelist::kd_hold()     { setwant(pkginfo::want_hold);      }
void packagelist::kd_deselect() { setwant(pkginfo::want_deinstall); }
void packagelist::kd_unhold()   { setwant(pkginfo::want_sentinel);  }
void packagelist::kd_purge()    { setwant(pkginfo::want_purge);     }

int would_like_to_install(pkginfo::pkgwant wantvalue, pkginfo *pkg) {
  /* Returns: 1 for yes, 0 for no, -1 for if they want to preserve an error condition. */
  debug(dbg_general, "would_like_to_install(%d, %s) status %d",
        wantvalue, pkg->set->name, pkg->status);

  if (wantvalue == pkginfo::want_install) return 1;
  if (wantvalue != pkginfo::want_hold) return 0;
  if (pkg->status == pkginfo::stat_installed) return 1;
  if (pkg->status == pkginfo::stat_notinstalled ||
      pkg->status == pkginfo::stat_configfiles) return 0;
  return -1;
}

const char *packagelist::itemname(int index) {
  return table[index]->pkg->set->name;
}

void packagelist::kd_swapstatorder() {
  if (sortorder == so_unsorted) return;
  switch (statsortorder) {
  case sso_avail:     statsortorder= sso_state;     break;
  case sso_state:     statsortorder= sso_unsorted;  break;
  case sso_unsorted:  statsortorder= sso_avail;     break;
  default: internerr("unknown statsort in kd_swapstatorder");
  }
  resortredisplay();
}

void packagelist::kd_swaporder() {
  switch (sortorder) {
  case so_priority:  sortorder= so_section;   break;
  case so_section:   sortorder= so_alpha;     break;
  case so_alpha:     sortorder= so_priority;  break;
  case so_unsorted:                           return;
  default: internerr("unknown sort in kd_swaporder");
  }
  resortredisplay();
}

void packagelist::resortredisplay() {
  const char *oldname = table[cursorline]->pkg->set->name;
  sortmakeheads();
  int newcursor;
  newcursor= 0;
  if (oldname) {
    int index;
    for (index=0; index<nitems; index++) {
      if (table[index]->pkg->set->name &&
          !strcasecmp(oldname, table[index]->pkg->set->name)) {
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

void packagelist::kd_versiondisplay() {
  switch (versiondisplayopt) {
  case vdo_both:       versiondisplayopt= vdo_none;       break;
  case vdo_none:       versiondisplayopt= vdo_available;  break;
  case vdo_available:  versiondisplayopt= vdo_both;       break;
  default: internerr("unknown versiondisplayopt in kd_versiondisplay");
  }
  setwidths();
  leftofscreen= 0;
  ldrawnstart= ldrawnend= -1;
  redrawtitle();
  redrawcolheads();
  redrawitemsrange(topofscreen, min(topofscreen + list_height, nitems));
  refreshlist();
}

void packagelist::kd_verbose() {
  verbose= !verbose;
  setwidths();
  leftofscreen= 0;
  ldrawnstart= ldrawnend= -1;
  redrawtitle();
  redrawcolheads();
  redrawitemsrange(topofscreen, min(topofscreen + list_height, nitems));
  refreshlist();
}

void packagelist::kd_quit_noop() { }

void packagelist::kd_revert_abort() {
  int index;
  for (index=0; index<nitems; index++) {
    if (table[index]->pkg->set->name)
      table[index]->selected= table[index]->original;
    ldrawnstart= ldrawnend= -1;
  }
  refreshlist(); redrawthisstate();
}

void packagelist::kd_revertdirect() {
  int index;
  for (index=0; index<nitems; index++) {
    if (table[index]->pkg->set->name)
      table[index]->selected= table[index]->direct;
    ldrawnstart= ldrawnend= -1;
  }
  refreshlist(); redrawthisstate();
}

void packagelist::kd_revertsuggest() {
  int index;
  for (index=0; index<nitems; index++) {
    if (table[index]->pkg->set->name)
      table[index]->selected= table[index]->suggested;
    ldrawnstart= ldrawnend= -1;
  }
  refreshlist(); redrawthisstate();
}

void
packagelist::kd_revertinstalled()
{
  int i;

  for (i = 0; i < nitems; i++) {
    if (table[i]->pkg->set->name)
      table[i]->selected = reallywant(pkginfo::want_sentinel, table[i]);
    ldrawnstart = ldrawnend = -1;
  }

  refreshlist();
  redrawthisstate();
}

/* FIXME: configurable purge/deselect */

void packagelist::kd_toggleinfo() {
  showinfo= (showinfo+2) % 3;
  setheights();
  if (cursorline >= topofscreen+list_height) topofscreen += list_height;
  if (topofscreen > nitems - list_height) topofscreen= nitems-list_height;
  if (topofscreen < 0) topofscreen= 0;
  infotopofscreen= 0;
  redraw1item(cursorline);
  refreshlist();
  redrawthisstate();
  redrawinfo();
}

void packagelist::kd_info() {
  if (!showinfo) {
    showinfo= 2; kd_toggleinfo();
  } else {
    currentinfo++;
    infotopofscreen=0;
    redrawinfo();
  }
}
