#
# Copyright (c) 2002 Danny Van de Pol - Alcatel Telecom Belgium
# danny.vandepol@alcatel.be
#
# Free usage under the same Perl Licence condition.
#

package Math::Geometry::Planar;

$VERSION   = '1.16';

use vars qw(
            $VERSION
            @ISA
            @EXPORT
            @EXPORT_OK
            $precision
           );

use strict;
#use Math::Geometry::Planar::GPC;
#use Math::Geometry::Planar::Offset;
use Carp;
use POSIX;

$precision = 7;

require Exporter;
@ISA       = qw(Exporter);
@EXPORT    = qw(
                SegmentLength Determinant DotProduct CrossProduct
                TriangleArea Colinear
                SegmentIntersection LineIntersection RayIntersection
                SegmentLineIntersection RayLineIntersection
                SegmentRayIntersection
                Perpendicular PerpendicularFoot
                DistanceToLine DistanceToSegment
                Gpc2Polygons GpcClip
                CircleToPoly ArcToPoly CalcAngle
               );
@EXPORT_OK = qw($precision);

=pod

=head1 NAME

Math::Geometry::Planar - A collection of planar geometry functions

=head1 SYNOPSIS

 use Math::Geometry::Planar;
 $polygon = Math::Geometry::Planar->new; creates a new polygon object;
 $contour = Math::Geometry::Planar->new; creates a new contour object;

=head4 Formats

A point is a reference to an array holding the x and y coordinates of the point.

 $point = [$x_coord,$y_coord];

A polygon is a reference to an (ordered) array of points.  The first point is the
begin and end point of the polygon. The points can be given in any direction
(clockwise or counter clockwise).

A contour is a reference to an array of polygons.  By convention, the first polygon
is the outer shape, all other polygons represent holes in the outer shape.  The outer
shape must enclose all holes !
Using this convention, the points can be given in any direction, however, keep
in mind that some functions (e.g. triangulation) require that the outer polygons
are entered in counter clockwise order and the inner polygons (holes) in clock
wise order.  The points, polygons, add_polygons methods will automatically set the
right order of points.
No points can be assigned to an object that already has polygons assigned to and
vice versa.

 $points = [[$x1,$y1],[$x2,$y2], ... ];
 $polygon->points($points);                    # assign points to polygon object
 $points1 = [[$x1,$y1],[$x2,$y2], ... ];
 $points2 = [[ax1,by1],[ax2,by2], ... ];
 $contour->polygons([$points1,$points2, ...]); # assign polgyons to contour object

=head1 METHODS

The available methods are:

=head4 $polygon->points(arg);

Returns the polygon points if no argument is entered.
If the argument is a refence to a points array, sets the points for a polygon object.

=head4 $contour->polygons(arg);

Returns the contour polygons if no argument is entered.
If the argument is a refence to a polygons array, sets the polygons for a contour object.

=head4 $contour->num_polygons;

Returns the total number of polygons in the contour.

=head4 $contour->add_polygons(arg);

Adds a list of polygons to a contour object (if the contour object doesn't have any
polygons yet, the very first polygon reference from the list is used as the outer
shape).  Returns the total number of polygons in the contour.

=head4 $contour->get_polygons(arg_1,arg_2, ... );

Returns a list of polygons where each element of the list corresponds to the polygon
at index arg_x - starting at 0, the outer shape. If the index arg_x is out of range,
the corresponding value in the result list wil be undefined.  If no argument is
entered, a full list of all polygons is returned. Please note that this method returns
a list rather then a reference.

=head4 $polygon->cleanup;

Remove colinear points from the polygon/contour.

=head4 $polygon->isconvex;

Returns true if the polygon/contour is convex. A contour is considered to be convex if
the outer shape is convex.

=head4 $polygon->issimple;

Returns true if the polygon/contour is simple.  A contour is considered to be simple if
all it's polygons are simple.

=head4 $polygon->perimeter;

Returns the perimeter of the polygon/contour. The perimeter of a contour is the perimeter
of the outer shape.

=head4 $polygon->area;

Returns the signed area of the polygon/contour (positive if the points are in counter
clockwise order). The area of a contour is the area of the outer shape minus the sum
of the area of the holes.

=head4 $polygon->centroid;

Returns the centroid (center of gravity) of the polygon/contour.

=head4 $polygon->isinside($point);

Returns true if point is inside the polygon/contour (a point is inside a contour if
it is inside the outer polygon and not inside a hole).

=head4 $polygon->rotate($angle,$center);

Returns polygon/contour rotated $angle (in radians) around $center.
If no center is entered, rotates around the origin.

=head4 $polygon->move($dx,$dy);

Returns polygon/contour moved $dx in x direction and $dy in y direction.

=head4 $polygon->mirrorx($center);

Returns polygon/contour mirrored in x direction
with (vertical) axis of reflection through point $center.
If no center is entered, axis is the Y-axis.

=head4 $polygon->mirrory($center);

Returns polygon/contour mirrored in y direction
with (horizontal) axis of reflection through point $center.
If no center is entered, axis is the X-axis.

=head4 $polygon->mirror($axos);

Returns polygon mirrored/contour along axis $axis (= array with 2 points defining
axis of reflection).

=head4 $polygon->scale($csale,$center);

Returns polygon/contour scaled by a factor $scale, center of scaling is $scale.
If no center is entered, center of scaling is the origin.

=head4 $polygon->bbox;

Returns the polygon's/contour's bounding box.

=head4 $polygon->minrectangle;

Returns the polygon's/contour's minimal (area) enclosing rectangle.

=head4 $polygon->convexhull;

Returns a polygon representing the convex hull of the polygon/contour.

=head4 $polygon->convexhull2;

Returns a polygon representing the convex hull of an arbitrary set of points
(works also on a contour, however a contour is a set of polygons and polygons
are ordered sets of points so the method above will be faster)

=head4 $polygon->triangulate;

Triangulates a polygon/contour based on Raimund Seidel's algorithm:
'A simple and fast incremental randomized algorithm for computing trapezoidal
decompositions and for triangulating polygons'
Returns a list of polygons (= the triangles)

=head4 $polygon->offset_polygon($distance);

Returns reference to an array of polygons representing the original polygon
offsetted by $distance

=head4 $polygon->convert2gpc;

Converts a polygon/contour to a gpc structure and returns the resulting gpc structure

=head1 EXPORTS

=head4 SegmentLength[$p1,$p2];

Returns the length of the segment (vector) p1p2

=head4 Determinant(x1,y1,x2,y2);

Returns the determinant of the matrix with rows x1,y1 and x2,y2 which is x1*y2 - y1*x2

=head4 DotProduct($p1,$p2,$p3,$p4);

Returns the vector dot product of vectors p1p2 and p3p4
or the dot product of p1p2 and p2p3 if $p4 is ommited from the argument list

=head4 CrossProduct($p1,$p2,$p3);

Returns the vector cross product of vectors p1p2 and p1p3

=head4 TriangleArea($p1,$p2,$p3);

Returns the signed area of the triangle p1p2p3

=head4 Colinear($p1,$p2,$p3);

Returns true if p1,p2 and p3 are colinear

=head4 SegmentIntersection($p1,$p2,$p3,$p4);

Returns the intersection point of segments p1p2 and p3p4,
false if segments don't intersect

=head4 LineIntersection($p1,$p2,$p3,$p4);

Returns the intersection point of lines p1p2 and p3p4,
false if lines don't intersect (parallel lines)

=head4 RayIntersection($p1,$p2,$p3,$p4);

Returns the intersection point of rays p1p2 and p3p4,
false if lines don't intersect (parallel rays)
p1 (p3) is the startpoint of the ray and p2 (p4) is
a point on the ray.

=head4 RayLineIntersection($p1,$p2,$p3,$p4);

Returns the intersection point of ray p1p2 and line p3p4,
false if lines don't intersect (parallel rays)
p1 is the startpoint of the ray and p2 is a point on the ray.

=head4 SegmentLineIntersection($p1,$p2,$p3,$p4);

Returns the intersection point of segment p1p2 and line p3p4,
false if lines don't intersect (parallel rays)

=head4 SegmentRayIntersection($p1,$p2,$p3,$p4);

Returns the intersection point of segment p1p2 and ray p3p4,
false if lines don't intersect (parallel rays)
p3 is the startpoint of the ray and p4 is a point on the ray.

=head4 Perpendicular($p1,$p2,$p3,$p4);

Returns true if lines (segments) p1p2 and p3p4 are perpendicular

=head4 PerpendicularFoot($p1,$p2,$p3);

Returns the perpendicular foot of p3 on line p1p2

=head4 DistanceToLine($p1,$p2,$p3);

Returns the perpendicular distance of p3 to line p1p2

=head4 DistanceToSegment($p1,$p2,$p3);

Returns the distance of p3 to segment p1p2. Depending on the point's
position, this is the distance to one of the endpoints or the
perpendicular distance to the segment.

=head4 Gpc2Polygons($gpc_contour);

Converts a gpc contour structure to an array of contours and returns the array

=head4 GpcClip($operation,$gpc_contour_1,$gpc_contour_2);

 $operation is DIFFERENCE, INTERSECTION, XOR or UNION
 $gpc_polygon_1 is the source polygon
 $gpc_polygon_2 is the clip polygon

Returns a gpc polygon structure which is the result of the gpc clipping operation

=head4 CircleToPoly($i,$p1,$p2,$p3);

Converts the circle through points p1p2p3 to a polygon with i segments

=head4 CircleToPoly($i,$center,$p1);

Converts the circle with center through point p1 to a polygon with i segments

=head4 CircleToPoly($i,$center,$radius);

Converts the circle with center and radius to a polygon with i segments

=head4 ArcToPoly($i,$p1,$p2,$p3);

Converts the arc with begin point p1, intermediate point p2 and end point p3
to a (non-closed !) polygon with i segments

=head4 ArcToPoly($i,$center,$p1,$p2,$direction);

Converts the arc with center, begin point p1 and end point p2 to a
(non-closed !) polygon with i segments.  If direction is 0, the arc
is traversed counter clockwise from p1 to p2, clockwise if direction is 1

=cut

require 5.005;

my $delta = 10 ** (-$precision);

