#!/usr/bin/tclsh

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
    exit [expr {$failcount == 0 ? 0:1}]
}

proc testserver {chan addr port} {
    fconfigure $chan -blocking 0
    dict set ::serverinfo "TestServer" schan $chan
}

proc irken_fixture {op} {
    if {$op eq "setup"} {
        irken::initvars
        irken::initui
        set ::serverchan [socket -server testserver -myaddr "localhost" 0]
        set chan [socket "localhost" [lindex [fconfigure $::serverchan -sockname] 2]]
        dict set ::servers $chan "TestServer"
        dict set ::serverinfo "TestServer" [dict merge [dict create chan $chan nick "test" casemapping "rfc1459"] $::ircdefaults]
        fconfigure $chan -blocking 0
        vwait ::serverinfo
        irken::ensurechan "TestServer" "" {}
        irken::ensurechan "TestServer/#test" "#test" {}
        irken::ensurechan "TestServer/target" "target" {}
        set ::active {}
        .nav selection set [irken::chanid "TestServer" "#test"]
        irken::selectchan
        return
    }
    catch {close [dict get $::serverinfo "TestServer" schan]}
    catch {close [dict get $::serverinfo "TestServer" chan]}
    catch {close $::serverchan}
    destroy {*}[lsearch -all -inline -not -exact [winfo children .] ".#BWidget"]
}

test hook {} {
    hook testevent lowpriority 5 {a} {
        set ::testval {}
        lappend ::testval l-$a
    }
    hook testevent hook 10 {a} {
        lappend ::testval h-$a
    }
    # basic hook call
    hook call testevent "foo"
    asserteq $::testval [list l-foo h-foo]

    # redefinition of a hook
    hook testevent hook 15 {a} {
        lappend ::testval "r-$a"
    }
    hook call testevent "foo"
    asserteq $::testval [list l-foo r-foo]

    # overriding a previous hook
    hook testevent override 20 {a} {
        lappend ::testval "h-$a"
    }
    hook call testevent "foo"
    asserteq $::testval [list l-foo r-foo h-foo]

    # stopping a hook chain
    hook testevent hook 10 {a} {
        lappend ::testval "stopped"
        return -code break
    }
    hook call testevent "foo"
    asserteq $::testval [list l-foo stopped]

    # changing argument for subsequent hooks
    hook testevent hook 10 {a} {
        return -code continue "bar"
    }
    hook call testevent "foo"
    asserteq $::testval "l-foo h-bar"
}

test irctolower {} {
    asserteq [irken::irctolower "ascii" "FOO"] "foo"
    asserteq [irken::irctolower "rfc1459" "FOO"] "foo"
    asserteq [irken::irctolower "strict-rfc1459" "FOO"] "foo"
    asserteq [irken::irctolower "ascii" "FOO\[\]^"] "foo\[\]^"
    asserteq [irken::irctolower "rfc1459" "FOO\[\]^"] "foo\{\}~"
    asserteq [irken::irctolower "strict-rfc1459" "FOO\[\]^"] "foo\{\}^"
}

test ircstrcmp {} {
    assert {[irken::ircstrcmp "ascii" "foo\[\]^" "foo\[\]^"] == 0}
    assert {[irken::ircstrcmp "ascii" "foo\[\]^" "foo\{\}~"] != 0}
    assert {[irken::ircstrcmp "rfc1459" "foo\[\]" "foo\{\}"] == 0}
    assert {[irken::ircstrcmp "strict-rfc1459" "foo\[\]" "foo\{\}"] == 0}
    assert {[irken::ircstrcmp "rfc1459" "foo\[\]^" "foo\{\}~"] == 0}
    assert {[irken::ircstrcmp "strict-rfc1459" "foo\[\]^" "foo\{\}~"] != 0}
}

test rankeduser {} {
    dict set ::serverinfo "TestServer" prefix {@ o + v}
    asserteq [irken::rankeduser "TestServer" [list foo [list o v]]] "0foo"
    asserteq [irken::rankeduser "TestServer" [list foo [list v]]] "1foo"
    asserteq [irken::rankeduser "TestServer" [list foo {}]] "2foo"
}

