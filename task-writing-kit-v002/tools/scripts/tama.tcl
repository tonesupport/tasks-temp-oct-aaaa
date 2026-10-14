# Thin wrapper: canonical tama lives at lib/tosu/tama.tcl
set _tama_wrap_dir [file dirname [file normalize [info script]]]
source [file join $_tama_wrap_dir .. lib tosu tama.tcl]
