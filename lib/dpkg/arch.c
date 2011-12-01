/*
 * libdpkg - Debian packaging suite library routines
 * arch.c - architecture database functions
 *
 * Copyright © 2011 Linaro Limited
 * Copyright © 2011 Raphaël Hertzog <hertzog@debian.org>
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

#include <config.h>
#include <compat.h>

#include <assert.h>
#include <ctype.h>
#include <string.h>

#include <dpkg/i18n.h>
#include <dpkg/ehandle.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/varbuf.h>
#include <dpkg/arch.h>

/**
 * Verify if the architecture name is valid.
 *
 * Returns NULL if the architecture name is valid. Otherwise it returns a
 * string describing why it's not valid. Currently it ensures the name
 * starts with an alphanumeric and is then composed of a combinations of
 * dashes and alphanumerics.
 *
 * The function will abort if you pass it a NULL pointer.
 *
 * @param name The architectute name to verify.
 */
const char *
dpkg_arch_name_is_illegal(const char *name)
{
	static char buf[150];
	const char *p = name;

	assert(name);
	if (!*p)
		return _("may not be empty string");
	if (!isalnum(*p))
		return _("must start with an alphanumeric");
	while (*++p != '\0')
		if (!isalnum(*p) && *p != '-')
			break;
	if (*p == '\0')
		return NULL;

	snprintf(buf, sizeof(buf), _("character `%c' not allowed (only "
	                             "letters, digits and characters `%s')"),
	         *p, "-");
	return buf;
}

/* This is a special architecture used to guarantee we always have a valid
 * structure to handle. */
static struct dpkg_arch arch_item_none = {
	.name = "",
	.type = arch_none,
	.next = NULL,
};
static struct dpkg_arch arch_item_empty = {
	.name = "",
	.type = arch_empty,
	.next = NULL,
};

static struct dpkg_arch arch_item_any = {
	.name = "any",
	.type = arch_wildcard,
	.next = NULL,
};
static struct dpkg_arch arch_item_all = {
	.name = "all",
	.type = arch_all,
	.next = &arch_item_any,
};
static struct dpkg_arch arch_item_native = {
	.name = ARCHITECTURE,
	.type = arch_native,
	.next = &arch_item_all,
};
static struct dpkg_arch *arch_list = &arch_item_native;

static struct dpkg_arch *
dpkg_arch_new(const char *name, enum dpkg_arch_type type)
{
	struct dpkg_arch *new;

	new = nfmalloc(sizeof(*new));
	new->next = NULL;
	new->name = nfstrsave(name);
	new->type = type;

	return new;
}

/**
 * Retrieve the struct dpkg_arch for the given architecture.
 *
 * Create a new structure for the architecture if it's not yet known from
 * the system, in that case it will have arch->type == arch_unknown, if the
 * architecture is illegal it will have arch->type == arch_illegal and if
 * name is NULL or an empty string then it will have arch->type == arch_none.
 *
 * @param name The architecture name.
 */
struct dpkg_arch *
dpkg_arch_find(const char *name)
{
	struct dpkg_arch *arch, *last_arch = NULL;
	enum dpkg_arch_type type;

	if (name == NULL)
		return &arch_item_none;
	if (name[0] == '\0')
		return &arch_item_empty;

	for (arch = arch_list; arch; arch = arch->next) {
		if (strcmp(arch->name, name) == 0)
			return arch;
		last_arch = arch;
	}

	if (dpkg_arch_name_is_illegal(name))
		type = arch_illegal;
	else
		type = arch_unknown;

	arch = dpkg_arch_new(name, type);
	last_arch->next = arch;

	return arch;
}

/**
 * Return the struct dpkg_arch corresponding to the architecture type.
 *
 * The function only returns instances for types which are unique. For
 * forward-compatibility any unknown type will return NULL.
 */
struct dpkg_arch *
dpkg_arch_get(enum dpkg_arch_type type)
{
	switch (type) {
	case arch_none:
		return &arch_item_none;
	case arch_empty:
		return &arch_item_empty;
	case arch_wildcard:
		return &arch_item_any;
	case arch_all:
		return &arch_item_all;
	case arch_native:
		return &arch_item_native;
	case arch_illegal:
	case arch_foreign:
	case arch_unknown:
		internerr("architecture type %d is not unique", type);
	default:
		/* Ignore unknown types for forward-compatibility. */
		return NULL;
	}
}

/**
 * Return the complete list of architectures.
 *
 * In fact it returns the first item of the linked list and you can
 * traverse the list by following arch->next until it's NULL.
 */
struct dpkg_arch *
dpkg_arch_get_list(void)
{
	return arch_list;
}

/**
 * Reset the list of architectures.
 *
 * Must be called before nffreeall() to ensure we don't point to
 * unallocated memory.
 */
void
dpkg_arch_reset_list(void)
{
	arch_item_any.next = NULL;
}

void
varbuf_add_archqual(struct varbuf *vb, const struct dpkg_arch *arch)
{
	if (arch->type == arch_none)
		return;

	varbuf_add_char(vb, ':');
	varbuf_add_str(vb, arch->name);
}
