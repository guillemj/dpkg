/*
 * dpkg - main program for package management
 * packages.c - common to actions that process packages
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
 * License along with dpkg; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */
#include <config.h>

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <ctype.h>
#include <unistd.h>
#include <string.h>
#include <assert.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>

#include "filesdb.h"
#include "main.h"

struct pkginqueue {
  struct pkginqueue *next;
  struct pkginfo *pkg;
};

static struct pkginqueue *queuehead= 0, **queuetail= &queuehead;

int queuelen=0, sincenothing=0, dependtry=0;

void add_to_queue(struct pkginfo *pkg) {
  struct pkginqueue *newent;

  newent= m_malloc(sizeof(struct pkginqueue));
  newent->pkg= pkg;
  newent->next= 0;
  *queuetail= newent;
  queuetail= &newent->next;

  queuelen++;
}

void packages(const char *const *argv) {
  struct pkgiterator *it;
  struct pkginfo *pkg;
  const char *thisarg;
  size_t l;
  
  modstatdb_init(admindir,
                 f_noact ?    msdbrw_readonly
               : fc_nonroot ? msdbrw_write
               :              msdbrw_needsuperuser);
  checkpath();

  if (f_pending) {

    if (*argv)
      badusage(_("--%s --pending does not take any non-option arguments"),cipaction->olong);

    it= iterpkgstart();
    while ((pkg= iterpkgnext(it)) != 0) {
      switch (cipaction->arg) {
      case act_configure:
        if (pkg->status != stat_unpacked && pkg->status != stat_halfconfigured)
          continue;
        if (pkg->want != want_install)
          continue;
        break;
      case act_remove:
      case act_purge:
        if (pkg->want != want_purge) {
          if (pkg->want != want_deinstall) continue;
          if (pkg->status == stat_configfiles) continue;
        }
        if (pkg->status == stat_notinstalled)
          continue;
        break;
      default:
        internerr("unknown action for pending");
      }
      add_to_queue(pkg);
    }
    iterpkgend(it);

  } else {
        
    if (!*argv)
      badusage(_("--%s needs at least one package name argument"), cipaction->olong);
    
    while ((thisarg= *argv++) != 0) {
      pkg= findpackage(thisarg);
      if (pkg->status == stat_notinstalled) {
        l= strlen(pkg->name);
        if (l >= sizeof(DEBEXT) && !strcmp(pkg->name+l-sizeof(DEBEXT)+1,DEBEXT))
          badusage(_("you must specify packages by their own names,"
                   " not by quoting the names of the files they come in"));
      }
      add_to_queue(pkg);
    }

  }

  ensure_diversions();

  process_queue();

  modstatdb_shutdown();
}

void process_queue(void) {
  struct pkginqueue *removeent, *rundown;
  struct pkginfo *volatile pkg;
  jmp_buf ejbuf;
  enum istobes istobe= itb_normal;
  
  clear_istobes();

  switch (cipaction->arg) {
  case act_configure: case act_install:  istobe= itb_installnew;  break;
  case act_remove: case act_purge:       istobe= itb_remove;      break;
  default: internerr("unknown action for queue start");
  }
  for (rundown= queuehead; rundown; rundown= rundown->next) {
    ensure_package_clientdata(rundown->pkg);
    if (rundown->pkg->clientdata->istobe == istobe) {
      /* Remove it from the queue - this is a second copy ! */
      switch (cipaction->arg) {
      case act_configure: case act_remove: case act_purge:
        printf(_("Package %s listed more than once, only processing once.\n"),
               rundown->pkg->name);
        break;
      case act_install:
        printf(_("More than one copy of package %s has been unpacked\n"
               " in this run !  Only configuring it once.\n"),
               rundown->pkg->name);
        break;
      default:
        internerr("unknown action in duplicate");
      }
      rundown->pkg= 0;
   } else {
      rundown->pkg->clientdata->istobe= istobe;
    }
  }
  
  while (queuelen) {
    removeent= queuehead;
    assert(removeent);
    queuehead= queuehead->next;
    queuelen--;
    if (queuetail == &removeent->next) queuetail= &queuehead;

    pkg= removeent->pkg;
    free(removeent);
    
    if (!pkg) continue; /* duplicate, which we removed earlier */

    assert(pkg->status <= stat_configfiles);

    if (setjmp(ejbuf)) {
      /* give up on it from the point of view of other packages, ie reset istobe */
      pkg->clientdata->istobe= itb_normal;
      error_unwind(ehflag_bombout);
      if (onerr_abort > 0) break;
      continue;
    }
    push_error_handler(&ejbuf,print_error_perpackage,pkg->name);
    if (sincenothing++ > queuelen*2+2) {
      dependtry++; sincenothing= 0;
      assert(dependtry <= 4);
    }
    switch (cipaction->arg) {
    case act_install:
      /* Don't try to configure pkgs that we've just disappeared. */
      if (pkg->status == stat_notinstalled)
        break;
    case act_configure:
      deferred_configure(pkg);
      break;
    case act_remove: case act_purge:
      deferred_remove(pkg);
      break;
    default:
      internerr("unknown action in queue");
    }
    if (ferror(stdout)) werr("stdout");
    if (ferror(stderr)) werr("stderr");
    set_error_display(0,0);
    error_unwind(ehflag_normaltidy);
  }
}    

