/*
 * libdpkg - Debian packaging suite library routines
 * compress.c - compression support functions
 *
 * Copyright © 2000 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2004 Scott James Remnant <scott@netsplit.com>
 * Copyright © 2006-2015 Guillem Jover <guillem@debian.org>
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

#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdlib.h>

#ifdef WITH_LIBZ
#include <zlib.h>
#endif
#ifdef WITH_LIBLZMA
#include <lzma.h>
#endif
#ifdef WITH_LIBBZ2
#include <bzlib.h>
#endif

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/error.h>
#include <dpkg/varbuf.h>
#include <dpkg/fdio.h>
#include <dpkg/buffer.h>
#include <dpkg/command.h>
#include <dpkg/compress.h>
#if !defined(WITH_LIBZ) || !defined(WITH_LIBLZMA) || !defined(WITH_LIBBZ2)
#include <dpkg/subproc.h>

static void DPKG_ATTR_SENTINEL
fd_fd_filter(int fd_in, int fd_out, const char *desc, const char *delenv[],
             const char *file, ...)
{
	va_list args;
	struct command cmd;
	pid_t pid;
	int i;

	pid = subproc_fork();
	if (pid == 0) {
		if (fd_in != 0) {
			m_dup2(fd_in, 0);
			close(fd_in);
		}
		if (fd_out != 1) {
			m_dup2(fd_out, 1);
			close(fd_out);
		}

		for (i = 0; delenv[i]; i++)
			unsetenv(delenv[i]);

		command_init(&cmd, file, desc);
		command_add_arg(&cmd, file);
		va_start(args, file);
		command_add_argv(&cmd, args);
		va_end(args);

		command_exec(&cmd);
	}
	subproc_reap(pid, desc, 0);
}
#endif

struct compressor {
	const char *name;
	const char *extension;
	int default_level;
	void (*fixup_params)(struct compress_params *params);
	void (*compress)(int fd_in, int fd_out, struct compress_params *params,
	                 const char *desc);
	void (*decompress)(int fd_in, int fd_out, const char *desc);
};

/*
 * No compressor (pass-through).
 */

static void
fixup_none_params(struct compress_params *params)
{
}

static void
decompress_none(int fd_in, int fd_out, const char *desc)
{
	struct dpkg_error err;

	if (fd_fd_copy(fd_in, fd_out, -1, &err) < 0)
		ohshit(_("%s: pass-through copy error: %s"), desc, err.str);
}

static void
compress_none(int fd_in, int fd_out, struct compress_params *params, const char *desc)
{
	struct dpkg_error err;

	if (fd_fd_copy(fd_in, fd_out, -1, &err) < 0)
		ohshit(_("%s: pass-through copy error: %s"), desc, err.str);
}

static const struct compressor compressor_none = {
	.name = "none",
	.extension = "",
	.default_level = 0,
	.fixup_params = fixup_none_params,
	.compress = compress_none,
	.decompress = decompress_none,
};

/*
 * Gzip compressor.
 */

#define GZIP		"gzip"

static void
fixup_gzip_params(struct compress_params *params)
{
	/* Normalize compression level. */
	if (params->level == 0)
		params->type = COMPRESSOR_TYPE_NONE;
}

#ifdef WITH_LIBZ
static void
decompress_gzip(int fd_in, int fd_out, const char *desc)
{
	char buffer[DPKG_BUFFER_SIZE];
	gzFile gzfile = gzdopen(fd_in, "r");

	if (gzfile == NULL)
		ohshit(_("%s: error binding input to gzip stream"), desc);

	for (;;) {
		int actualread, actualwrite;

		actualread = gzread(gzfile, buffer, sizeof(buffer));
		if (actualread < 0) {
			int z_errnum = 0;
			const char *errmsg = gzerror(gzfile, &z_errnum);

			if (z_errnum == Z_ERRNO)
				errmsg = strerror(errno);
			ohshit(_("%s: internal gzip read error: '%s'"), desc,
			       errmsg);
		}
		if (actualread == 0) /* EOF. */
			break;

		actualwrite = fd_write(fd_out, buffer, actualread);
		if (actualwrite != actualread)
			ohshite(_("%s: internal gzip write error"), desc);
	}

	if (close(fd_out))
		ohshite(_("%s: internal gzip write error"), desc);
}

