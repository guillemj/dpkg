/*
 * dpkg-split - splitting and joining of multipart *.deb archives
 * split.c - splitting archives
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
#include <stdlib.h>
#include <limits.h>
#include <assert.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include "dpkg-split.h"

void do_split(const char *const *argv) {
  const char *sourcefile, *prefix;
  char *palloc;
  int l, fd;
  char partsizebuf[30], lengthbuf[30], partsizeallowbuf[30];
  struct stat stab;

  sourcefile= *argv++;
  if (!sourcefile)
    badusage(_("--split needs a source filename argument"));
  prefix= *argv++;
  if (prefix && *argv)
    badusage(_("--split takes at most a source filename and destination prefix"));
  if (!prefix) {
    l= strlen(sourcefile);
    palloc= nfmalloc(l+1);
    strcpy(palloc,sourcefile);
    if (!strcmp(palloc+l-(sizeof(DEBEXT)-1),DEBEXT)) {
      l -= (sizeof(DEBEXT)-1);
      palloc[l]= 0;
    }
    prefix= palloc;
  }
  sprintf(partsizebuf,"%ld",maxpartsize-HEADERALLOWANCE);
  sprintf(partsizeallowbuf,"%ld",maxpartsize);
  fd= open(sourcefile,O_RDONLY);
  if (!fd) ohshite(_("unable to open source file `%.250s'"),sourcefile);
  if (fstat(fd,&stab)) ohshite(_("unable to fstat source file"));
  if (!S_ISREG(stab.st_mode)) ohshit(_("source file `%.250s' not a plain file"),sourcefile);
  sprintf(lengthbuf,"%lu",(unsigned long)stab.st_size);
  m_dup2(fd,0);
  execl(MKSPLITSCRIPT,MKSPLITSCRIPT,
        sourcefile,partsizebuf,prefix,lengthbuf,partsizeallowbuf,msdos?"yes":"no",
        NULL);
  ohshite(_("unable to exec mksplit"));
}
