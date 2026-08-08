# Xenon Performance v1.9.2 — hardware memory probe
#
# Strict, read-only DLL entry probe for Xbox 360/Xenon.
# Uses the 32-bit ABI style used by FreeChainXenon samples.
# No XAM UI calls from the loader thread. No NAND/SMC/game-memory writes.
#
# DLL_PROCESS_ATTACH (r4 == 1): resolve MmQueryStatistics (ordinal 198),
# query MM_STATISTICS, validate basic fields, and return TRUE on success.
# Other DLL reasons return TRUE immediately.

.set ORD_MM_QUERY_STATISTICS, 198

.section .text
.global _start

_start:
    # Preserve the DLL loader return path using a 32-bit ABI stack frame.
    mflr    r0
    stwu    r1, -0x100(r1)
    stw     r0,  0x08(r1)
    stw     r31, 0x0c(r1)

    # Only probe on DLL_PROCESS_ATTACH.
    cmpwi   r4, 1
    bne     probe_success

    li      r3, ORD_MM_QUERY_STATISTICS
    bl      get_kernel_export
    cmpwi   r3, 0
    beq     probe_failure
    mr      r31, r3

    # MM_STATISTICS is 26 DWORDs / 104 bytes.
    addi    r4, r1, 0x20
    li      r5, 0
    li      r6, 26
    mtctr   r6
zero_stats:
    stw     r5, 0(r4)
    addi    r4, r4, 4
    bdnz    zero_stats

    li      r5, 104
    stw     r5, 0x20(r1)       # Length

    mtctr   r31
    addi    r3, r1, 0x20
    bctrl

    # Validate the fields we will later feed to the optimizer.
    lwz     r4, 0x24(r1)       # TotalPhysicalPages
    cmpwi   r4, 0
    beq     probe_failure

    lwz     r5, 0x2c(r1)       # TitleAvailablePages
    cmpw    r5, r4
    bgt     probe_failure

probe_success:
    li      r3, 1              # TRUE: DLL load accepted / probe passed
    b       probe_return

probe_failure:
    li      r3, 0              # FALSE: make loader reject the probe visibly

probe_return:
    lwz     r31, 0x0c(r1)
    lwz     r0,  0x08(r1)
    addi    r1, r1, 0x100
    mtlr    r0
    blr

# Read a 32-bit little-endian PE field.
# IN:  r4 = address
# OUT: r4 = host-order 32-bit value
get_le32:
    li      r5, 24
    lbz     r6, 3(r4)
    slw     r6, r6, r5
    subi    r5, r5, 8
    lbz     r7, 2(r4)
    slw     r7, r7, r5
    or      r6, r6, r7
    subi    r5, r5, 8
    lbz     r7, 1(r4)
    slw     r7, r7, r5
    or      r6, r6, r7
    lbz     r7, 0(r4)
    or      r4, r6, r7
    blr

# Resolve an xboxkrnl export by ordinal.
# This intentionally follows the FreeChainXenon resolver address construction:
# no zero-extension of 0x8004xxxx kernel addresses.
# IN:  r3 = ordinal
# OUT: r3 = callable address or zero
get_kernel_export:
    mflr    r12

    lis     r4, 0x8004
    ori     r4, r4, 0x003c
    bl      get_le32
    addis   r4, r4, 0x8004

    addi    r4, r4, 0x0078
    bl      get_le32
    addis   r4, r4, 0x8004

    mr      r8, r4
    addi    r4, r4, 0x0014
    bl      get_le32
    cmpw    r3, r4
    bgt     export_missing

    subi    r3, r3, 1
    addi    r4, r8, 0x001c
    bl      get_le32
    addis   r4, r4, 0x8004

    mulli   r3, r3, 4
    add     r4, r4, r3
    bl      get_le32
    addis   r3, r4, 0x8004

    mtlr    r12
    blr

export_missing:
    li      r3, 0
    mtlr    r12
    blr