test colorcode {} {
    asserteq [irken::colorcode "normal text"] [list "normal text" {}]
    asserteq [irken::colorcode "\x02normal \x02text"] [list "normal text" {{0 push bold} {7 pop bold}}]
    asserteq [irken::colorcode "\x1dnormal \x1dtext"] [list "normal text" {{0 push italic} {7 pop italic}}]
    asserteq [irken::colorcode "\x1fnormal \x1ftext"] [list "normal text" {{0 push underline} {7 pop underline}}]
    asserteq [irken::colorcode "\x034rainbow \x03text"] [list "rainbow text" {{0 push fg_red} {8 pop fg_red}}]
    asserteq [irken::colorcode "\x034,5rainbow \x034,99text"] [list "rainbow text" {{0 push fg_red} {0 push bg_maroon} {8 pop bg_maroon}}]
    asserteq [irken::colorcode "\x0314,15rainbow \x03text"] [list "rainbow text" {{0 push fg_gray} {0 push bg_lgray} {8 pop fg_gray} {8 pop bg_lgray}}]
    asserteq [irken::colorcode "\x0304rainbow \x03text"] [list "rainbow text" {{0 push fg_red} {8 pop fg_red}}]
    asserteq [irken::colorcode "\x02bold\x02 normal \x02\x1dbold italic\x02 italic \x02bold italic\x1d bold"] \
        [list "bold normal bold italic italic bold italic bold" \
             {{0 push bold} {4 pop bold} {12 push bold} {12 pop bold} {12 push bolditalic} {23 pop bolditalic} {23 push italic} {31 pop italic} {31 push bolditalic} {42 pop bolditalic} {42 push bold}}]
    asserteq [irken::colorcode "\x02\x1dbold italic\x0f normal"] [list "bold italic normal" {{0 push bold} {0 pop bold} {0 push bolditalic} {11 pop bolditalic}}]
    asserteq [irken::colorcode "\x16reversed\x16 normal"] [list "reversed normal" {{0 push fg_white} {0 push bg_black} {8 pop fg_white} {8 pop bg_black}}]
    asserteq [irken::colorcode "\x16rev\x034,5-ersed\x16 col\x03or"] [list "rev-ersed color" {{0 push fg_white} {0 push bg_black} {3 pop fg_white} {3 push fg_maroon} {3 pop bg_black} {3 push bg_red} {9 pop fg_maroon} {9 push fg_red} {9 pop bg_red} {9 push bg_maroon} {13 pop fg_red} {13 pop bg_maroon}}]
}

test httpregexp {} {
    assert {[regexp $irken::httpregexp "testing text"] == 0}
    assert {[regexp $irken::httpregexp "http://example.com/"] == 1}
    assert {[regexp $irken::httpregexp "https://example.com/"] == 1}
    regexp $irken::httpregexp "https://example.com/." match
    asserteq $match "https://example.com/"
    regexp $irken::httpregexp "https://example.com/, " match
    asserteq $match "https://example.com/"
    assert {[regexp $irken::httpregexp "https://example.com/#foo\[bar\]%20"] == 1}
}

test regexranges {} {
    asserteq [irken::regexranges "testing text" te te] {{0 push te} {2 pop te} {8 push te} {10 pop te}}
    asserteq [irken::regexranges "x https://example.com/ x" $irken::httpregexp hlink] {{2 push hlink} {22 pop hlink}}
}

test combinestyles {} {
    asserteq [irken::combinestyles "rainbow text" {{0 push te} {2 pop te} {8 push te} {10 pop te} {4 push ing} {7 pop ing}}] \
        [list "ra" te "in" {} "bow" ing " " {} "te" te "xt" {}]
}

test ischannel {} {
    set ::serverinfo [dict create "TestServer" $::ircdefaults]
    assert {[irken::ischannel [irken::chanid "TestServer" "#foo"]]}
    assert {[irken::ischannel [irken::chanid "TestServer" "#"]]}
    assert {[irken::ischannel [irken::chanid "TestServer" "&foo"]]}
    assert {![irken::ischannel [irken::chanid "TestServer" "foo"]]}
    assert {![irken::ischannel [irken::chanid "TestServer" "# foo"]]}
    assert {![irken::ischannel [irken::chanid "TestServer" "#\afoo"]]}
    dict set ::serverinfo "TestServer" channellen 2
    assert {[irken::ischannel [irken::chanid "TestServer" "#fo"]]}
    assert {![irken::ischannel [irken::chanid "TestServer" "#foo"]]}
    dict set ::serverinfo "TestServer" chantypes #
    assert {![irken::ischannel [irken::chanid "TestServer" "&fo"]]}
}

