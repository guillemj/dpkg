/*
 * libdpkg - Debian packaging suite library routines
 * dpkg-def.h - C language support definitions
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

#ifndef DPKG_DEF_H
#define DPKG_DEF_H

#include <config.h>

#if HAVE_C_ATTRIBUTE
# define CONSTANT __attribute__((constant))
# define PRINTFFORMAT(si, tc) __attribute__((format(printf,si,tc)))
# define NONRETURNING __attribute__((noreturn))
# define UNUSED __attribute__((unused))
#else
# define CONSTANT
# define PRINTFFORMAT(si, tc)
# define NONRETURNING
# define UNUSED
#endif

#endif
