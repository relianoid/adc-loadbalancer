#!/usr/bin/perl
###############################################################################
#
#    RELIANOID Software License
#    This file is part of the RELIANOID Load Balancer software package.
#
#    Copyright (C) 2014-today RELIANOID
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

use strict;
use warnings;
use feature qw(signatures);

use Carp;
use Regexp::IPv6 qw($IPv6_re);
use Relianoid::Net::Validate;

my $eload = eval { require Relianoid::ELoad };

=pod

=head1 Module

Relianoid::Validate

=cut

# Notes about regular expressions:
#
# \w matches the 63 characters [a-zA-Z0-9_] (most of the time)
#

my $UNSIGNED8BITS = qr/(?:25[0-5]|2[0-4]\d|(?!0)[1]?\d\d?|0)/;                         # (0-255)
my $UNSIGNED7BITS = qr/(?:[0-9]{1,2}|10[0-9]|11[0-9]|12[0-8])/;                        # (0-128)
my $HEXCHAR       = qr/(?:[A-Fa-f0-9])/;
my $ipv6_word     = qr/(?:$HEXCHAR+){1,4}/;
my $ipv4_addr     = qr/(?:$UNSIGNED8BITS\.){3}$UNSIGNED8BITS/;
my $ipv6_addr     = $IPv6_re;
my $mac_addr      = qr/(?:$HEXCHAR$HEXCHAR\:){5}$HEXCHAR$HEXCHAR/;
my $ipv4v6        = qr/(?:$ipv4_addr|$ipv6_addr)/;
my $boolean       = qr/(?:true|false)/;
my $enable        = qr/(?:enable|disable)/;
my $integer       = qr/\d+/;
my $natural       = qr/[1-9]\d*/;                                                      # natural number = {1, 2, 3, ...}
my $weekdays      = qr/(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)/;
my $minutes       = qr/(?:\d|[0-5]\d)/;
my $hours         = qr/(?:\d|[0-1]\d|2[0-3])/;
my $months        = qr/(?:[1-9]|1[0-2])/;
my $dayofmonth    = qr/(?:[1-9]|[1-2]\d|3[01])/;                                       # day of month
my $rrdTime       = qr/\d\d-\d\d-(?:\d\d)?\d\d-\d\d:\d\d/;    # MM-DD-[YY]YY-hh:mm ; example: "11-09-2020-14:05";

my $hostname = qr/[a-z][a-z0-9\-]{0,253}[a-z0-9]/;
my $service  = qr/[a-zA-Z0-9][a-zA-Z0-9_\-\.]*/;
my $zone     = qr/(?:$hostname\.)+[a-z]{2,}/;

my $cert_name = qr/(?:\*[_|\.])?\w[\w\.\(\)\@ \-]*/;

my $vlan_tag        = qr/\d{1,4}/;
my $virtual_tag     = qr/[a-zA-Z0-9\-]{1,13}/;
my $nic_if          = qr/[a-zA-Z0-9\-]{1,15}/;
my $bond_if         = qr/[a-zA-Z0-9\-]{1,15}/;
my $vlan_if         = qr/[a-zA-Z0-9\-]{1,13}\.$vlan_tag/;
my $interface       = qr/$nic_if(?:\.$vlan_tag)?(?:\:$virtual_tag)?/;
my $port_range      = qr/(?:[1-9]\d{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])/;
my $graphsFrequency = qr/(?:daily|weekly|monthly|yearly)/;

my $blacklists_source = qr{(?:\d{1,3}\.){3}\d{1,3}(?:\/\d{1,2})?};
my $dos_global        = qr/(?:sshbruteforce)/;
my $dos_all           = qr/(?:limitconns|limitsec)/;
my $dos_tcp           = qr/(?:bogustcpflags|limitrst)/;

my $run_actions = qr/^(?:stop|start|restart)$/;

my $name  = qr/^(?:[a-zA-Z0-9][\w]{5,31})$/;
my $email = qr/(?:[a-zA-Z][\w\_\.]+)\@(?:[a-zA-Z0-9.-]+)\.(?:[a-zA-Z]{2,4})/;

