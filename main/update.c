/*
 * dpkg - main program for package management
 * update.c - options which update the `available' database
 *
 * Copyright (C) 1995 Ian Jackson <iwj10@cus.cam.ac.uk>
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

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fnmatch.h>
#include <assert.h>
#include <unistd.h>

#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
#include "myopt.h"

#include "main.h"

void availablefrompackages(const char *const *argv, int replace) {
  const char *sourcefile= argv[0];
  int count;
  static struct varbuf vb;
  
  if (!sourcefile || argv[1])
    badusage("--%s needs exactly one Packages file argument", cipaction->olong);
  
  if (!f_noact) {
    if (access(admindir,W_OK)) {
      if (errno != EACCES)
        ohshite("unable to access dpkg status area for bulk available update");
      else
        ohshit("bulk available update requires write access to dpkg status area");
    }
    lockdatabase(admindir);
  }
  
  if (replace) {
    printf("Replacing available packages info, using %s.\n",sourcefile);
  } else {
    printf("Updating available packages info, using %s.\n",sourcefile);
  }

  varbufaddstr(&vb,admindir);
  varbufaddstr(&vb,"/" AVAILFILE);
  varbufaddc(&vb,0);
  
  if (!replace)
    parsedb(vb.buf, pdb_recordavailable|pdb_rejectstatus, 0,0,0);

  count= parsedb(sourcefile, pdb_recordavailable|pdb_rejectstatus, 0,0,0);

  if (!f_noact) {
    writedb(vb.buf,1,0);
    unlockdatabase(admindir);
  }
  
  printf("Information about %d package(s) was updated.\n",count);
}
