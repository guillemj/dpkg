/*
 * dselect - Debian package maintenance user interface
 * pkgdepcon.cc - dependency and conflict resolution
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
#include <string.h>
#include <stdio.h>

#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

#include "dselect.h"
#include "pkglist.h"

static const int depdebug= 1;

bool
packagelist::useavailable(pkginfo *pkg)
{
  if (pkg->clientdata &&
      pkg->clientdata->selected == pkginfo::want_install &&
      informative(pkg,&pkg->available) &&
      (!(pkg->status == pkginfo::stat_installed ||
         pkg->status == pkginfo::stat_triggersawaited ||
         pkg->status == pkginfo::stat_triggerspending) ||
       versioncompare(&pkg->available.version,&pkg->installed.version) > 0))
    return true;
  else
    return false;
}

pkginfoperfile *packagelist::findinfo(pkginfo *pkg) {
  pkginfoperfile *r;
  r= useavailable(pkg) ? &pkg->available : &pkg->installed;
  if (debug)
    fprintf(debug,"packagelist[%p]::findinfo(%s) useavailable=%d\n",this,pkg->name,useavailable(pkg));

  return r;
}
  
int packagelist::checkdependers(pkginfo *pkg, int changemade) {
  struct deppossi *possi;
  
  for (possi = pkg->available.depended; possi; possi = possi->nextrev) {
    if (!useavailable(possi->up->up))
      continue;
    changemade = max(changemade, resolvedepcon(possi->up));
  }
  for (possi = pkg->installed.depended; possi; possi = possi->nextrev) {
    if (useavailable(possi->up->up))
      continue;
    changemade = max(changemade, resolvedepcon(possi->up));
  }
  return changemade;
}

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
      if (depdebug && debug)
        fprintf(debug,"packagelist[%p]::resolvesuggest() loop[%i] %s / %d\n",
                this, index, table[index]->pkg->name, changemade);
      dependency *depends;
      for (depends= findinfo(table[index]->pkg)->depends;
           depends;
           depends= depends->next) {
        changemade = max(changemade, resolvedepcon(depends));
      }
      changemade= checkdependers(table[index]->pkg,changemade);
      for (depends= findinfo(table[index]->pkg)->depends;
           depends;
           depends= depends->next) {
        if (depends->type != dep_provides) continue;
        changemade= checkdependers(depends->list->ed,changemade);
      }
      if (depdebug && debug)
        fprintf(debug,"packagelist[%p]::resolvesuggest() loop[%i] %s / -> %d\n",
                this, index, table[index]->pkg->name, changemade);
    }
    if (!changemade) break;
    maxchangemade = max(maxchangemade, changemade);
  }
  if (debug)
    fprintf(debug,"packagelist[%p]::resolvesuggest() done; maxchangemade=%d\n",
            this,maxchangemade);
  return maxchangemade;
}

static int dep_update_best_to_change_stop(perpackagestate *& best, pkginfo *trythis) {
  // There's no point trying to select a pure virtual package.
  if (!trythis->clientdata) return 0;
  
  if (depdebug && debug)
    fprintf(debug,"update_best_to_change(best=%s{%d}, test=%s{%d});\n",
            best ? best->pkg->name : "", best ? (int)best->spriority : -1,
            trythis->name, trythis->clientdata->spriority);

  // If the problem is caused by us deselecting one of these packages
  // we should not try to select another one instead.
  if (trythis->clientdata->spriority == sp_deselecting) return 1;

  // If we haven't found anything yet then this is our best so far.
  if (!best) goto yes;

  // If only one of the packages is available, use that one
  if (!informative(trythis,&trythis->available) &&
      informative(best->pkg,&best->pkg->available)) return 0;
  if (informative(trythis,&trythis->available) &&
      !informative(best->pkg,&best->pkg->available)) goto yes;
  
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
  if (depdebug && debug) fprintf(debug,"update_best_to_change(); yes\n");

  best=trythis->clientdata; return 0;
}

int
packagelist::deselect_one_of(pkginfo *per, pkginfo *ped, dependency *dep)
{
  perpackagestate *er= per->clientdata;
  perpackagestate *ed= ped->clientdata;

  if (!er || !would_like_to_install(er->selected,per) ||
      !ed || !would_like_to_install(ed->selected,ped)) return 0;
  
  add(dep, dp_must);

  er= per->clientdata;  // these can be changed by add
  ed= ped->clientdata;
  
  if (depdebug && debug)
    fprintf(debug,"packagelist[%p]::deselect_one_of(): er %s{%d} ed %s{%d} [%p]\n",
            this, er->pkg->name, er->spriority, ed->pkg->name, ed->spriority, dep);
  
  perpackagestate *best;

  // Try not keep packages needing reinstallation.
  if (per->eflag & pkginfo::eflag_reinstreq)
    best = ed;
  else if (ped->eflag & pkginfo::eflag_reinstreq)
    best = er;
  else if (er->spriority < ed->spriority) best= er; // We'd rather change the
  else if (er->spriority > ed->spriority) best= ed; // one with the lowest priority.
  // ... failing that the one with the highest priority
  else if (er->pkg->priority > ed->pkg->priority)
    best = er;
  else if (er->pkg->priority < ed->pkg->priority)
    best = ed;
  else best= ed;                                      // ... failing that, the second

  if (depdebug && debug)
    fprintf(debug,"packagelist[%p]::deselect_one_of(): best %s{%d}\n",
            this, best->pkg->name, best->spriority);

  if (best->spriority >= sp_deselecting) return 0;
  best->suggested=
    best->pkg->status == pkginfo::stat_notinstalled
      ? pkginfo::want_purge : pkginfo::want_deinstall; // FIXME: configurable.
  best->selected= best->suggested;
  best->spriority= sp_deselecting;

  return 2;
}

int packagelist::resolvedepcon(dependency *depends) {
  perpackagestate *best, *fixbyupgrade;
  deppossi *possi, *provider;
  int r, foundany;

  if (depdebug && debug) {
    fprintf(debug,"packagelist[%p]::resolvedepcon([%p] %s --%s-->",
            this, depends, depends->up->name, relatestrings[depends->type]);
    for (possi=depends->list; possi; possi=possi->next)
      fprintf(debug," %s",possi->ed->name);
    fprintf(debug,"); (ing)->want=%s\n",
            depends->up->clientdata
            ? wantstrings[depends->up->clientdata->suggested]
            : "(no clientdata)");
  }
  
  if (!depends->up->clientdata) return 0;

  switch (depends->type) {

  case dep_provides:
  case dep_replaces:
    return 0;

  case dep_enhances:
  case dep_suggests:
  case dep_recommends:
  case dep_depends:
  case dep_predepends:
    if (would_like_to_install(depends->up->clientdata->selected,depends->up) <= 0)
      return 0;

    fixbyupgrade= 0;
    
    possi = depends->list;
    while (possi && !deppossatisfied(possi, &fixbyupgrade))
      possi = possi->next;
    if (depdebug && debug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): depends found %s\n",
              this,depends,
              possi ? possi->ed->name : "[none]");
    if (possi) return 0;

    // Ensures all in the recursive list; adds info strings; ups priorities
    switch (depends->type) {
    case dep_enhances:
    case dep_suggests:
    	r= add(depends, dp_may);
	return r;
    case dep_recommends: 
    	r= add(depends, dp_should);
	break;
    default:
    	r= add(depends, dp_must);
    }

    if (fixbyupgrade) {
      if (depdebug && debug) fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): "
                            "fixbyupgrade %s\n", this,depends,fixbyupgrade->pkg->name);
      best= fixbyupgrade;
    } else {
      best= 0;
      for (possi= depends->list;
           possi;
           possi= possi->next) {
        foundany= 0;
        if (possi->ed->clientdata) foundany= 1;
        if (dep_update_best_to_change_stop(best, possi->ed)) goto mustdeselect;
        for (provider = possi->ed->available.depended;
             provider;
             provider= provider->nextrev) {
          if (provider->up->type != dep_provides) continue;
          if (provider->up->up->clientdata) foundany= 1;
          if (dep_update_best_to_change_stop(best, provider->up->up)) goto mustdeselect;
        }
        if (!foundany) addunavailable(possi);
      }
      if (!best) {
        if (depdebug && debug) fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): "
                              "mustdeselect nobest\n", this,depends);
        return r;
      }
    }
    if (depdebug && debug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): select best=%s{%d}\n",
              this,depends, best->pkg->name, best->spriority);
    if (best->spriority >= sp_selecting) return r;
    /* Always select depends. Only select recommends if we got here because
     * of a manually-initiated install request. */
    if (depends->type != dep_recommends || manual_install) {
      best->selected= best->suggested= pkginfo::want_install;
      best->spriority= sp_selecting;
    }
    return r ? 2 : 0;
    
  mustdeselect:
    best= depends->up->clientdata;
    if (depdebug && debug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): mustdeselect best=%s{%d}\n",
              this,depends, best->pkg->name, best->spriority);

    if (best->spriority >= sp_deselecting) return r;
    /* Always remove depends, but never remove recommends. */
    if (depends->type != dep_recommends) {
      best->selected= best->suggested=
        best->pkg->status == pkginfo::stat_notinstalled
          ? pkginfo::want_purge : pkginfo::want_deinstall; // FIXME: configurable
      best->spriority= sp_deselecting;
    }
    return r ? 2 : 0;
    
  case dep_conflicts:
  case dep_breaks:

    if (depdebug && debug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): conflict\n",
              this,depends);
    
    if (would_like_to_install(depends->up->clientdata->selected,depends->up) == 0)
      return 0;

    if (depdebug && debug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): conflict installing 1\n",
              this,depends);

    if (!deppossatisfied(depends->list,0)) return 0;

    if (depdebug && debug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): conflict satisfied - ouch\n",
              this,depends);

    if (depends->up != depends->list->ed) {
      r= deselect_one_of(depends->up, depends->list->ed, depends);  if (r) return r;
    }
    for (provider = depends->list->ed->available.depended;
         provider;
         provider= provider->nextrev) {
      if (provider->up->type != dep_provides) continue;
      if (provider->up->up == depends->up) continue; // conflicts & provides same thing
      r= deselect_one_of(depends->up, provider->up->up, depends);  if (r) return r;
    }
    if (depdebug && debug)
      fprintf(debug,"packagelist[%p]::resolvedepcon([%p]): no desel\n", this,depends);
    return 0;
    
  default:
    internerr("unknown deptype");
  }
  /* never reached, make gcc happy */
  return 1;
}