my %format_re = (

    # generic types
    integer     => $integer,
    natural_num => $natural,
    boolean     => $boolean,
    ipv4v6      => $ipv4v6,
    rrd_time    => $rrdTime,

    # hostname
    hostname => $hostname,

    # license
    license_format => qr/(?:txt|html)/,

    # log
    log => qr/[\.\-\w]+/,

    # api
    zapi_key      => qr/[a-zA-Z0-9]+/,
    zapi_status   => $enable,
    zapi_password => qr/.+/,

    # common
    port      => $port_range,
    multiport => qr/(?:\*|(?:$port_range|$port_range\:$port_range)(?:,$port_range|,$port_range\:$port_range)*)/,

    user     => qr/[\w]+/,
    password => qr/.+/,

    # system
    dns_nameserver => $ipv4v6,
    dns            => qr/(?:primary|secondary)/,
    ssh_port       => $port_range,
    ssh_listen     => qr/(?:$ipv4v6|\*)/,
    snmp_status    => $boolean,
    snmp_ip        => qr/(?:$ipv4v6|\*)/,
    snmp_community => qr{.+},
    snmp_port      => $port_range,
    snmp_scope     => qr{(?:\d{1,3}\.){3}\d{1,3}\/\d{1,2}},    # ip/mask
    ntp            => qr{[\w\.\-]+},
    http_proxy     => qr{\S*},                                 # use any character except the spaces

    # farms
    farm_name             => qr/[a-zA-Z0-9\-]+/,
    farm_profile          => qr/HTTP|GSLB|L4XNAT|DATALINK/,
    backend               => qr/\d+/,
    service               => $service,
    http_service          => qr/[a-zA-Z0-9\-]+/,
    gslb_service          => qr/[a-zA-Z0-9][\w\-]*/,
    farm_modules          => qr/(?:gslb|dslb|lslb)/,
    service_position      => qr/\d+/,
    l4_session            => qr/[ \._\:\w]+/,
    l7_session            => qr/[ \._\:\w]+/,
    farm_maintenance_mode => qr/(?:drain|cut)/,               # not used from API 4

    # cipher
    ciphers => qr/(?:all|highsecurity|customsecurity|ssloffloading)/,    # not used from API 4

    # backup
    backup        => qr/[\w-]+/,
    backup_action => qr/apply/,

    # graphs
    graphs_frequency => $graphsFrequency,
    graphs_system_id => qr/(?:cpu|load|ram|swap)/,
    mount_point      => qr/root[\w\-\.\/]*/,

    # http
    redirect_code    => qr/(?:301|302|307)/,                             # not used from API 4
    http_sts_status  => qr/(?:true|false)/,                              # not used from API 4
    http_sts_timeout => qr/(?:\d+)/,

    # GSLB
    zone                => qr/(?:$hostname\.)+[a-z]{2,}/,
    resource_id         => qr/\d+/,
    resource_name       => qr/(?:[\w\-\.]+|\@)/,
    resource_ttl        => qr/$natural/,                                            # except zero
    resource_type       => qr/(?:NS|A|AAAA|CNAME|DYNA|MX|SRV|TXT|PTR|NAPTR)/,       # not used from API 4
    resource_data       => qr/.+/,                                                  # allow anything (TXT type needs it)
    resource_data_A     => $ipv4_addr,
    resource_data_AAAA  => $ipv6_addr,
    resource_data_DYNA  => $service,
    resource_data_NS    => qr/[a-zA-Z0-9\-]+/,
    resource_data_CNAME => qr/[a-z\.]+/,
    resource_data_MX    => qr/[a-z\.\ 0-9]+/,
    resource_data_TXT   => qr/.+/,                                                  # all characters allow
    resource_data_SRV   => qr/[0-9]+ [0-9]+ [0-9]+ .+/,                             # https://www.ietf.org/rfc/rfc2782
    resource_data_PTR   => qr/[a-z\.]+/,
    resource_data_NAPTR => qr/[0-9]+ [0-9]+\|[a-zA-Z]?\|[a-zA-Z0-9\+]*\|.*\|.+/,    # https://www.ietf.org/rfc/rfc2915

    # interfaces ( WARNING: length in characters < 16  )
    mac_addr         => $mac_addr,
    interface        => $interface,
    nic_interface    => $nic_if,
    bond_interface   => $bond_if,
    vlan_interface   => $vlan_if,
    virt_interface   => qr/(?:$bond_if|$nic_if)(?:\.$vlan_tag)?:$virtual_tag/,
    routed_interface => qr/(?:$nic_if|$bond_if|$vlan_if)/,
    interface_type   => qr/(?:nic|vlan|virtual|bond)/,
    vlan_tag         => qr/$vlan_tag/,
    virtual_tag      => qr/$virtual_tag/,
    bond_mode_num    => qr/[0-6]/,
    bond_mode_short  =>
      qr/(?:balance-rr|active-backup|balance-xor|broadcast|802.3ad|balance-tlb|balance-alb)/,    # not used from API 4

    # notifications
    notif_alert  => qr/(?:backends|cluster|license|interface|package|certificate)/,
    notif_method => qr/(?:email)/,
    notif_tls    => $boolean,
    notif_action => $enable,
    notif_time   => $natural,                                                                    # this value can't be 0

    # IPDS
    # blacklists
    day_of_month         => qr{$dayofmonth},
    weekdays             => qr{$weekdays},
    blacklists_name      => qr{\w+},
    blacklists_source    => qr{$blacklists_source},
    blacklists_source_id => qr{(?:\d+|$blacklists_source(?:,$blacklists_source)*)},

    blacklists_url            => qr{.+},
    blacklists_hour           => $hours,
    blacklists_minutes        => $minutes,
    blacklists_period         => $natural,
    blacklists_day            => qr{(:?$dayofmonth|$weekdays)},
    blacklists_policy         => qr{(:?allow|deny)},              # not used from API 4
    blacklists_type           => qr{(:?local|remote)},            # not used from API 4
    blacklists_unit           => qr{(:?hours|minutes)},           # not used from API 4
    blacklists_frequency      => qr{(:?daily|weekly|monthly)},    # not used from API 4
    blacklists_frequency_type => qr{(:?period|exact)},            # not used from API 4

    # DoS
    dos_name        => qr/[\w]+/,
    dos_rule        => qr/(?:$dos_global|$dos_all|$dos_tcp)/,
    dos_rule_farm   => qr/(?:$dos_all|$dos_tcp)/,
    dos_rule_global => $dos_global,
    dos_rule_all    => $dos_all,
    dos_rule_tcp    => $dos_tcp,
    dos_time        => $natural,
    dos_limit_conns => $natural,
    dos_limit       => $natural,
    dos_limit_burst => $natural,
    dos_port        => $port_range,
    dos_hits        => $natural,

    # RBL
    rbl_name          => qr/[\w]+/,
    rbl_domain        => qr/[\w\.\-]+/,
    rbl_log_level     => qr/[0-7]/,
    rbl_only_logging  => $boolean,
    rbl_cache_size    => $natural,
    rbl_cache_time    => $natural,
    rbl_queue_size    => $natural,
    rbl_thread_max    => $natural,
    rbl_local_traffic => $boolean,
    rbl_actions       => $run_actions,    # not used from API 4

    # WAF
    http_code      => qr/[0-9]{3}/,
    waf_set_name   => qr/[\.\w-]+/,
    waf_rule_id    => qr/\d+/,
    waf_chain_id   => qr/\d+/,
    waf_severity   => qr/[0-9]/,
    waf_phase      => qr/(?:[1-5]|request|response|logging)/,
    waf_log        => qr/(?:$boolean|)/,
    waf_audit_log  => qr/(?:$boolean|)/,
    waf_skip       => qr/[0-9]+/,
    waf_skip_after => qr/\w+/,
    waf_set_status => qr/(?:$boolean|detection)/,
    waf_file       => qr/(?:[\s+\w-]+)/,

    # certificates filenames
    certificate_name    => $cert_name,
    certificate         => qr/$cert_name\.(?:pem|csr)/,
    cert_pem            => qr/$cert_name\.pem/,
    cert_name           => qr/[a-zA-Z0-9\-]+/,
    cert_csr            => qr/\w[\w\.\-]*\.csr/,
    cert_dh2048         => qr/\w[\w\.\-]*_dh2048\.pem/,
    le_certificate_name => $cert_name,
    le_mail             => $email,

    # IPS
    IPv4_addr => qr/$ipv4_addr/,
    IPv4_mask => qr/(?:$ipv4_addr|3[0-2]|[1-2][0-9]|[0-9])/,

    IPv6_addr => qr/$ipv6_addr/,
    IPv6_mask => $UNSIGNED7BITS,

    ip_addr       => $ipv4v6,
    ip_mask       => qr/(?:$ipv4_addr|$UNSIGNED7BITS)/,
    ip_addr_range => qr/$ipv4_addr-$ipv4_addr/,

    # farm guardian
    fg_name    => qr/[\w-]+/,
    fg_type    => qr/(?:http|https|l4xnat|gslb)/,    # not used from API 4
    fg_enabled => $boolean,
    fg_log     => $boolean,
    fg_time    => qr/$natural/,                      # this value can't be 0

    # RBAC
    user_name     => qr/[a-z0-9][-a-z0-9_.]+/,
    rbac_password => qr/(?=.*[0-9])(?=.*[a-zA-Z]).{8,512}/,
    group_name    => qr/[\w-]+/,
    role_name     => qr/[\w-]+/,

    # alias
    alias_id        => qr/(?:$ipv4v6|$interface)/,
    alias_backend   => qr/$ipv4v6/,
    alias_interface => qr/$interface/,
    alias_name      => qr/(?:$zone|[\w-]+)/,
    alias_type      => qr/(?:backend|interface)/,

    # routing
    route_rule_id  => qr/$natural/,
    route_table_id => qr/[\w\.\-]+/,
    route_entry_id => qr/$natural/,

    # vpn
    vpn_name => qr/[a-zA-Z][a-zA-Z0-9\-]*/,
    vpn_user => qr/[a-zA-Z][a-zA-Z0-9\-]*/,

);

