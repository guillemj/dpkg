/*
 * dpkg - main program for package management
 * trigproc.c - trigger processing
 *
 * Copyright © 2007 Canonical Ltd
 * written by Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008-2013 Guillem Jover <guillem@debian.org>
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

#include <sys/fcntl.h>
#include <sys/stat.h>

#include <assert.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg.h>
#include <dpkg/pkg-queue.h>
#include <dpkg/triglib.h>

#include "main.h"
#include "filesdb.h"
#include "infodb.h"

/*
 * Trigger processing algorithms:
 *
 *
 * There is a separate queue (‘deferred trigproc list’) for triggers
 * ‘relevant’ to what we just did; when we find something triggered ‘now’
 * we add it to that queue (unless --no-triggers).
 *
 *
 * We want to prefer configuring packages where possible to doing
 * trigger processing, but we want to prefer trigger processing to
 * cycle-breaking and dependency forcing. This is achieved as
 * follows:
 *
 * Each time during configure processing where a package D is blocked by
 * only (ie Depends unsatisfied but would be satisfied by) a t-awaiter W
 * we make a note of (one of) W's t-pending, T. (Only the last such T.)
 * (If --no-triggers and nonempty argument list and package isn't in
 * argument list then we don't do this.)
 *
 * Each time in packages.c where we increment dependtry, we instead see
 * if we have encountered such a t-pending T. If we do, we trigproc T
 * instead of incrementing dependtry and this counts as having done
 * something so we reset sincenothing.
 *
 *
 * For --triggers-only and --configure, we go through each thing in the
 * argument queue (the add_to_queue queue) and check what its state is
 * and if appropriate we trigproc it. If we didn't have a queue (or had
 * just --pending) we search all triggers-pending packages and add them
 * to the deferred trigproc list.
 *
 *
 * Before quitting from most operations, we trigproc each package in the
 * deferred trigproc list. This may (if not --no-triggers) of course add
 * new things to the deferred trigproc list.
 *
 *
 * Note that ‘we trigproc T’ must involve trigger cycle detection and
 * also automatic setting of t-awaiters to t-pending or installed. In
 * particular, we do cycle detection even for trigger processing in the
 * configure dependtry loop (and it is OK to do it for explicitly
 * specified packages from the command line arguments; duplicates are
 * removed by packages.c:process_queue).
 */

/*========== Deferred trigger queue. ==========*/

static struct pkg_queue deferred = PKG_QUEUE_INIT;

static void
trigproc_enqueue_deferred(struct pkginfo *pend)
{
	if (f_triggers < 0)
		return;
	ensure_package_clientdata(pend);
	if (pend->clientdata->trigprocdeferred)
		return;
	pend->clientdata->trigprocdeferred = pkg_queue_push(&deferred, pend);
	debug(dbg_triggers, "trigproc_enqueue_deferred pend=%s",
	      pkg_name(pend, pnaw_always));
}

void
trigproc_run_deferred(void)
{
	jmp_buf ejbuf;

	debug(dbg_triggers, "trigproc_run_deferred");
	while (!pkg_queue_is_empty(&deferred)) {
		struct pkginfo *pkg;

		pkg  = pkg_queue_pop(&deferred);
		if (!pkg)
			continue;

		if (setjmp(ejbuf)) {
			pop_error_context(ehflag_bombout);
			continue;
		}
		push_error_context_jump(&ejbuf, print_error_perpackage,
		                        pkg_name(pkg, pnaw_nonambig));

		pkg->clientdata->trigprocdeferred = NULL;
		trigproc(pkg);

		pop_error_context(ehflag_normaltidy);
	}
}

/*
 * Called by modstatdb_note.
 */
void
trig_activate_packageprocessing(struct pkginfo *pkg)
{
	debug(dbg_triggersdetail, "trigproc_activate_packageprocessing pkg=%s",
	      pkg_name(pkg, pnaw_always));

	trig_parse_ci(pkg_infodb_get_file(pkg, &pkg->installed, TRIGGERSCIFILE),
	              NULL, trig_cicb_statuschange_activate,
	              pkg, &pkg->installed);
}

