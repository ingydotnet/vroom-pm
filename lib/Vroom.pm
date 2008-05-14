package Vroom;
use 5.006001;
use strict;
use warnings;

# use XXX;
# use diagnostics;

our $VERSION = '0.10';

use IO::All;
use YAML::XS;
use Class::Field 'field', 'const';
use Getopt::Long;
use Carp;

field input => 'slides.vroom';
field stream => '';
field ext => '';
field clean => 0;
field vroom => 0;
field digits => 0;
field config => {
    title => 'Unnamed Presentation',
    height => 24,
    width => 80,
    list_indent => 10,
};

sub new {
    return bless {}, shift;
}

sub run {
    my $self = shift;

    local @ARGV = @_;

    $self->getOptions;

    $self->cleanUp;
    return if $self->clean;

    $self->makeAll;

    $self->startUp if $self->vroom;
}

sub getOptions {
    my $self = shift;
    GetOptions(
        "clean" => \$self->{clean},
        "input=s"  => \$self->{input},
        "vroom"  => \$self->{vroom},
    ) or die $self->usage;

    do { delete $self->{$_} unless defined $self->{$_} }
        for qw(clean input vroom);

    my @files = <*.vroom>;

    $self->input($files[0])
        if @files;
}

sub cleanUp {
    unlink(glob "0*");
    unlink(".vimrc");
}

sub makeAll {
    my $self = shift;
    $self->getInput;
    $self->buildSlides;
    $self->writeVimrc;
}

sub getInput {
    my $self = shift;
    my $stream = io($self->input)->all
        or croak "No input provided. Make a file called 'slides.vroom'";
    $self->stream($stream);
}

sub buildSlides {
    my $self = shift;
    my @split = grep length, split /^(----\ *.*)\n/m, $self->stream;
    push @split, '----' if $split[0] =~ /\n/;
    my (@raw_configs, @raw_slides);
    while (@split) {
        my ($config, $slide) = splice(@split, 0, 2);
        $config =~ s/^----\s*(.*?)\s*$/$1/;
        push @raw_configs, $config;
        push @raw_slides, $slide;
    }
    $self->{digits} = int(log(@raw_slides)/log(10)) + 2;

    my $number = 1;

    for my $raw_slide (@raw_slides) {
        my $config = $self->parseSlideConfig(shift @raw_configs);
        next if $config->{skip};

        $raw_slide = $self->applyOptions($raw_slide, $config)
            or next;        

        $raw_slide = $self->padVertical($raw_slide);

        my @slides;
        my $slide = '';
        for (split /^\+/m, $raw_slide) {
            $slide .= $_;
            push @slides, $slide;
        }

        my $base_name = $self->formatNumber($number++);

        my $suffix = 'a';
        for (my $i = 1; $i <= @slides; $i++) {
            my $slide = $self->padFullScreen($slides[$i - 1]);
            $slide =~ s{^\ *==\ *(.*?)\ *$}
                       {' ' x (($self->config->{width} - length($1)) / 2) . $1}gem;
            my $suf = $suffix++;
            $suf = $suf eq 'a'
                ? ''
                : $i == @slides
                    ? 'z'
                    : $suf;
            io("$base_name$suf" . $self->ext)->print($slide);
        }
    }
}

sub formatNumber {
    my $self = shift;
    my $number = shift;
    my $digits = $self->digits;
    return sprintf "%0${digits}d", $number;
}

sub parseSlideConfig {
    my $self = shift;
    my $string = shift;
    my $config = {};
    for my $option (split /\s*,\s*/, $string) {
        $config->{$1} = 1
            if $option =~ /^(config|skip|center|perl|yaml)$/;
        $config->{indent} = $1
            if $option =~ /i(\d+)/;
    }
    return $config;
}

