#include <assert.h>
#include <stdio.h>
#include "../src/xp_optimizer.h"

static XpTelemetry base_game(void)
{
    XpTelemetry t = {0};
    t.title_id = 0x12345678u;
    t.is_game = true;
    t.total_physical_bytes = 512u * 1024u * 1024u;
    t.free_physical_bytes = 128u * 1024u * 1024u;
    t.cpu_temp_c = 58.0f;
    t.gpu_temp_c = 56.0f;
    t.edram_temp_c = 51.0f;
    t.board_temp_c = 40.0f;
    t.frame_time_avg_ms = 16.7f;
    t.frame_time_p95_ms = 17.5f;
    t.frame_time_jitter_ms = 1.0f;
    return t;
}

int main(void)
{
    XpTelemetry t = base_game();
    XpOptimizationPlan p = xp_optimizer_plan(&t);
    assert(p.profile == XP_PROFILE_PERFORMANCE);
    assert(p.hardware_writes_enabled == false);

    t.free_physical_bytes = 32u * 1024u * 1024u;
    p = xp_optimizer_plan(&t);
    assert(p.profile == XP_PROFILE_MEMORY_PRESSURE);
    assert((p.proposed_actions & XP_ACTION_MEMORY_RECLAIM) != 0);
    assert(p.hardware_writes_enabled == false);

    t = base_game();
    t.cpu_temp_c = 80.0f;
    p = xp_optimizer_plan(&t);
    assert(p.profile == XP_PROFILE_THERMAL_GUARD);
    assert(p.proposed_actions == XP_ACTION_THERMAL_GUARD);
    assert(p.hardware_writes_enabled == false);

    t = base_game();
    t.frame_time_p95_ms = 28.0f;
    p = xp_optimizer_plan(&t);
    assert(p.profile == XP_PROFILE_BALANCED);
    assert((p.proposed_actions & XP_ACTION_FRAME_PACING) != 0);
    assert(p.hardware_writes_enabled == false);

    t = base_game();
    t.is_game = false;
    p = xp_optimizer_plan(&t);
    assert(p.profile == XP_PROFILE_IDLE);
    assert(p.proposed_actions == XP_ACTION_NONE);

    p = xp_optimizer_plan(NULL);
    assert(p.profile == XP_PROFILE_SAFE);
    assert(p.hardware_writes_enabled == false);

    puts("XPOPT1 PASS: optimizer policy gates validated; hardware writes remain disabled");
    return 0;
}
