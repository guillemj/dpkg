/*
 * dpkg - main program for package management
 * infodb.h - package control information database
 *
 * Copyright © 2011 Guillem Jover <guillem@debian.org>
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

#ifndef DPKG_INFODB_H
#define DPKG_INFODB_H

#include <stdbool.h>

#include <dpkg/dpkg-db.h>

bool pkg_infodb_has_file(struct pkginfo *pkg, const char *name);

typedef void pkg_infodb_file_func(const char *filename, const char *filetype);

void pkg_infodb_foreach(struct pkginfo *pkg, pkg_infodb_file_func *func);

#endif /* DPKG_INFODB_H */
