# program via JTAG - windows VM
open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE {deploy/hsm_overlay.bit} $device
program_hw_devices $device

close_hw_target
disconnect_hw_server
close_hw_manager