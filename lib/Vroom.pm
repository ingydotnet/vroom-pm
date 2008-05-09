package Vroom;
use 5.006001;
use strict;
use warnings;

use IO::All;
use YAML::XS;
use Class::Field 'field', 'const';
use Getopt::Long;
use Carp;

field input => '';
field ext => '';
field height => 20;
field width => 80;

sub new {
    return bless {}, shift;
}

sub run {
    my $self = shift;

    $self->getOptions;
    $self->cleanUp;
}

sub getOptions {
    my $self = shift;
    my $height = $self->height;
    my $width = $self->width;
    GetOptions(
        "height=i" => \$height,
        "width=i"  => \$width,
    );
    $self->height($height);
    $self->width($width);
}

sub cleanUp {
    my $self = shift;
    if (-e $self->dir) {
        $_->unlink for io($self->dir)->All_Files;
    }
}

sub getInput {
    my $self = shift;
    my $input = io('-')->all || io('vroom')->all
        or croak "No input provided. Make a file called 'vroom'";
    $self->input($input);
}

sub buildSlides {
    my $self = shift;
    my @raw_slides = grep length, split /^----\n/m, $self->input;
    $self->digits = int(log(@raw_slides)/log(10)) + 2;

    my $number = 1;

    for my $raw_slide (@raw_slides) {
        $self->ext('');
        if ($raw_slide =~ s/^!(.*)\n//) {
            $raw_slide = setOptions($raw_slide, $1)
                or next;
        }
        $raw_slide = padVertical($raw_slide);
        my @slides;
        my $slide = '';
        for (split /^\+/m, $raw_slide) {
            $slide .= $_;
            push @slides, $slide;
        }

        my $base_name = $self->formatNumber($number++);

        my $suffix = 'a';
        for (my $i = 1; $i <= @slides; $i++) {
            my $slide = padFullScreen($slides[$i - 1]);
            $slide =~ s{^\ *==\ *(.*?)\ *$}
                       {' ' x (($self->width - length($1)) / 2) . $1}gem;
            io("$base_name$suffix" . $self->ext)->print($slide);
            $suffix++;
        }
    }
}

sub writeVimrc {
    my $self = shift;
    io(".vimrc")->print(<<"...");
map <SPACE> :n<CR>:<CR>gg
map <BACKSPACE> :N<CR>:<CR>gg
map R :!perl %<CR>
map Q :q!<CR>
set laststatus=2
set statusline=$self->{title}
...
}

sub writeMakefile {
    my $self = shift;
    io("Makefile")->print(<<'...');
trouble love tracks:
        vim [a-z]*
...
}

sub printFinished {
    print "Your slide show is ready... vroom vroom!!!\n";
}

sub setOptions {
    my $self = shift;
    my ($slide, $options) = @_;
    my @options = split /,/, $options;
    my $config = {};
    for my $option (@options) {
        if ($option eq 'config') {
            $config = { %$config, %{(YAML::XS::Load($slide))} };
            return '';
        }
        if ($option =~ /^c(enter)?$/) {
            $slide =~ s{^(\+?)\ *(.*?)\ *$}
                       {$1 . ' ' x ((78 - length($2)) / 2) . $2}gem;
            $slide =~ s{^\s*$}{}gm;
        }
        if ($option =~ /^i(\d+)$/) {
            my $indent = $1;
            $slide =~ s{^(\+?)}{$1 . ' ' x $indent}gem;
        }
        if ($option =~ /^(pl|js|rb|yaml)$/) {
            $self->ext(".$1");
        }
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
    my $before = int(($self->height - $lines) / 2) - 1;
    return "\n" x $before . $slide;
}

sub padFullScreen {
    my $self = shift;
    my $slide = shift;
    chomp $slide;
    my @lines = split /\n/, $slide;
    my $lines = @lines;
    my $after = $self->height - $lines + 1;
    return $slide . "\n" x $after;
}

=head1 NAME

Vroom - Slide Shows in Vim

=head1 SYNOPSIS

    > vim vroom         # Write Some Slides
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



=head1 INPUT FORMAT



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
