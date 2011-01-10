/*
 * dpkg - main program for package management
 * packages.c - common to actions that process packages
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

#include <sys/types.h>
#include <sys/stat.h>

#include <assert.h>
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg-list.h>
#include <dpkg/pkg-queue.h>
#include <dpkg/myopt.h>

#include "filesdb.h"
#include "main.h"

static struct pkginfo *progress_bytrigproc;
static struct pkg_queue queue = PKG_QUEUE_INIT;

int sincenothing = 0, dependtry = 0;

void
add_to_queue(struct pkginfo *pkg)
{
  pkg_queue_push(&queue, pkg);
}

static void
enqueue_pending(void)
{
  struct pkgiterator *it;
  struct pkginfo *pkg;

  it = pkg_db_iter_new();
  while ((pkg = pkg_db_iter_next(it)) != NULL) {
    switch (cipaction->arg) {
    case act_configure:
      if (!(pkg->status == stat_unpacked ||
            pkg->status == stat_halfconfigured ||
            pkg->trigpend_head))
        continue;
      if (pkg->want != want_install)
        continue;
      break;
    case act_triggers:
      if (!pkg->trigpend_head)
        continue;
      if (pkg->want != want_install)
        continue;
      break;
    case act_remove:
    case act_purge:
      if (pkg->want != want_purge) {
        if (pkg->want != want_deinstall)
          continue;
        if (pkg->status == stat_configfiles)
          continue;
      }
      if (pkg->status == stat_notinstalled)
        continue;
      break;
    default:
      internerr("unknown action '%d'", cipaction->arg);
    }
    add_to_queue(pkg);
  }
  pkg_db_iter_free(it);
}

static void
enqueue_specified(const char *const *argv)
{
  const char *thisarg;

  while ((thisarg = *argv++) != NULL) {
    struct pkginfo *pkg;

    pkg = pkg_db_find(thisarg);
    if (pkg->status == stat_notinstalled) {
      size_t l = strlen(pkg->name);
      const char *extension = pkg->name + l - sizeof(DEBEXT) + 1;

      if (l >= sizeof(DEBEXT) && strcmp(extension, DEBEXT) == 0)
        badusage(_("you must specify packages by their own names,"
                   " not by quoting the names of the files they come in"));
    }
    add_to_queue(pkg);
  }
}

void
packages(const char *const *argv)
{
  trigproc_install_hooks();

  modstatdb_init(admindir,
                 f_noact ?    msdbrw_readonly
               : fc_nonroot ? msdbrw_write
               :              msdbrw_needsuperuser);
  checkpath();
  log_message("startup packages %s", cipaction->olong);

  if (f_pending) {
    if (*argv)
      badusage(_("--%s --pending does not take any non-option arguments"),cipaction->olong);

    enqueue_pending();
  } else {
    if (!*argv)
      badusage(_("--%s needs at least one package name argument"), cipaction->olong);

    enqueue_specified(argv);
  }

  ensure_diversions();

  process_queue();
  trigproc_run_deferred();

  modstatdb_shutdown();
}

void process_queue(void) {
  struct pkg_list *rundown;
  struct pkginfo *volatile pkg;
  volatile enum action action_todo;
  jmp_buf ejbuf;
  enum istobes istobe= itb_normal;

  if (abort_processing)
    return;

  clear_istobes();

  switch (cipaction->arg) {
  case act_triggers:
  case act_configure: case act_install:  istobe= itb_installnew;  break;
  case act_remove: case act_purge:       istobe= itb_remove;      break;
  default:
    internerr("unknown action '%d'", cipaction->arg);
  }
  for (rundown = queue.head; rundown; rundown = rundown->next) {
    ensure_package_clientdata(rundown->pkg);
    if (rundown->pkg->clientdata->istobe == istobe) {
      /* Erase the queue entry - this is a second copy! */
      switch (cipaction->arg) {
      case act_triggers:
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
        internerr("unknown action '%d'", cipaction->arg);
      }
      rundown->pkg = NULL;
   } else {
      rundown->pkg->clientdata->istobe= istobe;
    }
  }

  while (!pkg_queue_is_empty(&queue)) {
    pkg = pkg_queue_pop(&queue);
    if (!pkg)
      continue; /* Duplicate, which we removed earlier. */

    action_todo = cipaction->arg;

    if (sincenothing++ > queue.length * 2 + 2) {
      if (progress_bytrigproc && progress_bytrigproc->trigpend_head) {
        add_to_queue(pkg);
        pkg = progress_bytrigproc;
        action_todo = act_configure;
      } else {
        dependtry++;
        sincenothing = 0;
        assert(dependtry <= 4);
      }
    }

    assert(pkg->status <= stat_installed);

    if (setjmp(ejbuf)) {
      /* Give up on it from the point of view of other packages, i.e. reset
       * istobe. */
      pkg->clientdata->istobe= itb_normal;

      pop_error_context(ehflag_bombout);
      if (abort_processing)
        return;
      continue;
    }
    push_error_context_jump(&ejbuf, print_error_perpackage, pkg->name);

    switch (action_todo) {
    case act_triggers:
      if (!pkg->trigpend_head)
        ohshit(_("package %.250s is not ready for trigger processing\n"
                 " (current status `%.250s' with no pending triggers)"),
               pkg->name, statusinfos[pkg->status].name);
      /* Fall through. */
    case act_install:
      /* Don't try to configure pkgs that we've just disappeared. */
      if (pkg->status == stat_notinstalled)
        break;
      /* Fall through. */
    case act_configure:
      /* Do whatever is most needed. */
      if (pkg->trigpend_head)
        trigproc(pkg);
      else
        deferred_configure(pkg);
      break;
    case act_remove: case act_purge:
      deferred_remove(pkg);
      break;
    default:
      internerr("unknown action '%d'", cipaction->arg);
    }
    m_output(stdout, _("<standard output>"));
    m_output(stderr, _("<standard error>"));

    pop_error_context(ehflag_normaltidy);
  }
  assert(!queue.length);
}

