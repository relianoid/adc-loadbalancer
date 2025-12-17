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
use feature qw(say signatures state);

use Relianoid::Log;

=pod

=head1 Module

Relianoid::Config

=cut

=pod

=head1 getGlobalConfiguration

Get the value of a configuration variable. The global.conf is parsed only the first time

Parameters:

    parameter - Name of the global configuration variable. Optional.
    force_reload - This parameter is a flag that force a reload of the global.conf structure, useful to reload the struct when it has been modified. Optional

Returns:

    scalar - Value of the configuration variable when a variable name is passed as an argument.
    scalar - Hash reference to all global configuration variables when no argument is passed.

=cut

sub getGlobalConfiguration ($parameter, $force_reload = 0) {
    state $global_conf = &parseGlobalConfiguration();

    if ($force_reload) {
        $global_conf = &parseGlobalConfiguration();
    }

    if ($parameter) {
        if (defined $global_conf->{$parameter}) {
            return $global_conf->{$parameter};
        }
        elsif ($parameter eq 'debug') {
            # workaround: no message is logged when the 'debug' parameter is not defined in global.conf.
            return;
        }
        else {
            &log_warn("The global configuration parameter '$parameter' has not been found", 'Configuration');

            return;
        }
    }

    return $global_conf;
}

=pod

=head1 parseGlobalConfiguration

Parse the global.conf file. It expands the variables too.

Parameters:

    global_conf_filepath - string - Optional. Set the location of a global.conf file.

Returns: hash ref

=cut

