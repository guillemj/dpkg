/*
 * dselect - Debian GNU/Linux package maintenance user interface
 * pkgdepcon.cc - dependency and conflict resolution
 *
 * Copyright (C) 1995 Ian Jackson <iwj10@cus.cam.ac.uk>
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

extern "C" {
#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
}
#include "dselect.h"
#include "pkglist.h"

static const int depdebug= 1;

int packagelist::resolvesuggest() {
  // We continually go around looking for things to change, but we may
  // only change the `suggested' value if we also increase the `priority'
  // Return 2 if we made a change due to a Recommended, Depends or Conficts,
  // or 1 if we offered or made a change because of an Optional line.
  if (debug)
    fprintf(debug,"packagelist[%p]::resolvesuggest()\n",this);
  int changemade, maxchangemade;
  maxchangemade= 0;
  for (;;) {
    changemade= 0;
    int index;
    for (index=0; index<nitems; index++) {
      if (!table[index]->pkg->name) continue;
      if (depdebug)
        fprintf(debug,"packagelist[%p]::resolvesuggest() loop[%i] %s / %d\n",
                this, index, table[index]->pkg->name, changemade);
      dependency *depends;
      for (depends= table[index]->pkg->available.depends;
           depends;
           depends= depends->next)
        changemade= greaterint(changemade, resolvedepcon(depends));
      deppossi *possi;
      for (possi= table[index]->pkg->available.depended;
           possi;
           possi= possi->nextrev) 
        changemade= greaterint(changemade, resolvedepcon(possi->up));
      for (depends= table[index]->pkg->available.depends;
           depends;
           depends= depends->next)
        if (depends->type == dep_provides)
          for (possi= depends->list->ed->available.valid
                      ? depends->list->ed->available.depended : 0;
               possi;
               possi= possi->nextrev)
            changemade= greaterint(changemade, resolvedepcon(possi->up));
      if (depdebug)
        fprintf(debug,"packagelist[%p]::resolvesuggest() loop[%i] %s / -> %d\n",
                this, index, table[index]->pkg->name, changemade);
    }
    if (!changemade) break;
    maxchangemade= greaterint(maxchangemade, changemade);
  }
  if (debug)
    fprintf(debug,"packagelist[%p]::resolvesuggest() done; maxchangemade=%d\n",
            this,maxchangemade);
  return maxchangemade;
}

static int dep_update_best_to_change_stop(perpackagestate *& best, pkginfo *trythis) {
  // There's no point trying to select a pure virtual package.
  if (!trythis->clientdata) return 0;
  
  if (depdebug)
    fprintf(debug,"update_best_to_change(best=%s{%d}, test=%s{%d});\n",
            best ? best->pkg->name : "", best ? (int)best->spriority : -1,
            trythis->name, trythis->clientdata->spriority);

  // If the problem is caused by us deselecting one of these packages
  // we should not try to select another one instead.
  if (trythis->clientdata->spriority == sp_deselecting) return 1;

  // If we haven't found anything yet then this is our best so far.
  if (!best) goto yes;
  
  // Select the package with the lowest priority (ie, the one of whom
  // we were least sure we wanted it deselected).
  if (trythis->clientdata->spriority > best->spriority) return 0;
  if (trythis->clientdata->spriority < best->spriority) goto yes;

  // Pick the package with the must fundamental recommendation level.
  if (trythis->priority > best->pkg->priority) return 0;
  if (trythis->priority < best->pkg->priority) goto yes;

  // If we're still unsure we'll change the first one in the list.
  return 0;
  
 yes:
  if (depdebug) fprintf(debug,"update_best_to_change(); yes\n");

  best=trythis->clientdata; return 0;
}

int packagelist::deselect_one_of(pkginfo *per, pkginfo *ped, dependency *display) {
  perpackagestate *er= per->clientdata;
  perpackagestate *ed= ped->clientdata;

  if (!er || !would_like_to_install(er->selected,per) ||
      !ed || !would_like_to_install(ed->selected,ped)) return 0;
  
  add(display,dp_must);

  er= per->clientdata;  // these can be changed by add
  ed= ped->clientdata;
  
  if (depdebug)
    fprintf(debug,"packagelist[%p]::deselect_one_of(): er %s{%d} ed %s{%d} [%p]\n",
            this, er->pkg->name, er->spriority, ed->pkg->name, ed->spriority, display);
  
  perpackagestate *best;

  if (per->eflag & pkginfo::eflagf_reinstreq) best= ed;      // Try not keep packages
  else if (ped->eflag & pkginfo::eflagf_reinstreq) best= er; //  needing reinstallation
  else if (er->spriority < ed->spriority) best= er; // We'd rather change the
  else if (er->spriority > ed->spriority) best= ed; // one with the lowest priority.
  else if (er->pkg->priority >
           er->pkg->priority) best= er;         // ... failing that the one with
  else if (er->pkg->priority <                  //  the highest priority
           er->pkg->priority) best= ed;
  
  else best= ed;                                      // ... failing that, the second

  if (depdebug)
    fprintf(debug,"packagelist[%p]::deselect_one_of(): best %s{%d}\n",
            this, best->pkg->name, best->spriority);

  if (best->spriority >= sp_deselecting) return 0;
  best->suggested=
    best->pkg->status == pkginfo::stat_notinstalled
      ? pkginfo::want_purge : pkginfo::want_deinstall; /* fixme: configurable */
  best->selected= best->suggested;
  best->spriority= sp_deselecting;

  return 2;
}

