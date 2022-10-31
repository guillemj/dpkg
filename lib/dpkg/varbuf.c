/*
 * libdpkg - Debian packaging suite library routines
 * varbuf.c - variable length expandable buffer handling
 *
 * Copyright © 1994,1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2008-2015 Guillem Jover <guillem@debian.org>
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

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

void
varbuf_add_char(struct varbuf *v, int c)
{
  varbuf_grow(v, 1);
  v->buf[v->used++]= c;
}

void
varbuf_dup_char(struct varbuf *v, int c, size_t n)
{
  if (n == 0)
    return;
  varbuf_grow(v, n);
  memset(v->buf + v->used, c, n);
  v->used += n;
}

void
varbuf_map_char(struct varbuf *v, int c_src, int c_dst)
{
  size_t i;

  for (i = 0; i < v->used; i++)
    if (v->buf[i] == c_src)
      v->buf[i] = c_dst;
}

int
varbuf_printf(struct varbuf *v, const char *fmt, ...)
{
  int r;
  va_list args;

  va_start(args, fmt);
  r = varbuf_vprintf(v, fmt, args);
  va_end(args);

  return r;
}

int
varbuf_vprintf(struct varbuf *v, const char *fmt, va_list args)
{
  va_list args_copy;
  int needed, r;

  va_copy(args_copy, args);
  needed = vsnprintf(NULL, 0, fmt, args_copy);
  va_end(args_copy);

  if (needed < 0)
    ohshite(_("error formatting string into varbuf variable"));

  varbuf_grow(v, needed + 1);

  r = vsnprintf(v->buf + v->used, needed + 1, fmt, args);
  if (r < 0)
    ohshite(_("error formatting string into varbuf variable"));

  v->used += r;

  return r;
}

void
varbuf_add_buf(struct varbuf *v, const void *s, size_t size)
{
  if (size == 0)
    return;
  varbuf_grow(v, size);
  memcpy(v->buf + v->used, s, size);
  v->used += size;
}

void
varbuf_add_dir(struct varbuf *v, const char *dirname)
{
  varbuf_add_str(v, dirname);
  if (v->used == 0 || v->buf[v->used - 1] != '/')
    varbuf_add_char(v, '/');
}

void
varbuf_end_str(struct varbuf *v)
{
  varbuf_grow(v, 1);
  v->buf[v->used] = '\0';
}

const char *
varbuf_get_str(struct varbuf *v)
{
  varbuf_end_str(v);

  return v->buf;
}

struct varbuf *
varbuf_new(size_t size)
{
  struct varbuf *v;

  v = m_malloc(sizeof(*v));
  varbuf_init(v, size);

  return v;
}

void
varbuf_init(struct varbuf *v, size_t size)
{
  v->used = 0;
  v->size = size;
  if (size)
    v->buf = m_malloc(size);
  else
    v->buf = NULL;
}

void
varbuf_reset(struct varbuf *v)
{
  v->used= 0;
}

void
varbuf_grow(struct varbuf *v, size_t need_size)
{
  size_t new_size;

  /* Make sure the varbuf is in a sane state. */
  if (v->size < v->used)
    internerr("varbuf used(%zu) > size(%zu)", v->used, v->size);

  /* Check if we already have enough room. */
  if ((v->size - v->used) >= need_size)
    return;

  /* Check if we overflow. */
  new_size = (v->size + need_size) * 2;
  if (new_size < v->size)
    ohshit(_("cannot grow varbuf to size %zu; it would overflow"), need_size);

  v->size = new_size;
  v->buf = m_realloc(v->buf, v->size);
}

void
varbuf_trunc(struct varbuf *v, size_t used_size)
{
  /* Make sure the caller does not claim more than available. */
  if (v->size < used_size)
    internerr("varbuf new_used(%zu) > size(%zu)", used_size, v->size);

  v->used = used_size;
}

void
varbuf_snapshot(struct varbuf *v, struct varbuf_state *vs)
{
  vs->v = v;
  vs->used = v->used;
}

void
varbuf_rollback(struct varbuf_state *vs)
{
  varbuf_trunc(vs->v, vs->used);
}

size_t
varbuf_rollback_len(struct varbuf_state *vs)
{
  if (vs->used > vs->v->used)
    internerr("varbuf state_used(%zu) > used(%zu)", vs->used, vs->v->used);
  return vs->v->used - vs->used;
}

const char *
varbuf_rollback_start(struct varbuf_state *vs)
{
  if (vs->v->buf == NULL) {
    if (vs->used)
      internerr("varbuf buf(NULL) state_used(%zu) > 0", vs->used);
    /* XXX: Ideally this would be handled by varbuf always having a valid
     * buf or switching all users to the getter, but for now this will do. */
    return "";
  }
  return vs->v->buf + vs->used;
}

char *
varbuf_detach(struct varbuf *v)
{
  char *buf = v->buf;

  v->buf = NULL;
  v->size = 0;
  v->used = 0;

  return buf;
}

void
varbuf_destroy(struct varbuf *v)
{
  free(v->buf); v->buf=NULL; v->size=0; v->used=0;
}

void
varbuf_free(struct varbuf *v)
{
  free(v->buf);
  free(v);
}
