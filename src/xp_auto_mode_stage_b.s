# Xenon Performance Stage B — resident Auto Mode
#
# Safety properties of this first Auto Mode build:
#   - polls XamGetCurrentTitleId every two seconds
#   - fingerprints the current XEX using execution metadata and header digest
#   - requires an exact registry match before an apply handler can run
#   - ships with profile_registry_count == 0, so every title is a no-op
#   - performs no filesystem, notification, NAND, SMC or game-memory writes

.set ORD_EX_CREATE_THREAD,             0x000d
.set ORD_KE_DELAY_EXECUTION_THREAD,    0x005a
.set ORD_NT_CLOSE,                     0x00cf
.set ORD_XEX_EXECUTABLE_MODULE_HANDLE, 0x0193
.set ORD_XEX_GET_MODULE_HANDLE,        0x0195
.set ORD_XEX_GET_PROCEDURE_ADDRESS,    0x0197
.set ORD_XAM_GET_CURRENT_TITLE_ID,     0x01cf

.set XEX_HEADER_EXECUTION_INFO,        0x00040006
.set XEX2_MAGIC,                       0x58455832
.set LDR_XEX_HEADER_BASE_OFFSET,       0x0058
.set XEX_EXECUTION_INFO_SIZE,          0x0018
.set XEX_SECURITY_DIGEST_END,          0x0178
.set XEX_SECURITY_HEADER_DIGEST,       0x0164

.set XP_IDENTITY_SIZE,                 0x0028
.set XP_PROFILE_SIZE,                  0x0030
.set XP_PROFILE_APPLY_OFFSET,          0x0024
.set XP_PROFILE_REVERT_OFFSET,         0x0028

.section .text
.global _start
.global auto_mode_thread
.global capture_execution_identity
.global find_exact_profile
.global apply_title_profile
.global revert_title_profile
.global profile_registry_count

_start:
    mflr    r0
    stwu    r1, -0x80(r1)
    stw     r0,  0x08(r1)
    stw     r30, 0x0c(r1)
    stw     r31, 0x10(r1)

    # DLL_PROCESS_ATTACH only. Other loader reasons remain a clean no-op.
    cmpwi   r4, 1
    bne     loader_success

    li      r3, ORD_EX_CREATE_THREAD
    bl      get_kernel_export
    cmpwi   r3, 0
    beq     loader_success
    mr      r31, r3

    li      r3, 0
    stw     r3, 0x20(r1)       # thread handle
    stw     r3, 0x24(r1)       # thread id

    addi    r3, r1, 0x20
    li      r4, 0              # inherit executable stack size
    addi    r5, r1, 0x24
    li      r6, 0              # XapiThreadStartup may be null
    lis     r7, auto_mode_thread@ha
    addi    r7, r7, auto_mode_thread@l
    li      r8, 0
    li      r9, 2              # system thread, starts immediately
    mtctr   r31
    bctrl
    cmpwi   r3, 0
    bne     loader_success

    # The worker owns its execution; close only our creation handle.
    lwz     r30, 0x20(r1)
    cmpwi   r30, 0
    beq     loader_success
    li      r3, ORD_NT_CLOSE
    bl      get_kernel_export
    cmpwi   r3, 0
    beq     loader_success
    mtctr   r3
    mr      r3, r30
    bctrl

loader_success:
    li      r3, 1
    lwz     r31, 0x10(r1)
    lwz     r30, 0x0c(r1)
    lwz     r0,  0x08(r1)
    addi    r1, r1, 0x80
    mtlr    r0
    blr

