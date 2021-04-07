#
# Use Comment Tag Info
#
# 2021 AF-1
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

package Plugins::UseCommentTagInfo::Plugin;

use strict;
use warnings;
use utf8;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Text;
use Slim::Schema;
use Data::Dumper;

use Plugins::UseCommentTagInfo::Settings;

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.usecommenttaginfo',
	'defaultLevel' => 'WARN',
	'description' => 'PLUGIN_USECOMMENTTAGINFO',
});
my $serverPrefs = preferences('server');
my $prefs = preferences('plugin.usecommenttaginfo');

$prefs->setChange(\&changedPrefs, 'commenttagconfigmatrix');

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(@_);

	initTitleFormats();
	initTrackInfoHandler();

	if (main::WEBUI) {
		Plugins::UseCommentTagInfo::Settings->new($class);
	}
}

sub initTrackInfoHandler {
	my $commenttagconfigmatrix = $prefs->get('commenttagconfigmatrix');
	if (keys %{$commenttagconfigmatrix} > 0) {
		foreach my $commenttagconfig (keys %{$commenttagconfigmatrix}) {
			if ($commenttagconfig ne '') {
				my $commenttagconfigID = $commenttagconfig;
				$log->debug('commentconfigID = '.$commenttagconfigID);
				my $searchstring = $commenttagconfigmatrix->{$commenttagconfig}->{'searchstring'};
				my $contextmenucategoryname = $commenttagconfigmatrix->{$commenttagconfig}->{'contextmenucategoryname'};
				if (defined $searchstring && defined $contextmenucategoryname) {
					my $contextmenuposition = $commenttagconfigmatrix->{$commenttagconfig}->{'contextmenuposition'};
					my $regID = "usecommenttaginfo_".$commenttagconfigID;
					my $possiblecontextmenupositions = [
						"after => 'artwork'", # 0
						"after => 'bottom'", # 1
						"parent => 'moreinfo', isa => 'top'", # 2
						"parent => 'moreinfo', isa => 'bottom'" # 3
					];
					my $thisPos = @{$possiblecontextmenupositions}[$contextmenuposition];
					Slim::Menu::TrackInfo->deregisterInfoProvider($regID);
					Slim::Menu::TrackInfo->registerInfoProvider($regID => (
						eval($thisPos),
						func => sub {
							return getTrackInfo(@_,$commenttagconfigID);
						}
					));
				}
			}
		}
	}
}

sub getTrackInfo {
	my ( $client, $url, $track, $remoteMeta, $tags, $filter, $commenttagconfigID) = @_;
	$log->debug("commenttagconfigID = ".$commenttagconfigID);

	if (Slim::Music::Import->stillScanning) {
		$log->warn("Warning: not available until library scan is completed");
		return;
	}
	my $commenttagconfigmatrix = $prefs->get('commenttagconfigmatrix');
	my $commenttagconfig = $commenttagconfigmatrix->{$commenttagconfigID};
		if (($commenttagconfig->{'searchstring'}) && ($commenttagconfig->{'contextmenucategoryname'}) && ($commenttagconfig->{'contextmenucategorycontent'})) {
				my $itemname = $commenttagconfig->{'contextmenucategoryname'};
				my $itemvalue = $commenttagconfig->{'contextmenucategorycontent'};

				my $thiscomment = $track->comment;

				if (defined $thiscomment && $thiscomment ne '') {
					if (index(lc($thiscomment), lc($commenttagconfig->{'searchstring'})) != -1) {

						$log->debug("text = ".$itemname.': '.$itemvalue);
						return {
							type => 'text',
							name => $itemname.': '.$itemvalue,
							itemvalue => $itemvalue,
							itemid => $track->id,
						};
					}
				}
		}
return;
}

sub initTitleFormats {
	my $commenttagconfigmatrix = $prefs->get('commenttagconfigmatrix');
	if (keys %{$commenttagconfigmatrix} > 0) {
		foreach my $commenttagconfig (keys %{$commenttagconfigmatrix}) {
			if ($commenttagconfig ne '') {
				my $commentconfigID = $commenttagconfig;
				my $titleformatenabled = $commenttagconfigmatrix->{$commenttagconfig}->{'titleformatenabled'};
				my $titleformatname = $commenttagconfigmatrix->{$commenttagconfig}->{'titleformatname'};
				if (defined $titleformatenabled && defined $titleformatname) {
					my $TF_name = "UCTI_".$titleformatname;
					addTitleFormat($TF_name);
					Slim::Music::TitleFormatter::addFormat($TF_name, sub {
							return getTitleFormat(@_,$commentconfigID);
					});
				}
			}
		}
	}
}

