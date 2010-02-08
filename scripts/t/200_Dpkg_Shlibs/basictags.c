/*
 * $ gcc -shared -fPIC -Wl,-soname -Wl,libbasictags.so.1 \
 *     -o libbasictags.so.1 -DAMD64 basictags.c
 * $ objdump -wfpTR libbasictags.so.1 > objdump.basictags-amd64
 * $ gcc -shared -fPIC -Wl,-soname -Wl,libbasictags.so.1 \
 *     -o libbasictags.so.1 basictags.c
 * $ objdump -wfpTR libbasictags.so.1 > objdump.basictags-i386
 */

void symbol11_optional() {}

#ifdef AMD64
void symbol21_amd64() {}
#endif

#ifndef AMD64
void symbol22_i386() {}
#endif

void symbol31_randomtag() {}

/* (arch=i386|optional)symbol41_i386_and_optional@Base */
#ifndef AMD64
void symbol41_i386_and_optional() {}
#endif

void symbol51_untagged() {}
