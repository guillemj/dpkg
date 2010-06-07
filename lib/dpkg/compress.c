/*
 * libdpkg - Debian packaging suite library routines
 * compress.c - compression support functions
 *
 * Copyright © 2000 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2004 Scott James Remnant <scott@netsplit.com>
 * Copyright © 2006-2010 Guillem Jover <guillem@debian.org>
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

#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

#ifdef WITH_ZLIB
#include <zlib.h>
#endif
#ifdef WITH_BZ2
#include <bzlib.h>
#endif

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/varbuf.h>
#include <dpkg/buffer.h>
#include <dpkg/command.h>
#include <dpkg/compress.h>

static void DPKG_ATTR_NORET DPKG_ATTR_SENTINEL
fd_fd_filter(int fd_in, int fd_out, const char *desc, const char *file, ...)
{
	va_list args;
	struct command cmd;

	if (fd_in != 0) {
		m_dup2(fd_in, 0);
		close(fd_in);
	}
	if (fd_out != 1) {
		m_dup2(fd_out, 1);
		close(fd_out);
	}

	command_init(&cmd, file, desc);
	command_add_arg(&cmd, file);
	va_start(args, file);
	command_add_argv(&cmd, args);
	va_end(args);

	command_exec(&cmd);
}

/*
 * No compressor (pass-through).
 */

static void DPKG_ATTR_NORET
decompress_none(int fd_in, int fd_out, const char *desc)
{
	fd_fd_copy(fd_in, fd_out, -1, _("%s: decompression"), desc);
	exit(0);
}

static void DPKG_ATTR_NORET
compress_none(int fd_in, int fd_out, int compress_level, const char *desc)
{
	fd_fd_copy(fd_in, fd_out, -1, _("%s: compression"), desc);
	exit(0);
}

struct compressor compressor_none = {
	.name = "none",
	.extension = "",
	.default_level = 0,
	.compress = compress_none,
	.decompress = decompress_none,
};

/*
 * Gzip compressor.
 */

#ifdef WITH_ZLIB
static void DPKG_ATTR_NORET
decompress_gzip(int fd_in, int fd_out, const char *desc)
{
	char buffer[4096];
	gzFile gzfile = gzdopen(fd_in, "r");

	if (gzfile == NULL)
		ohshit(_("%s: error binding input to gzip stream"), desc);

	for (;;) {
		int actualread, actualwrite;

		actualread = gzread(gzfile, buffer, sizeof(buffer));
		if (actualread < 0) {
			int err = 0;
			const char *errmsg = gzerror(gzfile, &err);

			if (err == Z_ERRNO)
				errmsg = strerror(errno);
			ohshit(_("%s: internal gzip read error: '%s'"), desc,
			       errmsg);
		}
		if (actualread == 0) /* EOF. */
			break;

		actualwrite = write(fd_out, buffer, actualread);
		if (actualwrite != actualread)
			ohshite(_("%s: internal gzip write error"), desc);
	}

	if (close(fd_out))
		ohshite(_("%s: internal gzip write error"), desc);

	exit(0);
}

static void DPKG_ATTR_NORET
compress_gzip(int fd_in, int fd_out, int compress_level, const char *desc)
{
	char buffer[4096];
	char combuf[6];
	int err;
	gzFile gzfile;

	snprintf(combuf, sizeof(combuf), "w%d", compress_level);
	gzfile = gzdopen(fd_out, combuf);
	if (gzfile == NULL)
		ohshit(_("%s: error binding output to gzip stream"), desc);

	for (;;) {
		int actualread, actualwrite;

		actualread = read(fd_in, buffer, sizeof(buffer));
		if (actualread < 0)
			ohshite(_("%s: internal gzip read error"), desc);
		if (actualread == 0) /* EOF. */
			break;

		actualwrite = gzwrite(gzfile, buffer, actualread);
		if (actualwrite != actualread) {
			const char *errmsg = gzerror(gzfile, &err);

			if (err == Z_ERRNO)
				errmsg = strerror(errno);
			ohshit(_("%s: internal gzip write error: '%s'"), desc,
			       errmsg);
		}
	}

	err = gzclose(gzfile);
	if (err) {
		const char *errmsg;

		if (err == Z_ERRNO)
			errmsg = strerror(errno);
		else
			errmsg = zError(err);
		ohshit(_("%s: internal gzip write error: %s"), desc, errmsg);
	}

	exit(0);
}
#else
static void DPKG_ATTR_NORET
decompress_gzip(int fd_in, int fd_out, const char *desc)
{
	fd_fd_filter(fd_in, fd_out, desc, GZIP, "-dc", NULL);
}

