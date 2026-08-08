# Xenon Performance v1.9.1 — hardware memory telemetry payload
#
# Read-only Xbox 360/Xenon PowerPC payload.
# - Resolves xboxkrnl exports dynamically.
# - Calls MmQueryStatistics (ordinal 198).
# - Resolves xam.xex with XexGetModuleHandle/XexGetProcedureAddress.
# - Reads XamGetCurrentTitleId (xam ordinal 463).
# - Queues a visible XNotifyQueueUI notification (xam ordinal 656).
# - Performs NO game-memory/NAND/SMC/filesystem writes.
#
# The raw .text is linked for 0x82010000 because the PE wrapper uses image base
# 0x82000000 and a 0x10000 .text RVA. The workflow verifies this invariant.

.set ORD_MM_QUERY_STATISTICS,      198
.set ORD_XEX_GET_MODULE_HANDLE,    405
.set ORD_XEX_GET_PROC_ADDRESS,     407
.set XAM_ORD_CURRENT_TITLE_ID,     463
.set XAM_ORD_NOTIFY_QUEUE_UI,      656

.section .text
.global _start

_start:
    # Preserve return path: unlike the old title tests this is a DLL-style payload
    # and must return TRUE cleanly to the loader.
    mflr    r0
    stdu    r1, -0x500(r1)
    std     r0,  0x20(r1)
    std     r25, 0x40(r1)
    std     r26, 0x48(r1)
    std     r27, 0x50(r1)
    std     r28, 0x58(r1)
    std     r29, 0x60(r1)
    std     r30, 0x68(r1)
    std     r31, 0x70(r1)

    # Resolve the three kernel exports we need.
    li      r3, ORD_XEX_GET_MODULE_HANDLE
    bl      get_kernel_export
    cmpdi   r3, 0
    beq     safe_return
    mr      r30, r3

    li      r3, ORD_XEX_GET_PROC_ADDRESS
    bl      get_kernel_export
    cmpdi   r3, 0
    beq     safe_return
    mr      r29, r3

    li      r3, ORD_MM_QUERY_STATISTICS
    bl      get_kernel_export
    cmpdi   r3, 0
    beq     safe_return
    mr      r28, r3

    # MM_STATISTICS is 104 bytes / 26 dwords.
    addi    r31, r1, 0x100
    mr      r8, r31
    li      r9, 0
    li      r10, 26
    mtctr   r10
zero_mmstats:
    stw     r9, 0(r8)
    addi    r8, r8, 4
    bdnz    zero_mmstats
    li      r9, 104
    stw     r9, 0(r31)             # Length

    # MmQueryStatistics(&stats). We validate the returned structure instead of
    # assuming a particular success-code convention.
    mtctr   r28
    mr      r3, r31
    bctrl
    lwz     r8, 4(r31)             # TotalPhysicalPages
    cmpwi   r8, 0
    beq     safe_return

    # XexGetModuleHandle("xam.xex", &hModule)
    li      r8, 0
    stw     r8, 0x180(r1)
    lis     r3, xam_name@ha
    addi    r3, r3, xam_name@l
    clrldi  r3, r3, 32
    addi    r4, r1, 0x180
    mtctr   r30
    bctrl
    lwz     r27, 0x180(r1)
    cmpwi   r27, 0
    beq     safe_return

    # Resolve XamGetCurrentTitleId.
    li      r8, 0
    stw     r8, 0x188(r1)
    mr      r3, r27
    li      r4, XAM_ORD_CURRENT_TITLE_ID
    addi    r5, r1, 0x188
    mtctr   r29
    bctrl
    lwz     r12, 0x188(r1)
    cmpwi   r12, 0
    beq     safe_return
    mtctr   r12
    bctrl
    mr      r25, r3                 # current Title ID

    # Resolve XNotifyQueueUI.
    li      r8, 0
    stw     r8, 0x18c(r1)
    mr      r3, r27
    li      r4, XAM_ORD_NOTIFY_QUEUE_UI
    addi    r5, r1, 0x18c
    mtctr   r29
    bctrl
    lwz     r26, 0x18c(r1)
    cmpwi   r26, 0
    beq     safe_return

    # Build UTF-16 message in the local stack buffer without libc/formatting:
    # "XP1.9.1 TID=XXXXXXXX TA=XXXXXXXX TP=XXXXXXXX"
    lis     r3, prefix_text@ha
    addi    r3, r3, prefix_text@l
    clrldi  r3, r3, 32
    addi    r4, r1, 0x200
    bl      copy_ascii_to_wide

    mr      r4, r3
    mr      r3, r25
    bl      append_hex32

    mr      r4, r3
    lis     r3, sep_title_avail@ha
    addi    r3, r3, sep_title_avail@l
    clrldi  r3, r3, 32
    bl      copy_ascii_to_wide

    mr      r4, r3
    lwz     r3, 12(r31)             # TitleAvailablePages
    bl      append_hex32

    mr      r4, r3
    lis     r3, sep_total_phys@ha
    addi    r3, r3, sep_total_phys@l
    clrldi  r3, r3, 32
    bl      copy_ascii_to_wide

    mr      r4, r3
    lwz     r3, 4(r31)              # TotalPhysicalPages
    bl      append_hex32

    li      r0, 0
    sth     r0, 0(r3)

    # XNotifyQueueUI(type=14, user=0, areas=XNOTIFY_SYSTEM(1), text, context=NULL)
    # This argument shape matches public Xbox 360 homebrew usage.
    li      r3, 14
    li      r4, 0
    li      r5, 1
    addi    r6, r1, 0x200
    li      r7, 0
    mtctr   r26
    bctrl

