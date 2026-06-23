package Algorithm::QuadTree::PP;

use strict;
use warnings;
use Exporter qw(import);

use Scalar::Util qw(weaken);

our @EXPORT = qw(
	_AQT_init
	_AQT_deinit
	_AQT_addObject
	_AQT_findObjects
	_AQT_delete
	_AQT_clear
);

use constant UNIQUE_RESULTS => 1;

use constant SHAPE_CIRCLE => 1;
use constant SHAPE_RECTANGLE => 2;

# recursive method which adds levels to the quadtree
sub _addLevel
{
	my ($self, $depth, $parent, @coords) = @_;
	my $node = {
		PARENT => $parent,
		OBJECTS => [],
		HAS_OBJECTS => 0,
		AREA => \@coords,
		DEPTH => $depth,
	};

	weaken $node->{PARENT} if $parent;

	if ($depth < $self->{DEPTH}) {
		my ($xmin, $ymin, $xmax, $ymax) = @coords;
		my $xmid = $xmin + ($xmax - $xmin) / 2;
		my $ymid = $ymin + ($ymax - $ymin) / 2;
		$depth += 1;

		# segment in the following order:
		# top left, top right, bottom left, bottom right
		$node->{CHILDREN} = [
			_addLevel($self, $depth, $node, $xmin, $ymid, $xmid, $ymax),
			_addLevel($self, $depth, $node, $xmid, $ymid, $xmax, $ymax),
			_addLevel($self, $depth, $node, $xmin, $ymin, $xmid, $ymid),
			_addLevel($self, $depth, $node, $xmid, $ymin, $xmax, $ymid),
		];
	}

	return $node;
}

# this private method executes $code on every leaf node of the tree
# which is within the circular shape
sub _loopOnNodes
{
	my ($self, $finding, $shape) = @_;
	my $shape_type = @{$shape} == 4 ? SHAPE_RECTANGLE : SHAPE_CIRCLE;

	# pre-calculate some of the circle characteristics
	if (@{$shape} == 3) {
		my $contained_radius = $shape->[2] / sqrt(2);

		# inner box for this circle - fully contained within the circle
		unshift @{$shape}, (
			$shape->[0] - $contained_radius,
			$shape->[1] - $contained_radius,
			$shape->[0] + $contained_radius,
			$shape->[1] + $contained_radius,
		);

		# avoid squaring the radius on each iteration
		$shape->[6] *= $shape->[6];
	}

	my @coords = @{$shape};

	my @nodes;
	my @loopargs = $self->{ROOT};
	my @loopargs_contained;
	my $fully_contained;
	my ($area, $cx, $cy);
	my $current;

	while ($current = shift @loopargs) {
		next if $finding && !$current->{HAS_OBJECTS};
		$area = $current->{AREA};

		$fully_contained =
			$coords[0] <= $area->[0] &&
			$coords[2] >= $area->[2] &&
			$coords[1] <= $area->[1] &&
			$coords[3] >= $area->[3];

		if (!$fully_contained) {
			if ($shape_type == SHAPE_CIRCLE) {
				$cx = $coords[4] < $area->[0]
					? $area->[0] - $coords[4]
					: $coords[4] > $area->[2]
						? $area->[2] - $coords[4]
						: 0
				;

				$cy = $coords[5] < $area->[1]
					? $area->[1] - $coords[5]
					: $coords[5] > $area->[3]
						? $area->[3] - $coords[5]
						: 0
				;

				next if $cx ** 2 + $cy ** 2
					> $coords[6];
			}
			elsif ($shape_type == SHAPE_RECTANGLE) {
				next if
					$coords[0] > $area->[2] ||
					$coords[2] < $area->[0] ||
					$coords[1] > $area->[3] ||
					$coords[3] < $area->[1];
			}
		}

		if ($finding) {
			push @nodes, $current;
			next unless $current->{CHILDREN};

			if ($fully_contained) {
				push @loopargs_contained, @{$current->{CHILDREN}};
			}
			else {
				push @loopargs, @{$current->{CHILDREN}};
			}
		}
		else {
			$current->{HAS_OBJECTS} = 1;
			if ($fully_contained || !$current->{CHILDREN}) {
				push @nodes, $current;
			}
			else {
				push @loopargs, @{$current->{CHILDREN}};
			}
		}
	}

	if ($finding) {
		while (my $current = shift @loopargs_contained) {
			next if !$current->{HAS_OBJECTS};

			push @nodes, $current;
			push @loopargs_contained, @{$current->{CHILDREN}}
				if $current->{CHILDREN};
		}
	}

	return \@nodes;
}

sub _clearHasObjects
{
	my $node = shift;

	if ($node->{CHILDREN}) {
		for my $child (@{$node->{CHILDREN}}) {
			return if $child->{HAS_OBJECTS};
		}
	}

	$node->{HAS_OBJECTS} = 0;
	if ($node->{PARENT}) {
		_clearHasObjects($node->{PARENT});
	}
}

sub _AQT_init
{
	my $obj = shift;

	$obj->{BACKREF} = {};
	$obj->{ROOT} = _addLevel(
		$obj,
		1,     #current depth
		undef, # parent - none
		$obj->{XMIN},
		$obj->{YMIN},
		$obj->{XMAX},
		$obj->{YMAX},
	);
}

sub _AQT_deinit
{
	# do nothing in PP implementation
}

sub _AQT_addObject
{
	my ($self, $object, @coords) = @_;
	pop @coords while @coords > 4;
	my $shape = \@coords;

	my $nodes = _loopOnNodes($self, 0, $shape);
	for my $node (@$nodes) {
		push @{$node->{OBJECTS}}, $object;
	}

	$self->{BACKREF}{$object} = $shape
		unless @$nodes == 0;
}

sub _AQT_findObjects
{
	my ($self, @coords) = @_;
	pop @coords while @coords > 4;

	# map returned nodes to an array containing all of
	# their objects
	my %hash;
	foreach my $node (@{_loopOnNodes($self, 1, \@coords)}) {
		foreach my $object (@{$node->{OBJECTS}}) {
			$hash{$object} = $object;
		}
	}

	return [values %hash];
}

sub _AQT_delete
{
	my ($self, $object) = @_;

	return unless exists $self->{BACKREF}{$object};

	for my $node (@{_loopOnNodes($self, 1, $self->{BACKREF}{$object})}) {
		@{$node->{OBJECTS}} = grep {$_ ne $object} @{$node->{OBJECTS}};
		_clearHasObjects($node) if !@{$node->{OBJECTS}};
	}

	delete $self->{BACKREF}{$object};
}

sub _AQT_clear
{
	my ($self) = @_;

	my @loopargs = $self->{ROOT};
	while (my $current = shift @loopargs) {
		next unless $current->{HAS_OBJECTS};

		@{$current->{OBJECTS}} = ();
		$current->{HAS_OBJECTS} = 0;

		if ($current->{CHILDREN}) {
			push @loopargs, @{$current->{CHILDREN}};
		}
	}

	%{$self->{BACKREF}} = ();
}

1;

