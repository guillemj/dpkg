/*
 * Functions for extracting tar archives.
 * Bruce Perens, April-May 1995
 * Copyright © 1995 Bruce Perens
 * This is free software under the GNU General Public License.
 */

#include <config.h>
#include <compat.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <pwd.h>
#include <grp.h>
#include <errno.h>

#include <dpkg/macros.h>
#include <dpkg/dpkg.h>
#include <dpkg/tarfn.h>

#define TAR_MAGIC_USTAR "ustar\0" "00"
#define TAR_MAGIC_GNU   "ustar "  " \0"

struct TarHeader {
	char Name[100];
	char Mode[8];
	char UserID[8];
	char GroupID[8];
	char Size[12];
	char ModificationTime[12];
	char Checksum[8];
	char LinkFlag;
	char LinkName[100];
	char MagicNumber[8];
	char UserName[32];
	char GroupName[32];
	char MajorDevice[8];
	char MinorDevice[8];
	char Prefix[155];	/* Only valid on ustar. */
};
typedef struct TarHeader TarHeader;

static const size_t TarChecksumOffset = offsetof(TarHeader, Checksum);

/* Octal-ASCII-to-long */
static long
OtoL(const char *s, int size)
{
	int n = 0;

	while (*s == ' ') {
		s++;
		size--;
	}

	while (--size >= 0 && *s >= '0' && *s <= '7')
		n = (n * 010) + (*s++ - '0');

	return n;
}

/* String block to C null-terminated string */
static char *
StoC(const char *s, int size)
{
	int len;
	char *str;

	len = strnlen(s, size);
	str = m_malloc(len + 1);
	memcpy(str, s, len);
	str[len] = '\0';

	return str;
}

/* FIXME: Rewrite using varbuf, once it supports the needed functionality. */
static char *
get_prefix_name(TarHeader *h)
{
	char *prefix, *name, *s;

	/* The size is not going to be bigger than that. */
	s = m_malloc(257);

	prefix = StoC(h->Prefix, sizeof(h->Prefix));
	name = StoC(h->Name, sizeof(h->Name));

	strcpy(s, prefix);
	strcat(s, "/");
	strcat(s, name);

	free(prefix);
	free(name);

	return s;
}

static int
DecodeTarHeader(char * block, TarInfo * d)
{
	TarHeader *h = (TarHeader *)block;
	unsigned char *s = (unsigned char *)block;
	struct passwd *passwd = NULL;
	struct group *group = NULL;
	unsigned int i;
	long sum;
	long checksum;

	if (memcmp(h->MagicNumber, TAR_MAGIC_GNU, 6) == 0)
		d->format = tar_format_gnu;
	else if (memcmp(h->MagicNumber, TAR_MAGIC_USTAR, 6) == 0)
		d->format = tar_format_ustar;
	else
		d->format = tar_format_old;

	if (*h->UserName)
		passwd = getpwnam(h->UserName);
	if (*h->GroupName)
		group = getgrnam(h->GroupName);

	/* Concatenate prefix and name to support ustar style long names. */
	if (d->format == tar_format_ustar && h->Prefix[0] != '\0')
		d->Name = get_prefix_name(h);
	else
		d->Name = StoC(h->Name, sizeof(h->Name));
	d->LinkName = StoC(h->LinkName, sizeof(h->LinkName));
	d->Mode = (mode_t)OtoL(h->Mode, sizeof(h->Mode));
	d->Size = (size_t)OtoL(h->Size, sizeof(h->Size));
	d->ModTime = (time_t)OtoL(h->ModificationTime,
	                          sizeof(h->ModificationTime));
	d->Device = ((OtoL(h->MajorDevice,
	                   sizeof(h->MajorDevice)) & 0xff) << 8) |
	            (OtoL(h->MinorDevice, sizeof(h->MinorDevice)) & 0xff);
	checksum = OtoL(h->Checksum, sizeof(h->Checksum));
	d->UserID = (uid_t)OtoL(h->UserID, sizeof(h->UserID));
	d->GroupID = (gid_t)OtoL(h->GroupID, sizeof(h->GroupID));
	d->Type = (TarFileType)h->LinkFlag;

	if (passwd)
		d->UserID = passwd->pw_uid;

	if (group)
		d->GroupID = group->gr_gid;

	/* Treat checksum field as all blank. */
	sum = ' ' * sizeof(h->Checksum);
	for (i = TarChecksumOffset; i > 0; i--)
		sum += *s++;
	/* Skip the real checksum field. */
	s += sizeof(h->Checksum);
	for (i = (512 - TarChecksumOffset - sizeof(h->Checksum)); i > 0; i--)
		sum += *s++;

	return (sum == checksum);
}