safe_return:
    ld      r25, 0x40(r1)
    ld      r26, 0x48(r1)
    ld      r27, 0x50(r1)
    ld      r28, 0x58(r1)
    ld      r29, 0x60(r1)
    ld      r30, 0x68(r1)
    ld      r31, 0x70(r1)
    ld      r0,  0x20(r1)
    addi    r1, r1, 0x500
    mtlr    r0
    li      r3, 1                    # TRUE: DLL load/entry succeeded
    blr

# r3 = ASCII source, r4 = UTF-16 destination.
# Returns r3 = destination pointer immediately after copied text.
copy_ascii_to_wide:
    mr      r8, r3
    mr      r9, r4
copy_ascii_loop:
    lbz     r10, 0(r8)
    cmpwi   r10, 0
    beq     copy_ascii_done
    sth     r10, 0(r9)
    addi    r8, r8, 1
    addi    r9, r9, 2
    b       copy_ascii_loop
copy_ascii_done:
    mr      r3, r9
    blr

# r3 = 32-bit value, r4 = UTF-16 destination.
# Appends exactly 8 uppercase hex digits and returns r3 = new destination.
append_hex32:
    mr      r8, r3
    mr      r9, r4
    li      r10, 28
    li      r11, 8
    mtctr   r11
append_hex_loop:
    srw     r12, r8, r10
    andi.   r12, r12, 0x0f
    cmpwi   r12, 9
    ble     append_hex_digit
    addi    r12, r12, 55             # A-F
    b       append_hex_store
append_hex_digit:
    addi    r12, r12, 48             # 0-9
append_hex_store:
    sth     r12, 0(r9)
    addi    r9, r9, 2
    addi    r10, r10, -4
    bdnz    append_hex_loop
    mr      r3, r9
    blr

# PE export resolver for xboxkrnl.exe at 0x80040000.
# r3 = ordinal. Returns zero-extended export VA in r3 or zero.
get_kernel_export:
    mflr    r11
    mr      r7, r3

    bl      load_kernel_base
    addi    r3, r9, 0x3c
    bl      get_le32
    add     r3, r3, r9

    addi    r3, r3, 0x78
    bl      get_le32
    add     r3, r3, r9

    mr      r8, r3
    addi    r3, r8, 0x14
    bl      get_le32
    cmpw    r7, r3
    bgt     export_not_found

    subi    r7, r7, 1
    addi    r3, r8, 0x1c
    bl      get_le32
    add     r3, r3, r9

    mulli   r7, r7, 4
    add     r3, r3, r7
    bl      get_le32
    add     r3, r3, r9
    clrldi  r3, r3, 32

    mtlr    r11
    blr

export_not_found:
    li      r3, 0
    mtlr    r11
    blr

# Build zero-extended 0x0000000080040000 in r9.
load_kernel_base:
    lis     r9, 0x8004
    clrldi  r9, r9, 32
    blr

# r3 -> little-endian 32-bit PE field. Returns zero-extended value in r3.
get_le32:
    lbz     r4, 0(r3)
    lbz     r5, 1(r3)
    lbz     r6, 2(r3)
    lbz     r10, 3(r3)
    slwi    r5, r5, 8
    slwi    r6, r6, 16
    slwi    r10, r10, 24
    or      r4, r4, r5
    or      r4, r4, r6
    or      r3, r4, r10
    clrldi  r3, r3, 32
    blr

.balign 4
xam_name:
    .asciz "xam.xex"
prefix_text:
    .asciz "XP1.9.1 TID="
sep_title_avail:
    .asciz " TA="
sep_total_phys:
    .asciz " TP="