static void DPKG_ATTR_NORET
compress_gzip(int fd_in, int fd_out, int compress_level, const char *desc)
{
	char combuf[6];

	snprintf(combuf, sizeof(combuf), "-c%d", compress_level);
	fd_fd_filter(fd_in, fd_out, desc, GZIP, combuf, NULL);
}
#endif

struct compressor compressor_gzip = {
	.name = "gzip",
	.extension = ".gz",
	.default_level = 9,
	.compress = compress_gzip,
	.decompress = decompress_gzip,
};

/*
 * Bzip2 compressor.
 */

#ifdef WITH_BZ2
static void DPKG_ATTR_NORET
decompress_bzip2(int fd_in, int fd_out, const char *desc)
{
	char buffer[4096];
	BZFILE *bzfile = BZ2_bzdopen(fd_in, "r");

	if (bzfile == NULL)
		ohshit(_("%s: error binding input to bzip2 stream"), desc);

	for (;;) {
		int actualread, actualwrite;

		actualread = BZ2_bzread(bzfile, buffer, sizeof(buffer));
		if (actualread < 0) {
			int err = 0;
			const char *errmsg = BZ2_bzerror(bzfile, &err);

			if (err == BZ_IO_ERROR)
				errmsg = strerror(errno);
			ohshit(_("%s: internal bzip2 read error: '%s'"), desc,
			       errmsg);
		}
		if (actualread == 0) /* EOF. */
			break;

		actualwrite = write(fd_out, buffer, actualread);
		if (actualwrite != actualread)
			ohshite(_("%s: internal bzip2 write error"), desc);
	}

	if (close(fd_out))
		ohshite(_("%s: internal bzip2 write error"), desc);

	exit(0);
}

static void DPKG_ATTR_NORET
compress_bzip2(int fd_in, int fd_out, int compress_level, const char *desc)
{
	char buffer[4096];
	char combuf[6];
	int err;
	BZFILE *bzfile;

	snprintf(combuf, sizeof(combuf), "w%d", compress_level);
	bzfile = BZ2_bzdopen(fd_out, combuf);
	if (bzfile == NULL)
		ohshit(_("%s: error binding output to bzip2 stream"), desc);

	for (;;) {
		int actualread, actualwrite;

		actualread = read(fd_in, buffer, sizeof(buffer));
		if (actualread < 0)
			ohshite(_("%s: internal bzip2 read error"), desc);
		if (actualread == 0) /* EOF. */
			break;

		actualwrite = BZ2_bzwrite(bzfile, buffer, actualread);
		if (actualwrite != actualread) {
			const char *errmsg = BZ2_bzerror(bzfile, &err);

			if (err == BZ_IO_ERROR)
				errmsg = strerror(errno);
			ohshit(_("%s: internal bzip2 write error: '%s'"), desc,
			       errmsg);
		}
	}

	BZ2_bzWriteClose(&err, bzfile, 0, NULL, NULL);
	if (err != BZ_OK) {
		const char *errmsg = _("unexpected bzip2 error");

		if (err == BZ_IO_ERROR)
			errmsg = strerror(errno);
		ohshit(_("%s: internal bzip2 write error: '%s'"), desc,
		       errmsg);
	}

	/* Because BZ2_bzWriteClose has done a fflush on the file handle,
	 * doing a close on the file descriptor associated with it should
	 * be safe™. */
	if (close(fd_out))
		ohshite(_("%s: internal bzip2 write error"), desc);

	exit(0);
}
#else
static void DPKG_ATTR_NORET
decompress_bzip2(int fd_in, int fd_out, const char *desc)
{
	fd_fd_filter(fd_in, fd_out, desc, BZIP2, "-dc", NULL);
}