static void
compress_gzip(int fd_in, int fd_out, struct compress_params *params, const char *desc)
{
	char buffer[DPKG_BUFFER_SIZE];
	char combuf[6];
	int strategy;
	int z_errnum;
	gzFile gzfile;

	if (params->strategy == COMPRESSOR_STRATEGY_FILTERED)
		strategy = 'f';
	else if (params->strategy == COMPRESSOR_STRATEGY_HUFFMAN)
		strategy = 'h';
	else if (params->strategy == COMPRESSOR_STRATEGY_RLE)
		strategy = 'R';
	else if (params->strategy == COMPRESSOR_STRATEGY_FIXED)
		strategy = 'F';
	else
		strategy = ' ';

	snprintf(combuf, sizeof(combuf), "w%d%c", params->level, strategy);
	gzfile = gzdopen(fd_out, combuf);
	if (gzfile == NULL)
		ohshit(_("%s: error binding output to gzip stream"), desc);

	for (;;) {
		int actualread, actualwrite;

		actualread = fd_read(fd_in, buffer, sizeof(buffer));
		if (actualread < 0)
			ohshite(_("%s: internal gzip read error"), desc);
		if (actualread == 0) /* EOF. */
			break;

		actualwrite = gzwrite(gzfile, buffer, actualread);
		if (actualwrite != actualread) {
			const char *errmsg = gzerror(gzfile, &z_errnum);

			if (z_errnum == Z_ERRNO)
				errmsg = strerror(errno);
			ohshit(_("%s: internal gzip write error: '%s'"), desc,
			       errmsg);
		}
	}

	z_errnum = gzclose(gzfile);
	if (z_errnum) {
		const char *errmsg;

		if (z_errnum == Z_ERRNO)
			errmsg = strerror(errno);
		else
			errmsg = zError(z_errnum);
		ohshit(_("%s: internal gzip write error: %s"), desc, errmsg);
	}
}
#else
static const char *env_gzip[] = { "GZIP", NULL };

static void
decompress_gzip(int fd_in, int fd_out, const char *desc)
{
	fd_fd_filter(fd_in, fd_out, desc, env_gzip, GZIP, "-dc", NULL);
}

static void
compress_gzip(int fd_in, int fd_out, struct compress_params *params, const char *desc)
{
	char combuf[6];

	snprintf(combuf, sizeof(combuf), "-c%d", params->level);
	fd_fd_filter(fd_in, fd_out, desc, env_gzip, GZIP, "-n", combuf, NULL);
}
#endif

static const struct compressor compressor_gzip = {
	.name = "gzip",
	.extension = ".gz",
	.default_level = 9,
	.fixup_params = fixup_gzip_params,
	.compress = compress_gzip,
	.decompress = decompress_gzip,
};

/*
 * Bzip2 compressor.
 */

#define BZIP2		"bzip2"

static void
fixup_bzip2_params(struct compress_params *params)
{
	/* Normalize compression level. */
	if (params->level == 0)
		params->level = 1;
}

#ifdef WITH_LIBBZ2
static void
decompress_bzip2(int fd_in, int fd_out, const char *desc)
{
	char buffer[DPKG_BUFFER_SIZE];
	BZFILE *bzfile = BZ2_bzdopen(fd_in, "r");

	if (bzfile == NULL)
		ohshit(_("%s: error binding input to bzip2 stream"), desc);

	for (;;) {
		int actualread, actualwrite;

		actualread = BZ2_bzread(bzfile, buffer, sizeof(buffer));
		if (actualread < 0) {
			int bz_errnum = 0;
			const char *errmsg = BZ2_bzerror(bzfile, &bz_errnum);

			if (bz_errnum == BZ_IO_ERROR)
				errmsg = strerror(errno);
			ohshit(_("%s: internal bzip2 read error: '%s'"), desc,
			       errmsg);
		}
		if (actualread == 0) /* EOF. */
			break;

		actualwrite = fd_write(fd_out, buffer, actualread);
		if (actualwrite != actualread)
			ohshite(_("%s: internal bzip2 write error"), desc);
	}

	if (close(fd_out))
		ohshite(_("%s: internal bzip2 write error"), desc);
}

