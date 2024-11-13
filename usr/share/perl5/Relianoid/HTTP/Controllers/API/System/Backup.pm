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

use Relianoid::Backup;

=pod

=head1 Module

Relianoid::HTTP::Controllers::API::System::Backup

=cut

# GET /system/backup
sub list_backups_controller () {
    my $desc    = "Get backups";
    my $backups = &getBackup();

    return &httpResponse({ code => 200, body => { description => $desc, params => $backups } });
}

# POST /system/backup
sub create_backup_controller ($json_obj) {
    my $desc = "Create a backups";

    my $params = &getAPIModel("system_backup-create.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if (&getExistsBackup($json_obj->{name})) {
        my $msg = "A backup already exists with this name.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $error = &createBackup($json_obj->{name});
    if ($error) {
        my $msg = "Error creating backup.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $msg  = "Backup $json_obj->{ 'name' } was created successfully.";
    my $body = {
        description => $desc,
        params      => $json_obj->{name},
        message     => $msg,
    };

    return &httpResponse({ code => 200, body => $body });
}

# GET /system/backup/BACKUP
sub download_backup_controller ($backup) {
    my $desc = "Download a backup";

    if (!&getExistsBackup($backup)) {
        my $msg = "Not found $backup backup.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $backup_dir           = &getGlobalConfiguration('backupdir');
    my $backup_filename      = &getBackupFilename($backup);

    return &httpDownloadResponse(desc => $desc, dir => $backup_dir, file => $backup_filename);
}

# PUT /system/backup/BACKUP
sub upload_backup_controller ($upload_filehandle, $name) {
    my $desc = "Upload a backup";

    if (!$upload_filehandle || !$name) {
        my $msg = "It's necessary to add a data binary file.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
    elsif (&getExistsBackup($name)) {
        my $msg = "A backup already exists with this name.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
    elsif (!&getValidFormat('backup', $name)) {
        my $msg = "The backup name has invalid characters.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $error = &uploadBackup($name, $upload_filehandle);
    if ($error == 1) {
        my $msg = "Error creating backup.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }
    elsif ($error == 2) {
        my $msg = "$name is not a valid backup.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $msg  = "Backup $name was created successfully.";
    my $body = { description => $desc, params => $name, message => $msg };

    return &httpResponse({ code => 200, body => $body });
}

# DELETE /system/backup/BACKUP
sub delete_backup_controller ($backup) {
    my $desc = "Delete backup $backup'";

    if (!&getExistsBackup($backup)) {
        my $msg = "$backup doesn't exist.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $error = &deleteBackup($backup);

    if ($error) {
        my $msg = "There was a error deleting list $backup.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    my $msg  = "The list $backup has been deleted successfully.";
    my $body = {
        description => $desc,
        success     => "true",
        message     => $msg,
    };

    return &httpResponse({ code => 200, body => $body });
}

# POST /system/backup/BACKUP/actions
sub apply_backup_controller ($json_obj, $backup) {
    my $desc = "Apply a backup to the system";

    my $params = &getAPIModel("system_backup-apply.json");

    # Check allowed parameters
    if (my $error_msg = &checkApiParams($json_obj, $params, $desc)) {
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $error_msg });
    }

    if (!&getExistsBackup($backup)) {
        my $msg = "Not found $backup backup.";
        return &httpErrorResponse({ code => 404, desc => $desc, msg => $msg });
    }

    my $b_version   = &getBackupVersion($backup);
    my $sys_version = &getGlobalConfiguration('version');
    if ($b_version ne $sys_version) {
        if (not exists $json_obj->{force}
            or (exists $json_obj->{force} and $json_obj->{force} ne 'true'))
        {
            my $msg =
              "The backup version ($b_version) is different to the Relianoid version ($sys_version). The parameter 'force' must be used to force the backup applying.";
            return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
        }
        else {
            &log_info("Applying The backup version ($b_version) is different to the Relianoid version ($sys_version).");
        }
    }

    my $msg   = "The backup was properly applied. Some changes need a system reboot to work.";
    my $error = &restoreBackup($backup);

    if ($error) {
        $msg = "There was a error applying the backup.";
        return &httpErrorResponse({ code => 400, desc => $desc, msg => $msg });
    }

    return &httpResponse({ code => 200, body => { description => $desc, message => $msg } });
}

1;