test parseline {} {
    set msg [irken::parseline ":nick!nick@irc.example.com PART #foo :Out of here!"]
    asserteq [dict get $msg cmd] "PART"
    asserteq [dict get $msg args] [list "#foo" "Out of here!"]
    set msg [irken::parseline ":nick!nick@irc.example.com QUIT :Out of here!"]
    asserteq [dict get $msg cmd] "QUIT"
    asserteq [dict get $msg args] [list "Out of here!"]
    set msg [irken::parseline ":nick!nick@irc.example.com JOIN #foo"]
    asserteq [dict get $msg cmd] "JOIN"
    asserteq [dict get $msg args] [list "#foo"]
    set msg [irken::parseline ":irc.example.com 333 nick #foo nick!user@2600::ffff:dddd:eeee:4444 1505726688"]
    asserteq [dict get $msg cmd] "333"
    asserteq [dict get $msg args] [list "nick" "#foo" "nick!user@2600::ffff:dddd:eeee:4444" "1505726688"]
    set msg [irken::parseline ":irc.example.com 353 nick = #foo :one two three four"]
    asserteq [dict get $msg cmd] "353"
    asserteq [dict get $msg args] [list "nick" "=" "#foo" "one two three four"]
    set msg [irken::parseline "@time=20211207T04:20:00Z :irc.example.com 353 nick = #foo :one two three four"]
    asserteq [dict get $msg cmd] "353"
    asserteq [dict get $msg args] [list "nick" "=" "#foo" "one two three four"]
}

test addchantext {irken_fixture} {
    irken::addchantext "TestServer/#test" "This is a test." -nick "tester" -tags self
    asserteq [lrange [dict get $::channeltext "TestServer/#test"] 2 end] [list "\ttester\t" "nick" "This is a test." {self line} "\n" {}]
}

test updateusermodes {irken_fixture} {
    irken::addchanuser "TestServer/#test" "test\[user\]" {o}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "test\[user\]" {o}]]
    assert {[.users exists "test\[user\]"]}
    irken::updateusermodes "TestServer/#test" "test\[user\]" {v} {o}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "test\[user\]" {v}]]
}

test addchanuser {irken_fixture} {
    irken::addchanuser "TestServer/#test" "test\[user\]" {}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "test\[user\]" {}]]
    assert {[.users exists "test\[user\]"]}

    irken::addchanuser "TestServer/#test" "@test\[user\]" {}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "test\[user\]" {o}]]
    assert {[.users exists "test\[user\]"]}
    assert {[.users tag has o "test\[user\]"]}
}

test remchanuser {irken_fixture} {
    set chanid [irken::chanid "TestServer" "#test"]
    irken::addchanuser $chanid "testuser" {}
    assert {[.users exists "testuser"]}
    irken::remchanuser $chanid "testuser"
    assert {![.users exists "testuser"]}
    irken::addchanuser $chanid "\\\\\\\\\\\\\\\\\\\\\\" {}
    irken::remchanuser $chanid "\\\\\\\\\\\\\\\\\\\\\\"
    assert {![.users exists "\\\\\\\\\\\\\\\\\\\\\\"]}

}

test removechan {irken_fixture} {
    assert {[dict exists $::channeltext "TestServer/#test"]}
    assert {[dict exists $::channelinfo "TestServer/#test"]}
    asserteq [.nav focus] "TestServer/#test"
    irken::removechan "TestServer/#test"
    assert {![dict exists $::channeltext "TestServer/#test"]}
    assert {![dict exists $::channelinfo "TestServer/#test"]}
    assert {![.nav exists "TestServer/#test"]}
    asserteq [.nav selection] "TestServer/target"
    asserteq [.nav focus] "TestServer/target"
    asserteq $::active "TestServer/target"
}

test closecmd {irken_fixture} {
    assert {[.nav exists "TestServer/#test"]}
    .cmd insert 1.0 "/close #test Testing"
    catch {irken::returnkey} _
    asserteq [gets [dict get $::serverinfo "TestServer" schan]] "PART #test :Testing"
    assert {![.nav exists "TestServer/#test"]}
    asserteq [.nav selection] "TestServer/target"
    asserteq [.nav focus] "TestServer/target"
    asserteq $::active "TestServer/target"
    assert {![dict exists $::channeltext "TestServer/#test"]}
    assert {![dict exists $::channelinfo "TestServer/#test"]}
}

test closecmdwithuser {irken_fixture} {
    .nav selection set [irken::chanid "TestServer" "target"]
    irken::selectchan
    .cmd insert 1.0 "/close target"
    catch {irken::returnkey} _
    assert {![.nav exists "TestServer/target"]}
    asserteq [.nav selection] "TestServer/#test"
    asserteq [.nav focus] "TestServer/#test"
    asserteq $::active "TestServer/#test"
    assert {![dict exists $::channeltext "TestServer/target"]}
    assert {![dict exists $::channelinfo "TestServer/target"]}
}

