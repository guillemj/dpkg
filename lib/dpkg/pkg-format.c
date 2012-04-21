/*
 * libdpkg - Debian packaging suite library routines
 * pkg-format.c - customizable package formatting
 *
 * Copyright © 2001 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2008-2012 Guillem Jover <guillem@debian.org>
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
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/parsedump.h>
#include <dpkg/pkg-show.h>
#include <dpkg/pkg-format.h>

enum pkg_format_type {
	PKG_FORMAT_INVALID,
	PKG_FORMAT_STRING,
	PKG_FORMAT_FIELD,
};

struct pkg_format_node {
	struct pkg_format_node *next;
	enum pkg_format_type type;
	size_t width;
	int pad;
	char *data;
};


static struct pkg_format_node *
pkg_format_node_new(void)
{
	struct pkg_format_node *buf;

	buf = m_malloc(sizeof(*buf));
	buf->type = PKG_FORMAT_INVALID;
	buf->next = NULL;
	buf->data = NULL;
	buf->width = 0;
	buf->pad = 0;

	return buf;
}

static bool
parsefield(struct pkg_format_node *cur, const char *fmt, const char *fmtend)
{
	int len;
	const char *ws;

	len = fmtend - fmt + 1;

	ws = memchr(fmt, ';', len);
	if (ws) {
		char *endptr;
		long w;

		w = strtol(ws + 1, &endptr, 0);
		if (endptr[0] != '}') {
			fprintf(stderr,
			        _("invalid character `%c' in field width\n"),
			       *endptr);
			return false;
		}

		if (w < 0) {
			cur->pad = 1;
			cur->width = (size_t)-w;
		} else
			cur->width = (size_t)w;

		len = ws - fmt;
	}

	cur->type = PKG_FORMAT_FIELD;
	cur->data = m_malloc(len + 1);
	memcpy(cur->data, fmt, len);
	cur->data[len] = '\0';

	return true;
}

static bool
parsestring(struct pkg_format_node *cur, const char *fmt, const char *fmtend)
{
	int len;
	char *write;

	len = fmtend - fmt + 1;

	cur->type = PKG_FORMAT_STRING;
	write = cur->data = m_malloc(len + 1);
	while (fmt <= fmtend) {
		if (*fmt == '\\') {
			fmt++;
			switch (*fmt) {
			case 'n':
				*write = '\n';
				break;
			case 't':
				*write = '\t';
				break;
			case 'r':
				*write = '\r';
				break;
			case '\\':
			default:
				*write = *fmt;
				break;
			}
		} else
			*write = *fmt;
		write++;
		fmt++;
	}
	*write = '\0';

	return true;
}

void
pkg_format_free(struct pkg_format_node *head)
{
	struct pkg_format_node *next;

	while (head) {
		next = head->next;
		free(head->data);
		free(head);
		head = next;
	}
}

struct pkg_format_node *
pkg_format_parse(const char *fmt)
{
	struct pkg_format_node *head;
	struct pkg_format_node *cur;
	const char *fmtend;

	head = cur = NULL;

	while (*fmt) {
		if (cur)
			cur = cur->next = pkg_format_node_new();
		else
			head = cur = pkg_format_node_new();

		if (fmt[0] == '$' && fmt[1] == '{') {
			fmtend = strchr(fmt, '}');
			if (!fmtend) {
				fprintf(stderr,
				      _("Closing brace missing in format\n"));
				pkg_format_free(head);
				return NULL;
			}

			if (!parsefield(cur, fmt + 2, fmtend - 1)) {
				pkg_format_free(head);
				return NULL;
			}
			fmt = fmtend + 1;
		} else {
			fmtend = fmt;
			do {
				fmtend += 1;
				fmtend = strchr(fmtend, '$');
			} while (fmtend && fmtend[1] != '{');

			if (!fmtend)
				fmtend = fmt + strlen(fmt);

			if (!parsestring(cur, fmt, fmtend - 1)) {
				pkg_format_free(head);
				return NULL;
			}
			fmt = fmtend;
		}
	}

	return head;
}

static void
virt_package(struct varbuf *vb,
             const struct pkginfo *pkg, const struct pkgbin *pkgbin,
             enum fwriteflags flags, const struct fieldinfo *fip)
{
	varbuf_add_pkgbin_name(vb, pkg, pkgbin, pnaw_nonambig);
}

static void
virt_status_abbrev(struct varbuf *vb,
                   const struct pkginfo *pkg, const struct pkgbin *pkgbin,
                   enum fwriteflags flags, const struct fieldinfo *fip)
{
	if (pkgbin != &pkg->installed)
		return;

	varbuf_add_char(vb, pkg_abbrev_want(pkg));
	varbuf_add_char(vb, pkg_abbrev_status(pkg));
	varbuf_add_char(vb, pkg_abbrev_eflag(pkg));
}

static void
virt_summary(struct varbuf *vb,
             const struct pkginfo *pkg, const struct pkgbin *pkgbin,
             enum fwriteflags flags, const struct fieldinfo *fip)
{
	const char *desc;
	int len;

	desc = pkg_summary(pkg, pkgbin, &len);

	varbuf_add_buf(vb, desc, len);
}

static void
virt_source_package(struct varbuf *vb,
                    const struct pkginfo *pkg, const struct pkgbin *pkgbin,
                    enum fwriteflags flags, const struct fieldinfo *fip)
{
	const char *name;
	size_t len;

	name = pkgbin->source;
	if (name == NULL)
		name = pkg->set->name;

	len = strcspn(name, " ");
	if (len == 0)
		len = strlen(name);

	varbuf_add_buf(vb, name, len);
}

static void
virt_source_version(struct varbuf *vb,
                    const struct pkginfo *pkg, const struct pkgbin *pkgbin,
                    enum fwriteflags flags, const struct fieldinfo *fip)
{
	const char *version;
	size_t len;

	if (pkgbin->source)
		version = strchr(pkgbin->source, '(');
	else
		version = NULL;

	if (version == NULL) {
		varbufversion(vb, &pkgbin->version, vdew_nonambig);
	} else {
		version++;

		len = strcspn(version, ")");
		if (len == 0)
			len = strlen(version);

		varbuf_add_buf(vb, version, len);
	}
}

const struct fieldinfo virtinfos[] = {
	{ "binary:Package", NULL, virt_package },
	{ "binary:Summary", NULL, virt_summary },
	{ "db:Status-Abbrev", NULL, virt_status_abbrev },
	{ "source:Package", NULL, virt_source_package },
	{ "source:Version", NULL, virt_source_version },
	{ NULL },
};

static const struct fieldinfo *
find_field_info(const struct fieldinfo *fields_head,
                const struct pkg_format_node *fmt_node)
{
	const struct fieldinfo *fip;

	for (fip = fields_head; fip->name; fip++)
		if (strcasecmp(fmt_node->data, fip->name) == 0)
			break;

	return fip;
}

void
pkg_format_show(const struct pkg_format_node *head,
                struct pkginfo *pkg, struct pkgbin *pkgbin)
{
	struct varbuf vb = VARBUF_INIT, fb = VARBUF_INIT, wb = VARBUF_INIT;

	while (head) {
		bool ok;
		char fmt[16];

		ok = false;

		if (head->width > 0)
			snprintf(fmt, 16, "%%%s%zus",
			         ((head->pad) ? "-" : ""), head->width);
		else
			strcpy(fmt, "%s");

		if (head->type == PKG_FORMAT_STRING) {
			varbuf_printf(&fb, fmt, head->data);
			ok = true;
		} else if (head->type == PKG_FORMAT_FIELD) {
			const struct fieldinfo *fip;

			fip = find_field_info(fieldinfos, head);

			if (fip->name == NULL)
				fip = find_field_info(virtinfos, head);

			if (fip->name) {
				fip->wcall(&wb, pkg, pkgbin, 0, fip);

				varbuf_end_str(&wb);
				varbuf_printf(&fb, fmt, wb.buf);
				varbuf_reset(&wb);
				ok = true;
			} else {
				const struct arbitraryfield *afp;

				for (afp = pkgbin->arbs; afp; afp = afp->next)
					if (strcasecmp(head->data, afp->name) == 0) {
						varbuf_printf(&fb, fmt, afp->value);
						ok = true;
						break;
					}
			}
		}

		if (ok) {
			size_t len = strlen(fb.buf);
			if ((head->width > 0) && (len > head->width))
				len = head->width;
			varbuf_add_buf(&vb, fb.buf, len);
		}

		varbuf_reset(&fb);
		head = head->next;
	}

	if (vb.buf) {
		varbuf_end_str(&vb);
		fputs(vb.buf, stdout);
	}

	varbuf_destroy(&wb);
	varbuf_destroy(&fb);
	varbuf_destroy(&vb);
}
