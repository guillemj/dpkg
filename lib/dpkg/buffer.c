/*
 * libdpkg - Debian packaging suite library routines
 * buffer.c - buffer I/O handling routines
 *
 * Copyright © 1999, 2000 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2000-2003 Adam Heath <doogie@debian.org>
 * Copyright © 2008, 2009 Guillem Jover <guillem@debian.org>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2,
 * or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with dpkg; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>
#include <compat.h>

#include <dpkg/i18n.h>

#include <sys/types.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

#include <dpkg/dpkg.h>
#include <dpkg/varbuf.h>
#include <dpkg/md5.h>
#include <dpkg/buffer.h>

struct buffer_write_md5ctx {
	struct MD5Context ctx;
	unsigned char **hash;
};

static void
buffer_md5_init(buffer_data_t data)
{
	struct buffer_write_md5ctx *ctx;

	ctx = m_malloc(sizeof(struct buffer_write_md5ctx));
	ctx->hash = data->data.ptr;
	data->data.ptr = ctx;
	MD5Init(&ctx->ctx);
}

off_t
buffer_init(buffer_data_t read_data, buffer_data_t write_data)
{
	switch (write_data->type) {
	case BUFFER_WRITE_MD5:
		buffer_md5_init(write_data);
		break;
	}
	return 0;
}

static void
buffer_md5_done(buffer_data_t data)
{
	struct buffer_write_md5ctx *ctx;
	unsigned char digest[16], *p = digest;
	unsigned char *hash;
	int i;

	ctx = (struct buffer_write_md5ctx *)data->data.ptr;
	*ctx->hash = hash = m_malloc(MD5HASHLEN + 1);
	MD5Final(digest, &ctx->ctx);
	for (i = 0; i < 16; ++i) {
		sprintf((char *)hash, "%02x", *p++);
		hash += 2;
	}
	*hash = '\0';
	free(ctx);
}

off_t
buffer_done(buffer_data_t read_data, buffer_data_t write_data)
{
	switch (write_data->type) {
	case BUFFER_WRITE_MD5:
		buffer_md5_done(write_data);
		break;
	}
	return 0;
}

off_t
buffer_write(buffer_data_t data, void *buf, off_t length, const char *desc)
{
	off_t ret = length;

	switch (data->type) {
	case BUFFER_WRITE_BUF:
		memcpy(data->data.ptr, buf, length);
		data->data.ptr += length;
		break;
	case BUFFER_WRITE_VBUF:
		varbufaddbuf((struct varbuf *)data->data.ptr, buf, length);
		break;
	case BUFFER_WRITE_FD:
		ret = write(data->data.i, buf, length);
		if (ret < 0 && errno != EINTR)
			ohshite(_("failed in buffer_write(fd) (%i, ret=%li): %s"),
			        data->data.i, (long)ret, desc);
		break;
	case BUFFER_WRITE_NULL:
		break;
	case BUFFER_WRITE_STREAM:
		ret = fwrite(buf, 1, length, (FILE *)data->data.ptr);
		if (feof((FILE *)data->data.ptr))
			ohshite(_("eof in buffer_write(stream): %s"), desc);
		if(ferror((FILE *)data->data.ptr))
			ohshite(_("error in buffer_write(stream): %s"), desc);
		break;
	case BUFFER_WRITE_MD5:
		MD5Update(&(((struct buffer_write_md5ctx *)data->data.ptr)->ctx), buf, length);
		break;
	default:
		fprintf(stderr, _("unknown data type `%i' in buffer_write\n"),
		        data->type);
	}

	return ret;
}

off_t
buffer_read(buffer_data_t data, void *buf, off_t length, const char *desc)
{
	off_t ret = length;

	switch (data->type) {
	case BUFFER_READ_FD:
		ret = read(data->data.i, buf, length);
		if(ret < 0 && errno != EINTR)
			ohshite(_("failed in buffer_read(fd): %s"), desc);
		break;
	case BUFFER_READ_STREAM:
		ret = fread(buf, 1, length, (FILE *)data->data.ptr);
		if (feof((FILE *)data->data.ptr))
			return ret;
		if (ferror((FILE *)data->data.ptr))
			ohshite(_("error in buffer_read(stream): %s"), desc);
		break;
	default:
		fprintf(stderr, _("unknown data type `%i' in buffer_read\n"),
		        data->type);
	}

	return ret;
}

#define buffer_copy_TYPE(name, type1, name1, type2, name2) \
off_t \
buffer_copy_##name(type1 n1, int typeIn, \
                   type2 n2, int typeOut, \
                   off_t limit, const char *desc, ...) \
{ \
	va_list al; \
	struct buffer_data read_data, write_data; \
	struct varbuf v = VARBUF_INIT; \
	off_t ret; \
\
	read_data.data.name1 = n1; \
	read_data.type = typeIn; \
	write_data.data.name2 = n2; \
	write_data.type = typeOut; \
\
	va_start(al, desc); \
	varbufvprintf(&v, desc, al); \
	va_end(al); \
\
	buffer_init(&read_data, &write_data); \
	ret = buffer_copy(&read_data, &write_data, limit, v.buf); \
	buffer_done(&read_data, &write_data); \
\
	varbuffree(&v); \
\
	return ret; \
}

buffer_copy_TYPE(IntInt, int, i, int, i);
buffer_copy_TYPE(IntPtr, int, i, void *, ptr);
buffer_copy_TYPE(PtrInt, void *, ptr, int, i);
buffer_copy_TYPE(PtrPtr, void *, ptr, void *, ptr);

off_t
buffer_copy(buffer_data_t read_data, buffer_data_t write_data,
            off_t limit, const char *desc)
{
	char *buf, *writebuf;
	int bufsize = 32768;
	long bytesread = 0, byteswritten = 0;
	off_t totalread = 0, totalwritten = 0;

	if ((limit != -1) && (limit < bufsize))
		bufsize = limit;
	if (bufsize == 0)
		return 0;

	writebuf = buf = m_malloc(bufsize);

	while (bytesread >= 0 && byteswritten >= 0 && bufsize > 0) {
		bytesread = buffer_read(read_data, buf, bufsize, desc);
		if (bytesread < 0) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			break;
		}
		if (bytesread == 0)
			break;

		totalread += bytesread;
		if (limit != -1) {
			limit -= bytesread;
			if (limit < bufsize)
				bufsize = limit;
		}
		writebuf = buf;
		while (bytesread) {
			byteswritten = buffer_write(write_data, writebuf, bytesread, desc);
			if (byteswritten == -1) {
				if (errno == EINTR || errno == EAGAIN)
					continue;
				break;
			}
			if (byteswritten == 0)
				break;

			bytesread -= byteswritten;
			totalwritten += byteswritten;
			writebuf += byteswritten;
		}
	}

	if (bytesread < 0 || byteswritten < 0)
		ohshite(_("failed in buffer_copy (%s)"), desc);
	if (limit > 0)
		ohshit(_("short read in buffer_copy (%s)"), desc);

	free(buf);

	return totalread;
}

