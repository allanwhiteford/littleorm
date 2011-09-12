use ORM::Db;
use ORM::Db::Field;

package ORM::Model;

use Moose;

has '_rec' => ( is => 'rw', isa => 'HashRef', required => 1, metaclass => 'ORM::Meta::Attribute', description => { ignore => 1 } );

use Carp::Assert;

sub get
{
	my $self = shift;

	my @args = @_;

	my $sql = $self -> __form_get_sql( @args, '_limit' => 1 );
	my $rec = &ORM::Db::getrow( $sql, $self -> __get_dbh( @args ) );

	my $rv = undef;

	if( $rec )
	{
		$rv = $self -> new( _rec => $rec );
	}

	return $rv;
}

sub values_list
{
	my ( $self, $fields, $args ) = @_;

	# example: @values = Class -> values_list( [ 'id', 'name' ], [ something => { '>', 100 } ] );
	# will return ( [ id, name ], [ id1, name1 ], ... )

	my @rv = ();

	foreach my $o ( $self -> get_many( @{ $args } ) )
	{
		my @l = map { $o -> $_() } @{ $fields };

		push @rv, \@l;
	}

	return @rv;
}

sub get_or_create
{
	my $self = shift;

	my $r = $self -> get( @_ );

	unless( $r )
	{
		$r = $self -> create( @_ );
	}

	return $r;
}

sub get_many
{
	my $self = shift;
	my @args = @_;

	my @outcome = ();

	my $sql = $self -> __form_get_sql( @args );
	my $sth = &ORM::Db::prep( $sql, $self -> __get_dbh( @args ) );
	$sth -> execute();

	while( my $data = $sth -> fetchrow_hashref() )
	{
		my $o = $self -> new( _rec => $data );
		push @outcome, $o;
	}
	$sth -> finish();

	return @outcome;

}

sub count
{
	my $self = shift;
	my @args = @_;

	my $outcome = 0;
	my $sql = $self -> __form_count_sql( @args );

	my $r = &ORM::Db::getrow( $sql, $self -> __get_dbh( @args ) );

	$outcome = $r -> { 'count' };

	return $outcome;
}

sub create
{
	my $self = shift;
	my @args = @_;

	my $sql = $self -> __form_insert_sql( @args );

	my $rc = &ORM::Db::doit( $sql, $self -> __get_dbh( @args ) );

	if( $rc == 1 )
	{
		return $self -> get( @_ );
	}

	assert( 0, sprintf( "%s: %s", $sql, &ORM::Db::errstr( $self -> __get_dbh( @args ) ) ) );
}

sub update
{
	my $self = shift;
	my $debug = shift;
	
	assert( my $pkattr = $self -> __find_primary_key(), 'cant update without primary key' );

	my @upadte_pairs = ();


ETxc0WxZs0boLUm1:
	foreach my $attr ( $self -> meta() -> get_all_attributes() )
	{
		my $aname = $attr -> name();

		if( $aname =~ /^_/ )
		{
			# internal attrs start with underscore, skip them
			next ETxc0WxZs0boLUm1;
		}

		if( &__descr_attr( $attr, 'ignore' ) 
		    or 
		    &__descr_attr( $attr, 'primary_key' )
		    or
		    &__descr_attr( $attr, 'ignore_write' ) )
		{
			next ETxc0WxZs0boLUm1;
		}

		my $value = &__prep_value_for_db( $attr, $self -> $aname() );
		push @upadte_pairs, sprintf( '%s=%s', &__get_db_field_name( $attr ), &ORM::Db::dbq( $value, $self -> __get_dbh() ) );

	}

	my $pkname = $pkattr -> name();

	my $sql = sprintf( 'UPDATE %s SET %s WHERE %s=%s',
			   $self -> _db_table(),
			   join( ',', @upadte_pairs ),
			   &__get_db_field_name( $pkattr ),
			   &ORM::Db::dbq( &__prep_value_for_db( $pkattr, $self -> $pkname() ),
					  $self -> __get_dbh() ) );


	if( $debug )
	{
		return $sql;
	} else
	{
		my $rc = &ORM::Db::doit( $sql, $self -> __get_dbh() );
		
		unless( $rc == 1 )
		{
			assert( 0, sprintf( "%s: %s", $sql, &ORM::Db::errstr( $self -> __get_dbh() ) ) );
		}
	}
}