/*** Dependency processing - common to --configure and --remove. ***/

/*
 * The algorithm for deciding what to configure or remove first is as
 * follows:
 *
 * Loop through all packages doing a ‘try 1’ until we've been round and
 * nothing has been done, then do ‘try 2’ and ‘try 3’ likewise.
 *
 * When configuring, in each try we check to see whether all
 * dependencies of this package are done. If so we do it. If some of
 * the dependencies aren't done yet but will be later we defer the
 * package, otherwise it is an error.
 *
 * When removing, in each try we check to see whether there are any
 * packages that would have dependencies missing if we removed this
 * one. If not we remove it now. If some of these packages are
 * themselves scheduled for removal we defer the package until they
 * have been done.
 *
 * The criteria for satisfying a dependency vary with the various
 * tries. In try 1 we treat the dependencies as absolute. In try 2 we
 * check break any cycles in the dependency graph involving the package
 * we are trying to process before trying to process the package
 * normally. In try 3 (which should only be reached if
 * --force-depends-version is set) we ignore version number clauses in
 * Depends lines. In try 4 (only reached if --force-depends is set) we
 * say "ok" regardless.
 *
 * If we are configuring and one of the packages we depend on is
 * awaiting configuration but wasn't specified in the argument list we
 * will add it to the argument list if --configure-any is specified.
 * In this case we note this as having "done something" so that we
 * don't needlessly escalate to higher levels of dependency checking
 * and breaking.
 */

enum found_status {
  found_none = 0,
  found_defer = 1,
  found_forced = 2,
  found_ok = 3,
};

/*
 * Return values:
 *   0: cannot be satisfied.
 *   1: defer: may be satisfied later, when other packages are better or
 *      at higher dependtry due to --force
 *      will set *fixbytrig to package whose trigger processing would help
 *      if applicable (and leave it alone otherwise).
 *   2: not satisfied but forcing
 *      (*interestingwarnings >= 0 on exit? caller is to print oemsgs).
 *   3: satisfied now.
 */
