/*
 * libdpkg - Debian packaging suite library routines
 * tarfn.c - tar archive extraction functions
 *
 * Copyright © 1995 Bruce Perens
 * Copyright © 2007-2011,2013-2014 Guillem Jover <guillem@debian.org>
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

#include <sys/stat.h>

#include <errno.h>
#include <string.h>
#include <pwd.h>
#include <grp.h>
#include <unistd.h>
#include <inttypes.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/macros.h>
#include <dpkg/dpkg.h>
#include <dpkg/tarfn.h>

#define TAR_MAGIC_USTAR "ustar\0" "00"
#define TAR_MAGIC_GNU   "ustar "  " \0"

struct tar_header {
	char name[100];
	char mode[8];
	char uid[8];
	char gid[8];
	char size[12];
	char mtime[12];
	char checksum[8];
	char linkflag;
	char linkname[100];
	char magic[8];
	char user[32];
	char group[32];
	char devmajor[8];
	char devminor[8];

	/* Only valid on ustar. */
	char prefix[155];
};

/**
 * Convert an ASCII octal string to an intmax_t.
 */
static intmax_t
OtoM(const char *s, int size)
{
	intmax_t n = 0;

	while (*s == ' ') {
		s++;
		size--;
	}

	while (--size >= 0 && *s >= '0' && *s <= '7')
		n = (n * 010) + (*s++ - '0');

	return n;
}

static char *
get_prefix_name(struct tar_header *h)
{
	char *path;

	m_asprintf(&path, "%.*s/%.*s", (int)sizeof(h->prefix), h->prefix,
	           (int)sizeof(h->name), h->name);

	return path;
}

static mode_t
get_unix_mode(struct tar_header *h)
{
	mode_t mode;
	enum tar_filetype type;

	type = (enum tar_filetype)h->linkflag;

	switch (type) {
	case TAR_FILETYPE_FILE0:
	case TAR_FILETYPE_FILE:
	case TAR_FILETYPE_HARDLINK:
		mode = S_IFREG;
		break;
	case TAR_FILETYPE_SYMLINK:
		mode = S_IFLNK;
		break;
	case TAR_FILETYPE_DIR:
		mode = S_IFDIR;
		break;
	case TAR_FILETYPE_CHARDEV:
		mode = S_IFCHR;
		break;
	case TAR_FILETYPE_BLOCKDEV:
		mode = S_IFBLK;
		break;
	case TAR_FILETYPE_FIFO:
		mode = S_IFIFO;
		break;
	default:
		mode = 0;
		break;
	}

	mode |= OtoM(h->mode, sizeof(h->mode));

	return mode;
}

static long
tar_header_checksum(struct tar_header *h)
{
	unsigned char *s = (unsigned char *)h;
	unsigned int i;
	const size_t checksum_offset = offsetof(struct tar_header, checksum);
	long sum;

	/* Treat checksum field as all blank. */
	sum = ' ' * sizeof(h->checksum);

	for (i = checksum_offset; i > 0; i--)
		sum += *s++;

	/* Skip the real checksum field. */
	s += sizeof(h->checksum);

	for (i = TARBLKSZ - checksum_offset - sizeof(h->checksum); i > 0; i--)
		sum += *s++;

	return sum;
}

static int
tar_header_decode(struct tar_header *h, struct tar_entry *d)
{
	struct passwd *passwd = NULL;
	struct group *group = NULL;
	long checksum;

	if (memcmp(h->magic, TAR_MAGIC_GNU, 6) == 0)
		d->format = TAR_FORMAT_GNU;
	else if (memcmp(h->magic, TAR_MAGIC_USTAR, 6) == 0)
		d->format = TAR_FORMAT_USTAR;
	else
		d->format = TAR_FORMAT_OLD;

	d->type = (enum tar_filetype)h->linkflag;
	if (d->type == TAR_FILETYPE_FILE0)
		d->type = TAR_FILETYPE_FILE;

	/* Concatenate prefix and name to support ustar style long names. */
	if (d->format == TAR_FORMAT_USTAR && h->prefix[0] != '\0')
		d->name = get_prefix_name(h);
	else
		d->name = m_strndup(h->name, sizeof(h->name));
	d->linkname = m_strndup(h->linkname, sizeof(h->linkname));
	d->stat.mode = get_unix_mode(h);
	d->size = (off_t)OtoM(h->size, sizeof(h->size));
	d->mtime = (time_t)OtoM(h->mtime, sizeof(h->mtime));
	d->dev = makedev(OtoM(h->devmajor, sizeof(h->devmajor)),
			 OtoM(h->devminor, sizeof(h->devminor)));

	if (*h->user)
		passwd = getpwnam(h->user);
	if (passwd)
		d->stat.uid = passwd->pw_uid;
	else
		d->stat.uid = (uid_t)OtoM(h->uid, sizeof(h->uid));

	if (*h->group)
		group = getgrnam(h->group);
	if (group)
		d->stat.gid = group->gr_gid;
	else
		d->stat.gid = (gid_t)OtoM(h->gid, sizeof(h->gid));

	checksum = OtoM(h->checksum, sizeof(h->checksum));

	return tar_header_checksum(h) == checksum;
}

