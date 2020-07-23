#pragma once
#include "pascal_str.h"

#include "config.h"
#include <dpkg/dpkg-db.h>

struct passed_through_package_info_record {
	struct pascal_str name;
	struct pascal_str arch;
	struct pascal_str version;
	struct pascal_str origin;
};

struct passed_through_package_info{
	unsigned int count;
	struct passed_through_package_info_record *records;
};

struct passed_through_package_info passed_through_package_info_init(void);

void free_passed_through_package_info_record(struct passed_through_package_info_record *r);

void passed_through_package_info_free(struct passed_through_package_info *unpackedInfo);

void passed_through_package_info_emplace(struct passed_through_package_info_record * rec, struct pkginfo *pkg);

void passed_through_package_info_append(struct passed_through_package_info *unpackedInfo, struct pkginfo *pkg);

void serialize_the_info_about_triggerers_into_an_env_variable(struct passed_through_package_info *unpackedInfo);
void serialize_the_info_about_pkg_into_an_env_variable(struct pkginfo *pkg);

size_t precompute_the_bencode_serialized_size(struct passed_through_package_info *unpackedInfo);