################################################################################
#
# calculate length of a line segment
#
# args : reference to array with 2 points defining line segment
#
sub SegmentLength {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 2) {
    carp("Need 2 points for a segment length calculation");
    return;
  }
  my @a = @{$points[0]};
  my @b = @{$points[1]};
  my $length = sqrt(DotProduct([$points[0],$points[1],$points[0],$points[1]]));
  return $length;
}
################################################################################
#  
#  The determinant for the matrix  | x1 y1 |
#                                  | x2 y2 |
#
# args : x1,y1,x2,y2
#
sub Determinant {
  my ($x1,$y1,$x2,$y2) = @_;
  return ($x1*$y2 - $x2*$y1);
}
################################################################################
#
# vector dot product
# calculates dotproduct vectors p1p2 and p3p4
# The dot product of a and b  is written as a.b and is
# defined by a.b = |a|*|b|*cos q 
#
# args : reference to an array with 4 points p1,p2,p3,p4 defining 2 vectors
#        a = vector p1p2 and b = vector p3p4
#        or
#        reference to an array with 3 points p1,p2,p3 defining 2 vectors
#        a = vector p1p2 and b = vector p1p3
#
sub DotProduct {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  my (@p1,@p2,@p3,@p4);
  if (@points == 4) {
    @p1 = @{$points[0]};
    @p2 = @{$points[1]};
    @p3 = @{$points[2]};
    @p4 = @{$points[3]};
  } elsif (@points == 3) {
    @p1 = @{$points[0]};
    @p2 = @{$points[1]};
    @p3 = @{$points[0]};
    @p4 = @{$points[2]};
  } else {
    carp("Need 3 or 4 points for a dot product");
    return;
  }
  return ($p2[0]-$p1[0])*($p4[0]-$p3[0]) + ($p2[1]-$p1[1])*($p4[1]-$p3[1]);
}
################################################################################
#
# returns vector cross product of vectors p1p2 and p1p3
# using Cramer's rule
#
# args : reference to an array with 3 points p1,p2 and p3
#
sub CrossProduct {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 3) {
    carp("Need 3 points for a cross product");
    return;
  }
  my @p1 = @{$points[0]};
  my @p2 = @{$points[1]};
  my @p3 = @{$points[2]};
  my $det_p2p3 = &Determinant($p2[0], $p2[1], $p3[0], $p3[1]);
  my $det_p1p3 = &Determinant($p1[0], $p1[1], $p3[0], $p3[1]);
  my $det_p1p2 = &Determinant($p1[0], $p1[1], $p2[0], $p2[1]);
  return ($det_p2p3-$det_p1p3+$det_p1p2);
}
################################################################################
#
#  The Cramer's Rule for area of a triangle is
#                                  | x1 y1 1 |
#                        A = 1/2 * | x2 y2 1 |
#                                  | x3 y3 1 |
# Which is 'half of the cross product of vectors ab and ac.
# The cross product of the vectors ab and ac is a vector perpendicular to the
# plane defined by ab and bc with a magnitude equal to the area of the
# parallelogram defined by a, b, c and ab + bc (vector sum)
# Don't forget that:  (ab x ac) = - (ac x ab)  (x = cross product)
# Which just means that if you reverse the vectors in the cross product,
# the resulting vector points in the opposite direction
# The direction of the resulting vector can be found with the "right hand rule"
# This can be used to determine the order of points a, b and c:
# clockwise or counter clockwise
#
# args : reference to an array with 3 points p1.p2,p3
#
sub TriangleArea {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 3) {  # need 3 points for a triangle ...
    carp("A triangle should have exactly 3 points");
    return;
  }
  return CrossProduct($pointsref)/2;
}
################################################################################
# 
# Check if 3 points are colinear
# Points are colinear if triangle area is 0
# Triangle area is crossproduct/2 so we can check the crossproduct instead
#
# args : reference to an array with 3 points p1.p2,p3
#
sub Colinear {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 3) {
    carp("Colinear only checks colinearity for 3 points");
    return;
  }
  # check the area of the triangle to find
  return (abs(CrossProduct($pointsref)) < $delta);
}
################################################################################
#
# calculate intersection point of 2 line segments
# returns false if segments don't intersect
# The theory:
#
#  Parametric representation of a line
#    if p1 (x1,y1) and p2 (x2,y2) are 2 points on a line and
#       P1 is the vector from (0,0) to (x1,y1)
#       P2 is the vector from (0,0) to (x2,y2)
#    then the parametric representation of the line is P = P1 + k (P2 - P1)
#    where k is an arbitrary scalar constant.
#    for a point on the line segement (p1,p2)  value of k is between 0 and 1
#
#  for the 2 line segements we get
#      Pa = P1 + k (P2 - P1)
#      Pb = P3 + l (P4 - P3)
#
#  For the intersection point Pa = Pb so we get the following equations
#      x1 + k (x2 - x1) = x3 + l (x4 - x3)
#      y1 + k (y2 - y1) = y3 + l (y4 - y3)
#  Which using Cramer's Rule results in
#          (x4 - x3)(y1 - y3) - (y4 - x3)(x1 - x3)
#      k = ---------------------------------------
#          (y4 - y3)(x2 - x1) - (x4 - x3)(y2 - y1)
#   and
#          (x2 - x1)(y1 - y3) - (y2 - y1)(x1 - x3)
#      l = ---------------------------------------
#          (y4 - y3)(x2 - x1) - (x4 - x3)(y2 - y1)
#
#  Note that the denominators are equal.  If the denominator is 9,
#  the lines are parallel.  Intersection is detected by checking if
#  both k and l are between 0 and 1.
#
#  The intersection point p5 (x5,y5) is:
#     x5 = x1 + k (x2 - x1)
#     y5 = y1 + k (y2 - y1)
#
# 'Touching' segments are considered as not intersecting
#
# args : reference to an array with 4 points p1,p2,p3,p4
#
sub SegmentIntersection {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 4) {
    carp("SegmentIntersection needs 4 points");
    return;
  }
  my @p1 = @{$points[0]}; # p1,p2 = segment 1
  my @p2 = @{$points[1]};
  my @p3 = @{$points[2]}; # p3,p4 = segment 2
  my @p4 = @{$points[3]};
  my @p5;
  my $n1 = Determinant(($p3[0]-$p1[0]),($p3[0]-$p4[0]),($p3[1]-$p1[1]),($p3[1]-$p4[1]));
  my $n2 = Determinant(($p2[0]-$p1[0]),($p3[0]-$p1[0]),($p2[1]-$p1[1]),($p3[1]-$p1[1]));
  my $d  = Determinant(($p2[0]-$p1[0]),($p3[0]-$p4[0]),($p2[1]-$p1[1]),($p3[1]-$p4[1]));
  if (abs($d) < $delta) {
    return 0; # parallel
  }
  if (!(($n1/$d < 1) && ($n2/$d < 1) &&
        ($n1/$d > 0) && ($n2/$d > 0))) {
    return 0;
  }
  $p5[0] = $p1[0] + $n1/$d * ($p2[0] - $p1[0]);
  $p5[1] = $p1[1] + $n1/$d * ($p2[1] - $p1[1]);
  return \@p5; # intersection point
}
################################################################################
#
# Intersection point of 2 lines - (almost) identical as for Segments
# each line is defined by 2 points
# 
# args : reference to an array with 4 points p1,p2,p3,p4
#
sub LineIntersection {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points < 4) {
    carp("LineIntersection needs 4 points");
    return;
  }
  my @p1 = @{$points[0]}; # p1,p2 = line 1
  my @p2 = @{$points[1]};
  my @p3 = @{$points[2]}; # p3,p4 = line 2
  my @p4 = @{$points[3]};
  my @p5;
  my $n1 = Determinant(($p3[0]-$p1[0]),($p3[0]-$p4[0]),($p3[1]-$p1[1]),($p3[1]-$p4[1]));
  my $d  = Determinant(($p2[0]-$p1[0]),($p3[0]-$p4[0]),($p2[1]-$p1[1]),($p3[1]-$p4[1]));
  if (abs($d) < $delta) {
    return 0; # parallel
  }
  $p5[0] = $p1[0] + $n1/$d * ($p2[0] - $p1[0]);
  $p5[1] = $p1[1] + $n1/$d * ($p2[1] - $p1[1]);
  return \@p5; # intersection point
}
################################################################################
#
# Intersection point of 2 rays
# 
# args : reference to an array with 4 points p1,p2,p3,p4
#
#  Parametric representation of a ray
#    if p1 (x1,y1) is the startpoint of the ray 
#    and p2 (x2,y2) are is a point on the ray then
#       P1 is the vector from (0,0) to (x1,y1)
#       P2 is the vector from (0,0) to (x2,y2)
#    then the parametric representation of the ray is P = P1 + k (P2 - P1)
#    where k is an arbitrary scalar constant.
#    for a point on the line segement (p1,p2)  value of k is positive
#
#  (A ray is often represented as a single point and a direction #  'theta'
#   in this case, one can easily define a second point as
#   x2 = x1 + cos(theta) and y2 = y2 + sin(theta)  )
#
#  for the 2 rays we get
#      Pa = P1 + k (P2 - P1)
#      Pb = P3 + l (P4 - P3)
#
# Touching rays are considered as not intersectin
#
sub RayIntersection {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 4) {
    carp("RayIntersection needs 4 points");
    return;
  }
  my @p1 = @{$points[0]}; # p1,p2 = segment 1 (startpoint is p1)
  my @p2 = @{$points[1]};
  my @p3 = @{$points[2]}; # p3,p4 = segment 2 (startpoint is p3)
  my @p4 = @{$points[3]};
  my @p5;
  my $n1 = Determinant(($p3[0]-$p1[0]),($p3[0]-$p4[0]),($p3[1]-$p1[1]),($p3[1]-$p4[1]));
  my $n2 = Determinant(($p2[0]-$p1[0]),($p3[0]-$p1[0]),($p2[1]-$p1[1]),($p3[1]-$p1[1]));
  my $d  = Determinant(($p2[0]-$p1[0]),($p3[0]-$p4[0]),($p2[1]-$p1[1]),($p3[1]-$p4[1]));
  if (abs($d) < $delta) {
    return 0; # parallel
  }
  if (!( ($n1/$d > 0) && ($n2/$d > 0))) {
    return 0;
  }
  $p5[0] = $p1[0] + $n1/$d * ($p2[0] - $p1[0]);
  $p5[1] = $p1[1] + $n1/$d * ($p2[1] - $p1[1]);
  return \@p5; # intersection point
}
################################################################################
#
# Intersection point of a segment and a line
# 
# args : reference to an array with 4 points p1,p2,p3,p4
#
sub SegmentLineIntersection {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 4) {
    carp("SegmentLineIntersection needs 4 points");
    return;
  }
  my @p1 = @{$points[0]}; # p1,p2 = segment
  my @p2 = @{$points[1]};
  my @p3 = @{$points[2]}; # p3,p4 = line
  my @p4 = @{$points[3]};
  my @p5;
  my $n1 = Determinant(($p3[0]-$p1[0]),($p3[0]-$p4[0]),($p3[1]-$p1[1]),($p3[1]-$p4[1]));
  my $d  = Determinant(($p2[0]-$p1[0]),($p3[0]-$p4[0]),($p2[1]-$p1[1]),($p3[1]-$p4[1]));
  if (abs($d) < $delta) {
    return 0; # parallel
  }
  if (!(($n1/$d < 1) && ($n1/$d > 0))) {
    return 0;
  }
  $p5[0] = $p1[0] + $n1/$d * ($p2[0] - $p1[0]);
  $p5[1] = $p1[1] + $n1/$d * ($p2[1] - $p1[1]);
  return \@p5; # intersection point
}
################################################################################
#
# Intersection point of a ray and a line
# 
# args : reference to an array with 4 points p1,p2,p3,p4
#
sub RayLineIntersection {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 4) {
    carp("RayLineIntersection needs 4 points");
    return;
  }
  my @p1 = @{$points[0]}; # p1,p2 = ray (startpoint p1)
  my @p2 = @{$points[1]};
  my @p3 = @{$points[2]}; # p3,p4 = line
  my @p4 = @{$points[3]};
  my @p5;
  my $n1 = Determinant(($p3[0]-$p1[0]),($p3[0]-$p4[0]),($p3[1]-$p1[1]),($p3[1]-$p4[1]));
  my $d  = Determinant(($p2[0]-$p1[0]),($p3[0]-$p4[0]),($p2[1]-$p1[1]),($p3[1]-$p4[1]));
  if (abs($d) < $delta) {
    return 0; # parallel
  }
  if (!($n1/$d > 0)) {
    return 0;
  }
  $p5[0] = $p1[0] + $n1/$d * ($p2[0] - $p1[0]);
  $p5[1] = $p1[1] + $n1/$d * ($p2[1] - $p1[1]);
  return \@p5; # intersection point
}
################################################################################
#
# Intersection point of a segment and a ray
# 
# args : reference to an array with 4 points p1,p2,p3,p4
#
sub SegmentRayIntersection {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 4) {
    carp("SegmentRayIntersection needs 4 points");
    return;
  }
  my @p1 = @{$points[0]}; # p1,p2 = segment
  my @p2 = @{$points[1]};
  my @p3 = @{$points[2]}; # p3,p4 = ray (startpoint p3)
  my @p4 = @{$points[3]};
  my @p5;
  my $n1 = Determinant(($p3[0]-$p1[0]),($p3[0]-$p4[0]),($p3[1]-$p1[1]),($p3[1]-$p4[1]));
  my $n2 = Determinant(($p2[0]-$p1[0]),($p3[0]-$p1[0]),($p2[1]-$p1[1]),($p3[1]-$p1[1]));
  my $d  = Determinant(($p2[0]-$p1[0]),($p3[0]-$p4[0]),($p2[1]-$p1[1]),($p3[1]-$p4[1]));
  if (abs($d) < $delta) {
    return 0; # parallel
  }
  if (!(($n1/$d < 1) && ($n1/$d > 0) && ($n2/$d > 0))) {
    return 0;
  }
  $p5[0] = $p1[0] + $n1/$d * ($p2[0] - $p1[0]);
  $p5[1] = $p1[1] + $n1/$d * ($p2[1] - $p1[1]);
  return \@p5; # intersection point
}
################################################################################
#
# returns true if 2 lines (segments) are perpendicular
# Lines are perpendicular if dot product is 0
# 
# args : reference to an array with 4 points p1,p2,p3,p4
#        p1p2 = line 1
#        p3p4 = line 2
#
sub Perpendicular {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 4) {
    carp("Perpendicular needs 4 points defining 2 lines or segments");
    return;
  }
  return (abs(DotProduct([$points[0],$points[1],$points[2],$points[3]])) < $delta);
}
################################################################################
#
# Calculates the 'perpendicular foot' of a point on a line
#
# args: reference to array with 3 points p1,p2,p3
#       p1p2 = line
#       p3   = point for which perpendicular foot is to be calculated
#
sub PerpendicularFoot {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points != 3) {
    carp("PerpendicularFoot needs 3 points defining a line and a point");
    return;
  }
  my @p1 = @{$points[0]}; # p1,p2 = line
  my @p2 = @{$points[1]};
  my @p3 = @{$points[2]}; # p3 point
  # vector penpenidular to line
  my @v;
  $v[0] =     $p2[1] - $p1[1];  # y2-y1
  $v[1] =  - ($p2[0] - $p1[0]); # -(x2-x1);
  # p4 = v + p3 is a second point of the line perpendicular to p1p2 going through p3
  my @p4;
  $p4[0] =  $p3[0] + $v[0];
  $p4[1] =  $p3[1] + $v[1];
  return LineIntersection([\@p1,\@p2,\@p3,\@p4]);
}
################################################################################
#
# Calculate distance from point p to line segment p1p2
#
# args: reference to array with 3 points: p1,p2,p3
#       p1p2 = segment
#       p3   = point for which distance is to be calculated
# returns distance from p3 to line segment p1p2
#         which is the smallest value from:
#            distance p3p1
#            distance p3p2
#            perpendicular distance from p3 to line p1p2
#
sub DistanceToSegment {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points < 3) {
    carp("DistanceToSegment needs 3 points defining a segment and a point");
    return;
  }
  # the perpendicular distance is the height of the parallelogram defined
  # by the 3 points devided by the base
  # Note the this is a signed value so it can be used to check at which
  # side the point is located
  # we use dot products to find out where point is located1G/dotpro
  my $d1 = DotProduct([$points[0],$points[1],$points[0],$points[2]]);
  my $d2 = DotProduct([$points[0],$points[1],$points[0],$points[1]]);
  my $dp = CrossProduct([$points[2],$points[0],$points[1]]) / sqrt $d2;
  if ($d1 <= 0) {
    return SegmentLength([$points[2],$points[0]]);
  } elsif ($d2 <= $d1) {
    return SegmentLength([$points[2],$points[1]]);
  } else {
    return $dp;
  }
}
################################################################################
#
# Calculate distance from point p to line p1p2
#
# args: reference to array with 3 points: p1,p2,p3
#       p1p2 = line
#       p3   = point for which distance is to be calculated
# returns 2 numbers
#   - perpendicular distance from p3 to line p1p2
#   - distance from p3 to line segment p1p2
#     which is the smallest value from:
#            distance p3p1
#            distance p3p2
#
sub DistanceToLine {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points < 3) {
    carp("DistanceToLine needs 3 points defining a line and a point");
    return;
  }
  # the perpendicular distance is the height of the parallelogram defined
  # by the 3 points devided by the base
  # Note the this is a signed value so it can be used to check at which
  # side the point is located
  # we use dot products to find out where point is located1G/dotpro
  my $d  = DotProduct([$points[0],$points[1],$points[0],$points[1]]);
  my $dp = CrossProduct([$points[2],$points[0],$points[1]]) / sqrt $d;
  return $dp;
}
################################################################################
#
# Initializer
#
sub new {
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;
  my $self = { @_ };
  bless($self,$class);
  return $self;
}
################################################################################
#
# args: reference to polygon object
#
sub points {
  my Math::Geometry::Planar $self = shift;
  if (@_) {
    if ($self->get_polygons) {
      carp("Object is a contour - can't add points");
      return;
    } else {
      # delete existing info
      $self->{points} = ();
      my $pointsref = shift;
      # normalize (a single polygon has only an outer shape
      # -> make points order counter clockwise)
      if (PolygonArea($pointsref) > 0) {
        $self->{points} = $pointsref;
      } else {
        $self->{points} = [reverse @{$pointsref}];
      }
    }
  }
  return $self->{points};
}
################################################################################
#
# args: reference to polygon object
#
sub polygons {
  my Math::Geometry::Planar $self = shift;
  if (@_) {
    if ($self->points) {
      carp("Object is a polygon - can't add polygons");
      return;
    } else {
      # delete existing info
      $self->{polygons} = ();
      my $polygons = shift;
      my @polygonrefs = @{$polygons};
      $self->add_polygons(@polygonrefs);
    }
  }
  return $self->{polygons};
}
################################################################################
#
# args: none
# returns the number of polygons in the contour
#
sub num_polygons {
  my Math::Geometry::Planar $self = shift;
  my $polygons = $self->{polygons};
  return 0 if (! $polygons);
  return scalar @{$polygons};
}
################################################################################
#
# args: list of references to polygons
# returns the number of polygons in the contour
#
sub add_polygons {
  my Math::Geometry::Planar $self = shift;
  return if (! @_); # nothing to add
  # can't add polygons to a polygon object
  if ($self->points) {
    carp("Object is a polygon - can't add polygons");
    return;
  }
  # first polygon is outer polygon
  if (! $self->num_polygons) {
    my $outer = shift;
    # counter clockwise for outer polygon
    if (PolygonArea($outer) < 0) {
      push @{$self->{polygons}}, [reverse @{$outer}];
    } else {
      push @{$self->{polygons}}, $outer;
    }
  }
  # inner polygon(s)
  while (@_) {
    # clockwise for inner polygon
    my $inner = shift;
    if (PolygonArea($inner) > 0) {
      push @{$self->{polygons}}, [reverse @{$inner}];
    } else {
      push @{$self->{polygons}}, $inner;
    }
  }
  return scalar @{$self->{polygons}};
}
################################################################################
#
# args: list of indices
# returns list of polygons indicated by indices
#         (list value at position n is undefined if the index at position
#          n is out of range)
#         list of all polygons indicated by indices
#
sub get_polygons {
  my Math::Geometry::Planar $self = shift;
  my @result;
  my $polygons = $self->{polygons};
  return if (! $polygons);
  my $i = 0;
  if (@_) {
    while (@_) {
      my $index = int shift;
      if ($index >= 0 && $index < num_polygons($self)) {
        $result[$i] = ${$polygons}[$index];
      } else {
        $result[$i] = undef;
      }
      $i++;
    }
    return @result;
  } else {
    return @{$polygons};
  }
}
################################################################################
# cleanup polygon = remove colinear points
#
# args: reference to polygon or contour object
#
sub cleanup {
  my ($self) = @_;
  my $pointsref = $self->points;
  if ($pointsref) {    # polygon object
    my @points = @$pointsref;
    for (my $i=0 ; $i< @points && @points > 2 ;$i++) {
      if (Colinear([$points[$i-2],$points[$i-1],$points[$i]])) {
        splice @points,$i-1,1;
        $i--;
      }
    }
    # replace polygon points
    $self->points([@points]);
    return [@points];
  } else {             # contour object
    my @polygonrefs = $self->get_polygons;
    for (my $j = 0; $j < @polygonrefs; $j++) {
      $pointsref = $polygonrefs[$j];
      my @points = @$pointsref;
      for (my $i=0 ; $i< @points && @points > 2 ;$i++) {
        if (Colinear([$points[$i-2],$points[$i-1],$points[$i]])) {
          splice @points,$i-1,1;
          $i--;
        }
      }
      $polygonrefs[$j] = [@points];
    }
    $self->polygons([@polygonrefs]);
    return [@polygonrefs];
  }
}
################################################################################
#
# Ah - more vector algebra
# We consider every set of 3 subsequent points p1,p2,p3 on the polygon and calculate
# the vector product of the vectors  p1p2 and p1p3.  All these products should
# have the same sign.  If the sign changes, the polygon is not convex
#
# make sure to remove colinear points first before calling perimeter
# (I prefer not to include the call to cleanup)
#
# args: reference to polygon or contour object
#       (for a contour we only check the outer shape)
#
sub isconvex {
  my ($self) = @_;
  my $pointsref = $self->points;
  if (! $pointsref) {
    $pointsref = ($self->get_polygons(0))[0];
    return if (! $pointsref); # empty object
  }
  my @points = @$pointsref;
  return 1 if (@points < 5); # every poly with a less then 5 points is convex
  my $prev = 0;
  for (my $i = 0 ; $i < @points ; $i++) {
    my $tmp = CrossProduct([$points[$i-2],$points[$i-1],$points[$i]]);
    # check if sign is different from pervious one(s)
    if ( ($prev < 0 && $tmp > 0) ||
         ($prev > 0 && $tmp < 0) ) {
      return 0;
    }
    $prev = $tmp;
  }
  return 1;
}
################################################################################
#
# Brute force attack:
# just check intersection for every segment versus every other segment
# so for a polygon with n ponts this will take n**2 intersection calculations
# I added a few simple improvements: to boost speed:
#   - don't check adjacant segments
#   - don't check against 'previous' segments (if we checked segment x versus y,
#     we don't need to check y versus x anymore)
# Results in (n-2)*(n-1)/2 - 1 checks  which is close to n**2/2 for large n
#
# make sure to remove colinear points first before calling perimeter
# (I prefer not to include the call to cleanup)
#
# args: reference to polygon or contour object
#       (a contour is considered to be simple if all it's shapes are simple)
#
sub IsSimplePolygon {
  my ($pointsref) = @_;
  my @points = @$pointsref;
  return 1 if (@points < 4); # triangles are simple polygons ...
  for (my $i = 0 ; $i < @points-2 ; $i++) {
    # check versus all next non-adjacant edges
    for (my $j = $i+2 ; $j < @points ; $j++) {
      # don't check first versus last segment (adjacant)
      next if ($i == 0 && $j == @points-1);
      if (SegmentIntersection([$points[$i-1],$points[$i],$points[$j-1],$points[$j]])) {
        return 0;
      }
    }
  }
  return 1;
}
################################################################################
#
# Check if polyogn or contour is simple
sub issimple {
  my ($self) = @_;
  my $pointsref = $self->points;
  if ($pointsref) {
    return IsSimplePolygon($pointsref);
  } else {
    my @polygonrefs = $self->get_polygons;
    my @result;
    foreach (@polygonrefs) {
      return 0 if (! IsSimplePolygon($_));
    }
    return 1;
  }
}
################################################################################
# makes only sense for simple polygons
# make sure to remove colinear points first before calling perimeter
# (I prefer not to include the call to colinear)
#
# args: reference to polygon or contour object
# returns the perimeter of the polygon or the perimeter of the outer shape of
# the contour
#
sub perimeter {
  my ($self) = @_;
  my $pointsref = $self->points;
  if (! $pointsref) {
    $pointsref = ($self->get_polygons(0))[0];
    return if (! $pointsref); # empty object
  }
  my @points = @$pointsref;
  my $perimeter = 0;
  if ($pointsref) {
    my @points = @$pointsref;
    if (@points < 3) { # no perimeter for lines and points
      carp("Can't calculate perimeter: polygon should have at least 3 points");
      return;
    }
    for (my $index=0;$index < @points; $index++) {
      $perimeter += SegmentLength([$points[$index-1],$points[$index]]);
    }
  }
  return $perimeter;
}
################################################################################
# makes only sense for simple polygons
# make sure to remove colinear points first before calling area
# returns a signed value, can be used to find out whether
# the order of points is clockwise or counter clockwise
# (I prefer not to include the call to colinear)
#
# args: reference to an array of points
#
sub PolygonArea {
  my $pointsref = $_[0];
  my @points = @$pointsref;
  if (@points < 3) { # no area for lines and points
    carp("Can't calculate area: polygon should have at least 3 points");
    return;
  }
  push @points,$points[0];  # provide closure
  my $area = 0;
  while(@points >= 2){
   $area += $points[0]->[0]*$points[1]->[1] - $points[1]->[0]*$points[0]->[1];
   shift @points;
  }
  return $area/2.0;
}
################################################################################
# Calculates the area of a polygon or a contour
# Makes only sense for simple polygons
# Returns a signed value so it can be used to find out whether
# the order of points in a polygon is clockwise or counter
# clockwise.
#
# args: reference to polygon or contour object
#
sub area {
  my ($self) = @_;
  my $pointsref = $self->points;
  my $area = 0;
  if ($pointsref) {
    $area = PolygonArea($pointsref);
  } else {
    my @polygonrefs = $self->get_polygons;
    foreach (@polygonrefs) {
      $area += PolygonArea($_);
    }
  }
  return $area;
}
################################################################################
#
# calculate the centroid of a polygon or contour
# (a.k.a. the center of mass a.k.a. the center of gravity)
#
# The centroid is calculated as the weighted sum of the centroids
# of a partition of the polygon into triangles. The centroid of a
# triangle is simply the average of its three vertices, i.e., it
# has coordinates (x1 + x2 + x3)/3 and (y1 + y2 + y3)/3. 
# In fact, the triangulation need not be a partition, but rather
# can use positively and negatively oriented triangles (with positive
# and negative areas), as is used when computing the area of a polygon
#
# makes only sense for simple polygons
# make sure to remove colinear points first before calling centroid
# (I prefer not to include the call to cleanup)
#
# args: reference to polygon object
#
sub centroid {
  my ($self) = @_;
  my @triangles = $self->triangulate;

  if (! @triangles) { # no result from triangulation
    carp("Nothing to calculate centroid for");
    return;
  }

  my @c;
  my $total_area;
  # triangulate
  foreach my $triangleref (@triangles) {
    my @triangle = @{$triangleref->points};
    my $area = TriangleArea([$triangle[0],$triangle[1],$triangle[2]]);
    # weighted centroid = area * centroid = area * sum / 3
    # we postpone division by 3 till we divide by total area to
    # minimize number of calculations
    $c[0] += ($triangle[0][0]+$triangle[1][0]+$triangle[2][0]) * $area;
    $c[1] += ($triangle[0][1]+$triangle[1][1]+$triangle[2][1]) * $area;
    $total_area += $area;
  }
  $c[0] = $c[0]/($total_area*3);
  $c[1] = $c[1]/($total_area*3);
  return \@c;
}
################################################################################
#
# The winding number method has been cused here.  Seems to
# be the most accurate one and, if well written, it matches
# the performance of the crossing number method.
# The winding number method counts the number of times a polygon
# winds around the point.  If the result is 0, the points is outside
# the polygon.
#
# args: reference to polygon object
#       reference to a point
#
sub IsInsidePolygon {
  my ($pointsref,$pointref) = @_;
  my @points = @$pointsref;
  if (@points < 3) { # polygon should at least have 3 points ...
    carp("Can't run inpolygon: polygon should have at least 3 points");
    return;
  }
  if (! $pointref) {
    carp("Can't run inpolygon: no point entered");
    return;
  }
  my @point = @$pointref;
  my $wn;  # thw winding number counter
  for (my $i = 0 ; $i < @points ; $i++) {
    my $cp = CrossProduct([$points[$i-1],$points[$i],$pointref]);
    # if colinear and in between the 2 points of the polygon
    # segment, it's on the perimeter and considered inside
    if ($cp == 0) {
      if (
          ((($points[$i-1][0] <= $point[0] &&
             $point[0] <= $points[$i][0])) ||
           (($points[$i-1][0] >= $point[0] &&
             $point[0] >= $points[$i][0])))
          &&
          ((($points[$i-1][1] <= $$pointref[1] &&
             $point[1] <= $points[$i][1])) ||
           (($points[$i-1][1] >= $point[1] &&
             $point[1] >= $points[$i][1])))
         ) {
         return 1;
       }
    }
    if ($points[$i-1][1] <= $point[1]) { # start y <= P.y
      if ($points[$i][1] > $point[1]) {  # // an upward crossing
        if ($cp > 0) {
          # point left of edge
          $wn++;                         # have a valid up intersect
        }
      }
    } else {                             # start y > P.y (no test needed)
      if ($points[$i][1] <= $point[1]) { # a downward crossing
        if ($cp < 0) {
          # point right of edge
          $wn--;                         # have a valid down intersect
        }
      }
    }
  }
  return $wn;
}
################################################################################
#
# Check if polygon inside polygon or contour
# (for a contour, a point is inside when it's within the outer shape and
#  not within one of the inner shapes (holes) )
sub isinside {
  my ($self,$pointref) = @_;
  my $pointsref = $self->points;
  if ($pointsref) {
    return IsInsidePolygon($pointsref,$pointref);
  } else {
    my @polygonrefs = $self->get_polygons;
    return 0 if (! IsInsidePolygon($polygonrefs[0],$pointref));
    my @result;
    for (my $i = 1; $i <@polygonrefs; $i++) {
      return 0 if (IsInsidePolygon($polygonrefs[$i],$pointref));
    }
    return 1;
  }
}
################################################################################
#
# a counter clockwise rotation over an angle a is given by the formula
#
#  / x2 \      /  cos(a)  -sin(a) \  / x1 \
#  |    |   =  |                  |  |    |
#  \ y2 /      \  sin(a)   cos(a) /  \ y1 /
#
# args: reference to polygon object
#       angle (in radians)
#       reference to center point (use origin if no center point entered)
#
sub RotatePolygon {
  my ($pointsref,$angle,$center) = @_;
  my $xc = 0;
  my $yc = 0;
  if ($center) {
    my @point = @$center;
    $xc = $point[0];
    $yc = $point[1];
  }
  if ($pointsref) {
    my @points = @$pointsref;
    my @result;
    for (my $i = 0 ; $i < @points ; $i++) {
      my $x = $xc + cos($angle)*($points[$i][0] - $xc) - sin($angle)*($points[$i][1] - $yc);
      my $y = $yc + sin($angle)*($points[$i][0] - $xc) + cos($angle)*($points[$i][1] - $yc);
      $result[$i][0] = $x;
      $result[$i][1] = $y;
    }
    return [@result];
  }
}
################################################################################
#
# rotate jpolygon or contour
#
sub rotate {
  my ($self,$angle,$center) = @_;
  my $rotate =  Math::Geometry::Planar->new;
  my $pointsref = $self->points;
  if ($pointsref) {
    $rotate->points(RotatePolygon($pointsref,$angle,$center));
  } else {
    my @polygonrefs = $self->get_polygons;
    my @result;
    foreach (@polygonrefs) {
      $rotate->add_polygons(RotatePolygon($_,$angle,$center));
    }
  }
  return $rotate;
}
################################################################################
#
# move a polygon over a distance in x and y direction
#
# args: reference to polygon object
#       X offset
#       y offset
#
sub MovePolygon {
  my ($pointsref,$dx,$dy) = @_;
  if ($pointsref) {
    my @points = @$pointsref;
    for (my $i = 0 ; $i < @points ; $i++) {
      $points[$i][0] = $points[$i][0] + $dx;
      $points[$i][1] = $points[$i][1] + $dy;
    }
    return [@points];
  }
}
################################################################################
#
# Move polygon or contour
#
sub move {
  my ($self,$dx,$dy) = @_;
  my $move =  Math::Geometry::Planar->new;
  my $pointsref = $self->points;
  if ($pointsref) {
    $move->points(MovePolygon($pointsref,$dx,$dy));
  } else {
    my @polygonrefs = $self->get_polygons;
    my @result;
    foreach (@polygonrefs) {
      $move->add_polygons(MovePolygon($_,$dx,$dy));
    }
  }
  return $move;
}
################################################################################
#
# mirror in x direction - vertical axis through point referenced by $center
# if no center entered, use y axis
#
# args: reference to polygon object
#       reference to center
#
sub MirrorXPolygon {
  my ($pointsref,$center) = @_;
  my @points = @$pointsref;
  if (@points == 0) { # nothing to mirror
    carp("Nothing to mirror ...");
    return;
  }
  my $xc = 0;
  my $yc = 0;
  if ($center) {
    my @point = @$center;
    $xc = $point[0];
    $yc = $point[1];
  }
  for (my $i = 0 ; $i < @points ; $i++) {
    $points[$i][0] = 2*$xc - $points[$i][0];
  }
  return [@points];
}
################################################################################
#
# mirror polygon or contour in x direction
#    (vertical axis through point referenced by $center)
sub mirrorx {
  my ($self,$dx,$dy) = @_;
  my $mirrorx =  Math::Geometry::Planar->new;
  my $pointsref = $self->points;
  if ($pointsref) {
    $mirrorx->points(MirrorXPolygon($pointsref,$dx,$dy));
  } else {
    my @polygonrefs = $self->get_polygons;
    my @result;
    foreach (@polygonrefs) {
      $mirrorx->add_polygons(MirrorXPolygon($_,$dx,$dy));
    }
  }
  return $mirrorx;
}
################################################################################
#
# mirror in y direction - horizontal axis through point referenced by $center
# if no center entered, use x axis
#
# args: reference to polygon object
#       reference to center
#
sub MirrorYPolygon {
  my ($pointsref,$center) = @_;
  my @points = @$pointsref;
  if (@points == 0) { # nothing to mirror
    carp("Nothing to mirror ...");
    return;
  }
  my $xc = 0;
  my $yc = 0;
  if ($center) {
    my @point = @$center;
    $xc = $point[0];
    $yc = $point[1];
  }
  for (my $i = 0 ; $i < @points ; $i++) {
    $points[$i][1] = 2*$yc - $points[$i][1];
  }
  return [@points];
}
################################################################################
#
# mirror polygon or contour in x direction
#    (vertical axis through point referenced by $center)
sub mirrory {
  my ($self,$dx,$dy) = @_;
  my $mirrory =  Math::Geometry::Planar->new;
  my $pointsref = $self->points;
  if ($pointsref) {
    $mirrory->points(MirrorYPolygon($pointsref,$dx,$dy));
  } else {
    my @polygonrefs = $self->get_polygons;
    my @result;
    foreach (@polygonrefs) {
      $mirrory->add_polygons(MirrorYPolygon($_,$dx,$dy));
    }
  }
  return $mirrory;
}
################################################################################
#
# mirror around axis determined by 2 points (p1p2)
#
# args: reference to polygon object
#       reference to array with to points defining reflection axis
#
sub MirrorPolygon {
  my ($pointsref,$axisref) = @_;
  my @points = @$pointsref;
  my @axis   = @$axisref;
  if (@axis != 2) { # need 2 points defining axis
    carp("Can't mirror: 2 points need to define axis");
    return;
  }
  my $p1ref = $axis[0];
  my $p2ref = $axis[1];
  my @p1 = @$p1ref;
  my @p2 = @$p2ref;
  if (@points == 0) { # nothing to mirror
    carp("Nothing to mirror ...");
    return;
  }
  for (my $i = 0 ; $i < @points ; $i++) {
    my $footref = PerpendicularFoot([\@p1,\@p2,$points[$i]]);
    my @foot = @$footref;
    $points[$i][0] = $foot[0] - ($points[$i][0] - $foot[0]);
    $points[$i][1] = $foot[1] - ($points[$i][1] - $foot[1]);
  }
  return [@points];
}
################################################################################
#
# mirror polygon or contour around axis determined by 2 points (p1p2)
#
sub mirror {
  my ($self,$axisref) = @_;
  my $mirror =  Math::Geometry::Planar->new;
  my $pointsref = $self->points;
  if ($pointsref) {
    $mirror->points(MirrorPolygon($pointsref,$axisref));
  } else {
    my @polygonrefs = $self->get_polygons;
    my @result;
    foreach (@polygonrefs) {
      $mirror->add_polygons(MirrorPolygon($_,$axisref));
    }
  }
  return $mirror;
}
################################################################################
#
# scale polygon from center
# I would choose the centroid ...
#
# args: reference to polygon object
#       scale factor
#       reference to center point
#
sub ScalePolygon {
  my ($pointsref,$scale,$center) = @_;
  my @points = @$pointsref;
  if (@points == 0) { # nothing to scale
    carp("Nothing to scale ...");
    return;
  }
  my $xc = 0;
  my $yc = 0;
  if ($center) {
    my @point = @$center;
    $xc = $point[0];
    $yc = $point[1];
  }
  # subtract center, scale and add center again
  for (my $i = 0 ; $i < @points ; $i++) {
    $points[$i][0] = $scale * ($points[$i][0] - $xc) + $xc;
    $points[$i][1] = $scale * ($points[$i][1] - $yc) + $yc;
  }
  return [@points];
}
################################################################################
#
# scale polygon from center
# I would choose the centroid ...
#
sub scale {
  my ($self,$factor,$center) = @_;
  my $scale =  Math::Geometry::Planar->new;
  my $pointsref = $self->points;
  if ($pointsref) {
    $scale->points(ScalePolygon($pointsref,$factor,$center));
  } else {
    my @polygonrefs = $self->get_polygons;
    my @result;
    foreach (@polygonrefs) {
      $scale->add_polygons(ScalePolygon($_,$factor,$center));
    }
  }
  return $scale;
}
################################################################################
#
# The "bounding box" of a set of points is the box with horizontal
# and vertical edges that contains all points
#
# args: reference to array of points or a contour
# returns reference to array of 4 points representing bounding box
#
sub bbox {
  my ($self) = @_;
  my $bbox =  Math::Geometry::Planar->new;
  my $pointsref = $self->points;
  if (! $pointsref) {
    $pointsref = ($self->get_polygons(0))[0];
    return if (! $pointsref); # empty object
  }
  my @points = @$pointsref;
  if (@points < 3) { # polygon should at least have 3 points ...
    carp("Can't determine bbox: polygon should have at least 3 points");
    return;
  }
  my $min_x = $points[0][0];
  my $min_y = $points[0][1];
  my $max_x = $points[0][0];
  my $max_y = $points[0][1];
  for (my $i = 1 ; $i < @points ; $i++) {
     $min_x = $points[$i][0] if ($points[$i][0] < $min_x);
     $min_y = $points[$i][1] if ($points[$i][1] < $min_y);
     $max_x = $points[$i][0] if ($points[$i][0] > $max_x);
     $max_y = $points[$i][1] if ($points[$i][1] > $max_y);
  }
  $bbox->points([[$min_x,$min_y],
                 [$min_x,$max_y],
                 [$max_x,$max_y],
                 [$max_x,$min_y]]);
  return $bbox;
}
################################################################################
#
# The "minimal enclosing rectangle" of a set of points is the box with minimal area
# that contains all points.
# We'll use the rotating calipers method here which works only on convex polygons
# so before calling minbbox, create the convex hull first for the set of points
# (taking into account whether or not the set of points represents a polygon).
#
# args: reference to array of points representing a convex polygon
# returns reference to array of 4 points representing minimal bounding rectangle
#
sub minrectangle {
  my ($self) = @_;
  my $minrectangle =  Math::Geometry::Planar->new;
  my $pointsref = $self->points;
  if (! $pointsref) {
    $pointsref = ($self->get_polygons(0))[0];
    return if (! $pointsref); # empty object
  }
  my @points = @$pointsref;
  if (@points < 3) { # polygon should at least have 3 points ...
    carp("Can't determine minrectangle: polygon should have at least 3 points");
    return;
  }
  my $d;
  # scan all segments and for each segment, calculate the area of the bounding
  # box that has one side coinciding with the segment
  my $min_area = 0;
  my @indices;
  for (my $i = 0 ; $i < @points ; $i++) {
    # for each segment, find the point (vertex) at the largest perpendicular distance
    # the opposite side of the current rectangle runs through this point
    my $mj;       # index of point at maximum distance
    my $maxj = 0; # maximum distance (squared)
    # Get coefficients of the implicit line equation ax + by +c = 0
    # Do NOT normalize since scaling by a constant
    # is irrelevant for just comparing distances.
    my $a = $points[$i-1][1] - $points[$i][1];
    my $b = $points[$i][0] - $points[$i-1][0];
    my $c = $points[$i-1][0] * $points[$i][1] - $points[$i][0] * $points[$i-1][1];
    # loop through point array testing for max distance to current segment
    for (my $j = -1 ; $j < @points-1 ; $j++) {
      next if ($j == $i || $j == $i-1); # exclude points of current segment
      # just use dist squared (sqrt not needed for comparison)
      # since the polygon is convex, all points are at the same side
      # so we don't need to take the absolute value for dist
      my $dist = $a * $points[$j][0] + $b * $points[$j][1] + $c;
      if ($dist > $maxj) {    # this point is further
          $mj   = $j;         # so have a new maximum
          $maxj = $dist;
      }
    }
    # the line -bx+ay+c=0 is perpendicular to ax+by+c=0
    # now find index of extreme points corresponding to perpendicular line
    # initialize to first point (note that points of current segment could
    # be one or even both of the extreme points)
    my $mk = 0;
    my $ml = 0;
    my $mink = -$b * $points[0][0] + $a * $points[0][1] + $c;
    my $maxl = -$b * $points[0][0] + $a * $points[0][1] + $c;
    for (my $j = 1 ; $j < @points ; $j++) {
      # use signed dist to get extreme points
      my $dist = -$b * $points[$j][0] + $a * $points[$j][1] + $c;
      if ($dist < $mink) {    # this point is further
          $mk   = $j;         # so have a new maximum
          $mink = $dist;
      }
      if ($dist > $maxl) {    # this point is further
          $ml   = $j;         # so have a new maximum
          $maxl = $dist;
      }
    }
    # now $maxj/sqrt(a**2+b**2) is the height of the current rectangle
    # and (|$mink| + |$maxl|)/sqrt(a**2+b**2) is the width
    # since area is width*height we can waste the costly sqrt function
    my $area = abs($maxj * ($mink-$maxl)) / ($a**2 +$b**2);
    if ($area < $min_area || ! $min_area) {
      $min_area = $area;
      @indices = ($i,$mj,$mk,$ml);
    }
  }
  my ($i,$j,$k,$l) = @indices;
  # Finally, get the corners of the minimum enclosing rectangle
  my $p1 = PerpendicularFoot([$points[$i-1],$points[$i],$points[$k]]);
  my $p2 = PerpendicularFoot([$points[$i-1],$points[$i],$points[$l]]);
  # now we calculate the second point on the line parallel to
  # the segment i going through the vertex j
  my $p  = [$points[$j][0]+$points[$i-1][0]-$points[$i][0],
            $points[$j][1]+$points[$i-1][1]-$points[$i][1]];
  my $p3 = PerpendicularFoot([$points[$j],$p,$points[$l]]);
  my $p4 = PerpendicularFoot([$points[$j],$p,$points[$k]]);
  $minrectangle->points([$p1,$p2,$p3,$p4]);
  return $minrectangle;
}
################################################################################
#
# triangulate polygon or contour
#
# args: polygon or contour object
# returns a reference to an array triangles
#
sub triangulate {
  my ($self) = @_;
  my $pointsref = $self->points;
  my @triangles;
  if ($pointsref) {
    @triangles = @{TriangulatePolygon([$pointsref])};
  } else {
    my $polygonrefs = $self->polygons;
    if ($polygonrefs) {
      @triangles = @{TriangulatePolygon($polygonrefs)};
    }
  }
  my @result;
  foreach (@triangles) {
    my $triangle =  Math::Geometry::Planar->new;
    $triangle->points($_);
    push @result,$triangle;
  }
  return @result;
}
################################################################################
#
# convexhull using the Melkman algorithm 
# (the set of input points represent a polygon and are thus ordered
#
# args: reference to ordered array of points representing a polygon
#       or contour (for a contour, we calculate the hull for the
#       outer shape)
# returns a reference to an array of the convex hull vertices
#
sub convexhull {
  my ($self) = @_;
  my $pointsref = $self->points;
  if (! $pointsref) {
    $pointsref = ($self->get_polygons(0))[0];
    return if (! $pointsref); # empty object
  }
  my @points = @$pointsref;
  return ([@points]) if (@points < 5);            # need at least 5 points
  # initialize a deque D[] from bottom to top so that the
  # 1st tree vertices of V[] are a counterclockwise triangle
  my @result;
  my $bot = @points-2;
  my $top = $bot+3;           # initial bottom and top deque indices
  $result[$bot] = $points[2]; # 3rd vertex is at both bot and top
  $result[$top] = $points[2]; # 3rd vertex is at both bot and top
  if (CrossProduct([$points[0], $points[1], $points[2]]) > 0) {
    $result[$bot+1] = $points[0];
    $result[$bot+2] = $points[1];       # ccw vertices are: 2,0,1,2
  } else {
    $result[$bot+1] = $points[1];
    $result[$bot+2] = $points[0];       # ccw vertices are: 2,1,0,2
  }

  # compute the hull on the deque D[]
  for (my $i=3; $i < @points; $i++) {   # process the rest of vertices
    # test if next vertex is inside the deque hull
    if ((CrossProduct([$result[$bot], $result[$bot+1], $points[$i]]) > 0) &&
      (CrossProduct([$result[$top-1], $result[$top], $points[$i]]) > 0) ) {
        last;         # skip an interior vertex
    }

    # incrementally add an exterior vertex to the deque hull
    # get the rightmost tangent at the deque bot
    while (CrossProduct([$result[$bot], $result[$bot+1], $points[$i]]) <= 0) {
      ++$bot;                      # remove bot of deque
      }
    $result[--$bot] = $points[$i]; # insert $points[i] at bot of deque

    # get the leftmost tangent at the deque top
    while (CrossProduct([$result[$top-1], $result[$top], $points[$i]]) <= 0) {
      --$top;                      # pop top of deque
      }
    $result[++$top] = $points[$i]; #/ push $points[i] onto top of deque
  }

  # transcribe deque D[] to the output hull array H[]
  my @returnval;
  for (my $h = 0; $h <= ($top-$bot-1); $h++) {
    $returnval[$h] = $result[$bot + $h];
  }
  my $hull =  Math::Geometry::Planar->new;
  $hull->points([@returnval]);
  return $hull;
}
################################################################################
#
# convexhull using Andrew's monotone chain 2D convex hull algorithm
# returns a reference to an array of the convex hull vertices
#
# args: reference to array of points (doesn't really need to be a polygon)
#       (also works for a contour - however, since a contour should consist
#       of polygons - which are ordered sets of points - the algorithm
#       above will be faster)
# returns a reference to an array of the convex hull vertices
#
sub convexhull2 {
  my ($self) = @_;
  my $pointsref = $self->points;
  if (! $pointsref) {
    $pointsref = ($self->get_polygons(0))[0];
    return if (! $pointsref); # empty object
  }
  my @points = @$pointsref;
  return ([@points]) if (@points < 5);            # need at least 5 points
  # first, sort the points by increasing x and y-coordinates
  @points = sort ByXY (@points);
  # Get the indices of points with min x-coord and min|max y-coord
  my @hull;
  my $bot = 0;
  my $top = -1;
  my $minmin = 0;
  my $minmax;
  my $xmin = $points[0][0];
  for (my $i = 1 ; $i < @points ; $i++) {
    if ($points[$i][0] != $xmin) {
      $minmax = $i - 1;
      last
    }
  }
  if ($minmax == @points-1) {      # degenerate case: all x-coords == xmin
    $hull[++$top] = $points[$minmin];
    if ($points[$minmax][1] != $points[$minmin][1]) { # a nontrivial segment
      $hull[$==$top] = $points[$minmax];
      return [@points];
    }
  }

  # Get the indices of points with max x-coord and min|max y-coord
  my $maxmin = 0;
  my $maxmax = @points - 1;
  my $xmax = $points[@points-1][0];
  for (my $i = @points - 2 ; $i >= 0 ; $i--) {
    if ($points[$i][0] != $xmax) {
      $maxmin = $i + 1;
      last;
    }
  }

  # Compute the lower hull on the stack @lower
  $hull[++$top] = $points[$minmin];    # push minmin point onto stack
  my $i = $minmax;
  while (++$i <= $maxmin) {
    # the lower line joins points[minmin] with points[maxmin]
    if (CrossProduct([$points[$minmin],$points[$maxmin],$points[$i]]) >= 0 && $i < $maxmin) {
      next;  # ignore points[i] above or on the lower line
    }
    while ($top > 0) {           # there are at least 2 points on the stack
      # test if points[i] is left of the line at the stack top
      if (CrossProduct([$hull[$top-1], $hull[$top], $points[$i]]) > 0) {
        last;                    # points[i] is a new hull vertex
      } else {
        $top--;
      }
    }
    $hull[++$top] = $points[$i]; # push points[i] onto stack
  }

  # Next, compute the upper hull on the stack H above the bottom hull
  if ($maxmax != $maxmin) {       # if distinct xmax points
    $hull[++$top] = $points[$maxmax];  # push maxmax point onto stack
  }
  $bot = $top;
  $i = $maxmin;
  while (--$i >= $minmax) {
    # the upper line joins points[maxmax] with points[minmax]
    if (CrossProduct([$points[$maxmax],$points[$minmax],$points[$i]]) >= 0 && $i > $minmax) {
      next;                        # ignore points[i] below or on the upper line
    }
    while ($top > $bot) {          # at least 2 points on the upper stack
      # test if points[i] is left of the line at the stack top
      if (CrossProduct([$hull[$top-1],$hull[$top],$points[$i]]) > 0) {
        last;                      # points[i] is a new hull vertex
      } else {
        $top--;
      }
    }
    $hull[++$top] = $points[$i];   # push points[i] onto stack
  }
  if ($minmax == $minmin) {
    shift @hull;                   # remove joining endpoint from stack
  }
  my $hull =  Math::Geometry::Planar->new;
  $hull->points([@hull]);
  return $hull;
}
################################################################################
#
# Offset polygons
#
sub offset_polygon {
  my ($self,$offset,$canvas) = @_;
  my $offset_polygons;
  my $pointsref = $self->points;
  if ($pointsref) {
    return [OffsetPolygon($pointsref,$offset,$canvas)];
  } else {
    carp("Can't offset contours - only polygons");
    return;
  }
}
################################################################################
#
# Sorting function to surt points first by X coordinate, then by Y coordinate
#
sub ByXY {
  my @p1 = @$a;
  my @p2 = @$b;
  my $result = $p1[0] <=> $p2[0];
  if ($result){
    return $result;
  } else {
    return $p1[1] <=> $p2[1];
  }
}
################################################################################
#
# convert polygon/contour to gpc contour
#
################################################################################
#
# convert gpc object to a set of contours
# A gpc contour object can consist of multiple outer shapes each having holes,
#
################################################################################
#
# gpc polygon clipping operatins
#
################################################################################
#
my $pi = atan2(1,1) * 4;
#
################################################################################
#
# convert a circle to a polygon
# arguments: first argument is the number of segments,
#            the other arguments are:
#  p1,p2,p3       : 3 points on the circle
# or
#  center,p1      : center and a point on the circle
# or
#  center,radius  : the center and the radius of the circle
#
################################################################################
#
# convert an arc to a polygon
# arguments: first argument is the number of segments,
#            the other arguments are:
#  p1,p2,p3          : startpoint, intermediate point, endpoint
# or
#  $center,p1,p2,$dir : center, startpoint, endpoint,  direction
#                       direction 0 counter clockwise
#                                 1 clockwise
# Note: the return value is a set of points, NOT a closed polygon !!!
#
sub ArcToPoly {
  my @args = @_;
  my @result;
  my ($segments,$p1,$p2,$p3,$center,$direction);
  my ($radius,$angle);
  my ($start_angle, $end_angle);
  if (@args == 4) {      # 3 points
    ($segments,$p1,$p2,$p3) = @args;
    $center = CalcCenter($p1,$p2,$p3);
    $radius = SegmentLength([$p1,$center]);
    # calculate start and end angles
    $start_angle  = CalcAngle($center,$p1);
    my $mid_angle = CalcAngle($center,$p2);
    $end_angle    = CalcAngle($center,$p3);
    if ( (($mid_angle   < $start_angle) && ($start_angle < $end_angle)) ||
         (($start_angle < $end_angle)   && ($end_angle   < $mid_angle)) ||
         (($end_angle   < $mid_angle)   && ($mid_angle   < $start_angle)) ) {
      $direction = 1;
    }
    $angle = $end_angle - $start_angle;
  } elsif (@args == 5) {  # center, begin, end, direction
    ($segments,$center,$p1,$p3,$direction) = @args;
    $radius = SegmentLength([$p1,$center]);
    # calculate start and end angles
    $start_angle = CalcAngle($center,$p1);
    $end_angle   = CalcAngle($center,$p3);
    $angle = $end_angle - $start_angle;
  } else {
    return;
  }

  if ($direction) {  # clockwise
    if ($angle > 0) {
      $angle = $angle - ($pi * 2);
    }
  } else {
    if ($angle < 0) {
      $angle = $angle + ($pi * 2);
    }
  }
  $angle = $angle / $segments;

  push @result,$p1; # start point
  for (my $i = 1 ; $i < $segments ; $i++) {
    push @result, [${$center}[0] + $radius * cos($start_angle + $angle * $i),
                   ${$center}[1] + $radius * sin($start_angle + $angle * $i)]
  }
  push @result,$p3; # end point
  return [@result];
}
################################################################################
#
# Calculate the center of a circle going through 3 points
#
sub CalcCenter {
  my ($p1_ref, $p2_ref, $p3_ref) = @_;
  my ($x1,$y1) = @{$p1_ref};
  my ($x2,$y2) = @{$p2_ref};
  my ($x3,$y3) = @{$p3_ref};
  # calculate midpoints of line segments p1p2 p2p3
  my $u1 = ($x1 + $x2)/2;
  my $v1 = ($y1 + $y2)/2;
  my $u2 = ($x2 + $x3)/2;
  my $v2 = ($y2 + $y3)/2;
  # linear equations y = a + bx
  my ($a1,$a2);
  my ($b1,$b2);
  # intersect (center) coordinates
  my ($xi,$yi);
  # slope of perpendicular = -1/slope
  if ($y1 != $y2) {
    $b1 = - ($x1 - $x2)/($y1 - $y2);
    $a1 = $v1 - $b1 * $u1;
  } else {
    $xi = $u1;
  }
  if ($y2 != $y3) {
    $b2 = - ($x2 - $x3)/($y2 - $y3);
    $a2 = $v2 - $b2 * $u2;
  } else {
    $xi = $u2;
  }
  # parallel lines (colinear is also parallel)
  return if ($b1 == $b2 || (!$b1 && !$b2));
  $xi = - ($a1 - $a2)/($b1 - $b2) if (!$xi);
  $yi = $a1 + $b1 * $xi if ($b1);
  $yi = $a2 + $b2 * $xi if ($b1);
  return [($xi,$yi)];
}
################################################################################
#
# calculate angel of vector p1p2
#
sub CalcAngle {
  my ($p1_ref,$p2_ref) = @_;
  my ($x1,$y1) = @{$p1_ref};
  my ($x2,$y2) = @{$p2_ref};
  return   0   if ($y1 == $y2 && $x1 == $x2);
  return   0   if ($y1 == $y2 && $x1 < $x2);
  return $pi   if ($y1 == $y2 && $x1 > $x2);
  return $pi/2 if ($x1 == $x2 && $y1 < $y2);
  return ($pi *3)/2 if ($x1 == $x2 && $y1 > $y2);
  my $angle = atan2($y2-$y1,$x2-$x1);
  return $angle;
}
################################################################################
#
#         This program is an implementation of a fast polygon
# triangulation algorithm based on the paper "A simple and fast
# incremental randomized algorithm for computing trapezoidal
# decompositions and for triangulating polygons" by Raimund Seidel.
#
#         The algorithm handles simple polygons with holes. The input is
# specified as contours. The outermost contour is anti-clockwise, while
# all the inner contours must be clockwise. No point should be repeated
# in the input. A sample input file 'data_1' is provided.
#
#         The output is a reference to a list of triangles. Each triangle
# is ar reference to an array fo three points, each point is a reference
# to an array holdign the x and y coordinates of the point.
# The number of output triangles produced for a polygon with n points is,
#         (n - 2) + 2*(#holes)
#
#         The program is a translation to perl of the C program written by
# Narkhede A. and Manocha D., Fast polygon triangulation algorithm based
# on Seidel's Algorithm, UNC-CH, 1994.
# Note that in this perl version, there are no statically allocated arrays
# so the only limit is the amount of (virtual) memory available.
#
# See also:
#
#   R. Seidel
#     "A simple and Fast Randomized Algorithm for Computing Trapezoidal
#      Decompositions and for Triangulating Polygons"
#     "Computational Geometry Theory & Applications"
#      Number = 1, Year 1991, Volume 1, Pages 51-64
#
#   J. O'Rourke
#     "Computational Geometry in {C}"
#      Cambridge University Press  - 1994
#
# Input specified as a contour with the restrictions mentioned above:
#   - first polygon is the outer shape and must be anti-clockwise.
#   - next polygons are inner shapels (holes) must be clockwise.
#   - Inner and outer shapes must be simple .
#
# Every contour is specified by giving all its points in order. No
# point shoud be repeated. i.e. if the outer contour is a square,
# only the four distinct endpoints shopudl be specified in order.
#
# Returns a reference to an array holding the triangles.
#

