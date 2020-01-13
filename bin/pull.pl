#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use LoxBerry::System;
use LoxBerry::IO;
use LoxBerry::Log;
use JSON;

use LWP::UserAgent;
use HTTP::Request;

my $VOLUME_GALLONS_TO_LITERS = 3.78541; # l/g
my $SALT_LEVEL_TENTHS_MAX = 80;

my $ewdsn = '';
my $ewuser = '';
my $ewpassword = "";
my $msnr = 1;
my $msudpport = 10001;
my $udpprefix = "ecowater";
my $useudp = 1;
my $usehttp = 0;

my $pcfgfile = "$lbpconfigdir/ecowater.cfg";
my $pcfg;
# my $dbg = 1;

my $log = LoxBerry::Log->new (
    name => 'request',
    addtime => 1,
);

my $json = JSON->new;


LOGSTART "Request started";
LOGINF "Reading configuration";
read_config();

LOGOK "Config was read";

if($log->loglevel() eq "7") {
    LOGWARN "Enabling LoxBerry::IO::DEBUG - Open also the Apache log to debug the sending routines of LoxBerry";
    $LoxBerry::IO::DEBUG = 1;
}

$msnr = $pcfg->param('Main.msno') if $pcfg->param('Main.msno');
$msudpport = $pcfg->param('Main.msudpport') if $pcfg->param('Main.msudpport');
$ewdsn = $pcfg->param('Main.ewdsn') if $pcfg->param('Main.ewdsn');
$ewuser = $pcfg->param('Main.ewuser') if $pcfg->param('Main.ewuser');
$ewpassword = $pcfg->param('Main.ewpassword') if $pcfg->param('Main.ewpassword');
$useudp = is_enabled($pcfg->param('Main.use_udp'));
$usehttp = is_enabled($pcfg->param('Main.use_http'));

LOGOK "Params initialized";

$ewdsn = $ARGV[2] if $ARGV[2];
$ewpassword = $ARGV[1] if $ARGV[1];
$ewuser = $ARGV[0] if $ARGV[0];
my $token =  login($ewuser, $ewpassword);
my ($deviceId, $status) = get_device_id($ewdsn, $token);
frequent_data($ewdsn, $token);
my %values =  get_data($ewdsn, $token);
$values{status} = $status eq "Online" ? 1 : 0;
my $json_values=  $json->encode(\%values);
LOGINF $json_values;

if ($useudp) {
    LOGINF "Sending data via UDP";
    LOGINF "DATA:  ".$json_values;
    LoxBerry::IO::msudp_send_mem($msnr, $msudpport, $udpprefix, %values);
}