sub _get_api_version () {
    return $ENV{API_VERSION} // "";
}

sub getAPIModel ($file_name) {
    require JSON;
    require Relianoid::API;
    require Relianoid::File;

    my $api_version = &_get_api_version();
    my $dir_name    = &getGlobalConfiguration("api_model_path") . "/v${api_version}/json";
    my $content     = getFile("${dir_name}/${file_name}");

    if ($content) {
        return JSON::decode_json($content)->{params};
    }
    else {
        return $content;
    }
}

=pod

=head1 getValidFormat

Validates a data format matching a value with a regular expression.
If no value is passed as an argument the regular expression is returned.

Usage:

    # validate exact data
    if ( ! &getValidFormat( "farm_name", $input_farmname ) ) {
        print "error";
    }

    # use the regular expression as a component for another regular expression
    my $file_regex = &getValidFormat( "certificate" );
    if ( $file_path =~ /$configdir\/$file_regex/ ) { ... }

Parameters:

    format_name	- type of format
    value		- value to be validated (optional)
    new_format_re	- structure with the formats to use. (optional)

Returns:

    false	- If value failed to be validated
    true	- If value was successfuly validated
    regex	- If no value was passed to be matched

See also:

    Mainly but not exclusively used in API v3.

=cut

sub getValidFormat ($format_name, $value = undef, %new_format_re) {
    # Checks if it should use the formats passed by parameters.
    %format_re = %new_format_re if (%new_format_re);

    #~ print "getValidFormat type:$format_name value:$value\n"; # DEBUG
    if (exists $format_re{$format_name}) {
        if (defined $value) {
            #~ print "$format_re{$format_name}\n"; # DEBUG
            if (ref($value) eq "ARRAY") {
                return !grep { !/^$format_re{$format_name}$/ } @{$value} > 0;
            }
            else {
                return $value =~ /^$format_re{$format_name}$/;
            }
        }
        else {
            #~ print "$format_re{$format_name}\n"; # DEBUG
            return $format_re{$format_name};
        }
    }
    else {
        my $message = "getValidFormat: format $format_name not found.";
        &log_info($message);
        die($message);
    }
}

