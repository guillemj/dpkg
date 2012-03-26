/*
 * libdpkg - Debian packaging suite library routines
 * deb-version.c - deb format version handling routines
 *
 * Copyright © 2012 Guillem Jover <guillem@debian.org>
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

#include <config.h>
#include <compat.h>

#include <string.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/deb-version.h>

const char *
deb_version_parse(struct deb_version *version, const char *str)
{
	const char *str_minor, *end;
	int major = 0;
	int minor = 0;

	for (end = str; *end && cisdigit(*end); end++)
		major = major * 10  + *end - '0';

	if (end == str)
		return _("format version with empty major component");
	if (*end != '.')
		return _("format version has no dot");

	for (end = str_minor = end + 1; *end && cisdigit(*end); end++)
		minor = minor * 10 + *end - '0';

	if (end == str_minor)
		return _("format version with empty minor component");
	if (*end != '\n' && *end != '\0')
		return _("format version followed by junk");

	version->major = major;
	version->minor = minor;

	return NULL;
}
