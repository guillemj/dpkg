/*
 * libdpkg - Debian packaging suite library routines
 * trigdeferred.h - parsing of triggers/Deferred
 *
 * Copyright © 2007 Canonical, Ltd.
 *   written by Ian Jackson <ian@chiark.greenend.org.uk>
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

#ifndef LIBDPKG_TRIGDEFERRED_H
#define LIBDPKG_TRIGDEFERRED_H

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

enum trigdef_updateflags {
	tduf_nolockok =           001,
	tduf_write =              002,
	tduf_nolock =             003,
	/* Should not be set unless _write is. */
	tduf_writeifempty =       010,
	tduf_writeifenoent =      020,
};

struct trigdefmeths {
	void (*trig_begin)(const char *trig);
	void (*package)(const char *awname);
	void (*trig_end)(void);
};

void trigdef_set_methods(const struct trigdefmeths *methods);

int trigdef_update_start(enum trigdef_updateflags uf, const char *admindir);
void trigdef_update_printf(const char *format, ...) DPKG_ATTR_PRINTF(1);
int trigdef_parse(void);
void trigdef_process_done(void);

DPKG_END_DECLS

#endif /* LIBDPKG_TRIGDEFERRED_H */