/*========== Actual trigger processing. ==========*/

struct trigcyclenode {
	struct trigcyclenode *next;
	struct trigcycleperpkg *pkgs;
	struct pkginfo *then_processed;
};

struct trigcycleperpkg {
	struct trigcycleperpkg *next;
	struct pkginfo *pkg;
	struct trigpend *then_trigs;
};

static bool tortoise_advance;
static struct trigcyclenode *tortoise, *hare;

void
trigproc_reset_cycle(void)
{
	tortoise_advance = false;
	tortoise = hare = NULL;
}

static bool
tortoise_not_in_hare(struct pkginfo *processing_now,
                     struct trigcycleperpkg *tortoise_pkg)
{
	const char *processing_now_name, *tortoise_name;
	struct trigpend *hare_trig, *tortoise_trig;

	processing_now_name = pkg_name(processing_now, pnaw_nonambig);
	tortoise_name = pkg_name(tortoise_pkg->pkg, pnaw_nonambig);

	debug(dbg_triggersdetail, "%s pnow=%s tortoise=%s", __func__,
	      processing_now_name, tortoise_name);
	for (tortoise_trig = tortoise_pkg->then_trigs;
	     tortoise_trig;
	     tortoise_trig = tortoise_trig->next) {
		debug(dbg_triggersdetail,
		      "%s pnow=%s tortoise=%s tortoisetrig=%s", __func__,
		      processing_now_name, tortoise_name, tortoise_trig->name);

		/* hare is now so we can just look up in the actual data. */
		for (hare_trig = tortoise_pkg->pkg->trigpend_head;
		     hare_trig;
		     hare_trig = hare_trig->next) {
			debug(dbg_triggersstupid, "%s pnow=%s tortoise=%s"
			      " tortoisetrig=%s haretrig=%s", __func__,
			      processing_now_name, tortoise_name,
			      tortoise_trig->name, hare_trig->name);
			if (strcmp(hare_trig->name, tortoise_trig->name) == 0)
				break;
		}

		if (hare_trig == NULL) {
			/* Not found in hare, yay! */
			debug(dbg_triggersdetail, "%s pnow=%s tortoise=%s OK",
			      __func__, processing_now_name, tortoise_name);
			return true;
		}
	}

	return false;
}

/*
 * Returns package we're to give up on.
 */
