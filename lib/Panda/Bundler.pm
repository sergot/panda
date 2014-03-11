class Panda::Bundler;
use Panda::Common;
use Panda::Project;

sub guess-project($where) {
    my $name;
    my $description;
    my $source-url;

    indir $where, {
        if 'META.info'.IO.e {
            try my $json = from-json 'META.info'.IO.slurp;
            if $json {
                $name        = $json<name>        if $json<name>;
                $description = $json<description> if $json<description>;
                $source-url  = $json<source-url>  if $json<source-url>;
            }
        }
        unless $name {
            $name = $where.parts<basename>.subst(/:i ^'p' 'erl'? '6-'/, '').split(/<[\-_]>+/, :g)>>.tc.join('::');
        }
        unless $description {
            $description = '.git/description'.IO.slurp if '.git/description'.IO.e
        }
        unless $source-url {
            try my $git = qx{git remote show origin}.lines.first(/\.git$/);
            if $git && $git ~~ /$<url>=\S+$/ {
                $source-url = $<url>;
                if $source-url ~~ m/'git@' $<host>=[.+] ':' $<repo>=[<-[:]>+] $/ {
                    $source-url = "git://$<host>/$<repo>"
                }
            }
        }
    };

    Panda::Project.new( :$name, :metainfo( :$description, :$source-url ) )
}

method bundle($panda, :$notests) {
    my $dir  = cwd.absolute;
    my $bone = guess-project($dir);

    temp $*EXECUTABLE_NAME = "$*EXECUTABLE_NAME -MPanda::DepTracker";
    %*ENV<PANDA_DEPTRACKER_FILE> = "$dir/deptracker-$*PID";
    %*ENV<PANDA_PROTRACKER_FILE> = "$dir/protracker-$*PID";

    $panda.announce('building', $bone);
    unless $_ = $panda.builder.build($dir) {
        die X::Panda.new($bone.name, 'build', $_)
    }
    if %*ENV<PANDA_DEPTRACKER_FILE>.IO.e {
        my $test = EVAL %*ENV<PANDA_DEPTRACKER_FILE>.IO.slurp;
        for $test.list -> $m {
            $bone.metainfo<build-depends>.push: $m<module_name> # XXX :auth/:ver/:from/...
        }
        %*ENV<PANDA_DEPTRACKER_FILE>.IO.spurt: ''
    }

    unless $notests {
        temp $*EXECUTABLE_NAME = "\"$*EXECUTABLE_NAME -MPanda::DepTracker\"";
        $panda.announce('testing', $bone);
        unless $_ = $panda.tester.test($dir) {
            die X::Panda.new($bone.name, 'test', $_)
        }
        if %*ENV<PANDA_DEPTRACKER_FILE>.IO.e {
            my $test = EVAL %*ENV<PANDA_DEPTRACKER_FILE>.IO.slurp;
            for $test.list -> $m {
                $bone.metainfo<test-depends>.push: $m<module_name> # XXX :auth/:ver/:from/...
            }
            %*ENV<PANDA_DEPTRACKER_FILE>.IO.spurt: ''
        }
        if %*ENV<PANDA_PROTRACKER_FILE>.IO.e {
            my $test = EVAL %*ENV<PANDA_PROTRACKER_FILE>.IO.slurp;
            for $test.list -> $m {
                for $m<symbols> (-) $bone.metainfo<build-depends> {
                    if $m<file> && $m<file>.match(/^"$dir" [ [\/|\\] blib [\/|\\] ]? $<relname>=.+/) -> $match {
                        $bone.metainfo<provides>{$_} = ~$match<relname>
                    }
                }
            }
        }
    }

    $bone.metainfo<depends> = [($bone.metainfo<test-depends> (&) $bone.metainfo<build-depends>).list.flat];

    $bone.metainfo<version> = prompt "Please enter version number (example: v1.2.3): ";

    $panda.announce('Creating META.info.proposed');
    'META.info.proposed'.IO.spurt: to-json {
        name          => $bone.name,
        description   => $bone.metainfo<description>,
        version       => $bone.metainfo<version>,
        build-depends => $bone.metainfo<build-depends>,
        test-depends  => $bone.metainfo<test-depends>,
        depends       => $bone.metainfo<depends>,
        provides      => $bone.metainfo<provides>,
        source-url    => $bone.metainfo<source-url>,
    };

    try unlink %*ENV<PANDA_DEPTRACKER_FILE> if %*ENV<PANDA_DEPTRACKER_FILE>.IO.e;
    try unlink %*ENV<PANDA_PROTRACKER_FILE> if %*ENV<PANDA_PROTRACKER_FILE>.IO.e;

    return True;
}

# vim: ft=perl6
