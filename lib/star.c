#ifdef HAVE_CONFIG_H
# include <config.h>
#endif
#include <tarfn.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <utime.h>
#include <errno.h>
#include <string.h>
#include <time.h>

static int
Read(void * userData, char * buffer, int length)
{
	/*
	 * If the status of the read function is < 0, it will be returned to
	 * the caller of TarExtractor().
	 */
	return read((int)userData, buffer, length);
}

static int
IOError(TarInfo * i)
{
	int	error = errno;	/* fflush() could cause errno to change */
	fflush(stdout);
	fprintf(stderr, "%s: %s\n", i->Name, strerror(error));

	/*
	 * The status returned by a coroutine of TarExtractor(), if it
	 * is non-zero, will be returned to the caller of TarExtractor().
	 */
	return -2;
}

static int
ExtractFile(TarInfo * i)
{
	/*
	 * If you don't want to extract the file, you must advance the tape
	 * by the file size rounded up to the next 512-byte boundary and
	 * return 0.
	 */

	int	fd = open(i->Name, O_CREAT|O_TRUNC|O_WRONLY, i->Mode & ~S_IFMT);
	char	buffer[512];
	size_t	size = i->Size;
	struct utimbuf t;
		
	if ( fd < 0 )
		return IOError(i);

	printf("File: %s\n", i->Name);

	while ( size > 0 ) {
		size_t	writeSize = size >= 512 ? 512 : size;

		if ( Read(i->UserData, buffer, 512) != 512 )
			return -1;	/* Something wrong with archive */
		if ( write(fd, buffer, writeSize) != writeSize )
			return IOError(i);	/* Write failure. */

		size -= writeSize;
	}
	/* fchown() and fchmod() are cheaper than chown() and chmod(). */
	fchown(fd, i->UserID, i->GroupID);
	fchmod(fd, i->Mode & ~S_IFMT);
	close(fd);
	t.actime = time(0);
	t.modtime = i->ModTime;
	utime(i->Name, &t);
	return 0;
}

static int
SetModes(TarInfo * i)
{
	struct utimbuf t;
#ifdef HAVE_LCHOWN
	lchown(i->Name, i->UserID, i->GroupID);
#else
	chown(i->Name, i->UserID, i->GroupID);
#endif
	chmod(i->Name, i->Mode & ~S_IFMT);
	t.actime = time(0);
	t.modtime = i->ModTime;
	utime(i->Name, &t);
        return 0;
}

static int
MakeDirectory(TarInfo * i)
{
	printf("Directory: %s\n", i->Name);
	if ( mkdir(i->Name, i->Mode & ~S_IFMT) != 0 ) {
		if ( errno == EEXIST ) {
			struct stat s;
			if ( stat(i->Name, &s) != 0 || !(s.st_mode & S_IFDIR) )
				return IOError(i);
		}
		else
			return IOError(i);
	}
	SetModes(i);
        return 0;
}

static int
MakeHardLink(TarInfo * i)
{
	printf("Hard Link: %s\n", i->Name);

	if ( link(i->LinkName, i->Name) != 0 )
		return IOError(i);
	SetModes(i);
        return 0;
}

static int
MakeSymbolicLink(TarInfo * i)
{
	printf("Symbolic Link: %s\n", i->Name);

	if ( symlink(i->LinkName, i->Name) != 0 )
		return -2;
	SetModes(i);
        return 0;
}

static int
MakeSpecialFile(TarInfo * i)
{
	printf("Special File: %s\n", i->Name);

	if ( mknod(i->Name, i->Mode, i->Device) != 0 )
		return -2;
	SetModes(i);
        return 0;
}

static const TarFunctions	functions = {
	Read,
	ExtractFile,
	MakeDirectory,
	MakeHardLink,
	MakeSymbolicLink,
	MakeSpecialFile
};

int
main(int argc, char * * argv)
{
	int	status = TarExtractor((void *)0, &functions);

	if ( status == -1 ) {
		fflush(stdout);
		fprintf(stderr, "Error in archive format.\n");
		return -1;
	}
	else
		return status;
}