int packagelist::resolvedepcon(dependency *depends) {
  perpackagestate *best;
  deppossi *possi, *provider;
  int r, foundany;

  if (depdebug) {
    fprintf(debug,"packagelist[%p]::resolvedepcon([%p] %s --%s-->",
            this,depends,depends->up->name,relatestrings[depends->type]);
    for (possi=depends->list; possi; possi=possi->next)
      fprintf(debug," %s",possi->ed->name);
    fprintf(debug,"); (ing)->want=%s\n",
            depends->up->clientdata
            ? wantstrings[depends->up->clientdata->suggested]
            : "(no clientdata)");
  }
  
  if (!depends->up->clientdata) return 0;
  
  if (depends->up->clientdata->selected != pkginfo::want_install) return 0;

  switch (depends->type) {

  case dep_provides:
  case dep_replaces:
    return 0;
    
  case dep_suggests:
    if (0) return 0; /* fixme: configurable */
    // fall through ...
  case dep_recommends:
  case dep_depends:
  case dep_predepends:
    for (possi= depends->list;
         possi && !deppossatisfied(possi);
         possi= possi->next);
    if (depdebug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): depends found %s\n",
              this,depends, possi ? possi->ed->name : "[none]");
    if (possi) return 0;

    // Ensures all in the recursive list; adds info strings; ups priorities
    r= add(depends, depends->type == dep_suggests ? dp_may : dp_must);

    if (depends->type == dep_suggests) return r;

    best= 0;
    for (possi= depends->list;
         possi;
         possi= possi->next) {
      foundany= 0;
      if (possi->ed->clientdata) foundany= 1;
      if (dep_update_best_to_change_stop(best, possi->ed)) goto mustdeselect;
      for (provider= possi->ed->available.valid ? possi->ed->available.depended : 0;
           provider;
           provider= provider->nextrev) {
        if (provider->up->type != dep_provides) continue;
        if (provider->up->up->clientdata) foundany= 1;
        if (dep_update_best_to_change_stop(best, provider->up->up)) goto mustdeselect;
      }
      if (!foundany) addunavailable(possi);
    }

    if (!best) {
      if (depdebug) fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): "
                            "mustdeselect nobest\n", this,depends);
      return r;
    }
    if (depdebug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): select best=%s{%d}\n",
              this,depends, best->pkg->name, best->spriority);
    if (best->spriority >= sp_selecting) return r;
    best->selected= best->suggested= pkginfo::want_install;
    best->spriority= sp_selecting;
    return 2;
    
  mustdeselect:
    best= depends->up->clientdata;
    if (depdebug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): mustdeselect best=%s{%d}\n",
              this,depends, best->pkg->name, best->spriority);

    if (best->spriority >= sp_deselecting) return r;
    best->selected= best->suggested=
      best->pkg->status == pkginfo::stat_notinstalled
        ? pkginfo::want_purge : pkginfo::want_deinstall; /* fixme: configurable */
    best->spriority= sp_deselecting;
    return 2;
    
  case dep_conflicts:
    if (!deppossatisfied(depends->list)) return 0;
    if (depends->up != depends->list->ed) {
      r= deselect_one_of(depends->up, depends->list->ed, depends);  if (r) return r;
    }
    for (provider= depends->list->ed->available.valid ?
                   depends->list->ed->available.depended : 0;
         provider;
         provider= provider->nextrev) {
      if (provider->up->type != dep_provides) continue;
      if (provider->up->up == depends->up) continue; // conflicts & provides same thing
      r= deselect_one_of(depends->up, provider->up->up, depends);  if (r) return r;
    }
    if (depdebug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): no desel\n", this,depends);
    return 0;
    
  default:
    internerr("unknown deptype");
  }
}

int deppossatisfied(deppossi *possi) {
  if (possi->ed->clientdata &&
      possi->ed->clientdata->selected == pkginfo::want_install &&
      !(possi->up->type == dep_conflicts && possi->up->up == possi->ed)) {
    // If it's installed, then either it's of the right version,
    // and therefore OK, or a version must have been specified,
    // in which case we don't need to look at the rest anyway.
    if (possi->verrel == deppossi::dvr_none) return 1;
    int r= versioncompare(&possi->ed->available.version,&possi->version);
    switch (possi->verrel) {
    case deppossi::dvr_earlierequal:   return r <= 0;
    case deppossi::dvr_laterequal:     return r >= 0;
    case deppossi::dvr_earlierstrict:  return r < 0;
    case deppossi::dvr_laterstrict:    return r > 0;
    case deppossi::dvr_exact:          return r == 0;
    default:                           internerr("unknown verrel");
    }
  }
  if (possi->verrel != deppossi::dvr_none) return 0;
  deppossi *provider;
  for (provider= possi->ed->available.valid ? possi->ed->available.depended : 0;
       provider;
       provider= provider->nextrev) {
    if (provider->up->type != dep_provides) continue;
    if (provider->up->up->clientdata &&
        would_like_to_install(provider->up->up->clientdata->selected,
                              provider->up->up) == 1)
      return 1;
  }
  return 0;
}