if ($usehttp) {
    LOGINF "Sending data via HTTP";
    LoxBerry::IO::mshttp_send_mem($msnr, $json_values);
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

sub login {
    my ($user, $password) = @_;
    # Create Request
    my $req = HTTP::Request->new('POST', 'https://user-field.aylanetworks.com/users/sign_in.json');
    my $loginRequest = {'user' => {'email' => $user, 'password' =>  $password, 'application' => {'app_id' => 'ecowater-mobile-id', 'app_secret' => 'ecowater-mobile-9026832'}}};
    $req->header( 'Content-Type' => 'application/json');
    $req->content($json->encode($loginRequest));
    my $lwp = LWP::UserAgent->new;
    $lwp->timeout(5);
    LOGINF "POST Login request\n";
    # print $req->as_string();
    my $resp = $lwp->request($req);
    LOGINF "Response status: " . $resp->status_line . " | Full response: " . $resp->content."\n";
    # print $resp->as_string();
    return $json->decode($resp->content())->{access_token};
}

sub get_device_id {
    my ($dsn, $accessToken) = @_;
    my $req = HTTP::Request->new('GET', 'https://ads-field.aylanetworks.com/apiv1/dsns/'.$dsn.'.json');
    $req->header('Authorization' => 'Bearer '.$accessToken);
    $req->header( 'Content-Type' => 'application/json');
    my $lwp = LWP::UserAgent->new;
    $lwp->timeout(5);
    LOGINF "GET device id request\n";
    # print $req->as_string();
    my $resp = $lwp->request($req);
    # print "Response status: " . $resp->status_line . " | Full response: " . $resp->content."\n";
    # print $resp->as_string();
    return ($json->decode($resp->content())->{device}{id}, $json->decode($resp->content())->{device}{connection_status});
}
sub frequent_data {
    my ($dsn, $accessToken) = @_;
    # Create Request
    my $req = HTTP::Request->new('POST', 'https://ads-field.aylanetworks.com/apiv1/dsns/'.$dsn.'/properties/get_frequent_data/datapoints.json');
    my $frequentDataRequest = {'datapoint' => {'value' => 1}};
    $req->header('Authorization' => 'Bearer '.$accessToken);
    $req->header( 'Content-Type' => 'application/json');
    $req->content($json->encode($frequentDataRequest));
    my $lwp = LWP::UserAgent->new;
    $lwp->timeout(5);
    LOGINF "POST Frequent Data request\n";
    # print $req->as_string();
    my $resp = $lwp->request($req);
    LOGINF "Response status: " . $resp->status_line . " | Full response: " . $resp->content."\n";
    # print $resp->as_string();
}

sub get_data {
    my ($dsn, $accessToken) = @_;
    # /apiv1/dsns/{dsn}/properties.json
    my $req = HTTP::Request->new('GET', 'https://ads-field.aylanetworks.com/apiv1/dsns/'.$dsn.'/properties.json');
    $req->header('Authorization' => 'Bearer '.$accessToken);
    $req->header( 'Content-Type' => 'application/json');
    my $lwp = LWP::UserAgent->new;
    $lwp->timeout(5);
    LOGINF "GET device data request\n";
    # print $req->as_string();
    my $resp = $lwp->request($req);
    # print "Response status: " . $resp->status_line . " | Full response: " . $resp->content."\n";
    # print $resp->as_string();
    my $elements = $json->decode($resp->content());

    my %values;
    foreach my $item (@$elements) {
        # TODO: get value from Config YAML PROP_SALT_LEVEL_TENTHS_MAX
        if ($item->{property}{name} eq  "salt_level_tenths") { $values{'salt_level'}  = $item->{property}{value} * 100 / $SALT_LEVEL_TENTHS_MAX; }
        if ($item->{property}{name} eq  "out_of_salt_estimate_days") { $values{'out_of_salt_estimate_days'}  = $item->{property}{value}; }
        if ($item->{property}{name} eq  "gallons_used_today") { $values{'used_today_liters'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS; }
        if ($item->{property}{name} eq  "avg_daily_use_gals") { $values{'avg_daily_use_liters'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS; }
        # TODO: get value from Config YAML
        if ($item->{property}{name} eq  "current_water_flow_gpm") { $values{'current_water_flow_lpm'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS * 0.1; }
        if ($item->{property}{name} eq  "treated_water_avail_gals") { $values{'treated_water_avail_liters'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS; }
    }
    return %values;
}

sub is_online {
    my ($deviceId, $accessToken) = @_;
    my $req = HTTP::Request->new('GET', 'https://ads-field.aylanetworks.com/apiv1/devices/'.$deviceId.'.json');
    $req->header('Authorization' => 'Bearer '.$accessToken);
    $req->header( 'Content-Type' => 'application/json');
    my $lwp = LWP::UserAgent->new;
    $lwp->timeout(5);
    print "GET is online request\n";
    # print $req->as_string();
    my $resp = $lwp->request($req);
    print "Response status: " . $resp->status_line . " | Full response: " . $resp->content."\n";
    # print $resp->as_string();
    return $json->decode($resp->content())->{device}{connection_status};
}

END
    {
        my $err = $?;
        # if ($xmlresp{'success'} eq "") {
        #     xmlresponse("Finished without errors", 200) if ($err == 0);
        #    xmlresponse("Unknown ERROR", 500) if ($err != 0);
        # }
        LOGEND "Finished without errors" if ($err == 0);
        LOGEND "Finished WITH ERRORS" if ($err != 0);
    }