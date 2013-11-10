package EvePIWH::Controller::Main;
use Mojo::Base 'Mojolicious::Controller';
use utf8;

use Data::Dumper;

use EvePIWH::Model::EveDB;

# This action will render a template
sub index {
  my $self = shift;

  my $evedb = EvePIWH::Model::EveDB->new( $self->stash('db') );
  my $products = $evedb->get_planetary_products();
  
  $self->param('p2', 0) &&  $self->param('p1',0) if $self->param('p3');
  $self->param('p1', 0) if $self->param('p2');

  my $search_product = $self->param('p3') || $self->param('p2') || $self->param('p1');

  if ( $search_product || ( $self->param('bonus') || $self->param('static') ) ) {
        my %params = (
            min_class => $self->param('min_class') || 1,
            max_class => $self->param('max_class') || 6,
            static    => $self->param('static'),
            bonus     => $self->param('bonus'),
        );
        $evedb->get_wh_with_product( $search_product, %params );
  }

  $self->render( products => $products, answer => $evedb );
}

1;
