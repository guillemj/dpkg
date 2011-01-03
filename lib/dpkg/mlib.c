/*
 * libdpkg - Debian packaging suite library routines
 * mlib.c - ‘must’ library: routines will succeed or longjmp
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

#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>

void *m_malloc(size_t amount) {
#ifdef MDEBUG
  unsigned short *r2, x;
#endif
  void *r;

  onerr_abort++;
  r= malloc(amount);
  if (!r) ohshite(_("malloc failed (%ld bytes)"),(long)amount);
  onerr_abort--;

#ifdef MDEBUG
  r2= r; x= (unsigned short)amount ^ 0xf000;
  while (amount >= 2) { *r2++= x; amount -= 2; }
#endif
  return r;
}

void *m_realloc(void *r, size_t amount) {
  onerr_abort++;
  r= realloc(r,amount);
  if (!r) ohshite(_("realloc failed (%ld bytes)"),(long)amount);
  onerr_abort--;

  return r;
}

char *
m_strdup(const char *str)
{
  char *new_str;

  onerr_abort++;
  new_str = strdup(str);
  if (!new_str)
    ohshite(_("failed to allocate memory"));
  onerr_abort--;

  return new_str;
}

void m_dup2(int oldfd, int newfd) {
  const char *const stdstrings[]= { "in", "out", "err" };

  if (dup2(oldfd,newfd) == newfd) return;

  onerr_abort++;
  if (newfd < 3) ohshite(_("failed to dup for std%s"),stdstrings[newfd]);
  ohshite(_("failed to dup for fd %d"),newfd);
}

void m_pipe(int *fds) {
  if (!pipe(fds)) return;
  onerr_abort++;
  ohshite(_("failed to create pipe"));
}

void
m_output(FILE *f, const char *name)
{
  fflush(f);
  if (ferror(f))
    ohshite(_("error writing to '%s'"), name);
}

void setcloexec(int fd, const char* fn) {
  int f;

  if ((f=fcntl(fd, F_GETFD))==-1)
    ohshite(_("unable to read filedescriptor flags for %.250s"),fn);
  if (fcntl(fd, F_SETFD, (f|FD_CLOEXEC))==-1)
    ohshite(_("unable to set close-on-exec flag for %.250s"),fn);
}