static void
compress_bzip2(int fd_in, int fd_out, struct compress_params *params, const char *desc)
{
	char buffer[DPKG_BUFFER_SIZE];
	char combuf[6];
	int bz_errnum;
	BZFILE *bzfile;

	snprintf(combuf, sizeof(combuf), "w%d", params->level);
	bzfile = BZ2_bzdopen(fd_out, combuf);
	if (bzfile == NULL)
		ohshit(_("%s: error binding output to bzip2 stream"), desc);

	for (;;) {
		int actualread, actualwrite;

		actualread = fd_read(fd_in, buffer, sizeof(buffer));
		if (actualread < 0)
			ohshite(_("%s: internal bzip2 read error"), desc);
		if (actualread == 0) /* EOF. */
			break;

		actualwrite = BZ2_bzwrite(bzfile, buffer, actualread);
		if (actualwrite != actualread) {
			const char *errmsg = BZ2_bzerror(bzfile, &bz_errnum);

			if (bz_errnum == BZ_IO_ERROR)
				errmsg = strerror(errno);
			ohshit(_("%s: internal bzip2 write error: '%s'"), desc,
			       errmsg);
		}
	}

	BZ2_bzWriteClose(&bz_errnum, bzfile, 0, NULL, NULL);
	if (bz_errnum != BZ_OK) {
		const char *errmsg = _("unexpected bzip2 error");

		if (bz_errnum == BZ_IO_ERROR)
			errmsg = strerror(errno);
		ohshit(_("%s: internal bzip2 write error: '%s'"), desc,
		       errmsg);
	}

	/* Because BZ2_bzWriteClose has done a fflush on the file handle,
	 * doing a close on the file descriptor associated with it should
	 * be safe™. */
	if (close(fd_out))
		ohshite(_("%s: internal bzip2 write error"), desc);
}
#else
static const char *env_bzip2[] = { "BZIP", "BZIP2", NULL };

static void
decompress_bzip2(int fd_in, int fd_out, const char *desc)
{
	fd_fd_filter(fd_in, fd_out, desc, env_bzip2, BZIP2, "-dc", NULL);
}

static void
compress_bzip2(int fd_in, int fd_out, struct compress_params *params, const char *desc)
{
	char combuf[6];

	snprintf(combuf, sizeof(combuf), "-c%d", params->level);
	fd_fd_filter(fd_in, fd_out, desc, env_bzip2, BZIP2, combuf, NULL);
}
#endif

static const struct compressor compressor_bzip2 = {
	.name = "bzip2",
	.extension = ".bz2",
	.default_level = 9,
	.fixup_params = fixup_bzip2_params,
	.compress = compress_bzip2,
	.decompress = decompress_bzip2,
};

/*
 * Xz compressor.
 */

#define XZ		"xz"

#ifdef WITH_LIBLZMA
enum dpkg_stream_status {
	DPKG_STREAM_INIT	= DPKG_BIT(1),
	DPKG_STREAM_RUN		= DPKG_BIT(2),
	DPKG_STREAM_COMPRESS	= DPKG_BIT(3),
	DPKG_STREAM_DECOMPRESS	= DPKG_BIT(4),
	DPKG_STREAM_FILTER	= DPKG_STREAM_COMPRESS | DPKG_STREAM_DECOMPRESS,
};

/* XXX: liblzma does not expose error messages. */
static const char *
dpkg_lzma_strerror(lzma_ret code, enum dpkg_stream_status status)
{
	const char *const impossible = _("internal error (bug)");

	switch (code) {
	case LZMA_MEM_ERROR:
		return strerror(ENOMEM);
	case LZMA_MEMLIMIT_ERROR:
		if (status & DPKG_STREAM_RUN)
			return _("memory usage limit reached");
		return impossible;
	case LZMA_OPTIONS_ERROR:
		if (status == (DPKG_STREAM_INIT | DPKG_STREAM_COMPRESS))
			return _("unsupported compression preset");
		if (status == (DPKG_STREAM_RUN | DPKG_STREAM_DECOMPRESS))
			return _("unsupported options in file header");
		return impossible;
	case LZMA_DATA_ERROR:
		if (status & DPKG_STREAM_RUN)
			return _("compressed data is corrupt");
		return impossible;
	case LZMA_BUF_ERROR:
		if (status & DPKG_STREAM_RUN)
			return _("unexpected end of input");
		return impossible;
	case LZMA_FORMAT_ERROR:
		if (status == (DPKG_STREAM_RUN | DPKG_STREAM_DECOMPRESS))
			return _("file format not recognized");
		return impossible;
	case LZMA_UNSUPPORTED_CHECK:
		if (status == (DPKG_STREAM_INIT | DPKG_STREAM_COMPRESS))
			return _("unsupported type of integrity check");
		return impossible;
	default:
		return impossible;
	}
}

