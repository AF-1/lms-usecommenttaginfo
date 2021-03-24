package Plugins::UseCommentTagInfo::Settings;

use strict;
use warnings;
use utf8;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Data::Dumper;

my $log = logger('plugin.usecommenttaginfo');
my $prefs = preferences('plugin.usecommenttaginfo');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_USECOMMENTTAGINFO');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/UseCommentTagInfo/settings/settings.html');
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
		my %commenttagconfigmatrix;
		my %searchstringDone;
		my %titleformatnameDone;

		for (my $n = 0; $n <= $maxItemNum; $n++) {
			my $commentconfigID = $paramRef->{"pref_idNum_$n"};
			my $searchstring = trim($paramRef->{"pref_searchstring_$n"} // '');
			my $contextmenucategoryname = trim($paramRef->{"pref_contextmenucategoryname_$n"} // '');
			my $contextmenucategorycontent = trim($paramRef->{"pref_contextmenucategorycontent_$n"} // '');
			my $contextmenuposition = $paramRef->{"pref_contextmenuposition_$n"};
			my $titleformatenabled = $paramRef->{"pref_titleformatenabled_$n"};
			my $titleformatname = trim($paramRef->{"pref_titleformatname_$n"} // '');
			my $titleformatdisplaystring = trim($paramRef->{"pref_titleformatdisplaystring_$n"} // '');
			if ((length($searchstring) > 0) && (((length($contextmenucategoryname) > 0) && (length($contextmenucategorycontent) > 0)) || ((defined $titleformatenabled) && (length($titleformatname) > 0)) && (length($titleformatdisplaystring) > 0)) && !$searchstringDone{$searchstring} && !$titleformatnameDone{$titleformatname}) {

				$commenttagconfigmatrix{$commentconfigID} = {
					'searchstring' => $searchstring,
					'contextmenucategoryname' => $contextmenucategoryname,
					'contextmenucategorycontent' => $contextmenucategorycontent,
					'contextmenuposition' => $contextmenuposition,
					'titleformatenabled' => $titleformatenabled,
					'titleformatname' => $titleformatname,
					'titleformatdisplaystring' => $titleformatdisplaystring
				};

				$searchstringDone{$searchstring} = 1;
				if (length($titleformatname) > 0) {
					$titleformatnameDone{$titleformatname} = 1;
				}
			}
		}
		$prefs->set('commenttagconfigmatrix', \%commenttagconfigmatrix);
		$paramRef->{commenttagconfigmatrix} = \%commenttagconfigmatrix;
		$log->debug("SAVED VALUES = ".Dumper(\%commenttagconfigmatrix));

		$result = $class->SUPER::handler($client, $paramRef);
	}
	# push to settings page

	my $commenttagconfigmatrix = $prefs->get('commenttagconfigmatrix');
	my @commenttagconfiglist;
	foreach my $commenttagconfig (sort keys %{$commenttagconfigmatrix}) {
		$log->debug("commentconfig = ".$commenttagconfig);
		my $searchstring = $commenttagconfigmatrix->{$commenttagconfig}->{'searchstring'};
		$log->debug("searchstring = ".$searchstring);
		push (@commenttagconfiglist, {
			'searchstring' => $commenttagconfigmatrix->{$commenttagconfig}->{'searchstring'},
			'contextmenucategoryname' => $commenttagconfigmatrix->{$commenttagconfig}->{'contextmenucategoryname'},
			'contextmenucategorycontent' => $commenttagconfigmatrix->{$commenttagconfig}->{'contextmenucategorycontent'},
			'contextmenuposition' => $commenttagconfigmatrix->{$commenttagconfig}->{'contextmenuposition'},
			'titleformatenabled' => $commenttagconfigmatrix->{$commenttagconfig}->{'titleformatenabled'},
			'titleformatname' => $commenttagconfigmatrix->{$commenttagconfig}->{'titleformatname'},
			'titleformatdisplaystring' => $commenttagconfigmatrix->{$commenttagconfig}->{'titleformatdisplaystring'}
		});
	}

	# add empty field
	if ((scalar @commenttagconfiglist + 1) < $maxItemNum) {
		push(@commenttagconfiglist, {
			'searchstring' => '',
			'contextmenucategoryname' => '',
			'contextmenucategorycontent' => '',
			'contextmenuposition' => '',
			'titleformatenabled' => undef,
			'titleformatname' => '',
			'titleformatdisplaystring' => ''
		});
	}

	$paramRef->{commenttagconfigmatrix} = \@commenttagconfiglist;
	$paramRef->{itemcount} = scalar @commenttagconfiglist;
	$log->debug("page list = ".Dumper($paramRef->{commenttagconfigmatrix}));

	$result = $class->SUPER::handler($client, $paramRef);

	return $result;
}

sub trim {
	my ($str) = @_;
	$str =~ s{^\s+}{};
	$str =~ s{\s+$}{};
	return $str;
}

1;
