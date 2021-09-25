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

package Plugins::UseCommentTagInfo::Plugin;

use strict;
use warnings;
use utf8;

use base qw(Slim::Plugin::Base);

use Scalar::Util qw(blessed);
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Text;
use Slim::Schema;
use Data::Dumper;

use Plugins::UseCommentTagInfo::Settings::SongDetails;
use Plugins::UseCommentTagInfo::Settings::TitleFormats;
use Plugins::UseCommentTagInfo::Settings::BrowseMenus;
use Plugins::UseCommentTagInfo::Settings::Extras;

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.usecommenttaginfo',
	'defaultLevel' => 'WARN',
	'description' => 'PLUGIN_USECOMMENTTAGINFO',
});
my $serverPrefs = preferences('server');
my $prefs = preferences('plugin.usecommenttaginfo');
my $isPostScanCall = 0;

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	initPrefs();
	initTitleFormats();
	initTrackInfoHandler();

	if (main::WEBUI) {
		Plugins::UseCommentTagInfo::Settings::SongDetails->new($class);
		Plugins::UseCommentTagInfo::Settings::TitleFormats->new($class);
		Plugins::UseCommentTagInfo::Settings::BrowseMenus->new($class);
		Plugins::UseCommentTagInfo::Settings::Extras->new($class);
	}
	Slim::Control::Request::subscribe(sub{
		initVirtualLibrariesDelayed();
		$isPostScanCall = 1;
	},[['rescan'],['done']]);
}

