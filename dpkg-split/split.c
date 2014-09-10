/*
 * dpkg-split - splitting and joining of multipart *.deb archives
 * split.c - splitting archives
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008-2011 Guillem Jover <guillem@debian.org>
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

#include <config.h>
#include <compat.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <limits.h>
#include <fcntl.h>
#include <libgen.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/path.h>
#include <dpkg/string.h>
#include <dpkg/subproc.h>
#include <dpkg/buffer.h>
#include <dpkg/ar.h>
#include <dpkg/options.h>

#include "dpkg-split.h"

static char *
deb_field(const char *filename, const char *field)
{
	struct dpkg_error err;
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
		ohshite(_("unable to execute %s (%s)"),
		        _("package field value extraction"), BACKEND);
	}
	close(p[1]);

	/* Parant reads from pipe. */
	varbuf_reset(&buf);
	if (fd_vbuf_copy(p[0], &buf, -1, &err) < 0)
		ohshit(_("cannot extract package field value from '%s': %s"),
		       filename, err.str);
	varbuf_end_str(&buf);

	close(p[0]);

	subproc_reap(pid, _("package field value extraction"), PROCPIPE);

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
mksplit(const char *file_src, const char *prefix, off_t maxpartsize,
        bool msdos)
{
	struct dpkg_error err;
	int fd_src;
	struct stat st;
	char hash[MD5HASHLEN + 1];
	char *package, *version, *arch;
	int nparts, curpart;
	off_t partsize;
	off_t cur_partsize, last_partsize;
	char *prefixdir = NULL, *msdos_prefix = NULL;
	struct varbuf file_dst = VARBUF_INIT;
	struct varbuf partmagic = VARBUF_INIT;
	struct varbuf partname = VARBUF_INIT;

	fd_src = open(file_src, O_RDONLY);
	if (fd_src < 0)
		ohshite(_("unable to open source file `%.250s'"), file_src);
	if (fstat(fd_src, &st))
		ohshite(_("unable to fstat source file"));
	if (!S_ISREG(st.st_mode))
		ohshit(_("source file `%.250s' not a plain file"), file_src);

	if (fd_md5(fd_src, hash, -1, &err) < 0)
		ohshit(_("cannot compute MD5 hash for file '%s': %s"),
		       file_src, err.str);
	lseek(fd_src, 0, SEEK_SET);

	/* FIXME: Use libdpkg-deb. */
	package = deb_field(file_src, "Package");
	version = deb_field(file_src, "Version");
	arch = deb_field(file_src, "Architecture");

	partsize = maxpartsize - HEADERALLOWANCE;
	last_partsize = st.st_size % partsize;
	if (last_partsize == 0)
		last_partsize = partsize;
	nparts = (st.st_size + partsize - 1) / partsize;

	printf(P_("Splitting package %s into %d part: ",
	          "Splitting package %s into %d parts: ", nparts),
	       package, nparts);

	if (msdos) {
		char *t;

		t = m_strdup(prefix);
		prefixdir = m_strdup(dirname(t));
		free(t);

		msdos_prefix = m_strdup(path_basename(prefix));
		prefix = clean_msdos_filename(msdos_prefix);
	}

	for (curpart = 1; curpart <= nparts; curpart++) {
		int fd_dst;

		varbuf_reset(&file_dst);
		/* Generate output filename. */
		if (msdos) {
			char *refname;
			int prefix_max;

			m_asprintf(&refname, "%dof%d", curpart, nparts);
			prefix_max = max(8 - strlen(refname), 0);
			varbuf_printf(&file_dst, "%s/%.*s%.8s.deb",
			              prefixdir, prefix_max, prefix, refname);
			free(refname);
		} else {
			varbuf_printf(&file_dst, "%s.%dof%d.deb",
			              prefix, curpart, nparts);
		}

		if (curpart == nparts)
			cur_partsize = last_partsize;
		else
			cur_partsize = partsize;

		if (cur_partsize > maxpartsize) {
			ohshit(_("header is too long, making part too long; "
			         "the package name or version\n"
			         "numbers must be extraordinarily long, "
			         "or something; giving up"));
		}

		/* Split the data. */
		fd_dst = creat(file_dst.buf, 0644);
		if (fd_dst < 0)
			ohshite(_("unable to open file '%s'"), file_dst.buf);

		/* Write the ar header. */
		dpkg_ar_put_magic(file_dst.buf, fd_dst);

		/* Write the debian-split part. */
		varbuf_printf(&partmagic,
		              "%s\n%s\n%s\n%s\n%jd\n%jd\n%d/%d\n%s\n",
		              SPLITVERSION, package, version, hash,
		              (intmax_t)st.st_size, (intmax_t)partsize,
		              curpart, nparts, arch);
		dpkg_ar_member_put_mem(file_dst.buf, fd_dst, PARTMAGIC,
		                       partmagic.buf, partmagic.used);
		varbuf_reset(&partmagic);

		/* Write the data part. */
		varbuf_printf(&partname, "data.%d", curpart);
		dpkg_ar_member_put_file(file_dst.buf, fd_dst, partname.buf,
		                        fd_src, cur_partsize);
		varbuf_reset(&partname);

		close(fd_dst);

		printf("%d ", curpart);
	}

	varbuf_destroy(&file_dst);
	varbuf_destroy(&partname);
	varbuf_destroy(&partmagic);

	free(package);
	free(version);
	free(arch);

	free(prefixdir);
	free(msdos_prefix);

	close(fd_src);

	printf(_("done\n"));

	return 0;
}

int
do_split(const char *const *argv)
{
	const char *sourcefile, *prefix;

	sourcefile = *argv++;
	if (!sourcefile)
		badusage(_("--split needs a source filename argument"));
	prefix = *argv++;
	if (prefix && *argv)
		badusage(_("--split takes at most a source filename and destination prefix"));
	if (!prefix) {
		size_t sourcefile_len = strlen(sourcefile);

		if (str_match_end(sourcefile, DEBEXT))
			sourcefile_len -= strlen(DEBEXT);

		prefix = nfstrnsave(sourcefile, sourcefile_len);
	}

	mksplit(sourcefile, prefix, opt_maxpartsize, opt_msdos);

	return 0;
}
