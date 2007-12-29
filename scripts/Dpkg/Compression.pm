package Dpkg::Compression;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(@comp_supported %comp_supported %comp_ext $comp_regex);

our @comp_supported = qw(gzip bzip2 lzma);
our %comp_supported = map { $_ => 1 } @comp_supported;
our %comp_ext = ( gzip => 'gz', bzip2 => 'bz2', lzma => 'lzma' );
our $comp_regex = '(?:gz|bz2|lzma)';

1;
