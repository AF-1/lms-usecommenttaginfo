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

package Plugins::UseCommentTagInfo::Settings::SongDetails;

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
	$class->SUPER::new($plugin,1);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_USECOMMENTTAGINFO');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/UseCommentTagInfo/settings/songdetails.html');
}

sub currentPage {
	return Slim::Utils::Strings::string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_SONGDETAILS');
}

sub pages {
	my %page = (
		'name' => Slim::Utils::Strings::string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_SONGDETAILS'),
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

	# Save buttons config
	if ($paramRef->{saveSettings}) {
		my %songdetailsconfigmatrix;
		my %searchstringDone;

		for (my $n = 0; $n <= $maxItemNum; $n++) {
			my $songdetailsconfigID = $paramRef->{"pref_idNum_$n"};
			my $searchstring = trim_leadtail($paramRef->{"pref_searchstring_$n"} // '');
			next if (($searchstring eq '') || ($searchstring =~ m|[^a-zA-Z0-9 -]|) || ($searchstring =~ m|.{61,}|));
			my $contextmenucategoryname = trim_leadtail($paramRef->{"pref_contextmenucategoryname_$n"} // '');
			next if (($contextmenucategoryname eq '') || ($contextmenucategoryname =~ m|[\^{}$@<>"#%?*:/\|\\]|));
			my $contextmenucategorycontent = trim_leadtail($paramRef->{"pref_contextmenucategorycontent_$n"} // '');
			next if ($contextmenucategorycontent eq '');
			my $contextmenuposition = $paramRef->{"pref_contextmenuposition_$n"};

			if (!$searchstringDone{$searchstring}) {
				$songdetailsconfigmatrix{$songdetailsconfigID} = {
					'searchstring' => $searchstring,
					'contextmenucategoryname' => $contextmenucategoryname,
					'contextmenucategorycontent' => $contextmenucategorycontent,
					'contextmenuposition' => $contextmenuposition,
				};
				$searchstringDone{$searchstring} = 1;
			}
		}
		$prefs->set('songdetailsconfigmatrix', \%songdetailsconfigmatrix);
		$paramRef->{songdetailsconfigmatrix} = \%songdetailsconfigmatrix;
		$log->debug('SAVED VALUES = '.Dumper(\%songdetailsconfigmatrix));

		$result = $class->SUPER::handler($client, $paramRef);
	}
	# push to settings page

	my $songdetailsconfigmatrix = $prefs->get('songdetailsconfigmatrix');
	my @songdetailsconfiglist;
	foreach my $songdetailsconfig (sort keys %{$songdetailsconfigmatrix}) {
		$log->debug('songdetailsconfig = '.$songdetailsconfig);
		my $searchstring = $songdetailsconfigmatrix->{$songdetailsconfig}->{'searchstring'};
		$log->debug('searchstring = '.$searchstring);
		push (@songdetailsconfiglist, {
			'searchstring' => $songdetailsconfigmatrix->{$songdetailsconfig}->{'searchstring'},
			'contextmenucategoryname' => $songdetailsconfigmatrix->{$songdetailsconfig}->{'contextmenucategoryname'},
			'contextmenucategorycontent' => $songdetailsconfigmatrix->{$songdetailsconfig}->{'contextmenucategorycontent'},
			'contextmenuposition' => $songdetailsconfigmatrix->{$songdetailsconfig}->{'contextmenuposition'},
		});
	}

	# add empty field
	if ((scalar @songdetailsconfiglist + 1) < $maxItemNum) {
		push(@songdetailsconfiglist, {
			'searchstring' => '',
			'contextmenucategoryname' => '',
			'contextmenucategorycontent' => '',
			'contextmenuposition' => '',
		});
	}

	$paramRef->{songdetailsconfigmatrix} = \@songdetailsconfiglist;
	$paramRef->{itemcount} = scalar @songdetailsconfiglist;
	$log->debug('page list = '.Dumper($paramRef->{songdetailsconfigmatrix}));

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
