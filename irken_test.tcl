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
        return -code error "Assertion failed: [list $a] != [list $b]"
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
                puts stderr "Fixture failure in $fixture: $err"
                exit 1
            }
        }
        try {
            incr testcount
            {*}$cmd
        } on error {err} {
            incr failcount
            puts stderr "Test failure in $cmd: $err"
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
        ensurechan [chanid "TestServer" ""] {}
        ensurechan [chanid "TestServer" "#test"] {}
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
