package EvePIWH::Model::EveDB;

use utf8;
use Modern::Perl;
use Data::Dumper;
use List::MoreUtils qw(uniq);

sub new {
    my $class = shift;
    my $db = shift;
    $class = ref ($class) || $class;

    my $self;

    $self = {
        db               => $db,
        product          => undef,
        resources        => undef,
        resource_planets => undef,
        planets          => undef,
        systems          => undef,
        psystems         => undef,
    };

    bless $self, $class;

    return $self;
}

sub get_wh_with_product {
    my ( $self, $search_product, %params ) = @_;

    $self->{product} = $search_product;
    $self->{resources} = $self->{planets} = $self->{systems} = $self->{psystems} = $self->{resource_planets} = undef;

    if ( $self->{product} ) {
        $self->get_resources_for_product( $self->{product} );
        $self->get_planets_for_resource();
        $self->get_planets_set();
    }

    $self->get_systems( %params );
    $self->get_systems_with_planetary() if $self->{product};
    $self->{psystems} = $self->{systems} unless $self->{product};

    return $self;
}

sub get_systems_with_planetary {
    my ( $self ) = @_;

    my $solarSystemsIDs;

    foreach my $sys ( @{ $self->{systems} } ) {
        foreach my $planets ( @{ $self->{planets} } ) {
            my $psystem = $self->{db}->selectall_arrayref(
                "SELECT 
                *
                FROM eve.mapSolarSystems s
                JOIN eve.mapLocationWormholeClasses wh ON wh.locationID = s.regionID
                LEFT JOIN eve.mapDenormalize map ON s.solarSystemID = map.solarSystemID AND ( map.groupID = 7 ) 
                LEFT JOIN eve.invTypes inv ON inv.typeID = map.typeID
                LEFT JOIN eve.mapWormholeStatics ws ON ws.systemName = s.solarSystemName
                WHERE
                inv.typeID IN ( $planets )
                AND s.solarSystemID = ?
                GROUP BY s.solarSystemID
                ",
                { Slice => {} }, $sys->{solarSystemID} );

            if ( $psystem ) {
                push @{$self->{psystems}}, $sys;
                last;
            }
        }
    }
 
    return $self;
}

sub get_systems {
    my ( $self, %params ) = @_;

    my $where;
    my @bind;

    if ( $params{bonus} ) {
        if ( $params{bonus} ne 'empty' ) {
            $where .= " AND inv.TypeID = ? ";
            push @bind, $params{bonus};
        }
        else {
            $where .= " AND inv.TypeID IS NULL ";
        }
    }
    if ( $params{min_class} && $params{max_class} ) {
        if ( $params{min_class} == $params{max_class} ) {
            $where .= " AND wormholeClassID = ? ";
            push @bind, $params{min_class};
        }
        else {
            $where .= " AND wormholeClassID >= ? AND wormholeClassID <= ? ";
            push @bind, $params{min_class};
            push @bind, $params{max_class};
        }
    }
    if ( $params{static} ) {
        $where .= " AND ws.firstStaticType = ? ";
        push @bind, $params{static};
    }

    #  --  map.groupID = 7  for planets
    my $systems = $self->{db}->selectall_arrayref(
        "SELECT 
        *
        FROM eve.mapSolarSystems s
        JOIN eve.mapLocationWormholeClasses wh ON wh.locationID = s.regionID
        LEFT JOIN eve.mapDenormalize map ON s.solarSystemID = map.solarSystemID AND ( map.groupID = 995 ) 
        LEFT JOIN eve.invTypes inv ON inv.typeID = map.typeID
        LEFT JOIN eve.mapWormholeStatics ws ON ws.systemName = s.solarSystemName
        WHERE
        s.security = -0.99
        $where
        LIMIT 50
        ",
        { Slice => {} }, @bind );

    $self->{systems} = $systems;
    return $self;
}