my $C_EPS     = 1e-10; # tolerance value: Used for making
                       # all decisions about collinearity or
                       # left/right of segment. Decrease
                       # this value if the input points are
                       # spaced very close together

my $INFINITY = 1<<29;

my $TRUE  = 1;
my $FALSE = 0;

my $T_X    = 1;
my $T_Y    = 2;
my $T_SINK = 3;

my $ST_VALID   = 1;
my $ST_INVALID = 2;

my $FIRSTPT = 1;
my $LASTPT  = 2;

my $S_LEFT  = 1;
my $S_RIGHT = 2;

my $SP_SIMPLE_LRUP =  1; # for splitting trapezoids
my $SP_SIMPLE_LRDN =  2;
my $SP_2UP_2DN     =  3;
my $SP_2UP_LEFT    =  4;
my $SP_2UP_RIGHT   =  5;
my $SP_2DN_LEFT    =  6;
my $SP_2DN_RIGHT   =  7;
my $SP_NOSPLIT     = -1;

my $TRI_LHS = 1;
my $TRI_RHS = 2;
my $TR_FROM_UP = 1;    # for traverse-direction
my $TR_FROM_DN = 2;

my $choose_idx = 1;
my @permute;
my $q_idx;
my $tr_idx;
my @qs;       # Query structure
my @tr;       # Trapezoid structure
my @seg;      # Segment table

