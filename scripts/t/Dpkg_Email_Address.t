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

use v5.36;
use utf8;

use Test::More tests => 34;
use Test::Dpkg qw(:paths);

use ok qw(Dpkg::Email::Address);
use ok qw(Dpkg::Email::AddressList);

my $addr = Dpkg::Email::Address->new();

$addr->parse('Some Name <email@example.org>');
is($addr->as_string, 'Some Name <email@example.org>',
    'Parse address correctly');
is($addr->name, 'Some Name',
    'Parse bare name from address correctly');
is($addr->email, 'email@example.org',
    'Parse bare name from address correctly');

$addr->parse('Some "Alias" Name <email@example.org>');
is($addr->as_string, 'Some "Alias" Name <email@example.org>',
    'Parse address with alias correctly');
is($addr->name, 'Some "Alias" Name',
    'Parse name from address with alias correctly');
is($addr->email, 'email@example.org',
    'Parse email from address with alias correctly');

$addr->parse('Some (🤞) Name <email@example.org>');
is($addr->as_string, 'Some (🤞) Name <email@example.org>',
    'Parse address with UTF-8 literals correctly');
is($addr->name, 'Some (🤞) Name',
    'Parse name from address with UTF-8 literals correctly');
is($addr->email, 'email@example.org',
    'Parse email from address with UTF-8 literals correctly');

$addr->parse('"Some Name, Comma" <email@example.org>');
is($addr->as_string, '"Some Name, Comma" <email@example.org>',
    'Parse address with quoted comma correctly');
is($addr->name, '"Some Name, Comma"',
    'Parse name from address with quoted comma correctly');
is($addr->email, 'email@example.org',
    'Parse email from address with quoted comma correctly');

my @uploaders_exp = (
    {
        desc => 'bare single address',
        value => 'Some Name <email@example.org>',
        parsed => [
            {
                name => 'Some Name',
                email => 'email@example.org',
            },
        ],
    },
    {
        desc => 'single bare address with trailing comma',
        value => 'Some Name <email@example.org> , ',
        normalized => 'Some Name <email@example.org>',
        parsed => [
            {
                name => 'Some Name',
                email => 'email@example.org',
            },
        ],
    },
    {
        desc => 'single address with alias',
        value => 'Some "Alias" Name <email@example.org>',
        parsed => [
            {
                name => 'Some "Alias" Name',
                email => 'email@example.org',
            },
        ],
    },
    {
        desc => 'single address with quoted comma',
        value => '"Some Name, Comma" <email@example.org>',
        parsed => [
            {
                name => '"Some Name, Comma"',
                email => 'email@example.org',
            },
        ],
    },
    {
        desc => 'two bare addresses',
        value => 'Some Name <some@example.org> , Other Name <other@example.org>',
        normalized => 'Some Name <some@example.org>, Other Name <other@example.org>',
        parsed => [
            {
                name => 'Some Name',
                email => 'some@example.org',
            },
            {
                name => 'Other Name',
                email => 'other@example.org',
            },
        ],
    },
    {
        desc => 'two bare addresses with trailing comma',
        value => 'Some Name <some@example.org> , Other Name <other@example.org> , ',
        normalized => 'Some Name <some@example.org>, Other Name <other@example.org>',
        parsed => [
            {
                name => 'Some Name',
                email => 'some@example.org',
            },
            {
                name => 'Other Name',
                email => 'other@example.org',
            },
        ],
    },
    {
        desc => 'two addresses with quoted comma and trailing comma',
        value => 'Some "Alias" Name <some@example.org> , "Other Name, Comma" <other@example.org> , ',
        normalized => 'Some "Alias" Name <some@example.org>, "Other Name, Comma" <other@example.org>',
        parsed => [
            {
                name => 'Some "Alias" Name',
                email => 'some@example.org',
            },
            {
                name => '"Other Name, Comma"',
                email => 'other@example.org',
            },
        ],
    },
    {
        desc => 'three bare addresses',
        value => 'Some Name <some@example.org> , Other Name <other@example.org>, Yet Another Name <yan@example.org>',
        normalized => 'Some Name <some@example.org>, Other Name <other@example.org>, Yet Another Name <yan@example.org>',
        parsed => [
            {
                name => 'Some Name',
                email => 'some@example.org',
            },
            {
                name => 'Other Name',
                email => 'other@example.org',
            },
            {
                name => 'Yet Another Name',
                email => 'yan@example.org',
            },
        ],
    },
    {
        desc => 'two bare addresses with trailing comma',
        value => 'Some Name <some@example.org> , Other Name <other@example.org> , Yet Another Name <yan@example.org> , ',
        normalized => 'Some Name <some@example.org>, Other Name <other@example.org>, Yet Another Name <yan@example.org>',
        parsed => [
            {
                name => 'Some Name',
                email => 'some@example.org',
            },
            {
                name => 'Other Name',
                email => 'other@example.org',
            },
            {
                name => 'Yet Another Name',
                email => 'yan@example.org',
            },
        ],
    },
    {
        desc => 'three addresses with quoted comma and trailing comma',
        value => 'Some "Alias" Name <some@example.org> , "Other Name, Comma"  <other@example.org> , Yet "Ds, Another" Name <yan@example.org> , ',
        normalized => 'Some "Alias" Name <some@example.org>, "Other Name, Comma"  <other@example.org>, Yet "Ds, Another" Name <yan@example.org>',
        parsed => [
            {
                name => 'Some "Alias" Name',
                email => 'some@example.org',
            },
            {
                name => '"Other Name, Comma" ',
                email => 'other@example.org',
            },
            {
                name => 'Yet "Ds, Another" Name',
                email => 'yan@example.org',
            },
        ],
    },
);

foreach my $uploader (@uploaders_exp) {
    my $addrlist = Dpkg::Email::AddressList->new($uploader->{value});

    my @res = map {
        $_->as_struct()
    } $addrlist->addrlist();

    is_deeply(\@res, $uploader->{parsed},
        "Parse uploader from $uploader->{desc}");
    is($addrlist->as_string(), $uploader->{normalized} // $uploader->{value},
        "Parse uploader from $uploader->{desc}, and stringified back");
}
