/*
 * dpkg - main program for package management
 * trigdeferred.l - parsing of triggers/Deferred
 *
 * Copyright (C) 2007 Canonical Ltd
 * written by Ian Jackson <ian@chiark.greenend.org.uk>
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

%option prefix="trigdef_yy"
/* Reset the name to the default value (instead of using "trigdeferred.c")
 * so that automake (ylwrap) can find it. */
%option outfile="lex.yy.c"
%option noyywrap
%option batch
%option nodefault
%option perf-report
%option warn
%option nounput

%x midline

%{

#include <config.h>

#include <sys/stat.h>
#include <sys/fcntl.h>

#include <dpkg.h>
#include <dpkg-db.h>

static struct varbuf fn, newfn;

%}

%%

[ \t\n]		/* whitespace */
#.*\n		/* comments */
[\x21-\x7e]+	{
	trigdef->trig_begin(trigdef_yytext);
	BEGIN(midline);
	}

<midline>[ \t]	/* whitespace */
<midline>[-0-9a-z][-+.0-9a-z]*	{
	if (trigdef_yytext[0] == '-' && trigdef_yytext[1])
		ohshit(_("invalid package name `%.250s' in triggers deferred "
		         "file `%.250s'"), trigdef_yytext, fn.buf);
	trigdef->package(trigdef_yytext);
	}
<midline>\n|#.*\n	{
	trigdef->trig_end();
	BEGIN(0);
	}
<midline><<EOF>>	{
	ohshit(_("truncated triggers deferred file `%.250s'"), fn.buf);
	}

<*>.	{
	ohshit(_("syntax error in triggers deferred file `%.250s' at "
	         "character `%s'%s"),
	       fn.buf, yytext, YY_START == midline ? " midline": "");
	}

%%

/*---------- Deferred file handling ----------*/

static int lock_fd = -1;
static FILE *old_deferred;

FILE *trig_new_deferred;
const struct trigdefmeths *trigdef;

static void
constructfn(struct varbuf *vb, const char *admindir, const char *tail)
{
	varbufreset(vb);
	varbufaddstr(vb, admindir);
	varbufaddstr(vb, "/" TRIGGERSDIR);
	varbufaddstr(vb, tail);
	varbufaddc(vb, 0);
}

int
trigdef_update_start(enum trigdef_updateflags uf, const char *admindir)
{
	struct stat stab;
	int r;

	if (uf & tduf_write) {
		constructfn(&fn, admindir, TRIGGERSLOCKFILE);
		if (lock_fd == -1) {
			lock_fd = open(fn.buf, O_RDWR | O_CREAT | O_TRUNC, 0600);
			if (lock_fd == -1) {
				if (!(errno == ENOENT && (uf & tduf_nolockok)))
					ohshite(_("unable to open/create "
					          "triggers lockfile `%.250s'"),
					        fn.buf);
				return -1;
			}
		}

		lock_file(&lock_fd, fn.buf, _("unable to lock triggers area"),
		          NULL);
	} else {
		/* Dummy for pop_cleanups. */
		push_cleanup(NULL, 0, NULL, 0, 0);
	}

	constructfn(&fn, admindir, TRIGGERSDEFERREDFILE);
	r = stat(fn.buf, &stab);
	if (r) {
		if (errno != ENOENT)
			ohshite(_("unable to stat triggers deferred file `%.250s'"),
			        fn.buf);
	} else if (!stab.st_size) {
		if (!(uf & tduf_writeifempty)) {
			pop_cleanup(ehflag_normaltidy);
			return -2;
		}
	}

	if (old_deferred)
		fclose(old_deferred);
	old_deferred = fopen(fn.buf, "r");
	if (!old_deferred) {
		if (errno != ENOENT)
			ohshite(_("unable to open triggers deferred file `%.250s'"),
			        fn.buf);
		if (!(uf & tduf_writeifenoent)) {
			pop_cleanup(ehflag_normaltidy);
			return -3;
		}
	}

	if (uf & tduf_write) {
		constructfn(&newfn, admindir, TRIGGERSDEFERREDFILE ".new");
		if (trig_new_deferred)
			fclose(trig_new_deferred);
		trig_new_deferred = fopen(newfn.buf, "w");
		if (!trig_new_deferred)
			ohshite(_("unable to open/create new triggers deferred file `%.250s'"),
			        newfn.buf);
	}

	if (!old_deferred)
		return 1;

	trigdef_yyrestart(old_deferred);
	BEGIN(0);

	return 2;
}

void
trigdef_process_done(void)
{
	int r;

	if (old_deferred) {
		if (ferror(old_deferred))
			ohshite(_("error reading triggers deferred file `%.250s'"),
			        fn.buf);
		fclose(old_deferred);
		old_deferred = NULL;
	}

	if (trig_new_deferred) {
		if (ferror(trig_new_deferred))
			ohshite(_("unable to write new triggers deferred "
			          "file `%.250s'"), newfn.buf);
		r = fclose(trig_new_deferred);
		trig_new_deferred = NULL;
		if (r)
			ohshite(_("unable to close new triggers deferred "
			          "file `%.250s'"), newfn.buf);

		if (rename(newfn.buf, fn.buf))
			ohshite(_("unable to install new triggers deferred "
			          "file `%.250s'"), fn.buf);
	}

	/* Unlock. */
	pop_cleanup(ehflag_normaltidy);
}