auto_mode_thread:
    mflr    r0
    stwu    r1, -0x180(r1)
    stw     r0,  0x08(r1)
    stw     r24, 0x0c(r1)
    stw     r25, 0x10(r1)
    stw     r26, 0x14(r1)
    stw     r27, 0x18(r1)
    stw     r28, 0x1c(r1)
    stw     r29, 0x28(r1)
    stw     r30, 0x2c(r1)
    stw     r31, 0x30(r1)

    li      r3, ORD_KE_DELAY_EXECUTION_THREAD
    bl      get_kernel_export
    cmpwi   r3, 0
    beq     auto_mode_exit
    mr      r31, r3

    # Let DLL_PROCESS_ATTACH return before touching loader-managed modules.
    li      r6, -1
    stw     r6, 0xa0(r1)
    lis     r6, 0xfece
    ori     r6, r6, 0xd300
    stw     r6, 0xa4(r1)
    li      r3, 0
    li      r4, 0
    addi    r5, r1, 0xa0
    mtctr   r31
    bctrl

    li      r3, ORD_XEX_GET_MODULE_HANDLE
    bl      get_kernel_export
    cmpwi   r3, 0
    beq     auto_mode_exit
    mr      r30, r3

    li      r3, ORD_XEX_GET_PROCEDURE_ADDRESS
    bl      get_kernel_export
    cmpwi   r3, 0
    beq     auto_mode_exit
    mr      r29, r3

    li      r3, ORD_XEX_EXECUTABLE_MODULE_HANDLE
    bl      get_kernel_export
    cmpwi   r3, 0
    beq     auto_mode_exit
    mr      r27, r3

    lis     r3, xam_module_name@ha
    addi    r3, r3, xam_module_name@l
    addi    r4, r1, 0x34
    mtctr   r30
    bctrl
    cmpwi   r3, 0
    bne     auto_mode_exit

    lwz     r3, 0x34(r1)
    li      r4, ORD_XAM_GET_CURRENT_TITLE_ID
    addi    r5, r1, 0x38
    mtctr   r29
    bctrl
    cmpwi   r3, 0
    bne     auto_mode_exit
    lwz     r26, 0x38(r1)
    cmpwi   r26, 0
    beq     auto_mode_exit

    li      r25, 0            # no active profile
    li      r6, 0
    stw     r6, 0x40(r1)      # current identity title id
    stw     r6, 0x64(r1)      # current identity valid

auto_mode_poll:
    mtctr   r26
    bctrl
    mr      r24, r3
    cmpwi   r24, 0
    beq     auto_mode_no_title

    mr      r3, r24
    addi    r4, r1, 0x70      # observed XpExecutionIdentity
    mr      r5, r27           # &XexExecutableModuleHandle
    bl      capture_execution_identity
    cmpwi   r3, 1
    bne     auto_mode_identity_invalid

    addi    r3, r1, 0x40      # current identity
    addi    r4, r1, 0x70      # observed identity
    bl      identities_equal
    cmpwi   r3, 1
    beq     auto_mode_sleep

    # The full identity changed. Revert before installing the new snapshot.
    cmpwi   r25, 0
    beq     auto_mode_copy_identity
    mr      r3, r25
    addi    r4, r1, 0x40
    bl      revert_title_profile
    li      r25, 0

auto_mode_copy_identity:
    addi    r6, r1, 0x70
    addi    r7, r1, 0x40
    li      r8, 10            # 0x28-byte identity including valid DWORD
    mtctr   r8

auto_mode_copy_identity_loop:
    lwz     r9, 0(r6)
    stw     r9, 0(r7)
    addi    r6, r6, 4
    addi    r7, r7, 4
    bdnz    auto_mode_copy_identity_loop

    addi    r3, r1, 0x40
    bl      find_exact_profile
    cmpwi   r3, 0
    beq     auto_mode_sleep    # unknown title: mandatory no-op

    mr      r25, r3
    mr      r3, r25
    addi    r4, r1, 0x40
    bl      apply_title_profile
    cmpwi   r3, 1
    beq     auto_mode_sleep
    li      r25, 0
    b       auto_mode_sleep

auto_mode_no_title:
    cmpwi   r25, 0
    beq     auto_mode_clear_identity
    mr      r3, r25
    addi    r4, r1, 0x40
    bl      revert_title_profile
    li      r25, 0

