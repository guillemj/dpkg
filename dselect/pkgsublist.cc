/*
 * dselect - Debian package maintenance user interface
 * pkgsublist.cc - status modification and recursive package list handling
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

extern "C" {
#include <dpkg.h>
#include <dpkg-db.h>
}
#include "dselect.h"
#include "bindings.h"

void packagelist::add(pkginfo *pkg) {
  if (debug) fprintf(debug,"packagelist[%p]::add(pkginfo %s)\n",this,pkg->name);
  if (!recursive ||  // never add things to top level
      !pkg->clientdata ||  // don't add pure virtual packages
      pkg->clientdata->uprec)  // don't add ones already in the recursive list
    return;
  if (debug) fprintf(debug,"packagelist[%p]::add(pkginfo %s) adding\n",this,pkg->name);
  perpackagestate *state= &datatable[nitems];
  state->pkg= pkg;
  state->direct= state->original= pkg->clientdata->selected;
  state->suggested= state->selected= pkg->clientdata->selected;
  state->spriority= sp_inherit; state->dpriority= dp_none;
  state->uprec= pkg->clientdata;
  state->relations.init();
  pkg->clientdata= state;
  table[nitems]= state;
  nitems++;
}   

void packagelist::add(pkginfo *pkg, pkginfo::pkgwant nw) {
  if (debug) fprintf(debug,"packagelist[%p]::add(pkginfo %s, %s)\n",
                     this,pkg->name,gettext(wantstrings[nw]));
  add(pkg);  if (!pkg->clientdata) return;
  pkg->clientdata->direct= nw;
  selpriority np;
  np= would_like_to_install(nw,pkg) ? sp_selecting : sp_deselecting;
  if (pkg->clientdata->spriority > np) return;
  if (debug) fprintf(debug,"packagelist[%p]::add(pkginfo %s, %s) setting\n",
                     this,pkg->name,gettext(wantstrings[nw]));
  pkg->clientdata->suggested= pkg->clientdata->selected= nw;
  pkg->clientdata->spriority= np;
    
}   

void packagelist::add(pkginfo *pkg, const char *extrainfo, showpriority showimp) {
  if (debug)
    fprintf(debug,"packagelist[%p]::add(pkginfo %s, \"...\", showpriority %d)\n",
            this,pkg->name,showimp);
  add(pkg);  if (!pkg->clientdata) return;
  if (pkg->clientdata->dpriority < showimp) pkg->clientdata->dpriority= showimp;
  pkg->clientdata->relations(extrainfo);
  pkg->clientdata->relations.terminate();
}   

int packagelist::alreadydone(doneent **done, void *check) {
  doneent *search;
  
  for (search= *done; search && search->dep != check; search=search->next);
  if (search) return 1;
  if (debug) fprintf(debug,"packagelist[%p]::alreadydone(%p,%p) new\n",
                     this,done,check);
  search= new doneent;
  search->next= *done;
  search->dep= check;
  *done= search;
  return 0;
}

void packagelist::addunavailable(deppossi *possi) {
  if (debug) fprintf(debug,"packagelist[%p]::addunavail(%p)\n",this,possi);

  if (!recursive) return;
  if (alreadydone(&unavdone,possi)) return;

  assert(possi->up->up->clientdata);
  assert(possi->up->up->clientdata->uprec);

  varbuf& vb= possi->up->up->clientdata->relations;
  vb(possi->ed->name);
  vb(_(" does not appear to be available\n"));
}

int packagelist::add(dependency *depends, showpriority displayimportance) {
  if (debug) fprintf(debug,"packagelist[%p]::add(dependency[%p])\n",this,depends);

  if (alreadydone(&depsdone,depends)) return 0;
  
  const char *comma= "";
  varbuf info;
  info(depends->up->name);
  info(' ');
  info(gettext(relatestrings[depends->type]));
  info(' ');
  deppossi *possi;
  for (possi=depends->list;
       possi;
       possi=possi->next, comma=(possi && possi->next ? ", " : _(" or "))) {
    info(comma);
    info(possi->ed->name);
    if (possi->verrel != dvr_none) {
      switch (possi->verrel) {
      case dvr_earlierequal:  info(" (<= "); break;
      case dvr_laterequal:    info(" (>= "); break;
      case dvr_earlierstrict: info(" (<< "); break;
      case dvr_laterstrict:   info(" (>> "); break;
      case dvr_exact:         info(" (= "); break;
      default: internerr("unknown verrel");
      }
      info(versiondescribe(&possi->version,vdew_never));
      info(")");
    }
  }
  info('\n');
  add(depends->up,info.string(),displayimportance);
  for (possi=depends->list; possi; possi=possi->next) {
    add(possi->ed,info.string(),displayimportance);
    if (possi->verrel == dvr_none && depends->type != dep_provides) {
      // providers aren't relevant if a version was specified, or
      // if we're looking at a provider relationship already
      deppossi *provider;
      for (provider= possi->ed->available.valid ? possi->ed->available.depended : 0;
           provider;
           provider=provider->nextrev) {
        if (provider->up->type != dep_provides) continue;
        add(provider->up->up,info.string(),displayimportance);
        add(provider->up,displayimportance);
      }
    }
  }
  return 1;
}

void repeatedlydisplay(packagelist *sub,
                       showpriority initial,
                       packagelist *unredisplay) {
  pkginfo **newl;
  keybindings *kb;
  
  if (debug) fprintf(debug,"repeatedlydisplay(packagelist[%p])\n",sub);
  if (sub->resolvesuggest() != 0 && sub->deletelessimp_anyleft(initial)) {
    if (debug) fprintf(debug,"repeatedlydisplay(packagelist[%p]) once\n",sub);
    if (unredisplay) unredisplay->enddisplay();
    for (;;) {
      manual_install = 0; /* Remove flag now that resolvesuggest has seen it. */
      newl= sub->display();
      if (!newl) break;
      if (debug) fprintf(debug,"repeatedlydisplay(packagelist[%p]) newl\n",sub);
      kb= sub->bindings; delete sub;
      sub= new packagelist(kb,newl);
      if (sub->resolvesuggest() <= 1) break;
      if (!sub->deletelessimp_anyleft(dp_must)) break;
      if (debug) fprintf(debug,"repeatedlydisplay(packagelist[%p]) again\n",sub);
    }
    if (unredisplay) unredisplay->startdisplay();
  }
  delete sub;
  if (debug) fprintf(debug,"repeatedlydisplay(packagelist[%p]) done\n",sub);
}

int packagelist::deletelessimp_anyleft(showpriority than) {
  if (debug)
    fprintf(debug,"packagelist[%p]::dli_al(%d): nitems=%d\n",this,than,nitems);
  int insat, runthr;
  for (runthr=0, insat=0;
       runthr < nitems;
       runthr++) {
    if (table[runthr]->dpriority < than) {
      table[runthr]->free(recursive);
    } else {
      if (insat != runthr) table[insat]= table[runthr];
      insat++;
    }
  }
  nitems= insat;
  if (debug) fprintf(debug,"packagelist[%p]::dli_al(%d) done; nitems=%d\n",
                     this,than,nitems);
  return nitems;
}