sub delete
{
	my $self = shift;

	my @args = @_;

	my $sql = $self -> __form_delete_sql( @args );

	my $rc = &ORM::Db::doit( $sql, $self -> __get_dbh( @args ) );

	return $rc;
}

sub meta_change_attr
{
	my $self = shift;

	my $arg = shift;

	my %attrs = @_;

	my $arg_obj = $self -> meta() -> find_attribute_by_name( $arg );

	my $d = $arg_obj -> description();

	while( my ( $k, $v ) = each %attrs )
	{
		if( $v )
		{
			$d -> { $k } = $v;
		} else
		{
			delete $d -> { $k };
		}
	}

	$arg_obj -> description( $d );
}

################################################################################
# Internal functions below
################################################################################

sub BUILD
{
	my $self = shift;

FXOINoqUOvIG1kAG:
	foreach my $attr ( $self -> meta() -> get_all_attributes() )
	{
		my $aname = $attr -> name();

		my $orm_initialized_attr_desc_option = 'orm_initialized_attr' . ref( $self );

		if( ( $aname =~ /^_/ ) or &__descr_attr( $attr, 'ignore' ) or &__descr_attr( $attr, $orm_initialized_attr_desc_option ) )
		{
			# internal attrs start with underscore, skip them
			next FXOINoqUOvIG1kAG;
		}

		{
			my $newdescr = ( &__descr_or_undef( $attr ) or {} );
			$newdescr -> { $orm_initialized_attr_desc_option } = 1;

			$attr -> default( undef );
			$self -> meta() -> add_attribute( $aname, ( is => 'rw',
								    isa => $attr -> { 'isa' },
								    coerce => $attr -> { 'coerce' },
								    lazy => 1,
								    metaclass => 'ORM::Meta::Attribute',
								    description => $newdescr,
								    default => sub { $_[ 0 ] -> __lazy_build_value( $attr ) } ) );
		}
	}
}

sub __lazy_build_value
{
	my $self = shift;
	my $attr = shift;

	my $rec_field_name = &__get_db_field_name( $attr );
	my $coerce_from = &__descr_attr( $attr, 'coerce_from' );

	my $r = $self -> _rec();
	my $t = $self -> _rec() -> { $rec_field_name };

	if( defined $coerce_from )
	{
		$t = $coerce_from -> ( $t );
		
	} elsif( my $foreign_key = &__descr_attr( $attr, 'foreign_key' ) )
	{
		&__load_module( $foreign_key );
		
		my $his_pk = $foreign_key -> __find_primary_key();
		
		$t = $foreign_key -> get( $his_pk -> name() => $t,
					  _dbh => $self -> __get_dbh() );
	}
	
	return $t;
}

sub __load_module
{
	my $mn = shift;

	$mn =~ s/::/\//g;
	$mn .= '.pm';

	require( $mn );

}

sub __form_insert_sql
{
	my $self = shift;

	my %args = @_;

	my @fields = ();
	my @values = ();

	my $dbh = $self -> __get_dbh( %args );

	foreach my $attr ( $self -> meta() -> get_all_attributes() )
	{
		my $aname = $attr -> name();
		unless( $args{ $aname } )
		{
			if( my $seqname = &__descr_attr( $attr, 'sequence' ) )
			{
				my $nv = &ORM::Db::nextval( $seqname, $dbh );

				$args{ $aname } = $nv;
			}
		}
	}

XmXRGqnrCTqWH52Z:
	while( my ( $arg, $val ) = each %args )
	{
		if( $arg =~ /^_/ )
		{
			next XmXRGqnrCTqWH52Z;
		}

		assert( my $attr = $self -> meta() -> find_attribute_by_name( $arg ), 
			sprintf( 'invalid attr name passed: %s', $arg ) );

		if( &__descr_attr( $attr, 'ignore' ) 
		    or 
		    &__descr_attr( $attr, 'ignore_write' ) )
		{
			next XmXRGqnrCTqWH52Z;
		}

		my $field_name = &__get_db_field_name( $attr );
		$val = &__prep_value_for_db( $attr, $val );
		
		push @fields, $field_name;
		push @values, $val;
	}

	my $sql = sprintf( "INSERT INTO %s (%s) VALUES (%s)",
			   $self -> _db_table(),
			   join( ',', @fields ),
			   join( ',', map { &ORM::Db::dbq( $_, $dbh ) } @values ) );

	return $sql;
}


