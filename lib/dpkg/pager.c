/*
 * libdpkg - Debian packaging suite library routines
 * pager.c - pager execution support
 *
 * Copyright © 2018 Guillem Jover <guillem@debian.org>
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

#include <config.h>
#include <compat.h>

#include <stdlib.h>
#include <unistd.h>

#include <dpkg/dpkg.h>
#include <dpkg/i18n.h>
#include <dpkg/string.h>
#include <dpkg/pager.h>

/**
 * Get a suitable pager.
 *
 * @return A string representing a pager.
 */
const char *
pager_get_exec(void)
{
	const char *pager;

	if (!isatty(0) || !isatty(1))
		return CAT;

	pager = getenv("PAGER");
	if (str_is_unset(pager))
		pager = DEFAULTPAGER;

	return pager;
}
