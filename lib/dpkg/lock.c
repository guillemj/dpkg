/*
 * libdpkg - Debian packaging suite library routines
 * lock.c - packages database locking
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

#include <sys/file.h>

#include <assert.h>
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

static void
cu_unlock_file(int argc, void **argv)
{
  int lockfd = *(int*)argv[0];
  struct flock fl;

  assert(lockfd >= 0);
  fl.l_type= F_UNLCK;
  fl.l_whence= SEEK_SET;
  fl.l_start= 0;
  fl.l_len= 0;
  if (fcntl(lockfd, F_SETLK, &fl) == -1)
    ohshite(_("unable to unlock dpkg status database"));
}

void
unlock_file(void)
{
  pop_cleanup(ehflag_normaltidy); /* Calls cu_unlock_file. */
}

/* lockfd must be allocated statically as its addresses is passed to
 * a cleanup handler. */
void
lock_file(int *lockfd, const char *filename,
          const char *emsg, const char *emsg_eagain)
{
  struct flock fl;

  setcloexec(*lockfd, filename);

  fl.l_type = F_WRLCK;
  fl.l_whence = SEEK_SET;
  fl.l_start = 0;
  fl.l_len = 0;

  if (fcntl(*lockfd, emsg_eagain ? F_SETLK : F_SETLKW, &fl) == -1) {
    if (emsg_eagain && (errno == EACCES || errno == EAGAIN))
      ohshit(emsg_eagain);
    ohshite(emsg);
  }

  push_cleanup(cu_unlock_file, ~0, NULL, 0, 1, lockfd);
}

