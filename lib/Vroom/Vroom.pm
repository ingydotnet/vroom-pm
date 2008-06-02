package Vroom::Vroom;
use 5.006001;
use strict;
use warnings;

# use XXX;
# use diagnostics;

our $VERSION = '0.13';

use IO::All;
use YAML::XS;
use Class::Field 'field', 'const';
use Getopt::Long;
use File::HomeDir;
use Cwd;
use Carp;

field input => 'slides.vroom';
field stream => '';
field ext => '';
field clean => 0;
field start => 0;
field digits => 0;
field config => {
    title => 'Untitled Presentation',
    height => 24,
    width => 80,
    list_indent => 10, skip => 0, };

sub new {
    return bless {}, shift;
}

sub vroom {
    my $self = ref($_[0]) ? shift : (shift)->new;

    $self->getOptions;

    unlink(glob "0*");
    return if $self->clean;

    $self->makeAll;

    $self->startUp if $self->start;
}

sub getOptions {
    my $self = shift;

    die <<'...' if cwd eq File::HomeDir->my_home;

Don't run vroom in your home directory.

Create a new directory for your slides and run vroom from there.
...

    GetOptions(
        "clean" => \$self->{clean},
        "input=s"  => \$self->{input},
        "vroom"  => \$self->{start},
    ) or die $self->usage;

    do { delete $self->{$_} unless defined $self->{$_} }
        for qw(clean input vroom);
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

    my $number = 0;

    for my $raw_slide (@raw_slides) {
        my $config = $self->parseSlideConfig(shift @raw_configs);

        next if $config->{skip};

        $raw_slide = $self->applyOptions($raw_slide, $config)
            or next;

        $number++;

        if ($self->config->{skip}) {
            $self->config->{skip}--;
            next;
        }

        $raw_slide = $self->padVertical($raw_slide);

        my @slides;
        my $slide = '';
        for (split /^\+/m, $raw_slide) {
            $slide .= $_;
            push @slides, $slide;
        }

        my $base_name = $self->formatNumber($number);

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
            if $option =~ /^(
                config|skip|center|
                perl|ruby|python|js|
                yaml|make|html
            )$/x;
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

    my $ext = 
        $config->{perl} ? ".pl" :
        $config->{js} ? ".js" :
        $config->{python} ? ".py" :
        $config->{ruby} ? ".rb" :
        $config->{html} ? ".html" :
        $config->{shell} ? ".sh" :
        $config->{yaml} ? ".yaml" :
        $config->{make} ? ".mk" :
        "";
    $self->ext($ext);

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

    my $home_vroom = File::HomeDir->my_home . "/.vroom/vimrc";
    my $home_vimrc = -e $home_vroom ? io($home_vroom)->all : ''; 

    die <<'...'
The .vimrc in your current directory does not look like vroom created it.

If you are sure it can be overwritten, please delete it yourself this one
time, and rerun vroom. You should not get this message again.

...
    if -e '.vimrc' and io('.vimrc')->getline !~ /Vroom-\d\.\d\d/;

    my $title = "%f         " . $self->config->{title};
    $title =~ s/\s/_/g;
    io(".vimrc")->print(<<"...");
" This .vimrc file was created by Vroom-$VERSION
map <SPACE> :n<CR>:<CR>gg
map <BACKSPACE> :N<CR>:<CR>gg
map R :!perl %<CR>
map Q :q!<CR>
map O :!open <cWORD><CR>
map E :e <cWORD><CR>
set laststatus=2
set statusline=$title

" Overrides from $home_vroom
$home_vimrc
...
}

sub startUp {
    exec "vim 0*";
}

=encoding utf8

=head1 NAME

Vroom::Vroom - Slide Shows in Vim

=head1 SYNOPSIS

    > mkdir MySlides    # Make a Directory for Your Slides
    > cd MySlides       # Go In There
    > vim slides.vroom  # Write Some Slides
    > vroom --vroom     # Show Your Slides

=head1 DESCRIPTION

Ever given a Slide Show and needed to switch over to the shell?

Now you don't ever have to switch again. You're already there.

Vroom lets you create your slides in a single file using a Wiki-like
style, much like Spork and Sporx do. The difference is that your slides
don't compile to HTML or JavaScript or XUL. They get turned into a set
of files that begin with '0', like '03' or '07c' or '05b.pl'.

The slides are named in alpha order. That means you can bring them all
into a Vim session with the command: C<vim 0*>. C<vroom --vroom> does
exactly that.

Vroom creates a file called C<./.vimrc> with helpful key mappings for
navigating a slideshow. See L<KEY MAPPINGS> below.

Please note that you will need the following line in your
C<$HOME/.vimrc> file in order to pick up the local C<.vimrc> file.

    set exrc

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

Here is an example slides.vroom file:

    ---- config
    # These are YAML settings for Vroom
    title: My Spiffy Slideshow
    height: 84
    width: 20
    # skip: 12      # Skip 12 slides. Useful when making slides.
    ---- center
    My Presentation

    by Ingy
    ----
    == Stuff I care about:

    * Foo
    +* Bar
    +* Baz
    ---- perl,i10
    # Perl code indented 10 spaces
    use Vroom::Vroom;

    print "Hello World";
    ---- center
    THE END

A line that starts with '==' is a header line. It will be centered.

Lines that begin with a '+' cause vroom to split the slide there,
causing an animation effect.

=head1 CONFIGURATION OPTIONS

Each slide can have one or more configuration options. Options are
a comma separated list that follow the '----' header for a slide.
Like this:

    ---- center
    ---- html
    ---- perl,i20
    ---- config
    ---- skip

=over

=item skip

Ignore the following slide completely.

=item center

Center the contents of the slide.

=item i##

'i' followed by a number means to indent the contents by the number of
characters.

=item perl,ruby,python,js,yaml,make,html

Specifies that the slide is one of those syntaxen, and that the
appropriate file extension will be used, thus causing vim to syntax
highlight the slide.

=item config

The slide is really a yaml configuration. It will not be displayed
in the presentation, but will tell vroom what to do from that point
forward. You can use more than one config slide in your
C<slides.vroom> file.

=back

You can specify the following confguration options in a config slide:

=over

=item title <text>

The title of your presentation.

=item height <number>

The number of lines in the terminal you plan to use when presenting the
show. Used for centering the content.

=item width <number>

The number of columns in the terminal you plan to use when presenting
the show. Used for centering the content.

=item list_indent <number>

Auto detect slides that have lists in them, and indent them by the
specified number of columns.

=back

=head1 KEY MAPPINGS

These are the standard key mappings specified in the local C<.vimrc>.

=over

=item <SPACE>

Advance one slide.

=item <BACKSPACE>

Go back one slide.

=item <R>

Run current slide as Perl.

=item <Q>

Quit Vroom.

=back

=head1 CUSTOM CONFIGURATION

You can create a file called C<.vroom/vimrc> in your home directory. If
vroom sees this file, it will append it onto every local C<.vimrc> file
it creates.

Use this file to specify your own custom vim settings for all your vroom
presentations.

=head1 NOTE

Vroom is called Vroom but the module is Vroom::Vroom because the
CPAN shell sometimes thinks Vroom is Tim Vroom, and it refuses to
install him.

Use a shell command like this to install Vroom:

    sudo cpan Vroom::Vroom

=head1 AUTHOR

Ingy döt Net <ingy@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008. Ingy döt Net.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
