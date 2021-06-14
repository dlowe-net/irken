### rot13 Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Adds a popup menu that rot13s a selection in the main text area.
#

namespace eval ::irken::rot13 {
    namespace import ::irken::*

    hook setupui rot13 50 {} {
        .t.popup add command -label "Rot13 Text" -state disabled -command [namespace code {textreplacerot13}]
        .t tag config rot13 -background {pale turquoise}
        .t tag lower rot13 sel
    }

    hook textpopup rot13 50 {x y rootx rooty} {
        .t.popup entryconfigure "Rot13 Text" -state [expr {([.t tag ranges sel] eq "") ? "disabled":"normal"}]
    }

    proc rot13 {text} {
        return [string map {a n b o c p d q e r f s g t h u i v j w k x l y m z n a o b p c q d r e s f t g u h v i w j x k y l z m A N B O C P D Q E R F S G T H U I V J W K X L Y M Z N A O B P C Q D R E S F T G U H V I W J X K Y L Z M} $text]
    }

    proc textreplacerot13 {} {
        foreach {start end} [.t tag ranges sel] {
            set text [rot13 [.t get $start $end]]
            .t configure -state normal
            .t delete $start $end
            .t insert $start $text {rot13 line}
            .t configure -state disabled
        }
    }

    hook cmdROT13 rot13 50 {serverid arg} {
        hook call cmdMSG [serverpart $::active] "[channelpart $::active] [rot13 $arg]"
    }
}
