/*
 * libdpkg - Debian packaging suite library routines
 * pkg-show.h - primitives for pkg information display
 *
 * Copyright © 2010 Guillem Jover <guillem@debian.org>
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

#ifndef DPKG_PKG_SHOW_H
#define DPKG_PKG_SHOW_H

#include <dpkg/macros.h>
#include <dpkg/dpkg-db.h>

DPKG_BEGIN_DECLS

const char *pkg_summary(const struct pkginfo *pkg, int *len_ret);

DPKG_END_DECLS

#endif /* DPKG_PKG_SHOW_H */