=pod

=head1 getValidPort

Validate if the port is valid for a type of farm.

Parameters:

    port - Port number.
    profile - Farm profile (HTTP, L4XNAT, GSLB or DATALINK). Optional.

Returns:

    Boolean - TRUE for a valid port number, FALSE otherwise.

=cut

sub getValidPort ($port, $profile = undef) {
    if ($profile =~ /^(?:HTTP|GSLB|eproxy)$/i) {
        return &getValidFormat('port', $port);
    }
    elsif ($profile =~ /^(?:L4XNAT)$/i) {
        return &getValidFormat('multiport', $port);
    }
    elsif ($profile =~ /^(?:DATALINK)$/i) {
        return !defined $port;
    }
    elsif (!defined $profile) {
        return &getValidFormat('port', $port);
    }
    else    # profile not supported
    {
        return 0;
    }
}

=pod

=head1 checkApiParams

Function to check parameters of a PUT or POST call.
It check a list of parameters, and apply it some checks:

    - Almost 1 parameter
    - All required parameters must exist
    - All required parameters are correct

Also, it checks: getValidFormat funcion, if black is allowed, intervals, aditionals regex, excepts regex and a list with the possbile values

It is possible add a error message with the correct format. 

For example: $parameter . "must have letters and digits"

Parameters:

    Json_obj - Parameters sent in a POST or PUT call
    Parameters - Hash of parameter objects

    parameter object:

    {
        parameter :

        {		# parameter is the key or parameter name
            "required" 	: "true",		# or not defined
            "non_blank" : "true",		# or not defined
            "interval" 	: "1,65535",	# it is possible define strings matchs ( non implement). For example: "ports" = "1-65535", "log_level":"1-3", ...
                                        # ",10" indicates that the value has to be less than 10 but without low limit
                                        # "10," indicates that the value has to be more than 10 but without high limit
                                        # The values of the interval has to be integer numbers
            "exceptions"	: [ "api", "webgui", "root" ],	# The parameter can't have got any of the listed values
            "values" : ["priority", "weight"],		# list of possible values for a parameter
            "length" : 32,				# it is the maximum string size for the value
            "regex"	: "/\w+,\d+/",		# regex format
            "ref"	: "array|hash",		# the expected input must be an array or hash ref. To allow ref inputs and non ref for a parameter use the word 'none'. Example:  'ref' => 'array|none'
            "valid_format"	: "farmname",		# regex stored in Validate.pm file, it checks with the function getValidFormat
            "function" : \&func,		# function of validating, the input parameter is the value of the argument. The function has to return 0 or 'false' when a error exists
            "format_msg"	: "must have letters and digits",	# used message when a value is not correct
        }
        param2 :

        {
            ...
        }
        ....
    }

