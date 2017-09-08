#!/usr/bin/wish8.6

source "irken.tcl"

set ::tests {}

proc test {name fixtures code} {
    proc test_$name {} $code
    lappend ::tests [list test_$name $fixtures]
}

proc assert {condition} {
    if {![uplevel 1 [list expr $condition]]} {
        return -code error "Assertion failed: $condition"
    }
}

proc asserteq {a b} {
    if {$a != $b} {
        return -code error "Assertion failed:\n[list $a] !=\n[list $b]"
    }
}

proc runtests {} {
    set testcount 0
    set passcount 0
    set failcount 0
    foreach test $::tests {
        lassign $test cmd fixtures
        foreach fixture $fixtures {
            try {
                {*}$fixture setup
            } on error {err} {
                puts stderr "Fixture failure in $fixture: $::errorInfo"
                exit 1
            }
        }
        try {
            incr testcount
            {*}$cmd
        } on error {err} {
            incr failcount
            puts stderr "Test failure in $cmd: $::errorInfo"
        } finally {
            foreach fixture [lreverse $fixtures] {
                {*}$fixture teardown
            }
        }
    }
    puts stdout "$testcount tests run, $failcount failed."
    exit 0
}

proc irken_fixture {op} {
    if {$op eq "setup"} {
        initvars
        initui
        # TODO: set up a server connection with a pipe
        dict set ::serverinfo "TestServer" [dict create fd 0 nick "test"]
        ensurechan "TestServer" "" {}
        ensurechan "TestServer" "#test" {}
        set ::active [chanid "TestServer" "#test"]
        return
    }
    destroy {*}[winfo children .]
}

test irctolower {} {
    asserteq [irctolower "FOO"] "foo"
    asserteq [irctolower "FOO\[\]"] "foo\{\}"
}

test ircstrcmp {} {
    assert {[ircstrcmp "foo" "foo"] == 0}
    assert {[ircstrcmp "foo\[\]" "foo\[\]"] == 0}
    assert {[ircstrcmp "foo\[\]" "foo\{\}"] == 0}
}

test colorcode {} {
    asserteq [colorcode "normal text"] [list "normal text" {}]
    asserteq [colorcode "\x02normal \x02text"] [list "normal text" {{0 push bold} {7 pop bold}}]
    asserteq [colorcode "\x1dnormal \x1dtext"] [list "normal text" {{0 push italic} {7 pop italic}}]
    asserteq [colorcode "\x1fnormal \x1ftext"] [list "normal text" {{0 push underline} {7 pop underline}}]
    asserteq [colorcode "\x034rainbow \x03text"] [list "rainbow text" {{0 push fg_red} {8 pop fg_red}}]
    asserteq [colorcode "\x034,5rainbow \x034,text"] [list "rainbow text" {{0 push fg_red} {0 push bg_maroon} {8 pop bg_maroon}}]
    asserteq [colorcode "\x034,5rainbow \x03,text"] [list "rainbow text" {{0 push fg_red} {0 push bg_maroon} {8 pop fg_red} {8 pop bg_maroon}}]
    # sometimes colors are sent with leading zeros :(
    asserteq [colorcode "\x0304rainbow \x03text"] [list "rainbow text" {{0 push fg_red} {8 pop fg_red}}]
    asserteq [colorcode "\x02bold\x02 normal \x02\x1dbold italic\x02 italic \x02bold italic\x1d bold"] \
        [list "bold normal bold italic italic bold italic bold" \
             {{0 push bold} {4 pop bold} {12 push bold} {12 pop bold} {12 push bolditalic} {23 pop bolditalic} {23 push italic} {31 pop italic} {31 push bolditalic} {42 pop bolditalic} {42 push bold}}]
    asserteq [colorcode "\x02\x1dbold italic\x0f normal"] [list "bold italic normal" {{0 push bold} {0 pop bold} {0 push bolditalic} {11 pop bolditalic}}]
    asserteq [colorcode "\x16reversed\x16 normal"] [list "reversed normal" {{0 push fg_white} {0 push bg_black} {8 pop fg_white} {8 pop bg_black}}]
    asserteq [colorcode "\x16rev\x034,5-ersed\x16 col\x03or"] [list "rev-ersed color" {{0 push fg_white} {0 push bg_black} {3 pop fg_white} {3 push fg_maroon} {3 pop bg_black} {3 push bg_red} {9 pop fg_maroon} {9 push fg_red} {9 pop bg_red} {9 push bg_maroon} {13 pop fg_red} {13 pop bg_maroon}}]
}

test regexranges {} {
    asserteq [regexranges "testing text" te te] {{0 push te} {2 pop te} {8 push te} {10 pop te}}
    asserteq [regexranges "x https://example.com/ x" {https?://[-a-zA-Z0-9@:%_/\+.~#?&=]+} hlink] {{2 push hlink} {22 pop hlink}}
}

test combinestyles {} {
    asserteq [combinestyles "rainbow text" {{0 push te} {2 pop te} {8 push te} {10 pop te} {4 push ing} {7 pop ing}}] \
        [list "ra" te "in" {} "bow" ing " " {} "te" te "xt" {}]
}

test addchantext {irken_fixture} {
    addchantext "TestServer/#test" "tester" "This is a test."
    asserteq [lrange [dict get $::channeltext "TestServer/#test"] 2 end] [list "\ttester\t" "nick" "This is a test." {}]

}

test addchanuser {irken_fixture} {
    addchanuser "TestServer/#test" "test\[user\]" {}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "test\[user\]" {}]]
    assert {[.users exists "test\[user\]"]}

    addchanuser "TestServer/#test" "@test\[user\]" {}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "test\[user\]" {ops}]]
    assert {[.users exists "test\[user\]"]}
    assert {[.users tag has ops "test\[user\]"]}
}

test remchanuser {irken_fixture} {
    addchanuser "TestServer/#test" "testuser" {}
    assert {[.users exists "testuser"]}
    remchanuser "TestServer/#test" "testuser"
    assert {![.users exists "testuser"]}
}

if {[info exists argv0] && [file dirname [file normalize [info script]/...]] eq [file dirname [file normalize $argv0/...]]} {
    runtests
}
