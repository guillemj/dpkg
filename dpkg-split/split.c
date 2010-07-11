/*
 * dpkg-split - splitting and joining of multipart *.deb archives
 * split.c - splitting archives
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2010 Guillem Jover <guillem@debian.org>
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

#include <config.h>
#include <compat.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <limits.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/subproc.h>
#include <dpkg/buffer.h>
#include <dpkg/ar.h>
#include <dpkg/myopt.h>

#include "dpkg-split.h"

static char *
deb_field(const char *filename, const char *field)
{
	pid_t pid;
	int p[2];
	struct varbuf buf = VARBUF_INIT;
	char *end;

	m_pipe(p);

	pid = subproc_fork();
	if (pid == 0) {
		/* Child writes to pipe. */
		m_dup2(p[1], 1);
		close(p[0]);
		close(p[1]);

		execlp(BACKEND, BACKEND, "--field", filename, field, NULL);
		ohshite(_("failed to exec dpkg-deb to extract field value"));
	}
	close(p[1]);

	/* Parant reads from pipe. */
	varbufreset(&buf);
	fd_vbuf_copy(p[0], &buf, -1, _("dpkg-deb field extraction"));
	varbufaddc(&buf, '\0');

	close(p[0]);

	subproc_wait_check(pid, _("dpkg-deb field extraction"), PROCPIPE);

	/* Trim down trailing junk. */
	for (end = buf.buf + strlen(buf.buf) - 1; end - buf.buf >= 1; end--)
		if (isspace(*end))
			*end = '\0';
		else
			break;

	return varbuf_detach(&buf);
}

/* Cleanup filename for use in crippled msdos systems. */
static char *
clean_msdos_filename(char *filename)
{
	char *d, *s;

	for (s = d = filename; *s; d++, s++) {
		if (*s == '+')
			*d = 'x';
		else if (isupper(*s))
			*d = tolower(*s);
		else if (islower(*s) || isdigit(*s))
			*d = *s;
		else
			s++;
	}

	return filename;
}

static int
mksplit(const char *file_src, const char *prefix, size_t partsize,
        size_t maxpartsize, bool msdos)
{
	int fd_src;
	struct stat st;
	char hash[MD5HASHLEN + 1];
	char *package, *version;
	int nparts, curpart;
	off_t startat;
	char *prefixdir = NULL, *msdos_prefix = NULL;
	struct varbuf file_dst = VARBUF_INIT;
	struct varbuf partmagic = VARBUF_INIT;
	struct varbuf partname = VARBUF_INIT;
	char *partdata;

	fd_src = open(file_src, O_RDONLY);
	if (fd_src < 0)
		ohshite(_("unable to open source file `%.250s'"), file_src);
	if (fstat(fd_src, &st))
		ohshite(_("unable to fstat source file"));
	if (!S_ISREG(st.st_mode))
		ohshit(_("source file `%.250s' not a plain file"), file_src);

	fd_md5(fd_src, hash, -1, "md5hash");
	lseek(fd_src, 0, SEEK_SET);

	/* FIXME: Use libdpkg-deb. */
	package = deb_field(file_src, "Package");
	version = deb_field(file_src, "Version");

	nparts = (st.st_size + partsize - 1) / partsize;

	setvbuf(stdout, NULL, _IONBF, 0);

	printf("Splitting package %s into %d parts: ", package, nparts);

	if (msdos) {
		char *t;

		t = m_strdup(prefix);
		prefixdir = m_strdup(dirname(t));
		free(t);

		t = m_strdup(prefix);
		msdos_prefix = m_strdup(basename(t));
		free(t);

		prefix = clean_msdos_filename(msdos_prefix);
	}

	partdata = m_malloc(partsize);
	curpart = 1;

	for (startat = 0; startat < st.st_size; startat += partsize) {
		int fd_dst;
		ssize_t partrealsize;

		varbufreset(&file_dst);
		/* Generate output filename. */
		if (msdos) {
			struct varbuf refname = VARBUF_INIT;
			int prefix_max;

			varbufprintf(&refname, "%dof%d", curpart, nparts);
			prefix_max = max(8 - strlen(refname.buf), 0);
			varbufprintf(&file_dst, "%s/%.*s%.8s.deb",
			             prefixdir, prefix_max, prefix,
			             refname.buf);
			varbuf_destroy(&refname);
		} else {
			varbufprintf(&file_dst, "%s.%dof%d.deb",
			             prefix, curpart, nparts);
		}

		/* Read data from the original package. */
		partrealsize = read(fd_src, partdata, partsize);
		if (partrealsize < 0)
			ohshite("mksplit: read");

		if ((size_t)partrealsize > maxpartsize) {
			ohshit("Header is too long, making part too long. "
			       "Your package name or version\n"
			       "numbers must be extraordinarily long, "
			       "or something. Giving up.\n");
		}

		/* Split the data. */
		fd_dst = open(file_dst.buf, O_CREAT | O_WRONLY, 0644);
		if (fd_dst < 0)
			ohshite(_("unable to open file '%s'"), file_dst.buf);

		/* Write the ar header. */
		dpkg_ar_put_magic(file_dst.buf, fd_dst);

		/* Write the debian-split part. */
		varbufprintf(&partmagic, "%s\n%s\n%s\n%s\n%zu\n%zu\n%d/%d\n",
		             SPLITVERSION, package, version, hash,
		             st.st_size, partsize, curpart, nparts);
		dpkg_ar_member_put_mem(file_dst.buf, fd_dst, PARTMAGIC,
		                       partmagic.buf, partmagic.used);
		varbufreset(&partmagic);

		/* Write the data part. */
		varbufprintf(&partname, "data.%d", curpart);
		dpkg_ar_member_put_mem(file_dst.buf, fd_dst, partname.buf,
		                       partdata, (size_t)partrealsize);
		varbufreset(&partname);

		close(fd_dst);

		printf("%d ", curpart);

		curpart++;
	}

	varbuf_destroy(&file_dst);
	varbuf_destroy(&partname);
	varbuf_destroy(&partmagic);
	free(partdata);

	free(prefixdir);
	free(msdos_prefix);

	close(fd_src);

	printf("done\n");

	return 0;
}

void
do_split(const char *const *argv)
{
	const char *sourcefile, *prefix;
	char *palloc;
	int l;
	size_t partsize;

	sourcefile = *argv++;
	if (!sourcefile)
		badusage(_("--split needs a source filename argument"));
	prefix = *argv++;
	if (prefix && *argv)
		badusage(_("--split takes at most a source filename and destination prefix"));
	if (!prefix) {
		l = strlen(sourcefile);
		palloc = nfmalloc(l + 1);
		strcpy(palloc, sourcefile);
		if (!strcmp(palloc + l - (sizeof(DEBEXT) - 1), DEBEXT)) {
			l -= (sizeof(DEBEXT) - 1);
			palloc[l] = '\0';
		}
		prefix = palloc;
	}
	partsize = opt_maxpartsize - HEADERALLOWANCE;

	mksplit(sourcefile, prefix, partsize, opt_maxpartsize, opt_msdos);

	exit(0);
}