sub initPrefs {
	my $browsemenus_parentfoldername = $prefs->get('browsemenus_parentfoldername');
	if (!defined $browsemenus_parentfoldername) {
		$prefs->set('browsemenus_parentfoldername', 'My Custom Menus');
	}
	my $browsemenus_parentfoldericon = $prefs->get('browsemenus_parentfoldericon');
	if (!defined $browsemenus_parentfoldericon) {
		$prefs->set('browsemenus_parentfoldericon', '0');
	}
	my $compisbygenre = $prefs->get('compisbygenre');
	my $compisrandom = $prefs->get('compisrandom');
	my $compisrandom_genreexcludelist = $prefs->get('compisrandom_genreexcludelist');
	if (!defined $compisrandom_genreexcludelist) {
		$prefs->set('compisrandom_genreexcludelist', 'Classical,Classical - Opera,Classical - BR,Soundtrack - TV &amp; Movie Themes');
	}
	my $operanoxmas = $prefs->get('operanoxmas');
	my $toplevelplaylistname = $prefs->get('toplevelplaylistname');
	if (!defined $toplevelplaylistname) {
		$prefs->set('toplevelplaylistname', 'none');
	}
	my $alterativetoplevelplaylistname = $prefs->get('alterativetoplevelplaylistname') || '';

	$prefs->init({
		browsemenus_parentfoldername => $browsemenus_parentfoldername,
		browsemenus_parentfoldericon => $browsemenus_parentfoldericon,
		compisbygenre => $compisbygenre,
		compisrandom => $compisrandom,
		compisrandom_genreexcludelist => $compisrandom_genreexcludelist,
		operanoxmas => $operanoxmas,
		toplevelplaylistname => $toplevelplaylistname,
		alterativetoplevelplaylistname => $alterativetoplevelplaylistname
	});

	$prefs->setValidate({
		validator => sub {
			if (defined $_[1] && $_[1] ne '') {
				return if $_[1] =~ m|[\^{}$@<>"#%?*:/\|\\]|;
				return if $_[1] =~ m|.{61,}|;
			}
			return 1;
		}
	}, 'browsemenus_parentfoldername', 'alterativetoplevelplaylistname');

	$prefs->setValidate({
		validator => sub {
			return if $_[1] =~ m|[\^{}$@<>"#%?*:/\|\\]|;
			return 1;
		}
	}, 'compisrandom_genreexcludelist');

	$prefs->setChange(sub {
			$log->debug('Change in track handler config detected. Reinitializing trackinfohandler.');
			initTrackInfoHandler();
			Slim::Music::Info::clearFormatDisplayCache();
		}, 'songdetailsconfigmatrix');
	$prefs->setChange(sub {
			$log->debug('Change in title format config detected. Reinitializing titleformats.');
			initTitleFormats();
			Slim::Music::Info::clearFormatDisplayCache();
		}, 'titleformatsconfigmatrix');
	$prefs->setChange(sub {
			$log->debug('Change in VL config changed. Reinitializing VLs + menus.');
			initVirtualLibrariesDelayed();
		}, 'browsemenusconfigmatrix', 'operanoxmas', 'compisrandom', 'compisrandom_genreexcludelist', 'compisbygenre');
	$prefs->setChange(sub {
			$log->debug('Change in VL menus config changed. Reinitializing VL menus.');
			initVLMenus();
		}, 'browsemenus_parentfoldername', 'browsemenus_parentfoldericon');
	$prefs->setChange(sub {
			$log->debug('Change in toplevelPL config detected. Reinitializing top level PL link.');
			initPLtoplevellink();
		}, 'toplevelplaylistname', 'alterativetoplevelplaylistname');
}

sub postinitPlugin {
	initPLtoplevellink();
	initVirtualLibraries();
}

sub initVirtualLibraries {
	$log->debug('Start initializing VLs.');

	## check if VLs are globally disabled
	if (defined ($prefs->get('vlstempdisabled'))) {
		# unregister VLs
		$log->debug('browse menus/VLs globally disabled. Unregistering UCTI VLs.');
		my $libraries = Slim::Music::VirtualLibraries->getLibraries();
		foreach my $thisVLrealID (keys %{$libraries}) {
			my $thisVLID = $libraries->{$thisVLrealID}->{'id'};
			$log->debug('VLID: '.$thisVLID.' - RealID: '.$thisVLrealID);
			if (starts_with($thisVLID, 'UCTI_VLID_') == 0) {
				Slim::Music::VirtualLibraries->unregisterLibrary($thisVLrealID);
			}
		}

		# unregister menus
		my $browsemenus_parentfolderID = 'UCTI_MYCUSTOMMENUS';
		Slim::Menu::BrowseLibrary->deregisterNode($browsemenus_parentfolderID);
		Slim::Menu::BrowseLibrary->deregisterNode('UCTI_HOMEMENU_COMPIS_EXCLUDEDGENRES_BROWSEMENU_COMPIS_RANDOM');
		Slim::Menu::BrowseLibrary->deregisterNode('UCTI_HOMEMENU_COMPIS_BROWSEMENU_COMPIS_BYGENRE');

		return;
	}

	my $started = time();
	my $browsemenusconfigmatrix = $prefs->get('browsemenusconfigmatrix');
	my $compisrandom = $prefs->get('compisrandom');
	my $operanoxmas = $prefs->get('operanoxmas');
	$log->debug('browsemenusconfigmatrix = '.Dumper($browsemenusconfigmatrix));

	### create/register VLs for custom browse menus

	if (keys %{$browsemenusconfigmatrix} > 0) {

		# unregister UCTI virtual libraries that are no longer part of the browsemenusconfigmatrix

		my $libraries = Slim::Music::VirtualLibraries->getLibraries();
		$log->debug('Found these virtual libraries: '.Dumper($libraries));

		foreach my $thisVLrealID (keys %{$libraries}) {
			my $thisVLID = $libraries->{$thisVLrealID}->{'id'};
			$log->debug('VLID: '.$thisVLID.' - RealID: '.$thisVLrealID);
			if (starts_with($thisVLID, 'UCTI_VLID_') == 0) {
				my $VLisinBrowseMenusConfigMatrix = 0;
				foreach my $browsemenusconfig (sort {lc($browsemenusconfigmatrix->{$a}->{browsemenu_name}) cmp lc($browsemenusconfigmatrix->{$b}->{browsemenu_name})} keys %{$browsemenusconfigmatrix}) {
					next if (!defined ($browsemenusconfigmatrix->{$browsemenusconfig}->{'enabled'}));
					my $searchstring = $browsemenusconfigmatrix->{$browsemenusconfig}->{'searchstring'};
					my $searchstringexclude = $browsemenusconfigmatrix->{$browsemenusconfig}->{'searchstringexclude'};
					my $VLID;
					if (defined $searchstringexclude && ($searchstringexclude ne '')) {
						$VLID = 'UCTI_VLID_'.trim_all(uc($searchstring.$searchstringexclude));
					} else {
						$VLID = 'UCTI_VLID_'.trim_all(uc($searchstring));
					}
					if ($VLID eq $thisVLID) {
						$log->debug('VL \''.$VLID.'\' already exists and is still part of the browsemenusconfigmatrix. No need to unregister it.');
						$VLisinBrowseMenusConfigMatrix = 1;
					}
				}
				if ($VLisinBrowseMenusConfigMatrix == 0) {
					$log->debug('VL \''.$thisVLID.'\' is not part of the browsemenusconfigmatrix. Unregistering VL.');
					Slim::Music::VirtualLibraries->unregisterLibrary($thisVLrealID);
				}
			}
		}

		# create/register VLs that don't exist yet

		foreach my $browsemenusconfig (sort {lc($browsemenusconfigmatrix->{$a}->{browsemenu_name}) cmp lc($browsemenusconfigmatrix->{$b}->{browsemenu_name})} keys %{$browsemenusconfigmatrix}) {
			my $enabled = $browsemenusconfigmatrix->{$browsemenusconfig}->{'enabled'};
			next if (!defined $enabled);
			my $searchstring = $browsemenusconfigmatrix->{$browsemenusconfig}->{'searchstring'};
			$log->debug('searchstring = '.$searchstring);
			my $searchstringexclude = $browsemenusconfigmatrix->{$browsemenusconfig}->{'searchstringexclude'};
			$log->debug('searchstringexclude = '.Dumper($searchstringexclude));
			my $browsemenu_name = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_name'};
			my $VLID;
			my $sqlstatement;
			if (defined $searchstringexclude && ($searchstringexclude ne '')) {
				$VLID = 'UCTI_VLID_'.trim_all(uc($searchstring.$searchstringexclude));
				$sqlstatement = "select count (*) from tracks left join comments comments on comments.track = tracks.id where comments.value like \"%%$searchstring%%\" and tracks.audio = 1 and not exists(select * from comments where comments.track=tracks.id and comments.value like \"%%$searchstringexclude%%\")";
			} else {
				$VLID = 'UCTI_VLID_'.trim_all(uc($searchstring));
				$sqlstatement = "select count (*) from tracks left join comments comments on comments.track = tracks.id where comments.value like \"%%$searchstring%%\" and tracks.audio = 1";
			}
			$log->debug('VLID = '.$VLID);

			my $VLalreadyexists = Slim::Music::VirtualLibraries->getRealId($VLID);
			$log->debug('Check if VL already exists. Returned real library id = '.Dumper($VLalreadyexists));

 			if (defined $VLalreadyexists) {
 				$log->debug('VL \''.$VLID.'\' already exists. No need to recreate it.');
 				if ($isPostScanCall == 1) {
					$log->debug('This is a post-scan call so let\'s refresh VL \''.$VLID.'\'.');
					Slim::Music::VirtualLibraries->rebuild($VLalreadyexists);
 				}
 				next;
 			};
 			$log->debug('VL \''.$VLID.'\' has not been created yet. Creating & registering it now.');

			my $trackcount = 0;
			my $dbh = getCurrentDBH();
			eval{
				my $sth = $dbh->prepare($sqlstatement);
				$sth->execute();
				$trackcount = $sth->fetchrow;
			};
			if ($@) {$log->debug("error: $@");}

			$log->debug('Found '.$trackcount.($trackcount == 1 ? ' track' : ' tracks').' for virtual library '.$VLID);

			if ($trackcount > 0) {
				my $library;
				if (defined $searchstringexclude && $searchstringexclude ne '') {
					$library = {
						id => $VLID,
						name => $browsemenu_name,
						sql => qq{insert or ignore into library_track (library, track) select '%s', tracks.id from tracks left join comments comments on comments.track = tracks.id where comments.value like "%%$searchstring%%" and tracks.audio = 1 and not exists(select * from comments where comments.track=tracks.id and comments.value like "%%$searchstringexclude%%") group by tracks.id},
					};
				} else {
					$library = {
						id => $VLID,
						name => $browsemenu_name,
						sql => qq{insert or ignore into library_track (library, track) select '%s', tracks.id from tracks left join comments comments on comments.track = tracks.id where comments.value like "%%$searchstring%%" and tracks.audio = 1 group by tracks.id},
					};
				}

				$log->debug('Registering virtual library '.$VLID);
				Slim::Music::VirtualLibraries->registerLibrary($library);
				Slim::Music::VirtualLibraries->rebuild($library->{id});
			}
		}
		$isPostScanCall = 0;
	}

	### create/register VLs for predefined browse menus

	# compilations random
	my $compisrandomlibrary;
	my $compisrandom_genreexcludelist = $prefs->get('compisrandom_genreexcludelist');
	if (defined $compisrandom_genreexcludelist && $compisrandom_genreexcludelist ne '') {
		my @genres = split /,/, $compisrandom_genreexcludelist;
		my $genreexcludelist = '';
		$genreexcludelist = join ',', map qq/'$_'/, @genres;
		$log->debug('compis random genre exclude list = '.$genreexcludelist);
		$compisrandomlibrary = {
			id => 'UCTI_HOMEMENUVLID_COMPIS_EXCLUDEDGENRES',
			name => string('PLUGIN_USECOMMENTTAGINFO_VLNAME_COMPIS_EXCLUDEDGENRES'),
			sql => qq{insert or ignore into library_track (library, track) select '%s', tracks.id from tracks,albums left join comments comments on comments.track = tracks.id where albums.id=tracks.album and albums.compilation=1 and tracks.audio = 1 and not exists(select * from comments where comments.track=tracks.id and comments.value like '%%EoJ%%') and not exists(select * from genre_track,genres where genre_track.track=tracks.id and genre_track.genre=genres.id and genres.name in ($genreexcludelist)) group by tracks.id},
		};
	} else {
		$compisrandomlibrary = {
			id => 'UCTI_HOMEMENUVLID_COMPIS_EXCLUDEDGENRES',
			name => string('PLUGIN_USECOMMENTTAGINFO_VLNAME_COMPIS_EXCLUDEDGENRES'),
			sql => qq{insert or ignore into library_track (library, track) select '%s', tracks.id from tracks,albums left join comments comments on comments.track = tracks.id where albums.id=tracks.album and albums.compilation=1 and tracks.audio = 1 group by tracks.id},
		};
	}
	if (defined $compisrandom) {
		my $VLalreadyexists = Slim::Music::VirtualLibraries->getRealId($compisrandomlibrary->{id});
		$log->debug('Check if VL Compis Random already exists. Returned library id = '.Dumper($VLalreadyexists));

		if (!defined $VLalreadyexists) {
			$log->debug('VL Compis Random has not been created yet. Creating & registering it now.');
			Slim::Music::VirtualLibraries->registerLibrary($compisrandomlibrary);
			Slim::Music::VirtualLibraries->rebuild($compisrandomlibrary->{id});
		} else {
			$log->debug('VL Compis Random already exists. No need to recreate it.');
		}
	} else {
		$log->debug('Unregistering VL Compis Random');
		Slim::Music::VirtualLibraries->unregisterLibrary(Slim::Music::VirtualLibraries->getRealId($compisrandomlibrary->{id}));
	}

	# Opera without Christmas
	my $operanoxmas_library = {
		id => 'UCTI_VLID_OPERANOXMAS',
		name => string('PLUGIN_USECOMMENTTAGINFO_VLNAME_OPERANOXMAS'),
		sql => qq{insert or ignore into library_track (library, track) select '%s', tracks.id from tracks JOIN genre_track on tracks.id=genre_track.track JOIN genres on genre_track.genre=genres.id and genre_track.genre=genres.id left join comments as excludecomments on tracks.id=excludecomments.track and (excludecomments.value like '%%Christmas%%' OR excludecomments.value like '%%never%%') where tracks.audio=1 and genres.name in ('Classical - Opera', 'Opera') and excludecomments.id is null and tracks.secs>90 group by tracks.id},
	};
	if (defined $operanoxmas) {
		my $VLalreadyexists = Slim::Music::VirtualLibraries->getRealId($operanoxmas_library->{id});
		$log->debug('Check if VL OperaNoXmas already exists. Returned library id = '.Dumper($VLalreadyexists));

		if (!defined $VLalreadyexists) {
			Slim::Music::VirtualLibraries->registerLibrary($operanoxmas_library);
			Slim::Music::VirtualLibraries->rebuild($operanoxmas_library->{id});
		} else {
			$log->debug('VL OperaNoXmas already exists. No need to recreate it.');
		}
	} else {
		$log->debug('Unregistering VL OperaNoXmas');
		Slim::Music::VirtualLibraries->unregisterLibrary(Slim::Music::VirtualLibraries->getRealId($operanoxmas_library->{id}));
	}

	my $ended = time() - $started;
	initVLMenus();
}

sub initVLMenus {
	$log->debug('Started initializing VL menus.');
	my $browsemenusconfigmatrix = $prefs->get('browsemenusconfigmatrix');
	my $operanoxmas = $prefs->get('operanoxmas');
	my $browsemenus_parentfolderID = 'UCTI_MYCUSTOMMENUS';
	my $browsemenus_parentfoldername = $prefs->get('browsemenus_parentfoldername') || $prefs->set('browsemenus_parentfoldername', 'My Custom Menus');

 	# deregister parent folder menu
	Slim::Menu::BrowseLibrary->deregisterNode($browsemenus_parentfolderID);
	my $nameToken = registerCustomString($browsemenus_parentfoldername);

	if ((keys %{$browsemenusconfigmatrix} > 0) || (defined $operanoxmas)) {
		my $browsemenus_parentfoldericon = $prefs->get('browsemenus_parentfoldericon');
		my $iconPath;
		if ($browsemenus_parentfoldericon == 1) {
			$iconPath = 'plugins/UseCommentTagInfo/html/images/browsemenupfoldericon.png';
		} elsif ($browsemenus_parentfoldericon == 2) {
			$iconPath = 'plugins/UseCommentTagInfo/html/images/folder_svg.png';
		} else {
			$iconPath = 'plugins/UseCommentTagInfo/html/images/music_svg.png';
		}
		$log->debug('browsemenus_parentfoldericon = '.$browsemenus_parentfoldericon);
		$log->debug('iconPath = '.$iconPath);

		my @enabledbrowsemenus;
		foreach my $thisconfig (keys %{$browsemenusconfigmatrix}) {
			if (defined $browsemenusconfigmatrix->{$thisconfig}->{'enabled'}) {
				push @enabledbrowsemenus, $thisconfig;
			}
		}
		$log->debug('enabled configs = '.scalar(@enabledbrowsemenus));

		### browse menus in UCTI parent folder (custom browse menus + operanoxmas)

		if (scalar (@enabledbrowsemenus) > 0 || (defined $operanoxmas)) {
			Slim::Menu::BrowseLibrary->registerNode({
				type => 'link',
				name => $nameToken,
				id => $browsemenus_parentfolderID,
				feed => sub {
					my ($client, $cb, $args, $pt) = @_;
					my @browseMenus = ();

					foreach my $browsemenusconfig (sort {lc($browsemenusconfigmatrix->{$a}->{browsemenu_name}) cmp lc($browsemenusconfigmatrix->{$b}->{browsemenu_name})} keys %{$browsemenusconfigmatrix}) {
						my $enabled = $browsemenusconfigmatrix->{$browsemenusconfig}->{'enabled'};
						next if (!$enabled);
						my $searchstring = $browsemenusconfigmatrix->{$browsemenusconfig}->{'searchstring'};
						$log->debug('searchstring = '.$searchstring);
						my $searchstringexclude = $browsemenusconfigmatrix->{$browsemenusconfig}->{'searchstringexclude'};
						$log->debug('searchstringexclude = '.Dumper($searchstringexclude));
						my $VLID;
						if (defined $searchstringexclude && ($searchstringexclude ne '')) {
							$VLID = 'UCTI_VLID_'.trim_all(uc($searchstring.$searchstringexclude));
						} else {
							$VLID = 'UCTI_VLID_'.trim_all(uc($searchstring));
						}
						$log->debug('VLID = '.$VLID);
						my $library_id = Slim::Music::VirtualLibraries->getRealId($VLID);
						next if (!$library_id);

						if (defined $enabled && defined $library_id) {
							my $pt = {library_id => $library_id};
							my $browsemenu_name = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_name'};
							$log->debug('browsemenu_name = '.$browsemenu_name);
							my $browsemenu_contributor_allartists = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_allartists'};
							my $browsemenu_contributor_albumartists = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_albumartists'};
							my $browsemenu_contributor_composers = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_composers'};
							my $browsemenu_contributor_conductors = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_conductors'};
							my $browsemenu_contributor_trackartists = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_trackartists'};
							my $browsemenu_contributor_bands = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_contributor_bands'};
							my $browsemenu_albums_all = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_albums_all'};
							my $browsemenu_albums_nocompis = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_albums_nocompis'};
							my $browsemenu_albums_compisonly = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_albums_compisonly'};
							my $browsemenu_genres = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_genres'};
							my $browsemenu_years = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_years'};
							my $browsemenu_tracks = $browsemenusconfigmatrix->{$browsemenusconfig}->{'browsemenu_tracks'};

							### ARTISTS MENUS ###

							# user configurable list of artists
							if (defined $browsemenu_contributor_allartists) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_MENUDISPLAYNAME_CONTIBUTOR_ALLARTISTS'),
									url => \&Slim::Menu::BrowseLibrary::_artists,
									icon => 'html/images/artists.png',
									jiveIcon => 'html/images/artists.png',
									id => $VLID.'_BROWSEMENU_ALLARTISTS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 209,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'},
											#'role_id:'.join ',', Slim::Schema::Contributor->contributorRoles()
										],
									}],
								};
							}

							# Album artists
							if (defined $browsemenu_contributor_albumartists) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_CONTIBUTOR_ALBUMARTISTS'),
									url => \&Slim::Menu::BrowseLibrary::_artists,
									icon => 'html/images/artists.png',
									jiveIcon => 'html/images/artists.png',
									id => $VLID.'_BROWSEMENU_ALBUMARTISTS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 210,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'},
											'role_id:ALBUMARTIST'
										],
									}],
								};
							}

							# Composers
							if (defined $browsemenu_contributor_composers) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_CONTIBUTOR_COMPOSERS'),
									url => \&Slim::Menu::BrowseLibrary::_artists,
									icon => 'html/images/artists.png',
									jiveIcon => 'html/images/artists.png',
									id => $VLID.'_BROWSEMENU_COMPOSERS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 211,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'},
											'role_id:COMPOSER'
										],
									}],
								};
							}

							# Conductors
							if (defined $browsemenu_contributor_conductors) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_CONTIBUTOR_CONDUCTORS'),
									url => \&Slim::Menu::BrowseLibrary::_artists,
									icon => 'html/images/artists.png',
									jiveIcon => 'html/images/artists.png',
									id => $VLID.'_BROWSEMENU_CONDUCTORS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 212,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'},
											'role_id:CONDUCTOR'
										],
									}],
								};
							}

							# Track Artists
							if (defined $browsemenu_contributor_trackartists) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_CONTIBUTOR_TRACKARTISTS'),
									url => \&Slim::Menu::BrowseLibrary::_artists,
									icon => 'html/images/artists.png',
									jiveIcon => 'html/images/artists.png',
									id => $VLID.'_BROWSEMENU_TRACKARTISTS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 213,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'},
											'role_id:TRACKARTIST'
										],
									}],
								};
							}

							# Bands
							if (defined $browsemenu_contributor_bands) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_CONTIBUTOR_BANDS'),
									url => \&Slim::Menu::BrowseLibrary::_artists,
									icon => 'html/images/artists.png',
									jiveIcon => 'html/images/artists.png',
									id => $VLID.'_BROWSEMENU_BANDS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 214,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'},
											'role_id:BAND'
										],
									}],
								};
							}

							### ALBUMS MENUS ###

							# All Albums
							if (defined $browsemenu_albums_all) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_MENUDISPLAYNAME_ALBUMS_ALL'),
									url => \&Slim::Menu::BrowseLibrary::_albums,
									icon => 'html/images/albums.png',
									jiveIcon => 'html/images/albums.png',
									id => $VLID.'_BROWSEMENU_ALLALBUMS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 215,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'}
										],
									}],
								};
							}

							# Albums without compilations
							if (defined $browsemenu_albums_nocompis) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_ALBUMS_NOCOMPIS'),
									url => \&Slim::Menu::BrowseLibrary::_albums,
									icon => 'html/images/albums.png',
									jiveIcon => 'html/images/albums.png',
									id => $VLID.'_BROWSEMENU_ALBUM_NOCOMPIS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 216,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'},
											'compilation: 0 || null'
										],
									}],
								};
							}

							# Compilations only
							if (defined $browsemenu_albums_compisonly) {
								$pt = {library_id => Slim::Music::VirtualLibraries->getRealId($VLID),
										artist_id => Slim::Schema->variousArtistsObject->id,
								};
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_ALBUMS_COMPIS_ONLY'),
									mode => 'vaalbums',
									url => \&Slim::Menu::BrowseLibrary::_albums,
									icon => 'html/images/albums.png',
									jiveIcon => 'html/images/albums.png',
									id => $VLID.'_BROWSEMENU_ALBUM_COMPISONLY',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 217,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'},
											'artist_id:'.$pt->{'artist_id'},
											'compilation: 1'
										],
									}],
								};
							}

							# Genres menu
							if (defined $browsemenu_genres) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_GENRES'),
									url => \&Slim::Menu::BrowseLibrary::_genres,
									icon => 'html/images/genres.png',
									jiveIcon => 'html/images/genres.png',
									id => $VLID.'_BROWSEMENU_GENRE_ALL',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 218,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'}
										],
									}],
								};
							}

							# Years menu
							if (defined $browsemenu_years) {
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_MENUDISPLAYNAME_YEARS'),
									url => \&Slim::Menu::BrowseLibrary::_years,
									icon => 'html/images/years.png',
									jiveIcon => 'html/images/years.png',
									id => $VLID.'_BROWSEMENU_YEARS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 219,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'}
										],
									}],
								};
							}

							# Just Tracks Menu
							if (defined $browsemenu_tracks) {
								$pt = {library_id => Slim::Music::VirtualLibraries->getRealId($VLID),
										sort => 'track',
										menuStyle => 'menuStyle:album'};
								push @browseMenus,{
									type => 'link',
									name => $browsemenu_name.' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_TRACKS'),
									url => \&Slim::Menu::BrowseLibrary::_tracks,
									icon => 'html/images/playlists.png',
									jiveIcon => 'html/images/playlists.png',
									id => $VLID.'_BROWSEMENU_TRACKS',
									condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
									weight => 220,
									cache => 1,
									passthrough => [{
										library_id => $pt->{'library_id'},
										searchTags => [
											'library_id:'.$pt->{'library_id'}
										],
									}],
								};
							}
						}
					}

					### predefined browse menus inside UCTI parent folder

					# Opera without Christmas
					if (defined $operanoxmas) {
						$pt = {library_id => Slim::Music::VirtualLibraries->getRealId('UCTI_VLID_OPERANOXMAS')};

						push @browseMenus,{
							type => 'link',
							name => string('PLUGIN_USECOMMENTTAGINFO_MENUNAME_OPERANOXMAS').' - '.string('PLUGIN_USECOMMENTTAGINFO_SETTINGS_BROWSEMENUS_MENUDISPLAYNAME_ALBUMS_ALL'),
							url => \&Slim::Menu::BrowseLibrary::_albums,
							icon => 'html/images/albums.png',
							jiveIcon => 'html/images/albums.png',
							id => 'UCTI_VLID_OPERANOXMAS_BROWSEMENU_ALLALBUMS',
							condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
							weight => 215,
							cache => 1,
							passthrough => [{
								library_id => $pt->{'library_id'},
								searchTags => [
									'library_id:'.$pt->{'library_id'}
								],
							}],
						};
					}

					$cb->({
						items => \@browseMenus,
					});
				},
				weight => 98,
				cache => 0,
				icon => $iconPath,
				jiveIcon => $iconPath,
			});
		}
	}

	### predefined browse menus on home menu level

	my @MyUCTI_CustomHomeMenuItems;

	# compilations random
	Slim::Menu::BrowseLibrary->deregisterNode('UCTI_HOMEMENU_COMPIS_EXCLUDEDGENRES_BROWSEMENU_COMPIS_RANDOM');
	my $compisrandom = $prefs->get('compisrandom');
	if (defined $compisrandom) {
		push @MyUCTI_CustomHomeMenuItems,{
			type => 'link',
			name=> 'PLUGIN_USECOMMENTTAGINFO_MENUNAME_COMPISRANDOM',
			params=>{library_id => Slim::Music::VirtualLibraries->getRealId('UCTI_HOMEMENUVLID_COMPIS_EXCLUDEDGENRES'),
					mode => 'randomalbums',
					sort => 'random'},
			feed => \&Slim::Menu::BrowseLibrary::_albums,
			icon => 'plugins/UseCommentTagInfo/html/images/randomcompis_svg.png',
			jiveIcon => 'plugins/UseCommentTagInfo/html/images/randomcompis_svg.png',
			homeMenuText => 'PLUGIN_USECOMMENTTAGINFO_MENUNAME_COMPISRANDOM',
			condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
			id => 'UCTI_HOMEMENU_COMPIS_EXCLUDEDGENRES_BROWSEMENU_COMPIS_RANDOM',
			weight => 25,
			cache => 0,
		};
	}

	# compilations by genre
	Slim::Menu::BrowseLibrary->deregisterNode('UCTI_HOMEMENU_COMPIS_BROWSEMENU_COMPIS_BYGENRE');
	my $compisbygenre = $prefs->get('compisbygenre');
	if (defined $compisbygenre) {
		push @MyUCTI_CustomHomeMenuItems,{
			type => 'link',
			name => 'PLUGIN_USECOMMENTTAGINFO_MENUNAME_COMPISBYGENRE',
			params => {artist_id => Slim::Schema->variousArtistsObject->id,
						mode => 'genres',
						sort => 'title'},
			feed => \&Slim::Menu::BrowseLibrary::_genres,
			icon => 'plugins/UseCommentTagInfo/html/images/compisbygenre_svg.png',
			jiveIcon => 'plugins/UseCommentTagInfo/html/images/compisbygenre_svg.png',
			homeMenuText => 'PLUGIN_USECOMMENTTAGINFO_MENUNAME_COMPISBYGENRE',
			condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
			id => 'UCTI_HOMEMENU_COMPIS_BROWSEMENU_COMPIS_BYGENRE',
			weight => 26,
			cache => 1,
		};
	}

	if (scalar(@MyUCTI_CustomHomeMenuItems) > 0) {
		foreach (@MyUCTI_CustomHomeMenuItems) {
			Slim::Menu::BrowseLibrary->deregisterNode($_);
			Slim::Menu::BrowseLibrary->registerNode($_);
		}
	}
	$log->debug('Finished initializing VL menus');
}