struct io_lzma {
	const char *desc;

	struct compress_params *params;
	enum dpkg_stream_status status;
	lzma_action action;

	void (*init)(struct io_lzma *io, lzma_stream *s);
	int (*code)(struct io_lzma *io, lzma_stream *s);
	void (*done)(struct io_lzma *io, lzma_stream *s);
};

static void
filter_lzma(struct io_lzma *io, int fd_in, int fd_out)
{
	uint8_t buf_in[DPKG_BUFFER_SIZE];
	uint8_t buf_out[DPKG_BUFFER_SIZE];
	lzma_stream s = LZMA_STREAM_INIT;
	lzma_ret ret;

	s.next_out = buf_out;
	s.avail_out = sizeof(buf_out);

	io->action = LZMA_RUN;
	io->status = DPKG_STREAM_INIT;
	io->init(io, &s);
	io->status = (io->status & DPKG_STREAM_FILTER) | DPKG_STREAM_RUN;

	do {
		ssize_t len;

		if (s.avail_in == 0 && io->action != LZMA_FINISH) {
			len = fd_read(fd_in, buf_in, sizeof(buf_in));
			if (len < 0)
				ohshite(_("%s: lzma read error"), io->desc);
			if (len == 0)
				io->action = LZMA_FINISH;
			s.next_in = buf_in;
			s.avail_in = len;
		}

		ret = io->code(io, &s);

		if (s.avail_out == 0 || ret == LZMA_STREAM_END) {
			len = fd_write(fd_out, buf_out, s.next_out - buf_out);
			if (len < 0)
				ohshite(_("%s: lzma write error"), io->desc);
			s.next_out = buf_out;
			s.avail_out = sizeof(buf_out);
		}
	} while (ret != LZMA_STREAM_END);

	io->done(io, &s);

	if (close(fd_out))
		ohshite(_("%s: lzma close error"), io->desc);
}

static void DPKG_ATTR_NORET
filter_lzma_error(struct io_lzma *io, lzma_ret ret)
{
	ohshit(_("%s: lzma error: %s"), io->desc,
	       dpkg_lzma_strerror(ret, io->status));
}

static void
filter_unxz_init(struct io_lzma *io, lzma_stream *s)
{
	uint64_t memlimit = UINT64_MAX;
	lzma_ret ret;

	io->status |= DPKG_STREAM_DECOMPRESS;

	ret = lzma_stream_decoder(s, memlimit, 0);
	if (ret != LZMA_OK)
		filter_lzma_error(io, ret);
}

static void
filter_xz_init(struct io_lzma *io, lzma_stream *s)
{
	uint32_t preset;
	lzma_check check = LZMA_CHECK_CRC64;
#ifdef HAVE_LZMA_MT
	lzma_mt mt_options = {
		.flags = 0,
		.threads = sysconf(_SC_NPROCESSORS_ONLN),
		.block_size = 0,
		.timeout = 0,
		.filters = NULL,
		.check = check,
	};
#endif
	lzma_ret ret;

	io->status |= DPKG_STREAM_COMPRESS;

	preset = io->params->level;
	if (io->params->strategy == COMPRESSOR_STRATEGY_EXTREME)
		preset |= LZMA_PRESET_EXTREME;

#ifdef HAVE_LZMA_MT
	mt_options.preset = preset;
	ret = lzma_stream_encoder_mt(s, &mt_options);
#else
	ret = lzma_easy_encoder(s, preset, check);
#endif

	if (ret != LZMA_OK)
		filter_lzma_error(io, ret);
}

static int
filter_lzma_code(struct io_lzma *io, lzma_stream *s)
{
	lzma_ret ret;

	ret = lzma_code(s, io->action);
	if (ret != LZMA_OK && ret != LZMA_STREAM_END)
		filter_lzma_error(io, ret);

	return ret;
}

