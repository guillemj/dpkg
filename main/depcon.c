/*
 * dpkg - main program for package management
 * depcon.c - dependency and conflict checking
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

#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <assert.h>

#include <dpkg.h>
#include <dpkg-db.h>

#include "main.h"

struct cyclesofarlink {
  struct cyclesofarlink *back;
  struct pkginfo *pkg;
  struct deppossi *possi;
};

static int findbreakcyclerecursive(struct pkginfo *pkg, struct cyclesofarlink *sofar);

static int foundcyclebroken(struct cyclesofarlink *thislink,
                            struct cyclesofarlink *sofar,
                            struct pkginfo *dependedon,
                            struct deppossi *possi) {
  struct cyclesofarlink *sol;
  const char *postinstfilename;
  struct stat stab;

  if(!possi) return 0;
  /* We're investigating the dependency `possi' to see if it
   * is part of a loop.  To this end we look to see whether the
   * depended-on package is already one of the packages whose
   * dependencies we're searching.
   */
  for (sol=sofar; sol && sol->pkg != dependedon; sol=sol->back);

  /* If not, we do a recursive search on it to see what we find. */
  if (!sol) return findbreakcyclerecursive(possi->ed,thislink);
  
  debug(dbg_depcon,"found cycle");
  /* Right, we now break one of the links.  We prefer to break
   * a dependency of a package without a postinst script, as
   * this is a null operation.  If this is not possible we break
   * the other link in the recursive calling tree which mentions
   * this package (this being the first package involved in the
   * cycle).  It doesn't particularly matter which we pick, but if
   * we break the earliest dependency we came across we may be
   * able to do something straight away when findbreakcycle returns.
   */
  sofar= thislink;
  for (sol= sofar; !(sol != sofar && sol->pkg == dependedon); sol=sol->back) {
    postinstfilename= pkgadminfile(sol->pkg,POSTINSTFILE);
    if (lstat(postinstfilename,&stab)) {
      if (errno == ENOENT) break;
      ohshite(_("unable to check for existence of `%.250s'"),postinstfilename);
    }
  }
  /* Now we have either a package with no postinst, or the other
   * occurrence of the current package in the list.
   */
  sol->possi->cyclebreak= 1;
  debug(dbg_depcon,"cycle broken at %s -> %s\n",
        sol->possi->up->up->name, sol->possi->ed->name);
  return 1;
}

static int findbreakcyclerecursive(struct pkginfo *pkg, struct cyclesofarlink *sofar) {
  /* Cycle breaking works recursively down the package dependency
   * tree.  `sofar' is the list of packages we've descended down
   * already - if we encounter any of its packages again in a
   * dependency we have found a cycle.
   */
  struct cyclesofarlink thislink, *sol;
  struct dependency *dep;
  struct deppossi *possi, *providelink;
  struct pkginfo *provider;

  if (pkg->color == black)
    return 0;
  pkg->color = gray;
  
  if (f_debug & dbg_depcondetail) {
    fprintf(stderr,"D0%05o: findbreakcyclerecursive %s ",dbg_depcondetail,pkg->name);
    for (sol=sofar; sol; sol=sol->back) fprintf(stderr," <- %s",sol->pkg->name);
    fprintf(stderr,"\n");
  }
  thislink.pkg= pkg;
  thislink.back= sofar;
  thislink.possi= 0;
  for (dep= pkg->installed.depends; dep; dep= dep->next) {
    if (dep->type != dep_depends && dep->type != dep_predepends) continue;
    for (possi= dep->list; possi; possi= possi->next) {
      /* Don't find the same cycles again. */
      if (possi->cyclebreak) continue;
      thislink.possi= possi;
      if (foundcyclebroken(&thislink,sofar,possi->ed,possi)) return 1;
      /* Right, now we try all the providers ... */
      for (providelink= possi->ed->installed.depended;
           providelink;
           providelink= providelink->nextrev) {
        if (providelink->up->type != dep_provides) continue;
        provider= providelink->up->up;
        if (provider->clientdata->istobe == itb_normal) continue;
        /* We don't break things at `provides' links, so `possi' is
         * still the one we use.
         */
        if (foundcyclebroken(&thislink,sofar,provider,possi)) return 1;
	if (foundcyclebroken(&thislink,sofar,possi->ed,provider->installed.depended)) return 1;
      }
    }
  }
  /* Nope, we didn't find a cycle to break. */
  pkg->color = black;
  return 0;
}

