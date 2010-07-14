/*
 * dpkg - main program for package management
 * main.c - main program
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
#include <sys/wait.h>

#include <errno.h>
#include <limits.h>
#include <ctype.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/myopt.h>

#include "main.h"

bool abort_processing = false;

static int nerrs = 0;

struct error_report {
  struct error_report *next;
  const char *what;
};

static struct error_report *reports = NULL;
static struct error_report **lastreport= &reports;
static struct error_report emergency;

void print_error_perpackage(const char *emsg, const char *arg) {
  struct error_report *nr;
  
  fprintf(stderr, _("%s: error processing %s (--%s):\n %s\n"),
          DPKG, arg, cipaction->olong, emsg);

  statusfd_send("status: %s : %s : %s", arg, "error", emsg);

  nr= malloc(sizeof(struct error_report));
  if (!nr) {
    perror(_("dpkg: failed to allocate memory for new entry in list of failed packages."));
    abort_processing = true;
    nr= &emergency;
  }
  nr->what= arg;
  nr->next = NULL;
  *lastreport= nr;
  lastreport= &nr->next;
    
  if (nerrs++ < errabort) return;
  fprintf(stderr, _("dpkg: too many errors, stopping\n"));
  abort_processing = true;
}

int reportbroken_retexitstatus(void) {
  if (reports) {
    fputs(_("Errors were encountered while processing:\n"),stderr);
    while (reports) {
      fprintf(stderr," %s\n",reports->what);
      reports= reports->next;
    }
  }
  if (abort_processing) {
    fputs(_("Processing was halted because there were too many errors.\n"),stderr);
  }
  return nerrs ? 1 : 0;
}

bool
skip_due_to_hold(struct pkginfo *pkg)
{
  if (pkg->want != want_hold)
    return false;
  if (fc_hold) {
    fprintf(stderr, _("Package %s was on hold, processing it anyway as you requested\n"),
            pkg->name);
    return false;
  }
  printf(_("Package %s is on hold, not touching it.  Use --force-hold to override.\n"),
         pkg->name);
  return true;
}

void forcibleerr(int forceflag, const char *fmt, ...) {
  va_list args;

  va_start(args, fmt);
  if (forceflag) {
    warning(_("overriding problem because --force enabled:"));
    fputc(' ', stderr);
    vfprintf(stderr, fmt, args);
    fputc('\n',stderr);
  } else {
    ohshitv(fmt, args);
  }
  va_end(args);
}