static void
filter_lzma_done(struct io_lzma *io, lzma_stream *s)
{
	lzma_end(s);
}

static void
decompress_xz(int fd_in, int fd_out, const char *desc)
{
	struct io_lzma io;

	io.init = filter_unxz_init;
	io.code = filter_lzma_code;
	io.done = filter_lzma_done;
	io.desc = desc;

	filter_lzma(&io, fd_in, fd_out);
}

static void
compress_xz(int fd_in, int fd_out, struct compress_params *params, const char *desc)
{
	struct io_lzma io;

	io.init = filter_xz_init;
	io.code = filter_lzma_code;
	io.done = filter_lzma_done;
	io.desc = desc;
	io.params = params;

	filter_lzma(&io, fd_in, fd_out);
}
#else
static const char *env_xz[] = { "XZ_DEFAULTS", "XZ_OPT", NULL };

static void
decompress_xz(int fd_in, int fd_out, const char *desc)
{
	fd_fd_filter(fd_in, fd_out, desc, env_xz, XZ, "-dc", NULL);
}

static void
compress_xz(int fd_in, int fd_out, struct compress_params *params, const char *desc)
{
	char combuf[6];
	const char *strategy;

	if (params->strategy == COMPRESSOR_STRATEGY_EXTREME)
		strategy = "-e";
	else
		strategy = NULL;

	snprintf(combuf, sizeof(combuf), "-c%d", params->level);
	fd_fd_filter(fd_in, fd_out, desc, env_xz, XZ, combuf, strategy, NULL);
}
#endif

static const struct compressor compressor_xz = {
	.name = "xz",
	.extension = ".xz",
	.default_level = 6,
	.fixup_params = fixup_none_params,
	.compress = compress_xz,
	.decompress = decompress_xz,
};

/*
 * Lzma compressor.
 */

#ifdef WITH_LIBLZMA
static void
filter_unlzma_init(struct io_lzma *io, lzma_stream *s)
{
	uint64_t memlimit = UINT64_MAX;
	lzma_ret ret;

	io->status |= DPKG_STREAM_DECOMPRESS;

	ret = lzma_alone_decoder(s, memlimit);
	if (ret != LZMA_OK)
		filter_lzma_error(io, ret);
}

static void
filter_lzma_init(struct io_lzma *io, lzma_stream *s)
{
	uint32_t preset;
	lzma_options_lzma options;
	lzma_ret ret;

	io->status |= DPKG_STREAM_COMPRESS;

	preset = io->params->level;
	if (io->params->strategy == COMPRESSOR_STRATEGY_EXTREME)
		preset |= LZMA_PRESET_EXTREME;
	if (lzma_lzma_preset(&options, preset))
		filter_lzma_error(io, LZMA_OPTIONS_ERROR);

	ret = lzma_alone_encoder(s, &options);
	if (ret != LZMA_OK)
		filter_lzma_error(io, ret);
}

static void
decompress_lzma(int fd_in, int fd_out, const char *desc)
{
	struct io_lzma io;

	io.init = filter_unlzma_init;
	io.code = filter_lzma_code;
	io.done = filter_lzma_done;
	io.desc = desc;

	filter_lzma(&io, fd_in, fd_out);
}

static void
compress_lzma(int fd_in, int fd_out, struct compress_params *params, const char *desc)
{
	struct io_lzma io;

	io.init = filter_lzma_init;
	io.code = filter_lzma_code;
	io.done = filter_lzma_done;
	io.desc = desc;
	io.params = params;

	filter_lzma(&io, fd_in, fd_out);
}
#else
static void
decompress_lzma(int fd_in, int fd_out, const char *desc)
{
	fd_fd_filter(fd_in, fd_out, desc, env_xz, XZ, "-dc", "--format=lzma", NULL);
}

static void
compress_lzma(int fd_in, int fd_out, struct compress_params *params, const char *desc)
{
	char combuf[6];

	snprintf(combuf, sizeof(combuf), "-c%d", params->level);
	fd_fd_filter(fd_in, fd_out, desc, env_xz, XZ, combuf, "--format=lzma", NULL);
}
#endif

static const struct compressor compressor_lzma = {
	.name = "lzma",
	.extension = ".lzma",
	.default_level = 6,
	.fixup_params = fixup_none_params,
	.compress = compress_lzma,
	.decompress = decompress_lzma,
};

