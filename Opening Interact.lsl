default {
    collision_start(integer n) { llMessageLinked(LINK_ALL_OTHERS, 1, "collide", llDetectedKey(0)); }
    touch_start(integer n) { llMessageLinked(LINK_ALL_OTHERS, 1, "touched", llDetectedKey(0)); }
}
