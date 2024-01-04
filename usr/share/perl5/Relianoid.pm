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

use Relianoid::Core;
use Relianoid::Log;
use Relianoid::Config;
use Relianoid::Validate;
use Relianoid::Debug;
use Relianoid::Netfilter;
use Relianoid::Net::Interface;
use Relianoid::FarmGuardian;
use Relianoid::Backup;
use Relianoid::RRD;
use Relianoid::SNMP;
use Relianoid::Stats;
use Relianoid::SystemInfo;
use Relianoid::System;
use Relianoid::API;

require Relianoid::CGI if defined $ENV{GATEWAY_INTERFACE};

=pod

=head1 Module

Relianoid

=cut

1;