static enum found_status
deppossi_ok_found(struct pkginfo *possdependee, struct pkginfo *requiredby,
                  struct pkginfo *removing, struct pkginfo *providing,
                  struct pkginfo **fixbytrig,
                  bool *matched, struct deppossi *checkversion,
                  int *interestingwarnings, struct varbuf *oemsgs)
{
  enum found_status thisf;

  if (ignore_depends(possdependee)) {
    debug(dbg_depcondetail,"      ignoring depended package so ok and found");
    return found_ok;
  }
  thisf = found_none;
  if (possdependee == removing) {
    if (providing) {
      varbufprintf(oemsgs,
		   _("  Package %s which provides %s is to be removed.\n"),
		   possdependee->name, providing->name);
    } else {
      varbufprintf(oemsgs, _("  Package %s is to be removed.\n"),
		   possdependee->name);
    }

    *matched = true;
    if (fc_depends)
      thisf = (dependtry >= 4) ? found_forced : found_defer;
    debug(dbg_depcondetail,"      removing possdependee, returning %d",thisf);
    return thisf;
  }
  switch (possdependee->status) {
  case stat_unpacked:
  case stat_halfconfigured:
  case stat_triggersawaited:
  case stat_triggerspending:
  case stat_installed:
    if (checkversion && !versionsatisfied(&possdependee->installed,checkversion)) {
      varbufprintf(oemsgs, _("  Version of %s on system is %s.\n"),
		   possdependee->name,
		   versiondescribe(&possdependee->installed.version,
				   vdew_nonambig));
      assert(checkversion->verrel != dvr_none);
      if (fc_depends || fc_dependsversion)
        thisf = (dependtry >= 3) ? found_forced : found_defer;
      debug(dbg_depcondetail,"      bad version, returning %d",thisf);
      (*interestingwarnings)++;
      return thisf;
    }
    if (possdependee->status == stat_installed ||
        possdependee->status == stat_triggerspending) {
      debug(dbg_depcondetail,"      is installed, ok and found");
      return found_ok;
    }
    if (possdependee->status == stat_triggersawaited) {
      assert(possdependee->trigaw.head);
      if (removing || !(f_triggers ||
                        possdependee->clientdata->istobe == itb_installnew)) {
        if (providing) {
          varbufprintf(oemsgs,
                       _("  Package %s which provides %s awaits trigger processing.\n"),
                       possdependee->name, providing->name);
        } else {
          varbufprintf(oemsgs,
                       _("  Package %s awaits trigger processing.\n"),
                       possdependee->name);
        }
        debug(dbg_depcondetail, "      triggers-awaited, no fixbytrig");
        goto unsuitable;
      }
      /* We don't check the status of trigaw.head->pend here, just in case
       * we get into the pathological situation where Triggers-Awaited but
       * the named package doesn't actually have any pending triggers. In
       * that case we queue the non-pending package for trigger processing
       * anyway, and that trigger processing will be a noop except for
       * sorting out all of the packages which name it in Triggers-Awaited.
       *
       * (This situation can only arise if modstatdb_note success in
       * clearing the triggers-pending status of the pending package
       * but then fails to go on to update the awaiters.) */
      *fixbytrig = possdependee->trigaw.head->pend;
      debug(dbg_depcondetail,
            "      triggers-awaited, fixbytrig '%s', defer",
            (*fixbytrig)->name);
      return found_defer;
    }
    if (possdependee->clientdata &&
        possdependee->clientdata->istobe == itb_installnew) {
      debug(dbg_depcondetail,"      unpacked/halfconfigured, defer");
      return found_defer;
    } else if (!removing && fc_configureany &&
               !skip_due_to_hold(possdependee) &&
               !(possdependee->status == stat_halfconfigured)) {
      fprintf(stderr,
              _("dpkg: also configuring `%s' (required by `%s')\n"),
              possdependee->name, requiredby->name);
      add_to_queue(possdependee);
      sincenothing = 0;
      return found_defer;
    } else {
      if (providing) {
	varbufprintf(oemsgs,
		     _("  Package %s which provides %s is not configured yet.\n"),
		     possdependee->name, providing->name);
      } else {
	varbufprintf(oemsgs, _("  Package %s is not configured yet.\n"),
		     possdependee->name);
      }

      debug(dbg_depcondetail, "      not configured/able");
      goto unsuitable;
    }

  default:
    if (providing) {
      varbufprintf(oemsgs,
		   _("  Package %s which provides %s is not installed.\n"),
		   possdependee->name, providing->name);
    } else {
      varbufprintf(oemsgs, _("  Package %s is not installed.\n"),
		   possdependee->name);
    }

    debug(dbg_depcondetail, "      not installed");
    goto unsuitable;
  }

unsuitable:
  if (fc_depends)
    thisf = (dependtry >= 4) ? found_forced : found_defer;

  debug(dbg_depcondetail, "        returning %d", thisf);
  (*interestingwarnings)++;

  return thisf;
}

