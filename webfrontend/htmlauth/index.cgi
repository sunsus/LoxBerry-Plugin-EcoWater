#!/usr/bin/perl

use LoxBerry::Web;
use CGI;
use warnings;
use strict;

my $pcfgfile = "$lbpconfigdir/ecowater.cfg";
my $pcfg;

our $cgi = CGI->new;
$cgi->import_names('R');

read_config();

ajax() if ($R::action eq "change");
form();
exit;

sub form
{
	# Main
	my $maintemplate = HTML::Template->new(
		filename => "$lbptemplatedir/index.html",
		global_vars => 1,
		loop_context_vars => 1,
		die_on_bad_params => 0,
		associate => $pcfg,
	);

	# Write form to template
	$R::form = 'settings' if (! $R::form);
	$maintemplate->param($R::form, 1);
	
	our %navbar;
	$navbar{1}{Name} = "Einstellungen";
	$navbar{1}{URL} = 'index.cgi?form=settings';
	$navbar{1}{active} = 1 if ($R::form eq "settings");

	$navbar{9}{Name} = "Logfiles";
	$navbar{9}{URL} = 'index.cgi?form=logfiles';
	$navbar{9}{active} = 1 if ($R::form eq "logfiles");


	
	# my %L = LoxBerry::System::readlanguage($maintemplate, "language.ini");

	LoxBerry::Web::lbheader("EcoWater", "https://www.loxwiki.eu/x/...., ");

	# For Settings form
	if ($R::form eq 'settings') {
	
		my $mshtml = LoxBerry::Web::mslist_select_html( FORMID => 'msno', SELECTED => $pcfg->param('Main.msno'), DATA_MINI => 0, LABEL => "Miniserver an den gesendet wird" );
		$maintemplate->param('MSHTML', $mshtml);
	
		$maintemplate->param('checked_use_http', 'checked') if (is_enabled($pcfg->param('Main.use_http')));
		$maintemplate->param('checked_use_udp', 'checked') if (is_enabled($pcfg->param('Main.use_udp')));
	
	}
	
	if ($R::form eq 'logfiles') {
		
		my $loglist_html;
		eval {
			$loglist_html = LoxBerry::Web::loglist_html();
		};
		if ($@) {
			$loglist_html = "Diese Funktion ist erst ab LoxBerry V1.2.5 verfügbar.";
		}
		$maintemplate->param("LOGLIST_HTML", $loglist_html);
	}
	

	print $maintemplate->output;

	LoxBerry::Web::lbfooter();

}

sub read_config
{
	
	if (! -e $pcfgfile) {
		$pcfg = new Config::Simple(syntax=>'ini');
		$pcfg->param("Main.ConfigVersion", "1");
		$pcfg->write($pcfgfile);
		
	}
	$pcfg = new Config::Simple($pcfgfile);
	$pcfg->autosave(1);
	$pcfg->param("Main.msudpport", 10001) if (! $pcfg->param("Main.msudpport"));
	$pcfg->param("Main.msno", 1) if (! $pcfg->param("Main.msno"));

}


##############################################
# Ajax calls
##############################################
sub ajax
{
	$pcfg->param("Main." . $R::key, $R::value);
	print $cgi->header(-type => 'application/json;charset=utf-8', -status => "204 No Content");
	exit;

}
