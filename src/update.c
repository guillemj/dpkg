/*
 * dpkg - main program for package management
 * update.c - options which update the `available' database
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

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fnmatch.h>
#include <assert.h>
#include <unistd.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>

#include "main.h"

void updateavailable(const char *const *argv) {
  const char *sourcefile= argv[0];
  int count= 0;
  static struct varbuf vb;

  switch (cipaction->arg) {
  case act_avclear:
    if (sourcefile) badusage(_("--%s takes no arguments"),cipaction->olong);
    break;
  case act_avreplace: case act_avmerge:
    if (!sourcefile || argv[1])
      badusage(_("--%s needs exactly one Packages file argument"),cipaction->olong);
    break;
  default:
    internerr("bad cipaction->arg in updateavailable");
  }
  
  if (!f_noact) {
    if (access(admindir,W_OK)) {
      if (errno != EACCES)
        ohshite(_("unable to access dpkg status area for bulk available update"));
      else
        ohshit(_("bulk available update requires write access to dpkg status area"));
    }
    lockdatabase(admindir);
  }
  
  switch (cipaction->arg) {
  case act_avreplace:
    printf(_("Replacing available packages info, using %s.\n"),sourcefile);
    break;
  case act_avmerge:
    printf(_("Updating available packages info, using %s.\n"),sourcefile);
    break;
  case act_avclear:
    break;
  default:
    internerr("bad cipaction->arg in update available");
  }

  varbufaddstr(&vb,admindir);
  varbufaddstr(&vb,"/" AVAILFILE);
  varbufaddc(&vb,0);

  if (cipaction->arg == act_avmerge)
    parsedb(vb.buf, pdb_recordavailable|pdb_rejectstatus, 0,0,0);

  if (cipaction->arg != act_avclear)
    count+= parsedb(sourcefile, pdb_recordavailable|pdb_rejectstatus, 0,0,0);

  if (!f_noact) {
    writedb(vb.buf,1,0);
    unlockdatabase(admindir);
  }

  if (cipaction->arg != act_avclear)
    printf(_("Information about %d package(s) was updated.\n"),count);
}

void forgetold(const char *const *argv) {
  struct pkgiterator *it;
  struct pkginfo *pkg;
  enum pkgwant oldwant;

  if (*argv) badusage(_("--forget-old-unavail takes no arguments"));

  modstatdb_init(admindir, f_noact ? msdbrw_readonly : msdbrw_write);

  it= iterpkgstart();
  while ((pkg= iterpkgnext(it))) {
    debug(dbg_eachfile,"forgetold checking %s",pkg->name);
    if (informative(pkg,&pkg->available)) {
      debug(dbg_eachfile,"forgetold ... informative available");
      continue;
    }
    if (pkg->want != want_purge && pkg->want != want_deinstall) {
      debug(dbg_eachfile,"forgetold ... informative want");
      continue;
    }
    oldwant= pkg->want;
    pkg->want= want_unknown;
    if (informative(pkg,&pkg->installed)) {
      debug(dbg_eachfile,"forgetold ... informative installed");
      pkg->want= oldwant;
      continue;
    }
    debug(dbg_general,"forgetold forgetting %s",pkg->name);
  }
  iterpkgend(it);
  
  modstatdb_shutdown();
}
