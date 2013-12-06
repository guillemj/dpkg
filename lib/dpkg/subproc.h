/*
 * libdpkg - Debian packaging suite library routines
 * subproc.h - sub-process handling routines
 *
 * Copyright © 2008 Guillem Jover <guillem@debian.org>
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

#ifndef LIBDPKG_SUBPROC_H
#define LIBDPKG_SUBPROC_H

#include <sys/types.h>

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

/**
 * @defgroup subproc Sub-process handling
 * @ingroup dpkg-internal
 * @{
 */

void subproc_signals_setup(const char *name);
void subproc_signals_cleanup(int argc, void **argv);

#define PROCPIPE 1
#define PROCWARN 2
#define PROCNOERR 4

pid_t subproc_fork(void);
int subproc_wait(pid_t pid, const char *desc);
int subproc_check(int status, const char *desc, int flags);
int subproc_wait_check(pid_t pid, const char *desc, int flags);

/** @} */

DPKG_END_DECLS

#endif /* LIBDPKG_SUBPROC_H */
