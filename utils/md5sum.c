/*
 * md5sum.c	- Generate/check MD5 Message Digests
 *
 * Compile and link with md5.c.  If you don't have getopt() in your library
 * also include getopt.c.  For MSDOS you can also link with the wildcard
 * initialization function (wildargs.obj for Turbo C and setargv.obj for MSC)
 * so that you can use wildcards on the commandline.
 *
 * Written March 1993 by Branko Lankester
 * Modified June 1993 by Colin Plumb for altered md5.c.
 * Modified Feburary 1995 by Ian Jackson for use with Colin Plumb's md5.c.
 * Hacked (modified is too nice a word) January 1997 by Galen Hazelwood
 *   to support GNU gettext.
 * This file is in the public domain.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <unistd.h>

#include "config.h"

/* Take care of NLS matters.  */

#if HAVE_LOCALE_H
# include <locale.h>
#endif
#if !HAVE_SETLOCALE
# define setlocale(Category, Locale) /* empty */
#endif

#if ENABLE_NLS
# include <libintl.h>
# define _(Text) gettext (Text)
#else
# undef bindtextdomain
# define bindtextdomain(Domain, Directory) /* empty */
# undef textdomain
# define textdomain(Domain) /* empty */
# define _(Text) Text
#endif

#include <dpkg.h>

#ifdef UNIX
#define	FOPRTXT	"r"
#define	FOPRBIN	"r"
#else
#ifdef VMS
#define	FOPRTXT	"r","ctx=stm"
#define	FOPRBIN	"rb","ctx=stm"
#else
#define	FOPRTXT	"r"
#define	FOPRBIN	"rb"
#endif
#endif

extern char *optarg;
extern int optind;
const char printforhelp[]= N_("Type md5sum --help for help.");
const char thisname[]= MD5SUM;

void usage(void);
void print_digest(unsigned char *p);
int mdfile(int fd, unsigned char *digest);
int do_check(FILE *chkf);
int hex_digit(int c);
int get_md5_line(FILE *fp, unsigned char *digest, char *file);

char *progname;
int verbose = 0;
int bin_mode = 0;

int
main(int argc, char **argv)
{
	int opt, rc = 0;
	int check = 0;
	FILE *fp = NULL;
	unsigned char digest[16];

	setlocale(LC_ALL, "");
	bindtextdomain(PACKAGE, LOCALEDIR);
	textdomain(PACKAGE);

	progname = *argv;
	while ((opt = getopt(argc, argv, "cbvp:h")) != EOF) {
		switch (opt) {
			case 'c': check = 1; break;
			case 'v': verbose = 1; break;
			case 'b': bin_mode = 1; break;
			default: usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (check) {
		switch (argc) {
			case 0: fp = stdin; break;
			case 1: if ((fp = fopen(*argv, FOPRTXT)) == NULL) {
					perror(*argv);
					exit(2);
				}
				break;
			default: usage();
		}
		exit(do_check(fp));
	}
	if (argc == 0) {
		if (mdfile(fileno(stdin), digest)) {
			fprintf(stderr, _("%s: read error on stdin\n"), progname);
			exit(2);
		}
		printf("%s\n", digest);
		exit(0);
	}
	for ( ; argc > 0; --argc, ++argv) {
		if (bin_mode)
			fp = fopen(*argv, FOPRBIN);
		else
			fp = fopen(*argv, FOPRTXT);
		if (fp == NULL) {
			perror(*argv);
			rc = 2;
			continue;
		}
		if (mdfile(fileno(fp), digest)) {
			fprintf(stderr, _("%s: error reading %s\n"), progname, *argv);
			rc = 2;
		} else {
			printf("%s %c%s\n", digest, bin_mode ? '*' : ' ', *argv);
		}
		fclose(fp);
	}
	exit(rc);
}

void
usage()
{
        fputs(_("usage: md5sum [-bv] [-c [file]] | [file...]\n\
Generates or checks MD5 Message Digests\n\
    -c  check message digests (default is generate)\n\
    -v  verbose, print file names when checking\n\
    -b  read files in binary mode\n\
The input for -c should be the list of message digests and file names\n\
that is printed on stdout by this program when it generates digests.\n"), stderr);
	exit(2);
}

int
mdfile(int fd, unsigned char *digest)
{
	ssize_t ret = fd_md5(fd, digest, -1, _("mdfile"));
	if ( ret >= 0 )
		return 0;
	else
		return ret;
}

int
hex_digit(int c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	return -1;
}

int
get_md5_line(FILE *fp, unsigned char *digest, char *file)
{
	char buf[1024];
	int i, d1, d2, rc;
	char *p = buf;

	if (fgets(buf, sizeof(buf), fp) == NULL)
		return -1;

	for (i = 0; i < 16; ++i) {
		if ((d1 = hex_digit(*p++)) == -1)
			return 0;
		if ((d2 = hex_digit(*p++)) == -1)
			return 0;
		*digest++ = d1*16 + d2;
	}
	if (*p++ != ' ')
		return 0;
	/*
	 * next char is an attribute char, space means text file
	 * if it's a '*' the file should be checked in binary mode.
	 */
	if (*p == ' ')
		rc = 1;
	else if (*p == '*')
		rc = 2;
	else {
		fprintf(stderr, _("%s: unrecognized line: %s"), progname, buf);
		return 0;
	}
	++p;
	i = strlen(p);
	if (i < 2 || i > 255)
		return 0;
	p[i-1] = '\0';
	strcpy(file, p);
	return rc;
}

int
do_check(FILE *chkf)
{
	int rc, ex = 0, failed = 0, checked = 0;
	unsigned char chk_digest[16], file_digest[16];
	char filename[256];
	FILE *fp;
	int flen = 14;

	while ((rc = get_md5_line(chkf, chk_digest, filename)) >= 0) {
		if (rc == 0)	/* not an md5 line */
			continue;
		if (verbose) {
			if (strlen(filename) > flen)
				flen = strlen(filename);
			fprintf(stderr, "%-*s ", flen, filename);
		}
		if (bin_mode || rc == 2)
			fp = fopen(filename, FOPRBIN);
		else
			fp = fopen(filename, FOPRTXT);
		if (fp == NULL) {
			fprintf(stderr, _("%s: can't open %s\n"), progname, filename);
			ex = 2;
			continue;
		}
		if (mdfile(fileno(fp), file_digest)) {
			fprintf(stderr, _("%s: error reading %s\n"), progname, filename);
			ex = 2;
			fclose(fp);
			continue;
		}
		fclose(fp);
		if (memcmp(chk_digest, file_digest, 16) != 0) {
			if (verbose)
				fprintf(stderr, _("FAILED\n"));
			else
				fprintf(stderr, _("%s: MD5 check failed for '%s'\n"), progname, filename);
			++failed;
		} else if (verbose)
			fprintf(stderr, _("OK\n"));
		++checked;
	}
	if (verbose && failed)
		fprintf(stderr, _("%s: %d of %d file(s) failed MD5 check\n"), progname, failed, checked);
	if (!checked) {
		fprintf(stderr, _("%s: no files checked\n"), progname);
		return 3;
	}
	if (!ex && failed)
		ex = 1;
	return ex;
}

