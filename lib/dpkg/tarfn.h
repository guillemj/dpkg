/*
 * libdpkg - Debian packaging suite library routines
 * tarfn.h - tar archive extraction functions
 *
 * Copyright © 1995 Bruce Perens
 * Copyright © 2009-2014, 2017 Guillem Jover <guillem@debian.org>
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

#ifndef LIBDPKG_TARFN_H
#define LIBDPKG_TARFN_H

#include <sys/types.h>

#include <stdint.h>

#include <dpkg/file.h>

/**
 * @defgroup tar Tar archive handling
 * @ingroup dpkg-public
 * @{
 */

#define TARBLKSZ	512

enum tar_format {
	TAR_FORMAT_OLD,
	TAR_FORMAT_GNU,
	TAR_FORMAT_USTAR,
	TAR_FORMAT_PAX,
};

enum tar_filetype {
	/** For compatibility with decades-old bug. */
	TAR_FILETYPE_FILE0 = '\0',
	TAR_FILETYPE_FILE = '0',
	TAR_FILETYPE_HARDLINK = '1',
	TAR_FILETYPE_SYMLINK = '2',
	TAR_FILETYPE_CHARDEV = '3',
	TAR_FILETYPE_BLOCKDEV = '4',
	TAR_FILETYPE_DIR = '5',
	TAR_FILETYPE_FIFO = '6',
	TAR_FILETYPE_GNU_LONGLINK = 'K',
	TAR_FILETYPE_GNU_LONGNAME = 'L',
};

struct tar_entry {
	/** Tar archive format. */
	enum tar_format format;
	/** File type. */
	enum tar_filetype type;
	/** File name. */
	char *name;
	/** Symlink or hardlink name. */
	char *linkname;
	/** File size. */
	off_t size;
	/** Last-modified time. */
	time_t mtime;
	/** Special device for mknod(). */
	dev_t dev;

	struct file_stat stat;
};

typedef int tar_read_func(void *ctx, char *buffer, int length);
typedef int tar_make_func(void *ctx, struct tar_entry *h);

struct tar_operations {
	tar_read_func *read;

	tar_make_func *extract_file;
	tar_make_func *link;
	tar_make_func *symlink;
	tar_make_func *mkdir;
	tar_make_func *mknod;
};

uintmax_t
tar_atoul(const char *s, size_t size, uintmax_t max);
intmax_t
tar_atosl(const char *s, size_t size, intmax_t min, intmax_t max);

void
tar_entry_update_from_system(struct tar_entry *te);

int tar_extractor(void *ctx, const struct tar_operations *ops);

/** @} */

#endif
