/*
 * dselect - Debian package maintenance user interface
 * dselect.h - external definitions for this program
 *
 * Copyright © 1994,1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef DSELECT_H
#define DSELECT_H

#include <signal.h>

#include <algorithm>

using std::min;
using std::max;

#include <dpkg/debug.h>

#include "dselect-curses.h"

#define DSELECT		"dselect"

#define TOTAL_LIST_WIDTH 180
#define MAX_DISPLAY_INFO 120

struct helpmenuentry {
	char key;
	const struct helpmessage *msg;
};

struct keybindings;

enum screenparts {
	background,
	list,
	listsel,
	title,
	thisstate,
	selstate,
	selstatesel,
	colheads,
	query,
	info_body,
	info_head,
	whatinfo,
	helpscreen,
	numscreenparts,
};

struct column {
	column(): title(nullptr), x(0), width(0)
	{ }
	void blank()
	{
		title = nullptr;
		x = 0;
		width = 0;
	}

	const char *title;
	int x;
	int width;
};

class baselist {
protected:
	// Screen dimensions &c.
	int xmax;
	int ymax;

	int title_height;
	int colheads_height;
	int list_height;
	int thisstate_height;
	int info_height;
	int whatinfo_height;

	int colheads_row;
	int thisstate_row;
	int info_row;
	int whatinfo_row;
	int list_row;

	int part_attr[numscreenparts];

	int gap_width;
	int col_cur_x;
	int total_width;

	void add_column(column &col, const char *title, int width);
	void end_column(column &col, const char *title);
	void draw_column_head(const column &col);
	void draw_column_sep(const column &col, int y);
	void draw_column_item(const column &col, int y, const char *item);

	/*
	 * (n)curses support:
	 * If listpad is null, then we have not started to display yet, and
	 * so none of the auto-displaying update routines need to display.
	 */
	WINDOW *listpad;
	WINDOW *infopad;
	WINDOW *colheadspad;
	WINDOW *thisstatepad;
	WINDOW *titlewin;
	WINDOW *whatinfowin;
	WINDOW *querywin;

	// Window resize handling (via SIGWINCH).
	void resize_window();

	int nitems;
	int ldrawnstart;
	int ldrawnend;
	int showinfo;
	int topofscreen;
	int leftofscreen;
	int cursorline;
	int infotopofscreen;
	int infolines;
	varbuf whatinfovb;
	varbuf searchstring;

	virtual void setheights();
	void unsizes();
	void dosearch();
	void displayhelp(const struct helpmenuentry *menu, int key);
	void displayerror(const char *str);

	void redrawall();
	// Argument start is inclusive, end is exclusive.
	void redrawitemsrange(int start, int end);
	void redraw1item(int index);
	void refreshlist();
	void refreshinfo();
	void refreshcolheads();
	void setcursor(int index);

	void itd_keys();

	virtual void redraw1itemsel(int index, int selected) = 0;
	virtual void redrawcolheads() = 0;
	virtual void redrawthisstate() = 0;
	virtual void redrawinfo() = 0;
	virtual void redrawtitle() = 0;
	virtual void setwidths() = 0;
	virtual const char *itemname(int index) = 0;
	virtual const struct helpmenuentry *helpmenulist() = 0;

	virtual bool checksearch(varbuf &str);
	virtual bool matchsearch(int index);
	void wordwrapinfo(int offset, const char *string);

public:

	keybindings *bindings;

	void kd_up();
	void kd_down();
	void kd_redraw();
	void kd_scrollon();
	void kd_scrollback();
	void kd_scrollon1();
	void kd_scrollback1();
	void kd_panon();
	void kd_panback();
	void kd_panon1();
	void kd_panback1();
	void kd_top();
	void kd_bottom();
	void kd_iscrollon();
	void kd_iscrollback();
	void kd_iscrollon1();
	void kd_iscrollback1();
	void kd_search();
	void kd_searchagain();
	void kd_help();

	void startdisplay();
	void enddisplay();

	explicit baselist(keybindings *);
	virtual ~baselist();
};

void
displayhelp(const struct helpmenuentry *menu, int key);

void
mywerase(WINDOW *win);

void
curseson();
void
cursesoff();

extern bool expertmode;

struct colordata {
	int fore;
	int back;
	int attr;
};
extern colordata color[];

// Evil recommends flag variable.
extern bool manual_install;

enum urqresult {
	urqr_normal,
	urqr_fail,
	urqr_quitmenu,
};
enum quitaction {
	qa_noquit,
	qa_quitchecksave,
	qa_quitnochecksave,
};

typedef urqresult urqfunction(void);
urqfunction urq_list;
urqfunction urq_quit;
urqfunction urq_menu;
urqfunction urq_setup;
urqfunction urq_update;
urqfunction urq_install;
urqfunction urq_config;
urqfunction urq_remove;

#endif /* DSELECT_H */
