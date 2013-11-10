package EvePIWH;
use Mojo::Base 'Mojolicious';
use utf8;
use Data::Dumper;
use Modern::Perl;

use Mojolicious::Plugin::Dbi;
use Mojolicious::Plugin::YamlConfig;

# This method will run once at server start
sub startup {
  my $self = shift;

  # Documentation browser under "/perldoc"
  # $self->plugin('PODRenderer');
  my $config = $self->plugin('yaml_config', {file => 'config/connect.yaml'});
  
  $self->plugin('dbi',{'dsn' => $config->{dsn},
                      'username' => $config->{username},
                       'password' => $config->{password},
                       'no_disconnect' => 1,
                       'stash_key' => 'db',
                       'dbi_attr' => { 'AutoCommit' => 1, 'RaiseError' => 1, 'PrintError' =>1 },
                       'on_connect_do' =>[ 'SET NAMES UTF8'],
                       'requests_per_connection' => 200
  });

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->any('/')->to('main#index', namespace => 'EvePIWH::Controller');
}

#$app->mode('production');

1;
