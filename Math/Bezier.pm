#========================================================================
# Math::Bezier
#
# Module for the solution of Bezier curves based on the algorithm 
# presented by Robert D. Miller in Graphics Gems V, "Quick and Simple
# Bezier Curve Drawing".
#
# Andy Wardley <abw@kfs.org>
#
# Copyright (C) 2000 Andy Wardley.  All Rights Reserved.
#
# This module is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
#========================================================================

package Math::Bezier;

use strict;
use vars qw( $VERSION );

$VERSION = '0.01';

use constant X  => 0;
use constant Y  => 1;
use constant CX => 2;
use constant CY => 3;


#------------------------------------------------------------------------
# new($x1, $y1, $x2, $y2, ..., $xn, $yn)
#
# Constructor method to create a new Bezier curve form.
#------------------------------------------------------------------------

sub new {
    my $class = shift;
    my @points = ref $_[0] eq 'ARRAY' ? @{$_[0]} : @_;
    my $size = scalar @points;
    my @ctrl;

    die "invalid control points, expects (x1, y1, x2, y2, ..., xn, yn)\n"
	if $size % 2;

    while (@points) {
	push(@ctrl, [ splice(@points, 0, 2) ]);
    }
    $size = scalar @ctrl;

    my $n = $size - 1;
    my $choose;

    for (my $k = 0; $k <= $n; $k++) {
	if ($k == 0) {
	    $choose = 1;
	}
	elsif ($k == 1) {
	    $choose = $n;
	}
	else {
	    $choose *= ($n - $k + 1) / $k;
	}
	$ctrl[$k]->[CX] = $ctrl[$k]->[X] * $choose;
	$ctrl[$k]->[CY] = $ctrl[$k]->[Y] * $choose;
    }

    bless \@ctrl, $class;
}


#------------------------------------------------------------------------
# point($theta)
#
# Calculate (x, y) point on curve at position $theta (in the range 0 - 1)
# along the curve.  Returns a list ($x, $y) or reference to a list 
# [$x, $y] when called in list or scalar context respectively.
#------------------------------------------------------------------------

sub point {
    my ($self, $t) = @_;
    my $size = scalar @$self;
    my (@points, $point);

    my $n = $size - 1;
    my $u = $t;

    push(@points, [ $self->[0]->[CX], $self->[0]->[CY] ]);

    for (my $k = 1; $k <= $n; $k++) {
	push(@points, [ $self->[$k]->[CX] * $u, $self->[$k]->[CY] * $u ]);
	$u *= $t;
    }

    $point = [ @{ $points[$n] } ];
    my $t1 = 1 - $t;
    my $tt = $t1;

    for (my $k = $n - 1; $k >= 0; $k--) {
	$point->[X] += $points[$k]->[X] * $tt;
	$point->[Y] += $points[$k]->[Y] * $tt;
	$tt = $tt * $t1;
    }

    return wantarray ? (@$point) : $point;
}    


#------------------------------------------------------------------------
# curve($npoints)
#
# Sample curve at $npoints points.  Returns a list or reference to a list 
# of (x, y) points along the curve, when called in list or scalar context
# respectively.
#------------------------------------------------------------------------

sub curve {
    my ($self, $npoints) = @_;
    $npoints = 20 unless defined $npoints;
    my @points;
    $npoints--;
    foreach (my $t = 0; $t <= $npoints; $t++) {
	push(@points, ($self->point($t / $npoints)));
    }
    return wantarray ? (@points) : \@points;
}

1;

__END__

=head1 NAME

Math::Bezier - solution of Bezier Curves

=head1 SYNOPSIS

    use Math::Bezier;

    # create curve passing list of (x, y) control points
    my $bezier = Math::Bezier->new($x1, $y1, $x2, $y2, ..., $xn, $yn);

    # or pass reference to list of control points
    my $bezier = Math::Bezier->new([ $x1, $y1, $x2, $y2, ..., $xn, $yn]);

    # determine (x, y) at point along curve, range 0 -> 1
    my ($x, $y) = $bezier->point(0.5);

    # returns list ref in scalar context
    my $xy = $bezier->point(0.5);

    # return list of 20 (x, y) points along curve
    my @curve = $bezier->curve(20);

    # returns list ref in scalar context
    my $curve = $bezier->curve(20);

=head1 DESCRIPTION

This module implements the algorithm for the solution of Bezier curves
as presented by Robert D. Miller in Graphics Gems V, "Quick and Simple
Bezier Curve Drawing".

A new Bezier curve is created using the new() constructor, passing a list
of (x, y) control points.

    use Math::Bezier;

    my @control = ( 0, 0, 10, 20, 30, -20, 40, 0 );
    my $bezier  = Math::Bezier->new(@control);

Alternately, a reference to a list of control points may be passed.

    my $bezier  = Math::Bezier->new(\@control);

The point($theta) method can then be called on the object, passing a
value in the range 0 to 1 which represents the distance along the
curve.  When called in list context, the method returns the x and y
coordinates of that point on the Bezier curve.

    my ($x, $y) = $bezier->point(0.5);
    print "x: $x  y: $y\n

When called in scalar context, it returns a reference to a list containing
the x and y coordinates.

    my $point = $bezier->point(0.5);
    print "x: $point->[0]  y: $point->[1]\n";

The curve($n) method can be used to return a set of points sampled
along the length of the curve (i.e. in the range 0 <= $theta <= 1).
The parameter indicates the number of sample points required,
defaulting to 20 if undefined.  The method returns a list of ($x1,
$y1, $x2, $y2, ..., $xn, $yn) points when called in list context, or 
a reference to such an array when called in scalar context.

    my @points = $bezier->curve(10);

    while (@points) {
	my ($x, $y) = splice(@points, 0, 2);
	print "x: $x  y: $y\n";
    }

    my $points = $bezier->curve(10);

    while (@$points) {
	my ($x, $y) = splice(@$points, 0, 2);
	print "x: $x  y: $y\n";
    }

=head1 AUTHOR

Andy Wardley E<lt>abw@kfs.orgE<gt>

=head1 SEE ALSO

Graphics Gems 5, edited by Alan W. Paeth, Academic Press, 1995,
ISBN 0-12-543455-3.  Section IV.8, 'Quick and Simple Bezier Curve
Drawing' by Robert D. Miller, pages 206-209.

=cut