sub getTitleFormat {
	my $TF_string = '';
	if (Slim::Music::Import->stillScanning) {
		$log->warn("Warning: not available until library scan is completed");
		return $TF_string;
	}
	my $track = shift;
	my $commentconfigID = shift;
	$log->debug("commentconfigID = ".$commentconfigID);
	my $commenttagconfigmatrix = $prefs->get('commenttagconfigmatrix');
	my $commenttagconfig = $commenttagconfigmatrix->{$commentconfigID};
	my $titleformatname = $commenttagconfig->{'titleformatname'};
	my $titleformatdisplaystring = $commenttagconfig->{'titleformatdisplaystring'};
	if (($titleformatname ne '') && ($titleformatdisplaystring ne '')) {
		my $thiscomment = $track->comment;
		if (defined $thiscomment && $thiscomment ne '') {
			if (index(lc($thiscomment), lc($commenttagconfig->{'searchstring'})) != -1) {
				$TF_string = $titleformatdisplaystring;
			}
		}
	}
	$log->debug("returned title format display string = ".Dumper($TF_string));
	return $TF_string;
}

sub changedPrefs {
	initTitleFormats();
	initTrackInfoHandler();
	Slim::Music::Info::clearFormatDisplayCache();
}

sub getCustomSkipFilterTypes {
	my @result = ();

	my %commentkeyword = (
		'id' => 'usecommenttaginfo_commentkeyword',
		'name' => 'Comment includes keyword',
		'mixtype' => 'track',
		'description' => 'Skip songs with specified keyword in comment tag (case insensitive)',
		'mixonly' => 1,
		'parameters' => [
			{
				'id' => 'keyword',
				'type' => 'text',
				'name' => 'Enter keyword'
			}
		]
	);
	push @result, \%commentkeyword;

	my %tracktitlekeyword = (
		'id' => 'usecommenttaginfo_tracktitlekeyword',
		'name' => 'Track title includes keyword',
		'mixtype' => 'track',
		'description' => 'Skip songs with specified keyword in track title (case insensitive)',
		'mixonly' => 1,
		'parameters' => [
			{
				'id' => 'titlekeyword',
				'type' => 'text',
				'name' => 'Enter keyword'
			}
		]
	);
	push @result, \%tracktitlekeyword;

	return \@result;
}

sub checkCustomSkipFilterType {
	my $client = shift;
	my $filter = shift;
	my $track = shift;

	my $parameters = $filter->{'parameter'};
	if($filter->{'id'} eq 'usecommenttaginfo_commentkeyword') {
		my $thiscomment = $track->comment;
		for my $parameter (@{$parameters}) {
			if($parameter->{'id'} eq 'keyword') {
				my $keywords = $parameter->{'value'};
				my $keyword = $keywords->[0] if(defined($keywords) && scalar(@{$keywords})>0);

				if (defined $thiscomment && $thiscomment ne '') {
					if (index(lc($thiscomment), lc($keyword)) != -1) {
						return 1;
					}
					last;
				}
			}
		}
	} elsif($filter->{'id'} eq 'usecommenttaginfo_tracktitlekeyword') {
		my $thistracktitle = $track->title;
		for my $parameter (@{$parameters}) {
			if($parameter->{'id'} eq 'titlekeyword') {
				my $titlekeywords = $parameter->{'value'};
				my $titlekeyword = $titlekeywords->[0] if(defined($titlekeywords) && scalar(@{$titlekeywords})>0);

				if (defined $thistracktitle && $thistracktitle ne '') {
					if (index(lc($thistracktitle), lc($titlekeyword)) != -1) {
						return 1;
					}
					last;
				}
			}
		}
	}
	return 0;
}

sub addTitleFormat {
	my $titleformat = shift;
	my $titleFormats = $serverPrefs->get('titleFormat');
	foreach my $format (@{$titleFormats}) {
		if($titleformat eq $format) {
			return;
		}
	}
	push @{$titleFormats},$titleformat;
	$serverPrefs->set('titleFormat',$titleFormats);
}

1;
