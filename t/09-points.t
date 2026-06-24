use strict;
use warnings;

BEGIN { $ENV{ALGORITHM_QUADTREE_BACKEND} = 'Algorithm::QuadTree::PP'; }

use Test::More;
use Algorithm::QuadTree;

use lib 't/lib';
use QuadTreeUtils;

$QuadTreeUtils::DEPTH = 2;

my $qt = Algorithm::QuadTree->new(
	-xmin  => 0,
	-xmax  => AREA_SIZE,
	-ymin  => 0,
	-ymax  => AREA_SIZE,
	-depth => $QuadTreeUtils::DEPTH
);

# start testing

subtest 'point should be added to one zone' => sub {
	$qt->add('point', 4, 4);

	my $top_left = $qt->getEnclosedObjects(
		zone_start(0),
		zone_start(0),
		zone_end(0),
		zone_end(0),
	);

	check_array $top_left, ['point'];

	my $top_right = $qt->getEnclosedObjects(
		zone_start(1),
		zone_start(0),
		zone_end(1),
		zone_end(0),
	);

	check_array $top_right, [];

	my $bottom_left = $qt->getEnclosedObjects(
		zone_start(0),
		zone_start(1),
		zone_end(0),
		zone_end(1),
	);

	check_array $bottom_left, [];

	my $bottom_right = $qt->getEnclosedObjects(
		zone_start(1),
		zone_start(1),
		zone_end(1),
		zone_end(1),
	);

	check_array $bottom_right, [];
};

subtest 'point should be added to all zones' => sub {
	$qt->clear;
	$qt->add('point', 5, 5);

	my $top_left = $qt->getEnclosedObjects(
		zone_start(0),
		zone_start(0),
		zone_end(0),
		zone_end(0),
	);

	check_array $top_left, ['point'];

	my $top_right = $qt->getEnclosedObjects(
		zone_start(1),
		zone_start(0),
		zone_end(1),
		zone_end(0),
	);

	check_array $top_right, ['point'];

	my $bottom_left = $qt->getEnclosedObjects(
		zone_start(0),
		zone_start(1),
		zone_end(0),
		zone_end(1),
	);

	check_array $bottom_left, ['point'];

	my $bottom_right = $qt->getEnclosedObjects(
		zone_start(1),
		zone_start(1),
		zone_end(1),
		zone_end(1),
	);

	check_array $bottom_right, ['point'];
};

subtest 'area to search should work properly for point shapes' => sub {
	$qt->clear;
	$qt->add('circle', 4, 4, 0.9);

	my $search = $qt->getEnclosedObjects(4.89, 4);

	check_array $search, ['circle'];
};

done_testing;

