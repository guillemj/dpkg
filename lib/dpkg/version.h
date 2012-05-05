/*
 * libdpkg - Debian packaging suite library routines
 * version.h - version handling routines
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

#ifndef LIBDPKG_VERSION_H
#define LIBDPKG_VERSION_H

#include <stdbool.h>

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

/**
 * @defgroup version Version handling
 * @ingroup dpkg-public
 * @{
 */

struct dpkg_version {
	unsigned long epoch;
	const char *version;
	const char *revision;
};

void dpkg_version_blank(struct dpkg_version *version);
bool dpkg_version_is_informative(const struct dpkg_version *version);

/** @} */

DPKG_END_DECLS

#endif /* LIBDPKG_VERSION_H */
