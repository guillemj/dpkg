/*
 * libdpkg - Debian packaging suite library routines
 * pkg-db.c - low level package database routines (hash tables, etc.)
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2008-2014 Guillem Jover <guillem@debian.org>
 * Copyright © 2011 Linaro Limited
 * Copyright © 2011 Raphaël Hertzog <hertzog@debian.org>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <assert.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/arch.h>

/* This must always be a prime for optimal performance.
 * With 4093 buckets, we glean a 20% speedup, for 8191 buckets
 * we get 23%. The nominal increase in memory usage is a mere
 * sizeof(void *) * 8063 (i.e. less than 32 KiB on 32bit systems). */
#define BINS 8191

static struct pkgset *bins[BINS];
static int npkg, nset;

#define FNV_offset_basis 2166136261ul
#define FNV_mixing_prime 16777619ul

/**
 * Fowler/Noll/Vo -- simple string hash.
 *
 * For more info, see <http://www.isthe.com/chongo/tech/comp/fnv/index.html>.
 */
static unsigned int hash(const char *name) {
  register unsigned int h = FNV_offset_basis;
  register unsigned int p = FNV_mixing_prime;
  while( *name ) {
    h *= p;
    h ^= *name++;
  }
  return h;
}

/**
 * Return the package set with the given name.
 *
 * If the package already exists in the internal database, then it returns
 * the existing structure. Otherwise it allocates a new one and will return
 * it. The actual name associated to the package set is a lowercase version
 * of the name given in parameter.
 *
 * A package set (struct pkgset) can be composed of multiple package instances
 * (struct pkginfo) where each instance is distinguished by its architecture
 * (as recorded in pkg.installed.arch and pkg.available.arch).
 *
 * @param inname Name of the package set.
 *
 * @return The package set.
 */
struct pkgset *
pkg_db_find_set(const char *inname)
{
  struct pkgset **setp, *new_set;
  char *name = m_strdup(inname), *p;

  p= name;
  while(*p) { *p= tolower(*p); p++; }

  setp = bins + (hash(name) % (BINS));
  while (*setp && strcasecmp((*setp)->name, name))
    setp = &(*setp)->next;
  if (*setp) {
    free(name);
    return *setp;
  }

  new_set = nfmalloc(sizeof(struct pkgset));
  pkgset_blank(new_set);
  new_set->name = nfstrsave(name);
  new_set->next = NULL;
  *setp = new_set;
  nset++;
  npkg++;

  free(name);

  return new_set;
}

/**
 * Return the singleton package instance from a package set.
 *
 * This means, if none are installed either an instance with native or
 * all arch or the first if none found, the single installed instance,
 * or NULL if more than one instance is installed.
 *
 * @param set The package set to use.
 *
 * @return The singleton package instance.
 */
struct pkginfo *
pkg_db_get_singleton(struct pkgset *set)
{
  struct pkginfo *pkg;

  switch (pkgset_installed_instances(set)) {
  case 0:
    /* Pick an available candidate. */
    for (pkg = &set->pkg; pkg; pkg = pkg->arch_next) {
      const struct dpkg_arch *arch = pkg->available.arch;

      if (arch->type == DPKG_ARCH_NATIVE || arch->type == DPKG_ARCH_ALL)
        return pkg;
    }
    /* Or failing that, the first entry. */
    return &set->pkg;
  case 1:
    for (pkg = &set->pkg; pkg; pkg = pkg->arch_next) {
      if (pkg->status > stat_notinstalled)
        return pkg;
    }
    internerr("pkgset '%s' should have one installed instance", set->name);
  default:
    return NULL;
  }
}

/**
 * Return the singleton package instance with the given name.
 *
 * @param name The package name.
 *
 * @return The package instance.
 */
struct pkginfo *
pkg_db_find_singleton(const char *name)
{
  struct pkgset *set;
  struct pkginfo *pkg;

  set = pkg_db_find_set(name);
  pkg = pkg_db_get_singleton(set);
  if (pkg == NULL)
    ohshit(_("ambiguous package name '%s' with more "
             "than one installed instance"), set->name);

  return pkg;
}

/**
 * Return the package instance in a set with the given architecture.
 *
 * It traverse the various instances to find out whether there's one
 * matching the given architecture. If found, it returns it. Otherwise it
 * allocates a new instance and registers it in the package set before
 * returning it.
 *
 * @param set  The package set to use.
 * @param arch The requested architecture.
 *
 * @return The package instance.
 */
