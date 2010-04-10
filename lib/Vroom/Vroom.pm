package Vroom::Vroom;
use 5.006001;
use strict;
use warnings;

our $VERSION = '0.21';

use IO::All;
use YAML::XS;
use Class::Field 'field';
use Getopt::Long;
use File::HomeDir;
use Cwd;
use Carp;

field input => 'slides.vroom';
field stream => '';
field ext => '';
field help => 0;
field clean => 0;
field compile => 0;
field sample => 0;
field run => 0;
field html => 0;
field ghpublish => 0;
field start => 0;
field digits => 0;
field skip => 0;
field config => {
    title => 'Untitled Presentation',
    height => 24,
    width => 80,
    list_indent => 10,
    skip => 0,
    vim => 'vim',
    vimrc => '',
    gvimrc => '',
};

sub new {
    return bless {}, shift;
}

sub usage {
    return <<'...';
    Usage: vroom [options]

    -new        - Create a sample 'slides.vroom' file
    -vroom      - Start slideshow
    -compile    - Generate slides
    -html       - Publish slides as HTML

    -skip=#     - Skip # of slides
    -input=name - Specify an input file name

    -clean      - Delete generated files
    -help       - Get help!
...
}

sub vroom {
    my $self = ref($_[0]) ? shift : (shift)->new;

    $self->getOptions;

    if ($self->sample) {
        $self->sampleSlides;
    }
    elsif ($self->run) {
        $self->runSlide;
    }
    elsif ($self->clean) {
        $self->cleanAll;
    }
    elsif ($self->compile) {
        $self->makeSlides;
    }
    elsif ($self->start) {
        $self->makeSlides;
        $self->startUp;
    }
    elsif ($self->html) {
        $self->makeHTML;
    }
    elsif ($self->ghpublish) {
        $self->makePublisher;
    }
    elsif ($self->help) {
        warn $self->usage;
    }
    else {
        warn $self->usage;
    }
}

sub getOptions {
    my $self = shift;

    die <<'...' if cwd eq File::HomeDir->my_home;

Don't run vroom in your home directory.

Create a new directory for your slides and run vroom from there.
...

    GetOptions(
        "help" => \$self->{help},
        "new" => \$self->{sample},
        "clean" => \$self->{clean},
        "compile" => \$self->{compile},
        "run" => \$self->{run},
        "html" => \$self->{html},
        "ghpublish" => \$self->{ghpublish},
        "input=s"  => \$self->{input},
        "vroom"  => \$self->{start},
        "skip=i" => \$self->{skip},
    ) or die $self->usage;

    do { delete $self->{$_} unless defined $self->{$_} }
        for qw(clean compile input vroom);
}

sub cleanUp {
    my $self = shift;
    unlink(glob "0*");
    unlink('.help');
    unlink('.vimrc');
    unlink('.gvimrc');
    unlink('run.slide');
}

sub cleanAll {
    my $self = shift;
    $self->cleanUp;
    io->dir('html')->rmtree;
}

sub runSlide {
    my $self = shift;
    my $slide = $ARGV[0];

    if ($slide =~ /\.pl$/) {
        exec "clear; $^X $slide";
    }

    $self->trim_slide;

    if ($slide =~ /\.py$/) {
        exec "clear; python run.slide";
    }
    elsif ($slide =~ /\.rb$/) {
        exec "clear; ruby run.slide";
    }
    elsif ($slide =~ /\.php$/) {
        exec "clear; php run.slide";
    }
    elsif ($slide =~ /\.js$/) {
        exec "clear; js run.slide";
    }
    elsif ($slide =~ /\.hs$/) {
        exec "clear; runghc run.slide";
    }
    elsif ($slide =~ /\.yaml$/) {
        exec "clear; $^X -MYAML::XS -MData::Dumper -e '\$Data::Dumper::Terse = 1; \$Data::Dumper::Indent = 1; print Dumper YAML::XS::LoadFile(shift)' run.slide";
    }
}

sub trim_slide {
    my $self = shift;
    my $slide = $ARGV[0];

    my $text < io($slide);
    $text =~ s/^\s*\n//;
    $text =~ s/\n\s*$/\n/;
    while ($text !~ /^\S/m) {
        $text =~ s/^ //mg;
    }
    $text > io('run.slide');
}