test handleMODE {irken_fixture} {
    irken::addchanuser [irken::chanid "TestServer" "#test"] "@target" {}
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "target" {o}]]
    hook call handleMODE "TestServer" [dict create src "foo" user "foo" host "foo.com" cmd "MODE" args [list "#test" -o target]]
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "target" {}]]
    assert {[.users exists "target"]}
    assert {![.users tag has o "target"]}
    hook call handleMODE "TestServer" [dict create src "foo" user "foo" host "foo.com" cmd "MODE" args [list "#test" +o target]]
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "target" {o}]]
    hook call handleMODE "TestServer" [dict create src "foo" user "foo" host "foo.com" cmd "MODE" args [list "#test" +v target]]
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "target" {o v}]]
}

test handleNICK {irken_fixture} {
    irken::addchanuser [irken::chanid "TestServer" "#test"] "target" {o}
    irken::ensurechan [irken::chanid "TestServer" "target"] "target" {}
    irken::addchantext "TestServer/target" "This is a test."
    set oldtext [dict get $::channeltext "TestServer/target"]
    hook call handleNICK "TestServer" [dict create src "target" user "foo" host "foo.com" cmd "NICK" args [list "other"]]
    assert {[.users exists "other"]}
    assert {![.users exists "target"]}
    asserteq $oldtext [dict get $::channeltext "TestServer/other"]
    asserteq [dict get $::channelinfo "TestServer/#test" users] [list [list "other" {o}]]
    assert {[dict exists $::channelinfo "TestServer/other"]}
    assert {[.nav exists "TestServer/other"]}
    assert {![.nav exists "TestServer/target"]}
}

test handleNICKuserselected {irken_fixture} {
    irken::ensurechan [irken::chanid "TestServer" "target"] "target" {}
    .nav selection set [irken::chanid "TestServer" "target"]
    irken::selectchan
    asserteq $::active "TestServer/target"
    hook call handleNICK "TestServer" [dict create src "target" user "foo" host "foo.com" cmd "NICK" args [list "other"]]
    irken::selectchan
    asserteq $::active "TestServer/other"
    assert {[.nav exists "TestServer/other"]}
    assert {![.nav exists "TestServer/target"]}
}

test handleNICKself {irken_fixture} {
    irken::ensurechan [irken::chanid "TestServer" "target"] "target" {}
    .nav selection set [irken::chanid "TestServer" "target"]
    irken::selectchan
    asserteq [.nick cget -text] "test"
    hook call handleNICK "TestServer" [dict create src "test" user "foo" host "foo.com" cmd "NICK" args [list "other"]]
    asserteq [dict get $::serverinfo "TestServer" nick] "other"
    asserteq [.nick cget -text] "other"
}

test handleKICKself {irken_fixture} {
    set chanid [irken::chanid "TestServer" "#test"]
    irken::ensurechan $chanid "#test" {}
    .nav selection set $chanid
    irken::selectchan
    hook call handleKICK "TestServer" [dict create src "kicker" user "foo" host "foo.com" cmd "KICK" args [list "#test" "test" "get out"]]
    asserteq [lrange [dict get $::channeltext "TestServer/#test"] 2 end] [list "\t*\t" "nick" "kicker kicks you from #test. (get out)" {system line} "\n" {}]
}

test handleKICKother {irken_fixture} {
    set chanid [irken::chanid "TestServer" "#test"]
    irken::ensurechan $chanid "#test" {}
    .nav selection set $chanid
    irken::selectchan
    hook call handleKICK "TestServer" [dict create src "kicker" user "foo" host "foo.com" cmd "KICK" args [list "#test" "target" "get out"]]
    asserteq [lrange [dict get $::channeltext "TestServer/#test"] 2 end] [list "\t*\t" "nick" "kicker kicks target from #test. (get out)" {system line} "\n" {}]
}

test disconnect {irken_fixture} {
    assert {![.nav tag has disabled "TestServer"]}
    set schan [dict get $::serverinfo "TestServer" schan]
    fconfigure $schan -blocking 0
    close $schan
    irken::recv [dict get $::serverinfo "TestServer" chan]
    assert {[.nav tag has disabled "TestServer"]}
    assert {[.nav tag has disabled "TestServer/#test"]}
    asserteq [lrange [dict get $::channeltext "TestServer"] 2 end] [list "\t*\t" {nick} "Server disconnected." {system line} "\n" {}]
}

if {[info exists argv0] && [file dirname [file normalize [info script]/...]] eq [file dirname [file normalize $argv0/...]]} {
    runtests
}
