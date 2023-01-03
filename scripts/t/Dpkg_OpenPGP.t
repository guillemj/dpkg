#!/usr/bin/perl
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

use strict;
use warnings;

use Test::More;
use Test::Dpkg qw(:paths :needs);

use File::Compare;

use Dpkg::ErrorHandling;
use Dpkg::Path qw(find_command);
use Dpkg::OpenPGP::KeyHandle;

my %backend_cmd = (
    auto => 'auto',
    gpg => 'gpg',
    sq => 'sq',
    sqop => 'sop',
    'pgpainless-cli' => 'sop',
);
my @cmds = test_needs_openpgp_backend();
unshift @cmds, 'auto';

plan tests => 2 + 15 * scalar @cmds;

use_ok('Dpkg::OpenPGP');
use_ok('Dpkg::OpenPGP::ErrorCodes');

report_options(quiet_warnings => 1);

sub test_diff
{
    my ($exp_file, $gen_file, $desc) = @_;

    my $res = compare($exp_file, $gen_file);
    if ($res) {
        system "diff -u '$exp_file' '$gen_file' >&2";
    }
    ok($res == 0, "$desc ($exp_file vs $gen_file)");
}

foreach my $cmd (@cmds) {
    my $datadir = test_get_data_path();
    my $tempdir = test_get_temp_path();

    my $backend = $backend_cmd{$cmd};
    my $openpgp = Dpkg::OpenPGP->new(
        backend => $backend,
        cmd => $cmd,
    );

    ok($openpgp->dearmor('PUBLIC KEY BLOCK', "$datadir/dpkg-test-pub.asc", "$tempdir/dpkg-test-pub.pgp") == OPENPGP_OK(),
        "($backend:$cmd) dearmoring OpenPGP ASCII Armored certificate");
    ok($openpgp->armor('PUBLIC KEY BLOCK', "$tempdir/dpkg-test-pub.pgp", "$tempdir/dpkg-test-pub.asc") == OPENPGP_OK(),
        "($backend:$cmd) armoring OpenPGP binary certificate");
    test_diff("$datadir/dpkg-test-pub.asc", "$tempdir/dpkg-test-pub.asc",
        "($backend:$cmd) OpenPGP certificate dearmor/armor round-trip correctly");

    ok($openpgp->armor('SIGNATURE', "$datadir/sign-file.sig", "$tempdir/sign-file.asc") == OPENPGP_OK(),
        "($backend:$cmd) armoring OpenPGP binary signature succeeded");
    ok(compare("$datadir/sign-file.sig", "$tempdir/sign-file.asc") != 0,
        "($backend:$cmd) armoring OpenPGP ASCII Armor changed the file");
    ok($openpgp->armor('SIGNATURE', "$datadir/sign-file.asc", "$tempdir/sign-file-rearmor.asc") == OPENPGP_OK(),
        "($backend:$cmd) armoring OpenPGP armored signature succeeded");
    test_diff("$datadir/sign-file.asc", "$tempdir/sign-file-rearmor.asc",
        "($backend:$cmd) rearmoring OpenPGP ASCII Armor changed the file");

    ok($openpgp->dearmor('SIGNATURE', "$tempdir/sign-file.asc", "$tempdir/sign-file.sig") == OPENPGP_OK(),
        "($backend:$cmd) dearmoring OpenPGP armored signature succeeded");
    test_diff("$datadir/sign-file.sig", "$tempdir/sign-file.sig",
        "($backend:$cmd) dearmored OpenPGP ASCII Armor signature matches");

    my $cert = "$datadir/dpkg-test-pub.asc";

    ok($openpgp->inline_verify("$datadir/sign-file-inline.asc", undef, $cert) == OPENPGP_OK(),
        "($backend:$cmd) verify OpenPGP ASCII Armor inline signature");
    ok($openpgp->inline_verify("$datadir/sign-file-inline.sig", undef, $cert) == OPENPGP_OK(),
        "($backend:$cmd) verify OpenPGP binary inline signature");

    ok($openpgp->verify("$datadir/sign-file", "$datadir/sign-file.asc", $cert) == OPENPGP_OK(),
        "($backend:$cmd) verify OpenPGP ASCII Armor detached signature");
    ok($openpgp->verify("$datadir/sign-file", "$datadir/sign-file.sig", $cert) == OPENPGP_OK(),
        "($backend:$cmd) verify OpenPGP binary detached signature");

    my $key = Dpkg::OpenPGP::KeyHandle->new(
        type => 'keyfile',
        handle => "$datadir/dpkg-test-sec.asc",
    );

    SKIP: {
        skip 'cannot use secrets', 2 unless $openpgp->can_use_secrets($key);

        ok($openpgp->inline_sign("$datadir/sign-file", "$tempdir/sign-file-inline.asc", $key) == OPENPGP_OK(),
            "($backend:$cmd) inline OpenPGP sign");
        ok($openpgp->inline_verify("$tempdir/sign-file-inline.asc", undef, $cert) == OPENPGP_OK(),
            "($backend:$cmd) verify generated inline OpenPGP signature");
    };

    # TODO: Add more test cases.
}

1;