sub initPLtoplevellink {
	$log->debug('Started initializing playlist toplevel link.');
	# deregister item first
	Slim::Menu::BrowseLibrary->deregisterNode('UCTI_HOMEMENU_TOPLEVEL_LINKEDPLAYLIST');

	# link to playlist in home menu
	my $toplevelplaylistname = $prefs->get('toplevelplaylistname') || 'none';
	if ($toplevelplaylistname eq 'none') {
		$prefs->set('alterativetoplevelplaylistname', '');
	}
	my $alterativetoplevelplaylistname = $prefs->get('alterativetoplevelplaylistname') || '';
	$log->debug('toplevelplaylistname = '.$toplevelplaylistname);
	$log->debug('alterativetoplevelplaylistname = '.Dumper($alterativetoplevelplaylistname));
	if ($toplevelplaylistname ne 'none') {
		my $homemenuTLPLname;
		if ($alterativetoplevelplaylistname ne '') {
			$log->debug('alterativetoplevelplaylistname = '.$alterativetoplevelplaylistname);
			$homemenuTLPLname = registerCustomString($alterativetoplevelplaylistname);
		} else {
			$homemenuTLPLname = registerCustomString($toplevelplaylistname);
		}
		$log->debug('name of home menu item for linked playlist = '.$homemenuTLPLname);
		my $toplevelplaylistID = getPlaylistIDforName($toplevelplaylistname);
		$log->debug('toplevelplaylistID = '.$toplevelplaylistID);

		Slim::Menu::BrowseLibrary->deregisterNode('UCTI_HOMEMENU_TOPLEVEL_LINKEDPLAYLIST');
		Slim::Menu::BrowseLibrary->registerNode({
			type => 'link',
			name => $homemenuTLPLname,
			params => {'playlist_id' => $toplevelplaylistID},
			feed => \&Slim::Menu::BrowseLibrary::_playlistTracks,
			icon => 'plugins/UseCommentTagInfo/html/images/browsemenupfoldericon.png',
			jiveIcon => 'plugins/UseCommentTagInfo/html/images/browsemenupfoldericon.png',
			homeMenuText => $homemenuTLPLname,
			condition => \&Slim::Menu::BrowseLibrary::isEnabledNode,
			id => 'UCTI_HOMEMENU_TOPLEVEL_LINKEDPLAYLIST',
			weight => 79,
			cache => 0,
		});
	}
	$log->debug('Finished initializing playlist toplevel link.');
}