sub __prep_value_for_db
{
	my ( $attr, $value ) = @_;

	my $rv = $value;

	my $coerce_to = &__descr_attr( $attr, 'coerce_to' );

	if( defined $coerce_to )
	{
		$rv = $coerce_to -> ( $value );
	}

	if( ref( $value ) and &__descr_attr( $attr, 'foreign_key' ) )
	{
		my $his_pk = $value -> __find_primary_key();
		my $his_pk_name = $his_pk -> name();
		$rv = $value -> $his_pk_name();
	}

	return $rv;

}

sub __form_delete_sql
{
	my $self = shift;

	my @args = @_;
	my %args = @args;

	if( ref( $self ) )
	{
		foreach my $attr ( $self -> meta() -> get_all_attributes() )
		{
			my $aname = $attr -> name();
			$args{ $aname } = $self -> $aname();
		}
	}

	my @where_args = $self -> __form_where( %args );

	my $sql = sprintf( "DELETE FROM %s WHERE %s", $self -> _db_table(), join( ' AND ', @where_args ) );

	return $sql;
}

sub __collect_field_names
{
	my $self = shift;

	my @rv = ();

QGVfwMGQEd15mtsn:
	foreach my $attr ( $self -> meta() -> get_all_attributes() )
	{
		
		my $aname = $attr -> name();

		if( $aname =~ /^_/ )
		{
			next QGVfwMGQEd15mtsn;
		}

		if( &__descr_attr( $attr, 'ignore' ) )
		{
			next QGVfwMGQEd15mtsn;
		}

		push @rv, &__get_db_field_name( $attr );
		
	}

	return @rv;
}

sub __form_get_sql
{
	my $self = shift;

	my @args = @_;
	my %args = @args;

	my @where_args = $self -> __form_where( @args );

	my @fields_names = $self -> __collect_field_names();

	my $sql = sprintf( "SELECT %s FROM %s WHERE %s",
			   join( ',', @fields_names ),
			   $self -> _db_table(), 
			   join( ' ' . ( $args{ '_logic' } or 'AND' ) . ' ', @where_args ) );

	$sql .= $self -> __form_additional_sql( @args );

	return $sql;

}

sub __form_count_sql
{
	my $self = shift;

	my @args = @_;
	my %args = @args;

	my @where_args = $self -> __form_where( @args );

	my $sql = sprintf( "SELECT count(1) FROM %s WHERE %s", $self -> _db_table(), join( ' ' . ( $args{ '_logic' } or 'AND' ) . ' ', @where_args ) );

	return $sql;
}

sub __form_additional_sql
{
	my $self = shift;

	my @args = @_;
	my %args = @args;

	my $sql = '';

	if( my $t = $args{ '_sortby' } )
	{
		if( ref( $t ) eq 'HASH' )
		{
			# then its like
			# { field1 => 'DESC',
			#   field2 => 'ASC' ... }

			my @pairs = ();

			while( my ( $k, $sort_order ) = each %{ $t } )
			{
				my $dbf = &__get_db_field_name( $self -> meta() -> find_attribute_by_name( $k ) );
				push @pairs, sprintf( '%s %s', $dbf, $sort_order );
			}
			$sql .= ' ORDER BY ' . join( ',', @pairs );
		} else
		{
			# then its attr name and unspecified order
			my $dbf = &__get_db_field_name( $self -> meta() -> find_attribute_by_name( $t ) );
			$sql .= ' ORDER BY ' . $dbf;
		}
	}

	if( my $t = int( $args{ '_limit' } or 0 ) )
	{
		$sql .= sprintf( ' LIMIT %d ', $t );
	}

	if( my $t = int( $args{ '_offset' } or 0 ) )
	{
		$sql .= sprintf( ' OFFSET %d ', $t );
	}

	return $sql;
}

