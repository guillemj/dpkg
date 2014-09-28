/*
 * libdpkg - Debian packaging suite library routines
 * t-string.c - test string handling
 *
 * Copyright © 2009-2011, 2014 Guillem Jover <guillem@debian.org>
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

#include <dpkg/test.h>
#include <dpkg/string.h>

#include <stdlib.h>
#include <string.h>

#include <stdio.h>

static void
test_str_is_set(void)
{
	/* Test if strings are unset. */
	test_pass(str_is_unset(NULL));
	test_pass(str_is_unset(""));
	test_fail(str_is_unset("aaa"));

	/* Test if strings are set. */
	test_fail(str_is_set(NULL));
	test_fail(str_is_set(""));
	test_pass(str_is_set("ccc"));
}

static void
test_str_match_end(void)
{
	test_pass(str_match_end("foo bar quux", "quux"));
	test_pass(str_match_end("foo bar quux", "bar quux"));
	test_pass(str_match_end("foo bar quux", "foo bar quux"));
	test_fail(str_match_end("foo bar quux", "foo bar quux zorg"));
	test_fail(str_match_end("foo bar quux", "foo bar"));
	test_fail(str_match_end("foo bar quux", "foo"));
}

static void
test_str_fnv_hash(void)
{
	test_pass(str_fnv_hash("") == 0x811c9dc5U);
	test_pass(str_fnv_hash("a") == 0xe40c292cUL);
	test_pass(str_fnv_hash("b") == 0xe70c2de5UL);
	test_pass(str_fnv_hash("c") == 0xe60c2c52UL);
	test_pass(str_fnv_hash("d") == 0xe10c2473UL);
	test_pass(str_fnv_hash("e") == 0xe00c22e0UL);
	test_pass(str_fnv_hash("f") == 0xe30c2799UL);
	test_pass(str_fnv_hash("fo") == 0x6222e842UL);
	test_pass(str_fnv_hash("foo") == 0xa9f37ed7UL);
	test_pass(str_fnv_hash("foob") == 0x3f5076efUL);
	test_pass(str_fnv_hash("fooba") == 0x39aaa18aUL);
	test_pass(str_fnv_hash("foobar") == 0xbf9cf968UL);

	test_pass(str_fnv_hash("test-string") == 0xd28f6e61UL);
	test_pass(str_fnv_hash("Test-string") == 0x00a54b81UL);
	test_pass(str_fnv_hash("rest-string") == 0x1cdeebffUL);
	test_pass(str_fnv_hash("Rest-string") == 0x20464b9fUL);
}

static void
test_str_escape_fmt(void)
{
	char buf[1024], *q;

	memset(buf, 'a', sizeof(buf));
	q = str_escape_fmt(buf, "", sizeof(buf));
	strcpy(q, " end");
	test_str(buf, ==, " end");

	memset(buf, 'a', sizeof(buf));
	q = str_escape_fmt(buf, "%", sizeof(buf));
	strcpy(q, " end");
	test_str(buf, ==, "%% end");

	memset(buf, 'a', sizeof(buf));
	q = str_escape_fmt(buf, "%%%", sizeof(buf));
	strcpy(q, " end");
	test_str(buf, ==, "%%%%%% end");

	memset(buf, 'a', sizeof(buf));
	q = str_escape_fmt(buf, "%b%b%c%c%%", sizeof(buf));
	strcpy(q, " end");
	test_str(buf, ==, "%%b%%b%%c%%c%%%% end");

	/* Test delimited buffer. */
	memset(buf, 'a', sizeof(buf));
	q = str_escape_fmt(buf, NULL, 0);
	test_mem(buf, ==, "aaaa", 4);

	memset(buf, 'a', sizeof(buf));
	q = str_escape_fmt(buf, "b", 1);
	test_str(q, ==, "");

	memset(buf, 'a', sizeof(buf));
	q = str_escape_fmt(buf, "%%%", 5);
	strcpy(q, " end");
	test_str(buf, ==, "%%%% end");

	memset(buf, 'a', sizeof(buf));
	q = str_escape_fmt(buf, "%%%", 4);
	strcpy(q, " end");
	test_str(buf, ==, "%% end");
}

static void
test_str_quote_meta(void)
{
	char *str;

	str = str_quote_meta("foo1 2bar");
	test_str(str, ==, "foo1\\ 2bar");
	free(str);

	str = str_quote_meta("foo1?2bar");
	test_str(str, ==, "foo1\\?2bar");
	free(str);

	str = str_quote_meta("foo1*2bar");
	test_str(str, ==, "foo1\\*2bar");
	free(str);
}

static void
test_str_strip_quotes(void)
{
	char buf[1024], *str;

	strcpy(buf, "unquoted text");
	str = str_strip_quotes(buf);
	test_str(str, ==, "unquoted text");

	strcpy(buf, "contained 'quoted text'");
	str = str_strip_quotes(buf);
	test_str(str, ==, "contained 'quoted text'");

	strcpy(buf, "contained \"quoted text\"");
	str = str_strip_quotes(buf);
	test_str(str, ==, "contained \"quoted text\"");

	strcpy(buf, "'unbalanced quotes");
	str = str_strip_quotes(buf);
	test_pass(str == NULL);

	strcpy(buf, "\"unbalanced quotes");
	str = str_strip_quotes(buf);
	test_pass(str == NULL);

	strcpy(buf, "'mismatched quotes\"");
	str = str_strip_quotes(buf);
	test_pass(str == NULL);

	strcpy(buf, "\"mismatched quotes'");
	str = str_strip_quotes(buf);
	test_pass(str == NULL);

	strcpy(buf, "'completely quoted text'");
	str = str_strip_quotes(buf);
	test_str(str, ==, "completely quoted text");

	strcpy(buf, "\"completely quoted text\"");
	str = str_strip_quotes(buf);
	test_str(str, ==, "completely quoted text");
}

static void
test(void)
{
	test_plan(48);

	test_str_is_set();
	test_str_match_end();
	test_str_fnv_hash();
	test_str_escape_fmt();
	test_str_quote_meta();
	test_str_strip_quotes();
}
