/*
 * dselect - Debian package maintenance user interface
 * method.h - access method handling declarations
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2001 Wichert Akkerman <wakkerma@debian.org>
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

#ifndef METHOD_H
#define METHOD_H

#define CMETHOPTFILE		"cmethopt"
#define METHLOCKFILE		"methlock"

#define METHODSDIR		"methods"

#define IMETHODMAXLEN		50
#define IOPTIONMAXLEN		IMETHODMAXLEN
#define METHODOPTIONSFILE	"names"
#define METHODSETUPSCRIPT	"setup"
#define METHODUPDATESCRIPT	"update"
#define METHODINSTALLSCRIPT	"install"
#define OPTIONSDESCPFX		"desc."
#define OPTIONINDEXMAXLEN	5

struct method {
  struct method *next, *prev;
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
  int status_width, name_width, description_width;
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

void readmethods(const char *pathbase, dselect_option **optionspp, int *nread);
void getcurrentopt();
void writecurrentopt();

#endif /* METHOD_H */
