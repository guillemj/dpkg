/*
 * dpkg-query - program to query the package database
 * showpkg.c - customizable package listing
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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <config.h>
#include <dpkg.h>
#include <dpkg-db.h>

#include <parsedump.h>
#include "main.h"


typedef enum { invalid, string, field } itemtype_t;

struct lstitem {
	itemtype_t type;
	size_t width;
	char* data;
	struct lstitem* next;
};


static struct lstitem* alloclstitem() {
	struct lstitem*	buf;

	buf=(struct lstitem*)malloc(sizeof(struct lstitem));
	buf->type=invalid;
	buf->next=NULL;
	buf->data=NULL;
	buf->width=0;

	return buf;
}

static void parsefield(struct lstitem* cur, const char* fmt, const char* fmtend) {
	int len;

	len=fmtend-fmt+1;

	cur->type=field;
	cur->data=(char*)malloc(len+1);
	memcpy(cur->data, fmt, len);
	cur->data[len]='\0';
}

static void parsestring(struct lstitem* cur, const char* fmt, const char* fmtend) {
	int len;
	char* write;

	len=fmtend-fmt+1;

	cur->type=string;
	write=cur->data=(char*)malloc(len+1);
	while (fmt<=fmtend) {
		if (*fmt=='\\') {
			fmt++;
			switch (*fmt) {
				case 'n':
					*write='\n';
					break;
				case 't':
					*write='\t';
					break;
				case 'r':
					*write='\r';
					break;
				case '\\':
				default:
					*write=*fmt;
					break;
			}
		} else
			*write=*fmt;
		write++;
		fmt++;
	}
	*write='\0';
}


void freeformat(struct lstitem* head) {
	struct lstitem* next;

	while (head) {
		next=head->next;
		free(head->data);
		free(head);
		head=next;
	}
}

struct lstitem* parseformat(const char* fmt) {
	struct lstitem* head;
	struct lstitem* cur;
	const char* fmtend;

	head=cur=NULL;
	
	while (*fmt) {
		if (cur)
			cur=cur->next=alloclstitem();
		else
			head=cur=alloclstitem();

		if (fmt[0]=='$' && fmt[1]=='{') {
			fmtend=strchr(fmt, '}');  // TODO: check for not-found
			if (!fmtend) {
				fprintf(stderr, _("Closing brace missing in format\n"));
				freeformat(head);
				return NULL;
			}
			cur->type=field;
			parsefield(cur, fmt+2, fmtend-1);
			fmt=fmtend+1;
		} else {
			fmtend=fmt;
			do {
				fmtend+=1;
				fmtend=strchr(fmtend, '$');
			} while (fmtend && fmtend[1]!='{');

			if (!fmtend)
				fmtend=fmt+strlen(fmt);

			parsestring(cur, fmt, fmtend-1);
			fmt=fmtend;
		}
	}

	return head;
}


static void dumpchain(struct lstitem* head) {
	while (head) {
		printf("Type: %s\n", (head->type==string) ? "string" : "field");
		printf("Width: %d\n", head->width);
		printf("Data: %s\n", head->data);
		printf("\n");
		head=head->next;
	}
}


void show1package(const struct lstitem* head, struct pkginfo *pkg) {
	struct varbuf vb, fb;

	/* Make sure we have package info available, even if it's all empty. */
	if (!pkg->installed.valid)
		blankpackageperfile(&pkg->installed);

	varbufinit(&vb);
	varbufinit(&fb);

	while (head) {
		int ok;

		ok=0;

		if (head->type==string) {
			varbufprintf(&fb, "%s", head->data);
			ok=1;
		} else if (head->type==field) {
			const struct fieldinfo* fip;

			for (fip=fieldinfos; fip->name; fip++) 
				if (strcasecmp(head->data, fip->name)==0)  {
					size_t len;
					char* i;

					fip->wcall(&fb,pkg,&pkg->installed,fip);
					/* Bugger, wcall adds the fieldname and a trailing newline we
					 * do not need. We should probably improve wcall to only do that
					 * optionally, but this will do for now (ie this is a TODO)
					 */
					fb.buf[fb.used-1]='\0';
					i=strchr(fb.buf, ':')+2;
					len=strlen(i)+1;
					memmove(fb.buf, i, len);

					ok=1;
					break;
				}

			if (!fip && pkg->installed.valid) {
				const struct arbitraryfield* afp;

				for (afp=pkg->installed.arbs; afp; afp=afp->next)
					if (strcasecmp(head->data, afp->name)==0) {
						varbufprintf(&fb, "%s", afp->value);
						ok=1;
						break;
					}
			}
		}

		if (ok) {
			size_t len=strlen(fb.buf);
			if ((head->width>0) && (len>head->width))
				len=head->width;
			varbufaddbuf(&vb, fb.buf, len);
		}

		varbufreset(&fb);
		head=head->next;
	}

	if (vb.buf) {
		varbufaddc(&vb, '\0');
		fputs(vb.buf,stdout);
	}

	varbuffree(&fb);
	varbuffree(&vb);
}

