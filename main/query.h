/*
 * dpkg-query - program to query the package database
 * query.h - external definitions for this program
 *
 * Copyright (C) 2001 Wichert Akkerman <wakkerma@debian.org>
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

#ifndef QUERY_H
#define QUERY_H

struct lstitem;

/* from showpkg.c */
struct lstitem* parseformat(const char* fmt);
void freeformat(struct lstitem* head);
void show1package(const struct lstitem* head, struct pkginfo *pkg);

#endif

