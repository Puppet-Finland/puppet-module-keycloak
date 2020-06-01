# Private class.
class keycloak::config::domain {
  assert_private()

  file { "${keycloak::install_base}/domain/configuration":
    ensure => 'directory',
    owner  => $keycloak::user,
    group  => $keycloak::group,
    mode   => '0750',
  }

  file { "${keycloak::install_base}/domain/configuration/profile.properties":
    ensure  => 'file',
    owner   => $keycloak::user,
    group   => $keycloak::group,
    content => template('keycloak/profile.properties.erb'),
    mode    => '0644',
    notify  => Class['keycloak::service'],
  }

  $_dirs = [
    "${keycloak::install_base}/domain/servers",
    "${keycloak::install_base}/domain/servers/${keycloak::server_name}",
    "${keycloak::install_base}/domain/servers/${keycloak::server_name}/configuration",
  ]

  file { $_dirs:
    ensure => 'directory',
    owner  => $keycloak::user,
    group  => $keycloak::group,
    mode   => '0755',
  }

  $_server_conf_dir = "${keycloak::install_base}/domain/servers/${keycloak::server_name}/configuration"
  $_add_user_keycloak_cmd = "${keycloak::install_base}/bin/add-user-keycloak.sh"
  $_add_user_keycloak_args = "--user ${keycloak::admin_user} --password ${keycloak::admin_user_password} --realm master --sc ${_server_conf_dir}/" # lint:ignore:140chars
  $_add_user_keycloak_state = "${keycloak::install_base}/.create-keycloak-admin-${keycloak::datasource_driver}"
  exec { 'create-keycloak-admin':
    command => "${_add_user_keycloak_cmd} ${_add_user_keycloak_args} && touch ${_add_user_keycloak_state}",
    creates => $_add_user_keycloak_state,
    notify  => Class['keycloak::service'],
  }

  $_add_user_wildfly_cmd = "${keycloak::install_base}/bin/add-user.sh"
  $_add_user_wildfly_args = "--user ${keycloak::wildfly_user} --password ${keycloak::wildfly_user_password} -e -s"
  $_add_user_wildfly_state = "${::keycloak::install_base}/.create-wildfly-user"
  exec { 'create-wildfly-user':
    command => "${_add_user_wildfly_cmd} ${_add_user_wildfly_args} && touch ${_add_user_wildfly_state}",
    creates => $_add_user_wildfly_state,
    notify  => Class['keycloak::service'],
  }

  if $keycloak::role == 'master' {

    # Remove load balancer group
    # Rename the server
    # Set port offset to zero, to run server on port 8080
    augeas { 'ensure-servername':
      incl      => "${keycloak::install_base}/domain/configuration/host-master.xml",
      context   => "/files${keycloak::install_base}/domain/configuration/host-master.xml/host/servers",
      load_path => '/opt/puppetlabs/puppet/share/augeas/lenses/dist',
      lens      => 'Xml.lns',
      changes   => [
        'rm server[1]',
        "set server/#attribute/name ${keycloak::server_name}",
        'set server/#attribute/group auth-server-group',
        'set server/#attribute/auto-start true',
        'set server/socket-bindings/#attribute/port-offset 0',
      ],
      notify    => Class['keycloak::service'],
    }

  } else { # host is a slave

    # Rename the server
    # Set port offset to zero, to run server in port 8080
    augeas { 'ensure-servername':
      incl      => "${keycloak::install_base}/domain/configuration/host-slave.xml",
      context   => "/files${keycloak::install_base}/domain/configuration/host-slave.xml/host/servers",
      load_path => '/opt/puppetlabs/puppet/share/augeas/lenses/dist',
      lens      => 'Xml.lns',
      changes   => [
        "set server/#attribute/name ${keycloak::server_name}",
        'set server/socket-bindings/#attribute/port-offset 0'
      ],
      notify    => Class['keycloak::service'],
    }

    # Set username for authentication to master
    augeas { 'ensure-username':
      incl      => "${keycloak::install_base}/domain/configuration/host-slave.xml",
      context   => "/files${keycloak::install_base}/domain/configuration/host-slave.xml/host/domain-controller/remote",
      load_path => '/opt/puppetlabs/puppet/share/augeas/lenses/dist',
      lens      => 'Xml.lns',
      changes   => [
        "set #attribute/username ${keycloak::wildfly_user}"
      ],
      notify    => Class['keycloak::service'],
    }


    # Set secret for authentication to master
    augeas { 'ensure-secret':
      incl      => "${keycloak::install_base}/domain/configuration/host-slave.xml",
      context   => "/files${keycloak::install_base}/domain/configuration/host-slave.xml/host/management/security-realms/security-realm[1]/server-identities/secret", # lint:ignore:140chars
      load_path => '/opt/puppetlabs/puppet/share/augeas/lenses/dist',
      lens      => 'Xml.lns',
      changes   => [
        "set #attribute/value ${keycloak::wildfly_user_password_base64}"
      ],
      notify    => Class['keycloak::service'],
    }
  } # end if host is a master

  file { "${keycloak::install_base}/config-domain.cli":
    ensure    => 'file',
    owner     => $keycloak::user,
    group     => $keycloak::group,
    mode      => '0600',
    content   => template('keycloak/config-domain.cli.erb'),
    notify    => Exec['jboss-cli.sh --file=config-domain.cli'],
    show_diff => false,
  }

  exec { 'jboss-cli.sh --file=config-domain.cli':
    command     => "${keycloak::install_base}/bin/jboss-cli.sh --file=config-domain.cli",
    cwd         => $keycloak::install_base,
    user        => $keycloak::user,
    group       => $keycloak::group,
    refreshonly => true,
    logoutput   => true,
    notify      => Class['keycloak::service'],
  }

  if $keycloak::java_opts {
    $java_opts_ensure = 'present'
  } else {
    $java_opts_ensure = 'absent'
  }

  if $keycloak::java_opts =~ Array {
    $java_opts = join($keycloak::java_opts, ' ')
  } else {
    $java_opts = $keycloak::java_opts
  }

  if $keycloak::java_opts_append {
    $_java_opts = "\$JAVA_OPTS ${java_opts}"
  } else {
    $_java_opts = $java_opts
  }

  file_line { 'domain.conf-JAVA_OPTS':
    ensure => $java_opts_ensure,
    path   => "${keycloak::install_base}/bin/domain.conf",
    line   => "JAVA_OPTS=\"${_java_opts}\"",
    match  => '^JAVA_OPTS=',
    notify => Class['keycloak::service'],
  }
}

