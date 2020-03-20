.extern bss_start
.extern bss_end

.extern data_flash_start
.extern data_start
.extern data_end

.extern stack_top

.global start
start:
    la t0, bss_start
    la t1, bss_end

    beq t0, t1, clear_bss_done
clear_bss:
    sw zero, 0(t0)
    addi t0, t0, 4
    bne t0, t1, clear_bss
clear_bss_done:

    la t0, data_flash_start
    la t1, data_start
    la t2, data_end

    beq t1, t2, copy_data_done
copy_data:
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    bne t1, t2, copy_data
copy_data_done:

    la sp, stack_top
    call main
    j .
