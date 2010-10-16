/*
 * libdpkg - Debian packaging suite library routines
 * ehandle.h - error handling
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2000,2001 Wichert Akkerman <wichert@debian.org>
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

#ifndef LIBDPKG_EHANDLE_H
#define LIBDPKG_EHANDLE_H

#include <setjmp.h>
#include <stddef.h>
#include <stdarg.h>

#include <dpkg/macros.h>

DPKG_BEGIN_DECLS

extern const char thisname[]; /* defined separately in each program */

extern volatile int onerr_abort;

enum {
	ehflag_normaltidy = 01,
	ehflag_bombout = 02,
	ehflag_recursiveerror = 04
};

typedef void error_handler(void);
typedef void error_printer(const char *emsg, const char *contextstring);

void print_fatal_error(const char *emsg, const char *contextstring);
void catch_fatal_error(void);

#define push_error_handler push_error_context_jump

void push_error_context_jump(jmp_buf *jbufp, error_printer *printerror,
                             const char *contextstring);
void push_error_context_func(error_handler *func, error_printer *printerror,
                             const char *contextstring);
void error_unwind(int flagset);

void push_cleanup(void (*f1)(int argc, void **argv), int flagmask1,
                  void (*f2)(int argc, void **argv), int flagmask2,
                  unsigned int nargs, ...);
void push_checkpoint(int mask, int value);
void pop_cleanup(int flagset);

void warning(const char *fmt, ...) DPKG_ATTR_PRINTF(1);

void ohshitv(const char *fmt, va_list args)
	DPKG_ATTR_NORET DPKG_ATTR_VPRINTF(1);
void ohshit(const char *fmt, ...) DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1);
void ohshite(const char *fmt, ...) DPKG_ATTR_NORET DPKG_ATTR_PRINTF(1);

void werr(const char *what) DPKG_ATTR_NORET;

void do_internerr(const char *file, int line, const char *fmt, ...)
	DPKG_ATTR_NORET DPKG_ATTR_PRINTF(3);
#define internerr(...) do_internerr(__FILE__, __LINE__, __VA_ARGS__)

DPKG_END_DECLS

#endif /* LIBDPKG_EHANDLE_H */
