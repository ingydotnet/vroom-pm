use inc::Module::Install;

name        'Vroom';
all_from    'lib/Vroom/Vroom.pm';

requires 'IO::All';
requires 'YAML::XS';
requires 'Class::Field';
requires 'File::HomeDir';
requires 'Template::Toolkit::Simple';

install_script 'vroom';

WriteAll;
