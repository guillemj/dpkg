#include <stdlib.h>

#include "pascal_str.h"
#include "bencode.h"

#include "triggerer_info_passthrough.h"
#include <dpkg/ehandle.h>



struct passed_through_package_info passed_through_package_info_init(void){
	struct passed_through_package_info unpackedInfo;
	unpackedInfo.count = 0;
	unpackedInfo.records = NULL;
	return unpackedInfo;
}


void free_passed_through_package_info_record(struct passed_through_package_info_record *r){
	free_pascal_string(&r->name);
	free_pascal_string(&r->arch);
	free_pascal_string(&r->version);
}

void passed_through_package_info_free(struct passed_through_package_info *unpackedInfo){
	for(unsigned short int i = 0; i< unpackedInfo->count; ++i){
		free_passed_through_package_info_record(&unpackedInfo->records[i]);
	}
	free(unpackedInfo->records);
	unpackedInfo->records = NULL;
	unpackedInfo->count = 0;
}

void passed_through_package_info_emplace_internal(struct passed_through_package_info_record * rec, struct pkginfo *pkg, struct pascal_str (*pascal_str_ctor)(char *)){
  rec->name = pascal_str_ctor(pkg->set->name);
  rec->version = pascal_str_ctor(pkg->available.version.version);
  rec->arch = pascal_str_ctor(pkg->available.arch->name);
  rec->origin = pascal_str_ctor(pkg->available.origin);
}

void passed_through_package_info_emplace(struct passed_through_package_info_record * rec, struct pkginfo *pkg){
  passed_through_package_info_emplace_internal(rec, pkg, init_pascal_str);
}

void passed_through_package_info_nonowning_emplace(struct passed_through_package_info_record * rec, struct pkginfo *pkg){
  passed_through_package_info_emplace_internal(rec, pkg, init_nonowning_pascal_str);
}

void passed_through_package_info_append(struct passed_through_package_info *unpackedInfo, struct pkginfo *pkg){
  if(!unpackedInfo)
    return;

	struct passed_through_package_info_record * rec;
	unsigned int prevCountAndIndex = unpackedInfo->count;
	unpackedInfo->records = realloc(unpackedInfo->records, sizeof(struct passed_through_package_info_record) * (++unpackedInfo->count));
	if(!unpackedInfo->records){
		ohshite("Unable to reallocate in %s", __func__);
	}
	rec = &(unpackedInfo->records[prevCountAndIndex]);
	passed_through_package_info_emplace(rec, pkg);
}

size_t precompute_the_bencode_serialized_size(struct passed_through_package_info *unpackedInfo){
    size_t totalSize = BENC_START_END;
    unsigned int i;
    for(i=0;i<unpackedInfo->count;++i){
      if(unpackedInfo->records[i].name.size){
        totalSize += measure_benc_pascal_str(&unpackedInfo->records[i].name);
        totalSize += BENC_START_END;
        totalSize += measure_benc_tag_value_pair(&unpackedInfo->records[i].arch);
        totalSize += measure_benc_tag_value_pair(&unpackedInfo->records[i].version);
        totalSize += measure_benc_tag_value_pair(&unpackedInfo->records[i].origin);
      }
    }
    totalSize ++; // null termination
    return totalSize;
}

void serialize_the_info_about_triggerers_into_an_env_variable(struct passed_through_package_info *unpackedInfo){
    unsigned int i;
    size_t totalSize = precompute_the_bencode_serialized_size(unpackedInfo);
    char buf4str[totalSize];
    char * serPtr;

    memset(buf4str, ' ', totalSize);
    buf4str[totalSize - 1] = 0;
    serPtr = &buf4str[0];
    *(serPtr++) = 'd';
    for(i=0;i<unpackedInfo->count;++i){
      serialize_benc_pascal_str(&serPtr, &unpackedInfo->records[i].name);
      *(serPtr++) = 'd';
      serialize_benc_tag_value_pair(&serPtr, 'A', &unpackedInfo->records[i].arch);
      serialize_benc_tag_value_pair(&serPtr, 'V', &unpackedInfo->records[i].version);
      serialize_benc_tag_value_pair(&serPtr, 'O', &unpackedInfo->records[i].origin);
      *(serPtr++) = 'e';
    }
    *(serPtr++) = 'e';
    if((unsigned long)((char*) serPtr - (char*) buf4str) > totalSize){
      ohshit("Buffer overflow %zu > %zu !", (char*) serPtr - (char*) buf4str, totalSize);
    }
    setenv("DPKG_TRIGGERER_PACKAGES_INFO", buf4str, 1);
}

void serialize_the_info_about_pkg_into_an_env_variable(struct pkginfo *pkg){
  struct passed_through_package_info_record rec;  // no need to free
  //passed_through_package_info_append(unpackedInfo, pkg);
  passed_through_package_info_emplace(&rec, pkg);
  struct passed_through_package_info i;
  i.records = &rec;
  i.count = 1;

  passed_through_package_info_nonowning_emplace(&rec, pkg);
  serialize_the_info_about_triggerers_into_an_env_variable(&i);
}
