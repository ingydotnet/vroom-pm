### This module was derived from Gloom - the Great Little OO Module!
### Read `perldoc Gloom` for more information.

package Vroom::OO;

use 5.008003;
use strict;
use warnings;

our $VERSION = '0.15';

sub import {
    my ($class, $flag) = @_;
    my ($package, $module) = caller(0);

    strict->import;
    warnings->import;

    if ($class->isa(__PACKAGE__) and
        defined $flag and
        $flag eq '-base'
    ) {
        $class->import_base($package, $module);
    }
    else {
        require Exporter;
        goto &Exporter::import;
    }
}

sub import_base {
    my ($class, $package, $module) = @_;
    no strict 'refs';
    push @{$package . '::ISA'}, $class;
    $class->import_fake($package, $module);
    $class->export_base($package);
}

sub import_fake {
    my ($class, $package, $module) = @_;
    my $inc_module = $package . '.pm';
    $inc_module =~ s/::/\//g;
    return if defined $INC{$inc_module};
    $INC{$inc_module} = $module;
}

sub export_base {
    my ($source, $target) = @_;
    no strict 'refs';
    for my $sub (map {
        /::/ ? $_ : "${source}::$_"
    } $source->EXPORT_BASE()) {
        my $name = $sub;
        $name =~ s/.*:://;
        *{$target . "::$name"} = \&$sub;
    }
}

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->init(@_);
    return $self;
}

sub init {
    my $self = shift;
    while (my ($property, $value) = splice(@_, 0, 2)) {
        unless ($self->can($property)) {
            my $class = ref $self;
            require Carp;
            Carp::confess("Class '$class' has no property '$property'");
        }
        $self->$property($value);
    }
}

my %code = (
    sub_start =>
      "sub {\n",
    set_default =>
      "  \$_[0]->{%s} = %s\n    unless exists \$_[0]->{%s};\n",
    class =>
      "  return do { my \$class = \$_[0]; %s } unless ref \$_[0];\n",
    init =>
      "  return \$_[0]->{%s} = do { my \$self = \$_[0]; %s }\n" .
      "    unless \$#_ > 0 or defined \$_[0]->{%s};\n",
    return_if_get =>
      "  return \$_[0]->{%s} unless \$#_ > 0;\n",
    set =>
      "  \$_[0]->{%s} = \$_[1];\n",
    onset =>
      "  do { local \$_ = \$_[1]; my \$self = \$_[0]; %s };\n",
    chain =>
      "  return \$_[0];\n}\n",
    sub_end => 
      "  return \$_[0]->{%s};\n}\n",
);

my $parse_arguments = sub {
    my $paired_arguments = shift || []; 
    my ($args, @values) = ({}, ());
    my %pairs = map { ($_, 1) } @$paired_arguments;
    while (@_) {
        my $elem = shift;
        if (defined $elem and defined $pairs{$elem} and @_) {
            $args->{$elem} = shift;
        }
        elsif ($elem eq '-chain') {
            $args->{-chain} = 1;
        }
        else {
            push @values, $elem;
        }
    }
    return wantarray ? ($args, @values) : $args;        
};

my $default_as_code = sub {
    no warnings 'once';
    require Data::Dumper;
    local $Data::Dumper::Sortkeys = 1;
    my $code = Data::Dumper::Dumper(shift);
    $code =~ s/^\$VAR1 = //;
    $code =~ s/;$//;
    return $code;
};

sub has {
    my $package = caller;
    my ($args, @values) = &$parse_arguments(
        [ qw(-package -class -init -onset) ],
        @_,
    );
    my ($has, $default) = @values;
    $package = $args->{-package} if defined $args->{-package};
    return if defined &{"${package}::$has"};
    my $default_string =
        ( ref($default) eq 'ARRAY' and not @$default )
        ? '[]'
        : (ref($default) eq 'HASH' and not keys %$default )
          ? '{}'
          : &$default_as_code($default);

    my $code = $code{sub_start};

    if ($args->{-class}) {
        if ($args->{-class} eq '-init') {
            $args->{-class} = $args->{-init};
            $args->{-class} =~ s/\$self/\$class/g;
        }
        my $fragment = $code{class};
        $code .= sprintf
            $fragment,
            $args->{-class};
    }

    if ($args->{-init}) {
        my $fragment = $code{init};
        $code .= sprintf
            $fragment,
            $has,
            $args->{-init},
            ($has) x 4;
    }
    $code .= sprintf $code{set_default}, $has, $default_string, $has
      if defined $default;
    $code .= sprintf $code{return_if_get}, $has;
    $code .= sprintf $code{set}, $has;
    $code .= sprintf $code{onset}, $args->{-onset}
      if defined $args->{-onset};
    if (defined $args->{-chain}) {
        $code .= $code{chain};
    }
    else {
        $code .= sprintf $code{sub_end}, $has;
    }

    my $sub = eval $code;
    die "eval('$code') failed: $@" if $@;
    no strict 'refs';
    *{"${package}::$has"} = $sub;
    return $code if defined wantarray;
}

our $DumpModule = 'YAML::XS';
sub WWW { require XXX; local $XXX::DumpModule = $DumpModule; XXX::WWW(@_) }
sub XXX { require XXX; local $XXX::DumpModule = $DumpModule; XXX::XXX(@_) }
sub YYY { require XXX; local $XXX::DumpModule = $DumpModule; XXX::YYY(@_) }
sub ZZZ { require XXX; local $XXX::DumpModule = $DumpModule; XXX::ZZZ(@_) }

sub EXPORT_BASE {
    return map { __PACKAGE__ . '::' .$_ }
        qw(has WWW XXX YYY ZZZ);
}
