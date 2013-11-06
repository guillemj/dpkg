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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

use Test::More;

unless (defined $ENV{DPKG_DEVEL_MODE}) {
    plan skip_all => 'not running in development mode';
}

if (defined $ENV{srcdir}) {
    chdir $ENV{srcdir} or die "cannot chdir to source directory: $!";
}

if (not eval { require Test::Perl::Critic }) {
    plan skip_all => 'Test::Perl::Critic required to criticize code';
}
if (not eval { require Perl::Critic::Utils }) {
    plan skik_all => 'Perl::Critic::Utils required to criticize code';
}

my @policies = qw(
    BuiltinFunctions::ProhibitBooleanGrep
    BuiltinFunctions::ProhibitLvalueSubstr
    BuiltinFunctions::ProhibitReverseSortBlock
    BuiltinFunctions::ProhibitSleepViaSelect
    BuiltinFunctions::ProhibitStringySplit
    BuiltinFunctions::ProhibitUniversalCan
    BuiltinFunctions::ProhibitUniversalIsa
    BuiltinFunctions::ProhibitVoidGrep
    BuiltinFunctions::ProhibitVoidMap
    BuiltinFunctions::RequireBlockGrep
    BuiltinFunctions::RequireBlockMap
    BuiltinFunctions::RequireGlobFunction
    BuiltinFunctions::RequireSimpleSortBlock
    ClassHierarchies::ProhibitAutoloading
    ClassHierarchies::ProhibitExplicitISA
    ClassHierarchies::ProhibitOneArgBless
    CodeLayout::ProhibitHardTabs
    CodeLayout::ProhibitQuotedWordLists
    CodeLayout::ProhibitTrailingWhitespace
    CodeLayout::RequireConsistentNewlines
    ControlStructures::ProhibitCStyleForLoops
    ControlStructures::ProhibitLabelsWithSpecialBlockNames
    ControlStructures::ProhibitNegativeExpressionsInUnlessAndUntilConditions
    ControlStructures::ProhibitUntilBlocks
    Documentation::RequirePackageMatchesPodName
    InputOutput::ProhibitBarewordFileHandles
    InputOutput::ProhibitInteractiveTest
    InputOutput::ProhibitJoinedReadline
    InputOutput::ProhibitOneArgSelect
    InputOutput::ProhibitReadlineInForLoop
    InputOutput::ProhibitTwoArgOpen
    InputOutput::RequireEncodingWithUTF8Layer
    Miscellanea::ProhibitFormats
    Miscellanea::ProhibitUnrestrictedNoCritic
    Miscellanea::ProhibitUselessNoCritic
    Modules::ProhibitConditionalUseStatements
    Modules::ProhibitEvilModules
    Modules::RequireBarewordIncludes
    Modules::RequireEndWithOne
    Modules::RequireExplicitPackage
    Modules::RequireFilenameMatchesPackage
    NamingConventions::Capitalization
    Objects::ProhibitIndirectSyntax
    RegularExpressions::ProhibitUnusualDelimiters
    RegularExpressions::RequireBracesForMultiline
    Subroutines::ProhibitExplicitReturnUndef
    Subroutines::ProhibitNestedSubs
    Subroutines::ProhibitReturnSort
    Subroutines::ProhibitUnusedPrivateSubroutines
    Subroutines::ProtectPrivateSubs
    TestingAndDebugging::ProhibitNoStrict
    TestingAndDebugging::ProhibitNoWarnings
    TestingAndDebugging::RequireUseStrict
    TestingAndDebugging::RequireUseWarnings
    ValuesAndExpressions::ProhibitCommaSeparatedStatements
    ValuesAndExpressions::ProhibitComplexVersion
    ValuesAndExpressions::ProhibitInterpolationOfLiterals
    ValuesAndExpressions::ProhibitLongChainsOfMethodCalls
    ValuesAndExpressions::ProhibitMismatchedOperators
    ValuesAndExpressions::ProhibitMixedBooleanOperators
    ValuesAndExpressions::ProhibitQuotesAsQuotelikeOperatorDelimiters
    ValuesAndExpressions::ProhibitSpecialLiteralHeredocTerminator
    ValuesAndExpressions::ProhibitVersionStrings
    ValuesAndExpressions::RequireConstantVersion
    ValuesAndExpressions::RequireNumberSeparators
    ValuesAndExpressions::RequireQuotedHeredocTerminator
    ValuesAndExpressions::RequireUpperCaseHeredocTerminator
    Variables::ProhibitAugmentedAssignmentInDeclaration
    Variables::ProhibitConditionalDeclarations
    Variables::ProhibitLocalVars
    Variables::ProhibitPackageVars
    Variables::ProhibitPerl4PackageNames
    Variables::ProhibitUnusedVariables
    Variables::ProtectPrivateVars
    Variables::RequireLexicalLoopIterators
    Variables::RequireNegativeIndices
);

Test::Perl::Critic->import(
    -profile => 'test/100_critic/perlcriticrc',
    -verbose => 8,
    -include => \@policies,
    -only => 1,
);

my @dirs = qw(test src/t utils/t scripts/t dselect scripts/Dpkg);
my @files = glob 'scripts/Dpkg.pm scripts/*.pl scripts/changelog/*.pl';
push @files, Perl::Critic::Utils::all_perl_files(@dirs);

plan tests => scalar @files;

for my $file (@files) {
    critic_ok($file);
}
