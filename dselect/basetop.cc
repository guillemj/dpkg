/*
 * dselect - Debian package maintenance user interface
 * bdrawtop.cc - base list class redraw of top
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
 * License along with this; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */
extern "C" {
#include <config.h>
}
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <ctype.h>

extern "C" {
#include <dpkg.h>
#include <dpkg-db.h>
}
#include "dselect.h"

void baselist::refreshlist() {
  redrawitemsrange(topofscreen,lesserint(nitems,topofscreen+list_height));
  int y, x, maxy, maxx;
  y= lesserint(list_row + list_height - 1,
               list_row + nitems - topofscreen - 1);
  x= lesserint(total_width - leftofscreen - 1,
               xmax - 1);
  pnoutrefresh(listpad, topofscreen,leftofscreen, list_row,0, y,x);
  getmaxyx(listpad,maxy,maxx);
  y++;
  while (y < list_row + list_height - 1) {
    pnoutrefresh(listpad, maxy-1,leftofscreen, y,0, y,x);
    y++;
  }
}

void baselist::redrawitemsrange(int start, int end) {
  if (ldrawnstart==-1) { ldrawnstart= ldrawnend= end; }
  while (ldrawnstart > start) { ldrawnstart--; redraw1item(ldrawnstart); }
  while (ldrawnend < end) { redraw1item(ldrawnend); ldrawnend++; }
}

void baselist::refreshcolheads() {
  pnoutrefresh(colheadspad, 0,leftofscreen, colheads_row,0,
               colheads_row, lesserint(total_width - leftofscreen - 1, xmax - 1));
}
