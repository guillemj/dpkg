/* -*- c++ -*-
 * dselect - Debian package maintenance user interface
 * method.h - access method handling declarations
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 20001 Wichert Akkerman <wakkerma@debian.org>
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

#ifndef METHOD_H
#define METHOD_H

struct method {
  struct method *next, *back;
  char *name, *path, *pathinmeth;
};

struct dselect_option {
  dselect_option *next;
  method *meth;
  char index[OPTIONINDEXMAXLEN];
  char *name, *summary;
  char *description;
};

class methodlist : public baselist {
protected:
  int status_width, gap_width, name_width, description_width;
  int name_column, description_column;

  // Table of methods
  struct dselect_option **table;

  // Misc.
  char searchstring[50];
  
  // Information displays
  void itd_description();
  
  // Define these virtuals
  void redraw1itemsel(int index, int selected);
  void redrawcolheads();
  void redrawthisstate();
  void redrawinfo();
  void redrawtitle();
  void setwidths();
  void setheights();
  const char *itemname(int index);
  const struct helpmenuentry *helpmenulist();

 public:
  // Keybinding functions */
  void kd_quit();
  void kd_abort();
  
  methodlist();
  quitaction display();
  ~methodlist();
};

extern int noptions;
extern struct dselect_option *options, *coption;
extern struct method *methods;

extern void readmethods(const char *pathbase, dselect_option **optionspp, int *nread);
extern void getcurrentopt();
extern void writecurrentopt();

#endif /* METHOD_H */
