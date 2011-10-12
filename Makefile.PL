use inc::Module::Install;

all_from    'lib/Vroom.pm';
readme_from;
manifest_skip;
ack_xxx;
version_check;

requires 'IO::All';
requires 'YAML::XS';
requires 'File::HomeDir';
requires 'Template::Toolkit::Simple';
requires 'Term::Size';

use_gloom 'Vroom::OO';

install_script 'vroom';

WriteAll;
