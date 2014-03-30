#!/usr/bin/env perl

use Modern::Perl;

use Carp;
use Data::Dumper;
use Getopt::Long;
use GraphViz2;
use Log::Any qw($log);
use Log::Any::Adapter;
use Pod::Usage;

package main;

my @files;
my @formats;
my $help      = 0;
my $legend    = 0;
my $outname   = 'ant';
my @projects;
my $rankdir   = 'LR';
my $splines   = 'ortho';
my $verbosity = 1;

Getopt::Long::Configure( qw(
                             bundling
                             permute
                         ) );
GetOptions(
  '<>'           => sub { push @files, @_; },
  'formats|f=s'  => \@formats,
  'help|h|?'     => \$help,
  'legend!'      => \$legend,
  'out|o=s'      => \$outname,
  'quiet|q'      => sub { $verbosity = 0; },
  'rankdir|r=s'  => \$rankdir,
  'splines|s=s'  => \$splines,
  'verbosity|v+' => \$verbosity,
) or do {
  $log->critical( 'Failed to parse command line options' );
  exit 1;
};

Log::Any::Adapter->set(
  'ScreenColoredLevel',
  colors => {
    trace     => 'magenta',
    # debug     => (none, terminal default)
    info      => 'green',
    notice    => 'blue',
    warning   => 'yellow',
    error     => 'red',
    critical  => 'red',
    alert     => 'red',
    emergency => 'red',
  },
  min_level => (
    'critical',
    'error',
    'warning',
    'info',
    'debug',
    'trace',
  )[ ( $verbosity > 3 ) ? 5 : $verbosity + 2 ],
  stderr    => 0,
);

my $usage     = {
  -exitval => 0,
  -verbose => $verbosity,
};

unless ( $help or @files ) {
  $usage->{-verbose} = 0;
  $help = 1;
  $usage->{-exitval} = 1;
  $log->error( 'No file specified, nothing to do (use `--help\' for more information)' );
}

pod2usage( $usage ) if $help;

sub node_name {
  my ( $file, $target ) = @_;
  return '---'.$file.'---'.$target;
}

################################################################################

package Ant::Project;

use Log::Any qw($log);
use Moose;

with 'XML::Rabbit::RootNode';

has 'name'    => (
  isa         => 'Str',
  traits      => [ qw( XPathValue ) ],
  xpath_query => '/project/@name',
);
has 'basedir' => (
  isa         => 'Str',
  traits      => [ qw( XPathValue ) ],
  xpath_query => '/project/@basedir',
);
has 'default' => (
  isa         => 'Str',
  traits      => [ qw( XPathValue ) ],
  xpath_query => '/project/@default',
);

has 'targets' => (
  isa         => 'ArrayRef[Ant::Target]',
  traits      => [ 'XPathObjectList' ],
  xpath_query => '/project/target',
);

sub make_subgraph {
  my ( $self, $graph ) = @_;

  $log->info( "Drawing project `".$self->name."', from file `".$self->_file."'" );

  $graph->push_subgraph(
    name  => 'cluster_' . $self->_file,
    graph => {
      label   => $self->name . '\n' . $self->_file,
      bgcolor => 'white',
    },
  );

  foreach my $target ( @{$self->targets} ) {
    $target->make_node( $self, $graph )
      if ( ref $target eq 'Ant::Target' );
  }

  $graph->pop_subgraph();

  return;
}

sub file_dependencies {
  my ( $self ) = @_;

  my @r = ();

  foreach my $target ( $self->targets ) {
    @r = ( @r, @{$target->file_dependencies} )
      if ( ref $target eq 'Ant::Target' );
  }

  return @r;
}

no Moose;
__PACKAGE__->meta->make_immutable();
1;

################################################################################

package Ant::Target;

use Log::Any qw($log);
use XML::Rabbit;

has 'name'    => (
  isa         => 'Str',
  traits      => [ qw( XPathValue ) ],
  xpath_query => './@name',
);
has 'depends' => (
  isa         => 'Str',
  traits      => [ qw( XPathValue ) ],
  xpath_query => './@depends',
);

