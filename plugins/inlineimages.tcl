### inlineimages Irken Plugin - copy to ~/.config/irken/ to use.
#
## Description:
#
#    When a link ending in jpg, gif, or png is posted, automatically
#    retrieves the images and displays them in-line.
#    
## Requirements:
#
#    This plugin requires installation of tcllib and imagemagick.
#

package require tls
package require http

namespace eval ::irken::inlineimages {

    # an image needs to be inserted on these conditions:
    #   - when selectchan is called, we need to swap out the images
    #   - when a cached image url is inserted into ACTIVE text
    #   - when an uncached image url is retrieved AND the channel is active

    # ::urlimages is a mapping from urls to images, used for caching image
    # data retrieved from the network.
    if {[info vars ::urlimages] eq ""} {
        set ::urlimages [dict create]
    }

    # ::chanimages is a per-channel list of {pos url}, used for
    # reconstructing the displayed images after channel selection.
    if {[info vars ::chanimages] eq ""} {
        set ::chanimages [dict create]
    }

    http::register https 443 tls::socket

    set ::charsinsertedperimage 2

    proc imageatpos {pos image} {
        .t image create "0.0 + $pos chars" -image $image -pady 5
        .t configure -state normal
        .t insert "0.1 + $pos chars" "\n" {}
        .t configure -state disabled
    }

    proc receiveimage {url token} {
        if {[::http::ncode $token] != 200} {
            ::http::cleanup $token
            return
        }
        if {[catch {::http::data $token} httpdata]} {
            ::http::cleanup $token
            return
        }
        if {[catch {open "|convert -geometry 300x300 - png:-" wb+} fp]} {
            ::http::cleanup $token
            return
        }
        puts -nonewline $fp $httpdata
        close $fp w
        set scaleddata [read $fp]
        close $fp r
        if {[catch {image create photo -data $scaleddata} scaled]} {
            ::http::cleanup $token
            return
        }
        dict set ::urlimages $url $scaled
        for {imagepos} [dict get? {} $::chanimages $active] {
            lassign $imagepos pos imageurl
            if {$url eq $imageurl} {
                imageatpos $imagepos $scaled
            }
        }
        ::http::cleanup $token
    }

    hook textinserted imgur 75 {chanid taggedtext} {
        foreach {newtext tag} $taggedtext {
            append text $newtext
        }
        # each image occupies one index in the text
        set imagepos [expr {$::charsinsertedperimage * [llength [dict get? {} $::chanimages $chanid]]}]
        incr imagepos -1
        foreach {chantext tag} [dict get $::channeltext $chanid] {
            incr imagepos [string length $chantext]
        }
        set start 0
        while {[regexp -indices -start $start -- {https?://[-a-zA-Z0-9@:%_/\+.~#?&=,:()]+?\.(?:jpg|gif|png)} $text urlrange]} {
            set url [string range $text {*}$urlrange]
            dict lappend ::chanimages $chanid [list $imagepos $url]
            if {[dict exists $::urlimages $url]} {
                if {$chanid eq $::active} {
                    set image [dict get $::urlimages $url]
                    if {$image ne ""} {
                        imageatpos $imagepos $image
                    }
                }
            } else {
                dict set ::urlimages $url ""
                http::geturl $url -binary 1 -command "receiveimage $url"
            }
            incr start [expr {[lindex $urlrange 1] + 1}]
        }
    }

    hook chanselected imgur 75 {chanid} {
        foreach {imagepos} [dict get? {} $::chanimages $chanid] {
            lassign $imagepos pos url
            set image [dict get? "" $::urlimages $url]
            if {$image ne ""} {
                imageatpos $pos $image
            }
        }
    }
}
