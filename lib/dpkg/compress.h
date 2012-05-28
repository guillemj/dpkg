/*
 * libdpkg - Debian packaging suite library routines
 * compress.h - compression support functions
 *
 * Copyright © 2004 Scott James Remnant <scott@netsplit.com>
 * Copyright © 2006-2012 Guillem Jover <guillem@debian.org>
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

#ifndef LIBDPKG_COMPRESS_H
#define LIBDPKG_COMPRESS_H

#include <dpkg/macros.h>
#include <dpkg/error.h>

#include <stdbool.h>

DPKG_BEGIN_DECLS

/**
 * @defgroup compress Compression
 * @ingroup dpkg-internal
 * @{
 */

enum compressor_type {
	compressor_type_unknown = -1,
	compressor_type_none,
	compressor_type_gzip,
	compressor_type_xz,
	compressor_type_bzip2,
	compressor_type_lzma,
};

enum compressor_strategy {
	compressor_strategy_unknown = -1,
	compressor_strategy_none,
	compressor_strategy_filtered,
	compressor_strategy_huffman,
	compressor_strategy_rle,
	compressor_strategy_fixed,
	compressor_strategy_extreme,
};

struct compress_params {
	enum compressor_type type;
	enum compressor_strategy strategy;
	int level;
};

enum compressor_type compressor_find_by_name(const char *name);
enum compressor_type compressor_find_by_extension(const char *name);

const char *compressor_get_extension(enum compressor_type type);

enum compressor_strategy compressor_get_strategy(const char *name);

bool compressor_check_params(struct compress_params *params,
                             struct dpkg_error *err);

void decompress_filter(enum compressor_type type, int fd_in, int fd_out,
                       const char *desc, ...)
                       DPKG_ATTR_PRINTF(4);
void compress_filter(struct compress_params *params, int fd_in, int fd_out,
                     const char *desc, ...)
                     DPKG_ATTR_PRINTF(4);

/** @} */

DPKG_END_DECLS

#endif /* LIBDPKG_COMPRESS_H */