sub get_resources_for_product {
    my ( $self, $product ) = @_;

    my $schematicName = $self->{db}->selectrow_array("SELECT typeName FROM invTypes WHERE typeID = ?", undef, $product );
    my $schematicID = $self->{db}->selectrow_array("SELECT schematicID FROM planetSchematics WHERE schematicName = ?;", undef, $schematicName );

    my $resources = $self->{db}->selectall_arrayref("SELECT * FROM planetSchematicsTypeMap p
                                                    LEFT JOIN invTypes i ON p.typeID = i.typeID
                                                    WHERE schematicID = ?;",{ Slice => {} }, $schematicID );
    foreach my $r ( @$resources ) {
        if ( $r->{marketGroupID} == 1333 ) {
            # ресурс с планеты
            push @{ $self->{resources} }, $r;
        }
        elsif ( $r->{typeID} eq $product ) {
            next;
        }
        else {
            $self->get_resources_for_product( $r->{typeID} );
        }
    }

    return $self;
}

sub get_planets_for_resource {
    my ( $self ) = @_;

    foreach my $r ( @{ $self->{resources} } ) {
        my $planets = $self->{db}->selectcol_arrayref("SELECT planetID FROM planetResources WHERE resourceID = ?", undef, $r->{typeID});
        push @{ $self->{resource_planets} }, $planets; #{ $r->{typeID} => $planets };
    }
    return $self;
}

sub normalize_planets_set {
    my ( $self ) = @_;

    my $sets = $self->{planets};

    foreach my $set ( @$sets ) {
        @$set = uniq sort @$set;
    }

    my @new_sets;

    for (my $i = 0; $i < scalar @$sets; $i++) {
        push @new_sets, join ',' , @{ $sets->[$i] };
    }

    @new_sets = uniq sort @new_sets;

    $self->{planets} = \@new_sets;

    return $self;
}

sub get_planets_set {
    my ( $self ) = @_;
    # TODO: Сделать ввиде норм алгоритма комбинаторной задачи, а не эту хуйню
    my $cnt = scalar @{ $self->{resource_planets} } if $self->{resource_planets};
    return $self unless $cnt;

    if ( $cnt == 1 ) {
        foreach ( @{ $self->{resource_planets}->[0] } ) {
            push @{ $self->{planets} }, $_;
        }
        return $self;
    }

    my $i = 0;
    my @set;

    if ( $cnt == 2 ) {
        foreach my $r ( @{ $self->{resource_planets}->[0] } ) {
           foreach my $p1 ( @{ $self->{resource_planets}->[1] } ) {
                push @{$set[$i]}, $p1;
                push @{$set[$i]}, $r;
                $i++;
            }
        }
    }
    else {
        foreach my $r ( @{ $self->{resource_planets}->[0] } ) {
           foreach my $p1 ( @{ $self->{resource_planets}->[1] } ) {
                foreach my $p2 ( @{ $self->{resource_planets}->[2] } ) {
                    foreach my $p3 ( @{ $self->{resource_planets}->[3] } ) {
                        push @{$set[$i]}, $p1;
                        push @{$set[$i]}, $p2;
                        push @{$set[$i]}, $p3;
                        push @{$set[$i]}, $r;
                        $i++;
                    }
                }   
            }
        }
    }

    push @{ $self->{planets}}, @set;

    $self->normalize_planets_set();
    return $self;
}


sub get_planetary_products {
    my ( $self ) = @_;

    my $products;
    $products->{p0} = $self->{db}->selectall_arrayref("SELECT p.*, i.*
                                    FROM eve.planetSchematicsTypeMap p
                                    INNER JOIN invTypes i ON i.typeID = p.typeID
                                    WHERE i.marketGroupID = 1333
                                    GROUP BY i.typeID;", { Slice => {} } );
    $products->{p1} = $self->{db}->selectall_arrayref("SELECT p.*, i.*
                                    FROM eve.planetSchematicsTypeMap p
                                    INNER JOIN invTypes i ON i.typeID = p.typeID
                                    WHERE i.marketGroupID = 1334
                                    GROUP BY i.typeID;",{ Slice => {} });
    $products->{p2} = $self->{db}->selectall_arrayref("SELECT p.*, i.*
                                    FROM eve.planetSchematicsTypeMap p
                                    INNER JOIN invTypes i ON i.typeID = p.typeID
                                    WHERE i.marketGroupID = 1335
                                    GROUP BY i.typeID;",{ Slice => {} });
    $products->{p3} = $self->{db}->selectall_arrayref("SELECT p.*, i.*
                                    FROM eve.planetSchematicsTypeMap p
                                    INNER JOIN invTypes i ON i.typeID = p.typeID
                                    WHERE i.marketGroupID = 1336
                                    GROUP BY i.typeID;",{ Slice => {} });
    $products->{p4} = $self->{db}->selectall_arrayref("SELECT p.*, i.*
                                    FROM eve.planetSchematicsTypeMap p
                                    INNER JOIN invTypes i ON i.typeID = p.typeID
                                    WHERE i.marketGroupID = 1337
                                    GROUP BY i.typeID;",{ Slice => {} });
    return $products;
}


1;