auto_mode_clear_identity:
    li      r6, 0
    stw     r6, 0x40(r1)
    stw     r6, 0x64(r1)
    b       auto_mode_sleep

auto_mode_identity_invalid:
    # Never leave a profile active when the exact executable cannot be proven.
    cmpwi   r25, 0
    beq     auto_mode_clear_identity
    mr      r3, r25
    addi    r4, r1, 0x40
    bl      revert_title_profile
    li      r25, 0
    b       auto_mode_clear_identity

auto_mode_sleep:
    # Relative NT interval: -20,000,000 * 100 ns = two seconds.
    li      r6, -1
    stw     r6, 0xa0(r1)
    lis     r6, 0xfece
    ori     r6, r6, 0xd300
    stw     r6, 0xa4(r1)
    li      r3, 0
    li      r4, 0
    addi    r5, r1, 0xa0
    mtctr   r31
    bctrl
    b       auto_mode_poll

auto_mode_exit:
    li      r3, 0
    lwz     r31, 0x30(r1)
    lwz     r30, 0x2c(r1)
    lwz     r29, 0x28(r1)
    lwz     r28, 0x1c(r1)
    lwz     r27, 0x18(r1)
    lwz     r26, 0x14(r1)
    lwz     r25, 0x10(r1)
    lwz     r24, 0x0c(r1)
    lwz     r0,  0x08(r1)
    addi    r1, r1, 0x180
    mtlr    r0
    blr

# IN: r3 = Xam title id, r4 = output identity, r5 = exported global address
# OUT: r3 = 1 only for a complete, internally consistent identity
capture_execution_identity:
    li      r7, 0
    stw     r7, 0x24(r4)      # valid = false until every gate passes

    lwz     r6, 0(r5)
    cmpwi   r6, 0
    beq     identity_failure
    lwz     r6, LDR_XEX_HEADER_BASE_OFFSET(r6)
    cmpwi   r6, 0
    beq     identity_failure

    lwz     r7, 0(r6)
    lis     r12, 0x5845
    ori     r12, r12, 0x5832
    cmpw    r7, r12
    bne     identity_failure

    lwz     r8, 0x08(r6)     # total XEX header size
    cmplwi  r8, 0x190
    blt     identity_failure
    lwz     r9, 0x14(r6)     # optional header count
    cmpwi   r9, 0
    beq     identity_failure
    cmplwi  r9, 0x100
    bgt     identity_failure
    addi    r10, r6, 0x18

identity_header_loop:
    lwz     r11, 0(r10)
    lis     r12, 0x0004
    ori     r12, r12, 0x0006
    cmpw    r11, r12
    beq     identity_execution_found
    addi    r10, r10, 8
    addi    r9, r9, -1
    cmpwi   r9, 0
    bne     identity_header_loop
    b       identity_failure

identity_execution_found:
    lwz     r11, 4(r10)
    cmplw   r11, r8
    bge     identity_failure
    addi    r12, r11, XEX_EXECUTION_INFO_SIZE
    cmplw   r12, r8
    bgt     identity_failure
    add     r10, r6, r11

    lwz     r12, 0x0c(r10)   # execution-info title id
    cmpw    r12, r3
    bne     identity_failure

    stw     r12, 0x00(r4)
    lwz     r12, 0x00(r10)
    stw     r12, 0x04(r4)    # media id
    lwz     r12, 0x04(r10)
    stw     r12, 0x08(r4)    # version
    lwz     r12, 0x08(r10)
    stw     r12, 0x0c(r4)    # base version

    lwz     r9, 0x10(r6)     # security-info offset
    cmplw   r9, r8
    bge     identity_failure
    addi    r10, r9, XEX_SECURITY_DIGEST_END
    cmplw   r10, r8
    bgt     identity_failure
    add     r10, r6, r9
    addi    r10, r10, XEX_SECURITY_HEADER_DIGEST

    lwz     r12, 0x00(r10)
    stw     r12, 0x10(r4)
    lwz     r12, 0x04(r10)
    stw     r12, 0x14(r4)
    lwz     r12, 0x08(r10)
    stw     r12, 0x18(r4)
    lwz     r12, 0x0c(r10)
    stw     r12, 0x1c(r4)
    lwz     r12, 0x10(r10)
    stw     r12, 0x20(r4)

    li      r3, 1
    stw     r3, 0x24(r4)
    blr