static struct pkginfo *
check_trigger_cycle(struct pkginfo *processing_now)
{
	struct trigcyclenode *tcn;
	struct trigcycleperpkg *tcpp, *tortoise_pkg;
	struct trigpend *tortoise_trig;
	struct pkgiterator *it;
	struct pkginfo *pkg, *giveup;
	const char *sep;

	debug(dbg_triggers, "check_triggers_cycle pnow=%s",
	      pkg_name(processing_now, pnaw_always));

	tcn = nfmalloc(sizeof(*tcn));
	tcn->pkgs = NULL;
	tcn->then_processed = processing_now;

	it = pkg_db_iter_new();
	while ((pkg = pkg_db_iter_next_pkg(it))) {
		if (!pkg->trigpend_head)
			continue;
		tcpp = nfmalloc(sizeof(*tcpp));
		tcpp->pkg = pkg;
		tcpp->then_trigs = pkg->trigpend_head;
		tcpp->next = tcn->pkgs;
		tcn->pkgs = tcpp;
	}
	pkg_db_iter_free(it);
	if (!hare) {
		debug(dbg_triggersdetail, "check_triggers_cycle pnow=%s first",
		      pkg_name(processing_now, pnaw_always));
		tcn->next = NULL;
		hare = tortoise = tcn;
		return NULL;
	}

	tcn->next = NULL;
	hare->next = tcn;
	hare = tcn;
	if (tortoise_advance)
		tortoise = tortoise->next;
	tortoise_advance = !tortoise_advance;

	/* Now we compare hare to tortoise.
	 * We want to find a trigger pending in tortoise which is not in hare
	 * if we find such a thing we have proved that hare isn't a superset
	 * of tortoise and so that we haven't found a loop (yet). */
	for (tortoise_pkg = tortoise->pkgs;
	     tortoise_pkg;
	     tortoise_pkg = tortoise_pkg->next) {
		if (tortoise_not_in_hare(processing_now, tortoise_pkg))
			return NULL;
	}
	/* Oh dear. hare is a superset of tortoise. We are making no
	 * progress. */
	notice(_("cycle found while processing triggers:\n"
	         " chain of packages whose triggers are or may be responsible:"));
	sep = "  ";
	for (tcn = tortoise; tcn; tcn = tcn->next) {
		fprintf(stderr, "%s%s", sep,
		        pkg_name(tcn->then_processed, pnaw_nonambig));
		sep = " -> ";
	}
	fprintf(stderr, _("\n" " packages' pending triggers which are"
	                  " or may be unresolvable:\n"));
	for (tortoise_pkg = tortoise->pkgs;
	     tortoise_pkg;
	     tortoise_pkg = tortoise_pkg->next) {
		fprintf(stderr, "  %s",
		        pkg_name(tortoise_pkg->pkg, pnaw_nonambig));
		sep = ": ";
		for (tortoise_trig = tortoise_pkg->then_trigs;
		     tortoise_trig;
		     tortoise_trig = tortoise_trig->next) {
			fprintf(stderr, "%s%s", sep, tortoise_trig->name);
		}
		fprintf(stderr, "\n");
	}

	/* We give up on the _earliest_ package involved. */
	giveup = tortoise->pkgs->pkg;
	debug(dbg_triggers, "check_triggers_cycle pnow=%s giveup=%p",
	      pkg_name(processing_now, pnaw_always),
	      pkg_name(giveup, pnaw_always));
	assert(giveup->status == stat_triggersawaited ||
	       giveup->status == stat_triggerspending);
	pkg_set_status(giveup, stat_halfconfigured);
	modstatdb_note(giveup);
	print_error_perpackage(_("triggers looping, abandoned"),
	                       pkg_name(giveup, pnaw_nonambig));

	return giveup;
}

/*
 * Does cycle checking. Doesn't mind if pkg has no triggers pending - in
 * that case does nothing but fix up any stale awaiters.
 */
void
trigproc(struct pkginfo *pkg)
{
	static struct varbuf namesarg;

	struct trigpend *tp;
	struct pkginfo *gaveup;

	debug(dbg_triggers, "trigproc %s", pkg_name(pkg, pnaw_always));

	if (pkg->clientdata->trigprocdeferred)
		pkg->clientdata->trigprocdeferred->pkg = NULL;
	pkg->clientdata->trigprocdeferred = NULL;

	if (pkg->trigpend_head) {
		assert(pkg->status == stat_triggerspending ||
		       pkg->status == stat_triggersawaited);

		gaveup = check_trigger_cycle(pkg);
		if (gaveup == pkg)
			return;

		printf(_("Processing triggers for %s ...\n"),
		       pkg_name(pkg, pnaw_nonambig));
		log_action("trigproc", pkg, &pkg->installed);

		varbuf_reset(&namesarg);
		for (tp = pkg->trigpend_head; tp; tp = tp->next) {
			varbuf_add_char(&namesarg, ' ');
			varbuf_add_str(&namesarg, tp->name);
		}
		varbuf_end_str(&namesarg);

		/* Setting the status to half-configured
		 * causes modstatdb_note to clear pending triggers. */
		pkg_set_status(pkg, stat_halfconfigured);
		modstatdb_note(pkg);

		if (!f_noact) {
			sincenothing = 0;
			maintainer_script_postinst(pkg, "triggered",
			                           namesarg.buf + 1, NULL);
		}

		/* This is to cope if the package triggers itself: */
		if (pkg->trigaw.head)
			pkg_set_status(pkg, stat_triggersawaited);
		else if (pkg->trigpend_head)
			pkg_set_status(pkg, stat_triggerspending);
		else
			pkg_set_status(pkg, stat_installed);
		modstatdb_note(pkg);

		post_postinst_tasks_core(pkg);
	} else {
		/* In other branch is done by modstatdb_note. */
		trig_clear_awaiters(pkg);
	}
}

