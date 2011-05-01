/*
 * libdpkg - Debian packaging suite library routines
 * buffer.c - buffer I/O handling routines
 *
 * Copyright © 1999, 2000 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2000-2003 Adam Heath <doogie@debian.org>
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

#include <config.h>
#include <compat.h>

#include <sys/types.h>

#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/varbuf.h>
#include <dpkg/md5.h>
#include <dpkg/fdio.h>
#include <dpkg/buffer.h>

struct buffer_md5_ctx {
	struct MD5Context ctx;
	char *hash;
};

static void
buffer_md5_init(struct buffer_data *data)
{
	struct buffer_md5_ctx *ctx;

	ctx = m_malloc(sizeof(*ctx));
	ctx->hash = data->arg.ptr;
	data->arg.ptr = ctx;
	MD5Init(&ctx->ctx);
}

static off_t
buffer_init(struct buffer_data *data)
{
	switch (data->type) {
	case BUFFER_WRITE_MD5:
		buffer_md5_init(data);
		break;
	}
	return 0;
}

static void
buffer_md5_done(struct buffer_data *data)
{
	struct buffer_md5_ctx *ctx;
	unsigned char digest[16], *p = digest;
	char *hash;
	int i;

	ctx = (struct buffer_md5_ctx *)data->arg.ptr;
	hash = ctx->hash;
	MD5Final(digest, &ctx->ctx);
	for (i = 0; i < 16; ++i) {
		sprintf(hash, "%02x", *p++);
		hash += 2;
	}
	*hash = '\0';
	free(ctx);
}

static off_t
buffer_done(struct buffer_data *data)
{
	switch (data->type) {
	case BUFFER_WRITE_MD5:
		buffer_md5_done(data);
		break;
	}
	return 0;
}

static off_t
buffer_write(struct buffer_data *data, const void *buf, off_t length)
{
	off_t ret = length;

	switch (data->type) {
	case BUFFER_WRITE_VBUF:
		varbuf_add_buf((struct varbuf *)data->arg.ptr, buf, length);
		break;
	case BUFFER_WRITE_FD:
		ret = fd_write(data->arg.i, buf, length);
		break;
	case BUFFER_WRITE_NULL:
		break;
	case BUFFER_WRITE_MD5:
		MD5Update(&(((struct buffer_md5_ctx *)data->arg.ptr)->ctx), buf, length);
		break;
	default:
		internerr("unknown data type '%i' in buffer_write",
		          data->type);
	}

	return ret;
}

static off_t
buffer_read(struct buffer_data *data, void *buf, off_t length)
{
	off_t ret;

	switch (data->type) {
	case BUFFER_READ_FD:
		ret = fd_read(data->arg.i, buf, length);
		break;
	default:
		internerr("unknown data type '%i' in buffer_read\n",
		          data->type);
	}

	return ret;
}

off_t
buffer_hash(const void *input, void *output, int type, off_t limit)
{
	struct buffer_data data = { .arg.ptr = output, .type = type };
	off_t ret;

	buffer_init(&data);
	ret = buffer_write(&data, input, limit);
	buffer_done(&data);

	return ret;
}

static off_t
buffer_copy(struct buffer_data *read_data, struct buffer_data *write_data,
            off_t limit, const char *desc)
{
	char *buf;
	int bufsize = 32768;
	off_t bytesread = 0, byteswritten = 0;
	off_t totalread = 0, totalwritten = 0;

	if ((limit != -1) && (limit < bufsize))
		bufsize = limit;
	if (bufsize == 0)
		return 0;

	buf = m_malloc(bufsize);

	buffer_init(write_data);

	while (bufsize > 0) {
		bytesread = buffer_read(read_data, buf, bufsize);
		if (bytesread < 0)
			break;
		if (bytesread == 0)
			break;

		totalread += bytesread;

		if (limit != -1) {
			limit -= bytesread;
			if (limit < bufsize)
				bufsize = limit;
		}

		byteswritten = buffer_write(write_data, buf, bytesread);
		if (byteswritten < 0)
			break;
		if (byteswritten == 0)
			break;

		totalwritten += byteswritten;
	}

	if (bytesread < 0)
		ohshite(_("failed to read on buffer copy for %s"), desc);
	if (byteswritten < 0)
		ohshite(_("failed in write on buffer copy for %s"), desc);
	if (limit > 0)
		ohshit(_("short read on buffer copy for %s"), desc);

	buffer_done(write_data);

	free(buf);

	return totalread;
}

off_t
buffer_copy_IntInt(int Iin, int Tin,
                   int Iout, int Tout,
                   off_t limit, const char *desc, ...)
{
	va_list args;
	struct buffer_data read_data = { .type = Tin, .arg.i = Iin };
	struct buffer_data write_data = { .type = Tout, .arg.i = Iout };
	struct varbuf v = VARBUF_INIT;
	off_t ret;

	va_start(args, desc);
	varbuf_vprintf(&v, desc, args);
	va_end(args);

	ret = buffer_copy(&read_data, &write_data, limit, v.buf);

	varbuf_destroy(&v);

	return ret;
}

off_t
buffer_copy_IntPtr(int Iin, int Tin,
                   void *Pout, int Tout,
                   off_t limit, const char *desc, ...)
{
	va_list args;
	struct buffer_data read_data = { .type = Tin, .arg.i = Iin };
	struct buffer_data write_data = { .type = Tout, .arg.ptr = Pout };
	struct varbuf v = VARBUF_INIT;
	off_t ret;

	va_start(args, desc);
	varbuf_vprintf(&v, desc, args);
	va_end(args);

	ret = buffer_copy(&read_data, &write_data, limit, v.buf);

	varbuf_destroy(&v);

	return ret;
}

static off_t
buffer_skip(struct buffer_data *input, off_t limit, const char *desc)
{
	struct buffer_data output;

	switch (input->type) {
	case BUFFER_READ_FD:
		if (lseek(input->arg.i, limit, SEEK_CUR) != -1)
			return limit;
		if (errno != ESPIPE)
			ohshite(_("failed to seek %s"), desc);
		break;
	default:
		internerr("unknown data type '%i' in buffer_skip\n",
		          input->type);
	}

	output.type = BUFFER_WRITE_NULL;
	output.arg.ptr = NULL;

	return buffer_copy(input, &output, limit, desc);
}

off_t
buffer_skip_Int(int I, int T, off_t limit, const char *desc_fmt, ...)
{
	va_list args; \
	struct buffer_data input = { .type = T, .arg.i = I };
	struct varbuf v = VARBUF_INIT;
	off_t ret;

	va_start(args, desc_fmt);
	varbuf_vprintf(&v, desc_fmt, args);
	va_end(args);

	ret = buffer_skip(&input, limit, v.buf);

	varbuf_destroy(&v);

	return ret;
}
