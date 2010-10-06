use inc::Module::Install;

name        'Vroom';
all_from    'lib/Vroom.pm';
readme_from;
manifest_skip;
ack_xxx;
version_check;

requires 'IO::All';
requires 'YAML::XS';
requires 'File::HomeDir';
requires 'Template::Toolkit::Simple';

use_gloom 'Vroom::OO';

install_script 'vroom';

WriteAll;