/*** dependency processing - common to --configure and --remove ***/

/*
 * The algorithm for deciding what to configure or remove first is as
 * follows:
 *
 * Loop through all packages doing a `try 1' until we've been round and
 * nothing has been done, then do `try 2' and `try 3' likewise.
 *
 * When configuring, in each try we check to see whether all
 * dependencies of this package are done.  If so we do it.  If some of
 * the dependencies aren't done yet but will be later we defer the
 * package, otherwise it is an error.
 *
 * When removing, in each try we check to see whether there are any
 * packages that would have dependencies missing if we removed this
 * one.  If not we remove it now.  If some of these packages are
 * themselves scheduled for removal we defer the package until they
 * have been done.
 *
 * The criteria for satisfying a dependency vary with the various
 * tries.  In try 1 we treat the dependencies as absolute.  In try 2 we
 * check break any cycles in the dependency graph involving the package
 * we are trying to process before trying to process the package
 * normally.  In try 3 (which should only be reached if
 * --force-depends-version is set) we ignore version number clauses in
 * Depends lines.  In try 4 (only reached if --force-depends is set) we
 * say "ok" regardless.
 *
 * If we are configuring and one of the packages we depend on is
 * awaiting configuration but wasn't specified in the argument list we
 * will add it to the argument list if --configure-any is specified.
 * In this case we note this as having "done something" so that we
 * don't needlessly escalate to higher levels of dependency checking
 * and breaking.
 */

static int deppossi_ok_found(struct pkginfo *possdependee,
                             struct pkginfo *requiredby,
                             struct pkginfo *removing,
                             struct pkginfo *providing,
                             int *matched,
                             struct deppossi *checkversion,
                             int *interestingwarnings,
                             struct varbuf *oemsgs) {
  int thisf;
  
  if (ignore_depends(possdependee)) {
    debug(dbg_depcondetail,"      ignoring depended package so ok and found");
    return 3;
  }
  thisf= 0;
  if (possdependee == removing) {
    varbufaddstr(oemsgs,_("  Package "));
    varbufaddstr(oemsgs,possdependee->name);
    if (providing) {
      varbufaddstr(oemsgs,_(" which provides "));
      varbufaddstr(oemsgs,providing->name);
    }
    varbufaddstr(oemsgs,_(" is to be removed.\n"));
    *matched= 1;
    if (fc_depends) thisf= (dependtry >= 4) ? 2 : 1;
    debug(dbg_depcondetail,"      removing possdependee, returning %d",thisf);
    return thisf;
  }
  switch (possdependee->status) {
  case stat_installed:
  case stat_unpacked:
  case stat_halfconfigured:
    assert(possdependee->installed.valid);
    if (checkversion && !versionsatisfied(&possdependee->installed,checkversion)) {
      varbufaddstr(oemsgs,_("  Version of "));
      varbufaddstr(oemsgs,possdependee->name);
      varbufaddstr(oemsgs,_(" on system is "));
      varbufaddstr(oemsgs,versiondescribe(&possdependee->installed.version,
                                          vdew_nonambig));
      varbufaddstr(oemsgs,".\n");
      assert(checkversion->verrel != dvr_none);
      if (fc_depends) thisf= (dependtry >= 3) ? 2 : 1;
      debug(dbg_depcondetail,"      bad version, returning %d",thisf);
      (*interestingwarnings)++;
      return thisf;
    }
    if (possdependee->status == stat_installed) {
      debug(dbg_depcondetail,"      is installed, ok and found");
      return 3;
    }
    if (possdependee->clientdata &&
        possdependee->clientdata->istobe == itb_installnew) {
      debug(dbg_depcondetail,"      unpacked/halfconfigured, defer");
      return 1;
    } else if (!removing && fc_configureany && !skip_due_to_hold(possdependee)) {
      fprintf(stderr,
              _("dpkg: also configuring `%s' (required by `%s')\n"),
              possdependee->name, requiredby->name);
      add_to_queue(possdependee); sincenothing=0; return 1;
    } else {
      varbufaddstr(oemsgs,_("  Package "));
      varbufaddstr(oemsgs,possdependee->name);
      if (providing) {
        varbufaddstr(oemsgs,_(" which provides "));
        varbufaddstr(oemsgs,providing->name);
      }
      varbufaddstr(oemsgs,_(" is not configured yet.\n"));
      if (fc_depends) thisf= (dependtry >= 4) ? 2 : 1;
      debug(dbg_depcondetail,"      not configured/able - returning %d",thisf);
      (*interestingwarnings)++;
      return thisf;
    }
  default:
    varbufaddstr(oemsgs,_("  Package "));
    varbufaddstr(oemsgs,possdependee->name);
    if (providing) {
      varbufaddstr(oemsgs,_(" which provides "));
      varbufaddstr(oemsgs,providing->name);
    }
    varbufaddstr(oemsgs,_(" is not installed.\n"));
    if (fc_depends) thisf= (dependtry >= 4) ? 2 : 1;
    debug(dbg_depcondetail,"      not installed - returning %d",thisf);
    (*interestingwarnings)++;
    return thisf;
  }
}

