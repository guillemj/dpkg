/* This program ensures that dpkg-divert and update-alternatives don't depend on POSIX.pm
 * being available and usable. This is probably a good thing since the perl packages have
 * known deficiencies to ensure that during upgrades. */

#include <stdio.h>
#include <errno.h>

int main(int argc, char** argv) {
	printf("%d", ENOENT);
	return 0;
}

