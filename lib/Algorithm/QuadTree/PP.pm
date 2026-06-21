package Algorithm::QuadTree::PP;

use strict;
use warnings;
use Exporter qw(import);

use Scalar::Util qw(weaken);

our @EXPORT = qw(
	_AQT_init
	_AQT_deinit
	_AQT_addObject
	_AQT_addObjects
	_AQT_findObjects
	_AQT_delete
	_AQT_clear
);

use constant UNIQUE_RESULTS => 1;

# recursive method which adds levels to the quadtree
sub _addLevel
{
	my ($self, $depth, $parent, @coords) = @_;
	my $node = {
		PARENT => $parent,
		HAS_OBJECTS => 0,
		AREA => \@coords,
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

	$node->{OBJECTS} = [];

	return $node;
}

# this private method executes $code on every leaf node of the tree
# which is within the circular shape
sub _loopOnNodesInCircle
{
	my ($self, $finding, @coords) = @_;

	# avoid squaring the radius on each iteration
	my $radius_squared = $coords[2] ** 2;

	my @nodes;
	my @loopargs = $self->{ROOT};
	while (my $current = shift @loopargs) {
		next if $finding && !$current->{HAS_OBJECTS};

		my ($cxmin, $cymin, $cxmax, $cymax) = @{$current->{AREA}};

		my $cx = $coords[0] < $cxmin
			? $cxmin - $coords[0]
			: $coords[0] > $cxmax
				? $cxmax - $coords[0]
				: 0
		;

		my $cy = $coords[1] < $cymin
			? $cymin - $coords[1]
			: $coords[1] > $cymax
				? $cymax - $coords[1]
				: 0
		;

		# first check if obj overlaps current segment.
		next if $cx ** 2 + $cy ** 2
			> $radius_squared;

		$current->{HAS_OBJECTS} = 1 if !$finding;
		if ($current->{CHILDREN}) {
			push @loopargs, @{$current->{CHILDREN}};
		} else {
			# segment is a leaf and overlaps the obj
			push @nodes, $current;
		}
	}

	return \@nodes;
}

# this private method executes $code on every leaf node of the tree
# which is within the rectangular shape
sub _loopOnNodesInRectangle
{
	my ($self, $finding, @coords) = @_;

	my @nodes;
	my @loopargs = $self->{ROOT};
	while (my $current = shift @loopargs) {
		next if $finding && !$current->{HAS_OBJECTS};

		# first check if obj overlaps current segment.
		next if
			$coords[0] > $current->{AREA}[2] ||
			$coords[2] < $current->{AREA}[0] ||
			$coords[1] > $current->{AREA}[3] ||
			$coords[3] < $current->{AREA}[1];

		$current->{HAS_OBJECTS} = 1 if !$finding;
		if ($current->{CHILDREN}) {
			push @loopargs, @{$current->{CHILDREN}};
		} else {
			# segment is a leaf and overlaps the obj
			push @nodes, $current;
		}
	}

	return \@nodes;
}

# choose the right function based on argument count
# first argument is always $self, second is $finding, the rest are coords
sub _loopOnNodes
{
	goto \&_loopOnNodesInCircle if @_ == 5;
	goto \&_loopOnNodesInRectangle;
}

sub _batchInsert
{
	my ($self, $items) = @_;

	foreach my $item (@$items) {
		if (@$item == 4) {
			$item->[3] = $item->[3] ** 2;
		}
		elsif (@$item != 5) {
			die 'unknown batch insertion item with size ' . scalar @$item;
		}
	}

	my @nodes;
	my @next_loopargs = @{$self->{ROOT}{CHILDREN}};
	$self->{ROOT}{OBJECTS} = $items;
	$self->{ROOT}{HAS_OBJECTS} ||= @$items > 0;

	my $depth = 1;
	while (@next_loopargs) {
		++$depth;
		my @loopargs = @next_loopargs;
		@next_loopargs = ();
		my @parents;

		foreach my $current (@loopargs) {
			my $parent = $current->{PARENT};
			push @parents, $parent;

			my $objects = $current->{OBJECTS};
			my ($cxmin, $cymin, $cxmax, $cymax) = @{$current->{AREA}};
			my $found = 0;

			foreach my $object_and_coords (@{$parent->{OBJECTS}}) {
				# first check if obj overlaps current segment.
				if (@$object_and_coords == 5) {
					next if
						$object_and_coords->[1] > $cxmax ||
						$object_and_coords->[3] < $cxmin ||
						$object_and_coords->[2] > $cymax ||
						$object_and_coords->[4] < $cymin;
				}
				else {
					my $cx = $object_and_coords->[1] < $cxmin
						? $cxmin - $object_and_coords->[1]
						: $object_and_coords->[1] > $cxmax
							? $cxmax - $object_and_coords->[1]
							: 0
					;

					my $cy = $object_and_coords->[2] < $cymin
						? $cymin - $object_and_coords->[2]
						: $object_and_coords->[2] > $cymax
							? $cymax - $object_and_coords->[2]
							: 0
					;

					# first check if obj overlaps current segment.
					next if $cx * $cx + $cy * $cy
						> $object_and_coords->[3];
				}

				$found = 1;
				push @$objects, $object_and_coords;
			}

			if ($found) {
				$current->{HAS_OBJECTS} = 1;
				if ($current->{CHILDREN}) {
					push @next_loopargs, @{$current->{CHILDREN}}
				}
				else {
					my $backref = $self->{BACKREF};
					foreach my $object (@$objects) {
						$object = $object->[0];
						push @{$self->{BACKREF}{$object}}, $current;
					}
				}
			}
		}

		foreach my $parent (@parents) {
			@{$parent->{OBJECTS}} = ();
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

	for my $node (@{_loopOnNodes($self, 0, @coords)}) {
		push @{$node->{OBJECTS}}, $object;
		push @{$self->{BACKREF}{$object}}, $node;
	}
}

sub _AQT_addObjects
{
	my ($self, @items) = @_;

	_batchInsert($self, \@items);
}

sub _AQT_findObjects
{
	my ($self, @coords) = @_;

	# map returned nodes to an array containing all of
	# their objects
	my %hash;
	foreach my $node (@{_loopOnNodes($self, 1, @coords)}) {
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

	for my $node (@{$self->{BACKREF}{$object}}) {
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
		$current->{HAS_OBJECTS} = 0;

		if ($current->{CHILDREN}) {
			push @loopargs, @{$current->{CHILDREN}};
		} else {
			@{$current->{OBJECTS}} = ();
		}
	}

	$self->{BACKREF} = {};
}

1;

