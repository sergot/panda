class Panda::Bundler;
use Panda::Common;
use Panda::Project;

sub guess-project($where) {
    my $name;
    my $description;
    my $source-url;

    indir $where, {
        if 'META6.json'.IO.e {
            try my $json = from-json 'META6.json'.IO.slurp;
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

    try {
        temp $*EXECUTABLE = "$*EXECUTABLE -MPanda::DepTracker";
        %*ENV<PANDA_DEPTRACKER_FILE> = "$dir/deptracker-build-$*PID";
        %*ENV<PANDA_PROTRACKER_FILE> = "$dir/protracker-build-$*PID";
        try unlink %*ENV<PANDA_DEPTRACKER_FILE> if %*ENV<PANDA_DEPTRACKER_FILE>.IO.e;
        try unlink %*ENV<PANDA_PROTRACKER_FILE> if %*ENV<PANDA_PROTRACKER_FILE>.IO.e;

        $panda.announce('building', $bone);
        unless $_ = $panda.builder.build($dir) {
            die X::Panda.new($bone.name, 'build', $_)
        }
        if %*ENV<PANDA_DEPTRACKER_FILE>.IO.e {
            my $test = EVAL %*ENV<PANDA_DEPTRACKER_FILE>.IO.slurp;
            for $test.list -> $m {
                $bone.metainfo<build-depends>.push: $m<module_name> unless $m<file> ~~ /^"$dir" [ [\/|\\] blib ]? [\/|\\] lib [\/|\\]/ # XXX :auth/:ver/:from/...
            }
            %*ENV<PANDA_DEPTRACKER_FILE>.IO.spurt: ''
        }

        if %*ENV<PANDA_PROTRACKER_FILE>.IO.e {
            my $test = EVAL %*ENV<PANDA_PROTRACKER_FILE>.IO.slurp;
            for $test.list -> $m {
                for $m<symbols> (-) $bone.metainfo<build-depends> {
                    if $m<file> && $m<file>.match(/^"$dir" [ [\/|\\] blib [\/|\\] ]? <?before 'lib' [\/|\\] > $<relname>=.+/) -> $match {
                        $bone.metainfo<build-provides>{$_} = ~$match<relname>
                    }
                }
            }
            %*ENV<PANDA_PROTRACKER_FILE>.IO.spurt: ''
        }

        unless $notests {
            temp $*EXECUTABLE = "\"$*EXECUTABLE -MPanda::DepTracker\"";
            $panda.announce('testing', $bone);
            unless $_ = $panda.tester.test($dir) {
                die X::Panda.new($bone.name, 'test', $_)
            }
            if %*ENV<PANDA_DEPTRACKER_FILE>.IO.e {
                my $test = EVAL %*ENV<PANDA_DEPTRACKER_FILE>.IO.slurp;
                for $test.list -> $m {
                    $bone.metainfo<test-depends>.push: $m<module_name> unless $m<file> ~~ /^"$dir" [ [\/|\\] blib ]? [\/|\\] lib [\/|\\]/ # XXX :auth/:ver/:from/...
                }
                $bone.metainfo<test-depends> = [$bone.metainfo<test-depends>.list.uniq];
            }
            if %*ENV<PANDA_PROTRACKER_FILE>.IO.e {
                my $test = EVAL %*ENV<PANDA_PROTRACKER_FILE>.IO.slurp;
                for $test.list -> $m {
                    for $m<symbols> (-) $bone.metainfo<build-depends> {
                        if $m<file> && $m<file>.match(/^"$dir" [ [\/|\\] blib [\/|\\] ]? <?before 'lib' [\/|\\] > $<relname>=.+/) -> $match {
                            $bone.metainfo<test-provides>{$_} = ~$match<relname>
                        }
                    }
                }
            }
        }

        unless $bone.name eq 'Panda' {
            $bone.metainfo<build-depends> = [($bone.metainfo<build-depends> (-) 'Panda::DepTracker').list.flat];
            $bone.metainfo<test-depends>  = [($bone.metainfo<test-depends> (-) 'Panda::DepTracker').list.flat];
        }
        $bone.metainfo<depends> = [($bone.metainfo<test-depends> (&) $bone.metainfo<build-depends>).list.flat];
        for $bone.metainfo<test-provides>.kv, $bone.metainfo<build-provides>.kv -> $k, $v {
            $bone.metainfo<provides>{$k} = $v
        }

        $bone.metainfo<version> = prompt "Please enter version number (example: v1.2.3): ";

        $panda.announce('Creating META6.json.proposed');
        'META6.json.proposed'.IO.spurt: to-json {
            perl           => 'v6',
            name           => $bone.name,
            description    => $bone.metainfo<description>,
            version        => $bone.metainfo<version>,
            build-depends  => $bone.metainfo<build-depends>,
            test-depends   => $bone.metainfo<test-depends>,
            depends        => $bone.metainfo<depends>,
            provides       => $bone.metainfo<provides>,
            support        => {
                source => $bone.metainfo<source-url>,
            }
        };

        CATCH {
            try unlink %*ENV<PANDA_DEPTRACKER_FILE> if %*ENV<PANDA_DEPTRACKER_FILE>.IO.e;
            try unlink %*ENV<PANDA_PROTRACKER_FILE> if %*ENV<PANDA_PROTRACKER_FILE>.IO.e;
        }
    }

    try unlink %*ENV<PANDA_DEPTRACKER_FILE> if %*ENV<PANDA_DEPTRACKER_FILE>.IO.e;
    try unlink %*ENV<PANDA_PROTRACKER_FILE> if %*ENV<PANDA_PROTRACKER_FILE>.IO.e;

    return True;
}

# vim: ft=perl6
