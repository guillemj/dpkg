/*
 * This is free and unencumbered software released into the public domain.

 * Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

 * In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 * For more information, please refer to <https://unlicense.org/>
 */

#include <string.h>
#include <stdlib.h>

#include "pascal_str.h"

struct pascal_str init_pascal_str(const char * s){
	struct pascal_str res;
	if(s){
		res.size = strlen(s);
		res.ptr = malloc(res.size + 1);
		strcpy(res.ptr, s);
	}else{
		res.size = 0;
		res.ptr = NULL;
	}
	return res;
}

struct pascal_str init_nonowning_pascal_str(const char * s){
	struct pascal_str res;
  res.size = strlen(s);
  res.ptr = s;
	return res;
}

void free_pascal_string(struct pascal_str *str){
	free(str->ptr);
	str->ptr = NULL;
	str->size = 0;
}