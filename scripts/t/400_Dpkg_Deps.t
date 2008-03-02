# -*- mode: cperl;-*-

use Test::More tests => 15;

use strict;
use warnings;

use_ok('Dpkg::Deps');

my $field_multiline = " , , libgtk2.0-common (= 2.10.13-1)  , libatk1.0-0 (>=
1.13.2), libc6 (>= 2.5-5), libcairo2 (>= 1.4.0), libcupsys2 (>= 1.2.7),
libfontconfig1 (>= 2.4.0), libglib2.0-0  (  >= 2.12.9), libgnutls13 (>=
1.6.3-0), libjpeg62, python (<< 2.5) , , ";
my $field_multiline_sorted = "libatk1.0-0 (>= 1.13.2), libc6 (>= 2.5-5), libcairo2 (>= 1.4.0), libcupsys2 (>= 1.2.7), libfontconfig1 (>= 2.4.0), libglib2.0-0 (>= 2.12.9), libgnutls13 (>= 1.6.3-0), libgtk2.0-common (= 2.10.13-1), libjpeg62, python (<< 2.5)";

my $dep_multiline = Dpkg::Deps::parse($field_multiline);
$dep_multiline->sort();
is($dep_multiline->dump(), $field_multiline_sorted, "Parse, sort and dump");

my $dep_subset = Dpkg::Deps::parse("libatk1.0-0 (>> 1.10), libc6, libcairo2");
is($dep_multiline->implies($dep_subset), 1, "Dep implies subset of itself");
is($dep_subset->implies($dep_multiline), undef, "Subset doesn't imply superset");
my $dep_opposite = Dpkg::Deps::parse("python (>= 2.5)");
is($dep_opposite->implies($dep_multiline), 0, "Opposite condition implies NOT the depends");

my $dep_or1 = Dpkg::Deps::parse("a|b (>=1.0)|c (>= 2.0)");
my $dep_or2 = Dpkg::Deps::parse("x|y|a|b|c (<= 0.5)|c (>=1.5)|d|e");
is($dep_or1->implies($dep_or2), 1, "Implication between OR 1/2");
is($dep_or2->implies($dep_or1), undef, "Implication between OR 2/2");

my $field_arch = "libc6 (>= 2.5) [!alpha !hurd-i386], libc6.1 [alpha], libc0.1 [hurd-i386]";
my $dep_i386 = Dpkg::Deps::parse($field_arch, reduce_arch => 1, host_arch => 'i386');
my $dep_alpha = Dpkg::Deps::parse($field_arch, reduce_arch => 1, host_arch => 'alpha');
my $dep_hurd = Dpkg::Deps::parse($field_arch, reduce_arch => 1, host_arch => 'hurd-i386');
is($dep_i386->dump(), "libc6 (>= 2.5)", "Arch reduce 1/3");
is($dep_alpha->dump(), "libc6.1", "Arch reduce 2/3");
is($dep_hurd->dump(), "libc0.1", "Arch reduce 3/3");


my $facts = Dpkg::Deps::KnownFacts->new();
$facts->add_installed_package("mypackage", "1.3.4-1");
$facts->add_provided_package("myvirtual", undef, undef, "mypackage");

my $field_duplicate = "libc6 (>= 2.3), libc6 (>= 2.6-1), mypackage (>=
1.3), myvirtual | something, python (>= 2.5)";
my $dep_dup = Dpkg::Deps::parse($field_duplicate);
$dep_dup->simplify_deps($facts, $dep_opposite);
is($dep_dup->dump(), "libc6 (>= 2.6-1)", "Simplify deps");

my $field_dup_union = "libc6 (>> 2.3), libc6 (>= 2.6-1), fake (<< 2.0),
fake(>> 3.0), fake (= 2.5), python (<< 2.5), python (= 2.4)";
my $dep_dup_union = Dpkg::Deps::parse($field_dup_union, union => 1);
$dep_dup_union->simplify_deps($facts);
is($dep_dup_union->dump(), "libc6 (>> 2.3), fake (<< 2.0), fake (>> 3.0), fake (= 2.5), python (<< 2.5)", "Simplify union deps");

my $dep_red = Dpkg::Deps::parse("abc | xyz, two, abc");
$dep_red->simplify_deps($facts, $dep_opposite);
is($dep_red->dump(), "abc, two", "Simplification respect order");

my $dep_empty1 = Dpkg::Deps::parse("");
is($dep_empty1->dump(), "", "Empty dependency");

my $dep_empty2 = Dpkg::Deps::parse(" , , ", union => 1);
is($dep_empty2->dump(), "", "' , , ' is also an empty dependency");