my @mchain; # Table to hold all the monotone
            # polygons . Each monotone polygon
            # is a circularly linked list
my @vert;   # chain init. information. This
            # is used to decide which
            # monotone polygon to split if
            # there are several other
            # polygons touching at the same
            # vertex
my @mon;    # contains position of any vertex in
            # the monotone chain for the polygon
my @visited;
my @op;     # contains the resulting list of triangles
            # and their vertex number
my ($chain_idx, $op_idx, $mon_idx);

sub TriangulatePolygon {

  $choose_idx = 1;
  @seg = ();
  @mchain = ();
  @vert = ();
  @mon = ();
  @visited = ();
  @op = ();

  my ($polygonrefs) = @_;
  my @polygons = @{$polygonrefs};

  my $ccount = 0;
  my $i = 1;
  while ($ccount < @polygons) {
    my @vertexarray = @{$polygons[$ccount]};
    my $npoints     = @vertexarray;
    my $first = $i;
    my $last  = $first + $npoints - 1;
    for (my $j = 0; $j < $npoints; $j++, $i++) {
      my @vertex = @{$vertexarray[$j]};
      $seg[$i]{v0}{x} = $vertex[0];
      $seg[$i]{v0}{y} = $vertex[1];
      if ($i == $last) {
        $seg[$i]{next} = $first;
        $seg[$i]{prev} = $i-1;
        my %tmp = %{$seg[$i]{v0}};
        $seg[$i-1]{v1} = \%tmp;
      } elsif ($i == $first) {
        $seg[$i]{next} = $i+1;
        $seg[$i]{prev} = $last;
        my %tmp = %{$seg[$i]{v0}};
        $seg[$last]{v1} = \%tmp;
      } else {
        $seg[$i]{prev} = $i-1;
        $seg[$i]{next} = $i+1;
        my %tmp = %{$seg[$i]{v0}};
        $seg[$i-1]{v1} = \%tmp;
      }
      $seg[$i]{is_inserted} = $FALSE;
    }
    $ccount++;
  }

  my $n = $i-1;

  _generate_random_ordering($n);
  _construct_trapezoids($n);
  my $nmonpoly = _monotonate_trapezoids($n);
  my $ntriangles = _triangulate_monotone_polygons($n, $nmonpoly);
  # now get the coordinates for all the triangles
  my @result;
  for (my $i = 0; $i < $ntriangles; $i++) {
    my @vertices = @{$op[$i]};
    my $triangle = [[$seg[$vertices[0]]{v0}{x},$seg[$vertices[0]]{v0}{y}],
                    [$seg[$vertices[1]]{v0}{x},$seg[$vertices[1]]{v0}{y}],
                    [$seg[$vertices[2]]{v0}{x},$seg[$vertices[2]]{v0}{y}]];
    push @result,$triangle;
  }
  return [@result];;
}