int dependencies_ok(struct pkginfo *pkg, struct pkginfo *removing,
                    struct varbuf *aemsgs) {
  int ok, matched, found, thisf, interestingwarnings;
  struct varbuf oemsgs;
  struct dependency *dep;
  struct deppossi *possi, *provider;

  varbufinit(&oemsgs);
  interestingwarnings= 0;
  ok= 2; /* 2=ok, 1=defer, 0=halt */
  debug(dbg_depcon,"checking dependencies of %s (- %s)",
        pkg->name, removing ? removing->name : "<none>");
  assert(pkg->installed.valid);
  for (dep= pkg->installed.depends; dep; dep= dep->next) {
    if (dep->type != dep_depends && dep->type != dep_predepends) continue;
    debug(dbg_depcondetail,"  checking group ...");
    matched= 0; varbufreset(&oemsgs);
    found= 0; /* 0=none, 1=defer, 2=withwarning, 3=ok */
    for (possi= dep->list; found != 3 && possi; possi= possi->next) {
      debug(dbg_depcondetail,"    checking possibility  -> %s",possi->ed->name);
      if (possi->cyclebreak) {
        debug(dbg_depcondetail,"      break cycle so ok and found");
        found= 3; break;
      }
      thisf= deppossi_ok_found(possi->ed,pkg,removing,0,
                               &matched,possi,&interestingwarnings,&oemsgs);
      if (thisf > found) found= thisf;
      if (found != 3 && possi->verrel == dvr_none) {
        if (possi->ed->installed.valid) {
          for (provider= possi->ed->installed.depended;
               found != 3 && provider;
               provider= provider->nextrev) {
            if (provider->up->type != dep_provides) continue;
            debug(dbg_depcondetail,"     checking provider %s",provider->up->up->name);
            thisf= deppossi_ok_found(provider->up->up,pkg,removing,possi->ed,
                                     &matched,0,&interestingwarnings,&oemsgs);
            if (thisf > found) found= thisf;
          }
        }
      }
      debug(dbg_depcondetail,"    found %d",found);
      if (thisf > found) found= thisf;
    }
    debug(dbg_depcondetail,"  found %d matched %d",found,matched);
    if (removing && !matched) continue;
    switch (found) {
    case 0:
      ok= 0;
    case 2:
      varbufaddstr(aemsgs, " ");
      varbufaddstr(aemsgs, pkg->name);
      varbufaddstr(aemsgs, _(" depends on "));
      varbufdependency(aemsgs, dep);
      if (interestingwarnings) {
        /* Don't print the line about the package to be removed if
         * that's the only line.
         */
        varbufaddstr(aemsgs, _("; however:\n"));
        varbufaddc(&oemsgs, 0);
        varbufaddstr(aemsgs, oemsgs.buf);
      } else {
        varbufaddstr(aemsgs, ".\n");
      }
      break;
    case 1:
      if (ok>1) ok= 1;
      break;
    case 3:
      break;
    default:
      internerr("unknown value for found");
    }
  }
  if (ok == 0 && (pkg->clientdata && pkg->clientdata->istobe == itb_remove))
    ok= 1;
  
  varbuffree(&oemsgs);
  debug(dbg_depcon,"ok %d msgs >>%.*s<<", ok, (int)aemsgs->used, aemsgs->buf);
  return ok;
}
