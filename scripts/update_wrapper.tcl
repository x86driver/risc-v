# scripts/update_wrapper.tcl
# GUI 用法：
#   source scripts/update_wrapper.tcl
#   update_bd_wrapper
#
# batch 用法：
#   vivado -mode batch -source scripts/update_wrapper.tcl -tclargs kcu105.xpr

proc update_bd_wrapper {{xpr ""}} {
    if {$xpr ne ""} {
        open_project $xpr
    }

    set proj_name [get_property NAME [current_project]]
    set proj_dir  [get_property DIRECTORY [current_project]]

    # 取得 BD
    set bds [get_files -quiet *.bd]
    if {[llength $bds] == 0} { error "No .bd found in project" }

    # 目前先假設單一 BD；若你有多個 BD，可改成 foreach
    set bd [lindex $bds 0]

    # 1) 強制重新產生 wrapper（產生在 .gen/.../hdl/*_wrapper.v）
    make_wrapper -files $bd -top -force

    # 2) 找到剛生成的 .gen wrapper（不寫死 design_1）
    set gen_glob [file join $proj_dir "${proj_name}.gen" sources_1 bd * hdl *_wrapper.v]
    set gen_list [glob -nocomplain $gen_glob]
    if {[llength $gen_list] == 0} { error "Cannot find generated wrapper under: $gen_glob" }

    # 如果有多個 wrapper，就取最新修改時間那個
    set gen_wrap ""
    set best_mtime -1
    foreach f $gen_list {
        set mt [file mtime $f]
        if {$mt > $best_mtime} { set best_mtime $mt; set gen_wrap $f }
    }

    # 3) 覆寫到 imports（這份要進 git）
    set imports_dir [file join $proj_dir "${proj_name}.srcs" sources_1 imports hdl]
    file mkdir $imports_dir
    set imp_wrap [file join $imports_dir [file tail $gen_wrap]]
    file copy -force $gen_wrap $imp_wrap

    # 4) 確保 project 只使用 imports wrapper（不要引用 .gen wrapper）
    #    - 移除 project 內指向 .gen 的 wrapper
    set gen_in_proj [get_files -quiet */*.gen/*/bd/*/hdl/*_wrapper.v]
    if {[llength $gen_in_proj] > 0} {
        remove_files $gen_in_proj
    }

    #    - 確保 imports wrapper 在 project 內
    if {[llength [get_files -quiet $imp_wrap]] == 0} {
        add_files -norecurse $imp_wrap
    }

    # 5) 設 top（用檔名推 module 名稱）
    set topmod [file rootname [file tail $imp_wrap]]
    set_property top $topmod [current_fileset]

    puts "Updated wrapper: $imp_wrap (top=$topmod)"
}

# batch 模式支援 -tclargs <xpr>
if {[llength $argv] >= 1} {
    update_bd_wrapper [lindex $argv 0]
}