Returns:

    String - Return a error message with the first error found or undef on success

=cut

sub checkApiParams ($json_obj, $param_obj, $description) {
    my $err_msg;

    ## Remove parameters do not according to the edition
    for my $p (keys %$param_obj) {
        if (
            exists $param_obj->{$p}{edition}
            && (   ($param_obj->{$p}{edition} eq 'ee' && !$eload)
                || ($param_obj->{$p}{edition} eq 'ce' && $eload))
          )
        {
            delete $param_obj->{$p};
        }
    }

    my @rec_keys = keys %{$json_obj};

    # Returns a help with the expected input parameters
    if (!@rec_keys) {
        &httpResponseHelp($param_obj, $description);
    }

    # All required parameters must exist
    my @expect_params = keys %{$param_obj};

    $err_msg = &checkParamsRequired(\@rec_keys, \@expect_params, $param_obj);
    return $err_msg if ($err_msg);

    # All sent parameters are correct
    $err_msg = &checkParamsInvalid(\@rec_keys, \@expect_params);
    return $err_msg if ($err_msg);

    # check for each parameter
    for my $param (@rec_keys) {
        my $custom_msg = "The parameter '$param' has not a valid value.";

        # Store the input value to keep the data type,
        # and to be restored at the end of the loop.
        # This is because numeric type are converted to string
        # when used in a string context, like in a regex.
        my $current_param_value = $json_obj->{$param};

        if (exists $param_obj->{$param}{format_msg}) {
            $custom_msg = "$param $param_obj->{$param}{format_msg}";
        }

        if (
               not defined $json_obj->{$param}
            or not length $json_obj->{$param}
            or (    ref $json_obj->{$param}
                and ref $json_obj->{$param} eq 'ARRAY'
                and @{ $json_obj->{$param} } == 0)
          )
        {
            # if blank value is allowed
            if (    $param_obj->{$param}{non_blank}
                and $param_obj->{$param}{non_blank} eq 'true')
            {
                return "The parameter '$param' can't be in blank.";
            }

            next;
        }

        # the input has to be a ref
        my $r = ref $json_obj->{$param} // '';
        if (exists $param_obj->{$param}{ref}) {
            if ($r eq '') {
                if ('none' !~ /$param_obj->{$param}{ref}/) {
                    return "The parameter '$param' expects a '$param_obj->{$param}{ref}' reference as input";
                }
            }
            elsif ($r !~ /^$param_obj->{$param}{ref}$/i) {
                return "The parameter '$param' expects a '$param_obj->{$param}{ref}' reference as input";
            }
        }
        elsif ($r eq 'ARRAY' or $r eq 'HASH') {
            return "The parameter '$param' does not expect a $r as input";
        }

        if ((exists $param_obj->{$param}{values})) {
            if ($r eq 'ARRAY') {
                for my $value (@{ $json_obj->{$param} }) {
                    if (!grep { $value eq $_ } @{ $param_obj->{$param}{values} }) {
                        return
                          "The parameter '$param' expects some of the following values: '"
                          . join("', '", @{ $param_obj->{$param}{values} }) . "'";
                    }
                }
            }
            else {
                if (!grep { $json_obj->{$param} eq $_ } @{ $param_obj->{$param}{values} }) {
                    return
                      "The parameter '$param' expects one of the following values: '"
                      . join("', '", @{ $param_obj->{$param}{values} }) . "'";
                }
            }
        }

        # getValidFormat funcion:
        if (    (exists $param_obj->{$param}{valid_format})
            and (!&getValidFormat($param_obj->{$param}{valid_format}, $json_obj->{$param})))
        {
            return $custom_msg;
        }

        # length
        if (exists $param_obj->{$param}{length}) {
            my $data_length = length($json_obj->{$param});
            if ($data_length > $param_obj->{$param}{length}) {
                return "The maximum length for '$param' is '$param_obj->{$param}{length}'";
            }
        }

        # intervals
        if (exists $param_obj->{$param}{interval}) {
            $err_msg =
              &checkParamsInterval($param_obj->{$param}{interval}, $param, $json_obj->{$param});
            return $err_msg if $err_msg;
        }

        # exceptions
        if (    (exists $param_obj->{$param}{exceptions})
            and (grep { /^$json_obj->{$param}$/ } @{ $param_obj->{$param}{exceptions} }))
        {
            return "The value '$json_obj->{$param}' is a reserved word of the parameter '$param'.";
        }

        # regex
        if ((exists $param_obj->{$param}{regex})) {
            if (defined $json_obj->{$param}) {
                # If ARRAY, evaluate all in values.
                if (ref($json_obj->{$param}) eq "ARRAY") {
                    for my $value (@{ $json_obj->{$param} }) {
                        return "The value '$value' is not valid for the parameter '$param'."
                          if (grep { !/^$param_obj->{$param}{regex}$/ } $value);
                    }
                }
                else {
                    return "The value '$json_obj->{$param}' is not valid for the parameter '$param'."
                      if ($json_obj->{$param} !~ /^$param_obj->{$param}{regex}$/);
                }
            }
        }

        # negated_regex
        if ((exists $param_obj->{$param}{negated_regex})) {
            if (defined $json_obj->{$param}) {
                # If ARRAY, evaluate all in values.
                if (ref($json_obj->{$param}) eq "ARRAY") {
                    for my $value (@{ $json_obj->{$param} }) {
                        return "The value '$value' is not valid for the parameter '$param'."
                          if (grep { /^$param_obj->{$param}{regex}$/ } $value);
                    }
                }
                else {
                    return "The value '$json_obj->{$param}' is not valid for the parameter '$param'."
                      if ($json_obj->{$param} =~ /$param_obj->{$param}{negated_regex}/);
                }
            }
        }

        # is_regex
        if (defined $param_obj->{$param}{is_regex}
            and $param_obj->{$param}{is_regex} eq 'true')
        {
            if (defined $json_obj->{$param}) {
                my $regex = eval { qr/$json_obj->{$param}/ };
                return "The value of field $param is an invalid regex" if $@;
            }
        }

        if (exists $param_obj->{$param}{function}) {
            my $result =
              &{ $param_obj->{$param}{function} }($json_obj->{$param});

            return $custom_msg if (!$result || $result eq 'false');
        }

        # Restore the data type that was received as input
        # from the beginning of the loop
        $json_obj->{$param} = $current_param_value;
    }

    return;
}