static void
breaks_check_one(struct varbuf *aemsgs, enum dep_check *ok,
                 struct deppossi *breaks, struct pkginfo *broken,
                 struct pkginfo *breaker, struct pkginfo *virtbroken)
{
  struct varbuf depmsg = VARBUF_INIT;

  debug(dbg_depcondetail, "      checking breaker %s virtbroken %s",
        breaker->name, virtbroken ? virtbroken->name : "<none>");

  if (breaker->status == stat_notinstalled ||
      breaker->status == stat_configfiles) return;
  if (broken == breaker) return;
  if (!versionsatisfied(&broken->installed, breaks)) return;
  if (ignore_depends(breaker)) return;
  if (virtbroken && ignore_depends(virtbroken)) return;

  varbufdependency(&depmsg, breaks->up);
  varbuf_add_char(&depmsg, '\0');
  varbufprintf(aemsgs, _(" %s (%s) breaks %s and is %s.\n"),
               breaker->name,
               versiondescribe(&breaker->installed.version, vdew_nonambig),
               depmsg.buf,
               gettext(statusstrings[breaker->status]));
  varbuf_destroy(&depmsg);

  if (virtbroken) {
    varbufprintf(aemsgs, _("  %s (%s) provides %s.\n"),
                 broken->name,
                 versiondescribe(&broken->installed.version, vdew_nonambig),
                 virtbroken->name);
  } else if (breaks->verrel != dvr_none) {
    varbufprintf(aemsgs, _("  Version of %s to be configured is %s.\n"),
                 broken->name,
                 versiondescribe(&broken->installed.version, vdew_nonambig));
    if (fc_dependsversion) return;
  }
  if (force_breaks(breaks)) return;
  *ok = dep_check_halt;
}

static void
breaks_check_target(struct varbuf *aemsgs, enum dep_check *ok,
                    struct pkginfo *broken, struct pkginfo *target,
                    struct pkginfo *virtbroken)
{
  struct deppossi *possi;

  for (possi = target->installed.depended; possi; possi = possi->rev_next) {
    if (possi->up->type != dep_breaks) continue;
    if (virtbroken && possi->verrel != dvr_none) continue;
    breaks_check_one(aemsgs, ok, possi, broken, possi->up->up, virtbroken);
  }
}

enum dep_check
breakses_ok(struct pkginfo *pkg, struct varbuf *aemsgs)
{
  struct dependency *dep;
  struct pkginfo *virtbroken;
  enum dep_check ok = dep_check_ok;

  debug(dbg_depcon, "    checking Breaks");

  breaks_check_target(aemsgs, &ok, pkg, pkg, NULL);

  for (dep= pkg->installed.depends; dep; dep= dep->next) {
    if (dep->type != dep_provides) continue;
    virtbroken= dep->list->ed;
    debug(dbg_depcondetail, "     checking virtbroken %s", virtbroken->name);
    breaks_check_target(aemsgs, &ok, pkg, virtbroken, virtbroken);
  }
  return ok;
}

/*
 * Checks [Pre]-Depends only.
 */
