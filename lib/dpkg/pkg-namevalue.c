/*
 * libdpkg - Debian packaging suite library routines
 * pkg-namevalue.c - name/value package tables
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2006-2014 Guillem Jover <guillem@debian.org>
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

#include <dpkg/dpkg-db.h>
#include <dpkg/namevalue.h>

const struct namevalue booleaninfos[] = {
	NAMEVALUE_DEF("no",			false),
	NAMEVALUE_DEF("yes",			true),
	{ .name = NULL }
};

const struct namevalue multiarchinfos[] = {
	NAMEVALUE_DEF("no",			PKG_MULTIARCH_NO),
	NAMEVALUE_DEF("same",			PKG_MULTIARCH_SAME),
	NAMEVALUE_DEF("allowed",		PKG_MULTIARCH_ALLOWED),
	NAMEVALUE_DEF("foreign",		PKG_MULTIARCH_FOREIGN),
	{ .name = NULL }
};

const struct namevalue priorityinfos[] = {
	NAMEVALUE_DEF("required",		pri_required),
	NAMEVALUE_DEF("important",		pri_important),
	NAMEVALUE_DEF("standard",		pri_standard),
	NAMEVALUE_DEF("optional",		pri_optional),
	NAMEVALUE_DEF("extra",			pri_extra),
	NAMEVALUE_FALLBACK_DEF("this is a bug - please report", pri_other),
	NAMEVALUE_DEF("unknown",		pri_unknown),
	{ .name = NULL }
};

const struct namevalue wantinfos[] = {
	NAMEVALUE_DEF("unknown",		want_unknown),
	NAMEVALUE_DEF("install",		want_install),
	NAMEVALUE_DEF("hold",			want_hold),
	NAMEVALUE_DEF("deinstall",		want_deinstall),
	NAMEVALUE_DEF("purge",			want_purge),
	{ .name = NULL }
};

const struct namevalue eflaginfos[] = {
	NAMEVALUE_DEF("ok",			eflag_ok),
	NAMEVALUE_DEF("reinstreq",		eflag_reinstreq),
	{ .name = NULL }
};

const struct namevalue statusinfos[] = {
	NAMEVALUE_DEF("not-installed",		stat_notinstalled),
	NAMEVALUE_DEF("config-files",		stat_configfiles),
	NAMEVALUE_DEF("half-installed",		stat_halfinstalled),
	NAMEVALUE_DEF("unpacked",		stat_unpacked),
	NAMEVALUE_DEF("half-configured",	stat_halfconfigured),
	NAMEVALUE_DEF("triggers-awaited",	stat_triggersawaited),
	NAMEVALUE_DEF("triggers-pending",	stat_triggerspending),
	NAMEVALUE_DEF("installed",		stat_installed),
	{ .name = NULL }
};
