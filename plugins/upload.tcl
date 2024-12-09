### upload Irken Plugin - upload files to envs.sh
#
# Description:
#
# Adds commands:
#    /upload - Prompt for a file to upload to envs.sh

package require TclCurl

namespace eval ::irken::upload {
    namespace import ::irc::* ::irken::*

    proc postFile { url sendFile } {
	set fp [open $sendFile r]
	fconfigure $fp -translation binary
	set fileContents [read $fp]
	close $fp

	set httpBody ""
	set resp [curl::transfer -url $url \
		      -post 1 -bodyvar httpBody \
		      -httppost [list name "file" bufferName [file tail $sendFile] buffer $fileContents]]
	puts $resp
	return [string trim $httpBody]
    }

    hook cmdUPLOAD upload 50 {servirid arg} {
	wm title . "Irken File Uploader"

	set types {
	    {"All Files" *}
	}
	set filename [tk_getOpenFile -filetypes $types -title "Choose a file"]
	if {$filename ne ""} {
	    set url https://envs.sh
	    hook call cmdMSG [serverpart $::active] "[channelpart $::active] [postFile $url $filename]"
	}
    }
}