sub applyOptions {
    my $self = shift;
    my ($slide, $config) = @_;

    $config = {
        %{$self->config},
        %$config,
    };

    $self->ext("");
    if ($config->{config}) {
        $config = {
            %{$self->config},
            %{(YAML::XS::Load($slide))},
        };
        $self->config($config);
        return '';
    }
    if ($config->{center}) {
        $slide =~ s{^(\+?)\ *(.*?)\ *$}
                   {$1 . ' ' x (($self->config->{width} - length($2)) / 2) . $2}gem;
        $slide =~ s{^\s*$}{}gm;
    }
    if (defined $config->{indent}) {
        my $indent = $config->{indent};
        $slide =~ s{^(\+?)}{$1 . ' ' x $indent}gem;
    }
    elsif ($slide =~ /^\+?\*/m) {
        my $indent = $config->{list_indent};
        $slide =~ s{^(\+?)}{$1 . ' ' x $indent}gem;
    }
    if ($config->{perl}) {
        $self->ext(".pl");
    }
    if ($config->{yaml}) {
        $self->ext(".yaml");
    }
    return $slide;
}

sub padVertical {
    my $self = shift;
    my $slide = shift;
    $slide =~ s/\A\s*\n//;
    $slide =~ s/\n\s*\z//;
    my @lines = split /\n/, $slide;
    my $lines = @lines;
    my $before = int(($self->config->{height} - $lines) / 2) - 1;
    return "\n" x $before . $slide;
}

sub padFullScreen {
    my $self = shift;
    my $slide = shift;
    chomp $slide;
    my @lines = split /\n/, $slide;
    my $lines = @lines;
    my $after = $self->config->{height} - $lines + 1;
    return $slide . "\n" x $after;
}

sub writeVimrc {
    my $self = shift;
    my $title = "%f         " . $self->config->{title};
    $title =~ s/\s/_/g;
    io(".vimrc")->print(<<"...");
map <SPACE> :n<CR>:<CR>gg
map <BACKSPACE> :N<CR>:<CR>gg
map R :!perl %<CR>
map Q :q!<CR>
set laststatus=2
set statusline=$title
...
}

sub startUp {
    exec "vim 0*";
}

=head1 NAME

Vroom - Slide Shows in Vim

=head1 SYNOPSIS

    > vim slides.vroom  # Write Some Slides
    > vroom --vroom     # Show Your Slides

=head1 DESCRIPTION

Ever given a Slide Show and needed to switch over to the shell?

Now you don't ever have to switch again. You're already there.

Vroom lets you create your slides in a single file using a Wiki-like
style, much like Spork and Sporx do. The difference is that your slides
don't compile to HTML or JavaScript or XUL. They get turned into a set
of files in a directory called C<slides>.

The slides are named in alpha order. That means you can bring them all
into a Vim session with the command: C<vim *>.

Vroom creates a file called C<slides/.vimrc> with many helpful key mappings
for navigating a slideshow. See L<KEY MAPPINGS> below.

Vroom takes advantage of Vim's syntax highlighting. It also lets you run
slides that contain code.

Since Vim is an editor, you can change your slides during the show.

=head1 COMMAND USAGE

Vroom has a few command line options:

=over

=item vroom

Just running vroom will compiles 'slides.vroom' into slide files.

=item vroom --vroom

Compile and start vim show.

=item vroom --clean

Clean up all the compiled  output files.

=back

=head1 INPUT FORMAT

Here is an example slides.vroom:

    ---- config
    title: My Spiffy Slideshow
    height: 84
    width: 20
    ---- center
    My Presentation

    by Ingy
    ----
    == Stuff I care about:

    * Foo
    +* Bar
    +* Baz
    ---- perl
    use Vroom;

    print "Hello World";
    ---- center
    THE END

=head1 KEY MAPPINGS

=over

=item <SPACE>

Advance one slide

=item <BACKSPACE>

Go back one slide

=item <R>

Run current slide as Perl

=item <Q>

Quit Vroom

=back

=head1 AUTHOR

Ingy döt Net <ingy@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008. Ingy döt Net.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