# Generate a random permutation of the segments 1..n
sub _generate_random_ordering {
  @permute = ();
  my ($n) = @_;
  my @input;
  for (my $i = 1 ; $i <= $n ; $i++) {
    $input[$i] = $i;
  }
  my $i = 1;
  for (my $i = 1 ; $i <= $n ; $i++) {
    my $m = int rand($#input) + 1;
    $permute[$i] = $input[$m];
    splice @input,$m,1;
  }
}

# Return the next segment in the generated random ordering of all the
# segments in S
sub _choose_segment {
  return $permute[$choose_idx++];
}

# Return a new node to be added into the query tree
sub _newnode {
  return $q_idx++;
}

# Return a free trapezoid
sub _newtrap {
  $tr[$tr_idx]{lseg} = -1;
  $tr[$tr_idx]{rseg} = -1;
  $tr[$tr_idx]{state} = $ST_VALID;
  # next statements added to prevent 'uninitialized' warnings
  $tr[$tr_idx]{d0} = 0;
  $tr[$tr_idx]{d1} = 0;
  $tr[$tr_idx]{u0} = 0;
  $tr[$tr_idx]{u1} = 0;
  $tr[$tr_idx]{usave} = 0;
  $tr[$tr_idx]{uside} = 0;
  return $tr_idx++;
}

# Floating point number comparison
sub _fp_equal {
  my ($X, $Y, $POINTS) = @_;
  my ($tX, $tY);
  $tX = sprintf("%.${POINTS}g", $X);
  $tY = sprintf("%.${POINTS}g", $Y);
  return $tX eq $tY;
}

# Return the maximum of the two points
sub _max {
  my ($v0_ref, $v1_ref) = @_;
  my %v0   = %{$v0_ref};
  my %v1   = %{$v1_ref};
  if ($v0{y} > $v1{y} + $C_EPS) {
    return \%v0;
  } elsif (_fp_equal($v0{y}, $v1{y}, $precision)) {
    if ($v0{x} > $v1{x} + $C_EPS) {
      return \%v0;
    } else {
      return \%v1;
    }
  } else {
    return \%v1;
  }
}

# Return the minimum of the two points
sub _min {
  my ($v0_ref, $v1_ref) = @_;
  my %v0   = %{$v0_ref};
  my %v1   = %{$v1_ref};
  if ($v0{y} < $v1{y} - $C_EPS) {
    return \%v0;
  } elsif (_fp_equal($v0{y}, $v1{y}, $precision)) {
    if ($v0{x} < $v1{x}) {
      return \%v0;
    } else {
      return \%v1;
    }
  } else {
    return \%v1;
  }
}

sub _greater_than {
  my ($v0_ref, $v1_ref) = @_;
  my %v0 = %{$v0_ref};
  my %v1 = %{$v1_ref};
  if ($v0{y} > $v1{y} + $C_EPS) {
    return 1;
  } elsif ($v0{y} < $v1{y} - $C_EPS) {
    return 0;
  } else {
    return ($v0{x} > $v1{x});
  }
}

sub _equal_to {
  my ($v0_ref, $v1_ref) = @_;
  my %v0 = %{$v0_ref};
  my %v1 = %{$v1_ref};
  return ( _fp_equal($v0{y}, $v1{y}, $precision) &&
           _fp_equal($v0{x}, $v1{x}, $precision) );
}

sub _greater_than_equal_to {
  my ($v0_ref, $v1_ref) = @_;
  my %v0 = %{$v0_ref};
  my %v1 = %{$v1_ref};
  if ($v0{y} > $v1{y} + $C_EPS) {
    return 1;
  } elsif ($v0{y} < $v1{y} - $C_EPS) {
    return 0;
  } else {
    return ($v0{x} >= $v1{x});
  }
}

sub _less_than {
  my ($v0_ref, $v1_ref) = @_;
  my %v0 = %{$v0_ref};
  my %v1 = %{$v1_ref};
  if ($v0{y} < $v1{y} - $C_EPS) {
    return 1;
  } elsif ($v0{y} > $v1{y} + $C_EPS) {
    return 0;
  } else {
    return ($v0{x} < $v1{x});
  }
}

# Initilialise the query structure (Q) and the trapezoid table (T)
# when the first segment is added to start the trapezoidation. The
# query-tree starts out with 4 trapezoids, one S-node and 2 Y-nodes
#
#                4
#   -----------------------------------
#                 \
#       1          \        2
#                   \
#   -----------------------------------
#                3
#

sub _init_query_structure {
  my ($segnum) = @_;

  my ($i1,$i2,$i3,$i4,$i5,$i6,$i7,$root);
  my ($t1,$t2,$t3,$t4);

  @qs = ();
  @tr = ();

  $q_idx  =  $tr_idx = 1;

  $i1 = _newnode();
  $qs[$i1]{nodetype} = $T_Y;

  my %tmpmax = %{_max($seg[$segnum]{v0}, $seg[$segnum]{v1})}; # root
  $qs[$i1]{yval} = {x => $tmpmax{x} , y => $tmpmax{y}};
  $root = $i1;

  $qs[$i1]{right} = $i2 = _newnode();
  $qs[$i2]{nodetype} = $T_SINK;
  $qs[$i2]{parent} = $i1;

  $qs[$i1]{left} = $i3 = _newnode();
  $qs[$i3]{nodetype} = $T_Y;
  my %tmpmin = %{_min($seg[$segnum]{v0}, $seg[$segnum]{v1})}; # root
  $qs[$i3]{yval} = {x => $tmpmin{x} , y => $tmpmin{y}};
  $qs[$i3]{parent} = $i1;

  $qs[$i3]{left} = $i4 = _newnode();
  $qs[$i4]{nodetype} = $T_SINK;
  $qs[$i4]{parent} = $i3;

  $qs[$i3]{right} = $i5 = _newnode();
  $qs[$i5]{nodetype} = $T_X;
  $qs[$i5]{segnum} = $segnum;
  $qs[$i5]{parent} = $i3;

  $qs[$i5]{left} = $i6 = _newnode();
  $qs[$i6]{nodetype} = $T_SINK;
  $qs[$i6]{parent} = $i5;

  $qs[$i5]{right} = $i7 = _newnode();
  $qs[$i7]{nodetype} = $T_SINK;
  $qs[$i7]{parent} = $i5;

  $t1 = _newtrap();    # middle left
  $t2 = _newtrap();    # middle right
  $t3 = _newtrap();    # bottom-most
  $t4 = _newtrap();    # topmost

  $tr[$t1]{hi} = {x => $qs[$i1]{yval}{x} , y => $qs[$i1]{yval}{y}};
  $tr[$t2]{hi} = {x => $qs[$i1]{yval}{x} , y => $qs[$i1]{yval}{y}};
  $tr[$t4]{lo} = {x => $qs[$i1]{yval}{x} , y => $qs[$i1]{yval}{y}};
  $tr[$t1]{lo} = {x => $qs[$i3]{yval}{x} , y => $qs[$i3]{yval}{y}};
  $tr[$t2]{lo} = {x => $qs[$i3]{yval}{x} , y => $qs[$i3]{yval}{y}};
  $tr[$t3]{hi} = {x => $qs[$i3]{yval}{x} , y => $qs[$i3]{yval}{y}};
  $tr[$t4]{hi} = {x =>      $INFINITY , y =>      $INFINITY};
  $tr[$t3]{lo} = {x => -1 * $INFINITY , y => -1 * $INFINITY};
  $tr[$t1]{rseg} = $tr[$t2]{lseg} = $segnum;
  $tr[$t1]{u0} = $tr[$t2]{u0} = $t4;
  $tr[$t1]{d0} = $tr[$t2]{d0} = $t3;
  $tr[$t4]{d0} = $tr[$t3]{u0} = $t1;
  $tr[$t4]{d1} = $tr[$t3]{u1} = $t2;

  $tr[$t1]{sink} = $i6;
  $tr[$t2]{sink} = $i7;
  $tr[$t3]{sink} = $i4;
  $tr[$t4]{sink} = $i2;

  $tr[$t1]{state} = $tr[$t2]{state} = $ST_VALID;
  $tr[$t3]{state} = $tr[$t4]{state} = $ST_VALID;

  $qs[$i2]{trnum} = $t4;
  $qs[$i4]{trnum} = $t3;
  $qs[$i6]{trnum} = $t1;
  $qs[$i7]{trnum} = $t2;

  $seg[$segnum]{is_inserted} = $TRUE;
  return $root;
}

# Update the roots stored for each of the endpoints of the segment.
# This is done to speed up the location-query for the endpoint when
# the segment is inserted into the trapezoidation subsequently
#
sub _find_new_roots {
  my ($segnum) = @_;

  return if ($seg[$segnum]{is_inserted});

  $seg[$segnum]{root0} = _locate_endpoint($seg[$segnum]{v0}, $seg[$segnum]{v1}, $seg[$segnum]{root0});
  $seg[$segnum]{root0} = $tr[$seg[$segnum]{root0}]{sink};

  $seg[$segnum]{root1} = _locate_endpoint($seg[$segnum]{v1}, $seg[$segnum]{v0}, $seg[$segnum]{root1});
  $seg[$segnum]{root1} = $tr[$seg[$segnum]{root1}]{sink};
}

# Main routine to perform trapezoidation
sub _construct_trapezoids {
  my ($nseg) = @_; #

  # Add the first segment and get the query structure and trapezoid
  # list initialised

  my $root = _init_query_structure(_choose_segment());

  for (my $i = 1 ; $i <= $nseg; $i++) {
    $seg[$i]{root0} = $seg[$i]{root1} = $root;
  }
  for (my $h = 1; $h <= _math_logstar_n($nseg); $h++) {
    for (my $i = _math_N($nseg, $h -1) + 1; $i <= _math_N($nseg, $h); $i++) {
      _add_segment(_choose_segment());
    }
    # Find a new root for each of the segment endpoints
    for (my $i = 1; $i <= $nseg; $i++) {
      _find_new_roots($i);
    }
  }
  for (my $i = _math_N($nseg, _math_logstar_n($nseg)) + 1; $i <= $nseg; $i++) {
    _add_segment(_choose_segment());
  }
}

# Add in the new segment into the trapezoidation and update Q and T
# structures. First locate the two endpoints of the segment in the
# Q-structure. Then start from the topmost trapezoid and go down to
# the  lower trapezoid dividing all the trapezoids in between .
#

sub _add_segment {
  my ($segnum) = @_;

  my ($tu, $tl, $sk, $tfirst, $tlast, $tnext);
  my ($tfirstr, $tlastr, $tfirstl, $tlastl);
  my ($i1, $i2, $t, $t1, $t2, $tn);
  my $tritop = 0;
  my $tribot = 0;
  my $is_swapped = 0;
  my $tmptriseg;
  my %s = %{$seg[$segnum]};

  if (_greater_than($s{v1}, $s{v0})) { # Get higher vertex in v0
    my %tmp;
    %tmp   = %{$s{v0}};
    $s{v0} = {x => $s{v1}{x} , y => $s{v1}{y}};
    $s{v1} = {x =>   $tmp{x} , y =>   $tmp{y}};
    my $tmp   = $s{root0};
    $s{root0} = $s{root1};
    $s{root1} = $tmp;
    $is_swapped = 1;
  }

  if (($is_swapped) ? !_inserted($segnum, $LASTPT) :
       !_inserted($segnum, $FIRSTPT)) { # insert v0 in the tree
    my $tmp_d;

    $tu = _locate_endpoint($s{v0}, $s{v1}, $s{root0});
    $tl = _newtrap();          # tl is the new lower trapezoid
    $tr[$tl]{state} = $ST_VALID;
    my %tmp = %{$tr[$tu]};
    my %tmphi = %{$tmp{hi}};
    my %tmplo = %{$tmp{lo}};
    $tr[$tl] = \%tmp;
    $tr[$tl]{hi} = {x => $tmphi{x} , y => $tmphi{y}};
    $tr[$tl]{lo} = {x => $tmplo{x} , y => $tmplo{y}};
    $tr[$tu]{lo} = {x => $s{v0}{x} , y => $s{v0}{y}};
    $tr[$tl]{hi} = {x => $s{v0}{x} , y => $s{v0}{y}};
    $tr[$tu]{d0} = $tl;
    $tr[$tu]{d1} = 0;
    $tr[$tl]{u0} = $tu;
    $tr[$tl]{u1} = 0;

    if ((($tmp_d = $tr[$tl]{d0}) > 0) && ($tr[$tmp_d]{u0} == $tu)) {
      $tr[$tmp_d]{u0} = $tl;
    }
    if ((($tmp_d = $tr[$tl]{d0}) > 0) && ($tr[$tmp_d]{u1} == $tu)) {
      $tr[$tmp_d]{u1} = $tl;
    }

    if ((($tmp_d = $tr[$tl]{d1}) > 0) && ($tr[$tmp_d]{u0} == $tu)) {
      $tr[$tmp_d]{u0} = $tl;
    }
    if ((($tmp_d = $tr[$tl]{d1}) > 0) && ($tr[$tmp_d]{u1} == $tu)) {
      $tr[$tmp_d]{u1} = $tl;
    }

    # Now update the query structure and obtain the sinks for the
    # two trapezoids

    $i1 = _newnode();          # Upper trapezoid sink
    $i2 = _newnode();          # Lower trapezoid sink
    $sk = $tr[$tu]{sink};

    $qs[$sk]{nodetype} = $T_Y;
    $qs[$sk]{yval}     = {x => $s{v0}{x} , y=> $s{v0}{y}};
    $qs[$sk]{segnum}   = $segnum;  # not really reqd ... maybe later
    $qs[$sk]{left}     = $i2;
    $qs[$sk]{right}    = $i1;

    $qs[$i1]{nodetype} = $T_SINK;
    $qs[$i1]{trnum}    = $tu;
    $qs[$i1]{parent}   = $sk;

    $qs[$i2]{nodetype} = $T_SINK;
    $qs[$i2]{trnum}    = $tl;
    $qs[$i2]{parent}   = $sk;

    $tr[$tu]{sink} = $i1;
    $tr[$tl]{sink} = $i2;
    $tfirst = $tl;
  } else {  # v0 already present
            # Get the topmost intersecting trapezoid
    $tfirst = _locate_endpoint($s{v0}, $s{v1}, $s{root0});
    $tritop = 1;
  }


  if (($is_swapped) ? !_inserted($segnum, $FIRSTPT) :
       !_inserted($segnum, $LASTPT)) { # insert v1 in the tree
    my $tmp_d;

    $tu = _locate_endpoint($s{v1}, $s{v0}, $s{root1});
    $tl = _newtrap();         # tl is the new lower trapezoid
    $tr[$tl]{state} = $ST_VALID;
    my %tmp = %{$tr[$tu]};
    my %tmphi = %{$tmp{hi}};
    my %tmplo = %{$tmp{lo}};
    $tr[$tl] = \%tmp;
    $tr[$tl]{hi} = {x => $tmphi{x} , y => $tmphi{y}};
    $tr[$tl]{lo} = {x => $tmplo{x} , y => $tmplo{y}};
    $tr[$tu]{lo} = {x => $s{v1}{x} , y => $s{v1}{y}};
    $tr[$tl]{hi} = {x => $s{v1}{x} , y => $s{v1}{y}};
    $tr[$tu]{d0} = $tl;
    $tr[$tu]{d1} = 0;
    $tr[$tl]{u0} = $tu;
    $tr[$tl]{u1} = 0;

    if ((($tmp_d = $tr[$tl]{d0}) > 0) && ($tr[$tmp_d]{u0} == $tu)) {
      $tr[$tmp_d]{u0} = $tl;
    }
    if ((($tmp_d = $tr[$tl]{d0}) > 0) && ($tr[$tmp_d]{u1} == $tu)) {
      $tr[$tmp_d]{u1} = $tl;
    }

    if ((($tmp_d = $tr[$tl]{d1}) > 0) && ($tr[$tmp_d]{u0} == $tu)) {
      $tr[$tmp_d]{u0} = $tl;
    }
    if ((($tmp_d = $tr[$tl]{d1}) > 0) && ($tr[$tmp_d]{u1} == $tu)) {
      $tr[$tmp_d]{u1} = $tl;
    }

    # Now update the query structure and obtain the sinks for the
    # two trapezoids

    $i1 = _newnode();          # Upper trapezoid sink
    $i2 = _newnode();          # Lower trapezoid sink
    $sk = $tr[$tu]{sink};

    $qs[$sk]{nodetype} = $T_Y;
    $qs[$sk]{yval}     = {x => $s{v1}{x} , y => $s{v1}{y}};
    $qs[$sk]{segnum}   = $segnum;   # not really reqd ... maybe later
    $qs[$sk]{left}     = $i2;
    $qs[$sk]{right}    = $i1;

    $qs[$i1]{nodetype} = $T_SINK;
    $qs[$i1]{trnum}    = $tu;
    $qs[$i1]{parent}   = $sk;

    $qs[$i2]{nodetype} = $T_SINK;
    $qs[$i2]{trnum}    = $tl;
    $qs[$i2]{parent}   = $sk;

    $tr[$tu]{sink} = $i1;
    $tr[$tl]{sink} = $i2;
    $tlast = $tu;
  } else {  # v1 already present
            # Get the lowermost intersecting trapezoid
    $tlast = _locate_endpoint($s{v1}, $s{v0}, $s{root1});
    $tribot = 1;
  }

  # Thread the segment into the query tree creating a new X-node
  # First, split all the trapezoids which are intersected by s into
  # two

  $t = $tfirst;               # topmost trapezoid

  while (($t > 0) &&
         _greater_than_equal_to($tr[$t]{lo}, $tr[$tlast]{lo})) {
                              # traverse from top to bot
    my ($t_sav, $tn_sav);
    $sk = $tr[$t]{sink};
    $i1 = _newnode();          # left trapezoid sink
    $i2 = _newnode();          # right trapezoid sink

    $qs[$sk]{nodetype} = $T_X;
    $qs[$sk]{segnum}   = $segnum;
    $qs[$sk]{left}     = $i1;
    $qs[$sk]{right}    = $i2;

    $qs[$i1]{nodetype} = $T_SINK;   # left trapezoid (use existing one)
    $qs[$i1]{trnum}    = $t;
    $qs[$i1]{parent}   = $sk;

    $qs[$i2]{nodetype} = $T_SINK;   # right trapezoid (allocate new)
    $qs[$i2]{trnum}    = $tn = _newtrap();
    $tr[$tn]{state}    = $ST_VALID;
    $qs[$i2]{parent}   = $sk;

    if ($t == $tfirst) {
      $tfirstr = $tn;
    }
    if (_equal_to($tr[$t]{lo}, $tr[$tlast]{lo})) {
      $tlastr = $tn;
    }

    my %tmp = %{$tr[$t]};
    my %tmphi = %{$tmp{hi}};
    my %tmplo = %{$tmp{lo}};
    $tr[$tn] = \%tmp;
    $tr[$tn]{hi} = {x => $tmphi{x} , y => $tmphi{y}};
    $tr[$tn]{lo} = {x => $tmplo{x} , y => $tmplo{y}};
    $tr[$t]{sink} = $i1;
    $tr[$tn]{sink} = $i2;
    $t_sav  = $t;
    $tn_sav = $tn;

    # error

    if (($tr[$t]{d0} <= 0) && ($tr[$t]{d1} <= 0)) {  # case cannot arise
      print "add_segment: error\n";

    # only one trapezoid below. partition t into two and make the
    # two resulting trapezoids t and tn as the upper neighbours of
    # the sole lower trapezoid

    } elsif (($tr[$t]{d0} > 0) && ($tr[$t]{d1} <= 0)) { # Only one trapezoid below
      if (($tr[$t]{u0} > 0) && ($tr[$t]{u1} > 0)) {     # continuation of a chain from abv.
        if ($tr[$t]{usave} > 0) {                 # three upper neighbours
          if ($tr[$t]{uside} == $S_LEFT) {
            $tr[$tn]{u0} = $tr[$t]{u1};
            $tr[$t]{u1}  = -1;
            $tr[$tn]{u1} = $tr[$t]{usave};

            $tr[$tr[$t]{u0}]{d0}  = $t;
            $tr[$tr[$tn]{u0}]{d0} = $tn;
            $tr[$tr[$tn]{u1}]{d0} = $tn;
          } else {                                # intersects in the right
            $tr[$tn]{u1} = -1;
            $tr[$tn]{u0} = $tr[$t]{u1};
            $tr[$t]{u1}  = $tr[$t]{u0};
            $tr[$t]{u0}  = $tr[$t]{usave};

            $tr[$tr[$t]{u0}]{d0} = $t;
            $tr[$tr[$t]{u1}]{d0} = $t;
            $tr[$tr[$tn]{u0}]{d0} = $tn;
          }

          $tr[$t]{usave} = $tr[$tn]{usave} = 0;
        } else {                                  # No usave.... simple case
          $tr[$tn]{u0} = $tr[$t]{u1};
          $tr[$t]{u1}  = $tr[$tn]{u1} = -1;
          $tr[$tr[$tn]{u0}]{d0} = $tn;
        }
      } else {                              # fresh seg. or upward cusp
        my $tmp_u = $tr[$t]{u0};
        my ($td0, $td1);
        if ((($td0 = $tr[$tmp_u]{d0}) > 0) &&
            (($td1 = $tr[$tmp_u]{d1}) > 0)) {  # upward cusp
          if (($tr[$td0]{rseg} > 0) &&
              !_is_left_of($tr[$td0]{rseg}, $s{v1})) {
            $tr[$t]{u0} = $tr[$t]{u1} = $tr[$tn]{u1} = -1;
            $tr[$tr[$tn]{u0}]{d1} = $tn;
          } else {   # cusp going leftwards
            $tr[$tn]{u0} = $tr[$tn]{u1} = $tr[$t]{u1} = -1;
            $tr[$tr[$t]{u0}]{d0} = $t;
          }
        } else {     # fresh segment
          $tr[$tr[$t]{u0}]{d0} = $t;
          $tr[$tr[$t]{u0}]{d1} = $tn;
        }
      }

      if (_fp_equal($tr[$t]{lo}{y}, $tr[$tlast]{lo}{y}, $precision) &&
          _fp_equal($tr[$t]{lo}{x}, $tr[$tlast]{lo}{x}, $precision) && $tribot) {
        # bottom forms a triangle

        if ($is_swapped) {
          $tmptriseg = $seg[$segnum]{prev};
        } else {
          $tmptriseg = $seg[$segnum]{next};
        }

        if (($tmptriseg > 0) && _is_left_of($tmptriseg, $s{v0})) { # L-R downward cusp
          $tr[$tr[$t]{d0}]{u0} = $t;
          $tr[$tn]{d0} = $tr[$tn]{d1} = -1;
        } else { # R-L downward cusp
          $tr[$tr[$tn]{d0}]{u1} = $tn;
          $tr[$t]{d0} = $tr[$t]{d1} = -1;
        }
      } else {
        if (($tr[$tr[$t]{d0}]{u0} > 0) && ($tr[$tr[$t]{d0}]{u1} > 0)) {
          if ($tr[$tr[$t]{d0}]{u0} == $t) {  # passes thru LHS
            $tr[$tr[$t]{d0}]{usave} = $tr[$tr[$t]{d0}]{u1};
            $tr[$tr[$t]{d0}]{uside} = $S_LEFT;
          } else {
            $tr[$tr[$t]{d0}]{usave} = $tr[$tr[$t]{d0}]{u0};
            $tr[$tr[$t]{d0}]{uside} = $S_RIGHT;
          }
        }
        $tr[$tr[$t]{d0}]{u0} = $t;
        $tr[$tr[$t]{d0}]{u1} = $tn;
      }

      $t = $tr[$t]{d0};

    } elsif (($tr[$t]{d0} <= 0) && ($tr[$t]{d1} > 0)) {  # Only one trapezoid below
      if (($tr[$t]{u0} > 0) && ($tr[$t]{u1} > 0)) {      # continuation of a chain from abv.
        if ($tr[$t]{usave} > 0) {     # three upper neighbours
          if ($tr[$t]{uside} == $S_LEFT) {
            $tr[$tn]{u0} = $tr[$t]{u1};
            $tr[$t]{u1}  = -1;
            $tr[$tn]{u1} = $tr[$t]{usave};

            $tr[$tr[$t]{u0}]{d0}  = $t;
            $tr[$tr[$tn]{u0}]{d0} = $tn;
            $tr[$tr[$tn]{u1}]{d0} = $tn;
          } else {  # intersects in the right
            $tr[$tn]{u1} = -1;
            $tr[$tn]{u0} = $tr[$t]{u1};
            $tr[$t]{u1}  = $tr[$t]{u0};
            $tr[$t]{u0}  = $tr[$t]{usave};

            $tr[$tr[$t]{u0}]{d0}  = $t;
            $tr[$tr[$t]{u1}]{d0}  = $t;
            $tr[$tr[$tn]{u0}]{d0} = $tn;
          }

          $tr[$t]{usave} = $tr[$tn]{usave} = 0;

        } else {  # No usave.... simple case
          $tr[$tn]{u0} = $tr[$t]{u1};
          $tr[$t]{u1} = $tr[$tn]{u1} = -1;
          $tr[$tr[$tn]{u0}]{d0} = $tn;
        }
      } else {  # fresh seg. or upward cusp
        my $tmp_u = $tr[$t]{u0};
        my ($td0,$td1);
        if ((($td0 = $tr[$tmp_u]{d0}) > 0) &&
            (($td1 = $tr[$tmp_u]{d1}) > 0)) {    # upward cusp
          if (($tr[$td0]{rseg} > 0) &&
              !_is_left_of($tr[$td0]{rseg}, $s{v1})) {
              $tr[$t]{u0} = $tr[$t]{u1} = $tr[$tn]{u1} = -1;
              $tr[$tr[$tn]{u0}]{d1} = $tn;
          } else {
            $tr[$tn]{u0} = $tr[$tn]{u1} = $tr[$t]{u1} = -1;
            $tr[$tr[$t]{u0}]{d0} = $t;
          }
        } else {  # fresh segment
          $tr[$tr[$t]{u0}]{d0} = $t;
          $tr[$tr[$t]{u0}]{d1} = $tn;
        }
      }

      if (_fp_equaL($tr[$t]{lo}{y}, $tr[$tlast]{lo}{y}, $precision) &&
          _fp_equal($tr[$t]{lo}{x}, $tr[$tlast]{lo}{x}, $precision) && $tribot) {
        # bottom forms a triangle
        my $tmpseg;

        if ($is_swapped) {
          $tmptriseg = $seg[$segnum]{prev};
        } else {
          $tmptriseg = $seg[$segnum]{next};
        }

        if (($tmpseg > 0) && _is_left_of($tmpseg, $s{v0})) {
          # L-R downward cusp
          $tr[$tr[$t]{d1}]{u0} = $t;
          $tr[$tn]{d0} = $tr[$tn]{d1} = -1;
        } else {
          # R-L downward cusp
          $tr[$tr[$tn]{d1}]{u1} = $tn;
          $tr[$t]{d0} = $tr[$t]{d1} = -1;
        }
      } else {
        if (($tr[$tr[$t]{d1}]{u0} > 0) && ($tr[$tr[$t]{d1}]{u1} > 0)) {
          if ($tr[$tr[$t]{d1}]{u0} == $t) { # passes thru LHS
            $tr[$tr[$t]{d1}]{usave} = $tr[$tr[$t]{d1}]{u1};
            $tr[$tr[$t]{d1}]{uside} = $S_LEFT;
          } else {
            $tr[$tr[$t]{d1}]{usave} = $tr[$tr[$t]{d1}]{u0};
            $tr[$tr[$t]{d1}]{uside} = $S_RIGHT;
          }
        }
        $tr[$tr[$t]{d1}]{u0} = $t;
        $tr[$tr[$t]{d1}]{u1} = $tn;
      }

      $t = $tr[$t]{d1};

    # two trapezoids below. Find out which one is intersected by
    # this segment and proceed down that one

    } else {
      my $tmpseg = $tr[$tr[$t]{d0}]{rseg};
      my ($y0,$yt);
      my %tmppt;
      my ($tnext, $i_d0, $i_d1);

      $i_d0 = $i_d1 = $FALSE;
      if (_fp_equal($tr[$t]{lo}{y}, $s{v0}{y}, $precision)) {
        if ($tr[$t]{lo}{x} > $s{v0}{x}) {
          $i_d0 = $TRUE;
        } else {
          $i_d1 = $TRUE;
        }
      } else {
        $tmppt{y} = $y0 = $tr[$t]{lo}{y};
        $yt       = ($y0 - $s{v0}{y})/($s{v1}{y} - $s{v0}{y});
        $tmppt{x} = $s{v0}{x} + $yt * ($s{v1}{x} - $s{v0}{x});

        if (_less_than(\%tmppt, $tr[$t]{lo})) {
          $i_d0 = $TRUE;
        } else {
          $i_d1 = $TRUE;
        }
      }

      # check continuity from the top so that the lower-neighbour
      # values are properly filled for the upper trapezoid

      if (($tr[$t]{u0} > 0) && ($tr[$t]{u1} > 0)) {  # continuation of a chain from abv.
        if ($tr[$t]{usave} > 0) {  # three upper neighbours
          if ($tr[$t]{uside} == $S_LEFT) {
            $tr[$tn]{u0} = $tr[$t]{u1};
            $tr[$t]{u1}  = -1;
            $tr[$tn]{u1} = $tr[$t]{usave};

            $tr[$tr[$t]{u0}]{d0}  = $t;
            $tr[$tr[$tn]{u0}]{d0} = $tn;
            $tr[$tr[$tn]{u1}]{d0} = $tn;
          } else {                    # intersects in the right
            $tr[$tn]{u1} = -1;
            $tr[$tn]{u0} = $tr[$t]{u1};
            $tr[$t]{u1}  = $tr[$t]{u0};
            $tr[$t]{u0}  = $tr[$t]{usave};

            $tr[$tr[$t]{u0}]{d0}  = $t;
            $tr[$tr[$t]{u1}]{d0}  = $t;
            $tr[$tr[$tn]{u0}]{d0} = $tn;
          }

          $tr[$t]{usave} = $tr[$tn]{usave} = 0;
        } else {                      # No usave.... simple case
          $tr[$tn]{u0} = $tr[$t]{u1};
          $tr[$tn]{u1} = -1;
          $tr[$t]{u1}  = -1;
          $tr[$tr[$tn]{u0}]{d0} = $tn;
        }
      } else {                        # fresh seg. or upward cusp
        my $tmp_u = $tr[$t]{u0};
        my ($td0, $td1);
        if ((($td0 = $tr[$tmp_u]{d0}) > 0) &&
            (($td1 = $tr[$tmp_u]{d1}) > 0)) {  # upward cusp
          if (($tr[$td0]{rseg} > 0) &&
              !_is_left_of($tr[$td0]{rseg}, $s{v1})) {
            $tr[$t]{u0} = $tr[$t]{u1} = $tr[$tn]{u1} = -1;
            $tr[$tr[$tn]{u0}]{d1} = $tn;
          } else {
            $tr[$tn]{u0} = $tr[$tn]{u1} = $tr[$t]{u1} = -1;
            $tr[$tr[$t]{u0}]{d0} = $t;
          }
        } else {                               # fresh segment
          $tr[$tr[$t]{u0}]{d0} = $t;
          $tr[$tr[$t]{u0}]{d1} = $tn;
        }
      }

      if (_fp_equal($tr[$t]{lo}{y}, $tr[$tlast]{lo}{y}, $precision) &&
          _fp_equal($tr[$t]{lo}{x}, $tr[$tlast]{lo}{x}, $precision) && $tribot) {
        # this case arises only at the lowest trapezoid.. i.e.
        # tlast, if the lower endpoint of the segment is
        # already inserted in the structure

        $tr[$tr[$t]{d0}]{u0} = $t;
        $tr[$tr[$t]{d0}]{u1} = -1;
        $tr[$tr[$t]{d1}]{u0} = $tn;
        $tr[$tr[$t]{d1}]{u1} = -1;

        $tr[$tn]{d0} = $tr[$t]{d1};
        $tr[$t]{d1} = $tr[$tn]{d1} = -1;

        $tnext = $tr[$t]{d1};
      } elsif ($i_d0) {               # intersecting d0
        $tr[$tr[$t]{d0}]{u0} = $t;
        $tr[$tr[$t]{d0}]{u1} = $tn;
        $tr[$tr[$t]{d1}]{u0} = $tn;
        $tr[$tr[$t]{d1}]{u1} = -1;

        # new code to determine the bottom neighbours of the
        # newly partitioned trapezoid

        $tr[$t]{d1} = -1;

        $tnext = $tr[$t]{d0};
      } else {                        # intersecting d1
        $tr[$tr[$t]{d0}]{u0} = $t;
        $tr[$tr[$t]{d0}]{u1} = -1;
        $tr[$tr[$t]{d1}]{u0} = $t;
        $tr[$tr[$t]{d1}]{u1} = $tn;

        # new code to determine the bottom neighbours of the
        # newly partitioned trapezoid

        $tr[$tn]{d0} = $tr[$t]{d1};
        $tr[$tn]{d1} = -1;

        $tnext = $tr[$t]{d1};
      }

      $t = $tnext;
    }

    $tr[$t_sav]{rseg} = $tr[$tn_sav]{lseg}  = $segnum;
  } # end-while

  # Now combine those trapezoids which share common segments. We can
  # use the pointers to the parent to connect these together. This
  # works only because all these new trapezoids have been formed
  # due to splitting by the segment, and hence have only one parent

  $tfirstl = $tfirst;
  $tlastl  = $tlast;
  merge_trapezoids($segnum, $tfirstl, $tlastl, $S_LEFT);
  merge_trapezoids($segnum, $tfirstr, $tlastr, $S_RIGHT);

  $seg[$segnum]{is_inserted} = $TRUE;
}

# Returns true if the corresponding endpoint of the given segment is
# already inserted into the segment tree. Use the simple test of
# whether the segment which shares this endpoint is already inserted

sub _inserted {
  my ($segnum, $whichpt) = @_;
  if ($whichpt == $FIRSTPT) {
    return $seg[$seg[$segnum]{prev}]{is_inserted};
  } else {
    return $seg[$seg[$segnum]{next}]{is_inserted};
  }
}

# This is query routine which determines which trapezoid does the
# point v lie in. The return value is the trapezoid number.
#

sub _locate_endpoint {
  my ($v_ref, $vo_ref, $r) = @_;
  my %v    = %{$v_ref};
  my %vo   = %{$vo_ref};
  my %rptr = %{$qs[$r]};

  SWITCH: {
    ($rptr{nodetype} == $T_SINK) && do {
      return $rptr{trnum};
    };
    ($rptr{nodetype} == $T_Y) && do {
      if (_greater_than(\%v, $rptr{yval})) { # above
        return _locate_endpoint(\%v, \%vo, $rptr{right});
      } elsif (_equal_to(\%v, $rptr{yval})) { # the point is already
                                              # inserted.
          if (_greater_than(\%vo, $rptr{yval})) {          # above
            return _locate_endpoint(\%v, \%vo, $rptr{right});
          } else {
            return _locate_endpoint(\%v, \%vo, $rptr{left}); # below
          }
      } else {
        return _locate_endpoint(\%v, \%vo, $rptr{left});     # below
      }
    };
    ($rptr{nodetype} == $T_X) && do {
      if (_equal_to(\%v, $seg[$rptr{segnum}]{v0}) ||
          _equal_to(\%v, $seg[$rptr{segnum}]{v1})) {
        if (_fp_equal($v{y}, $vo{y}, $precision)) { # horizontal segment
          if ($vo{x} < $v{x}) {
            return _locate_endpoint(\%v, \%vo, $rptr{left});  # left
          } else {
            return _locate_endpoint(\%v, \%vo, $rptr{right}); # right
          }
        } elsif (_is_left_of($rptr{segnum}, \%vo)) {
            return _locate_endpoint(\%v, \%vo, $rptr{left});  # left
        } else {
            return _locate_endpoint(\%v, \%vo, $rptr{right}); # right
        }
      } elsif (_is_left_of($rptr{segnum}, \%v)) {
        return _locate_endpoint(\%v, \%vo, $rptr{left});  # left
      } else {
        return _locate_endpoint(\%v, \%vo, $rptr{right}); # right
      }
    };
    # default
    croak("Haggu !!!!!");
  }
}

# Thread in the segment into the existing trapezoidation. The
# limiting trapezoids are given by tfirst and tlast (which are the
# trapezoids containing the two endpoints of the segment. Merges all
# possible trapezoids which flank this segment and have been recently
# divided because of its insertion
#

sub merge_trapezoids {
  my ($segnum, $tfirst, $tlast, $side) = @_;
  my ($t, $tnext, $cond);
  my $ptnext;

  # First merge polys on the LHS
  $t = $tfirst;
  # while (($t > 0) && _greater_than_equal_to($tr[$t]{lo}, $tr[$tlast]{lo})) {
  while ($t > 0) {
    last if (! _greater_than_equal_to($tr[$t]{lo}, $tr[$tlast]{lo}));
    if ($side == $S_LEFT) {
      $cond = (((($tnext = $tr[$t]{d0}) > 0) && ($tr[$tnext]{rseg} == $segnum)) ||
               ((($tnext = $tr[$t]{d1}) > 0) && ($tr[$tnext]{rseg} == $segnum)));
    } else {
      $cond = (((($tnext = $tr[$t]{d0}) > 0) && ($tr[$tnext]{lseg} == $segnum)) ||
               ((($tnext = $tr[$t]{d1}) > 0) && ($tr[$tnext]{lseg} == $segnum)));
    }
    if ($cond) {
      if (($tr[$t]{lseg} == $tr[$tnext]{lseg}) &&
          ($tr[$t]{rseg} == $tr[$tnext]{rseg})) { # good neighbours
                                                  # merge them
        # Use the upper node as the new node i.e. t
        $ptnext = $qs[$tr[$tnext]{sink}]{parent};
        if ($qs[$ptnext]{left} == $tr[$tnext]{sink}) {
          $qs[$ptnext]{left} = $tr[$t]{sink};
        } else {
          $qs[$ptnext]{right} = $tr[$t]{sink};     # redirect parent
        }
        # Change the upper neighbours of the lower trapezoids
        if (($tr[$t]{d0} = $tr[$tnext]{d0}) > 0) {
          if ($tr[$tr[$t]{d0}]{u0} == $tnext) {
            $tr[$tr[$t]{d0}]{u0} = $t;
          } elsif ($tr[$tr[$t]{d0}]{u1} == $tnext) {
            $tr[$tr[$t]{d0}]{u1} = $t;
          }
        }
        if (($tr[$t]{d1} = $tr[$tnext]{d1}) > 0) {
          if ($tr[$tr[$t]{d1}]{u0} == $tnext) {
            $tr[$tr[$t]{d1}]{u0} = $t;
          } elsif ($tr[$tr[$t]{d1}]{u1} == $tnext) {
            $tr[$tr[$t]{d1}]{u1} = $t;
          }
        }
        $tr[$t]{lo} = {x => $tr[$tnext]{lo}{x} , y=> $tr[$tnext]{lo}{y}};
        $tr[$tnext]{state} = 2; # invalidate the lower
                                # trapezium
      } else {            #* not good neighbours
        $t = $tnext;
      }
    } else {              #* do not satisfy the outer if
        $t = $tnext;
    }
  } # end-while
}

# Retun TRUE if the vertex v is to the left of line segment no.
# segnum. Takes care of the degenerate cases when both the vertices
# have the same y--cood, etc.
#

sub _is_left_of {
  my ($segnum, $v_ref) = @_;
  my %s = %{$seg[$segnum]};
  my $area;
  my %v = %{$v_ref};

  if (_greater_than($s{v1}, $s{v0})) { # seg. going upwards
    if (_fp_equal($s{v1}{y}, $v{y}, $precision)) {
      if ($v{x} < $s{v1}{x}) {
        $area = 1;
      } else {
        $area = -1;
      }
    } elsif (_fp_equal($s{v0}{y}, $v{y}, $precision)) {
      if ($v{x} < $s{v0}{x}) {
        $area = 1;
      } else{
        $area = -1;
      }
    } else {
      $area = _Cross($s{v0}, $s{v1}, \%v);
    }
  } else {                        # v0 > v1
    if (_fp_equal($s{v1}{y}, $v{y}, $precision)) {
      if ($v{x} < $s{v1}{x}) {
        $area = 1;
      } else {
        $area = -1;
      }
    } elsif (_fp_equal($s{v0}{y}, $v{y}, $precision)) {
      if ($v{x} < $s{v0}{x}) {
        $area = 1;
      } else {
        $area = -1;
      }
    } else {
      $area = _Cross($s{v1}, $s{v0}, \%v);
    }
  }
  if ($area > 0) {
    return $TRUE;
  } else {
    return $FALSE;
  };
}

sub _Cross {
  my ($v0_ref, $v1_ref, $v2_ref) = @_;
  my %v0 = %{$v0_ref};
  my %v1 = %{$v1_ref};
  my %v2 = %{$v2_ref};
  return ( ($v1{x} - $v0{x}) * ($v2{y} - $v0{y}) -
           ($v1{y} - $v0{y}) * ($v2{x} - $v0{x}) );
}

# Get log*n for given n
sub _math_logstar_n {
  my ($n) = @_;
  my $i = 0;
  for ($i = 0 ; $n >= 1 ; $i++) {
    $n = log($n)/log(2);  # log2
  }
  return ($i - 1);
}

sub _math_N {
  my ($n,$h) = @_;
  my $v = $n;
  for (my $i = 0 ; $i < $h; $i++) {
    $v = log($v)/log(2);  # log2
  }
  return (ceil($n/$v));
}

# This function returns TRUE or FALSE depending upon whether the
# vertex is inside the polygon or not. The polygon must already have
# been triangulated before this routine is called.
# This routine will always detect all the points belonging to the
# set (polygon-area - polygon-boundary). The return value for points
# on the boundary is not consistent!!!
#

sub is_point_inside_polygon {
  my @vertex = @_;
  my %v;
  my ($trnum, $rseg);

  %v = {x => $vertex[0] , y => $vertex[1]};

  $trnum = _locate_endpoint(&v, &v, 1);
  my %t = %{$tr[$trnum]};

  if ($t{state} == $ST_INVALID) {
    return $FALSE;
  }

  if (($t{lseg} <= 0) || ($t{rseg} <= 0)) {
    return $FALSE;
  }
  $rseg = $t{rseg};
  return _greater_than_equal_to($seg[$rseg]{v1}, $seg[$rseg]{v0});
}

sub _Cross_Sine {
  my ($v0_ref, $v1_ref)  = @_;
  my %v0 = %{$v0_ref};
  my %v1 = %{$v1_ref};
  return ($v0{x} * $v1{y} - $v1{x} * $v0{y});
}

sub _Length {
  my ($v0_ref)  = @_;
  my %v0 = %{$v0_ref};
  return (sqrt($v0{x} * $v0{x} + $v0{y} * $v0{y}));
}

sub _Dot {
  my ($v0_ref, $v1_ref)  = @_;
  my %v0 = %{$v0_ref};
  my %v1 = %{$v1_ref};
  return ($v0{x} * $v1{x} + $v0{y} * $v1{y})
}

# Function returns TRUE if the trapezoid lies inside the polygon
sub inside_polygon {
  my ($t_ref) = @_;
  my %t = %{$t_ref};
  my $rseg = $t{rseg};
  if ($t{state} == $ST_INVALID) {
    return 0;
  }
  if (($t{lseg} <= 0) || ($t{rseg} <= 0)) {
    return 0;
  }
  if ((($t{u0} <= 0) && ($t{u1} <= 0)) ||
      (($t{d0} <= 0) && ($t{d1} <= 0)))  { # triangle
    return (_greater_than($seg[$rseg]{v1}, $seg[$rseg]{v0}));
  }
  return 0;
}

# return a new mon structure from the table
sub _newmon {
  return ++$mon_idx;
}

# return a new chain element from the table
sub _new_chain_element {
  return ++$chain_idx;
}

sub _get_angle {
  my ($vp0_ref, $vpnext_ref, $vp1_ref) = @_;
  my %vp0    = %{$vp0_ref};
  my %vpnext = %{$vpnext_ref};
  my %vp1    = %{$vp1_ref};

  my ($v0, $v1);

  $v0 = {x => $vpnext{x} - $vp0{x} , y => $vpnext{y} - $vp0{y}};
  $v1 = {x => $vp1{x}    - $vp0{x} , y => $vp1{y}    - $vp0{y}};
  return 0 if(_Length($v0) == 0 || _Length($v1) == 0);
  if (_Cross_Sine($v0, $v1) >= 0) { # sine is positive
    return _Dot($v0, $v1)/_Length($v0)/_Length($v1);
  } else {
    return (-1 * _Dot($v0, $v1)/_Length($v0)/_Length($v1) - 2);
  }
}

# (v0, v1) is the new diagonal to be added to the polygon. Find which
# chain to use and return the positions of v0 and v1 in p and q
sub _get_vertex_positions {
  my ($v0, $v1) = @_;

  my (%vp0, %vp1);
  my ($angle, $temp);
  my ($tp, $tq);

  %vp0 = %{$vert[$v0]};
  %vp1 = %{$vert[$v1]};

  # p is identified as follows. Scan from (v0, v1) rightwards till
  # you hit the first segment starting from v0. That chain is the
  # chain of our interest

  $angle = -4.0;
  for (my $i = 0; $i < 4; $i++) {
    next if (! $vp0{vnext}[$i]); # prevents 'uninitialized' warnings
    if ($vp0{vnext}[$i] <= 0) {
      next;
    }
    if (($temp = _get_angle($vp0{pt}, $vert[$vp0{vnext}[$i]]{pt}, $vp1{pt})) > $angle) {
      $angle = $temp;
      $tp = $i;
    }
  }

  # $ip_ref = \$tp;

  # Do similar actions for q

  $angle = -4.0;
  for (my $i = 0; $i < 4; $i++) {
    next if (! $vp1{vnext}[$i]); # prevents 'uninitialized' warnings
    if ($vp1{vnext}[$i] <= 0) {
      next;
    }
    if (($temp = _get_angle($vp1{pt}, $vert[$vp1{vnext}[$i]]{pt}, $vp0{pt})) > $angle) {
      $angle = $temp;
      $tq = $i;
    }
  }

  # $iq_ref = \$tq;

  return ($tp,$tq);

}

# v0 and v1 are specified in anti-clockwise order with respect to
# the current monotone polygon mcur. Split the current polygon into
# two polygons using the diagonal (v0, v1)
#
sub _make_new_monotone_poly {
  my ($mcur, $v0, $v1) = @_;

  my ($p, $q, $ip, $iq);
  my $mnew = _newmon;
  my ($i, $j, $nf0, $nf1);

  my %vp0 = %{$vert[$v0]};
  my %vp1 = %{$vert[$v1]};

  ($ip,$iq) = _get_vertex_positions($v0, $v1);

  $p = $vp0{vpos}[$ip];
  $q = $vp1{vpos}[$iq];

  # At this stage, we have got the positions of v0 and v1 in the
  # desired chain. Now modify the linked lists

  $i = _new_chain_element;        # for the new list
  $j = _new_chain_element;

  $mchain[$i]{vnum} = $v0;
  $mchain[$j]{vnum} = $v1;

  $mchain[$i]{next} = $mchain[$p]{next};
  $mchain[$mchain[$p]{next}]{prev} = $i;
  $mchain[$i]{prev} = $j;
  $mchain[$j]{next} = $i;
  $mchain[$j]{prev} = $mchain[$q]{prev};
  $mchain[$mchain[$q]{prev}]{next} = $j;

  $mchain[$p]{next} = $q;
  $mchain[$q]{prev} = $p;

  $nf0 = $vp0{nextfree};
  $nf1 = $vp1{nextfree};

  $vert[$v0]{vnext}[$ip] = $v1;

  $vert[$v0]{vpos}[$nf0] = $i;
  $vert[$v0]{vnext}[$nf0] = $mchain[$mchain[$i]{next}]{vnum};
  $vert[$v1]{vpos}[$nf1] = $j;
  $vert[$v1]{vnext}[$nf1] = $v0;

  $vert[$v0]{nextfree}++;
  $vert[$v1]{nextfree}++;

  $mon[$mcur] = $p;
  $mon[$mnew] = $i;
  return $mnew;
}

# Main routine to get monotone polygons from the trapezoidation of
# the polygon.
#

sub _monotonate_trapezoids {
  my ($n) = @_;

  my $tr_start;

  # First locate a trapezoid which lies inside the polygon
  # and which is triangular
  my $i;
  for ($i = 1; $i < $#tr; $i++) {
    if (inside_polygon($tr[$i])) {
      last;
    }
  }
  $tr_start = $i;

  # Initialise the mon data-structure and start spanning all the
  # trapezoids within the polygon

  for (my $i = 1; $i <= $n; $i++) {
    $mchain[$i]{prev} = $seg[$i]{prev};
    $mchain[$i]{next} = $seg[$i]{next};
    $mchain[$i]{vnum} = $i;
    $vert[$i]{pt} = {x => $seg[$i]{v0}{x} , y => $seg[$i]{v0}{y}};
    $vert[$i]{vnext}[0] = $seg[$i]{next}; # next vertex
    $vert[$i]{vpos}[0] = $i;              # locn. of next vertex
    $vert[$i]{nextfree} = 1;
  }

  $chain_idx = $n;
  $mon_idx = 0;
  $mon[0] = 1;                       # position of any vertex in the first chain

  # traverse the polygon
  if ($tr[$tr_start]{u0} > 0) {
    _traverse_polygon(0, $tr_start, $tr[$tr_start]{u0}, $TR_FROM_UP);
  } elsif ($tr[$tr_start]{d0} > 0) {
    _traverse_polygon(0, $tr_start, $tr[$tr_start]{d0}, $TR_FROM_DN);
  }

  # return the number of polygons created
  return _newmon;
}

# recursively visit all the trapezoids
sub _traverse_polygon {
  my ($mcur, $trnum, $from, $dir) = @_;

  if (!$trnum) {  # patch dvdp
    return 0;
  }
  my %t = %{$tr[$trnum]};
  my ($howsplit, $mnew);
  my ($v0, $v1, $v0next, $v1next);
  my ($retval, $tmp);
  my $do_switch = $FALSE;

  if (($trnum <= 0) || $visited[$trnum]) {
    return 0;
  }

  $visited[$trnum] = $TRUE;

  # We have much more information available here.
  # rseg: goes upwards
  # lseg: goes downwards

  # Initially assume that dir = TR_FROM_DN (from the left)
  # Switch v0 and v1 if necessary afterwards

  # special cases for triangles with cusps at the opposite ends.
  # take care of this first
  if (($t{u0} <= 0) && ($t{u1} <= 0)) {
    if (($t{d0} > 0) && ($t{d1} > 0)) { # downward opening triangle
      $v0 = $tr[$t{d1}]{lseg};
      $v1 = $t{lseg};
      if ($from == $t{d1}) {
        $do_switch = $TRUE;
        $mnew = _make_new_monotone_poly($mcur, $v1, $v0);
        _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
        _traverse_polygon($mnew, $t{d0}, $trnum, $TR_FROM_UP);
      } else {
        $mnew = _make_new_monotone_poly($mcur, $v0, $v1);
        _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
        _traverse_polygon($mnew, $t{d1}, $trnum, $TR_FROM_UP);
      }
    } else {
      $retval = $SP_NOSPLIT;        # Just traverse all neighbours
      _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
      _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
      _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
      _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
    }
  } elsif (($t{d0} <= 0) && ($t{d1} <= 0)) {
    if (($t{u0} > 0) && ($t{u1} > 0)) { # upward opening triangle
      $v0 = $t{rseg};
      $v1 = $tr[$t{u0}]{rseg};
      if ($from == $t{u1}) {
        $do_switch = $TRUE;
        $mnew = _make_new_monotone_poly($mcur, $v1, $v0);
        _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
        _traverse_polygon($mnew, $t{u0}, $trnum, $TR_FROM_DN);
      } else {
        $mnew = _make_new_monotone_poly($mcur, $v0, $v1);
        _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
        _traverse_polygon($mnew, $t{u1}, $trnum, $TR_FROM_DN);
      }
    } else {
      $retval = $SP_NOSPLIT;        # Just traverse all neighbours
      _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
      _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
      _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
      _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
    }
  } elsif (($t{u0} > 0) && ($t{u1} > 0)) {
    if (($t{d0} > 0) && ($t{d1} > 0)) { # downward + upward cusps
      $v0 = $tr[$t{d1}]{lseg};
      $v1 = $tr[$t{u0}]{rseg};
      $retval = $SP_2UP_2DN;
      if ((($dir == $TR_FROM_DN) && ($t{d1} == $from)) ||
          (($dir == $TR_FROM_UP) && ($t{u1} == $from))) {
        $do_switch = $TRUE;
        $mnew = _make_new_monotone_poly($mcur, $v1, $v0);
        _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
        _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
        _traverse_polygon($mnew, $t{u0}, $trnum, $TR_FROM_DN);
        _traverse_polygon($mnew, $t{d0}, $trnum, $TR_FROM_UP);
      } else {
        $mnew = _make_new_monotone_poly($mcur, $v0, $v1);
        _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
        _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
        _traverse_polygon($mnew, $t{u1}, $trnum, $TR_FROM_DN);
        _traverse_polygon($mnew, $t{d1}, $trnum, $TR_FROM_UP);
      }
    } else {                      #* only downward cusp
      if (_equal_to($t{lo}, $seg[$t{lseg}]{v1})) {
        $v0 = $tr[$t{u0}]{rseg};
        $v1 = $seg[$t{lseg}]{next};

        $retval = $SP_2UP_LEFT;
        if (($dir == $TR_FROM_UP) && ($t{u0} == $from)) {
          $do_switch = $TRUE;
          $mnew = _make_new_monotone_poly($mcur, $v1, $v0);
          _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{d0}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{u1}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{d1}, $trnum, $TR_FROM_UP);
        } else {
          $mnew = _make_new_monotone_poly($mcur, $v0, $v1);
          _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{u0}, $trnum, $TR_FROM_DN);
        }
      } else {
        $v0 = $t{rseg};
        $v1 = $tr[$t{u0}]{rseg};
        $retval = $SP_2UP_RIGHT;
        if (($dir == $TR_FROM_UP) && ($t{u1} == $from)) {
          $do_switch = $TRUE;
          $mnew = _make_new_monotone_poly($mcur, $v1, $v0);
          _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{d1}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{d0}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{u0}, $trnum, $TR_FROM_DN);
        } else {
          $mnew = _make_new_monotone_poly($mcur, $v0, $v1);
          _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{u1}, $trnum, $TR_FROM_DN);
        }
      }
    }
  } elsif (($t{u0} > 0) || ($t{u1} > 0)) { # no downward cusp
    if (($t{d0} > 0) && ($t{d1} > 0)) { # only upward cusp
      if (_equal_to($t{hi}, $seg[$t{lseg}]{v0})) {
        $v0 = $tr[$t{d1}]{lseg};
        $v1 = $t{lseg};
        $retval = $SP_2DN_LEFT;
        if (!(($dir == $TR_FROM_DN) && ($t{d0} == $from))) {
          $do_switch = $TRUE;
          $mnew = _make_new_monotone_poly($mcur, $v1, $v0);
          _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{d0}, $trnum, $TR_FROM_UP);
        } else {
          $mnew = _make_new_monotone_poly($mcur, $v0, $v1);
          _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{u1}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{d1}, $trnum, $TR_FROM_UP);
        }
      } else {
        $v0 = $tr[$t{d1}]{lseg};
        $v1 = $seg[$t{rseg}]{next};

        $retval = $SP_2DN_RIGHT;
        if (($dir == $TR_FROM_DN) && ($t{d1} == $from)) {
          $do_switch = $TRUE;
          $mnew = _make_new_monotone_poly($mcur, $v1, $v0);
          _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{u1}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{d0}, $trnum, $TR_FROM_UP);
        } else {
          $mnew = _make_new_monotone_poly($mcur, $v0, $v1);
          _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{d1}, $trnum, $TR_FROM_UP);
        }
      }
    } else { # no cusp
      if (_equal_to($t{hi}, $seg[$t{lseg}]{v0}) &&
          _equal_to($t{lo}, $seg[$t{rseg}]{v0})) {
        $v0 = $t{rseg};
        $v1 = $t{lseg};
        $retval = $SP_SIMPLE_LRDN;
        if ($dir == $TR_FROM_UP) {
          $do_switch = $TRUE;
          $mnew = _make_new_monotone_poly($mcur, $v1, $v0);
          _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{d1}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{d0}, $trnum, $TR_FROM_UP);
        } else {
          $mnew = _make_new_monotone_poly($mcur, $v0, $v1);
          _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{u1}, $trnum, $TR_FROM_DN);
        }
      } elsif (_equal_to($t{hi}, $seg[$t{rseg}]{v1}) &&
               _equal_to($t{lo}, $seg[$t{lseg}]{v1})) {
        $v0 = $seg[$t{rseg}]{next};
        $v1 = $seg[$t{lseg}]{next};

        $retval = $SP_SIMPLE_LRUP;
        if ($dir == $TR_FROM_UP) {
          $do_switch = $TRUE;
          $mnew = _make_new_monotone_poly($mcur, $v1, $v0);
          _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{d1}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{d0}, $trnum, $TR_FROM_UP);
        } else {
          $mnew = _make_new_monotone_poly($mcur, $v0, $v1);
          _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
          _traverse_polygon($mnew, $t{u0}, $trnum, $TR_FROM_DN);
          _traverse_polygon($mnew, $t{u1}, $trnum, $TR_FROM_DN);
        }
      } else { # no split possible
        $retval = $SP_NOSPLIT;
        _traverse_polygon($mcur, $t{u0}, $trnum, $TR_FROM_DN);
        _traverse_polygon($mcur, $t{d0}, $trnum, $TR_FROM_UP);
        _traverse_polygon($mcur, $t{u1}, $trnum, $TR_FROM_DN);
        _traverse_polygon($mcur, $t{d1}, $trnum, $TR_FROM_UP);
      }
    }
  }

  return $retval;
}