struct pkginfo *
pkg_db_get_pkg(struct pkgset *set, const struct dpkg_arch *arch)
{
  struct pkginfo *pkg, **pkgp;

  assert(arch);
  assert(arch->type != DPKG_ARCH_NONE);

  pkg = &set->pkg;

  /* If there's a single unused slot, let's use that. */
  if (pkg->installed.arch->type == DPKG_ARCH_NONE && pkg->arch_next == NULL) {
    pkg->installed.arch = arch;
    pkg->available.arch = arch;
    return pkg;
  }

  /* Match the slot with the most appropriate architecture. The installed
   * architecture always has preference over the available one, as there's
   * a small time window on cross-grades, where they might differ. */
  for (pkgp = &pkg; *pkgp; pkgp = &(*pkgp)->arch_next) {
    if ((*pkgp)->installed.arch == arch)
      return *pkgp;
  }

  /* Need to create a new instance for the wanted architecture. */
  pkg = nfmalloc(sizeof(struct pkginfo));
  pkg_blank(pkg);
  pkg->set = set;
  pkg->arch_next = NULL;
  pkg->installed.arch = arch;
  pkg->available.arch = arch;
  *pkgp = pkg;
  npkg++;

  return pkg;
}

/**
 * Return the package instance with the given name and architecture.
 *
 * @param name The package name.
 * @param arch The requested architecture.
 *
 * @return The package instance.
 */
struct pkginfo *
pkg_db_find_pkg(const char *name, const struct dpkg_arch *arch)
{
  struct pkgset *set;
  struct pkginfo *pkg;

  set = pkg_db_find_set(name);
  pkg = pkg_db_get_pkg(set, arch);

  return pkg;
}

/**
 * Return the number of package sets available in the database.
 *
 * @return The number of package sets.
 */
int
pkg_db_count_set(void)
{
  return nset;
}

/**
 * Return the number of package instances available in the database.
 *
 * @return The number of package instances.
 */
int
pkg_db_count_pkg(void)
{
  return npkg;
}

struct pkgiterator {
  struct pkginfo *pkg;
  int nbinn;
};

/**
 * Create a new package iterator.
 *
 * It can iterate either over package sets or over package instances.
 *
 * @return The iterator.
 */
struct pkgiterator *
pkg_db_iter_new(void)
{
  struct pkgiterator *iter;

  iter = m_malloc(sizeof(struct pkgiterator));
  iter->pkg = NULL;
  iter->nbinn = 0;

  return iter;
}

/**
 * Return the next package set in the database.
 *
 * If no further package set is available, it will return NULL.
 *
 * @name iter The iterator.
 *
 * @return A package set.
 */
struct pkgset *
pkg_db_iter_next_set(struct pkgiterator *iter)
{
  struct pkgset *set;

  while (!iter->pkg) {
    if (iter->nbinn >= BINS)
      return NULL;
    if (bins[iter->nbinn])
      iter->pkg = &bins[iter->nbinn]->pkg;
    iter->nbinn++;
  }

  set = iter->pkg->set;
  if (set->next)
    iter->pkg = &set->next->pkg;
  else
    iter->pkg = NULL;

  return set;
}

/**
 * Return the next package instance in the database.
 *
 * If no further package instance is available, it will return NULL. Note
 * that it will return all instances of a given package set in sequential
 * order. The first instance for a given package set will always correspond
 * to the native architecture even if that package is not installed or
 * available.
 *
 * @name iter The iterator.
 *
 * @return A package instance.
 */
struct pkginfo *
pkg_db_iter_next_pkg(struct pkgiterator *iter)
{
  struct pkginfo *r;

  while (!iter->pkg) {
    if (iter->nbinn >= BINS)
      return NULL;
    if (bins[iter->nbinn])
      iter->pkg = &bins[iter->nbinn]->pkg;
    iter->nbinn++;
  }

  r = iter->pkg;
  if (r->arch_next)
    iter->pkg = r->arch_next;
  else if (r->set->next)
    iter->pkg = &r->set->next->pkg;
  else
    iter->pkg = NULL;

  return r;
}

/**
 * Free the package database iterator.
 *
 * @name iter The iterator.
 */
void
pkg_db_iter_free(struct pkgiterator *iter)
{
  free(iter);
}

void
pkg_db_reset(void)
{
  int i;

  dpkg_arch_reset_list();
  nffreeall();
  nset = 0;
  npkg = 0;
  for (i=0; i<BINS; i++) bins[i]= NULL;
}

void
pkg_db_report(FILE *file)
{
  int i, c;
  struct pkgset *pkg;
  int *freq;

  freq = m_malloc(sizeof(int) * nset + 1);
  for (i = 0; i <= nset; i++)
    freq[i] = 0;
  for (i=0; i<BINS; i++) {
    for (c=0, pkg= bins[i]; pkg; c++, pkg= pkg->next);
    fprintf(file,"bin %5d has %7d\n",i,c);
    freq[c]++;
  }
  for (i = nset; i > 0 && freq[i] == 0; i--);
  while (i >= 0) {
    fprintf(file, "size %7d occurs %5d times\n", i, freq[i]);
    i--;
  }

  m_output(file, "<hash report>");

  free(freq);
}
