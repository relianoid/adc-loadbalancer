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

use File::stat;
use File::Basename;

=pod

=head1 Module

Relianoid::Backup

=cut

=pod

=head1 getBackup

List the backups in the system.

Parameters:

    none

Returns:

    scalar - Array reference.

=cut

sub getBackup () {
    my @backups;
    my $backupdir = &getGlobalConfiguration('backupdir');
    my $backup_re = &getValidFormat('backup');

    opendir(my $directory, $backupdir);
    my @files = grep { /^backup.*/ } readdir($directory);
    closedir($directory);

    for my $line (@files) {
        my $filepath = "$backupdir/$line";
        chomp($filepath);

        $line =~ s/backup-($backup_re).tar.gz/$1/;

        use Time::localtime qw(ctime);

        my $datetime_string = ctime(stat($filepath)->mtime);
        $datetime_string = &logAndGet("date -d \"${datetime_string}\" +%F\"  \"%T\" \"%Z -u");
        chomp($datetime_string);
        push @backups,
          {
            'name'    => $line,
            'date'    => $datetime_string,
            'version' => &getBackupVersion($line)
          };
    }

    return \@backups;
}

=pod

=head1 getExistsBackup

Check if there is a backup with the given name.

Parameters:

    name - Backup name.

Returns:

    1     - if the backup exists.
    undef - if the backup does not exist.

=cut

sub getExistsBackup ($name) {
    my $find;

    for my $backup (@{ &getBackup() }) {
        if ($backup->{name} =~ /^$name/,) {
            $find = 1;
            last;
        }
    }
    return $find;
}

=pod

=head1 createBackup

Creates a backup with the given name

Parameters:

    name - Backup name.

Returns:

    integer - ERRNO or return code of backup creation process.

=cut

sub createBackup ($name) {
    my $backup_cmd = &getGlobalConfiguration('backup_cmd');
    return &logAndRun("$backup_cmd $name -c");
}

=pod

=head1 getBackupFilename

Get a backup file name, not includin the directory.

Parameters:

    backup - Backup name.

Returns: string - Backup's absolute path.

=cut

sub getBackupFilename ($backup) {
    return "backup-${backup}.tar.gz";
}

=pod

=head1 uploadBackup 

Store an uploaded backup.

Parameters:

    filename          - Uploaded backup file name.
    upload_filehandle - File handle or file content.

Returns:

    2 - The file is not a .tar.gz
    1 - on failure.
    0 - on success.

=cut

sub uploadBackup ($filename, $upload_filehandle) {
    my $error;
    my $backupdir = &getGlobalConfiguration('backupdir');
    my $tar       = &getGlobalConfiguration('tar');

    $filename = "backup-$filename.tar.gz";
    my $filepath = "$backupdir/$filename";

    if (!-f $filepath) {
        open(my $disk_fh, '>', $filepath) or die "$!";

        binmode $disk_fh;

        use MIME::Base64 qw( decode_base64 );
        print $disk_fh decode_base64($upload_filehandle);

        close $disk_fh;
    }
    else {
        return 1;
    }

    # check the file, looking for the global.conf config file
    my $config_path = &getGlobalConfiguration('globalcfg');

    # remove the first slash
    $config_path =~ s/^\///;

    $error = &logAndRun("$tar -tf $filepath $config_path");

    if ($error) {
        &zenlog("$filename looks being a not valid backup", 'error', 'backup');
        unlink $filepath;
        return 2;
    }

    return $error;
}

=pod

=head1 deleteBackup

Delete a backup.

Parameters:

    file - Backup name.

Returns:

    1     - on failure.
    undef - on success.

=cut

sub deleteBackup ($file) {
    $file = "backup-$file.tar.gz";
    my $backupdir = &getGlobalConfiguration("backupdir");
    my $filepath  = "$backupdir/$file";
    my $error;

    if (-e $filepath) {
        unlink($filepath);
        &zenlog("Deleted backup file $file", "info", "SYSTEM");
    }
    else {
        &zenlog("File $file not found", "warning", "SYSTEM");
        $error = 1;
    }

    return $error;
}

=pod

=head1 applyBackup

Restore files from a backup.

Parameters:

    backup - Backup name.

Returns:

    integer - 0 on success or another value on failure.

=cut

sub applyBackup ($backup) {
    my $error;
    my $tar               = &getGlobalConfiguration('tar');
    my $file              = &getGlobalConfiguration('backupdir') . "/backup-$backup.tar.gz";
    my $relianoid_service = &getGlobalConfiguration('relianoid_service');
    my $systemctl         = &getGlobalConfiguration('systemctl');

    # get current version
    my $version = &getGlobalConfiguration('version');

    &zenlog("Stopping Relianoid service", "info", "SYSTEM");
    $error = &logAndRun("$systemctl stop $relianoid_service");
    if ($error) {
        &zenlog("Problem stopping Relianoid Load Balancer service", "error", "SYSTEM");
        return $error;
    }

    &zenlog("Restoring backup $file", "info", "SYSTEM");
    my $cmd   = "$tar -xvzf $file -C /";
    my $eject = &logAndGet($cmd, 'array');

    if (not @{$eject}) {
        &zenlog("The backup $file could not be extracted", "error", "SYSTEM");
        return $error;
    }

    &zenlog("unpacked files: @{$eject}", "info", "SYSTEM");

    # it would overwrite version if it was different
    require Relianoid::System;
    &setGlobalConfiguration('version', $version);

    unlink '/relianoid_version';

    # set migration files process
    my $migration_flag = &getGlobalConfiguration('migration_flag');
    open(my $fh, '>', $migration_flag) or die "$!";
    close($fh);
    &zenlog("Migration Flag enabled") if (-e $migration_flag);

    $error = &logAndRun("$systemctl start $relianoid_service");

    if (!$error) {
        &zenlog("Backup applied and Relianoid Load Balancer restarted...", "info", "SYSTEM");
    }
    else {
        &zenlog("Problem restarting Relianoid Load Balancer service", "error", "SYSTEM");
    }

    return $error;
}

=pod

=head1 getBackupVersion

It gets the version of relianoid from which the backup was created

Parameters:

    backup - Backup name.

Returns:

    String - Relianoid version

=cut

sub getBackupVersion ($backup) {
    my $tar         = &getGlobalConfiguration('tar');
    my $file        = &getGlobalConfiguration('backupdir') . "/backup-$backup.tar.gz";
    my $config_path = &getGlobalConfiguration('globalcfg');

    # remove the first slash
    $config_path =~ s/^\///;

    my $cmd = "${tar} -xOf ${file} ${config_path}";
    zenlog("Running: $cmd", "debug");

    my @lines = `$cmd`;

    if ($?) {
        zenlog("errno: $?", "error");
    }

    my $version = "";

    for my $line (@lines) {
        if ($line =~ /^\s*\$version\s*=\s*(?:"(.*)"|\'(.*)\');(?:\s*#update)?\s*$/) {
            $version = $1;
            last;
        }
    }

    &zenlog("Backup: $backup, version: $version", "debug3", "system");

    return $version;
}

1;