# For each monotone polygon, find the ymax and ymin (to determine the
# two y-monotone chains) and pass on this monotone polygon for greedy
# triangulation.
# Take care not to triangulate duplicate monotone polygons

sub _triangulate_monotone_polygons {
  my ($nvert, $nmonpoly) = @_;

  my ($ymax, $ymin);
  my ($p, $vfirst, $posmax, $posmin, $v);
  my ($vcount, $processed);

  $op_idx = 0;
  for (my $i = 0; $i < $nmonpoly; $i++) {
    $vcount = 1;
    $processed = $FALSE;
    $vfirst = $mchain[$mon[$i]]{vnum};
    $ymax = {x => $vert[$vfirst]{pt}{x} , y => $vert[$vfirst]{pt}{y}};
    $ymin = {x => $vert[$vfirst]{pt}{x} , y => $vert[$vfirst]{pt}{y}};
    $posmax = $posmin = $mon[$i];
    $mchain[$mon[$i]]{marked} = $TRUE;
    $p = $mchain[$mon[$i]]{next};
    while (($v = $mchain[$p]{vnum}) != $vfirst) {
      if ($mchain[$p]{marked}) {
        $processed = $TRUE;
        last;                # break from while
      } else {
        $mchain[$p]{marked} = $TRUE;
      }

      if (_greater_than($vert[$v]{pt}, $ymax)) {
        $ymax = {x => $vert[$v]{pt}{x} , y => $vert[$v]{pt}{y}};
        $posmax = $p;
      }
      if (_less_than($vert[$v]{pt}, $ymin)) {
        $ymin = {x => $vert[$v]{pt}{x} , y => $vert[$v]{pt}{y}};
        $posmin = $p;
      }
      $p = $mchain[$p]{next};
      $vcount++;
    }

    if ($processed) {              # Go to next polygon
      next;
    }

    if ($vcount == 3) {            # already a triangle
      $op[$op_idx][0] = $mchain[$p]{vnum};
      $op[$op_idx][1] = $mchain[$mchain[$p]{next}]{vnum};
      $op[$op_idx][2] = $mchain[$mchain[$p]{prev}]{vnum};
      $op_idx++;
    } else {                      # triangulate the polygon
      $v = $mchain[$mchain[$posmax]{next}]{vnum};
      if (_equal_to($vert[$v]{pt}, $ymin)) {  # LHS is a single line
        _triangulate_single_polygon($nvert, $posmax, $TRI_LHS);
      } else {
        _triangulate_single_polygon($nvert, $posmax, $TRI_RHS);
      }
    }
  }

  return $op_idx;
}

