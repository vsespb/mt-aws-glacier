# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

package TestUtils;

require Exporter;
use base qw/Exporter/;
                                                                                                                                                                                                                                                                               
our @EXPORT = qw/fake_config config_create_and_parse disable_validations/;

sub fake_config(@)
{
	my ($cb, %data) = (pop @_, @_);
	no warnings 'redefine';
	local *App::MtAws::ConfigEngine::read_config = sub { %data ? { %data } : { (key=>'mykey', secret => 'mysecret', region => 'myregion') } };
	disable_validations($cb);
}

sub disable_validations
{
	local %disable_validations = ( 
		'override_validations' => {
			journal => undef,
			secret  => undef,
			key => undef, 
		},
	);
	shift->();
}

sub config_create_and_parse(@)
{
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(@_);
	($errors, $warnings, $command, $result);
}

1;