=pod

=head1 checkParamsInterval

Check parameters when there are required params. The value has to be a integer number

Parameters:

    Interval - String with the expected interval. The low and high limits must be splitted with a comma character ','
    Parameter - Parameter name
    Value - Parameter value

Returns:

    String - It returns a string with the error message or undef on success

=cut

sub checkParamsInterval ($interval, $param, $value) {
    my $err_msg;

    if ($interval =~ /,/) {
        my ($low_limit, $high_limit) = split(',', $interval);

        my $msg = "";
        if (defined $low_limit and defined $high_limit and length $high_limit) {
            $msg = "'$param' has to be an integer number between '$low_limit' and '$high_limit'";
        }
        elsif (defined $low_limit) {
            $msg = "'$param' has to be an integer number greater than or equal to '$low_limit'";
        }
        elsif (defined $high_limit) {
            $msg = "'$param' has to be an integer number lower than or equal to '$high_limit'";
        }

        $err_msg = $msg
          if ( ($value !~ /^\d*$/)
            || ($high_limit and $value > $high_limit)
            || ($low_limit  and $value < $low_limit));
    }
    else {
        die "Expected a interval string, got: $interval";
    }

    return $err_msg;
}

=pod

=head1 checkParamsInvalid

Check if some of the sent parameters is invalid for the current API call