enum dep_check
dependencies_ok(struct pkginfo *pkg, struct pkginfo *removing,
                struct varbuf *aemsgs)
{
  /* Valid values: 2 = ok, 1 = defer, 0 = halt. */
  enum dep_check ok;
  /* Valid values: 0 = none, 1 = defer, 2 = withwarning, 3 = ok. */
  enum found_status found, thisf;
  int interestingwarnings;
  bool matched, anycannotfixbytrig;
  struct varbuf oemsgs = VARBUF_INIT;
  struct dependency *dep;
  struct deppossi *possi, *provider;
  struct pkginfo *possfixbytrig, *canfixbytrig;

  interestingwarnings= 0;
  ok = dep_check_ok;
  debug(dbg_depcon,"checking dependencies of %s (- %s)",
        pkg->name, removing ? removing->name : "<none>");

  anycannotfixbytrig = false;
  canfixbytrig = NULL;
  for (dep= pkg->installed.depends; dep; dep= dep->next) {
    if (dep->type != dep_depends && dep->type != dep_predepends) continue;
    debug(dbg_depcondetail,"  checking group ...");
    matched = false;
    varbuf_reset(&oemsgs);
    found = found_none;
    possfixbytrig = NULL;
    for (possi = dep->list; found != found_ok && possi; possi = possi->next) {
      debug(dbg_depcondetail,"    checking possibility  -> %s",possi->ed->name);
      if (possi->cyclebreak) {
        debug(dbg_depcondetail,"      break cycle so ok and found");
        found = found_ok;
        break;
      }
      thisf = deppossi_ok_found(possi->ed, pkg, removing, NULL,
                                &possfixbytrig,
                               &matched,possi,&interestingwarnings,&oemsgs);
      if (thisf > found) found= thisf;
      if (found != found_ok && possi->verrel == dvr_none) {
        for (provider = possi->ed->installed.depended;
             found != found_ok && provider;
             provider = provider->rev_next) {
          if (provider->up->type != dep_provides)
            continue;
          debug(dbg_depcondetail, "     checking provider %s",
                provider->up->up->name);
          thisf = deppossi_ok_found(provider->up->up, pkg, removing, possi->ed,
                                    &possfixbytrig, &matched, NULL,
                                    &interestingwarnings, &oemsgs);
          if (thisf > found)
            found = thisf;
        }
      }
      debug(dbg_depcondetail,"    found %d",found);
      if (thisf > found) found= thisf;
    }
    debug(dbg_depcondetail, "  found %d matched %d possfixbytrig %s",
          found, matched, possfixbytrig ? possfixbytrig->name : "-");
    if (removing && !matched) continue;
    switch (found) {
    case found_none:
      anycannotfixbytrig = true;
      ok = dep_check_halt;
    case found_forced:
      varbufaddstr(aemsgs, " ");
      varbufaddstr(aemsgs, pkg->name);
      varbufaddstr(aemsgs, _(" depends on "));
      varbufdependency(aemsgs, dep);
      if (interestingwarnings) {
        /* Don't print the line about the package to be removed if
         * that's the only line. */
        varbufaddstr(aemsgs, _("; however:\n"));
        varbuf_add_char(&oemsgs, '\0');
        varbufaddstr(aemsgs, oemsgs.buf);
      } else {
        varbufaddstr(aemsgs, ".\n");
      }
      break;
    case found_defer:
      if (possfixbytrig)
        canfixbytrig = possfixbytrig;
      else
        anycannotfixbytrig = true;
      if (ok > dep_check_defer)
        ok = dep_check_defer;
      break;
    case found_ok:
      break;
    default:
      internerr("unknown value for found '%d'", found);
    }
  }
  if (ok == dep_check_halt &&
      (pkg->clientdata && pkg->clientdata->istobe == itb_remove))
    ok = dep_check_defer;
  if (!anycannotfixbytrig && canfixbytrig)
    progress_bytrigproc = canfixbytrig;

  varbuf_destroy(&oemsgs);
  debug(dbg_depcon,"ok %d msgs >>%.*s<<", ok, (int)aemsgs->used, aemsgs->buf);
  return ok;
}
