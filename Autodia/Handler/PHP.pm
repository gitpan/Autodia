################################################################
# AutoDIA - Automatic Dia XML.   (C)Copyright 2001 A Trevena   #
#                                                              #
# AutoDIA comes with ABSOLUTELY NO WARRANTY; see COPYING file  #
# This is free software, and you are welcome to redistribute   #
# it under certain conditions; see COPYING file for details    #
################################################################
package Autodia::Handler::PHP;

require Exporter;

use strict;

use vars qw($VERSION @ISA @EXPORT);
use Autodia::Handler;
use Data::Dumper;

@ISA = qw(Autodia::Handler Exporter);

use Autodia::Diagram;

#---------------------------------------------------------------

#####################
# Constructor Methods

# new inherited from Handler

#------------------------------------------------------------------------
# Access Methods

# parse_file inherited from Handler

#-----------------------------------------------------------------------------
# Internal Methods

# _initialise inherited from Handler

sub _parse
  {
    my $self     = shift;
    my $fh       = shift;
    my $filename = shift;
    my $Diagram  = $self->{Diagram};
    my $incode = 0;
    my $inclass = 0;
    my $infunc = 0;
    my $inclassparen = 0;
    my $infuncparen = 0;
    my $incommentcount = 0;
    my $incomment = 0;

    my $Class;

    $self->{pod} = 0;

    # parse through file looking for stuff
    foreach my $line (<$fh>)
      {
	chomp $line;
	if ($self->_discard_line($line)) { next; }

	my $commentup = $line =~ tr/\/\*/\/\*/;
	my $commentdown = $line =~ tr/\*\//\*\//;
	$incommentcount = $commentup - $commentdown;
	if ($incommentcount > 0) {
	  $incomment = 1;
	} else {
	  $incomment = 0;
	}
	next if $incomment;


	my $up = $line =~ tr/\{/\{/;
	my $down = $line =~ tr/\}/\}/;
        $inclassparen = $inclassparen + $up - $down if ($inclass > 0);
	$infuncparen = $infuncparen + $up - $down if ($infunc > 0);
	$inclass = 0 if ($inclassparen < 1);
	$infunc = 0 if ($infuncparen < 1);

	print "$inclassparen : $inclass $infuncparen : $infunc \n";

	if ($line =~ /^\s*class\s+([^\s\(\)\{\}]+)/) {
	  my $className = $1;
	  $inclass = 1;
	  $inclassparen = $up - $down;
	  print "Classname: $className matched on:\n$line\n";
	  $Class = Autodia::Diagram::Class->new($className);
	  # add to diagram
	  $Diagram->add_class($Class);
	  if ($line =~ /.*extends\s+(\S+)/) {
	    my $superclass = $1;
	    $self->_is_package(\$Class, $filename);
	    my @superclasses = split(" ", $superclass);

	    foreach my $super (@superclasses) # WHILE_SUPERCLASSES
	      {
		# discard if stopword
		next if ($super =~ /(?:exporter|autoloader)/i);
		# create superclass
		my $Superclass = Autodia::Diagram::Superclass->new($super);
		# add superclass to diagram
		my $exists_already = $Diagram->add_superclass($Superclass);
		if (ref $exists_already)
		  {
		    $Superclass = $exists_already;
		  }
		# create new inheritance
		my $Inheritance = Autodia::Diagram::Inheritance->new($Class, $Superclass);
		# add inheritance to superclass
		$Superclass->add_inheritance($Inheritance);
		# add inheritance to class
		$Class->add_inheritance($Inheritance);
		# add inheritance to diagram
		$Diagram->add_inheritance($Inheritance);
	      }
	  }

	}

	if ($line =~ /^\s*(include|require)\s+\(*\"*([^\"\)]+)\"*\)*/) {
	  my $componentName = $2;

	  print "componentname: $componentName matched on:\n$line\n";
	  # discard if stopword
	  next if ($componentName =~ /(strict|vars|exporter|autoloader|data::dumper)/i);

	  # check package exists before doing stuff
	  $self->_is_package(\$Class, $filename);

	  # create component
	  my $Component = Autodia::Diagram::Component->new($componentName);
	  # add component to diagram
	  my $exists = $Diagram->add_component($Component);

	  # replace component if redundant
	  if (ref $exists)
	    {
	      $Component = $exists;
	    }
	  # create new dependancy
	  my $Dependancy = Autodia::Diagram::Dependancy->new($Class, $Component);
	  # add dependancy to diagram
	  $Diagram->add_dependancy($Dependancy);
	  # add dependancy to class
	  $Class->add_dependancy($Dependancy);
	  # add dependancy to component
	  $Component->add_dependancy($Dependancy);
	}

	if ($line =~ /^.*=\s*new\s+([^\s\(\)\{\}\;]+)/) {
	  my $componentName = $1;

	  print "componentname: $componentName matched on:\n$line\n";
	  # discard if stopword
	  next if ($componentName =~ /(strict|vars|exporter|autoloader|data::dumper)/i);

	  # check package exists before doing stuff
	  $self->_is_package(\$Class, $filename);

	  # create component
	  my $Component = Autodia::Diagram::Component->new($componentName);
	  # add component to diagram
	  my $exists = $Diagram->add_component($Component);

	  # replace component if redundant
	  if (ref $exists)
	    {
	      $Component = $exists;
	    }
	  # create new dependancy
	  my $Dependancy = Autodia::Diagram::Dependancy->new($Class, $Component);
	  # add dependancy to diagram
	  $Diagram->add_dependancy($Dependancy);
	  # add dependancy to class
	  $Class->add_dependancy($Dependancy);
	  # add dependancy to component
	  $Component->add_dependancy($Dependancy);
	}


	if ($line =~ /^\s*var\s+\$([^\s=\{\}\(\)]+)/) {
	    last unless $inclass;
	    my $attribute_name = $1;
	    my $default;
	    $attribute_name =~ s/(.*);/$1/g;
	    if ($line =~ /^\s*var\s+\$(\S+)\s*=\s*(.*)/) {
	      $default = $2;
	      $default =~ s/(.*);/$1/;
	      $default =~ s/(.*)\/\/.*/$1/;
	      $default =~ s/(.*)\/\*.*/$1/;
	    }
	    print "Attr found: $attribute_name = $default\n$line\n";
	    my $attribute_visibility = ( $attribute_name =~ m/^\_/ ) ? 1 : 0;
	    $Class->add_attribute({
				   name => $attribute_name,
				   visibility => $attribute_visibility,
				   value => $default,
				  });

	}

	# if line contains sub then parse for method data
	if ($line =~ /^\s*function\s+([^\s\(\)]+)/)
	  {
	    unless ($inclass) {
	      my @newclass = reverse split (/\//, $filename);

	      $Class = Autodia::Diagram::Class->new($newclass[0]);
	      # add to diagram
	      $Diagram->add_class($Class);
	      $inclass = 1;
	      $inclassparen = $up - $down;
	    }
	      my $subname = $1;
	      $infunc = 1;
	      $infuncparen = $up - $down;
	      print "Function found: $subname\n$line\n";
	      my %subroutine = ( "name" => $subname, );
	      $subroutine{"visibility"} = ($subroutine{"name"} =~ m/^\_/) ? 1 : 0;
	      # check for explicit parameters
	      if ($line =~ /function\s+(\S+)\s*\((.+?)\)/) 
	      {
		  my $parameter_string = $2;

		  $parameter_string =~ s/\s*//g;
		  $parameter_string =~ s/\$//g;
		  print "Params: $parameter_string\n";
		  my @parameters1 = split(",",$parameter_string);
		  my @parameters;
		  foreach my $par (@parameters1) {
		    my ($name, $val) = split (/=/, $par);
		    $val =~ s/\"//g;
		    my %temphash = (
				 Name => $name,
				 Val => $val,
				);
		    push @parameters, \%temphash;

		  }
		  $subroutine{"Param"} = \@parameters;
		}
	    print Dumper(\%subroutine);
	    $Class->add_operation(\%subroutine);
	  }

   }

    $self->{Diagram} = $Diagram;

    return;
  }

sub _discard_line
{
  my $self    = shift;
  my $line    = shift;
  my $discard = 0;

  SWITCH:
    {
	if ($line =~ m/^\s*$/) # if line is blank or white space discard
	{
	    $discard = 1;
	    last SWITCH;
	}

	if ($line =~ /^\s*\/\//) # if line is a comment discard
	{
	    $discard = 1;
	    last SWITCH;
	}

	if ($line =~ /^\s*\=head/) # if line starts with pod syntax discard and flag with $pod
	{
	    $self->{pod} = 1;
	    $discard = 1;
	    last SWITCH;
	}

	if ($line =~ /^\s*\=cut/) # if line starts with pod end syntax then unflag and discard
	{
	    $self->{pod} = 0;
	    $discard = 1;
	    last SWITCH;
	}

	if ($self->{pod} == 1) # if line is part of pod then discard
	{
	    $discard = 1;
	    last SWITCH;
	}
    }
    return $discard;
}

####-----

sub _is_package
  {
    my $self    = shift;
    my $package = shift;
    my $Diagram = $self->{Diagram};

    unless(ref $$package)
       {
	 my $filename = shift;

	 # create new class with name
	 $$package = Autodia::Diagram::Class->new($filename);
	 # add class to diagram
	 $Diagram->add_class($$package);
       }

    return;
  }

####-----

1;

###############################################################################

=head1 NAME

HandlerPHP.pm - AutoDia handler for PHP

=head1 INTRODUCTION

HandlerPHP is registered in the Autodia.pm module, which contains a hash of language names and the name of their respective language - in this case:

%language_handlers = ( .. ,
		       php => "HandlerPHP",
		       .. );

%patterns = ( .. ,
	      php => \%php,
              .. );

my %php = (
             regex      => '\w+\.php$',
             wildcards => [
                        "php",
                                ],
                        );


=head1 CONSTRUCTION METHOD

use HandlerPHP;

my $handler = HandlerPHP->New(\%Config);

This creates a new handler using the Configuration hash to provide rules selected at the command line.

=head1 ACCESS METHODS

$handler->Parse(filename); # where filename includes full or relative path.

This parses the named file and returns 1 if successful or 0 if the file could not be opened.

$handler->output(); # any arguments are ignored.

This outputs the output file according to the rules in the %Config hash passed at initialisation of the object and the template.

=cut
