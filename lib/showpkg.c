/*
 * libdpkg - Debian packaging suite library routines
 * showpkg.c - customizable package listing
 *
 * Copyright (C) 2001 Wichert Akkerman <wakkerma@debian.org>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of version 2 of the GNU General Public
 * License version 2 as published by the Free Software Foundation.
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
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <dpkg.h>
#include <dpkg-db.h>

#include <parsedump.h>


typedef enum { invalid, string, field } itemtype_t;

struct lstitem {
	itemtype_t type;
	size_t width;
	int pad;
	char* data;
	struct lstitem* next;
};


static struct lstitem* alloclstitem(void) {
	struct lstitem*	buf;

	buf=(struct lstitem*)malloc(sizeof(struct lstitem));
	buf->type=invalid;
	buf->next=NULL;
	buf->data=NULL;
	buf->width=0;
	buf->pad=0;

	return buf;
}


static int parsefield(struct lstitem* cur, const char* fmt, const char* fmtend) {
	int len;
	const char* ws;

	len=fmtend-fmt+1;

	ws=(const char*)memchr(fmt, ';', len);
	if (ws) {
		char* endptr;
		long w;

		w=strtol(ws+1,&endptr,0);
		if (endptr[0]!='}') {
			fprintf(stderr, _("invalid character `%c' in field width\n"), *endptr);
			return 0;
		}

		if (w<0) {
			cur->pad=1;
			cur->width=(size_t)-w;
		} else
			cur->width=(size_t)w;

		len=ws-fmt;
	}

	cur->type=field;
	cur->data=(char*)malloc(len+1);
	memcpy(cur->data, fmt, len);
	cur->data[len]='\0';

	return 1;
}


static int parsestring(struct lstitem* cur, const char* fmt, const char* fmtend) {
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

	return 1;
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
			fmtend=strchr(fmt, '}');
			if (!fmtend) {
				fprintf(stderr, _("Closing brace missing in format\n"));
				freeformat(head);
				return NULL;
			}
			cur->type=field;
			if (!parsefield(cur, fmt+2, fmtend-1)) {
				freeformat(head);
				return NULL;
			}
			fmt=fmtend+1;
		} else {
			fmtend=fmt;
			do {
				fmtend+=1;
				fmtend=strchr(fmtend, '$');
			} while (fmtend && fmtend[1]!='{');

			if (!fmtend)
				fmtend=fmt+strlen(fmt);

			if (!parsestring(cur, fmt, fmtend-1)) {
				freeformat(head);
				return NULL;
			}
			fmt=fmtend;
		}
	}

	return head;
}


#define dumpchain(head) {\
	const struct lstitem* ptr = head;\
	while (ptr) {\
		printf("Type: %s\n", (ptr->type==string) ? "string" : "field");\
		printf("Width: %d\n", ptr->width);\
		printf("Data: %s\n", ptr->data);\
		printf("\n");\
		ptr=ptr->next;\
	}\
}\


void show1package(const struct lstitem* head, struct pkginfo *pkg) {
	struct varbuf vb, fb, wb;

	/* Make sure we have package info available, even if it's all empty. */
	if (!pkg->installed.valid)
		blankpackageperfile(&pkg->installed);

	varbufinit(&vb);
	varbufinit(&fb);
	varbufinit(&wb);

	while (head) {
		int ok;
		char fmt[16];

		ok=0;

		if (head->width>0)
			snprintf(fmt,16,"%%%s%ds",
				((head->pad) ? "-" : ""), head->width);
		else
			strcpy(fmt, "%s");

		if (head->type==string) {
			varbufprintf(&fb, fmt, head->data);
			ok=1;
		} else if (head->type==field) {
			const struct fieldinfo* fip;

			for (fip=fieldinfos; fip->name; fip++) 
				if (strcasecmp(head->data, fip->name)==0)  {
					fip->wcall(&wb,pkg,&pkg->installed,0,fip);
					if (!wb.used)
						break;

					varbufaddc(&wb, '\0');
					varbufprintf(&fb, fmt, wb.buf);
					varbufreset(&wb);
					ok=1;
					break;
				}

			if (!fip && pkg->installed.valid) {
				const struct arbitraryfield* afp;

				for (afp=pkg->installed.arbs; afp; afp=afp->next)
					if (strcasecmp(head->data, afp->name)==0) {
						varbufprintf(&fb, fmt, afp->value);
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

	varbuffree(&wb);
	varbuffree(&fb);
	varbuffree(&vb);
}

