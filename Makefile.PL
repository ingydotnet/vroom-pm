use inc::Module::Install;

name        'Vroom';
all_from    'lib/Vroom.pm';

require 'IO::All';
require 'YAML::XS';
require 'Class::Field';

WriteAll;
