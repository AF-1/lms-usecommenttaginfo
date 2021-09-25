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

package Plugins::UseCommentTagInfo::Settings::BrowseMenus;

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
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/UseCommentTagInfo/settings/browsemenus.html');
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
	return ($prefs, qw(vlstempdisabled compisbygenre compisrandom operanoxmas));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	my $result = undef;
 	my $maxItemNum = 40;

	if ($paramRef->{saveSettings}) {
		my %browsemenusconfigmatrix;
		my %searchstringDone;
		my %browsemenu_nameDone;

		for (my $n = 0; $n <= $maxItemNum; $n++) {
			my $browsemenusconfigID = $paramRef->{"pref_idNum_$n"};
			next if (!defined $browsemenusconfigID);
			my $num_menus_enabled = 0;
			my $enabled = $paramRef->{"pref_enabled_$n"} // undef;
			my $searchstring = trim_leadtail($paramRef->{"pref_searchstring_$n"} // '');
			next if (($searchstring eq '') || ($searchstring =~ m|[^a-zA-Z0-9 -]|) || ($searchstring =~ m|.{61,}|));
			my $searchstringexclude = trim_leadtail($paramRef->{"pref_searchstringexclude_$n"} // '');
			next if (($searchstringexclude =~ m|[^a-zA-Z0-9 -]|) || ($searchstringexclude =~ m|.{61,}|));
			my $browsemenu_name = trim_leadtail($paramRef->{"pref_browsemenu_name_$n"} // '');
			next if (($browsemenu_name eq '') || ($browsemenu_name =~ m|[\^{}$@<>"#%?*:/\|\\]|));
			my $browsemenu_contributor_allartists = $paramRef->{"pref_browsemenu_contributor_allartists_$n"} // undef;
			my $browsemenu_contributor_albumartists = $paramRef->{"pref_browsemenu_contributor_albumartists_$n"} // undef;
			my $browsemenu_contributor_composers = $paramRef->{"pref_browsemenu_contributor_composers_$n"} // undef;
			my $browsemenu_contributor_conductors = $paramRef->{"pref_browsemenu_contributor_conductors_$n"} // undef;
			my $browsemenu_contributor_trackartists = $paramRef->{"pref_browsemenu_contributor_trackartists_$n"} // undef;
			my $browsemenu_contributor_bands = $paramRef->{"pref_browsemenu_contributor_bands_$n"} // undef;
			my $browsemenu_albums_all = $paramRef->{"pref_browsemenu_albums_all_$n"} // undef;
			my $browsemenu_albums_nocompis = $paramRef->{"pref_browsemenu_albums_nocompis_$n"} // undef;
			my $browsemenu_albums_compisonly = $paramRef->{"pref_browsemenu_albums_compisonly_$n"} // undef;
			my $browsemenu_genres = $paramRef->{"pref_browsemenu_genres_$n"} // undef;
			my $browsemenu_years = $paramRef->{"pref_browsemenu_years_$n"} // undef;
			my $browsemenu_tracks = $paramRef->{"pref_browsemenu_tracks_$n"} // undef;

			for ($browsemenu_contributor_allartists, $browsemenu_contributor_albumartists, $browsemenu_contributor_composers, $browsemenu_contributor_conductors, $browsemenu_contributor_trackartists, $browsemenu_contributor_bands, $browsemenu_albums_all, $browsemenu_albums_nocompis, $browsemenu_albums_compisonly, $browsemenu_genres, $browsemenu_years, $browsemenu_tracks) {
			$num_menus_enabled++ if defined;
			}
			$log->debug('number of browse menus enabled for \''.$browsemenu_name.'\' = '.$num_menus_enabled);
			if (($num_menus_enabled > 0) && !$searchstringDone{$searchstring.$searchstringexclude} && !$browsemenu_nameDone{$browsemenu_name}) {
				$browsemenusconfigmatrix{$browsemenusconfigID} = {
					'enabled' => $enabled,
					'searchstring' => $searchstring,
					'searchstringexclude' => $searchstringexclude,
					'browsemenu_name' => $browsemenu_name,
					'browsemenu_contributor_allartists' => $browsemenu_contributor_allartists,
					'browsemenu_contributor_albumartists' => $browsemenu_contributor_albumartists,
					'browsemenu_contributor_composers' => $browsemenu_contributor_composers,
					'browsemenu_contributor_conductors' => $browsemenu_contributor_conductors,
					'browsemenu_contributor_trackartists' => $browsemenu_contributor_trackartists,
					'browsemenu_contributor_bands' => $browsemenu_contributor_bands,
					'browsemenu_albums_all' => $browsemenu_albums_all,
					'browsemenu_albums_nocompis' => $browsemenu_albums_nocompis,
					'browsemenu_albums_compisonly' => $browsemenu_albums_compisonly,
					'browsemenu_genres' => $browsemenu_genres,
					'browsemenu_years' => $browsemenu_years,
					'browsemenu_tracks' => $browsemenu_tracks,
			};

				$searchstringDone{$searchstring.$searchstringexclude} = 1;
				$browsemenu_nameDone{$browsemenu_name} = 1;
			}
		}
		$prefs->set('browsemenusconfigmatrix', \%browsemenusconfigmatrix);
		$paramRef->{browsemenusconfigmatrix} = \%browsemenusconfigmatrix;
		$log->debug('SAVED VALUES = '.Dumper(\%browsemenusconfigmatrix));

		$result = $class->SUPER::handler($client, $paramRef);
	}

	# push to settings page

	my $browsemenusconfigmatrix = $prefs->get('browsemenusconfigmatrix');
	my $browsemenusconfiglist;
	foreach my $browsemenusconfig (sort keys %{$browsemenusconfigmatrix}) {
		$log->debug('browsemenusconfig = '.$browsemenusconfig);
		my $searchstring = $browsemenusconfigmatrix->{$browsemenusconfig}->{'searchstring'};
		$log->debug('searchstring = '.$searchstring);
		push (@{$browsemenusconfiglist}, {
			'enabled' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'enabled'},
			'searchstring' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'searchstring'},
			'searchstringexclude' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'searchstringexclude'},
			'browsemenu_name' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_name'},
			'browsemenu_contributor_allartists' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_allartists'},
			'browsemenu_contributor_albumartists' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_albumartists'},
			'browsemenu_contributor_composers' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_composers'},
			'browsemenu_contributor_conductors' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_conductors'},
			'browsemenu_contributor_trackartists' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_trackartists'},
			'browsemenu_contributor_bands' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_bands'},
			'browsemenu_albums_all' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_albums_all'},
			'browsemenu_albums_nocompis' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_albums_nocompis'},
			'browsemenu_albums_compisonly' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_albums_compisonly'},
			'browsemenu_genres' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_genres'},
			'browsemenu_years' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_years'},
			'browsemenu_tracks' => $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_tracks'},
		});
	}

	my (@browsemenusconfiglistsorted, @browsemenusconfiglistsortedDisabled);
	foreach my $thisconfig (@{$browsemenusconfiglist}) {
		if (defined $thisconfig->{enabled}) {
			push @browsemenusconfiglistsorted, $thisconfig;
		} else {
			push @browsemenusconfiglistsortedDisabled, $thisconfig;
		}
	}
	@browsemenusconfiglistsorted = sort {lc($a->{browsemenu_name}) cmp lc($b->{browsemenu_name})} @browsemenusconfiglistsorted;
	@browsemenusconfiglistsortedDisabled = sort {lc($a->{browsemenu_name}) cmp lc($b->{browsemenu_name})} @browsemenusconfiglistsortedDisabled;
	push (@browsemenusconfiglistsorted, @browsemenusconfiglistsortedDisabled);

	# add empty row
	if ((scalar @browsemenusconfiglistsorted + 1) < $maxItemNum) {
		push(@browsemenusconfiglistsorted, {
			'enabled' => undef,
			'searchstring' => '',
			'searchstringexclude' => '',
			'browsemenu_name' => '',
			'browsemenu_contributor_allartists' => undef,
			'browsemenu_contributor_albumartists' => undef,
			'browsemenu_contributor_composers' => undef,
			'browsemenu_contributor_conductors' => undef,
			'browsemenu_contributor_trackartists' => undef,
			'browsemenu_contributor_bands' => undef,
			'browsemenu_albums_all' => undef,
			'browsemenu_albums_nocompis' => undef,
			'browsemenu_albums_compisonly' => undef,
			'browsemenu_genres' => undef,
			'browsemenu_years' => undef,
			'browsemenu_tracks' => undef,
		});
	}

	$paramRef->{browsemenusconfigmatrix} = \@browsemenusconfiglistsorted;
	$paramRef->{itemcount} = scalar @browsemenusconfiglistsorted;
	$log->debug('list pushed to page = '.Dumper($paramRef->{browsemenusconfigmatrix}));

	$result = $class->SUPER::handler($client, $paramRef);

	return $result;
}

sub trim_leadtail {
	my ($str) = @_;
	$str =~ s{^\s+}{};
	$str =~ s{\s+$}{};
	return $str;
}

sub trim_all {
	my ($str) = @_;
	$str =~ s/ //g;
	return $str;
}

1;
