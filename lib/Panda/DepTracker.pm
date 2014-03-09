class DepTracker is CompUnitRepo {
    method load_module($module_name, %opts, *@GLOBALish is rw, :$line, :$file) {
        if %*ENV<PANDA_DEPTRACKER_FILE> && $module_name ne 'Panda::DepTracker' {
            %*ENV<PANDA_DEPTRACKER_FILE>.IO.spurt: { :$module_name, :%opts }.perl ~ ",\n", :append;
        }
        nextsame;
    }
}
nqp::bindhllsym('perl6', 'ModuleLoader', DepTracker);