sub initTrackInfoHandler {
	$log->debug('Start initializing trackinfohandlers.');
	my $songdetailsconfigmatrix = $prefs->get('songdetailsconfigmatrix');
	if (keys %{$songdetailsconfigmatrix} > 0) {
		foreach my $songdetailsconfig (keys %{$songdetailsconfigmatrix}) {
			my $enabled = $songdetailsconfigmatrix->{$songdetailsconfig}->{'enabled'};
			next if (!defined $enabled);
			my $songdetailsconfigID = $songdetailsconfig;
			$log->debug('songdetailsconfigID = '.$songdetailsconfigID);
			my $searchstring = $songdetailsconfigmatrix->{$songdetailsconfig}->{'searchstring'};
			my $contextmenucategoryname = $songdetailsconfigmatrix->{$songdetailsconfig}->{'contextmenucategoryname'};
			if (defined $searchstring && defined $contextmenucategoryname) {
				my $contextmenuposition = $songdetailsconfigmatrix->{$songdetailsconfig}->{'contextmenuposition'};
				my $regID = 'UCTI_TIHregID_'.$songdetailsconfigID;
				$log->debug('trackinfohandler ID = '.$regID);
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
						return getTrackInfo(@_,$songdetailsconfigID);
					}
				));
			}
		}
	}
	$log->debug('Finished initializing trackinfohandlers.');
}

