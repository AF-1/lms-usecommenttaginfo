#
# Use Comment Tag Info
#
# (c) 2021 AF-1
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#

package Plugins::UseCommentTagInfo::Settings::TitleFormats;

use strict;
use warnings;
use utf8;

use base qw(Plugins::UseCommentTagInfo::Settings::BaseSettings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Data::Dumper;

my $prefs = preferences('plugin.usecommenttaginfo');
my $log = logger('plugin.usecommenttaginfo');

my $plugin;

sub new {
	my $class = shift;
	$plugin = shift;
	$class->SUPER::new($plugin);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_USECOMMENTTAGINFO_SETTINGS_TITLEFORMATS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/UseCommentTagInfo/settings/titleformats.html');
}

sub currentPage {
	return name();
}

sub pages {
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
	return ($prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	my $result = undef;
	my $maxItemNum = 40;

	# Save title formats config
	if ($paramRef->{saveSettings}) {
		my %titleformatsconfigmatrix;
		my %searchstringDone;
		my %titleformatnameDone;

		for (my $n = 0; $n <= $maxItemNum; $n++) {
			my $titleformatsconfigID = $paramRef->{"pref_idNum_$n"};
			my $enabled = $paramRef->{"pref_enabled_$n"} // undef;
			my $searchstring = trim_leadtail($paramRef->{"pref_searchstring_$n"} // '');
			next if (($searchstring eq '') || ($searchstring =~ m|[^a-zA-Z0-9 -]|) || ($searchstring =~ m|.{61,}|));
			my $titleformatname = $paramRef->{"pref_titleformatname_$n"} // '';
			next if (($titleformatname eq '') || ($titleformatname =~ m|[\^{}$@<>"#%?*:/\|\\]|));
			$titleformatname = trim_all(uc($titleformatname));
			my $titleformatdisplaystring = trim_leadtail($paramRef->{"pref_titleformatdisplaystring_$n"} // '');
			next if ($titleformatdisplaystring eq '');

			if (!$searchstringDone{$searchstring} && !$titleformatnameDone{$titleformatname}) {
				$titleformatsconfigmatrix{$titleformatsconfigID} = {
					'enabled' => $enabled,
					'searchstring' => $searchstring,
					'titleformatname' => $titleformatname,
					'titleformatdisplaystring' => $titleformatdisplaystring
				};
				$searchstringDone{$searchstring} = 1;
				$titleformatnameDone{$titleformatname} = 1;
			}
		}
		$prefs->set('titleformatsconfigmatrix', \%titleformatsconfigmatrix);
		$paramRef->{titleformatsconfigmatrix} = \%titleformatsconfigmatrix;
		$log->debug('SAVED VALUES = '.Dumper(\%titleformatsconfigmatrix));

		$result = $class->SUPER::handler($client, $paramRef);
	}
	# push to settings page

	my $titleformatsconfigmatrix = $prefs->get('titleformatsconfigmatrix');
	my $titleformatsconfiglist;
	foreach my $titleformatsconfig (sort keys %{$titleformatsconfigmatrix}) {
		$log->debug('titleformatsconfig = '.$titleformatsconfig);
		my $searchstring = $titleformatsconfigmatrix->{$titleformatsconfig}->{'searchstring'};
		$log->debug('searchstring = '.$searchstring);
		push (@{$titleformatsconfiglist}, {
			'enabled' => $titleformatsconfigmatrix->{$titleformatsconfig}->{'enabled'},
			'searchstring' => $titleformatsconfigmatrix->{$titleformatsconfig}->{'searchstring'},
			'titleformatname' => $titleformatsconfigmatrix->{$titleformatsconfig}->{'titleformatname'},
			'titleformatdisplaystring' => $titleformatsconfigmatrix->{$titleformatsconfig}->{'titleformatdisplaystring'}
		});
	}

	my (@titleformatsconfiglistsorted, @titleformatsconfiglistsortedDisabled);
	foreach my $thisconfig (@{$titleformatsconfiglist}) {
		if (defined $thisconfig->{enabled}) {
			push @titleformatsconfiglistsorted, $thisconfig;
		} else {
			push @titleformatsconfiglistsortedDisabled, $thisconfig;
		}
	}
	@titleformatsconfiglistsorted = sort {$a->{titleformatname} cmp $b->{titleformatname}} @titleformatsconfiglistsorted;
	@titleformatsconfiglistsortedDisabled = sort {$a->{titleformatname} cmp $b->{titleformatname}} @titleformatsconfiglistsortedDisabled;
	push (@titleformatsconfiglistsorted, @titleformatsconfiglistsortedDisabled);

	# add empty field
	if ((scalar @titleformatsconfiglistsorted + 1) < $maxItemNum) {
		push(@titleformatsconfiglistsorted, {
			'enabled' => undef,
			'searchstring' => '',
			'titleformatname' => '',
			'titleformatdisplaystring' => ''
		});
	}

	$paramRef->{titleformatsconfigmatrix} = \@titleformatsconfiglistsorted;
	$paramRef->{itemcount} = scalar @titleformatsconfiglistsorted;
	$log->debug('page list = '.Dumper($paramRef->{titleformatsconfigmatrix}));

	$result = $class->SUPER::handler($client, $paramRef);

	return $result;
}

sub trim_all {
	my ($str) = @_;
	$str =~ s/ //g;
	return $str;
}

sub trim_leadtail {
	my ($str) = @_;
	$str =~ s{^\s+}{};
	$str =~ s{\s+$}{};
	return $str;
}

1;
