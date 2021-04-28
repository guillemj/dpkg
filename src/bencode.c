/*
 * This is free and unencumbered software released into the public domain.

 * Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

 * In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 * For more information, please refer to <https://unlicense.org/>
 */

#include <stdio.h>

#include "bencode.h"

size_t measure_benc_pascal_str(struct pascal_str *s){
	return snprintf(NULL, 0, "%zu:", s->size) + s->size;
}

void serialize_benc_pascal_str(char **serPtr, struct pascal_str *s){
	*serPtr += sprintf(*serPtr, "%zu:%s", s->size, s->ptr);
}
void serialize_benc_tag(char **serPtr, char tag){
	*serPtr += sprintf(*serPtr, "1:%c", tag);
}

void serialize_benc_tag_value_pair(char **serPtr, char tag, struct pascal_str *s){
	if(s->ptr){
		serialize_benc_tag(serPtr, tag);
		serialize_benc_pascal_str(serPtr, s);
	}
}


size_t measure_benc_tag_value_pair(struct pascal_str *s){
	if(s->ptr){
		return measure_benc_pascal_str(s) + OUR_BENC_KEY_TAG_SIZE;
	} else {
		return 0;
	}
}
