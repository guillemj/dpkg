package Dpkg::Checksums;

use strict;
use warnings;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(internerr syserr subprocerr failure error
                           warning );

use base qw(Exporter);
our @EXPORT = qw(@check_supported %check_supported %check_prog %check_regex
                 readchecksums readallchecksums getchecksums);

our @check_supported = qw(md5 sha1 sha256);
our %check_supported = map { $_ => 1 } @check_supported;
our %check_prog = ( md5 => 'md5sum', sha1 => 'sha1sum',
		    sha256 => 'sha256sum' );
our %check_regex = ( md5 => qr/[0-9a-f]{32}/,
		     sha1 => qr/[0-9a-f]{40}/,
		     sha256 => qr/[0-9a-f]{64}/ );

sub extractchecksum {
    my ($alg, $checksum) = @_;
    ($checksum =~ /^($check_regex{$alg})(\s|$)/m)
	|| failure(_g("checksum program gave bogus output `%s'"), $checksum);
    return $1;
}


sub readchecksums {
    my ($alg, $fieldtext, $checksums, $sizes) = @_;
    my %checksums;

    $alg = lc($alg);
    unless ($check_supported{$alg}) {
	warning(_g("Unknown checksum algorithm \`%s', ignoring"), $alg);
	return;
    }
    my $rx_fname = qr/[0-9a-zA-Z][-+:.,=0-9a-zA-Z_~]+/;
    for my $checksum (split /\n /, $fieldtext) {
	next if $checksum eq '';
	$checksum =~ m/^($check_regex{$alg})\s+(\d+)\s+($rx_fname)$/
	    || do {
		warning(_g("Checksums-%s field contains bad line \`%s'"),
			ucfirst($alg), $checksum);
		next;
	};
	my ($sum, $size, $file) = ($1, $2, $3);
	if (exists($checksums->{$file}{$alg})
	    and $checksums->{$file}{$alg} ne $sum) {
	    error(_g("Conflicting checksums \`%s\' and \`%s' for file \`%s'"),
		  $checksums->{$file}{$alg}, $sum, $file);
	}
	if (exists($sizes->{$file})
	    and $sizes->{$file} != $size) {
	    error(_g("Conflicting file sizes \`%u\' and \`%u' for file \`%s'"),
		  $sizes->{$file}, $size, $file);
	}
	$checksums->{$file}{$alg} = $sum;
	$sizes->{$file} = $size;
    }

    return 1;
}

sub readallchecksums {
    my ($fields, $checksums, $sizes) = @_;

    foreach my $field (keys %$fields) {
	if ($field =~ /^Checksums-(\w+)$/
	    && defined($fields->{$field})) {
	    readchecksums($1, $fields->{$field}, $checksums, $sizes);
	}
    }
}

sub getchecksums {
    my ($file, $checksums, $size) = @_;

    (my @s = stat($file)) || syserr(_g("cannot fstat file %s"), $file);
    my $newsize = $s[7];
    if (defined($$size)
	and $newsize != $$size) {
	error(_g("File %s has size %u instead of expected %u"),
	      $file, $newsize, $$size);
    }
    $$size = $newsize;

    foreach my $alg (@check_supported) {
	my $prog = $check_prog{$alg};
	my $newsum = `$prog $file`;
	$? && subprocerr("%s %s", $prog, $file);
	$newsum = extractchecksum($alg, $newsum);

	if (defined($checksums->{$alg})
	    and $newsum ne $checksums->{$alg}) {
	    error(_g("File %s has checksum %s instead of expected %s (algorithm %s)"),
		  $file, $newsum, $checksums->{$alg}, $alg);
	}
	$checksums->{$alg} = $newsum;
    }
}

1;
