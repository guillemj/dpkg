#!/usr/bin/perl
#
# dpkg-parsechangelog
#
# Copyright © 1996 Ian Jackson
# Copyright © 2001 Wichert Akkerman
# Copyright © 2006-2012 Guillem Jover <guillem@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use v5.36;

use Dpkg ();
use Dpkg::Gettext;
use Dpkg::Getopt;
use Dpkg::ErrorHandling;
use Dpkg::Changelog::Parse;

textdomain('dpkg-dev');

my %options;
my $fieldname;

sub usage {
    printf g_(
"Usage: %s [<option>...]\n" .
    ''), $Dpkg::PROGNAME;
    print_option_sep();

    printf g_(
"Options:\n" .
"  -l, --file <changelog-file>\n" .
"          Get per-version info from this file.\n" .
"  -F <changelog-format>\n" .
"          Force changelog format.\n" .
"  -S, --show-field <field>\n" .
"          Show the values for <field>.\n" .
"  -?, --help\n" .
"          Show this help message.\n" .
"      --version\n" .
"          Show the version.\n" .
    '');
    print_option_sep();

    printf g_(
"Parser options:\n" .
"      --format <output-format>\n" .
"          Set output format (defaults to 'dpkg').\n" .
"      --reverse\n" .
"          Include all changes in reverse order.\n" .
"      --all\n" .
"          Include all changes.\n" .
"  -s, --since <version>\n" .
"          Include all changes later than <version>.\n" .
"  -v <version>\n" .
"          Ditto.\n" .
"  -u, --until <version>\n" .
"          Include all changes earlier than <version>.\n" .
"  -f, --from <version>\n" .
"          Include all changes equal or later than <version>.\n" .
"  -t, --to <version>\n" .
"          Include all changes up to or equal than <version>.\n" .
"  -c, --count <number>\n" .
"          Include <number> entries from the top (or tail if <number> is lower\n" .
"          than 0).\n" .
"  -n <number>\n" .
"          Ditto.\n" .
"  -o, --offset <number>\n" .
"          Change starting point for --count, counted from the top (or tail\n" .
"          if <number> is lower than 0).\n" .
    '');
}

@ARGV = normalize_options(args => \@ARGV, delim => '--');

while (@ARGV) {
    last unless $ARGV[0] =~ m/^-/;

    my $arg = shift;

    if ($arg eq '--') {
        last;
    } elsif ($arg eq '-L') {
        warning(g_('-L is obsolete; it is without effect'));
    } elsif ($arg eq '-F') {
        $options{changelogformat} = shift;
        usageerr(g_('bad changelog format name'))
            unless length $options{changelogformat} and
                          $options{changelogformat} =~ m/^([0-9a-z]+)$/;
    } elsif ($arg eq '--format') {
        $options{format} = shift;
    } elsif ($arg eq '--reverse') {
        $options{reverse} = 1;
    } elsif ($arg eq '-l' or $arg eq '--file') {
        $options{filename} = shift;
        usageerr(g_('missing changelog filename'))
            unless length $options{filename};
    } elsif ($arg eq '-S' or $arg eq '--show-field') {
        $fieldname = shift;
    } elsif ($arg eq '-c' or $arg eq '--count' or $arg eq '-n') {
        $options{count} = shift;
    } elsif ($arg eq '-f' or $arg eq '--from') {
        $options{from} = shift;
    } elsif ($arg eq '-o' or $arg eq '--offset') {
        $options{offset} = shift;
    } elsif ($arg eq '-s' or $arg eq '--since' or $arg eq '-v') {
        $options{since} = shift;
    } elsif ($arg eq '-t' or $arg eq '--to') {
        $options{to} = shift;
    } elsif ($arg eq '-u' or $arg eq '--until') {
        ## no critic (ControlStructures::ProhibitUntilBlocks)
        $options{until} = shift;
        ## use critic
    } elsif ($arg eq '--all') {
        $options{all} = undef;
    } elsif ($arg eq '-?' or $arg eq '--help') {
        usage();
        exit 0;
    } elsif ($arg eq '--version') {
        print_version();
        exit 0;
    } else {
        usageerr(g_("unknown option '%s'"), $arg);
    }
}
usageerr(g_('takes no non-option arguments')) if @ARGV;

my $count = 0;
my @fields = changelog_parse(%options);
foreach my $f (@fields) {
    print "\n" if $count++;
    if ($fieldname) {
        next if not exists $f->{$fieldname};

        my ($first_line, @lines) = split /\n/, $f->{$fieldname};

        my $v = '';
        $v .= $first_line if length $first_line;
        $v .= "\n";
        foreach (@lines) {
            s/\s+$//;
            if (length == 0 or /^\.+$/) {
                $v .= ".$_\n";
            } else {
                $v .= "$_\n";
            }
        }
        print $v;
    } else {
        print $f->output();
    }
}
