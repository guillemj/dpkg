#
# Parse::DebianChangelog
#
# Copyright 1996 Ian Jackson
# Copyright 2005 Frank Lichtenheld <frank@lichtenheld.de>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#

=head1 NAME

Parse::DebianChangelog - parse Debian changelogs and output them in other formats

=head1 SYNOPSIS

    use Parse::DebianChangelog;

    my $chglog = Parse::DebianChangelog->init( { infile => 'debian/changelog',
                                                 HTML => { outfile => 'changelog.html' } );
    $chglog->html;

    # the following is semantically equivalent
    my $chglog = Parse::DebianChangelog->init();
    $chglog->parse( { infile => 'debian/changelog' } );
    $chglog->html( { outfile => 'changelog.html' } );

    my $changes = $chglog->dpkg_str( { since => '1.0-1' } );
    print $changes;

=head1 DESCRIPTION

Parse::DebianChangelog parses Debian changelogs as described in the Debian
policy (version 3.6.2.1 at the time of this writing). See section
L<"SEE ALSO"> for locations where to find this definition.

The parser tries to ignore most cruft like # or /* */ style comments,
CVS comments, vim variables, emacs local variables and stuff from
older changelogs with other formats at the end of the file.
NOTE: most of these are ignored silently currently, there is no
parser error issued for them. This should become configurable in the
future.

Beside giving access to the details of the parsed file via the
L<"data"> method, Parse::DebianChangelog also supports converting these
changelogs to various other formats. These are currently:

=over 4

=item dpkg

Format as known from L<dpkg-parsechangelog(1)>. All requested entries
(see L<"METHODS"> for an explanation what this means) are returned in
the usual Debian control format, merged in one stanza, ready to be used
in a F<.changes> file.

=item rfc822

Similar to the C<dpkg> format, but the requested entries are returned
as one stanza each, i.e. they are not merged. This is probably the format
to use if you want a machine-usable representation of the changelog.

=item xml

Just a simple XML dump of the changelog data. Without any schema or
DTD currently, just some made up XML. The actual format might still
change. Comments and Improvements welcome.

=item html

The changelog is converted to a somewhat nice looking HTML file with
some nice features as a quick-link bar with direct links to every entry.
NOTE: This is not very configurable yet and was specifically designed
to be used on L<http://packages.debian.org/>. This is planned to be
changed until version 1.0.

=back

=head2 METHODS

=cut

package Parse::DebianChangelog;

use strict;
use warnings;

use Fcntl qw( :flock );
use English;
use Locale::gettext;
use Date::Parse;
use Parse::DebianChangelog::Util qw( :all );
use Parse::DebianChangelog::Entry;

our $VERSION = '1.1.1';

=pod

=head3 init

Creates a new object instance. Takes a reference to a hash as
optional argument, which is interpreted as configuration options.
There are currently no supported general configuration options, but
see the other methods for more specific configuration options which
can also specified to C<init>.

If C<infile> or C<instring> are specified (see L<parse>), C<parse()>
is called from C<init>. If a fatal error is encountered during parsing
(e.g. the file can't be opened), C<init> will not return a
valid object but C<undef>!

=cut

sub init {
    my $classname = shift;
    my $config = shift || {};
    my $self = {};
    bless( $self, $classname );

    $config->{verbose} = 1 if $config->{debug};
    $self->{config} = $config;

    $self->init_filters;
    $self->reset_parse_errors;

    if ($self->{config}{infile} || $self->{config}{instring}) {
	defined($self->parse) or return undef;
    }

    return $self;
}

=pod

=head3 reset_parse_errors

Can be used to delete all information about errors ocurred during
previous L<parse> runs. Note that C<parse()> also calls this method.

=cut

sub reset_parse_errors {
    my ($self) = @_;

    $self->{errors}{parser} = [];
}

sub _do_parse_error {
    my ($self, $file, $line_nr, $error, $line) = @_;
    shift;

    push @{$self->{errors}{parser}}, [ @_ ];

    $file = substr $file, 0, 20;
    unless ($self->{config}{quiet}) {
	if ($line) {
	    warn "WARN: $file(l$NR): $error\nLINE: $line\n";
	} else {
	    warn "WARN: $file(l$NR): $error\n";
	}
    }
}

=pod

=head3 get_parse_errors

Returns all error messages from the last L<parse> run.
If called in scalar context returns a human readable
string representation. If called in list context returns
an array of arrays. Each of these arrays contains

=over 4

=item 1.

the filename of the parsed file or C<String> if a string was
parsed directly

=item 2.

the line number where the error occurred

=item 3.

an error description

=item 4.

the original line

=back

NOTE: This format isn't stable yet and may change in later versions
of this module.

=cut

sub get_parse_errors {
    my ($self) = @_;

    if (wantarray) {
	return @{$self->{errors}{parser}};
    } else {
	my $res = "";
	foreach my $e (@{$self->{errors}{parser}}) {
	    if ($e->[3]) {
		$res .= __g( "WARN: %s(l%s): %s\nLINE: %s\n", @$e );
	    } else {
		$res .= __g( "WARN: %s(l%s): %s\n", @$e );
	    }
	}
	return $res;
    }
}

sub _do_fatal_error {
    my ($self, @msg) = @_;

    $self->{errors}{fatal} = "@msg";
    warn __g( "FATAL: %s", "@msg")."\n" unless $self->{config}{quiet};
}

=pod

=head3 get_error

Get the last non-parser error (e.g. the file to parse couldn't be opened).

=cut

sub get_error {
    my ($self) = @_;

    return $self->{errors}{fatal};
}

=pod

=head3 parse

Parses either the file named in configuration item C<infile> or the string
saved in configuration item C<instring>.
Accepts a hash ref as optional argument which can contain configuration
items.

Returns C<undef> in case of error (e.g. "file not found", B<not> parse
errors) and the object if successful. If C<undef> was returned, you
can get the reason for the failure by calling the L<get_error> method.

=cut

sub __g {
    my $string = shift;
    return sprintf( dgettext( 'Parse-DebianChangelog', $string ), @_ );
}

sub parse {
    my ($self, $config) = @_;

    foreach my $c (keys %$config) {
	$self->{config}{$c} = $config->{$c};
    }

    my ($fh, $file);
    if ($file = $self->{config}{infile}) {
	open $fh, '<', $file or do {
	    $self->_do_fatal_error( __g( "can't open file %s: %s",
					 $file, $! ));
	    return undef;
	};
	flock $fh, LOCK_SH or do {
	    $self->_do_fatal_error( __g( "can't lock file %s: %s",
					 $file, $! ));
	    return undef;
	};
    } elsif (my $string = $self->{config}{instring}) {
	eval { require IO::String };
	if ($@) {
	    $self->_do_fatal_error( __g( "can't load IO::String: %s",
					 $@ ));
	    return undef;
	}
	$fh = IO::String->new( $string );
	$file = 'String';
    } else {
	$self->_do_fatal_error( __g( 'no changelog file specified' ));
	return undef;
    }

    $self->reset_parse_errors;

    $self->{data} = [];

# based on /usr/lib/dpkg/parsechangelog/debian
    my $expect='first heading';
    my $entry = Parse::DebianChangelog::Entry->init();
    my $blanklines = 0;
    my $unknowncounter = 1; # to make version unique, e.g. for using as id

    while (<$fh>) {
	s/\s*\n$//;
#	printf(STDERR "%-39.39s %-39.39s\n",$expect,$_);
	if (m/^(\w[-+0-9a-z.]*) \(([^\(\) \t]+)\)((\s+[-0-9a-z]+)+)\;/i) {
	    unless ($expect eq 'first heading'
		    || $expect eq 'next heading or eof') {
		$entry->{ERROR} = [ $file, $NR,
				  __g( "found start of entry where expected %s",
				       $expect ), "$_" ];
		$self->_do_parse_error(@{$entry->{ERROR}});
	    }
	    unless ($entry->is_empty) {
		$entry->{'Closes'} = find_closes( $entry->{Changes} );
#		    print STDERR, Dumper($entry);
		push @{$self->{data}}, $entry;
		$entry = Parse::DebianChangelog::Entry->init();
	    }
	    {
		$entry->{'Source'} = "$1";
		$entry->{'Version'} = "$2";
		$entry->{'Header'} = "$_";
		($entry->{'Distribution'} = "$3") =~ s/^\s+//;
		$entry->{'Changes'} = $entry->{'Urgency_Comment'} = '';
		$entry->{'Urgency'} = $entry->{'Urgency_LC'} = 'unknown';
	    }
	    (my $rhs = $POSTMATCH) =~ s/^\s+//;
	    my %kvdone;
#	    print STDERR "RHS: $rhs\n";
	    for my $kv (split(/\s*,\s*/,$rhs)) {
		$kv =~ m/^([-0-9a-z]+)\=\s*(.*\S)$/i ||
		    $self->_do_parse_error($file, $NR,
					   __g( "bad key-value after \`;': \`%s'", $kv ));
		my $k = ucfirst $1;
		my $v = $2;
		$kvdone{$k}++ && $self->_do_parse_error($file, $NR,
						       __g( "repeated key-value %s", $k ));
		if ($k eq 'Urgency') {
		    $v =~ m/^([-0-9a-z]+)((\s+.*)?)$/i ||
			$self->_do_parse_error($file, $NR,
					      __g( "badly formatted urgency value" ),
					      $v);
		    $entry->{'Urgency'} = "$1";
		    $entry->{'Urgency_LC'} = lc("$1");
		    $entry->{'Urgency_Comment'} = "$2";
		} elsif ($k =~ m/^X[BCS]+-/i) {
		    # Extensions - XB for putting in Binary,
		    # XC for putting in Control, XS for putting in Source
		    $entry->{$k}= $v;
		} else {
		    $self->_do_parse_error($file, $NR,
					  __g( "unknown key-value key %s - copying to XS-%s", $k, $k ));
		    $entry->{ExtraFields}{"XS-$k"} = $v;
		}
	    }
	    $expect= 'start of change data';
	    $blanklines = 0;
	} elsif (m/^(;;\s*)?Local variables:/io) {
	    last; # skip Emacs variables at end of file
	} elsif (m/^vim:/io) {
	    last; # skip vim variables at end of file
	} elsif (m/^\$\w+:.*\$/o) {
	    next; # skip stuff that look like a CVS keyword
	} elsif (m/^\# /o) {
	    next; # skip comments, even that's not supported
	} elsif (m,^/\*.*\*/,o) {
	    next; # more comments
	} elsif (m/^(\w+\s+\w+\s+\d{1,2} \d{1,2}:\d{1,2}:\d{1,2}\s+[\w\s]*\d{4})\s+(.*)\s+(<|\()(.*)(\)|>)/o
		 || m/^(\w+\s+\w+\s+\d{1,2},?\s*\d{4})\s+(.*)\s+(<|\()(.*)(\)|>)/o
		 || m/^(\w[-+0-9a-z.]*) \(([^\(\) \t]+)\)\;?/io
		 || m/^([\w.+-]+)(-| )(\S+) Debian (\S+)/io
		 || m/^Changes from version (.*) to (.*):/io
		 || m/^Changes for [\w.+-]+-[\w.+-]+:?$/io
		 || m/^Old Changelog:$/io
		 || m/^(?:\d+:)?\w[\w.+~-]*:?$/o) {
	    # save entries on old changelog format verbatim
	    # we assume the rest of the file will be in old format once we
	    # hit it for the first time
	    $self->{oldformat} = "$_\n";
	    $self->{oldformat} .= join "", <$fh>;
	} elsif (m/^\S/) {
	    $self->_do_parse_error($file, $NR,
				  __g( "badly formatted heading line" ), "$_");
	} elsif (m/^ \-\- (.*) <(.*)>(  ?)((\w+\,\s*)?\d{1,2}\s+\w+\s+\d{4}\s+\d{1,2}:\d\d:\d\d\s+[-+]\d{4}(\s+\([^\\\(\)]\))?)$/o) {
	    $expect eq 'more change data or trailer' ||
		$self->_do_parse_error($file, $NR,
				       __g( "found trailer where expected %s",
					    $expect ), "$_");
	    if ($3 ne '  ') {
		$self->_do_parse_error($file, $NR,
				       __g( "badly formatted trailer line" ),
				       "$_");
	    }
	    $entry->{'Trailer'} = $_;
	    $entry->{'Maintainer'} = "$1 <$2>" unless $entry->{'Maintainer'};
	    unless($entry->{'Date'} && defined $entry->{'Timestamp'}) {
		$entry->{'Date'} = "$4";
		$entry->{'Timestamp'} = str2time($4);
		unless (defined $entry->{'Timestamp'}) {
		    $self->_do_parse_error( $file, $NR,
					    __g( "couldn't parse date %s",
						 "$4" ) );
		}
	    }
	    $expect = 'next heading or eof';
	} elsif (m/^ \-\-/) {
	    $entry->{ERROR} = [ $file, $NR,
			      __g( "badly formatted trailer line" ), "$_" ];
	    $self->_do_parse_error(@{$entry->{ERROR}});
#	    $expect = 'next heading or eof'
#		if $expect eq 'more change data or trailer';
	} elsif (m/^\s{2,}(\S)/) {
	    $expect eq 'start of change data'
		|| $expect eq 'more change data or trailer'
		|| do {
		    $self->_do_parse_error($file, $NR,
			    __g( "found change data where expected %s",
				 $expect ), "$_");
		    if (($expect eq 'next heading or eof')
			&& !$entry->is_empty) {
			# lets assume we have missed the actual header line
			$entry->{'Closes'} = find_closes( $entry->{Changes} );
#		    print STDERR, Dumper($entry);
			push @{$self->{data}}, $entry;
			$entry = Parse::DebianChangelog::Entry->init();
			$entry->{Source} =
			    $entry->{Distribution} = $entry->{Urgency} =
			    $entry->{Urgency_LC} = 'unknown';
			$entry->{Version} = 'unknown'.($unknowncounter++);
			$entry->{Urgency_Comment} = '';
			$entry->{ERROR} = [ $file, $NR,
					    __g( "found change data where expected %s",
						 $expect ), "$_" ];
		    }
		};
	    $entry->{'Changes'} .= (" \n" x $blanklines)." $_\n";
	    if (!$entry->{'Items'} || ($1 eq '*')) {
		$entry->{'Items'} ||= [];
		push @{$entry->{'Items'}}, "$_\n";
	    } else {
		$entry->{'Items'}[-1] .= (" \n" x $blanklines)." $_\n";
	    }
	    $blanklines = 0;
	    $expect = 'more change data or trailer';
	} elsif (!m/\S/) {
	    next if $expect eq 'start of change data'
		|| $expect eq 'next heading or eof';
	    $expect eq 'more change data or trailer'
		|| $self->_do_parse_error($file, $NR,
					 __g( "found blank line where expected %s",
					      $expect ));
	    $blanklines++;
	} else {
	    $self->_do_parse_error($file, $NR, __g( "unrecognised line" ),
				   "$_");
	    ($expect eq 'start of change data'
		|| $expect eq 'more change data or trailer')
		&& do {
		    # lets assume change data if we expected it
		    $entry->{'Changes'} .= (" \n" x $blanklines)." $_\n";
		    if (!$entry->{'Items'}) {
			$entry->{'Items'} ||= [];
			push @{$entry->{'Items'}}, "$_\n";
		    } else {
			$entry->{'Items'}[-1] .= (" \n" x $blanklines)." $_\n";
		    }
		    $blanklines = 0;
		    $expect = 'more change data or trailer';
		    $entry->{ERROR} = [ $file, $NR, __g( "unrecognised line" ),
					"$_" ];
		};
	}
    }

    $expect eq 'next heading or eof'
	|| do {
	    $entry->{ERROR} = [ $file, $NR,
				__g( "found eof where expected %s",
				     $expect ) ];
	    $self->_do_parse_error( @{$entry->{ERROR}} );
	};
    unless ($entry->is_empty) {
	$entry->{'Closes'} = find_closes( $entry->{Changes} );
	push @{$self->{data}}, $entry;
    }

    if ($self->{config}{infile}) {
	close $fh or do {
	    $self->_do_fatal_error( __g( "can't close file %s: %s",
					 $file, $! ));
	    return undef;
	};
    }

#    use Data::Dumper;
#    print Dumper( $self );

    return $self;
}

=pod

=head3 data

C<data> returns an array (if called in list context) or a reference
to an array of Parse::DebianChangelog::Entry objects which each
represent one entry of the changelog.

This is currently merely a placeholder to enable users to get to the
raw data, expect changes to this API in the near future.

This method supports the common output options described in
section L<"COMMON OUTPUT OPTIONS">.

=cut

sub data {
    my ($self, $config) = @_;

    my $data = $self->{data};
    if ($config) {
	$self->{config}{DATA} = $config if $config;
	$data = $self->_data_range( $config ) or return undef;
    }
    return @$data if wantarray;
    return $data;
}

sub __sanity_check_range {
    my ( $data, $from, $to, $since, $until, $start, $end ) = @_;

    if (($$start || $$end) && ($$from || $$since || $$to || $$until)) {
	warn( __g( "you can't combine 'count' or 'offset' with any other range option" ) ."\n");
	$$from = $$since = $$to = $$until = '';
    }
    if ($$from && $$since) {
	warn( __g( "you can only specify one of 'from' and 'since'" ) ."\n");
	$$from = '';
    }
    if ($$to && $$until) {
	warn( __g( "you can only specify one of 'to' and 'until'" ) ."\n");
	$$to = '';
    }
    if ($$since && ($data->[0]{Version} eq $$since)) {
	warn( __g( "'since' option specifies most recent version" ) ."\n");
	$$since = '';
    }
    if ($$until && ($data->[$#{$data}]{Version} eq $$until)) {
	warn( __g( "'until' option specifies oldest version" ) ."\n");
	$$until = '';
    }
    $$start = 0 if $$start < 0;
    return if $$start > $#$data;
    $$end = $#$data if $$end > $#$data;
    return if $$end < 0;
    $$end = $$start if $$end < $$start;
    #TODO: compare versions
    return 1;
}

sub _data_range {
    my ($self, $config) = @_;

    my $data = $self->data or return undef;

    return [ @$data ] if $config->{all};

    my $since = $config->{since} || '';
    my $until = $config->{until} || '';
    my $from = $config->{from} || '';
    my $to = $config->{to} || '';
    my $count = $config->{count} || 0;
    my $offset = $config->{offset} || 0;

    return if $offset and not $count;
    if ($offset > 0) {
	$offset -= ($count < 0);
    } elsif ($offset < 0) {
	$offset = $#$data + ($count > 0) + $offset;
    } else {
	$offset = $#$data if $count < 0;
    }
    my $start = my $end = $offset;
    $start += $count+1 if $count < 0;
    $end += $count-1 if $count > 0;

    return unless __sanity_check_range( $data, \$from, \$to,
					\$since, \$until,
					\$start, \$end );


    unless ($from or $to or $since or $until or $start or $end) {
	return [ @$data ] if $config->{default_all} and not $count;
	return [ $data->[0] ];
    }

    return [ @{$data}[$start .. $end] ] if $start or $end;

    my @result;

    my $include = 1;
    $include = 0 if $to or $until;
    foreach (@$data) {
	my $v = $_->{Version};
	$include = 1 if $v eq $to;
	last if $v eq $since;

	push @result, $_ if $include;

	$include = 1 if $v eq $until;
	last if $v eq $from;
    }

    return \@result;
}

=pod

=head3 dpkg

(and B<dpkg_str>)

C<dpkg> returns a hash (in list context) or a hash reference
(in scalar context) where the keys are field names and the values are
field values. The following fields are given:

=over 4

=item Source

package name (in the first entry)

=item Version

packages' version (from first entry)

=item Distribution

target distribution (from first entry)

=item Urgency

urgency (highest of all printed entries)

=item Maintainer

person that created the (first) entry

=item Date

date of the (first) entry

=item Closes

bugs closed by the entry/entries, sorted by bug number

=item Changes

content of the the entry/entries

=back

C<dpkg_str> returns a stringified version of this hash which should look
exactly like the output of L<dpkg-parsechangelog(1)>. The fields are
ordered like in the list above.

Both methods only support the common output options described in
section L<"COMMON OUTPUT OPTIONS">.

=head3 dpkg_str

See L<dpkg>.

=cut

our ( %FIELDIMPS, %URGENCIES );
BEGIN {
    my $i=100;
    grep($FIELDIMPS{$_}=$i--,
	 qw(Source Version Distribution Urgency Maintainer Date Closes
	    Changes));
    $i=1;
    grep($URGENCIES{$_}=$i++,
	 qw(low medium high critical emergency));
}

sub dpkg {
    my ($self, $config) = @_;

    $self->{config}{DPKG} = $config if $config;

    $config = $self->{config}{DPKG} || {};
    my $data = $self->_data_range( $config ) or return undef;

    my %f;
    foreach my $field (qw( Urgency Source Version
			   Distribution Maintainer Date )) {
	$f{$field} = $data->[0]{$field};
    }

    $f{Changes} = get_dpkg_changes( $data->[0] );
    $f{Closes} = [ @{$data->[0]{Closes}} ];

    my $first = 1; my $urg_comment = '';
    foreach my $entry (@$data) {
	$first = 0, next if $first;

	my $oldurg = $f{Urgency} || '';
	my $oldurgn = $URGENCIES{$f{Urgency}} || -1;
	my $newurg = $entry->{Urgency_LC} || '';
	my $newurgn = $URGENCIES{$entry->{Urgency_LC}} || -1;
	$f{Urgency} = ($newurgn > $oldurgn) ? $newurg : $oldurg;
	$urg_comment .= $entry->{Urgency_Comment};

	$f{Changes} .= "\n .".get_dpkg_changes( $entry );
	push @{$f{Closes}}, @{$entry->{Closes}};
    }

    $f{Closes} = join " ", sort { $a <=> $b } @{$f{Closes}};
    $f{Urgency} .= $urg_comment;

    return %f if wantarray;
    return \%f;
}

sub dpkg_str {
    return data2rfc822( scalar dpkg(@_), \%FIELDIMPS );
}

=pod

=head3 rfc822

(and B<rfc822_str>)

C<rfc822> returns an array of hashes (in list context) or a reference
to this array (in scalar context) where each hash represents one entry
in the changelog. For the format of such a hash see the description
of the L<"dpkg"> method (while ignoring the remarks about which
values are taken from the first entry).

C<rfc822_str> returns a stringified version of this hash which looks
similar to the output of dpkg-parsechangelog but instead of one
stanza the output contains one stanza for each entry.

Both methods only support the common output options described in
section L<"COMMON OUTPUT OPTIONS">.

=head3 rfc822_str

See L<rfc822>.

=cut

sub rfc822 {
    my ($self, $config) = @_;

    $self->{config}{RFC822} = $config if $config;

    $config = $self->{config}{RFC822} || {};
    my $data = $self->_data_range( $config ) or return undef;
    my @out_data;

    foreach my $entry (@$data) {
	my %f;
	foreach my $field (qw( Urgency Source Version
			   Distribution Maintainer Date )) {
	    $f{$field} = $entry->{$field};
	}

	$f{Urgency} .= $entry->{Urgency_Comment};
	$f{Changes} = get_dpkg_changes( $entry );
	$f{Closes} = join " ", sort { $a <=> $b } @{$entry->{Closes}};
	push @out_data, \%f;
    }

    return @out_data if wantarray;
    return \@out_data;
}

sub rfc822_str {
    return data2rfc822_mult( scalar rfc822(@_), \%FIELDIMPS );
}

sub __version2id {
    my $version = shift;
    $version =~ s/[^\w.:-]/_/go;
    return "version$version";
}

=pod

=head3 xml

(and B<xml_str>)

C<xml> converts the changelog to some free-form (i.e. there is neither
a DTD or a schema for it) XML.

The method C<xml_str> is an alias for C<xml>.

Both methods support the common output options described in
section L<"COMMON OUTPUT OPTIONS"> and additionally the following
configuration options (as usual to give
in a hash reference as parameter to the method call):

=over 4

=item outfile

directly write the output to the file specified

=back

=head3 xml_str

See L<xml>.

=cut

sub xml {
    my ($self, $config) = @_;

    $self->{config}{XML} = $config if $config;
    $config = $self->{config}{XML} || {};
    $config->{default_all} = 1 unless exists $config->{all};
    my $data = $self->_data_range( $config ) or return undef;
    my %out_data;
    $out_data{Entry} = [];

    require XML::Simple;
    import XML::Simple qw( :strict );

    foreach my $entry (@$data) {
	my %f;
	foreach my $field (qw( Urgency Source Version
			       Distribution Closes )) {
	    $f{$field} = $entry->{$field};
	}
	foreach my $field (qw( Maintainer Changes )) {
	    $f{$field} = [ $entry->{$field} ];
	}

	$f{Urgency} .= $entry->{Urgency_Comment};
	$f{Date} = { timestamp => $entry->{Timestamp},
		     content => $entry->{Date} };
	push @{$out_data{Entry}}, \%f;
    }

    my $xml_str;
    my %xml_opts = ( SuppressEmpty => 1, KeyAttr => {},
		     RootName => 'Changelog' );
    $xml_str = XMLout( \%out_data, %xml_opts );
    if ($config->{outfile}) {
	open my $fh, '>', $config->{outfile} or return undef;
	flock $fh, LOCK_EX or return undef;

	print $fh $xml_str;

	close $fh or return undef;
    }

    return $xml_str;
}

sub xml_str {
    return xml(@_);
}

=pod

=head3 html

(and B<html_str>)

C<html> converts the changelog to a HTML file with some nice features
such as a quick-link bar with direct links to every entry. The HTML
is generated with the help of HTML::Template. If you want to change
the output you should use the default template provided with this module
as a base and read the documentation of HTML::Template to understand
how to edit it.

The method C<html_str> is an alias for C<html>.

Both methods support the common output options described in
section L<"COMMON OUTPUT OPTIONS"> and additionally the following
configuration options (as usual to give
in a hash reference as parameter to the method call):

=over 4

=item outfile

directly write the output to the file specified

=item template

template file to use, defaults to tmpl/default.tmpl, so you
most likely want to override that.
NOTE: The plan is to provide a configuration file for the module
later to be able to use sane defaults here.

=item style

path to the CSS stylesheet to use (a default might be specified
in the template and will be honoured, see the default template
for an example)

=item print_style

path to the CSS stylesheet to use for printing (see the notes for
C<style> about default values)

=back

=head3 html_str

See L<html>.

=cut

sub html {
    my ($self, $config) = @_;

    $self->{config}{HTML} = $config if $config;
    $config = $self->{config}{HTML} || {};
    $config->{default_all} = 1 unless exists $config->{all};
    my $data = $self->_data_range( $config ) or return undef;

    require CGI;
    import CGI qw( -no_xhtml -no_debug );
    require HTML::Template;

    my $template = HTML::Template->new(filename => $config->{template}
				       || 'tmpl/default.tmpl',
				       die_on_bad_params => 0);
    $template->param( MODULE_NAME => ref($self),
		      MODULE_VERSION => $VERSION,
		      GENERATED_DATE => gmtime()." UTC",
		      SOURCE_NEWEST => $data->[0]{Source},
		      VERSION_NEWEST => $data->[0]{Version},
		      MAINTAINER_NEWEST => $data->[0]{Maintainer},
		      );

    $template->param( CSS_FILE_SCREEN => $config->{style} )
	if $config->{style};
    $template->param( CSS_FILE_PRINT => $config->{print_style} )
	if $config->{print_style};

    my $cgi = new CGI;
    $cgi->autoEscape(0);

    my %navigation;
    my $last_year;
    foreach my $entry (@$data) {
	my $year = $last_year; # try to deal gracefully with unparsable dates
	if (defined $entry->{Timestamp}) {
	    $year = (gmtime($entry->{Timestamp}))[5] + 1900;
	    $last_year = $year;
	}

	$year ||= (($entry->{Date} =~ /\s(\d{4})\s/) ? $1 : (gmtime)[5] + 1900);

	$navigation{$year}{NAV_VERSIONS} ||= [];
	$navigation{$year}{NAV_YEAR} ||= $year;

	$entry->{Maintainer} ||= 'unknown';
	$entry->{Date} ||= 'unknown';
	push @{$navigation{$year}{NAV_VERSIONS}},
	       { NAV_VERSION_ID => __version2id($entry->{Version}),
		 NAV_VERSION => $entry->{Version},
		 NAV_MAINTAINER => $entry->{Maintainer},
		 NAV_DATE => $entry->{Date} };
    }
    my @nav_years;
    foreach my $y (reverse sort keys %navigation) {
	push @nav_years, $navigation{$y};
    }
    $template->param( OLDFORMAT => (($self->{oldformat}||'') ne ''),
		      NAV_YEARS => \@nav_years );


    my %years;
    $last_year = undef;
    foreach my $entry (@$data) {
	my $year = $last_year; # try to deal gracefully with unparsable dates
	if (defined $entry->{Timestamp}) {
	    $year = (gmtime($entry->{Timestamp}))[5] + 1900;
	}
	$year ||= (($entry->{Date} =~ /\s(\d{4})\s/) ? $1 : (gmtime)[5] + 1900);

	if (!$last_year || ($year < $last_year)) {
	    $last_year = $year;
	}

	$years{$last_year}{CONTENT_VERSIONS} ||= [];
	$years{$last_year}{CONTENT_YEAR} ||= $last_year;

	my $text = $self->apply_filters( 'html::changes',
					 $entry->{Changes}, $cgi );

	(my $maint_name = $entry->{Maintainer} ) =~ s|<([a-zA-Z0-9_\+\-\.]+\@([a-zA-Z0-9][\w\.+\-]+\.[a-zA-Z]{2,}))>||o;
	my $maint_mail = $1;

	my $parse_error;
	$parse_error = $cgi->p( { -class=>'parse_error' },
				"(There has been a parse error in the entry above, if some values don't make sense please check the original changelog)" )
	    if $entry->{ERROR};

	push @{$years{$last_year}{CONTENT_VERSIONS}}, {
	    CONTENT_VERSION => $entry->{Version},
	    CONTENT_VERSION_ID => __version2id($entry->{Version}),
	    CONTENT_URGENCY => $entry->{Urgency}.$entry->{Urgency_Comment},
	    CONTENT_URGENCY_NORM => $entry->{Urgency_LC},
	    CONTENT_DISTRIBUTION => $entry->{Distribution},
	    CONTENT_DISTRIBUTION_NORM => lc($entry->{Distribution}),
	    CONTENT_SOURCE => $entry->{Source},
	    CONTENT_CHANGES => $text,
	    CONTENT_CHANGES_UNFILTERED => $entry->{Changes},
	    CONTENT_DATE => $entry->{Date},
	    CONTENT_MAINTAINER_NAME => $maint_name,
	    CONTENT_MAINTAINER_EMAIL => $maint_mail,
	    CONTENT_PARSE_ERROR => $parse_error,
	};
    }
    my @content_years;
    foreach my $y (reverse sort keys %years) {
	push @content_years, $years{$y};
    }
    $template->param( OLDFORMAT_CHANGES => $self->{oldformat},
		      CONTENT_YEARS => \@content_years );

    my $html_str = $template->output;

    if ($config->{outfile}) {
	open my $fh, '>', $config->{outfile} or return undef;
	flock $fh, LOCK_EX or return undef;

	print $fh $html_str;

	close $fh or return undef;
    }

    return $html_str;
}

sub html_str {
    return html(@_);
}


=pod

=head3 init_filters

not yet documented

=cut

sub init_filters {
    my ($self) = @_;

    require Parse::DebianChangelog::ChangesFilters;

    $self->{filters} = {};

    $self->{filters}{'html::changes'} =
	[ @Parse::DebianChangelog::ChangesFilters::all_filters ];
}

=pod

=head3 apply_filters

not yet documented

=cut

sub apply_filters {
    my ($self, $filter_class, $text, $data) = @_;

    foreach my $f (@{$self->{filters}{$filter_class}}) {
	$text = &$f( $text, $data );
    }
    return $text;
}

=pod

=head3 add_filter, delete_filter, replace_filter

not yet documented

=cut

sub add_filter {
    my ($self, $filter_class, $filter, $pos) = @_;

    $self->{filters}{$filter_class} ||= [];
    unless ($pos) {
	push @{$self->{filters}{$filter_class}}, $filter;
    } elsif ($pos == 1) {
	unshift @{$self->{filters}{$filter_class}}, $filter;
    } elsif ($pos > 1) {
	my $length = @{$self->{filters}{$filter_class}};
	$self->{filters}{$filter_class} =
	    [ @{$self->{filters}{$filter_class}[0 .. ($pos-2)]}, $filter,
	      @{$self->{filters}{$filter_class}[($pos-1) .. ($length-1)]} ];
    }

    return $self;
}

sub delete_filter {
    my ($self, $filter_class, $filter) = @_;

    my $pos;
    unless (ref $filter) {
	$pos = $filter;

	return delete $self->{filters}{$filter_class}[$pos];
    }

    $self->{filters}{$filter_class} ||= [];
    my @deleted;
    for my $i (0 .. $#{$self->{filters}{$filter_class}}) {
	push @deleted, delete $self->{filters}{$filter_class}[$i]
	    if $self->{filters}{$filter_class}[$i] == $filter;
    }

    return @deleted;
}

sub replace_filter {
    my ($self, $filter_class, $filter, @new_filters) = @_;

    my @pos;
    unless (ref $filter) {
	$pos[0] = $filter;
    } else {
	$self->{filters}{$filter_class} ||= [];
	for my $i (0 .. $#{$self->{filters}{$filter_class}}) {
	    push @pos, $i
		if $self->{filters}{$filter_class}[$i] == $filter;
	}
    }

    foreach my $p (@pos) {
	$self->delete_filter( $filter_class, $p );

	foreach my $f (@new_filters) {
	    $self->add_filter( $filter_class, $f, $p++);
	}
    }

    return $self;
}

1;
__END__

=head1 COMMON OUTPUT OPTIONS

The following options are supported by all output methods,
all take a version number as value:

=over 4

=item since

Causes changelog information from all versions strictly
later than B<version> to be used.

(works exactly like the C<-v> option of dpkg-parsechangelog).

=item until

Causes changelog information from all versions strictly
earlier than B<version> to be used.

=item from

Similar to C<since> but also includes the information for the
specified B<version> itself.

=item to

Similar to C<until> but also includes the information for the
specified B<version> itself.

=back

The following options also supported by all output methods but
don't take version numbers as values:

=over 4

=item all

If set to a true value, all entries of the changelog are returned,
this overrides all other options. While the XML and HTML formats
default to all == true, this does of course not overwrite other
options unless it is set explicitly with the call.

=item count

Expects a signed integer as value. Returns C<value> entries from the
top of the changelog if set to a positive integer, and C<abs(value)>
entries from the tail if set to a negative integer.

=item offset

Expects a signed integer as value. Changes the starting point for
C<count>, either counted from the top (positive integer) or from
the tail (negative integer). C<offset> has no effect if C<count>
wasn't given as well.

=back

Some examples for the above options. Imagine an example changelog with
entries for the versions 1.2, 1.3, 2.0, 2.1, 2.2, 3.0 and 3.1.

            Call                               Included entries
 C<E<lt>formatE<gt>({ since =E<gt> '2.0' })>  3.1, 3.0, 2.2
 C<E<lt>formatE<gt>({ until =E<gt> '2.0' })>  1.3, 1.2
 C<E<lt>formatE<gt>({ from =E<gt> '2.0' })>   3.1, 3.0, 2.2, 2.1, 2.0
 C<E<lt>formatE<gt>({ to =E<gt> '2.0' })>     2.0, 1.3, 1.2
 C<E<lt>formatE<gt>({ count =E<gt> 2 }>>      3.1, 3.0
 C<E<lt>formatE<gt>({ count =E<gt> -2 }>>     1.3, 1.2
 C<E<lt>formatE<gt>({ count =E<gt> 3,
		      offset=E<gt> 2 }>>      2.2, 2.1, 2.0
 C<E<lt>formatE<gt>({ count =E<gt> 2,
		      offset=E<gt> -3 }>>     2.0, 1.3
 C<E<lt>formatE<gt>({ count =E<gt> -2,
		      offset=E<gt> 3 }>>      3.0, 2.2
 C<E<lt>formatE<gt>({ count =E<gt> -2,
		      offset=E<gt> -3 }>>     2.2, 2.1

Any combination of one option of C<since> and C<from> and one of
C<until> and C<to> returns the intersection of the two results
with only one of the options specified.

=head1 SEE ALSO

Parse::DebianChangelog::Entry, Parse::DebianChangelog::ChangesFilters

Description of the Debian changelog format in the Debian policy:
L<http://www.debian.org/doc/debian-policy/ch-source.html#s-dpkgchangelog>.

=head1 AUTHOR

Frank Lichtenheld, E<lt>frank@lichtenheld.deE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Frank Lichtenheld

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

=cut