int findbreakcycle(struct pkginfo *pkg) {
  struct pkgiterator *iter;
  struct pkginfo *tpkg;
	
  /* Clear the visited flag of all packages before we traverse them. */
  for (iter = iterpkgstart(); (tpkg=iterpkgnext(iter)); ) {
    tpkg->color = white;
  }

  return findbreakcyclerecursive(pkg, 0);
}

void describedepcon(struct varbuf *addto, struct dependency *dep) {
  varbufaddstr(addto,dep->up->name);
  switch (dep->type) {
  case dep_depends:     varbufaddstr(addto, _(" depends on "));     break;
  case dep_predepends:  varbufaddstr(addto, _(" pre-depends on ")); break;
  case dep_recommends:  varbufaddstr(addto, _(" recommends "));     break;
  case dep_conflicts:   varbufaddstr(addto, _(" conflicts with ")); break;
  case dep_suggests:    varbufaddstr(addto, _(" suggests ")); break;
  case dep_enhances:    varbufaddstr(addto, _(" enhances "));       break;
  default:              internerr("unknown deptype");
  }
  varbufdependency(addto, dep);
}
  
int depisok(struct dependency *dep, struct varbuf *whynot,
            struct pkginfo **canfixbyremove, int allowunconfigd) {
  /* *whynot must already have been initialised; it need not be
   * empty though - it will be reset before use.
   * If depisok returns 0 for `not OK' it will contain a description,
   * newline-terminated BUT NOT NULL-TERMINATED, of the reason.
   * If depisok returns 1 it will contain garbage.
   * allowunconfigd should be non-zero during the `Pre-Depends' checking
   * before a package is unpacked, when it is sufficient for the package
   * to be unpacked provided that both the unpacked and previously-configured
   * versions are acceptable.
   */
  struct deppossi *possi;
  struct deppossi *provider;
  int nconflicts;

  /* Use this buffer so that when internationalisation comes along we
   * don't have to rewrite the code completely, only redo the sprintf strings
   * (assuming we have the fancy argument-number-specifiers).
   * Allow 250x3 for package names, versions, &c, + 250 for ourselves.
   */
  char linebuf[1024];

  assert(dep->type == dep_depends || dep->type == dep_predepends ||
         dep->type == dep_conflicts || dep->type == dep_recommends ||
	 dep->type == dep_suggests || dep->type == dep_enhances );
  
  /* The dependency is always OK if we're trying to remove the depend*ing*
   * package.
   */
  switch (dep->up->clientdata->istobe) {
  case itb_remove: case itb_deconfigure:
    return 1;
  case itb_normal:
    /* Only `installed' packages can be make dependency problems */
    switch (dep->up->status) {
    case stat_installed:
      break;
    case stat_notinstalled: case stat_configfiles: case stat_halfinstalled:
    case stat_halfconfigured: case stat_unpacked:
      return 1;
    default:
      internerr("unknown status depending");
    }
    break;
  case itb_installnew: case itb_preinstall:
    break;
  default:
    internerr("unknown istobe depending");
  }

  /* Describe the dependency, in case we have to moan about it. */
  varbufreset(whynot);
  varbufaddc(whynot, ' ');
  describedepcon(whynot, dep);
  varbufaddc(whynot,'\n');
  
  /* TODO: check dep_enhances as well (WTA) */
  if (dep->type == dep_depends || dep->type == dep_predepends ||
      dep->type == dep_recommends || dep->type == dep_suggests ) {
    
    /* Go through the alternatives.  As soon as we find one that
     * we like, we return `1' straight away.  Otherwise, when we get to
     * the end we'll have accumulated all the reasons in whynot and
     * can return `0'.
     */

    for (possi= dep->list; possi; possi= possi->next) {
      switch (possi->ed->clientdata->istobe) {
      case itb_remove:
        sprintf(linebuf,_("  %.250s is to be removed.\n"),possi->ed->name);
        break;
      case itb_deconfigure:
        sprintf(linebuf,_("  %.250s is to be deconfigured.\n"),possi->ed->name);
        break;
      case itb_installnew:
        if (versionsatisfied(&possi->ed->available,possi)) return 1;
        sprintf(linebuf,_("  %.250s is to be installed, but is version %.250s.\n"),
                possi->ed->name,
                versiondescribe(&possi->ed->available.version,vdew_nonambig));
        break;
      case itb_normal: case itb_preinstall:
        switch (possi->ed->status) {
        case stat_installed:
          if (versionsatisfied(&possi->ed->installed,possi)) return 1;
          sprintf(linebuf,_("  %.250s is installed, but is version %.250s.\n"),
                  possi->ed->name,
                  versiondescribe(&possi->ed->installed.version,vdew_nonambig));
          break;
        case stat_notinstalled:
          /* Don't say anything about this yet - it might be a virtual package.
           * Later on, if nothing has put anything in linebuf, we know that it
           * isn't and issue a diagnostic then.
           */
          *linebuf= 0;
          break;
        case stat_unpacked:
        case stat_halfconfigured:
          if (allowunconfigd) {
            if (!informativeversion(&possi->ed->configversion)) {
              sprintf(linebuf, _("  %.250s is unpacked, but has never been configured.\n"),
                      possi->ed->name);
              break;
            } else if (!versionsatisfied(&possi->ed->installed, possi)) {
              sprintf(linebuf, _("  %.250s is unpacked, but is version %.250s.\n"),
                      possi->ed->name,
                      versiondescribe(&possi->ed->available.version,vdew_nonambig));
              break;
            } else if (!versionsatisfied3(&possi->ed->configversion,
                                          &possi->version,possi->verrel)) {
              sprintf(linebuf, _("  %.250s latest configured version is %.250s.\n"),
                      possi->ed->name,
                      versiondescribe(&possi->ed->configversion,vdew_nonambig));
              break;
            } else {
              return 1;
            }
          }
        default:
          sprintf(linebuf, _("  %.250s is %s.\n"),
                  possi->ed->name, gettext(statusstrings[possi->ed->status]));
          break;
        }
        break;
      default:
        internerr("unknown istobe depended");
      }
      varbufaddstr(whynot, linebuf);

      /* If there was no version specified we try looking for Providers. */
      if (possi->verrel == dvr_none) {
        
        /* See if the package we're about to install Provides it. */
        for (provider= possi->ed->available.depended;
             provider;
             provider= provider->nextrev) {
          if (provider->up->type != dep_provides) continue;
          if (provider->up->up->clientdata->istobe == itb_installnew) return 1;
        }

        /* Now look at the packages already on the system. */
        for (provider= possi->ed->installed.depended;
             provider;
             provider= provider->nextrev) {
          if (provider->up->type != dep_provides) continue;
          
          switch (provider->up->up->clientdata->istobe) {
          case itb_installnew:
            /* Don't pay any attention to the Provides field of the
             * currently-installed version of the package we're trying
             * to install.  We dealt with that by using the available
             * information above.
             */
            continue; 
          case itb_remove:
            sprintf(linebuf, _("  %.250s provides %.250s but is to be removed.\n"),
                    provider->up->up->name, possi->ed->name);
            break;
          case itb_deconfigure:
            sprintf(linebuf, _("  %.250s provides %.250s but is to be deconfigured.\n"),
                    provider->up->up->name, possi->ed->name);
            break;
          case itb_normal: case itb_preinstall:
            if (provider->up->up->status == stat_installed) return 1;
            sprintf(linebuf, _("  %.250s provides %.250s but is %s.\n"),
                    provider->up->up->name, possi->ed->name,
                    gettext(statusstrings[provider->up->up->status]));
            break;
          default:
            internerr("unknown istobe provider");
          }
          varbufaddstr(whynot, linebuf);
        }
        
        if (!*linebuf) {
          /* If the package wasn't installed at all, and we haven't said
           * yet why this isn't satisfied, we should say so now.
           */
          sprintf(linebuf, _("  %.250s is not installed.\n"), possi->ed->name);
          varbufaddstr(whynot, linebuf);
        }
      }
    }

    if (canfixbyremove) *canfixbyremove= 0;
    return 0;

  } else {
    
    /* It's a conflict.  There's only one main alternative,
     * but we also have to consider Providers.  We return `0' as soon
     * as we find something that matches the conflict, and only describe
     * it then.  If we get to the end without finding anything we return `1'.
     */

    possi= dep->list;
    nconflicts= 0;

    if (possi->ed != possi->up->up) {
      /* If the package conflicts with itself it must mean that it conflicts
       * with other packages which provide the same virtual name.  We therefore
       * don't look at the real package and go on to the virtual ones.
       */
      
      switch (possi->ed->clientdata->istobe) {
      case itb_remove:
        break;
      case itb_installnew:
        if (!versionsatisfied(&possi->ed->available, possi)) break;
        sprintf(linebuf, _("  %.250s (version %.250s) is to be installed.\n"),
                possi->ed->name,
                versiondescribe(&possi->ed->available.version,vdew_nonambig));
        varbufaddstr(whynot, linebuf);
        if (!canfixbyremove) return 0;
        nconflicts++;
        *canfixbyremove= possi->ed;
        break;
      case itb_normal: case itb_deconfigure: case itb_preinstall:
        switch (possi->ed->status) {
        case stat_notinstalled: case stat_configfiles:
          break;
        default:
          if (!versionsatisfied(&possi->ed->installed, possi)) break;
          sprintf(linebuf, _("  %.250s (version %.250s) is %s.\n"),
                  possi->ed->name,
                  versiondescribe(&possi->ed->installed.version,vdew_nonambig),
                  gettext(statusstrings[possi->ed->status]));
          varbufaddstr(whynot, linebuf);
          if (!canfixbyremove) return 0;
          nconflicts++;
          *canfixbyremove= possi->ed;
        }
        break;
      default:
        internerr("unknown istobe conflict");
      }
    }

    /* If there was no version specified we try looking for Providers. */
    if (possi->verrel == dvr_none) {
        
      /* See if the package we're about to install Provides it. */
      for (provider= possi->ed->available.depended;
           provider;
           provider= provider->nextrev) {
        if (provider->up->type != dep_provides) continue;
        if (provider->up->up->clientdata->istobe != itb_installnew) continue;
        if (provider->up->up == dep->up) continue; /* conflicts and provides the same */
        sprintf(linebuf, _("  %.250s provides %.250s and is to be installed.\n"),
                provider->up->up->name, possi->ed->name);
        varbufaddstr(whynot, linebuf);
        /* We can't remove the one we're about to install: */
        if (canfixbyremove) *canfixbyremove= 0;
        return 0;
      }

      /* Now look at the packages already on the system. */
      for (provider= possi->ed->installed.depended;
           provider;
           provider= provider->nextrev) {
        if (provider->up->type != dep_provides) continue;
          
        if (provider->up->up == dep->up) continue; /* conflicts and provides the same */
        
        switch (provider->up->up->clientdata->istobe) {
        case itb_installnew:
          /* Don't pay any attention to the Provides field of the
           * currently-installed version of the package we're trying
           * to install.  We dealt with that package by using the
           * available information above.
           */
          continue; 
        case itb_remove:
          continue;
        case itb_normal: case itb_deconfigure: case itb_preinstall:
          switch (provider->up->up->status) {
          case stat_notinstalled: case stat_configfiles:
            continue;
          default:
            sprintf(linebuf, _("  %.250s provides %.250s and is %s.\n"),
                    provider->up->up->name, possi->ed->name,
                    gettext(statusstrings[provider->up->up->status]));
            varbufaddstr(whynot, linebuf);
            if (!canfixbyremove) return 0;
            nconflicts++;
            *canfixbyremove= provider->up->up;
            break;
          }
          break;
        default:
          internerr("unknown istobe conflict provider");
        }
      }
    }

    if (!nconflicts) return 1;
    if (nconflicts>1) *canfixbyremove= 0;
    return 0;

  } /* if (dependency) {...} else {...} */
}