bool
packagelist::deppossatisfied(deppossi *possi, perpackagestate **fixbyupgrade)
{
  // `satisfied' here for Conflicts and Breaks means that the
  //  restriction is violated ie that the target package is wanted
  int would;
  pkginfo::pkgwant want= pkginfo::want_purge;
  
  if (possi->ed->clientdata) {
    want= possi->ed->clientdata->selected;
    would= would_like_to_install(want,possi->ed);
  } else {
    would= 0;
  }
  
  if ((possi->up->type == dep_conflicts || possi->up->type == dep_breaks)
      ? possi->up->up != possi->ed && would != 0
      : would > 0) {
    // If it's to be installed or left installed, then either it's of
    // the right version, and therefore OK, or a version must have
    // been specified, in which case we don't need to look at the rest
    // anyway.
    if (useavailable(possi->ed)) {
      assert(want == pkginfo::want_install);
      return versionsatisfied(&possi->ed->available,possi);
    } else {
      if (versionsatisfied(&possi->ed->installed, possi))
        return true;
      if (want == pkginfo::want_hold && fixbyupgrade && !*fixbyupgrade &&
          versionsatisfied(&possi->ed->available,possi) &&
          versioncompare(&possi->ed->available.version,
                         &possi->ed->installed.version) > 1)
        *fixbyupgrade= possi->ed->clientdata;
      return false;
    }
  }
  if (possi->verrel != dvr_none)
    return false;
  deppossi *provider;

  for (provider = possi->ed->installed.depended;
       provider;
       provider = provider->nextrev) {
    if (provider->up->type == dep_provides &&
        provider->up->up->clientdata &&
        !useavailable(provider->up->up) &&
        would_like_to_install(provider->up->up->clientdata->selected,
                              provider->up->up))
      return true;
  }
  for (provider = possi->ed->available.depended;
       provider;
       provider = provider->nextrev) {
    if (provider->up->type != dep_provides ||
        !provider->up->up->clientdata ||
        !would_like_to_install(provider->up->up->clientdata->selected,
                               provider->up->up))
      continue;
    if (useavailable(provider->up->up))
      return true;
    if (fixbyupgrade && !*fixbyupgrade &&
        (!(provider->up->up->status == pkginfo::stat_installed ||
           provider->up->up->status == pkginfo::stat_triggerspending ||
           provider->up->up->status == pkginfo::stat_triggersawaited) ||
         versioncompare(&provider->up->up->available.version,
                        &provider->up->up->installed.version) > 1))
      *fixbyupgrade = provider->up->up->clientdata;
  }
  return false;
}
