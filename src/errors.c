/*
 * dpkg - main program for package management
 * main.c - main program
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
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <limits.h>
#include <ctype.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>

#include "main.h"

int nerrs= 0;

struct error_report {
  struct error_report *next;
  const char *what;
};

static struct error_report *reports=0;
static struct error_report **lastreport= &reports;
static struct error_report emergency;

extern struct pipef *status_pipes;

void print_error_perpackage(const char *emsg, const char *arg) {
  struct error_report *nr;
  
  fprintf(stderr, _("%s: error processing %s (--%s):\n %s\n"),
          DPKG, arg, cipaction->olong, emsg);

  if (status_pipes) {
     static struct varbuf *status= NULL;
     struct pipef *pipef= status_pipes;
     int r;
     if (status == NULL) {
	status = nfmalloc(sizeof(struct varbuf));
	varbufinit(status);
     } else
	varbufreset(status);

     r= varbufprintf(status, "status: %s : %s : %s\n", arg, "error",emsg);
     while (pipef) {
	write(pipef->fd, status->buf, r);
	pipef= pipef->next;
     }
  }


  nr= malloc(sizeof(struct error_report));
  if (!nr) {
    perror(_("dpkg: failed to allocate memory for new entry in list of failed packages."));
    onerr_abort++;
    nr= &emergency;
  }
  nr->what= arg;
  nr->next= 0;
  *lastreport= nr;
  lastreport= &nr->next;
    
  if (nerrs++ < errabort) return;
  fprintf(stderr, _("dpkg: too many errors, stopping\n"));
  onerr_abort++;
}

int reportbroken_retexitstatus(void) {
  if (reports) {
    fputs(_("Errors were encountered while processing:\n"),stderr);
    while (reports) {
      fprintf(stderr," %s\n",reports->what);
      reports= reports->next;
    }
  }
  if (onerr_abort) {
    fputs(_("Processing was halted because there were too many errors.\n"),stderr);
  }
  return nerrs || onerr_abort ? 1 : 0;
}

int skip_due_to_hold(struct pkginfo *pkg) {
  if (pkg->want != want_hold) return 0;
  if (fc_hold) {
    fprintf(stderr, _("Package %s was on hold, processing it anyway as you request\n"),
            pkg->name);
    return 0;
  }
  printf(_("Package %s is on hold, not touching it.  Use --force-hold to override.\n"),
         pkg->name);
  return 1;
}

void forcibleerr(int forceflag, const char *fmt, ...) {
  va_list al;
  va_start(al,fmt);
  if (forceflag) {
    fputs(_("dpkg - warning, overriding problem because --force enabled:\n "),stderr);
    vfprintf(stderr,fmt,al);
    fputc('\n',stderr);
  } else {
    ohshitv(fmt,al);
  }
  va_end(al);
}
