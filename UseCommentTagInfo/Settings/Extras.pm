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

package Plugins::UseCommentTagInfo::Settings::Extras;

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
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_USECOMMENTTAGINFO_SETTINGS_EXTRAS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/UseCommentTagInfo/settings/extras.html');
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
	return ($prefs, qw(compisrandom_genreexcludelist toplevelplaylistname alterativetoplevelplaylistname browsemenus_parentfoldername browsemenus_parentfoldericon));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	if ($paramRef->{'saveSettings'}) { }
	my $result = $class->SUPER::handler($client, $paramRef);
	return $result;
}

sub beforeRender {
	my ($class, $paramRef) = @_;
	my $toplevelplaylistname = $prefs->get('toplevelplaylistname');
	my @allplaylists = ();
	my $queryresult = Slim::Control::Request::executeRequest(undef, ['playlists', '0', '500']);
	my $playlistcount = $queryresult->getResult('count');

	if ($playlistcount > 0) {
		my $playlistarray = $queryresult->getResult('playlists_loop');
		push @{$playlistarray}, {playlist => 'none', id => 0};
		my @pagePLarray;

		foreach my $thisPL (@{$playlistarray}) {
			my $thisPLname = $thisPL->{'playlist'};
			my $chosen = '';
			if ($thisPLname eq $toplevelplaylistname) {$chosen = 'yes';}
			my $thisPLid = $thisPL->{'id'};
			push @pagePLarray, {playlist => $thisPLname, id => $thisPLid, chosen => $chosen};
		}
		my @sortedarray = sort {$a->{id} <=> $b->{id}} @pagePLarray;

		$log->debug('sorted playlists = '.Dumper(\@sortedarray));
		if ($toplevelplaylistname ne 'none') {
			$paramRef->{homemenuplaylist} = 'linked';
		}
		$paramRef->{playlistcount} = $playlistcount;
		$paramRef->{allplaylists} = \@sortedarray;
	}
}

1;
