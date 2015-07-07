/*
 * libcompat - system compatibility library
 *
 * Based on code from libselinux, Public Domain.
 * Copyright © 2014 Guillem Jover <guillem@debian.org>
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

#include <string.h>
#include <stdlib.h>

#include <selinux/selinux.h>
#include <selinux/context.h>

#include "compat.h"

int
setexecfilecon(const char *filename, const char *fallback)
{
	int rc;

	security_context_t curcon = NULL, newcon = NULL, filecon = NULL;
	security_class_t seclass;
	context_t tmpcon = NULL;

	if (is_selinux_enabled() < 1)
		return 0;

	rc = getcon(&curcon);
	if (rc < 0)
		goto out;

	rc = getfilecon(filename, &filecon);
	if (rc < 0)
		goto out;

	seclass = string_to_security_class("process");
	if (seclass == 0)
		goto out;

	rc = security_compute_create(curcon, filecon, seclass, &newcon);
	if (rc < 0)
		goto out;

	if (strcmp(curcon, newcon) == 0) {
		/* No default transition, use fallback for now. */
		rc = -1;
		tmpcon = context_new(curcon);
		if (tmpcon == NULL)
			goto out;
		if (context_type_set(tmpcon, fallback))
			goto out;
		freecon(newcon);
		newcon = strdup(context_str(tmpcon));
		if (newcon == NULL)
			goto out;
	}

	rc = setexeccon(newcon);

out:
	if (rc < 0 && security_getenforce() == 0)
		rc = 0;

	context_free(tmpcon);
	freecon(newcon);
	freecon(curcon);
	freecon(filecon);

	return rc;
}