Parameters:

    Receive Parameters - It is the list of sent parameters in the API call
    Expected parameters - It is the list of expected parameters for a API call

Returns:

    String - It returns a string with the error message or undef on success

=cut

sub checkParamsInvalid ($rec_keys, $expect_params) {
    my $err_msg;
    my @non_valid;

    for my $param (@{$rec_keys}) {
        push @non_valid, "'$param'" if (!grep { /^$param$/ } @{$expect_params});
    }

    if (@non_valid) {
        $err_msg = &putArrayAsText(\@non_valid,
                "The parameter<sp>s</sp> <pl> <bs>is<|>are</bp> not correct for this call. Please, try with: '"
              . join("', '", @{$expect_params})
              . "'");
    }

    return $err_msg;
}

=pod

=head1 checkParamsRequired

Check if all the mandatory parameters has been sent in the current API call

Parameters:

    Receive Parameters - It is the list of sent parameters in the API call
    Expected parameters - It is the list of expected parameters for a API call
    Model - It is the struct with all allowed parameters and its possible values and options

Returns:

    String - It returns a string with the error message or undef on success

=cut

sub checkParamsRequired ($rec_keys, $expect_params, $param_obj) {
    my @miss_params;
    my $err_msg;

    for my $param (@{$expect_params}) {
        next if (!exists $param_obj->{$param}{required});

        if ($param_obj->{$param}{required} eq 'true') {
            push @miss_params, "'$param'"
              if (!grep { /^$param$/ } @{$rec_keys});
        }
    }

    if (@miss_params) {
        $err_msg = &putArrayAsText(\@miss_params, "The required parameter<sp>s</sp> <pl> <bs>is<|>are</bp> missing.");
    }
    return $err_msg;
}

