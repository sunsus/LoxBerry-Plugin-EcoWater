#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use LoxBerry::System;
use LoxBerry::IO;
use LoxBerry::Log;
use JSON;
use YAML::XS 'LoadFile';

use LWP::UserAgent;
use HTTP::Request;

use List::MoreUtils qw(first_index);

my $VOLUME_GALLONS_TO_LITERS = 3.78541; # l/g

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
if(!$pcfg->param("Main.ewmodelid")) {
    my ($model_id, $system_type) = get_model_id($ewdsn, $token);
    $pcfg->param("Main.ewmodelid", $model_id);
    $pcfg->param("Main.ewsystemtype", $system_type);
}
# Read Device Config from YAML
my $config = device_config($pcfg->param("Main.ewmodelid"));
my ($deviceId, $status) = get_device_id($ewdsn, $token);
frequent_data($ewdsn, $token);
my %values =  get_data($ewdsn, $token, $config);
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


sub read_config {

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
    if($log->loglevel() eq "7") {
        LOGINF "Response status: " . $resp->status_line . " | Full response: " . $resp->content."\n";
    }
    # print "Response status: " . $resp->status_line . " | Full response: " . $resp->content."\n";
    # print $resp->as_string();
    return ($json->decode($resp->content())->{device}{id}, $json->decode($resp->content())->{device}{connection_status});
}

sub get_model_id {
    my ($dsn, $accessToken) = @_;
    # /apiv1/dsns/{dsn}/properties.json
    my $properties = 'names[]=model_id&names[]=system_type';
    my $req = HTTP::Request->new('GET', "https://ads-field.aylanetworks.com/apiv1/dsns/$dsn/properties.json?$properties");
    $req->header('Authorization' => 'Bearer '.$accessToken);
    $req->header( 'Content-Type' => 'application/json');
    my $lwp = LWP::UserAgent->new;
    $lwp->timeout(5);
    LOGINF "GET device model_id / system_type request\n";
    # print $req->as_string();
    my $resp = $lwp->request($req);
    if($log->loglevel() eq "7") {
        LOGINF "Response status: " . $resp->status_line . " | Full response: " . $resp->content."\n";
    }
    # print $resp->as_string();
    my $elements = $json->decode($resp->content());

    my $config = device_config(91007);

    my %values;
    foreach my $item (@$elements) {
        if ($item->{property}{name} eq  "model_id") { $values{'model_id'}  = $item->{property}{value}}
        if ($item->{property}{name} eq  "system_type") { $values{'system_type'}  = $item->{property}{value}; }
    }
    return ($values{'model_id'},  $values{'system_type'});
}

sub get_enum_int {
    my ($config, $enum, $value) = @_;
    return first_index { $_ eq $value } @{$config->{device_properties}->{$enum}->{enum}};
}

sub get_int_enum {
    my ($config, $enum, $index) = @_;
    return $config->{device_properties}->{$enum}->{enum}[$index];
}

sub set_data_point {
    my ($dsn, $key, $value, $accessToken) = @_;
    # Create Request
    my $req = HTTP::Request->new('POST', "https://ads-field.aylanetworks.com/apiv1/dsns/$dsn/properties/$key/datapoints.json");
    my $frequentDataRequest = {'datapoint' => {'value' => $value}};
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

sub frequent_data {
    my ($dsn, $accessToken) = @_;
    set_data_point($dsn, 'get_frequent_data', 1, $accessToken)
}

sub start_regen {
    my ($dsn, $accessToken) = @_;
    set_data_point($dsn, 'regen_status_enum', get_enum_int($config, 'regen_status_enum', 'regenerating'), $accessToken)
}

sub plan_regen {
    my ($dsn, $accessToken) = @_;
    set_data_point($dsn, 'regen_status_enum', get_enum_int($config, 'regen_status_enum', 'scheduled'), $accessToken)
}

sub cancel_regen {
    my ($dsn, $accessToken) = @_;
    set_data_point($dsn, 'regen_status_enum', get_enum_int($config, 'regen_status_enum', 'none'), $accessToken)
}

sub get_data {
    my ($dsn, $accessToken, $config) = @_;
    # /apiv1/dsns/{dsn}/properties.json
    my $properties = 'names[]=salt_level_tenths&names[]=out_of_salt_estimate_days&names[]=gallons_used_today&names[]=avg_daily_use_gals&names[]=current_water_flow_gpm&names[]=treated_water_avail_gals&names[]=model_id&names[]=system_type&names[]=regen_enable_enum&names[]=regen_status_enum&names[]=regen_time_secs&names[]=avg_daily_gal_tenths&names[]=days_in_operation&names[]=dispensed_gal&names[]=filter_life_remaining_days&names[]=tds_removal_percent';
    my $req = HTTP::Request->new('GET', "https://ads-field.aylanetworks.com/apiv1/dsns/$dsn/properties.json?$properties");
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
        if ($item->{property}{name} eq  "salt_level_tenths") { $values{'salt_level'}  = $item->{property}{value} * 100 / $config->{device_properties}->{salt_level_tenths}->{max}; }
        if ($item->{property}{name} eq  "out_of_salt_estimate_days") { $values{'out_of_salt_estimate_days'}  = $item->{property}{value}; }
        if ($item->{property}{name} eq  "gallons_used_today") { $values{'used_today_liters'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS; }
        if ($item->{property}{name} eq  "avg_daily_use_gals") { $values{'avg_daily_use_liters'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS; }
        if ($item->{property}{name} eq  "current_water_flow_gpm") { $values{'current_water_flow_lpm'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS * $config->{device_properties}->{current_water_flow_gpm}->{conversion};}
        if ($item->{property}{name} eq  "treated_water_avail_gals") { $values{'treated_water_avail_liters'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS; }
        if ($item->{property}{name} eq  "regen_enable_enum") { $values{'regen_enable_enum_text'}  = get_int_enum($config, 'regen_enable_enum', $item->{property}{value});}
        if ($item->{property}{name} eq  "regen_enable_enum") { $values{'regen_enable_enum'}  = $item->{property}{value};}
        if ($item->{property}{name} eq  "regen_status_enum") { $values{'regen_status_enum_text'}  = get_int_enum($config, 'regen_status_enum', $item->{property}{value});}
        if ($item->{property}{name} eq  "regen_status_enum") { $values{'regen_status_enum'}  = $item->{property}{value};}
        if ($item->{property}{name} eq  "regen_time_secs") { $values{'regen_time_secs'}  = $item->{property}{value};}
        if ($item->{property}{name} eq  "avg_daily_gal_tenths") { $values{'avg_daily_liters_tenths'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS; }
        if ($item->{property}{name} eq  "days_in_operation") { $values{'days_in_operation'}  = $item->{property}{value}; }
        if ($item->{property}{name} eq  "dispensed_gal") { $values{'dispensed_liters'}  = $item->{property}{value} * $VOLUME_GALLONS_TO_LITERS; }
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

sub device_config {
    my ($deviceType) = @_;
    my $config = LoadFile("$lbpdatadir/softeners/$deviceType.yml");
    return $config;
    # https://www.perl.com/article/29/2013/9/17/How-to-Load-YAML-Config-Files/
    # "$lbpdatadir/softeners/".$deviceType.".yaml";
    # my $emailName = $config->{salt_level_tenths}->{max};
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
