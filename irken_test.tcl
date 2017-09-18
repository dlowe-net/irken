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
            puts stdout "$cmd..."
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

proc testserver {fd addr port} {
    fconfigure $fd -blocking 0
    dict set ::serverinfo "TestServer" sfd $fd
}

proc irken_fixture {op} {
    if {$op eq "setup"} {
        initvars
        initui
        set ::serverfd [socket -server testserver -myaddr "localhost" 0]
        set fd [socket "localhost" [lindex [fconfigure $::serverfd -sockname] 2]]
        dict set ::serverinfo "TestServer" [dict merge [dict create fd $fd nick "test" casemapping "rfc1459"] $::ircdefaults]
        fconfigure $fd -blocking 0
        vwait ::serverinfo
        ensurechan "TestServer" "" {}
        ensurechan "TestServer" "#test" {}
        ensurechan "TestServer" "target" {}
        set ::active {}
        .nav selection set [chanid "TestServer" "#test"]
        selectchan
        return
    }
    close [dict get $::serverinfo "TestServer" sfd]
    close [dict get $::serverinfo "TestServer" fd]
    close $::serverfd
    destroy {*}[lsearch -all -inline -not -exact [winfo children .] ".#BWidget"]
}

test irctolower {} {
    asserteq [irctolower "ascii" "FOO"] "foo"
    asserteq [irctolower "rfc1459" "FOO"] "foo"
    asserteq [irctolower "strict-rfc1459" "FOO"] "foo"
    asserteq [irctolower "ascii" "FOO\[\]^"] "foo\[\]^"
    asserteq [irctolower "rfc1459" "FOO\[\]^"] "foo\{\}~"
    asserteq [irctolower "strict-rfc1459" "FOO\[\]^"] "foo\{\}^"
}

test ircstrcmp {} {
    assert {[ircstrcmp "ascii" "foo\[\]^" "foo\[\]^"] == 0}
    assert {[ircstrcmp "ascii" "foo\[\]^" "foo\{\}~"] != 0}
    assert {[ircstrcmp "rfc1459" "foo\[\]" "foo\{\}"] == 0}
    assert {[ircstrcmp "strict-rfc1459" "foo\[\]" "foo\{\}"] == 0}
    assert {[ircstrcmp "rfc1459" "foo\[\]^" "foo\{\}~"] == 0}
    assert {[ircstrcmp "strict-rfc1459" "foo\[\]^" "foo\{\}~"] != 0}
}

test rankeduser {} {
    dict set ::serverinfo "TestServer" prefix {@ o + v}
    asserteq [rankeduser "TestServer" [list foo [list o v]]] "0foo"
    asserteq [rankeduser "TestServer" [list foo [list v]]] "1foo"
    asserteq [rankeduser "TestServer" [list foo {}]] "2foo"
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

test ischannel {} {
    set ::serverinfo [dict create "TestServer" $::ircdefaults]
    assert {[ischannel [chanid "TestServer" "#foo"]]}
    assert {[ischannel [chanid "TestServer" "#"]]}
    assert {[ischannel [chanid "TestServer" "&foo"]]}
    assert {![ischannel [chanid "TestServer" "foo"]]}
    assert {![ischannel [chanid "TestServer" "# foo"]]}
    assert {![ischannel [chanid "TestServer" "#\afoo"]]}
    dict set ::serverinfo "TestServer" channellen 2
    assert {[ischannel [chanid "TestServer" "#fo"]]}
    assert {![ischannel [chanid "TestServer" "#foo"]]}
    dict set ::serverinfo "TestServer" chantypes #
    assert {![ischannel [chanid "TestServer" "&fo"]]}
}

test addchantext {irken_fixture} {
    addchantext "TestServer/#test" "This is a test." -nick "tester" -tags self
    asserteq [lrange [dict get $::channeltext "TestServer/#test"] 2 end] [list "\ttester\t" "nick" "This is a test." {self line}]
}

test addchanuser {irken_fixture} {
    addchanuser "TestServer/#test" "test\[user\]" {}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "test\[user\]" {}]]
    assert {[.users exists "test\[user\]"]}

    addchanuser "TestServer/#test" "@test\[user\]" {}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "test\[user\]" {o}]]
    assert {[.users exists "test\[user\]"]}
    assert {[.users tag has o "test\[user\]"]}
}

test remchanuser {irken_fixture} {
    addchanuser "TestServer/#test" "testuser" {}
    assert {[.users exists "testuser"]}
    remchanuser "TestServer/#test" "testuser"
    assert {![.users exists "testuser"]}
}

test removechan {irken_fixture} {
    assert {[dict exists $::channeltext "TestServer/#test"]}
    assert {[dict exists $::channelinfo "TestServer/#test"]}
    asserteq [.nav focus] "TestServer/#test"
    removechan "TestServer/#test"
    assert {![dict exists $::channeltext "TestServer/#test"]}
    assert {![dict exists $::channelinfo "TestServer/#test"]}
    assert {![.nav exists "TestServer/#test"]}
    asserteq [.nav selection] "TestServer/target"
    asserteq [.nav focus] "TestServer/target"
    asserteq $::active "TestServer/target"
}

test closecmd {irken_fixture} {
    .cmd configure -validate none
    .cmd insert 0 "/close #test"
    .cmd configure -validate key
    returnkey
    asserteq [gets [dict get $::serverinfo "TestServer" sfd]] "PART #test :"
    assert {![.nav exists "TestServer/#test"]}
    asserteq [.nav selection] "TestServer/target"
    asserteq [.nav focus] "TestServer/target"
    asserteq $::active "TestServer/target"
    assert {![dict exists $::channeltext "TestServer/#test"]}
    assert {![dict exists $::channelinfo "TestServer/#test"]}
}

test closecmdwithuser {irken_fixture} {
    .nav selection set [chanid "TestServer" "target"]
    selectchan
    .cmd configure -validate none
    .cmd insert 0 "/close target"
    .cmd configure -validate key
    returnkey
    assert {![.nav exists "TestServer/target"]}
    asserteq [.nav selection] "TestServer/#test"
    asserteq [.nav focus] "TestServer/#test"
    asserteq $::active "TestServer/#test"
    assert {![dict exists $::channeltext "TestServer/target"]}
    assert {![dict exists $::channelinfo "TestServer/target"]}
}

test handleMODE {irken_fixture} {
    addchanuser [chanid "TestServer" "#test"] "@target" {}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "target" {o}]]
    hook call handleMODE "TestServer" [dict create src "foo" user "foo" host "foo.com" cmd "MODE" args [list "#test" -o target] trailing ""]
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "target" {}]]
    assert {[.users exists "target"]}
    assert {![.users tag has o "target"]}
    hook call handleMODE "TestServer" [dict create src "foo" user "foo" host "foo.com" cmd "MODE" args [list "#test" +o target] trailing ""]
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "target" {o}]]
    hook call handleMODE "TestServer" [dict create src "foo" user "foo" host "foo.com" cmd "MODE" args [list "#test" +v target] trailing ""]
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "target" {o v}]]
}

if {[info exists argv0] && [file dirname [file normalize [info script]/...]] eq [file dirname [file normalize $argv0/...]]} {
    runtests
}