# These are *not* all the tasks, just the ones we want for now
has 'tasks' => (
  isa_map     => {
    './/ant'     => 'Ant::Task',
    './/antcall' => 'Ant::Task',
    './/subant'  => 'Ant::Task',
  },
  traits      => [qw( XPathObjectList )],
  xpath_query => join( '|', qw(
                                .//ant
                                .//antcall
                                .//subant
                            ) ),
);

sub make_node {
  my ( $self, $parent, $graph ) = @_;

  $log->debug( "\ttarget: `".$self->name."'" );

  my $style = '';
  if ( defined $parent->default and $self->name eq $parent->default ) {
    $log->debug( "\t\tdefault" );
    $style = 'bold';
  }
  $graph->add_node(
    name  => ::node_name( $parent->_file, $self->name ),
    label => $self->name,
    style => $style,
  );

  # Dependencies
  if ( defined $self->depends ) {
    foreach my $dependency ( split( /\s*,+\s*/, $self->depends ) ) {
      $log->debug( "\t\tdepends: `".$self->name."' -> `$dependency'" );
      $graph->add_edge(
        from => ::node_name( $parent->_file, $self->name ),
        to   => ::node_name( $parent->_file, $dependency ),
      );
    }
  }

  # Calls
  if ( defined $self->tasks ) {
    foreach my $task ( $self->tasks ) {
      $task = @{$task}[0];
      if ( defined $task and ref $task eq 'Ant::Task' ) {
        #say "call: ".::Dumper( $task );
        my $other_target = $task->target;
        if ( defined $other_target ) {
          my $other_file = $task->file;
          $other_file = $parent->_file unless defined $other_file and $other_file ne '';
          $log->debug( "\t\tcalls: `".$self->name."' -> `$other_target' (in file `$other_file', using `".$task->node->nodeName."')" );
          $graph->add_edge(
            from  => ::node_name( $parent->_file, $self->name ),
            to    => ::node_name( $other_file, $other_target ),
            label => $task->node->nodeName,
            style => 'dashed',
          );
        }
      }
    }
  }

  return;
}

sub file_dependencies {
  my ( $self ) = @_;

  my @r = ();

  foreach my $task ( $self->tasks ) {
    push @r, $task->file_dependency;
  }

  return @r;
}

finalize_class();

################################################################################

package Ant::Task;
use XML::Rabbit;

has 'target'  => (
  isa         => 'Str',
  traits      => [ qw( XPathValue ) ],
  xpath_query => './@target',
);
has 'file'    => (
  isa         => 'Str',
  traits      => [ qw( XPathValue ) ],
  xpath_query => './@file',
);

finalize_class();

################################################################################

package main;

push @formats, 'pdf' unless ( @formats );
@formats = split(/,/,join(',',@formats));

$log->debug( "Files:\n\t" . join '\n\t', @files );

my ( $graph ) = GraphViz2->new(
  edge   => {
    color => 'black',
  },
  global => {
    directed => 1,
  },
  graph  => {
    bgcolor => 'gray25',
    margin  => 0,
    rankdir => $rankdir,
    splines => $splines,
  },
  node   => {
    shape     => 'box',
    color     => 'black',
    # style     => 'filled',
    fillcolor => 'gray75',
  },
);

foreach my $infile ( @files ) {
  $log->debug( "Parsing file: `$infile'" );
  push @projects, Ant::Project->new( file => $infile->{name} );
}

foreach my $project ( @projects ) {
  $project->make_subgraph( $graph );
}

if ( $legend ) {
  my $t1a = '_legend_target_1A';
  my $t1b = '_legend_target_1B';
  my $t2a = '_legend_target_2A';
  my $t2b = '_legend_target_2B';

  $graph->push_subgraph(
    name  => 'cluster___legend',
    graph => {
      label   => 'Legend',
      bgcolor => 'white',
      rankdir => 'LR',
    },
  );

  $graph->add_node(
    name  => $t1a,
    label => 'target A',
  );
  $graph->add_node(
    name  => $t1b,
    label => 'target B',
  );
  $graph->add_edge(
    from  => $t1a,
    to    => $t1b,
    label => 'A depends on B',
  );

  $graph->add_node(
    name  => $t2a,
    label => 'target A',
  );
  $graph->add_node(
    name  => $t2b,
    label => 'target B',
  );
  $graph->add_edge(
    from  => $t2a,
    to    => $t2b,
    label => 'A calls B',
    style => 'dashed',
  );

  $graph->add_node(
    name  => '_legend_target_default',
    label => 'default target',
    style => 'bold',
  );

  $graph->pop_subgraph();
}