sub getTrackInfo {
	my ($client, $url, $track, $remoteMeta, $tags, $filter, $songdetailsconfigID) = @_;
	$log->debug('songdetailsconfigID = '.$songdetailsconfigID);

	if (Slim::Music::Import->stillScanning) {
		$log->warn('Warning: not available until library scan is completed');
		return;
	}

	# check if remote track is part of online library
	if ((Slim::Music::Info::isRemoteURL($url) == 1)) {
		$log->debug('ignoring remote track without comment tag: '.$url);
		return;
	}

	# check for dead/moved local tracks
	if ((Slim::Music::Info::isRemoteURL($url) != 1) && (!defined($track->filesize))) {
		$log->debug('track dead or moved??? Track URL: '.$url);
		return;
	}

	my $songdetailsconfigmatrix = $prefs->get('songdetailsconfigmatrix');
	my $songdetailsconfig = $songdetailsconfigmatrix->{$songdetailsconfigID};
		if (($songdetailsconfig->{'searchstring'}) && ($songdetailsconfig->{'contextmenucategoryname'}) && ($songdetailsconfig->{'contextmenucategorycontent'})) {
			my $itemname = $songdetailsconfig->{'contextmenucategoryname'};
			my $itemvalue = $songdetailsconfig->{'contextmenucategorycontent'};
			my $thiscomment = $track->comment;

			if (defined $thiscomment && $thiscomment ne '') {
				if (index(lc($thiscomment), lc($songdetailsconfig->{'searchstring'})) != -1) {

					$log->debug('text = '.$itemname.': '.$itemvalue);
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
	$log->debug('Start initializing titleformats.');
	my $titleformatsconfigmatrix = $prefs->get('titleformatsconfigmatrix');
	if (keys %{$titleformatsconfigmatrix} > 0) {
		foreach my $titleformatsconfig (keys %{$titleformatsconfigmatrix}) {
			if ($titleformatsconfig ne '') {
				my $enabled = $titleformatsconfigmatrix->{$titleformatsconfig}->{'enabled'};
				next if (!defined $enabled);
				my $titleformatsconfigID = $titleformatsconfig;
				$log->debug('titleformatsconfigID = '.$titleformatsconfigID);
				my $titleformatname = $titleformatsconfigmatrix->{$titleformatsconfig}->{'titleformatname'};
				if (defined $titleformatname) {
					my $TF_name = 'UCTI_'.uc(trim_all($titleformatname));
					$log->debug('titleformat name = '.$TF_name);
					addTitleFormat($TF_name);
					Slim::Music::TitleFormatter::addFormat($TF_name, sub {
						return getTitleFormat(@_,$titleformatsconfigID);
					});
				}
			}
		}
	}
	$log->debug('Finished initializing titleformats.');
}

sub getTitleFormat {
	my $track = shift;
	my $titleformatsconfigID = shift;
	my $TF_string = HTML::Entities::decode_entities('&#xa0;'); # "NO-BREAK SPACE" - HTML Entity (hex): &#xa0;

	if (Slim::Music::Import->stillScanning) {
		$log->warn('Warning: not available until library scan is completed');
		return $TF_string;
	}
	$log->debug('titleformatsconfigID = '.$titleformatsconfigID);

	if ($track && !blessed($track)) {
		$log->debug('track is not blessed');
 		$track = Slim::Schema->find('Track', $track->{id});
		if (!blessed($track)) {
			$log->debug('No track object found');
			return $TF_string;
		}
	}
	my $trackURL = $track->url;

	# check if remote track is part of online library
	if ((Slim::Music::Info::isRemoteURL($trackURL) == 1)) {
		$log->info('ignoring remote track without comment tag: '.$trackURL);
		return $TF_string;
	}

	# check for dead/moved local tracks
	if ((Slim::Music::Info::isRemoteURL($trackURL) != 1) && (!defined($track->filesize))) {
		$log->info('track dead or moved??? Track URL: '.$trackURL);
		return $TF_string;
	}

	my $titleformatsconfigmatrix = $prefs->get('titleformatsconfigmatrix');
	my $titleformatsconfig = $titleformatsconfigmatrix->{$titleformatsconfigID};
	my $titleformatname = $titleformatsconfig->{'titleformatname'};
	my $titleformatdisplaystring = $titleformatsconfig->{'titleformatdisplaystring'};
	if (($titleformatname ne '') && ($titleformatdisplaystring ne '')) {
		my $thiscomment = $track->comment;
		if (defined $thiscomment && $thiscomment ne '') {
			if (index(lc($thiscomment), lc($titleformatsconfig->{'searchstring'})) != -1) {
				$TF_string = $titleformatdisplaystring;
			}
		}
	}
	$log->debug('returned title format display string for track = '.Dumper($TF_string));
	return $TF_string;
}


sub initVirtualLibrariesDelayed {
	$log->debug('Delayed VL init to prevent multiple inits');
	$log->debug('Killing existing VL init timers');
	Slim::Utils::Timers::killOneTimer(undef, \&initVirtualLibraries);
	$log->debug('Scheduling a delayed VL init');
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 5, \&initVirtualLibraries);
}

sub initExtraMenusDelayed {
	$log->debug('Delayed extra menus init invoked to prevent multiple inits');
	$log->debug('Killing existing timers');
	Slim::Utils::Timers::killOneTimer(undef, \&initExtraMenus);
	$log->debug('Scheduling a delayed extra menus init');
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 2, \&initExtraMenus);
}

sub getPlaylistIDforName {
	my $playlistname = shift;
	my $queryresult = Slim::Control::Request::executeRequest('', ['playlists', 0, 1, 'search:'.$playlistname]);
	my $existsPL = $queryresult->getResult('count');
	my $playlistid;
	if ($existsPL > 0) {
		$log->debug('Playlist \''.$playlistname.'\' exists.');
		my $PLloop = $queryresult->getResult('playlists_loop');
		foreach my $playlist (@{$PLloop}) {
			$playlistid = $playlist->{id};
		}
	return $playlistid || '' ;
	} else {
		$log->warn('Couldn\'t find chosen playlist to link to.')
	}
}

sub registerCustomString {
	my $string = shift;
	if (!Slim::Utils::Strings::stringExists($string)) {
		my $token = uc(Slim::Utils::Text::ignoreCase($string, 1));
		$token =~ s/\s/_/g;
		$token = 'PLUGIN_UCTI_BROWSEMENUS_' . $token;
		Slim::Utils::Strings::storeExtraStrings([{
			strings => {EN => $string},
			token => $token,
		}]) if !Slim::Utils::Strings::stringExists($token);
		return $token;
	}
	return $string;
}

sub getVirtualLibraries {
	my $libraries = Slim::Music::VirtualLibraries->getLibraries();
	my %libraries;

	%libraries = map {
		$_ => $libraries->{$_}->{name}
	} keys %{$libraries} if keys %{$libraries};

	return \%libraries;
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

sub starts_with {
	# complete_string, start_string, position
	return rindex($_[0], $_[1], 0);
	# returns 0 for yes, -1 for no
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

1;