sub parseGlobalConfiguration ($global_conf_filepath = "/usr/local/relianoid/config/global.conf") {
    my $global_conf;

    use Fcntl qw(:flock);

    if (open(my $global_conf_file, '<', $global_conf_filepath)) {
        flock($global_conf_file, LOCK_SH)
          or die "Cannot lock file ${global_conf_file}: $!\n";

        my @lines = <$global_conf_file>;
        close $global_conf_file;

        # build globalconf struct
        for my $conf_line (@lines) {
            # extract variable name and value
            if ($conf_line =~ /^\s*\$(\w+)\s*=\s*(?:"(.*)"|\'(.*)\');(?:\s*#update)?\s*$/) {
                $global_conf->{$1} = $2;
            }
        }
    }
    else {
        my $msg = "Could not open $global_conf_filepath: $!";
        &log_error($msg, "SYSTEM");
        die $msg;
    }

    # expand the variables, by replacing every variable used in the $var_value by its content
    for my $param (keys %{$global_conf}) {
        while ($global_conf->{$param} =~ /\$(\w+)/) {
            my $var   = $1;
            my $value = $global_conf->{$var} // '';
            $global_conf->{$param} =~ s/\$$var/$value/;
        }
    }

    return $global_conf;
}

=pod

=head1 setGlobalConfiguration

Set a value to a configuration variable

Parameters:

    param - Configuration variable name.
    value - New value to be set on the configuration variable.

Returns: integer - errno

FIXME:

- Receive a hash, to be able to set a list of settings
- Control file handling errors.

=cut

sub setGlobalConfiguration ($param, $value) {
    my $global_conf_file = &getGlobalConfiguration('globalcfg');
    my $output           = -1;

    use Fcntl qw(:flock);

    if (open(my $fh, '+<', $global_conf_file)) {    ## no critic (InputOutput::RequireBriefOpen)
        flock($fh, LOCK_EX) or die "Cannot lock file ${global_conf_file}: $!\n";
        my @lines = <$fh>;

        for my $line (@lines) {
            if ($line =~ /^\$$param\s*=/) {
                $line   = "\$${param}=\"${value}\";\n";
                $output = 0;
                last;
            }
        }

        seek $fh, 0, 0;
        truncate $fh, 0;    # reduce file size to 0
        print {$fh} join("", @lines);
        close $fh;
    }
    else {
        log_error("Could not open file ${global_conf_file}: $!");
    }

    # reload global.conf struct
    &getGlobalConfiguration(undef, 1);

    return $output;
}

=pod

=head1 setConfigStr2Arr

Put a list of string parameters as array references

Parameters:

    obj        - reference to a hash
    param_list - list of parameters to change from string to array

Returns: hash ref - Object updated

=cut

sub setConfigStr2Arr ($obj, $param_list) {
    for my $param_name (@{$param_list}) {
        my @list = ();

        # split parameter if it is not a blank string
        @list = sort split(' ', $obj->{$param_name})
          if ($obj->{$param_name});
        $obj->{$param_name} = \@list;
    }

    return $obj;
}

=pod

=head1 getTinyObj

Get a Config::Tiny object from a file name.
This function has 3 behaviors:

it can returns all parameters from all groups
or it can returns all parameters from a group
or it can returns only selected parameters.
selected parameters can be ignored,undef or error if they do not exists

Parameters:

    file_path - Path to file.
    section - Group to get. Empty means all groups.
    key_ref - Array of parameters to get. Empty means all parameters
    key_action - string define the action. Possible values are "ignored|undef|error".Empty means error.

Returns: hash ref | undef

A reference to Config::Tiny object when success, undef on failure.

=cut

sub getTinyObj ($filepath, $section = undef, $key_ref = undef, $key_action = "error") {
    if (!-f "$filepath") {
        return;
    }

    require Config::Tiny;
    my $conf = Config::Tiny->read($filepath);

    if (not defined $conf) {
        return;
    }

    if (not defined $section) {
        return $conf;
    }

    if (not exists $conf->{$section}) {
        return;
    }

    if (not defined $key_ref) {
        return $conf->{$section};
    }

    if (ref $key_ref ne 'ARRAY') {
        return;
    }

    my $filtered_conf = {};
    $conf = $conf->{$section};

    for my $param (@{$key_ref}) {
        if (defined $conf->{$param}) {
            $filtered_conf->{$param} = $conf->{$param};
        }
        else {
            if ($key_action eq "error") {
                return;
            }

            if ($key_action eq "undef") {
                $filtered_conf->{$param} = undef;
            }
        }
    }

    return $filtered_conf;
}

=pod

=head1 setTinyObj

Save a change in a config file. The file is locker before than applying the changes
This function has 2 behaviors:

it can receives a hash ref to save a struct
or it can receive a key and parameter to replace a value

Parameters:

    path   - Tiny conguration file where to apply the change
    object - Group to apply the change
    key    - parameter to change or struct ref to overwrite.
    value  - new value for the parameter or action for struct ref. The possible action values are: "update" to update only existing params , "new" to delete old params and set news ones or empty to add all new params.
    action - This is a optional parameter. The possible values are: "add" to add
             a item to a list, or "del" to delete a item from a list, or "remove" to delete the key

Returns: integer - errno

=cut

sub setTinyObj ($path, $object = undef, $key = undef, $value = undef, $action = undef) {
    unless ($object) {
        &log_info("Object not defined trying to save it in file $path");
        return;
    }

    &log_debug2("Modify $object from $path");

    require Relianoid::Lock;
    require Config::Tiny;
    require Relianoid::File;

    my $lock_file = &getLockFile($path);
    my $lock_fd   = &openlock($lock_file, 'w');

    my $fileHandle;
    if (!-f "$path") {
        createFile($path);
        $fileHandle = Config::Tiny->new;
    }
    else {
        $fileHandle = Config::Tiny->read($path);
    }

    unless ($fileHandle) {
        &log_info("Could not open file $path: " . Config::Tiny::errstr());
        return -1;
    }

    # save all struct
    if (ref $key) {
        if ((defined $value) and ($value eq "new")) {
            $fileHandle->{$object} = {};
        }
        for my $param (keys %{$key}) {
            if (ref $key->{$param} eq 'ARRAY') {
                $key->{$param} = join(' ', @{ $key->{$param} });
            }
            next
              if (  (!exists $fileHandle->{$object}{$param})
                and ((defined $value) and ($value eq "update")));

            $fileHandle->{$object}{$param} = $key->{$param};
        }
    }

    # save a parameter
    else {
        if ($action and 'add' eq $action) {
            $fileHandle->{$object}{$key} .= " $value";
        }
        elsif ($action and 'del' eq $action) {
            $fileHandle->{$object}{$key} =~ s/(^| )$value( |$)/ /;
        }
        elsif ($action and 'remove' eq $action) {
            delete $fileHandle->{$object}{$key};
        }
        else {
            $fileHandle->{$object}{$key} = $value;
        }
    }

    my $error = $fileHandle->write($path) ? 0 : 1;

    close $lock_fd;
    unlink $lock_file;

    return $error;
}

=pod

=head1 delTinyObj

It deletes a object of a tiny file. The tiny file is locked before than set the configuration

Parameters:

    path   - string - Tiny file name where the object will be deleted
    object - string - Group name

Returns: integer - errno

=cut

sub delTinyObj ($path, $object) {
    &log_debug2("Delete $object from $path");

    require Relianoid::Lock;

    my $lock_file = &getLockFile($path);
    my $lock_fd   = &openlock($lock_file, 'w');

    my $fileHandle = Config::Tiny->read($path);
    delete $fileHandle->{$object};

    my $error = $fileHandle->write($path) ? 0 : 1;

    close $lock_fd;
    unlink $lock_file;

    return $error;
}

=pod

=head1 migrateConfigFiles

Apply migration scripts.

Parameters: none

Returns: none

=cut

sub migrateConfigFiles () {
    # Avoid configuration dependency before migrations.
    my $migrations_dir = '/usr/local/relianoid/migrations';

    opendir(my $dh, $migrations_dir);
    my @files = grep { -f "${migrations_dir}/$_" } sort readdir($dh);
    closedir $dh;

    for my $file (@files) {
        my $errno = system("${migrations_dir}/${file} >/dev/null");
        my $msg   = "";

        if ($errno == 0) {
            log_info($file);
        }
        else {
            log_error($file);
        }
    }

    return;
}

1;