/*========== Transitional global activation. ==========*/

static void
transitional_interest_callback_ro(const char *trig, struct pkginfo *pkg,
                                  struct pkgbin *pkgbin, enum trig_options opts)
{
	struct pkginfo *pend = pkg;
	struct pkgbin *pendbin = pkgbin;

	debug(dbg_triggersdetail,
	      "trig_transitional_interest_callback trig=%s pend=%s",
	      trig, pkgbin_name(pend, pendbin, pnaw_always));
	if (pend->status >= stat_triggersawaited)
		trig_note_pend(pend, nfstrsave(trig));
}

static void
transitional_interest_callback(const char *trig, struct pkginfo *pkg,
                               struct pkgbin *pkgbin, enum trig_options opts)
{
	struct pkginfo *pend = pkg;
	struct pkgbin *pendbin = pkgbin;

	trig_cicb_interest_add(trig, pend, pendbin, opts);
	transitional_interest_callback_ro(trig, pend, pendbin, opts);
}

/*
 * cstatus might be msdbrw_readonly if we're in --no-act mode, in which
 * case we don't write out all of the interest files etc. but we do
 * invent all of the activations for our own benefit.
 */
static void
trig_transitional_activate(enum modstatdb_rw cstatus)
{
	struct pkgiterator *it;
	struct pkginfo *pkg;

	it = pkg_db_iter_new();
	while ((pkg = pkg_db_iter_next_pkg(it))) {
		if (pkg->status <= stat_halfinstalled)
			continue;
		debug(dbg_triggersdetail, "trig_transitional_activate %s %s",
		      pkg_name(pkg, pnaw_always),
		      statusinfos[pkg->status].name);
		pkg->trigpend_head = NULL;
		trig_parse_ci(pkg_infodb_get_file(pkg, &pkg->installed,
		                                  TRIGGERSCIFILE),
		              cstatus >= msdbrw_write ?
		              transitional_interest_callback :
		              transitional_interest_callback_ro, NULL,
		              pkg, &pkg->installed);
		/* Ensure we're not creating incoherent data that can't
		 * be written down. This should never happen in theory but
		 * can happen if you restore an old status file that is
		 * not in sync with the infodb files. */
		if (pkg->status < stat_triggersawaited)
			continue;

		if (pkg->trigaw.head)
			pkg_set_status(pkg, stat_triggersawaited);
		else if (pkg->trigpend_head)
			pkg_set_status(pkg, stat_triggerspending);
		else
			pkg_set_status(pkg, stat_installed);
	}
	pkg_db_iter_free(it);

	if (cstatus >= msdbrw_write) {
		modstatdb_checkpoint();
		trig_file_interests_save();
	}
}

/*========== Hook setup. ==========*/

static struct filenamenode *
th_proper_nn_find(const char *name, bool nonew)
{
	return findnamenode(name, nonew ? fnn_nonew : 0);
}

TRIGHOOKS_DEFINE_NAMENODE_ACCESSORS

static const struct trig_hooks trig_our_hooks = {
	.enqueue_deferred = trigproc_enqueue_deferred,
	.transitional_activate = trig_transitional_activate,
	.namenode_find = th_proper_nn_find,
	.namenode_interested = th_nn_interested,
	.namenode_name = th_nn_name,
};

void
trigproc_install_hooks(void)
{
	trig_override_hooks(&trig_our_hooks);
}
