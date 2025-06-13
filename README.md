Irken
=======

Irken is an attempt to build a small, functional, IRC client in Tcl/Tk.  It
aims to honor as much of IRC as possible while still remaining small enough to
understand by tinkerers.

Features
--------

- supports multiple IRC servers
- adjustable three-pane interface
- highlights mentions of your nick
- clickable hyperlinks
- topic editing
- event hooks for easy customization
- nick tab completion
- presence notification
- command history
- color and formatting

![Screenshot](https://raw.githubusercontent.com/dlowe-net/irken/master/screenshot.png)

Running
-------

These instructions are for Linux.  Windows support is unlikely.

1. Install `tcl`, `tcllib`, `tcl-tls`, and `bwidget` - you need at least version
   8.6 of TCL.  For systems based on Debian (like Ubuntu or Linux
   Mint), you can run `sudo apt install tcl tcllib tcl-tls bwidget`.  Feel
   free to contribute instructions for other distributions.
2. Copy or symlink any desired plugins into into `~/.config/irken/`  You may
   have to make the directory.
3. Run `irken.tcl`. By default, it will create a configuration file that
   connects you to freenode.net and joins the #irken channel.

Configuration
-------------

On startup, if no configuration files are found, a file will be created at
`~/.config/irken/irken.tcl` with a server entry.  Any files ending with
`.tcl` will in the configuration directory will be executed in alphabetical
order.  Since configuration is done with normal Tcl files, theoretically any
customization can be achieved.

Servers are configured with this command:

    server <server ID> <options>

The server ID must not contain spaces.  The options are these:

* `-host` (required) server hostname
* `-nick` (required) nick for connecting to server
* `-port` (optional) server port for connection.  Defaults to 6697 if `-insecure` is
  false, or 6667 if `-insecure` is true.
* `-pass` (optional) password for server connection
* `-insecure` (optional) use an un-encrypted connection if True
* `-autoconnect` (optional) connect to server on startup if True
* `-autojoin` (optional) a list of channels to join.  specified like `{"#one" "#two"}`

You may also wish to try some custom fonts, which you can do like this:

    font configure Irken.Fixed -family "Cousine" -size "10"

Built-in commands
-----------------

* `/CLOSE [<channel>]` - remove the channel from the UI, leaving it if necessary
* `/EVAL <command>` - evaluate a TCL command, and display the result
* `/JOIN <channel>` - join a channel on the current server
* `/ME <action>` - send an action to the channel/person
* `/MSG <nick> <message>` - opens a channel and sends a private message to another person.
* `/PART [<channel>]` - leave a channel on the current server
* `/QUERY <nick>` - open a channel to privately message another person
* `/RELOAD` - reload the whole app.  Used mostly for development.
* `/SERVER <server id>` - connect to a server.  The server must already be configured.
* `/<anything else>` - sends the string verbatim to the server.

Keyboard commands
-----------------

* `Control-PageUp` / `Control-PageDown` - navigates to prev/next channel
* `PageUp` / `PageDown` - pages up and down on the current window
* `Up arrow` / `Down arrow` - on command line, goes into the past or future in the command history
* `Tab` - on command line, completes nick at the cursor.  Press tab again for
  next match.
* `Return` - on topic line, sets the topic to whatever is in the text box
* `Return` - on command line, either does the command or sends a message to the
  current channel.
* `Control-space` - navigate to the next channel where there are unread
  messages.

Included Plugins
----------------

Copy these to your .config/irken/ directory to activate.

* `aliases` - Allows user-defined commands
* `chanlist` - Adds a GUI for browsing the channel list returned by /LIST
* `daybreak` - Every midnight, inserts the date into every channel so that you
  can tell on which day a given message was sent.
* `dtnotify` - Creates a desktop notification when your nick is mentioned, using
  the /usr/bin/notify-send binary.  Since the notification isn't controlled by
  irken, though, they tend to pile up.
* `filterjoins` - Keeps track of who has talked in a channel, and hides
  join, part, and quit messages from those who haven't talked.
* `friend` - Allows addition of "friends" per-server.  Friends show up on the
  top of the user list in channels, their messages are highlighted in blue, and
  a message window is automatically opened for them on startup.
* `ignore` - Allows you to ignore all messages from certain nicks.
* `ijchain` - Implements integration with the ijchain and ischain bots
in the freenode #tcl channel.
* `inlineimages` - Displays images mentioned on IRC inline.
* `popupmenus` - Add popup menus for operations on channels, servers,
  and users.
* `restorewinpos` - Keeps track of your window position and opens it at the same
place on startup.
* `reconnect` - Automatically reconnects to servers when they
  disconnect.
* `rot13` - Add popup menu command for decoding rot13 and a /rot13 command.
* `search` - Adds /search <pattern> command which outputs matching lines to
  a new window.

Writing New Plugins
-------------------

Plugins are implemented as Tcl files which are loaded on startup.  Typically, a
plugin will install hooks to add commands or respond to messages.  Hooks are
defined with the following command:

    hook <trigger> <handle> <priority> <parameter list> <code>

When a hook's trigger occurs, each hook is called in order of priority.  The
hook's handle should be unique, and is used so that the hook may be redefined.

A hook may return in one of three ways:

- `return -code continue <list>` - continues processing to the next hook, but
  the parameter list will be set to the return value.
- `return -code break` - stops hook processing.
- normal return - continues processing to the next hook, ignoring the return
  value.

In Irken, triggers are of the form `handleMESSAGE`, `ctcpMESSAGE`, or
`cmdCOMMAND`.  The priority of the normal irken handling of a hook is 50.
These hooks should always execute, since much of the UI depends on them.  The
priority of normal irken message display is set to 75, so that plugins may
block or change messages before they are displayed.

`handleMESSAGE` hooks are passed a serverid and message, where message is a
dict containing the fields:

- `src`: the source of the message
- `user`: username of the source
- `host`: hostname of the source
- `cmd`: command of the message
- `args`: a list of the arguments for the command
- `line`: the raw line from the server

`cmdCOMMAND` hooks are passed a serverid and the string following the command.

`tagchantext` hooks are called when a message is added to a channel.  It is
passed the text to be formatted and a list of ranges in the form `{<index> push
<tag>}` or `{<index> pop <tag>}`.  These hooks *must* return via `return -code
continue`, with new ranges being appended to the old.

Some useful hooks:

- `handle001` - used for when the user is logged into the server and ready
- `handlePRIVMSG` - used for when a message is received on a channel or privately
- `cmdMSG` - used for sending all messages (but not actions) to a channel or
  privately.

Make sure to look at the included plugins for inspiration!