/*
 * Generic compressor filter.
 */

static const struct compressor *compressor_array[] = {
	[COMPRESSOR_TYPE_NONE] = &compressor_none,
	[COMPRESSOR_TYPE_GZIP] = &compressor_gzip,
	[COMPRESSOR_TYPE_XZ] = &compressor_xz,
	[COMPRESSOR_TYPE_BZIP2] = &compressor_bzip2,
	[COMPRESSOR_TYPE_LZMA] = &compressor_lzma,
};

static const struct compressor *
compressor(enum compressor_type type)
{
	const enum compressor_type max_type = array_count(compressor_array);

	if (type < 0 || type >= max_type)
		internerr("compressor_type %d is out of range", type);

	return compressor_array[type];
}

const char *
compressor_get_name(enum compressor_type type)
{
	return compressor(type)->name;
}

const char *
compressor_get_extension(enum compressor_type type)
{
	return compressor(type)->extension;
}

enum compressor_type
compressor_find_by_name(const char *name)
{
	size_t i;

	for (i = 0; i < array_count(compressor_array); i++)
		if (strcmp(compressor_array[i]->name, name) == 0)
			return i;

	return COMPRESSOR_TYPE_UNKNOWN;
}

enum compressor_type
compressor_find_by_extension(const char *extension)
{
	size_t i;

	for (i = 0; i < array_count(compressor_array); i++)
		if (strcmp(compressor_array[i]->extension, extension) == 0)
			return i;

	return COMPRESSOR_TYPE_UNKNOWN;
}

enum compressor_strategy
compressor_get_strategy(const char *name)
{
	if (strcmp(name, "none") == 0)
		return COMPRESSOR_STRATEGY_NONE;
	if (strcmp(name, "filtered") == 0)
		return COMPRESSOR_STRATEGY_FILTERED;
	if (strcmp(name, "huffman") == 0)
		return COMPRESSOR_STRATEGY_HUFFMAN;
	if (strcmp(name, "rle") == 0)
		return COMPRESSOR_STRATEGY_RLE;
	if (strcmp(name, "fixed") == 0)
		return COMPRESSOR_STRATEGY_FIXED;
	if (strcmp(name, "extreme") == 0)
		return COMPRESSOR_STRATEGY_EXTREME;

	return COMPRESSOR_STRATEGY_UNKNOWN;
}

static void
compressor_fixup_params(struct compress_params *params)
{
	compressor(params->type)->fixup_params(params);

	if (params->level < 0)
		params->level = compressor(params->type)->default_level;
}

bool
compressor_check_params(struct compress_params *params, struct dpkg_error *err)
{
	compressor_fixup_params(params);

	if (params->strategy == COMPRESSOR_STRATEGY_NONE)
		return true;

	if (params->type == COMPRESSOR_TYPE_GZIP &&
	    (params->strategy == COMPRESSOR_STRATEGY_FILTERED ||
	     params->strategy == COMPRESSOR_STRATEGY_HUFFMAN ||
	     params->strategy == COMPRESSOR_STRATEGY_RLE ||
	     params->strategy == COMPRESSOR_STRATEGY_FIXED))
		return true;

	if (params->type == COMPRESSOR_TYPE_XZ &&
	    params->strategy == COMPRESSOR_STRATEGY_EXTREME)
		return true;

	dpkg_put_error(err, _("unknown compression strategy"));
	return false;
}

void
decompress_filter(enum compressor_type type, int fd_in, int fd_out,
                  const char *desc_fmt, ...)
{
	va_list args;
	struct varbuf desc = VARBUF_INIT;

	va_start(args, desc_fmt);
	varbuf_vprintf(&desc, desc_fmt, args);
	va_end(args);

	compressor(type)->decompress(fd_in, fd_out, desc.buf);

	varbuf_destroy(&desc);
}

void
compress_filter(struct compress_params *params, int fd_in, int fd_out,
                const char *desc_fmt, ...)
{
	va_list args;
	struct varbuf desc = VARBUF_INIT;

	va_start(args, desc_fmt);
	varbuf_vprintf(&desc, desc_fmt, args);
	va_end(args);

	compressor(params->type)->compress(fd_in, fd_out, params, desc.buf);

	varbuf_destroy(&desc);
}
