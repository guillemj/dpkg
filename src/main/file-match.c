/*
 * dpkg - main program for package management
 * file-match.c - file name/type match tracking functions
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <stdlib.h>

#include <dpkg/dpkg.h>

#include "file-match.h"

struct match_node *
match_node_new(const char *name, const char *type, struct match_node *next)
{
	struct match_node *node;

	node = m_malloc(sizeof(*node));
	node->next = next;
	node->filename = m_strdup(name);
	node->filetype = m_strdup(type);

	return node;
}

void
match_node_free(struct match_node *node)
{
	free(node->filetype);
	free(node->filename);
	free(node);
}
