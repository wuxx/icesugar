.extern bss_start
.extern bss_end

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

    la sp, stack_top
    call main
    j .