=pod

=head1 httpResponseHelp

This function sends a response to client with the expected input parameters model.

This function returns a 400 HTTP error code

Parameters:

    Model - It is the struct with all allowed parameters and its possible values and options
    Description - Descriptive message about the API call

Returns:

    None

=cut

sub httpResponseHelp ($param_obj, $desc) {
    my $resp_param = [];

    # build the output
    for my $p (keys %{$param_obj}) {
        my $param->{name} = $p;
        if (exists $param_obj->{$p}{valid_format}) {
            $param->{format} = $param_obj->{$p}{valid_format};
        }
        if (exists $param_obj->{$p}{values}) {
            $param->{possible_values} = $param_obj->{$p}{values};
        }
        if (exists $param_obj->{$p}{interval}) {
            my ($ll, $hl) = split(',', $param_obj->{$p}{interval});
            $ll                = '-' if (!defined $ll);
            $hl                = '-' if (!defined $hl);
            $param->{interval} = "Expects a value between '$ll' and '$hl'.";
        }
        if (exists $param_obj->{$p}{non_blank}
            and $param_obj->{$p}{non_blank} eq 'true')
        {
            push @{ $param->{options} }, "non_blank";
        }
        if (exists $param_obj->{$p}{required}
            and $param_obj->{$p}{required} eq 'true')
        {
            push @{ $param->{options} }, "required";
        }
        if (exists $param_obj->{$p}{format_msg}) {
            $param->{description} = $param_obj->{$p}{format_msg};
        }
        if (exists $param_obj->{$p}{ref}) {
            $param->{ref} = $param_obj->{$p}{ref};
        }

        push @{$resp_param}, $param;
    }

    my $msg  = "No parameter has been sent. Please, try with:";
    my $body = {
        message => $msg,
        params  => $resp_param,
    };
    $body->{description} = $desc if (defined $desc);

    return &httpResponse({ code => 400, body => $body });
}

=pod

=head1 putArrayAsText

This funcion receives a text string and a list of values and it generates a
text with the values.

It uses a delimited to modify the text string passed as argument:

    put list - <pl>
    select plural - <sp>text</sp>
    select single - <ss>text</ss>
    select between single or plural - <bs>text_single<|>text_plural</bp>

Examples:

    putArrayAsText ( ["password", "user", "key"], "The possible value<sp>s</sp> <sp>are</sp>: <pl>")
        return: ""
    putArrayAsText ( ["", "", ""], "The values are")
        return: ""

Parameters:

    Parameters - List of parameters to add to the string message
    Text string - Text

Returns:

    String - Return a message adjust to the number of parameters passed

=cut

sub putArrayAsText ($array_ref, $msg) {
    my @array = @{$array_ref};

    # one element
    if (scalar @array == 1) {
        # save single tags
        $msg =~ s/<\/?ss>//g;

        # remove plural text
        #~ $msg =~ s/<sp>.+<\/?sp>// while ( $msg =~ /<sp>/ );
        $msg =~ s/<sp>.+<\/?sp>//g;

        # select between plural and single text
        #~ $msg =~ s/<bs>(.+)<|>.+<\/bp>/$1/ while ( $msg =~ /<|>/ );
        $msg =~ s/<bs>(.+)<\|>.+<\/bp>/$1/g;

        # put list
        $msg =~ s/<pl>/$array[0]/;
    }

    # more than one element
    else {
        # save plual tags
        $msg =~ s/<\/?sp>//g;

        # remove single text
        #~ $msg =~ s/<ss>.+<\/?ss>// while ( $msg =~ /<ss>/ );
        $msg =~ s/<ss>.+<\/?ss>//g;

        # select between plural and single text
        #~ $msg =~ s/<bs>.+<|>(.+)<\/bp>/$1/ while ( $msg =~ /<|>/ );
        $msg =~ s/<bs>.+<\|>(.+)<\/bp>/$1/g;

        my $lastItem = pop @array;
        my $list     = join(", ", @array);
        $list .= " and $lastItem";

        # put list
        $msg =~ s/<pl>/$list/;
    }

    return $msg;
}

1;
