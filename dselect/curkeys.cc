/*
 * dselect - Debian package maintenance user interface
 * curkeys.cc - list of ncurses keys for name <-> key mapping
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
#include <dpkg.h>
#include <dpkg-db.h>
}
#include "dselect.h"
#include "bindings.h"

const keybindings::keyname keybindings::keynames[] = {
#include "curkeys.h"
};