sub __form_where
{
	my $self = shift;

	my @args = @_;

	my @where_args = ( '1=1' );

	my $dbh = $self -> __get_dbh( @args );


fhFwaEknUtY5xwNr:
	while( my $attr = shift @args )
	{
		my $val = shift @args;

		if( $attr eq '_where' )
		{
			push @where_args, $val;

		}

		if( $attr =~ /^_/ ) # skip system agrs, they start with underscore
		{
			next fhFwaEknUtY5xwNr;
		}

		assert( my $class_attr = $self -> meta() -> find_attribute_by_name( $attr ),
			sprintf( 'invalid non-system attribute in where: %s', $attr ) );

		if( &__descr_attr( $class_attr, 'ignore' ) )
		{
			next fhFwaEknUtY5xwNr;
		}

		my $class_attr_isa = $class_attr -> { 'isa' };

		my $col = &__get_db_field_name( $class_attr );

		my $op = '=';
		my $field = ORM::Db::Field -> by_type( &__descr_attr( $class_attr, 'db_field_type' ) or $class_attr_isa );

		if( ref( $val ) eq 'HASH' )
		{
			if( $class_attr_isa =~ 'HashRef' )
			{
				next fhFwaEknUtY5xwNr;
			} else
			{
				my %t = %{ $val };
				( $op, $val ) = each %t;

				$val = &ORM::Db::dbq( &__prep_value_for_db( $class_attr, $val ),
						      $dbh );
			}

		} elsif( ref( $val ) eq 'ARRAY' )
		{

			if( $class_attr_isa =~ 'ArrayRef' )
			{
				$val = &ORM::Db::dbq( &__prep_value_for_db( $class_attr, $val ),
						      $dbh );
			} else
			{
				$op = 'IN';
				$val = sprintf( '(%s)', join( ',', map { &ORM::Db::dbq( &__prep_value_for_db( $class_attr, $_ ),
											$dbh ) } @{ $val } ) );
			}

		} else
		{
			$val = &ORM::Db::dbq( &__prep_value_for_db( $class_attr, $val ),
					      $dbh );
		}

		$op = $field -> appropriate_op( $op );

		if( $op )
		{
			push @where_args, sprintf( '%s %s %s', $col, $op, $val );
		}
	}
	return @where_args;
}

sub __find_primary_key
{
	my $self = shift;

	foreach my $attr ( $self -> meta() -> get_all_attributes() )
	{

		if( my $pk = &__descr_attr( $attr, 'primary_key' ) )
		{
			return $attr;
		}
	}
}

sub __descr_or_undef
{
	my $attr = shift;

	my $rv = undef;

	eval {
		$rv = $attr -> description();
	};

	return $rv;
}

sub __get_db_field_name
{
	my $attr = shift;

	assert( $attr );

	my $rv = $attr -> name();

	if( my $t = &__descr_attr( $attr, 'db_field' ) )
	{
		$rv = $t;
	}
	
	return $rv;
}

sub __descr_attr
{
	my $attr = shift;
	my $attr_attr_name = shift;

	my $rv = undef;

	if( my $d = &__descr_or_undef( $attr ) )
	{
		if( my $t = $d -> { $attr_attr_name } )
		{
			$rv = $t;
		}
	}

	return $rv;
}

sub __get_dbh
{
	my $self = shift;

	my %args = @_;

	my $dbh = &ORM::Db::dbh_is_ok( $self -> __get_class_dbh() );

	unless( $dbh )
	{
		if( my $t = &ORM::Db::dbh_is_ok( $args{ '_dbh' } ) )
		{
			$dbh = $t;
			$self -> __set_class_dbh( $dbh );
			ORM::Db -> __set_default_if_not_set( $dbh );
		}
	}

	unless( $dbh )
	{
		if( my $t = &ORM::Db::dbh_is_ok( &ORM::Db::get_dbh() ) )
		{
			$dbh = $t;
			$self -> __set_class_dbh( $dbh );
		}
	}

	return $dbh;
}

sub __get_class_dbh
{

	my $self = shift;

	my $calling_package = ( ref( $self ) or $self );

	my $dbh = undef;

	{
		no strict "refs";
		$dbh = ${ $calling_package . "::_dbh" };
	}

	return $dbh;

	
}

sub __set_class_dbh
{
	my $self = shift;

	my $calling_package = ( ref( $self ) or $self );

	my $dbh = shift;


	{
		no strict "refs";
		${ $calling_package . "::_dbh" } = $dbh;
	}

}

42;