# A greedy corner-cutting algorithm to triangulate a y-monotone
# polygon in O(n) time.
# Joseph O-Rourke, Computational Geometry in C.
#
sub _triangulate_single_polygon {
  my ($nvert, $posmax, $side) = @_;

  my $v;
  my @rc;
  my $ri = 0;        # reflex chain
  my ($endv, $tmp, $vpos);

  if ($side == $TRI_RHS) {   # RHS segment is a single segment
    $rc[0] = $mchain[$posmax]{vnum};
    $tmp   = $mchain[$posmax]{next};
    $rc[1] = $mchain[$tmp]{vnum};
    $ri = 1;

    $vpos = $mchain[$tmp]{next};
    $v = $mchain[$vpos]{vnum};

    if (($endv = $mchain[$mchain[$posmax]{prev}]{vnum}) == 0) {
      $endv = $nvert;
    }
  } else {                              # LHS is a single segment
    $tmp = $mchain[$posmax]{next};
    $rc[0] = $mchain[$tmp]{vnum};
    $tmp = $mchain[$tmp]{next};
    $rc[1] = $mchain[$tmp]{vnum};
    $ri = 1;

    $vpos = $mchain[$tmp]{next};
    $v = $mchain[$vpos]{vnum};

    $endv = $mchain[$posmax]{vnum};
  }

  while (($v != $endv) || ($ri > 1)) {
    if ($ri > 0) {              # reflex chain is non-empty
      if (_Cross($vert[$v]{pt}, $vert[$rc[$ri - 1]]{pt}, $vert[$rc[$ri]]{pt}) > 0) {
        # convex corner: cut if off
        $op[$op_idx][0] = $rc[$ri - 1];
        $op[$op_idx][1] = $rc[$ri];
        $op[$op_idx][2] = $v;
        $op_idx++;
        $ri--;
      } else {     # non-convex
                   # add v to the chain
        $ri++;
        $rc[$ri] = $v;
        $vpos = $mchain[$vpos]{next};
        $v = $mchain[$vpos]{vnum};
      }
    } else {       # reflex-chain empty: add v to the
                   # reflex chain and advance it
      $rc[++$ri] = $v;
      $vpos = $mchain[$vpos]{next};
      $v = $mchain[$vpos]{vnum};
    }
  } # end-while

  # reached the bottom vertex. Add in the triangle formed
  $op[$op_idx][0] = $rc[$ri - 1];
  $op[$op_idx][1] = $rc[$ri];
  $op[$op_idx][2] = $v;
  $op_idx++;
  $ri--;

}

1;