sub makeSlides {
    my $self = shift;
    $self->cleanUp;
    $self->getInput;
    $self->buildSlides;
    $self->writeVimrc;
    $self->writeHelp;
}

sub makeHTML {
    my $self = shift;
    require Template::Toolkit::Simple;
    $self->cleanAll;
    $self->makeSlides;
    io('html')->mkdir;
    my @slides = glob('0*');
    for (my $i = 0; $i < @slides; $i++) {
        my $slide = $slides[$i];
        my $prev = ($i > 0) ? $slides[$i - 1] : '';
        my $next = ($i + 1 < @slides) ? $slides[$i + 1] : '';
        my $text = io($slide)->all;
        my $title = $text;
        $text = Template::Toolkit::Simple->new()->render(
            $self->slideTemplate,
            {
                title => "$slide",
                prev => $prev,
                next => $next,
                content => $text,
            }
        );
        io("html/$slide.html")->print($text);
    }

    my $index = [];
    for (my $i = 0; $i < @slides; $i++) {
        my $slide = $slides[$i];
        next if $slide =~ /^\d+[a-z]/;
        my $title = io($slide)->all;
        $title =~ s/.*?((?-s:\S.*)).*/$1/s;
        push @$index, [$slide, $title];
    }

    io("html/index.html")->print(
        Template::Toolkit::Simple->new()->render(
            $self->indexTemplate,
            {
                config => $self->config,
                index => $index,
            }
        )
    );
    $self->cleanUp;
}

sub indexTemplate {
    \ <<'...'
<html>
<head>
<title>[% config.title | html %]</title>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<script>
function navigate(e) {
    var keynum = (window.event) // IE
        ? e.keyCode
        : e.which;
    if (keynum == 13 || keynum == 32) {
        window.location = "001.html";
        return false;
    }
    return true;
}
</script>
<style>
body {
    font-family: sans-serif;
}
h4 {
    color: #888;
}
</style>
</head>
<body>
<h4>Use SPACEBAR to peruse the slides or click one to start...<h4>
<h1>[% config.title | html %]</h1>
<ul>
[% FOR entry = index -%]
[% slide = entry.shift() -%]
[% title = entry.shift() -%]
<li><a href="[% slide %].html">[% title | html %]</a></li>
[% END -%]
</ul>
<p>This presentation was generated by <a
href="http://ingydotnet.github.com/vroom-pm">Vroom</a>. Use &lt;SPACE&gt; key to go
forward and &lt;BACKSPACE&gt; to go backwards.
</p>
</body>
...
}

sub slideTemplate {
    \ <<'...'
<html>
<head>
<title>[% title | html %]</title>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<script>
function navigate(e) {
    var keynum = (window.event) // IE
        ? e.keyCode
        : e.which;
    if (keynum == 8) {
[% IF prev -%]
        window.location = "[% prev %]" + ".html";
[% END -%]
        return false;
    }
[% IF next -%]
    if (keynum == 13 || keynum == 32) {
        window.location = "[% next %]" + ".html";
        return false;
    }
[% END -%]
    if (keynum == 73 || keynum == 105) {
        window.location = "index.html";
        return false;
    }
    return true;
}
</script>
</head>
<body onkeypress="return navigate(event)">
<pre>
[%- content | html -%]
</pre>
</body>
...
}

sub getInput {
    my $self = shift;
    my @stream = io($self->input)->slurp
        or croak "No input provided. Make a file called 'slides.vroom'";
    my $stream = join '', map {
        /^----\s+include\s+(\S+)/
        ? scalar(io($1)->all)
        : $_
    } @stream;
    $self->stream($stream);
}

