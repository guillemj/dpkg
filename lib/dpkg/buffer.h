/*
 * libdpkg - Debian packaging suite library routines
 * buffer.h - buffer I/O handling routines
 *
 * Copyright © 1999, 2000 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2000-2003 Adam Heath <doogie@debian.org>
 * Copyright © 2005 Scott James Remnant
 * Copyright © 2008, 2009 Guillem Jover <guillem@debian.org>
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

#ifndef LIBDPKG_BUFFER_H
#define LIBDPKG_BUFFER_H

#include <sys/types.h>

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

#define BUFFER_WRITE_BUF		0
#define BUFFER_WRITE_VBUF		1
#define BUFFER_WRITE_FD			2
#define BUFFER_WRITE_NULL		3
#define BUFFER_WRITE_MD5		5

#define BUFFER_READ_FD			0

struct buffer_data {
	union {
		void *ptr;
		int i;
	} arg;
	int type;
};

# define buffer_md5(buf, hash, limit) \
	buffer_hash(buf, hash, BUFFER_WRITE_MD5, limit)

# define fd_md5(fd, hash, limit, ...) \
	buffer_copy_IntPtr(fd, BUFFER_READ_FD, hash, BUFFER_WRITE_MD5, \
	                   limit, __VA_ARGS__)
# define fd_fd_copy(fd1, fd2, limit, ...) \
	buffer_copy_IntInt(fd1, BUFFER_READ_FD, fd2, BUFFER_WRITE_FD, \
	                   limit, __VA_ARGS__)
# define fd_buf_copy(fd, buf, limit, ...) \
	buffer_copy_IntPtr(fd, BUFFER_READ_FD, buf, BUFFER_WRITE_BUF, \
	                   limit, __VA_ARGS__)
# define fd_vbuf_copy(fd, buf, limit, ...) \
	buffer_copy_IntPtr(fd, BUFFER_READ_FD, buf, BUFFER_WRITE_VBUF, \
	                   limit, __VA_ARGS__)
# define fd_null_copy(fd, limit, ...) \
	if (lseek(fd, limit, SEEK_CUR) == -1) { \
		if (errno != ESPIPE) \
			ohshite(__VA_ARGS__); \
		buffer_copy_IntPtr(fd, BUFFER_READ_FD, \
		                   NULL, BUFFER_WRITE_NULL, \
		                   limit, __VA_ARGS__); \
	}

off_t buffer_copy_PtrInt(void *p, int typeIn, int i, int typeOut,
                         off_t limit, const char *desc,
                         ...) DPKG_ATTR_PRINTF(6);
off_t buffer_copy_PtrPtr(void *p1, int typeIn, void *p2, int typeOut,
                         off_t limit, const char *desc,
                         ...) DPKG_ATTR_PRINTF(6);
off_t buffer_copy_IntPtr(int i, int typeIn, void *p, int typeOut,
                         off_t limit, const char *desc,
                         ...) DPKG_ATTR_PRINTF(6);
off_t buffer_copy_IntInt(int i1, int typeIn, int i2, int typeOut,
                         off_t limit, const char *desc,
                         ...) DPKG_ATTR_PRINTF(6);
off_t buffer_hash(const void *buf, void *hash, int typeOut, off_t length);

off_t buffer_write(struct buffer_data *data, const void *buf, off_t length);
off_t buffer_read(struct buffer_data *data, void *buf, off_t length);
off_t buffer_init(struct buffer_data *read_data,
                  struct buffer_data *write_data);
off_t buffer_done(struct buffer_data *read_data,
                  struct buffer_data *write_data);
off_t buffer_copy(struct buffer_data *read_data,
                  struct buffer_data *write_data,
                  off_t limit, const char *desc);

DPKG_END_DECLS

#endif /* LIBDPKG_BUFFER_H */
