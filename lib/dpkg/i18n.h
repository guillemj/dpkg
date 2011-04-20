/*
 * libdpkg - Debian packaging suite library routines
 * i18n.h - i18n support
 *
 * Copyright © 2008-2011 Guillem Jover <guillem@debian.org>
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

#ifndef LIBDPKG_I18N_H
#define LIBDPKG_I18N_H

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

#include <gettext.h>

/* We need to include this because pgettext() uses LC_MESSAGES, but libintl.h
 * which gets pulled by gettext.h only includes it if building optimized. */
#include <locale.h>

#define _(str) gettext(str)
#define P_(str, str_plural, n) ngettext(str, str_plural, n)
#define N_(str) gettext_noop(str)
#define C_(ctxt, str) pgettext(ctxt, str)

DPKG_END_DECLS

#endif /* LIBDPKG_I18N_H */
