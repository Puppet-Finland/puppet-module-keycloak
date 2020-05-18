#!/bin/sh

# Exit on any error
set -e

# Preparations required prior to "puppet apply".

usage() {
    echo
    echo "Usage: run_puppet.sh -b basedir"
    echo
    echo "Options:"
    echo " -b   Base directory for dependency Puppet modules installed by"
    echo "      librarian-puppet."
    echo " -m   Puppet manifests to run. Put them in the provision folder"
    exit 1
}

# Parse the options

# We are run without parameters -> usage
if [ "$1" = "" ]; then
    usage
fi

while getopts "b:m:h" options; do
    case $options in
        b ) BASEDIR=$OPTARG;;
	m ) MANIFESTS=$OPTARG;;
        h ) usage;;
        \? ) usage;;
        * ) usage;;
    esac
done

CWD=`pwd`

# Configure with "puppet apply"
PUPPET_APPLY="/opt/puppetlabs/bin/puppet apply --modulepath=$BASEDIR/modules"

# Pass variables to Puppet manifests via environment variables
export FACTER_profile='/etc/profile.d/openvpn.sh'
export FACTER_basedir="$BASEDIR"
export FACTER_keycloak_version='9.0.3'
export FACTER_keycloak_datasource_host='db.local'
export FACTER_keycloak_dbname='keycloak'
export FACTER_keycloak_datasource_username='keycloak'
export FACTER_keycloak_datasource_password='keycloak'
export FACTER_keycloak_admin_user='admin'
export FACTER_keycloak_admin_user_password='changeme'
export FACTER_manage_package_repo='false'
export FACTER_postgresql_version='9.6'
export FACTER_postgresql_manage_package_repo='true'
export FACTER_postgresql_listen_address='*'
export FACTER_db_username='keycloak'
export FACTER_db_password='keycloak'
export FACTER_db_database='keycloak'
export FACTER_db_connection_limit='300'

for manifest in $MANIFESTS; do
    $PUPPET_APPLY /install/$manifest
done

cd $CWD
