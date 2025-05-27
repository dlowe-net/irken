### upload Irken Plugin - upload files to envs.sh
#
# Description:
#
#    Open up the file picker and upload the file to envs.sh.
#
# Requirements:
#
#    This plugin requires installation of tclcurl.
#
# Adds commands:
#    /upload - Prompt for a file to upload to envs.sh

package require TclCurl

namespace eval ::irken::upload {
    namespace import ::irc::* ::irken::*

    proc postFile { url sendFile } {
	if {![catch {open $sendFile r} fp]} {
	    fconfigure $fp -translation binary
	    set fileContents [read $fp]
	    close $fp

	    set httpBody ""
	    if {![catch {curl::transfer -url $url \
			     -post 1 -bodyvar httpBody \
			     -httppost [list name "file" bufferName [file tail $sendFile] buffer $fileContents]}]} {

		return [string trim $httpBody]
	    } else {
		addchantext $::active "Warning: unable to upload: $httpBody" -tags {fg_red italic}
	    }
	} else {
	    addchantext $::active "Warning: unable to open $sendFile" -tags {fg_red italic}
	}
    }

    hook cmdUPLOAD upload 50 {serverid arg} {
	set filename [tk_getOpenFile -filetypes {{{Images} {.png .jpg .jpeg .gif .PNG .JPG .JPEG .GIF}} {{All Files} {*}}} -title "Choose a file"]
	if {$filename ne ""} {
	    set url https://envs.sh
	    hook call cmdMSG [serverpart $::active] "[channelpart $::active] [postFile $url $filename]"
	}
    }
}
