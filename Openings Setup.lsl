// Openings Setup - setup menu for Openings
// Copyleft 2020-2021 Typhaine Artez
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
// ****************************************************************
// ****************************************************************

key OWNER;

integer menu_chan;  // dialog listener
string menu_step;   // which page (SELECT, INFO, COPY, TYPE, GROUP, AXIS, DIR, AUTOCLOSE, PAIRING, ACTIONS)

// current link settings
integer cur_link;       // link number
integer cur_opened;     // is it opened?
string cur_type;        // type: SLIDE, ROTATE (pivot on side), HINGE (pivot on center)
string cur_group;       // group name
string cur_pair;        // pairing (EXCL - exclusive, SYNC - synchronized, REV - sync. reverted)
string cur_axis;        // local axis of rotation/translation (X, Y, Z)
integer cur_dir;        // direction (CW/CCW)
string cur_dirtxt;      // string version of cur_dir
integer cur_units;      // amount of move in % of size or degrees
integer cur_autoclose;  // number of seconds before autoclosing (0 to disable)
integer cur_phantom;    // is it set to phantom when opened


////////////////////////////////////////////////////////////////////////////////////////////////////
// Send a message to the main Opening script
send(integer num, string str, key id) {
    llMessageLinked(LINK_THIS, num, str, id);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Get the configuration of the link from its description
// Returns TRUE if config loaded corectly
integer getConfig() {
    // set good defaults
    cur_opened = FALSE;
    cur_type = "";
    cur_group = "";
    cur_pair = "";
    cur_axis = "Z";
    cur_dir = 1;
    cur_units = 90;
    cur_autoclose = 0;
    cur_phantom = FALSE;

    if (!cur_link) return FALSE;
    string desc = llToUpper(llList2String(llGetLinkPrimitiveParams(cur_link, [PRIM_DESC]), 0));
    list l = llParseString2List(desc, [" "], []);
    if ([] == l) return FALSE;

    // format: @{opened} type .... any other option
    string type = llList2String(l, 1);
    if (-1 == llListFindList(["SLIDE", "ROTATE", "HINGE"], [type])) return FALSE;
    cur_type = type;

    string opened = llList2String(l, 0);
    if (-1 == llListFindList(["@0", "@1"], [opened])) return FALSE;
    cur_opened = (integer)llGetSubString(opened, 1, 1);

    string prm;
    integer i;
    integer n = llGetListLength(l);
    for (i = 2; i < n; ++i) {
        prm = llList2String(l, i);
        if ("GRP" == prm) cur_group = llList2String(l, ++i);
        else if ("PAIR" == prm) cur_pair = llList2String(l, ++i);
        else if ("X" == prm || "Y" == prm || "Z" == prm) cur_axis = prm;
        else if ("-X" == prm || "-Y" == prm || "-Z" == prm) cur_axis = prm;
        else if ("CCW" == prm || "LEFT" == prm || "DOWN" == prm) { cur_dirtxt = prm; cur_dir = 1; }
        else if ("CW" == prm || "RIGHT" == prm || "UP" == prm) { cur_dirtxt = prm; cur_dir = -1; }
        else if ("AC" == prm) cur_autoclose = (integer)llList2String(l, ++i);
        else if ("PH" == prm) cur_phantom = TRUE;
        else if ("%" == llGetSubString(prm, -1, -1)) cur_units = (integer)llGetSubString(prm, 0, -2);
    }

    return TRUE;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Set the current configuration to the link description
setConfig() {
    if (cur_type == "") return;

    // with autoclose, the opening could be closed when it was opened, so check it
    list l = llParseString2List(llToUpper(llList2String(llGetLinkPrimitiveParams(cur_link, [PRIM_DESC]), 0)), [" "], []);
    string opened = llList2String(l, 0);
    if ("@" == llGetSubString(opened, 0, 0)) cur_opened = (integer)llGetSubString(opened, 1, 1);

    l = "@"+(string)cur_opened;
    l += cur_type;
    if ("" != cur_group) l += ["GRP", cur_group];
    if ("" != cur_pair) l += ["PAIR", cur_pair];
    l += cur_axis;
    if ("" != cur_dirtxt) l += cur_dirtxt;
    l += (string)cur_units+"%";
    if (cur_autoclose) l += ["AC", cur_autoclose];
    if (cur_phantom) l += "PH";
    llSetLinkPrimitiveParamsFast(cur_link, [PRIM_DESC, llDumpList2String(l, " ")]);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// converts a boolean to a string
string bool2str(integer b) {
    return llList2String(["false","true"], b);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Returns menu text for selection
string txtSelected() {
    string txt = "\nSelection: " + llGetLinkName(cur_link) + " (link "+(string)cur_link+")\n";
    if ("" != cur_type) txt = txt
        + "\nType: " + llList2String(["Slide", "Rotate", "Hinge"],
            llListFindList(["SLIDE","ROTATE","HINGE"], cur_type))
        + "\nGroup: " + cur_group
        + "\nPairing: " + llList2String(["None", "Exclusive", "Synchronized"],
                llListFindList(["", "EXCL", "SYNC"], [cur_pair]))
        + "\nAxis: " + cur_axis
        + "\nDirection: " + llList2String(["CW/Right/Up", "CCW/Left/Down"], (cur_dir > 0))
        + "\nUnits: " + (string)cur_units + llList2String(["°", "%"], (integer)(cur_type == "SLIDE"))
        + "\nAutoclose: " + llList2String(["disabled", (string)cur_autoclose+" seconds"], (cur_autoclose > 0))
        + "\nPhantom: " + bool2str(cur_phantom)
        + "\n[Test]: test open/close"
        + "\n[Actions]: open the actions menu (copy, test, etc...)"
        ;
    return txt + "\n";
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Show the menu
menu() {
    if (!menu_chan) {
        menu_chan = 0x80000000 | ((integer)("0x"+llGetSubString((string)OWNER, 0, 7))
            ^ ((integer)llFrand(0x7FFFFF80) + 1));
        llListen(menu_chan, "", OWNER, "");
    }

    string txt;
    list btns;

    if ("" == menu_step) {
        menu_step = "SELECT";
        txt = "Select the door/window you want to setup by touching it";
        btns = ["OK"];
        send(1, "lock", ""); // lock openings during selection
    }
    else if ("INFO" == menu_step) {
        txt = txtSelected();
        if ("" != cur_type) btns = [
            "Type", "Group", "Pairing",
            "Axis", "Direction", "Units",
            "Autoclose", "Phantom", "[Test]",
            "[Actions]", "[Copy]", "[Select]"
        ];
        else menu_step = "TYPE";
    }
    else if ("ACTIONS" == menu_step) {
        txt = "Select the action to perform";
        if ("" != cur_type) btns = [
            "Open", "Close", "Toggle",
            "Reset", " ", "[Back]"
        ];
    }
    if ("TYPE" == menu_step) {
        txt += "Select the type you want:"
            + "\nSlide: move on one axis"
            + "\nRorate: rotate on a pivot side"
            + "\nHinge: rotate from object center";
        btns = [
            "Slide", "Rotate", "Hinge",
            " ", " ", "[Cancel]"
        ];
    }
    else if ("GROUP" == menu_step) {
        txt = "\nSelect the group name\n(the group name will be forced to uppercase)";
    }
    else if ("PAIRING" == menu_step) {
        txt = "\nSelect how openings on the same group work together:"
            + "\nNone: openings of the same group are independent"
            + "\nExclusive: when one opens, others cannot move"
            + "\nSynchronized: all opens at the same time";
        btns = [
            "None", "Exclusive", "Synchronized",
            " ", " ", "[Cancel]"
        ];
    }
    else if ("AXIS" == menu_step) {
        txt += "Select the moving axis you want:\n"
            + "(axis is relative to prim local orientation)";
        btns = [
            "X", "Y", "Z",
            "-X", "-Y", "-Z",
            " ", " ", "[Cancel]"
        ];
    }
    else if ("DIR" == menu_step) {
        txt += "Select the direction you want:\n"
            + "(CCW/CW for rotation, Left/Down or Right/Up for sliding)";
        btns = [
            "Clockwise", "Counter CW", " ",
            "Right", "Left", " ",
            "Up", "Down", " ",
            " ", " ", "[Cancel]"
        ];
    }
    else if ("UNITS" == menu_step) {
        txt += "\nEnter the amount of move to do:\n"
            + "(in percent of object size for slide, in degrees for rotation)";
    }
    else if ("AUTOCLOSE" == menu_step) {
        txt = "\nEnter the time in seconds before closing (0 to disable)";
    }
    else if ("COPY" == menu_step) {
        txt = "\nSelect the link you want to copy the setup from by touching it";
        btns = ["OK"];
        send(1, "lock", "");
    }

    if ("" != txt) {
        if ([] == btns) llTextBox(OWNER, txt, menu_chan);
        else llDialog(OWNER, txt,
            llList2List(btns,9,11)+llList2List(btns,6,8)+llList2List(btns,3,5)+llList2List(btns,0,2),
            menu_chan);
    }
}

handle_touch(integer link, key id) {
    integer myLink = llGetLinkNumber();
    if (id != OWNER) return;
    if (myLink != link && !("SELECT" == menu_step || "COPY" == menu_step)) return;
    if ("SELECT" == menu_step) {
        send(1, "unlock", "");
        cur_link = link;
        getConfig();
        menu_step = "INFO";
    }
    else if ("COPY" == menu_step) {
        send(1, "unlock", "");
        // load config to copy and save it in new link
        integer saved = cur_link;
        cur_link = link;
        if (getConfig()) {
            cur_link = saved;
            setConfig();
        }
        else {
            cur_link = saved;
            getConfig();
        }
        menu_step = "INFO";
    }
    else {
        // start config
        menu_step = "";
        cur_link = 0;
        getConfig();
    }
    menu();
}

////////////////////////////////////////////////////////////////////////////////////////////////////

default {
    //----------------------------------------------------------------------------------------------
    changed(integer c) {
        if ((CHANGED_OWNER |CHANGED_REGION_RESTART) & c) llResetScript();
    }
    //----------------------------------------------------------------------------------------------
    state_entry() {
        OWNER = llGetOwner();
        send(1, "unlock", "");
    }
    //----------------------------------------------------------------------------------------------
    touch_start(integer n) {
        handle_touch(llDetectedLinkNumber(0), llDetectedKey(0));
    }
    //----------------------------------------------------------------------------------------------
    listen(integer c, string name, key id, string msg) {
        string new_step = "INFO";
        if ("[Cancel]" == msg) { if ("" == cur_type) new_step = "SELECT"; }
        else if (" " == msg || ("OK" == msg && "SELECT" == menu_step)) new_step = menu_step;
        else if ("INFO" == menu_step) {
            if ("Type" == msg) new_step = "TYPE";
            else if ("Group" == msg) new_step = "GROUP";
            else if ("Pairing" == msg) new_step = "PAIRING";
            else if ("Axis" == msg) new_step = "AXIS";
            else if ("Direction" == msg) new_step = "DIR";
            else if ("Units" == msg) new_step = "UNITS";
            else if ("Autoclose" == msg) new_step = "AUTOCLOSE";
            else if ("Phantom" == msg) { cur_phantom = 1 - cur_phantom; setConfig(); }
            else if ("[Test]" == msg) send(1, "toggle", (string)cur_link);
            else if ("[Actions]" == msg) new_step = "ACTIONS";
            else if ("[Select]" == msg) new_step = "";
            else if ("[Copy]" == msg) new_step = "COPY";
        }
        else if ("ACTIONS" == menu_step) {
            new_step = "ACTIONS";
            if ("Open" ==msg) send(1, "open", (string)cur_link);
            else if ("Close" == msg) send(1, "close", (string)cur_link);
            else if ("Toggle" == msg) send(1, "toggle", (string)cur_link);
            else if ("Reset" == msg) { llSetLinkPrimitiveParamsFast(cur_link, [PRIM_DESC, ""]); new_step = ""; }
            else if ("[Back]" == msg) new_step = "INFO";
        }
        else if ("TYPE" == menu_step) {
            getConfig();
            if ("Slide" == msg) cur_type = "SLIDE";
            else if ("Rotate" == msg) cur_type = "ROTATE";
            else if ("Hinge" == msg) cur_type = "HINGE";
            setConfig();
        }
        else if ("GROUP" == menu_step) {
            cur_group = llToUpper(msg);
            setConfig();
        }
        else if ("PAIRING" == menu_step) {
            if ("Exclusive" == msg) cur_pair = "EXCL";
            else if ("Synchronized" == msg) cur_pair = "SYNC";
            else if ("None" == msg) cur_pair = "";
            setConfig();
        }
        else if ("AXIS" == menu_step) {
            cur_axis = msg;
            setConfig();
        }
        else if ("DIR" == menu_step) {
            if ("Counter CW" == msg) { cur_dirtxt = "CCW"; cur_dir = 1; }
            else if ("Left" == msg) { cur_dirtxt = "LEFT"; cur_dir = 1; }
            else if ("Down" == msg) { cur_dirtxt = "DOWN"; cur_dir = 1; }
            else if ("Clockwise" == msg) { cur_dirtxt = "CW"; cur_dir = -1; }
            else if ("Right" == msg) { cur_dirtxt = "RIGHT"; cur_dir = -1; }
            else if ("Up" == msg) { cur_dirtxt = "UP"; cur_dir = -1; }
            setConfig();
        }
        else if ("UNITS" == menu_step) {
            cur_units = (integer)msg;
            setConfig();
        }
        else if ("AUTOCLOSE" == menu_step) {
            cur_autoclose = (integer)msg;
            setConfig();
        }
        menu_step = new_step;
        menu();
    }
    link_message(integer sender, integer num, string str, key id) {
        if ("touched" != str) return;
        handle_touch(sender, id);
   }
}