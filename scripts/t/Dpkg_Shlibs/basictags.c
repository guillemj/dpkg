/*
 * $ gcc -shared -fPIC -Wl,-soname -Wl,libbasictags.so.1 \
 *     -o libbasictags.so.1 -DAMD64 basictags.c
 * $ objdump -wfpTR libbasictags.so.1 > objdump.basictags-amd64
 * $ gcc -shared -fPIC -Wl,-soname -Wl,libbasictags.so.1 \
 *     -o libbasictags.so.1 basictags.c
 * $ objdump -wfpTR libbasictags.so.1 > objdump.basictags-i386
 */

void symbol11_optional(void);
void symbol11_optional(void) {}

#ifdef AMD64
void symbol21_amd64(void);
void symbol21_amd64(void) {}
#endif

#ifndef AMD64
void symbol22_i386(void);
void symbol22_i386(void) {}
#endif

void symbol31_randomtag(void);
void symbol31_randomtag(void) {}

/* (arch=i386|optional)symbol41_i386_and_optional@Base */
#ifndef AMD64
void symbol41_i386_and_optional(void);
void symbol41_i386_and_optional(void) {}
#endif

void symbol51_untagged(void);
void symbol51_untagged(void) {}
