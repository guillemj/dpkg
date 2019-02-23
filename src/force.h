/*
 * dpkg - main program for package management
 * force.h - forced operation support
 *
 * Copyright © 1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2006, 2008-2019 Guillem Jover <guillem@debian.org>
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef DPKG_FORCE_H
#define DPKG_FORCE_H

#include <dpkg/dpkg.h>
#include <dpkg/options.h>

extern int fc_architecture;
extern int fc_badpath;
extern int fc_badverify;
extern int fc_badversion;
extern int fc_breaks;
extern int fc_conff_ask;
extern int fc_conff_def;
extern int fc_conff_miss;
extern int fc_conff_new;
extern int fc_conff_old;
extern int fc_configureany;
extern int fc_conflicts;
extern int fc_depends;
extern int fc_dependsversion;
extern int fc_downgrade;
extern int fc_hold;
extern int fc_nonroot;
extern int fc_overwrite;
extern int fc_overwritedir;
extern int fc_overwritediverted;
extern int fc_removeessential;
extern int fc_removereinstreq;
extern int fc_script_chrootless;
extern int fc_unsafe_io;

void
set_force(const struct cmdinfo *cip, const char *value);

void
forcibleerr(int forceflag, const char *format, ...) DPKG_ATTR_PRINTF(2);
int
forcible_nonroot_error(int rc);

#endif /* DPKG_FORCE_H */