/**
 * Decode a GNU longlink or longname from the tar archive.
 *
 * The way the GNU long{link,name} stuff works is like this:
 *
 * - The first header is a “dummy” header that contains the size of the
 *   filename.
 * - The next N headers contain the filename.
 * - After the headers with the filename comes the “real” header with a
 *   bogus name or link.
 */
static int
tar_gnu_long(void *ctx, const struct tar_operations *ops, struct tar_entry *te,
             char **longp)
{
	char buf[TARBLKSZ];
	char *bp;
	int status = 0;
	int long_read;

	free(*longp);
	*longp = bp = m_malloc(te->size);

	for (long_read = te->size; long_read > 0; long_read -= TARBLKSZ) {
		int copysize;

		status = ops->read(ctx, buf, TARBLKSZ);
		if (status == TARBLKSZ)
			status = 0;
		else {
			/* Read partial header record? */
			if (status > 0) {
				errno = 0;
				status = -1;
			}

			/* If we didn't get TARBLKSZ bytes read, punt. */
			break;
		}

		copysize = min(long_read, TARBLKSZ);
		memcpy(bp, buf, copysize);
		bp += copysize;
	};

	return status;
}

static void
tar_entry_copy(struct tar_entry *dst, struct tar_entry *src)
{
	memcpy(dst, src, sizeof(struct tar_entry));

	dst->name = m_strdup(src->name);
	dst->linkname = m_strdup(src->linkname);
}

static void
tar_entry_destroy(struct tar_entry *te)
{
	free(te->name);
	free(te->linkname);
}

struct symlinkList {
	struct symlinkList *next;
	struct tar_entry h;
};

int
tar_extractor(void *ctx, const struct tar_operations *ops)
{
	int status;
	char buffer[TARBLKSZ];
	struct tar_entry h;

	char *next_long_name, *next_long_link;
	struct symlinkList *symlink_head, *symlink_tail, *symlink_node;

	next_long_name = NULL;
	next_long_link = NULL;
	symlink_tail = symlink_head = NULL;

	h.name = NULL;
	h.linkname = NULL;

	while ((status = ops->read(ctx, buffer, TARBLKSZ)) == TARBLKSZ) {
		int name_len;

		if (!tar_header_decode((struct tar_header *)buffer, &h)) {
			if (h.name[0] == '\0') {
				/* End of tape. */
				status = 0;
			} else {
				/* Indicates broken tarfile:
				 * “Header checksum error”. */
				errno = 0;
				status = -1;
			}
			tar_entry_destroy(&h);
			break;
		}
		if (h.type != TAR_FILETYPE_GNU_LONGLINK &&
		    h.type != TAR_FILETYPE_GNU_LONGNAME) {
			if (next_long_name)
				h.name = next_long_name;

			if (next_long_link)
				h.linkname = next_long_link;

			next_long_link = NULL;
			next_long_name = NULL;
		}

		if (h.name[0] == '\0') {
			/* Indicates broken tarfile: “Bad header data”. */
			errno = 0;
			status = -1;
			tar_entry_destroy(&h);
			break;
		}

		name_len = strlen(h.name);

		switch (h.type) {
		case TAR_FILETYPE_FILE:
			/* Compatibility with pre-ANSI ustar. */
			if (h.name[name_len - 1] != '/') {
				status = ops->extract_file(ctx, &h);
				break;
			}
			/* Else, fall through. */
		case TAR_FILETYPE_DIR:
			if (h.name[name_len - 1] == '/') {
				h.name[name_len - 1] = '\0';
			}
			status = ops->mkdir(ctx, &h);
			break;
		case TAR_FILETYPE_HARDLINK:
			status = ops->link(ctx, &h);
			break;
		case TAR_FILETYPE_SYMLINK:
			symlink_node = m_malloc(sizeof(*symlink_node));
			symlink_node->next = NULL;
			tar_entry_copy(&symlink_node->h, &h);

			if (symlink_head)
				symlink_tail->next = symlink_node;
			else
				symlink_head = symlink_node;
			symlink_tail = symlink_node;
			status = 0;
			break;
		case TAR_FILETYPE_CHARDEV:
		case TAR_FILETYPE_BLOCKDEV:
		case TAR_FILETYPE_FIFO:
			status = ops->mknod(ctx, &h);
			break;
		case TAR_FILETYPE_GNU_LONGLINK:
			status = tar_gnu_long(ctx, ops, &h, &next_long_link);
			break;
		case TAR_FILETYPE_GNU_LONGNAME:
			status = tar_gnu_long(ctx, ops, &h, &next_long_name);
			break;
		default:
			/* Indicates broken tarfile: “Bad header field”. */
			errno = 0;
			status = -1;
		}
		tar_entry_destroy(&h);
		if (status != 0)
			/* Pass on status from coroutine. */
			break;
	}

	while (symlink_head) {
		symlink_node = symlink_head->next;
		if (status == 0)
			status = ops->symlink(ctx, &symlink_head->h);
		tar_entry_destroy(&symlink_head->h);
		free(symlink_head);
		symlink_head = symlink_node;
	}
	/* Make sure we free the long names, in case of a bogus or truncated
	 * tar archive with long entries not followed by a normal entry. */
	free(next_long_name);
	free(next_long_link);

	if (status > 0) {
		/* Indicates broken tarfile: “Read partial header record”. */
		errno = 0;
		return -1;
	} else {
		/* Return whatever I/O function returned. */
		return status;
	}
}