sub buildSlides {
    my $self = shift;
    my @split = split /^(----\ *.*)\n/m, $self->stream;
    shift @split;
    @split = grep length, @split;
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

        if ($self->config->{skip} or $self->skip) {
            $self->config->{skip}-- if $self->config->{skip};
            $self->{skip}-- if $self->{skip};
            next;
        }

        $raw_slide = $self->padVertical($raw_slide);

        my @slides;
        my $slide = '';
        for (split /^\+/m, $raw_slide) {
            $slide = '' if $config->{replace};
            $slide .= $_;
            $slide = $self->padVertical($slide)
                if $config->{replace};
            push @slides, $slide;
        }

        my $base_name = $self->formatNumber($number);

        my $suffix = 'a';
        for (my $i = 1; $i <= @slides; $i++) {
            my $slide = $self->padFullScreen($slides[$i - 1]);
            chomp $slide;
            $slide .= "\n";
            if ($slide =~ s/^\ *!(.*\n)//m) {
                $slide .= $1;
            }
            # this option can't be applied ahead of time
            if ($config->{undent}) {
                my $undent = $config->{undent};
                $slide =~ s/^.{$undent}//gm;
            }
            $slide =~ s{^\ *==\ +(.*?)\ *$}
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

my $types = {
    # add pl6 and py3
    perl => 'pl', pl => 'pl',
    ruby => 'rb', rb => 'rb',
    python => 'py', py => 'py',
    haskell => 'hs', hs => 'hs',
    javascript => 'js', js => 'js',
    actionscript => 'as', as => 'as',
    shell => 'sh', sh => 'sh',
    php => 'php',
    java => 'java',
    yaml => 'yaml',
    xml => 'xml',
    json => 'json',
    html => 'html',
    make => 'make',
    diff => 'diff',
    conf => 'conf',
};
sub parseSlideConfig {
    my $self = shift;
    my $string = shift;
    my $config = {};
    my $type_list = join '|', keys %$types;
    for my $option (split /\s*,\s*/, $string) {
        $config->{$1} = 1
            if $option =~ /^(config|skip|center|replace|$type_list)$/;
        $config->{indent} = $1
            if $option =~ /i(\d+)/;
        $config->{undent} = $1
            if $option =~ /i-(\d+)/;
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
    elsif (defined $config->{indent}) {
        my $indent = $config->{indent};
        $slide =~ s{^(\+?)}{$1 . ' ' x $indent}gem;
    }
    elsif ($slide =~ /^\+?\*/m) {
        my $indent = $config->{list_indent};
        $slide =~ s{^(\+?)}{$1 . ' ' x $indent}gem;
    }

    my $ext = '';
    for my $key (keys %$config) {
        if (my $e = $types->{$key}) {
            $ext = ".$e";
            last;
        }
    }
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

    my $home_vimrc = File::HomeDir->my_home . "/.vroom/vimrc";
    my $home_vimrc_content = -e $home_vimrc ? io($home_vimrc)->all : ''; 

    die <<'...'
The .vimrc in your current directory does not look like vroom created it.

If you are sure it can be overwritten, please delete it yourself this one
time, and rerun vroom. You should not get this message again.

...
    if -e '.vimrc' and io('.vimrc')->getline !~ /Vroom-\d\.\d\d/;

    my $title = "%-20f " . $self->config->{title};
    $title =~ s/\s/\\ /g;
    io(".vimrc")->print(<<"...");
" This .vimrc file was created by Vroom-$VERSION
map <SPACE> :n<CR>:<CR>gg
map <BACKSPACE> :N<CR>:<CR>gg
map R :!vroom -run %<CR>
map RR :!vroom -run %<CR>
map VV :!vroom -vroom<CR>
map QQ :q!<CR>
map OO :!open <cWORD><CR><CR>
map EE :e <cWORD><CR>
map !! G:!open <cWORD><CR><CR>
map ?? :e .help<CR>
set laststatus=2
set statusline=$title

" Overrides from $home_vimrc
$home_vimrc_content

" Values from slides.vroom config section. (under 'vimrc')
${\ $self->config->{vimrc}}
...

    if ($self->config->{vim} =~ /\bgvim\b/) {
        my $home_gvimrc = File::HomeDir->my_home . "/.vroom/gvimrc";
        my $home_gvimrc_content = -e $home_gvimrc ? io($home_gvimrc)->all : ''; 

        io(".gvimrc")->print(<<"...");
" Values from slides.vroom config section. (under 'gvimrc')
${\ $self->config->{gvimrc}}

" Overrides from $home_gvimrc
$home_gvimrc_content
...
    }
}

sub writeHelp {
    my $self = shift;
    io('.help')->print(<<'...');

    <SPACE>         Advance
    <BACKSPACE>     Go back

    ??              Help
    QQ              Quit Vroom

    RR              Run slide as a program
    VV              vroom --vroom 
    EE              Edit file under cursor
    OO              Open file under cursor (Mac OS X)


    (Press SPACE to leave Help screen and continue)

...
}

sub startUp {
    my $self = shift;
    my $vim = $self->config->{vim};
    exec "$vim 0*";
}

sub sampleSlides {
    my $self = shift;
    my $file = $self->input;
    die <<"..." if -e $file;
'$file' already exists.

If you really want to generate a new template slides file,
please delete or move this one.
...
    io($file)->print(<<'...');
# This is a sample Vroom input file. It should help you get started.
#
# Edit this file with your content. Then run `vroom --vroom` to start
# the show!
#
# See `perldoc Vroom::Vroom` for complete details.
#
---- config
# Basic config options.
title: Vroom!
indent: 5
height: 18
width: 69
skip: 0

# The following options are for Gvim usage.
# vim: gvim
# gvimrc: |
#   set fuopt=maxhorz,maxvert
#   set guioptions=egmLtT
#   set guifont=Bitstream_Vera_Sans_Mono:h18
#   set guicursor=a:blinkon0-ver25-Cursor
#   colorscheme default

---- center
Vroom!

by Ingy döt Net

(hint: press the spacebar)

----
== Slideshows in Vim

* Hate using PowerPoint or HTML Slides for Talks?
+* Use Vroom!

+* You can write you slides in Vim...
* ...and present them in Vim!

----
== Getting Started

* Write a file called 'slides.vroom'.
  * Do this in a new directory.
* Run 'vroom --vroom'.
* Voilà!

----
== Navigation

* Hit <SPACE> to move forward.
* Hit <BACKSPACE> to go backwards.
* Hit 'Q' to quit.

---- perl,i4
# This is some Perl code.
# Notice the syntax highlighting.
# Run it with the <RR> vim command.
for my $word (qw(Vroom totally rocks!)) {
    print "$word\n";
}

----
== Get Vroom!

* http://search.cpan.org/dist/Vroom/
* http://github.com/ingydotnet/vroom-pm/

----
== Vroom as HTML

* http://ingydotnet.github.com/vroom-pm/

----
== The End
...
    print "'$file' created.\n";
}

sub makePublisher {
    my $self = shift;
    my $input = $self->input;
    die "Error: This doesn't look like a Vroom directory.\n"
      unless -f $input;
    die "Error: This doesn't look like a git repository.\n"
      unless -d '.git';
    die "Error: No writeable /tmp directory on this system.\n"
      unless -d '/tmp' and -w '/tmp';
    die "Error: There is no git branch called 'gh-pages'.\n" .
        "Perhaps you should run `git branch gh-pages` first.\n"
        unless `git branch` =~ /\bgh-pages\b/;
    io('ghpublish')->print(<<'...');
#!/bin/sh

# This script is experimental. Please understand it before you run it on
# your system. Just because it works for Ingy, doesn't mean it will work
# for you.

if [ -e "/tmp/html" ]; then
    echo "Error: /tmp/html already exists. Perhaps remove it."
    exit 13
fi

# Create HTML slides.
vroom --html || exit 1
# Move the html directory to /tmp
mv html /tmp || exit 1
# Stash any local stuff that isn't committed.
git stash || exit 1
# Switch to your gh-pages branch. (That you already created. Right?)
git checkout gh-pages || exit 1
# Remove all the html files from the gh-pages branch.
rm -f *.html || exit 1
# Move the HTML slides in here.
mv /tmp/html/* . || exit 1
# Remove the html directory from /tmp
rmdir /tmp/html || exit 1
# Add any new files to git.
git add 0* index.html || exit 1
# Commit your changes.
git commit -am 'Publish my slides' || exit 1
# Push them to GitHub.
git push origin gh-pages || exit 1
# Switch back to the master branch.
git checkout master || exit 1
# Get your uncommitted changes back.
git stash pop || exit 1

# Voilà! (hopefully)
...

    chmod 0755, 'ghpublish';

    print <<'...';
Created the shell script called 'ghpublish'.

This script is somewhat experimental, so please read the code to make sure
it makes sense on your system.

If it makes sense to you, run it. (at your own risk :)
...
}

=encoding utf8

=head1 NAME

Vroom::Vroom - Slide Shows in Vim

=head1 SYNOPSIS

    > mkdir MySlides    # Make a Directory for Your Slides
    > cd MySlides       # Go In There
    > vroom -new        # Create Example Slides File
    > vim slides.vroom  # Edit the File and Add Your Own Slides
    > vroom --vroom     # Show Your Slides
    > vroom --html      # Publish Your Slides as HTML

=head1 DESCRIPTION

Ever given a Slide Show and needed to switch over to Vim?

Now you don't ever have to switch again. You're already there.

Vroom lets you create your slides in a single file using a Wiki-like
style, much like Spork and Sporx do. The difference is that your slides
don't compile to HTML or JavaScript or XUL. They get turned into a set
of files that begin with '0', like '03' or '07c' or '05b.pl'.

The slides are named in alphabetic order. That means you can bring them
all into a Vim session with the command: C<vim 0*>. C<vroom --vroom>
does exactly that.

You can do things like advance to the next slide with the spacebar.
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

=item vroom --new

Write an example C<slides.vroom> file. This example contains all the
config options and also examples of all the Vroom syntax features.

=item vroom --vroom

Compile (create) the slides files from the input file and start vim
show.

=item vroom --compile

Just compile the slides.

=item vroom --html

Publish the slides to HTML, with embedded JavaScript to navigate with
the spacebar and backspace keys. Created in the C<html/> subdirectory.

=item vroom --clean

Clean up all the compiled output files.

=item vroom --ghpublish

Creates a shell script in the current directory, that is intended to
publish your slides to the special GitHub branch called gh-pages. See
L<GITHUB NOTES> below.

This command does NOT run the script. It merely creates it for you. It is up
to you to review the script and run it (if it makes sense on your system).

=item vroom <action> --skip=#

The skip option takes a number as its input and skips that number of
files during compilation. This is useful when you are polishing your slides
and are finished with the first 50. You can say:

    vroom --vroom --skip=50

and it will start on slide #51.

=item vroom <action> --input=<file_name>

This option lets you specify an alternate input file name, instead of the
default one, C<slides.vroom>.

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

    ---- config
    ---- center
    ---- perl,i20
    ---- include file-name
    ---- replace
    ---- skip

=over

=item config

The slide is really a yaml configuration. It will not be displayed
in the presentation, but will tell vroom what to do from that point
forward.

Usually, a C<config> slide is the first thing in your input file, but
you can use more than one config slide.

=item center

Center the contents of the slide.

=item i##

'i' followed by a number means to indent the contents by the number of
characters.

=item i-##

'i' followed by a negative number means to strip that number of leading 
characters from the contents of the slide.  This can be useful if you need
to have characters special to Vroom::Vroom at the beginning of your lines,
for example if the contents of your slide is unified diff output.

=item perl,ruby,python,php,javascript,haskell,actionscript,html,yaml,xml,json,make,shell,diff

Specifies that the slide is one of those syntaxen, and that the
appropriate file extension will be used, thus causing vim to syntax
highlight the slide.

=item include file-path-name

Replace the line with the contents of the specified file. Useful to
include long files that would make your slides file unruly.

=item replace

With the C<replace> option, the '+' animations in the slide cause the
content to replace the previous partial slide, rather than append to it.

=item skip

Ignore the following slide completely.

=back

=head2 CONFIG SLIDE OPTIONS

You can specify the following configuration options in a config slide:

=over

=item title: <text>

The title of your presentation.

=item height: <number>

The number of lines in the terminal you plan to use when presenting the
show. Used for centering the content.

=item width: <number>

The number of columns in the terminal you plan to use when presenting
the show. Used for centering the content.

=item indent: <number>

All slides will be indented by this number of spaces by default.

=item list_indent: <number>

Auto detect slides that have lists in them, and indent them by the
specified number of columns.

=item vim: <name>

You can specify the name of the vim executable to use. If you set this to
C<gvim> special gvim support will be provided.

=item GVim options

The following options are available, if your vim option is set to gvim.

    fuopt: maxhorz,maxvert
    guioptions: egmLtT
    guicursor: a:blinkon0-ver25-Cursor
    guifont: Bitstream_Vera_Sans_Mono:h18

These are all documented by gvim's help system. Please see that for more
information.

=back

=head1 KEY MAPPINGS

These are the standard key mappings specified in the local C<.vimrc>.

=over

=item <SPACE>

Advance one slide.

=item <BACKSPACE>

Go back one slide.

=item ??

Bring up the help screen.

=item RR (or R -- deprecated)

If the current slide is declared Perl, Python, Ruby, PHP, Haskell or
JavaScript, then run it accordingly.

=item QQ

Quit Vroom.

=item VV

Since these vim options apply while editing the C<slides.vroom> file
(yes, beware), you can use this shortcut to launch Vroom on the current
contents whilst writing your slides.

=item EE

Edit the file that the cursor is on the filename of.

You can put file path names in your slides, and then easily bring them
up during your presentation.

=item OO

On a Mac, run the OS X C<open> command on the argument that your cursor is on.

For instance, if you want to display an image, you could put the file
path of the image in your slide, then use OO to launch it.

=back

=head1 CUSTOM CONFIGURATION

You can create a file called C<.vroom/vimrc> in your home directory. If
vroom sees this file, it will append it onto every local C<.vimrc> file
it creates.

Use this file to specify your own custom vim settings for all your vroom
presentations.

You can also create a file called C<.vroom/gvimrc> for gvim overrides,
if you are using gvim.

=head1 USING MacVim OR gvim

If you have a Mac, you really should try using MacVim for Vroom slide
shows. You can run it in fullscreen mode, and it looks kinda
professional.

To do this, set the vim option in your config section:

    vim: gvim

NOTE: On my Mac, I have gvim symlinked to mvim, which is a smart startup
      script that ships with MacVim. Ping me, if you have questions
      about this setup.

=head1 GITHUB NOTES

I(ngy) put all my public talks on github. I think it is an excellent way
to publish your slides and give people a url to review them. Here are
the things I do to make this work well:

1) I create a repository for every presentation I give. The name of
   the repo is of the form <topic>-<event/time>-talk. You can go to
   L<http://github.com/ingydotnet/> and look for the repos ending
   with C<-talk>.

2) GitHub has a feature called gh-pages that you can use to create a
   website for each github repo. I use this feature to publish the html
   output of my talk. I do something like this:

    vroom --html
    mv html /tmp
    git branch gh-pages
    git checkout gh-pages
    rm -r *.html
    mv /tmp/html/* .
    rmdir /tmp/html
    git add .
    git commit -m 'Publish my slides'
    git push origin gh-pages
    git checkout master

2B) Vroom comes with a C<--ghpublish> option. If you run:

    > vroom -ghpublish

it will generate a script called C<ghpublish> that contains commands like the
ones above, to publish your slides to a gh-pages branch.

3) If my repo is called C<vroom-yapcna2009-talk>, then after I publish
   the talk to the gh-pages branch, it will be available as
   L<http://ingydotnet.github.com/vroom-yapcna2009-talk>.
   I then link this url from
   L<http://github.com/ingydotnet/vroom-yapcna2009-talk> as the Homepage
   url.

You can see an example of a talk published to HTML and posted via gh-pages
at L<http://ingydotnet.github.com/vroom-pm/>.

=head1 NOTE

Vroom is called Vroom, but the module is Vroom::Vroom because the
CPAN shell sometimes thinks Vroom is Tim Vroom, and it refuses to
install him.

Use a shell command like this to install Vroom:

    sudo cpan Vroom::Vroom

=head1 AUTHOR

Ingy döt Net <ingy@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008, 2009. Ingy döt Net.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut
