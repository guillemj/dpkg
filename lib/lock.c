/*
 * libdpkg - Debian packaging suite library routines
 * lock.c - packages database locking
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

#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <assert.h>
#include <fcntl.h>
#include <sys/file.h>

#include <dpkg.h>
#include <dpkg-db.h>

static int dblockfd= -1;

static void cu_unlockdb(int argc, void **argv) {
  struct flock fl;
  assert(dblockfd >= 0);
  fl.l_type= F_UNLCK;
  fl.l_whence= SEEK_SET;
  fl.l_start= 0;
  fl.l_len= 0;
  if (fcntl(dblockfd,F_SETLK,&fl) == -1)
    ohshite(_("unable to unlock dpkg status database"));
}

void unlockdatabase(const char *admindir) {
  pop_cleanup(ehflag_normaltidy); /* calls cu_unlockdb */
}

void lockdatabase(const char *admindir) {
  int n;
  struct flock fl;
  char *dblockfile= NULL;
  
    n= strlen(admindir);
    dblockfile= m_malloc(n+sizeof(LOCKFILE)+2);
    strcpy(dblockfile,admindir);
    strcpy(dblockfile+n, "/" LOCKFILE);
  if (dblockfd == -1) {
    dblockfd= open(dblockfile, O_RDWR|O_CREAT|O_TRUNC, 0660);
    if (dblockfd == -1) {
      if (errno == EPERM)
        ohshit(_("you do not have permission to lock the dpkg status database"));
      ohshite(_("unable to open/create status database lockfile"));
    }
  }
  fl.l_type= F_WRLCK;
  fl.l_whence= SEEK_SET;
  fl.l_start= 0;
  fl.l_len= 0;
  if (fcntl(dblockfd,F_SETLK,&fl) == -1) {
    if (errno == EACCES || errno == EAGAIN)
      ohshit(_("status database area is locked by another process"));
    ohshite(_("unable to lock dpkg status database"));
  }
  setcloexec(dblockfd, dblockfile);
  free(dblockfile);
  push_cleanup(cu_unlockdb,~0, NULL,0, 0);
}
