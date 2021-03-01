// Openings - central management of prefabs openings
// Copyleft 2020-2021 Typhaine Artez
//
// Based on:
// http://wiki.secondlife.com/wiki/One_Script,_many_doors
// YADS: https://github.com/uriesk/Door-Script-YASM
//
// This program is free software: you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// version 3 as published my the Free Software Foundation:
// http://www.gnu.org/licenses/gpl.html
//
// ****************************************************************
// ****************************************************************
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// The part about hinged swining doors of this software was 
// originally written by KyleFlynn Resident. 
// Mr. Flynn can be reached at kyleflynnresident@gmail.com.
// However, I don't often check that email. You'd do better
// to catch me online, which I often am.
// ****************************************************************
// ****************************************************************

////////////////////////////////////////////////////////////////////////////////////////////////////

integer all_locked;         // touch/collide have no effect if TRUE
list still_opened;          // list of opened items that will be auto closed: [link, type, unixtime]
integer altered_opened;     // list has been altered by a manual closing
integer use_acls;           // TRUE=without config owner only, FALSE=everyone

// settings of currently processed opening
key cur_user;           // who touched/collided
integer cur_link;       // link number
string cur_type;        // type (SLIDE, ROTATE, HINGE)
string cur_group;       // group the opening belongs to
string cur_pair;        // sync with other openings of the group: EXCL, SYNC
integer cur_opened;     // is opened (0/1)
integer cur_phantom;    // does phantom on opening?
string cur_axis;        // sliding/rotation axis (X/Y/Z)
integer cur_dir;        // direction (-1/1)
integer cur_autoclose;  // time in seconds after the opening is automatically closed
integer cur_units;      // percentrage of sliding, angle for rotation
list cur_others;        // list of other links in the same group

vector cur_cpos;        // closed local position
rotation cur_crot;      // closed local rotation
integer cur_cshape;     // closed prim shape type

// ACLs
list acls;      // authorization list (first item is mode ("O"=owner, "G"=group, "A"=all)
                // followed by pairs of items: "A" for allow, "D" for deny, then the access definition
key nckey;      // .access notecard (for automatic reload on notecard change)
integer ncline; // parse notecard