identity_failure:
    li      r3, 0
    blr

# IN: r3 = first identity, r4 = second identity
# OUT: r3 = 1 only when both valid identities match all key bytes
identities_equal:
    lwz     r5, 0x24(r3)
    cmpwi   r5, 1
    bne     identities_not_equal
    lwz     r5, 0x24(r4)
    cmpwi   r5, 1
    bne     identities_not_equal
    li      r5, 9
    mtctr   r5

identities_compare_loop:
    lwz     r6, 0(r3)
    lwz     r7, 0(r4)
    cmpw    r6, r7
    bne     identities_not_equal
    addi    r3, r3, 4
    addi    r4, r4, 4
    bdnz    identities_compare_loop
    li      r3, 1
    blr

identities_not_equal:
    li      r3, 0
    blr

# Exact registry key: title/media/version/base-version/header-digest.
# The shipped registry count is zero, therefore all titles return no match.
find_exact_profile:
    lis     r4, profile_registry_count@ha
    addi    r4, r4, profile_registry_count@l
    lwz     r4, 0(r4)
    cmpwi   r4, 0
    beq     profile_not_found
    lis     r5, profile_registry@ha
    addi    r5, r5, profile_registry@l

profile_outer_loop:
    mr      r9, r3
    mr      r10, r5
    li      r6, 9             # four IDs plus five digest DWORDs
    mtctr   r6

profile_compare_loop:
    lwz     r7, 0(r9)
    lwz     r8, 0(r10)
    cmpw    r7, r8
    bne     profile_next
    addi    r9, r9, 4
    addi    r10, r10, 4
    bdnz    profile_compare_loop
    mr      r3, r5
    blr

profile_next:
    addi    r5, r5, XP_PROFILE_SIZE
    addi    r4, r4, -1
    cmpwi   r4, 0
    bne     profile_outer_loop

profile_not_found:
    li      r3, 0
    blr

# Profile handlers are deliberately absent in this build. Future handlers must
# validate expected original bytes and provide the paired revert routine.
apply_title_profile:
    mflr    r0
    stwu    r1, -0x40(r1)
    stw     r0, 0x08(r1)
    lwz     r12, XP_PROFILE_APPLY_OFFSET(r3)
    cmpwi   r12, 0
    beq     profile_apply_blocked
    mr      r5, r3
    mr      r3, r4
    mr      r4, r5
    mtctr   r12
    bctrl
    b       profile_apply_return

profile_apply_blocked:
    li      r3, 0

profile_apply_return:
    lwz     r0, 0x08(r1)
    addi    r1, r1, 0x40
    mtlr    r0
    blr

revert_title_profile:
    mflr    r0
    stwu    r1, -0x40(r1)
    stw     r0, 0x08(r1)
    lwz     r12, XP_PROFILE_REVERT_OFFSET(r3)
    cmpwi   r12, 0
    beq     profile_revert_done
    mr      r5, r3
    mr      r3, r4
    mr      r4, r5
    mtctr   r12
    bctrl

profile_revert_done:
    lwz     r0, 0x08(r1)
    addi    r1, r1, 0x40
    mtlr    r0
    blr

# Read a 32-bit little-endian PE field from xboxkrnl's in-memory image.
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

# Resolve an xboxkrnl export by ordinal without importing an SDK library.
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

.align 2
xam_module_name:
    .asciz  "xam.xex"

.align 2
profile_registry_count:
    .long   0
profile_registry:
    # Intentionally empty. Unknown titles are always a no-op in Stage B.
profile_registry_end:
