use strict; use warnings;
package Vroom;
our $VERSION = '0.37';
use Vroom::Mo;

use File::HomeDir;
use IO::All;
use Template::Toolkit::Simple;
use Term::Size::Any qw( chars pixels );
use YAML::XS;
use File::Spec;
use File::Copy;

use Getopt::Long;
use Cwd;
use Carp;

use Encode;

has input => 'slides.vroom';
has notesfile => 'notes.txt';
has has_notes => 0;
has stream => '';
has ext => '';
has help => 0;
has clean => 0;
has compile => 0;
has sample => 0;
has run => 0;
has html => 0;
has text => 0;
has ghpublish => 0;
has start => 0;
has digits => 0;
has skip => 0;
has config => {
    title => 'Untitled Presentation',
    height => 24,
    width => 80,
    list_indent => 10,
    skip => 0,
    vim => 'vim',
    vim_opts => '-u NONE',
    vimrc => '',
    gvimrc => '',
    script => '',
    auto_size => 0,
};

sub usage {
    return <<'...';
    Usage: vroom <command> [options]

    Commands:
        new          - Create a sample 'slides.vroom' file
        vroom        - Start slideshow
        compile      - Generate slides
        html         - Publish slides as HTML
        text         - Publish slides as plain text
        clean        - Delete generated files
        help         - Get help!

    Options:
        --skip=#     - Skip # of slides
        --input=name - Specify an input file name

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
    elsif ($self->text) {
        $self->makeText;
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

    my $cmd = shift(@ARGV) or die $self->usage;
    die $self->usage unless $cmd =~ s/
        ^-{0,2}(
            help |
            new |
            vroom |
            compile |
            run |
            html |
            text |
            clean |
            ghpublish
        )$
    /$1/x;
    $cmd = 'start' if $cmd eq 'vroom';
    $cmd = 'sample' if $cmd eq 'new';
    $self->{$cmd} = 1;

    GetOptions(
        "input=s"  => \$self->{input},
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
    unlink($self->notesfile);
    io->dir('bin')->rmtree;
    io->dir('done')->rmtree;
}

sub cleanAll {
    my $self = shift;
    $self->cleanUp;
    io->dir('html')->rmtree;
    io->dir('text')->rmtree;
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
    elsif ($slide =~ /\.sh$/) {
        exec "clear; $ENV{SHELL} -i run.slide";
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
    $self->writeScriptRunner;
    $self->writeHelp;
}

sub makeText {
    my $self = shift;
    $self->cleanAll;
    $self->makeSlides;
    io('text')->mkdir;
    my @slides = glob('0*');
    for my $slide (@slides) {
        next unless $slide =~ /^(\d+)(\.\S+)?$/;
        my $num = $1;
        my $ext = $2 || '';
        my $text = io(-e "${num}z$ext" ? "${num}z$ext" : "$num$ext")->all();
        io(catfile('text',$slide))->print($text);
    }
    eval {
        copy('.vimrc','text');
    };
    $self->cleanUp;
}

sub makeHTML {
    my $self = shift;
    $self->cleanAll;
    $self->makeSlides;
    io('html')->mkdir;
    my @slides = glob('0*');
    my @notes = $self->parse_notesfile;
    for (my $i = 0; $i < @slides; $i++) {
        my $slide = $slides[$i];
        my $prev = ($i > 0) ? $slides[$i - 1] : 'index';
        my $next = ($i + 1 < @slides) ? $slides[$i + 1] : '';
        my $text = io($slide)->all;
        $text = Template::Toolkit::Simple->new()->render(
            $self->slideTemplate,
            {
                title => $notes[$i]->{'title'},
                prev => $prev,
                next => $next,
                content => decode_utf8($text),
                notes => $self->htmlize_note($notes[$i]->{'text'}),
            }
        );
        io(catfile('html',$slide.'.html'))->print($text);
    }

    my $index = [];
    for (my $i = 0; $i < @slides; $i++) {
        my $slide = $slides[$i];
        next if $slide =~ /^\d+[a-z]/;
        my $title = io($slide)->all;
        $title =~ s/.*?((?-s:\S.*)).*/$1/s;
        push @$index, [$slide, decode_utf8($title)];
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
        window.location = "[% index.0.0 %].html";
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
<body onkeydown="return navigate(event)">
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
</html>
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
<body onkeydown="return navigate(event)">
<div style="border-style: solid ; border-width: 2px ; font-size: x-large">
<pre>
[%- content | html -%]
</pre>
</div>
<br>
<div style="font-size: small">
<p>[% notes %]</p>
</div>
</body>
</html>
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

my $TRANSITION   = qr/^\+/m;
my $SLIDE_MARKER = qr/^={4}\n/m;
my $TITLE_MARKER = qr/^%\s*(.*?)\n/m;

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
        $self->has_notes(1) if $slide =~ $SLIDE_MARKER;
    }
    $self->{digits} = int(log(@raw_slides)/log(10)) + 2;

    my $number = 0;

    '' > io($self->notesfile) if $self->has_notes;                      # start with a blank file so we can append
    for my $raw_slide (@raw_slides) {
        my $config = $self->parseSlideConfig(shift @raw_configs);

        next if $config->{skip};

        # could move the increment of $number up here, but then we'd count config slides
        # and we don't really want to do that
        # so just use $number + 1 for now, and we'll increment below
        my ($title, $notes) = $self->extract_notes($raw_slide, $number + 1);

        $raw_slide = $self->applyOptions($raw_slide, $config)
            or next;

        $number++;

        if ($self->config->{skip} or $self->skip) {
            $self->config->{skip}-- if $self->config->{skip};
            $self->{skip}-- if $self->{skip};
            next;
        }

        $self->print_notes($title, $number, $notes) if $self->has_notes;

        $raw_slide = $self->padVertical($raw_slide);

        my @slides;
        my @scripts;
        my $slide = '';
        for my $part (split /$TRANSITION/, $raw_slide) {
            $slide = '' if $config->{replace};
            my $script = '';
            if ($self->config->{script}) {
                ($part, $script) = $self->parseScript($part);
            }
            $slide .= $part;
            $slide = $self->padVertical($slide)
                if $config->{replace};
            push @slides, $slide;
            push @scripts, $script;
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
            my $file_name = "$base_name$suf" . $self->ext;
            io($file_name)->print($slide);
            if (my $script = shift @scripts) {
                io("bin/$file_name")->assert->print($script);
            }
        }
    }
}

my $NEXT_SLIDE = '<Space>';

sub extract_notes {
    my $self = shift;
    # have to deal with the slide argument in $_[0] directly so we can modify it
    my $number = $_[1];

    my $title = $_[0] =~ s/$TITLE_MARKER// ? $1 : "Slide $number";
    my $notes = $_[0] =~ s/$SLIDE_MARKER(.*)\s*\Z//s ? $1 : '';

    # verify that the number of transitions in the notes matches the number of transitions in the slide
    # if not, do something about it
    # (note: using a secret operator here; see http://www.catonmat.net/blog/secret-perl-operators/#goatse )
    my $num_slide_transitions =()= $_[0] =~ /$TRANSITION/g;
    my $num_notes_transitions =()= $notes =~ /$TRANSITION/g;
    if ($num_notes_transitions < $num_slide_transitions)
    {
        # add more transitions
        $notes .= "\n+" x ($num_slide_transitions - $num_notes_transitions);
    }
    elsif ($num_notes_transitions > $num_slide_transitions)
    {
        # warn, and then remove transitions
        # we'll reverse the string so we can remove transitions from back to front
        warn("too many transitions for slide $title");
        $notes = reverse $notes;
        $notes =~ s/\+\n/\n/ for 1..($num_notes_transitions - $num_slide_transitions);
        $notes = reverse $notes;
    }

    $notes =~ s/$TRANSITION/$NEXT_SLIDE\n/g;

    return ($title, $notes);
}

sub print_notes {
    my $self = shift;
    my ($title, $number, $notes) = @_;

    "\n" . ($number == 1 ? ' ' x length($NEXT_SLIDE) : $NEXT_SLIDE) . "    -- $title --\n\n$notes\n" >> io($self->notesfile);
}

sub parse_notesfile
{
    my $self = shift;

    return () unless -r $self->notesfile;
    my $notes = io($self->notesfile)->slurp;

    # first slide doesn't have a marker, so we'll add one, for consistency
    $notes = $NEXT_SLIDE . $notes;

    my @notes;
    my @stream = split(/\Q$NEXT_SLIDE\E(?:\s+-- (.*?) --)?\s*/, $notes);
    # skipping 0 because, since we're starting with what we're splitting on, the first field will
    # always be empty
    for (1..$#stream)
    {
        if ($_ % 2)
        {
            my $title = $stream[$_];
            $title = $notes[-1]->{'title'} unless defined $title;
            push @notes, { title => $title };
        }
        else
        {
            my $text = $stream[$_];
            $text =~ s/\s+\Z//;
            $notes[-1]->{'text'} = $stream[$_];
        }
    }

    return @notes;
}

my %inline_tags; BEGIN { %inline_tags = ( BQ => 'code', IT => 'i', BO => 'b', ); }
sub inline_element { my $t = $_[1]; $t =~ s/^.//; $t =~ s/.$//; return "<$inline_tags{$_[0]}>$t</$inline_tags{$_[0]}>" }
sub htmlize_note
{
     use Text::Balanced qw< extract_multiple extract_delimited >;

    my $self = shift;
    my ($note) = @_;
    $note = '' unless defined $note;

    $note =~ s{((^\s*\*\s+.+?\n)+)}{"<ul>" . join('', map { s/^\s*\*\s+//; "<li>$_</li>" } split("\n", $1)) . "</ul>"}meg;

    my @bits;
    $note = join('', map { ref $_ ? scalar((push @bits, inline_element(ref $_, $$_)), "{X$#bits}") : $_ }
        extract_multiple($note,
        [
            { BQ => sub { extract_delimited($_[0], q{`}, '', q{`}) } },
            { IT => sub { extract_delimited($_[0], q{_}, '', q{_}) } },
            { BO => sub { extract_delimited($_[0], q{*}, '', q{*}) } },
            qr/[^`_*]+/,
        ])
    );
    $note =~ s{--}{&mdash;}g;
    $note =~ s{ \.\.\.}{&nbsp;...}g;
    $note =~ s{\n+}{</p><p>}g;
    $note =~ s/{X(\d+)}/$bits[$1]/g;

    return $note;
}

sub parseScript {
    my $self = shift;
    my $text = shift;
    chomp $text;
    $text .= "\n";
    my $script = '';
    my $delim = $self->config->{script};
    while ($text =~ s/^[\ \t]*\Q$delim\E(.*\n)//m) {
        $script .= $1;
    }
    return ($text, $script);
}

sub formatNumber {
    my $self = shift;
    my $number = shift;
    my $digits = $self->digits;
    return sprintf "%0${digits}d", $number;
}

my $types = {
    # add pl6 and py3
    perl => 'pl', pl => 'pl', pm => 'pm',
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
        $config->{$option} = 1
            if $option =~ /^cd/;
        $config->{$1} = 1
            if $option =~ /^(config|skip|center|replace|$type_list)$/;
        $config->{$1} = 1
            if $option =~ /^(\.\w+)$/;
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

        if ($config->{auto_size}) {
            my ($columns, $rows) = Term::Size::Any::chars *STDOUT{IO};

            $config->{width}  = $columns;
            $config->{height} = $rows;
        }

        $self->config($config);
        return '';
    }

    $slide ||= '';
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
        elsif ($key =~ s/^cd//) {
            if (my $e = $types->{$key}) {
                $ext = ".cd.$e";
                last;
            }
        }
        elsif ($key =~ s/^\.(\w+)//) {
            $ext = ".$1";
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
    $slide =~ s/ +$//mg;
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

    my $next_cmd = $self->config->{script}
        ? ':n<CR>:<CR>:call RunIf()<CR>:<CR>gg'
        : ':n<CR>:<CR>gg';
    my $script_functions = $self->config->{script} ? <<'...' : '';
function RunIf()
    let script = "bin/" . expand("%")
    let done = "done/" . expand("%")
    if filereadable(done)
        return
    endif
    if filereadable(script)
        call system("sh " . script)
        call system("touch " . done)
    endif
    return
endfunction

function RunNow()
    let done = "done/" . expand("%")
    call system("rm -f " . done)
    call RunIf()
endfunction
...

    die <<'...'
The .vimrc in your current directory does not look like vroom created it.

If you are sure it can be overwritten, please delete it yourself this one
time, and rerun vroom. You should not get this message again.

...
    if -e '.vimrc' and io('.vimrc')->getline !~ /Vroom-\d\.\d\d/;

    my $title = "%-20f " . $self->config->{title};
    $title =~ s/\s/\\ /g;
    no strict 'refs';
    io(".vimrc")->print(<<"...");
" This .vimrc file was created by Vroom-${"VERSION"}
set nocompatible
syntax on
$script_functions
map <SPACE> $next_cmd
map <BACKSPACE> :N<CR>:<CR>gg
map R :!vroom -run %<CR>
map RR :!vroom -run %<CR>
map AA :call RunNow()<CR>:<CR>
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

sub writeScriptRunner {
    my $self = shift;
    return unless $self->config->{script};
    mkdir 'done';
}

sub writeHelp {
    my $self = shift;
    io('.help')->print(<<'...');

    <SPACE>         Advance
    <BACKSPACE>     Go back

    ??              Help
    QQ              Quit Vroom

    RR              Run slide as a program
    VV              vroom vroom
    EE              Edit file under cursor
    OO              Open file under cursor (Mac OS X)


    (Press SPACE to leave Help screen and continue)

...
}

sub startUp {
    my $self = shift;
    my $vim = $self->config->{vim};
    my $vim_opts = $self->config->{vim_opts} || '';
    exec "$vim $vim_opts '+source .vimrc' 0*";
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
# Edit this file with your content. Then run `vroom vroom` to start
# the show!
#
# See `perldoc Vroom` for complete details.
#
---- config
# Basic config options.
title: Vroom!
indent: 5
auto_size: 1
# height: 18
# width: 69
vim_opts: '-u NONE'
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
* Run 'vroom vroom'.
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
vroom html || exit 1
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

1;
