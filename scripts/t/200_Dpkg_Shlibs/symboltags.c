/*
 * $ gcc -shared -fPIC -Wl,-soname -Wl,libsymboltags.so.1 \
 *     -o libsymboltags.so.1 -DAMD64 symboltags.c
 * $ objdump -wfpTR libsymboltags.so.1 > objdump.tags-amd64
 * $ gcc -shared -fPIC -Wl,-soname -Wl,libsymboltags.so.1 \
 *     -o libsymboltags.so.1 symboltags.c
 * $ objdump -wfpTR libsymboltags.so.1 > objdump.tags-i386
 */

void symbol11_optional() {}

#ifdef AMD64
void symbol21_amd64() {}
#endif

#ifndef AMD64
void* symbol22_i386() {}
#endif

void symbol31_randomtag() {}

/* (arch=i386|optional)symbol41_i386_and_optional@Base */
#ifndef AMD64
void symbol41_i386_and_optional() {}
#endif

void symbol51_untagged() {}
