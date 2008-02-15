package Dpkg::Compression;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(@comp_supported %comp_supported %comp_ext $comp_regex
		 %comp_prog %comp_decomp_prog);

our @comp_supported = qw(gzip bzip2 lzma);
our %comp_supported = map { $_ => 1 } @comp_supported;
our %comp_ext = (gzip => 'gz', bzip2 => 'bz2', lzma => 'lzma');
our $comp_regex = '(?:gz|bz2|lzma)';
our %comp_prog = (gzip => 'gzip', bzip2 => 'bzip2', lzma => 'lzma');
our %comp_decomp_prog = (gzip => 'gunzip', bzip2 => 'bunzip2', lzma => 'unlzma');

1;