typedef struct symlinkList {
	TarInfo h;
	struct symlinkList *next;
} symlinkList;

int
TarExtractor(void *userData, const TarFunctions *functions)
{
	int status;
	char buffer[512];
	TarInfo h;

	char *next_long_name, *next_long_link;
	char *bp;
	char **longp;
	int long_read;
	symlinkList *symlink_head, *symlink_tail, *symlink_node;

	next_long_name = NULL;
	next_long_link = NULL;
	long_read = 0;
	symlink_tail = symlink_node = symlink_head = m_malloc(sizeof(symlinkList));
	symlink_head->next = NULL;

	h.Name = NULL;
	h.LinkName = NULL;
	h.UserData = userData;

	while ((status = functions->Read(userData, buffer, 512)) == 512) {
		int nameLength;

		if (!DecodeTarHeader(buffer, &h)) {
			if (h.Name[0] == '\0') {
				/* End of tape. */
				status = 0;
			} else {
				/* Indicates broken tarfile:
				 * “Header checksum error”. */
				errno = 0;
				status = -1;
			}
			break;
		}
		if (h.Type != GNU_LONGLINK && h.Type != GNU_LONGNAME) {
			if (next_long_name)
				h.Name = next_long_name;

			if (next_long_link)
				h.LinkName = next_long_link;

			next_long_link = NULL;
			next_long_name = NULL;
		}

		if (h.Name[0] == '\0') {
			/* Indicates broken tarfile: “Bad header data”. */
			errno = 0;
			status = -1;
			break;
		}

		nameLength = strlen(h.Name);

		switch (h.Type) {
		case NormalFile0:
		case NormalFile1:
			/* Compatibility with pre-ANSI ustar. */
			if (h.Name[nameLength - 1] != '/') {
				status = (*functions->ExtractFile)(&h);
				break;
			}
			/* Else, fall through. */
		case Directory:
			if (h.Name[nameLength - 1] == '/') {
				h.Name[nameLength - 1] = '\0';
			}
			status = (*functions->MakeDirectory)(&h);
			break;
		case HardLink:
			status = (*functions->MakeHardLink)(&h);
			break;
		case SymbolicLink:
			memcpy(&symlink_tail->h, &h, sizeof(TarInfo));
			symlink_tail->h.Name = m_strdup(h.Name);
			symlink_tail->h.LinkName = m_strdup(h.LinkName);
			symlink_tail->next = m_malloc(sizeof(symlinkList));

			symlink_tail = symlink_tail->next;
			symlink_tail->next = NULL;
			status = 0;
			break;
		case CharacterDevice:
		case BlockDevice:
		case FIFO:
			status = (*functions->MakeSpecialFile)(&h);
			break;
		case GNU_LONGLINK:
		case GNU_LONGNAME:
			/* Set longp to the location of the long filename or
			 * link we're trying to deal with. */
			longp = ((h.Type == GNU_LONGNAME) ?
			         &next_long_name :
			         &next_long_link);

			if (*longp)
				free(*longp);

			*longp = m_malloc(h.Size);
			bp = *longp;

			/* The way the GNU long{link,name} stuff works is like
			 * this:
			 *
			 * The first header is a “dummy” header that contains
			 *   the size of the filename.
			 * The next N headers contain the filename.
			 * After the headers with the filename comes the
			 *   “real” header with a bogus name or link. */
			for (long_read = h.Size;
			     long_read > 0;
			     long_read -= 512) {
				int copysize;

				status = functions->Read(userData, buffer, 512);
				/* If we didn't get 512 bytes read, punt. */
				if (512 != status) {
					 /* Read partial header record? */
					if (status > 0) {
						errno = 0;
						status = -1;
					}
					break;
				}
				copysize = min(long_read, 512);
				memcpy (bp, buffer, copysize);
				bp += copysize;
			};

			/* This decode function expects status to be 0 after
			 * the case statement if we successfully decoded. I
			 * guess what we just did was successful. */
			status = 0;
			break;
		default:
			/* Indicates broken tarfile: “Bad header field”. */
			errno = 0;
			status = -1;
		}
		if (status != 0)
			/* Pass on status from coroutine. */
			break;
	}

	while (symlink_node->next) {
		if (status == 0)
			status = (*functions->MakeSymbolicLink)(&symlink_node->h);
		symlink_tail = symlink_node->next;
		free(symlink_node->h.Name);
		free(symlink_node->h.LinkName);
		free(symlink_node);
		symlink_node = symlink_tail;
	}
	free(symlink_node);
	free(h.Name);
	free(h.LinkName);

	if (status > 0) {
		/* Indicates broken tarfile: “Read partial header record”. */
		errno = 0;
		return -1;
	} else {
		/* Return whatever I/O function returned. */
		return status;
	}
}