////////////////////////////////////////////////////////////////////////////////////////////////////
// Load Access Control List from notecard
// Returns TRUE if some data need to be read
integer reloadACLs(string data) {
    if (EOF == data) {
        llOwnerSay("Authorizations loaded.");
        return FALSE;
    }
    if ("--START--" == data) {
        nckey = llGetInventoryKey(".access");
        if (NULL_KEY != nckey) {
            acls = ["O"]; // by default, owner only
            ncline = 0;
            llGetNotecardLine(".access", ncline);
            return TRUE;
        }
        // no ACLs used
        acls = ["A"];   // by default, everyone
        return FALSE;
    }
    if ("" != data && 0 != llSubStringIndex(data, "#")) {
        // read data
        integer sep = llSubStringIndex(data, "=");
        if (~sep) {
            string kw = llToLower(llStringTrim(llGetSubString(data, 0, sep-1), STRING_TRIM));
            string val = llToLower(llStringTrim(llGetSubString(data, sep+1, -1), STRING_TRIM));
            if ("mode" == kw) {
                if ("all" == val) val = "A";
                else if ("group" == val) val = "G";
                else if ("owner" == val) val = "O";
                else val = "";
                if ("" != val) acls = llListReplaceList(acls, [val], 0, 0);
            }
            else if ("allow" == kw) acls += ["A", val];
            else if ("deny" == kw) acls += ["D", val];
            else llOwnerSay("Warning: unrecognized line: " + data);
        }
    }
    // read next line
    llGetNotecardLine(".access", ++ncline);
    return TRUE;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Returns TRUE if user key is allowed to operate
integer isAuthorized(key id) {
    if (llGetOwner() == id) return TRUE; // owner always allowed
    string mode = llList2String(acls, 0);
    string type;
    string auth;
    string name = llToLower(osReplaceString(osReplaceString(llKey2Name(id), " ?@.*$", "", 1, 0), "\\.", " ", -1, 0));
    integer pos;
    integer n = llGetListLength(acls) - 2;
    for (; 0 < n; n -= 2) {
        type = llList2String(acls, n);
        auth = llList2String(acls, n+1);
        // check agent key, the faster
        if (osIsUUID(auth) && id == (key)auth) return ("A" == type);
        // normalize name first last (all lower case, without grid suffix, no dots)
        auth = osReplaceString(osReplaceString(auth, " ?@.*$", "", 1, 0), "\\.", " ", -1, 0);
        if (-1 != ~llSubStringIndex(name, auth)) return ("A" == type);
    }
    // not matched, check mode
    if ("A" == mode || ("G" == mode && llSameGroup(id))) return TRUE;
    return FALSE; // owner only
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Returns TRUE is opening is correctly configured, and update current opening settings
integer getConfig(integer link) {
    list l = llParseString2List(llList2String(llGetLinkPrimitiveParams(link, [PRIM_DESC]), 0), [" "], []);
    integer count = llGetListLength(l);
    if (!count) return FALSE;
    string opened = llList2String(l, 0);
    if ("@0" != opened && "@1" != opened) return FALSE;

    string type = llList2String(l, 1);
    if (!~llListFindList(["SLIDE", "ROTATE", "HINGE"], [type])) return FALSE;

    // reset to good defaults
    cur_opened = (integer)llGetSubString(opened, 1, 1);
    cur_type = type;
    cur_link = link;
    cur_group = "";
    cur_pair = "";
    cur_phantom = FALSE;
    cur_axis = "Z";
    cur_dir = 1;
    cur_autoclose = 0;
    cur_units = 90;

    string prm;
    integer i;
    for (i = 1; i < count; ++i) {
        prm = llToUpper(llList2String(l, i));
        if ("PH" == prm) cur_phantom = TRUE;
        else if ("AC" == prm) cur_autoclose = (integer)llList2String(l, ++i);
        else if ("GRP" == prm) cur_group = llList2String(l, ++i);
        else if ("PAIR" == prm) cur_pair = llList2String(l, ++i);
        else if ("X" == prm || "Y" == prm || "Z" == prm) cur_axis = prm;
        else if ("CCW" == prm || "LEFT" == prm || "DOWN" == prm) cur_dir = 1;
        else if ("CW" == prm || "RIGHT" == prm || "UP" == prm) cur_dir = -1;
        else if ("%" == llGetSubString(prm, -1, -1)) cur_units = (integer)llGetSubString(prm, 0, -2);
    }
    return TRUE;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Update PRIM_TEXT and current config variables with new closed position/rotation/shape type
storeClosedState() {
    list pp = llGetLinkPrimitiveParams(cur_link, [PRIM_POS_LOCAL, PRIM_ROT_LOCAL, PRIM_PHYSICS_SHAPE_TYPE]);
    cur_cpos = llList2Vector(pp, 0);
    cur_crot = llList2Rot(pp, 1);
    cur_cshape = llList2Integer(pp, 2);
    llSetLinkPrimitiveParamsFast(cur_link, [
        PRIM_TEXT, llDumpList2String([cur_cpos,cur_crot,cur_cshape], ";"), <1,1,1>, 0.0
    ]);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Returns TRUE if closed state could be retrieved in current config variables
integer getClosedState() {
    list l = llParseString2List(llList2String(llGetLinkPrimitiveParams(cur_link, [PRIM_TEXT]), 0), [";"], []);
    if ([] != l) {
        cur_cpos = (vector)llList2String(l, 0);
        cur_crot = (rotation)llList2String(l, 1);
        cur_cshape = (integer)llList2String(l, 2);
        return TRUE;
    }
    return FALSE;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Remove all PRIM_TEXT properties on the link set 
resetStoredStates() {
    list pp;
    integer c = llGetNumberOfPrims();
    for (; 1 < c; --c) {
        if (!llSubStringIndex(llList2String(llGetLinkPrimitiveParams(c, [PRIM_TEXT]), 0), "@")) {
            pp += [PRIM_LINK_TARGET, c, PRIM_TEXT, "", <1,1,1>, 0.0];
            if (PRIM_PHYSICS_SHAPE_NONE == llList2Integer(llGetLinkPrimitiveParams(c, [PRIM_PHYSICS_SHAPE_TYPE]), 0)) {
                pp += [PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_PRIM];
            }
        }
    }
    llSetLinkPrimitiveParamsFast(LINK_THIS, pp);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Update the first part of the description to reflect the inverted opened state
updateOpened() {
    cur_opened = 1 - cur_opened;
    list desc = llParseString2List(llList2String(llGetLinkPrimitiveParams(cur_link, [PRIM_DESC]), 0), [" "], []);
    llSetLinkPrimitiveParamsFast(cur_link, [PRIM_DESC,
        llDumpList2String(llListReplaceList(desc, ["@"+(string)cur_opened], 0, 0), " ")
    ]);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
integer exclusiveOpened(string group) {
    list l;
    string desc;
    integer n = llGetNumberOfPrims();
    for (; 1 < n; --n) {
        if (n != cur_link) {
            desc = llList2String(llGetLinkPrimitiveParams(n, [PRIM_DESC]), 0);
            if (-1 != llSubStringIndex(desc, "GRP "+group) && "@1" == llGetSubString(desc, 0, 1)) return TRUE;
        }
    }
    return FALSE;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
list getGroupLinks() {
    if ("" == cur_group) return [];

    list l;
    string desc;
    integer n = llGetNumberOfPrims();
    for (; 1 < n; --n) {
        if (n != cur_link) {
            desc = llList2String(llGetLinkPrimitiveParams(n, [PRIM_DESC]), 0);
            if (~llSubStringIndex(desc, "GRP "+cur_group)) l += n;
        }
    }
    return l;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Open or close on needed
triggerOpening(integer forceTo, integer doPaired) {
    if (forceTo == cur_opened) return;
    if (cur_opened) {
        // currently opened, let's close it, inverting direction
        cur_dir *= -1;
        // also remove from the still opened list
        integer index = llListFindList(still_opened, [cur_link, cur_type]);
        if (~index) {
            still_opened = llDeleteSubList(still_opened, index, index+2);
            if ([] != still_opened) altered_opened = TRUE;
            else llSetTimerEvent(0.0);
        }
        // if the opening was not correctly initialized, inform the owner
        if (!getClosedState()) {
            llOwnerSay("link #"+(string)cur_link+" ("+llGetLinkName(cur_link)+") "
            + "was not correctly initialized. Please correct the position in closed state "
            + "and set at the beginning of the description of the link @0 instead of @1");
            return;
        }
    }
    else {
        // first check if this opening is not manually exclusive with another from the same group
        if ("" != cur_group && "EXCL" == cur_pair) {
            if (exclusiveOpened(cur_group)) {
                if (NULL_KEY != cur_user) llRegionSayTo(cur_user, 0,
                    "Cannot open, exclusive with another opened in group "+cur_group);
                return;
            }
        }
        // when the door is closed, we store the closed post/rot/shape type
        storeClosedState();
        // set it phantom if asked
        if (cur_phantom) llSetLinkPrimitiveParamsFast(cur_link, [PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_NONE]);
        // record this opened state and set the timer even if autoclose
        still_opened += [cur_link, cur_type];
        if (cur_autoclose) still_opened += llGetUnixTime();
        else still_opened += 0; // says not autoclosing
        // if first item, start the timer
        if (3 == llGetListLength(still_opened) && 0 != cur_autoclose) llSetTimerEvent(1.0);
    }
    if ("SLIDE" == cur_type) slideOpening(cur_opened);
    else if ("ROTATE" == cur_type) rotateOpening(cur_opened);
    else if ("HINGE" == cur_type) hingeOpening(cur_opened);
    updateOpened();
    if (doPaired && "SYNC" == cur_pair) {
        list paired = getGroupLinks();
        integer n = llGetListLength(paired);
        while (~(--n)) {
            if (getConfig(llList2Integer(paired, n))) triggerOpening(forceTo, FALSE);
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Do the slide move
slideOpening(integer was_opened) {
    list pp;
    playSound("slide", cur_cpos);
    if (was_opened) {
        // restore to closed state
        pp = [PRIM_POS_LOCAL, cur_cpos, PRIM_PHYSICS_SHAPE_TYPE, cur_cshape];
    }
    else {
        vector size = llList2Vector(llGetLinkPrimitiveParams(cur_link, [PRIM_SIZE]), 0);
        vector newpos;
        float width;
        if ("X" == cur_axis) { newpos.x = 1.0; width = size.x; }
        else if ("Y" == cur_axis) { newpos.y = 1.0; width = size.y; }
        else if ("Z" == cur_axis) { newpos.z = 1.0; width = size.z; }
        newpos = cur_cpos + (newpos * cur_units * width / 100.0 * cur_dir) * cur_crot;
        pp = [PRIM_POS_LOCAL, newpos];
        if (cur_phantom) pp += [PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_NONE];
    }
    llSetLinkPrimitiveParamsFast(cur_link, pp);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Do the rotation move
rotateOpening(integer was_opened) {
    list pp;
    if (was_opened) {
        // restore to closed state
        playSound("open", cur_cpos);
        pp = [PRIM_ROT_LOCAL, cur_crot, PRIM_PHYSICS_SHAPE_TYPE, cur_cshape];
    }
    else {
        playSound("close", cur_cpos);
        rotation rot = llList2Rot(llGetLinkPrimitiveParams(cur_link, [PRIM_ROT_LOCAL]), 0);
        vector axes = ZERO_VECTOR;
        if ("X" == cur_axis) axes.x = 1.0;
        else if ("Y" == cur_axis) axes.y = 1.0;
        else if ("Z" == cur_axis) axes.z = 1.0;
        rotation newrot = llEuler2Rot(axes * cur_units * cur_dir * DEG_TO_RAD) * rot;
        pp = [PRIM_ROT_LOCAL, newrot];
        if (cur_phantom) pp += [PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_NONE];
    }
    llSetLinkPrimitiveParamsFast(cur_link, pp);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Do the rotation with hinge
hingeOpening(integer was_opened) {
    list pp;
    if (was_opened) {
        // restore to closed state
        playSound("close", cur_cpos);
        pp = [PRIM_POS_LOCAL, cur_cpos, PRIM_ROT_LOCAL, cur_crot, PRIM_PHYSICS_SHAPE_TYPE, cur_cshape];
    }
    else {
        playSound("open", cur_cpos);
        vector size = llList2Vector(llGetLinkPrimitiveParams(cur_link, [PRIM_SIZE]), 0);
        vector vrot = ZERO_VECTOR;
        vector axes = ZERO_VECTOR;
        if ("X" == cur_axis) {
            axes.x = 1.0;
            if (size.y > size.z) vrot.y = size.y / 2;
            else vrot.z = size.z / 2;
        }
        else if ("Y" == cur_axis) {
            axes.y = 1.0;
            if (size.x > size.z) vrot.x = size.x / 2;
            else vrot.z = size.z / 2;
        }
        else if ("Z" == cur_axis) {
            axes.z = 1.0;
            if (size.x > size.y) vrot.x = size.x / 2;
            else vrot.y = size.y / 2;
        }
        vector hinge = cur_cpos - vrot * cur_crot;
        rotation orbit = llEuler2Rot(axes * cur_units * DEG_TO_RAD * cur_dir);
        vector radius = vrot * orbit * cur_crot;
        vector newpos = hinge + radius;
        rotation newrot = orbit * cur_crot;
        pp = [PRIM_POS_LOCAL, newpos, PRIM_ROT_LOCAL, newrot];
        if (cur_phantom) pp += [PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_NONE];
    }
    llSetLinkPrimitiveParamsFast(cur_link, pp);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Check to close opened items with autoclose
processAutoclose() {
@redo_opened;
    integer n = llGetListLength(still_opened) - 3;
    for (; -1 < n; n -= 3) {
        if (altered_opened) {
            altered_opened = FALSE;
            jump redo_opened;
        }
        if (getConfig(llList2Integer(still_opened, n))) {
            // chech remaining time
            integer at = llList2Integer(still_opened, n+2);
            if (0 != at && llGetUnixTime() - at > cur_autoclose) triggerOpening(0, FALSE);
        }
        else {
            // could not get the config, we wont be able to autoclose, se delete this entry
            still_opened = llDeleteSubList(still_opened, n, -1);
        }
    }
}

/*
////////////////////////////////////////////////////////////////////////////////////////////////////
//This functions is from Nomad Padar, pretty awesome!
//encode from vector to integer
integer vec2int(vector v) {
    integer x = (integer)(v.x);
    integer y = (integer)(v.y);
    integer z = (integer)(v.z);
    integer out;
 
    //Rounds to 0, .5, or 1.0
    float delta = v.x - x;
    if ((delta > .25) && (delta < .75)) out += 0x10000000;
    else if (delta > .75) out += 0x1;
 
    delta = v.y - y;
    if ((delta > .25) && (delta < .75)) out += 0x20000000;
    else if (delta > .75) out += 0x100;
 
    delta = v.z - z;
    if ((delta > .25) && (delta < .75)) out += 0x40000000;
    else if (delta > .75) out += 0x10000;
 
    return out + x + (y << 8) + (z << 16);
}
*/
////////////////////////////////////////////////////////////////////////////////////////////////////
playSound(string snd, vector pos) {
//    llRezObject(snd, llGetPos(), ZERO_VECTOR, ZERO_ROTATION, vec2int(pos));
}

////////////////////////////////////////////////////////////////////////////////////////////////////

default {
    //----------------------------------------------------------------------------------------------
    changed(integer c) {
        if (CHANGED_OWNER & c) llResetScript();
        if ((CHANGED_INVENTORY & c) && (llGetInventoryKey(".access") != nckey)) reloadACLs("--START--");
    }
    //----------------------------------------------------------------------------------------------
    state_entry() {
        reloadACLs("--START--");
        resetStoredStates();
    }
    //----------------------------------------------------------------------------------------------
    link_message(integer sender, integer num, string str, key id) {
        if (1 != num) return; // 1 is for openings
        if (all_locked && "unlock" != str) return;
        if ("collide" == str) {
            // a link reports a collision
            if (!isAuthorized(id) || !getConfig(sender)) return;
            triggerOpening(1, TRUE);
        }
        else if ("touched" == str) {
            // a link reports a touch
            if (!isAuthorized(id) || !getConfig(sender)) return;
            triggerOpening(-1, TRUE);
        }
        else if ("toggle" == str) {
            num = (integer)id;
            if (1 < num && getConfig(num)) triggerOpening(-1, TRUE);
        }
        else if ("open" == str) {
            num = (integer)id;
            if (1 < num) {
                if (getConfig(num)) triggerOpening(1, TRUE);
            }
        }
        else if ("close" == str) {
            num = (integer)id;  // link number
            if (1 < num) {
                if (getConfig(num)) triggerOpening(0, TRUE);
            }
        }
        else if ("lock" == str) {
            all_locked = TRUE;
        }
        else if ("unlock" == str) {
            all_locked = FALSE;
        }
    }
    //----------------------------------------------------------------------------------------------
    timer() {
        // timer runs once a second as long as there are opened items
        if ([] == still_opened) llSetTimerEvent(0.0);
        else processAutoclose();
    }
    //----------------------------------------------------------------------------------------------
    dataserver(key id, string data) {
        reloadACLs(data);
    }
}