foreach my $format ( @formats ) {
  my $outfile = "$outname.$format";
  $graph->run(
    format      => $format,
    output_file => $outfile,
  ) or carp "Failed to write file `$outfile'!";
  $log->info( "Wrote file: `$outfile'" );
}

exit 0;

__END__

=pod

=encoding utf8

=head1 NAME

L<ant2gv.pl>

=head1 VERSION

0.3

=head1 USAGE

ant2gv.pl [options] file...

=head1 DESCRIPTION

Draws graphs of Ant target dependencies (and calls), using Graphviz.

=head1 REQUIRED ARGUMENTS

At least one Ant file must be specified.

=head1 OPTIONS

=over

=item B<--help|-h|-?>

Prints the help text and exits.

=item B<--verbose|-v>

Increase verbosity.  Can be used multiple times for more output, e.g:

-vvv

When used together with B<--help> prints more help.

=item B<--quiet|-q>

Suppress all output that is not errors or warnings.

=item B<--out|-o>

Specifies the base of the names of the output files.  Together with its format
(see C<--format>) each file's name is constructed as C<E<lt>base
nameE<gt>.E<lt>formatE<gt>>.  E.g. with:

--out graph --format svg,png

you get the files F<graph.svg> and F<graph.svg>.

Default: C<ant>

=item B<--format|-f E<lt>format[,format[...]]E<gt>>

Specifies the output formats.  Default is C<pdf>.  Multiple formats can be
specified as a comma-separated list, as multiple uses of the option or a
combination of the two.  Thus the following are equivalent:

--format pdf,png,svg
--format pdf --format png --format svg
--format pdf,png --format svg

=item B<--legend|--no-legend>

Turn on or off the inclusion of a legend.

=item B<--rankdir|-r E<lt>directionE<gt>>

Set the direction of the graph.  Possible values are the same as the C<rankdir>
Graphviz attribute, e.g:

=over

=item

C<LR> (B<L>eft-to-B<R>ight)

=item

C<RL> (B<R>ight-to-B<L>eft)

=item

C<TB> (B<T>op-to-B<B>ottom)

=item

C<BT> (B<B>ottom-to-B<T>op)

=back

E.g: If the direction is `LR', that means `B<L>eft-to-B<R>ight', which in turn
means that if target `A' depends on a target `B', then `A' will be drawn to the
left of `B' (the arrow going left-to-right).

See L<the Graphviz documentation for
C<rankdir>|http://www.graphviz.org/content/attrs #drankdir>.

Default: C<LR>

=item B<--splines|-s E<lt>styleE<gt>>

Set the way lines are drawn.  Possible values are the same as the C<splines>
Graphviz attribute, e.g:

=over

=item

C<none>

=item

C<line>

=item

C<polyline>

=item

C<curved>

=item

C<ortho>

=item

C<spline>

=back

See L<the Graphviz documentation for
C<splines>|http://www.graphviz.org/content/attrs #dsplines>.

Default: C<ortho>

=back

=head1 RETURN VALUE

Zero if everything went well.  Non-zero means something went wrong.  The output
should give you more details.

=head1 EXAMPLES

=head2 Generate a simple graph for a single Ant file:

ant2gv.pl build.xml

=head1 BUGS

=over

=item

Ant calls without explicit files appear somewhat strange in the graph.

=back

=head1 AUTHOR

Theo `Biffen' Willows

=head1 HISTORY

=head2 0.1

Initial version.

=head2 0.2

=over

=item

Multi-file support.

=item

Legend.  Can be turned on or off (C<--legend> option).

=item

Minor bug fixes.

=back

=head2 0.3

=over

=item

Better logging.

=item

Ability to specify output file name(s) (C<--out> option).

=back

=head1 COPYRIGHT AND LICENSE

Copyright 2013 Theo `Biffen' Willows

This library is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

=over

=item

L<Apache Ant|http://ant.apache.org>

=item

L<Graphviz|http://www.graphviz.org>

=back

=cut