static void DPKG_ATTR_NORET
compress_bzip2(int fd_in, int fd_out, int compress_level, const char *desc)
{
	char combuf[6];

	snprintf(combuf, sizeof(combuf), "-c%d", compress_level);
	fd_fd_filter(fd_in, fd_out, desc, BZIP2, combuf, NULL);
}
#endif

struct compressor compressor_bzip2 = {
	.name = "bzip2",
	.extension = ".bz2",
	.default_level = 9,
	.compress = compress_bzip2,
	.decompress = decompress_bzip2,
};

/*
 * Xz compressor.
 */

static void DPKG_ATTR_NORET
decompress_xz(int fd_in, int fd_out, const char *desc)
{
	fd_fd_filter(fd_in, fd_out, desc, XZ, "-dc", NULL);
}

static void DPKG_ATTR_NORET
compress_xz(int fd_in, int fd_out, int compress_level, const char *desc)
{
	char combuf[6];

	snprintf(combuf, sizeof(combuf), "-c%d", compress_level);
	fd_fd_filter(fd_in, fd_out, desc, XZ, combuf, NULL);
}

struct compressor compressor_xz = {
	.name = "xz",
	.extension = ".xz",
	.default_level = 6,
	.compress = compress_xz,
	.decompress = decompress_xz,
};

/*
 * Lzma compressor.
 */

static void DPKG_ATTR_NORET
decompress_lzma(int fd_in, int fd_out, const char *desc)
{
	fd_fd_filter(fd_in, fd_out, desc, XZ, "-dc", "--format=lzma", NULL);
}

static void DPKG_ATTR_NORET
compress_lzma(int fd_in, int fd_out, int compress_level, const char *desc)
{
	char combuf[6];

	snprintf(combuf, sizeof(combuf), "-c%d", compress_level);
	fd_fd_filter(fd_in, fd_out, desc, XZ, combuf, "--format=lzma", NULL);
}

struct compressor compressor_lzma = {
	.name = "lzma",
	.extension = ".lzma",
	.default_level = 6,
	.compress = compress_lzma,
	.decompress = decompress_lzma,
};

/*
 * Generic compressor filter.
 */

static struct compressor *compressor_array[] = {
	&compressor_none,
	&compressor_gzip,
	&compressor_xz,
	&compressor_bzip2,
	&compressor_lzma,
};

struct compressor *
compressor_find_by_name(const char *name)
{
	size_t i;

	for (i = 0; i < array_count(compressor_array); i++)
		if (strcmp(compressor_array[i]->name, name) == 0)
			return compressor_array[i];

	return NULL;
}

struct compressor *
compressor_find_by_extension(const char *extension)
{
	size_t i;

	for (i = 0; i < array_count(compressor_array); i++)
		if (strcmp(compressor_array[i]->extension, extension) == 0)
			return compressor_array[i];

	return NULL;
}

void
decompress_filter(struct compressor *compressor, int fd_in, int fd_out,
                  const char *desc_fmt, ...)
{
	va_list args;
	struct varbuf desc = VARBUF_INIT;

	if (compressor == NULL)
		internerr("no compressor specified");

	va_start(args, desc_fmt);
	varbufvprintf(&desc, desc_fmt, args);
	va_end(args);

	compressor->decompress(fd_in, fd_out, desc.buf);

	exit(0);
}

void
compress_filter(struct compressor *compressor, int fd_in, int fd_out,
                int compress_level, const char *desc_fmt, ...)
{
	va_list args;
	struct varbuf desc = VARBUF_INIT;

	if (compressor == NULL)
		internerr("no compressor specified");

	va_start(args, desc_fmt);
	varbufvprintf(&desc, desc_fmt, args);
	va_end(args);

	if (compress_level < 0)
		compress_level = compressor->default_level;
	else if (compress_level == 0)
		compressor = &compressor_none;

	compressor->compress(fd_in, fd_out, compress_level, desc.buf);

	exit(0);
}
