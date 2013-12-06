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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef LIBDPKG_TRIGDEFERRED_H
#define LIBDPKG_TRIGDEFERRED_H

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

/**
 * @defgroup trigdeferred Trigger deferred file handling
 * @ingroup dpkg-internal
 * @{
 */

enum trigdef_updateflags {
	tduf_nolockok		= DPKG_BIT(0),
	tduf_write		= DPKG_BIT(1),
	tduf_nolock		= tduf_nolockok | tduf_write,
	/** Should not be set unless _write is. */
	tduf_writeifempty	= DPKG_BIT(3),
	tduf_writeifenoent	= DPKG_BIT(4),
};

enum trigdef_update_status {
	tdus_error_no_dir = -1,
	tdus_error_empty_deferred = -2,
	tdus_error_no_deferred = -3,
	tdus_no_deferred = 1,
	tdus_ok = 2,
};

struct trigdefmeths {
	void (*trig_begin)(const char *trig);
	void (*package)(const char *awname);
	void (*trig_end)(void);
};

void trigdef_set_methods(const struct trigdefmeths *methods);

enum trigdef_update_status trigdef_update_start(enum trigdef_updateflags uf);
void trigdef_update_printf(const char *format, ...) DPKG_ATTR_PRINTF(1);
int trigdef_parse(void);
void trigdef_process_done(void);

/** @} */

DPKG_END_DECLS

#endif /* LIBDPKG_TRIGDEFERRED_H */
