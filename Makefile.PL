use inc::Module::Install;

name        'Vroom';
all_from    'lib/Vroom/Vroom.pm';

requires 'IO::All';
requires 'YAML::XS';
requires 'Class::Field';

install_script 'vroom';

WriteAll;
